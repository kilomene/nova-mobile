using System;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Implemented by the player (and AI drivers when the Player/Squads systems
    /// are ported). All vehicle input flows through here.
    /// Conventions: DriveMoveInput.x: -1 (left) .. +1 (right);
    /// DriveMoveInput.y: +1 = forward push. Yaw convention: vehicle forward =
    /// (-sin(yaw), 0, -cos(yaw)) — matches the -Z model-forward port.
    /// </summary>
    public interface IVehicleDriver
    {
        Transform Transform { get; }
        Vector2 DriveMoveInput { get; }
        bool DriveGas { get; }
        bool DriveBrake { get; }
        bool DriveNitro { get; }
        bool DriveHandbrake { get; }
        bool DriveUp { get; }    // helicopter climb
        bool DriveDown { get; }  // helicopter descend
        bool WantsFire { get; }
        float AimYaw { get; }    // world yaw of the driver's aim, same convention as controller yaw
        void OnEnterVehicle(VehicleController vehicle);
        void OnExitVehicle(Vector3 exitPos);
        void UpdateDriving(VehicleController vehicle, Vector3 seatWorldPos);
        void NotifyOutOfFuel();
        void ApplyDamage(float amount, Vector3 fromPos, string kind);
    }

    /// <summary>
    /// Drivable vehicle: arcade transform-based physics per locomotion type
    /// (no WheelCollider — cannot be tuned blind), enter/exit, fuel burn,
    /// nitro, damage/smoke/fire/explosion chain, and vehicle weapons
    /// (tank cannon, heli minigun, B2 bombs). Ports vehicle.gd faithfully.
    /// Model forward = -Z (Godot port convention).
    /// </summary>
    public class VehicleController : MonoBehaviour, IVehicleDamageable
    {
        private const float R2D = 57.29578f;

        // ---- exact cross-system contract (CONVENTIONS.md) ----
        public VehicleSpec Spec;
        public float Fuel, Health01 = 1f;
        public bool IsOccupied;
        public int HornIndex;

        public void Enter()
        {
            // The Player system calls SetDriver(driver) first, then Enter().
            if (Destroyed || IsOccupied || Driver == null) return;
            IsOccupied = true;
            Driver.OnEnterVehicle(this);
            if (EnteredVehicle != null) EnteredVehicle(this);
        }

        public void Exit()
        {
            if (!IsOccupied) return;
            Vector3 exitPos = transform.position
                + transform.right * (Model.Width * 0.5f + 1.2f)
                + Vector3.up * 0.6f;
            IVehicleDriver d = Driver;
            Driver = null;
            IsOccupied = false;
            IsRefueling = false;
            if (d != null) d.OnExitVehicle(exitPos);
            if (ExitedVehicle != null) ExitedVehicle();
        }

        public void AddFuel(float a)
        {
            if (Spec.FuelCapacity <= 0f) return;
            Fuel = Mathf.Min(Spec.FuelCapacity, Fuel + a);
            if (Fuel > 0.01f) OutOfFuel = false;
        }
        // ---- end contract ----

        public static event Action<VehicleController> EnteredVehicle;
        public static event Action ExitedVehicle;

        // Public state (read by HUD, fuel stations, AI).
        public VehicleType Type;
        public VehicleExtra Extra;
        public VehicleModel Model;
        public IVehicleDriver Driver { get; private set; }
        public bool Destroyed { get; private set; }
        public bool OutOfFuel { get; private set; }
        public bool IsRefueling;
        public float Speed;          // signed forward speed (m/s)
        public float Nitro = 100f;
        public bool LightsOn;
        public float EnterRadius = 3.5f;

        // Physics state.
        private float yaw;           // radians; forward = (-sin, 0, -cos)
        private float pitch;         // radians; B2 only
        private float vy;            // vertical velocity (heli / ground gravity)
        private bool flying;         // B2 airborne

        // Weapons.
        private float cannonCd, bombCd, minigunAcc;
        private int bombsLeft;

        // Damage FX flags.
        private bool smoking, burning;

        // Audio / lights.
        private AudioSource engineSource, oneSource, skidSource;
        private Light[] headlights;
        private float thudCd;

        private static readonly Collider[] _overlapBuf = new Collider[32];
        private RaycastHit _hit;

        // ------------------------------------------------------------ setup
        public static VehicleController Spawn(VehicleType type, Vector3 pos, float yawDegrees, int skinIndex = -1)
        {
            var go = new GameObject("Vehicle_" + type);
            var vc = go.AddComponent<VehicleController>();
            vc.Setup(type, skinIndex);
            go.transform.position = pos;
            vc.yaw = yawDegrees / R2D;
            vc.ApplyOrientation(0f);
            return vc;
        }

        public void Setup(VehicleType type, int skinIndex = -1)
        {
            Type = type;
            Spec = VehicleData.Get(type);
            Extra = VehicleData.Extra(type);
            HornIndex = VehicleAudio.HornIndexFor(type);
            Fuel = Spec.FuelCapacity;
            Health01 = 1f;
            VehicleEffects.Prewarm();
            VehicleAudio.Prewarm();
            Model = VehicleFactory.Build(type, skinIndex);
            Model.Root.transform.SetParent(transform, false);
            var col = gameObject.AddComponent<BoxCollider>();
            col.size = new Vector3(Model.Width, Model.Height, Model.Length);
            col.center = new Vector3(0f, Model.Height * 0.5f, 0f);
            // Kinematic body: no physics cost, but enables trigger interactions
            // (fuel-can pickups etc.). All motion stays transform-driven.
            var rb = gameObject.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.useGravity = false;
            bombsLeft = Extra.BombCount;
            BuildHeadlights();
            BuildAudio();
        }

        public void SetDriver(IVehicleDriver d) { Driver = d; }

        public string GetEnterPrompt()
        {
            if (Destroyed || IsOccupied) return null;
            return "Enter " + Spec.Name;
        }

        public Vector3 SeatWorld() { return transform.TransformPoint(Model.SeatOffset); }
        public Vector3 MuzzleWorld() { return transform.TransformPoint(Model.MuzzleOffset); }
        private Vector3 Forward() { return new Vector3(-Mathf.Sin(yaw), 0f, -Mathf.Cos(yaw)); }

        private void ApplyOrientation(float pitchRad)
        {
            Vector3 fwd = new Vector3(
                -Mathf.Sin(yaw) * Mathf.Cos(pitchRad),
                Mathf.Sin(pitchRad),
                -Mathf.Cos(yaw) * Mathf.Cos(pitchRad));
            if (fwd.sqrMagnitude < 0.0001f) fwd = new Vector3(0f, 0f, -1f);
            transform.rotation = Quaternion.LookRotation(-fwd, Vector3.up);
        }

        private void BuildHeadlights()
        {
            headlights = new Light[2];
            for (int i = 0; i < 2; i++)
            {
                float sx = i == 0 ? -1f : 1f;
                var go = new GameObject(i == 0 ? "Headlight_L" : "Headlight_R");
                go.transform.SetParent(transform, false);
                go.transform.localPosition = new Vector3(sx * Model.Width * 0.32f, 0.9f, -Model.Length * 0.48f);
                go.transform.localRotation = Quaternion.Euler(0f, 180f, 0f); // face -Z (model forward)
                var l = go.AddComponent<Light>();
                l.type = LightType.Spot;
                l.color = new Color(1f, 0.95f, 0.85f);
                l.intensity = 0f;
                l.spotAngle = 56f; // Godot spot_angle 28 = half-angle
                l.range = 30f;
                headlights[i] = l;
            }
        }

        public void ToggleLights()
        {
            LightsOn = !LightsOn;
            if (headlights == null) return;
            for (int i = 0; i < headlights.Length; i++)
                if (headlights[i] != null) headlights[i].intensity = LightsOn ? 3f : 0f;
        }

        public void Horn()
        {
            if (Destroyed || oneSource == null) return;
            oneSource.PlayOneShot(VehicleAudio.HornClip(HornIndex));
        }

        private void BuildAudio()
        {
            string kind = VehicleAudio.EngineKindFor(Type);
            if (!string.IsNullOrEmpty(kind))
            {
                var go = new GameObject("EngineAudio");
                go.transform.SetParent(transform, false);
                engineSource = go.AddComponent<AudioSource>();
                engineSource.clip = VehicleAudio.EngineLoop(kind);
                engineSource.loop = true;
                engineSource.spatialBlend = 1f;
                engineSource.volume = 0f;
                engineSource.Play();
            }
            {
                var go = new GameObject("OneShotAudio");
                go.transform.SetParent(transform, false);
                oneSource = go.AddComponent<AudioSource>();
                oneSource.spatialBlend = 1f;
            }
            {
                var go = new GameObject("SkidAudio");
                go.transform.SetParent(transform, false);
                skidSource = go.AddComponent<AudioSource>();
                skidSource.clip = VehicleAudio.SkidLoop();
                skidSource.loop = true;
                skidSource.spatialBlend = 1f;
                skidSource.volume = 0f;
                skidSource.Play();
            }
        }

        // ------------------------------------------------------------ fuel
        /// <summary>Burn fuel; returns the effective throttle (0 when dry).</summary>
        private float ApplyFuel(float dt, float throttle)
        {
            if (!Spec.UsesFuel || Destroyed) return throttle;
            if (OutOfFuel) return 0f;
            Fuel = Mathf.Max(0f, Fuel - Spec.FuelBurnRate * (0.25f + 0.75f * Mathf.Abs(throttle)) * dt);
            if (Fuel <= 0.01f)
            {
                OutOfFuel = true;
                if (Driver != null) Driver.NotifyOutOfFuel();
                return 0f;
            }
            return throttle;
        }

        public bool NeedsFuel() { return Spec.UsesFuel && Fuel < Spec.FuelCapacity - 1f; }
        public float FuelFrac()
        {
            if (!Spec.UsesFuel || Spec.FuelCapacity <= 0f) return 1f;
            return Mathf.Clamp01(Fuel / Spec.FuelCapacity);
        }

        // ------------------------------------------------------------ physics
        private void FixedUpdate()
        {
            if (Destroyed) return;
            if (Driver == null)
            {
                Speed = 0f; // parked
                UpdateRotor(Time.fixedDeltaTime);
                return;
            }
            float dt = Time.fixedDeltaTime;
            switch (Extra.Loco)
            {
                case Locomotion.Ground: DriveGroundLike(dt, false, false); break;
                case Locomotion.Hover: DriveGroundLike(dt, true, false); break;
                case Locomotion.Water: DriveGroundLike(dt, false, true); break;
                case Locomotion.Air: DriveAir(dt); break;
                case Locomotion.Plane: DrivePlane(dt); break;
            }
        }

        // Arcade ground/hover/water driving (ports _drive_ground/_drive_hover/_drive_water).
        private void DriveGroundLike(float dt, bool isHover, bool isWater)
        {
            Vector2 inp = Driver.DriveMoveInput;
            float throttle = inp.y;
            if (Driver.DriveGas) throttle = 1f;
            else if (Driver.DriveBrake) throttle = -0.7f;
            float top = Spec.TopSpeed;
            if (Driver.DriveNitro && Nitro > 1f && throttle > 0.1f)
            {
                top *= Extra.NitroMult;
                Nitro = Mathf.Max(0f, Nitro - 35f * dt);
            }
            else Nitro = Mathf.Min(100f, Nitro + 12f * dt);
            throttle = ApplyFuel(dt, throttle);
            float target = throttle * top;
            float rate = Mathf.Abs(target) > Mathf.Abs(Speed) ? Spec.Acceleration : Extra.Brake;
            bool hbrake = Driver.DriveHandbrake;
            if (hbrake)
            {
                rate = Extra.Brake * 2.2f;
                Speed = Mathf.MoveTowards(Speed, 0f, rate * dt);
            }
            else Speed = Mathf.MoveTowards(Speed, target, rate * dt);
            float steer = inp.x;
            float turnMult = hbrake ? 1.7f : 1f;
            float sf = Mathf.Clamp01(Mathf.Abs(Speed) / Mathf.Max(top, 1f));
            float dirSign = Mathf.Abs(Speed) > 0.5f ? Mathf.Sign(Speed) : 1f;
            yaw -= steer * Spec.TurnRate * turnMult * sf * dirSign * dt;

            float gy = VehicleEffects.GroundHeight(transform.position);
            Vector3 pos = transform.position;
            Vector3 fwd = Forward();
            if (isWater)
            {
                if (gy > 0.25f) Speed = Mathf.MoveTowards(Speed, 0f, 20f * dt); // beached
                else
                {
                    pos += fwd * Speed * dt;
                    pos.y = Mathf.Lerp(pos.y, VehicleEffects.WaterLevel, 6f * dt);
                }
            }
            else if (isHover)
            {
                pos += fwd * Speed * dt;
                float targetY = Mathf.Max(gy, -0.2f) + Extra.HoverHeight;
                pos.y = Mathf.Lerp(pos.y, targetY, 6f * dt);
            }
            else
            {
                bool grounded = pos.y <= gy + 0.35f;
                if (!grounded) vy -= 22f * dt; else vy = -0.5f;
                pos += fwd * Speed * dt;
                pos.y += vy * dt;
                if (grounded && pos.y < gy) pos.y = gy;
            }
            transform.position = pos;
            ApplyOrientation(0f);
            CheckImpact(dt);
            if (!isWater) CheckRam();
            if (Extra.Lean && Model.Body != null)
            {
                float wantRoll = -steer * 0.35f * sf;
                Vector3 e = Model.Body.localEulerAngles;
                float cur = (e.z > 180f ? e.z - 360f : e.z) / R2D;
                Model.Body.localRotation = Quaternion.Euler(0f, 0f, Mathf.Lerp(cur, wantRoll, 8f * dt) * R2D);
            }
            Driver.UpdateDriving(this, SeatWorld());
            UpdateWheels(dt, inp);
            UpdateRotor(dt);
            UpdateTurret(dt);
        }

        // Helicopter VTOL (ports _drive_air).
        private void DriveAir(float dt)
        {
            Vector2 inp = Driver.DriveMoveInput;
            float top = Spec.TopSpeed;
            float up = 0f;
            if (Driver.DriveUp) up += 1f;
            if (Driver.DriveDown) up -= 1f;
            vy = Mathf.MoveTowards(vy, up * 9f, 22f * dt);

            Vector3 localWish = new Vector3(inp.x, 0f, -inp.y);
            float spd = 0f;
            if (localWish.sqrMagnitude > 0.0001f)
            {
                // World-space wish (Godot: basis * wish), then face it.
                float c = Mathf.Cos(yaw), s = Mathf.Sin(yaw);
                float wx = localWish.x * c + localWish.z * s;
                float wz = -localWish.x * s + localWish.z * c;
                float yawTarget = Mathf.Atan2(-wx, -wz);
                yaw = Mathf.LerpAngle(yaw, yawTarget, 1f - Mathf.Exp(-3f * dt));
                spd = top; // arcade: any stick deflection = full cruise (matches Godot)
            }
            if (Spec.UsesFuel)
            {
                float burn = Mathf.Clamp01((spd > 0f ? 1f : 0f) + Mathf.Abs(up));
                burn = Mathf.Min(burn, 1.5f);
                float before = ApplyFuel(dt, burn);
                if (OutOfFuel || before <= 0f)
                {
                    up = 0f; spd = 0f;
                    vy = Mathf.MoveTowards(vy, -3f, 10f * dt); // autorotate down gently
                }
            }
            Vector3 pos = transform.position;
            pos += Forward() * spd * dt;
            pos.y += vy * dt;
            float gy = VehicleEffects.GroundHeight(pos);
            if (pos.y < gy + 0.8f && vy < 0f) { pos.y = gy + 0.8f; vy = 0f; }
            transform.position = pos;
            ApplyOrientation(0f);
            Driver.UpdateDriving(this, SeatWorld());
            UpdateRotor(dt);
            UpdateTurret(dt);
        }

        // B2 arcade flight (ports _drive_plane).
        private void DrivePlane(float dt)
        {
            Vector2 inp = Driver.DriveMoveInput;
            float top = Spec.TopSpeed;
            if (!flying)
            {
                Speed = Mathf.MoveTowards(Speed, top, Spec.Acceleration * dt);
                Vector3 pos = transform.position + Forward() * Speed * dt;
                pos.y = VehicleEffects.GroundHeight(pos);
                transform.position = pos;
                ApplyOrientation(0f);
                if (Speed >= Extra.TakeoffSpeed && inp.y > 0.3f) flying = true; // push forward to lift
                CheckImpact(dt);
                CheckRam();
            }
            else
            {
                Speed = Mathf.MoveTowards(Speed, top, 6f * dt);
                yaw -= inp.x * Spec.TurnRate * dt;
                pitch = Mathf.Clamp(Mathf.Lerp(pitch, inp.y * 0.45f, 3f * dt), -0.6f, 0.6f);
                Vector3 fwd3 = new Vector3(
                    -Mathf.Sin(yaw) * Mathf.Cos(pitch), Mathf.Sin(pitch),
                    -Mathf.Cos(yaw) * Mathf.Cos(pitch));
                Vector3 pos = transform.position + fwd3 * Speed * dt;
                float gy = VehicleEffects.GroundHeight(pos);
                bool hitWall = Physics.SphereCast(transform.position, 1f, fwd3, out _hit, Speed * dt + 1f)
                    && _hit.collider.GetComponent<VehicleController>() != this;
                if (pos.y <= gy + 0.5f || hitWall)
                {
                    float impact = Speed;
                    flying = false;
                    pitch = 0f;
                    pos.y = gy;
                    if (impact > 40f) TakeDamage(120f, pos, "crash");
                }
                transform.position = pos;
                ApplyOrientation(pitch);
            }
            Driver.UpdateDriving(this, SeatWorld());
            UpdateRotor(dt);
            UpdateTurret(dt);
        }

        // Forward obstacle: block at very close range, thud + slow on hard hits.
        private void CheckImpact(float dt)
        {
            if (thudCd > 0f) thudCd -= dt;
            Vector3 nose = transform.position + Forward() * (Model.Length * 0.5f + 0.4f) + Vector3.up * 1f;
            if (Physics.SphereCast(nose, 0.7f, Forward(), out _hit, 1.2f)
                && _hit.collider.GetComponent<VehicleController>() != this)
            {
                if (_hit.distance < 0.5f) Speed = 0f;
                else if (Mathf.Abs(Speed) > 12f && thudCd <= 0f)
                {
                    thudCd = 0.4f;
                    if (oneSource != null) oneSource.PlayOneShot(VehicleAudio.Thud());
                    Speed *= 0.55f;
                }
            }
        }

        // Ram damageables at speed (ports _check_ram).
        private void CheckRam()
        {
            if (Mathf.Abs(Speed) < 8f) return;
            Vector3 nose = transform.position + Forward() * (Model.Length * 0.5f) + Vector3.up * 1f;
            int n = Physics.OverlapSphereNonAlloc(nose, 1.2f, _overlapBuf);
            for (int i = 0; i < n; i++)
            {
                Collider c = _overlapBuf[i];
                if (c == null) continue;
                var dmg = c.GetComponent<IVehicleDamageable>();
                if (dmg == null || !dmg.IsAlive) continue;
                if ((dmg as UnityEngine.Object) == this) continue;
                if (Driver != null && dmg.Transform == Driver.Transform) continue; // never ram the driver
                dmg.TakeDamage(Extra.RamDamage, transform.position, "ram");
                Speed *= 0.6f;
            }
        }

        private void UpdateWheels(float dt, Vector2 inp)
        {
            float spinDeg = Speed * dt / 0.35f * R2D;
            for (int i = 0; i < Model.WheelSpins.Count; i++)
                Model.WheelSpins[i].Rotate(spinDeg, 0f, 0f);
            float wantYaw = -inp.x * 0.45f * R2D;
            for (int i = 0; i < Model.WheelSteers.Count; i++)
            {
                Transform s = Model.WheelSteers[i];
                Vector3 e = s.localEulerAngles;
                float cur = e.y > 180f ? e.y - 360f : e.y;
                s.localRotation = Quaternion.Euler(0f, Mathf.Lerp(cur, wantYaw, 10f * dt), 0f);
            }
        }

        private float rotorSpeed;
        private void UpdateRotor(float dt)
        {
            float target = (Driver != null || Extra.Loco == Locomotion.Air) ? 200f : 0f; // rad/s visual blur
            rotorSpeed = Mathf.Lerp(rotorSpeed, target, 2f * dt);
            if (Model.RotorMain != null) Model.RotorMain.Rotate(0f, rotorSpeed * R2D * dt, 0f);
            if (Model.RotorTail != null) Model.RotorTail.Rotate(rotorSpeed * 0.15f * R2D * dt, 0f, 0f);
        }

        // Tank turret follows the driver's aim yaw (ports _update_weapon_aim).
        private void UpdateTurret(float dt)
        {
            if (Extra.Weapon != VehicleWeapon.Cannon || Driver == null || Model.Turret == null) return;
            float want = Driver.AimYaw - yaw;
            while (want > Mathf.PI) want -= Mathf.PI * 2f;
            while (want < -Mathf.PI) want += Mathf.PI * 2f;
            Vector3 e = Model.Turret.localEulerAngles;
            float cur = (e.y > 180f ? e.y - 360f : e.y) / R2D;
            float d = want - cur;
            if (d > Mathf.PI) d -= Mathf.PI * 2f;
            if (d < -Mathf.PI) d += Mathf.PI * 2f;
            Model.Turret.localRotation = Quaternion.Euler(0f, (cur + d * (1f - Mathf.Exp(-6f * dt))) * R2D, 0f);
        }

        // ------------------------------------------------------------ weapons
        private void Update()
        {
            if (Destroyed) return;
            if (cannonCd > 0f) cannonCd -= Time.deltaTime;
            if (bombCd > 0f) bombCd -= Time.deltaTime;
            if (Extra.Weapon != VehicleWeapon.None && Driver != null && Driver.WantsFire)
            {
                switch (Extra.Weapon)
                {
                    case VehicleWeapon.Cannon:
                        if (cannonCd <= 0f) { cannonCd = Extra.CannonCd; FireCannon(); }
                        break;
                    case VehicleWeapon.Minigun:
                        minigunAcc += Time.deltaTime;
                        float interval = 60f / Mathf.Max(Extra.MinigunRpm, 1f);
                        while (minigunAcc >= interval) { minigunAcc -= interval; FireMinigun(); }
                        break;
                    case VehicleWeapon.Bombs:
                        if (bombCd <= 0f && bombsLeft > 0) { bombCd = Extra.BombCd; bombsLeft--; DropBomb(); }
                        break;
                }
            }
            else if (Extra.Weapon == VehicleWeapon.Minigun) minigunAcc = 0f;
            UpdateAudio();
        }

        public int BombsLeft { get { return bombsLeft; } }

        private void FireCannon()
        {
            Vector3 from = MuzzleWorld();
            Vector3 dir = new Vector3(-Mathf.Sin(Driver.AimYaw), 0f, -Mathf.Cos(Driver.AimYaw));
            Vector3 impact = from + dir * 120f;
            RaycastHit hit;
            // Step past our own hull if the ray starts inside it.
            Vector3 origin = from;
            for (int i = 0; i < 3; i++)
            {
                if (!Physics.Raycast(origin, dir, out hit, 120f)) break;
                if (hit.collider.GetComponent<VehicleController>() != this) { impact = hit.point; break; }
                origin = hit.point + dir * 0.5f;
                impact = origin + dir * 120f;
            }
            VehicleEffects.Explode(impact, Extra.CannonRadius, Extra.CannonDamage, this);
            if (oneSource != null) oneSource.PlayOneShot(ProcAudio.Explosion("veh_cannon", 0.8f), 0.8f);
        }

        private void FireMinigun()
        {
            Vector3 from = SeatWorld() + Vector3.up * 1.6f;
            Vector3 dir = new Vector3(-Mathf.Sin(Driver.AimYaw), 0f, -Mathf.Cos(Driver.AimYaw));
            Vector3 target = from + dir * 90f;
            RaycastHit hit;
            if (Physics.Raycast(from, dir, out hit, 90f)
                && hit.collider.GetComponent<VehicleController>() != this) target = hit.point;
            int n = Physics.OverlapSphereNonAlloc(target, 2.5f, _overlapBuf);
            for (int i = 0; i < n; i++)
            {
                Collider c = _overlapBuf[i];
                if (c == null) continue;
                var dmg = c.GetComponent<IVehicleDamageable>();
                if (dmg == null || !dmg.IsAlive) continue;
                if ((dmg as UnityEngine.Object) == this) continue;
                if (Driver != null && dmg.Transform == Driver.Transform) continue;
                dmg.TakeDamage(Extra.MinigunDamage, target, "bullet");
            }
        }

        private void DropBomb()
        {
            VehicleEffects.DropBomb(MuzzleWorld(), Extra.BombRadius, Extra.BombDamage);
        }

        // ------------------------------------------------------------ damage
        public void TakeDamage(float amount, Vector3 fromPos, string kind)
        {
            if (Destroyed) return;
            float maxHp = Mathf.Max(Spec.Health, 1f);
            Health01 = Mathf.Clamp01(Health01 - amount / maxHp);
            if (Health01 <= 0.5f && !smoking)
            {
                smoking = true;
                VehicleEffects.AttachSmoke(transform, new Vector3(0f, 1.2f, 0f));
            }
            if (Health01 <= 0.25f && !burning)
            {
                burning = true;
                VehicleEffects.AttachFire(transform, new Vector3(0f, 1.2f, 0f));
            }
            if (Health01 <= 0f) ExplodeVehicle();
        }

        public void TakeDamage(float amount, string kind = "bullet")
        {
            TakeDamage(amount, transform.position, kind);
        }

        bool IVehicleDamageable.IsAlive { get { return !Destroyed; } }
        Transform IVehicleDamageable.Transform { get { return transform; } }
        void IVehicleDamageable.TakeDamage(float amount, Vector3 fromPos, string kind)
        {
            TakeDamage(amount, fromPos, kind);
        }

        private void ExplodeVehicle()
        {
            Destroyed = true;
            Vector3 pos = transform.position + Vector3.up * 1f;
            VehicleEffects.Explode(pos, 6f, 80f, this);
            IVehicleDriver d = Driver;
            if (d != null)
            {
                Vector3 exitPos = transform.position
                    + transform.right * (Model.Width * 0.5f + 1.2f) + Vector3.up * 0.6f;
                Driver = null;
                IsOccupied = false;
                IsRefueling = false;
                d.OnExitVehicle(exitPos);
                d.ApplyDamage(40f, pos, "explosive");
                if (ExitedVehicle != null) ExitedVehicle();
            }
            // Burnt wreck: char the whole model, silence it.
            CharRecursive(transform);
            if (engineSource != null) engineSource.Stop();
            if (skidSource != null) skidSource.Stop();
        }

        private void CharRecursive(Transform t)
        {
            var mr = t.GetComponent<MeshRenderer>();
            if (mr != null) mr.sharedMaterial = VehicleMats.Charred();
            for (int i = 0; i < t.childCount; i++) CharRecursive(t.GetChild(i));
        }

        // ------------------------------------------------------------ audio
        private void UpdateAudio()
        {
            float dt = Time.deltaTime;
            if (engineSource != null)
            {
                float top = Mathf.Max(Spec.TopSpeed, 1f);
                float rpm01 = Mathf.Clamp01(Mathf.Abs(Speed) / top);
                if (Extra.Loco == Locomotion.Air) rpm01 = Mathf.Clamp01(0.55f + Mathf.Abs(vy) / 18f);
                engineSource.pitch = 0.7f + rpm01 * 1.1f;
                float wantVol = (Driver != null && !Destroyed && !OutOfFuel) ? 0.25f + rpm01 * 0.35f : 0.004f;
                engineSource.volume = Mathf.Lerp(engineSource.volume, wantVol, 4f * dt);
            }
            if (skidSource != null)
            {
                float skid = 0f;
                if (Driver != null && (Extra.Loco == Locomotion.Ground || Extra.Loco == Locomotion.Hover))
                {
                    Vector3 fwd = Forward();
                    Vector3 vel = fwd * Speed;
                    Vector3 lat = vel - fwd * Vector3.Dot(vel, fwd);
                    if (Mathf.Abs(Speed) > 10f && lat.magnitude > 3f)
                        skid = Mathf.Clamp01(lat.magnitude / 8f);
                }
                skidSource.volume = Mathf.Lerp(skidSource.volume, 0.001f + skid * 0.5f, 6f * dt);
            }
        }
    }
}
