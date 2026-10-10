using System;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Arsenal;
using NovaMobile.Classes;
using NovaMobile.Core;
using NovaMobile.Economy;
using NovaMobile.Soldiers;
using NovaMobile.Vehicles;

namespace NovaMobile.Match
{
    /// <summary>
    /// 3D lobby (visual bible §1): NOT a flat menu. The player's operator
    /// (Soldiers rig, idle animation, current skin, holding the primary weapon)
    /// stands center-screen in a small military-base environment (concrete
    /// barriers, tent, parked vehicle). Profile card top-left, LOADOUT button
    /// bottom-left (operator / class / weapons + skins, all persisted),
    /// STORE top-right, big yellow START bottom-right -> straight into the
    /// drop-in. No map select (one world), no pre-match screens.
    /// </summary>
    public class LobbyScene : MonoBehaviour
    {
        public static LobbyScene Instance;

        private MatchManager _mgr;
        private GameObject _sceneRoot;
        private Camera _cam;
        private SoldierRig _operator;
        private GameObject _heldGun;

        private GameObject _uiRoot;
        private StoreUI _store;
        private Text _profileName;
        private Text _profileLevel;
        private GameObject _loadoutPanel;
        private GameObject _operatorPanel;
        private Image _sentinelCard;
        private Image _breacherCard;

        private LoadoutData Loadout => _mgr != null ? _mgr.Loadout : LoadoutData.Load();

        public static LobbyScene Show(MatchManager mgr)
        {
            if (Instance == null)
            {
                var go = new GameObject("LobbyScene");
                Instance = go.AddComponent<LobbyScene>();
                Instance._mgr = mgr;
                Instance.BuildScene();
                Instance.BuildUI();
            }
            Instance._mgr = mgr;
            Instance.gameObject.SetActive(true);
            Instance.RefreshOperator();
            return Instance;
        }

        public void Show()
        {
            gameObject.SetActive(true);
            RefreshOperator();
        }

        public void Hide()
        {
            if (_loadoutPanel != null) _loadoutPanel.SetActive(false);
            gameObject.SetActive(false);
        }

        private void OnDestroy() { if (Instance == this) Instance = null; }

        // ---------------- 3D environment ----------------

