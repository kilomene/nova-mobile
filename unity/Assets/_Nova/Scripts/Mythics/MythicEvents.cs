using System;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Cross-system mythic events. The Match system subscribes to
    /// OnEvolutionMilestone to show the banner UI (and can forward it to the
    /// killfeed, e.g. "ZENAS — M5 "Dragonfire" AWAKENED").
    /// </summary>
    public static class MythicEvents
    {
        /// <summary>
        /// Milestone banner: (gunId, themeId, stage) with stage 1..3 =
        /// AWAKENED / ASCENDANT / MYTHIC.
        /// </summary>
        public static Action<string, string, int> OnEvolutionMilestone;

        public static void RaiseEvolutionMilestone(string gunId, string themeId, int stage)
        {
            var h = OnEvolutionMilestone;
            if (h != null) h(gunId, themeId, stage);
        }
    }
}
