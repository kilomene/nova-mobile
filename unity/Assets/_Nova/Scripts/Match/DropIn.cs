using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Core;
using NovaMobile.Player;
using NovaMobile.Soldiers;
using NovaMobile.World;

namespace NovaMobile.Match
{
    /// <summary>
    /// Skydive drop-in sequence (visual bible §2, ported from main.gd/player.gd):
    /// plane path across the world -> jump -> steerable freefall -> wingsuit
    /// glide (colored smoke trails, squad follow, descent line, POI names on
    /// the terrain) -> detailed parachute canopy with rigging lines -> landing.
    /// HUD: compass strip (TouchHUD), SPEED km/h + ALT/GROUND readouts.
    /// On landing, control returns to the PlayerController and combat begins.
    /// </summary>
    public class DropIn : MonoBehaviour
    {
        public enum DropStage { Plane, Freefall, Wingsuit, Chute, Landed }
        public static DropIn Active;

        private const float PlaneAlt = 420f;
        private const float PlaneSpeed = 95f;
        private const float FreefallV = 55f;
        private const float FreefallSteer = 18f;
        private const float WingsuitFwd = 35f;
        private const float WingsuitV = 12f;
        private const float ChuteV = 6.5f;
        private const float ChuteSteer = 9f;
        private const float ChuteDeployAlt = 60f;

        private PlayerController _player;
        private TouchHUD _hud;
        private SoldierRig _rig;
        private Camera _cam;

        private DropStage _stage;
        private GameObject _plane;
        private Vector3 _planeDir;
        private float _planeT;
        private Vector3 _vel;
        private float _groundY;

        // Follow-the-leader.
        private Transform _followTarget;
        private string _followName = "";
        private Text _followChip;
        private Button _cancelFollowBtn;

        // Drop HUD.
        private GameObject _dropHud;
        private Text _speedText;
        private Text _altText;
        private Button _jumpBtn;
        private Button _chuteBtn;

        // Wingsuit visuals.
        private TrailRenderer _trail;
        private LineRenderer _descentLine;

        // Parachute visuals.
        private GameObject _canopy;
        private readonly List<LineRenderer> _rigging = new List<LineRenderer>(8);

        // POI name labels on the terrain.
        private readonly List<GameObject> _poiLabels = new List<GameObject>(64);

        public void Begin(PlayerController player, TouchHUD hud)
        {
            Active = this;
            _player = player;
            _hud = hud;
            _rig = player.GetComponentInChildren<SoldierRig>();
            _cam = player.PlayerCamera;

            // Take over: the PlayerController is disabled until landing.
            _player.enabled = false;
            if (_hud != null) _hud.CrosshairVisible = false;

            float half = WorldData.WorldSize * 0.5f;
            float z0 = Random.Range(-half * 0.6f, half * 0.6f);
            Vector3 start = new Vector3(-half - 150f, PlaneAlt, z0);
            _planeDir = Vector3.right;
            _player.transform.position = start;
            _player.transform.rotation = Quaternion.LookRotation(_planeDir);

            BuildPlane(start);
            BuildDropHud();
            SpawnPoiLabels();
            _groundY = SampleGround(start);

            _stage = DropStage.Plane;
            _planeT = 0f;
            _vel = Vector3.zero;
        }

        private void OnDestroy()
        {
            if (Active == this) Active = null;
            CleanupDropVisuals();
            if (_dropHud != null) Destroy(_dropHud);
            if (_plane != null) Destroy(_plane);
        }

        /// <summary>Squad follow: steer toward a teammate. Null clears.</summary>
        public void SetFollowTarget(Transform target, string name, Color trailColor)
        {
            _followTarget = target;
            _followName = name ?? "";
            if (_followChip != null)
            {
                _followChip.gameObject.SetActive(target != null);
                _followChip.text = target != null ? "FOLLOWING " + _followName.ToUpper() : "";
            }
            if (_cancelFollowBtn != null)
                _cancelFollowBtn.gameObject.SetActive(target != null);
            if (_trail != null) { _trail.startColor = trailColor; _trail.endColor = trailColor; }
        }

