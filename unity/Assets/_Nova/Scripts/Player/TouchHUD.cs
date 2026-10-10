using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Core;

namespace NovaMobile.Player
{
    /// <summary>
    /// CODM Advanced-Mode touch HUD, built entirely at runtime in uGUI.
    /// Ported from hud.gd / hud_icons.gd: screen-fraction button layout,
    /// dynamic-origin left-half joystick, right-half look-drag filtering,
    /// rounded translucent panels with orange pressed state, radial cooldown
    /// sweeps, tap-to-expand minimap, custom-layout mode.
    ///
    /// 17 controls: joystick zone, fire, ADS, jump, crouch/slide, prone,
    /// reload, grenade (cook), frag/smoke select, armor plate, inspect, emote,
    /// minimap, skill (class ability), weapon swap, ping, sprint.
    ///
    /// TouchHUD owns ALL raw-touch hit-testing. FPSController asks
    /// IsUiTouch(fingerId) to decide which drags are look drags.
    /// The Match system fills MinimapView.texture each frame.
    /// </summary>
    public class TouchHUD : MonoBehaviour
    {
        public enum ButtonKind { Tap, Hold }

        // ---- button events (Match/FPSController subscribe) ----
        public event Action FireDown, FireUp;
        public event Action AdsPressed;
        public event Action JumpDown, JumpUp;
        public event Action CrouchDown, CrouchUp;
        public event Action PronePressed;
        public event Action ReloadPressed;
        public event Action GrenadeDown, GrenadeUp;
        public event Action NadeSelectPressed;
        public event Action ArmorPressed;
        public event Action InspectDown, InspectUp;
        public event Action EmotePressed;
        public event Action SkillPressed;
        public event Action SwapPressed;
        public event Action PingPressed;
        public event Action SprintPressed;
        public event Action MinimapPressed;

        private struct ButtonDef
        {
            public string id; public HudIcon icon; public string caption;
            public float fx, fy, d; public ButtonKind kind;
            public ButtonDef(string id, HudIcon icon, string caption,
                float fx, float fy, float d, ButtonKind kind)
            {
                this.id = id; this.icon = icon; this.caption = caption;
                this.fx = fx; this.fy = fy; this.d = d; this.kind = kind;
            }
        }

        // Default CODM Advanced-Mode layout (fractions; y from top, d = fraction of height).
        private static readonly ButtonDef[] Layout = new ButtonDef[]
        {
            new ButtonDef("fire",    HudIcon.Fire,    "FIRE",   0.925f, 0.780f, 0.175f, ButtonKind.Hold),
            new ButtonDef("ads",     HudIcon.Ads,     "ADS",    0.815f, 0.655f, 0.115f, ButtonKind.Tap),
            new ButtonDef("jump",    HudIcon.Jump,    "JUMP",   0.925f, 0.575f, 0.115f, ButtonKind.Hold),
            new ButtonDef("crouch",  HudIcon.Crouch,  "CRCH",   0.805f, 0.795f, 0.110f, ButtonKind.Hold),
            new ButtonDef("prone",   HudIcon.Prone,   "PRN",    0.715f, 0.685f, 0.095f, ButtonKind.Tap),
            new ButtonDef("grenade", HudIcon.Grenade, "GRN",    0.925f, 0.400f, 0.105f, ButtonKind.Hold),
            new ButtonDef("sprint",  HudIcon.Sprint,  "SPRINT", 0.695f, 0.830f, 0.085f, ButtonKind.Tap),
            new ButtonDef("reload",  HudIcon.Reload,  "RLD",    0.615f, 0.900f, 0.080f, ButtonKind.Tap),
            new ButtonDef("swap",    HudIcon.Swap,    "SWAP",   0.615f, 0.790f, 0.080f, ButtonKind.Tap),
            new ButtonDef("armor",   HudIcon.Armor,   "ARMOR",  0.545f, 0.900f, 0.080f, ButtonKind.Tap),
            new ButtonDef("skill",   HudIcon.Skill,   "SKILL",  0.545f, 0.790f, 0.080f, ButtonKind.Tap),
            new ButtonDef("inspect", HudIcon.Inspect, "INSP",   0.495f, 0.900f, 0.070f, ButtonKind.Hold),
            new ButtonDef("emote",   HudIcon.Emote,   "EMOTE",  0.495f, 0.790f, 0.070f, ButtonKind.Tap),
            new ButtonDef("ping",    HudIcon.Ping,    "PING",   0.845f, 0.450f, 0.060f, ButtonKind.Tap),
            new ButtonDef("nade",    HudIcon.Nade,    "FRAG",   0.845f, 0.525f, 0.060f, ButtonKind.Tap),
        };

