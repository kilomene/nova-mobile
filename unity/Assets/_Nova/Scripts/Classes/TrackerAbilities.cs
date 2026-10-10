using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    // ==================================================================
    // TRACKER profession
    // ==================================================================

    /// <summary>Sensor Dart: thrown dart scans 30m on landing, marks enemies 8s.</summary>
    public class PathfinderAbility : ClassAbility
    {
        public override string ClassId => "pathfinder";
        public override float Cooldown => ClassData.Get("pathfinder").Cooldown * CooldownMultiplier;

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            OnActivated();
            return true;
        }

        protected override bool DoActivate()
        {
            Vector3 target = AimPoint(40f);
            Vector3 from = transform.position + Vector3.up * 1.4f;
            ThrowArc(from, target, 4f, 0.6f, land =>
            {
                ClassFx.GroundRing(land, 30f, 1.5f, new Color(1f, 0.72f, 0.15f, 0.7f));
                CombatHelper.QueryHostiles(this, land, 30f, _scratch);
                for (int i = 0; i < _scratch.Count; i++)
                    MarkEnemy(_scratch[i], 8f);
            });
            return true;
        }

        public override void OnDamagedEnemy(GameObject enemy)
        {
            if (!IsPlayer || enemy == null) return;
            MarkEnemy(enemy, 6f); // Bloodhound: damaged enemies stay marked 6s
        }

        public override float AdsSpeedMult() => 1.2f;
    }

    /// <summary>Cyber-Hound: deploys a fast melee companion for 20s.</summary>
    public class KennelmasterAbility : ClassAbility
    {
        public override string ClassId => "kennelmaster";
        public override float Cooldown => ClassData.Get("kennelmaster").Cooldown * CooldownMultiplier;

        private HoundCompanion _hound;

        public bool HoundActive => _hound != null;

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            OnActivated();
            return true;
        }

        protected override bool DoActivate()
        {
            var go = new GameObject("CyberHound");
            go.transform.position = transform.position + new Vector3(1.5f, 0.5f, 0f);
            var mi = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Object.Destroy(mi.GetComponent<Collider>());
            mi.transform.SetParent(go.transform, false);
            mi.transform.localScale = new Vector3(0.5f, 0.6f, 1.1f);
            mi.transform.localPosition = new Vector3(0f, 0.45f, 0f);
            var mat = new Material(Shader.Find("Standard")) { color = new Color(0.15f, 0.16f, 0.18f) };
            mat.SetColor("_EmissionColor", new Color(1f, 0.4f, 0.1f));
            mat.EnableKeyword("_EMISSION");
            mi.GetComponent<Renderer>().sharedMaterial = mat;
            _hound = go.AddComponent<HoundCompanion>();
            _hound.Owner = this;
            _hound.Life = 20f;
            _hound.Hp = 30f;
            return true;
        }

        protected override void Tick(float dt)
        {
            // Destroyed hounds read as null via Unity's == overload; nothing to do.
            // Pheromone Field reads _hound through NoticeRangeMult.
        }

        public override float NoticeRangeMult() =>
            (_hound != null ? 0.8f : 1f);
    }

    /// <summary>Cyber-hound companion: chases nearest enemy, bites 8 dmg / 0.8s.</summary>
    public class HoundCompanion : MonoBehaviour, IDamageable
    {
        public KennelmasterAbility Owner;
        public float Life = 20f;
        public float Hp = 30f;
        public bool IsAlive => Hp > 0f && Life > 0f;

        private float _biteCd;
        private readonly List<GameObject> _scratch = new List<GameObject>(8);

        public void TakeDamage(float amount, Vector3 fromPosition, DamageCause cause)
        {
            Hp -= amount;
            if (Hp <= 0f) Destroy(gameObject);
        }

        private void Update()
        {
            float dt = Time.deltaTime;
            Life -= dt;
            if (Life <= 0f || Hp <= 0f) { Destroy(gameObject); return; }
            if (Owner == null) { Destroy(gameObject); return; }

            Vector3 ownerPos = Owner.transform.position;
            CombatHelper.QueryHostiles(Owner, transform.position, 40f, _scratch);
            GameObject best = null;
            float bd = float.MaxValue;
            for (int i = 0; i < _scratch.Count; i++)
            {
                float d = (_scratch[i].transform.position - transform.position).sqrMagnitude;
                if (d < bd) { bd = d; best = _scratch[i]; }
            }

            Vector3 move = Vector3.zero;
            if (best == null)
            {
                Vector3 to = ownerPos - transform.position;
                to.y = 0f;
                if (to.magnitude > 3f) move = to.normalized * 7f;
            }
            else
            {
                Vector3 to = best.transform.position - transform.position;
                to.y = 0f;
                if (to.magnitude > 1.2f)
                {
                    move = to.normalized * 8.5f;
                }
                else
                {
                    _biteCd -= dt;
                    if (_biteCd <= 0f)
                    {
                        _biteCd = 0.8f;
                        var d = best.GetComponent<IDamageable>();
                        if (d != null && d.IsAlive)
                        {
                            d.TakeDamage(Owner.ApplyOutgoingDamage(8f, DamageCause.Melee),
                                best.transform.position, DamageCause.Melee);
                            Owner.OnDamagedEnemy(best);
                        }
                    }
                }
            }
            move.y = -9f;
            transform.position += move * dt;
            if (move.sqrMagnitude > 0.01f)
                transform.rotation = Quaternion.LookRotation(new Vector3(move.x, 0f, move.z));
        }

    }

    /// <summary>EMP Drone: seeks nearest enemy, pulses slow + fire-suppress for 15s.</summary>
    public class SaboteurAbility : ClassAbility
    {
        public override string ClassId => "saboteur";
        public override float Cooldown => ClassData.Get("saboteur").Cooldown * CooldownMultiplier;

        private GameObject _drone;
        private float _droneT;
        private float _pulseT;
        private float _sightT;
        private readonly List<GameObject> _deployScratch = new List<GameObject>(8);

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            OnActivated();
            return true;
        }

        protected override bool DoActivate()
        {
            _drone = ClassFx.DeployBase(transform.position + new Vector3(0f, 2f, 0f), Accent, 0.3f, 0.4f);
            _droneT = 15f;
            _pulseT = 0f;
            return true;
        }

        protected override void Tick(float dt)
        {
            // Engineer Sight: enemy deployables glow red through walls.
            _sightT -= dt;
            if (_sightT <= 0f && IsPlayer)
            {
                _sightT = 2f;
                DeployableRegistry.Query(transform.position, 30f, _deployScratch, true);
                for (int i = 0; i < _deployScratch.Count; i++)
                    ClassFx.Marker(_deployScratch[i].transform, 2f, new Color(1f, 0.2f, 0.2f));
            }

            if (_drone == null) return;
            _droneT -= dt;
            if (_droneT <= 0f) { Destroy(_drone); _drone = null; return; }

            GameObject best = NearestHostile(_drone.transform.position, 45f);
            if (best != null)
            {
                Vector3 want = best.transform.position + new Vector3(0f, 3f, 0f);
                _drone.transform.position = Vector3.Lerp(_drone.transform.position, want, 2f * dt);
            }
            _pulseT -= dt;
            if (_pulseT <= 0f)
            {
                _pulseT = 3f;
                ClassFx.GroundRing(_drone.transform.position, 12f, 0.8f, new Color(0.4f, 0.8f, 1f, 0.6f));
                CombatHelper.QueryHostiles(this, _drone.transform.position, 12f, _scratch);
                for (int i = 0; i < _scratch.Count; i++)
                {
                    var slow = _scratch[i].GetComponent<ISlowable>();
                    if (slow != null) slow.ApplySlow(0.5f, 3f);
                    var sup = _scratch[i].GetComponent<ISuppressable>();
                    if (sup != null) sup.SuppressFire(2f);
                }
            }
        }
    }

    /// <summary>Catapult Pad: drop a pad; stepping on it launches you 25m skyward.</summary>
    public class SkyhookAbility : ClassAbility
    {
        public override string ClassId => "skyhook";
        public override float Cooldown => ClassData.Get("skyhook").Cooldown * CooldownMultiplier;

        private readonly List<PadEntry> _pads = new List<PadEntry>(2);

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            OnActivated();
            return true;
        }

        protected override bool DoActivate()
        {
            var pad = ClassFx.DeployBase(transform.position, Accent, 0.9f, 0.25f);
            ClassFx.DestroyAfter(pad, 25f);
            _pads.Add(new PadEntry { Node = pad, Pos = pad.transform.position, TimeLeft = 25f, Kind = 0 });
            return true;
        }

        protected override void Tick(float dt)
        {
            for (int i = _pads.Count - 1; i >= 0; i--)
            {
                var p = _pads[i];
                p.TimeLeft -= dt;
                if (p.TimeLeft <= 0f || p.Node == null)
                {
                    if (p.Node != null) Destroy(p.Node);
                    _pads.RemoveAt(i);
                    continue;
                }
                if (OwnerAlive && Body != null && !Body.Gliding &&
                    (transform.position - p.Pos).sqrMagnitude < 1.8f * 1.8f)
                {
                    Vector3 fwd = transform.forward;
                    fwd.y = 0f;
                    fwd = fwd.sqrMagnitude > 0.001f ? fwd.normalized : Vector3.forward;
                    Body.Velocity = fwd * 10f + Vector3.up * 17f;
                    Body.SetGliding(true);
                    Destroy(p.Node);
                    _pads.RemoveAt(i);
                }
                else _pads[i] = p;
            }
        }
    }

    /// <summary>Smart Mortar: 6 guided shells over ~8s at the nearest enemy in 45m.</summary>
    public class BallistaAbility : ClassAbility
    {
        public override string ClassId => "ballista";
        public override float Cooldown => ClassData.Get("ballista").Cooldown * CooldownMultiplier;

        private MortarDeployable _mortar;
        private float _shellT;
        private float _durT;
        private int _shells;

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            OnActivated();
            return true;
        }

        protected override bool DoActivate()
        {
            Vector3 pos = GroundSnap(transform.position + new Vector3(2f, 0f, 0f));
            var node = ClassFx.DeployBase(pos, Accent, 0.5f, 1.1f);
            _mortar = node.AddComponent<MortarDeployable>();
            _mortar.Hp = 60f;
            _mortar.EnemyOwned = !IsPlayer;
            _shells = 6;
            _shellT = 0.5f;
            _durT = 12f;
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_mortar == null) return;
            _durT -= dt;
            if (_durT <= 0f || _shells <= 0)
            {
                if (_mortar != null) Destroy(_mortar.gameObject);
                _mortar = null;
                return;
            }
            _shellT -= dt;
            if (_shellT > 0f) return;
            _shellT = 1.3f;
            GameObject tgt = NearestHostile(_mortar.transform.position, 45f);
            if (tgt == null) return;
            _shells--;
            Vector3 from = _mortar.transform.position + Vector3.up;
            Vector3 dest = tgt.transform.position;
            ThrowArc(from, dest, 10f, 0.9f, land =>
            {
                ClassFx.Explode(land, 3f);
                DamageHostiles(land, 3.5f, 25f, DamageCause.Explosion);
            });
        }

        protected override float OutgoingDamageMult(DamageCause cause) =>
            cause == DamageCause.Explosion ? 1.25f : 1f;
    }

    /// <summary>Destroyable deployable with HP (mortar 60, turret 100, wall 120).</summary>
    public class DeployableHealth : MonoBehaviour, IDamageable
    {
        public float Hp = 60f;
        /// <summary>True when owned by an enemy of the player (for Engineer Sight).</summary>
        public bool EnemyOwned;
        public bool IsAlive => Hp > 0f && this != null;

        public void TakeDamage(float amount, Vector3 fromPosition, DamageCause cause)
        {
            Hp -= amount;
            if (Hp <= 0f)
            {
                DeployableRegistry.Unregister(gameObject);
                Destroy(gameObject);
            }
        }

        protected virtual void OnEnable() => DeployableRegistry.Register(gameObject);
        protected virtual void OnDisable() => DeployableRegistry.Unregister(gameObject);
    }

    public class MortarDeployable : DeployableHealth {}
}
