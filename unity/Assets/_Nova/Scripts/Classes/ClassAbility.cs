using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    // ------------------------------------------------------------------
    // Interfaces the Classes system expects other systems to implement.
    // Player/enemy code calls the ClassAbility hooks; ability code calls
    // these interfaces with null-checks and degrades gracefully.
    // ------------------------------------------------------------------

    /// <summary>
    /// The body an ability is attached to (player or bot). Implemented by the
    /// Player / Soldiers systems on the same GameObject as the ClassAbility.
    /// </summary>
    public interface IClassBody
    {
        float Hp { get; set; }
        float MaxHp { get; }
        int Armor { get; set; }
        int MaxArmor { get; }
        bool IsAlive { get; }
        bool IsPlayer { get; }
        bool IsSprinting { get; }
        bool IsGrounded { get; }
        bool Gliding { get; set; }
        /// <summary>Seconds of invisibility remaining (active camo / decoy shroud).</summary>
        float InvisibleTime { get; set; }
        /// <summary>Set by weapon code every frame the owner fires.</summary>
        bool WasFiring { get; }
        Vector3 Velocity { get; set; }
        /// <summary>Final movement multiplier consumed by the movement code.</summary>
        float SpeedMultiplier { get; set; }
        /// <summary>Where the owner is aiming, up to maxDist (camera raycast for players).</summary>
        Vector3 AimTarget(float maxDist);
        void SetGliding(bool gliding);
        void CleanseSlow();
        void AddArmor(int amount);
        void AddAmmo(int amount);
    }

    /// <summary>Anything that can take ability damage: use Core.IDamageable.</summary>

    public interface ISlowable { void ApplySlow(float factor, float duration); }
    public interface IStunnable { void Stun(float duration); }
    /// <summary>Suppresses outgoing gunfire for a duration (EMP / shockwave).</summary>
    public interface ISuppressable { void SuppressFire(float duration); }
    public interface IInvestigator { void Investigate(Vector3 position, float duration); }
    public interface IJammable { void SetJammed(bool jammed, float duration); }
    public interface IMarkable { void SetMarked(float duration); }
    public interface IKnockbackable { void Knockback(Vector3 impulse); }
    public interface ILaunchable { void Launch(Vector3 velocity); }

    /// <summary>Loot pickups the Replicator mirror can duplicate (Loot system registers).</summary>
    public interface ILootPickup
    {
        GameObject gameObject { get; }
        string Kind { get; }
        int Amount { get; }
        int Tier { get; }
    }

    // ------------------------------------------------------------------
    // Abstract base — exact contract shape from CONVENTIONS.md.
    // ------------------------------------------------------------------

    /// <summary>
    /// Base class for all 30 BR class abilities. Attach one per actor via
    /// <see cref="ClassAbilityRegistry.Attach"/>. Player/enemy code drives the
    /// active via <see cref="TryActivate"/> and routes damage/healing/movement
    /// through the Apply* hooks so profession + class passives stay correct.
    /// </summary>
    public abstract class ClassAbility : MonoBehaviour
    {
        // ---- contract (CONVENTIONS.md) ----
        public abstract string ClassId { get; }
        public abstract float Cooldown { get; }
        public abstract bool TryActivate();
        public virtual void ApplyPassive() {}

        // ---- identity / cooldown state ----
        public ClassSpec Spec => ClassData.Get(ClassId);
        public string Profession => _profession;
        public Color Accent => _accent;

        public float CooldownLeft { get; protected set; }
        public bool IsReady => CooldownLeft <= 0f;
        public float CooldownFrac =>
            Cooldown <= 0f ? 1f : Mathf.Clamp01(1f - CooldownLeft / Cooldown);

        /// <summary>Fired with CooldownFrac whenever the cooldown changes.</summary>
        public event Action<float> CooldownChanged;

        /// <summary>Passive cooldown multiplier (Overclock 0.75, Deep Pockets / Attuned 0.8).</summary>
        protected virtual float CooldownMultiplier => 1f;

        protected IClassBody Body;
        protected bool IsPlayer => Body != null && Body.IsPlayer;
        protected bool OwnerAlive => Body != null && Body.IsAlive;
        private string _profession = "";
        private Color _accent = Color.white;

        // ---- shared buff timers (set by concrete abilities) ----
        protected float _disruptT;    // disrupt profession: +15% speed after skill
        protected float _overchargeT; // volt shock rounds: +30% outgoing damage
        protected float _deflectT;    // ronin bullet deflect window
        protected float _wraithDmgT;   // wraith ghost-rounds window
        protected float _tempHp;      // surgeon overheal buffer (decays 5/s)

        // Scratch buffer for hostile queries — reused, never allocated per frame.
        protected readonly List<GameObject> _scratch = new List<GameObject>(24);

        protected virtual void Awake()
        {
            Body = GetComponent<IClassBody>();
            var spec = ClassData.Get(ClassId);
            _profession = spec.Profession;
            _accent = spec.Accent;
        }

        protected virtual void Update()
        {
            float dt = Time.deltaTime;
            if (CooldownLeft > 0f)
            {
                CooldownLeft = Mathf.Max(0f, CooldownLeft - dt);
                CooldownChanged?.Invoke(CooldownFrac);
            }
            _disruptT = Mathf.Max(0f, _disruptT - dt);
            _overchargeT = Mathf.Max(0f, _overchargeT - dt);
            _deflectT = Mathf.Max(0f, _deflectT - dt);
            _wraithDmgT = Mathf.Max(0f, _wraithDmgT - dt);
            _tempHp = Mathf.Max(0f, _tempHp - 5f * dt);

            // Support profession: steady bonus regen (surgeon 10/s, others 6/s).
            if (IsPlayer && Profession == "support" && OwnerAlive && Body.Hp < Body.MaxHp)
            {
                float bonus = ClassId == "surgeon" ? 10f : 6f;
                Body.Hp = Mathf.Min(Body.Hp + bonus * dt, Body.MaxHp);
            }
            // Disrupt profession speed boost flows through SpeedMultiplier.
            if (IsPlayer && Body != null)
                Body.SpeedMultiplier = MoveSpeedMult();

            Tick(dt);
        }

        // ---- activation template ----
        // Concrete abilities implement TryActivate() via:
        //   if (TryRetrigger()) return true;
        //   if (!CanActivate()) return false;
        //   if (!DoActivate()) return false;
        //   OnActivated(); return true;

        protected virtual bool TryRetrigger() => false;
        protected abstract bool DoActivate();

        protected bool CanActivate()
        {
            return OwnerAlive && IsReady;
        }

        protected void OnActivated(float cooldownFrac = 1f)
        {
            if (Cooldown > 0f)
            {
                CooldownLeft = Cooldown * cooldownFrac;
                CooldownChanged?.Invoke(CooldownFrac);
            }
            if (Profession == "disrupt")
                _disruptT = 6f;
        }

        /// <summary>Per-frame ability logic. Timers only — no allocations.</summary>
        protected virtual void Tick(float dt) {}

        // ------------------------------------------------------------------
        // Passive hooks — called by player/enemy code.
        // ------------------------------------------------------------------

        /// <summary>
        /// Incoming-damage pipeline. Player/enemy code MUST call this before
        /// subtracting HP: dmg = ability.ApplyIncomingDamage(raw, cause).
        /// Handles profession resists, class resists, deflect, dome, temp-HP absorb.
        /// </summary>
        public float ApplyIncomingDamage(float amount, DamageCause cause)
        {
            float dmg = amount * IncomingDamageMult(cause);
            if (_tempHp > 0f && dmg > 0f)
            {
                float absorbed = Mathf.Min(_tempHp, dmg);
                _tempHp -= absorbed;
                dmg -= absorbed;
            }
            return dmg;
        }

        /// <summary>Multiplier applied to incoming damage (profession + class).</summary>
        protected virtual float IncomingDamageMult(DamageCause cause)
        {
            float m = 1f;
            if (Profession == "defense")
            {
                if (cause == DamageCause.Explosion) m *= 0.65f;
                if (cause == DamageCause.Zone) m *= 0.75f;
            }
            if (Profession == "stealth" && cause == DamageCause.Bullet
                && Body != null && Body.IsSprinting)
                m *= 0.85f;
            return m;
        }

        /// <summary>
        /// Lethal-blow save. Call pattern in player/enemy damage code:
        ///   float dmg = ability.ApplyIncomingDamage(raw, cause);
        ///   if (hp - dmg &lt;= 0 &amp;&amp; ability.TrySurviveLethal()) { /* hp already set */ }
        ///   else hp -= dmg;
        /// Returns true when a once-per-match save was consumed.
        /// </summary>
        public virtual bool TrySurviveLethal() => false;

        /// <summary>Healing pipeline: player code calls ability.ApplyHealing(raw).</summary>
        public float ApplyHealing(float amount) => amount * HealingMult();

        protected virtual float HealingMult()
        {
            return Profession == "support" ? 1.4f : 1f;
        }

        /// <summary>Outgoing-damage pipeline: player code calls ability.ApplyOutgoingDamage(raw, cause).</summary>
        public float ApplyOutgoingDamage(float amount, DamageCause cause) =>
            amount * OutgoingDamageMult(cause)
                   * (_overchargeT > 0f ? 1.3f : 1f)
                   * (_wraithDmgT > 0f ? 1.5f : 1f);

        protected virtual float OutgoingDamageMult(DamageCause cause) => 1f;

        /// <summary>Movement multiplier consumed by the movement code.</summary>
        public virtual float MoveSpeedMult()
        {
            float m = 1f;
            if (Profession == "tracker") m *= 1.1f;
            if (_disruptT > 0f) m *= 1.15f;
            return m;
        }

        /// <summary>Enemy notice-range multiplier (how much later enemies spot the owner).</summary>
        public virtual float NoticeRangeMult() =>
            Profession == "stealth" ? 0.7f : 1f;

        public virtual float AdsSpeedMult() => 1f;
        public virtual float JumpHeightMult() => 1f;
        public virtual float FallDamageMult() => 1f;
        /// <summary>+N grenade capacity (quartermaster).</summary>
        public virtual int BonusGrenadeCapacity() => 0;
        /// <summary>Ammo pickup multiplier (quartermaster 1.5, replicator 1.25).</summary>
        public virtual float AmmoPickupMult() => 1f;
        /// <summary>Chance a gun roll comes out a tier hotter (replicator 0.2).</summary>
        public virtual float LootTierUpChance() => 0f;
        /// <summary>+N% launcher reload speed as a multiplier (overlord 1.5).</summary>
        public virtual float LauncherReloadMult() => 1f;

        public virtual bool ImmuneToSlow => false;
        public virtual bool ImmuneToKnockback => false;
        public virtual bool ImmuneToJam => false;

        /// <summary>Called by player code whenever the owner damages an enemy.</summary>
        public virtual void OnDamagedEnemy(GameObject enemy)
        {
            if (!IsPlayer || enemy == null) return;
            if (Profession == "tracker")
                MarkEnemy(enemy, ClassId == "pathfinder" ? 6f : 5f);
        }

        // ------------------------------------------------------------------
        // Shared helpers for concrete abilities.
        // ------------------------------------------------------------------

        /// <summary>Attach a floating red diamond marker above an enemy for dur seconds.</summary>
        protected void MarkEnemy(GameObject enemy, float dur)
        {
            if (enemy == null) return;
            var markable = enemy.GetComponent<IMarkable>();
            if (markable != null) markable.SetMarked(dur);
            ClassFx.Marker(enemy.transform, dur, new Color(1f, 0.25f, 0.2f));
        }

        /// <summary>Damage every hostile in radius (no allocs beyond the scratch list).</summary>
        protected void DamageHostiles(Vector3 pos, float radius, float dmg, DamageCause cause)
        {
            CombatHelper.QueryHostiles(this, pos, radius, _scratch);
            for (int i = 0; i < _scratch.Count; i++)
            {
                var d = _scratch[i].GetComponent<IDamageable>();
                if (d != null && d.IsAlive)
                    d.TakeDamage(ApplyOutgoingDamage(dmg, cause), pos, cause);
            }
            OnDamagedAny(_scratch);
        }

        /// <summary>Nearest hostile within radius, or null.</summary>
        protected GameObject NearestHostile(Vector3 pos, float radius)
        {
            CombatHelper.QueryHostiles(this, pos, radius, _scratch);
            GameObject best = null;
            float bd = float.MaxValue;
            for (int i = 0; i < _scratch.Count; i++)
            {
                float d = (_scratch[i].transform.position - pos).sqrMagnitude;
                if (d < bd) { bd = d; best = _scratch[i]; }
            }
            return best;
        }

        private void OnDamagedAny(List<GameObject> targets)
        {
            if (!IsPlayer) return;
            for (int i = 0; i < targets.Count; i++)
                OnDamagedEnemy(targets[i]);
        }

        protected Vector3 AimPoint(float maxDist)
        {
            if (Body != null) return Body.AimTarget(maxDist);
            return transform.position + transform.forward * maxDist;
        }

        protected Vector3 GroundSnap(Vector3 p) => CombatHelper.GroundSnap(gameObject, p);

        protected void ThrowArc(Vector3 from, Vector3 to, float arcH, float duration, Action<Vector3> onLand) =>
            CombatHelper.ThrowArc(this, from, to, arcH, duration, onLand);
    }
}
