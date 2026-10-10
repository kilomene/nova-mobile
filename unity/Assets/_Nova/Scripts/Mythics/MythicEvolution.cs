using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Kill evolution, ported from Godot mythic_skins.gd evolution_stage():
    /// Dormant -> AWAKENED (5 kills) -> ASCENDANT (10) -> MYTHIC (20).
    /// Each stage upgrades shader emission intensity (SetEvolve), accent scale,
    /// and tracer brightness; milestones fire the banner event the Match system
    /// listens to, plus a sting and a big kill banner in-world.
    /// Integration: the Match system calls OnKill when the local player scores a
    /// kill with a mythic-skinned gun; call ResetMatch when a match starts.
    /// </summary>
    public static class MythicEvolution
    {
        private static readonly Dictionary<string, int> _kills = new Dictionary<string, int>();

        public static int KillsFor(string gunId)
        {
            int k;
            return _kills.TryGetValue(gunId, out k) ? k : 0;
        }

        public static int StageFor(string gunId)
        {
            return MythicData.EvolutionStage(KillsFor(gunId));
        }

        /// <summary>Call when a match starts so evolution counts reset.</summary>
        public static void ResetMatch()
        {
            _kills.Clear();
        }

        /// <summary>
        /// Call when the local player scores a kill with a mythic-skinned gun.
        /// gunRoot: the gun GameObject (may be null); worldPos: victim position.
        /// </summary>
        public static void OnKill(string gunId, string themeId, GameObject gunRoot, Vector3 worldPos)
        {
            if (string.IsNullOrEmpty(themeId)) return;
            int k = KillsFor(gunId) + 1;
            _kills[gunId] = k;
            int stage = MythicData.EvolutionStage(k);
            if (gunRoot != null) SkinApplier.SetEvolve(gunRoot, stage);
            string milestone = "";
            for (int i = 1; i < MythicData.StageKills.Length; i++)
                if (k == MythicData.StageKills[i]) milestone = MythicData.StageNames[i];
            MythicFx.PlayKillFx(worldPos, themeId, k, milestone);
            if (milestone != "")
            {
                MythicFx.PlaySting();
                MythicEvents.RaiseEvolutionMilestone(gunId, themeId, stage);
            }
        }
    }
}
