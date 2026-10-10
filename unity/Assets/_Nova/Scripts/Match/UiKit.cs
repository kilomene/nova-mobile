using System;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Events;
using UnityEngine.EventSystems;
using NovaMobile.Core;

namespace NovaMobile.Match
{
    /// <summary>
    /// Small shared uGUI builders for the Match system (lobby, HUD feedback,
    /// victory screens). Runtime-built UI only — no editor assets. Fonts,
    /// ring/dot/arrow textures are generated once and cached.
    /// </summary>
    internal static class UiKit
    {
        private static Font _font;
        private static Texture2D _ringTex;
        private static Texture2D _dotTex;
        private static Texture2D _arrowTex;
        private static Texture2D _xTex;

        public static Font Font
        {
            get
            {
                if (_font == null)
                    _font = Resources.GetBuiltinResource<Font>("Arial.ttf");
                return _font;
            }
        }

        public static void EnsureEventSystem()
        {
            if (EventSystem.current != null) return;
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }

        /// <summary>Full-screen overlay canvas, CODM landscape reference.</summary>
        public static GameObject OverlayCanvas(string name, int sortingOrder)
        {
            EnsureEventSystem();
            var go = new GameObject(name);
            var canvas = go.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = sortingOrder;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920f, 1080f);
            scaler.matchWidthOrHeight = 0.5f;
            go.AddComponent<GraphicRaycaster>();
            return go;
        }

        public static void Place(RectTransform rt, float x0, float y0, float x1, float y1)
        {
            rt.anchorMin = new Vector2(x0, y0);
            rt.anchorMax = new Vector2(x1, y1);
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;
        }

        public static Text Label(Transform parent, string text, int size, Color color,
            TextAnchor anchor = TextAnchor.MiddleCenter, FontStyle style = FontStyle.Normal)
        {
            var go = new GameObject("Label");
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Font;
            t.text = text;
            t.fontSize = size;
            t.color = color;
            t.alignment = anchor;
            t.fontStyle = style;
            t.raycastTarget = false;
            return t;
        }

        public static Image Panel(Transform parent, Color color)
        {
            var go = new GameObject("Panel");
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.color = color;
            img.raycastTarget = false;
            return img;
        }

        public static Button Button(Transform parent, string label, UnityAction onClick,
            Color? bg = null, int fontSize = 30)
        {
            var go = new GameObject("Button");
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.color = bg ?? new Color(1f, 0.62f, 0.12f, 0.95f); // CODM orange
            var btn = go.AddComponent<Button>();
            var t = Label(go.transform, label, fontSize, Color.white, TextAnchor.MiddleCenter, FontStyle.Bold);
            var trt = t.GetComponent<RectTransform>();
            Place(trt, 0f, 0f, 1f, 1f);
            btn.onClick.AddListener(onClick);
            // Pressed tint.
            var colors = btn.colors;
            colors.pressedColor = new Color(1f, 0.75f, 0.25f, 1f);
            btn.colors = colors;
            return btn;
        }

        public static void SetText(Text t, string s) { if (t != null) t.text = s; }

        // ---------------- cached procedural sprites ----------------

        private static Sprite SpriteOf(Texture2D tex)
        {
            return Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height),
                new Vector2(0.5f, 0.5f), 100f);
        }

        /// <summary>Thin white ring (tint via Image.color), for zone circles.</summary>
        public static Sprite RingSprite()
        {
            if (_ringTex == null)
            {
                int s = 256, th = 7;
                _ringTex = new Texture2D(s, s, TextureFormat.ARGB32, false);
                var px = new Color[s * s];
                float c = s * 0.5f, r = c - th * 0.5f;
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                        float a = 1f - Mathf.Clamp01(Mathf.Abs(d - r) / (th * 0.5f));
                        px[y * s + x] = new Color(1f, 1f, 1f, a);
                    }
                _ringTex.SetPixels(px);
                _ringTex.Apply();
            }
            return SpriteOf(_ringTex);
        }

        /// <summary>Soft white dot (tint via Image.color), for map markers.</summary>
        public static Sprite DotSprite()
        {
            if (_dotTex == null)
            {
                int s = 64;
                _dotTex = new Texture2D(s, s, TextureFormat.ARGB32, false);
                var px = new Color[s * s];
                float c = s * 0.5f;
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c)) / c;
                        float a = 1f - Mathf.Clamp01((d - 0.55f) / 0.45f);
                        px[y * s + x] = new Color(1f, 1f, 1f, a);
                    }
                _dotTex.SetPixels(px);
                _dotTex.Apply();
            }
            return SpriteOf(_dotTex);
        }

        /// <summary>Up-pointing triangle arrow (player marker on the minimap).</summary>
        public static Sprite ArrowSprite()
        {
            if (_arrowTex == null)
            {
                int w = 64, h = 64;
                _arrowTex = new Texture2D(w, h, TextureFormat.ARGB32, false);
                var px = new Color[w * h];
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++)
                    {
                        // Triangle: apex top-center, base bottom.
                        float t = 1f - (float)y / h; // 1 at top
                        float halfW = (w * 0.5f) * (1f - t) + 2f;
                        float a = Mathf.Abs(x - w * 0.5f) < halfW ? 1f : 0f;
                        px[y * w + x] = new Color(1f, 1f, 1f, a);
                    }
                _arrowTex.SetPixels(px);
                _arrowTex.Apply();
            }
            return SpriteOf(_arrowTex);
        }

        /// <summary>Hitmarker X (tint via Image.color).</summary>
        public static Sprite HitXSprite()
        {
            if (_xTex == null)
            {
                int s = 96, th = 10;
                _xTex = new Texture2D(s, s, TextureFormat.ARGB32, false);
                var px = new Color[s * s];
                float c = s * 0.5f;
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float dx = Mathf.Abs(x - c), dy = Mathf.Abs(y - c);
                        float d = Mathf.Abs(dx - dy);
                        float a = 1f - Mathf.Clamp01((d - th * 0.5f) / (th * 0.5f));
                        px[y * s + x] = new Color(1f, 1f, 1f, a);
                    }
                _xTex.SetPixels(px);
                _xTex.Apply();
            }
            return SpriteOf(_xTex);
        }
    }
}
