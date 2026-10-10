using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    /// <summary>
    /// uGUI HUD skill button wired to the local player's ClassAbility.
    /// Radial cooldown sweep (Image.FillMethod.Radial360) + countdown / READY label.
    /// Built fully in code; anchored by screen fraction per project conventions.
    /// </summary>
    public class ClassSkillButton : MonoBehaviour
    {
        private ClassAbility _ability;
        private Image _fill;
        private Text _label;
        private Button _button;
        private Image _bg;

        /// <summary>Build the button under a Canvas and bind it to an ability.</summary>
        public static ClassSkillButton Create(Transform canvasParent, ClassAbility ability)
        {
            var root = new GameObject("ClassSkillButton");
            root.transform.SetParent(canvasParent, false);
            var rt = root.AddComponent<RectTransform>();
            // Bottom-center-right, mirroring the Godot placement (vp.x*0.5+170, vp.y-120).
            NovaUtils.PlaceByFraction(rt, 0.62f, 0.03f, 0.74f, 0.21f);

            var btn = root.AddComponent<ClassSkillButton>();
            btn.Build(ability);
            return btn;
        }

        private static Font DefaultFont()
        {
            var f = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            return f;
        }

        private void Build(ClassAbility ability)
        {
            _ability = ability;
            Color accent = ability != null ? ability.Accent : Color.white;

            _bg = gameObject.AddComponent<Image>();
            _bg.color = new Color(0.08f, 0.09f, 0.11f, 0.85f);

            _button = gameObject.AddComponent<Button>();
            _button.targetGraphic = _bg;
            var colors = _button.colors;
            colors.pressedColor = new Color(0.2f, 0.22f, 0.26f, 0.9f);
            colors.disabledColor = new Color(0.08f, 0.09f, 0.11f, 0.6f);
            _button.colors = colors;
            _button.onClick.AddListener(OnPressed);

            // Radial cooldown sweep overlay.
            var fillGo = new GameObject("CooldownSweep");
            fillGo.transform.SetParent(transform, false);
            var fillRt = fillGo.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(fillRt, 0f, 0f, 1f, 1f);
            _fill = fillGo.AddComponent<Image>();
            _fill.color = new Color(0.05f, 0.05f, 0.07f, 0.72f);
            _fill.fillMethod = Image.FillMethod.Radial360;
            _fill.fillOrigin = (int)Image.Origin360.Top;
            _fill.fillClockwise = false;
            _fill.fillAmount = 0f;
            _fill.raycastTarget = false;

            // Accent ring: thin frame image behind the label.
            var frameGo = new GameObject("Frame");
            frameGo.transform.SetParent(transform, false);
            var frameRt = frameGo.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(frameRt, 0f, 0f, 1f, 1f);
            var frame = frameGo.AddComponent<Image>();
            frame.color = accent;
            frame.raycastTarget = false;
            // Frame as border: use a slightly inset bg-colored panel on top.
            var insetGo = new GameObject("Inset");
            insetGo.transform.SetParent(frameGo.transform, false);
            var insetRt = insetGo.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(insetRt, 0.04f, 0.04f, 0.96f, 0.96f);
            var inset = insetGo.AddComponent<Image>();
            inset.color = new Color(0.08f, 0.09f, 0.11f, 0.0f);
            inset.raycastTarget = false;

            // Label.
            var labelGo = new GameObject("Label");
            labelGo.transform.SetParent(transform, false);
            var labelRt = labelGo.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(labelRt, 0.05f, 0.05f, 0.95f, 0.95f);
            _label = labelGo.AddComponent<Text>();
            _label.font = DefaultFont();
            _label.alignment = TextAnchor.MiddleCenter;
            _label.fontSize = 22;
            _label.fontStyle = FontStyle.Bold;
            _label.color = Color.white;
            _label.raycastTarget = false;
            _label.text = ability != null ? ability.Spec.ActiveName.ToUpperInvariant() : "SKILL";

            Refresh(1f);
        }

        private void OnPressed()
        {
            if (_ability != null) _ability.TryActivate();
        }

        private void Update()
        {
            if (_ability == null) return;
            float frac = _ability.CooldownFrac;
            _fill.fillAmount = 1f - frac;
            if (_ability.CooldownLeft > 0f)
            {
                _label.text = Mathf.CeilToInt(_ability.CooldownLeft) + "s";
                _label.color = new Color(0.65f, 0.65f, 0.7f);
                _button.interactable = false;
            }
            else
            {
                _label.text = "READY";
                _label.color = _ability.Accent;
                _button.interactable = true;
            }
        }

        private void Refresh(float frac)
        {
            if (_fill != null) _fill.fillAmount = 1f - frac;
        }

        /// <summary>Rebind to a different ability (class change mid-session).</summary>
        public void Rebind(ClassAbility ability)
        {
            _ability = ability;
            if (_label != null && ability != null)
                _label.text = ability.Spec.ActiveName.ToUpperInvariant();
        }
    }
}
