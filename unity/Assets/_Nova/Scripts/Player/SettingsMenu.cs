using System;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Player;

namespace NovaMobile.Player
{
    /// <summary>
    /// CODM-style settings screen, built at runtime in uGUI. Ported from
    /// settings_menu.gd: dark military theme, orange/white accents, 7
    /// sections. All changes persist via ControlSettings (JSON in
    /// Application.persistentDataPath).
    ///
    /// Sections: Sensitivity, Gyroscope, Aim Assist, Fire Mode, Feel,
    /// HUD Layout, Graphics.
    /// </summary>
    public class SettingsMenu : MonoBehaviour
    {
        private static readonly Color Accent = new Color(1.0f, 0.60f, 0.12f);
        private static readonly Color Bg = new Color(0.03f, 0.04f, 0.06f, 0.96f);
        private static readonly Color PanelCol = new Color(0.08f, 0.10f, 0.13f, 1.0f);
        private static readonly Color TextDim = new Color(0.75f, 0.78f, 0.82f);

        private static readonly string[] QualityNames =
            { "LOW", "BALANCED", "HIGH", "ULTRA" };

        public TouchHUD Hud; // wired by Match; found lazily otherwise

        private GameObject _root;
        private Font _font;
        private float _cursor;
        private RectTransform _content;
        private const float ContentWidth = 700f;

        // ------------------------------------------------------------------
        public bool IsOpen => _root != null;

        public void Open()
        {
            if (_root != null) return;
            ControlSettings.LoadAll();
            _font = Resources.GetBuiltinResource<Font>("Arial.ttf");
            if (Hud == null) Hud = FindFirstObjectByType<TouchHUD>();
            Build();
        }

        public void Close()
        {
            if (_root != null) Destroy(_root);
            _root = null;
        }

        // ---------------- build ----------------
        private void Build()
        {
            _root = new GameObject("SettingsMenu");
            var canvas = _root.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 30;
            _root.AddComponent<GraphicRaycaster>();

            var bg = NewImage(_root.transform, "Dim", Bg);
            Stretch(bg.rectTransform);

            // Centered panel.
            var panelGo = new GameObject("Panel");
            panelGo.transform.SetParent(_root.transform, false);
            var panelRt = panelGo.AddComponent<RectTransform>();
            panelRt.anchorMin = panelRt.anchorMax = new Vector2(0.5f, 0.5f);
            float panelH = Mathf.Min(660f, Screen.height - 60f);
            panelRt.sizeDelta = new Vector2(760f, panelH);
            var panelImg = panelGo.AddComponent<Image>();
            panelImg.sprite = SpriteOf(HudIcons.PanelNormal());
            panelImg.color = PanelCol;
            panelImg.type = Image.Type.Sliced;

            // Title bar.
            var title = NewText(panelGo.transform, "SETTINGS", 30, Color.white,
                TextAnchor.MiddleLeft);
            PlaceTop(title.rectTransform, 24f, 16f, 500f, 48f);
            var xBtn = NewButton(panelGo.transform, "X", 24, Accent);
            PlaceTop(xBtn.GetComponent<RectTransform>(), 760f - 80f, 16f, 56f, 48f);
            xBtn.onClick.AddListener(Close);

            // Scroll area.
            var scrollGo = new GameObject("Scroll");
            scrollGo.transform.SetParent(panelGo.transform, false);
            var scrollRt = scrollGo.AddComponent<RectTransform>();
            scrollRt.anchorMin = new Vector2(0.5f, 0.5f);
            scrollRt.anchorMax = new Vector2(0.5f, 0.5f);
            scrollRt.pivot = new Vector2(0.5f, 0.5f);
            scrollRt.anchoredPosition = new Vector2(0f, -20f);
            scrollRt.sizeDelta = new Vector2(720f, panelH - 110f);
            var scroll = scrollGo.AddComponent<ScrollRect>();
            scrollGo.AddComponent<RectMask2D>();
            scroll.horizontal = false;

            var vpGo = new GameObject("Viewport");
            vpGo.transform.SetParent(scrollGo.transform, false);
            var vpRt = vpGo.AddComponent<RectTransform>();
            Stretch(vpRt);
            scroll.viewport = vpRt;

            var contentGo = new GameObject("Content");
            contentGo.transform.SetParent(vpGo.transform, false);
            _content = contentGo.AddComponent<RectTransform>();
            _content.anchorMin = new Vector2(0.5f, 1f);
            _content.anchorMax = new Vector2(0.5f, 1f);
            _content.pivot = new Vector2(0.5f, 1f);
            _content.anchoredPosition = Vector2.zero;
            scroll.content = _content;

            _cursor = 8f;
            BuildSections();
            _content.sizeDelta = new Vector2(ContentWidth, _cursor + 16f);
        }

