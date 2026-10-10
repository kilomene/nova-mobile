using UnityEngine;

namespace NovaMobile.Economy
{
    /// <summary>
    /// NOVA store catalog — static data tables ported faithfully from Godot
    /// scripts/store_defs.gd. Data-only: tabs, NP packs, direct-buy mythic skin
    /// offers, bundles, and the 3 lucky draws.
    ///
    /// Contract (CONVENTIONS.md): StoreData.NpPacks / .Draws / .Bundles with the
    /// NpPack { Id, Np, Ngn, Usd } shape. Name/Bonus are additive display fields.
    /// </summary>
    public struct NpPack
    {
        public string Id;
        public int Np;
        public int Ngn;
        public float Usd;
        public string Name;    // display name ("Fortune of Points")
        public string Bonus;   // bonus ribbon text ("" when none)

        public NpPack(string id, int np, int ngn, float usd, string name, string bonus)
        {
            Id = id; Np = np; Ngn = ngn; Usd = usd; Name = name; Bonus = bonus;
        }
    }

    public enum DrawItemKind { Mythic, Epic, Rare, Common }

    public struct DrawItem
    {
        public DrawItemKind Kind;
        public string Gun;     // mythic items only: gun id
        public int SkinIdx;    // mythic items only: 1-based skin index
        public string Label;   // non-mythic items: flair label

        public DrawItem(DrawItemKind kind, string gun, int skinIdx, string label)
        {
            Kind = kind; Gun = gun; SkinIdx = skinIdx; Label = label;
        }
    }

    public struct DrawDef
    {
        public string Id;
        public string Name;
        public int EndsInDays;
        public DrawItem[] Items;   // exactly 10 slots

        public DrawDef(string id, string name, int endsInDays, DrawItem[] items)
        {
            Id = id; Name = name; EndsInDays = endsInDays; Items = items;
        }
    }

    public struct BundleDef
    {
        public string Id;
        public string Name;
        public string Gun;     // mythic skin gun
        public int SkinIdx;    // 1-based
        public int Price;      // NP
        public string Desc;

        public BundleDef(string id, string name, string gun, int skinIdx, int price, string desc)
        {
            Id = id; Name = name; Gun = gun; SkinIdx = skinIdx; Price = price; Desc = desc;
        }
    }

    public struct SkinOffer
    {
        public string Gun;
        public int SkinIdx;

        public SkinOffer(string gun, int skinIdx) { Gun = gun; SkinIdx = skinIdx; }
    }

    public struct StoreTab
    {
        public string Id;
        public string Name;
        public bool Locked;
        public string LockNote;

        public StoreTab(string id, string name, bool locked, string lockNote)
        {
            Id = id; Name = name; Locked = locked; LockNote = lockNote;
        }
    }

    public static class StoreData
    {
        public static readonly StoreTab[] Tabs = {
            new StoreTab("featured",   "FEATURED",        false, ""),
            new StoreTab("draws",      "LUCKY DRAWS",     false, ""),
            new StoreTab("skins",      "WEAPON SKINS",    false, ""),
            new StoreTab("bundles",    "BUNDLES",         false, ""),
            new StoreTab("characters", "CHARACTERS 🔒",   true,  "PREMIUM OPERATORS — COMING SOON"),
            new StoreTab("pass",       "BATTLE PASS 🔒",  true,  "SEASON 1 BATTLE PASS — COMING SOON"),
            new StoreTab("np",         "BUY NOVA POINTS", false, ""),
        };

        public static readonly NpPack[] NpPacks = {
            new NpPack("np_100",  100,  1500,  1.0f, "Handful of Points", ""),
            new NpPack("np_500",  500,  6500,  4.5f, "Stack of Points",   "+25 BONUS"),
            new NpPack("np_1000", 1100, 12000, 8.0f, "Pile of Points",    "+100 BONUS"),
            new NpPack("np_2500", 2900, 27500, 18.0f,"Vault of Points",   "+400 BONUS"),
            new NpPack("np_5000", 6200, 50000, 32.0f,"Fortune of Points", "+1200 BONUS"),
        };

        public const int MythicPrice = 950;