        private void Update()
        {
            if (_stage == DropStage.Landed || _player == null) return;
            float dt = Time.deltaTime;
            Vector3 p = _player.transform.position;

            switch (_stage)
            {
                case DropStage.Plane: UpdatePlane(dt, ref p); break;
                case DropStage.Freefall: UpdateFall(dt, ref p, false); break;
                case DropStage.Wingsuit: UpdateFall(dt, ref p, true); break;
                case DropStage.Chute: UpdateChute(dt, ref p); break;
            }

            _player.transform.position = p;
            UpdateCamera(dt, p);
            UpdateDropHud(p);
            BillboardPoiLabels();
        }

        // ---------------- stages ----------------

        private void UpdatePlane(float dt, ref Vector3 p)
        {
            _planeT += dt;
            p += _planeDir * PlaneSpeed * dt;
            if (_plane != null) _plane.transform.position = p + new Vector3(0f, 2f, 0f);
            _jumpBtn.gameObject.SetActive(true);
            if (_planeT > 8f) Jump(); // auto-jump if the player never taps
        }

        private void Jump()
        {
            if (_stage != DropStage.Plane) return;
            _stage = DropStage.Freefall;
            _jumpBtn.gameObject.SetActive(false);
            if (_plane != null) Destroy(_plane);
            _vel = _planeDir * PlaneSpeed * 0.4f;
            _vel.y = -8f;
            if (_rig != null && _rig.Anim != null) _rig.Anim.Play(SoldierClip.Wingsuit);
            BuildTrail(new Color(1f, 0.2f, 0.15f, 0.9f)); // red squad smoke
            BuildDescentLine();
            _chuteBtn.gameObject.SetActive(true);
        }

        private void UpdateFall(float dt, ref Vector3 p, bool wingsuit)
        {
            Vector2 joy = _hud != null ? _hud.Joystick : Vector2.zero;

            if (!wingsuit && joy.magnitude > 0.75f)
            {
                _stage = DropStage.Wingsuit;
                wingsuit = true;
            }
            else if (wingsuit && joy.magnitude < 0.35f)
            {
                _stage = DropStage.Freefall;
                wingsuit = false;
            }

            if (_followTarget != null)
            {
                // Auto-steer toward the leader.
                Vector3 to = _followTarget.position - p; to.y = 0f;
                if (to.sqrMagnitude > 4f) joy = new Vector2(to.normalized.x, to.normalized.z);
            }

            if (wingsuit)
            {
                Vector3 fwd = _player.transform.forward; fwd.y = 0f; fwd.Normalize();
                if (joy.sqrMagnitude > 0.01f)
                {
                    // Steer the glide direction with the stick.
                    Vector3 wish = new Vector3(joy.x, 0f, joy.y);
                    wish = Quaternion.Euler(0f, _camYaw, 0f) * wish;
                    fwd = Vector3.Slerp(fwd, wish.normalized, Mathf.Min(1f, dt * 3f));
                    _player.transform.rotation = Quaternion.LookRotation(fwd);
                }
                _vel.x = fwd.x * WingsuitFwd;
                _vel.z = fwd.z * WingsuitFwd;
                _vel.y = Mathf.MoveTowards(_vel.y, -WingsuitV, 30f * dt);
            }
            else
            {
                Vector3 wish = new Vector3(joy.x, 0f, joy.y);
                wish = Quaternion.Euler(0f, _camYaw, 0f) * wish;
                _vel.x = wish.x * FreefallSteer;
                _vel.z = wish.z * FreefallSteer;
                _vel.y = Mathf.MoveTowards(_vel.y, -FreefallV, 40f * dt);
            }

            p += _vel * dt;
            ClampToWorld(ref p);

            float alt = p.y - _groundY;
            if (alt <= ChuteDeployAlt) DeployChute();
            else if (p.y <= _groundY + 0.6f) Land();
        }

        private void DeployChute()
        {
            if (_stage == DropStage.Chute) return;
            _stage = DropStage.Chute;
            _chuteBtn.gameObject.SetActive(false);
            _vel *= 0.25f;
            if (_rig != null && _rig.Anim != null) _rig.Anim.Play(SoldierClip.Parachute);
            BuildCanopy();
            if (_trail != null) _trail.emitting = false;
        }

