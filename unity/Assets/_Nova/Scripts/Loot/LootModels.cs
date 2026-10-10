using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Loot
{
    /// <summary>
    /// Real 3D ground-loot models built from MeshBuilder parts (no flat icons):
    /// medkit, armor plates, armor shard, caliber-colored ammo boxes, cash bundles,
    /// frag grenades, smoke canisters, scorestreak devices, attachment cases,
    /// fuel jerrycans, plus tier visuals (glow rings, rarity beams for Epic+).
    /// Ported from loot_models.gd. Materials are shared via a static cache.
    /// </summary>
    public static class LootModels
    {
        private static readonly Dictionary<string, Material> MatCache = new Dictionary<string, Material>();

        private static Material Mat(Color color, float emission = 0f, float metallic = 0f)
        {
            string key = string.Format("m_{0:F2}_{1:F2}_{2:F2}_e{3:F1}_m{4:F1}",
                color.r, color.g, color.b, emission, metallic);
            Material m;
            if (MatCache.TryGetValue(key, out m)) return m;
            Shader s = Shader.Find("Standard");
            m = new Material(s);
            m.color = color;
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Glossiness", 0.45f);
            if (emission > 0f)
            {
                m.EnableKeyword("_EMISSION");
                m.SetColor("_EmissionColor", color * emission);
            }
            MatCache[key] = m;
            return m;
        }

        private static Material UnlitMat(Color color)
        {
            string key = string.Format("u_{0:F2}_{1:F2}_{2:F2}", color.r, color.g, color.b);
            Material m;
            if (MatCache.TryGetValue(key, out m)) return m;
            Shader s = Shader.Find("Unlit/Color");
            if (s == null) s = Shader.Find("Standard");
            m = new Material(s);
            m.color = color;
            MatCache[key] = m;
            return m;
        }

        private static Material TransparentMat(Color color, float alpha)
        {
            string key = string.Format("t_{0:F2}_{1:F2}_{2:F2}_a{3:F2}", color.r, color.g, color.b, alpha);
            Material m;
            if (MatCache.TryGetValue(key, out m)) return m;
            m = new Material(Shader.Find("Standard"));
            m.SetFloat("_Mode", 3f);
            m.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
            m.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            m.SetInt("_ZWrite", 0);
            m.DisableKeyword("_ALPHATEST_ON");
            m.EnableKeyword("_ALPHABLEND_ON");
            m.renderQueue = 3000;
            Color c = color; c.a = alpha;
            m.color = c;
            MatCache[key] = m;
            return m;
        }

        // ---- mesh helpers ----

        private static GameObject PartObject(string name, List<MeshBuilder.Part> parts, Material mat)
        {
            return MeshBuilder.BuildObject(name, parts, mat);
        }

        private static void AddBox(GameObject parent, Vector3 size, Vector3 pos, Material mat, Vector3? euler = null)
        {
            Quaternion q = euler.HasValue ? Quaternion.Euler(euler.Value) : Quaternion.identity;
            var go = MeshBuilder.BuildObject("p",
                new List<MeshBuilder.Part> { MeshBuilder.Box(size, Matrix4x4.TRS(pos, q, Vector3.one)) }, mat);
            go.transform.SetParent(parent.transform, false);
        }

        private static void AddCylinder(GameObject parent, float radius, float height, int segs,
            Vector3 pos, Material mat)
        {
            var go = MeshBuilder.BuildObject("p",
                new List<MeshBuilder.Part> { MeshBuilder.Cylinder(radius, height, segs, Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one)) }, mat);
            go.transform.SetParent(parent.transform, false);
        }

        /// <summary>Sphere part (stacked latitude rings); MeshBuilder has no sphere.</summary>
        private static MeshBuilder.Part Sphere(float radius, int latSegs, int lonSegs, Matrix4x4 m)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var tris = new List<int>();
            for (int i = 0; i <= latSegs; i++)
            {
                float v = (float)i / latSegs;
                float theta = v * Mathf.PI;
                float sinT = Mathf.Sin(theta), cosT = Mathf.Cos(theta);
                for (int j = 0; j <= lonSegs; j++)
                {
                    float u = (float)j / lonSegs;
                    float phi = u * Mathf.PI * 2f;
                    Vector3 n = new Vector3(sinT * Mathf.Cos(phi), cosT, sinT * Mathf.Sin(phi));
                    verts.Add(m.MultiplyPoint3x4(n * radius));
                    normals.Add(m.MultiplyVector(n).normalized);
                }
            }
            for (int i = 0; i < latSegs; i++)
                for (int j = 0; j < lonSegs; j++)
                {
                    int a = i * (lonSegs + 1) + j;
                    int b = a + lonSegs + 1;
                    tris.Add(a); tris.Add(b); tris.Add(a + 1);
                    tris.Add(a + 1); tris.Add(b); tris.Add(b + 1);
                }
            return new MeshBuilder.Part
            {
                Verts = verts.ToArray(), Tris = tris.ToArray(), Normals = normals.ToArray(),
                Uv = new Vector2[verts.Count], Matrix = Matrix4x4.identity
            };
        }

        /// <summary>Torus part in the XZ plane.</summary>
        private static MeshBuilder.Part Torus(float ringR, float tubeR, int ringSegs, int tubeSegs, Matrix4x4 m)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var tris = new List<int>();
            for (int i = 0; i <= ringSegs; i++)
            {
                float u = (float)i / ringSegs * Mathf.PI * 2f;
                Vector3 center = new Vector3(Mathf.Cos(u) * ringR, 0f, Mathf.Sin(u) * ringR);
                for (int j = 0; j <= tubeSegs; j++)
                {
                    float v = (float)j / tubeSegs * Mathf.PI * 2f;
                    Vector3 n = new Vector3(Mathf.Cos(u) * Mathf.Cos(v), Mathf.Sin(v), Mathf.Sin(u) * Mathf.Cos(v));
                    verts.Add(m.MultiplyPoint3x4(center + n * tubeR));
                    normals.Add(m.MultiplyVector(n).normalized);
                }
            }
            for (int i = 0; i < ringSegs; i++)
                for (int j = 0; j < tubeSegs; j++)
                {
                    int a = i * (tubeSegs + 1) + j;
                    int b = a + tubeSegs + 1;
                    tris.Add(a); tris.Add(b); tris.Add(a + 1);
                    tris.Add(a + 1); tris.Add(b); tris.Add(b + 1);
                }
            return new MeshBuilder.Part
            {
                Verts = verts.ToArray(), Tris = tris.ToArray(), Normals = normals.ToArray(),
                Uv = new Vector2[verts.Count], Matrix = Matrix4x4.identity
            };
        }

        private static void AddTorus(GameObject parent, float ringR, float tubeR, Vector3 pos, Material mat)
        {
            var go = MeshBuilder.BuildObject("p",
                new List<MeshBuilder.Part> { Torus(ringR, tubeR, 24, 10, Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one)) }, mat);
            go.transform.SetParent(parent.transform, false);
        }

        // ---- loot models ----

        /// <summary>White medkit box with a red cross.</summary>
        public static GameObject Medkit()
        {
            var root = new GameObject("Medkit");
            AddBox(root, new Vector3(0.42f, 0.26f, 0.30f), Vector3.zero, Mat(new Color(0.92f, 0.93f, 0.95f), 0.25f));
            Material red = Mat(new Color(0.85f, 0.10f, 0.12f), 0.6f);
            AddBox(root, new Vector3(0.20f, 0.06f, 0.02f), new Vector3(0f, 0.02f, 0.16f), red);
            AddBox(root, new Vector3(0.06f, 0.20f, 0.02f), new Vector3(0f, 0.02f, 0.16f), red);
            AddBox(root, new Vector3(0.30f, 0.05f, 0.06f), new Vector3(0f, 0.16f, 0f), Mat(new Color(0.55f, 0.56f, 0.58f), 0f, 0.4f));
            return root;
        }

        /// <summary>Stack of two armor plates (blue-grey ceramic).</summary>
        public static GameObject ArmorPlates()
        {
            var root = new GameObject("ArmorPlates");
            Material pm = Mat(new Color(0.30f, 0.45f, 0.75f), 0.55f);
            AddBox(root, new Vector3(0.36f, 0.05f, 0.28f), Vector3.zero, pm);
            AddBox(root, new Vector3(0.36f, 0.05f, 0.28f), new Vector3(0.03f, 0.07f, 0.02f), pm,
                new Vector3(0f, 0.35f * Mathf.Rad2Deg, 0f));
            return root;
        }

        /// <summary>Single armor shard fragment (+1 plate worth of armor).</summary>
        public static GameObject ArmorShard()
        {
            var root = new GameObject("ArmorShard");
            AddBox(root, new Vector3(0.22f, 0.04f, 0.18f), Vector3.zero, Mat(new Color(0.35f, 0.55f, 0.9f), 0.9f),
                new Vector3(0f, 0.5f * Mathf.Rad2Deg, 0f));
            return root;
        }

        /// <summary>Ammo box colored by caliber, with bullet tips on top.</summary>
        public static GameObject AmmoBox(string caliber)
        {
            var root = new GameObject("AmmoBox");
            AddBox(root, new Vector3(0.40f, 0.22f, 0.28f), Vector3.zero, Mat(new Color(0.45f, 0.38f, 0.25f), 0.15f));
            Material tipm = Mat(LootTable.CaliberColor(caliber), 0.7f, 0.6f);
            for (int i = 0; i < 4; i++)
            {
                float x = -0.12f + 0.08f * i;
                var tip = MeshBuilder.BuildObject("tip",
                    new List<MeshBuilder.Part> { MeshBuilder.Cylinder(0.02f, 0.10f, 8, Matrix4x4.TRS(new Vector3(x, 0.16f, 0f), Quaternion.identity, Vector3.one)) }, tipm);
                tip.transform.SetParent(root.transform, false);
            }
            return root;
        }

        /// <summary>Cash bundle: banded green stack.</summary>
        public static GameObject CashBundle()
        {
            var root = new GameObject("CashBundle");
            AddBox(root, new Vector3(0.34f, 0.12f, 0.24f), Vector3.zero, Mat(new Color(0.15f, 0.55f, 0.25f), 0.5f));
            AddBox(root, new Vector3(0.36f, 0.035f, 0.26f), new Vector3(0f, 0.01f, 0f), Mat(new Color(0.85f, 0.80f, 0.60f), 0.2f));
            return root;
        }

        /// <summary>Frag grenade: dark sphere body + lever + pin ring.</summary>
        public static GameObject FragGrenade()
        {
            var root = new GameObject("FragGrenade");
            Material body = Mat(new Color(0.20f, 0.28f, 0.16f), 0.2f, 0.35f);
            var bm = MeshBuilder.BuildObject("body",
                new List<MeshBuilder.Part> { Sphere(0.09f, 10, 14, Matrix4x4.identity) }, body);
            bm.transform.SetParent(root.transform, false);
            bm.transform.localScale = new Vector3(1f, 1.15f, 1f);
            AddBox(root, new Vector3(0.10f, 0.03f, 0.03f), new Vector3(0f, 0.12f, 0f), Mat(new Color(0.5f, 0.5f, 0.52f), 0f, 0.7f));
            var ring = MeshBuilder.BuildObject("ring",
                new List<MeshBuilder.Part> { Torus(0.035f, 0.01f, 12, 6, Matrix4x4.TRS(new Vector3(0.07f, 0.13f, 0f), Quaternion.identity, Vector3.one)) },
                Mat(new Color(0.6f, 0.6f, 0.62f), 0f, 0.8f));
            ring.transform.SetParent(root.transform, false);
            return root;
        }

        /// <summary>Smoke canister: grey cylinder with a light band.</summary>
        public static GameObject SmokeCanister()
        {
            var root = new GameObject("SmokeCanister");
            AddCylinder(root, 0.07f, 0.20f, 12, Vector3.zero, Mat(new Color(0.55f, 0.57f, 0.60f), 0.15f, 0.5f));
            AddCylinder(root, 0.072f, 0.06f, 12, new Vector3(0f, 0.05f, 0f), Mat(new Color(0.75f, 0.75f, 0.78f), 0.7f));
            return root;
        }

        /// <summary>Scorestreak device: "uav" quad-rotor drone or "strike" designator.</summary>
        public static GameObject StreakDevice(string kind)
        {
            var root = new GameObject("StreakDevice");
            if (kind == "uav")
            {
                AddBox(root, new Vector3(0.22f, 0.06f, 0.22f), Vector3.zero, Mat(new Color(0.25f, 0.28f, 0.32f), 0.4f, 0.5f));
                Material rm = Mat(new Color(0.2f, 0.8f, 1.0f), 1.2f);
                foreach (float sx in new float[] { -1f, 1f })
                    foreach (float sz in new float[] { -1f, 1f })
                        AddCylinder(root, 0.09f, 0.015f, 10, new Vector3(0.14f * sx, 0.05f, 0.14f * sz), rm);
            }
            else
            {
                AddBox(root, new Vector3(0.26f, 0.10f, 0.18f), Vector3.zero, Mat(new Color(0.18f, 0.18f, 0.20f), 0.3f, 0.4f));
                AddBox(root, new Vector3(0.05f, 0.05f, 0.05f), new Vector3(0f, 0.08f, 0f), Mat(new Color(1f, 0.1f, 0.1f), 2f));
            }
            return root;
        }

        /// <summary>Attachment in a foam-lined case.</summary>
        public static GameObject AttachmentCase()
        {
            var root = new GameObject("AttachmentCase");
            AddBox(root, new Vector3(0.30f, 0.12f, 0.22f), Vector3.zero, Mat(new Color(0.16f, 0.17f, 0.20f), 0.2f, 0.3f));
            AddBox(root, new Vector3(0.24f, 0.04f, 0.16f), new Vector3(0f, 0.05f, 0f), Mat(new Color(0.30f, 0.55f, 0.85f), 0.9f));
            return root;
        }

        /// <summary>Red jerrycan (port of loot.gd's inline _fuel_can_model).</summary>
        public static GameObject FuelCan()
        {
            var root = new GameObject("FuelCan");
            AddBox(root, new Vector3(0.35f, 0.5f, 0.22f), Vector3.zero, Mat(new Color(0.75f, 0.12f, 0.08f), 0.3f));
            Material dark = Mat(new Color(0.15f, 0.15f, 0.16f));
            AddBox(root, new Vector3(0.30f, 0.06f, 0.06f), new Vector3(0f, 0.28f, 0f), dark);
            AddCylinder(root, 0.05f, 0.06f, 10, new Vector3(0.10f, 0.28f, 0f), dark);
            return root;
        }

        /// <summary>Tall translucent rarity beam pillar (Epic+), visible far away.</summary>
        public static GameObject RarityBeam(Rarity rarity)
        {
            var root = new GameObject("RarityBeam");
            Color c = LootTable.RarityColor(rarity);
            var go = MeshBuilder.BuildObject("beam",
                new List<MeshBuilder.Part> { MeshBuilder.Cylinder(0.45f, 26f, 12, Matrix4x4.identity) },
                TransparentMat(c, 0.35f));
            go.transform.SetParent(root.transform, false);
            go.transform.localPosition = new Vector3(0f, 13f, 0f);
            return root;
        }

        /// <summary>Flat tier glow ring on the ground.</summary>
        public static GameObject TierRing(Rarity rarity, float radius = 0.5f)
        {
            var root = new GameObject("TierRing");
            var go = MeshBuilder.BuildObject("ring",
                new List<MeshBuilder.Part> { Torus(radius - 0.04f, 0.04f, 24, 8, Matrix4x4.identity) },
                UnlitMat(LootTable.RarityColor(rarity)));
            go.transform.SetParent(root.transform, false);
            return root;
        }

        /// <summary>Pulse ring used by LootPing (shared builder to avoid dup code).</summary>
        public static Mesh TorusMesh(float ringR, float tubeR, int ringSegs = 24, int tubeSegs = 10)
        {
            return MeshBuilder.Combine(new List<MeshBuilder.Part>
                { Torus(ringR, tubeR, ringSegs, tubeSegs, Matrix4x4.identity) });
        }
    }
}
