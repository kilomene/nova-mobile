using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using NovaMobile.Arsenal;
using NovaMobile.Classes;
using NovaMobile.Core;
using NovaMobile.Player;

namespace NovaMobile.Loot
{
    /// <summary>
    /// CODM-style loot UI (visual bible §8, overrides the Godot spec on visuals):
    /// - NEARBY panel (right side): slides in when loot is close, categorized
    ///   sections (Weapon / MAGAZINE / Medicine / Gear); tap an entry to pick up.
    /// - BOX panel: death-box contents in Weapon / Attachment / Medicine sections;
    ///   tap an entry to take it.
    /// - Pickup cards (bottom-right): item + rarity color on every collect.
    /// Ground loot keeps its 3D models with rarity color coding + beams.
    /// uGUI only; builds its own canvas so it works without the HUD canvas.
    /// </summary>
    public class LootUI : MonoBehaviour
    {
        public static LootUI Instance { get; private set; }

        /// <summary>Create the UI if the match didn't (idempotent).</summary>
        public static LootUI Ensure()
        {
            if (Instance != null) return Instance;
            var go = new GameObject("LootUI");
            DontDestroyOnLoad(go);
            return go.AddComponent<LootUI>();
        }

        // ---------------- BOX panel entries ----------------

        public struct BoxEntry
        {
            public string Section;      // "Weapon" | "Attachment" | "Medicine" | "MAGAZINE"
            public string Title;
            public string Desc;
            public Rarity Tier;
            public LootIconKind Icon;
            public Action Take;
        }

        // ---------------- config ----------------

        private const float NearbyRange = 6f;
        private const float RefreshInterval = 0.4f;
        private const int MaxEntries = 6;
        private const int MaxCards = 4;

        private static readonly string[] Sections = { "Weapon", "MAGAZINE", "Medicine", "Gear" };

        // ---------------- state ----------------

        private Canvas _canvas;
        private Font _font;

        // NEARBY
        private RectTransform _nearbyRoot;
        private RectTransform _nearbyList;
        private float _nearbyX;          // slide offset (0 = shown)
        private bool _nearbyShown;
        private float _refreshT;
        private int _nearbySig;
        private readonly List<NearbyEntry> _entries = new List<NearbyEntry>(16);
        private readonly List<GameObject> _entryGos = new List<GameObject>(16);
        private readonly List<ILootPickup> _lootScratch = new List<ILootPickup>(32);
        private GunPickup[] _gunScratch = new GunPickup[0];

        // BOX
        private RectTransform _boxRoot;
        private RectTransform _boxList;
        private Text _boxTitle;
        private readonly List<BoxEntry> _boxEntries = new List<BoxEntry>();
        private readonly List<GameObject> _boxGos = new List<GameObject>(12);

        // pickup cards
        private RectTransform _cardStack;
        private readonly List<CardSlot> _cards = new List<CardSlot>(MaxCards);

        private struct NearbyEntry
        {
            public string Section;
            public string Name;
            public string Sub;
            public Rarity Tier;
            public LootIconKind Icon;
            public float Dist;
            public LootPickup Loot;
            public GunPickup Gun;
        }

        private struct CardSlot
        {
            public GameObject Go;
            public CanvasGroup Cg;
            public Text Name;
            public Image Strip;
            public float Life;
        }

        // ---------------- lifecycle ----------------

        private void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
            _font = Resources.GetBuiltinResource(typeof(Font), "Arial.ttf") as Font;
            BuildCanvas();
            BuildNearby();
            BuildBox();
            BuildCards();
            LootPickup.OnPickupCard += ShowPickupCard;
            GunPickup.OnAnyPickedUp += (msg, tier) =>
                ShowPickupCard(msg, (Rarity)Mathf.Clamp(tier, 0, 6));
        }

        private void OnDestroy()
        {
            if (Instance == this) Instance = null;
            LootPickup.OnPickupCard -= ShowPickupCard;
        }

