using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;
using NovaMobile.Economy;
using NovaMobile.Vehicles;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Mythic VEHICLE skins — visual-bible §6 authority (overrides the Godot spec
    /// on visuals): at minimum the buggy (ATV) and the pickup get the flagship
    /// hot-pink/magenta + gold "Pink Reign" treatment with glowing accents —
    /// animated mythic paint, gold trim, hood spikes, rear spoiler, underglow.
    /// Works on any VehicleType built by VehicleFactory. Call ApplyTo AFTER
    /// VehicleFactory.Build (it recolors the shared paint materials and adds a
    /// "MythicVehicleAccents" holder under model.Body so accents bank with it).
    /// stage: visual intensity (default 3 = full mythic).
    /// </summary>
    public static class MythicVehicle
    {
        public const string DefaultThemeId = "pinkreign";
        public const string AccentHolderName = "MythicVehicleAccents";

        // Vehicle material classification (VehicleMats keys). Paint bodies get the
        // animated armor material; dark metals get accent; emissive lights get the
        // bright glow. Tires, glass, wood, seats etc. are left untouched.
        private static readonly string[] ArmorKeys = {
            "paint_sedan", "paint_bike", "paint_truck", "paint_tank", "paint_heli",
            "paint_boat", "paint_hover", "paint_b2", "paint_suv", "paint_pickup",
            "paint_sport", "paint_atv", "paint_armored", "paint_jeep",
        };
        private static readonly string[] AccentKeys = {
            "metal_dark", "steel", "chrome", "deck_grey", "bed_liner", "track", "accent_orange",
        };
        private static readonly string[] GlowKeys = {
            "light_head", "light_tail", "glow_cyan", "glow_orange",
            "nav_red", "nav_green", "nav_white",
        };

        // NOTE: classification is by child GameObject NAME ("Body_paint_atv"),
        // not by material instance — VehicleSkins.Apply swaps paint materials for
        // per-skin instances after Build, so instance identity can't be trusted.
        // Longest-suffix match wins ("bed_liner" beats a naive last-'_' split).
        private static int ClassOfName(string childName)
        {
            if (string.IsNullOrEmpty(childName)) return -1;
            int best = -1;
            int bestLen = -1;
            for (int i = 0; i < ArmorKeys.Length; i++)
            {
                string k = ArmorKeys[i];
                if (childName.Length > k.Length + 1 &&
                    childName[childName.Length - k.Length - 1] == '_' &&
                    childName.EndsWith(k, System.StringComparison.Ordinal) && k.Length > bestLen)
                { best = MythicMaterials.Armor; bestLen = k.Length; }
            }
            for (int i = 0; i < AccentKeys.Length; i++)
            {
                string k = AccentKeys[i];
                if (childName.Length > k.Length + 1 &&
                    childName[childName.Length - k.Length - 1] == '_' &&
                    childName.EndsWith(k, System.StringComparison.Ordinal) && k.Length > bestLen)
                { best = MythicMaterials.Accent; bestLen = k.Length; }
            }
            for (int i = 0; i < GlowKeys.Length; i++)
            {
                string k = GlowKeys[i];
                if (childName.Length > k.Length + 1 &&
                    childName[childName.Length - k.Length - 1] == '_' &&
                    childName.EndsWith(k, System.StringComparison.Ordinal) && k.Length > bestLen)
                { best = MythicMaterials.Glow; bestLen = k.Length; }
            }
            return best;
        }

        /// <summary>Skin id contract for vehicle mythics (NpWallet ownership).</summary>
        public static string SkinIdFor(VehicleType type)
        {
            return "vehicle_" + type.ToString().ToLowerInvariant() + "_mythic";
        }

        public static bool OwnsSkin(VehicleType type)
        {
            return NpWallet.OwnsSkin(SkinIdFor(type));
        }

        public static void UnlockSkin(VehicleType type)
        {
            NpWallet.UnlockSkin(SkinIdFor(type));
        }

        /// <summary>
        /// Apply a mythic vehicle skin. Idempotent: re-applying removes the old
        /// accent holder first. Never touches wheel colliders or glass.
        /// </summary>
        public static void ApplyTo(VehicleModel model, string themeId = DefaultThemeId, int stage = 3)
        {
            if (model == null || model.Body == null) return;
            MythicTheme t = MythicData.ThemeById(themeId);
            if (t.Id == null) return;
            Material[] mats = MythicMaterials.ForTheme(themeId);
            if (mats == null) return; // shader missing; MythicMaterials warned already
            Transform body = model.Body;
            Transform old = body.Find(AccentHolderName);
            if (old != null) Object.Destroy(old.gameObject);
            RecolorRecursive(body, mats);
            BuildAccents(model, t, mats);
            SkinApplier.SetEvolve(body.gameObject, stage);
            Transform holder = body.Find(AccentHolderName);
            if (holder != null)
            {
                float s = 1.0f + 0.12f * stage;
                holder.localScale = new Vector3(s, s, s);
            }
        }

        private static void RecolorRecursive(Transform t, Material[] mats)
        {
            MeshRenderer mr = t.GetComponent<MeshRenderer>();
            if (mr != null)
            {
                int cls = ClassOfName(t.name);
                if (cls >= 0) mr.sharedMaterial = mats[cls];
            }
            for (int i = 0; i < t.childCount; i++)
                RecolorRecursive(t.GetChild(i), mats);
        }

        // Vehicle forward = -Z (headlights sit at -Z in VehicleFactory builders).
        // Accents: underglow, rear spoiler fins, hood spikes, flank trim rails —
        // silhouette-changing and loud at distance.
        private static void BuildAccents(VehicleModel model, MythicTheme t, Material[] mats)
        {
            Transform body = model.Body;
            float L = Mathf.Max(1f, model.Length);
            float W = Mathf.Max(0.8f, model.Width);
            float H = Mathf.Max(0.8f, model.Height);
            GameObject holder = new GameObject(AccentHolderName);
            holder.transform.SetParent(body, false);
            Material glow = mats[MythicMaterials.Glow];
            Material accent = mats[MythicMaterials.Accent];

            // Underglow: wide glowing plane under the chassis — the 50m read.
            AddBox(holder, "Underglow", new Vector3(W * 0.85f, 0.03f, L * 0.8f),
                new Vector3(0f, 0.10f, 0f), Quaternion.identity, glow);

            // Rear spoiler fins: 3 swept fins across the rear top (silhouette change).
            for (int i = -1; i <= 1; i++)
            {
                Vector3 pos = new Vector3(i * W * 0.28f, H + 0.16f, L * 0.36f);
                Quaternion rot = Quaternion.Euler(-0.5f * Mathf.Rad2Deg, 0f, 0f);
                AddBox(holder, "Spoiler" + i, new Vector3(0.07f, 0.42f, 0.55f), pos, rot, accent);
            }

            // Hood spikes: glowing spikes down the front hood (front = -Z).
            for (int i = 0; i < 3; i++)
            {
                Vector3 pos = new Vector3(0f, H * 0.62f + 0.06f * i, -L * 0.30f + i * L * 0.08f);
                AddBox(holder, "HoodSpike" + i, new Vector3(0.05f, 0.16f + 0.05f * i, 0.05f),
                    pos, Quaternion.identity, glow);
            }

            // Gold trim rails along both flanks.
            for (int s = -1; s <= 1; s += 2)
            {
                Vector3 pos = new Vector3(s * (W / 2f), H * 0.5f, 0f);
                AddBox(holder, "Trim" + s, new Vector3(0.035f, 0.06f, L * 0.78f),
                    pos, Quaternion.identity, glow);
            }
        }

        private static void AddBox(GameObject holder, string name, Vector3 size,
            Vector3 pos, Quaternion rot, Material mat)
        {
            GameObject go = new GameObject(name);
            go.transform.SetParent(holder.transform, false);
            MeshFilter mf = go.AddComponent<MeshFilter>();
            var parts = new List<MeshBuilder.Part>(1) {
                MeshBuilder.Box(size, Matrix4x4.TRS(pos, rot, Vector3.one))
            };
            mf.mesh = MeshBuilder.Combine(parts);
            MeshRenderer mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
        }
    }
}
