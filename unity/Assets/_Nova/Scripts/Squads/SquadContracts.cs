using UnityEngine;
using NovaMobile.Classes;
using NovaMobile.Core;

namespace NovaMobile.Squads
{
    /// <summary>Squad-level orders issued by SquadManager's staggered think tick.</summary>
    public enum SquadOrder { Regroup, Attack, Defend, Rotate }

    /// <summary>
    /// Implemented by the Player (or MatchManager) so bots can skip targets
    /// that are still skydiving in. The Match system wires this when it is
    /// ported; until then the check is null-safe (treated as not dropping).
    /// </summary>
    public interface IDropState
    {
        bool IsDropping { get; }
    }

    /// <summary>
    /// Implemented by the Player so AI teammates can detect and perform the
    /// 5-second revive channel on a downed local player.
    /// </summary>
    public interface IDownedPlayer
    {
        bool IsDowned { get; }
        void Revive();
    }

    /// <summary>
    /// Anything the bot brains can acquire, track, and damage: bot agents
    /// and the local player (via PlayerTarget). Lets NearestHostile return
    /// the player without a BotAgent wrapper.
    /// </summary>
    public interface ITargetable
    {
        GameObject gameObject { get; }
        Transform transform { get; }
        bool IsDead { get; }
        bool IsDowned { get; }
        int SquadId { get; }
        string Callsign { get; }
        /// <summary>Chest-height aim point (+1.2m).</summary>
        Vector3 AimPosition { get; }
        /// <summary>Class-body surface for velocity/fairness reads; may be null.</summary>
        IClassBody Body { get; }
        void DamageBot(float amount, Vector3 fromPos, NovaMobile.Core.DamageCause cause,
            bool headshot, GameObject killerGo);
    }
}