        private void BuildSections()
        {
            // --- Sensitivity ---
            Header("SENSITIVITY");
            SliderRow("Camera", "cam_sens", 0.2f, 3.0f, 0.05f, "0.00");
            SliderRow("ADS", "ads_sens", 0.1f, 2.0f, 0.05f, "0.00");
            SliderRow("4x Scope", "zoom4_sens", 0.1f, 1.5f, 0.05f, "0.00");
            SliderRow("8x Scope", "zoom8_sens", 0.1f, 1.5f, 0.05f, "0.00");
            ToggleRow("Invert Y", "invert_y");
            // --- Gyroscope ---
            Header("GYROSCOPE");
            ToggleRow("Gyro Aim", "gyro_enabled");
            SliderRow("Gyro Sensitivity", "gyro_sens", 0.2f, 3.0f, 0.05f, "0.00");
            // --- Aim assist ---
            Header("AIM ASSIST");
            ToggleRow("Aim Assist", "aim_assist");
            SliderRow("Assist Strength", "assist_strength", 0.0f, 1.0f, 0.05f, "0.00");
            // --- Fire mode ---
            Header("FIRE MODE");
            FireModeRow();
            // --- Feel ---
            Header("FEEL");
            ToggleRow("Haptics", "haptics");
            SliderRow("HUD Opacity", "hud_opacity", 0.3f, 1.0f, 0.05f, "0.00",
                onChanged: () => Hud?.ApplyOpacity());
            // --- HUD layout ---
            Header("HUD LAYOUT");
            ActionRow("Move / resize buttons", "CUSTOMIZE", () =>
            {
                if (Hud != null) Hud.SetCustomize(true);
                Close();
            });
            ActionRow("Restore CODM default", "RESET", () =>
            {
                ControlSettings.ClearLayout();
                ControlSettings.SaveAll();
                Hud?.ApplyLayout();
            });
            // --- Graphics ---
            Header("GRAPHICS");
            var gfxBtn = ActionRow("Quality preset", QualityNames[ControlSettings.QualityLevel], null);
            gfxBtn.onClick.AddListener(() =>
            {
                int next = (ControlSettings.QualityLevel + 1) % QualityNames.Length;
                ControlSettings.SetQuality(next);
                ControlSettings.SaveAll();
                QualitySettings.SetQualityLevel(next, true);
                var t = gfxBtn.GetComponentInChildren<Text>();
                if (t != null) t.text = QualityNames[next];
            });
            QualitySettings.SetQualityLevel(ControlSettings.QualityLevel, true);
        }

        // ---------------- row builders ----------------
        private void Header(string text)
        {
            var l = NewText(_content, text, 20, Accent, TextAnchor.MiddleLeft);
            PlaceRow(l.rectTransform, 40f);
            _cursor += 40f;
            var rule = NewImage(_content, "Rule", new Color(1f, 0.6f, 0.12f, 0.35f));
            PlaceRow(rule.rectTransform, 2f, indent: 0f);
            _cursor += 10f;
        }