        private void UpdateChute(float dt, ref Vector3 p)
        {
            Vector2 joy = _hud != null ? _hud.Joystick : Vector2.zero;
            if (_followTarget != null)
            {
                Vector3 to = _followTarget.position - p; to.y = 0f;
                if (to.sqrMagnitude > 4f) joy = new Vector2(to.normalized.x, to.normalized.z);
            }
            Vector3 wish = new Vector3(joy.x, 0f, joy.y);
            wish = Quaternion.Euler(0f, _camYaw, 0f) * wish;
            _vel.x = Mathf.MoveTowards(_vel.x, wish.x * ChuteSteer, 20f * dt);
            _vel.z = Mathf.MoveTowards(_vel.z, wish.z * ChuteSteer, 20f * dt);
            _vel.y = Mathf.MoveTowards(_vel.y, -ChuteV, 25f * dt);
            if (wish.sqrMagnitude > 0.01f)
                _player.transform.rotation = Quaternion.Slerp(_player.transform.rotation,
                    Quaternion.LookRotation(wish.normalized), Mathf.Min(1f, dt * 2.5f));
            p += _vel * dt;
            ClampToWorld(ref p);
            if (p.y <= _groundY + 0.6f) Land();
        }

        private void Land()
        {
            _stage = DropStage.Landed;
            Vector3 p = _player.transform.position;
            p.y = _groundY + 0.6f;
            _player.transform.position = p;
            CleanupDropVisuals();
            if (_dropHud != null) Destroy(_dropHud);
            if (_hud != null) _hud.CrosshairVisible = true;
            _player.enabled = true; // control returns to the PlayerController
            MatchManager.Instance.BeginCombat();
        }

        private float _camYaw;
        private void UpdateCamera(float dt, Vector3 p)
        {
            if (_cam == null) return;
            _camYaw = _cam.transform.eulerAngles.y;
            // Chase cam: behind + above the diver.
            Vector3 back = _player.transform.forward * -1f;
            back.y = 0f; back.Normalize();
            Vector3 want = p + back * 7f + Vector3.up * 3.2f;
            _cam.transform.position = Vector3.Lerp(_cam.transform.position, want, Mathf.Min(1f, dt * 5f));
            _cam.transform.LookAt(p + Vector3.up * 1.2f);
            _camYaw = _cam.transform.eulerAngles.y;
            if (_hud != null) _hud.SetHeading(_camYaw);
        }

        private void UpdateDropHud(Vector3 p)
        {
            if (_dropHud == null) return;
            float speedKmh = new Vector3(_vel.x, 0f, _vel.z).magnitude * 3.6f + Mathf.Abs(_vel.y) * 1.2f;
            if (_speedText != null) _speedText.text = Mathf.RoundToInt(speedKmh) + " Km/h";
            float alt = Mathf.Max(0f, p.y - _groundY);
            if (_altText != null) _altText.text = "ALT " + Mathf.RoundToInt(p.y) + "\nGROUND " + Mathf.RoundToInt(alt);
        }

        private void ClampToWorld(ref Vector3 p)
        {
            float half = WorldData.WorldSize * 0.5f + 120f;
            p.x = Mathf.Clamp(p.x, -half, half);
            p.z = Mathf.Clamp(p.z, -half, half);
        }

        private float SampleGround(Vector3 p)
        {
            RaycastHit hit;
            if (Physics.Raycast(new Vector3(p.x, 500f, p.z), Vector3.down, out hit, 600f))
                return hit.point.y;
            return 0f;
        }

        // ---------------- visuals ----------------

        private void BuildPlane(Vector3 at)
        {
            _plane = new GameObject("DropPlane");
            var mat = new Material(Shader.Find("Unlit/Color"));
            mat.color = new Color(0.25f, 0.28f, 0.32f, 1f);
            // Fuselage.
            var fus = GameObject.CreatePrimitive(PrimitiveType.Cube);
            fus.transform.SetParent(_plane.transform, false);
            fus.transform.localScale = new Vector3(3f, 2.5f, 14f);
            fus.GetComponent<Renderer>().material = mat;
            // Wings.
            var wing = GameObject.CreatePrimitive(PrimitiveType.Cube);
            wing.transform.SetParent(_plane.transform, false);
            wing.transform.localScale = new Vector3(22f, 0.4f, 4f);
            wing.GetComponent<Renderer>().material = mat;
            // Tail.
            var tail = GameObject.CreatePrimitive(PrimitiveType.Cube);
            tail.transform.SetParent(_plane.transform, false);
            tail.transform.localPosition = new Vector3(0f, 2f, -6f);
            tail.transform.localScale = new Vector3(0.4f, 4f, 3f);
            tail.GetComponent<Renderer>().material = mat;
            foreach (var c in _plane.GetComponentsInChildren<Collider>()) Destroy(c);
            _plane.transform.position = at + new Vector3(0f, 2f, 0f);
            _plane.transform.rotation = Quaternion.LookRotation(_planeDir);
        }

