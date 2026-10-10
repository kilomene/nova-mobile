using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    /// <summary>
    /// Pre-match class select screen: scrollable grid of all 30 classes with
    /// names, descriptions, actives and passives. Built fully in code.
    /// Usage: ClassSelectUI.Show(parent, id => { /* start match with id */ });
    /// </summary>
    public class ClassSelectUI : MonoBehaviour
    {
        private Action<string> _onChosen;
        private string _selectedId;
        private readonly Dictionary<string, Image> _cardBgs = new Dictionary<string, Image>();
        private Text _summaryText;

        /// <summary>Show the select screen. Calls onChosen(classId) on confirm.</summary>
        public static ClassSelectUI Show(Transform parent, Action<string> onChosen, string initialId = null)
        {
            EnsureEventSystem();
            var root = new GameObject("ClassSelectUI");
            root.transform.SetParent(parent, false);
            var ui = root.AddComponent<ClassSelectUI>();
            ui.Build(onChosen, initialId);
            return ui;
        }

        private static void EnsureEventSystem()
        {
            if (EventSystem.current != null) return;
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }

        private static Font DefaultFont() =>
            Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

        private void Build(Action<string> onChosen, string initialId)
        {
            _onChosen = onChosen;
            _selectedId = !string.IsNullOrEmpty(initialId) ? initialId : ClassData.Classes[0].Id;

            var canvas = gameObject.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 100;
            gameObject.AddComponent<GraphicRaycaster>();
            var scaler = gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920f, 1080f);
            scaler.matchWidthOrHeight = 0.5f;

            var rootRt = gameObject.GetComponent<RectTransform>();
            NovaUtils.PlaceByFraction(rootRt, 0f, 0f, 1f, 1f);

            var bg = gameObject.AddComponent<Image>();
            bg.color = new Color(0.04f, 0.05f, 0.07f, 0.97f);

            // Title.
            var title = NewText(transform, "CHOOSE YOUR CLASS", 54, FontStyle.Bold,
                new Color(1f, 0.85f, 0.3f));
            var titleRt = title.GetComponent<RectTransform>();
            NovaUtils.PlaceByFraction(titleRt, 0f, 0.90f, 1f, 1f);

            var subtitle = NewText(transform,
                "30 NOVA-original classes — each more advanced than anything else out there",
                26, FontStyle.Normal, new Color(0.7f, 0.72f, 0.78f));
            NovaUtils.PlaceByFraction(subtitle.GetComponent<RectTransform>(), 0f, 0.855f, 1f, 0.90f);

            // Scrollable grid.
            var scrollGo = new GameObject("Grid");
            scrollGo.transform.SetParent(transform, false);
            var scrollRt = scrollGo.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(scrollRt, 0.02f, 0.16f, 0.98f, 0.85f);
            var scroll = scrollGo.AddComponent<ScrollRect>();
            scroll.horizontal = false;
            scroll.vertical = true;
            scroll.scrollSensitivity = 24f;

            var viewport = new GameObject("Viewport");
            viewport.transform.SetParent(scrollGo.transform, false);
            var vpRt = viewport.AddComponent<RectTransform>();
            NovaUtils.PlaceByFraction(vpRt, 0f, 0f, 1f, 1f);
            viewport.AddComponent<Image>().color = new Color(0f, 0f, 0f, 0f);
            viewport.AddComponent<Mask>().showMaskGraphic = false;
            scroll.viewport = vpRt;

            var content = new GameObject("Content");
            content.transform.SetParent(viewport.transform, false);
            var contentRt = content.AddComponent<RectTransform>();
            contentRt.anchorMin = new Vector2(0f, 1f);
            contentRt.anchorMax = new Vector2(1f, 1f);
            contentRt.pivot = new Vector2(0.5f, 1f);
            contentRt.offsetMin = Vector2.zero;
            contentRt.offsetMax = Vector2.zero;
            var grid = content.AddComponent<GridLayoutGroup>();
            grid.cellSize = new Vector2(880f, 420f);
            grid.spacing = new Vector2(24f, 24f);
            grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            grid.constraintCount = 2;
            grid.childAlignment = TextAnchor.UpperCenter;
            var fitter = content.AddComponent<ContentSizeFitter>();
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            scroll.content = contentRt;

            foreach (var spec in ClassData.Classes)
                BuildCard(content.transform, spec);

            // Bottom bar: summary + confirm.
            var bar = new GameObject("BottomBar");
            bar.transform.SetParent(transform, false);
            NovaUtils.PlaceByFraction(bar.AddComponent<RectTransform>(), 0f, 0f, 1f, 0.15f);
            var barImg = bar.AddComponent<Image>();
            barImg.color = new Color(0.07f, 0.08f, 0.11f, 1f);

            _summaryText = NewText(bar.transform, "", 30, FontStyle.Bold, Color.white);
            NovaUtils.PlaceByFraction(_summaryText.GetComponent<RectTransform>(), 0.02f, 0.1f, 0.70f, 0.9f);
            _summaryText.alignment = TextAnchor.MiddleLeft;

            var confirmGo = new GameObject("ConfirmButton");
            confirmGo.transform.SetParent(bar.transform, false);
            NovaUtils.PlaceByFraction(confirmGo.AddComponent<RectTransform>(), 0.74f, 0.15f, 0.98f, 0.85f);
            var confirmImg = confirmGo.AddComponent<Image>();
            confirmImg.color = new Color(0.95f, 0.72f, 0.15f);
            var confirmBtn = confirmGo.AddComponent<Button>();
            var confirmLabel = NewText(confirmGo.transform, "DEPLOY", 40, FontStyle.Bold, Color.black);
            NovaUtils.PlaceByFraction(confirmLabel.GetComponent<RectTransform>(), 0f, 0f, 1f, 1f);
            confirmBtn.onClick.AddListener(OnConfirm);

            RefreshSelection();
        }

        private void BuildCard(Transform parent, ClassSpec spec)
        {
            var card = new GameObject("Card_" + spec.Id);
            card.transform.SetParent(parent, false);
            var bg = card.AddComponent<Image>();
            bg.color = new Color(0.10f, 0.11f, 0.14f, 1f);
            _cardBgs[spec.Id] = bg;
            var btn = card.AddComponent<Button>();
            string id = spec.Id;
            btn.onClick.AddListener(() => Select(id));

            var layout = card.AddComponent<VerticalLayoutGroup>();
            layout.padding = new RectOffset(18, 18, 14, 14);
            layout.spacing = 8;
            layout.childControlWidth = true;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = true;

            Color profColor = ClassData.ProfessionColor(spec.Profession);

            // Header: profession tag + name.
            var header = new GameObject("Header");
            header.transform.SetParent(card.transform, false);
            var hLayout = header.AddComponent<HorizontalLayoutGroup>();
            hLayout.spacing = 12;
            hLayout.childForceExpandHeight = false;
            var tag = NewText(header.transform,
                ClassData.ProfessionDisplayName(spec.Profession), 24, FontStyle.Bold, profColor);
            var name = NewText(header.transform, spec.Name, 36, FontStyle.Bold, Color.white);
            name.GetComponent<RectTransform>().sizeDelta = new Vector2(0f, 52f);

            var tagline = NewText(card.transform, spec.Tagline, 24, FontStyle.Italic,
                new Color(0.75f, 0.77f, 0.82f));
            tagline.GetComponent<RectTransform>().sizeDelta = new Vector2(0f, 40f);

            var active = NewText(card.transform,
                "ACTIVE — " + spec.ActiveName + " (" + spec.Cooldown + "s)\n" + spec.ActiveDesc,
                23, FontStyle.Normal, new Color(0.92f, 0.94f, 0.98f));
            var passive = NewText(card.transform,
                "PASSIVE — " + spec.PassiveName + "\n" + spec.PassiveDesc + "\n" +
                "PROFESSION — " + ClassData.ProfessionPassive(spec.Profession),
                23, FontStyle.Normal, new Color(0.65f, 0.85f, 0.75f));

            // Accent strip at the bottom.
            var strip = new GameObject("Strip");
            strip.transform.SetParent(card.transform, false);
            var stripRt = strip.AddComponent<RectTransform>();
            stripRt.sizeDelta = new Vector2(0f, 8f);
            var stripLayout = strip.AddComponent<LayoutElement>();
            stripLayout.minHeight = 8f;
            stripLayout.preferredHeight = 8f;
            var stripImg = strip.AddComponent<Image>();
            stripImg.color = profColor;
        }

        private Text NewText(Transform parent, string text, int size, FontStyle style, Color color)
        {
            var go = new GameObject("Text");
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = DefaultFont();
            t.text = text;
            t.fontSize = size;
            t.fontStyle = style;
            t.color = color;
            t.alignment = TextAnchor.UpperLeft;
            t.horizontalOverflow = HorizontalWrapMode.Wrap;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            return t;
        }

        private void Select(string id)
        {
            _selectedId = id;
            RefreshSelection();
        }

        private void RefreshSelection()
        {
            foreach (var kv in _cardBgs)
                kv.Value.color = kv.Key == _selectedId
                    ? new Color(0.16f, 0.18f, 0.24f, 1f)
                    : new Color(0.10f, 0.11f, 0.14f, 1f);
            ClassSpec spec = ClassData.Get(_selectedId);
            if (_summaryText != null)
                _summaryText.text = spec.Name + " — " + spec.ActiveName + " / " + spec.PassiveName;
        }

        private void OnConfirm()
        {
            _onChosen?.Invoke(_selectedId);
            Destroy(gameObject);
        }
    }
}
