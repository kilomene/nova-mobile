using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Core;
using NovaMobile.Economy;

namespace NovaMobile.Arsenal
{
    /// <summary>
    /// NOVA gunsmith: pick primary gun, mythic skin, attachments — with a live 3D
    /// preview, stat bars, and STK ("4 SHOTS · 3 HEAD") front and center.
    /// Lobby LOADOUT screen: the loadout (character/class/guns/skins) is chosen and
    /// saved here; match start goes straight into drop-in (no pre-match picking).
    /// Ported from Godot gunsmith.gd. uGUI only, anchored by screen fraction.
    ///
    /// Mythic hooks (filled by the Mythics system; sensible fallbacks otherwise):
    ///   SkinCountHook / SkinNameHook / SkinColorHook / SkinOwnershipHook.
    /// Skin ownership is checked via NovaMobile.Economy.NpWallet.OwnsSkin(skinId)
    /// per the cross-system contract (skinId = gunId + "_skin_" + index).
    /// </summary>
    public class GunsmithUI : MonoBehaviour
    {
        public const int MythicPrice = 950; // StoreDefs.MYTHIC_PRICE (store_defs.gd)

        /// <summary>Fired on SAVE LOADOUT: (gunId, skinIdx, attachIds).</summary>
        public Action<string, int, string[]> OnDeploy;
        /// <summary>Fired when a locked mythic skin is tapped: (skinId, price).</summary>
        public Action<string, int> OnSkinLocked;

        // Mythics-system hooks (optional; fallbacks keep the panel functional).
        public static Func<string, int> SkinCountHook;                    // default 3
        public static Func<string, int, string> SkinNameHook;             // default "MYTHIC SKIN n"
        public static Func<string, int, Color> SkinColorHook;             // default purple
        public static Func<string, bool> SkinOwnershipHook;               // default NpWallet

        private static readonly string[] AttachSlots = new string[] { "muzzle", "optic", "magazine", "underbarrel" };

        private GunClass _selClass = GunClass.AssaultRifle;
        private string _selGun = "m5";
        private int _selSkin;
        private readonly Dictionary<string, string> _selAttach = new Dictionary<string, string>();

        private Transform _gunList;
        private Transform _skinBox;
        private Transform _attachBox;
        private Text _previewName;
        private Text _stkLabel;
        private Text _statsLabel;
        private Text _attachDescLabel;
        private readonly Dictionary<string, Image> _statBars = new Dictionary<string, Image>();
        private readonly Dictionary<string, Text> _statVals = new Dictionary<string, Text>();

        // 3D preview
        private GameObject _rigRoot;
        private Camera _previewCam;
        private RenderTexture _previewRt;
        private GameObject _previewRoot;
        private float _previewT;
        private const int PreviewLayer = 28;

        private Font _font;
        private static readonly Color Gold = new Color(1f, 0.75f, 0.2f);
        private static readonly Color StkOrange = new Color(1f, 0.62f, 0.15f);

        // ---------------- construction ----------------
        public static GunsmithUI Create()
        {
            var go = new GameObject("GunsmithUI");
            var ui = go.AddComponent<GunsmithUI>();
            var canvas = go.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 20;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280f, 720f);
            go.AddComponent<GraphicRaycaster>();
            ui._font = Resources.GetBuiltinResource<Font>("Arial.ttf");
            ui.Build();
            return ui;
        }

        private void Build()
        {
            var bg = AddImage(transform, new Color(0.03f, 0.04f, 0.06f, 0.97f));
            Stretch(bg);
            var root = AddVBox(transform, 10);
            Stretch(root);
            var pad = root.GetComponent<VerticalLayoutGroup>();
            pad.padding = new RectOffset(24, 24, 16, 16);

            var title = AddText(root, "GUNSMITH", 44, Gold, TextAnchor.MiddleCenter);
            AddText(root, "SELECT PRIMARY WEAPON · MYTHIC SKIN · ATTACHMENTS", 18,
                new Color(0.8f, 0.8f, 0.8f), TextAnchor.MiddleCenter);

            var hb = new GameObject("Columns").AddComponent<RectTransform>();
            hb.SetParent(root, false);
            var hl = hb.gameObject.AddComponent<HorizontalLayoutGroup>();
            hl.spacing = 16;
            hl.childForceExpandWidth = false;
            hl.childForceExpandHeight = true;
            var hle = hb.gameObject.AddComponent<LayoutElement>();
            hle.flexibleHeight = 1f;

            BuildLeft(hb.transform);
            BuildCenter(hb.transform);
            BuildRight(hb.transform);
            RefreshGunList();
            RebuildPreview();
            RefreshAttachments();
        }

