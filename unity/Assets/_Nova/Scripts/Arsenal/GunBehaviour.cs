using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Arsenal
{
    /// <summary>
    /// Hit report for one landed shot. Armor is applied by the subscriber.
    /// </summary>
    public struct GunHit
    {
        public IDamageable Target;
        public float Damage;
        public bool Headshot;
        public Vector3 Point;
        public Vector3 Direction;
    }

    /// <summary>
    /// Gun fire behaviour: rpm timer, fire modes (auto/semi/burst/pump/bolt/melee/
    /// rocket/grenade), hitscan with spread + penetration, shotgun pellets, timed
    /// reload (front-loading for rockets), ADS spread modifiers, per-AmmoType reserve
    /// inventory, recoil kick + return. No per-frame allocations in the fire path.
    ///
    /// Wiring: assign AimOrigin (camera/character muzzle ray origin), MuzzlePoint
    /// (from GunFactory's "MuzzlePoint" child), and call PullTrigger()/TriggerHeld
    /// from the owning character controller. Damage lands via OnHit; tracers and
    /// muzzle flash via OnTracer/OnMuzzleFlash hooks (FX owned by other systems).
    /// </summary>
    public class GunBehaviour : MonoBehaviour
    {
        public GunSpec Spec;
        public GunExtended Ext;
        public EffStats Stats;

        public Transform AimOrigin;   // camera: ray origin + forward
        public Transform MuzzlePoint; // GunFactory "MuzzlePoint" child
        public LayerMask HitMask = ~0;
        public GameObject Owner;

        public Action<GunHit> OnHit;
        public Action<Vector3, Vector3, Color> OnTracer; // from, to, color
        public Action OnMuzzleFlash;
        public Action<int, int> OnAmmoChanged; // mag, reserve
        public Action OnReloadStarted;
        public Action OnReloadFinished;
        public Action OnDryFire;

        public const float AdsSpreadMult = 0.35f;

        /// <summary>Starting reserve per ammo type (Godot AMMO_START).</summary>
        public static int StartReserve(AmmoType t)
        {
            switch (t)
            {
                case AmmoType.Light: return 240;
                case AmmoType.Medium: return 150;
                case AmmoType.Heavy: return 40;
                case AmmoType.Shell: return 24;
                case AmmoType.Rocket: return 4;
                case AmmoType.Grenade: return 6;
                default: return 0;
            }
        }

        private readonly Dictionary<AmmoType, int> _reserve = new Dictionary<AmmoType, int>();
        private int _mag;
        private float _fireTimer;
        private int _burstLeft;
        private bool _triggerHeld;
        private bool _reloading;
        private float _reloadT;
        private float _reloadDur;
        private bool _frontLoaded; // rocket round chambered early in the reload
        private bool _aiming;
        private readonly RaycastHit[] _hits = new RaycastHit[8];
        private System.Random _rng = new System.Random();

        // recoil: kick + return (mirrors Godot player _recoil Vector2)
        private Vector2 _recoilOffset;
        private Transform _pitchPivot;
        private Transform _yawPivot;
        private Vector3 _pitchBase;
        private Vector3 _yawBase;
        private const float RecoilReturn = 2.2f;

        public int MagInGun { get { return _mag; } }
        public bool IsReloading { get { return _reloading; } }
        public bool IsAiming { get { return _aiming; } set { _aiming = value; } }
        public Vector2 RecoilOffset { get { return _recoilOffset; } }

        public bool TriggerHeld
        {
            get { return _triggerHeld; }
            set { _triggerHeld = value; }
        }

        /// <summary>Attach camera pivots for direct recoil application.</summary>
        public void AttachCamera(Transform yawPivot, Transform pitchPivot)
        {
            _yawPivot = yawPivot;
            _pitchPivot = pitchPivot;
            if (_yawPivot != null) _yawBase = _yawPivot.localEulerAngles;
            if (_pitchPivot != null) _pitchBase = _pitchPivot.localEulerAngles;
        }

        public void Setup(GunSpec spec, string[] attachIds)
        {
            Spec = spec;
            Ext = GunData.GetExtended(spec.Id);
            SetAttachments(attachIds);
            _mag = Stats.Mag;
            if (!_reserve.ContainsKey(spec.Ammo))
                _reserve[spec.Ammo] = StartReserve(spec.Ammo);
            _fireTimer = 0f;
            _burstLeft = 0;
            _reloading = false;
            _recoilOffset = Vector2.zero;
            EmitAmmo();
        }

        public void SetAttachments(string[] attachIds)
        {
            int oldMag = Stats.Mag;
            Stats = AttachmentData.Effective(Spec, attachIds);
            if (oldMag > 0)
                _mag = Mathf.Min(_mag, Stats.Mag);
            else
                _mag = Stats.Mag;
        }

        public int GetReserve(AmmoType t)
        {
            int v;
            return _reserve.TryGetValue(t, out v) ? v : 0;
        }

        public void AddAmmo(AmmoType t, int n)
        {
            _reserve[t] = Mathf.Min(GetReserve(t) + n, 999);
            EmitAmmo();
        }

        /// <summary>Edge-triggered pull (semi / burst / pump / bolt / melee / launcher).</summary>
        public void PullTrigger()
        {
            if (_reloading) return;
            switch (Ext.Mode)
            {
                case GunFireMode.Auto:
                    break; // handled by TriggerHeld in Update
                case GunFireMode.Burst:
                    if (_burstLeft <= 0) _burstLeft = Ext.BurstN;
                    break;
                default:
                    TryFire();
                    break;
            }
        }

        private void Update()
        {
            _fireTimer -= Time.deltaTime;
            if (_reloading)
            {
                _reloadT += Time.deltaTime;
                // RP-7 style front-loading: the round is chambered early in the reload,
                // so cancelling still leaves a loaded round.
                if (!_frontLoaded && Ext.Mode == GunFireMode.Rocket && _reloadT >= _reloadDur * 0.25f)
                {
                    _frontLoaded = true;
                    _mag = 1;
                    EmitAmmo();
                }
                if (_reloadT >= _reloadDur)
                    FinishReload();
            }
            else if (_triggerHeld && Ext.Mode == GunFireMode.Auto)
                TryFire();
            else if (_burstLeft > 0)
                TryFire();

            // recoil return
            if (_recoilOffset.sqrMagnitude > 0.000001f)
            {
                _recoilOffset = Vector2.MoveTowards(_recoilOffset, Vector2.zero, RecoilReturn * Time.deltaTime);
                ApplyRecoil();
            }
        }

        private float ShotInterval()
        {
            return Stats.Rpm > 0f ? 60f / Stats.Rpm : 0.5f;
        }

        private void TryFire()
        {
            if (_fireTimer > 0f || _reloading) return;
            bool isMelee = Ext.Mode == GunFireMode.Melee;
            if (!isMelee && _mag <= 0)
            {
                if (OnDryFire != null) OnDryFire();
                StartReload();
                return;
            }
            _fireTimer = ShotInterval();
            if (!isMelee) _mag--;
            if (_burstLeft > 0) _burstLeft--;

            float spread = CurrentSpread();
            Vector3 origin = AimOrigin != null ? AimOrigin.position : transform.position;
            Vector3 fwd = AimOrigin != null ? AimOrigin.forward : transform.forward;

            if (Ext.Mode == GunFireMode.Melee)
            {
                MeleeSwing(origin, fwd);
            }
            else if (Ext.Mode == GunFireMode.Rocket || Ext.Mode == GunFireMode.Grenade)
            {
                Vector3 from = MuzzlePoint != null ? MuzzlePoint.position : origin + fwd * 0.6f;
                GunProjectile.Launch(from, ApplySpread(fwd, spread), Ext.ProjSpeed, Ext.ProjGrav,
                    Ext.BlastRadius, Spec.Damage, Owner);
                if (OnMuzzleFlash != null) OnMuzzleFlash();
            }
            else
            {
                int pellets = Spec.Class == GunClass.Shotgun ? Mathf.Max(Ext.Pellets, 1) : 1;
                for (int i = 0; i < pellets; i++)
                    FireHitscan(origin, fwd, spread);
                if (OnMuzzleFlash != null) OnMuzzleFlash();
            }

            // recoil kick (camera up + slight yaw drift)
            _recoilOffset.y += Stats.RecoilV;
            _recoilOffset.x += ((float)_rng.NextDouble() - 0.5f) * 2f * Stats.RecoilH;
            ApplyRecoil();
            EmitAmmo();
        }

        private void ApplyRecoil()
        {
            if (_yawPivot != null)
                _yawPivot.localEulerAngles = _yawBase + new Vector3(0f, _recoilOffset.x * Mathf.Rad2Deg, 0f);
            if (_pitchPivot != null)
                _pitchPivot.localEulerAngles = _pitchBase + new Vector3(-_recoilOffset.y * Mathf.Rad2Deg, 0f, 0f);
        }

        public float CurrentSpread()
        {
            float s = Stats.Spread;
            if (_aiming) s *= AdsSpreadMult;
            return s;
        }

        private Vector3 ApplySpread(Vector3 dir, float spread)
        {
            if (spread <= 0f) return dir;
            float a = (float)_rng.NextDouble() * Mathf.PI * 2f;
            float r = spread * Mathf.Sqrt((float)_rng.NextDouble());
            Vector3 right = Vector3.Cross(dir, Vector3.up);
            if (right.sqrMagnitude < 0.001f) right = Vector3.right;
            right.Normalize();
            Vector3 up = Vector3.Cross(right, dir).normalized;
            return (dir + right * Mathf.Cos(a) * r + up * Mathf.Sin(a) * r).normalized;
        }

        private void FireHitscan(Vector3 origin, Vector3 dir, float spread)
        {
            Vector3 shotDir = ApplySpread(dir, spread);
            float maxDist = Stats.RangeFar * 1.5f;
            int count = Physics.RaycastNonAlloc(origin, shotDir, _hits, maxDist, HitMask);
            if (count == 0)
            {
                if (OnTracer != null) OnTracer(origin, origin + shotDir * maxDist, TracerColor());
                return;
            }
            // sort by distance (insertion sort over the small buffer)
            for (int i = 1; i < count; i++)
            {
                RaycastHit tmp = _hits[i];
                int j = i - 1;
                while (j >= 0 && _hits[j].distance > tmp.distance)
                {
                    _hits[j + 1] = _hits[j];
                    j--;
                }
                _hits[j + 1] = tmp;
            }
            // penetration: 1 + floor(pen) targets, 0.6x damage per subsequent target
            int maxTargets = 1 + Mathf.FloorToInt(Ext.Pen);
            int damaged = 0;
            Vector3 tracerEnd = origin + shotDir * maxDist;
            for (int i = 0; i < count && damaged < maxTargets; i++)
            {
                RaycastHit h = _hits[i];
                tracerEnd = h.point;
                var target = h.collider.GetComponentInParent<IDamageable>();
                if (target == null || !target.IsAlive) continue;
                bool head = h.collider.GetComponentInParent<HeadshotZone>() != null;
                float dmg = GunData.DamageAtRange(Spec, h.distance);
                if (head) dmg *= Spec.HeadMult;
                float fall = 1f;
                for (int k = 0; k < damaged; k++) fall *= 0.6f;
                var hit = new GunHit
                {
                    Target = target,
                    Damage = dmg * fall,
                    Headshot = head,
                    Point = h.point,
                    Direction = shotDir
                };
                if (OnHit != null) OnHit(hit);
                damaged++;
            }
            if (OnTracer != null) OnTracer(origin, tracerEnd, TracerColor());
        }

        private void MeleeSwing(Vector3 origin, Vector3 dir)
        {
            float range = Ext.RangeNear;
            int count = Physics.RaycastNonAlloc(origin, dir, _hits, range, HitMask);
            for (int i = 0; i < count; i++)
            {
                var target = _hits[i].collider.GetComponentInParent<IDamageable>();
                if (target == null || !target.IsAlive) continue;
                var hit = new GunHit
                {
                    Target = target,
                    Damage = Spec.Damage,
                    Headshot = false,
                    Point = _hits[i].point,
                    Direction = dir
                };
                if (OnHit != null) OnHit(hit);
                break; // one target per swing
            }
        }

        private Color TracerColor()
        {
            // Mythic system may override via hook; default warm tracer.
            if (TracerColorHook != null) return TracerColorHook(Spec.Id);
            return new Color(1f, 0.85f, 0.5f);
        }

        /// <summary>Hook for the Mythics system to supply themed tracer colors.</summary>
        public static Func<string, Color> TracerColorHook;

        // ---------------- reload ----------------
        public void StartReload()
        {
            if (_reloading) return;
            if (_mag >= Stats.Mag) return;
            if (GetReserve(Spec.Ammo) <= 0) return;
            if (Spec.Ammo == AmmoType.None) return;
            _reloading = true;
            _reloadT = 0f;
            _reloadDur = Stats.Reload;
            _frontLoaded = false;
            if (OnReloadStarted != null) OnReloadStarted();
        }

        public void CancelReload()
        {
            if (!_reloading) return;
            _reloading = false;
            // Front-loaded rockets keep their chambered round on cancel.
            if (OnReloadFinished != null) OnReloadFinished();
        }

        private void FinishReload()
        {
            _reloading = false;
            int need = Stats.Mag - _mag;
            int take = Mathf.Min(need, GetReserve(Spec.Ammo));
            _mag += take;
            _reserve[Spec.Ammo] = GetReserve(Spec.Ammo) - take;
            EmitAmmo();
            if (OnReloadFinished != null) OnReloadFinished();
        }

        private void EmitAmmo()
        {
            if (OnAmmoChanged != null) OnAmmoChanged(_mag, GetReserve(Spec.Ammo));
        }
    }
}
