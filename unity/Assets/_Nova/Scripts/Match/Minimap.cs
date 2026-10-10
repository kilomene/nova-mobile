using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Core;
using NovaMobile.Player;

namespace NovaMobile.Match
{
    /// <summary>
    /// Square minimap, top-right, with the match timer beneath it (visual bible §3).
    /// A dedicated top-down orthographic camera renders the world into a
    /// RenderTexture (the terrain backdrop); zone rings, player arrow,
    /// teammates, buy-station $, fuel F, airdrop and ping markers are drawn as
    /// pooled UI overlays positioned from world coordinates each frame.
    ///
    /// The legacy circular TouchHUD minimap is hidden while a match runs; the
    /// live texture is still assigned to TouchHUD.MinimapView.texture per contract.
    /// </summary>
    public class Minimap : MonoBehaviour
    {
        public static Minimap Instance;

        private const int RtSize = 256;
        private const float WorldViewSize = 350f;  // ortho half-extent: whole 690m world fits
        private const float ZoomViewSize = 150f;   // zoomed tactical view

        private TouchHUD _hud;
        private Camera _cam;
        private RenderTexture _rt;
        private GameObject _root;          // match-HUD canvas root for this minimap
        private RectTransform _square;     // square frame
        private Image _zoneRing;
        private Image _nextRing;
        private Image _playerArrow;
        private Text _timerText;
        private readonly List<Image> _matePool = new List<Image>(8);
        private readonly List<Image> _enemyPool = new List<Image>(64);
        private readonly List<Image> _stationPool = new List<Image>(28);
        private readonly List<Text> _stationLabels = new List<Text>(28);
        private readonly List<Image> _dropPool = new List<Image>(8);
        private readonly List<Image> _pingPool = new List<Image>(16);
        private bool _zoomed;
        private float _viewSize = WorldViewSize;
        private float _pxPerMeter;
        private Vector2 _centerPx;

        // Reused scratch (no per-frame allocs).
        private static readonly Color MateGreen = new Color(0.3f, 1f, 0.4f, 0.95f);
        private static readonly Color EnemyRed = new Color(1f, 0.2f, 0.15f, 0.95f);

        public static Minimap Ensure(TouchHUD hud)
        {
            if (Instance == null)
            {
                var go = new GameObject("Minimap");
                Instance = go.AddComponent<Minimap>();
                Instance.Setup(hud);
            }
            else Instance._hud = hud;
            return Instance;
        }

        private void OnDestroy()
        {
            if (_hud != null) _hud.MinimapPressed -= ToggleZoom;
            if (_rt != null) { _rt.Release(); Destroy(_rt); }
            if (Instance == this) Instance = null;
        }

