using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Arsenal;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Mythic skin theme catalog, ported from Godot scripts/mythic_skins.gd.
    /// 15 themes (14 from the Godot spec + the flagship "Pink Reign" added under
    /// visual-bible §6 authority), 3 deterministic skins per gun x 137 guns.
    /// Skin id contract: gunId + "_skin_" + idx (idx 1..3; 0 = standard finish).
    /// Kill evolution: Dormant -> AWAKENED (5) -> ASCENDANT (10) -> MYTHIC (20).
    /// </summary>
    public enum MythicPattern
    {
        Cracks = 0,   // molten cracks (Dragonfire, Bloodmoon, Phoenix, Crimson Oath)
        Frost = 1,    // creeping frost (Glacier)
        Nebula = 2,   // swirling void (Necrovoid, Onyx Reign)
        Circuit = 3,  // circuitry traces (Mecha)
        Flow = 4,     // energy flow bands (Solarflare, Venom, Aurora, Sandstorm, Abyssal, Stormcaller)
    }

    public struct MythicTheme
    {
        public string Id;
        public string Name;
        public MythicPattern Pattern;
        public Color Primary;
        public Color Secondary;
        public Color Tracer;
        public Color Flash;
        public float Pulse;
        public int Crystals;
        public int Fins;
        public int Ring;
        public int Plates;
    }

    public struct MythicSkin
    {
        public string ThemeId;
        public string DisplayName;
    }

    public static class MythicData
    {
        public const int SkinsPerGun = 3;

        /// <summary>Kill thresholds per evolution stage; index = stage (0 dormant).</summary>
        public static readonly int[] StageKills = { 0, 5, 10, 20 };

        /// <summary>Stage display names; stage 0 (dormant) shows nothing.</summary>
        public static readonly string[] StageNames = { "", "AWAKENED", "ASCENDANT", "MYTHIC" };

        public static readonly MythicTheme[] Themes = {
            new MythicTheme { Id = "dragonfire", Name = "Dragonfire", Pattern = MythicPattern.Cracks,
                Primary = new Color(1.0f, 0.32f, 0.05f), Secondary = new Color(1.0f, 0.72f, 0.15f),
                Tracer = new Color(1.0f, 0.50f, 0.10f), Flash = new Color(1.0f, 0.45f, 0.10f),
                Pulse = 4.2f, Crystals = 0, Fins = 3, Ring = 1, Plates = 0 },
            new MythicTheme { Id = "glacier", Name = "Glacier", Pattern = MythicPattern.Frost,
                Primary = new Color(0.45f, 0.80f, 1.0f), Secondary = new Color(0.90f, 0.97f, 1.0f),
                Tracer = new Color(0.60f, 0.85f, 1.0f), Flash = new Color(0.70f, 0.90f, 1.0f),
                Pulse = 2.2f, Crystals = 5, Fins = 0, Ring = 1, Plates = 0 },
            new MythicTheme { Id = "necrovoid", Name = "Necrovoid", Pattern = MythicPattern.Nebula,
                Primary = new Color(0.60f, 0.15f, 0.90f), Secondary = new Color(0.85f, 0.40f, 1.0f),
                Tracer = new Color(0.70f, 0.30f, 1.0f), Flash = new Color(0.65f, 0.25f, 0.95f),
                Pulse = 3.0f, Crystals = 3, Fins = 0, Ring = 0, Plates = 0 },
            new MythicTheme { Id = "solarflare", Name = "Solarflare", Pattern = MythicPattern.Flow,
                Primary = new Color(1.0f, 0.85f, 0.20f), Secondary = new Color(1.0f, 1.0f, 0.85f),
                Tracer = new Color(1.0f, 0.90f, 0.40f), Flash = new Color(1.0f, 0.90f, 0.50f),
                Pulse = 5.0f, Crystals = 0, Fins = 2, Ring = 1, Plates = 0 },
            new MythicTheme { Id = "venom", Name = "Venom", Pattern = MythicPattern.Flow,
                Primary = new Color(0.35f, 1.0f, 0.25f), Secondary = new Color(0.75f, 1.0f, 0.40f),
                Tracer = new Color(0.50f, 1.0f, 0.30f), Flash = new Color(0.50f, 1.0f, 0.35f),
                Pulse = 3.6f, Crystals = 2, Fins = 2, Ring = 0, Plates = 0 },
            new MythicTheme { Id = "bloodmoon", Name = "Bloodmoon", Pattern = MythicPattern.Cracks,
                Primary = new Color(0.90f, 0.08f, 0.12f), Secondary = new Color(1.0f, 0.35f, 0.30f),
                Tracer = new Color(1.0f, 0.20f, 0.20f), Flash = new Color(1.0f, 0.25f, 0.25f),
                Pulse = 2.6f, Crystals = 0, Fins = 3, Ring = 1, Plates = 0 },
            new MythicTheme { Id = "mecha", Name = "Mecha", Pattern = MythicPattern.Circuit,
                Primary = new Color(0.20f, 0.90f, 1.0f), Secondary = new Color(0.85f, 0.95f, 1.0f),
                Tracer = new Color(0.30f, 0.90f, 1.0f), Flash = new Color(0.40f, 0.90f, 1.0f),
                Pulse = 6.0f, Crystals = 0, Fins = 0, Ring = 1, Plates = 3 },
            new MythicTheme { Id = "aurora", Name = "Aurora", Pattern = MythicPattern.Flow,
                Primary = new Color(0.25f, 1.0f, 0.75f), Secondary = new Color(1.0f, 0.40f, 0.85f),
                Tracer = new Color(0.40f, 1.0f, 0.80f), Flash = new Color(0.50f, 1.0f, 0.85f),
                Pulse = 2.0f, Crystals = 3, Fins = 0, Ring = 1, Plates = 0 },
            new MythicTheme { Id = "sandstorm", Name = "Sandstorm", Pattern = MythicPattern.Flow,
                Primary = new Color(1.0f, 0.70f, 0.25f), Secondary = new Color(0.90f, 0.80f, 0.55f),
                Tracer = new Color(1.0f, 0.80f, 0.40f), Flash = new Color(1.0f, 0.75f, 0.35f),
                Pulse = 3.2f, Crystals = 0, Fins = 2, Ring = 0, Plates = 2 },
            new MythicTheme { Id = "abyssal", Name = "Abyssal", Pattern = MythicPattern.Flow,
                Primary = new Color(0.10f, 0.40f, 1.0f), Secondary = new Color(0.35f, 0.85f, 1.0f),
                Tracer = new Color(0.25f, 0.55f, 1.0f), Flash = new Color(0.30f, 0.60f, 1.0f),
                Pulse = 2.8f, Crystals = 4, Fins = 0, Ring = 1, Plates = 0 },
            new MythicTheme { Id = "phoenix", Name = "Phoenix", Pattern = MythicPattern.Cracks,
                Primary = new Color(1.0f, 0.55f, 0.10f), Secondary = new Color(1.0f, 0.90f, 0.60f),
                Tracer = new Color(1.0f, 0.65f, 0.20f), Flash = new Color(1.0f, 0.60f, 0.25f),
                Pulse = 4.6f, Crystals = 0, Fins = 4, Ring = 1, Plates = 0 },
            new MythicTheme { Id = "stormcaller", Name = "Stormcaller", Pattern = MythicPattern.Flow,
                Primary = new Color(0.50f, 0.70f, 1.0f), Secondary = new Color(0.95f, 0.95f, 1.0f),
                Tracer = new Color(0.60f, 0.75f, 1.0f), Flash = new Color(0.65f, 0.80f, 1.0f),
                Pulse = 7.0f, Crystals = 2, Fins = 0, Ring = 1, Plates = 2 },
            new MythicTheme { Id = "crimson", Name = "Crimson Oath", Pattern = MythicPattern.Cracks,
                Primary = new Color(0.75f, 0.05f, 0.20f), Secondary = new Color(1.0f, 0.50f, 0.55f),
                Tracer = new Color(0.90f, 0.15f, 0.30f), Flash = new Color(0.95f, 0.20f, 0.30f),
                Pulse = 3.8f, Crystals = 0, Fins = 3, Ring = 0, Plates = 0 },
            new MythicTheme { Id = "onyx", Name = "Onyx Reign", Pattern = MythicPattern.Nebula,
                Primary = new Color(0.50f, 0.25f, 0.90f), Secondary = new Color(0.75f, 0.60f, 1.0f),
                Tracer = new Color(0.60f, 0.40f, 1.0f), Flash = new Color(0.55f, 0.35f, 0.95f),
                Pulse = 2.4f, Crystals = 3, Fins = 0, Ring = 1, Plates = 0 },
            // Flagship revenue skin (visual-bible §6 authority): vivid hot pink /
            // magenta with gold accents — the CODM-observed mythic bar.
            new MythicTheme { Id = "pinkreign", Name = "Pink Reign", Pattern = MythicPattern.Flow,
                Primary = new Color(1.0f, 0.08f, 0.45f), Secondary = new Color(1.0f, 0.80f, 0.20f),
                Tracer = new Color(1.0f, 0.40f, 0.70f), Flash = new Color(1.0f, 0.70f, 0.30f),
                Pulse = 6.5f, Crystals = 3, Fins = 3, Ring = 1, Plates = 2 },
        };

        private static readonly Dictionary<string, MythicSkin[]> _skinsCache = new Dictionary<string, MythicSkin[]>();

        public static MythicTheme ThemeById(string themeId)
        {
            if (string.IsNullOrEmpty(themeId)) return default(MythicTheme);
            for (int i = 0; i < Themes.Length; i++)
                if (Themes[i].Id == themeId) return Themes[i];
            return default(MythicTheme);
        }

        // Stable FNV-1a hash: .NET string.GetHashCode is not deterministic across runs.
        private static int StableHash(string s)
        {
            unchecked
            {
                uint h = 2166136261u;
                for (int i = 0; i < s.Length; i++)
                {
                    h ^= s[i];
                    h *= 16777619u;
                }
                return (int)(h & 0x7fffffff);
            }
        }

        /// <summary>
        /// Deterministic 3 distinct themes per gun. Same approach as the Godot
        /// version (hash-seeded start, coprime step so all themes are visited;
        /// step 7 for 15 themes). Cached per gun id (no per-call allocation after first).
        /// </summary>
        public static MythicSkin[] SkinsFor(string gunId)
        {
            if (string.IsNullOrEmpty(gunId) || !GunData.Has(gunId))
                return new MythicSkin[0];
            MythicSkin[] cached;
            if (_skinsCache.TryGetValue(gunId, out cached)) return cached;
            string gunName = GunData.Get(gunId).Name;
            int n = Themes.Length;
            var picks = new List<int>(SkinsPerGun);
            int idx = StableHash(gunId) % n;
            int guard = 0;
            while (picks.Count < SkinsPerGun && guard < 64)
            {
                guard++;
                if (!picks.Contains(idx)) picks.Add(idx);
                idx = (idx + 7) % n; // 7 is coprime with 15: visits every theme
            }
            var skins = new MythicSkin[picks.Count];
            for (int i = 0; i < picks.Count; i++)
            {
                MythicTheme t = Themes[picks[i]];
                skins[i] = new MythicSkin
                {
                    ThemeId = t.Id,
                    DisplayName = gunName + " \"" + t.Name + "\"",
                };
            }
            _skinsCache[gunId] = skins;
            return skins;
        }

        /// <summary>Skin id contract shared with NpWallet ownership checks.</summary>
        public static string SkinId(string gunId, int skinIdx)
        {
            return gunId + "_skin_" + skinIdx;
        }

        public static int SkinCount(string gunId)
        {
            return SkinsFor(gunId).Length;
        }

        /// <summary>1-based skin index (0 = standard finish, returns "").</summary>
        public static string SkinDisplayName(string gunId, int skinIdx)
        {
            if (skinIdx <= 0) return "";
            MythicSkin[] skins = SkinsFor(gunId);
            return skinIdx - 1 < skins.Length ? skins[skinIdx - 1].DisplayName : "";
        }

        /// <summary>1-based skin index (0 = standard finish, returns "").</summary>
        public static string SkinThemeId(string gunId, int skinIdx)
        {
            if (skinIdx <= 0) return "";
            MythicSkin[] skins = SkinsFor(gunId);
            return skinIdx - 1 < skins.Length ? skins[skinIdx - 1].ThemeId : "";
        }

        public static Color SkinPrimaryColor(string gunId, int skinIdx)
        {
            MythicTheme t = ThemeById(SkinThemeId(gunId, skinIdx));
            return t.Id != null ? t.Primary : new Color(0.85f, 0.50f, 1.0f); // fallback purple
        }

        public static Color TracerColor(string gunId, int skinIdx)
        {
            MythicTheme t = ThemeById(SkinThemeId(gunId, skinIdx));
            return t.Id != null ? t.Tracer : new Color(1.0f, 0.85f, 0.50f); // default warm tracer
        }

        public static Color FlashColor(string gunId, int skinIdx)
        {
            MythicTheme t = ThemeById(SkinThemeId(gunId, skinIdx));
            return t.Id != null ? t.Flash : new Color(1.0f, 0.75f, 0.40f);
        }

        /// <summary>Evolution stage 0..3 (Dormant/AWAKENED/ASCENDANT/MYTHIC).</summary>
        public static int EvolutionStage(int kills)
        {
            if (kills >= 20) return 3;
            if (kills >= 10) return 2;
            if (kills >= 5) return 1;
            return 0;
        }
    }
}