        private void SliderRow(string label, string key, float min, float max,
            float step, string fmt, Action onChanged = null)
        {
            var row = new GameObject("Row_" + key);
            row.transform.SetParent(_content, false);
            var rt = row.AddComponent<RectTransform>();
            PlaceRow(rt, 56f);

            var lab = NewText(row.transform, label, 19, TextDim, TextAnchor.MiddleLeft);
            lab.rectTransform.anchorMin = lab.rectTransform.anchorMax = new Vector2(0f, 0.5f);
            lab.rectTransform.pivot = new Vector2(0f, 0.5f);
            lab.rectTransform.anchoredPosition = new Vector2(10f, 0f);
            lab.rectTransform.sizeDelta = new Vector2(220f, 40f);

            var slider = NewSlider(row.transform);
            slider.GetComponent<RectTransform>().anchorMin = slider.GetComponent<RectTransform>().anchorMax = new Vector2(0f, 0.5f);
            slider.GetComponent<RectTransform>().pivot = new Vector2(0f, 0.5f);
            slider.GetComponent<RectTransform>().anchoredPosition = new Vector2(240f, 0f);
            slider.GetComponent<RectTransform>().sizeDelta = new Vector2(320f, 36f);
            slider.minValue = min;
            slider.maxValue = max;
            slider.wholeNumbers = false;

            var val = NewText(row.transform, "", 19, Color.white, TextAnchor.MiddleLeft);
            val.rectTransform.anchorMin = val.rectTransform.anchorMax = new Vector2(0f, 0.5f);
            val.rectTransform.pivot = new Vector2(0f, 0.5f);
            val.rectTransform.anchoredPosition = new Vector2(570f, 0f);
            val.rectTransform.sizeDelta = new Vector2(110f, 40f);

            slider.onValueChanged.AddListener(v =>
            {
                float stepped = Mathf.Round(v / step) * step;
                ControlSettings.SetValue(key, stepped);
                ControlSettings.SaveAll();
                val.text = stepped.ToString(fmt);
                onChanged?.Invoke();
            });
            slider.value = GetFloat(key);
            val.text = GetFloat(key).ToString(fmt);
            _cursor += 56f;
        }

        private void ToggleRow(string label, string key)
        {
            var row = new GameObject("Row_" + key);
            row.transform.SetParent(_content, false);
            var rt = row.AddComponent<RectTransform>();
            PlaceRow(rt, 52f);

            var lab = NewText(row.transform, label, 19, TextDim, TextAnchor.MiddleLeft);
            lab.rectTransform.anchorMin = lab.rectTransform.anchorMax = new Vector2(0f, 0.5f);
            lab.rectTransform.pivot = new Vector2(0f, 0.5f);
            lab.rectTransform.anchoredPosition = new Vector2(10f, 0f);
            lab.rectTransform.sizeDelta = new Vector2(460f, 40f);

            var btn = NewButton(row.transform, "", 19, Color.white);
            btn.GetComponent<RectTransform>().anchorMin = btn.GetComponent<RectTransform>().anchorMax = new Vector2(0f, 0.5f);
            btn.GetComponent<RectTransform>().pivot = new Vector2(0f, 0.5f);
            btn.GetComponent<RectTransform>().anchoredPosition = new Vector2(560f, 0f);
            btn.GetComponent<RectTransform>().sizeDelta = new Vector2(110f, 44f);
            var btnText = btn.GetComponentInChildren<Text>();

            Action paint = () =>
            {
                bool on = GetBool(key);
                btnText.text = on ? "ON" : "OFF";
                btnText.color = on ? Accent : TextDim;
            };
            btn.onClick.AddListener(() =>
            {
                ControlSettings.SetValue(key, !GetBool(key));
                ControlSettings.SaveAll();
                paint();
            });
            paint();
            _cursor += 52f;
        }