        private void BuildTrail(Color color)
        {
            var tr = _player.gameObject.AddComponent<TrailRenderer>();
            tr.time = 2.5f;
            tr.startWidth = 0.9f; tr.endWidth = 0.1f;
            tr.startColor = color; tr.endColor = new Color(color.r, color.g, color.b, 0f);
            tr.material = new Material(Shader.Find("Unlit/Transparent"));
            tr.emitting = true;
            _trail = tr;
        }

        private void BuildDescentLine()
        {
            var go = new GameObject("DescentLine");
            go.transform.SetParent(transform, false);
            _descentLine = go.AddComponent<LineRenderer>();
            _descentLine.positionCount = 2;
            _descentLine.startWidth = 0.25f; _descentLine.endWidth = 0.25f;
            _descentLine.material = new Material(Shader.Find("Unlit/Color"));
            _descentLine.material.color = new Color(1f, 0.85f, 0.2f, 0.9f); // thin yellow line
            _descentLine.useWorldSpace = true;
        }

        private void BuildCanopy()
        {
            _canopy = new GameObject("Parachute");
            _canopy.transform.SetParent(_player.transform, false);
            _canopy.transform.localPosition = new Vector3(0f, 4.2f, 0f);
            // Detailed canopy: half-dome with alternating panel colors.
            var dome = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            dome.transform.SetParent(_canopy.transform, false);
            dome.transform.localScale = new Vector3(7f, 2.2f, 5.5f);
            // Flatten the bottom by sinking it (dome reads as a canopy from below).
            var cmat = new Material(Shader.Find("Unlit/Color"));
            cmat.color = new Color(1f, 0.55f, 0.1f, 1f); // safety orange
            dome.GetComponent<Renderer>().material = cmat;
            Destroy(dome.GetComponent<Collider>());
            // White crown panel.
            var crown = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            crown.transform.SetParent(_canopy.transform, false);
            crown.transform.localPosition = new Vector3(0f, 1.1f, 0f);
            crown.transform.localScale = new Vector3(2.4f, 1.2f, 2f);
            var wmat = new Material(Shader.Find("Unlit/Color"));
            wmat.color = Color.white;
            crown.GetComponent<Renderer>().material = wmat;
            Destroy(crown.GetComponent<Collider>());
            // Rigging lines: 8 lines from canopy rim to the harness.
            var lmat = new Material(Shader.Find("Unlit/Color"));
            lmat.color = new Color(0.9f, 0.9f, 0.9f, 0.95f);
            for (int i = 0; i < 8; i++)
            {
                var lg = new GameObject("Rig" + i);
                lg.transform.SetParent(_canopy.transform, false);
                var lr = lg.AddComponent<LineRenderer>();
                lr.positionCount = 2;
                lr.startWidth = 0.05f; lr.endWidth = 0.05f;
                lr.material = lmat;
                lr.useWorldSpace = false;
                float a = i / 8f * Mathf.PI * 2f;
                lr.SetPosition(0, new Vector3(Mathf.Cos(a) * 3.4f, -0.4f, Mathf.Sin(a) * 2.7f));
                lr.SetPosition(1, new Vector3(0f, -3.4f, 0f)); // harness at the shoulders
                _rigging.Add(lr);
            }
        }