        private void BuildLeft(Transform parent)
        {
            var lv = AddVBox(parent, 6);
            var le = lv.gameObject.AddComponent<LayoutElement>();
            le.preferredWidth = 300f;
            le.flexibleHeight = 1f;

            var grid = new GameObject("ClassTabs").AddComponent<RectTransform>();
            grid.SetParent(lv, false);
            var gl = grid.gameObject.AddComponent<GridLayoutGroup>();
            gl.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            gl.constraintCount = 3;
            gl.cellSize = new Vector2(92f, 40f);
            gl.spacing = new Vector2(6f, 6f);
            foreach (GunClass c in Enum.GetValues(typeof(GunClass)))
            {
                GunClass cc = c;
                var b = AddButton(grid.transform, GunData.ClassDisplayName(cc).ToUpper(), 13,
                    () => OnClassTab(cc));
                b.GetComponent<LayoutElement>().preferredHeight = 40f;
            }

            var scroll = new GameObject("GunScroll").AddComponent<RectTransform>();
            scroll.SetParent(lv, false);
            var sle = scroll.gameObject.AddComponent<LayoutElement>();
            sle.flexibleHeight = 1f;
            var sr = scroll.gameObject.AddComponent<ScrollRect>();
            sr.horizontal = false;
            var viewport = new GameObject("Viewport").AddComponent<RectTransform>();
            viewport.SetParent(scroll, false);
            Stretch(viewport);
            viewport.gameObject.AddComponent<Image>().color = new Color(0f, 0f, 0f, 0.25f);
            viewport.gameObject.AddComponent<Mask>().showMaskGraphic = true;
            _gunList = AddVBox(viewport, 4);
            var cle = _gunList.gameObject.AddComponent<LayoutElement>();
            cle.flexibleWidth = 1f;
            sr.content = _gunList.GetComponent<RectTransform>();
            sr.viewport = viewport;
        }

        private void BuildCenter(Transform parent)
        {
            var cv = AddVBox(parent, 8);
            var cle = cv.gameObject.AddComponent<LayoutElement>();
            cle.flexibleWidth = 1f;
            cle.flexibleHeight = 1f;

            // preview camera -> RenderTexture -> RawImage.
            // The whole preview rig lives at a remote position on its own layer so no
            // gameplay camera can ever see it.
            _previewRt = new RenderTexture(512, 512, 16);
            var rawGo = new GameObject("Preview").AddComponent<RectTransform>();
            rawGo.SetParent(cv, false);
            var rle = rawGo.gameObject.AddComponent<LayoutElement>();
            rle.flexibleWidth = 1f;
            rle.flexibleHeight = 1f;
            var raw = rawGo.gameObject.AddComponent<RawImage>();
            raw.texture = _previewRt;
            raw.color = new Color(0.05f, 0.06f, 0.08f, 1f);

            _rigRoot = new GameObject("PreviewRig");
            _rigRoot.transform.position = new Vector3(0f, -500f, 0f);
            var camGo = new GameObject("PreviewCam");
            camGo.transform.SetParent(_rigRoot.transform, false);
            _previewCam = camGo.AddComponent<Camera>();
            _previewCam.cullingMask = 1 << PreviewLayer;
            _previewCam.clearFlags = CameraClearFlags.SolidColor;
            _previewCam.backgroundColor = new Color(0.05f, 0.06f, 0.08f, 1f);
            _previewCam.targetTexture = _previewRt;
            _previewCam.enabled = false;
            var sunGo = new GameObject("PreviewSun");
            sunGo.transform.SetParent(_rigRoot.transform, false);
            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 1.2f;
            sun.cullingMask = 1 << PreviewLayer;
            sunGo.transform.rotation = Quaternion.Euler(-40f, 35f, 0f);
            var fillGo = new GameObject("PreviewFill");
            fillGo.transform.SetParent(_rigRoot.transform, false);
            var fill = fillGo.AddComponent<Light>();
            fill.type = LightType.Point;
            fill.intensity = 0.5f;
            fill.cullingMask = 1 << PreviewLayer;
            fillGo.transform.localPosition = new Vector3(-0.6f, 0.4f, 0.8f);
            DontDestroyOnLoad(_rigRoot);

            _previewName = AddText(cv, "", 24, Color.white, TextAnchor.MiddleCenter);
        }

