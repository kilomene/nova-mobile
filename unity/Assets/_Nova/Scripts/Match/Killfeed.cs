using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Arsenal;
using NovaMobile.Player;

namespace NovaMobile.Match
{
    /// <summary>
    /// Top-left killfeed, under the alive counter (visual bible §3, §11):
    /// "killer [weapon icon] victim" in white/red, "DOWNED BY YOU" notices.
    /// Entries fade after 6s. Rows are pooled; weapon icons are procedural
    /// gun glyphs generated once per GunClass.
    /// Ported from hud.gd add_killfeed.
    /// </summary>
    public class Killfeed : MonoBehaviour
    {
        public static Killfeed Instance;

        private const int MaxRows = 6;
        private const float FadeAfter = 6f;

        private class Row
        {
            public GameObject Go;
            public CanvasGroup Cg;
            public Text Killer;
            public Image Icon;
            public Text Victim;
            public float Age;
            public bool Active;
        }

        private readonly List<Row> _rows = new List<Row>(MaxRows);
        private int _cursor;
        private TouchHUD _hud;

        // Gun glyph cache: GunClass -> sprite (built once).
        private static readonly Dictionary<GunClass, Sprite> GlyphCache =
            new Dictionary<GunClass, Sprite>();

        public static Killfeed Ensure(TouchHUD hud)
        {
            if (Instance == null)
            {
                var go = new GameObject("Killfeed");
                Instance = go.AddComponent<Killfeed>();
                Instance.Build(hud);
            }
            return Instance;
        }

        private void OnDestroy()
        {
            MatchEvents.KillReported -= OnKillReported;
            if (Instance == this) Instance = null;
        }

        private void Build(TouchHUD hud)
        {
            _hud = hud;
            Transform anchor = hud != null ? (Transform)hud.KillfeedAnchor : null;
            if (anchor == null)
            {
                var canvas = UiKit.OverlayCanvas("KillfeedFallback", 11);
                canvas.transform.SetParent(transform, false);
                anchor = canvas.transform;
            }
            // The anchor is owned by the Match system: stack rows vertically,
            // below the alive counter.
            var art = anchor.GetComponent<RectTransform>();
            if (art != null) art.anchoredPosition = new Vector2(16f, -116f);
            var vlg = anchor.gameObject.GetComponent<VerticalLayoutGroup>();
            if (vlg == null)
            {
                vlg = anchor.gameObject.AddComponent<VerticalLayoutGroup>();
                vlg.spacing = 4f;
                vlg.childControlWidth = true;
                vlg.childControlHeight = false;
                vlg.childForceExpandWidth = false;
                vlg.childForceExpandHeight = false;
            }
            for (int i = 0; i < MaxRows; i++)
            {
                var go = new GameObject("KfRow");
                go.transform.SetParent(anchor, false);
                var rt = go.AddComponent<RectTransform>();
                var cg = go.AddComponent<CanvasGroup>();
                cg.alpha = 0f;

                var bg = go.AddComponent<Image>();
                bg.color = new Color(0f, 0f, 0f, 0.45f);
                bg.raycastTarget = false;

                var killer = UiKit.Label(go.transform, "", 20, Color.white, TextAnchor.MiddleLeft, FontStyle.Bold);
                var icon = new GameObject("Icon").AddComponent<Image>();
                icon.transform.SetParent(go.transform, false);
                icon.raycastTarget = false;
                var victim = UiKit.Label(go.transform, "", 20, new Color(1f, 0.55f, 0.45f), TextAnchor.MiddleLeft);

                var krt = killer.GetComponent<RectTransform>();
                var irt = icon.GetComponent<RectTransform>();
                var vrt = victim.GetComponent<RectTransform>();
                UiKit.Place(krt, 0.02f, 0f, 0.44f, 1f);
                UiKit.Place(irt, 0.45f, 0.15f, 0.60f, 0.85f);
                UiKit.Place(vrt, 0.61f, 0f, 1f, 1f);

                var hle = go.AddComponent<LayoutElement>();
                hle.preferredHeight = 34f;
                go.SetActive(false);
                _rows.Add(new Row { Go = go, Cg = cg, Killer = killer, Icon = icon, Victim = victim });
            }
            MatchEvents.KillReported += OnKillReported;
        }

        private void OnKillReported(string killer, string victim, string gunId)
        {
            bool downedByYou = killer == "YOU" && victim.StartsWith("DOWNED ");
            string v = downedByYou ? victim.Substring(7) : victim;
            bool squadKill = killer.StartsWith("[SQUAD]");
            string k = squadKill ? killer.Substring(7) : killer;
            AddEntry(k, v, gunId, squadKill, downedByYou);
        }