        /// <summary>Direct-buy mythic skins (sample of the 411 catalog), 950 NP each.</summary>
        public static readonly SkinOffer[] SkinOffers = {
            new SkinOffer("m5", 1),    new SkinOffer("kv47", 2),
            new SkinOffer("mp9", 1),   new SkinOffer("dg12", 3),
            new SkinOffer("mg60", 2),  new SkinOffer("lw9", 1),
            new SkinOffer("mk14", 3),  new SkinOffer("sg9", 2),
            new SkinOffer("p9", 1),    new SkinOffer("knife", 2),
            new SkinOffer("rp7", 1),   new SkinOffer("kn44", 3),
            new SkinOffer("lk24", 1),  new SkinOffer("vsk9", 2),
            new SkinOffer("k10", 3),   new SkinOffer("p45", 1),
            new SkinOffer("bx200", 2), new SkinOffer("sr8", 3),
            new SkinOffer("sr4", 1),   new SkinOffer("sa9", 2),
            new SkinOffer("mp50", 3),  new SkinOffer("katana", 1),
            new SkinOffer("rl4", 2),   new SkinOffer("br9", 1),
        };

        public static readonly BundleDef[] Bundles = {
            new BundleDef("bundle_dragonfire", "DRAGONFIRE ARSENAL", "kv47", 1, 1500,
                "Mythic KV-47 skin + Ember operator card + Molten calling card + Flame avatar frame"),
            new BundleDef("bundle_glacier", "GLACIER PROTOCOL", "lw9", 1, 1500,
                "Mythic LW-9 skin + Frost operator card + Icefield calling card + Crystal avatar frame"),
            new BundleDef("bundle_necrovoid", "NECROVOID UPRISING", "m5", 2, 1800,
                "Mythic M5 skin + Void operator card + Abyss calling card + Rift avatar frame + animated banner"),
        };

        /// <summary>Escalating per-spin NP costs (CODM rule).</summary>
        public static readonly int[] DrawSpinCosts = { 30, 60, 110, 180, 270, 380, 510, 660, 830, 1020 };

        /// <summary>Per-kind odds, re-weighted over the remaining pool each spin.</summary>
        public static float DrawOdds(DrawItemKind kind)
        {
            switch (kind)
            {
                case DrawItemKind.Mythic: return 0.03f;
                case DrawItemKind.Epic:   return 0.12f;
                case DrawItemKind.Rare:   return 0.30f;
                default:                  return 0.55f;
            }
        }

        public static readonly DrawDef[] Draws = {
            new DrawDef("draw_dragonfire", "DRAGONFIRE DRAW", 6, new DrawItem[] {
                new DrawItem(DrawItemKind.Mythic, "kv47", 1, ""),
                new DrawItem(DrawItemKind.Epic,   "", 0, "Ember Calling Card"),
                new DrawItem(DrawItemKind.Epic,   "", 0, "Molten Avatar Frame"),
                new DrawItem(DrawItemKind.Rare,   "", 0, "Dragonfire Weapon Charm"),
                new DrawItem(DrawItemKind.Rare,   "", 0, "Ember Operator Card"),
                new DrawItem(DrawItemKind.Common, "", 0, "500 Cash Bundle (BR)"),
                new DrawItem(DrawItemKind.Common, "", 0, "Armor Shard Pack"),
                new DrawItem(DrawItemKind.Common, "", 0, "Smoke Grenade Skin: Ember"),
                new DrawItem(DrawItemKind.Common, "", 0, "Frag Grenade Skin: Magma"),
                new DrawItem(DrawItemKind.Common, "", 0, "Parachute Skin: Firestorm"),
            }),
            new DrawDef("draw_glacier", "GLACIER DRAW", 13, new DrawItem[] {
                new DrawItem(DrawItemKind.Mythic, "lw9", 1, ""),
                new DrawItem(DrawItemKind.Epic,   "", 0, "Icefield Calling Card"),
                new DrawItem(DrawItemKind.Epic,   "", 0, "Crystal Avatar Frame"),
                new DrawItem(DrawItemKind.Rare,   "", 0, "Glacier Weapon Charm"),
                new DrawItem(DrawItemKind.Rare,   "", 0, "Frost Operator Card"),
                new DrawItem(DrawItemKind.Common, "", 0, "500 Cash Bundle (BR)"),
                new DrawItem(DrawItemKind.Common, "", 0, "Armor Shard Pack"),
                new DrawItem(DrawItemKind.Common, "", 0, "Smoke Grenade Skin: Blizzard"),
                new DrawItem(DrawItemKind.Common, "", 0, "Frag Grenade Skin: Icicle"),
                new DrawItem(DrawItemKind.Common, "", 0, "Parachute Skin: Whiteout"),
            }),
            new DrawDef("draw_necrovoid", "NECROVOID DRAW", 20, new DrawItem[] {
                new DrawItem(DrawItemKind.Mythic, "m5", 2, ""),
                new DrawItem(DrawItemKind.Epic,   "", 0, "Abyss Calling Card"),
                new DrawItem(DrawItemKind.Epic,   "", 0, "Rift Avatar Frame"),
                new DrawItem(DrawItemKind.Rare,   "", 0, "Necrovoid Weapon Charm"),
                new DrawItem(DrawItemKind.Rare,   "", 0, "Void Operator Card"),
                new DrawItem(DrawItemKind.Common, "", 0, "500 Cash Bundle (BR)"),
                new DrawItem(DrawItemKind.Common, "", 0, "Armor Shard Pack"),
                new DrawItem(DrawItemKind.Common, "", 0, "Smoke Grenade Skin: Voidmist"),
                new DrawItem(DrawItemKind.Common, "", 0, "Frag Grenade Skin: Singularity"),
                new DrawItem(DrawItemKind.Common, "", 0, "Parachute Skin: Eventide"),
            }),
        };