        private void Update()
        {
            _refreshT -= Time.deltaTime;
            if (_refreshT <= 0f)
            {
                _refreshT = RefreshInterval;
                RefreshNearby();
            }
            // slide animation (offset recomputed from live canvas width)
            float w = _canvas.GetComponent<RectTransform>().rect.width;
            float hidden = 0.25f * w + 40f;
            float target = _nearbyShown ? 0f : hidden;
            _nearbyX = Mathf.Lerp(_nearbyX, target, Mathf.Min(Time.deltaTime * 8f, 1f));
            Vector2 ap = _nearbyRoot.anchoredPosition;
            ap.x = _nearbyX;
            _nearbyRoot.anchoredPosition = ap;
            // pickup cards fade
            for (int i = _cards.Count - 1; i >= 0; i--)
            {
                var c = _cards[i];
                c.Life -= Time.deltaTime;
                c.Cg.alpha = Mathf.Clamp01(Mathf.Min(c.Life / 0.5f, (2.5f - c.Life) / 0.3f + 0.2f));
                _cards[i] = c;
                if (c.Life <= 0f)
                {
                    Destroy(c.Go);
                    _cards.RemoveAt(i);
                }
            }
        }

        // ---------------- canvas ----------------

        private void BuildCanvas()
        {
            var go = new GameObject("LootUICanvas");
            go.transform.SetParent(transform, false);
            _canvas = go.AddComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _canvas.sortingOrder = 20;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.matchWidthOrHeight = 0.5f;
            go.AddComponent<GraphicRaycaster>();
        }

        private RectTransform Panel(RectTransform parent, string name,
            float xMin, float yMin, float xMax, float yMax)
        {
            var go = new GameObject(name);
            var rt = go.AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = new Vector2(xMin, yMin);
            rt.anchorMax = new Vector2(xMax, yMax);
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;
            return rt;
        }

        private Image Bg(RectTransform parent, Color c)
        {
            var img = parent.gameObject.AddComponent<Image>();
            img.color = c;
            return img;
        }

        private Text Label(RectTransform parent, string text, int size, Color c, bool bold = false)
        {
            var go = new GameObject("T");
            var rt = go.AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
            var t = go.AddComponent<Text>();
            t.font = _font;
            t.text = text;
            t.fontSize = size;
            t.color = c;
            t.alignment = TextAnchor.MiddleLeft;
            if (bold) t.fontStyle = FontStyle.Bold;
            return t;
        }

        // ---------------- NEARBY panel ----------------

        private void BuildNearby()
        {
            _nearbyRoot = Panel(_canvas.transform as RectTransform, "Nearby",
                0.735f, 0.30f, 0.985f, 0.66f);
            Bg(_nearbyRoot, new Color(0.05f, 0.06f, 0.08f, 0.82f));

            // gold accent tab on the left edge
            var tab = Panel(_nearbyRoot, "Tab", 0f, 0f, 0.035f, 1f);
            Bg(tab, new Color(0.95f, 0.78f, 0.25f, 1f));

            var header = Panel(_nearbyRoot, "Header", 0.05f, 0.88f, 1f, 1f);
            Label(header, "NEARBY", 30, Color.white, true);

            var scroll = Panel(_nearbyRoot, "List", 0.05f, 0.02f, 1f, 0.88f);
            _nearbyList = scroll;
            _nearbyX = 2000f; // start off-screen; Update eases it in when loot appears
            _nearbyRoot.gameObject.SetActive(true);
        }

        private string SectionFor(LootPickup lp)
        {
            switch (lp.Item.Kind)
            {
                case LootKind.Ammo: return "MAGAZINE";
                case LootKind.Health:
                case LootKind.Armor:
                case LootKind.Shard: return "Medicine";
                default: return "Gear";
            }
        }

