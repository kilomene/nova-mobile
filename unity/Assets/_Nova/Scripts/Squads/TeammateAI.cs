using UnityEngine;
using NovaMobile.Core;
using NovaMobile.Player;
using NovaMobile.Soldiers;

namespace NovaMobile.Squads
{
    /// <summary>
    /// AI teammate driver, ported from ally.gd: follows the player in
    /// formation, engages the player's target, runs the 5s revive channel on
    /// the downed player, reacts to high-tier Loot ping events, and calls out
    /// contacts on the radio net. Goes downed (30s bleed-out) instead of dying
    /// while a squadmate lives.
    /// </summary>
    [RequireComponent(typeof(BotAgent))]
    [RequireComponent(typeof(CharacterController))]
    public class TeammateAI : MonoBehaviour, IBotDriver
    {
        private const float Speed = 2.9f;
        private const float EngageSpeed = 4.1f;
        private const float FollowDist = 3.2f;
        private const float AttackRange = 26.0f;
        private const float ShotInterval = 1.4f;
        private const float FarLodDist = 170f;

        private static readonly float[] LaneOffsets = { 2.2f, -2.2f, 3.6f };

        private BotAgent _agent;
        private CharacterController _cc;
        private SquadManager _sm;
        private int _slot;

        private ITargetable _foe;
        private float _shotT;
        private float _barkCd;
        private float _reviveT;
        private IDownedPlayer _reviveTarget;
        private Vector3 _investigatePos;
        private float _investigateT;
        private bool _engaged;

        private void Awake()
        {
            _agent = GetComponent<BotAgent>();
            _cc = GetComponent<CharacterController>();
            _agent.Driver = this;
        }

        private void Start()
        {
            _sm = SquadManager.Instance;
            _slot = _agent.Slot;
            _shotT = Random.value * ShotInterval;
        }

        public void SetupSlot(int slot) { _slot = slot; }

        public void Investigate(Vector3 pos, float duration)
        {
            _investigatePos = pos;
            _investigateT = duration;
        }

        private void OnEnable()
        {
            SquadManager.LootPingged += OnLootPing;
        }

        private void OnDisable()
        {
            SquadManager.LootPingged -= OnLootPing;
        }

        private void OnLootPing(Vector3 pos, int tier, string label)
        {
            // React to high-tier loot pings (epic+), like loot_ping.gd's AI hook.
            if (_sm == null || _sm.Player == null) return;
            if (tier < 4) return;
            float d = (_sm.PlayerPos - pos).magnitude;
            if (d < 45f)
            {
                Investigate(pos, 20f);
                Bark(_agent.Callsign + ": Ping — " + label + " nearby.");
            }
        }

        // ------------------------------------------------------------------ drive
        public void Drive(float dt)
        {
            if (_sm == null) _sm = SquadManager.Instance;
            if (_barkCd > 0f) _barkCd -= dt;

            GameObject playerGo = _sm != null ? _sm.Player : null;
            if (playerGo == null || !playerGo.activeInHierarchy)
            {
                _agent.SetMove(Vector3.zero, 0f);
                return;
            }

            Vector3 pp = _sm.PlayerPos;
            bool far = (transform.position - pp).sqrMagnitude > FarLodDist * FarLodDist;
            _agent.SetFarLod(far);
            if (far) return;

            Vector3 moveDir = Vector3.zero;
            bool engaging = false;
            float aimYaw = 0f;
            _reviveTarget = null;

            // Priority 1: revive the downed player (5s channel).
            IDownedPlayer dp = playerGo.GetComponent<IDownedPlayer>();
            if (dp != null && dp.IsDowned)
            {
                _reviveTarget = dp;
                Vector3 toP = pp - transform.position;
                toP.y = 0f;
                if (toP.magnitude > 2.5f)
                {
                    moveDir = toP.normalized;
                    _reviveT = 0f;
                    _agent.FaceTowards(toP, 6f, dt);
                }
                else
                {
                    _reviveT += dt;
                    _agent.FaceTowards(toP, 8f, dt);
                    if (_reviveT >= 5f)
                    {
                        dp.Revive();
                        _reviveT = 0f;
                        _reviveTarget = null;
                        SquadManager.RadioBark(_agent.Callsign, BotNames.BarkRevive);
                    }
                }
            }
            else
            {
                _reviveT = 0f;
            }

            // Priority 2: combat — prefer the player's target.
            if (_reviveTarget == null)
            {
                _foe = PickFoe(pp);
                if (_foe != null)
                {
                    engaging = true;
                    Vector3 toF = _foe.transform.position - transform.position;
                    toF.y = 0f;
                    _agent.FaceTowards(toF, 8f, dt);
                    float wantYaw = Mathf.Atan2(toF.x, toF.z) * Mathf.Rad2Deg;
                    aimYaw = Mathf.DeltaAngle(transform.eulerAngles.y, wantYaw) * Mathf.Deg2Rad;
                    _shotT -= dt;
                    if (_shotT <= 0f)
                    {
                        _shotT = ShotInterval * Random.Range(0.85f, 1.2f);
                        AllyShoot(_foe);
                    }
                    if (toF.magnitude > 8f) moveDir = toF.normalized;
                }
                else if (_investigateT > 0f)
                {
                    _investigateT -= dt;
                    Vector3 toI = _investigatePos - transform.position;
                    toI.y = 0f;
                    if (toI.magnitude > 2f)
                    {
                        moveDir = toI.normalized;
                        _agent.FaceTowards(toI, 5f, dt);
                    }
                    else _investigateT = 0f;
                }
                else
                {
                    // Priority 3: formation follow (lane offsets behind the player).
                    Vector3 back = playerGo.transform.forward * -1f;
                    Vector3 side = playerGo.transform.right;
                    float lane = LaneOffsets[_slot % 3];
                    Vector3 want = pp + back * FollowDist + side * lane;
                    Vector3 toP2 = want - transform.position;
                    toP2.y = 0f;
                    if (toP2.magnitude > 1.6f)
                    {
                        moveDir = toP2.normalized;
                        _agent.FaceTowards(moveDir, 6f, dt);
                    }
                    else
                    {
                        _agent.FaceTowards(playerGo.transform.forward, 4f, dt);
                    }
                }
            }

            float spd = engaging ? EngageSpeed : Speed;
            bool stunned = _agent.IsStunned || _agent.IsJammed;
            _agent.SetMove(stunned ? Vector3.zero : moveDir, spd);
            _engaged = engaging && !stunned;

            Animate(spd, aimYaw, moveDir);
        }

