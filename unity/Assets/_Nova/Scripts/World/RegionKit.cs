using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>Loot spawn registered by a region builder (region-local until aggregated).</summary>
    public struct LootSpot
    {
        public string Kind;      // "health" | "armor" | "ammo"
        public int Amount;
        public Vector3 Position;  // region-local; WorldBuilder offsets to world
        public int Tier;

        public LootSpot(string kind, int amount, Vector3 pos, int tier)
        {
            Kind = kind; Amount = amount; Position = pos; Tier = tier;
        }
    }

    /// <summary>Per-region build state passed to every region builder.</summary>
    public sealed class RegionContext
    {
        public string Name;
        public Vector3 Origin;              // world-space region origin
        public Transform Root;              // region GameObject (building parent)
        public System.Random Rng;
        public WorldMaterials Mats;
        public WorldBatch Batch;            // region-local batch
        public readonly List<LootSpot> Loot = new List<LootSpot>();
        public readonly List<Vector3> EnemySpawns = new List<Vector3>();
        public readonly List<Vector3> HousePositions = new List<Vector3>();
        public Vector3 PlayerSpawn = new Vector3(0f, 0.6f, 52f);

        public float Rf() => (float)Rng.NextDouble();
        public float RfRange(float a, float b) => a + (float)Rng.NextDouble() * (b - a);
        public int Ri(int a, int b) => Rng.Next(a, b); // [a, b)
        public T Pick<T>(T[] arr) => arr[Rng.Next(arr.Length)];

        public void AddLoot(string kind, int amount, Vector3 localPos, int tier = 1)
        {
            Loot.Add(new LootSpot(kind, amount, localPos, tier));
        }

        public void AddLootRing(Vector3 center, float y, int count, int tier)
        {
            string[] kinds = { "health", "armor", "ammo" };
            int[] amounts = { 40, 50, 60 };
            for (int k = 0; k < count; k++)
            {
                float a = Mathf.PI * 2f * k / count;
                float rad = 4f + (k % 3) * 2f;
                int ki = k % 3;
                AddLoot(kinds[ki], amounts[ki],
                    center + new Vector3(Mathf.Cos(a) * rad, y, Mathf.Sin(a) * rad), tier);
            }
        }
    }

    /// <summary>
    /// Shared small-scale builders used by the region builders (props, vegetation,
    /// ground slabs, road strips). Region-local space; colliders where gameplay needs.
    /// </summary>
    public static class RegionKit
    {
        public static Matrix4x4 T(Vector3 p) => Matrix4x4.TRS(p, Quaternion.identity, Vector3.one);
        public static Matrix4x4 TR(Vector3 p, float yawDeg) =>
            Matrix4x4.TRS(p, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);

        public static void Box(RegionContext ctx, Vector3 size, Vector3 pos, Material mat,
            Color col, bool collide = false, float yawDeg = 0f)
        {
            ctx.Batch.Box(size, TR(pos, yawDeg), mat, col, collide);
        }

        public static void Cyl(RegionContext ctx, float r, float h, Vector3 pos, Material mat,
            Color col, bool collide = false, int seg = 10)
        {
            ctx.Batch.Cylinder(r, h, seg, T(pos), mat, col, collide);
        }

        /// <summary>Solid ground slab with collider, top at topY.</summary>
        public static void GroundRect(RegionContext ctx, float x0, float x1, float z0, float z1,
            float topY, Material mat, Color col)
        {
            float sx = x1 - x0, sz = z1 - z0;
            Box(ctx, new Vector3(sx, 0.6f, sz),
                new Vector3((x0 + x1) * 0.5f, topY - 0.3f, (z0 + z1) * 0.5f), mat, col, true);
        }

        public static void RoadStrip(RegionContext ctx, float x0, float x1, float z0, float z1)
        {
            // Textured ribbon: ProcTexture.Road() carries lane markings, center dashes
            // and tire-wear bands (u 0..1 across, v tiled along).
            bool alongX = (x1 - x0) >= (z1 - z0);
            ctx.Batch.RoadQuad(x0, x1, z0, z1, 0.06f, alongX, ctx.Mats.Road);
        }

        // NOTE: lane markings come from the ProcTexture.Road() texture itself
        // (center dashes, edge lines, tire-wear bands) — no separate dash boxes.

        /// <summary>
        /// Water surface quad. UVs tile the Water() texture ~8m; the offset is scrolled
        /// by WaterAnimator (scrolling material offset) and the shader adds waves.
        /// </summary>
        public static void WaterPlane(RegionContext ctx, float w, float d, Vector3 pos)
        {
            var part = NovaMobile.Core.MeshBuilder.GroundQuad(1f,
                Matrix4x4.TRS(pos, Quaternion.identity, new Vector3(w, 1f, d)));
            var uv = part.Uv;
            for (int i = 0; i < uv.Length; i++)
                uv[i] = new Vector2(uv[i].x * w / 8f, uv[i].y * d / 8f);
            part.Uv = uv;
            // MeshBuilder.GroundQuad winds clockwise seen from above; flip to CCW.
            var tris = part.Tris;
            for (int i = 0; i < tris.Length; i += 3)
            {
                int tmp = tris[i + 1];
                tris[i + 1] = tris[i + 2];
                tris[i + 2] = tmp;
            }
            part.Tris = tris;
            ctx.Batch.Part(part, ctx.Mats.Water, Color.white);
        }

        /// <summary>
        /// Tree: trunk cylinder + 2-3 deformed foliage spheres with the Foliage()
        /// texture (port of the Godot _tree).
        /// </summary>
        public static void Tree(RegionContext ctx, float x, float z, float groundY = 0f)
        {
            float h = ctx.RfRange(2.4f, 3.6f);
            Cyl(ctx, 0.22f, h, new Vector3(x, groundY + h * 0.5f, z),
                ctx.Mats.Trunk, Color.white);
            ctx.Batch.Collider(new Vector3(0.5f, h, 0.5f),
                T(new Vector3(x, groundY + h * 0.5f, z)));
            int blobs = ctx.Ri(2, 4);
            for (int i = 0; i < blobs; i++)
            {
                float cs = ctx.RfRange(1.9f, 2.9f);
                float ox = ctx.RfRange(-0.9f, 0.9f), oz = ctx.RfRange(-0.9f, 0.9f);
                ctx.Batch.Rock(new Vector3(cs, cs * 0.72f, cs),
                    T(new Vector3(x + ox, groundY + h + 0.3f + i * 0.8f, z + oz)),
                    ctx.Mats.Foliage, Color.white, false, 0.28f);
            }
        }

        public static void Palm(RegionContext ctx, float x, float z, float groundY = 0f)
        {
            float h = ctx.RfRange(4f, 6f);
            float lean = ctx.RfRange(-6f, 6f);
            var m = TR(new Vector3(x, groundY + h * 0.5f, z), 0f)
                * Matrix4x4.TRS(Vector3.zero, Quaternion.AngleAxis(lean, Vector3.forward), Vector3.one);
            ctx.Batch.Cylinder(0.16f, h, 8, m, ctx.Mats.Trunk, Color.white);
            for (int i = 0; i < 6; i++)
            {
                float a = Mathf.PI * 2f * i / 6f + ctx.Rf() * 0.5f;
                var frond = new Vector3(x + Mathf.Cos(a) * 1.6f, groundY + h + 0.4f, z + Mathf.Sin(a) * 1.6f);
                BuildingFactory.Strut(ctx.Batch,
                    new Vector3(x, groundY + h + 0.6f, z), frond, 0.28f, 0.1f,
                    ctx.Mats.Foliage, Color.white);
            }
        }

        /// <summary>Simple parked car from boxes (props only).</summary>
        public static void Car(RegionContext ctx, Vector3 pos, float yawDeg, Color body)
        {
            var f = TR(pos, yawDeg);
            ctx.Batch.Box(new Vector3(1.8f, 0.6f, 4.2f), f * T(new Vector3(0f, 0.65f, 0f)),
                ctx.Mats.Metal, body, true);
            ctx.Batch.Box(new Vector3(1.6f, 0.55f, 2.2f), f * T(new Vector3(0f, 1.2f, -0.2f)),
                ctx.Mats.GlassDark, Color.white);
            foreach (float sx in new[] { -0.85f, 0.85f })
                foreach (float sz in new[] { -1.4f, 1.4f })
                    ctx.Batch.Cylinder(0.33f, 0.25f, 8, f * T(new Vector3(sx, 0.33f, sz)),
                        ctx.Mats.HullBlack, Color.white);
        }

        /// <summary>Street lamp: pole + emissive head (no real light cost).</summary>
        public static void Streetlight(RegionContext ctx, Vector3 pos, float yawDeg, float h = 7.5f)
        {
            Cyl(ctx, 0.09f, h, pos + new Vector3(0f, h * 0.5f, 0f), ctx.Mats.SteelDark, Color.white);
            Box(ctx, new Vector3(0.5f, 0.18f, 0.7f), pos + new Vector3(0f, h, 0.3f),
                ctx.Mats.Emissive, new Color(1f, 0.95f, 0.8f), false, yawDeg);
        }

        /// <summary>Sandbag wall segment (cover).</summary>
        public static void SandbagWall(RegionContext ctx, float x, float z, float yawDeg, float length = 3.6f)
        {
            var f = TR(new Vector3(x, 0f, z), yawDeg);
            int n = Mathf.Max(2, Mathf.RoundToInt(length / 1.2f));
            for (int i = 0; i < n; i++)
            {
                float lx = -length * 0.5f + length * (i + 0.5f) / n;
                for (int r = 0; r < 3; r++)
                    ctx.Batch.Rock(new Vector3(1.1f, 0.35f, 0.6f),
                        f * T(new Vector3(lx, 0.18f + r * 0.32f, 0f)),
                        ctx.Mats.Sand, Color.white);
            }
            ctx.Batch.Collider(new Vector3(length, 1.1f, 0.7f), f * T(new Vector3(0f, 0.55f, 0f)));
        }

        /// <summary>Watchtower: 4 legs, cabin, roof (port of barracks/valley _watchtower).</summary>
        public static void Watchtower(RegionContext ctx, float x, float z, float yawDeg)
        {
            var f = TR(new Vector3(x, 0f, z), yawDeg);
            foreach (float sx in new[] { -1.2f, 1.2f })
                foreach (float sz in new[] { -1.2f, 1.2f })
                {
                    var leg = f * T(new Vector3(sx, 3f, sz));
                    ctx.Batch.Box(new Vector3(0.25f, 6f, 0.25f), leg, ctx.Mats.WoodDark, Color.white, true);
                }
            ctx.Batch.Box(new Vector3(3.4f, 0.25f, 3.4f), f * T(new Vector3(0f, 6f, 0f)),
                ctx.Mats.Wood, Color.white, true);
            // cabin with window band
            BuildingFactory.WindowWall(ctx.Batch, f * T(new Vector3(0f, 6.1f, 1.6f)),
                3.2f, 2.2f, 0.15f, ctx.Mats.Wood, Color.white, ctx.Mats);
            ctx.Batch.Box(new Vector3(3.2f, 2.2f, 0.15f), f * T(new Vector3(0f, 7.2f, -1.6f)),
                ctx.Mats.Wood, Color.white, true);
            ctx.Batch.Box(new Vector3(3.8f, 0.15f, 3.8f), f * T(new Vector3(0f, 8.5f, 0f)),
                ctx.Mats.RoofGrey, Color.white);
            BuildingFactory.Stairs(ctx.Batch, f, 1.4f, 6f, 1.2f, 0f, 6f, 0f,
                ctx.Mats.WoodDark, ctx.Mats.WoodDark);
            ctx.AddLoot("ammo", 60, new Vector3(x, 6.6f, z), 2);
        }

        /// <summary>Simple market stall (port of the Godot _stall).</summary>
        public static void Stall(RegionContext ctx, Vector3 pos, float yawDeg)
        {
            var f = TR(pos, yawDeg);
            foreach (float cx in new[] { -1f, 1f })
                foreach (float cz in new[] { -1f, 1f })
                    ctx.Batch.Box(new Vector3(0.12f, 2.3f, 0.12f),
                        f * T(new Vector3(cx * 1.3f, 1.15f, cz * 1f)), ctx.Mats.WoodDark, Color.white, true);
            var canopy = f * Matrix4x4.TRS(new Vector3(0f, 2.42f, 0f),
                Quaternion.AngleAxis(4.5f, Vector3.right), Vector3.one);
            ctx.Batch.Box(new Vector3(3.2f, 0.08f, 2.6f), canopy, ctx.Mats.RoofRed, Color.white);
            ctx.Batch.Box(new Vector3(2.4f, 0.1f, 1.4f), f * T(new Vector3(0f, 0.85f, 0f)),
                ctx.Mats.WoodDark, Color.white, true);
            for (int i = 0; i < 4; i++)
                ctx.Batch.Box(new Vector3(0.3f, 0.25f, 0.3f),
                    f * T(new Vector3(-0.8f + i * 0.55f, 1.02f, ctx.RfRange(-0.3f, 0.3f))),
                    ctx.Mats.Wood, new Color(0.8f, 0.5f, 0.25f));
        }

        /// <summary>Crate stack prop.</summary>
        public static void CrateStack(RegionContext ctx, Vector3 pos, float s = 0.9f)
        {
            Box(ctx, new Vector3(s, s, s), pos + new Vector3(0f, s * 0.5f, 0f),
                ctx.Mats.Wood, Color.white, true);
            Box(ctx, new Vector3(s * 0.7f, s * 0.7f, s * 0.7f),
                pos + new Vector3(s * 0.2f, s + s * 0.35f, 0f), ctx.Mats.WoodDark, Color.white, true);
        }
    }
}
