using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>
    /// World quality tiers. Scatter density and procedural texture sizes step down on
    /// the Low tier so the 690m world scales to weaker phones. "Low" is detected from
    /// the active QualitySettings level name (falling back to level index 0).
    /// </summary>
    public static class WorldQuality
    {
        public static readonly bool IsLow;

        static WorldQuality()
        {
            bool low = false;
            try
            {
                string[] names = QualitySettings.names;
                int lvl = QualitySettings.GetQualityLevel();
                if (names != null && lvl >= 0 && lvl < names.Length)
                    low = names[lvl].ToLowerInvariant().Contains("low");
                else
                    low = lvl == 0;
            }
            catch
            {
                low = false;
            }
            IsLow = low;
        }

        /// <summary>Procedural texture size: full on Medium+, halved (min 64) on Low.</summary>
        public static int TextureSize(int normal)
        {
            return IsLow ? Mathf.Max(64, normal / 2) : normal;
        }

        /// <summary>Multiplier for wilderness/prop scatter density.</summary>
        public static float ScatterScale => IsLow ? 0.45f : 1f;
    }
}
