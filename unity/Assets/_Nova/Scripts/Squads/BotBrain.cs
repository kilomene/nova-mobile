using UnityEngine;
using NovaMobile.Core;
using NovaMobile.Player;
using NovaMobile.Soldiers;
using NovaMobile.Classes;

namespace NovaMobile.Squads
{
    /// <summary>
    /// The 9 tactical brain states. Exact contract shape from CONVENTIONS.md.
    /// </summary>
    public enum BotBrainState
    {
        Wander, Engage, Suppress, Flank, Cover, Peek, Nade, ReviveMate, Rotate
    }

    /// <summary>
    /// Tactical bot brain, ported from enemy.gd: focus fire, flanking, cover +
    /// peek-fire rhythm, frags at clustered targets, smoke for revives, zone
    /// rotation. Hard but fair: 0.35–0.7s reaction delay, distance/movement
    /// miss chances, LOS + hearing only (no wallhacks, no aimbots).
    /// </summary>
    [RequireComponent(typeof(BotAgent))]
    [RequireComponent(typeof(CharacterController))]
    public class BotBrain : MonoBehaviour, IBotDriver
    {
        private const float Speed = 2.6f;
        private const float EngageSpeed = 4.0f;
        private const float FlankSpeed = 6.0f;
        private const float AttackRange = 26.0f;
        private const float ShotInterval = 1.7f;
        private const float FarLodDist = 170f;

        private BotAgent _agent;
        private CharacterController _cc;
        private SquadManager _sm;

        private BotBrainState _state = BotBrainState.Wander;
        private float _thinkT;
        private ITargetable _tgt;
        private float _reactT;
        private float _noLosT;
        private Vector3 _coverPos;
        private float _coverCd;
        private float _peekT;
        private bool _peekHide;
        private Vector3 _flankPos;
        private int _grenades = 1;
        private int _smokes = 1;
        private float _nadeCd;
        private BotAgent _reviveTarget;
        private float _reviveT;
        private float _lastHurtT = -99f;
        private Vector3 _lastHurtFrom;
        private float _barkCd;

        private Vector3 _wanderTarget;
        private float _idleT;
        private float _shotT;
        private Vector3 _investigatePos;
        private float _investigateT;
        private float _strafeT;
        private int _strafeDir = 1;
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
            _thinkT = Random.value * 0.4f;
            _shotT = Random.value * ShotInterval;
            if (Random.value < 0.35f) _grenades = 2;
            _wanderTarget = RandomWanderPoint();
        }

        public void NotifyHurt(Vector3 fromPos)
        {
            _lastHurtT = Time.time;
            _lastHurtFrom = fromPos;
        }

        public void Investigate(Vector3 pos, float duration)
        {
            _investigatePos = pos;
            _investigateT = duration;
        }

        // ------------------------------------------------------------------ drive
        public void Drive(float dt)
        {
            if (_sm == null) _sm = SquadManager.Instance;

            if (_reactT > 0f) _reactT -= dt;
            if (_coverCd > 0f) _coverCd -= dt;
            if (_nadeCd > 0f) _nadeCd -= dt;
            if (_barkCd > 0f) _barkCd -= dt;

            // Far LOD: settle only (anim holds pose); the agent handles it.
            Vector3 pp = _sm != null ? _sm.PlayerPos : transform.position;
            bool far = (transform.position - pp).sqrMagnitude > FarLodDist * FarLodDist;
            _agent.SetFarLod(far);
            if (far) return;

            _thinkT -= dt;
            if (_thinkT <= 0f)
            {
                _thinkT = 0.3f + Random.value * 0.15f;
                Think();
            }
            Move(dt);
            Animate();
        }

