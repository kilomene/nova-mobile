using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Match
{
    /// <summary>
    /// 6-phase shrinking safe zone, ported from main.gd WORLD_PHASES / WORLD_DPS
    /// (NOVA WORLD is always the 690m world — no map select).
    /// White/blue translucent boundary wall, outside-zone HP drain, screen-edge
    /// warning vignette, "SAFE ZONE WILL SHRINK IN 1 MINUTE(S)" warning banner,
    /// countdown text under the compass. No damage while skydiving in.
    /// </summary>
    public class Collapse : MonoBehaviour
    {
        public static Collapse Instance;

        // Ported exactly from main.gd WORLD_PHASES / WORLD_DPS.
        private static readonly float[,] Phases = new float[,]
        {
            // wait, shrink, radius
            { 45f, 60f, 300f },
            { 35f, 50f, 190f },
            { 30f, 45f, 110f },
            { 25f, 40f, 55f },
            { 20f, 30f, 25f },
            { 15f, 25f, 3f },
        };
        private static readonly float[] Dps = { 2f, 4f, 8f, 12f, 16f, 20f };
        private const int PhaseCount = 6;

        public bool Running { get; private set; }

        /// <summary>Current safe zone (x/z plane), meters.</summary>
        public Vector2 ZoneCenter { get; private set; }
        public float ZoneRadius { get; private set; }
        public Vector2 NextCenter { get; private set; }
        public float NextRadius { get; private set; }
        public int PhaseIndex { get; private set; }
        public bool Shrinking { get; private set; }

        private float _timer;
        private float _shrinkFrom;
        private Vector2 _shrinkFromC;
        private float _dmgAcc;
        private bool _warned60;
        private GameObject _wall;
        private Material _wallMat;
        private float _wallPulse;

        public static Collapse Ensure()
        {
            if (Instance == null)
            {
                var go = new GameObject("Collapse");
                Instance = go.AddComponent<Collapse>();
            }
            return Instance;
        }

        private void OnDestroy() { if (Instance == this) Instance = null; }

        /// <summary>Fresh zone for a new match (before the drop).</summary>
        public void Reset()
        {
            Running = false;
            PhaseIndex = 0;
            Shrinking = false;
            float half = World.WorldData.WorldSize * 0.5f;
            ZoneCenter = new Vector2(
                Random.Range(-half * 0.35f, half * 0.35f),
                Random.Range(-half * 0.35f, half * 0.35f));
            ZoneRadius = 430f; // main.gd world-mode start radius
            NextCenter = ZoneCenter;
            NextRadius = ZoneRadius;
            _timer = Phases[0, 0];
            _dmgAcc = 0f;
            _warned60 = false;
            EnsureWall();
            UpdateWall();
        }

        public void Begin()
        {
            Running = true;
            MatchEvents.RaiseZonePhaseChanged(0, false);
        }

        public void Stop()
        {
            Running = false;
            if (_wall != null) _wall.SetActive(false);
            if (FeedbackLayer.Iface != null)
            {
                FeedbackLayer.Iface.SetZoneVignette(0f);
                FeedbackLayer.Iface.SetZoneText("", false);
            }
        }

        private void Update()
        {
            if (!Running) return;
            var mgr = MatchManager.Instance;
            if (mgr == null) return;

            float dt = Time.deltaTime;

            if (PhaseIndex >= PhaseCount)
            {
                // Past the last phase: maximum pressure.
                ApplyZoneDamage(20f * dt, mgr);
                PushHud();
                return;
            }

            _timer -= dt;
            if (!Shrinking)
            {
                PushZoneText("SAFE ZONE SHRINKS IN " + FormatTime(_timer), false);
                if (!_warned60 && _timer <= 60f && _timer > 0f)
                {
                    _warned60 = true;
                    if (FeedbackLayer.Iface != null)
                        FeedbackLayer.Iface.ShowBanner("SAFE ZONE WILL SHRINK IN 1 MINUTE(S)",
                            "GET READY TO ROTATE", new Color(1f, 0.75f, 0.25f), 3f);
                }
                if (_timer <= 0f)
                {
                    Shrinking = true;
                    _timer = Phases[PhaseIndex, 1];
                    _shrinkFrom = ZoneRadius;
                    _shrinkFromC = ZoneCenter;
                    NextRadius = Phases[PhaseIndex, 2];
                    float maxOff = Mathf.Max(0f, ZoneRadius - NextRadius);
                    NextCenter = ZoneCenter + Random.insideUnitCircle * maxOff * 0.4f;
                    MatchEvents.RaiseZonePhaseChanged(PhaseIndex, true);
                    if (FeedbackLayer.Iface != null)
                        FeedbackLayer.Iface.ShowBanner("ZONE SHRINKING", "",
                            new Color(0.6f, 0.8f, 1f), 2f);
                }
            }
            else
            {
                float total = Phases[PhaseIndex, 1];
                float t = 1f - Mathf.Clamp01(_timer / total);
                ZoneRadius = Mathf.Lerp(_shrinkFrom, NextRadius, t);
                ZoneCenter = Vector2.Lerp(_shrinkFromC, NextCenter, t);
                PushZoneText("GET TO THE ZONE", true);
                ApplyZoneDamage(Dps[PhaseIndex] * dt, mgr);
                if (_timer <= 0f)
                {
                    PhaseIndex++;
                    Shrinking = false;
                    _warned60 = false;
                    _timer = PhaseIndex < PhaseCount ? Phases[PhaseIndex, 0] : 9999f;
                    MatchEvents.RaiseZonePhaseChanged(PhaseIndex, false);
                }
            }

            UpdateWall();
            PushHud();
        }

        private void ApplyZoneDamage(float amount, MatchManager mgr)
        {
            if (mgr.Phase == MatchPhase.Drop) return; // no zone damage while skydiving in
            if (mgr.Player == null || !mgr.Player.IsAlive) return;
            Vector2 flat = new Vector2(mgr.Player.transform.position.x, mgr.Player.transform.position.z);
            bool outside = Vector2.Distance(flat, ZoneCenter) > ZoneRadius;
            if (FeedbackLayer.Iface != null)
                FeedbackLayer.Iface.SetZoneVignette(outside ? 1f : 0f);
            if (!outside) { _dmgAcc = 0f; return; }
            _dmgAcc += amount;
            int d = Mathf.FloorToInt(_dmgAcc);
            if (d >= 1)
            {
                _dmgAcc -= d;
                mgr.Player.TakeDamage(d, Vector3.zero, DamageCause.Zone);
            }
        }

        private void PushZoneText(string s, bool danger)
        {
            if (FeedbackLayer.Iface != null)
                FeedbackLayer.Iface.SetZoneText(s, danger);
        }

        private void PushHud() { /* minimap reads Collapse.Instance directly */ }

        private static string FormatTime(float s)
        {
            s = Mathf.Max(0f, s);
            int m = Mathf.FloorToInt(s / 60f);
            int sec = Mathf.FloorToInt(s % 60f);
            return m + ":" + sec.ToString("00");
        }

        // ---------------- boundary wall ----------------

        private void EnsureWall()
        {
            if (_wall != null) { _wall.SetActive(true); return; }
            _wall = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            _wall.name = "ZoneWall";
            Object.Destroy(_wall.GetComponent<Collider>());
            _wallMat = new Material(Shader.Find("Unlit/Transparent"));
            _wallMat.color = new Color(0.55f, 0.75f, 1f, 0.28f); // white/blue translucent
            _wall.GetComponent<Renderer>().material = _wallMat;
            _wall.transform.SetParent(transform, false);
        }

        private void UpdateWall()
        {
            if (_wall == null) return;
            _wallPulse += Time.deltaTime;
            float a = 0.24f + 0.08f * Mathf.Sin(_wallPulse * 2f);
            _wallMat.color = new Color(0.55f, 0.75f, 1f, a);
            _wall.transform.position = new Vector3(ZoneCenter.x, 30f, ZoneCenter.y);
            _wall.transform.localScale = new Vector3(ZoneRadius * 2f, 60f, ZoneRadius * 2f);
        }
    }
}
