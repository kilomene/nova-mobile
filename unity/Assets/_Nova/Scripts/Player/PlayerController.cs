using System;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Player
{
    /// <summary>
    /// Aim-assist target provider, filled by the Match/Soldiers system.
    /// Returns true and the target chest position when a valid target sits
    /// inside the assist cone.
    /// </summary>
    public interface IAimAssistSource
    {
        bool FindAssistTarget(Vector3 camPos, Vector3 forward,
            float maxAngleRad, out Vector3 targetPos, out float angleRad);
    }

    /// <summary>
    /// Third-person over-shoulder player controller (CODM BR style).
    /// Ported from player.gd: movement, stances, slide, drop-shot, ADS,
    /// grenades, armor plates, health/regen, touch look, gyro, aim assist.
    ///
    /// CAMERA (per visual-target update): over-shoulder TPP — the camera sits
    /// behind and slightly right of the character's shoulder, crosshair stays
    /// center-screen. ADS pulls the camera in closer over the shoulder and
    /// tightens FOV; it never switches to first person. The visible character
    /// is the Soldiers rig (parented to this GameObject by the Match system);
    /// this controller exposes locomotion state + animation hooks for it.
    ///
    /// Mobile-first: no per-frame allocations in Update (Input.GetTouch loop,
    /// no LINQ, cached structs only).
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class PlayerController : MonoBehaviour, IDamageable
    {
        // ---- tuning (from player.gd) ----
        private const float WalkSpeed = 5.2f;
        private const float SprintMult = 1.38f;
        private const float AdsSlow = 0.6f;
        private const float CrouchMult = 0.5f;
        private const float ProneMult = 0.32f;
        private const float JumpVelocity = 4.6f;
        private const float Gravity = 9.81f;
        private const float TouchSens = 0.0045f; // rad per px
        private const float AdsSensMult = 0.6f;
        private const float HipFov = 75.0f;
        private const float SprintFov = 83.0f;
        private const float AdsFov = 50.0f; // TPP: tighter, stays third-person
        private const float SlideTime = 0.85f;
        private const float SlideCooldown = 0.5f;
        private const float SlideMinSpeed = 5.0f;
        private const float CrouchHoldProne = 0.45f;
        private const float RegenDelay = 5.0f;
        private const float RegenRate = 25.0f;
        private const float GrenadeFuse = 2.0f;
        private const float GrenadePower = 15.0f;
        private const float SmokePower = 14.0f;

        // Stance geometry: controller height / camera shoulder height.
        private const float StandHeight = 1.7f, StandHead = 1.55f;
        private const float CrouchHeight = 1.2f, CrouchHead = 1.00f;
        private const float ProneHeight = 0.8f, ProneHead = 0.50f;

        // Camera boom: behind + right of the shoulder.
        private const float CamDist = 2.6f;
        private const float CamDistAds = 1.25f;
        private const float CamSide = 0.55f;
        private const float CamSideAds = 0.45f;
        private const float CamSmooth = 14.0f;

        // ---- health / armor ----
        public int MaxHp = 100;
        public int ArmorCap = 150;
        public int MaxPlates = 6;
        public int PlateValue = 50;
        public float PlateApplyTime = 2.0f;

        // ---- refs (wired by the Match system; camera/head built if null) ----
        public Camera PlayerCamera;
        public TouchHUD Hud;

        /// <summary>Hook for CODM "simple" fire mode: true while an enemy is
        /// under the crosshair. Set by the Match/Arsenal system.</summary>
        public Func<bool> SimpleModeTargetProvider;

        /// <summary>Aim-assist target source (Soldiers/Match system).</summary>
        public IAimAssistSource AimAssistSource;

        /// <summary>Optic zoom of the current weapon (0 = iron/red-dot).
        /// Set by the Arsenal system; scales ADS sensitivity.</summary>
        public float OpticZoom;

        // ---- events ----
        public event Action<int, int, int> HealthChanged; // hp, maxHp, armor
        public event Action Died;
        public event Action ArmorBroken;
        public event Action Footstep;
        public event Action Jumped;
        public event Action Landed;
        public event Action<int> GrenadeCountChanged;
        public event Action<int> SmokeCountChanged;
        public event Action<int> ArmorPlatesChanged;
        public event Action ArmorApplyStarted;
        public event Action<float> ArmorApplyProgress; // 0..1, animation hook
        public event Action ArmorApplyCompleted;
        public event Action ReloadRequested;
        public event Action SkillPressed;
        public event Action PingPressed;
        public event Action EmotePressed;
        public event Action SwapPressed;
        public event Action InspectStarted;
        public event Action InspectStopped;

        // ---- state ----
        private CharacterController _cc;
        private Transform _headAnchor;
        private float _yaw;   // radians, + = right
        private float _pitch; // radians, + = up, clamped +/-1.35
        private Vector3 _vel;
        private bool _grounded;

        private int _hp;
        private int _armor;
        private int _plates;
        private bool _dead;
        private float _sinceDamage = 99f;

        private bool _ads;
        private bool _sprinting;
        private bool _mobileSprint;
        private bool _crouching;
        private bool _proning;
        private bool _sliding;
        private float _slideTimer;
        private float _slideCd;
        private Vector3 _slideDir;

        private bool _crouchHolding;
        private float _crouchHoldT;
        private bool _dropShot; // crouch tap while firing -> prone; skip up-toggle

        private bool _touchFiring;
        private bool _wasFiring;

        private bool _cooking;
        private float _cookT;
        private int _grenades = 6;
        private int _smokes;
        private bool _nadeFrag = true;

        private float _armorTimer;

        private bool _inspecting;
        private float _inspectT;

        private float _bobT;
        private int _stepCycle;

        private int _lookFinger = -1;
        private Vector3 _camPos; // smoothed camera position
        private bool _camSnap = true;
        private Vector3 _camForward = Vector3.forward;

        // ---- public state for the Soldiers animation system ----
        public bool IsAlive => !_dead;
        bool IDamageable.IsAlive => !_dead;
        public bool IsAds => _ads;
        public bool IsSprinting => _sprinting;
        public bool IsCrouching => _crouching;
        public bool IsProning => _proning;
        public bool IsSliding => _sliding;
        public bool IsGrounded => _grounded;
        public bool IsInspecting => _inspecting;
        public bool IsApplyingArmor => _armorTimer > 0f;
        public int Hp => _hp;
        public int Armor => _armor;
        public int ArmorPlates => _plates;
        public int GrenadeCount => _grenades;
        public int SmokeCount => _smokes;
        public float HorizontalSpeed => new Vector2(_vel.x, _vel.z).magnitude;
        public Vector3 CameraForward => _camForward;
        public Transform HeadAnchor => _headAnchor;
        /// <summary>Crosshair world point (camera forward, 60 m).</summary>
        public Vector3 AimPoint => _camPos + _camForward * 60f;
        /// <summary>True while the fire button (or simple-mode auto-fire) is held.</summary>
        public bool WantFire { get; private set; }

        // ------------------------------------------------------------------
        private void Awake()
        {
            _cc = GetComponent<CharacterController>();
            _hp = MaxHp;

            _headAnchor = new GameObject("HeadAnchor").transform;
            _headAnchor.SetParent(transform, false);
            _headAnchor.localPosition = new Vector3(0, StandHead, 0);

            if (PlayerCamera == null)
            {
                var camGo = new GameObject("PlayerCamera");
                PlayerCamera = camGo.AddComponent<Camera>();
                PlayerCamera.fieldOfView = HipFov;
                PlayerCamera.nearClipPlane = 0.05f;
            }

            if (Hud == null)
                Hud = FindFirstObjectByType<TouchHUD>();
            if (Hud != null)
                BindHud(Hud);

            if (SystemInfo.supportsGyroscope)
                Input.gyro.enabled = ControlSettings.GyroEnabled;
        }

        private void OnEnable()
        {
            // In case Hud was created after us.
            if (Hud == null)
            {
                Hud = FindFirstObjectByType<TouchHUD>();
                if (Hud != null) BindHud(Hud);
            }
        }

        public void BindHud(TouchHUD hud)
        {
            Hud = hud;
            hud.FireDown += () => SetTouchFiring(true);
            hud.FireUp += () => SetTouchFiring(false);
            hud.AdsPressed += () => SetAds(!_ads);
            hud.JumpDown += TryJump;
            hud.CrouchDown += CrouchDown;
            hud.CrouchUp += CrouchUp;
            hud.PronePressed += ToggleProne;
            hud.ReloadPressed += () => ReloadRequested?.Invoke();
            hud.GrenadeDown += StartGrenadeCook;
            hud.GrenadeUp += ReleaseGrenade;
            hud.NadeSelectPressed += () =>
            {
                _nadeFrag = !_nadeFrag;
                hud.SetNadeFrag(_nadeFrag);
            };
            hud.ArmorPressed += ApplyArmorPlate;
            hud.InspectDown += StartInspect;
            hud.InspectUp += StopInspect;
            hud.EmotePressed += () => EmotePressed?.Invoke();
            hud.SkillPressed += () => SkillPressed?.Invoke();
            hud.SwapPressed += () => SwapPressed?.Invoke();
            hud.PingPressed += () => PingPressed?.Invoke();
            hud.SprintPressed += ToggleSprint;
            hud.SetGrenadeCount(_grenades);
            hud.SetSmokeCount(_smokes);
            hud.SetArmorPlates(_plates);
        }

        // ================= input =================
        public void SetTouchFiring(bool b) { _touchFiring = b; }

        public void ToggleSprint()
        {
            if (_dead) return;
            _mobileSprint = !_mobileSprint;
            if (!_mobileSprint) _sprinting = false;
            Hud?.SetSprintActive(_mobileSprint);
        }

        public void TryJump()
        {
            if (_dead) return;
            if (_sliding)
            {
                // Slide-cancel: pop upright, gun ready.
                _sliding = false;
                ApplyStance();
            }
            if (_grounded)
            {
                _vel.y = JumpVelocity;
                _grounded = false;
                Jumped?.Invoke();
            }
        }

        public void CrouchDown()
        {
            if (_dead || _crouchHolding) return;
            // Drop-shot: crouch tap while firing drops to prone.
            if ((_touchFiring || WantFire) && !_proning)
            {
                _dropShot = true;
                SetProne(true);
                return;
            }
            _crouchHolding = true;
            _crouchHoldT = 0f;
            if (_sliding) return;
            if (_sprinting && _grounded)
            {
                StartSlide();
                _crouchHolding = false; // slide consumed the press
            }
        }

        public void CrouchUp()
        {
            if (!_crouchHolding && !_dropShot) return;
            _crouchHolding = false;
            if (_dropShot) { _dropShot = false; return; }
            if (_dead) return;
            if (_crouchHoldT >= CrouchHoldProne && !_sliding)
            {
                if (!_proning) SetProne(true); // held crouch -> prone (CODM)
            }
            else
            {
                ToggleCrouch(); // quick tap -> crouch / slide
            }
        }

        public void ToggleCrouch()
        {
            if (_dead || _sliding) return;
            if (_sprinting && _grounded) { StartSlide(); return; }
            _crouching = !_crouching;
            if (_crouching) { _proning = false; _sprinting = false; }
            ApplyStance();
        }

        public void ToggleProne()
        {
            if (_dead || !_grounded || _sliding) return;
            SetProne(!_proning);
        }

        private void SetProne(bool on)
        {
            _proning = on;
            if (on) { _crouching = false; _sprinting = false; }
            ApplyStance();
        }

        private void StartSlide()
        {
            if (_slideCd > 0f) return;
            _sliding = true;
            _slideTimer = SlideTime;
            _slideCd = SlideTime + SlideCooldown;
            _crouching = false;
            _sprinting = false;
            Vector2 hv = new Vector2(_vel.x, _vel.z);
            if (hv.magnitude > 0.5f)
                _slideDir = new Vector3(hv.x, 0, hv.y).normalized;
            else
                _slideDir = transform.forward;
            ApplyStance();
        }

        public void SetAds(bool b)
        {
            if (_dead || _sprinting) b = false;
            if (_ads == b) return;
            _ads = b;
            Hud?.SetAdsActive(_ads);
        }

        // ================= grenades =================
        public void AddGrenades(int n)
        {
            _grenades = Mathf.Min(_grenades + n, 12);
            GrenadeCountChanged?.Invoke(_grenades);
            Hud?.SetGrenadeCount(_grenades);
        }

        public void AddSmoke(int n)
        {
            _smokes = Mathf.Min(_smokes + n, 6);
            SmokeCountChanged?.Invoke(_smokes);
            Hud?.SetSmokeCount(_smokes);
        }

        public void StartGrenadeCook()
        {
            if (_dead || _cooking) return;
            if (_grenades <= 0) return;
            _cooking = true;
            _cookT = 0f;
            _sprinting = false;
        }

        public void ReleaseGrenade()
        {
            if (!_cooking) return;
            _cooking = false;
            _grenades--;
            GrenadeCountChanged?.Invoke(_grenades);
            Hud?.SetGrenadeCount(_grenades);
            Hud?.StartCooldown("grenade", 1.2f);
            Vector3 from = _headAnchor.position + _camForward * 0.6f;
            FragGrenade.Spawn(from, _camForward, GrenadePower,
                Mathf.Max(GrenadeFuse - _cookT, 0.15f), gameObject);
        }

        /// <summary>Instant smoke throw (no cooking).</summary>
        public void ThrowSmoke()
        {
            if (_dead || _cooking || _smokes <= 0) return;
            _smokes--;
            SmokeCountChanged?.Invoke(_smokes);
            Hud?.SetSmokeCount(_smokes);
            Hud?.StartCooldown("nade", 1.0f);
            Vector3 from = _headAnchor.position + _camForward * 0.6f;
            SmokeGrenade.Spawn(from, _camForward, SmokePower, gameObject);
        }

        // ================= armor plates =================
        public void AddArmorPlate()
        {
            if (_dead) return;
            if (_plates < MaxPlates)
            {
                _plates++;
                ArmorPlatesChanged?.Invoke(_plates);
                Hud?.SetArmorPlates(_plates);
            }
        }

        /// <summary>CODM plate apply: 2 s, +50 armor, cannot fire meanwhile.</summary>
        public void ApplyArmorPlate()
        {
            if (_dead || _armorTimer > 0f || _plates <= 0 || _armor >= ArmorCap)
                return;
            _plates--;
            ArmorPlatesChanged?.Invoke(_plates);
            Hud?.SetArmorPlates(_plates);
            _armorTimer = PlateApplyTime;
            Hud?.StartCooldown("armor", PlateApplyTime);
            ArmorApplyStarted?.Invoke();
        }

        // ================= inspect =================
        public void StartInspect()
        {
            if (_dead || _inspecting) return;
            _inspecting = true;
            _inspectT = 0f;
            InspectStarted?.Invoke();
        }

        public void StopInspect()
        {
            if (!_inspecting) return;
            _inspecting = false;
            InspectStopped?.Invoke();
        }

        // ================= damage =================
        public void TakeDamage(float amount, Vector3 from, DamageCause cause)
        {
            if (_dead) return;
            _sinceDamage = 0f;
            bool hadArmor = _armor > 0;
            float remaining = amount;
            if (_armor > 0)
            {
                float absorbed = Mathf.Min(_armor, remaining);
                _armor -= (int)absorbed;
                remaining -= absorbed;
            }
            _hp = Mathf.Max(_hp - (int)remaining, 0);
            HealthChanged?.Invoke(_hp, MaxHp, _armor);
            if (hadArmor && _armor <= 0) ArmorBroken?.Invoke();
            if (_hp <= 0)
            {
                _dead = true;
                Died?.Invoke();
            }
        }

        public void Heal(int n)
        {
            if (_dead) return;
            _hp = Mathf.Min(_hp + n, MaxHp);
            HealthChanged?.Invoke(_hp, MaxHp, _armor);
        }

        public void Respawn(Vector3 pos)
        {
            transform.position = pos;
            _vel = Vector3.zero;
            _hp = MaxHp;
            _armor = 0;
            _dead = false;
            _sprinting = false;
            _crouching = false;
            _proning = false;
            _sliding = false;
            _cooking = false;
            _inspecting = false;
            _armorTimer = 0f;
            _yaw = 0f; _pitch = 0f;
            _camSnap = true;
            ApplyStance();
            SetAds(false);
            HealthChanged?.Invoke(_hp, MaxHp, _armor);
        }

        // ================= per-frame =================
        private void Update()
        {
            if (_dead) return;
            float dt = Time.deltaTime;

            UpdateLook(dt);
            UpdateGyro(dt);

            if (_crouchHolding) _crouchHoldT += dt;
            if (_slideCd > 0f) _slideCd -= dt;
            if (_sliding)
            {
                _slideTimer -= dt;
                if (_slideTimer <= 0f)
                {
                    _sliding = false;
                    ApplyStance();
                }
            }

            // Armor plate apply timer (blocks firing).
            if (_armorTimer > 0f)
            {
                _armorTimer -= dt;
                ArmorApplyProgress?.Invoke(
                    1f - Mathf.Max(_armorTimer, 0f) / PlateApplyTime);
                if (_armorTimer <= 0f)
                {
                    _armor = Mathf.Min(_armor + PlateValue, ArmorCap);
                    HealthChanged?.Invoke(_hp, MaxHp, _armor);
                    ArmorApplyCompleted?.Invoke();
                }
            }

            // Grenade cooking (auto-release before the fuse runs out).
            if (_cooking)
            {
                _cookT += dt;
                if (_cookT >= GrenadeFuse - 0.15f) ReleaseGrenade();
            }

            // Inspect: 3 s, cancelled by firing or moving.
            if (_inspecting)
            {
                if (_wasFiring || _sprinting || _sliding) StopInspect();
                else
                {
                    _inspectT += dt;
                    if (_inspectT >= 3f) StopInspect();
                }
            }

            // Health regen.
            _sinceDamage += dt;
            if (_sinceDamage >= RegenDelay && _hp < MaxHp)
            {
                _hp = Mathf.Min(_hp + (int)(RegenRate * dt), MaxHp);
                HealthChanged?.Invoke(_hp, MaxHp, _armor);
            }

            // Fire intent: manual (advanced) or crosshair auto-fire (simple).
            bool wantFire = _touchFiring;
            if (ControlSettings.FireMode == "simple" && !_touchFiring)
            {
                var prov = SimpleModeTargetProvider;
                if (prov != null && prov()) wantFire = true;
            }
            if (_armorTimer > 0f) wantFire = false; // CODM: no fire while plating
            bool pressedEdge = wantFire && !_wasFiring;
            _wasFiring = wantFire;
            WantFire = wantFire;
            if (pressedEdge)
            {
                if (_sprinting) { _sprinting = false; Hud?.SetSprintActive(false); }
                if (ControlSettings.Haptics) Handheld.Vibrate();
            }

            UpdateMovement(dt);
            UpdateCamera(dt);
            UpdateBob(dt);

            Hud?.SetHeading(_yaw * Mathf.Rad2Deg);
        }

        private void UpdateLook(float dt)
        {
            int n = Input.touchCount;
            for (int i = 0; i < n; i++)
            {
                Touch t = Input.GetTouch(i);
                if (t.phase == TouchPhase.Began)
                {
                    // Right-half drags that didn't start on UI = look.
                    if (_lookFinger == -1
                        && t.position.x > Screen.width * 0.5f
                        && (Hud == null || !Hud.IsUiTouch(t.fingerId)))
                    {
                        _lookFinger = t.fingerId;
                    }
                }
                else if (t.phase == TouchPhase.Moved)
                {
                    if (t.fingerId == _lookFinger)
                    {
                        // deltaPosition is up-positive / right-positive:
                        // drag up = look up, drag right = look right.
                        Vector2 d = ApplyAimAssist(t.deltaPosition * LookSens());
                        RotateLook(d.x, d.y);
                    }
                }
                else if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled)
                {
                    if (t.fingerId == _lookFinger) _lookFinger = -1;
                }
            }
        }

        private float LookSens()
        {
            float mult = 1f;
            if (OpticZoom >= 8f) mult = ControlSettings.Zoom8Sens;
            else if (OpticZoom >= 4f) mult = ControlSettings.Zoom4Sens;
            else if (_ads) mult = ControlSettings.AdsSens;
            return TouchSens * ControlSettings.CamSens * mult;
        }

        private void RotateLook(float dx, float dy)
        {
            _yaw += dx;
            float iy = ControlSettings.InvertY ? -1f : 1f;
            _pitch = Mathf.Clamp(_pitch + dy * iy, -1.35f, 1.35f);
            transform.rotation = Quaternion.Euler(0f, _yaw * Mathf.Rad2Deg, 0f);
        }

        /// <summary>
        /// Aim assist: crosshair magnetism (slowdown near targets) + gentle
        /// rotational pull while ADS. Subtle by design — never a hard lock.
        /// Ported from player.gd _assist_delta.
        /// </summary>
        private Vector2 ApplyAimAssist(Vector2 d)
        {
            if (!ControlSettings.AimAssist || ControlSettings.AssistStrength <= 0.01f)
                return d;
            var src = AimAssistSource;
            if (src == null) return d;
            Vector3 target;
            float ang;
            if (!src.FindAssistTarget(_camPos, _camForward, 0.16f, out target, out ang))
                return d;
            float strength = ControlSettings.AssistStrength;
            float slow = 1f - strength * 0.55f * (1f - ang / 0.16f);
            Vector2 nd = d * slow;
            if (_ads)
            {
                Vector3 to = target - _camPos;
                float wantYaw = Mathf.Atan2(to.x, to.z);
                float dyaw = Mathf.DeltaAngle(_yaw * Mathf.Rad2Deg, wantYaw * Mathf.Rad2Deg)
                             * Mathf.Deg2Rad;
                Vector2 flat = new Vector2(to.x, to.z);
                float wantPitch = Mathf.Atan2(to.y, Mathf.Max(flat.magnitude, 0.01f));
                float dpitch = Mathf.Clamp(
                    Mathf.DeltaAngle(_pitch * Mathf.Rad2Deg, wantPitch * Mathf.Rad2Deg)
                    * Mathf.Deg2Rad, -0.2f, 0.2f);
                float cap = 0.012f * strength;
                nd.x += Mathf.Clamp(dyaw * 0.16f * strength, -cap, cap);
                nd.y += Mathf.Clamp(dpitch * 0.16f * strength, -cap, cap);
            }
            return nd;
        }

        private void UpdateGyro(float dt)
        {
            if (!ControlSettings.GyroEnabled || _dead) return;
            if (!SystemInfo.supportsGyroscope) return;
            Vector3 g = Input.gyro.rotationRate; // rad/s
            if (g.sqrMagnitude > 0.0004f)
            {
                float gs = ControlSettings.GyroSens;
                // Match player.gd mapping (gyro y -> yaw, gyro x -> pitch).
                RotateLook(g.y * gs * dt, -g.x * gs * dt);
            }
        }

        private void UpdateMovement(float dt)
        {
            Vector2 joy = Hud != null ? Hud.Joystick : Vector2.zero;
#if UNITY_EDITOR || UNITY_STANDALONE
            // Desktop test fallback.
            joy.x += Input.GetAxis("Horizontal");
            joy.y += Input.GetAxis("Vertical");
            joy = Vector2.ClampMagnitude(joy, 1f);
            if (Input.GetKeyDown(KeyCode.Space)) TryJump();
#endif
            // Sprint: mobile toggle + forward, blocked by ADS/stance/slide.
            bool fwd = joy.y > 0.1f;
            bool wantSprint = _mobileSprint && fwd && _grounded
                && !_ads && !_crouching && !_proning && !_sliding;
            if (wantSprint != _sprinting)
            {
                _sprinting = wantSprint;
                if (wantSprint && _ads) SetAds(false);
            }

            float speed = WalkSpeed;
            if (_ads) speed *= AdsSlow;
            if (_sprinting) speed *= SprintMult;
            if (_crouching) speed *= CrouchMult;
            if (_proning) speed *= ProneMult;

            Vector3 moveDir = Vector3.zero;
            if (joy.sqrMagnitude > 0.0001f)
            {
                moveDir = transform.TransformDirection(new Vector3(joy.x, 0f, joy.y));
                moveDir.y = 0f;
                moveDir.Normalize();
            }

            if (_sliding)
            {
                // Power slide: keep momentum, slight decay. Can shoot mid-slide.
                float sp = Mathf.Max(
                    new Vector2(_vel.x, _vel.z).magnitude, SlideMinSpeed);
                _vel.x = _slideDir.x * sp;
                _vel.z = _slideDir.z * sp;
                _bobT += dt * sp;
            }
            else if (moveDir.sqrMagnitude > 0.001f)
            {
                _vel.x = moveDir.x * speed;
                _vel.z = moveDir.z * speed;
                _bobT += dt * speed * 1.6f;
            }
            else
            {
                float dec = speed * 4f * dt;
                _vel.x = Mathf.MoveTowards(_vel.x, 0f, dec);
                _vel.z = Mathf.MoveTowards(_vel.z, 0f, dec);
            }

            // Gravity.
            bool wasGrounded = _grounded;
            if (_grounded && _vel.y < 0f) _vel.y = -1f; // stick to ground
            _vel.y -= Gravity * dt;

            _cc.Move(_vel * dt);
            _grounded = _cc.isGrounded;
            if (_grounded && !wasGrounded) Landed?.Invoke();

            // Keep inside a sane bound if the Match system didn't clamp.
            Vector3 p = transform.position;
            if (p.y < -8f)
            {
                p.y = 2f;
                transform.position = p;
                _vel = Vector3.zero;
            }
        }

        private void UpdateCamera(float dt)
        {
            float headH = _proning ? ProneHead : (_crouching || _sliding ? CrouchHead : StandHead);
            _headAnchor.localPosition = new Vector3(0f, headH, 0f);

            float dist = _ads ? CamDistAds : CamDist;
            float side = _ads ? CamSideAds : CamSide;

            Vector3 pivot = transform.position + Vector3.up * headH;
            float yawRad = _yaw;
            Vector3 fwd = new Vector3(Mathf.Sin(yawRad), 0f, Mathf.Cos(yawRad));
            Vector3 right = new Vector3(fwd.z, 0f, -fwd.x);

            Vector3 desired = pivot + right * side - fwd * dist + Vector3.up * 0.12f;

            // Camera collision: pull in on world hits (ignore self hits < 0.35 m).
            Vector3 toCam = desired - pivot;
            float fullDist = toCam.magnitude;
            RaycastHit hit;
            if (fullDist > 0.001f
                && Physics.Raycast(pivot, toCam / fullDist, out hit, fullDist))
            {
                if (hit.distance > 0.35f)
                    desired = pivot + toCam.normalized * (hit.distance * 0.9f);
            }

            if (_camSnap)
            {
                _camPos = desired;
                _camSnap = false;
            }
            else
            {
                _camPos = Vector3.Lerp(_camPos, desired, Mathf.Min(CamSmooth * dt, 1f));
            }

            // Look direction from pitch/yaw; crosshair stays center-screen.
            float pitchDeg = _pitch * Mathf.Rad2Deg;
            float yawDeg = _yaw * Mathf.Rad2Deg;
            _camForward = Quaternion.Euler(-pitchDeg, yawDeg, 0f) * Vector3.forward;
            Vector3 lookAt = pivot + _camForward * 10f;

            PlayerCamera.transform.position = _camPos;
            PlayerCamera.transform.LookAt(lookAt);

            float targetFov = _ads ? AdsFov : (_sprinting ? SprintFov : HipFov);
            PlayerCamera.fieldOfView = Mathf.Lerp(
                PlayerCamera.fieldOfView, targetFov, Mathf.Min(10f * dt, 1f));
        }

        private void UpdateBob(float dt)
        {
            float hs = new Vector2(_vel.x, _vel.z).magnitude;
            if (hs > 0.5f && _grounded && !_sliding)
            {
                // Subtle TPP camera bob.
                float bobY = Mathf.Sin(_bobT * 2f) * 0.012f;
                float bobX = Mathf.Cos(_bobT) * 0.008f;
                PlayerCamera.transform.position +=
                    PlayerCamera.transform.right * bobX + Vector3.up * bobY;
                int cycle = Mathf.FloorToInt(_bobT / Mathf.PI);
                if (cycle != _stepCycle)
                {
                    _stepCycle = cycle;
                    if (hs > 1f) Footstep?.Invoke(); // timing hook for audio/anims
                }
            }
        }

        private void ApplyStance()
        {
            if (_proning)
            {
                _cc.height = ProneHeight;
                _cc.center = new Vector3(0f, ProneHeight * 0.5f, 0f);
            }
            else if (_crouching || _sliding)
            {
                _cc.height = CrouchHeight;
                _cc.center = new Vector3(0f, CrouchHeight * 0.5f, 0f);
            }
            else
            {
                _cc.height = StandHeight;
                _cc.center = new Vector3(0f, StandHeight * 0.5f, 0f);
            }
        }
    }
}
