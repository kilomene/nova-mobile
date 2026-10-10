using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.World
{
    public enum BuildingArchetype { House, Shop, Warehouse, Tower }

    /// <summary>Parameters for one procedurally built enterable building.</summary>
    public struct BuildingSpec
    {
        public BuildingArchetype Archetype;
        public float Width, Depth, FloorHeight;
        public int Floors;
        public Color WallColor;
        public int Seed;
        public bool FlatRoof;     // false => pitched gable roof (houses)
        public bool RoofAccess;   // stairs reach the roof (flat roofs)
        public bool Stilts;       // raise the floor on stilts (Makoko stilt houses)
        public bool Helipad;      // painted H on the roof (towers)
        public string SignText;   // shop sign, empty = none
        public Color SignColor;

        public static BuildingSpec House(float w, float d, int floors, Color wall, int seed)
        {
            return new BuildingSpec
            {
                Archetype = BuildingArchetype.House, Width = w, Depth = d,
                FloorHeight = 3.0f, Floors = floors, WallColor = wall, Seed = seed,
                FlatRoof = false, RoofAccess = false, Stilts = false,
                Helipad = false, SignText = "", SignColor = Color.white
            };
        }

        public static BuildingSpec Shop(float w, float d, int floors, Color wall, int seed,
            string sign, Color signColor)
        {
            return new BuildingSpec
            {
                Archetype = BuildingArchetype.Shop, Width = w, Depth = d,
                FloorHeight = 3.4f, Floors = floors, WallColor = wall, Seed = seed,
                FlatRoof = true, RoofAccess = true, Stilts = false,
                Helipad = false, SignText = sign, SignColor = signColor
            };
        }

        public static BuildingSpec Warehouse(float w, float d, Color wall, int seed)
        {
            return new BuildingSpec
            {
                Archetype = BuildingArchetype.Warehouse, Width = w, Depth = d,
                FloorHeight = 5.0f, Floors = 1, WallColor = wall, Seed = seed,
                FlatRoof = true, RoofAccess = true, Stilts = false,
                Helipad = false, SignText = "", SignColor = Color.white
            };
        }

        public static BuildingSpec Tower(float w, float d, int floors, Color wall, int seed, bool helipad)
        {
            return new BuildingSpec
            {
                Archetype = BuildingArchetype.Tower, Width = w, Depth = d,
                FloorHeight = 3.2f, Floors = floors, WallColor = wall, Seed = seed,
                FlatRoof = true, RoofAccess = true, Stilts = false,
                Helipad = helipad, SignText = "", SignColor = Color.white
            };
        }
    }

    /// <summary>
    /// Builds enterable buildings into a WorldBatch (geometry is batched with the
    /// region, not per-building renderers). Ports the construction idiom shared by
    /// the Godot region scripts: walls with REAL door/window holes (shoot-through),
    /// floor slabs with stairwell holes, visual steps + ramp colliders, trim, and
    /// flat roofs with parapets + stair access. Returns a Building whose
    /// LootSockets the Loot system fills and whose CoverPoints AI can use.
    /// </summary>
    public static class BuildingFactory
    {
        public struct Hole { public float Xc, Y0, W, H; }

        private static Matrix4x4 T(Vector3 p) => Matrix4x4.TRS(p, Quaternion.identity, Vector3.one);
        private static Matrix4x4 Frame(Vector3 origin, float yawDeg) =>
            Matrix4x4.TRS(origin, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);

        // ---------------- wall helpers (port of _wall_open / _window_wall) ----------------

        /// <summary>Wall with rectangular holes [xCenter, yBottom, w, h] — real openings.</summary>
        public static void WallOpen(WorldBatch batch, Matrix4x4 frame, float w, float h, float t,
            List<Hole> holes, Material mat, Color col, bool collide = true)
        {
            holes.Sort((a, b) => a.Xc.CompareTo(b.Xc));
            float x0 = -w * 0.5f;
            foreach (var hl in holes)
            {
                float segW = (hl.Xc - hl.W * 0.5f) - x0;
                if (segW > 0.05f)
                    batch.Box(new Vector3(segW, h, t), frame * T(new Vector3(x0 + segW * 0.5f, h * 0.5f, 0f)), mat, col, collide);
                if (hl.Y0 > 0.05f)
                    batch.Box(new Vector3(hl.W, hl.Y0, t), frame * T(new Vector3(hl.Xc, hl.Y0 * 0.5f, 0f)), mat, col, collide);
                float top = hl.Y0 + hl.H;
                if (h - top > 0.05f)
                    batch.Box(new Vector3(hl.W, h - top, t), frame * T(new Vector3(hl.Xc, top + (h - top) * 0.5f, 0f)), mat, col, collide);
                x0 = hl.Xc + hl.W * 0.5f;
            }
            float lastW = w * 0.5f - x0;
            if (lastW > 0.05f)
                batch.Box(new Vector3(lastW, h, t), frame * T(new Vector3(x0 + lastW * 0.5f, h * 0.5f, 0f)), mat, col, collide);
        }

        public static void TrimOpening(WorldBatch batch, Matrix4x4 frame, float xc, float y0,
            float w, float h, float t, Material trimMat)
        {
            var c = Color.white;
            batch.Box(new Vector3(w + 0.24f, 0.12f, t + 0.08f), frame * T(new Vector3(xc, y0 - 0.02f, 0f)), trimMat, c);
            batch.Box(new Vector3(w + 0.24f, 0.12f, t + 0.08f), frame * T(new Vector3(xc, y0 + h + 0.02f, 0f)), trimMat, c);
            batch.Box(new Vector3(0.12f, h + 0.24f, t + 0.08f), frame * T(new Vector3(xc - w * 0.5f - 0.02f, y0 + h * 0.5f, 0f)), trimMat, c);
            batch.Box(new Vector3(0.12f, h + 0.24f, t + 0.08f), frame * T(new Vector3(xc + w * 0.5f + 0.02f, y0 + h * 0.5f, 0f)), trimMat, c);
        }

        /// <summary>Evenly spaced shoot-through window band with trim + dark glass inset.</summary>
        public static void WindowWall(WorldBatch batch, Matrix4x4 frame, float w, float h, float t,
            Material mat, Color col, WorldMaterials mats)
        {
            int n = Mathf.Max(2, Mathf.RoundToInt(w / 3.0f));
            var holes = new List<Hole>(n);
            for (int i = 0; i < n; i++)
            {
                float xc = -w * 0.5f + w * (i + 0.5f) / n;
                holes.Add(new Hole { Xc = xc, Y0 = 1.1f, W = 1.4f, H = 1.3f });
            }
            WallOpen(batch, frame, w, h, t, holes, mat, col, true);
            foreach (var hl in holes)
            {
                TrimOpening(batch, frame, hl.Xc, hl.Y0, hl.W, hl.H, t, mats.Trim);
                // dark glass inset, set back from the opening (visual only, still open)
                batch.Box(new Vector3(hl.W, hl.H, 0.04f),
                    frame * T(new Vector3(hl.Xc, hl.Y0 + hl.H * 0.5f, -t * 0.5f - 0.25f)),
                    mats.GlassDark, Color.white);
                // emissive sill strip: night-lighting feel, no real light cost
                batch.Box(new Vector3(hl.W, 0.06f, 0.06f),
                    frame * T(new Vector3(hl.Xc, hl.Y0 - 0.06f, t * 0.5f + 0.02f)),
                    mats.Emissive, new Color(1f, 0.85f, 0.55f));
            }
        }

        // ---------------- slab / stairs helpers ----------------

        public static void Slab(WorldBatch batch, Matrix4x4 frame, float w, float d, float y,
            Material mat, float t = 0.25f)
        {
            batch.Box(new Vector3(w, t, d), frame * T(new Vector3(0f, y - t * 0.5f, 0f)), mat, Color.white, true);
        }

        /// <summary>Floor slab with a rectangular stairwell hole (port of _slab_hole).</summary>
        public static void SlabHole(WorldBatch batch, Matrix4x4 frame, float w, float d, float y,
            float hx0, float hx1, float hz, float hzw, Material mat)
        {
            float t = 0.25f;
            float y0 = y - t * 0.5f;
            if (hx0 > -w * 0.5f + 0.05f)
            {
                float sw = hx0 + w * 0.5f;
                batch.Box(new Vector3(sw, t, d), frame * T(new Vector3(-w * 0.5f + sw * 0.5f, y0, 0f)), mat, Color.white, true);
            }
            if (w * 0.5f - hx1 > 0.05f)
            {
                float sw2 = w * 0.5f - hx1;
                batch.Box(new Vector3(sw2, t, d), frame * T(new Vector3(hx1 + sw2 * 0.5f, y0, 0f)), mat, Color.white, true);
            }
            float hw = hx1 - hx0;
            float fz0 = -d * 0.5f, fz1 = hz - hzw * 0.5f, bz0 = hz + hzw * 0.5f, bz1 = d * 0.5f;
            if (fz1 - fz0 > 0.05f)
                batch.Box(new Vector3(hw, t, fz1 - fz0), frame * T(new Vector3((hx0 + hx1) * 0.5f, y0, (fz0 + fz1) * 0.5f)), mat, Color.white, true);
            if (bz1 - bz0 > 0.05f)
                batch.Box(new Vector3(hw, t, bz1 - bz0), frame * T(new Vector3((hx0 + hx1) * 0.5f, y0, (bz0 + bz1) * 0.5f)), mat, Color.white, true);
        }

        /// <summary>Visual steps + one ramp collider (port of the Godot _stairs).</summary>
        public static void Stairs(WorldBatch batch, Matrix4x4 frame, float x0, float run,
            float width, float zc, float rise, float yBase, Material stepMat, Material railMat)
        {
            const int steps = 10;
            for (int i = 0; i < steps; i++)
            {
                float sx = x0 + run * (i + 0.5f) / steps;
                float sy = yBase + rise * (i + 0.5f) / steps;
                batch.Box(new Vector3(run / steps + 0.05f, 0.09f, width),
                    frame * T(new Vector3(sx, sy - 0.045f, zc)), stepMat, Color.white);
            }
            float length = Mathf.Sqrt(run * run + rise * rise);
            float ang = Mathf.Atan2(rise, run) * Mathf.Rad2Deg;
            var rampM = frame * Matrix4x4.TRS(
                new Vector3(x0 + run * 0.5f, yBase + rise * 0.5f - 0.06f, zc),
                Quaternion.AngleAxis(ang, Vector3.forward), Vector3.one);
            batch.Collider(new Vector3(length, 0.12f, width), rampM);
            // handrail strut
            Strut(batch, frame.MultiplyPoint3x4(new Vector3(x0, yBase + 1f, zc - width * 0.5f)),
                frame.MultiplyPoint3x4(new Vector3(x0 + run, yBase + rise + 1f, zc - width * 0.5f)),
                0.06f, 0.06f, railMat, Color.white);
        }

        /// <summary>Oriented beam between two points (port of _strut).</summary>
        public static void Strut(WorldBatch batch, Vector3 a, Vector3 b, float w, float d,
            Material mat, Color col)
        {
            Vector3 dv = b - a;
            float length = dv.magnitude;
            if (length < 0.01f) return;
            Vector3 mid = (a + b) * 0.5f;
            Quaternion q = Quaternion.LookRotation(dv.normalized);
            batch.Box(new Vector3(w, length, d), Matrix4x4.TRS(mid, q, Vector3.one), mat, col);
        }

        // ---------------- roofs ----------------

        private static void RoofGable(WorldBatch batch, Matrix4x4 frame, float w, float d,
            float baseY, Material roofMat, Material trimMat, System.Random rng)
        {
            float rise = 1.0f + (float)rng.NextDouble() * 0.5f;
            float run = d * 0.5f + 0.45f;
            float slope = Mathf.Sqrt(run * run + rise * rise);
            float ang = Mathf.Atan2(rise, run) * Mathf.Rad2Deg;
            var rc = new Color(0.55f, 0.32f, 0.18f);
            foreach (float sgn in new[] { 1f, -1f })
            {
                var local = Matrix4x4.TRS(new Vector3(0f, baseY + rise * 0.5f, sgn * run * 0.5f),
                    Quaternion.AngleAxis(sgn * ang, Vector3.right), Vector3.one);
                batch.Box(new Vector3(w + 0.9f, 0.12f, slope + 0.25f), frame * local, roofMat, rc);
            }
            batch.Box(new Vector3(w + 0.9f, 0.14f, 0.45f),
                frame * T(new Vector3(0f, baseY + rise + 0.03f, 0f)), trimMat, rc);
        }

        private static void Parapet(WorldBatch batch, Matrix4x4 frame, float w, float d, float y,
            Material mat, Color col)
        {
            float h = 1.1f, t = 0.22f;
            batch.Box(new Vector3(w + 0.25f, h, t), frame * T(new Vector3(0f, y + h * 0.5f, d * 0.5f)), mat, col, true);
            batch.Box(new Vector3(w + 0.25f, h, t), frame * T(new Vector3(0f, y + h * 0.5f, -d * 0.5f)), mat, col, true);
            batch.Box(new Vector3(t, h, d + 0.25f), frame * T(new Vector3(w * 0.5f, y + h * 0.5f, 0f)), mat, col, true);
            batch.Box(new Vector3(t, h, d + 0.25f), frame * T(new Vector3(-w * 0.5f, y + h * 0.5f, 0f)), mat, col, true);
        }

        // ---------------- sockets ----------------

        private static LootSpawnPoint AddSocket(Building b, Vector3 localPos, int tier)
        {
            var go = new GameObject("LootSocket_T" + tier);
            go.transform.SetParent(b.transform, false);
            go.transform.localPosition = localPos;
            var sp = go.AddComponent<LootSpawnPoint>();
            sp.Tier = tier;
            return sp;
        }

        private static Transform AddCover(Building b, string name, Vector3 localPos)
        {
            var go = new GameObject(name);
            go.transform.SetParent(b.transform, false);
            go.transform.localPosition = localPos;
            return go.transform;
        }

        // ---------------- main entry ----------------

        /// <summary>
        /// Build one enterable building. Geometry goes into <paramref name="batch"/>
        /// (region-local space); sockets/cover points become children of the returned
        /// Building, positioned at <paramref name="localPos"/> with yaw rotation.
        /// </summary>
        public static Building Build(WorldBatch batch, BuildingSpec spec, Transform parent,
            Vector3 localPos, float yawDeg, WorldMaterials mats, System.Random rng)
        {
            var go = new GameObject("Building_" + spec.Archetype);
            go.transform.SetParent(parent, false);
            go.transform.SetPositionAndRotation(localPos, Quaternion.Euler(0f, yawDeg, 0f));
            var b = go.AddComponent<Building>();
            b.Archetype = spec.Archetype;
            b.Width = spec.Width; b.Depth = spec.Depth;
            b.Floors = spec.Floors; b.FloorHeight = spec.FloorHeight;

            float w = spec.Width, d = spec.Depth, fh = spec.FloorHeight, t = 0.22f;
            var frame = Matrix4x4.identity; // building-local; GO transform carries pos/yaw
            var wallCol = spec.WallColor;
            float baseY = 0f;

            if (spec.Stilts)
            {
                // Makoko stilt houses: floor deck raised, stilts down into the water.
                baseY = 0.9f;
                for (int sx = -1; sx <= 1; sx++)
                    for (int sz = -1; sz <= 1; sz += 2)
                        batch.Cylinder(0.13f, 2.6f, 8,
                            frame * T(new Vector3(sx * (w * 0.5f - 0.35f), -0.4f, sz * (d * 0.5f - 0.35f))),
                            mats.WoodDark, Color.white);
            }

            // Floor slab.
            batch.Box(new Vector3(w + 0.6f, 0.18f, d + 0.6f),
                frame * T(new Vector3(0f, baseY - 0.09f, 0f)), mats.Wood, Color.white, true);

            var sockets = new List<LootSpawnPoint>();
            var covers = new List<Transform>();

            for (int f = 0; f < spec.Floors; f++)
            {
                float fy = baseY + fh * f;
                bool groundFloor = f == 0;

                // Front (+z): door on ground floor, window band above; back/sides: window bands.
                var frontHoles = new List<Hole>();
                if (groundFloor)
                {
                    frontHoles.Add(new Hole { Xc = 0f, Y0 = 0f, W = 1.4f, H = 2.4f }); // door
                    frontHoles.Add(new Hole { Xc = -w * 0.3f, Y0 = 1.1f, W = 1.4f, H = 1.3f });
                    frontHoles.Add(new Hole { Xc = w * 0.3f, Y0 = 1.1f, W = 1.4f, H = 1.3f });
                }
                else
                {
                    int n = Mathf.Max(2, Mathf.RoundToInt(w / 3f));
                    for (int i = 0; i < n; i++)
                        frontHoles.Add(new Hole { Xc = -w * 0.5f + w * (i + 0.5f) / n, Y0 = 1.1f, W = 1.4f, H = 1.3f });
                }
                WallOpen(batch, frame * T(new Vector3(0f, fy, d * 0.5f)), w, fh, t, frontHoles, mats.Wall, wallCol);
                TrimOpening(batch, frame * T(new Vector3(0f, fy, d * 0.5f)), 0f, 0f, 1.4f, 2.4f, t, mats.Trim);
                WindowWall(batch, frame * T(new Vector3(0f, fy, -d * 0.5f)), w, fh, t, mats.Wall, wallCol, mats);
                WindowWall(batch, frame * Matrix4x4.TRS(new Vector3(w * 0.5f, fy, 0f), Quaternion.Euler(0f, 90f, 0f), Vector3.one),
                    d, fh, t, mats.Wall, wallCol, mats);
                WindowWall(batch, frame * Matrix4x4.TRS(new Vector3(-w * 0.5f, fy, 0f), Quaternion.Euler(0f, -90f, 0f), Vector3.one),
                    d, fh, t, mats.Wall, wallCol, mats);

                // Shop extras: signboard + awning on the front.
                if (spec.Archetype == BuildingArchetype.Shop && groundFloor && !string.IsNullOrEmpty(spec.SignText))
                {
                    batch.Box(new Vector3(w * 0.7f, 1.0f, 0.3f),
                        frame * T(new Vector3(0f, fy + fh - 0.6f, d * 0.5f + 0.15f)), mats.Trim, Color.white);
                    batch.Box(new Vector3(w * 0.7f - 0.3f, 0.7f, 0.32f),
                        frame * T(new Vector3(0f, fy + fh - 0.6f, d * 0.5f + 0.15f)), mats.Emissive, spec.SignColor);
                    var awn = frame * Matrix4x4.TRS(new Vector3(0f, fy + 2.6f, d * 0.5f + 0.75f),
                        Quaternion.AngleAxis(20f, Vector3.right), Vector3.one);
                    batch.Box(new Vector3(w * 0.8f, 0.08f, 1.7f), awn, mats.Trim, spec.SignColor);
                }

                // Interior: simple furniture blocks double as cover.
                if ((float)rng.NextDouble() < 0.8f)
                    batch.Box(new Vector3(1.9f, 0.45f, 0.95f),
                        frame * T(new Vector3(-w * 0.26f, fy + 0.22f, -d * 0.3f)), mats.WoodDark, Color.white, true);
                if ((float)rng.NextDouble() < 0.7f)
                    batch.Box(new Vector3(0.9f, 0.9f, 0.9f),
                        frame * T(new Vector3(w * 0.28f, fy + 0.45f, -d * 0.28f)), mats.Wood, Color.white, true);

                // Loot sockets on this floor.
                sockets.Add(AddSocket(b, new Vector3(-w * 0.3f, fy + 0.55f, 0f), f == 0 ? 1 : 2));
                sockets.Add(AddSocket(b, new Vector3(w * 0.3f, fy + 0.55f, -d * 0.25f), f == 0 ? 1 : 2));

                // Upper floor slab with stairwell hole + stairs (not on top floor).
                if (f < spec.Floors - 1 || spec.RoofAccess)
                {
                    float sy = baseY + fh * (f + 1);
                    float hx0 = -w * 0.5f + 0.8f, hx1 = hx0 + Mathf.Min(w - 1.6f, 3.2f);
                    float hzc = -d * 0.5f + 1.4f;
                    SlabHole(batch, frame, w, d, sy, hx0, hx1, hzc, 1.6f, mats.Concrete);
                    Stairs(batch, frame, hx0, hx1 - hx0, 1.6f, hzc, fh, fy, mats.ConcreteDark, mats.Metal);
                }
            }

            float roofY = baseY + fh * spec.Floors;
            if (spec.FlatRoof)
            {
                // Flat roof slab + parapet; stairs already reach it when RoofAccess.
                Slab(batch, frame, w, d, roofY + 0.12f, mats.Concrete);
                Parapet(batch, frame, w, d, roofY + 0.24f, mats.Wall, wallCol);
                // Roof clutter: AC units.
                for (int i = 0; i < 2; i++)
                    batch.Box(new Vector3(1.2f, 0.9f, 0.9f),
                        frame * T(new Vector3(-w * 0.3f + i * w * 0.3f, roofY + 0.7f, d * 0.18f)),
                        mats.Metal, Color.white, true);
                if (spec.Helipad)
                {
                    batch.Cylinder(4.2f, 0.14f, 16, frame * T(new Vector3(0f, roofY + 0.3f, 0f)), mats.AsphaltPlain, Color.white);
                    batch.Box(new Vector3(2.3f, 0.03f, 0.5f), frame * T(new Vector3(0f, roofY + 0.4f, 0f)), mats.PaintYellow, Color.white);
                    batch.Box(new Vector3(0.5f, 0.03f, 2.4f), frame * T(new Vector3(-0.9f, roofY + 0.4f, 0f)), mats.PaintYellow, Color.white);
                    batch.Box(new Vector3(0.5f, 0.03f, 2.4f), frame * T(new Vector3(0.9f, roofY + 0.4f, 0f)), mats.PaintYellow, Color.white);
                }
                sockets.Add(AddSocket(b, new Vector3(w * 0.25f, roofY + 0.8f, d * 0.2f), 2));
            }
            else
            {
                RoofGable(batch, frame, w, d, roofY, mats.RoofRed, mats.Trim, rng);
            }

            // Cover points: outside corners + flanking the door.
            covers.Add(AddCover(b, "Cover_0", new Vector3(-w * 0.5f - 1.2f, 0f, d * 0.5f + 1.2f)));
            covers.Add(AddCover(b, "Cover_1", new Vector3(w * 0.5f + 1.2f, 0f, d * 0.5f + 1.2f)));
            covers.Add(AddCover(b, "Cover_2", new Vector3(-w * 0.5f - 1.2f, 0f, -d * 0.5f - 1.2f)));
            covers.Add(AddCover(b, "Cover_3", new Vector3(w * 0.5f + 1.2f, 0f, -d * 0.5f - 1.2f)));

            b.LootSockets = sockets.ToArray();
            b.CoverPoints = covers.ToArray();
            return b;
        }
    }
}
