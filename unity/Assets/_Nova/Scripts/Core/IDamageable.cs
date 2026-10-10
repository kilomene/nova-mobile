using UnityEngine;

namespace NovaMobile.Core
{
    /// <summary>
    /// Canonical damage contract: anything that can take damage from bullets,
    /// explosions, melee, abilities (bots, players, vehicles, deployables).
    /// </summary>
    public interface IDamageable
    {
        void TakeDamage(float amount, Vector3 from, DamageCause cause);
        bool IsAlive { get; }
    }
}