        private Button ActionRow(string label, string btnText, Action onPress)
        {
            var row = new GameObject("Row_Action");
            row.transform.SetParent(_content, false);
            var rt = row.AddComponent<RectTransform>();
            PlaceRow(rt, 56f);

            var lab = NewText(row.transform, label, 19, TextDim, TextAnchor.MiddleLeft);
            lab.rectTransform.anchorMin = lab.rectTransform.anchorMax = new Vector2(0f, 0.5f);
            lab.rectTransform.pivot = new Vector2(0f, 0.5f);
            lab.rectTransform.anchoredPosition = new Vector2(10f, 0f);
            lab.rectTransform.sizeDelta = new Vector2(380f, 40f);

            var btn = NewButton(row.transform, btnText, 19, Accent);
            btn.GetComponent<RectTransform>().anchorMin = btn.GetComponent<RectTransform>().anchorMax = new Vector2(0f, 0.5f);
            btn.GetComponent<RectTransform>().pivot = new Vector2(0f, 0.5f);
            btn.GetComponent<RectTransform>().anchoredPosition = new Vector2(420f, 0f);
            btn.GetComponent<RectTransform>().sizeDelta = new Vector2(260f, 48f);
            if (onPress != null) btn.onClick.AddListener(() => onPress());
            _cursor += 56f;
            return btn;
        }

        private void FireModeRow()
        {
            var row = new GameObject("Row_FireMode");
            row.transform.SetParent(_content, false);
            var rt = row.AddComponent<RectTransform>();
            PlaceRow(rt, 64f);

            Button[] btns = new Button[2];
            string[] modes = { "advanced", "simple" };
            for (int i = 0; i < 2; i++)
            {
                int idx = i;
                var b = NewButton(row.transform, modes[i].ToUpper(), 20, TextDim);
                b.GetComponent<RectTransform>().anchorMin = b.GetComponent<RectTransform>().anchorMax = new Vector2(0f, 0.5f);
                b.GetComponent<RectTransform>().pivot = new Vector2(0f, 0.5f);
                b.GetComponent<RectTransform>().anchoredPosition = new Vector2(10f + idx * 240f, 0f);
                b.GetComponent<RectTransform>().sizeDelta = new Vector2(220f, 52f);
                btns[idx] = b;
                b.onClick.AddListener(() =>
                {
                    ControlSettings.SetFireMode(modes[idx]);
                    ControlSettings.SaveAll();
                    PaintFireModes(btns, modes);
                });
            }
            PaintFireModes(btns, modes);
            _cursor += 64f;
        }

        private static void PaintFireModes(Button[] btns, string[] modes)
        {
            for (int i = 0; i < btns.Length; i++)
            {
                bool sel = ControlSettings.FireMode == modes[i];
                var t = btns[i].GetComponentInChildren<Text>();
                if (t != null) t.color = sel ? Accent : TextDim;
            }
        }

        // ---------------- widget helpers ----------------
        private static readonly System.Collections.Generic.Dictionary<Texture2D, Sprite>
            _spriteCache = new System.Collections.Generic.Dictionary<Texture2D, Sprite>();

