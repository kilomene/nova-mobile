using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Player;

namespace NovaMobile.Match
{
    /// <summary>
    /// Center-screen combat feedback (visual bible §3, §11):
    /// - center-top event banners ("FIRST AIRDROP")
    /// - kill banners ("ELIMINATED — 7 KILL(S)")
    /// - floating yellow damage numbers ("343 DAMAGE DEALT")
    /// - "KNOCKED DOWN" / "DOWNED BY YOU" states
    /// - hitmarker (X, red on kill) + red hit-direction arcs
    /// - big yellow compass degree number, top-center over the compass strip
    /// - zone text under the compass ("SAFE ZONE SHRINKS IN 0:45")
    /// - alive count "100/100" top-left above the killfeed
    /// - screen-edge warning vignette (zone damage)
    /// - mythic milestone banners (wired to MatchEvents.MythicMilestone)
    ///
    /// All dynamic elements are pooled; no per-frame allocations.
    /// </summary>
    public class FeedbackLayer : MonoBehaviour
    {
        public static FeedbackLayer Iface;

        private const int DmgPoolN = 12;

        private GameObject _root;
        private TouchHUD _hud;

        // Banner (center-top).
        private Text _bannerMain;
        private Text _bannerSub;
        private CanvasGroup _bannerCg;
        private float _bannerT;

        // Kill banner (center).
        private Text _killBanner;
        private CanvasGroup _killCg;
        private float _killT;

        // Mythic banner (center, below kill banner).
        private Text _mythicBanner;
        private CanvasGroup _mythicCg;
        private float _mythicT;

        // Damage numbers.
        private class DmgNum
        {
            public Text T; public CanvasGroup Cg; public float Age; public bool Active;
            public Vector3 World; public float Rise;
        }
        private readonly List<DmgNum> _dmgPool = new List<DmgNum>(DmgPoolN);
        private int _dmgCursor;

        // Knocked state.
        private Text _knockedText;
        private Text _knockedSub;

        // Hitmarker + direction.
        private Image _hitX;
        private float _hitT;
        private Image _hitDir;
        private float _hitDirT;
        private static Texture2D _arcTex;

        // Degree number + zone text + alive count.
        private Text _degreeText;
        private Text _zoneText;
        private Text _aliveText;

        // Zone vignette.
        private Image _vignette;
        private float _vignettePulse;

        private Camera _cam;

        public static FeedbackLayer Ensure(TouchHUD hud)
        {
            if (Iface == null)
            {
                var go = new GameObject("FeedbackLayer");
                Iface = go.AddComponent<FeedbackLayer>();
                Iface.Build(hud);
            }
            return Iface;
        }

        private void OnDestroy()
        {
            MatchEvents.MythicMilestone -= OnMythicMilestone;
            MatchEvents.HitConfirmed -= OnHitConfirmed;
            MatchEvents.PlayerDownedState -= OnPlayerDownedState;
            if (Iface == this) Iface = null;
        }

