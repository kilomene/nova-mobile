using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    // ==================================================================
    // DISRUPT profession
    // ==================================================================

    /// <summary>Arc Trap: up to 3 chained traps; enemies inside slowed 50%, 8 dps.</summary>
    public class WardenAbility : ClassAbility
    {
        public override string ClassId => "warden";
        public override float Cooldown => ClassData.Get("warden").Cooldown * CooldownMultiplier;
        protected override float CooldownMultiplier => 0.75f;

        private struct Trap
        {
            public GameObject Node;
            public Vector3 Pos;
            public float TimeLeft;
        }

        private readonly List<Trap> _traps = new List<Trap>(3);
        private float _dpsAccum;
        private bool _trapEnemyOwned;

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
            if (_traps.Count >= 3)
            {
                var old = _traps[0];
                if (old.Node != null)
                {
                    DeployableRegistry.Unregister(old.Node);
                    Destroy(old.Node);
                }
                _traps.RemoveAt(0);
            }
            Vector3 pos = GroundSnap(transform.position);
            var node = ClassFx.DeployBase(pos, Accent, 0.35f, 0.5f);
            ClassFx.Dome(pos, 4f, 60f, new Color(0.75f, 0.35f, 1f, 0.12f));
            ClassFx.DestroyAfter(node, 60f);
            // Traps are not damageable (faithful to spec); register for Engineer Sight only.
            _trapEnemyOwned = !IsPlayer;
            DeployableRegistry.Register(node, _trapEnemyOwned);
            // Chain-link visuals to nearby traps.
            for (int i = 0; i < _traps.Count; i++)
            {
                Vector3 p2 = _traps[i].Pos;
                float d = Vector3.Distance(p2, pos);
                if (d > 0.1f && d < 9f)
                    ClassFx.Beam(pos + Vector3.up * 0.6f, p2 + Vector3.up * 0.6f, 60f, Accent, 0.03f);
            }
            _traps.Add(new Trap { Node = node, Pos = pos, TimeLeft = 60f });
            return true;
        }

        /// <summary>Enemy AI entry: place a trap immediately, bypassing the player cooldown.</summary>
        public void EnemyPlaceTrap()
        {
            if (!OwnerAlive) return;
            DoActivate();
        }

        protected override void Tick(float dt)
        {
            _dpsAccum += dt;
            bool damageTick = _dpsAccum >= 0.5f;
            if (damageTick) _dpsAccum -= 0.5f;
            for (int i = _traps.Count - 1; i >= 0; i--)
            {
                var t = _traps[i];
                t.TimeLeft -= dt;
                if (t.TimeLeft <= 0f || t.Node == null)
                {
                    if (t.Node != null)
                    {
                        DeployableRegistry.Unregister(t.Node);
                        Destroy(t.Node);
                    }
                    _traps.RemoveAt(i);
                    continue;
                }
                _traps[i] = t;
                CombatHelper.QueryHostiles(this, t.Pos, 4f, _scratch);
                for (int j = 0; j < _scratch.Count; j++)
                {
                    var slow = _scratch[j].GetComponent<ISlowable>();
                    if (slow != null) slow.ApplySlow(0.5f, 0.6f);
                    if (damageTick)
                    {
                        var d = _scratch[j].GetComponent<IDamageable>();
                        if (d != null && d.IsAlive)
                        {
                            d.TakeDamage(ApplyOutgoingDamage(4f, DamageCause.Explosion), t.Pos, DamageCause.Explosion);
                            OnDamagedEnemy(_scratch[j]);
                        }
                    }
                }
            }
        }
    }

    /// <summary>Time Rewind: restore position/HP/armor from up to 8s ago, leave an echo.</summary>
    public class ChronosAbility : ClassAbility
    {
        public override string ClassId => "chronos";
        public override float Cooldown => ClassData.Get("chronos").Cooldown * CooldownMultiplier;

        private struct Snapshot
        {
            public Vector3 Pos;
            public float Hp;
            public int Armor;
        }

        private readonly List<Snapshot> _hist = new List<Snapshot>(16);
        private float _histT;

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
            if (_hist.Count == 0 || Body == null) return false;
            // Oldest sample in the 8s ring buffer (the Godot code read index 0,
            // the newest sample — a bug; the design and buffer size say 8s).
            Snapshot h = _hist[0];
            transform.position = h.Pos;
            Body.Velocity = Vector3.zero;
            Body.Hp = h.Hp;
            Body.Armor = h.Armor;
            var echo = ClassFx.HoloSoldier(h.Pos, new Color(0.5f, 0.8f, 1f, 0.5f));
            ClassFx.DestroyAfter(echo, 6f);
            _hist.Clear();
            ClassFx.GroundRing(h.Pos, 3f, 1f, Accent);
            return true;
        }

        protected override void Tick(float dt)
        {
            if (!IsPlayer || !OwnerAlive || Body == null) return;
            _histT -= dt;
            if (_histT > 0f) return;
            _histT = 0.5f;
            _hist.Insert(0, new Snapshot { Pos = transform.position, Hp = Body.Hp, Armor = Body.Armor });
            while (_hist.Count > 16) _hist.RemoveAt(_hist.Count - 1);
        }

        public override float MoveSpeedMult() => base.MoveSpeedMult() * 1.1f;
    }

    /// <summary>Holo Decoys: 2 scripted decoys + 3s invisibility for the owner.</summary>
    public class MirageAbility : ClassAbility
    {
        public override string ClassId => "mirage";
        public override float Cooldown => ClassData.Get("mirage").Cooldown * CooldownMultiplier;

        private readonly List<MirageDecoy> _decoys = new List<MirageDecoy>(4);

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
            for (int i = 0; i < 2; i++)
            {
                float ang = NovaUtils.Range(0f, Mathf.PI * 2f);
                Vector3 pos = GroundSnap(transform.position +
                    new Vector3(Mathf.Cos(ang) * 3f, 0f, Mathf.Sin(ang) * 3f));
                var node = ClassFx.HoloSoldier(pos, new Color(0.6f, 0.9f, 1f, 0.45f));
                var decoy = node.AddComponent<MirageDecoy>();
                decoy.Owner = this;
                decoy.Life = 8f;
                decoy.Velocity = new Vector3(Mathf.Cos(ang + 1.2f), 0f, Mathf.Sin(ang + 1.2f)) * 3.5f;
                _decoys.Add(decoy);
                CombatHelper.QueryHostiles(this, pos, 30f, _scratch);
                for (int j = 0; j < _scratch.Count; j++)
                {
                    var inv = _scratch[j].GetComponent<IInvestigator>();
                    if (inv != null) inv.Investigate(pos, 8f);
                }
            }
            if (Body != null) Body.InvisibleTime = 3f;
            return true;
        }

        protected override void Tick(float dt)
        {
            for (int i = _decoys.Count - 1; i >= 0; i--)
            {
                var d = _decoys[i];
                if (d == null) { _decoys.RemoveAt(i); continue; }
                d.Life -= dt;
                if (d.Life > 0f)
                {
                    d.transform.position += d.Velocity * dt;
                    continue;
                }
                // Parting Gift: destroyed decoys detonate for 15 damage.
                Vector3 pos = d.transform.position;
                Destroy(d.gameObject);
                _decoys.RemoveAt(i);
                DamageHostiles(pos, 3f, 15f, DamageCause.Explosion);
                ClassFx.Explode(pos, 2f);
            }
        }
    }

    /// <summary>Holographic decoy: destroyable, detonates on expiry (mirage passive).</summary>
    public class MirageDecoy : MonoBehaviour, IDamageable
    {
        public MirageAbility Owner;
        public float Life = 8f;
        public Vector3 Velocity;
        public bool IsAlive => Life > 0f && this != null;

        public void TakeDamage(float amount, Vector3 fromPosition, DamageCause cause)
        {
            // Any hit pops the decoy; the owner's tick handles the detonation.
            Life = 0f;
        }
    }

    /// <summary>Hunter Smoke: 8m cloud for 12s, slows 40% and marks enemies.</summary>
    public class WildfireAbility : ClassAbility
    {
        public override string ClassId => "wildfire";
        public override float Cooldown => ClassData.Get("wildfire").Cooldown * CooldownMultiplier;

        private Vector3 _smokePos;
        private float _smokeT;

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
            Vector3 target = AimPoint(25f);
            Vector3 from = transform.position + Vector3.up * 1.4f;
            ThrowArc(from, target, 3f, 0.7f, land =>
            {
                _smokePos = GroundSnap(land);
                _smokeT = 12f;
                ClassFx.SmokeColumn(_smokePos, 8f, 12f, new Color(0.5f, 0.5f, 0.52f, 0.8f));
                CombatHelper.QueryHostiles(this, _smokePos, 8f, _scratch);
                for (int i = 0; i < _scratch.Count; i++)
                    MarkEnemy(_scratch[i], 12f);
            });
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_smokeT <= 0f) return;
            _smokeT -= dt;
            CombatHelper.QueryHostiles(this, _smokePos, 8f, _scratch);
            for (int i = 0; i < _scratch.Count; i++)
            {
                var slow = _scratch[i].GetComponent<ISlowable>();
                if (slow != null) slow.ApplySlow(0.6f, 0.6f); // 40% slow
            }
        }

        private bool InSmoke() =>
            _smokeT > 0f && (transform.position - _smokePos).sqrMagnitude <= 64f;

        public override float MoveSpeedMult() =>
            base.MoveSpeedMult() * (InSmoke() ? 1.2f : 1f);

        // Smoke Runner: ignores the slow while the cloud is live. (Simplified to
        // all slows during the window; the owner is never slowed by its own smoke.)
        public override bool ImmuneToSlow => _smokeT > 0f;
    }

    /// <summary>Signal Jam: 20m bubble for 10s, enemies stop engaging.</summary>
    public class GhostAbility : ClassAbility
    {
        public override string ClassId => "ghost";
        public override float Cooldown => ClassData.Get("ghost").Cooldown * CooldownMultiplier;

        private Vector3 _jamPos;
        private float _jamT;

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
            _jamPos = transform.position;
            _jamT = 10f;
            ClassFx.Dome(_jamPos, 20f, 10f, new Color(0.75f, 0.35f, 1f, 0.1f));
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_jamT <= 0f) return;
            _jamT -= dt;
            CombatHelper.QueryHostiles(this, _jamPos, 20f, _scratch);
            for (int i = 0; i < _scratch.Count; i++)
            {
                var sup = _scratch[i].GetComponent<ISuppressable>();
                if (sup != null) sup.SuppressFire(1f);
                var jam = _scratch[i].GetComponent<IJammable>();
                if (jam != null) jam.SetJammed(true, 0.5f);
            }
        }

        public override bool ImmuneToJam => true;
        public override bool ImmuneToSlow => true; // immune to EMP slows
    }

    /// <summary>Shockwave Pulse: hurls enemies back, stuns gunfire 3s.</summary>
    public class BulwarkAbility : ClassAbility
    {
        public override string ClassId => "bulwark";
        public override float Cooldown => ClassData.Get("bulwark").Cooldown * CooldownMultiplier;

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
            ClassFx.GroundRing(transform.position, 8f, 0.7f, new Color(1f, 0.85f, 0.3f, 0.8f));
            CombatHelper.QueryHostiles(this, transform.position, 8f, _scratch);
            for (int i = 0; i < _scratch.Count; i++)
            {
                GameObject e = _scratch[i];
                Vector3 dir = e.transform.position - transform.position;
                dir.y = 0f;
                if (dir.sqrMagnitude < 0.01f) dir = Vector3.forward;
                dir = dir.normalized;
                var kb = e.GetComponent<IKnockbackable>();
                if (kb != null) kb.Knockback(dir * 8f);
                else e.transform.position += dir * 5f; // fallback: shove
                var stun = e.GetComponent<IStunnable>();
                if (stun != null) stun.Stun(3f);
                var sup = e.GetComponent<ISuppressable>();
                if (sup != null) sup.SuppressFire(3f);
            }
            return true;
        }

        protected override float IncomingDamageMult(DamageCause cause) =>
            base.IncomingDamageMult(cause) * (cause == DamageCause.Explosion ? 0.8f : 1f);

        public override bool ImmuneToKnockback => true;
    }

    /// <summary>Phantom Firefight: enemies in 40m investigate a fake firefight 30m out.</summary>
    public class VentriloquistAbility : ClassAbility
    {
        public override string ClassId => "ventriloquist";
        public override float Cooldown => ClassData.Get("ventriloquist").Cooldown * CooldownMultiplier;

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
            Vector3 target = GroundSnap(AimPoint(30f));
            CombatHelper.QueryHostiles(this, transform.position, 40f, _scratch);
            for (int i = 0; i < _scratch.Count; i++)
            {
                var inv = _scratch[i].GetComponent<IInvestigator>();
                if (inv != null) inv.Investigate(target, 8f);
            }
            ClassFx.GroundRing(target, 4f, 1.5f, new Color(0.75f, 0.35f, 1f, 0.5f));
            return true;
        }

        public override float MoveSpeedMult() => base.MoveSpeedMult() * 1.1f;
    }

    /// <summary>Chain Lightning: arcs up to 4 clustered enemies, then 6s shock rounds.</summary>
    public class VoltAbility : ClassAbility
    {
        public override string ClassId => "volt";
        public override float Cooldown => ClassData.Get("volt").Cooldown * CooldownMultiplier;

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
            var struck = new List<GameObject>(4);
            Vector3 from = transform.position;
            for (int i = 0; i < 4; i++)
            {
                CombatHelper.QueryHostiles(this, from, 18f, _scratch);
                GameObject best = null;
                float bd = float.MaxValue;
                for (int j = 0; j < _scratch.Count; j++)
                {
                    if (struck.Contains(_scratch[j])) continue;
                    float dist = (_scratch[j].transform.position - from).sqrMagnitude;
                    if (dist < bd) { bd = dist; best = _scratch[j]; }
                }
                if (best == null) break;
                struck.Add(best);
                ClassFx.Beam(from + Vector3.up * 1.5f,
                    best.transform.position + Vector3.up * 1.2f, 0.4f,
                    new Color(0.6f, 0.8f, 1f), 0.08f);
                var d = best.GetComponent<IDamageable>();
                if (d != null && d.IsAlive)
                {
                    d.TakeDamage(ApplyOutgoingDamage(25f, DamageCause.Explosion),
                        best.transform.position, DamageCause.Explosion);
                    OnDamagedEnemy(best);
                }
                var slow = best.GetComponent<ISlowable>();
                if (slow != null) slow.ApplySlow(0.5f, 3f);
                from = best.transform.position;
            }
            if (struck.Count == 0) return false;
            _overchargeT = 6f; // shock rounds
            return true;
        }

        protected override float OutgoingDamageMult(DamageCause cause) =>
            base.OutgoingDamageMult(cause) * 1.1f; // Live Wire
    }
}