        private void BuildScene()
        {
            _sceneRoot = new GameObject("LobbyEnv");
            _sceneRoot.transform.SetParent(transform, false);

            // Camera: frames the operator center-screen.
            var camGo = new GameObject("LobbyCam");
            camGo.transform.SetParent(_sceneRoot.transform, false);
            _cam = camGo.AddComponent<Camera>();
            _cam.transform.position = new Vector3(0f, 1.7f, 4.6f);
            _cam.transform.LookAt(new Vector3(0f, 1.05f, 0f));
            _cam.fieldOfView = 42f;
            _cam.backgroundColor = new Color(0.55f, 0.74f, 0.92f, 1f); // hazy sky
            _cam.clearFlags = CameraClearFlags.SolidColor;

            var sun = new GameObject("Sun").AddComponent<Light>();
            sun.transform.SetParent(_sceneRoot.transform, false);
            sun.type = LightType.Directional;
            sun.intensity = 1.15f;
            sun.color = new Color(1f, 0.96f, 0.9f);
            sun.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            RenderSettings.ambientLight = new Color(0.55f, 0.6f, 0.68f);

            // Ground: textured parade square.
            var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
            ground.name = "Ground";
            ground.transform.SetParent(_sceneRoot.transform, false);
            ground.transform.localScale = new Vector3(7f, 1f, 7f);
            var gmat = new Material(Shader.Find("Unlit/Texture"));
            gmat.mainTexture = ProcTexture.Dirt(256, 23);
            ground.GetComponent<Renderer>().material = gmat;

            var concMat = new Material(Shader.Find("Unlit/Color"));
            concMat.color = new Color(0.62f, 0.62f, 0.64f, 1f);

            // Concrete barriers flanking the operator.
            for (int i = 0; i < 4; i++)
            {
                var b = GameObject.CreatePrimitive(PrimitiveType.Cube);
                b.name = "Barrier" + i;
                b.transform.SetParent(_sceneRoot.transform, false);
                float x = (i % 2 == 0 ? -1f : 1f) * 4.2f;
                float z = (i < 2 ? 1f : -1f) * 2.6f;
                b.transform.position = new Vector3(x, 0.55f, z);
                b.transform.localScale = new Vector3(2.6f, 1.1f, 0.6f);
                b.transform.rotation = Quaternion.Euler(0f, (i % 2 == 0 ? 12f : -12f), 0f);
                b.GetComponent<Renderer>().material = concMat;
            }

            // Tent: poles + slanted canopy, back-right.
            var tentMat = new Material(Shader.Find("Unlit/Color"));
            tentMat.color = new Color(0.42f, 0.44f, 0.36f, 1f);
            for (int i = 0; i < 4; i++)
            {
                var pole = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                pole.transform.SetParent(_sceneRoot.transform, false);
                pole.transform.position = new Vector3(5.5f + (i % 2) * 3f, 1.25f, -4.5f + (i / 2) * 3f);
                pole.transform.localScale = new Vector3(0.12f, 2.5f, 0.12f);
                pole.GetComponent<Renderer>().material = concMat;
            }
            var canopy = GameObject.CreatePrimitive(PrimitiveType.Cube);
            canopy.transform.SetParent(_sceneRoot.transform, false);
            canopy.transform.position = new Vector3(7f, 2.75f, -3f);
            canopy.transform.localScale = new Vector3(4.4f, 0.15f, 4.4f);
            canopy.transform.rotation = Quaternion.Euler(0f, 0f, 6f);
            canopy.GetComponent<Renderer>().material = tentMat;

            // Parked vehicle (Jeep) back-left.
            try
            {
                var vm = VehicleFactory.Build(VehicleType.Jeep, 0);
                vm.Root.transform.SetParent(_sceneRoot.transform, false);
                vm.Root.transform.position = new Vector3(-6.5f, 0f, -4f);
                vm.Root.transform.rotation = Quaternion.Euler(0f, 35f, 0f);
            }
            catch (Exception e) { Debug.LogWarning("[LobbyScene] vehicle: " + e.Message); }

            // Ammo crates near the operator.
            var crateMat = new Material(Shader.Find("Unlit/Color"));
            crateMat.color = new Color(0.45f, 0.36f, 0.22f, 1f);
            for (int i = 0; i < 3; i++)
            {
                var c = GameObject.CreatePrimitive(PrimitiveType.Cube);
                c.transform.SetParent(_sceneRoot.transform, false);
                c.transform.position = new Vector3(2.6f + (i % 2) * 0.7f, 0.3f + (i / 2) * 0.62f, 1.8f);
                c.transform.localScale = new Vector3(0.6f, 0.6f, 0.6f);
                c.GetComponent<Renderer>().material = crateMat;
            }

            // Distant building silhouettes for depth.
            var bMat = new Material(Shader.Find("Unlit/Color"));
            bMat.color = new Color(0.5f, 0.55f, 0.62f, 1f);
            for (int i = 0; i < 5; i++)
            {
                var b = GameObject.CreatePrimitive(PrimitiveType.Cube);
                b.transform.SetParent(_sceneRoot.transform, false);
                b.transform.position = new Vector3(-18f + i * 9f, 3f, -22f);
                b.transform.localScale = new Vector3(6f, 6f + (i % 3) * 2f, 5f);
                b.GetComponent<Renderer>().material = bMat;
            }
        }

