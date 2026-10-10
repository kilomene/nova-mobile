using System;
using UnityEngine;
using NovaMobile.Arsenal;
using NovaMobile.Classes;
using NovaMobile.Core;
using NovaMobile.Soldiers;

namespace NovaMobile.Squads
{
    /// <summary>
    /// Per-frame tactic driver attached to the same GameObject (BotBrain for
    /// hostiles, TeammateAI for allies). Computes movement/shoot intents.
    /// </summary>
    public interface IBotDriver
    {
        void Drive(float dt);
        void Investigate(Vector3 pos, float duration);
    }

    /// <summary>
    /// One bot combatant body — replaces both Godot NovaEnemy and NovaAlly.
    /// CharacterController locomotion, hp/armor, downed-not-dead with bleed-out,
    /// animated death via SoldierRig, a visual Arsenal gun, a Classes ability
    /// (passive applied at spawn), and EnemyRegistry registration.
    /// The tactic driver (BotBrain / TeammateAI) feeds movement intents; this
    /// class owns physics, health, and the rig.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class BotAgent : MonoBehaviour,
        IDamageable,
        IClassBody, ITargetable,
        ISlowable, IStunnable, IJammable, ISuppressable,
        IInvestigator, IMarkable, IKnockbackable, ILaunchable
    {
        // ------------------------------------------------------------------ identity
        public int SquadId = -1;
        public int Slot = -1;
        public string Callsign = "HOSTILE";
        public int HumanSlot = -1;      // 0 = local player, 1..30 reserved, -1 = AI
        public bool ReservedOnline;     // Phase-2 server slot; runs as AI today
        public bool IsTeammate;         // squad-0 ally (driven by TeammateAI)
        public SquadManager Squadman;

        // ------------------------------------------------------------------ combat stats
        public float MaxHp = 100f;
        public float Hp = 100f;
        public int Armor;
        public int MaxArmor = 100;
        public string GunId = "m5";
        public float ShotDamage = 9f;   // enemies 9, allies 10 (set at spawn)

        public event Action<BotAgent> Died;
        public event Action<BotAgent> Downed;

        public SoldierRig Rig { get; private set; }
        public SoldierAnim Anim { get; private set; }
        public IBotDriver Driver { get; set; }
        public GameObject LastKiller { get; private set; }

        public bool IsDead { get { return _dead; } }
        public bool IsDowned { get { return _downed; } }
        public bool SkipDowned;         // abstract/zone kills bypass downed state
        public bool IsStunned { get { return _stunT > 0f; } }
        public bool IsJammed { get { return _jammed; } }

        private CharacterController _cc;
        private Vector3 _moveDir = Vector3.zero;
        private float _moveSpeed;
        private Vector3 _vel;           // vertical + impulse velocity
        private float _faceYaw;
        private bool _dead;
        private bool _downed;
        private float _bleedT;
        private float _stunT;
        private float _slowT;
        private float _jamT;
        private bool _jammed;
        private float _markedT;
        private float _invisibleT;
        private bool _wasFiring;
        private float _fireT;           // WasFiring decay
        private bool _gliding;
        private bool _farLod;
        private GameObject _muzzleFlash;
        private float _flashT;
        private bool _movingWas;
        private bool _animTakeover; // driver played an anim this frame: skip locomotion anim
        private ClassAbility _ability;

        private static Material _flashMat;
        private static Mesh _flashMesh;

        // ------------------------------------------------------------------ spawn
        public void Setup(int squadId, int slot, string callsign, bool isTeammate,
            int humanSlot, bool reservedOnline, SquadManager squadman)
        {
            SquadId = squadId;
            Slot = slot;
            Callsign = callsign;
            IsTeammate = isTeammate;
            HumanSlot = humanSlot;
            ReservedOnline = reservedOnline;
            Squadman = squadman;
            gameObject.name = (isTeammate ? "Ally_" : "Bot_") + callsign;
        }

        private void Awake()
        {
            _cc = GetComponent<CharacterController>();
            if (_cc == null) _cc = gameObject.AddComponent<CharacterController>();
            _cc.radius = 0.35f;
            _cc.height = 1.8f;
            _cc.center = new Vector3(0f, 0.9f, 0f);
            _cc.stepOffset = 0.4f;
        }

        /// <summary>Build rig, gun, class ability; call once after Setup.</summary>
        public void Build(System.Random rng)
        {
            // Rig + anim.
            var variant = IsTeammate
                ? SoldierVariant.Breacher
                : (SoldierVariant)rng.Next(0, 2);
            Rig = SoldierRig.Build(variant, "Rig");
            Rig.transform.SetParent(transform, false);
            Rig.transform.localPosition = Vector3.zero;
            Rig.transform.localRotation = Quaternion.identity;
            Anim = Rig.Anim;
            Anim.SetLod(false);
            _faceYaw = transform.eulerAngles.y;

            // Visual gun (hitscan logic stays in the driver).
            try
            {
                GunSpec spec = GunData.Get(GunId);
                GameObject gun = GunFactory.BuildGun(spec, false);
                Rig.AttachWeapon(gun);
            }
            catch (Exception) { /* visual only; bots still fight hitscan */ }

            // Class ability: passive hooks applied at spawn.
            try
            {
                if (ClassData.Classes != null && ClassData.Classes.Length > 0)
                {
                    string classId = ClassData.Classes[rng.Next(ClassData.Classes.Length)].Id;
                    _ability = ClassAbilityRegistry.Attach(gameObject, classId);
                    gameObject.AddComponent<EnemyClassDriver>();
                }
            }
            catch (Exception) { _ability = null; }

            BuildMuzzleFlash();
            EnemyRegistry.Register(gameObject);
            BotNameplate.Attach(this); // CODM-style callsign plate (bible §4)
        }

        private void BuildMuzzleFlash()
        {
            if (_flashMat == null)
            {
                _flashMat = new Material(Shader.Find("Standard"));
                _flashMat.color = new Color(1f, 0.85f, 0.4f);
                _flashMat.SetColor("_EmissionColor", new Color(1f, 0.7f, 0.2f) * 3f);
                _flashMat.EnableKeyword("_EMISSION");
            }
            if (_flashMesh == null)
            {
                _flashMesh = new Mesh();
                _flashMesh.vertices = new[] {
                    new Vector3(-0.14f, -0.14f, 0f), new Vector3(0.14f, -0.14f, 0f),
                    new Vector3(0.14f, 0.14f, 0f), new Vector3(-0.14f, 0.14f, 0f) };
                _flashMesh.triangles = new[] { 0, 2, 1, 0, 3, 2 };
                _flashMesh.normals = new[] {
                    Vector3.forward, Vector3.forward, Vector3.forward, Vector3.forward };
                _flashMesh.uv = new[] {
                    Vector2.zero, Vector2.right, Vector2.one, Vector2.up };
                _flashMesh.RecalculateBounds();
            }
            _muzzleFlash = new GameObject("MuzzleFlash");
            _muzzleFlash.transform.SetParent(Rig.WeaponMount, false);
            _muzzleFlash.transform.localPosition = new Vector3(0f, 0.01f, 0.62f);
            var mf = _muzzleFlash.AddComponent<MeshFilter>();
            mf.sharedMesh = _flashMesh;
            var mr = _muzzleFlash.AddComponent<MeshRenderer>();
            mr.sharedMaterial = _flashMat;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            _muzzleFlash.SetActive(false);
        }

        // ------------------------------------------------------------------ driver intents
        public void SetMove(Vector3 dir, float speed)
        {
            _moveDir = dir;
            _moveSpeed = speed;
        }

        public void FaceTowards(Vector3 worldDir, float rate, float dt)
        {
            if (worldDir.sqrMagnitude < 0.0001f) return;
            float want = Mathf.Atan2(worldDir.x, worldDir.z) * Mathf.Rad2Deg;
            _faceYaw = Mathf.LerpAngle(_faceYaw, want, Mathf.Clamp01(rate * dt));
            transform.rotation = Quaternion.Euler(0f, _faceYaw, 0f);
        }

        public void SetFarLod(bool far)
        {
            if (far == _farLod) return;
            _farLod = far;
            Anim.SetLod(far);
        }

        /// <summary>Muzzle flash + jolt + audio + gunshot hearing event.</summary>
        public void NotifyFired()
        {
            _wasFiring = true;
            _fireT = 0.25f;
            _flashT = 0.08f;
            if (_muzzleFlash != null) _muzzleFlash.SetActive(true);
            Anim.AddJolt(0.9f);
            try { BotAudio.PlayAt(GunAudio.ShotClip(GunId), Rig.MuzzlePoint(), 0.8f); }
            catch (Exception) { }
            if (Squadman != null) Squadman.HearShot(transform.position, SquadId);
        }

        public void PlayAnim(SoldierClip clip, float fade = 0.2f, float rate = 1f)
        {
            Anim.Play(clip, fade, rate);
        }

        public void PlayAction(SoldierClip clip)
        {
            Anim.PlayAction(clip);
        }

        /// <summary>
        /// Called by the driver when it plays a state anim (peek, revive,
        /// engaged run): the locomotion animator stays out of the way.
        /// </summary>
        public void TakeOverAnimation() { _animTakeover = true; }

        public void SetAim(float weight, float yaw, float pitch)
        {
            Anim.SetAim(weight, yaw, pitch, false);
        }

        // ------------------------------------------------------------------ frame
        private void Update()
        {
            if (_dead) return;
            float dt = Time.deltaTime;

            if (_downed)
            {
                DownedTick(dt);
                return;
            }

            // Timers.
            if (_stunT > 0f) _stunT -= dt;
            if (_jamT > 0f) { _jamT -= dt; if (_jamT <= 0f) _jammed = false; }
            if (_slowT > 0f) { _slowT -= dt; if (_slowT <= 0f) SpeedMultiplier = 1f; }
            if (_markedT > 0f) _markedT -= dt;
            if (_invisibleT > 0f) _invisibleT -= dt;
            if (_fireT > 0f) { _fireT -= dt; if (_fireT <= 0f) _wasFiring = false; }
            if (_flashT > 0f)
            {
                _flashT -= dt;
                if (_flashT <= 0f && _muzzleFlash != null) _muzzleFlash.SetActive(false);
            }

            // Far LOD: settle only (saves CPU at world scale); anim holds pose.
            if (_farLod)
            {
                ApplyGravity(dt);
                _cc.Move(_vel * dt);
                return;
            }

            _moveDir = Vector3.zero;
            _moveSpeed = 0f;
            _animTakeover = false;
            if (Driver != null) Driver.Drive(dt);

            bool stunned = IsStunned || IsJammed;
            Vector3 planar = stunned ? Vector3.zero : _moveDir * _moveSpeed * SpeedMultiplier;
            ApplyGravity(dt);
            _vel.x = planar.x;
            _vel.z = planar.z;
            _cc.Move(_vel * dt);

            // Fell through the world: snap home (set by SquadManager at spawn).
            if (transform.position.y < -6f && Squadman != null)
            {
                transform.position = Squadman.HomePosition(this) + Vector3.up * 0.5f;
                _vel = Vector3.zero;
            }

            AnimateLocomotion(stunned);
        }

        private void ApplyGravity(float dt)
        {
            if (_cc.isGrounded)
            {
                if (_vel.y < 0f) _vel.y = -0.5f;
            }
            else
            {
                _vel.y -= 22f * dt;
                // Buoyancy: spring toward the surface so bots swim.
                if (transform.position.y < 0.1f)
                {
                    float depth = -0.25f - transform.position.y;
                    float targetVy = Mathf.Clamp(depth * 9f, -2.5f, 3f);
                    _vel.y = Mathf.MoveTowards(_vel.y, targetVy, 28f * dt);
                }
            }
        }

        private void DownedTick(float dt)
        {
            _bleedT -= dt;
            _vel.x = 0f;
            _vel.z = 0f;
            ApplyGravity(dt);
            _cc.Move(_vel * dt);
            if (_bleedT <= 0f)
            {
                SkipDowned = true;
                Die(DamageCause.Bullet, false);
                SkipDowned = false;
            }
        }

        private void AnimateLocomotion(bool stunned)
        {
            if (_animTakeover) return; // driver owns the anim this frame
            float spd = new Vector2(_vel.x, _vel.z).magnitude;
            bool moving = spd > 0.4f && !stunned;
            if (moving)
            {
                float rate = spd / 2.6f;
                Anim.Play(spd > 4.5f ? SoldierClip.Run : SoldierClip.Walk, 0.25f, rate);
                Anim.SetAim(0f, 0f, 0f, false);
                _movingWas = true;
            }
            else if (_movingWas)
            {
                Anim.Play(SoldierClip.Idle, 0.3f);
                Anim.SetAim(0f, 0f, 0f, false);
                _movingWas = false;
            }
        }

        // ------------------------------------------------------------------ damage
        void IDamageable.TakeDamage(float amount, Vector3 from, DamageCause cause)
        {
            DamageBot(amount, from, cause, cause == DamageCause.Headshot, null);
        }

        /// <summary>
        /// Godot-faithful damage entry: amount, hit origin, cause, headshot flag,
        /// killer GameObject (for killfeed attribution).
        /// </summary>
        public void DamageBot(float amount, Vector3 fromPos, DamageCause cause,
            bool headshot, GameObject killerGo)
        {
            if (_dead) return;
            if (killerGo != null) LastKiller = killerGo;
            Hp -= amount;

            // Getting shot: inform the brain (cover break) for bullet hits.
            if (cause == DamageCause.Bullet && fromPos != Vector3.zero)
            {
                var brain = Driver as BotBrain;
                if (brain != null) brain.NotifyHurt(fromPos);
            }

            Vector3 toHit = fromPos - transform.position;
            if (toHit.sqrMagnitude > 0.0001f)
            {
                // PlayHit wants direction FROM victim TOWARD the source.
                Rig.PlayHit(toHit.normalized);
            }

            if (Hp <= 0f)
            {
                if (!SkipDowned && Squadman != null && Squadman.HasLivingMate(this))
                    GoDowned();
                else
                    Die(cause, headshot);
            }
        }

        private void GoDowned()
        {
            _downed = true;
            _bleedT = 30f; // downed-not-dead bleed-out window
            Anim.Play(SoldierClip.ProneIdle, 0.3f);
            Anim.SetAim(0f, 0f, 0f, false);
            if (Squadman != null) Squadman.OnCombatantDown(this);
            if (Downed != null) Downed(this);
            SquadManager.RadioBark(Callsign, BotNames.BarkDowned);
        }

        /// <summary>Revive from downed with partial health (5s channel completed).</summary>
        public void ReviveAlly()
        {
            if (_dead || !_downed) return;
            _downed = false;
            Hp = MaxHp * (IsTeammate ? 0.5f : 0.4f);
            Rig.Revive();
            BotNameplate.SetVisible(this, true);
            Anim.Play(SoldierClip.Idle, 0.2f);
            Anim.SetAim(0f, 0f, 0f, false);
        }

        public void Die(DamageCause cause, bool headshot)
        {
            if (_dead) return;
            _dead = true;
            _downed = false;
            EnemyRegistry.Unregister(gameObject);
            BotNameplate.SetVisible(this, false); // plate drops with the body
            Vector3 hitDir = Vector3.zero;
            if (LastKiller != null)
                hitDir = (LastKiller.transform.position - transform.position).normalized;
            Rig.Die(headshot ? DamageCause.Headshot : cause, hitDir);
            Rig.CorpseExpired += OnCorpseExpired;
            if (Squadman != null) Squadman.OnCombatantDead(this, cause, headshot);
            if (Died != null) Died(this);
        }

        private void OnCorpseExpired(SoldierRig rig)
        {
            rig.CorpseExpired -= OnCorpseExpired;
            gameObject.SetActive(false); // pooled corpse slot; SquadManager may reuse
        }

        /// <summary>
        /// CODM-style redeploy: drop a dead teammate back into the match at
        /// the given position with full health.
        /// </summary>
        public void Redeploy(Vector3 pos)
        {
            Rig.Revive();
            EnemyRegistry.Register(gameObject);
            transform.position = pos + Vector3.up * 0.6f;
            _vel = Vector3.zero;
            Hp = MaxHp;
            Armor = 0;
            _dead = false;
            _downed = false;
            LastKiller = null;
            SpeedMultiplier = 1f;
            _stunT = 0f;
            _jammed = false;
            _cc.enabled = true;
            gameObject.SetActive(true);
            BotNameplate.SetVisible(this, true);
            Anim.Play(SoldierClip.Idle, 0.1f);
            Anim.SetAim(0f, 0f, 0f, false);
        }

        private void OnDestroy()
        {
            EnemyRegistry.Unregister(gameObject);
            BotNameplate.Detach(this);
        }

        public string KillerName()
        {
            if (LastKiller == null) return "";
            var pa = LastKiller.GetComponent<BotAgent>();
            if (pa != null) return pa.Callsign;
            if (LastKiller.CompareTag("Player")) return "YOU";
            return "HOSTILE";
        }

        // ------------------------------------------------------------------ IClassBody
        float IClassBody.Hp { get { return Hp; } set { Hp = value; } }
        float IClassBody.MaxHp { get { return MaxHp; } }
        int IClassBody.Armor { get { return Armor; } set { Armor = value; } }
        int IClassBody.MaxArmor { get { return MaxArmor; } }
        bool IClassBody.IsAlive { get { return !_dead; } }
        bool IDamageable.IsAlive { get { return !_dead; } }
        bool IClassBody.IsPlayer { get { return false; } }
        bool IClassBody.IsSprinting
        {
            get { return new Vector2(_vel.x, _vel.z).magnitude > 4.5f; }
        }
        bool IClassBody.IsGrounded { get { return _cc != null && _cc.isGrounded; } }
        float IClassBody.InvisibleTime
        {
            get { return _invisibleT; } set { _invisibleT = value; }
        }
        bool IClassBody.WasFiring { get { return _wasFiring; } }
        Vector3 IClassBody.Velocity
        {
            get { return _vel; }
            set { _vel.x = value.x; _vel.z = value.z; if (value.y > _vel.y) _vel.y = value.y; }
        }
        public float SpeedMultiplier { get; set; } = 1f;
        bool IClassBody.Gliding { get { return _gliding; } set { _gliding = value; } }

        Vector3 IClassBody.AimTarget(float maxDist)
        {
            return transform.position + transform.forward * maxDist;
        }

        void IClassBody.SetGliding(bool gliding) { _gliding = gliding; }
        void IClassBody.CleanseSlow() { _slowT = 0f; SpeedMultiplier = 1f; }
        void IClassBody.AddArmor(int amount)
        {
            Armor = Mathf.Min(MaxArmor, Armor + amount);
        }
        void IClassBody.AddAmmo(int amount) { /* bots use hitscan: no ammo economy */ }

        // ------------------------------------------------------------------ ITargetable
        int ITargetable.SquadId { get { return SquadId; } }
        string ITargetable.Callsign { get { return Callsign; } }
        Vector3 ITargetable.AimPosition
        {
            get { return transform.position + Vector3.up * 1.2f; }
        }

        IClassBody ITargetable.Body { get { return this; } }

        // ------------------------------------------------------------------ ability interfaces
        void ISlowable.ApplySlow(float factor, float duration)
        {
            SpeedMultiplier = _slowT > 0f ? Mathf.Min(SpeedMultiplier, factor) : factor;
            _slowT = Mathf.Max(_slowT, duration);
        }

        void IStunnable.Stun(float duration) { _stunT = Mathf.Max(_stunT, duration); }

        void IJammable.SetJammed(bool jammed, float duration)
        {
            _jammed = jammed;
            _jamT = Mathf.Max(_jamT, duration);
        }

        void ISuppressable.SuppressFire(float duration)
        {
            _jammed = true; // suppresses outgoing gunfire
            _jamT = Mathf.Max(_jamT, duration);
        }

        void IInvestigator.Investigate(Vector3 position, float duration)
        {
            if (Driver != null) Driver.Investigate(position, duration);
        }

        void IMarkable.SetMarked(float duration) { _markedT = Mathf.Max(_markedT, duration); }

        void IKnockbackable.Knockback(Vector3 impulse) { _vel += impulse; }
        void ILaunchable.Launch(Vector3 velocity) { _vel = velocity; }
    }
}