        private static Sprite SpriteOf(Texture2D tex)
        {
            Sprite s;
            if (_spriteCache.TryGetValue(tex, out s)) return s;
            s = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height),
                new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect,
                new Vector4(40, 40, 40, 40));
            _spriteCache[tex] = s;
            return s;
        }

        private void PlaceRow(RectTransform rt, float h, float indent = 10f)
        {
            rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 1f);
            rt.pivot = new Vector2(0.5f, 1f);
            rt.anchoredPosition = new Vector2(0f, -_cursor);
            rt.sizeDelta = new Vector2(ContentWidth - indent * 2f, h);
        }

        private static void PlaceTop(RectTransform rt, float x, float y, float w, float h)
        {
            rt.anchorMin = rt.anchorMax = new Vector2(0f, 1f);
            rt.pivot = new Vector2(0f, 1f);
            rt.anchoredPosition = new Vector2(x, -y);
            rt.sizeDelta = new Vector2(w, h);
        }

        private static void Stretch(RectTransform rt)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.pivot = new Vector2(0.5f, 0.5f);
            rt.offsetMin = rt.offsetMax = Vector2.zero;
        }

        private Image NewImage(Transform parent, string name, Color col)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.color = col;
            img.raycastTarget = true;
            return img;
        }

        private Text NewText(Transform parent, string text, int size, Color col,
            TextAnchor anchor)
        {
            var go = new GameObject("Text");
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = _font;
            t.text = text;
            t.fontSize = size;
            t.color = col;
            t.alignment = anchor;
            t.raycastTarget = false;
            t.rectTransform.anchorMin = t.rectTransform.anchorMax = new Vector2(0f, 1f);
            t.rectTransform.pivot = new Vector2(0f, 1f);
            return t;
        }

        private Button NewButton(Transform parent, string text, int size, Color col)
        {
            var go = new GameObject("Button");
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.sprite = SpriteOf(HudIcons.PanelNormal());
            img.type = Image.Type.Sliced;
            img.raycastTarget = true;
            var btn = go.AddComponent<Button>();
            btn.transition = Selectable.Transition.None;
            var t = NewText(go.transform, text, size, col, TextAnchor.MiddleCenter);
            var trt = t.rectTransform;
            trt.anchorMin = Vector2.zero;
            trt.anchorMax = Vector2.one;
            trt.pivot = new Vector2(0.5f, 0.5f);
            trt.offsetMin = trt.offsetMax = Vector2.zero;
            btn.targetGraphic = img;
            return btn;
        }

        private Slider NewSlider(Transform parent)
        {
            var go = new GameObject("Slider");
            go.transform.SetParent(parent, false);
            var bg = go.AddComponent<Image>();
            bg.color = new Color(0.16f, 0.18f, 0.22f);
            bg.raycastTarget = true;
            var slider = go.AddComponent<Slider>();
            slider.transition = Selectable.Transition.None;

            var fillGo = new GameObject("Fill");
            fillGo.transform.SetParent(go.transform, false);
            var fillRt = fillGo.AddComponent<RectTransform>();
            fillRt.anchorMin = new Vector2(0f, 0f);
            fillRt.anchorMax = new Vector2(0f, 1f);
            fillRt.pivot = new Vector2(0f, 0.5f);
            fillRt.offsetMin = new Vector2(0f, 4f);
            fillRt.offsetMax = new Vector2(0f, -4f);
            var fillImg = fillGo.AddComponent<Image>();
            fillImg.color = Accent;
            fillImg.raycastTarget = false;

            var handleGo = new GameObject("Handle");
            handleGo.transform.SetParent(go.transform, false);
            var handleRt = handleGo.AddComponent<RectTransform>();
            handleRt.sizeDelta = new Vector2(28f, 28f);
            var handleImg = handleGo.AddComponent<Image>();
            handleImg.sprite = SpriteOf(HudIcons.JoystickKnob());
            handleImg.raycastTarget = false;

            slider.fillRect = fillRt;
            slider.handleRect = handleRt;
            slider.targetGraphic = bg;
            return slider;
        }

        // ---------------- settings access ----------------
        private static float GetFloat(string key)
        {
            switch (key)
            {
                case "cam_sens": return ControlSettings.CamSens;
                case "ads_sens": return ControlSettings.AdsSens;
                case "zoom4_sens": return ControlSettings.Zoom4Sens;
                case "zoom8_sens": return ControlSettings.Zoom8Sens;
                case "gyro_sens": return ControlSettings.GyroSens;
                case "assist_strength": return ControlSettings.AssistStrength;
                case "hud_opacity": return ControlSettings.HudOpacity;
                default: return 1f;
            }
        }

        private static bool GetBool(string key)
        {
            switch (key)
            {
                case "invert_y": return ControlSettings.InvertY;
                case "gyro_enabled": return ControlSettings.GyroEnabled;
                case "aim_assist": return ControlSettings.AimAssist;
                case "haptics": return ControlSettings.Haptics;
                default: return false;
            }
        }
    }
}