        private void RefreshNearby()
        {
            GameObject player = CombatHelper.FindPlayer();
            _entries.Clear();
            if (player != null)
            {
                Vector3 pp = player.transform.position;
                LootPickupRegistry.Query(pp, NearbyRange, _lootScratch);
                for (int i = 0; i < _lootScratch.Count && _entries.Count < MaxEntries; i++)
                {
                    var lp = _lootScratch[i] as LootPickup;
                    if (lp == null || !lp.gameObject.activeInHierarchy) continue;
                    float d = Vector3.Distance(lp.transform.position, pp);
                    _entries.Add(new NearbyEntry
                    {
                        Section = SectionFor(lp),
                        Name = lp.DisplayName(),
                        Sub = SubFor(lp),
                        Tier = lp.Item.Rarity,
                        Icon = LootIcons.ForKind(lp.Item.Kind),
                        Dist = d,
                        Loot = lp,
                    });
                }
                _gunScratch = GameObject.FindObjectsByType<GunPickup>(FindObjectsSortMode.None);
                for (int i = 0; i < _gunScratch.Length && _entries.Count < MaxEntries; i++)
                {
                    var gp = _gunScratch[i];
                    if (gp == null) continue;
                    float d = Vector3.Distance(gp.transform.position, pp);
                    if (d > NearbyRange) continue;
                    GunSpec g = GunData.Get(gp.gunId);
                    _entries.Add(new NearbyEntry
                    {
                        Section = "Weapon",
                        Name = GunData.FullName(g),
                        Sub = LootTable.RarityName((Rarity)Mathf.Clamp(gp.tier, 0, 6)) + " " + g.Class,
                        Tier = (Rarity)Mathf.Clamp(gp.tier, 0, 6),
                        Icon = gp.attachId != "" ? LootIconKind.Attachment : LootIconKind.Gun,
                        Dist = d,
                        Gun = gp,
                    });
                }
            }
            // sort: section order, then distance (insertion sort, tiny list)
            for (int i = 1; i < _entries.Count; i++)
            {
                var key = _entries[i];
                int j = i - 1;
                while (j >= 0 && CompareEntries(_entries[j], key) > 0)
                {
                    _entries[j + 1] = _entries[j];
                    j--;
                }
                _entries[j + 1] = key;
            }
            _nearbyShown = _entries.Count > 0;
            // Rebuild the list UI only when the visible set actually changes
            // (distance alone doesn't change what's shown).
            int sig = 17;
            for (int i = 0; i < _entries.Count; i++)
            {
                var se = _entries[i];
                sig = sig * 31 + se.Name.GetHashCode();
                sig = sig * 31 + se.Sub.GetHashCode();
                sig = sig * 31 + (int)se.Tier * 7 + (int)se.Icon;
            }
            if (sig != _nearbySig)
            {
                _nearbySig = sig;
                RebuildNearbyList();
            }
        }

        private static int SectionIndex(string s)
        {
            for (int i = 0; i < Sections.Length; i++)
                if (Sections[i] == s) return i;
            return 99;
        }

        private static int CompareEntries(NearbyEntry a, NearbyEntry b)
        {
            int sa = SectionIndex(a.Section), sb = SectionIndex(b.Section);
            if (sa != sb) return sa - sb;
            return a.Dist.CompareTo(b.Dist);
        }

        private static string SubFor(LootPickup lp)
        {
            switch (lp.Item.Kind)
            {
                case LootKind.Ammo: return lp.Item.Amount + " rounds";
                case LootKind.Health: return "Restores " + lp.Item.Amount + " HP";
                case LootKind.Armor:
                case LootKind.Shard: return "Armor Repair — increases HP by 50";
                case LootKind.Cash: return "Spend at buy stations";
                case LootKind.Frag: return "Throwable explosive";
                case LootKind.Smoke: return "Tactical cover";
                case LootKind.Scorestreak:
                    return lp.ScorestreakId == "uav" ? "Reveals enemies" : "Area bombardment";
                case LootKind.FuelCan: return "Refuels vehicles";
                case LootKind.Attachment: return "Gun attachment";
                default: return "";
            }
        }

        private void RebuildNearbyList()
        {
            for (int i = 0; i < _entryGos.Count; i++) Destroy(_entryGos[i]);
            _entryGos.Clear();

            float y = 1f;
            const float rowH = 0.13f;
            const float secH = 0.055f;
            string lastSec = null;
            foreach (var e in _entries)
            {
                if (e.Section != lastSec)
                {
                    lastSec = e.Section;
                    var sec = Panel(_nearbyList, "Sec", 0.02f, y - secH, 0.98f, y);
                    Label(sec, e.Section.ToUpperInvariant(), 20, new Color(0.75f, 0.78f, 0.82f), true);
                    y -= secH;
                }
                var entry = e; // capture
                var row = Panel(_nearbyList, "Row", 0.02f, y - rowH, 0.98f, y);
                var btn = row.gameObject.AddComponent<Button>();
                var bg = Bg(row, new Color(0.93f, 0.94f, 0.95f, 0.96f));
                btn.targetGraphic = bg;
                btn.onClick.AddListener(() => TakeNearby(entry));

                // rarity strip
                var strip = Panel(row, "Strip", 0f, 0f, 0.02f, 1f);
                Bg(strip, LootTable.RarityColor(entry.Tier));
                // icon
                var icon = Panel(row, "Icon", 0.04f, 0.12f, 0.20f, 0.88f);
                var img = icon.gameObject.AddComponent<Image>();
                img.sprite = Sprite.Create(LootIcons.Get(entry.Icon),
                    new Rect(0, 0, LootIcons.Size, LootIcons.Size), new Vector2(0.5f, 0.5f));
                // texts
                var nameR = Panel(row, "Name", 0.23f, 0.45f, 1f, 0.95f);
                Label(nameR, entry.Name, 22, new Color(0.1f, 0.11f, 0.13f), true);
                var subR = Panel(row, "Sub", 0.23f, 0.05f, 1f, 0.5f);
                Label(subR, entry.Sub, 18, new Color(0.45f, 0.47f, 0.5f));

                _entryGos.Add(row.gameObject);
                y -= rowH + 0.012f;
            }
        }

