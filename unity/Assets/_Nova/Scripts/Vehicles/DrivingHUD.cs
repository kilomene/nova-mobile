using System;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;
using NovaMobile.Core;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Driving HUD (uGUI, built in code — no scene needed): speedometer, RPM bar,
    /// fuel gauge, hull bar, nitro meter, headlight toggle, camera-switch hook,
    /// horn and exit buttons, plus mobile controls: steering (tilt via
    /// Input.acceleration + on-screen arrows), gas/brake pedals, handbrake, nitro.
    /// Owns the mobile drive-input state the Player system's driver reads.
    /// </summary>
    public class DrivingHUD : MonoBehaviour
    {
        public static DrivingHUD Instance { get; private set; }

        /// <summary>Boot from code: HUD exists without any scene wiring.</summary>
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void AutoCreate()
        {
            if (Instance == null)
                new GameObject("DrivingHUD_Root").AddComponent<DrivingHUD>();
        }

        /// <summary>Fired by the camera-switch button; the camera system subscribes.</summary>
        public event Action CameraSwitchRequested;

        // ---- mobile input state (read by the player's IVehicleDriver impl) ----
        public bool TiltSteering = true;
        public float SteerAxis { get; private set; }   // -1 (left) .. +1 (right)
        public bool GasHeld { get; private set; }
        public bool BrakeHeld { get; private set; }
        public bool NitroHeld { get; private set; }
        public bool HandbrakeHeld { get; private set; }

        public Vector2 MoveInput
        {
            get
            {
                float throttle = GasHeld ? 1f : (BrakeHeld ? -0.7f : 0f);
                return new Vector2(SteerAxis, throttle);
            }
        }

        private VehicleController _vehicle;
        private Canvas _canvas;
        private Font _font;

        private Text _speedText, _fuelText, _nameText, _bombsText;
        private Image _rpmFill, _fuelFill, _hullFill, _nitroFill;

        private bool _steerLeft, _steerRight;

        private void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
            DontDestroyOnLoad(gameObject);
            _font = Resources.GetBuiltinResource<Font>("Arial.ttf");
            BuildUI();
            _canvas.enabled = false;
            VehicleController.EnteredVehicle += ShowFor;
            VehicleController.ExitedVehicle += Hide;
        }

        private void OnDestroy()
        {
            VehicleController.EnteredVehicle -= ShowFor;
            VehicleController.ExitedVehicle -= Hide;
        }

        public void ShowFor(VehicleController v)
        {
            _vehicle = v;
            if (v != null) _nameText.text = v.Spec.Name + "  [" + v.Model.SkinName + "]";
            _canvas.enabled = true;
        }

        public void Hide()
        {
            _vehicle = null;
            _canvas.enabled = false;
            ClearInputs();
        }

        private void ClearInputs()
        {
            SteerAxis = 0f;
            GasHeld = BrakeHeld = NitroHeld = HandbrakeHeld = false;
            _steerLeft = _steerRight = false;
        }

        // ------------------------------------------------------------ UI build
        private Image Panel(float x0, float y0, float x1, float y1, Color c)
        {
            var go = new GameObject("Panel");
            go.transform.SetParent(_canvas.transform, false);
            var rt = go.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(rt, x0, y0, x1, y1);
            var img = go.AddComponent<Image>();
            img.color = c;
            return img;
        }

        private Text Label(Transform parent, string name, float x0, float y0, float x1, float y1,
            int size, Color color, TextAnchor anchor = TextAnchor.MiddleCenter)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var rt = go.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(rt, x0, y0, x1, y1);
            var t = go.AddComponent<Text>();
            t.font = _font;
            t.fontSize = size;
            t.color = color;
            t.alignment = anchor;
            t.text = "";
            return t;
        }

        private Image Bar(Transform parent, string name, float x0, float y0, float x1, float y1, Color fill)
        {
            var bg = new GameObject(name + "_Bg");
            bg.transform.SetParent(parent, false);
            var brt = bg.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(brt, x0, y0, x1, y1);
            var bimg = bg.AddComponent<Image>();
            bimg.color = new Color(0f, 0f, 0f, 0.55f);
            var fg = new GameObject(name + "_Fill");
            fg.transform.SetParent(bg.transform, false);
            var frt = fg.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(frt, 0f, 0f, 1f, 1f);
            var fimg = fg.AddComponent<Image>();
            fimg.color = fill;
            fimg.type = Image.Type.Filled;
            fimg.fillMethod = Image.FillMethod.Horizontal;
            fimg.fillOrigin = (int)Image.OriginHorizontal.Left;
            return fimg;
        }

        private sealed class HoldRelay : MonoBehaviour
        {
            public Action<bool> OnHold;
            private void Wire()
            {
                var et = gameObject.AddComponent<EventTrigger>();
                var down = new EventTrigger.Entry { eventID = EventTriggerType.PointerDown };
                down.callback.AddListener(_ => { if (OnHold != null) OnHold(true); });
                var up = new EventTrigger.Entry { eventID = EventTriggerType.PointerUp };
                up.callback.AddListener(_ => { if (OnHold != null) OnHold(false); });
                var exit = new EventTrigger.Entry { eventID = EventTriggerType.PointerExit };
                exit.callback.AddListener(_ => { if (OnHold != null) OnHold(false); });
                et.triggers.Add(down); et.triggers.Add(up); et.triggers.Add(exit);
            }
            public static HoldRelay Attach(GameObject go, Action<bool> cb)
            {
                var h = go.AddComponent<HoldRelay>();
                h.OnHold = cb;
                h.Wire();
                return h;
            }
        }

        private Button MakeButton(string name, string text, float x0, float y0, float x1, float y1,
            Color color, Action onClick, Action<bool> onHold = null, int fontSize = 28)
        {
            var go = new GameObject(name);
            go.transform.SetParent(_canvas.transform, false);
            var rt = go.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(rt, x0, y0, x1, y1);
            var img = go.AddComponent<Image>();
            img.color = color;
            var btn = go.AddComponent<Button>();
            var t = go.AddComponent<Text>();
            t.font = _font; t.fontSize = fontSize; t.color = Color.white;
            t.alignment = TextAnchor.MiddleCenter; t.text = text;
            if (onClick != null) btn.onClick.AddListener(() => onClick());
            if (onHold != null) HoldRelay.Attach(go, onHold);
            return btn;
        }

        private void BuildUI()
        {
            var go = new GameObject("DrivingHUD");
            _canvas = go.AddComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _canvas.sortingOrder = 50;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920f, 1080f);
            go.AddComponent<GraphicRaycaster>();
            DontDestroyOnLoad(go);
            _canvas.transform.SetParent(transform, false);

            // Vehicle name plate (top center).
            _nameText = Label(_canvas.transform, "Name", 0.30f, 0.93f, 0.70f, 0.98f, 30, Color.white);

            // Speed cluster (bottom right).
            Panel(0.78f, 0.02f, 0.99f, 0.20f, new Color(0f, 0f, 0f, 0.45f));
            _speedText = Label(_canvas.transform, "Speed", 0.79f, 0.09f, 0.98f, 0.19f, 54, Color.white);
            _rpmFill = Bar(_canvas.transform, "RPM", 0.79f, 0.035f, 0.98f, 0.07f, new Color(1f, 0.35f, 0.1f));
            _bombsText = Label(_canvas.transform, "Bombs", 0.79f, 0.20f, 0.98f, 0.25f, 26, new Color(1f, 0.8f, 0.3f));

            // Status bars (bottom left, above steering).
            _hullFill = Bar(_canvas.transform, "Hull", 0.02f, 0.30f, 0.20f, 0.335f, new Color(0.2f, 0.9f, 0.25f));
            _nitroFill = Bar(_canvas.transform, "Nitro", 0.02f, 0.255f, 0.20f, 0.29f, new Color(0.2f, 0.8f, 1f));
            _fuelFill = Bar(_canvas.transform, "Fuel", 0.02f, 0.21f, 0.20f, 0.245f, new Color(1f, 0.6f, 0.1f));
            _fuelText = Label(_canvas.transform, "FuelText", 0.02f, 0.16f, 0.20f, 0.205f, 24, new Color(1f, 0.75f, 0.4f));

            // Steering arrows (bottom left).
            MakeButton("SteerLeft", "◀", 0.02f, 0.02f, 0.10f, 0.15f,
                new Color(0.1f, 0.1f, 0.15f, 0.6f), null, h => _steerLeft = h, 48);
            MakeButton("SteerRight", "▶", 0.11f, 0.02f, 0.19f, 0.15f,
                new Color(0.1f, 0.1f, 0.15f, 0.6f), null, h => _steerRight = h, 48);

            // Pedals (bottom right).
            MakeButton("Gas", "GAS", 0.88f, 0.26f, 0.98f, 0.44f,
                new Color(0.1f, 0.5f, 0.15f, 0.65f), null, h => GasHeld = h, 32);
            MakeButton("Brake", "BRK", 0.77f, 0.26f, 0.87f, 0.44f,
                new Color(0.55f, 0.12f, 0.12f, 0.65f), null, h => BrakeHeld = h, 32);
            MakeButton("Handbrake", "HB", 0.77f, 0.45f, 0.87f, 0.56f,
                new Color(0.5f, 0.35f, 0.08f, 0.65f), null, h => HandbrakeHeld = h, 28);
            MakeButton("Nitro", "N₂O", 0.88f, 0.45f, 0.98f, 0.56f,
                new Color(0.1f, 0.4f, 0.6f, 0.65f), null, h => NitroHeld = h, 28);

            // Utility column (right edge).
            MakeButton("Horn", "📯", 0.93f, 0.60f, 0.99f, 0.70f,
                new Color(0.15f, 0.15f, 0.2f, 0.6f),
                () => { if (_vehicle != null) _vehicle.Horn(); }, null, 36);
            MakeButton("Lights", "💡", 0.93f, 0.71f, 0.99f, 0.81f,
                new Color(0.15f, 0.15f, 0.2f, 0.6f),
                () => { if (_vehicle != null) _vehicle.ToggleLights(); }, null, 36);
            MakeButton("Camera", "🎥", 0.93f, 0.82f, 0.99f, 0.92f,
                new Color(0.15f, 0.15f, 0.2f, 0.6f),
                () => { if (CameraSwitchRequested != null) CameraSwitchRequested(); }, null, 36);
            MakeButton("Exit", "EXIT", 0.83f, 0.82f, 0.92f, 0.92f,
                new Color(0.6f, 0.15f, 0.1f, 0.7f),
                () => { if (_vehicle != null) _vehicle.Exit(); }, null, 30);
        }

        private void Update()
        {
            // Steering: on-screen arrows + optional tilt.
            float steer = 0f;
            if (_steerLeft) steer -= 1f;
            if (_steerRight) steer += 1f;
            if (TiltSteering && SystemInfo.supportsAccelerometer)
                steer += Mathf.Clamp(Input.acceleration.x * 1.6f, -1f, 1f);
            SteerAxis = Mathf.Clamp(steer, -1f, 1f);

            if (_vehicle == null || !_canvas.enabled) return;

            _speedText.text = Mathf.RoundToInt(Mathf.Abs(_vehicle.Speed) * 3.6f) + " km/h";
            float rpm01 = Mathf.Clamp01(Mathf.Abs(_vehicle.Speed) / Mathf.Max(_vehicle.Spec.TopSpeed, 1f));
            _rpmFill.fillAmount = rpm01;
            _hullFill.fillAmount = _vehicle.Health01;
            _hullFill.color = Color.Lerp(Color.red, new Color(0.2f, 0.9f, 0.25f), _vehicle.Health01);
            _nitroFill.fillAmount = _vehicle.Nitro / 100f;
            if (_vehicle.Spec.UsesFuel)
            {
                _fuelFill.fillAmount = _vehicle.FuelFrac();
                _fuelText.text = "FUEL " + Mathf.RoundToInt(_vehicle.FuelFrac() * 100f) + "%";
            }
            else
            {
                _fuelFill.fillAmount = 0f;
                _fuelText.text = _vehicle.OutOfFuel ? "OUT OF FUEL" : "";
            }
            if (_vehicle.OutOfFuel && _vehicle.Spec.UsesFuel)
                _fuelText.text = "OUT OF FUEL!";
            if (_vehicle.Extra.Weapon == VehicleWeapon.Bombs)
                _bombsText.text = "BOMBS: " + _vehicle.BombsLeft;
            else
                _bombsText.text = "";
        }
    }
}