        private const float MmapFx = 0.900f, MmapFy = 0.150f;
        private const float MmapD = 0.260f, MmapDBig = 0.440f;

        private class Button
        {
            public ButtonDef def;
            public RectTransform rt;
            public Image bg;
            public Text caption;
            public Image cooldown;
            public Rect screenRect; // px, recomputed on layout
            public bool pressed;
            public float cdLeft, cdTotal;
            public bool activeTint;
            public int finger = -1;
        }

        private enum Assign { None, Button, Joystick, Minimap }

        private struct TouchState
        {
            public Assign assign;
            public int buttonIdx;
            public float startTime;
            public Vector2 startPos;
        }

        private Canvas _canvas;
        private readonly List<Button> _buttons = new List<Button>();
        private readonly Dictionary<int, TouchState> _touches = new Dictionary<int, TouchState>();

        private Image _joyBase, _joyKnob;
        private RectTransform _joyBaseRt, _joyKnobRt;
        private int _joyFinger = -1;
        private Vector2 _joyOrigin;
        private Vector2 _joystick;
        private const float JoyRadiusRef = 110f; // reference px (at 1080p height)

        private RawImage _minimap;
        private RectTransform _minimapRt;
        private bool _minimapBig;
        private float _minimapTapT;
        private Vector2 _minimapTapPos;
        private int _minimapFinger = -1;

        private bool _customize;
        private readonly Dictionary<int, int> _czFingers = new Dictionary<int, int>(); // finger -> button idx
        private readonly Dictionary<int, Vector2> _czGrab = new Dictionary<int, Vector2>(); // finger -> grab offset px
        private int _czPinchA = -1, _czPinchB = -1, _czPinchBtn = -1;
        private float _czPinchDist, _czPinchD0;

        private bool _nadeFrag = true;
        private int _grenadeCount, _smokeCount, _armorPlates;

        // Crosshair (center-screen, TPP).
        private Image _cross;
        private RectTransform _crossRt;
        private float _crossPulse;

        // Compass strip (top-center, fed by camera heading).
        private const float PxPerDeg = 4f;
        private RectTransform _compassStrip;
        private Image _zoneMarker;
        private float _heading;
        private float? _zoneBearing;

        // Killfeed anchor (top-left; owned by the Match system).
        private RectTransform _killfeedAnchor;

        private static Font _font;

        /// <summary>Joystick vector: x right+, y up+ (forward), -1..1.</summary>
        public Vector2 Joystick => _joystick;

        /// <summary>RawImage the Match system paints the minimap into.</summary>
        public RawImage MinimapView => _minimap;

        public Texture MinimapTexture
        {
            set { if (_minimap != null) _minimap.texture = value; }
        }

        /// <summary>Crosshair spread pulse (Arsenal calls this on each shot).</summary>
        public void NotifyFired() { _crossPulse = 1f; }

        public bool CrosshairVisible
        {
            set { if (_cross != null) _cross.gameObject.SetActive(value); }
        }

        /// <summary>Anchor slot for the Match system's killfeed (top-left).</summary>
        public RectTransform KillfeedAnchor => _killfeedAnchor;

        /// <summary>Feed the compass strip with the camera heading, degrees.</summary>
        public void SetHeading(float degrees)
        {
            _heading = Normalize360(degrees);
            if (_compassStrip == null) return;
            float x = 260f - (_heading + 360f) * PxPerDeg;
            _compassStrip.anchoredPosition = new Vector2(x, 0f);
            UpdateZoneMarker();
        }

        /// <summary>Next-zone bearing marker on the compass (null hides it).</summary>
        public void SetZoneBearing(float? bearing)
        {
            _zoneBearing = bearing;
            UpdateZoneMarker();
        }

        private static float Normalize360(float d)
        {
            d %= 360f;
            if (d < 0f) d += 360f;
            return d;
        }

        private void UpdateZoneMarker()
        {
            if (_zoneMarker == null) return;
            if (!_zoneBearing.HasValue)
            {
                _zoneMarker.gameObject.SetActive(false);
                return;
            }
            float rel = Mathf.DeltaAngle(_heading, _zoneBearing.Value);
            if (Mathf.Abs(rel) > 62f)
            {
                _zoneMarker.gameObject.SetActive(false);
                return;
            }
            _zoneMarker.gameObject.SetActive(true);
            _zoneMarker.rectTransform.anchoredPosition =
                new Vector2(260f + rel * PxPerDeg, -2f);
        }

        public bool IsCustomizing => _customize;

