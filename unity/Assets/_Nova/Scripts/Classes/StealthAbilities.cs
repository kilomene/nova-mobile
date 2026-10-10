using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    // ==================================================================
    // STEALTH profession
    // ==================================================================

    /// <summary>Grapple Hook: yank to an aim point up to 40m; drop attack 75 on landing.</summary>
    public class SpiderAbility : ClassAbility
    {
        public override string ClassId => "spider";
        public override float Cooldown => ClassData.Get("spider").Cooldown * CooldownMultiplier;

        private bool _grappling;
        private Vector3 _grappleTo;
        private FxItem _beam;

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
            _grappleTo = AimPoint(40f);
            _grappling = true;
            return true;
        }

        protected override void Tick(float dt)
        {
            if (!_grappling || Body == null) return;
            Vector3 to = _grappleTo - transform.position;
            if (to.magnitude < 2f)
            {
                _grappling = false;
                EndBeam();
                // Drop attack: landing on an enemy from above.
                DamageHostiles(transform.position, 3f, 75f, DamageCause.Melee);
                return;
            }
            Body.Velocity = to.normalized * 24f;
            UpdateBeam();
        }

        private void UpdateBeam()
        {
            Vector3 a = transform.position + Vector3.up * 1.5f;
            Vector3 b = _grappleTo;
            if (_beam == null)
            {
                var go = ClassFx.Beam(a, b, 30f, new Color(0.8f, 0.8f, 0.85f), 0.04f);
                _beam = go.GetComponent<FxItem>();
                if (_beam != null) _beam.HoldManual = true; // spider drives the rope
            }
            else
            {
                float len = Mathf.Max(Vector3.Distance(a, b), 0.01f);
                _beam.transform.position = (a + b) * 0.5f;
                _beam.transform.LookAt(b);
                _beam.transform.localScale = new Vector3(0.04f, 0.04f, len);
            }
        }

        private void EndBeam()
        {
            if (_beam != null)
            {
                ClassFx.Return(_beam);
                _beam = null;
            }
        }

        private void OnDisable() => EndBeam();

        public override float NoticeRangeMult() => base.NoticeRangeMult() * 0.65f;
    }

    /// <summary>Active Camo: near-invisibility 8s; firing breaks it and arms +50% damage 3s.</summary>
    public class WraithAbility : ClassAbility
    {
        public override string ClassId => "wraith";
        public override float Cooldown => ClassData.Get("wraith").Cooldown * CooldownMultiplier;

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
            if (Body == null) return false;
            Body.InvisibleTime = 8f;
            _wraithDmgT = 0f;
            return true;
        }

        protected override void Tick(float dt)
        {
            // Firing breaks camo and arms Ghost Rounds (+50% damage for 3s).
            if (IsPlayer && Body != null && Body.InvisibleTime > 0f && Body.WasFiring)
            {
                Body.InvisibleTime = 0f;
                _wraithDmgT = 3f;
            }
        }
    }

    /// <summary>Nitrogen Leap: 12m up with 4s air control; re-trigger = 30-dmg ground slam.</summary>
    public class CometAbility : ClassAbility
    {
        public override string ClassId => "comet";
        public override float Cooldown => ClassData.Get("comet").Cooldown * CooldownMultiplier;

        private float _jetT;
        private bool _slamArmed;

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
            if (_jetT <= 0f || Body == null) return false;
            _slamArmed = true;
            Body.Velocity = new Vector3(0f, -30f, 0f);
            return true;
        }

        protected override bool DoActivate()
        {
            if (Body == null) return false;
            Vector3 v = Body.Velocity;
            v.y = 14f;
            Body.Velocity = v;
            _jetT = 4f;
            _slamArmed = false;
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_jetT <= 0f || Body == null) return;
            _jetT -= dt;
            if (!Body.IsGrounded)
            {
                Vector3 v = Body.Velocity;
                v.y = Mathf.Max(v.y, -3f); // nitrogen air control softens the fall
                Body.Velocity = v;
            }
            if (_slamArmed && Body.IsGrounded)
            {
                _slamArmed = false;
                _jetT = 0f;
                ClassFx.Explode(transform.position, 3f);
                DamageHostiles(transform.position, 5f, 30f, DamageCause.Explosion);
                ClassFx.GroundRing(transform.position, 5f, 0.8f, Accent);
            }
        }

        public override float JumpHeightMult() => 1.2f;
        public override float FallDamageMult() => 0.5f;
    }

    /// <summary>Katana Dash: 12m dash, 50 dmg chained up to 3 targets, 1.5s bullet deflect.</summary>
    public class RoninAbility : ClassAbility
    {
        public override string ClassId => "ronin";
        public override float Cooldown => ClassData.Get("ronin").Cooldown * CooldownMultiplier;

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
            Vector3 dir = transform.forward;
            dir.y = 0f;
            dir = dir.sqrMagnitude > 0.001f ? dir.normalized : Vector3.forward;
            Vector3 from = transform.position;
            transform.position = GroundSnap(from + dir * 12f) + Vector3.up * 0.1f;
            ClassFx.GroundRing(from, 2f, 0.5f, Accent);

            int hit = 0;
            Vector3 chainFrom = transform.position;
            for (int i = 0; i < 3; i++)
            {
                GameObject best = NearestHostile(chainFrom, 10f);
                if (best == null) break;
                var d = best.GetComponent<IDamageable>();
                if (d != null && d.IsAlive)
                {
                    d.TakeDamage(ApplyOutgoingDamage(50f, DamageCause.Melee),
                        best.transform.position, DamageCause.Melee);
                    OnDamagedEnemy(best);
                }
                hit++;
                chainFrom = best.transform.position;
                Vector3 away = best.transform.position - transform.position;
                away.y = 0f;
                if (away.magnitude > 0.5f && hit < 3)
                    transform.position = GroundSnap(best.transform.position - away.normalized * 2f)
                        + Vector3.up * 0.1f;
            }
            _deflectT = 1.5f;
            return true;
        }

        protected override float IncomingDamageMult(DamageCause cause) =>
            base.IncomingDamageMult(cause) * (_deflectT > 0f ? 0.3f : 1f);

        protected override float OutgoingDamageMult(DamageCause cause) =>
            base.OutgoingDamageMult(cause) * (cause == DamageCause.Melee ? 1.25f : 1f);
    }

    /// <summary>Jetpack: 6s true flight toward aim; re-trigger cancels into a slide landing.</summary>
    public class ValkyrieAbility : ClassAbility
    {
        public override string ClassId => "valkyrie";
        public override float Cooldown => ClassData.Get("valkyrie").Cooldown * CooldownMultiplier;

        private float _jetT;

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
            if (_jetT <= 0f) return false;
            _jetT = 0f; // slam-cancel into a silent slide landing
            if (Body != null) Body.Velocity = Vector3.zero;
            return true;
        }

        protected override bool DoActivate()
        {
            _jetT = 6f;
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_jetT <= 0f || Body == null) return;
            _jetT -= dt;
            Vector3 dir = transform.forward;
            Body.Velocity = dir * 8f + Vector3.up * 2.5f;
            if (_jetT <= 0f) Body.Velocity = Vector3.zero;
        }

        public override float FallDamageMult() => 0.5f;
    }

    /// <summary>Blink Beacon: throw up to 20m; re-trigger within 30s blinks to it.</summary>
    public class GatekeeperAbility : ClassAbility
    {
        public override string ClassId => "gatekeeper";
        public override float Cooldown => ClassData.Get("gatekeeper").Cooldown * CooldownMultiplier;
        protected override float CooldownMultiplier => 0.8f;

        private GameObject _beacon;
        private Vector3 _beaconPos;
        private float _beaconT;

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
            if (_beacon == null || Body == null) return false;
            Vector3 keep = Body.Velocity;
            transform.position = _beaconPos + Vector3.up * 0.6f;
            Body.Velocity = keep; // keep momentum for trick plays
            ClassFx.GroundRing(_beaconPos, 2.5f, 0.8f, Accent);
            Destroy(_beacon);
            _beacon = null;
            _beaconT = 0f;
            CooldownLeft = Cooldown;
            return true;
        }

        protected override bool DoActivate()
        {
            Vector3 target = AimPoint(20f);
            _beaconPos = GroundSnap(target);
            _beacon = ClassFx.DeployBase(_beaconPos, Accent, 0.35f, 0.8f);
            _beaconT = 30f;
            return true;
        }

        protected override void Tick(float dt)
        {
            if (_beaconT <= 0f) return;
            _beaconT -= dt;
            if (_beaconT <= 0f && _beacon != null)
            {
                Destroy(_beacon);
                _beacon = null;
            }
        }
    }

    /// <summary>Bounce Pad: launches anyone 15m up; re-trigger remote-detonates.</summary>
    public class TrampolineAbility : ClassAbility
    {
        public override string ClassId => "trampoline";
        public override float Cooldown => ClassData.Get("trampoline").Cooldown * CooldownMultiplier;

        private readonly List<PadEntry> _pads = new List<PadEntry>(2);

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
            if (_pads.Count == 0) return false;
            for (int i = 0; i < _pads.Count; i++)
            {
                Vector3 pp = _pads[i].Pos;
                ClassFx.GroundRing(pp, 3f, 0.6f, Accent);
                CombatHelper.QueryHostiles(this, pp, 2.5f, _scratch);
                for (int j = 0; j < _scratch.Count; j++)
                {
                    var launch = _scratch[j].GetComponent<ILaunchable>();
                    if (launch != null) launch.Launch(Vector3.up * 17f);
                    else
                    {
                        var body = _scratch[j].GetComponent<IClassBody>();
                        if (body != null)
                        {
                            Vector3 v = body.Velocity;
                            v.y = 17f;
                            body.Velocity = v;
                        }
                    }
                }
                if (_pads[i].Node != null) Destroy(_pads[i].Node);
            }
            _pads.Clear();
            CooldownLeft = Cooldown;
            return true;
        }

        protected override bool DoActivate()
        {
            Vector3 pos = GroundSnap(transform.position + new Vector3(1.5f, 0f, 0f));
            var pad = ClassFx.DeployBase(pos, Accent, 0.9f, 0.25f);
            ClassFx.DestroyAfter(pad, 40f);
            _pads.Add(new PadEntry { Node = pad, Pos = pos, TimeLeft = 40f, Kind = 1 });
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
                _pads[i] = p;
                if ((transform.position - p.Pos).sqrMagnitude > 1.8f * 1.8f) continue;
                if (!OwnerAlive || Body == null) continue;
                // Spring Loaded: your pads launch you 30% higher.
                Vector3 v = Body.Velocity;
                v.y = 19.5f * 1.3f;
                Body.Velocity = v;
                ClassFx.GroundRing(p.Pos, 2.5f, 0.5f, Accent);
                // Enemies bounce too.
                CombatHelper.QueryHostiles(this, p.Pos, 1.8f, _scratch);
                for (int j = 0; j < _scratch.Count; j++)
                {
                    if (_scratch[j] == gameObject) continue;
                    var launch = _scratch[j].GetComponent<ILaunchable>();
                    if (launch != null) launch.Launch(Vector3.up * 16f);
                    else
                    {
                        var eb = _scratch[j].GetComponent<IClassBody>();
                        if (eb != null)
                        {
                            Vector3 ev = eb.Velocity;
                            ev.y = 16f;
                            eb.Velocity = ev;
                        }
                    }
                }
            }
        }

        public override float FallDamageMult() => 0.5f;
    }
}
