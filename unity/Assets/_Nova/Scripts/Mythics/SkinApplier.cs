using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Applies a mythic skin to a gun GameObject built by Arsenal's GunFactory:
    /// recolors the named parts (Body/Barrel/Mag/Stock/Sight/Muzzle/Grip) with the
    /// theme's animated materials, attaches theme geometry accents
    /// (crystals/fins/muzzle ring/armor plates), and records the skin so the
    /// tracer hook and kill evolution can find it. skinIdx 0 = standard finish
    /// (no-op). Works on viewmodels and world models alike.
    /// </summary>
    public static class SkinApplier
    {
        public const string AccentHolderName = "MythicAccents";

        // Godot material classification (mythic_skins.gd _classify): body keys get
        // the armor material, accent keys get accent, glass/emissive get glow.
        // NOTE: classification is by child GameObject NAME ("Body_gunmetal"),
        // not by material instance — GunFactory assigns mr.material (a per-part
        // clone), so instance identity can't be trusted.
        private static readonly string[] PartNames = { "Body", "Barrel", "Mag", "Stock", "Sight", "Muzzle", "Grip" };
        private static readonly string[] ArmorKeys = { "gunmetal", "black", "carbon", "graphite", "dark" };
        private static readonly string[] AccentKeys = { "wood", "tan", "od", "steel", "brass", "bronze", "bluegrey", "grey", "white", "sand" };
        private const string GlowKey = "glass";

        private static readonly MaterialPropertyBlock _block = new MaterialPropertyBlock();
        private static Mesh _torusMesh;

        /// <summary>Extract the factory material key from a "PartName_matKey" child name.</summary>
        private static string MatKeyFor(string childName)
        {
            if (string.IsNullOrEmpty(childName)) return null;
            for (int i = 0; i < PartNames.Length; i++)
            {
                string p = PartNames[i];
                if (childName.Length > p.Length + 1 &&
                    childName[p.Length] == '_' &&
                    childName.StartsWith(p, System.StringComparison.Ordinal))
                    return childName.Substring(p.Length + 1);
            }
            return null;
        }

        private static int ClassOfKey(string key)
        {
            if (string.IsNullOrEmpty(key)) return -1;
            if (key.StartsWith("emit:", System.StringComparison.Ordinal)) return MythicMaterials.Glow; // emissive bits
            for (int i = 0; i < ArmorKeys.Length; i++)
                if (key == ArmorKeys[i]) return MythicMaterials.Armor;
            for (int i = 0; i < AccentKeys.Length; i++)
                if (key == AccentKeys[i]) return MythicMaterials.Accent;
            if (key == GlowKey) return MythicMaterials.Glow;
            return -1;
        }

        /// <summary>
        /// Apply skin to a GunFactory-built gun root. Re-applying a different skin
        /// first removes the old MythicAccents holder (idempotent re-skin).
        /// </summary>
        public static void ApplyToModel(GameObject root, string gunId, int skinIdx, int stage = 0)
        {
            if (root == null || skinIdx <= 0) return;
            string themeId = MythicData.SkinThemeId(gunId, skinIdx);
            if (string.IsNullOrEmpty(themeId)) return;
            Material[] mats = MythicMaterials.ForTheme(themeId);
            if (mats == null) return; // shader missing; MythicMaterials warned already
            Transform old = root.transform.Find(AccentHolderName);
            if (old != null) Object.Destroy(old.gameObject);
            RecolorRecursive(root.transform, mats);
            BuildThemeAccents(root, themeId, mats);
            SetEvolve(root, stage);
            MythicGunRig rig = root.GetComponent<MythicGunRig>();
            if (rig == null) rig = root.AddComponent<MythicGunRig>();
            rig.Setup(gunId, themeId);
            MythicHooks.RememberSkin(gunId, skinIdx);
        }

        private static void RecolorRecursive(Transform t, Material[] mats)
        {
            MeshRenderer mr = t.GetComponent<MeshRenderer>();
            if (mr != null)
            {
                int cls = ClassOfKey(MatKeyFor(t.name));
                if (cls >= 0) mr.sharedMaterial = mats[cls];
            }
            for (int i = 0; i < t.childCount; i++)
                RecolorRecursive(t.GetChild(i), mats);
        }

        /// <summary>
        /// Set the shader _Evolve uniform (0..1) per model instance via
        /// MaterialPropertyBlock, and scale the accent holder with the stage.
        /// Allocation-free: no lists, no LINQ.
        /// </summary>
        public static void SetEvolve(GameObject root, int stage)
        {
            if (root == null) return;
            float v = Mathf.Clamp01(stage / 3f);
            SetEvolveRecursive(root.transform, v);
            Transform holder = root.transform.Find(AccentHolderName);
            if (holder != null)
            {
                float s = 1.0f + 0.12f * stage; // accents grow bold: 1.0 -> 1.36
                holder.localScale = new Vector3(s, s, s);
            }
        }

        private static void SetEvolveRecursive(Transform t, float v)
        {
            MeshRenderer mr = t.GetComponent<MeshRenderer>();
            if (mr != null && MythicMaterials.IsMythicMaterial(mr.sharedMaterial))
            {
                mr.GetPropertyBlock(_block);
                _block.SetFloat("_Evolve", v);
                mr.SetPropertyBlock(_block);
            }
            for (int i = 0; i < t.childCount; i++)
                SetEvolveRecursive(t.GetChild(i), v);
        }

        // ---------------- theme accents ----------------
        // Guns point along +Z in the Unity port (Godot used -Z), origin at the
        // receiver. Accent positions mirror the Godot _build_theme_accents() layout.

        private static void BuildThemeAccents(GameObject root, string themeId, Material[] mats)
        {
            MythicTheme t = MythicData.ThemeById(themeId);
            GameObject holder = new GameObject(AccentHolderName);
            holder.transform.SetParent(root.transform, false);

            for (int i = 0; i < t.Crystals; i++)
            {
                // Oversized crystals: silhouette-changing, readable at distance.
                float s = 0.048f + 0.02f * (i % 2);
                float side = (i % 2 == 0) ? 1f : -1f;
                Vector3 pos = new Vector3(side * 0.055f, 0.035f + 0.012f * (i / 2), -0.02f + 0.09f * (i / 2));
                Quaternion rot = Quaternion.Euler(-0.3f * side * Mathf.Rad2Deg, 0f, 0.55f * side * Mathf.Rad2Deg);
                MeshBuilder.Part part = MeshBuilder.Box(new Vector3(s * 0.5f, s * 1.6f, s * 0.5f),
                    Matrix4x4.TRS(pos, rot, Vector3.one));
                AddAccent(holder, "Crystal" + i, part, mats[MythicMaterials.Glow]);
            }

            for (int i = 0; i < t.Fins; i++)
            {
                float side = (i % 2 == 0) ? 1f : -1f;
                Vector3 pos = new Vector3(side * 0.032f, 0.055f, 0.28f + 0.1f * (i / 2));
                Quaternion rot = Quaternion.Euler(0f, 0f, -0.45f * side * Mathf.Rad2Deg);
                MeshBuilder.Part part = MeshBuilder.Box(new Vector3(0.012f, 0.085f, 0.17f),
                    Matrix4x4.TRS(pos, rot, Vector3.one));
                AddAccent(holder, "Fin" + i, part, mats[MythicMaterials.Accent]);
            }

            if (t.Ring > 0)
            {
                GameObject ring = new GameObject("MuzzleRing");
                ring.transform.SetParent(holder.transform, false);
                MeshFilter mf = ring.AddComponent<MeshFilter>();
                mf.mesh = TorusMesh();
                MeshRenderer mr = ring.AddComponent<MeshRenderer>();
                mr.sharedMaterial = mats[MythicMaterials.Glow];
                Transform mp = root.transform.Find("MuzzlePoint");
                ring.transform.localPosition = mp != null ? mp.localPosition : new Vector3(0f, 0.02f, 0.62f);
            }

            for (int i = 0; i < t.Plates; i++)
            {
                Vector3 pos = new Vector3(0f, 0.062f, -0.1f + 0.12f * i);
                MeshBuilder.Part part = MeshBuilder.Box(new Vector3(0.11f, 0.018f, 0.13f),
                    Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one));
                AddAccent(holder, "Plate" + i, part, mats[MythicMaterials.Accent]);
            }
        }

        private static void AddAccent(GameObject holder, string name, MeshBuilder.Part part, Material mat)
        {
            GameObject go = new GameObject(name);
            go.transform.SetParent(holder.transform, false);
            MeshFilter mf = go.AddComponent<MeshFilter>();
            var parts = new List<MeshBuilder.Part>(1) { part };
            mf.mesh = MeshBuilder.Combine(parts);
            MeshRenderer mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat; // shared theme material: stays batchable, MPB-driven
        }

        /// <summary>Torus around the barrel axis (+Z), cached. inner 0.038 / outer 0.062.</summary>
        private static Mesh TorusMesh()
        {
            if (_torusMesh != null) return _torusMesh;
            const float ringR = 0.05f;
            const float tubeR = 0.012f;
            const int radial = 12;
            const int tube = 8;
            var verts = new List<Vector3>((radial + 1) * (tube + 1));
            var normals = new List<Vector3>((radial + 1) * (tube + 1));
            var uvs = new List<Vector2>((radial + 1) * (tube + 1));
            var tris = new List<int>(radial * tube * 6);
            for (int i = 0; i <= radial; i++)
            {
                float a = i / (float)radial * Mathf.PI * 2f;
                Vector3 center = new Vector3(Mathf.Cos(a) * ringR, Mathf.Sin(a) * ringR, 0f);
                Vector3 radialDir = new Vector3(Mathf.Cos(a), Mathf.Sin(a), 0f);
                for (int j = 0; j <= tube; j++)
                {
                    float b = j / (float)tube * Mathf.PI * 2f;
                    Vector3 off = radialDir * (Mathf.Cos(b) * tubeR) + new Vector3(0f, 0f, Mathf.Sin(b) * tubeR);
                    verts.Add(center + off);
                    normals.Add(off.normalized);
                    uvs.Add(new Vector2(i / (float)radial, j / (float)tube));
                    if (i < radial && j < tube)
                    {
                        int r0 = i * (tube + 1) + j;
                        int r1 = (i + 1) * (tube + 1) + j;
                        tris.Add(r0); tris.Add(r1); tris.Add(r0 + 1);
                        tris.Add(r0 + 1); tris.Add(r1); tris.Add(r1 + 1);
                    }
                }
            }
            _torusMesh = new Mesh();
            _torusMesh.SetVertices(verts);
            _torusMesh.SetNormals(normals);
            _torusMesh.SetUVs(0, uvs);
            _torusMesh.SetTriangles(tris, 0);
            _torusMesh.RecalculateBounds();
            return _torusMesh;
        }
    }
}
