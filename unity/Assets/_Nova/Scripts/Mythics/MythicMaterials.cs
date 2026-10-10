using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Per-theme shared material cache (3 materials per theme: armor / accent / glow),
    /// all driven by the single parameterized Nova/MythicSkin shader.
    /// Materials are SHARED across every gun using the theme — per-instance kill
    /// evolution goes through MaterialPropertyBlock (see SkinApplier.SetEvolve),
    /// so re-skinning never allocates materials at runtime.
    /// </summary>
    public static class MythicMaterials
    {
        public const string ShaderName = "Nova/MythicSkin";
        public const int Armor = 0;
        public const int Accent = 1;
        public const int Glow = 2;

        private static readonly Dictionary<string, Material[]> _cache = new Dictionary<string, Material[]>();
        private static readonly HashSet<Material> _all = new HashSet<Material>();

        /// <summary>True when the material is one of the shared mythic materials.</summary>
        public static bool IsMythicMaterial(Material m)
        {
            return m != null && _all.Contains(m);
        }

        /// <summary>Returns {armor, accent, glow} for a theme id, building on first use.</summary>
        public static Material[] ForTheme(string themeId)
        {
            Material[] mats;
            if (_cache.TryGetValue(themeId, out mats)) return mats;
            MythicTheme t = MythicData.ThemeById(themeId);
            if (t.Id == null) return null;
            Shader sh = Shader.Find(ShaderName);
            if (sh == null)
            {
                Debug.LogWarning("[Mythics] Shader not found: " + ShaderName +
                    ". Add it to Graphics > Always Included Shaders.");
                return null;
            }
            // Mirrors Godot theme_mats(): armor = full pattern, accent = softer
            // secondary, glow = bright secondary with flow pattern (crystals/rings).
            // Glow strengths pushed hard per visual-bible §6: mythics must SCREAM.
            mats = new Material[3];
            mats[Armor] = Make(sh, t, t.Primary, t.Secondary, 2.4f, 0.6f, null);
            mats[Accent] = Make(sh, t, t.Secondary, t.Secondary, 1.7f, 0.6f, null);
            mats[Glow] = Make(sh, t, t.Secondary, t.Secondary, 3.6f, 0.9f, (int)MythicPattern.Flow);
            _cache[themeId] = mats;
            for (int i = 0; i < 3; i++) _all.Add(mats[i]);
            return mats;
        }

        private static Material Make(Shader sh, MythicTheme t, Color primary, Color secondary,
            float glow, float animMul, int? patternOverride)
        {
            var m = new Material(sh);
            m.SetColor("_Primary", primary);
            m.SetColor("_Secondary", secondary);
            m.SetInt("_Pattern", patternOverride.HasValue ? patternOverride.Value : (int)t.Pattern);
            m.SetFloat("_Evolve", 0f);
            m.SetFloat("_GlowStrength", glow);
            m.SetFloat("_AnimSpeed", t.Pulse * animMul);
            return m;
        }

        /// <summary>Build every theme's materials up front (one-time, at boot).</summary>
        public static void Warm()
        {
            for (int i = 0; i < MythicData.Themes.Length; i++)
                ForTheme(MythicData.Themes[i].Id);
        }
    }
}
