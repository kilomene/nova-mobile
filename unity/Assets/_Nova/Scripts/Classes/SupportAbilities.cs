using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    // ==================================================================
    // SUPPORT profession
    // ==================================================================

    /// <summary>Trauma Station: heals 12 HP/s in 6m for 12s, cleanses, overheals to temp HP.</summary>
    public class SurgeonAbility : ClassAbility
    {
        public override string ClassId => "surgeon";
        public override float Cooldown => ClassData.Get("surgeon").Cooldown * CooldownMultiplier;

        private Vector3 _stationPos;
        private float _stationT;

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
            _stationPos = GroundSnap(transform.position);
            _stationT = 12f;
            var node = ClassFx.DeployBase(_stationPos, Accent, 0.5f, 1f);
            ClassFx.DestroyAfter(node, 12f);
            ClassFx.Dome(_stationPos, 6f, 12f, new Color(0.25f, 0.85f, 0.45f, 0.14f));
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_stationT <= 0f) return;
            _stationT -= dt;
            if (!OwnerAlive || Body == null) return;
            if ((transform.position - _stationPos).sqrMagnitude > 6f * 6f) return;
            Body.CleanseSlow();
            float heal = ApplyHealing(12f * dt);
            float newHp = Mathf.Min(Body.Hp + heal, Body.MaxHp + 25f);
            Body.Hp = newHp;
            if (newHp > Body.MaxHp)
                _tempHp = Mathf.Min(_tempHp + 4f * dt, 25f);
        }

        protected override float HealingMult() => base.HealingMult() * 1.5f;
    }

    /// <summary>Supply Drop: 3 shareable packs (2x +50 armor, 1x +60 ammo).</summary>
    public class QuartermasterAbility : ClassAbility
    {
        public override string ClassId => "quartermaster";
        public override float Cooldown => ClassData.Get("quartermaster").Cooldown * CooldownMultiplier;
        protected override float CooldownMultiplier => 0.8f;

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
            for (int i = 0; i < 3; i++)
            {
                Vector3 off = new Vector3(
                    NovaUtils.Range(-2.5f, 2.5f), 0f, NovaUtils.Range(-2.5f, 2.5f));
                Vector3 pos = GroundSnap(transform.position + off) + Vector3.up * 0.55f;
                bool armorPack = i < 2;
                SupplyPack.Spawn(pos, armorPack, armorPack ? 50 : 60);
            }
            ClassFx.GroundRing(transform.position, 3f, 1f, Accent);
            return true;
        }

        public override int BonusGrenadeCapacity() => 1;
        public override float AmmoPickupMult() => 1.5f;
    }

    /// <summary>Shareable supply pack: proximity pickup granting armor or ammo.</summary>
    public class SupplyPack : MonoBehaviour
    {
        public bool IsArmorPack = true;
        public int Amount = 50;
        private float _life = 60f;
        private float _pulseT;
        private static readonly Collider[] OverlapBuf = new Collider[16];

        public static SupplyPack Spawn(Vector3 pos, bool armorPack, int amount)
        {
            var go = new GameObject(armorPack ? "ArmorPack" : "AmmoPack");
            go.transform.position = pos;
            var box = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Object.Destroy(box.GetComponent<Collider>());
            box.transform.SetParent(go.transform, false);
            box.transform.localScale = new Vector3(0.6f, 0.4f, 0.6f);
            var mat = new Material(Shader.Find("Unlit/Color"))
            {
                color = armorPack ? new Color(0.3f, 0.6f, 1f) : new Color(1f, 0.8f, 0.2f)
            };
            box.GetComponent<Renderer>().sharedMaterial = mat;
            var pack = go.AddComponent<SupplyPack>();
            pack.IsArmorPack = armorPack;
            pack.Amount = amount;
            var trigger = go.AddComponent<SphereCollider>();
            trigger.isTrigger = true;
            trigger.radius = 1.6f;
            return pack;
        }

        private void Update()
        {
            _life -= Time.deltaTime;
            if (_life <= 0f) { Destroy(gameObject); return; }
            _pulseT -= Time.deltaTime;
            if (_pulseT <= 0f)
            {
                _pulseT = 0.5f;
                // Pickup check without trigger callbacks (works even if the other
                // body has no Rigidbody): scan for nearby IClassBody.
                int n = Physics.OverlapSphereNonAlloc(transform.position, 1.6f, OverlapBuf,
                    Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
                for (int i = 0; i < n; i++)
                {
                    var body = OverlapBuf[i].GetComponentInParent<IClassBody>();
                    if (body == null || !body.IsAlive || !body.IsPlayer) continue;
                    if (IsArmorPack) body.AddArmor(Amount);
                    else body.AddAmmo(Amount);
                    Destroy(gameObject);
                    return;
                }
            }
        }
    }

    /// <summary>Kinetic Dome: 5m / 10s, -50% bullet damage for the owner inside.</summary>
    public class AegisAbility : ClassAbility
    {
        public override string ClassId => "aegis";
        public override float Cooldown => ClassData.Get("aegis").Cooldown * CooldownMultiplier;

        private Vector3 _domePos;
        private float _domeT;

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
            _domePos = transform.position;
            _domeT = 10f;
            ClassFx.Dome(_domePos, 5f, 10f, new Color(0.3f, 0.7f, 1f, 0.22f));
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_domeT > 0f) _domeT -= dt;
        }

        public override void ApplyPassive()
        {
            if (Body != null && IsPlayer)
                Body.Armor = Mathf.Min(Body.Armor + 50, Body.MaxArmor);
        }

        protected override float IncomingDamageMult(DamageCause cause)
        {
            float m = base.IncomingDamageMult(cause);
            if (cause == DamageCause.Bullet && _domeT > 0f &&
                (transform.position - _domePos).sqrMagnitude <= 25f)
                m *= 0.5f;
            return m;
        }
    }

    /// <summary>Guardian Drone: orbits 15s, zaps nearest enemy in 30m every 1.2s.</summary>
    public class PhoenixAbility : ClassAbility
    {
        public override string ClassId => "phoenix";
        public override float Cooldown => ClassData.Get("phoenix").Cooldown * CooldownMultiplier;

        private float _guardT;
        private float _guardCd;
        private bool _reviveUsed;

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
            _guardT = 15f;
            _guardCd = 0f;
            var vis = ClassFx.DeployBase(transform.position + new Vector3(0f, 2.2f, 0f), Accent, 0.25f, 0.3f);
            ClassFx.DestroyAfter(vis, 15f);
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_guardT <= 0f) return;
            _guardT -= dt;
            _guardCd -= dt;
            if (_guardCd > 0f) return;
            _guardCd = 1.2f;
            GameObject tgt = NearestHostile(transform.position, 30f);
            if (tgt == null) return;
            var d = tgt.GetComponent<IDamageable>();
            if (d != null && d.IsAlive)
            {
                d.TakeDamage(ApplyOutgoingDamage(12f, DamageCause.Bullet),
                    tgt.transform.position, DamageCause.Bullet);
                OnDamagedEnemy(tgt);
            }
            ClassFx.Beam(transform.position + new Vector3(0f, 2.2f, 0f),
                tgt.transform.position + new Vector3(0f, 1.2f, 0f), 0.25f, Accent, 0.04f);
        }

        public override bool TrySurviveLethal()
        {
            if (!IsPlayer || _reviveUsed || Body == null) return false;
            _reviveUsed = true;
            Body.Hp = 50f;
            ClassFx.GroundRing(transform.position, 3f, 1.2f, new Color(0.25f, 0.85f, 0.45f));
            return true;
        }
    }

    /// <summary>Tactical Mirror: duplicates the 3 nearest loot pickups in 12m.</summary>
    public class ReplicatorAbility : ClassAbility
    {
        public override string ClassId => "replicator";
        public override float Cooldown => ClassData.Get("replicator").Cooldown * CooldownMultiplier;

        /// <summary>
        /// Wired by the Loot system to spawn a real duplicate pickup.
        /// Fallback (no subscriber): the source pickup is re-armed in place.
        /// </summary>
        public static event System.Action<ILootPickup, Vector3> RequestDuplicateLoot;

        private readonly List<ILootPickup> _lootScratch = new List<ILootPickup>(8);

        public override bool TryActivate()
        {
            if (TryRetrigger()) return true;
            if (!CanActivate()) return false;
            if (!DoActivate()) return false;
            // Intent: instantly halve the remaining cooldown. Activation requires a
            // ready skill, so apply the half to the fresh cooldown (the Godot code
            // subtracted from the pre-activation leftover, which was always ~0).
            OnActivated(0.5f);
            return true;
        }

        protected override bool DoActivate()
        {
            LootPickupRegistry.Query(transform.position, 12f, _lootScratch);
            // Nearest 3 (insertion sort over a tiny list — no allocs).
            int n = Mathf.Min(3, _lootScratch.Count);
            for (int k = 0; k < n; k++)
            {
                int best = k;
                float bd = float.MaxValue;
                for (int i = k; i < _lootScratch.Count; i++)
                {
                    float d = (_lootScratch[i].gameObject.transform.position - transform.position).sqrMagnitude;
                    if (d < bd) { bd = d; best = i; }
                }
                var tmp = _lootScratch[k];
                _lootScratch[k] = _lootScratch[best];
                _lootScratch[best] = tmp;
            }
            for (int i = 0; i < n; i++)
            {
                var src = _lootScratch[i];
                Vector3 pos = src.gameObject.transform.position +
                    new Vector3(NovaUtils.Range(-1.5f, 1.5f), 0.2f, NovaUtils.Range(-1.5f, 1.5f));
                RequestDuplicateLoot?.Invoke(src, pos);
            }
            ClassFx.GroundRing(transform.position, 4f, 1f, Accent);
            return true;
        }

        public override float AmmoPickupMult() => 1.25f;
        public override float LootTierUpChance() => 0.2f;
    }
}