        private void Setup(TouchHUD hud)
        {
            _hud = hud;
            // Top-down camera, north-up (screen up = world -Z).
            var camGo = new GameObject("MinimapCam");
            camGo.transform.SetParent(transform, false);
            _cam = camGo.AddComponent<Camera>();
            _cam.orthographic = true;
            _cam.orthographicSize = _viewSize;
            _cam.nearClipPlane = 1f;
            _cam.farClipPlane = 600f;
            _cam.clearFlags = CameraClearFlags.SolidColor;
            _cam.backgroundColor = new Color(0.05f, 0.09f, 0.07f, 1f);
            _cam.cullingMask = ~0;
            _rt = new RenderTexture(RtSize, RtSize, 16, RenderTextureFormat.ARGB32);
            _rt.name = "MinimapRT";
            _cam.targetTexture = _rt;
            _cam.enabled = true;

            // Square frame, top-right, below the TouchHUD buttons (sorting 9 < 10).
            var canvas = UiKit.OverlayCanvas("MatchMinimap", 9);
            canvas.transform.SetParent(transform, false);
            _root = canvas;
            var frame = new GameObject("Frame");
            frame.transform.SetParent(canvas.transform, false);
            var frt = frame.AddComponent<RectTransform>();
            // Square, top-right with margin.
            frt.anchorMin = new Vector2(1f, 1f); frt.anchorMax = new Vector2(1f, 1f);
            float s = 300f;
            frt.sizeDelta = new Vector2(s, s);
            frt.anchoredPosition = new Vector2(-s * 0.5f - 24f, -s * 0.5f - 24f);
            var border = frame.AddComponent<Image>();
            border.color = new Color(1f, 1f, 1f, 0.35f);
            border.raycastTarget = false;

            var view = new GameObject("View");
            view.transform.SetParent(frame.transform, false);
            _square = view.AddComponent<RectTransform>();
            UiKit.Place(_square, 0f, 0f, 1f, 1f);
            _square.offsetMin = new Vector2(3f, 3f); _square.offsetMax = new Vector2(-3f, -3f);
            var raw = view.AddComponent<RawImage>();
            raw.texture = _rt;
            raw.raycastTarget = false;
            var mask = view.AddComponent<RectMask2D>(); // clip markers to the square

            // Contract: keep the legacy view fed too.
            if (_hud != null) _hud.MinimapTexture = _rt;

            _zoneRing = MarkerImage(view.transform, UiKit.RingSprite(), new Color(1f, 1f, 1f, 0.9f));
            _nextRing = MarkerImage(view.transform, UiKit.RingSprite(), new Color(1f, 1f, 1f, 0.35f));
            _playerArrow = MarkerImage(view.transform, UiKit.ArrowSprite(), new Color(0.35f, 1f, 0.45f, 1f));

            for (int i = 0; i < 8; i++) _matePool.Add(MarkerImage(view.transform, UiKit.DotSprite(), MateGreen));
            for (int i = 0; i < 64; i++) _enemyPool.Add(MarkerImage(view.transform, UiKit.DotSprite(), EnemyRed));
            for (int i = 0; i < 28; i++)
            {
                _stationPool.Add(MarkerImage(view.transform, UiKit.DotSprite(), Color.white));
                _stationLabels.Add(UiKit.Label(view.transform, "", 22, Color.white));
            }
            for (int i = 0; i < 8; i++) _dropPool.Add(MarkerImage(view.transform, UiKit.DotSprite(), new Color(1f, 0.55f, 0.1f, 0.95f)));
            for (int i = 0; i < 16; i++) _pingPool.Add(MarkerImage(view.transform, UiKit.DotSprite(), Color.yellow));

            // Match timer beneath the square (visual bible §3: e.g. 01:45).
            _timerText = UiKit.Label(canvas.transform, "00:00", 30, new Color(1f, 1f, 1f, 0.9f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            var trt = _timerText.GetComponent<RectTransform>();
            trt.anchorMin = new Vector2(1f, 1f); trt.anchorMax = new Vector2(1f, 1f);
            trt.sizeDelta = new Vector2(200f, 44f);
            trt.anchoredPosition = new Vector2(-s * 0.5f - 24f, -s - 24f - 26f);

            if (_hud != null) _hud.MinimapPressed += ToggleZoom;

            _centerPx = new Vector2(s * 0.5f, s * 0.5f);
            _pxPerMeter = (s - 12f) / (_viewSize * 2f);
        }

        private static Image MarkerImage(Transform parent, Sprite sprite, Color color)
        {
            var go = new GameObject("Mk");
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.sprite = sprite;
            img.color = color;
            img.raycastTarget = false;
            var rt = img.GetComponent<RectTransform>();
            rt.anchorMin = new Vector2(0.5f, 0.5f); rt.anchorMax = new Vector2(0.5f, 0.5f);
            rt.sizeDelta = new Vector2(14f, 14f);
            go.SetActive(false);
            return img;
        }

        private void ToggleZoom()
        {
            _zoomed = !_zoomed;
            _viewSize = _zoomed ? ZoomViewSize : WorldViewSize;
            _cam.orthographicSize = _viewSize;
            _pxPerMeter = (300f - 12f) / (_viewSize * 2f);
        }

        private void LateUpdate()
        {
            var mgr = MatchManager.Instance;
            if (mgr == null || mgr.Player == null) { _root.SetActive(false); return; }
            if (!_root.activeSelf) _root.SetActive(true);

            Vector3 pp = mgr.Player.transform.position;
            _cam.transform.position = new Vector3(pp.x, pp.y + 220f, pp.z);
            _cam.transform.rotation = Quaternion.LookRotation(Vector3.down, new Vector3(0f, 0f, -1f));

            // Timer: match elapsed MM:SS.
            int t = Mathf.FloorToInt(mgr.MatchTime);
            _timerText.text = string.Format("{0:00}:{1:00}", t / 60, t % 60);

            var col = Collapse.Instance;
            if (col != null && col.Running)
            {
                PlaceRing(_zoneRing, pp, col.ZoneCenter, col.ZoneRadius, new Color(1f, 1f, 1f, 0.9f));
                PlaceRing(_nextRing, pp, col.NextCenter, col.NextRadius, new Color(1f, 1f, 1f, 0.35f));
            }
            else { _zoneRing.gameObject.SetActive(false); _nextRing.gameObject.SetActive(false); }

            // Player arrow, rotated by yaw (screen up = -Z).
            float yaw = mgr.Player.transform.eulerAngles.y;
            PlaceDot(_playerArrow, pp, pp, 20f);
            _playerArrow.rectTransform.rotation = Quaternion.Euler(0f, 0f, -yaw);

            // Teammates (green), downed ring skipped (Squads system owns downed visuals).
            int mi = 0;
            for (int i = 0; i < MatchMarkers.Teammates.Count && mi < _matePool.Count; i++)
            {
                var tr = MatchMarkers.Teammates[i];
                if (tr == null) continue;
                PlaceDot(_matePool[mi], pp, tr.position, 12f);
                mi++;
            }
            HideRest(_matePool, mi);

            // Enemies: all while UAV is up, else only nearby (< 25 m).
            int ei = 0;
            for (int i = 0; i < MatchMarkers.Enemies.Count && ei < _enemyPool.Count; i++)
            {
                var tr = MatchMarkers.Enemies[i];
                if (tr == null) continue;
                if (!MatchMarkers.UavActive &&
                    (tr.position - pp).sqrMagnitude > 25f * 25f) continue;
                PlaceDot(_enemyPool[ei], pp, tr.position, 12f);
                ei++;
            }
            HideRest(_enemyPool, ei);

            // Buy stations ($) green, fuel stations (F) orange.
            int si = 0;
            si = PlaceStations(si, MatchMarkers.BuyStations, pp,
                new Color(0.25f, 1f, 0.45f), "$");
            si = PlaceStations(si, MatchMarkers.FuelStations, pp,
                new Color(1f, 0.7f, 0.3f), "F");
            HideRest(_stationPool, si);
            for (int i = si; i < _stationLabels.Count; i++) _stationLabels[i].gameObject.SetActive(false);

            // Airdrops: orange squares.
            int di = 0;
            for (int i = 0; i < MatchMarkers.Airdrops.Count && di < _dropPool.Count; i++)
            {
                PlaceDot(_dropPool[di], pp, MatchMarkers.Airdrops[i], 16f);
                di++;
            }
            HideRest(_dropPool, di);

            // Loot pings: tier-colored dots.
            int pi = 0;
            for (int i = 0; i < MatchMarkers.Pings.Count && pi < _pingPool.Count; i++)
            {
                var pg = MatchMarkers.Pings[i];
                _pingPool[pi].color = pg.Color;
                PlaceDot(_pingPool[pi], pp, pg.Pos, 12f);
                pi++;
            }
            HideRest(_pingPool, pi);
        }

        private int PlaceStations(int si, List<Vector3> list, Vector3 pp, Color c, string label)
        {
            for (int i = 0; i < list.Count && si < _stationPool.Count; i++)
            {
                var img = _stationPool[si];
                img.color = new Color(c.r * 0.35f, c.g * 0.35f, c.b * 0.35f, 0.9f);
                PlaceDot(img, pp, list[i], 18f);
                var lab = _stationLabels[si];
                lab.gameObject.SetActive(true);
                lab.text = label;
                lab.color = c;
                var lrt = lab.GetComponent<RectTransform>();
                lrt.anchorMin = new Vector2(0.5f, 0.5f); lrt.anchorMax = new Vector2(0.5f, 0.5f);
                lrt.anchoredPosition = img.rectTransform.anchoredPosition;
                lrt.sizeDelta = new Vector2(24f, 24f);
                si++;
            }
            return si;
        }

        private void PlaceRing(Image ring, Vector3 playerPos, Vector2 center, float radius, Color c)
        {
            var rt = ring.rectTransform;
            float d = radius * 2f * _pxPerMeter;
            rt.sizeDelta = new Vector2(d, d);
            rt.anchoredPosition = WorldToMap(playerPos, new Vector3(center.x, 0f, center.y));
            ring.color = c;
            ring.gameObject.SetActive(true);
        }

        private void PlaceDot(Image dot, Vector3 playerPos, Vector3 worldPos, float size)
        {
            var rt = dot.rectTransform;
            rt.sizeDelta = new Vector2(size, size);
            rt.anchoredPosition = WorldToMap(playerPos, worldPos);
            dot.gameObject.SetActive(true);
        }

        private Vector2 WorldToMap(Vector3 playerPos, Vector3 worldPos)
        {
            float dx = (worldPos.x - playerPos.x) * _pxPerMeter;
            float dz = (worldPos.z - playerPos.z) * _pxPerMeter;
            Vector2 p = _centerPx + new Vector2(dx, -dz);
            // Clamp inside the square.
            p.x = Mathf.Clamp(p.x, 8f, 292f);
            p.y = Mathf.Clamp(p.y, 8f, 292f);
            return p - _centerPx;
        }

        private static void HideRest(List<Image> pool, int used)
        {
            for (int i = used; i < pool.Count; i++)
                if (pool[i].gameObject.activeSelf) pool[i].gameObject.SetActive(false);
        }

    }
}