        /// <summary>Add a killfeed entry. killer may be "" for system notices.</summary>
        public void AddEntry(string killer, string victim, string gunId,
            bool squadKill = false, bool downedByYou = false)
        {
            Row r = _rows[_cursor];
            _cursor = (_cursor + 1) % MaxRows;

            r.Killer.text = downedByYou ? "DOWNED BY YOU" : killer;
            r.Killer.color = downedByYou ? new Color(1f, 0.85f, 0.3f)
                : squadKill ? new Color(1f, 0.35f, 0.3f) : Color.white;
            r.Victim.text = victim;
            r.Victim.color = squadKill ? new Color(1f, 0.35f, 0.3f) : new Color(1f, 0.72f, 0.6f);
            r.Icon.sprite = GlyphFor(gunId);
            r.Icon.color = Color.white;

            r.Age = 0f; r.Active = true;
            r.Cg.alpha = 1f;
            r.Go.SetActive(true);
            // Newest on top: move to first sibling.
            r.Go.transform.SetAsFirstSibling();
        }

        private void Update()
        {
            for (int i = 0; i < _rows.Count; i++)
            {
                Row r = _rows[i];
                if (!r.Active) continue;
                r.Age += Time.deltaTime;
                if (r.Age >= FadeAfter)
                {
                    r.Cg.alpha = Mathf.Max(0f, r.Cg.alpha - Time.deltaTime * 2f);
                    if (r.Cg.alpha <= 0f) { r.Active = false; r.Go.SetActive(false); }
                }
            }
        }

        // ---------------- procedural weapon glyphs ----------------

        private static Sprite GlyphFor(string gunId)
        {
            GunClass gc = GunClass.AssaultRifle;
            try
            {
                if (!string.IsNullOrEmpty(gunId))
                    gc = GunData.Get(gunId).Class;
            }
            catch { gc = GunClass.AssaultRifle; }
            Sprite spr;
            if (!GlyphCache.TryGetValue(gc, out spr))
            {
                Texture2D tex = BuildGlyph(gc);
                spr = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height),
                    new Vector2(0.5f, 0.5f), 100f);
                GlyphCache[gc] = spr;
            }
            return spr;
        }

        /// <summary>Simple side-profile gun silhouette per class, white on transparent.</summary>
        private static Texture2D BuildGlyph(GunClass gc)
        {
            int w = 64, h = 24;
            var tex = new Texture2D(w, h, TextureFormat.ARGB32, false);
            var px = new Color[w * h];
            for (int i = 0; i < px.Length; i++) px[i] = Color.clear;

            // Draw filled rects in pixel space.
            switch (gc)
            {
                case GunClass.Pistol:
                    Rect(tex, px, w, h, 18, 10, 22, 5);   // slide
                    Rect(tex, px, w, h, 24, 15, 6, 8);    // grip
                    break;
                case GunClass.SMG:
                    Rect(tex, px, w, h, 8, 10, 40, 5);
                    Rect(tex, px, w, h, 26, 15, 5, 8);    // mag
                    Rect(tex, px, w, h, 2, 8, 8, 9);      // stock
                    break;
                case GunClass.Shotgun:
                    Rect(tex, px, w, h, 6, 9, 48, 7);     // thick barrel+body
                    Rect(tex, px, w, h, 20, 16, 6, 7);    // grip
                    break;
                case GunClass.Sniper:
                    Rect(tex, px, w, h, 4, 11, 52, 3);    // long thin barrel
                    Rect(tex, px, w, h, 22, 8, 14, 4);    // scope
                    Rect(tex, px, w, h, 24, 14, 5, 8);    // stock/grip
                    break;
                case GunClass.LMG:
                    Rect(tex, px, w, h, 8, 9, 44, 6);
                    Rect(tex, px, w, h, 24, 15, 10, 8);   // box mag
                    Rect(tex, px, w, h, 44, 6, 4, 10);    // bipod
                    break;
                case GunClass.Launcher:
                    Rect(tex, px, w, h, 6, 8, 46, 9);     // tube
                    Rect(tex, px, w, h, 24, 17, 6, 6);    // grip
                    break;
                case GunClass.Melee:
                    Rect(tex, px, w, h, 10, 11, 40, 3);    // blade
                    Rect(tex, px, w, h, 4, 9, 8, 7);       // handle
                    break;
                default: // AssaultRifle + Marksman
                    Rect(tex, px, w, h, 8, 10, 44, 5);
                    Rect(tex, px, w, h, 28, 15, 5, 8);    // mag
                    Rect(tex, px, w, h, 2, 8, 8, 9);      // stock
                    Rect(tex, px, w, h, 30, 5, 12, 4);    // sight
                    break;
            }
            tex.SetPixels(px);
            tex.Apply();
            return tex;
        }

        private static void Rect(Texture2D tex, Color[] px, int w, int h,
            int x, int y, int rw, int rh)
        {
            for (int j = y; j < y + rh && j < h; j++)
                for (int i = x; i < x + rw && i < w; i++)
                    px[j * w + i] = Color.white;
        }
    }
}