        // ------------------------------------------------------------------ think
        private void Think()
        {
            ITargetable newTgt = _sm != null
                ? _sm.NearestHostile(_agent, AttackRange + 14f)
                : null;
            if (newTgt != _tgt)
            {
                _tgt = newTgt;
                if (_tgt != null)
                {
                    _reactT = Random.Range(0.35f, 0.7f); // human-like reaction
                    _noLosT = 0f;
                }
            }
            if (_tgt != null && _tgt.IsDead)
                _tgt = null;

            int order = -1;
            string role = "";
            if (_sm != null)
            {
                var sq = _sm.SquadOf(_agent);
                if (sq != null)
                {
                    order = (int)sq.Order;
                    string r;
                    if (sq.Roles.TryGetValue(_agent, out r)) role = r;
                }
            }

            // Downed squadmate: nearest free buddy revives.
            if (role == "revive" && _sm != null)
            {
                BotAgent dm = _sm.DownedMate(_agent);
                if (dm != null)
                {
                    _reviveTarget = dm;
                    _state = BotBrainState.ReviveMate;
                    _reviveT = 0f;
                    return;
                }
            }
            _reviveTarget = null;

            // Zone rotation overrides everything (except revive).
            if (order == (int)SquadOrder.Rotate)
            {
                _state = BotBrainState.Rotate;
                return;
            }

            if (_tgt != null)
            {
                float d = FlatDist(_tgt.transform.position);
                bool los = HasLos(_tgt);
                if (los) _noLosT = 0f;
                else _noLosT += 0.35f;

                // Took fire recently and exposed: break for cover.
                if (_coverCd <= 0f && Time.time - _lastHurtT < 1.2f
                    && _state != BotBrainState.Cover && _state != BotBrainState.Peek)
                {
                    Vector3 away = transform.position - _lastHurtFrom;
                    away.y = 0f;
                    _coverPos = transform.position
                        + (away.sqrMagnitude > 0.01f ? away.normalized : transform.forward) * 8f;
                    _coverPos.y = transform.position.y;
                    _state = BotBrainState.Cover;
                    _coverCd = 6f;
                    _peekT = 0f;
                    _peekHide = false;
                    return;
                }

                if (role == "flank" && d > 10f)
                {
                    Vector3 toT = _tgt.transform.position - transform.position;
                    toT.y = 0f;
                    Vector3 side = new Vector3(-toT.z, 0f, toT.x).normalized;
                    Vector3 rel = transform.position - _tgt.transform.position;
                    if (rel.x * side.x + rel.z * side.z < 0f) side = -side;
                    _flankPos = _tgt.transform.position + side * 14f + toT.normalized * 4f;
                    _state = BotBrainState.Flank;
                    return;
                }
                if (_state == BotBrainState.Flank && d < 9f)
                    _state = BotBrainState.Engage;

                if (_state != BotBrainState.Flank && _state != BotBrainState.Cover
                    && _state != BotBrainState.Peek)
                {
                    // Grenade: entrenched/clustered target at mid range.
                    if (_grenades > 0 && _nadeCd <= 0f && d > 8f && d < 24f
                        && (_noLosT > 2f || ClusteredTarget()))
                    {
                        _state = BotBrainState.Nade;
                        return;
                    }
                    _state = (role == "suppress" && !los)
                        ? BotBrainState.Suppress
                        : BotBrainState.Engage;
                }
                return;
            }

            // No target: investigate the focus squad, or wander.
            _state = BotBrainState.Wander;
            if (order == (int)SquadOrder.Attack && _sm != null)
            {
                var sq2 = _sm.SquadOf(_agent);
                if (sq2 != null && sq2.Focus != null)
                    Investigate(sq2.Focus.Centroid, 8f);
            }
        }

        private bool ClusteredTarget()
        {
            if (_tgt == null || _sm == null) return false;
            int n = 0;
            Vector3 tp = _tgt.transform.position;
            var list = _sm.Combatants;
            for (int i = 0; i < list.Count; i++)
            {
                BotAgent c = list[i];
                if (c == null || c == _tgt || c.IsDead || c.SquadId != _tgt.SquadId)
                    continue;
                if ((c.transform.position - tp).sqrMagnitude < 36f) n++;
            }
            return n >= 1;
        }

        private float FlatDist(Vector3 p)
        {
            Vector3 d = p - transform.position;
            return Mathf.Sqrt(d.x * d.x + d.z * d.z);
        }

        private bool HasLos(ITargetable tgt)
        {
            Vector3 from = transform.position + Vector3.up * 1.5f;
            Vector3 to = tgt.AimPosition;
            if (SmokeGrenade.BlocksSight(from, to)) return false;
            Vector3 dir = to - from;
            float dist = dir.magnitude;
            if (dist < 0.001f) return true;
            // Exclude self without allocations: briefly disable our own collider.
            _cc.enabled = false;
            RaycastHit hit;
            bool blocked = Physics.Raycast(from, dir / dist, out hit, dist,
                ~0, QueryTriggerInteraction.Ignore);
            bool clear = !blocked || RayHitTarget(hit, tgt);
            _cc.enabled = true;
            return clear;
        }