        // ------------------------------------------------------------------
        private void Awake()
        {
            ControlSettings.LoadAll();
            _font = Resources.GetBuiltinResource<Font>("Arial.ttf");
            BuildCanvas();
            BuildButtons();
            BuildJoystick();
            BuildMinimap();
            BuildCrosshair();
            BuildCompass();
            BuildKillfeedAnchor();
            ApplyLayout();
            ApplyOpacity();
        }

        private void BuildCanvas()
        {
            var go = new GameObject("TouchHUDCanvas");
            go.transform.SetParent(transform, false);
            _canvas = go.AddComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _canvas.sortingOrder = 10;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.matchWidthOrHeight = 0.5f;
            go.AddComponent<GraphicRaycaster>();
        }

        private void BuildButtons()
        {
            foreach (var def in Layout)
            {
                var b = new Button { def = def };
                var go = new GameObject("Btn_" + def.id);
                go.transform.SetParent(_canvas.transform, false);
                b.rt = go.AddComponent<RectTransform>();
                b.bg = go.AddComponent<Image>();
                b.bg.sprite = SpriteFrom(HudIcons.PanelNormal());
                b.bg.raycastTarget = false;

                var iconGo = new GameObject("Icon");
                iconGo.transform.SetParent(go.transform, false);
                var iconRt = iconGo.AddComponent<RectTransform>();
                NovaUtils.PlaceByFraction(iconRt, 0.12f, 0.06f, 0.88f, 0.72f);
                var iconImg = iconGo.AddComponent<Image>();
                iconImg.sprite = SpriteFrom(HudIcons.Glyph(def.icon));
                iconImg.raycastTarget = false;
                iconImg.preserveAspect = true;

                var capGo = new GameObject("Caption");
                capGo.transform.SetParent(go.transform, false);
                var capRt = capGo.AddComponent<RectTransform>();
                NovaUtils.PlaceByFraction(capRt, 0.02f, 0.72f, 0.98f, 0.98f);
                b.caption = capGo.AddComponent<Text>();
                b.caption.font = _font;
                b.caption.text = def.caption;
                b.caption.alignment = TextAnchor.MiddleCenter;
                b.caption.color = new Color(1, 1, 1, 0.85f);
                b.caption.raycastTarget = false;
                b.caption.resizeTextForBestFit = true;
                b.caption.resizeTextMinSize = 8;
                b.caption.resizeTextMaxSize = 40;

                var cdGo = new GameObject("Cooldown");
                cdGo.transform.SetParent(go.transform, false);
                var cdRt = cdGo.AddComponent<RectTransform>();
                NovaUtils.PlaceByFraction(cdRt, 0f, 0f, 1f, 1f);
                b.cooldown = cdGo.AddComponent<Image>();
                b.cooldown.sprite = SpriteFrom(HudIcons.PanelNormal());
                b.cooldown.color = new Color(0, 0, 0, 0.55f);
                b.cooldown.type = Image.Type.Filled;
                b.cooldown.fillMethod = Image.FillMethod.Radial360;
                b.cooldown.fillOrigin = (int)Image.Origin360.Top;
                b.cooldown.raycastTarget = false;
                b.cooldown.gameObject.SetActive(false);

                _buttons.Add(b);
            }
        }

        private static readonly Dictionary<Texture2D, Sprite> _spriteCache =
            new Dictionary<Texture2D, Sprite>();