        private void Build(TouchHUD hud)
        {
            _hud = hud;
            var canvas = UiKit.OverlayCanvas("MatchFeedback", 11);
            canvas.transform.SetParent(transform, false);
            _root = canvas;

            // Center-top event banner.
            _bannerMain = UiKit.Label(canvas.transform, "", 44, new Color(1f, 0.75f, 0.25f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            _bannerSub = UiKit.Label(canvas.transform, "", 26, new Color(1f, 1f, 1f, 0.9f));
            UiKit.Place(_bannerMain.GetComponent<RectTransform>(), 0f, 0.80f, 1f, 0.88f);
            UiKit.Place(_bannerSub.GetComponent<RectTransform>(), 0f, 0.755f, 1f, 0.80f);
            _bannerCg = _bannerMain.gameObject.AddComponent<CanvasGroup>();
            _bannerSub.gameObject.AddComponent<CanvasGroup>();
            _bannerCg.alpha = 0f;

            // Kill banner (center).
            _killBanner = UiKit.Label(canvas.transform, "", 56, Color.white,
                TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(_killBanner.GetComponent<RectTransform>(), 0f, 0.55f, 1f, 0.68f);
            _killCg = _killBanner.gameObject.AddComponent<CanvasGroup>();
            _killCg.alpha = 0f;

            // Mythic milestone banner (center, lower).
            _mythicBanner = UiKit.Label(canvas.transform, "", 40, new Color(1f, 0.45f, 0.95f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(_mythicBanner.GetComponent<RectTransform>(), 0f, 0.44f, 1f, 0.54f);
            _mythicCg = _mythicBanner.gameObject.AddComponent<CanvasGroup>();
            _mythicCg.alpha = 0f;

            // Damage number pool.
            for (int i = 0; i < DmgPoolN; i++)
            {
                var t = UiKit.Label(canvas.transform, "", 30, new Color(1f, 0.85f, 0.2f),
                    TextAnchor.MiddleCenter, FontStyle.Bold);
                t.gameObject.SetActive(false);
                _dmgPool.Add(new DmgNum { T = t, Cg = t.gameObject.AddComponent<CanvasGroup>() });
            }

            // Knocked-down state.
            _knockedText = UiKit.Label(canvas.transform, "", 52, new Color(1f, 0.25f, 0.2f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            _knockedSub = UiKit.Label(canvas.transform, "", 26, Color.white);
            UiKit.Place(_knockedText.GetComponent<RectTransform>(), 0f, 0.36f, 1f, 0.46f);
            UiKit.Place(_knockedSub.GetComponent<RectTransform>(), 0f, 0.31f, 1f, 0.36f);
            _knockedText.gameObject.SetActive(false);
            _knockedSub.gameObject.SetActive(false);

            // Hitmarker X (center screen).
            var hx = new GameObject("HitX");
            hx.transform.SetParent(canvas.transform, false);
            _hitX = hx.AddComponent<Image>();
            _hitX.sprite = UiKit.HitXSprite();
            _hitX.raycastTarget = false;
            var hrt = _hitX.GetComponent<RectTransform>();
            UiKit.Place(hrt, 0.47f, 0.44f, 0.53f, 0.56f);
            _hitX.gameObject.SetActive(false);

            // Hit-direction arc.
            var hd = new GameObject("HitDir");
            hd.transform.SetParent(canvas.transform, false);
            _hitDir = hd.AddComponent<Image>();
            _hitDir.sprite = ArcSprite();
            _hitDir.raycastTarget = false;
            var drt = _hitDir.GetComponent<RectTransform>();
            UiKit.Place(drt, 0.40f, 0.32f, 0.60f, 0.68f);
            _hitDir.gameObject.SetActive(false);

            // Big yellow degree number, top-center (over the compass strip).
            _degreeText = UiKit.Label(canvas.transform, "0", 46, new Color(1f, 0.85f, 0.2f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(_degreeText.GetComponent<RectTransform>(), 0.44f, 0.90f, 0.56f, 0.99f);

            // Zone text under the compass.
            _zoneText = UiKit.Label(canvas.transform, "", 26, new Color(1f, 1f, 1f, 0.95f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(_zoneText.GetComponent<RectTransform>(), 0.30f, 0.845f, 0.70f, 0.895f);

            // Alive count top-left, above the killfeed ("100/100").
            _aliveText = UiKit.Label(canvas.transform, "", 30, Color.white,
                TextAnchor.MiddleLeft, FontStyle.Bold);
            UiKit.Place(_aliveText.GetComponent<RectTransform>(), 0.012f, 0.905f, 0.20f, 0.965f);

            // Screen-edge warning vignette (zone damage).
            var vg = new GameObject("ZoneVignette");
            vg.transform.SetParent(canvas.transform, false);
            _vignette = vg.AddComponent<Image>();
            _vignette.sprite = VignetteSprite();
            _vignette.color = new Color(1f, 0.15f, 0.1f, 0f);
            _vignette.raycastTarget = false;
            UiKit.Place(_vignette.GetComponent<RectTransform>(), 0f, 0f, 1f, 1f);

            MatchEvents.MythicMilestone += OnMythicMilestone;
            MatchEvents.HitConfirmed += OnHitConfirmed;
            MatchEvents.PlayerDownedState += OnPlayerDownedState;
        }

        // ---------------- public API ----------------

        public void ShowBanner(string main, string sub, Color color, float duration = 2.5f)
        {
            _bannerMain.text = main;
            _bannerMain.color = color;
            _bannerSub.text = sub ?? "";
            _bannerT = duration;
            _bannerCg.alpha = 1f;
            _bannerSub.GetComponent<CanvasGroup>().alpha = 1f;
        }

        public void ShowKillBanner(int kills)
        {
            _killBanner.text = "ELIMINATED — " + kills + " KILL(S)";
            _killT = 2.2f;
            _killCg.alpha = 1f;
        }

        public void SpawnDamageNumber(Vector3 worldPos, float amount)
        {
            DmgNum d = _dmgPool[_dmgCursor];
            _dmgCursor = (_dmgCursor + 1) % DmgPoolN;
            d.World = worldPos;
            d.Age = 0f; d.Rise = 0f; d.Active = true;
            d.T.text = Mathf.RoundToInt(amount) + " DAMAGE DEALT";
            d.T.gameObject.SetActive(true);
            d.Cg.alpha = 1f;
        }

        public void ShowKnockedDown(bool byPlayer)
        {
            _knockedText.text = byPlayer ? "DOWNED BY YOU" : "KNOCKED DOWN";
            _knockedText.color = byPlayer ? new Color(1f, 0.85f, 0.3f) : new Color(1f, 0.25f, 0.2f);
            _knockedSub.text = byPlayer ? "FINISH THEM" : "WAITING FOR REVIVE — A TEAMMATE CAN SAVE YOU";
            _knockedText.gameObject.SetActive(true);
            _knockedSub.gameObject.SetActive(true);
        }

        public void HideKnocked()
        {
            _knockedText.gameObject.SetActive(false);
            _knockedSub.gameObject.SetActive(false);
        }

        public void SetAlive(int alive, int total)
        {
            _aliveText.text = alive + "/" + total;
            _aliveText.color = alive <= 10 ? new Color(1f, 0.4f, 0.3f) : Color.white;
        }

        public void SetZoneText(string s, bool danger)
        {
            _zoneText.text = s;
            _zoneText.color = danger ? new Color(1f, 0.45f, 0.35f) : new Color(1f, 1f, 1f, 0.95f);
        }

        /// <summary>Screen-edge warning while outside the zone (0..1 intensity).</summary>
        public void SetZoneVignette(float intensity)
        {
            _vignettePulse = Mathf.Clamp01(intensity);
        }

        // ---------------- events ----------------

        private void OnHitConfirmed(bool killed, float fromDirDeg)
        {
            _hitX.color = killed ? new Color(1f, 0.15f, 0.1f, 1f) : Color.white;
            _hitX.gameObject.SetActive(true);
            _hitT = 0.3f;
            if (_hud != null) _hud.NotifyFired();

            // Direction arc: rotate so the arc points toward the damage source.
            _hitDir.rectTransform.rotation = Quaternion.Euler(0f, 0f, -fromDirDeg);
            _hitDir.gameObject.SetActive(true);
            _hitDirT = 1f;
        }

        private void OnMythicMilestone(string theme, int kills, string milestone)
        {
            _mythicBanner.text = theme.ToUpper() + " — " + milestone.ToUpper() + " (" + kills + " KILLS)";
            _mythicT = 3f;
            _mythicCg.alpha = 1f;
        }

        private void OnPlayerDownedState(bool downed)
        {
            if (downed) ShowKnockedDown(false);
            else HideKnocked();
        }

        // ---------------- per-frame ----------------

        private void Update()
        {
            var mgr = MatchManager.Instance;
            if (mgr != null && mgr.Player != null && mgr.Player.PlayerCamera != null)
                _cam = mgr.Player.PlayerCamera;

            // Banner fades.
            if (_bannerT > 0f)
            {
                _bannerT -= Time.deltaTime;
                if (_bannerT <= 0f) FadeOut(_bannerCg);
            }
            if (_killT > 0f)
            {
                _killT -= Time.deltaTime;
                if (_killT <= 0f) FadeOut(_killCg);
            }
            if (_mythicT > 0f)
            {
                _mythicT -= Time.deltaTime;
                if (_mythicT <= 0f) FadeOut(_mythicCg);
            }

            // Damage numbers float up and fade.
            for (int i = 0; i < _dmgPool.Count; i++)
            {
                DmgNum d = _dmgPool[i];
                if (!d.Active) continue;
                d.Age += Time.deltaTime;
                d.Rise += Time.deltaTime * 60f;
                if (_cam != null)
                {
                    Vector3 sp = _cam.WorldToScreenPoint(d.World + Vector3.up * (d.Rise / 100f));
                    var rt = d.T.GetComponent<RectTransform>();
                    rt.position = sp;
                }
                if (d.Age > 0.9f)
                {
                    d.Cg.alpha = Mathf.Max(0f, d.Cg.alpha - Time.deltaTime * 2.5f);
                    if (d.Cg.alpha <= 0f) { d.Active = false; d.T.gameObject.SetActive(false); }
                }
            }

            // Hitmarker + direction fade.
            if (_hitT > 0f)
            {
                _hitT -= Time.deltaTime;
                if (_hitT <= 0f) _hitX.gameObject.SetActive(false);
            }
            if (_hitDirT > 0f)
            {
                _hitDirT -= Time.deltaTime;
                var c = _hitDir.color;
                c.a = Mathf.Clamp01(_hitDirT);
                _hitDir.color = c;
                if (_hitDirT <= 0f) _hitDir.gameObject.SetActive(false);
            }

            // Degree number from the player camera heading (north = -Z).
            if (_cam != null)
            {
                Vector3 f = _cam.transform.forward;
                float deg = Mathf.Atan2(f.x, -f.z) * Mathf.Rad2Deg;
                if (deg < 0f) deg += 360f;
                _degreeText.text = Mathf.RoundToInt(deg).ToString();
            }

            // Zone vignette pulse.
            if (_vignettePulse > 0f)
            {
                float a = _vignettePulse * (0.45f + 0.25f * Mathf.Sin(Time.time * 6f));
                _vignette.color = new Color(1f, 0.15f, 0.1f, a);
            }
            else if (_vignette.color.a > 0f)
            {
                _vignette.color = new Color(1f, 0.15f, 0.1f,
                    Mathf.Max(0f, _vignette.color.a - Time.deltaTime * 2f));
            }
        }

        private static void FadeOut(CanvasGroup cg)
        {
            // Quick fade handled next frames; simplest: hide.
            cg.alpha = 0f;
        }

        // ---------------- procedural sprites ----------------

        private static Sprite ArcSprite()
        {
            if (_arcTex == null)
            {
                int s = 256;
                _arcTex = new Texture2D(s, s, TextureFormat.ARGB32, false);
                var px = new Color[s * s];
                float c = s * 0.5f, r = c - 24f;
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float dx = x - c, dy = y - c;
                        float d = Mathf.Sqrt(dx * dx + dy * dy);
                        // Arc across the top (damage from ahead).
                        float ang = Mathf.Atan2(dx, -(dy)) * Mathf.Rad2Deg; // 0 = up
                        float inArc = 1f - Mathf.Clamp01(Mathf.Abs(ang) / 55f);
                        float inRing = 1f - Mathf.Clamp01(Mathf.Abs(d - r) / 18f);
                        px[y * s + x] = new Color(1f, 0.15f, 0.1f, inArc * inRing);
                    }
                _arcTex.SetPixels(px);
                _arcTex.Apply();
            }
            return Sprite.Create(_arcTex, new Rect(0, 0, _arcTex.width, _arcTex.height),
                new Vector2(0.5f, 0.5f), 100f);
        }

        private static Texture2D _vigTex;
        private static Sprite VignetteSprite()
        {
            if (_vigTex == null)
            {
                int w = 256, h = 144;
                _vigTex = new Texture2D(w, h, TextureFormat.ARGB32, false);
                var px = new Color[w * h];
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++)
                    {
                        float nx = Mathf.Abs(x / (float)w - 0.5f) * 2f;
                        float ny = Mathf.Abs(y / (float)h - 0.5f) * 2f;
                        float e = Mathf.Max(nx, ny);
                        float a = Mathf.Clamp01((e - 0.55f) / 0.45f);
                        px[y * w + x] = new Color(1f, 1f, 1f, a * a);
                    }
                _vigTex.SetPixels(px);
                _vigTex.Apply();
            }
            return Sprite.Create(_vigTex, new Rect(0, 0, _vigTex.width, _vigTex.height),
                new Vector2(0.5f, 0.5f), 100f);
        }
    }
}
