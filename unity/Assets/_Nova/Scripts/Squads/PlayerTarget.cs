using UnityEngine;
using NovaMobile.Classes;
using NovaMobile.Core;

namespace NovaMobile.Squads
{
    /// <summary>
    /// ITargetable adapter for the local player, attached by
    /// SquadManager.RegisterPlayer. Lets the bot brains acquire, LOS-check,
    /// and damage the player through the same interface as BotAgent —
    /// including the skydive skip (IsDead reports true while dropping so
    /// target acquisition ignores the player, matching squad_manager.gd).
    /// </summary>
    public class PlayerTarget : MonoBehaviour, ITargetable
    {
        private IDamageable _dmg;
        private IClassBody _body;
        private IDownedPlayer _downed;
        private IDropState _drop;

        private void Awake()
        {
            _dmg = GetComponent<IDamageable>();
            _body = GetComponent<IClassBody>();
            _downed = GetComponent<IDownedPlayer>();
            _drop = GetComponent<IDropState>();
        }

        // A skydiving player is not a valid target (squad_manager.gd: don't
        // shoot parachuters on the way in).
        public bool IsDead
        {
            get
            {
                if (_drop != null && _drop.IsDropping) return true;
                return _dmg != null && !_dmg.IsAlive;
            }
        }

        public bool IsDowned { get { return _downed != null && _downed.IsDowned; } }
        public int SquadId { get { return 0; } }
        public string Callsign { get { return "YOU"; } }

        public Vector3 AimPosition
        {
            get { return transform.position + Vector3.up * 1.2f; }
        }

        public IClassBody Body { get { return _body; } }

        public void DamageBot(float amount, Vector3 fromPos, DamageCause cause,
            bool headshot, GameObject killerGo)
        {
            if (_dmg != null)
                _dmg.TakeDamage(amount, fromPos, headshot ? DamageCause.Headshot : cause);
        }
    }
}