        private void BuildRight(Transform parent)
        {
            var rv = AddVBox(parent, 8);
            var rle = rv.gameObject.AddComponent<LayoutElement>();
            rle.preferredWidth = 360f;
            rle.flexibleHeight = 1f;

            _stkLabel = AddText(rv, "", 30, StkOrange, TextAnchor.MiddleCenter);
            _statsLabel = AddText(rv, "", 16, new Color(0.85f, 0.85f, 0.85f), TextAnchor.UpperLeft);

            BuildStatBars(rv);

            AddText(rv, "MYTHIC SKINS", 18, new Color(0.85f, 0.5f, 1f), TextAnchor.MiddleLeft);
            _skinBox = AddVBox(rv, 4);
            var evo = AddText(rv, "Mythic skins evolve at 5 / 10 / 20 match kills.", 13,
                new Color(0.7f, 0.7f, 0.75f), TextAnchor.UpperLeft);

            AddText(rv, "ATTACHMENTS", 18, new Color(0.6f, 0.85f, 1f), TextAnchor.MiddleLeft);
            _attachBox = AddVBox(rv, 4);
            _attachDescLabel = AddText(rv, "", 12, new Color(0.7f, 0.75f, 0.8f), TextAnchor.UpperLeft);

            var dep = AddButton(rv, "SAVE LOADOUT", 26, OnDeployPressed);
            dep.GetComponentInChildren<Text>().color = Gold;
            var dle = dep.GetComponent<LayoutElement>();
            dle.preferredHeight = 64f;
        }

        private void BuildStatBars(Transform parent)
        {
            string[] stats = { "Damage", "RPM", "Range", "Mag", "Recoil" };
            foreach (string s in stats)
            {
                var row = new GameObject("Stat_" + s).AddComponent<RectTransform>();
                row.SetParent(parent, false);
                var hl = row.gameObject.AddComponent<HorizontalLayoutGroup>();
                hl.spacing = 8;
                hl.childForceExpandWidth = false;
                var lab = AddText(row.transform, s, 13, new Color(0.75f, 0.75f, 0.78f), TextAnchor.MiddleLeft);
                lab.GetComponent<LayoutElement>().preferredWidth = 70f;
                var bgGo = new GameObject("BarBg").AddComponent<RectTransform>();
                bgGo.SetParent(row.transform, false);
                var bgLe = bgGo.gameObject.AddComponent<LayoutElement>();
                bgLe.flexibleWidth = 1f;
                bgLe.preferredHeight = 14f;
                var bgImg = bgGo.gameObject.AddComponent<Image>();
                bgImg.color = new Color(0.15f, 0.16f, 0.18f, 1f);
                var fillGo = new GameObject("BarFill").AddComponent<RectTransform>();
                fillGo.SetParent(bgGo, false);
                Stretch(fillGo);
                var fill = fillGo.gameObject.AddComponent<Image>();
                fill.color = Gold;
                fill.type = Image.Type.Filled;
                fill.fillMethod = Image.FillMethod.Horizontal;
                _statBars[s] = fill;
                var val = AddText(row.transform, "", 13, Color.white, TextAnchor.MiddleRight);
                val.GetComponent<LayoutElement>().preferredWidth = 60f;
                _statVals[s] = val;
            }
        }

        // ---------------- UI helpers ----------------
        private RectTransform AddImage(Transform parent, Color c)
        {
            var rt = new GameObject("Image").AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.gameObject.AddComponent<Image>().color = c;
            return rt;
        }