        private void TakeNearby(NearbyEntry e)
        {
            GameObject player = CombatHelper.FindPlayer();
            if (player == null) return;
            if (e.Loot != null)
            {
                var pc = player.GetComponentInParent<PlayerController>();
                if (pc == null) pc = player.GetComponent<PlayerController>();
                if (pc != null && Vector3.Distance(e.Loot.transform.position, player.transform.position) <= NearbyRange + 2f)
                    e.Loot.TakeBy(pc);
            }
            else if (e.Gun != null)
            {
                var carrier = player.GetComponentInParent<IGunCarrier>();
                if (carrier == null) carrier = player.GetComponent<IGunCarrier>();
                if (carrier != null && Vector3.Distance(e.Gun.transform.position, player.transform.position) <= NearbyRange + 2f)
                    e.Gun.TakeBy(carrier);
            }
        }

        // ---------------- BOX panel ----------------

        private void BuildBox()
        {
            _boxRoot = Panel(_canvas.transform as RectTransform, "Box",
                0.28f, 0.22f, 0.72f, 0.80f);
            Bg(_boxRoot, new Color(0.05f, 0.06f, 0.08f, 0.88f));

            var tab = Panel(_boxRoot, "Tab", 0f, 0f, 0.02f, 1f);
            Bg(tab, new Color(0.95f, 0.78f, 0.25f, 1f));

            var header = Panel(_boxRoot, "Header", 0.04f, 0.90f, 0.90f, 1f);
            _boxTitle = Label(header, "BOX", 32, Color.white, true);

            var closeR = Panel(_boxRoot, "Close", 0.90f, 0.90f, 1f, 1f);
            var closeBtn = closeR.gameObject.AddComponent<Button>();
            var closeBg = Bg(closeR, new Color(0.5f, 0.12f, 0.12f, 0.9f));
            closeBtn.targetGraphic = closeBg;
            Label(closeR, "X", 28, Color.white, true);
            closeBtn.onClick.AddListener(HideBox);

            var list = Panel(_boxRoot, "List", 0.04f, 0.03f, 0.98f, 0.90f);
            _boxList = list;
            _boxRoot.gameObject.SetActive(false);
        }

        public void ShowBox(string title, List<BoxEntry> entries)
        {
            _boxEntries.Clear();
            _boxEntries.AddRange(entries);
            _boxTitle.text = title.ToUpperInvariant();
            _boxRoot.gameObject.SetActive(true);
            RebuildBoxList();
        }

        public void HideBox()
        {
            _boxRoot.gameObject.SetActive(false);
            _boxEntries.Clear();
        }