        private static Sprite SpriteFrom(Texture2D tex)
        {
            Sprite s;
            if (_spriteCache.TryGetValue(tex, out s)) return s;
            s = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height),
                new Vector2(0.5f, 0.5f), 100f);
            _spriteCache[tex] = s;
            return s;
        }

        private void BuildJoystick()
        {
            var baseGo = new GameObject("JoystickBase");
            baseGo.transform.SetParent(_canvas.transform, false);
            _joyBaseRt = baseGo.AddComponent<RectTransform>();
            _joyBase = baseGo.AddComponent<Image>();
            _joyBase.sprite = SpriteFrom(HudIcons.JoystickBase());
            _joyBase.raycastTarget = false;
            baseGo.SetActive(false);

            var knobGo = new GameObject("JoystickKnob");
            knobGo.transform.SetParent(_canvas.transform, false);
            _joyKnobRt = knobGo.AddComponent<RectTransform>();
            _joyKnob = knobGo.AddComponent<Image>();
            _joyKnob.sprite = SpriteFrom(HudIcons.JoystickKnob());
            _joyKnob.raycastTarget = false;
            knobGo.SetActive(false);
        }

        private void BuildMinimap()
        {
            // Circular-masked RawImage placeholder; the Match system paints
            // the live minimap texture into MinimapView.texture.
            var maskGo = new GameObject("MinimapMask");
            maskGo.transform.SetParent(_canvas.transform, false);
            var maskImg = maskGo.AddComponent<Image>();
            maskImg.sprite = SpriteFrom(HudIcons.CircleMask());
            maskImg.raycastTarget = false;
            var mask = maskGo.AddComponent<Mask>();
            mask.showMaskGraphic = false;
            var go = new GameObject("Minimap");
            go.transform.SetParent(maskGo.transform, false);
            _minimapRt = go.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(_minimapRt, 0f, 0f, 1f, 1f);
            _minimap = go.AddComponent<RawImage>();
            _minimap.raycastTarget = false;
            _minimap.color = new Color(0.05f, 0.07f, 0.10f, 0.85f);
            _minimapMaskRt = maskGo.GetComponent<RectTransform>();
        }

        private RectTransform _minimapMaskRt;

        // ---------------- layout ----------------
        /// <summary>Recompute screen rects from fractions + layout overrides.</summary>
        public void ApplyLayout()
        {
            float W = Screen.width, H = Screen.height;
            foreach (var b in _buttons)
            {
                float fx = b.def.fx, fy = b.def.fy, d = b.def.d;
                ControlSettings.LayoutEntry ov;
                if (ControlSettings.TryGetLayout(b.def.id, out ov))
                {
                    fx = ov.x; fy = ov.y; d = ov.d;
                }
                float dpx = d * H;
                // Anchor at a point; size in reference px so CanvasScaler scales it.
                NovaUtils.PlaceByFraction(b.rt, fx, 1f - fy, fx, 1f - fy);
                b.rt.sizeDelta = new Vector2(d * 1080f, d * 1080f);
                b.screenRect = new Rect(fx * W - dpx * 0.5f, (1f - fy) * H - dpx * 0.5f, dpx, dpx);
                b.bg.color = b.pressed
                    ? new Color(1.0f, 0.55f, 0.10f, 0.60f)
                    : Color.white;
                b.bg.sprite = b.activeTint ? SpriteFrom(HudIcons.PanelActive())
                                           : SpriteFrom(HudIcons.PanelNormal());
            }
            float md = (_minimapBig ? MmapDBig : MmapD);
            NovaUtils.PlaceByFraction(_minimapMaskRt, MmapFx, 1f - MmapFy, MmapFx, 1f - MmapFy);
            _minimapMaskRt.sizeDelta = new Vector2(md * 1080f, md * 1080f);
        }

        public void ApplyOpacity()
        {
            float a = ControlSettings.HudOpacity;
            foreach (var b in _buttons)
            {
                var grp = b.rt.GetComponent<CanvasGroup>();
                if (grp == null) grp = b.rt.gameObject.AddComponent<CanvasGroup>();
                grp.alpha = a;
            }
        }

        private Rect MinimapRect()
        {
            float md = (_minimapBig ? MmapDBig : MmapD) * Screen.height;
            return new Rect(MmapFx * Screen.width - md * 0.5f,
                (1f - MmapFy) * Screen.height - md * 0.5f, md, md);
        }

        private Rect JoyZone()
        {
            float W = Screen.width, H = Screen.height;
            return new Rect(0, H * 0.38f, W * 0.45f, H * 0.62f);
        }

        // ---------------- crosshair / compass / killfeed ----------------
        private void BuildCrosshair()
        {
            var go = new GameObject("Crosshair");
            go.transform.SetParent(_canvas.transform, false);
            _crossRt = go.AddComponent<RectTransform>();
            _crossRt.anchorMin = _crossRt.anchorMax = new Vector2(0.5f, 0.5f);
            _crossRt.anchoredPosition = Vector2.zero;
            _crossRt.sizeDelta = new Vector2(96f, 96f);
            _cross = go.AddComponent<Image>();
            _cross.sprite = SpriteFrom(HudIcons.Crosshair());
            _cross.raycastTarget = false;
        }

        private void BuildCompass()
        {
            var go = new GameObject("Compass");
            go.transform.SetParent(_canvas.transform, false);
            var rt = go.AddComponent<RectTransform>();
            rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 1f);
            rt.anchoredPosition = new Vector2(0f, -30f);
            rt.sizeDelta = new Vector2(520f, 44f);
            var bg = go.AddComponent<Image>();
            bg.sprite = SpriteFrom(HudIcons.PanelNormal());
            bg.raycastTarget = false;
            var mask = go.AddComponent<Mask>();
            mask.showMaskGraphic = true;

            var stripGo = new GameObject("Strip");
            stripGo.transform.SetParent(go.transform, false);
            _compassStrip = stripGo.AddComponent<RectTransform>();
            _compassStrip.anchorMin = _compassStrip.anchorMax = new Vector2(0f, 0.5f);
            _compassStrip.pivot = new Vector2(0f, 0.5f);
            _compassStrip.sizeDelta = new Vector2(PxPerDeg * 720f, 44f);

            string[] cards = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" };
            for (int deg = 0; deg < 720; deg += 15)
            {
                bool major = deg % 45 == 0;
                var tickGo = new GameObject("Tick");
                tickGo.transform.SetParent(stripGo.transform, false);
                var tickRt = tickGo.AddComponent<RectTransform>();
                tickRt.anchorMin = tickRt.anchorMax = new Vector2(0f, 0.5f);
                tickRt.pivot = new Vector2(0.5f, 0.5f);
                tickRt.anchoredPosition = new Vector2(deg * PxPerDeg, 12f);
                tickRt.sizeDelta = new Vector2(2f, major ? 14f : 8f);
                var tickImg = tickGo.AddComponent<Image>();
                tickImg.sprite = SpriteFrom(HudIcons.WhitePixel());
                tickImg.color = new Color(1, 1, 1, major ? 0.9f : 0.4f);
                tickImg.raycastTarget = false;

                var labGo = new GameObject("Label");
                labGo.transform.SetParent(stripGo.transform, false);
                var labRt = labGo.AddComponent<RectTransform>();
                labRt.anchorMin = labRt.anchorMax = new Vector2(0f, 0.5f);
                labRt.pivot = new Vector2(0.5f, 0.5f);
                labRt.anchoredPosition = new Vector2(deg * PxPerDeg, -10f);
                labRt.sizeDelta = new Vector2(64f, 24f);
                var lab = labGo.AddComponent<Text>();
                lab.font = _font;
                lab.alignment = TextAnchor.MiddleCenter;
                lab.raycastTarget = false;
                if (major)
                {
                    lab.text = cards[(deg / 45) % 8];
                    lab.fontSize = 20;
                    lab.color = HudIcons.Accent;
                }
                else if (deg % 30 == 0)
                {
                    lab.text = (deg % 360).ToString();
                    lab.fontSize = 14;
                    lab.color = new Color(1, 1, 1, 0.6f);
                }
                else
                {
                    Destroy(labGo);
                }
            }

            // Center caret.
            var caretGo = new GameObject("Caret");
            caretGo.transform.SetParent(go.transform, false);
            var caretRt = caretGo.AddComponent<RectTransform>();
            caretRt.anchorMin = caretRt.anchorMax = new Vector2(0.5f, 1f);
            caretRt.pivot = new Vector2(0.5f, 0f);
            caretRt.anchoredPosition = new Vector2(0f, -2f);
            caretRt.sizeDelta = new Vector2(24f, 18f);
            var caretImg = caretGo.AddComponent<Image>();
            caretImg.sprite = SpriteFrom(HudIcons.Caret());
            caretImg.raycastTarget = false;

            // Zone bearing marker (hidden until SetZoneBearing is called).
            var zmGo = new GameObject("ZoneMarker");
            zmGo.transform.SetParent(go.transform, false);
            var zmRt = zmGo.AddComponent<RectTransform>();
            zmRt.anchorMin = zmRt.anchorMax = new Vector2(0f, 0.5f);
            zmRt.pivot = new Vector2(0.5f, 0.5f);
            zmRt.sizeDelta = new Vector2(28f, 28f);
            _zoneMarker = zmGo.AddComponent<Image>();
            _zoneMarker.sprite = SpriteFrom(HudIcons.Glyph(HudIcon.Ping));
            _zoneMarker.color = HudIcons.Accent;
            _zoneMarker.raycastTarget = false;
            zmGo.SetActive(false);
        }

        private void BuildKillfeedAnchor()
        {
            var go = new GameObject("KillfeedAnchor");
            go.transform.SetParent(_canvas.transform, false);
            _killfeedAnchor = go.AddComponent<RectTransform>();
            _killfeedAnchor.anchorMin = _killfeedAnchor.anchorMax = new Vector2(0f, 1f);
            _killfeedAnchor.pivot = new Vector2(0f, 1f);
            _killfeedAnchor.anchoredPosition = new Vector2(16f, -64f);
            _killfeedAnchor.sizeDelta = new Vector2(420f, 320f);
        }
        // ---------------- public setters ----------------
        public void SetGrenadeCount(int n)
        {
            _grenadeCount = n;
            RefreshNadeCaption();
        }

        public void SetSmokeCount(int n)
        {
            _smokeCount = n;
            RefreshNadeCaption();
        }

        public void SetNadeFrag(bool frag)
        {
            _nadeFrag = frag;
            RefreshNadeCaption();
        }

        public bool NadeIsFrag => _nadeFrag;

        private void RefreshNadeCaption()
        {
            var b = FindButton("nade");
            if (b == null) return;
            int n = _nadeFrag ? _grenadeCount : _smokeCount;
            b.caption.text = (_nadeFrag ? "FRAG " : "SMK ") + n;
        }

        public void SetArmorPlates(int n)
        {
            _armorPlates = n;
            var b = FindButton("armor");
            if (b != null) b.caption.text = "ARMOR " + n;
        }

        public void SetAdsActive(bool on) { SetActiveTint("ads", on); }
        public void SetSprintActive(bool on) { SetActiveTint("sprint", on); }

        private void SetActiveTint(string id, bool on)
        {
            var b = FindButton(id);
            if (b == null) return;
            b.activeTint = on;
            b.bg.sprite = on ? SpriteFrom(HudIcons.PanelActive())
                             : SpriteFrom(HudIcons.PanelNormal());
        }

        /// <summary>Radial cooldown sweep on a button (grenade, armor, ...).</summary>
        public void StartCooldown(string id, float sec)
        {
            var b = FindButton(id);
            if (b == null) return;
            b.cdTotal = Mathf.Max(sec, 0.01f);
            b.cdLeft = sec;
            b.cooldown.gameObject.SetActive(true);
        }

        private Button FindButton(string id)
        {
            for (int i = 0; i < _buttons.Count; i++)
                if (_buttons[i].def.id == id) return _buttons[i];
            return null;
        }

        /// <summary>
        /// True when this finger began on a HUD button, the joystick zone or
        /// the minimap — i.e. NOT a look drag. FPSController calls this.
        /// </summary>
        public bool IsUiTouch(int fingerId)
        {
            TouchState st;
            if (_touches.TryGetValue(fingerId, out st))
                return st.assign != Assign.None;
            return false;
        }

        // ---------------- customize mode ----------------
        public void SetCustomize(bool on)
        {
            _customize = on;
            _touches.Clear();
            _czFingers.Clear();
            _czGrab.Clear();
            _joyFinger = -1;
            _joystick = Vector2.zero;
            _joyBase.gameObject.SetActive(false);
            _joyKnob.gameObject.SetActive(false);
            if (!on) ControlSettings.SaveAll();
        }

        // ---------------- per-frame ----------------
        private void Update()
        {
            int n = Input.touchCount;
            for (int i = 0; i < n; i++)
            {
                Touch t = Input.GetTouch(i);
                switch (t.phase)
                {
                    case TouchPhase.Began: OnTouchBegan(t); break;
                    case TouchPhase.Moved:
                    case TouchPhase.Stationary: OnTouchHeld(t); break;
                    case TouchPhase.Ended:
                    case TouchPhase.Canceled: OnTouchEnded(t); break;
                }
            }
            // Cooldown sweeps (allocation-free).
            for (int i = 0; i < _buttons.Count; i++)
            {
                var b = _buttons[i];
                if (b.cdLeft > 0f)
                {
                    b.cdLeft = Mathf.Max(b.cdLeft - Time.deltaTime, 0f);
                    b.cooldown.fillAmount = b.cdLeft / b.cdTotal;
                    if (b.cdLeft <= 0f) b.cooldown.gameObject.SetActive(false);
                }
            }
            // Crosshair spread pulse.
            if (_crossPulse > 0f && _crossRt != null)
            {
                _crossPulse = Mathf.Max(_crossPulse - Time.deltaTime * 6f, 0f);
                float s = 1f + 0.35f * _crossPulse;
                _crossRt.localScale = new Vector3(s, s, 1f);
            }
            if (_customize) UpdateCustomizePinch();
        }

        private int ButtonAt(Vector2 p)
        {
            // Topmost = reverse insertion order; 8px slop.
            for (int i = _buttons.Count - 1; i >= 0; i--)
            {
                var r = _buttons[i].screenRect;
                r.xMin -= 8; r.yMin -= 8; r.xMax += 8; r.yMax += 8;
                if (r.Contains(p)) return i;
            }
            return -1;
        }

        private void OnTouchBegan(Touch t)
        {
            var st = new TouchState
            {
                assign = Assign.None,
                buttonIdx = -1,
                startTime = Time.time,
                startPos = t.position
            };
            if (_customize)
            {
                int bi = ButtonAt(t.position);
                if (bi >= 0)
                {
                    var b = _buttons[bi];
                    _czFingers[t.fingerId] = bi;
                    _czGrab[t.fingerId] = t.position - RectCenter(b.screenRect);
                    // Pinch: second finger on the same button starts resize.
                    foreach (var kv in _czFingers)
                    {
                        if (kv.Key != t.fingerId && kv.Value == bi)
                        {
                            _czPinchA = kv.Key; _czPinchB = t.fingerId;
                            _czPinchBtn = bi;
                            _czPinchDist = Vector2.Distance(
                                GetTouchPos(kv.Key), t.position);
                            _czPinchD0 = _buttons[bi].def.d;
                            break;
                        }
                    }
                    st.assign = Assign.Button;
                    st.buttonIdx = bi;
                }
                _touches[t.fingerId] = st;
                return;
            }

            int hit = ButtonAt(t.position);
            if (hit >= 0)
            {
                st.assign = Assign.Button;
                st.buttonIdx = hit;
                ButtonDown(_buttons[hit], t.fingerId);
            }
            else if (MinimapRect().Contains(t.position))
            {
                st.assign = Assign.Minimap;
                _minimapFinger = t.fingerId;
                _minimapTapT = Time.time;
                _minimapTapPos = t.position;
            }
            else if (_joyFinger == -1 && JoyZone().Contains(t.position))
            {
                st.assign = Assign.Joystick;
                _joyFinger = t.fingerId;
                _joyOrigin = t.position;
                _joystick = Vector2.zero;
                ShowJoystick(t.position, t.position);
            }
            _touches[t.fingerId] = st;
        }

        private void OnTouchHeld(Touch t)
        {
            TouchState st;
            if (!_touches.TryGetValue(t.fingerId, out st)) return;
            if (_customize)
            {
                int bi;
                if (_czFingers.TryGetValue(t.fingerId, out bi))
                {
                    var b = _buttons[bi];
                    Vector2 grab = _czGrab[t.fingerId];
                    Vector2 nc = t.position - grab;
                    float half = Mathf.Min(b.screenRect.width, b.screenRect.height) * 0.5f;
                    nc.x = Mathf.Clamp(nc.x, half, Screen.width - half);
                    nc.y = Mathf.Clamp(nc.y, half, Screen.height - half);
                    b.screenRect = new Rect(nc.x - half, nc.y - half,
                        b.screenRect.width, b.screenRect.height);
                    // Move the anchored rect to match (fractional anchor).
                    float fx = nc.x / Screen.width;
                    float fy = 1f - nc.y / Screen.height;
                    float d = b.screenRect.height / Screen.height;
                    NovaUtils.PlaceByFraction(b.rt, fx, 1f - fy, fx, 1f - fy);
                    b.rt.sizeDelta = new Vector2(d * 1080f, d * 1080f);
                    ControlSettings.SetLayout(b.def.id, fx, fy, d);
                }
                return;
            }
            if (st.assign == Assign.Joystick && t.fingerId == _joyFinger)
            {
                float scale = Screen.height / 1080f;
                float radius = JoyRadiusRef * scale;
                Vector2 d = t.position - _joyOrigin;
                if (d.magnitude > radius) d = d.normalized * radius;
                _joystick = new Vector2(d.x / radius, -d.y / radius);
                ShowJoystick(_joyOrigin, _joyOrigin + d);
            }
        }

        private void OnTouchEnded(Touch t)
        {
            TouchState st;
            if (!_touches.TryGetValue(t.fingerId, out st))
            {
                _touches.Remove(t.fingerId);
                return;
            }
            if (_customize)
            {
                _czFingers.Remove(t.fingerId);
                _czGrab.Remove(t.fingerId);
                if (t.fingerId == _czPinchA || t.fingerId == _czPinchB)
                {
                    _czPinchA = _czPinchB = -1; _czPinchBtn = -1;
                    ControlSettings.SaveAll();
                }
                else
                {
                    ControlSettings.SaveAll();
                }
                _touches.Remove(t.fingerId);
                return;
            }
            if (st.assign == Assign.Button && st.buttonIdx >= 0)
            {
                var b = _buttons[st.buttonIdx];
                ButtonUp(b, t.fingerId, inside: b.screenRect.Contains(t.position));
            }
            else if (st.assign == Assign.Joystick && t.fingerId == _joyFinger)
            {
                _joyFinger = -1;
                _joystick = Vector2.zero;
                _joyBase.gameObject.SetActive(false);
                _joyKnob.gameObject.SetActive(false);
            }
            else if (st.assign == Assign.Minimap && t.fingerId == _minimapFinger)
            {
                float dt = Time.time - _minimapTapT;
                if (dt < 0.35f && Vector2.Distance(t.position, _minimapTapPos) < 24f)
                {
                    _minimapBig = !_minimapBig;
                    ApplyLayout();
                    MinimapPressed?.Invoke();
                }
                _minimapFinger = -1;
            }
            _touches.Remove(t.fingerId);
        }

        private void UpdateCustomizePinch()
        {
            if (_czPinchBtn < 0 || _czPinchA < 0 || _czPinchB < 0) return;
            Vector2 pa = GetTouchPos(_czPinchA), pb = GetTouchPos(_czPinchB);
            if (pa.x < 0 || pb.x < 0) return;
            float dist = Vector2.Distance(pa, pb);
            if (dist < 1f || _czPinchDist < 1f) return;
            var b = _buttons[_czPinchBtn];
            float d = Mathf.Clamp(_czPinchD0 * (dist / _czPinchDist), 0.04f, 0.28f);
            Vector2 ctr = RectCenter(b.screenRect);
            float dpx = d * Screen.height;
            b.screenRect = new Rect(ctr.x - dpx * 0.5f, ctr.y - dpx * 0.5f, dpx, dpx);
            float fx = ctr.x / Screen.width, fy = 1f - ctr.y / Screen.height;
            NovaUtils.PlaceByFraction(b.rt, fx, 1f - fy, fx, 1f - fy);
            b.rt.sizeDelta = new Vector2(d * 1080f, d * 1080f);
            ControlSettings.SetLayout(b.def.id, fx, fy, d);
        }

        private static Vector2 GetTouchPos(int fingerId)
        {
            int n = Input.touchCount;
            for (int i = 0; i < n; i++)
            {
                Touch t = Input.GetTouch(i);
                if (t.fingerId == fingerId) return t.position;
            }
            return new Vector2(-1, -1);
        }

        private static Vector2 RectCenter(Rect r)
        {
            return new Vector2(r.x + r.width * 0.5f, r.y + r.height * 0.5f);
        }

        private void ShowJoystick(Vector2 origin, Vector2 knob)
        {
            float scale = Screen.height / 1080f;
            float baseR = JoyRadiusRef * scale;
            _joyBase.gameObject.SetActive(true);
            _joyKnob.gameObject.SetActive(true);
            PositionAt(_joyBaseRt, origin, baseR * 2f);
            PositionAt(_joyKnobRt, knob, baseR * 0.9f);
        }

        private static void PositionAt(RectTransform rt, Vector2 screenPos, float sizePx)
        {
            // ScreenSpaceOverlay + ScaleWithScreenSize: anchoredPosition is in
            // reference px, so convert from screen px.
            float s = Screen.height / 1080f;
            rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 0.5f);
            rt.anchoredPosition = new Vector2(
                (screenPos.x - Screen.width * 0.5f) / s,
                (screenPos.y - Screen.height * 0.5f) / s);
            rt.sizeDelta = new Vector2(sizePx / s, sizePx / s);
        }

        // ---------------- button press dispatch ----------------
        private void ButtonDown(Button b, int finger)
        {
            b.pressed = true;
            b.finger = finger;
            b.bg.color = new Color(1.0f, 0.55f, 0.10f, 0.60f); // orange pressed
            switch (b.def.id)
            {
                case "fire": FireDown?.Invoke(); break;
                case "jump": JumpDown?.Invoke(); break;
                case "crouch": CrouchDown?.Invoke(); break;
                case "grenade": GrenadeDown?.Invoke(); break;
                case "inspect": InspectDown?.Invoke(); break;
            }
        }

        private void ButtonUp(Button b, int finger, bool inside)
        {
            if (b.finger != finger) return;
            b.pressed = false;
            b.finger = -1;
            b.bg.color = Color.white;
            switch (b.def.id)
            {
                case "fire": FireUp?.Invoke(); break;
                case "jump": JumpUp?.Invoke(); break;
                case "crouch": CrouchUp?.Invoke(); break;
                case "grenade": GrenadeUp?.Invoke(); break;
                case "inspect": InspectUp?.Invoke(); break;
            }
            if (!inside) return; // tap actions need release inside the button
            switch (b.def.id)
            {
                case "ads": AdsPressed?.Invoke(); break;
                case "prone": PronePressed?.Invoke(); break;
                case "sprint": SprintPressed?.Invoke(); break;
                case "reload": ReloadPressed?.Invoke(); break;
                case "swap": SwapPressed?.Invoke(); break;
                case "armor": ArmorPressed?.Invoke(); break;
                case "skill": SkillPressed?.Invoke(); break;
                case "emote": EmotePressed?.Invoke(); break;
                case "ping": PingPressed?.Invoke(); break;
                case "nade": NadeSelectPressed?.Invoke(); break;
            }
        }
    }
}
