using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace NovaMobile.Economy
{
    /// <summary>
    /// NOVA in-game store — CODM-style uGUI, built fully from code.
    /// Tabs: Featured, Lucky Draws, Weapon Skins, Bundles, Characters (locked),
    /// Battle Pass (locked), Buy NOVA Points.
    /// Dark military visual language, orange accents, card-based items.
    /// Mythic skins bought here unlock in the gunsmith (NpWallet ownership).
    /// Ported from Godot scripts/store.gd.
    /// </summary>
    public class StoreUI : MonoBehaviour
    {
        public event Action Closed;

        // ------------------------------------------------------------ palette
        private static readonly Color Orange = new Color(1.0f, 0.75f, 0.2f);
        private static readonly Color Bg = new Color(0.03f, 0.04f, 0.06f, 0.97f);
        private static readonly Color Card = new Color(0.07f, 0.09f, 0.12f);
        private static readonly Color Muted = new Color(0.65f, 0.68f, 0.72f);
        private static readonly Color Green = new Color(0.35f, 0.9f, 0.45f);
        private static readonly Color Gold = new Color(1.0f, 0.9f, 0.4f);
        private static readonly Color IceBlue = new Color(0.6f, 0.85f, 1.0f);
        private static readonly Color MythicPink = new Color(1.0f, 0.6f, 1.0f);

        private Canvas _canvas;
        private Payments _payments;
        private Text _npLabel;
        private Text _msg;
        private Transform _contentBox;
        private string _selTab = "featured";
        private string _selDraw = "draw_dragonfire";
        private System.Random _rng = new System.Random();

        // Draw countdown expiries: set once per app session from EndsInDays
        // (mirrors Godot, which stamped them at store open).
        private static readonly Dictionary<string, long> _drawExpiry = new Dictionary<string, long>();

        // Live countdown title labels (drawId -> title text), ticked each second.
        private readonly List<CountdownBind> _countdowns = new List<CountdownBind>();
        private float _tick;
        private Font _font;

        private struct CountdownBind
        {
            public string DrawId;
            public Text Title;
        }

        // ---------------------------------------------------------------- API

        /// <summary>Show the store (builds the canvas on first call).</summary>
        public void Show()
        {
            if (_canvas == null) Build();
            _canvas.gameObject.SetActive(true);
            SelectTab("featured");
        }

        public void Hide()
        {
            if (_canvas != null) _canvas.gameObject.SetActive(false);
        }

        public void OpenTab(string tabId)
        {
            if (_canvas == null) Build();
            _canvas.gameObject.SetActive(true);
            SelectTab(tabId);
        }

        // --------------------------------------------------------------- build

        private void Build()
        {
            _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            for (int i = 0; i < StoreData.Draws.Length; i++)
            {
                DrawDef d = StoreData.Draws[i];
                if (!_drawExpiry.ContainsKey(d.Id))
                    _drawExpiry[d.Id] = now + (long)d.EndsInDays * 86400L;
            }

            var go = new GameObject("StoreCanvas");
            go.transform.SetParent(transform, false);
            _canvas = go.AddComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _canvas.sortingOrder = 20;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.matchWidthOrHeight = 0.5f;
            go.AddComponent<GraphicRaycaster>();

            var bg = new GameObject("BG");
            bg.transform.SetParent(go.transform, false);
            bg.AddComponent<Image>().color = Bg;
            Stretch(bg.GetComponent<RectTransform>());

            var margin = new GameObject("Margin");
            margin.transform.SetParent(go.transform, false);
            var mrt = margin.GetComponent<RectTransform>();
            Stretch(mrt);
            mrt.offsetMin = new Vector2(20, 12);
            mrt.offsetMax = new Vector2(-20, -12);

            var vb = new GameObject("VBox");
            vb.transform.SetParent(margin.transform, false);
            var vl = vb.AddComponent<VerticalLayoutGroup>();
            vl.spacing = 8;
            vl.childControlWidth = true;
            vl.childControlHeight = false;
            Stretch(vb.GetComponent<RectTransform>());

            BuildTopBar(vb.transform);
            BuildTabs(vb.transform);

            _msg = MakeLabel(vb.transform, "", 16, Orange);
            _msg.alignment = TextAnchor.MiddleCenter;

            var scrollGo = new GameObject("Scroll");
            scrollGo.transform.SetParent(vb.transform, false);
            var sle = scrollGo.AddComponent<LayoutElement>();
            sle.flexibleHeight = 1;
            var scroll = scrollGo.AddComponent<ScrollRect>();
            scroll.horizontal = false;

            var contentGo = new GameObject("Content");
            contentGo.transform.SetParent(scrollGo.transform, false);
            var crt = contentGo.GetComponent<RectTransform>();
            crt.anchorMin = new Vector2(0, 1); crt.anchorMax = new Vector2(1, 1);
            crt.pivot = new Vector2(0.5f, 1);
            var cl = contentGo.AddComponent<VerticalLayoutGroup>();
            cl.spacing = 10;
            cl.childControlWidth = true;
            cl.childControlHeight = false;
            cl.childForceExpandWidth = true;
            var csf = contentGo.AddComponent<ContentSizeFitter>();
            csf.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            _contentBox = contentGo.transform;
            scroll.content = crt;

            _payments = gameObject.AddComponent<Payments>();
            _payments.Completed += OnPurchaseCompleted;
            _payments.Failed += OnPurchaseFailed;

            RefreshTab();
        }

        private void BuildTopBar(Transform parent)
        {
            var hb = new GameObject("TopBar");
            hb.transform.SetParent(parent, false);
            var hl = hb.AddComponent<HorizontalLayoutGroup>();
            hl.spacing = 12;
            hl.childAlignment = TextAnchor.MiddleLeft;

            var title = MakeLabel(hb.transform, "NOVA STORE", 40, Orange);
            var tle = title.gameObject.AddComponent<LayoutElement>();
            tle.flexibleWidth = 1;

            _npLabel = MakeLabel(hb.transform, "", 24, Gold);
            var npb = MakeButton(hb.transform, "+ NP", 18, () => SelectTab("np"), 110, 48);
            npb.GetComponentInChildren<Text>().color = Orange;
            MakeButton(hb.transform, "✕ CLOSE", 18, () =>
            {
                Hide();
                if (Closed != null) Closed();
            }, 140, 48);
            RefreshBalance();
        }

        private void BuildTabs(Transform parent)
        {
            var row = new GameObject("Tabs");
            row.transform.SetParent(parent, false);
            var hl = row.AddComponent<HorizontalLayoutGroup>();
            hl.spacing = 6;
            hl.childControlWidth = true;
            for (int i = 0; i < StoreData.Tabs.Length; i++)
            {
                StoreTab t = StoreData.Tabs[i];
                var b = MakeButton(row.transform, t.Name, 15, null, 0, 46);
                var le = b.gameObject.AddComponent<LayoutElement>();
                le.flexibleWidth = 1;
                if (t.Locked)
                {
                    b.interactable = false;
                    b.GetComponentInChildren<Text>().color = Muted;
                    var tip = b.gameObject.AddComponent<TooltipShim>();
                    tip.Tip = t.LockNote;
                }
                else
                {
                    string tid = t.Id;
                    b.onClick.AddListener(() => SelectTab(tid));
                }
            }
        }

        private void SelectTab(string tid)
        {
            _selTab = tid;
            if (_msg != null) _msg.text = "";
            RefreshTab();
        }

        private void RefreshBalance()
        {
            if (_npLabel != null) _npLabel.text = "◈ " + NpWallet.Balance + " NP";
        }

        private void RefreshTab()
        {
            if (_contentBox == null) return;
            _countdowns.Clear();
            for (int i = _contentBox.childCount - 1; i >= 0; i--)
                Destroy(_contentBox.GetChild(i).gameObject);
            RefreshBalance();
            switch (_selTab)
            {
                case "featured": TabFeatured(); break;
                case "draws": TabDraws(); break;
                case "skins": TabSkins(); break;
                case "bundles": TabBundles(); break;
                case "np": TabNp(); break;
                default: TabLocked(); break;
            }
        }

        private void Update()
        {
            if (_canvas == null || !_canvas.gameObject.activeInHierarchy) return;
            _tick += Time.deltaTime;
            if (_tick < 1f) return;
            _tick = 0f;
            if (_selTab != "featured" && _selTab != "draws") return;
            for (int i = 0; i < _countdowns.Count; i++)
            {
                CountdownBind cb = _countdowns[i];
                if (cb.Title == null) continue;
                string nm = cb.DrawId;
                for (int d = 0; d < StoreData.Draws.Length; d++)
                    if (StoreData.Draws[d].Id == cb.DrawId) nm = StoreData.Draws[d].Name;
                cb.Title.text = nm + "  ·  " + Countdown(cb.DrawId);
            }
        }

        private string Countdown(string drawId)
        {
            long left = 0;
            long exp;
            if (_drawExpiry.TryGetValue(drawId, out exp))
                left = Math.Max(0L, exp - DateTimeOffset.UtcNow.ToUnixTimeSeconds());
            long d = left / 86400, h = (left % 86400) / 3600, m = (left % 3600) / 60;
            return string.Format("Ends in {0}d {1:00}h {2:00}m", d, h, m);
        }

        // --------------------------------------------------------------- helpers

        private static void Stretch(RectTransform rt)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;
        }

        private Text MakeLabel(Transform parent, string text, int size, Color color)
        {
            var go = new GameObject("Label");
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.text = text;
            t.font = _font;
            t.fontSize = size;
            t.color = color;
            return t;
        }

        private Button MakeButton(Transform parent, string text, int size, Action onClick, float w, float h)
        {
            var go = new GameObject("Button");
            go.transform.SetParent(parent, false);
            var btn = go.AddComponent<Button>();
            var img = go.AddComponent<Image>();
            img.color = new Color(0.12f, 0.14f, 0.17f);
            var le = go.AddComponent<LayoutElement>();
            le.preferredWidth = w;
            le.preferredHeight = h;
            if (w <= 0) le.flexibleWidth = 1;
            var tgo = new GameObject("Text");
            tgo.transform.SetParent(go.transform, false);
            var t = tgo.AddComponent<Text>();
            t.text = text;
            t.font = _font;
            t.fontSize = size;
            t.color = Color.white;
            t.alignment = TextAnchor.MiddleCenter;
            Stretch(tgo.GetComponent<RectTransform>());
            if (onClick != null) btn.onClick.AddListener(() => onClick());
            return btn;
        }

        /// <summary>Styled card; returns the content holder.</summary>
        private Transform MakeCard(string title, Color titleColor)
        {
            var p = new GameObject("Card");
            p.transform.SetParent(_contentBox, false);
            var img = p.AddComponent<Image>();
            img.color = Card;
            var vb = new GameObject("VBox");
            vb.transform.SetParent(p.transform, false);
            var vl = vb.AddComponent<VerticalLayoutGroup>();
            vl.spacing = 6;
            vl.padding = new RectOffset(14, 14, 10, 10);
            Stretch(vb.GetComponent<RectTransform>());
            var t = MakeLabel(vb.transform, title, 20, titleColor);
            RegisterCountdown(title, t);
            return vb.transform;
        }

        private void RegisterCountdown(string title, Text titleLabel)
        {
            for (int i = 0; i < StoreData.Draws.Length; i++)
            {
                if (title.StartsWith(StoreData.Draws[i].Name))
                {
                    _countdowns.Add(new CountdownBind { DrawId = StoreData.Draws[i].Id, Title = titleLabel });
                    return;
                }
            }
        }

        private Text Note(Transform parent, string text, int size, Color color)
        {
            var l = MakeLabel(parent, text, size, color);
            return l;
        }

        // --------------------------------------------------------------- featured

        private void TabFeatured()
        {
            DrawDef d = StoreData.Draws[0];
            var vb = MakeCard(d.Name + "  ·  " + Countdown(d.Id), Orange);
            Note(vb, "Top prize: " + StoreData.ItemLabel(StoreData.DrawTopPrize(d.Id)), 16, MythicPink);
            Note(vb, "10 spins · escalating costs · owned items removed from pool · 10th spin GUARANTEES the mythic", 14, Muted);
            string did = d.Id;
            MakeButton(vb, "VIEW DRAW →", 17, () =>
            {
                _selDraw = did;
                SelectTab("draws");
            }, 220, 48);
            for (int i = 0; i < StoreData.Bundles.Length; i++)
            {
                BundleDef bu = StoreData.Bundles[i];
                bool owned = NpWallet.OwnsBundle(bu.Id);
                var cb = MakeCard(bu.Name + (owned ? "  ·  OWNED" : ""), IceBlue);
                Note(cb, bu.Desc, 14, Muted);
                if (!owned)
                {
                    string bid = bu.Id;
                    MakeButton(cb, "BUY — " + bu.Price + " NP", 16, () => OnBuyBundle(bid), 220, 44);
                }
            }
        }

        // ------------------------------------------------------------------ draws

        private void TabDraws()
        {
            var sel = new GameObject("DrawSel");
            sel.transform.SetParent(_contentBox, false);
            var hl = sel.AddComponent<HorizontalLayoutGroup>();
            hl.spacing = 8;
            for (int i = 0; i < StoreData.Draws.Length; i++)
            {
                DrawDef dd = StoreData.Draws[i];
                string id = dd.Id;
                var b = MakeButton(sel.transform, dd.Name, 15, () =>
                {
                    _selDraw = id;
                    RefreshTab();
                }, 0, 44);
                if (id == _selDraw) b.GetComponentInChildren<Text>().color = Orange;
            }

            DrawDef draw = StoreData.DrawById(_selDraw);
            if (draw.Id == null) return;
            NpWallet.DrawState st = NpWallet.GetDrawState(_selDraw);

            var vb = MakeCard(draw.Name + "  ·  " + Countdown(_selDraw), Orange);
            Note(vb, "Top prize: " + StoreData.ItemLabel(StoreData.DrawTopPrize(_selDraw)), 16, MythicPink);
            Note(vb, "Odds per spin — Mythic 3% · Epic 12% · Rare 30% · Common 55% (re-weighted over remaining pool)", 14, Muted);

            // 10-slot grid.
            var gridGo = new GameObject("Grid");
            gridGo.transform.SetParent(vb, false);
            var grid = gridGo.AddComponent<GridLayoutGroup>();
            grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            grid.constraintCount = 5;
            grid.spacing = new Vector2(6, 6);
            grid.cellSize = new Vector2(300, 64);
            grid.childAlignment = TextAnchor.UpperLeft;
            for (int i = 0; i < draw.Items.Length; i++)
            {
                DrawItem it = draw.Items[i];
                var cell = new GameObject("Slot" + i);
                cell.transform.SetParent(gridGo.transform, false);
                var cimg = cell.AddComponent<Image>();
                cimg.color = new Color(0.09f, 0.11f, 0.14f);
                var lab = MakeLabel(cell.transform, "", 14, Color.white);
                lab.alignment = TextAnchor.MiddleCenter;
                Stretch(lab.GetComponent<RectTransform>());
                if (st.Won.Contains(i))
                {
                    lab.text = "✔ " + StoreData.ItemLabel(it);
                    lab.color = Green;
                }
                else
                {
                    lab.text = StoreData.ItemLabel(it);
                    lab.color = StoreData.RarityColor(it.Kind);
                }
            }

            int spinsUsed = st.Won.Count;
            if (spinsUsed >= 10)
            {
                Note(vb, "DRAW COMPLETE — all 10 items claimed.", 16, Green);
            }
            else
            {
                int cost = LuckyDraw.SpinCost(spinsUsed);
                int n = spinsUsed + 1;
                var sb = MakeButton(vb, "SPIN (" + n + ") — " + cost + " NP", 19, OnSpin, 280, 56);
                bool afford = NpWallet.Balance >= cost;
                sb.interactable = afford;
                sb.GetComponentInChildren<Text>().color = afford ? Orange : Muted;
                if (!afford)
                {
                    var tip = sb.gameObject.AddComponent<TooltipShim>();
                    tip.Tip = "Insufficient NP — buy more in the BUY NOVA POINTS tab";
                }
                Note(vb, "Full draw (all 10 spins) = " + StoreData.DrawFullCost()
                    + " NP — 10th spin guarantees the mythic.", 14, Muted);
            }
        }

        private void OnSpin()
        {
            LuckyDraw.SpinResult r = LuckyDraw.Spin(_selDraw, _rng);
            if (!r.Ok)
            {
                _msg.text = "Spin failed: " + r.Reason;
                return;
            }
            _msg.text = (r.Guaranteed ? "✦ GUARANTEED MYTHIC! " : "Won: ") + r.Label;
            RefreshTab();
        }

        // ------------------------------------------------------------------ skins

        private void TabSkins()
        {
            Note(_contentBox, "Direct-buy mythic skins — " + StoreData.MythicPrice
                + " NP each. Owned skins unlock in the gunsmith.", 15, Orange);
            var gridGo = new GameObject("Grid");
            gridGo.transform.SetParent(_contentBox, false);
            var grid = gridGo.AddComponent<GridLayoutGroup>();
            grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            grid.constraintCount = 2;
            grid.spacing = new Vector2(8, 8);
            grid.cellSize = new Vector2(700, 150);
            for (int i = 0; i < StoreData.SkinOffers.Length; i++)
            {
                SkinOffer offer = StoreData.SkinOffers[i];
                string gun = offer.Gun;
                int idx = offer.SkinIdx;
                var cell = new GameObject("Offer_" + gun + idx);
                cell.transform.SetParent(gridGo.transform, false);
                var cimg = cell.AddComponent<Image>();
                cimg.color = Card;
                var vb = new GameObject("VBox");
                vb.transform.SetParent(cell.transform, false);
                var vl = vb.AddComponent<VerticalLayoutGroup>();
                vl.spacing = 4;
                vl.padding = new RectOffset(10, 10, 8, 8);
                Stretch(vb.GetComponent<RectTransform>());
                MakeLabel(vb.transform, "✦ " + StoreData.MythicSkinLabel(gun, idx), 17, MythicPink);
                string gunName = gun.ToUpperInvariant();
                if (NovaMobile.Arsenal.GunData.Has(gun))
                    gunName = NovaMobile.Arsenal.GunData.Get(gun).Name;
                MakeLabel(vb.transform, gunName + " · MYTHIC", 13, Muted);
                bool owned = NpWallet.OwnsSkin(NpWallet.SkinId(gun, idx));
                if (owned)
                {
                    MakeLabel(vb.transform, "✔ OWNED — equip in gunsmith", 14, Green);
                }
                else
                {
                    var b = MakeButton(vb.transform, "BUY — " + StoreData.MythicPrice + " NP",
                        15, () => OnBuySkin(gun, idx), 200, 44);
                    bool afford = NpWallet.Balance >= StoreData.MythicPrice;
                    b.interactable = afford;
                    b.GetComponentInChildren<Text>().color = afford ? Orange : Muted;
                }
            }
        }

        private void OnBuySkin(string gun, int idx)
        {
            if (NpWallet.BuySkin(gun, idx))
                _msg.text = "✔ Unlocked: " + StoreData.MythicSkinLabel(gun, idx);
            else
                _msg.text = "Could not buy — insufficient NP or already owned.";
            RefreshTab();
        }

        // ---------------------------------------------------------------- bundles

        private void TabBundles()
        {
            for (int i = 0; i < StoreData.Bundles.Length; i++)
            {
                BundleDef bu = StoreData.Bundles[i];
                bool owned = NpWallet.OwnsBundle(bu.Id);
                var vb = MakeCard(bu.Name + (owned ? "  ·  OWNED" : ""), IceBlue);
                Note(vb, "Includes mythic skin: " + StoreData.MythicSkinLabel(bu.Gun, bu.SkinIdx), 15, MythicPink);
                Note(vb, bu.Desc, 14, Muted);
                if (owned)
                {
                    Note(vb, "✔ OWNED — skin equippable in gunsmith", 14, Green);
                }
                else
                {
                    string bid = bu.Id;
                    int price = bu.Price;
                    var b = MakeButton(vb, "BUY BUNDLE — " + price + " NP", 17,
                        () => OnBuyBundle(bid), 260, 48);
                    bool afford = NpWallet.Balance >= price;
                    b.interactable = afford;
                    b.GetComponentInChildren<Text>().color = afford ? Orange : Muted;
                }
            }
        }

        private void OnBuyBundle(string bid)
        {
            if (NpWallet.BuyBundle(bid))
                _msg.text = "✔ Bundle unlocked: " + StoreData.BundleById(bid).Name;
            else
                _msg.text = "Could not buy bundle — insufficient NP or already owned.";
            RefreshTab();
        }

        // --------------------------------------------------------------------- np

        private void TabNp()
        {
            Note(_contentBox, "NOVA Points are bought with REAL money via Flutterwave (secure checkout). NP buys mythic skins, draws and bundles.", 15, Orange);
            if (_payments != null && _payments.IsTestMode)
            {
                Note(_contentBox, "⚠ TEST MODE — no real money moves. Live mode requires the payments backend hosted with its secret key (see Payments).", 14, new Color(1.0f, 0.55f, 0.3f));
            }
            var gridGo = new GameObject("Grid");
            gridGo.transform.SetParent(_contentBox, false);
            var grid = gridGo.AddComponent<GridLayoutGroup>();
            grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            grid.constraintCount = 2;
            grid.spacing = new Vector2(8, 8);
            grid.cellSize = new Vector2(700, 230);
            for (int i = 0; i < StoreData.NpPacks.Length; i++)
            {
                NpPack pack = StoreData.NpPacks[i];
                var cell = new GameObject("Pack_" + pack.Id);
                cell.transform.SetParent(gridGo.transform, false);
                var cimg = cell.AddComponent<Image>();
                cimg.color = Card;
                var vb = new GameObject("VBox");
                vb.transform.SetParent(cell.transform, false);
                var vl = vb.AddComponent<VerticalLayoutGroup>();
                vl.spacing = 4;
                vl.padding = new RectOffset(12, 12, 10, 10);
                Stretch(vb.GetComponent<RectTransform>());
                MakeLabel(vb.transform, "◈ " + pack.Np + " NP", 24, Gold);
                MakeLabel(vb.transform, pack.Name, 14, Muted);
                if (pack.Bonus != "")
                    MakeLabel(vb.transform, pack.Bonus, 14, Green);
                MakeLabel(vb.transform, "₦" + FmtNaira(pack.Ngn) + "  ·  $" + pack.Usd.ToString("0.00"), 18, Color.white);
                string pid = pack.Id;
                MakeButton(vb.transform, "BUY", 17, () => OnBuyNp(pid), 180, 46);
            }
        }

        private static string FmtNaira(int n)
        {
            string s = n.ToString();
            string outp = "";
            while (s.Length > 3)
            {
                outp = "," + s.Substring(s.Length - 3) + outp;
                s = s.Substring(0, s.Length - 3);
            }
            return s + outp;
        }

        private void OnBuyNp(string pid)
        {
            _msg.text = "Opening secure checkout…";
            _payments.Purchase(pid);
        }

        private void OnPurchaseCompleted(string packId, int np, string txRef)
        {
            _msg.text = "✔ +" + np + " NP added! (receipt " + txRef + ")";
            RefreshTab();
        }

        private void OnPurchaseFailed(string packId, string reason)
        {
            _msg.text = "Purchase failed: " + reason + " — no charge made.";
            RefreshTab();
        }

        // ----------------------------------------------------------------- locked

        private void TabLocked()
        {
            string name = _selTab;
            string note = "COMING SOON";
            for (int i = 0; i < StoreData.Tabs.Length; i++)
            {
                if (StoreData.Tabs[i].Id == _selTab)
                {
                    name = StoreData.Tabs[i].Name;
                    note = StoreData.Tabs[i].LockNote;
                }
            }
            var vb = MakeCard(name, Muted);
            var l = MakeLabel(vb, "🔒\n" + note, 26, Muted);
            l.alignment = TextAnchor.MiddleCenter;
        }
    }

    /// <summary>
    /// Minimal tooltip stand-in (Unity has no built-in tooltip for uGUI at
    /// runtime): stores the tip text on disabled buttons. A HUD tooltip
    /// system can read these later.
    /// </summary>
    public class TooltipShim : MonoBehaviour
    {
        public string Tip = "";
    }
}
