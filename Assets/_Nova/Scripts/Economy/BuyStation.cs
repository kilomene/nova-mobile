using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace NovaMobile.Economy
{
    /// <summary>
    /// NOVA buy-station kiosk — CODM-style in-world shop, ported from Godot
    /// scripts/buy_station.gd. Builds the kiosk procedurally (base, posts,
    /// canopy, counter, screen, floating "$", green light), opens a 20-item
    /// shop UI when the player is in range, and spends match cash (CashPurse).
    ///
    /// Effect hooks (other systems subscribe):
    ///   ItemPurchased(itemId)   — Player/Match applies the bought effect
    ///                             (heal, armor, ammo, scorestreaks, ...)
    ///   RedeployRequested       — Squads system drops a dog-tagged teammate
    ///                             back in ($2000 REDEPLOY item)
    ///   TankDropRequested(pos)  — Airdrop system flies a tank in ($10000)
    ///   StationRegistered/StationRemoved — minimap "$" icons (HUD system)
    ///
    /// Shop inventory mirrors the researched CODM Season 5 buy-station list.
    /// </summary>
    public struct ShopItem
    {
        public string Id;
        public string Cat;
        public string Name;
        public int Price;
        public string Desc;

        public ShopItem(string id, string cat, string name, int price, string desc)
        {
            Id = id; Cat = cat; Name = name; Price = price; Desc = desc;
        }
    }

    public class BuyStation : MonoBehaviour
    {
        public const float InteractRadius = 4f;

        public static readonly ShopItem[] ShopItems = {
            new ShopItem("frag_bundle", "EQUIPMENT", "Frag Grenades ×3",   400,  "+3 cookable frags"),
            new ShopItem("medkit",      "EQUIPMENT", "Field Medkit",        500,  "Full heal"),
            new ShopItem("gas_mask",    "EQUIPMENT", "Gas Mask",            3000, "30s collapse immunity"),
            new ShopItem("shield",      "EQUIPMENT", "Shield Turret",       2000, "Deployable cover wall"),
            new ShopItem("armor",       "PLATES",    "Armor Plate Bundle",  1500, "Full armor refill"),
            new ShopItem("carrier",     "PLATES",    "Juggernaut Carrier",  2500, "+50 max armor, this match"),
            new ShopItem("ammo",        "AMMO",      "Ammo Box",            2000, "+240 all reserve ammo"),
            new ShopItem("mystery",     "WEAPONS",   "Mystery Weapon",      4000, "Random tier-4/5 gun"),
            new ShopItem("heavy",       "WEAPONS",   "Thunderhead RP-7",    6000, "Guaranteed heavy launcher"),
            new ShopItem("uav",         "STREAKS",   "UAV Sweep",           4000, "Reveal all enemies 25s"),
            new ShopItem("strike",      "STREAKS",   "Cluster Strike",      3000, "Missile barrage"),
            new ShopItem("precision",   "STREAKS",   "Precision Airstrike", 3500, "One massive blast"),
            new ShopItem("sentry",      "STREAKS",   "Sentry Gun",          4000, "Auto-turret, 60s"),
            new ShopItem("bomber",      "STREAKS",   "'Jaka' Bomb Run",     8000, "B2 carpet-bombs aim line"),
            new ShopItem("modkit",      "GUN MODS",  "Gunsmith Mod Kit",    1500, "Random attachment fitted"),
            new ShopItem("tankdrop",    "TANK DROP", "Tank Drop Marker",     10000,"Tank airdropped nearby"),
            new ShopItem("repair",      "VEHICLE",   "Vehicle Repair",      1500, "Full repair (while driving)"),
            new ShopItem("paint",       "VEHICLE",   "Paint Job",           400,  "New paint (while driving)"),
            new ShopItem("revive",      "SURVIVAL",  "Self-Revive Kit",     4500, "Revive yourself once"),
            new ShopItem("redeploy",    "SURVIVAL",  "Redeploy Teammate",   2000, "Drop a tagged teammate back in"),
        };

        public static ShopItem[] Items() { return ShopItems; }

        public static int Price(string itemId)
        {
            for (int i = 0; i < ShopItems.Length; i++)
                if (ShopItems[i].Id == itemId) return ShopItems[i].Price;
            return 0;
        }

        public static ShopItem ItemById(string itemId)
        {
            for (int i = 0; i < ShopItems.Length; i++)
                if (ShopItems[i].Id == itemId) return ShopItems[i];
            return default(ShopItem);
        }

        public static bool CanAfford(int cash, string itemId)
        {
            return cash >= Price(itemId);
        }

        // ------------------------------------------------------------ hooks
        public static readonly List<BuyStation> Stations = new List<BuyStation>();
        public static event Action<BuyStation> StationRegistered;
        public static event Action<BuyStation> StationRemoved;
        public static event Action<string> ItemPurchased;      // itemId
        public static event Action RedeployRequested;          // squads hook
        public static event Action<Vector3> TankDropRequested; // airdrop hook

        // -------------------------------------------------------------- build
        private Transform _sign;
        private float _t;
        private Canvas _promptCanvas;
        private Button _promptBtn;
        private Canvas _shopCanvas;
        private Text _cashLabel;
        private Text _shopMsg;
        private Transform _shopList;
        private bool _shopOpen;
        private Font _font;

        private void Awake()
        {
            BuildKiosk();
            var col = gameObject.AddComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = InteractRadius;
            col.center = new Vector3(0, 1f, 0);
            var rb = gameObject.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.useGravity = false;
        }

        private void OnEnable()
        {
            Stations.Add(this);
            if (StationRegistered != null) StationRegistered(this);
        }

        private void OnDisable()
        {
            Stations.Remove(this);
            if (StationRemoved != null) StationRemoved(this);
        }

        private void AddBox(Vector3 size, Vector3 pos, Material mat)
        {
            var mi = GameObject.CreatePrimitive(PrimitiveType.Cube);
            mi.transform.SetParent(transform, false);
            mi.transform.localPosition = pos;
            mi.transform.localScale = size;
            var r = mi.GetComponent<Renderer>();
            r.sharedMaterial = mat;
        }

        private void BuildKiosk()
        {
            var dark = new Material(Shader.Find("Standard"));
            dark.color = new Color(0.12f, 0.13f, 0.15f);
            var accent = new Material(Shader.Find("Standard"));
            accent.color = new Color(0.1f, 0.5f, 0.2f);
            accent.EnableKeyword("_EMISSION");
            accent.SetColor("_EmissionColor", new Color(0.1f, 0.9f, 0.3f) * 1.2f);
            var screen = new Material(Shader.Find("Standard"));
            screen.color = new Color(0.02f, 0.05f, 0.08f);
            screen.EnableKeyword("_EMISSION");
            screen.SetColor("_EmissionColor", new Color(0.2f, 0.8f, 1.0f) * 0.9f);

            // Base + posts + canopy.
            AddBox(new Vector3(2.4f, 0.25f, 1.6f), new Vector3(0, 0.12f, 0), dark);
            AddBox(new Vector3(0.18f, 2.6f, 0.18f), new Vector3(-1.0f, 1.4f, -0.6f), dark);
            AddBox(new Vector3(0.18f, 2.6f, 0.18f), new Vector3(1.0f, 1.4f, -0.6f), dark);
            AddBox(new Vector3(0.18f, 2.6f, 0.18f), new Vector3(-1.0f, 1.4f, 0.6f), dark);
            AddBox(new Vector3(0.18f, 2.6f, 0.18f), new Vector3(1.0f, 1.4f, 0.6f), dark);
            AddBox(new Vector3(2.8f, 0.18f, 2.0f), new Vector3(0, 2.75f, 0), accent);
            // Counter + screen terminal.
            AddBox(new Vector3(2.0f, 1.0f, 0.7f), new Vector3(0, 0.75f, 0.3f), dark);
            AddBox(new Vector3(1.2f, 0.8f, 0.08f), new Vector3(0, 1.7f, -0.35f), screen);

            // Floating "$" sign (billboarded toward the camera).
            var signGo = new GameObject("DollarSign");
            signGo.transform.SetParent(transform, false);
            signGo.transform.localPosition = new Vector3(0, 3.6f, 0);
            var tm = signGo.AddComponent<TextMesh>();
            tm.text = "$";
            tm.fontSize = 128;
            tm.characterSize = 0.012f;
            tm.color = new Color(0.3f, 1.0f, 0.4f);
            tm.anchor = TextAnchor.MiddleCenter;
            tm.alignment = TextAlignment.Center;
            var f = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            if (f != null) tm.font = f;
            _sign = signGo.transform;

            // Green point light so it reads at a distance.
            var lightGo = new GameObject("KioskLight");
            lightGo.transform.SetParent(transform, false);
            lightGo.transform.localPosition = new Vector3(0, 3.0f, 0);
            var light = lightGo.AddComponent<Light>();
            light.type = LightType.Point;
            light.color = new Color(0.3f, 1.0f, 0.45f);
            light.intensity = 1.2f;
            light.range = 9f;
        }

        private void Update()
        {
            _t += Time.deltaTime;
            if (_sign != null)
            {
                _sign.localPosition = new Vector3(0, 3.6f + Mathf.Sin(_t * 2f) * 0.15f, 0);
                Camera cam = Camera.main;
                if (cam != null) _sign.rotation = cam.transform.rotation;
            }
        }

        // -------------------------------------------------------- interaction

        private void OnTriggerEnter(Collider other)
        {
            if (!other.CompareTag("Player")) return;
            ShowPrompt(true);
        }

        private void OnTriggerExit(Collider other)
        {
            if (!other.CompareTag("Player")) return;
            ShowPrompt(false);
            CloseShop();
        }

        private void ShowPrompt(bool show)
        {
            if (_promptCanvas == null) BuildPrompt();
            _promptCanvas.gameObject.SetActive(show);
        }

        private void BuildPrompt()
        {
            _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            var go = new GameObject("BuyPrompt");
            go.transform.SetParent(transform, false);
            _promptCanvas = go.AddComponent<Canvas>();
            _promptCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _promptCanvas.sortingOrder = 15;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            go.AddComponent<GraphicRaycaster>();

            var btnGo = new GameObject("PromptBtn");
            btnGo.transform.SetParent(go.transform, false);
            _promptBtn = btnGo.AddComponent<Button>();
            var rt = btnGo.GetComponent<RectTransform>();
            rt.anchorMin = new Vector2(0.5f, 0.02f);
            rt.anchorMax = new Vector2(0.5f, 0.02f);
            rt.sizeDelta = new Vector2(420, 90);
            var img = btnGo.AddComponent<Image>();
            img.color = new Color(0.05f, 0.25f, 0.1f, 0.95f);
            var txtGo = new GameObject("Text");
            txtGo.transform.SetParent(btnGo.transform, false);
            var txt = txtGo.AddComponent<Text>();
            txt.text = "$ BUY STATION — TAP TO SHOP";
            txt.font = _font;
            txt.fontSize = 26;
            txt.color = new Color(0.3f, 1.0f, 0.4f);
            txt.alignment = TextAnchor.MiddleCenter;
            var trt = txtGo.GetComponent<RectTransform>();
            trt.anchorMin = Vector2.zero; trt.anchorMax = Vector2.one;
            trt.offsetMin = Vector2.zero; trt.offsetMax = Vector2.zero;
            _promptBtn.onClick.AddListener(OpenShop);
            go.SetActive(false);
        }

        // ------------------------------------------------------------- shop UI

        private void OpenShop()
        {
            if (_shopCanvas == null) BuildShop();
            _shopOpen = true;
            _shopCanvas.gameObject.SetActive(true);
            RefreshShop();
        }

        private void CloseShop()
        {
            _shopOpen = false;
            if (_shopCanvas != null) _shopCanvas.gameObject.SetActive(false);
        }

        public bool IsShopOpen
        {
            get { return _shopOpen; }
        }

        private void BuildShop()
        {
            if (_font == null) _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            var go = new GameObject("ShopCanvas");
            go.transform.SetParent(transform, false);
            _shopCanvas = go.AddComponent<Canvas>();
            _shopCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _shopCanvas.sortingOrder = 21;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            go.AddComponent<GraphicRaycaster>();

            var bgGo = new GameObject("BG");
            bgGo.transform.SetParent(go.transform, false);
            var bgImg = bgGo.AddComponent<Image>();
           
            bgImg.color = new Color(0.02f, 0.03f, 0.04f, 0.96f);
            var brt = bgGo.GetComponent<RectTransform>();
            brt.anchorMin = Vector2.zero; brt.anchorMax = Vector2.one;
            brt.offsetMin = Vector2.zero; brt.offsetMax = Vector2.zero;

            var panelGo = new GameObject("Panel");
            panelGo.transform.SetParent(go.transform, false);
            var prt = panelGo.GetComponent<RectTransform>();
            prt.anchorMin = new Vector2(0.15f, 0.08f);
            prt.anchorMax = new Vector2(0.85f, 0.94f);
            prt.offsetMin = Vector2.zero; prt.offsetMax = Vector2.zero;
            var pimg = panelGo.AddComponent<Image>();
            pimg.color = new Color(0.06f, 0.08f, 0.1f, 1f);
            var pv = panelGo.AddComponent<VerticalLayoutGroup>();
            pv.spacing = 6;
            pv.padding = new RectOffset(16, 16, 12, 12);
            pv.childControlWidth = true;
            pv.childControlHeight = false;

            var title = new GameObject("Title").AddComponent<Text>();
            title.transform.SetParent(panelGo.transform, false);
            title.text = "$ BUY STATION";
            title.font = _font; title.fontSize = 34;
            title.color = new Color(0.3f, 1.0f, 0.4f);
            title.alignment = TextAnchor.MiddleCenter;

            _cashLabel = new GameObject("Cash").AddComponent<Text>();
            _cashLabel.transform.SetParent(panelGo.transform, false);
            _cashLabel.font = _font; _cashLabel.fontSize = 26;
            _cashLabel.color = new Color(1.0f, 0.9f, 0.4f);
            _cashLabel.alignment = TextAnchor.MiddleCenter;

            _shopMsg = new GameObject("Msg").AddComponent<Text>();
            _shopMsg.transform.SetParent(panelGo.transform, false);
            _shopMsg.font = _font; _shopMsg.fontSize = 18;
            _shopMsg.color = new Color(1.0f, 0.75f, 0.2f);
            _shopMsg.alignment = TextAnchor.MiddleCenter;

            var scrollGo = new GameObject("Scroll");
            scrollGo.transform.SetParent(panelGo.transform, false);
            var sle = scrollGo.AddComponent<LayoutElement>();
            sle.flexibleHeight = 1;
            var scroll = scrollGo.AddComponent<ScrollRect>();
            scroll.horizontal = false;

            var listGo = new GameObject("List");
            listGo.transform.SetParent(scrollGo.transform, false);
            var lrt = listGo.GetComponent<RectTransform>();
            lrt.anchorMin = new Vector2(0, 1); lrt.anchorMax = new Vector2(1, 1);
            lrt.pivot = new Vector2(0.5f, 1);
            var ll = listGo.AddComponent<VerticalLayoutGroup>();
            ll.spacing = 4;
            ll.childControlWidth = true;
            ll.childControlHeight = false;
            ll.childForceExpandWidth = true;
            var lsf = listGo.AddComponent<ContentSizeFitter>();
            lsf.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            _shopList = listGo.transform;
            scroll.content = lrt;

            var closeGo = new GameObject("CloseBtn");
            closeGo.transform.SetParent(panelGo.transform, false);
            var closeBtn = closeGo.AddComponent<Button>();
            var crt = closeGo.GetComponent<RectTransform>();
            crt.sizeDelta = new Vector2(300, 64);
            var cimg = closeGo.AddComponent<Image>();
            cimg.color = new Color(0.25f, 0.1f, 0.1f);
            var ctxtGo = new GameObject("Text");
            ctxtGo.transform.SetParent(closeGo.transform, false);
            var ctxt = ctxtGo.AddComponent<Text>();
            ctxt.text = "✕ CLOSE";
            ctxt.font = _font; ctxt.fontSize = 22;
            ctxt.color = Color.white;
            ctxt.alignment = TextAnchor.MiddleCenter;
            var ctrt = ctxtGo.GetComponent<RectTransform>();
            ctrt.anchorMin = Vector2.zero; ctrt.anchorMax = Vector2.one;
            ctrt.offsetMin = Vector2.zero; ctrt.offsetMax = Vector2.zero;
            closeBtn.onClick.AddListener(CloseShop);

            go.SetActive(false);
        }

        /// <summary>
        /// Shop list grouped into CATEGORY sections with Warzone-style headers:
        /// EQUIPMENT, PLATES, AMMO, WEAPONS, STREAKS, GUN MODS, TANK DROP,
        /// VEHICLE, SURVIVAL.
        /// </summary>
        private void RefreshShop()
        {
            if (!_shopOpen) return;
            for (int i = _shopList.childCount - 1; i >= 0; i--)
                Destroy(_shopList.GetChild(i).gameObject);
            _cashLabel.text = "CASH: $" + CashPurse.Balance;
            _shopMsg.text = "";
            string lastCat = null;
            for (int i = 0; i < BuyStation.ShopItems.Length; i++)
            {
                ShopItem item = BuyStation.ShopItems[i];
                if (item.Cat != lastCat)
                {
                    lastCat = item.Cat;
                    var hdr = new GameObject("Cat_" + item.Cat).AddComponent<Text>();
                    hdr.transform.SetParent(_shopList, false);
                    hdr.text = "—— " + item.Cat + " ——";
                    hdr.font = _font;
                    hdr.fontSize = 22;
                    hdr.fontStyle = FontStyle.Bold;
                    hdr.color = new Color(1.0f, 0.75f, 0.2f);
                    hdr.alignment = TextAnchor.MiddleLeft;
                    var hle = hdr.gameObject.AddComponent<LayoutElement>();
                    hle.preferredHeight = 40;
                }
                AddShopRow(item);
            }
        }

        private void AddShopRow(ShopItem item)
        {
            var rowGo = new GameObject("Row_" + item.Id);
            rowGo.transform.SetParent(_shopList, false);
            var rimg = rowGo.AddComponent<Image>();
            rimg.color = new Color(0.09f, 0.11f, 0.14f);
            var rle = rowGo.AddComponent<LayoutElement>();
            rle.preferredHeight = 64;
            var hl = rowGo.AddComponent<HorizontalLayoutGroup>();
            hl.spacing = 10;
            hl.padding = new RectOffset(10, 10, 6, 6);
            hl.childAlignment = TextAnchor.MiddleLeft;

            var nameGo = new GameObject("Name").AddComponent<Text>();
            nameGo.transform.SetParent(rowGo.transform, false);
            nameGo.text = item.Name + "\n<size=14><color=#A8ADB5>" + item.Desc + "</color></size>";
            nameGo.font = _font; nameGo.fontSize = 19;
            nameGo.color = Color.white;
            var nle = nameGo.gameObject.AddComponent<LayoutElement>();
            nle.flexibleWidth = 1;

            var btnGo = new GameObject("Buy");
            btnGo.transform.SetParent(rowGo.transform, false);
            var btn = btnGo.AddComponent<Button>();
            var brt = btnGo.GetComponent<RectTransform>();
            brt.sizeDelta = new Vector2(170, 52);
            var bimg = btnGo.AddComponent<Image>();
            bool afford = CashPurse.Balance >= item.Price;
            bimg.color = afford ? new Color(0.1f, 0.35f, 0.15f) : new Color(0.15f, 0.15f, 0.15f);
            var btxtGo = new GameObject("Text");
            btxtGo.transform.SetParent(btnGo.transform, false);
            var btxt = btxtGo.AddComponent<Text>();
            btxt.text = "$" + item.Price;
            btxt.font = _font; btxt.fontSize = 20;
            btxt.color = afford ? new Color(0.3f, 1.0f, 0.4f) : new Color(0.5f, 0.5f, 0.5f);
            btxt.alignment = TextAnchor.MiddleCenter;
            var btrt = btxtGo.GetComponent<RectTransform>();
            btrt.anchorMin = Vector2.zero; btrt.anchorMax = Vector2.one;
            btrt.offsetMin = Vector2.zero; btrt.offsetMax = Vector2.zero;
            btn.interactable = afford;
            string id = item.Id;
            btn.onClick.AddListener(() => OnBuyItem(id));
        }

        private void OnBuyItem(string itemId)
        {
            int price = BuyStation.Price(itemId);
            if (price <= 0) return;
            if (!CashPurse.Spend(price, "buy_station:" + itemId))
            {
                _shopMsg.text = "Insufficient cash.";
                RefreshShop();
                return;
            }
            // Route to gameplay systems.
            if (itemId == "redeploy")
            {
                if (BuyStation.RedeployRequested != null) BuyStation.RedeployRequested();
            }
            else if (itemId == "tankdrop")
            {
                if (BuyStation.TankDropRequested != null) BuyStation.TankDropRequested(transform.position);
            }
            if (BuyStation.ItemPurchased != null) BuyStation.ItemPurchased(itemId);
            _shopMsg.text = "✔ Purchased: " + BuyStation.ItemById(itemId).Name;
            RefreshShop();
        }
    }
}