        private void RefreshOperator()
        {
            var loadout = Loadout;
            SoldierVariant v = loadout.CharacterVariant == 1 ? SoldierVariant.Breacher : SoldierVariant.Sentinel;
            if (_operator == null)
            {
                _operator = SoldierRig.Build(v, "LobbyOperator");
                _operator.transform.SetParent(_sceneRoot.transform, false);
                _operator.transform.position = Vector3.zero;
                _operator.transform.rotation = Quaternion.Euler(0f, 180f, 0f); // face the camera
            }
            else _operator.SetVariant(v);
            if (_operator.Anim != null) _operator.Anim.Play(SoldierClip.Idle);

            // Primary weapon in hand.
            if (_heldGun != null) Destroy(_heldGun);
            try
            {
                var spec = GunData.Get(loadout.PrimaryGunId);
                _heldGun = GunFactory.BuildGun(spec, false);
                var mount = _operator.WeaponMount;
                if (mount != null)
                {
                    _heldGun.transform.SetParent(mount, false);
                    _heldGun.transform.localPosition = Vector3.zero;
                    _heldGun.transform.localRotation = Quaternion.identity;
                }
                else _heldGun.transform.SetParent(_operator.transform, false);
            }
            catch (Exception e) { Debug.LogWarning("[LobbyScene] gun: " + e.Message); }

            // Operator card highlight.
            if (_sentinelCard != null)
            {
                _sentinelCard.color = loadout.CharacterVariant == 0
                    ? new Color(1f, 0.72f, 0.15f, 0.95f) : new Color(0.16f, 0.18f, 0.22f, 0.92f);
                _breacherCard.color = loadout.CharacterVariant == 1
                    ? new Color(1f, 0.72f, 0.15f, 0.95f) : new Color(0.16f, 0.18f, 0.22f, 0.92f);
            }
        }

        // ---------------- UI ----------------

