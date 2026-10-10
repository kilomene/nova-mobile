using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    // ==================================================================
    // DEFENSE profession
    // ==================================================================

    /// <summary>Aegis Wall: 3m ballistic wall (120 HP); re-trigger picks it back up.</summary>
    public class RampartAbility : ClassAbility
    {
        public override string ClassId => "rampart";
        public override float Cooldown => ClassData.Get("rampart").Cooldown * CooldownMultiplier;

        private GameObject _wall;

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            OnActivated();
            return true;
        }

        protected override bool TryRetrigger()
        {
            if (_wall == null) return false;
            Destroy(_wall);
            _wall = null;
            CooldownLeft = Cooldown * 0.5f; // pick-up refunds half the cooldown
            return true;
        }

        protected override bool DoActivate()
        {
            Vector3 fwd = transform.forward;
            fwd.y = 0f;
            fwd = fwd.sqrMagnitude > 0.001f ? fwd.normalized : Vector3.forward;
            Vector3 pos = GroundSnap(transform.position + fwd * 2.5f);

            _wall = new GameObject("AegisWall");
            _wall.transform.position = pos;
            _wall.transform.LookAt(pos + fwd * 5f, Vector3.up);
            var mesh = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Object.Destroy(mesh.GetComponent<Collider>());
            mesh.transform.SetParent(_wall.transform, false);
            mesh.transform.localScale = new Vector3(3f, 2.2f, 0.25f);
            mesh.transform.localPosition = new Vector3(0f, 1.1f, 0f);
            var mat = new Material(Shader.Find("Standard")) { color = new Color(0.2f, 0.24f, 0.3f) };
            mat.SetFloat("_Metallic", 0.4f);
            mesh.GetComponent<Renderer>().sharedMaterial = mat;
            var col = _wall.AddComponent<BoxCollider>();
            col.center = new Vector3(0f, 1.1f, 0f);
            col.size = new Vector3(3f, 2.2f, 0.25f);
            var hp = _wall.AddComponent<DeployableHealth>();
            hp.Hp = 120f;
            hp.EnemyOwned = !IsPlayer;

            // Flashbang pulse on deploy: stun nearby enemies' gunfire.
            CombatHelper.QueryHostiles(this, pos, 10f, _scratch);
            for (int i = 0; i < _scratch.Count; i++)
            {
                var stun = _scratch[i].GetComponent<IStunnable>();
                if (stun != null) stun.Stun(4f);
            }
            ClassFx.GroundRing(pos, 3f, 0.8f, new Color(1f, 1f, 1f, 0.9f));
            return true;
        }

        protected override float IncomingDamageMult(DamageCause cause) =>
            base.IncomingDamageMult(cause) * (cause != DamageCause.Bullet ? 0.6f : 1f);
    }

    /// <summary>Sentry Turret: 100 HP, 60s, 12 dmg / 1.5s at nearest enemy in 30m.</summary>
    public class LastWordAbility : ClassAbility
    {
        public override string ClassId => "lastword";
        public override float Cooldown => ClassData.Get("lastword").Cooldown * CooldownMultiplier;

        private DeployableHealth _turret;
        private float _turretT;
        private float _turretCd;
        private bool _standUsed;

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
            var node = ClassFx.DeployBase(pos, Accent, 0.5f, 1f);
            _turret = node.AddComponent<DeployableHealth>();
            _turret.Hp = 100f;
            _turret.EnemyOwned = !IsPlayer;
            _turretT = 60f;
            _turretCd = 0.5f;
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_turret == null) return;
            _turretT -= dt;
            if (_turretT <= 0f) { Destroy(_turret.gameObject); _turret = null; return; }
            _turretCd -= dt;
            if (_turretCd > 0f) return;
            _turretCd = 1.5f;
            GameObject tgt = NearestHostile(_turret.transform.position, 30f);
            if (tgt == null) return;
            var d = tgt.GetComponent<IDamageable>();
            if (d != null && d.IsAlive)
            {
                d.TakeDamage(ApplyOutgoingDamage(12f, DamageCause.Bullet),
                    tgt.transform.position, DamageCause.Bullet);
                OnDamagedEnemy(tgt);
            }
            ClassFx.Beam(_turret.transform.position + new Vector3(0f, 1.2f, 0f),
                tgt.transform.position + new Vector3(0f, 1f, 0f), 0.2f,
                new Color(1f, 0.8f, 0.3f), 0.05f);
        }

        public override bool TrySurviveLethal()
        {
            if (!IsPlayer || _standUsed || Body == null) return false;
            _standUsed = true;
            Body.Hp = 25f;
            ClassFx.GroundRing(transform.position, 3f, 1.2f, new Color(0.3f, 0.6f, 1f));
            return true;
        }
    }

    /// <summary>Cluster Strike: laser designator, 2s later 5 strikes walk a 12m zone.</summary>
    public class OverlordAbility : ClassAbility
    {
        public override string ClassId => "overlord";
        public override float Cooldown => ClassData.Get("overlord").Cooldown * CooldownMultiplier;

        private Vector3 _strikePos;
        private float _strikeT = -1f;
        private int _strikeN;

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
            _strikePos = GroundSnap(AimPoint(45f));
            _strikeT = 2f;
            _strikeN = 5;
            ClassFx.Beam(transform.position + new Vector3(0f, 1.5f, 0f),
                _strikePos + new Vector3(0f, 8f, 0f), 2f, new Color(1f, 0.2f, 0.2f), 0.06f);
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_strikeT < 0f) return;
            _strikeT -= dt;
            if (_strikeT > 0f) return;
            if (_strikeN <= 0) { _strikeT = -1f; return; }
            _strikeN--;
            _strikeT = 0.8f;
            Vector3 p = _strikePos + new Vector3(
                NovaUtils.Range(-6f, 6f), 0f, NovaUtils.Range(-6f, 6f));
            ClassFx.Explode(p, 4f);
            DamageHostiles(p, 5f, 30f, DamageCause.Explosion);
        }

        protected override float OutgoingDamageMult(DamageCause cause) =>
            base.OutgoingDamageMult(cause) * (cause == DamageCause.Explosion ? 1.15f : 1f);

        public override float LauncherReloadMult() => 1.5f;
    }

    /// <summary>Tar Bag: 6m pool (slow 60%, 6 dps); re-trigger detonates for 40.</summary>
    public class PyreAbility : ClassAbility
    {
        public override string ClassId => "pyre";
        public override float Cooldown => ClassData.Get("pyre").Cooldown * CooldownMultiplier;

        private Vector3 _tarPos;
        private float _tarT;
        private GameObject _tarNode;
        private float _dpsAccum;

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            OnActivated();
            return true;
        }

        protected override bool TryRetrigger()
        {
            if (_tarT <= 0f) return false;
            _tarT = 0f;
            if (_tarNode != null) Destroy(_tarNode);
            _tarNode = null;
            ClassFx.Explode(_tarPos, 4.5f);
            DamageHostiles(_tarPos, 6.5f, 40f, DamageCause.Explosion);
            CooldownLeft = Cooldown;
            return true;
        }

        protected override bool DoActivate()
        {
            Vector3 target = AimPoint(22f);
            Vector3 from = transform.position + Vector3.up * 1.4f;
            ThrowArc(from, target, 3f, 0.7f, land =>
            {
                _tarPos = GroundSnap(land);
                _tarT = 12f;
                _tarNode = ClassFx.Dome(_tarPos, 6f, 12f, new Color(0.12f, 0.1f, 0.08f, 0.55f));
            });
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_tarT <= 0f) return;
            _tarT -= dt;
            if (_tarT <= 0f)
            {
                if (_tarNode != null) Destroy(_tarNode);
                _tarNode = null;
                return;
            }
            _dpsAccum += dt;
            bool damageTick = _dpsAccum >= 0.5f;
            if (damageTick) _dpsAccum -= 0.5f;
            CombatHelper.QueryHostiles(this, _tarPos, 6f, _scratch);
            for (int i = 0; i < _scratch.Count; i++)
            {
                var slow = _scratch[i].GetComponent<ISlowable>();
                if (slow != null) slow.ApplySlow(0.4f, 0.6f);
                if (damageTick)
                {
                    var d = _scratch[i].GetComponent<IDamageable>();
                    if (d != null && d.IsAlive)
                    {
                        d.TakeDamage(ApplyOutgoingDamage(3f, DamageCause.Explosion), _tarPos, DamageCause.Explosion);
                        OnDamagedEnemy(_scratch[i]);
                    }
                }
            }
        }

        protected override float OutgoingDamageMult(DamageCause cause) =>
            base.OutgoingDamageMult(cause) * (cause == DamageCause.Explosion ? 1.2f : 1f);
    }

    /// <summary>Radiation Zone: 7m / 15s, 10 dps ramping +5/s per linger-second. Owner immune.</summary>
    public class FalloutAbility : ClassAbility
    {
        public override string ClassId => "fallout";
        public override float Cooldown => ClassData.Get("fallout").Cooldown * CooldownMultiplier;

        private Vector3 _radPos;
        private float _radT;
        private readonly Dictionary<GameObject, float> _heat = new Dictionary<GameObject, float>();
        private readonly List<GameObject> _seen = new List<GameObject>(8);
        private readonly List<GameObject> _removeScratch = new List<GameObject>(8);
        private float _dpsAccum;

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
            _radPos = GroundSnap(transform.position);
            _radT = 15f;
            _heat.Clear();
            ClassFx.Dome(_radPos, 7f, 15f, new Color(0.4f, 1f, 0.3f, 0.16f));
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_radT <= 0f) return;
            _radT -= dt;
            _dpsAccum += dt;
            bool damageTick = _dpsAccum >= 0.5f;
            if (damageTick) _dpsAccum -= 0.5f;

            CombatHelper.QueryHostiles(this, _radPos, 7f, _seen);
            // Per-enemy linger heat (ramping dps); entries for leavers are dropped.
            _removeScratch.Clear();
            foreach (var kv in _heat)
                if (!_seen.Contains(kv.Key) || kv.Key == null) _removeScratch.Add(kv.Key);
            for (int i = 0; i < _removeScratch.Count; i++) _heat.Remove(_removeScratch[i]);

            for (int i = 0; i < _seen.Count; i++)
            {
                GameObject e = _seen[i];
                float heat = 0f;
                _heat.TryGetValue(e, out heat);
                heat += dt;
                _heat[e] = heat;
                if (!damageTick) continue;
                var d = e.GetComponent<IDamageable>();
                if (d == null || !d.IsAlive) continue;
                float dps = 10f + 5f * heat;
                d.TakeDamage(ApplyOutgoingDamage(dps * 0.5f, DamageCause.Zone), _radPos, DamageCause.Zone);
                OnDamagedEnemy(e);
            }
        }
    }
}
