using System;
using UnityEngine;

namespace NovaMobile.Match
{
    /// <summary>
    /// Cross-system event hub for the match. Other systems (Squads, Arsenal,
    /// Mythics, Loot) raise these; the Match UI layer (Killfeed, FeedbackLayer)
    /// subscribes. Static so systems that spawn before the MatchManager can
    /// still report.
    /// </summary>
    public static class MatchEvents
    {
        /// <summary>A combatant died: (killerName, victimName, gunId).</summary>
        public static event Action<string, string, string> KillReported;
        /// <summary>The local player dealt damage: (amount, worldPosition).</summary>
        public static event Action<float, Vector3> PlayerDamageDealt;
        /// <summary>Mythic skin milestone hit: (themeName, killCount, milestone).</summary>
        public static event Action<string, int, string> MythicMilestone;
        /// <summary>Local player downed-state changed: true = knocked, needs revive.</summary>
        public static event Action<bool> PlayerDownedState;
        /// <summary>Zone phase changed: (phaseIndex, shrinking).</summary>
        public static event Action<int, bool> ZonePhaseChanged;
        /// <summary>Hit confirmed on an enemy: (killed, fromDirectionDegrees).</summary>
        public static event Action<bool, float> HitConfirmed;

        public static void RaiseKillReported(string killer, string victim, string gunId)
        {
            var h = KillReported; if (h != null) h(killer, victim, gunId);
        }
        public static void RaisePlayerDamageDealt(float amount, Vector3 worldPos)
        {
            var h = PlayerDamageDealt; if (h != null) h(amount, worldPos);
        }
        public static void RaiseMythicMilestone(string theme, int kills, string milestone)
        {
            var h = MythicMilestone; if (h != null) h(theme, kills, milestone);
        }
        public static void RaisePlayerDownedState(bool downed)
        {
            var h = PlayerDownedState; if (h != null) h(downed);
        }
        public static void RaiseZonePhaseChanged(int phase, bool shrinking)
        {
            var h = ZonePhaseChanged; if (h != null) h(phase, shrinking);
        }
        public static void RaiseHitConfirmed(bool killed, float fromDirDeg)
        {
            var h = HitConfirmed; if (h != null) h(killed, fromDirDeg);
        }
    }
}