        private void RebuildBoxList()
        {
            for (int i = 0; i < _boxGos.Count; i++) Destroy(_boxGos[i]);
            _boxGos.Clear();

            float y = 1f;
            const float rowH = 0.11f;
            const float secH = 0.06f;
            string lastSec = null;
            for (int idx = 0; idx < _boxEntries.Count; idx++)
            {
                var e = _boxEntries[idx];
                if (e.Section != lastSec)
                {
                    lastSec = e.Section;
                    var sec = Panel(_boxList, "Sec", 0f, y - secH, 1f, y);
                    Label(sec, e.Section, 22, new Color(0.75f, 0.78f, 0.82f), true);
                    y -= secH;
                }
                int captured = idx;
                var row = Panel(_boxList, "Row", 0f, y - rowH, 1f, y);
                var btn = row.gameObject.AddComponent<Button>();
                var bg = Bg(row, new Color(0.93f, 0.94f, 0.95f, 0.96f));
                btn.targetGraphic = bg;
                btn.onClick.AddListener(() => TakeBoxEntry(captured));

                var strip = Panel(row, "Strip", 0f, 0f, 0.015f, 1f);
                Bg(strip, LootTable.RarityColor(e.Tier));
                var icon = Panel(row, "Icon", 0.03f, 0.12f, 0.13f, 0.88f);
                var img = icon.gameObject.AddComponent<Image>();
                img.sprite = Sprite.Create(LootIcons.Get(e.Icon),
                    new Rect(0, 0, LootIcons.Size, LootIcons.Size), new Vector2(0.5f, 0.5f));
                var nameR = Panel(row, "Name", 0.16f, 0.45f, 1f, 0.95f);
                Label(nameR, e.Title, 24, new Color(0.1f, 0.11f, 0.13f), true);
                var subR = Panel(row, "Sub", 0.16f, 0.05f, 1f, 0.5f);
                Label(subR, e.Desc, 19, new Color(0.45f, 0.47f, 0.5f));

                _boxGos.Add(row.gameObject);
                y -= rowH + 0.012f;
            }
        }

        private void TakeBoxEntry(int idx)
        {
            if (idx < 0 || idx >= _boxEntries.Count) return;
            var e = _boxEntries[idx];
            _boxEntries.RemoveAt(idx);
            try { if (e.Take != null) e.Take(); } catch (Exception ex) { Debug.LogWarning("[LootUI] box take failed: " + ex.Message); }
            if (LootPickup.OnPickupCard != null) LootPickup.OnPickupCard(e.Title, e.Tier);
            if (_boxEntries.Count == 0) HideBox();
            else RebuildBoxList();
        }

        // ---------------- pickup cards ----------------

        private void BuildCards()
        {
            _cardStack = Panel(_canvas.transform as RectTransform, "Cards",
                0.76f, 0.02f, 0.995f, 0.26f);
        }

        public void ShowPickupCard(string name, Rarity rarity)
        {
            if (_cards.Count >= MaxCards)
            {
                var oldest = _cards[0];
                Destroy(oldest.Go);
                _cards.RemoveAt(0);
            }
            var go = new GameObject("Card");
            var rt = go.AddComponent<RectTransform>();
            rt.SetParent(_cardStack, false);
            // stacked bottom-up by LayoutCards
            rt.anchorMin = new Vector2(0f, 0f);
            rt.anchorMax = new Vector2(1f, 0f);
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;

            var bg = go.AddComponent<Image>();
            bg.color = new Color(0.05f, 0.06f, 0.08f, 0.85f);
            var strip = new GameObject("Strip").AddComponent<RectTransform>();
            strip.SetParent(rt, false);
            strip.anchorMin = new Vector2(0f, 0f); strip.anchorMax = new Vector2(0.03f, 1f);
            strip.offsetMin = Vector2.zero; strip.offsetMax = Vector2.zero;
            var stripImg = strip.gameObject.AddComponent<Image>();
            stripImg.color = LootTable.RarityColor(rarity);

            var nameGo = new GameObject("Name");
            var nrt = nameGo.AddComponent<RectTransform>();
            nrt.SetParent(rt, false);
            nrt.anchorMin = new Vector2(0.05f, 0f); nrt.anchorMax = new Vector2(1f, 1f);
            nrt.offsetMin = Vector2.zero; nrt.offsetMax = Vector2.zero;
            var t = nameGo.AddComponent<Text>();
            t.font = _font;
            t.text = name.ToUpperInvariant();
            t.fontSize = 22;
            t.color = Color.white;
            t.fontStyle = FontStyle.Bold;
            t.alignment = TextAnchor.MiddleLeft;

            var cg = go.AddComponent<CanvasGroup>();
            cg.alpha = 0f;
            _cards.Add(new CardSlot { Go = go, Cg = cg, Name = t, Strip = stripImg, Life = 2.5f });
            LayoutCards();
        }

        private void LayoutCards()
        {
            // bottom card at the bottom of the stack area
            for (int i = 0; i < _cards.Count; i++)
            {
                var c = _cards[i];
                var rt = c.Go.GetComponent<RectTransform>();
                float y0 = i * 0.055f;
                rt.offsetMin = new Vector2(0f, y0 * 1080f);
                rt.offsetMax = new Vector2(0f, (y0 + 0.05f) * 1080f);
            }
        }
    }
}