        private ITargetable PickFoe(Vector3 playerPos)
        {
            if (_sm == null || _sm.TestCeasefire) return null;
            // Player's target first: when the player recently fired, engage the
            // hostile nearest to their aim point.
            Vector3 focusPos = playerPos;
            bool hasFocus = false;
            if (_sm.PlayerFiredRecently(out focusPos)) hasFocus = true;

            ITargetable best = null;
            float bd = hasFocus ? 40f : AttackRange;
            Vector3 scanFrom = hasFocus ? focusPos : transform.position;
            var list = _sm.Combatants;
            for (int i = 0; i < list.Count; i++)
            {
                BotAgent c = list[i];
                if (c == null || c.IsDead || c.IsDowned || c.SquadId == 0) continue;
                float d = (c.transform.position - scanFrom).magnitude;
                if (d < bd && HasLos(c)) { bd = d; best = c; }
            }
            if (best != null && best != _foe) Callout(best);
            return best;
        }

        private void Callout(ITargetable e)
        {
            if (_barkCd > 0f) return;
            _barkCd = 14f;
            SquadManager.RadioBark(_agent.Callsign,
                new string[] { BotNames.Bark(BotNames.BarkEngage, SquadManager.Rng) + " — " + e.Callsign });
        }

        private void Bark(string line)
        {
            if (_barkCd > 0f) return;
            _barkCd = 9f;
            SquadManager.RadioBarkRaw(_agent.Callsign, line);
        }

        private bool HasLos(ITargetable tgt)
        {
            Vector3 from = transform.position + Vector3.up * 1.5f;
            Vector3 to = tgt.AimPosition;
            if (SmokeGrenade.BlocksSight(from, to)) return false;
            Vector3 dir = to - from;
            float dist = dir.magnitude;
            if (dist < 0.001f) return true;
            _cc.enabled = false;
            RaycastHit hit;
            bool blocked = Physics.Raycast(from, dir / dist, out hit, dist,
                ~0, QueryTriggerInteraction.Ignore);
            bool clear = !blocked || RayHitTarget(hit, tgt);
            _cc.enabled = true;
            return clear;
        }

        private static bool RayHitTarget(RaycastHit hit, ITargetable tgt)
        {
            var ba = tgt as BotAgent;
            if (ba != null)
                return hit.collider.GetComponentInParent<BotAgent>() == ba;
            return hit.collider.GetComponentInParent<PlayerTarget>() != null;
        }

        private void AllyShoot(ITargetable e)
        {
            _agent.NotifyFired();
            // Allies hit reliably at close range; honest falloff past 18m.
            float d = (e.transform.position - transform.position).magnitude;
            float hitP = d < 12f ? 0.85f : Mathf.Clamp(0.85f - (d - 12f) * 0.03f, 0.3f, 0.85f);
            if (Random.value < hitP)
                e.DamageBot(_agent.ShotDamage, transform.position,
                    DamageCause.Bullet, false, gameObject);
        }

        private void Animate(float spd, float aimYaw, Vector3 moveDir)
        {
            var anim = _agent.Anim;
            if (anim == null) return;
            if (_reviveTarget != null)
            {
                _agent.TakeOverAnimation();
                anim.Play(SoldierClip.CrouchIdle, 0.2f);
                anim.SetAim(0f, 0f, 0f, false);
            }
            else if (_engaged)
            {
                _agent.TakeOverAnimation();
                anim.Play(SoldierClip.Run, 0.2f, spd / 4.2f);
                anim.SetAim(1f, aimYaw, 0f, false);
            }
            else if (moveDir.sqrMagnitude > 0.001f)
            {
                _agent.TakeOverAnimation();
                anim.Play(SoldierClip.Walk, 0.25f, spd / 2.9f);
                anim.SetAim(0f, 0f, 0f, false);
            }
            // else: the agent's idle anim already ran.
        }
    }
}