        private void BuildUI()
        {
            _uiRoot = UiKit.OverlayCanvas("LobbyUI", 20);
            _uiRoot.transform.SetParent(transform, false);

            // Top-left: profile card.
            var card = UiKit.Panel(_uiRoot.transform, new Color(0.05f, 0.06f, 0.09f, 0.85f));
            UiKit.Place(card.GetComponent<RectTransform>(), 0.012f, 0.86f, 0.20f, 0.985f);
            _profileName = UiKit.Label(card.transform, "ZENAS", 34, Color.white,
                TextAnchor.MiddleLeft, FontStyle.Bold);
            UiKit.Place(_profileName.GetComponent<RectTransform>(), 0.06f, 0.5f, 0.94f, 0.95f);
            _profileLevel = UiKit.Label(card.transform, "LV.1 — RECRUIT", 22,
                new Color(1f, 0.85f, 0.3f), TextAnchor.MiddleLeft);
            UiKit.Place(_profileLevel.GetComponent<RectTransform>(), 0.06f, 0.08f, 0.94f, 0.5f);

            // Header.
            var header = UiKit.Label(_uiRoot.transform, "NOVA MOBILE — BATTLE ROYALE", 40,
                Color.white, TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(header.GetComponent<RectTransform>(), 0.22f, 0.90f, 0.78f, 0.985f);

            // Top-right: STORE (Economy system's full store UI).
            var storeBtn = UiKit.Button(_uiRoot.transform, "STORE",
                () => EnsureStore().Show(), new Color(0.15f, 0.45f, 0.85f, 0.95f), 30);
            UiKit.Place(storeBtn.GetComponent<RectTransform>(), 0.86f, 0.885f, 0.985f, 0.975f);

            // Bottom-left: LOADOUT.
            var loadoutBtn = UiKit.Button(_uiRoot.transform, "LOADOUT",
                () => ToggleLoadoutPanel(), new Color(0.16f, 0.18f, 0.24f, 0.95f), 36);
            UiKit.Place(loadoutBtn.GetComponent<RectTransform>(), 0.03f, 0.04f, 0.24f, 0.16f);

            // Bottom-right: big yellow START -> straight into the drop-in.
            var startBtn = UiKit.Button(_uiRoot.transform, "DEPLOY — START",
                () => _mgr.StartMatch(), new Color(1f, 0.72f, 0.12f, 1f), 44);
            UiKit.Place(startBtn.GetComponent<RectTransform>(), 0.68f, 0.04f, 0.97f, 0.17f);
            var st = startBtn.GetComponentInChildren<Text>();
            if (st != null) st.color = Color.black;

            // Current loadout summary (bottom-center).
            var sum = UiKit.Label(_uiRoot.transform, "", 24, new Color(1f, 1f, 1f, 0.85f));
            UiKit.Place(sum.GetComponent<RectTransform>(), 0.26f, 0.05f, 0.66f, 0.15f);
            sum.gameObject.AddComponent<LoadoutSummaryBinder>().Bind(sum, this);

            BuildLoadoutPanel();
            BuildOperatorPanel();
            _loadoutPanel.SetActive(false);
            _operatorPanel.SetActive(false);
        }

        private void BuildLoadoutPanel()
        {
            _loadoutPanel = new GameObject("LoadoutPanel");
            _loadoutPanel.transform.SetParent(_uiRoot.transform, false);
            var rt = _loadoutPanel.AddComponent<RectTransform>();
            UiKit.Place(rt, 0.03f, 0.18f, 0.45f, 0.84f);
            var bg = _loadoutPanel.AddComponent<Image>();
            bg.color = new Color(0.05f, 0.06f, 0.09f, 0.96f);

            var title = UiKit.Label(_loadoutPanel.transform, "LOADOUT", 38,
                new Color(1f, 0.85f, 0.3f), TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(title.GetComponent<RectTransform>(), 0f, 0.86f, 1f, 0.98f);

            var opBtn = UiKit.Button(_loadoutPanel.transform, "OPERATOR",
                () => { _operatorPanel.SetActive(true); },
                new Color(0.2f, 0.24f, 0.32f, 1f), 32);
            UiKit.Place(opBtn.GetComponent<RectTransform>(), 0.08f, 0.62f, 0.92f, 0.80f);

            var clBtn = UiKit.Button(_loadoutPanel.transform, "CLASS",
                () =>
                {
                    string cur = Loadout.ClassId;
                    ClassSelectUI.Show(_uiRoot.transform, (id) =>
                    {
                        var l = Loadout; l.ClassId = id; l.Save();
                        RefreshOperator();
                    }, cur);
                },
                new Color(0.2f, 0.24f, 0.32f, 1f), 32);
            UiKit.Place(clBtn.GetComponent<RectTransform>(), 0.08f, 0.42f, 0.92f, 0.60f);

            var wpBtn = UiKit.Button(_loadoutPanel.transform, "WEAPONS + SKINS",
                () =>
                {
                    var gs = GunsmithUI.Create();
                    gs.transform.SetParent(_uiRoot.transform, false);
                    gs.OnDeploy = (gid, skin, attach) =>
                    {
                        var l = Loadout;
                        l.PrimaryGunId = gid; l.PrimarySkin = skin;
                        l.PrimaryAttachments = attach ?? new string[0];
                        l.Save();
                        RefreshOperator();
                        Destroy(gs.gameObject);
                    };
                    // Close affordance (GunsmithUI has none of its own).
                    var x = UiKit.Button(gs.transform, "X", () => Destroy(gs.gameObject),
                        new Color(0.7f, 0.15f, 0.12f, 0.95f), 30);
                    var xrt = x.GetComponent<RectTransform>();
                    xrt.anchorMin = new Vector2(1f, 1f); xrt.anchorMax = new Vector2(1f, 1f);
                    xrt.sizeDelta = new Vector2(70f, 70f);
                    xrt.anchoredPosition = new Vector2(-45f, -45f);
                },
                new Color(0.2f, 0.24f, 0.32f, 1f), 32);
            UiKit.Place(wpBtn.GetComponent<RectTransform>(), 0.08f, 0.22f, 0.92f, 0.40f);

            var close = UiKit.Button(_loadoutPanel.transform, "CLOSE",
                () => _loadoutPanel.SetActive(false),
                new Color(0.35f, 0.12f, 0.1f, 1f), 28);
            UiKit.Place(close.GetComponent<RectTransform>(), 0.30f, 0.04f, 0.70f, 0.16f);
        }

        private void BuildOperatorPanel()
        {
            _operatorPanel = new GameObject("OperatorPanel");
            _operatorPanel.transform.SetParent(_uiRoot.transform, false);
            var rt = _operatorPanel.AddComponent<RectTransform>();
            UiKit.Place(rt, 0.47f, 0.18f, 0.89f, 0.84f);
            var bg = _operatorPanel.AddComponent<Image>();
            bg.color = new Color(0.05f, 0.06f, 0.09f, 0.96f);

            var title = UiKit.Label(_operatorPanel.transform, "CHOOSE OPERATOR", 34,
                new Color(1f, 0.85f, 0.3f), TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(title.GetComponent<RectTransform>(), 0f, 0.86f, 1f, 0.98f);

            _sentinelCard = MakeOperatorCard(_operatorPanel.transform,
                0.06f, 0.30f, 0.46f, 0.82f,
                "SENTINEL", "Masked operator\nDigital-camo helmet\nRed-lens goggles", 0);
            _breacherCard = MakeOperatorCard(_operatorPanel.transform,
                0.54f, 0.30f, 0.94f, 0.82f,
                "BREACHER", "Bare-faced shotgunner\nTan cap\nShell chest rig", 1);

            var close = UiKit.Button(_operatorPanel.transform, "DONE",
                () => _operatorPanel.SetActive(false),
                new Color(1f, 0.62f, 0.12f, 1f), 28);
            UiKit.Place(close.GetComponent<RectTransform>(), 0.32f, 0.06f, 0.68f, 0.20f);
        }

        private Image MakeOperatorCard(Transform parent,
            float x0, float y0, float x1, float y1, string name, string desc, int variant)
        {
            var go = new GameObject("Op_" + name);
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.color = new Color(0.16f, 0.18f, 0.22f, 0.92f);
            UiKit.Place(go.GetComponent<RectTransform>(), x0, y0, x1, y1);
            var btn = go.AddComponent<Button>();
            btn.onClick.AddListener(() =>
            {
                var l = Loadout; l.CharacterVariant = variant; l.Save();
                RefreshOperator();
            });
            var tn = UiKit.Label(go.transform, name, 30, Color.white, TextAnchor.MiddleCenter, FontStyle.Bold);
            UiKit.Place(tn.GetComponent<RectTransform>(), 0f, 0.62f, 1f, 0.95f);
            var td = UiKit.Label(go.transform, desc, 22, new Color(0.75f, 0.78f, 0.85f));
            UiKit.Place(td.GetComponent<RectTransform>(), 0.05f, 0.05f, 0.95f, 0.60f);
            return img;
        }

        private void ToggleLoadoutPanel()
        {
            _loadoutPanel.SetActive(!_loadoutPanel.activeSelf);
            if (!_loadoutPanel.activeSelf && _operatorPanel != null)
                _operatorPanel.SetActive(false);
        }

        private StoreUI EnsureStore()
        {
            if (_store == null)
            {
                var go = new GameObject("StoreUI");
                go.transform.SetParent(transform, false);
                _store = go.AddComponent<StoreUI>();
            }
            return _store;
        }

        // Binds the bottom-center summary line to the current loadout.
        private class LoadoutSummaryBinder : MonoBehaviour
        {
            private Text _t; private LobbyScene _scene;
            public void Bind(Text t, LobbyScene s) { _t = t; _scene = s; }
            private void Update()
            {
                if (_t == null || _scene == null) return;
                var l = _scene.Loadout;
                string op = l.CharacterVariant == 1 ? "BREACHER" : "SENTINEL";
                string gun;
                try { gun = GunData.Get(l.PrimaryGunId).Name.ToUpper(); }
                catch { gun = l.PrimaryGunId.ToUpper(); }
                string cls;
                try { cls = ClassData.Get(l.ClassId).Name.ToUpper(); }
                catch { cls = l.ClassId.ToUpper(); }
                _t.text = op + "  ·  " + cls + "  ·  " + gun;
            }
        }
    }
}