        private void Stretch(RectTransform rt)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;
        }

        private RectTransform AddVBox(Transform parent, float spacing)
        {
            var rt = new GameObject("VBox").AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            var vg = rt.gameObject.AddComponent<VerticalLayoutGroup>();
            vg.spacing = spacing;
            vg.childForceExpandWidth = true;
            vg.childForceExpandHeight = false;
            vg.childControlHeight = true;
            return rt;
        }

        private Text AddText(Transform parent, string text, int size, Color color, TextAnchor anchor)
        {
            var rt = new GameObject("Text").AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            var t = rt.gameObject.AddComponent<Text>();
            t.text = text;
            t.font = _font;
            t.fontSize = size;
            t.color = color;
            t.alignment = anchor;
            var le = rt.gameObject.AddComponent<LayoutElement>();
            le.preferredHeight = size * 1.35f;
            return t;
        }

        private Button AddButton(Transform parent, string text, int size, Action onClick)
        {
            var rt = new GameObject("Button").AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            var img = rt.gameObject.AddComponent<Image>();
            img.color = new Color(0.12f, 0.14f, 0.17f, 1f);
            var btn = rt.gameObject.AddComponent<Button>();
            var t = new GameObject("Label").AddComponent<RectTransform>();
            t.SetParent(rt, false);
            Stretch(t);
            var txt = t.gameObject.AddComponent<Text>();
            txt.text = text;
            txt.font = _font;
            txt.fontSize = size;
            txt.color = Color.white;
            txt.alignment = TextAnchor.MiddleCenter;
            btn.onClick.AddListener(() => onClick());
            rt.gameObject.AddComponent<LayoutElement>();
            return btn;
        }

        // ---------------- refresh ----------------
        private void RefreshGunList()
        {
            foreach (Transform child in _gunList)
                Destroy(child.gameObject);
            foreach (GunSpec g in GunData.Guns)
            {
                if (g.Class != _selClass) continue;
                GunSpec gg = g;
                var b = AddButton(_gunList,
                    gg.Name + " \"" + GunData.GetExtended(gg.Id).Alias + "\"\n" + GunData.StkLabel(gg),
                    15, () => OnGunPick(gg.Id));
                b.GetComponent<LayoutElement>().preferredHeight = 56f;
                if (gg.Id == _selGun)
                    b.GetComponentInChildren<Text>().color = Gold;
            }
        }

        private void RebuildPreview()
        {
            if (_previewRoot != null)
                Destroy(_previewRoot);
            GunSpec g = GunData.Get(_selGun);
            _previewRoot = GunFactory.BuildGun(g, false);
            _previewRoot.transform.SetParent(_rigRoot.transform, false);
            SetLayerRecursive(_previewRoot.transform, PreviewLayer);
            _previewRoot.transform.localPosition = new Vector3(0f, -0.05f, 0.1f);
            _previewCam.transform.localPosition = new Vector3(0.55f, 0.32f, 1.05f) + _previewRoot.transform.localPosition;
            _previewCam.transform.LookAt(_rigRoot.transform.TransformPoint(
                _previewRoot.transform.localPosition + new Vector3(0f, 0.05f, -0.15f)));
            _previewCam.Render();
            string skn = SkinName(_selGun, _selSkin);
            _previewName.text = GunData.FullName(g) + (skn == "" ? "" : "\n" + skn);
            _previewName.color = skn == "" ? Color.white : new Color(1f, 0.6f, 1f);
            RefreshStats();
            RefreshSkins();
        }

        private static void SetLayerRecursive(Transform t, int layer)
        {
            t.gameObject.layer = layer;
            foreach (Transform child in t)
                SetLayerRecursive(child, layer);
        }

        private void RefreshStats()
        {
            GunSpec g = GunData.Get(_selGun);
            GunExtended e = GunData.GetExtended(_selGun);
            _stkLabel.text = GunData.StkLabel(g);
            _statsLabel.text = string.Format("Damage {0} · RPM {1} · Mag {2}\nRange {3}m–{4}m · {5}\n{6}",
                (int)g.Damage, (int)g.Rpm, g.MagSize,
                (int)e.RangeNear, (int)g.Range,
                GunData.ClassDisplayName(g.Class), e.Role);
            SetBar("Damage", g.Damage / 150f, ((int)g.Damage).ToString());
            SetBar("RPM", g.Rpm / 1150f, ((int)g.Rpm).ToString());
            SetBar("Range", g.Range / 250f, ((int)g.Range).ToString());
            SetBar("Mag", g.MagSize / 100f, g.MagSize.ToString());
            SetBar("Recoil", Mathf.Clamp01(g.Recoil / 0.1f), g.Recoil.ToString("F3"));
        }

        private void SetBar(string name, float f, string val)
        {
            Image bar;
            Text txt;
            if (_statBars.TryGetValue(name, out bar)) bar.fillAmount = Mathf.Clamp01(f);
            if (_statVals.TryGetValue(name, out txt)) txt.text = val;
        }

        private int SkinCount(string gunId)
        {
            return SkinCountHook != null ? SkinCountHook(gunId) : 3;
        }

        private string SkinName(string gunId, int idx)
        {
            if (idx <= 0) return "";
            return SkinNameHook != null ? SkinNameHook(gunId, idx) : "MYTHIC SKIN " + idx;
        }

        private bool OwnsSkin(string gunId, int idx)
        {
            string skinId = gunId + "_skin_" + idx;
            if (SkinOwnershipHook != null) return SkinOwnershipHook(skinId);
            return NpWallet.OwnsSkin(skinId);
        }

        private void RefreshSkins()
        {
            foreach (Transform child in _skinBox)
                Destroy(child.gameObject);
            var b0 = AddButton(_skinBox, "STANDARD", 16, () => OnSkinPick(0));
            b0.GetComponent<LayoutElement>().preferredHeight = 44f;
            if (_selSkin == 0)
                b0.GetComponentInChildren<Text>().color = Gold;
            int n = SkinCount(_selGun);
            for (int i = 1; i <= n; i++)
            {
                int idx = i;
                bool owned = OwnsSkin(_selGun, idx);
                string nm = SkinName(_selGun, idx);
                var b = AddButton(_skinBox,
                    (owned ? "✦ " : "🔒 ") + nm + (owned ? "" : " — " + MythicPrice + " NP"),
                    16, () => OnSkinPick(idx));
                b.GetComponent<LayoutElement>().preferredHeight = 44f;
                var txt = b.GetComponentInChildren<Text>();
                Color c = owned
                    ? (SkinColorHook != null ? SkinColorHook(_selGun, idx) : new Color(0.85f, 0.5f, 1f))
                    : new Color(0.55f, 0.57f, 0.6f);
                if (_selSkin == idx) c = Gold;
                txt.color = c;
            }
        }

        private void RefreshAttachments()
        {
            foreach (Transform child in _attachBox)
                Destroy(child.gameObject);
            var descs = new List<string>();
            foreach (string slot in AttachSlots)
            {
                var row = new GameObject("Slot_" + slot).AddComponent<RectTransform>();
                row.SetParent(_attachBox, false);
                var hl = row.gameObject.AddComponent<HorizontalLayoutGroup>();
                hl.spacing = 4;
                hl.childForceExpandWidth = false;
                var lab = AddText(row.transform, slot.ToUpper(), 13,
                    new Color(0.75f, 0.75f, 0.78f), TextAnchor.MiddleLeft);
                lab.GetComponent<LayoutElement>().preferredWidth = 96f;
                string cur;
                _selAttach.TryGetValue(slot, out cur);
                var noneB = AddButton(row.transform, "—", 14, () => OnAttachPick(slot, ""));
                noneB.GetComponent<LayoutElement>().preferredWidth = 44f;
                if (cur == null)
                    noneB.GetComponentInChildren<Text>().color = Gold;
                foreach (AttachmentMod m in AttachmentData.Mods)
                {
                    if (m.Slot != slot) continue;
                    AttachmentMod mm = m;
                    var b = AddButton(row.transform, mm.Name, 12, () => OnAttachPick(slot, mm.Id));
                    var le = b.GetComponent<LayoutElement>();
                    le.flexibleWidth = 1f;
                    le.preferredHeight = 36f;
                    if (cur == mm.Id)
                    {
                        b.GetComponentInChildren<Text>().color = Gold;
                        descs.Add(mm.Name + ": " + AttachmentData.ModDescription(mm));
                    }
                }
            }
            _attachDescLabel.text = string.Join("\n", descs.ToArray());
        }

        // ---------------- events ----------------
        private void OnClassTab(GunClass c)
        {
            _selClass = c;
            _selSkin = 0;
            _selAttach.Clear();
            foreach (GunSpec g in GunData.Guns)
                if (g.Class == c) { _selGun = g.Id; break; }
            RefreshGunList();
            RebuildPreview();
            RefreshAttachments();
        }

        private void OnGunPick(string gid)
        {
            _selGun = gid;
            _selSkin = 0;
            RefreshGunList();
            RebuildPreview();
        }

        private void OnSkinPick(int idx)
        {
            if (idx > 0 && !OwnsSkin(_selGun, idx))
            {
                // Locked mythic — buy it in the NOVA STORE.
                if (OnSkinLocked != null)
                    OnSkinLocked(_selGun + "_skin_" + idx, MythicPrice);
                return;
            }
            _selSkin = idx;
            RebuildPreview();
        }

        private void OnAttachPick(string slot, string aid)
        {
            if (aid == "")
                _selAttach.Remove(slot);
            else
                _selAttach[slot] = aid;
            RefreshAttachments();
            RefreshStats();
        }

        private void OnDeployPressed()
        {
            var at = new List<string>();
            foreach (string slot in AttachSlots)
            {
                string v;
                if (_selAttach.TryGetValue(slot, out v)) at.Add(v);
            }
            if (OnDeploy != null) OnDeploy(_selGun, _selSkin, at.ToArray());
        }

        private void Update()
        {
            _previewT += Time.deltaTime;
            if (_previewRoot != null)
                _previewRoot.transform.rotation = Quaternion.Euler(0f, _previewT * 0.7f * Mathf.Rad2Deg, 0f);
            if (_previewCam != null && _previewRt != null)
                _previewCam.Render();
        }

        private void OnDestroy()
        {
            if (_previewRt != null)
            {
                Destroy(_previewRt);
                _previewRt = null;
            }
            if (_rigRoot != null)
                Destroy(_rigRoot);
        }
    }
}