        /// <summary>
        /// True when the ray's first solid hit is the intended target: its own
        /// BotAgent for bots, any collider under the player root for the player.
        /// </summary>
        private static bool RayHitTarget(RaycastHit hit, ITargetable tgt)
        {
            var ba = tgt as BotAgent;
            if (ba != null)
                return hit.collider.GetComponentInParent<BotAgent>() == ba;
            return hit.collider.GetComponentInParent<PlayerTarget>() != null;
        }

        // ------------------------------------------------------------------ move
        private void Move(float dt)
        {
            Vector3 moveDir = Vector3.zero;
            float spd = Speed;
            bool shooting = false;

            switch (_state)
            {
                case BotBrainState.Engage:
                    if (_tgt != null && !_tgt.IsDead)
                    {
                        Vector3 toT = _tgt.transform.position - transform.position;
                        toT.y = 0f;
                        float d = toT.magnitude;
                        _agent.FaceTowards(toT, 8f, dt);
                        if (HasLos(_tgt))
                        {
                            shooting = true;
                            if (d > 14f) { moveDir = toT.normalized; spd = EngageSpeed; }
                            else if (d < 5f) { moveDir = -toT.normalized * 0.6f; spd = Speed; }
                            else
                            {
                                _strafeT -= dt;
                                if (_strafeT <= 0f)
                                {
                                    _strafeT = 0.9f;
                                    _strafeDir = -_strafeDir;
                                }
                                Vector3 side = new Vector3(-toT.z, 0f, toT.x).normalized;
                                moveDir = side * _strafeDir;
                                spd = Speed * 0.8f;
                            }
                        }
                        else { moveDir = toT.normalized; spd = EngageSpeed; }
                    }
                    break;

                case BotBrainState.Suppress:
                    if (_tgt != null && !_tgt.IsDead)
                    {
                        Vector3 toT2 = _tgt.transform.position - transform.position;
                        toT2.y = 0f;
                        _agent.FaceTowards(toT2, 8f, dt);
                        moveDir = toT2.normalized;
                        spd = EngageSpeed;
                        shooting = HasLos(_tgt) || _noLosT < 4f; // fire at last known pos
                    }
                    break;

                case BotBrainState.Flank:
                    {
                        Vector3 toF = _flankPos - transform.position;
                        toF.y = 0f;
                        if (toF.magnitude > 2f)
                        {
                            moveDir = toF.normalized;
                            spd = FlankSpeed;
                            _agent.FaceTowards(toF, 6f, dt);
                        }
                        else _state = BotBrainState.Engage;
                        if (_tgt != null && !_tgt.IsDead && HasLos(_tgt) && _reactT <= 0f)
                            shooting = true;
                    }
                    break;

                case BotBrainState.Cover:
                    {
                        Vector3 toC = _coverPos - transform.position;
                        toC.y = 0f;
                        if (toC.magnitude > 1.5f)
                        {
                            moveDir = toC.normalized;
                            spd = EngageSpeed;
                            _agent.FaceTowards(toC, 6f, dt);
                        }
                        else
                        {
                            _state = BotBrainState.Peek;
                            _peekT = 1.6f;
                            _peekHide = true;
                        }
                    }
                    break;

                case BotBrainState.Peek:
                    _peekT -= dt;
                    if (_peekT <= 0f)
                    {
                        _peekHide = !_peekHide;
                        _peekT = _peekHide ? 1.6f : 1.1f; // hide 1.6s, expose 1.1s
                    }
                    if (_tgt != null && !_tgt.IsDead)
                    {
                        Vector3 toT3 = _tgt.transform.position - transform.position;
                        toT3.y = 0f;
                        _agent.FaceTowards(toT3, 8f, dt);
                        shooting = !_peekHide && HasLos(_tgt);
                    }
                    if (_tgt == null) _state = BotBrainState.Wander;
                    break;

                case BotBrainState.Nade:
                    if (_tgt != null && !_tgt.IsDead)
                    {
                        Vector3 toT4 = _tgt.transform.position - transform.position;
                        toT4.y = 0f;
                        _agent.FaceTowards(toT4, 10f, dt);
                        ThrowFrag(_tgt.transform.position);
                    }
                    _state = BotBrainState.Engage;
                    _nadeCd = 8f;
                    break;

                case BotBrainState.ReviveMate:
                    if (_reviveTarget != null && !_reviveTarget.IsDead && _reviveTarget.IsDowned)
                    {
                        Vector3 toR = _reviveTarget.transform.position - transform.position;
                        toR.y = 0f;
                        if (toR.magnitude > 2.5f)
                        {
                            moveDir = toR.normalized;
                            spd = EngageSpeed;
                            _agent.FaceTowards(toR, 6f, dt);
                            _reviveT = 0f;
                            if (toR.magnitude > 12f && _smokes > 0)
                                ThrowSmoke(_reviveTarget.transform.position);
                        }
                        else
                        {
                            _reviveT += dt;
                            if (_reviveT >= 5f) // 5s revive channel
                            {
                                _reviveTarget.ReviveAlly();
                                SquadManager.RadioBark(_agent.Callsign, BotNames.BarkRevive);
                                _state = BotBrainState.Wander;
                                _reviveTarget = null;
                            }
                        }
                    }
                    else { _state = BotBrainState.Wander; _reviveTarget = null; }
                    break;

                case BotBrainState.Rotate:
                    {
                        Vector3 rp = _sm != null ? _sm.SquadOrderPos(_agent) : transform.position;
                        Vector3 toZ = rp - transform.position;
                        toZ.y = 0f;
                        if (toZ.magnitude > 4f)
                        {
                            moveDir = toZ.normalized;
                            spd = FlankSpeed;
                            _agent.FaceTowards(toZ, 6f, dt);
                            if (_barkCd <= 0f)
                            {
                                _barkCd = 12f;
                                SquadManager.RadioBark(_agent.Callsign, BotNames.BarkRotate);
                            }
                        }
                        else _state = BotBrainState.Wander;
                    }
                    break;

                default: // Wander: investigate sounds, else walk/idle between points.
                    if (_investigateT > 0f)
                    {
                        _investigateT -= dt;
                        Vector3 toI = _investigatePos - transform.position;
                        toI.y = 0f;
                        if (toI.magnitude > 1.5f)
                        {
                            moveDir = toI.normalized;
                            _agent.FaceTowards(toI, 5f, dt);
                        }
                        else _investigateT = 0f;
                    }
                    else if (_idleT > 0f)
                    {
                        _idleT -= dt;
                    }
                    else
                    {
                        Vector3 toT5 = _wanderTarget - transform.position;
                        toT5.y = 0f;
                        if (toT5.magnitude < 1.5f)
                        {
                            _idleT = Random.Range(1f, 3f);
                            _wanderTarget = RandomWanderPoint();
                        }
                        else
                        {
                            moveDir = toT5.normalized;
                            _agent.FaceTowards(toT5, 5f, dt);
                        }
                    }
                    break;
            }

            bool stunned = _agent.IsStunned || _agent.IsJammed;
            _agent.SetMove(stunned ? Vector3.zero : moveDir, spd);
            _engaged = shooting && !stunned;
            if (_engaged && _tgt != null && !_tgt.IsDead)
                TryShoot(dt, _tgt);
        }

