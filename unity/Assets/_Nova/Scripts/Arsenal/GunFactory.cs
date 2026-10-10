using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Arsenal
{
    /// <summary>
    /// Parametric gun mesh builder, ported from Godot gun_models.gd.
    /// All guns are built pointing along +Z (Unity forward) with the origin at the
    /// receiver/trigger area. (Note: the Godot long-gun builder already places barrels
    /// at +Z local; pistol/melee/launcher builders place them at -Z, so those are
    /// Z-mirrored here to keep one consistent forward convention.)
    ///
    /// BuildGun(spec, firstPerson:false) is the THIRD-PERSON model — the priority:
    /// clean readable silhouettes per weapon class for characters' hands / backs at
    /// 3-5 m. firstPerson:true builds a simplified variant (detail parts skipped).
    ///
    /// Named child parts ("Body","Barrel","Mag","Stock","Sight","Muzzle","Grip") are
    /// always created so the Mythics system can attach accents; plus "MuzzlePoint"
    /// and "Eject" locators. Materials are shared via a static cache keyed by color.
    /// </summary>
    public static class GunFactory
    {
        // ---------------- materials ----------------
        private struct MatDef
        {
            public Color color;
            public float metallic;
            public float smoothness;
            public bool emissive;
            public Color emission;
        }

        private static readonly Dictionary<string, Material> _mats = new Dictionary<string, Material>();

        private static MatDef DefOf(string key)
        {
            switch (key)
            {
                case "gunmetal": return new MatDef { color = new Color(0.16f, 0.17f, 0.19f), metallic = 0.85f, smoothness = 0.62f };
                case "black":    return new MatDef { color = new Color(0.09f, 0.09f, 0.10f), metallic = 0.15f, smoothness = 0.32f };
                case "steel":    return new MatDef { color = new Color(0.48f, 0.50f, 0.53f), metallic = 0.90f, smoothness = 0.70f };
                case "wood":     return new MatDef { color = new Color(0.42f, 0.26f, 0.14f), metallic = 0.00f, smoothness = 0.42f };
                case "tan":      return new MatDef { color = new Color(0.52f, 0.44f, 0.31f), metallic = 0.05f, smoothness = 0.38f };
                case "od":       return new MatDef { color = new Color(0.28f, 0.32f, 0.22f), metallic = 0.10f, smoothness = 0.40f };
                case "grey":     return new MatDef { color = new Color(0.35f, 0.36f, 0.38f), metallic = 0.40f, smoothness = 0.50f };
                case "white":    return new MatDef { color = new Color(0.76f, 0.76f, 0.79f), metallic = 0.20f, smoothness = 0.55f };
                case "dark":     return new MatDef { color = new Color(0.04f, 0.04f, 0.05f), metallic = 0.30f, smoothness = 0.40f };
                case "brass":    return new MatDef { color = new Color(0.72f, 0.55f, 0.25f), metallic = 0.90f, smoothness = 0.65f };
                case "bronze":   return new MatDef { color = new Color(0.45f, 0.32f, 0.18f), metallic = 0.85f, smoothness = 0.58f };
                case "graphite": return new MatDef { color = new Color(0.22f, 0.23f, 0.26f), metallic = 0.70f, smoothness = 0.55f };
                case "bluegrey": return new MatDef { color = new Color(0.30f, 0.36f, 0.44f), metallic = 0.50f, smoothness = 0.50f };
                case "carbon":   return new MatDef { color = new Color(0.07f, 0.07f, 0.08f), metallic = 0.35f, smoothness = 0.60f };
                case "sand":     return new MatDef { color = new Color(0.62f, 0.54f, 0.40f), metallic = 0.05f, smoothness = 0.35f };
                case "glass":    return new MatDef { color = new Color(0.25f, 0.55f, 0.75f), metallic = 0.10f, smoothness = 0.85f,
                                                    emissive = true, emission = new Color(0.12f, 0.30f, 0.42f) };
                default:         return new MatDef { color = new Color(0.12f, 0.12f, 0.13f), metallic = 0.50f, smoothness = 0.50f };
            }
        }

        /// <summary>Shared material cache keyed by color name.</summary>
        public static Material Mat(string key)
        {
            Material m;
            if (_mats.TryGetValue(key, out m)) return m;
            MatDef d = DefOf(key);
            m = new Material(Shader.Find("Standard"));
            m.color = d.color;
            m.SetFloat("_Metallic", d.metallic);
            m.SetFloat("_Glossiness", d.smoothness);
            if (d.emissive)
            {
                m.EnableKeyword("_EMISSION");
                m.SetColor("_EmissionColor", d.emission);
            }
            _mats[key] = m;
            return m;
        }

        /// <summary>Body color-scheme mapping (same fallbacks as Godot _body_mat).</summary>
        public static Material BodyMat(string scheme)
        {
            if (scheme == "gunmetal") return Mat("gunmetal");
            if (scheme == "tan" || scheme == "sand") return Mat("tan");
            if (scheme == "od") return Mat("od");
            if (scheme == "grey") return Mat("grey");
            if (scheme == "white") return Mat("white");
            if (scheme == "bronze") return Mat("bronze");
            if (scheme == "graphite") return Mat("graphite");
            if (scheme == "bluegrey") return Mat("bluegrey");
            return Mat("black");
        }

        public static string BodyKey(string scheme)
        {
            if (scheme == "gunmetal") return "gunmetal";
            if (scheme == "tan" || scheme == "sand") return "tan";
            if (scheme == "od") return "od";
            if (scheme == "grey") return "grey";
            if (scheme == "white") return "white";
            if (scheme == "bronze") return "bronze";
            if (scheme == "graphite") return "graphite";
            if (scheme == "bluegrey") return "bluegrey";
            return "black";
        }

        private static readonly Dictionary<string, Material> _emissive = new Dictionary<string, Material>();

        public static Material EmissiveMat(Color c)
        {
            string key = c.ToString();
            Material m;
            if (_emissive.TryGetValue(key, out m)) return m;
            m = new Material(Shader.Find("Standard"));
            m.color = Color.black;
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", c);
            _emissive[key] = m;
            return m;
        }

        // ---------------- build context ----------------
        private struct BinEntry
        {
            public MeshBuilder.Part part;
            public string mat;
        }

        private class BuildCtx
        {
            public readonly Dictionary<string, List<BinEntry>> bins = new Dictionary<string, List<BinEntry>>();
            public bool detail = true;   // false = simplified first-person variant
            public bool mirrorZ = false; // true = mirror Godot -Z-forward builders to +Z
        }

        private static readonly string[] PartNames = new string[]
            { "Body", "Barrel", "Mag", "Stock", "Sight", "Muzzle", "Grip" };

        private static Vector3 V(float x, float y, float z) { return new Vector3(x, y, z); }

        // Godot-space -> build-space. Long guns: identity. Others: mirror Z so the
        // barrel ends up at +Z (Unity forward) like every other gun.
        private static Vector3 P(BuildCtx c, Vector3 p)
        {
            return c.mirrorZ ? new Vector3(p.x, p.y, -p.z) : p;
        }

        // Euler radians, Godot XYZ -> mirrored frame: (rx,ry,rz) -> (-rx,-ry,rz).
        private static Vector3 E(BuildCtx c, Vector3 e)
        {
            return c.mirrorZ ? new Vector3(-e.x, -e.y, e.z) : e;
        }

        private static Vector3 A(BuildCtx c, Vector3 a)
        {
            return c.mirrorZ ? new Vector3(a.x, a.y, -a.z) : a;
        }

        private static void Add(BuildCtx c, string part, string mat, MeshBuilder.Part p)
        {
            List<BinEntry> list;
            if (!c.bins.TryGetValue(part, out list))
            {
                list = new List<BinEntry>();
                c.bins[part] = list;
            }
            list.Add(new BinEntry { part = p, mat = mat });
        }

        private static void Box(BuildCtx c, string part, string mat, Vector3 size, Vector3 pos, Vector3 eulerRad)
        {
            var m = Matrix4x4.TRS(P(c, pos), Quaternion.Euler(E(c, eulerRad) * Mathf.Rad2Deg), Vector3.one);
            Add(c, part, mat, MeshBuilder.Box(size, m));
        }

        private static void Cyl(BuildCtx c, string part, string mat, float radius, float height,
            int segs, Vector3 pos, Vector3 axis)
        {
            Vector3 ax = A(c, axis).normalized;
            var m = Matrix4x4.TRS(P(c, pos), Quaternion.FromToRotation(Vector3.up, ax), Vector3.one);
            Add(c, part, mat, MeshBuilder.Cylinder(radius, height, segs, m));
        }

        /// <summary>Tapered cylinder (Godot CylinderMesh top_radius/bottom_radius).</summary>
        private static void Frustum(BuildCtx c, string part, string mat, float topR, float botR,
            float height, int segs, Vector3 pos, Vector3 axis)
        {
            Vector3 ax = A(c, axis).normalized;
            var m = Matrix4x4.TRS(P(c, pos), Quaternion.FromToRotation(Vector3.up, ax), Vector3.one);
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var tris = new List<int>();
            for (int i = 0; i <= segs; i++)
            {
                float a = (float)i / segs * Mathf.PI * 2f;
                float ca = Mathf.Cos(a), sa = Mathf.Sin(a);
                int b = verts.Count;
                verts.Add(m.MultiplyPoint3x4(new Vector3(ca * botR, -height / 2f, sa * botR)));
                verts.Add(m.MultiplyPoint3x4(new Vector3(ca * topR, height / 2f, sa * topR)));
                Vector3 n = m.MultiplyVector(new Vector3(ca, (botR - topR) / height, sa)).normalized;
                normals.Add(n); normals.Add(n);
                if (i < segs)
                {
                    tris.Add(b); tris.Add(b + 2); tris.Add(b + 1);
                    tris.Add(b + 1); tris.Add(b + 2); tris.Add(b + 3);
                }
            }
            int cb = verts.Count;
            verts.Add(m.MultiplyPoint3x4(new Vector3(0f, -height / 2f, 0f)));
            normals.Add(m.MultiplyVector(Vector3.down));
            verts.Add(m.MultiplyPoint3x4(new Vector3(0f, height / 2f, 0f)));
            normals.Add(m.MultiplyVector(Vector3.up));
            for (int i = 0; i < segs; i++)
            {
                tris.Add(cb); tris.Add((i + 1) * 2); tris.Add(i * 2);
                tris.Add(cb + 1); tris.Add(i * 2 + 1); tris.Add((i + 1) * 2 + 1);
            }
            var uv = new Vector2[verts.Count];
            Add(c, part, mat, new MeshBuilder.Part
            {
                Verts = verts.ToArray(), Tris = tris.ToArray(),
                Normals = normals.ToArray(), Uv = uv, Matrix = Matrix4x4.identity
            });
        }

        // ---------------- extras helpers ----------------
        private static bool HasExtra(GunModelSpec m, string name)
        {
            if (m.Extras == null) return false;
            for (int i = 0; i < m.Extras.Length; i++)
                if (m.Extras[i] == name) return true;
            return false;
        }

        private static bool HasMeta(GunModelSpec m, string name)
        {
            return HasExtra(m, name);
        }

        private static string MetaValue(GunModelSpec m, string prefix)
        {
            if (m.Extras == null) return "";
            for (int i = 0; i < m.Extras.Length; i++)
            {
                string e = m.Extras[i];
                if (e.StartsWith(prefix + ":", StringComparison.Ordinal))
                    return e.Substring(prefix.Length + 1);
            }
            return "";
        }

        // ---------------- public entry ----------------
        /// <summary>
        /// Builds a full gun GameObject. firstPerson:false = detailed third-person model
        /// (the priority); firstPerson:true = simplified variant. Named child parts:
        /// Body, Barrel, Mag, Stock, Sight, Muzzle, Grip (+ MuzzlePoint, Eject locators).
        /// </summary>
        public static GameObject BuildGun(GunSpec spec, bool firstPerson)
        {
            var ctx = new BuildCtx { detail = !firstPerson, mirrorZ = false };
            GunModelSpec m = spec.Model;
            Vector3 muzzlePos, ejectPos;
            switch (spec.Class)
            {
                case GunClass.Melee:
                    ctx.mirrorZ = true;
                    BuildMelee(ctx, m);
                    muzzlePos = new Vector3(0f, 0f, 0.4f);
                    ejectPos = new Vector3(0.06f, 0.03f, 0.02f);
                    break;
                case GunClass.Pistol:
                    ctx.mirrorZ = true;
                    BuildPistol(ctx, m);
                    float blp = 0.12f + m.Barrel;
                    muzzlePos = new Vector3(0f, 0.03f, blp + 0.02f);
                    ejectPos = new Vector3(0.06f, 0.03f, 0.02f);
                    break;
                case GunClass.Launcher:
                    ctx.mirrorZ = true;
                    BuildLauncher(ctx, m);
                    muzzlePos = new Vector3(0f, 0.03f, 0.62f);
                    ejectPos = new Vector3(0.06f, 0.03f, 0.02f);
                    break;
                default:
                    BuildLongGun(ctx, m);
                    float bl2 = m.Barrel;
                    float extra = (m.Muzzle == "suppressor" || m.Muzzle == "shroud") ? 0.24f : 0.10f;
                    muzzlePos = new Vector3(0f, 0.02f, 0.17f + bl2 + extra);
                    ejectPos = new Vector3(0.06f, 0.03f, -0.02f);
                    break;
            }

            var root = new GameObject((firstPerson ? "Viewmodel_" : "TP_") + spec.Id);
            foreach (string partName in PartNames)
            {
                var partGo = new GameObject(partName);
                partGo.transform.SetParent(root.transform, false);
                List<BinEntry> list;
                if (!ctx.bins.TryGetValue(partName, out list)) continue;
                // group by material -> one combined mesh each
                var byMat = new Dictionary<string, List<MeshBuilder.Part>>();
                for (int i = 0; i < list.Count; i++)
                {
                    List<MeshBuilder.Part> pl;
                    if (!byMat.TryGetValue(list[i].mat, out pl))
                    {
                        pl = new List<MeshBuilder.Part>();
                        byMat[list[i].mat] = pl;
                    }
                    pl.Add(list[i].part);
                }
                foreach (var kv in byMat)
                {
                    var go = new GameObject(partName + "_" + kv.Key);
                    go.transform.SetParent(partGo.transform, false);
                    var mf = go.AddComponent<MeshFilter>();
                    mf.mesh = MeshBuilder.Combine(kv.Value);
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.material = kv.Key.StartsWith("emit:", StringComparison.Ordinal)
                        ? EmissiveMat(ParseColor(kv.Key.Substring(5)))
                        : Mat(kv.Key);
                }
            }
            var muzzleGo = new GameObject("MuzzlePoint");
            muzzleGo.transform.SetParent(root.transform, false);
            muzzleGo.transform.localPosition = muzzlePos;
            var ejectGo = new GameObject("Eject");
            ejectGo.transform.SetParent(root.transform, false);
            ejectGo.transform.localPosition = ejectPos;
            return root;
        }

        private static Color ParseColor(string s)
        {
            // "r,g,b"
            string[] p = s.Split(',');
            if (p.Length < 3) return Color.white;
            float r, g, b;
            if (!float.TryParse(p[0], out r)) r = 1f;
            if (!float.TryParse(p[1], out g)) g = 1f;
            if (!float.TryParse(p[2], out b)) b = 1f;
            return new Color(r, g, b);
        }

        /// <summary>Sight-line height above gun origin (for ADS centering).</summary>
        public static float SightHeight(string gunId)
        {
            GunSpec g = GunData.Get(gunId);
            string s = g.Model.Sight;
            if (s == "scope" || s == "scopelong" || s == "thermal") return 0.095f;
            if (s == "holo" || s == "acog") return 0.085f;
            if (s == "reddot") return 0.080f;
            return 0.072f;
        }

        /// <summary>
        /// Simplified ground/loot model (cheap variant for pickups at distance),
        /// ported from Godot build_world_model. Barrel toward +Z.
        /// </summary>
        public static GameObject BuildWorldModel(GunSpec spec)
        {
            var ctx = new BuildCtx { detail = false, mirrorZ = spec.Class == GunClass.Pistol || spec.Class == GunClass.Launcher || spec.Class == GunClass.Melee };
            GunModelSpec m = spec.Model;
            string body = BodyKey(m.Body);
            string dark = "dark";
            switch (spec.Class)
            {
                case GunClass.Melee:
                    BuildMelee(ctx, m);
                    break;
                case GunClass.Pistol:
                    {
                        string style = m.Style;
                        if (style == "crossbow")
                        {
                            Box(ctx, "Body", body, V(0.05f, 0.07f, 0.30f), V(0, 0, -0.05f), V(0, 0, 0));
                            Box(ctx, "Body", dark, V(0.34f, 0.025f, 0.05f), V(0, 0.02f, -0.12f), V(0, 0, 0));
                        }
                        else if (style == "revolver")
                        {
                            Box(ctx, "Body", body, V(0.045f, 0.07f, 0.16f), V(0, 0, 0), V(0, 0, 0));
                            Cyl(ctx, "Body", dark, 0.035f, 0.07f, 10, V(0, 0.01f, -0.02f), V(0, 0, 1));
                            Cyl(ctx, "Barrel", dark, 0.016f, 0.16f, 8, V(0, 0.02f, -0.12f), V(0, 0, 1));
                        }
                        else if (style == "nailgun")
                        {
                            Box(ctx, "Body", body, V(0.07f, 0.10f, 0.22f), V(0, 0, 0), V(0, 0, 0));
                            Box(ctx, "Body", dark, V(0.03f, 0.03f, 0.24f), V(0, 0.065f, 0), V(0, 0, 0));
                        }
                        else
                        {
                            Box(ctx, "Body", body, V(0.05f, 0.07f, 0.22f), V(0, 0, 0), V(0, 0, 0));
                            Box(ctx, "Grip", body, V(0.045f, 0.14f, 0.06f), V(0, -0.09f, 0.05f), V(0.2f, 0, 0));
                            Box(ctx, "Sight", dark, V(0.02f, 0.02f, 0.05f), V(0, 0.05f, -0.08f), V(0, 0, 0));
                        }
                    }
                    break;
                case GunClass.Launcher:
                    Cyl(ctx, "Body", body, 0.055f, 0.9f, 10, V(0, 0, 0), V(0, 0, 1));
                    if (m.Style == "rpg7")
                        Frustum(ctx, "Muzzle", dark, 0.012f, 0.075f, 0.20f, 10, V(0, 0, -0.55f), V(0, 0, 1));
                    Box(ctx, "Grip", "wood", V(0.05f, 0.12f, 0.08f), V(0, -0.1f, 0.1f), V(0, 0, 0));
                    break;
                default:
                    {
                        float bl = m.Barrel;
                        Box(ctx, "Body", body, V(0.07f, 0.10f, 0.38f), V(0, 0, 0), V(0, 0, 0));
                        Cyl(ctx, "Barrel", "gunmetal", 0.022f, bl, 8, V(0, 0.02f, 0.19f + bl * 0.5f), V(0, 0, 1));
                        Box(ctx, "Body", body, V(0.08f, 0.09f, 0.26f), V(0, 0.01f, 0.28f), V(0, 0, 0));
                        MagWorld(ctx, m, body);
                        Box(ctx, "Stock", body, V(0.06f, 0.12f, 0.26f), V(0, -0.01f, -0.32f), V(0, 0, 0));
                        string sight = m.Sight;
                        if (sight == "scope" || sight == "scopelong")
                            Cyl(ctx, "Sight", dark, 0.035f, 0.24f, 8, V(0, 0.10f, -0.02f), V(0, 0, 1));
                    }
                    break;
            }
            var root = new GameObject("Worldmodel_" + spec.Id);
            foreach (string partName in PartNames)
            {
                List<BinEntry> list;
                if (!ctx.bins.TryGetValue(partName, out list)) continue;
                var partGo = new GameObject(partName);
                partGo.transform.SetParent(root.transform, false);
                var byMat = new Dictionary<string, List<MeshBuilder.Part>>();
                for (int i = 0; i < list.Count; i++)
                {
                    List<MeshBuilder.Part> p2;
                    if (!byMat.TryGetValue(list[i].mat, out p2))
                    {
                        p2 = new List<MeshBuilder.Part>();
                        byMat[list[i].mat] = p2;
                    }
                    p2.Add(list[i].part);
                }
                foreach (var kv in byMat)
                {
                    var go = new GameObject(partName + "_" + kv.Key);
                    go.transform.SetParent(partGo.transform, false);
                    var mf = go.AddComponent<MeshFilter>();
                    mf.mesh = MeshBuilder.Combine(kv.Value);
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.material = Mat(kv.Key);
                }
            }
            return root;
        }

        private static void MagWorld(BuildCtx c, GunModelSpec m, string body)
        {
            string kind = m.Mag;
            if (kind == "drum")
                Cyl(c, "Mag", body, 0.10f, 0.06f, 10, V(0, -0.14f, 0.06f), V(1, 0, 0));
            else if (kind == "box" || kind == "belt")
                Box(c, "Mag", body, V(0.13f, 0.15f, 0.17f), V(-0.1f, -0.12f, 0.02f), V(0, 0, 0));
            else if (kind == "pan")
                Cyl(c, "Mag", body, 0.11f, 0.045f, 10, V(0, 0.10f, 0.05f), V(0, 1, 0));
            else if (kind == "helix" || kind == "helixunder")
                Cyl(c, "Mag", body, 0.038f, 0.30f, 8, V(0, -0.06f, 0.12f), V(0, 0, 1));
            else if (kind == "tube")
                Cyl(c, "Mag", "gunmetal", 0.028f, 0.34f, 8, V(0, -0.045f, 0.32f), V(0, 0, 1));
            else if (kind == "none" || kind == "internal") { }
            else
                Box(c, "Mag", body, V(0.05f, 0.2f, 0.09f), V(0, -0.16f, 0.06f), V(-0.15f, 0, 0));
        }

        // ---------------- long guns (ar/smg/lmg/sniper/marksman/shotgun) ----------------
        // Detailed viewmodel for third-person. Godot coordinates used verbatim
        // (barrel already at +Z in the spec). Set ctx.detail=false for the
        // simplified first-person variant.
        private static void BuildLongGun(BuildCtx c, GunModelSpec m)
        {
            string body = BodyKey(m.Body);
            string dark = "dark";
            string steel = "steel";
            string gunmetal = "gunmetal";
            string wood = (m.Accent == "wood") ? "wood" : body;
            string style = m.Style;
            float bl = m.Barrel;

            // --- receiver (style-shaped) ---
            float rl = 0.36f;
            string recv = MetaValue(m, "receiver");
            if (style == "bullpup")
            {
                rl = 0.46f;
                Box(c, "Body", body, V(0.075f, 0.105f, rl), V(0, 0, 0.02f), V(0, 0, 0));
                Box(c, "Body", "black", V(0.06f, 0.05f, 0.10f), V(0, -0.075f, -0.14f), V(0, 0, 0));
            }
            else if (style == "machine" || style == "rapid")
            {
                Box(c, "Body", body, V(0.06f, 0.085f, 0.30f), V(0, 0, 0), V(0, 0, 0));
                rl = 0.30f;
            }
            else if (recv == "slim")
                Box(c, "Body", body, V(0.055f, 0.08f, rl), V(0, 0, 0), V(0, 0, 0));
            else if (recv == "boxy")
                Box(c, "Body", body, V(0.085f, 0.115f, rl), V(0, 0.005f, 0), V(0, 0, 0));
            else if (recv == "angular")
            {
                Box(c, "Body", body, V(0.07f, 0.095f, rl), V(0, 0, 0), V(0, 0, 0));
                Box(c, "Body", body, V(0.05f, 0.06f, rl * 0.5f), V(0, 0.03f, rl * 0.2f), V(0.3f, 0, 0));
            }
            else if (recv == "tube")
                Cyl(c, "Body", body, 0.042f, rl, 10, V(0, 0, 0), V(0, 0, 1));
            else
                Box(c, "Body", body, V(0.068f, 0.095f, rl), V(0, 0, 0), V(0, 0, 0));

            // top rail (skippable for sporter/vintage hunting looks)
            if (!HasMeta(m, "notoprail"))
                Box(c, "Body", dark, V(0.03f, 0.012f, rl * 0.8f), V(0, 0.054f, 0.02f), V(0, 0, 0));
            // carry handle (retro)
            if (HasMeta(m, "carryhandle"))
            {
                Box(c, "Body", body, V(0.025f, 0.05f, 0.20f), V(0, 0.085f, -0.02f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Body", body, V(0.025f, 0.012f, 0.16f), V(0, 0.115f, -0.02f), V(0, 0, 0));
            }
            // revolving cylinder (Outlaw-style bolt sniper)
            if (HasMeta(m, "cylinder"))
            {
                Cyl(c, "Body", steel, 0.045f, 0.10f, 12, V(0, 0, -0.10f), V(0, 0, 1));
                if (c.detail)
                    for (int i = 0; i < 6; i++)
                    {
                        float a = (float)i * Mathf.PI * 2f / 6f;
                        Box(c, "Body", dark, V(0.016f, 0.016f, 0.10f),
                            V(Mathf.Cos(a) * 0.032f, Mathf.Sin(a) * 0.032f, -0.10f), V(0, 0, 0));
                    }
            }
            // lever loop (lever-action)
            if (HasMeta(m, "lever") && c.detail)
            {
                Box(c, "Body", steel, V(0.012f, 0.09f, 0.05f), V(0, -0.13f, -0.02f), V(0, 0, 0));
                Box(c, "Body", steel, V(0.012f, 0.012f, 0.09f), V(0, -0.175f, -0.04f), V(0, 0, 0));
            }
            // glowing accent (exotic guns: NA-45 primer ring etc.)
            string glow = MetaValue(m, "glow");
            if (glow != "")
            {
                Color gc = glow == "amber" ? new Color(1f, 0.7f, 0.15f)
                    : glow == "cyan" ? new Color(0.2f, 0.9f, 1f)
                    : glow == "red" ? new Color(1f, 0.2f, 0.15f)
                    : new Color(0.5f, 1f, 0.3f);
                Box(c, "Body", "emit:" + gc.r + "," + gc.g + "," + gc.b,
                    V(0.072f, 0.02f, 0.06f), V(0, 0, 0.10f), V(0, 0, 0));
            }
            // ejection port (right side) + charging handle (rear top)
            if (c.detail)
            {
                Box(c, "Body", dark, V(0.005f, 0.035f, 0.09f), V(0.036f, 0.012f, 0.03f), V(0, 0, 0));
                Box(c, "Body", steel, V(0.05f, 0.015f, 0.03f), V(0, 0.055f, -rl * 0.5f + 0.02f), V(0, 0, 0));
            }

            // --- barrel + handguard ---
            float bstart = rl * 0.5f;
            if (HasMeta(m, "twinbarrel"))
            {
                Cyl(c, "Barrel", gunmetal, 0.021f, bl, 10, V(-0.035f, 0.02f, bstart + bl * 0.5f), V(0, 0, 1));
                Cyl(c, "Barrel", gunmetal, 0.021f, bl, 10, V(0.035f, 0.02f, bstart + bl * 0.5f), V(0, 0, 1));
            }
            else
                Cyl(c, "Barrel", gunmetal, 0.021f, bl, 10, V(0, 0.02f, bstart + bl * 0.5f), V(0, 0, 1));
            float hgLen = Mathf.Min(bl * 0.55f, 0.30f);
            if (style == "heavy" || style == "belt")
                hgLen = Mathf.Min(bl * 0.6f, 0.34f);
            string hgMat = (m.Accent == "wood" && (style == "piston" || style == "classic")) ? wood : body;
            Box(c, "Body", hgMat, V(0.075f, 0.085f, hgLen), V(0, 0.015f, bstart + hgLen * 0.5f + 0.02f), V(0, 0, 0));
            // heatshield vents
            if (HasExtra(m, "heatshield") && c.detail)
                for (int i = 0; i < 3; i++)
                    Box(c, "Body", dark, V(0.078f, 0.012f, 0.03f), V(0, 0.05f, bstart + 0.08f + i * 0.06f), V(0, 0, 0));

            // --- muzzle device ---
            MuzzleDevice(c, m, V(0, 0.02f, bstart + bl));
            // --- magazine / stock / grip / sights / extras ---
            MagDetail(c, m, body);
            StockDetail(c, m, body, rl);
            Box(c, "Grip", "black", V(0.045f, 0.13f, 0.055f), V(0, -0.10f, -0.07f), V(0.35f, 0, 0));
            if (c.detail)
            {
                Box(c, "Grip", steel, V(0.012f, 0.05f, 0.02f), V(0, -0.075f, -0.015f), V(0.2f, 0, 0));
                Box(c, "Grip", dark, V(0.05f, 0.012f, 0.11f), V(0, -0.105f, -0.03f), V(0, 0, 0));
            }
            SightDetail(c, m, dark, steel);
            if (HasExtra(m, "foregrip"))
                Box(c, "Grip", "black", V(0.04f, 0.11f, 0.045f), V(0, -0.07f, bstart + hgLen * 0.6f), V(0.15f, 0, 0));
            if (HasExtra(m, "bipod"))
            {
                Box(c, "Body", steel, V(0.015f, 0.16f, 0.015f), V(-0.05f, -0.10f, bstart + bl * 0.8f), V(0, 0, 0.25f));
                Box(c, "Body", steel, V(0.015f, 0.16f, 0.015f), V(0.05f, -0.10f, bstart + bl * 0.8f), V(0, 0, -0.25f));
            }
            if (HasExtra(m, "laser"))
                Box(c, "Body", dark, V(0.03f, 0.03f, 0.07f), V(0.05f, 0.02f, bstart + 0.10f), V(0, 0, 0));
            if (HasExtra(m, "bayonet"))
                Box(c, "Barrel", steel, V(0.012f, 0.03f, 0.24f), V(0, -0.02f, bstart + bl + 0.10f), V(0, 0, 0));
            if (HasExtra(m, "carry"))
                Box(c, "Body", body, V(0.025f, 0.05f, 0.24f), V(0, 0.085f, -0.02f), V(0, 0, 0));
        }

        private static void MuzzleDevice(BuildCtx c, GunModelSpec m, Vector3 tip)
        {
            string kind = m.Muzzle;
            string gunmetal = "gunmetal";
            string dark = "dark";
            if (kind == "suppressor")
            {
                Cyl(c, "Muzzle", dark, 0.034f, 0.20f, 12, tip + V(0, 0, 0.10f), V(0, 0, 1));
                Cyl(c, "Muzzle", gunmetal, 0.036f, 0.03f, 12, tip + V(0, 0, 0.02f), V(0, 0, 1));
            }
            else if (kind == "comp")
            {
                Box(c, "Muzzle", gunmetal, V(0.05f, 0.05f, 0.09f), tip + V(0, 0, 0.045f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Muzzle", dark, V(0.054f, 0.02f, 0.06f), tip + V(0, 0.01f, 0.045f), V(0, 0, 0));
            }
            else if (kind == "brake")
            {
                Box(c, "Muzzle", gunmetal, V(0.062f, 0.062f, 0.11f), tip + V(0, 0, 0.055f), V(0, 0, 0));
                if (c.detail)
                    for (int i = 0; i < 2; i++)
                        Box(c, "Muzzle", dark, V(0.066f, 0.02f, 0.03f), tip + V(0, 0.015f, 0.03f + i * 0.05f), V(0, 0, 0));
            }
            else if (kind == "linear")
            {
                Cyl(c, "Muzzle", gunmetal, 0.032f, 0.13f, 10, tip + V(0, 0, 0.065f), V(0, 0, 1));
                Cyl(c, "Muzzle", dark, 0.034f, 0.02f, 10, tip + V(0, 0, 0.01f), V(0, 0, 1));
            }
            else if (kind == "shroud")
            {
                Cyl(c, "Muzzle", dark, 0.038f, 0.22f, 12, tip + V(0, 0, 0.11f), V(0, 0, 1));
                if (c.detail)
                    for (int i = 0; i < 3; i++)
                        Cyl(c, "Muzzle", gunmetal, 0.040f, 0.015f, 12, tip + V(0, 0, 0.05f + i * 0.06f), V(0, 0, 1));
            }
            else if (kind == "none") { }
            else // flash hider: prongs
            {
                Cyl(c, "Muzzle", gunmetal, 0.026f, 0.07f, 8, tip + V(0, 0, 0.035f), V(0, 0, 1));
                if (c.detail)
                    for (int i = 0; i < 3; i++)
                    {
                        float a = (float)i * Mathf.PI * 2f / 3f;
                        Box(c, "Muzzle", gunmetal, V(0.012f, 0.012f, 0.05f),
                            tip + V(Mathf.Cos(a) * 0.022f, Mathf.Sin(a) * 0.022f, 0.085f), V(0, 0, 0));
                    }
            }
        }

        private static void MagDetail(BuildCtx c, GunModelSpec m, string body)
        {
            string kind = m.Mag;
            string dark = "dark";
            if (kind == "curved")
            {
                Box(c, "Mag", body, V(0.052f, 0.24f, 0.095f), V(0, -0.16f, 0.07f), V(-0.28f, 0, 0));
                if (c.detail)
                    Box(c, "Mag", dark, V(0.056f, 0.03f, 0.10f), V(0, -0.27f, 0.10f), V(-0.28f, 0, 0));
            }
            else if (kind == "drum")
            {
                Cyl(c, "Mag", body, 0.095f, 0.06f, 14, V(0, -0.14f, 0.06f), V(1, 0, 0));
                if (c.detail)
                    Cyl(c, "Mag", dark, 0.03f, 0.065f, 10, V(0, -0.14f, 0.06f), V(1, 0, 0));
            }
            else if (kind == "box")
            {
                Box(c, "Mag", body, V(0.13f, 0.16f, 0.18f), V(-0.10f, -0.13f, 0.02f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Mag", dark, V(0.02f, 0.05f, 0.10f), V(-0.035f, -0.06f, 0.02f), V(0, 0, 0));
            }
            else if (kind == "tube")
            {
                Cyl(c, "Mag", "gunmetal", 0.028f, 0.36f, 10, V(0, -0.048f, 0.34f), V(0, 0, 1));
                Box(c, "Mag", dark, V(0.05f, 0.03f, 0.06f), V(0, -0.048f, 0.18f), V(0, 0, 0));
            }
            else if (kind == "stick")
                Box(c, "Mag", body, V(0.045f, 0.17f, 0.07f), V(0, -0.13f, 0.05f), V(0.1f, 0, 0));
            else if (kind == "helix")
            {
                Cyl(c, "Mag", body, 0.038f, 0.30f, 10, V(0, 0.085f, 0.02f), V(0, 0, 1));
                if (c.detail)
                    Box(c, "Mag", dark, V(0.03f, 0.05f, 0.06f), V(0, 0.03f, 0.02f), V(0, 0, 0));
            }
            else if (kind == "helixunder")
            {
                Cyl(c, "Mag", body, 0.035f, 0.34f, 10, V(0, -0.062f, 0.22f), V(0, 0, 1));
                if (c.detail)
                    Box(c, "Mag", dark, V(0.03f, 0.05f, 0.06f), V(0, -0.02f, 0.06f), V(0, 0, 0));
            }
            else if (kind == "pan")
            {
                Cyl(c, "Mag", body, 0.115f, 0.045f, 14, V(0, 0.10f, 0.05f), V(0, 1, 0));
                if (c.detail)
                    Cyl(c, "Mag", dark, 0.03f, 0.05f, 10, V(0, 0.10f, 0.05f), V(0, 1, 0));
            }
            else if (kind == "belt")
            {
                Box(c, "Mag", body, V(0.11f, 0.13f, 0.15f), V(-0.09f, -0.11f, 0.03f), V(0, 0, 0));
                if (c.detail)
                    for (int i = 0; i < 4; i++)
                        Box(c, "Mag", "brass", V(0.02f, 0.025f, 0.05f),
                            V(-0.03f, -0.05f - i * 0.008f, 0.03f), V(0, 0, 0.5f));
            }
            else if (kind == "casket")
            {
                Box(c, "Mag", body, V(0.085f, 0.19f, 0.10f), V(0, -0.14f, 0.06f), V(-0.08f, 0, 0));
                if (c.detail)
                    Box(c, "Mag", dark, V(0.089f, 0.03f, 0.104f), V(0, -0.225f, 0.075f), V(-0.08f, 0, 0));
            }
            else if (kind == "saddle")
            {
                Cyl(c, "Mag", "gunmetal", 0.026f, 0.30f, 8, V(-0.045f, -0.05f, 0.30f), V(0, 0, 1));
                Cyl(c, "Mag", "gunmetal", 0.026f, 0.30f, 8, V(0.045f, -0.05f, 0.30f), V(0, 0, 1));
            }
            else if (kind == "internal" || kind == "none") { }
            else // straight
                Box(c, "Mag", body, V(0.048f, 0.21f, 0.085f), V(0, -0.15f, 0.06f), V(-0.06f, 0, 0));
        }

        private static void StockDetail(BuildCtx c, GunModelSpec m, string body, float rl)
        {
            string kind = m.Stock;
            float rear = -rl * 0.5f;
            if (kind == "bullpup" || kind == "none")
                Box(c, "Stock", "black", V(0.06f, 0.10f, 0.06f), V(0, -0.01f, rear - 0.02f), V(0, 0, 0));
            else if (kind == "folding")
            {
                Box(c, "Stock", body, V(0.045f, 0.09f, 0.22f), V(0.01f, -0.01f, rear - 0.11f), V(0, 0.06f, 0));
                Box(c, "Stock", "black", V(0.05f, 0.11f, 0.04f), V(0.01f, -0.01f, rear - 0.23f), V(0, 0, 0));
            }
            else if (kind == "skeleton")
            {
                Box(c, "Stock", body, V(0.02f, 0.03f, 0.24f), V(-0.025f, 0.02f, rear - 0.12f), V(0, 0, 0));
                Box(c, "Stock", body, V(0.02f, 0.03f, 0.24f), V(0.025f, 0.02f, rear - 0.12f), V(0, 0, 0));
                Box(c, "Stock", "black", V(0.07f, 0.12f, 0.04f), V(0, -0.01f, rear - 0.25f), V(0, 0, 0));
            }
            else if (kind == "wire")
            {
                Cyl(c, "Stock", "steel", 0.011f, 0.24f, 8, V(-0.025f, 0, rear - 0.12f), V(0, 0, -1));
                Cyl(c, "Stock", "steel", 0.011f, 0.24f, 8, V(0.025f, 0, rear - 0.12f), V(0, 0, -1));
                Box(c, "Stock", "black", V(0.07f, 0.10f, 0.035f), V(0, -0.01f, rear - 0.25f), V(0, 0, 0));
            }
            else if (kind == "brace")
            {
                Box(c, "Stock", body, V(0.05f, 0.09f, 0.14f), V(0, -0.01f, rear - 0.07f), V(0, 0, 0));
                Box(c, "Stock", "black", V(0.055f, 0.05f, 0.05f), V(0, -0.01f, rear - 0.16f), V(0, 0, 0));
            }
            else if (kind == "pdw")
            {
                Box(c, "Stock", body, V(0.04f, 0.07f, 0.16f), V(0, 0, rear - 0.08f), V(0, 0, 0));
                Box(c, "Stock", "black", V(0.055f, 0.10f, 0.03f), V(0, -0.01f, rear - 0.17f), V(0, 0, 0));
            }
            else if (kind == "thumbhole")
            {
                Box(c, "Stock", body, V(0.06f, 0.13f, 0.30f), V(0, -0.02f, rear - 0.15f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Stock", "dark", V(0.062f, 0.05f, 0.10f), V(0, -0.03f, rear - 0.12f), V(0, 0, 0));
                Box(c, "Stock", "black", V(0.065f, 0.13f, 0.04f), V(0, -0.02f, rear - 0.31f), V(0, 0, 0));
            }
            else if (kind == "chassis")
            {
                Box(c, "Stock", "graphite", V(0.055f, 0.09f, 0.24f), V(0, 0.01f, rear - 0.12f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Stock", "black", V(0.06f, 0.04f, 0.12f), V(0, 0.06f, rear - 0.10f), V(0, 0, 0));
                Box(c, "Stock", "black", V(0.06f, 0.12f, 0.04f), V(0, -0.01f, rear - 0.26f), V(0, 0, 0));
            }
            else // fixed
            {
                Box(c, "Stock", body, V(0.055f, 0.115f, 0.26f), V(0, -0.015f, rear - 0.13f), V(0, 0, 0));
                Box(c, "Stock", "black", V(0.06f, 0.125f, 0.035f), V(0, -0.015f, rear - 0.27f), V(0, 0, 0));
            }
        }

        private static void SightDetail(BuildCtx c, GunModelSpec m, string dark, string steel)
        {
            string kind = m.Sight;
            if (kind == "iron")
            {
                Box(c, "Sight", dark, V(0.012f, 0.035f, 0.012f), V(-0.018f, 0.075f, -0.13f), V(0, 0, 0));
                Box(c, "Sight", dark, V(0.012f, 0.035f, 0.012f), V(0.018f, 0.075f, -0.13f), V(0, 0, 0));
                Box(c, "Sight", dark, V(0.05f, 0.012f, 0.02f), V(0, 0.06f, -0.13f), V(0, 0, 0));
                Box(c, "Sight", dark, V(0.01f, 0.03f, 0.01f), V(0, 0.075f, 0.16f), V(0, 0, 0));
            }
            else if (kind == "reddot")
            {
                Box(c, "Sight", dark, V(0.05f, 0.055f, 0.09f), V(0, 0.085f, -0.05f), V(0, 0, 0));
                Cyl(c, "Sight", "glass", 0.02f, 0.012f, 10, V(0, 0.085f, -0.095f), V(0, 0, -1));
                if (c.detail)
                    Box(c, "Sight", dark, V(0.03f, 0.03f, 0.02f), V(0, 0.06f, -0.05f), V(0, 0, 0));
            }
            else if (kind == "holo")
            {
                Box(c, "Sight", dark, V(0.06f, 0.07f, 0.11f), V(0, 0.09f, -0.05f), V(0, 0, 0));
                Box(c, "Sight", "glass", V(0.045f, 0.045f, 0.005f), V(0, 0.09f, -0.108f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Sight", dark, V(0.03f, 0.035f, 0.02f), V(0, 0.06f, -0.05f), V(0, 0, 0));
            }
            else if (kind == "scope" || kind == "scopelong")
            {
                float sl = kind == "scopelong" ? 0.30f : 0.22f;
                Cyl(c, "Sight", dark, 0.032f, sl, 12, V(0, 0.095f, -0.03f), V(0, 0, 1));
                Cyl(c, "Sight", dark, 0.036f, 0.05f, 12, V(0, 0.095f, -0.03f - sl * 0.5f), V(0, 0, 1));
                Cyl(c, "Sight", "glass", 0.028f, 0.006f, 12, V(0, 0.095f, -0.03f - sl * 0.5f - 0.028f), V(0, 0, 1));
                if (c.detail)
                {
                    Box(c, "Sight", steel, V(0.025f, 0.035f, 0.03f), V(0, 0.068f, -0.10f), V(0, 0, 0));
                    Box(c, "Sight", steel, V(0.025f, 0.035f, 0.03f), V(0, 0.068f, 0.04f), V(0, 0, 0));
                    Cyl(c, "Sight", steel, 0.012f, 0.02f, 8, V(0.04f, 0.095f, -0.03f), V(1, 0, 0));
                }
            }
            else if (kind == "thermal")
            {
                Box(c, "Sight", dark, V(0.065f, 0.075f, 0.16f), V(0, 0.095f, -0.04f), V(0, 0, 0));
                Box(c, "Sight", "glass", V(0.05f, 0.05f, 0.01f), V(0, 0.095f, -0.125f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Sight", steel, V(0.03f, 0.04f, 0.03f), V(0, 0.062f, -0.04f), V(0, 0, 0));
            }
            else if (kind == "acog")
            {
                Box(c, "Sight", dark, V(0.045f, 0.06f, 0.14f), V(0, 0.09f, -0.04f), V(0, 0, 0));
                Cyl(c, "Sight", "glass", 0.026f, 0.02f, 10, V(0, 0.09f, -0.115f), V(0, 0, 1));
                if (c.detail)
                {
                    Box(c, "Sight", steel, V(0.012f, 0.02f, 0.06f), V(0, 0.125f, -0.04f), V(0, 0, 0));
                    Box(c, "Sight", steel, V(0.03f, 0.035f, 0.03f), V(0, 0.062f, -0.04f), V(0, 0, 0));
                }
            }
        }

        // ---------------- pistols (mirrored: Godot barrel -Z -> +Z) ----------------
        private static void BuildPistol(BuildCtx c, GunModelSpec m)
        {
            string body = BodyKey(m.Body);
            string dark = "dark";
            string steel = "steel";
            string gunmetal = "gunmetal";
            string style = m.Style;
            float sl = 0.20f;
            if (style == "machine") sl = 0.24f;
            // slide
            Box(c, "Body", gunmetal, V(0.052f, 0.062f, sl), V(0, 0.03f, -sl * 0.5f + 0.03f), V(0, 0, 0));
            // slide serrations
            if (c.detail)
                for (int i = 0; i < 3; i++)
                    Box(c, "Body", dark, V(0.056f, 0.02f, 0.012f), V(0, 0.03f, -i * 0.025f), V(0, 0, 0));
            // frame
            Box(c, "Body", body, V(0.046f, 0.035f, sl * 0.9f), V(0, -0.008f, -sl * 0.5f + 0.03f), V(0, 0, 0));
            // grip (angled)
            Box(c, "Grip", body, V(0.048f, 0.15f, 0.062f), V(0, -0.095f, 0.055f), V(0.28f, 0, 0));
            // trigger + guard
            if (c.detail)
            {
                Box(c, "Grip", steel, V(0.012f, 0.035f, 0.018f), V(0, -0.045f, -0.02f), V(0.2f, 0, 0));
                Box(c, "Grip", dark, V(0.05f, 0.01f, 0.09f), V(0, -0.068f, -0.015f), V(0, 0, 0));
            }
            // sights
            Box(c, "Sight", dark, V(0.01f, 0.022f, 0.01f), V(0, 0.07f, -sl + 0.02f), V(0, 0, 0));
            Box(c, "Sight", dark, V(0.03f, 0.02f, 0.012f), V(0, 0.068f, 0.01f), V(0, 0, 0));
            // muzzle device
            string mz = m.Muzzle;
            Vector3 tip = V(0, 0.03f, -sl + 0.03f);
            if (mz == "suppressor")
                Cyl(c, "Muzzle", dark, 0.028f, 0.16f, 10, tip + V(0, 0, -0.08f), V(0, 0, 1));
            else if (mz == "comp")
                Box(c, "Muzzle", gunmetal, V(0.055f, 0.05f, 0.05f), tip + V(0, 0, -0.025f), V(0, 0, 0));
            else if (mz == "brake")
                Box(c, "Muzzle", gunmetal, V(0.06f, 0.065f, 0.06f), tip + V(0, 0, -0.03f), V(0, 0, 0));
            if (style == "machine")
            {
                Cyl(c, "Stock", steel, 0.009f, 0.20f, 6, V(-0.02f, -0.02f, 0.14f), V(0, 0, -1));
                Cyl(c, "Stock", steel, 0.009f, 0.20f, 6, V(0.02f, -0.02f, 0.14f), V(0, 0, -1));
                Box(c, "Stock", "black", V(0.05f, 0.09f, 0.03f), V(0, -0.02f, 0.25f), V(0, 0, 0));
                Box(c, "Mag", body, V(0.045f, 0.20f, 0.06f), V(0, -0.13f, 0.055f), V(0.28f, 0, 0));
            }
            if (style == "heavy")
                Box(c, "Body", body, V(0.058f, 0.07f, sl), V(0, 0.03f, -sl * 0.5f + 0.03f), V(0, 0, 0));
            if (style == "revolver")
            {
                Box(c, "Body", body, V(0.045f, 0.07f, 0.16f), V(0, 0.01f, 0.02f), V(0, 0, 0));
                Cyl(c, "Body", steel, 0.035f, 0.07f, 12, V(0, 0.02f, -0.03f), V(0, 0, 1));
                if (c.detail)
                    for (int i = 0; i < 6; i++)
                    {
                        float a = (float)i * Mathf.PI * 2f / 6f;
                        Box(c, "Body", dark, V(0.012f, 0.012f, 0.072f),
                            V(Mathf.Cos(a) * 0.024f, 0.02f + Mathf.Sin(a) * 0.024f, -0.03f), V(0, 0, 0));
                    }
                Cyl(c, "Barrel", gunmetal, 0.016f, 0.16f, 8, V(0, 0.035f, -0.14f), V(0, 0, 1));
                if (c.detail)
                {
                    Box(c, "Barrel", dark, V(0.014f, 0.02f, 0.16f), V(0, 0.055f, -0.14f), V(0, 0, 0));
                    Box(c, "Body", steel, V(0.02f, 0.05f, 0.03f), V(0, 0.05f, 0.10f), V(-0.5f, 0, 0));
                }
                Box(c, "Grip", "wood", V(0.05f, 0.13f, 0.07f), V(0, -0.09f, 0.06f), V(0.25f, 0, 0));
            }
            if (style == "burst")
            {
                Box(c, "Mag", body, V(0.05f, 0.06f, 0.09f), V(0, -0.16f, 0.055f), V(0.28f, 0, 0));
                if (c.detail)
                    Box(c, "Body", steel, V(0.014f, 0.014f, 0.03f), V(0.032f, 0, 0.03f), V(0, 0, 0));
            }
            if (style == "shorty")
            {
                Cyl(c, "Barrel", gunmetal, 0.024f, 0.16f, 8, V(-0.02f, 0.03f, -0.10f), V(0, 0, 1));
                Cyl(c, "Barrel", gunmetal, 0.024f, 0.16f, 8, V(0.02f, 0.03f, -0.10f), V(0, 0, 1));
                Box(c, "Body", body, V(0.06f, 0.05f, 0.10f), V(0, 0, 0), V(0, 0, 0));
                Box(c, "Body", "wood", V(0.055f, 0.06f, 0.09f), V(0, -0.01f, -0.06f), V(0, 0, 0));
                Box(c, "Grip", "wood", V(0.05f, 0.12f, 0.06f), V(0, -0.09f, 0.05f), V(0.3f, 0, 0));
            }
            if (style == "crossbow")
            {
                Box(c, "Body", body, V(0.05f, 0.07f, 0.30f), V(0, 0, -0.05f), V(0, 0, 0));
                Box(c, "Body", dark, V(0.34f, 0.025f, 0.05f), V(0, 0.02f, -0.16f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Body", steel, V(0.30f, 0.006f, 0.006f), V(0, 0.02f, -0.13f), V(0, 0, 0));
                Cyl(c, "Barrel", "wood", 0.008f, 0.24f, 6, V(0, 0.045f, -0.12f), V(0, 0, 1));
                Box(c, "Sight", dark, V(0.04f, 0.05f, 0.10f), V(0, 0.085f, -0.02f), V(0, 0, 0));
                Box(c, "Grip", body, V(0.05f, 0.12f, 0.06f), V(0, -0.09f, 0.06f), V(0.3f, 0, 0));
            }
            if (style == "fullauto")
            {
                Box(c, "Mag", body, V(0.05f, 0.09f, 0.09f), V(0, -0.17f, 0.055f), V(0.28f, 0, 0));
                Box(c, "Grip", "black", V(0.035f, 0.06f, 0.04f), V(0, -0.06f, -0.10f), V(0, 0, 0));
            }
            if (style == "nailgun")
            {
                Box(c, "Body", "graphite", V(0.07f, 0.10f, 0.22f), V(0, 0.03f, -0.04f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Body", steel, V(0.03f, 0.03f, 0.24f), V(0, 0.095f, -0.04f), V(0, 0, 0));
                Cyl(c, "Muzzle", dark, 0.025f, 0.10f, 8, V(0, 0.03f, -0.20f), V(0, 0, 1));
                Box(c, "Grip", "black", V(0.05f, 0.13f, 0.07f), V(0, -0.09f, 0.05f), V(0.25f, 0, 0));
            }
        }

        // ---------------- melee (mirrored) ----------------
        private static void BuildMelee(BuildCtx c, GunModelSpec m)
        {
            string style = m.Style;
            string steel = "steel";
            string dark = "dark";
            if (style == "knife")
            {
                Box(c, "Grip", dark, V(0.035f, 0.045f, 0.13f), V(0, -0.02f, 0.10f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Body", steel, V(0.045f, 0.012f, 0.02f), V(0, -0.02f, 0.03f), V(0, 0, 0));
                Box(c, "Barrel", steel, V(0.028f, 0.012f, 0.24f), V(0, -0.02f, -0.10f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Barrel", steel, V(0.020f, 0.010f, 0.10f), V(0, -0.02f, -0.26f), V(0, 0, 0));
            }
            else if (style == "axe")
            {
                Box(c, "Grip", "wood", V(0.04f, 0.045f, 0.55f), V(0, -0.02f, -0.10f), V(0, 0, 0));
                Box(c, "Barrel", steel, V(0.03f, 0.16f, 0.22f), V(0, 0.03f, -0.36f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Barrel", dark, V(0.032f, 0.06f, 0.06f), V(0, 0.03f, -0.24f), V(0, 0, 0));
            }
            else // katana (default)
            {
                Box(c, "Grip", dark, V(0.032f, 0.04f, 0.28f), V(0, -0.02f, 0.16f), V(0, 0, 0));
                if (c.detail)
                    Cyl(c, "Body", "brass", 0.045f, 0.012f, 10, V(0, -0.02f, 0.015f), V(0, 0, 1));
                Box(c, "Barrel", steel, V(0.024f, 0.008f, 0.55f), V(0, -0.015f, -0.28f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Barrel", steel, V(0.018f, 0.007f, 0.18f), V(0, -0.012f, -0.62f), V(0, 0, 0));
            }
            if (style == "bat")
            {
                Cyl(c, "Barrel", "wood", 0.035f, 0.42f, 10, V(0, -0.02f, -0.18f), V(0, 0, 1));
                Cyl(c, "Grip", "wood", 0.016f, 0.20f, 8, V(0, -0.02f, 0.10f), V(0, 0, 1));
                if (c.detail)
                    Cyl(c, "Grip", "wood", 0.028f, 0.03f, 8, V(0, -0.02f, 0.21f), V(0, 0, 1));
            }
            if (style == "shovel")
            {
                Cyl(c, "Grip", "wood", 0.018f, 0.45f, 8, V(0, -0.02f, 0.05f), V(0, 0, 1));
                Box(c, "Barrel", steel, V(0.16f, 0.015f, 0.24f), V(0, -0.02f, -0.28f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Grip", dark, V(0.05f, 0.05f, 0.08f), V(0, -0.02f, 0.28f), V(0, 0, 0));
            }
            if (style == "machete")
            {
                Box(c, "Grip", dark, V(0.035f, 0.045f, 0.14f), V(0, -0.02f, 0.12f), V(0, 0, 0));
                Box(c, "Barrel", steel, V(0.075f, 0.012f, 0.42f), V(0, -0.015f, -0.16f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Barrel", steel, V(0.05f, 0.010f, 0.10f), V(0, -0.012f, -0.40f), V(0, 0, 0.2f));
            }
            if (style == "fists")
            {
                Box(c, "Body", dark, V(0.09f, 0.09f, 0.12f), V(-0.05f, -0.02f, -0.10f), V(0, 0, 0));
                Box(c, "Body", dark, V(0.09f, 0.09f, 0.12f), V(0.05f, -0.02f, -0.10f), V(0, 0, 0));
                if (c.detail)
                {
                    Box(c, "Body", steel, V(0.095f, 0.03f, 0.125f), V(-0.05f, 0.03f, -0.10f), V(0, 0, 0));
                    Box(c, "Body", steel, V(0.095f, 0.03f, 0.125f), V(0.05f, 0.03f, -0.10f), V(0, 0, 0));
                }
            }
            if (style == "sticks")
            {
                Cyl(c, "Barrel", "wood", 0.016f, 0.55f, 8, V(-0.04f, -0.02f, -0.15f), V(0, 0, 1));
                Cyl(c, "Barrel", "wood", 0.016f, 0.55f, 8, V(0.04f, -0.02f, -0.15f), V(0, 0, 1));
            }
            if (style == "sai")
            {
                float[] sxs = { -0.045f, 0.045f };
                foreach (float sx in sxs)
                {
                    Box(c, "Barrel", steel, V(0.014f, 0.014f, 0.22f), V(sx, -0.02f, -0.12f), V(0, 0, 0));
                    if (c.detail)
                    {
                        Box(c, "Barrel", steel, V(0.010f, 0.010f, 0.10f), V(sx - 0.025f, -0.02f, -0.06f), V(0, 0, 0));
                        Box(c, "Barrel", steel, V(0.010f, 0.010f, 0.10f), V(sx + 0.025f, -0.02f, -0.06f), V(0, 0, 0));
                    }
                    Box(c, "Grip", dark, V(0.03f, 0.035f, 0.10f), V(sx, -0.02f, 0.04f), V(0, 0, 0));
                }
            }
            if (style == "wrench")
            {
                Box(c, "Grip", steel, V(0.03f, 0.025f, 0.40f), V(0, -0.02f, 0.02f), V(0, 0, 0));
                Box(c, "Barrel", steel, V(0.09f, 0.03f, 0.10f), V(0, -0.02f, -0.22f), V(0, 0, 0));
                if (c.detail)
                {
                    Box(c, "Barrel", steel, V(0.035f, 0.032f, 0.05f), V(-0.028f, -0.02f, -0.27f), V(0, 0, 0));
                    Box(c, "Barrel", steel, V(0.035f, 0.032f, 0.05f), V(0.028f, -0.02f, -0.27f), V(0, 0, 0));
                }
            }
        }

        // ---------------- launchers (mirrored) ----------------
        private static void BuildLauncher(BuildCtx c, GunModelSpec m)
        {
            string style = m.Style;
            string body = BodyKey(m.Body);
            string dark = "dark";
            string steel = "steel";
            if (style == "rpg")
            {
                Cyl(c, "Body", body, 0.055f, 0.95f, 12, V(0, 0.03f, -0.10f), V(0, 0, 1));
                Frustum(c, "Muzzle", dark, 0.012f, 0.055f, 0.22f, 12, V(0, 0.03f, -0.68f), V(0, 0, 1));
                Cyl(c, "Muzzle", dark, 0.075f, 0.12f, 12, V(0, 0.03f, 0.42f), V(0, 0, 1));
                Box(c, "Grip", "wood", V(0.05f, 0.13f, 0.06f), V(0, -0.09f, -0.05f), V(0.3f, 0, 0));
                if (c.detail)
                    Box(c, "Grip", steel, V(0.012f, 0.04f, 0.02f), V(0, -0.06f, -0.10f), V(0, 0, 0));
                Box(c, "Sight", dark, V(0.01f, 0.05f, 0.01f), V(0, 0.10f, -0.30f), V(0, 0, 0));
                if (c.detail)
                    Box(c, "Sight", dark, V(0.03f, 0.03f, 0.01f), V(0, 0.115f, -0.30f), V(0, 0, 0));
            }
            else // glauncher: chunky revolver-style GL
            {
                Box(c, "Body", body, V(0.075f, 0.11f, 0.34f), V(0, 0, 0), V(0, 0, 0));
                Cyl(c, "Barrel", "gunmetal", 0.035f, 0.34f, 10, V(0, 0.02f, -0.32f), V(0, 0, 1));
                Cyl(c, "Body", dark, 0.075f, 0.14f, 12, V(0, -0.01f, -0.05f), V(0, 0, 1));
                Box(c, "Grip", "wood", V(0.05f, 0.12f, 0.06f), V(0, -0.10f, 0.10f), V(0.3f, 0, 0));
                Box(c, "Stock", body, V(0.055f, 0.11f, 0.22f), V(0, -0.01f, 0.28f), V(0, 0, 0));
                Box(c, "Sight", dark, V(0.012f, 0.04f, 0.012f), V(0, 0.075f, -0.44f), V(0, 0, 0));
            }
            if (style == "rpg7")
            {
                // NOVA RP-7 "Thunderhead": long tube + flared venturi + front-loaded warhead.
                Cyl(c, "Body", body, 0.055f, 1.05f, 12, V(0, 0.03f, -0.08f), V(0, 0, 1));
                Frustum(c, "Muzzle", dark, 0.055f, 0.09f, 0.18f, 12, V(0, 0.03f, 0.50f), V(0, 0, 1));
                Cyl(c, "Muzzle", dark, 0.065f, 0.12f, 12, V(0, 0.03f, -0.66f), V(0, 0, 1));
                Cyl(c, "Muzzle", body, 0.075f, 0.14f, 12, V(0, 0.03f, -0.78f), V(0, 0, 1));
                Frustum(c, "Muzzle", dark, 0.010f, 0.075f, 0.18f, 12, V(0, 0.03f, -0.94f), V(0, 0, 1));
                float[] fxs = { -0.10f, 0.10f };
                foreach (float fx in fxs)
                {
                    Box(c, "Muzzle", dark, V(0.006f, 0.10f, 0.14f), V(fx, 0.03f, -0.72f), V(0, 0, 0));
                    Box(c, "Muzzle", dark, V(0.10f, 0.006f, 0.14f), V(0, 0.03f + fx, -0.72f), V(0, 0, 0));
                }
                string wood = "wood";
                Box(c, "Body", wood, V(0.13f, 0.05f, 0.22f), V(0, 0.035f, -0.30f), V(0, 0, 0));
                Box(c, "Body", wood, V(0.13f, 0.05f, 0.20f), V(0, 0.035f, 0.18f), V(0, 0, 0));
                if (c.detail)
                {
                    Cyl(c, "Body", dark, 0.062f, 0.03f, 12, V(0, 0.03f, -0.14f), V(0, 0, 1));
                    Cyl(c, "Body", dark, 0.062f, 0.03f, 12, V(0, 0.03f, 0.32f), V(0, 0, 1));
                }
                Box(c, "Grip", wood, V(0.05f, 0.14f, 0.06f), V(0, -0.10f, 0.02f), V(0.3f, 0, 0));
                if (c.detail)
                    Box(c, "Grip", steel, V(0.012f, 0.045f, 0.02f), V(0, -0.055f, -0.03f), V(0, 0, 0));
                Box(c, "Sight", dark, V(0.012f, 0.075f, 0.012f), V(0, 0.115f, -0.44f), V(0, 0, 0));
                if (c.detail)
                {
                    Box(c, "Sight", dark, V(0.012f, 0.06f, 0.012f), V(-0.02f, 0.105f, 0.02f), V(0, 0, 0));
                    Box(c, "Sight", dark, V(0.012f, 0.06f, 0.012f), V(0.02f, 0.105f, 0.02f), V(0, 0, 0));
                    Box(c, "Sight", dark, V(0.052f, 0.012f, 0.012f), V(0, 0.135f, 0.02f), V(0, 0, 0));
                }
            }
            if (style == "stinger")
            {
                Cyl(c, "Body", body, 0.05f, 1.05f, 12, V(0, 0.03f, -0.10f), V(0, 0, 1));
                Cyl(c, "Muzzle", dark, 0.055f, 0.10f, 12, V(0, 0.03f, -0.62f), V(0, 0, 1));
                Box(c, "Grip", "black", V(0.05f, 0.14f, 0.07f), V(0, -0.09f, 0.05f), V(0.25f, 0, 0));
                Box(c, "Sight", dark, V(0.04f, 0.10f, 0.06f), V(0, 0.12f, -0.20f), V(0, 0, 0));
                if (c.detail)
                    Cyl(c, "Sight", "glass", 0.02f, 0.02f, 8, V(0, 0.12f, -0.24f), V(0, 0, 1));
                Cyl(c, "Muzzle", dark, 0.065f, 0.10f, 12, V(0, 0.03f, 0.45f), V(0, 0, 1));
            }
            if (style == "disc")
            {
                Box(c, "Body", "graphite", V(0.09f, 0.12f, 0.30f), V(0, 0, 0), V(0, 0, 0));
                Cyl(c, "Mag", dark, 0.09f, 0.05f, 14, V(0, 0.10f, 0.02f), V(0, 1, 0));
                Cyl(c, "Mag", "steel", 0.07f, 0.055f, 14, V(0, 0.10f, 0.02f), V(0, 1, 0));
                Box(c, "Barrel", dark, V(0.05f, 0.05f, 0.12f), V(0, 0.02f, -0.20f), V(0, 0, 0));
                Box(c, "Grip", "black", V(0.05f, 0.12f, 0.06f), V(0, -0.10f, 0.08f), V(0.3f, 0, 0));
                Box(c, "Body", "emit:0.2,0.9,1", V(0.095f, 0.015f, 0.02f), V(0, 0, 0.14f), V(0, 0, 0));
            }
        }
    }
}