        private void SpawnPoiLabels()
        {
            foreach (var poi in WorldData.Pois)
            {
                var go = new GameObject("Poi_" + poi.Id);
                go.transform.SetParent(transform, false);
                go.transform.position = poi.Position + new Vector3(0f, 90f, 0f);
                var tm = go.AddComponent<TextMesh>();
                tm.text = poi.Name.ToUpper();
                tm.fontSize = 48;
                tm.characterSize = 2.2f;
                tm.color = new Color(1f, 1f, 1f, 0.85f);
                tm.anchor = TextAnchor.MiddleCenter;
                tm.alignment = TextAlignment.Center;
                _poiLabels.Add(go);
            }
        }

        private void BillboardPoiLabels()
        {
            if (_cam == null) return;
            for (int i = 0; i < _poiLabels.Count; i++)
            {
                var go = _poiLabels[i];
                if (go == null) continue;
                go.transform.rotation = _cam.transform.rotation;
                // Fade out as the player gets close to the ground.
                float alt = _player.transform.position.y - _groundY;
                var tm = go.GetComponent<TextMesh>();
                var c = tm.color;
                c.a = Mathf.Clamp01((alt - 40f) / 120f) * 0.85f;
                tm.color = c;
            }
        }

        private void CleanupDropVisuals()
        {
            if (_trail != null) Destroy(_trail);
            if (_descentLine != null) Destroy(_descentLine.gameObject);
            if (_canopy != null) Destroy(_canopy);
            for (int i = 0; i < _poiLabels.Count; i++)
                if (_poiLabels[i] != null) Destroy(_poiLabels[i]);
            _poiLabels.Clear();
        }

        private void LateUpdate()
        {
            // Keep the yellow descent line drawn from the diver to the ground.
            if (_descentLine != null && _player != null)
            {
                Vector3 p = _player.transform.position;
                _descentLine.SetPosition(0, p);
                _descentLine.SetPosition(1, new Vector3(p.x, _groundY, p.z));
            }
        }

        // ---------------- drop HUD ----------------

        private void BuildDropHud()
        {
            _dropHud = UiKit.OverlayCanvas("DropHud", 12);
            _dropHud.transform.SetParent(transform, false);

            // SPEED km/h + ALT/GROUND readouts, right side (bible §2).
            _speedText = UiKit.Label(_dropHud.transform, "0 Km/h", 34, Color.white,
                TextAnchor.MiddleRight, FontStyle.Bold);
            UiKit.Place(_speedText.GetComponent<RectTransform>(), 0.78f, 0.42f, 0.97f, 0.50f);
            _altText = UiKit.Label(_dropHud.transform, "ALT 0\nGROUND 0", 26,
                new Color(1f, 1f, 1f, 0.9f), TextAnchor.MiddleRight);
            UiKit.Place(_altText.GetComponent<RectTransform>(), 0.78f, 0.32f, 0.97f, 0.42f);

            // "Following X" chip + Cancel Follow.
            _followChip = UiKit.Label(_dropHud.transform, "", 26, new Color(1f, 0.85f, 0.3f),
                TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(_followChip.GetComponent<RectTransform>(), 0.35f, 0.70f, 0.65f, 0.76f);
            _followChip.gameObject.SetActive(false);
            _cancelFollowBtn = UiKit.Button(_dropHud.transform, "CANCEL FOLLOW",
                () => SetFollowTarget(null, "", Color.white),
                new Color(0.2f, 0.22f, 0.26f, 0.9f), 22);
            UiKit.Place(_cancelFollowBtn.GetComponent<RectTransform>(), 0.42f, 0.64f, 0.58f, 0.69f);
            _cancelFollowBtn.gameObject.SetActive(false);

            // JUMP prompt (plane stage).
            _jumpBtn = UiKit.Button(_dropHud.transform, "JUMP",
                () => Jump(), new Color(1f, 0.62f, 0.12f, 0.95f), 40);
            UiKit.Place(_jumpBtn.GetComponent<RectTransform>(), 0.40f, 0.18f, 0.60f, 0.30f);
            _jumpBtn.gameObject.SetActive(false);

            // Manual chute deploy.
            _chuteBtn = UiKit.Button(_dropHud.transform, "DEPLOY CHUTE",
                () => DeployChute(), new Color(0.2f, 0.5f, 0.9f, 0.9f), 26);
            UiKit.Place(_chuteBtn.GetComponent<RectTransform>(), 0.42f, 0.10f, 0.58f, 0.18f);
            _chuteBtn.gameObject.SetActive(false);
        }
    }
}