        private Vector3 RandomWanderPoint()
        {
            Vector3 home = _sm != null ? _sm.HomePosition(_agent) : transform.position;
            float ext = 330f; // world half-extent fallback
            float x = Mathf.Clamp(home.x + Random.Range(-30f, 30f), -ext, ext);
            float z = Mathf.Clamp(home.z + Random.Range(-30f, 30f), -ext, ext);
            return new Vector3(x, transform.position.y, z);
        }

        // ------------------------------------------------------------------ shooting
        private void TryShoot(float dt, ITargetable tgt)
        {
            if (_reactT > 0f) return;
            _shotT -= dt;
            if (_shotT > 0f) return;
            _shotT = ShotInterval * Random.Range(0.85f, 1.25f);

            _agent.NotifyFired();

            Vector3 tp = tgt.transform.position;
            float d = FlatDist(tp);
            float hitP = Mathf.Clamp(0.72f - d * 0.016f, 0.18f, 0.72f);
            // Moving targets and moving shooters are harder to hit.
            IClassBody tbody = tgt.Body;
            if (tbody != null)
            {
                Vector3 tv3 = tbody.Velocity;
                if (new Vector2(tv3.x, tv3.z).magnitude > 4f) hitP *= 0.6f;
            }
            Vector3 sv = ((IClassBody)_agent).Velocity;
            if (new Vector2(sv.x, sv.z).magnitude > 3f) hitP *= 0.7f;
            if (_state == BotBrainState.Suppress && !HasLos(tgt)) hitP *= 0.35f;

            if (Random.value < hitP)
            {
                bool headshot = Random.value < 0.12f;
                tgt.DamageBot(_agent.ShotDamage, transform.position,
                    headshot ? DamageCause.Headshot : DamageCause.Bullet,
                    headshot, gameObject);
                if (!tgt.IsDead && !tgt.IsDowned && Random.value < 0.25f)
                    SquadManager.RadioBark(_agent.Callsign, BotNames.BarkKill);
            }
            // else: clean miss — no free damage, no tracer spam on mobile.
        }