        // ---------------------------------------------------------------- lookups

        public static NpPack NpPackById(string id)
        {
            for (int i = 0; i < NpPacks.Length; i++)
                if (NpPacks[i].Id == id) return NpPacks[i];
            return default(NpPack);
        }

        public static DrawDef DrawById(string id)
        {
            for (int i = 0; i < Draws.Length; i++)
                if (Draws[i].Id == id) return Draws[i];
            return default(DrawDef);
        }

        public static BundleDef BundleById(string id)
        {
            for (int i = 0; i < Bundles.Length; i++)
                if (Bundles[i].Id == id) return Bundles[i];
            return default(BundleDef);
        }

        public static DrawItem DrawTopPrize(string drawId)
        {
            DrawDef d = DrawById(drawId);
            if (d.Items == null) return default(DrawItem);
            for (int i = 0; i < d.Items.Length; i++)
                if (d.Items[i].Kind == DrawItemKind.Mythic) return d.Items[i];
            return default(DrawItem);
        }

        /// <summary>Full-draw cost (all 10 spins) — 4050 NP.</summary>
        public static int DrawFullCost()
        {
            int t = 0;
            for (int i = 0; i < DrawSpinCosts.Length; i++) t += DrawSpinCosts[i];
            return t;
        }

        // ------------------------------------------------- mythic skin naming
        // Godot names skins "<GunName> \"<Theme>\"", picking 3 distinct themes
        // per gun with a stride-5 walk over the 14-theme table seeded by the
        // gun id hash. Ported here with a stable FNV-1a hash (Godot's internal
        // String.hash is not portable); format and determinism match.

        private static readonly string[] MythicThemeNames = {
            "Dragonfire", "Glacier", "Necrovoid", "Solarflare", "Venom",
            "Bloodmoon", "Mecha", "Aurora", "Sandstorm", "Abyssal",
            "Phoenix", "Stormcaller", "Crimson Oath", "Onyx Reign",
        };

        private static int StableHash(string s)
        {
            unchecked
            {
                uint h = 2166136261u;
                for (int i = 0; i < s.Length; i++)
                {
                    h ^= s[i];
                    h *= 16777619u;
                }
                return (int)(h & 0x7fffffff);
            }
        }

        /// <summary>Theme name for a gun's Nth mythic skin (1-based), Godot-style.</summary>
        public static string MythicSkinTheme(string gunId, int skinIdx)
        {
            if (skinIdx < 1 || skinIdx > 3) return "";
            int start = StableHash(gunId) % MythicThemeNames.Length;
            int theme = (start + (skinIdx - 1) * 5) % MythicThemeNames.Length;
            return MythicThemeNames[theme];
        }

        /// <summary>Display label for a draw/bundle skin item. Mythic labels come
        /// from the real skin naming rule so they never go stale.</summary>
        public static string MythicSkinLabel(string gunId, int skinIdx)
        {
            string theme = MythicSkinTheme(gunId, skinIdx);
            if (theme == "") return "MYTHIC SKIN";
            string gunName = gunId.ToUpperInvariant();
            if (NovaMobile.Arsenal.GunData.Has(gunId))
                gunName = NovaMobile.Arsenal.GunData.Get(gunId).Name;
            return gunName + " \"" + theme + "\"";
        }

        public static string ItemLabel(DrawItem item)
        {
            if (item.Kind == DrawItemKind.Mythic)
                return "MYTHIC: " + MythicSkinLabel(item.Gun, item.SkinIdx);
            return item.Label;
        }

        public static Color RarityColor(DrawItemKind kind)
        {
            switch (kind)
            {
                case DrawItemKind.Mythic: return new Color(1.0f, 0.6f, 1.0f);
                case DrawItemKind.Epic:   return new Color(0.75f, 0.5f, 1.0f);
                case DrawItemKind.Rare:   return new Color(0.45f, 0.7f, 1.0f);
                default:                  return new Color(0.7f, 0.7f, 0.7f);
            }
        }
    }
}