        private void ThrowFrag(Vector3 at)
        {
            if (_grenades <= 0) return;
            _grenades--;
            _agent.PlayAction(SoldierClip.GrenadeThrow);
            SquadManager.RadioBark(_agent.Callsign, BotNames.BarkGrenade);
            Vector3 from = transform.position + Vector3.up * 1.5f;
            Vector3 to = at + new Vector3(Random.Range(-1.5f, 1.5f), 0f, Random.Range(-1.5f, 1.5f));
            Vector3 dir = (to - from).normalized;
            float dist = FlatDist(at);
            FragGrenade.Spawn(from, dir, dist * 0.85f + 5f, 0f, gameObject);
        }

        private void ThrowSmoke(Vector3 at)
        {
            if (_smokes <= 0) return;
            _smokes--;
            _agent.PlayAction(SoldierClip.GrenadeThrow);
            Vector3 from = transform.position + Vector3.up * 1.5f;
            Vector3 dir = ((at + Vector3.up * 0.5f) - from).normalized;
            SmokeGrenade.Spawn(from, dir, 12f, gameObject);
        }

        // ------------------------------------------------------------------ animation
        private void Animate()
        {
            var anim = _agent.Anim;
            if (anim == null) return;
            var body = (IClassBody)_agent;
            float spd = new Vector2(body.Velocity.x, body.Velocity.z).magnitude;

            if (_state == BotBrainState.Peek && _peekHide)
            {
                _agent.TakeOverAnimation();
                anim.Play(SoldierClip.CrouchIdle, 0.2f);
                anim.SetAim(0f, 0f, 0f, false);
            }
            else if (_state == BotBrainState.Cover)
            {
                _agent.TakeOverAnimation();
                anim.Play(SoldierClip.CrouchWalk, 0.2f, spd / 2.6f);
                anim.SetAim(0f, 0f, 0f, false);
            }
            else if (_state == BotBrainState.ReviveMate && _reviveTarget != null
                && (_reviveTarget.transform.position - transform.position).magnitude <= 2.5f)
            {
                _agent.TakeOverAnimation();
                anim.Play(SoldierClip.CrouchIdle, 0.2f);
                anim.SetAim(0f, 0f, 0f, false);
            }
            else if (_engaged)
            {
                _agent.TakeOverAnimation();
                anim.Play(SoldierClip.Run, 0.2f, spd / 4.2f);
                if (_tgt != null && !_tgt.IsDead)
                {
                    Vector3 toT = _tgt.transform.position - transform.position;
                    float wantYaw = Mathf.Atan2(toT.x, toT.z) * Mathf.Rad2Deg;
                    float rel = Mathf.DeltaAngle(transform.eulerAngles.y, wantYaw) * Mathf.Deg2Rad;
                    anim.SetAim(1f, rel, 0f, false);
                }
                else anim.SetAim(0f, 0f, 0f, false);
            }
            // else: the agent's locomotion anim (walk/run/idle) already ran.
        }
    }
}
