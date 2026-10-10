using UnityEngine;

namespace NovaMobile.Loot
{
    /// <summary>7-tier loot rarity spectrum (Common -> Relic). Contract shape per CONVENTIONS.md.</summary>
    public enum Rarity { Common, Uncommon, Rare, Epic, Legendary, Mythic, Relic }

    /// <summary>Kinds of ground loot. Weapon loot is NOT a kind here: it rides on
    /// LootItem.GunId and spawns through Arsenal.GunPickup (mirroring Godot, where
    /// guns were a separate GunPickup scene).</summary>
    public enum LootKind { Health, Armor, Ammo, Cash, Frag, Smoke, Shard, Scorestreak, FuelCan, Attachment }

    /// <summary>One rolled loot result. Contract shape per CONVENTIONS.md.</summary>
    public struct LootItem
    {
        public LootKind Kind;
        public Rarity Rarity;
        public string GunId;        // gunId for weapon loot (spawns a GunPickup)
        public int Amount;
        public string AttachmentId; // set when Kind == Attachment

        public LootItem(LootKind kind, Rarity rarity, int amount = 1)
        {
            Kind = kind;
            Rarity = rarity;
            GunId = "";
            Amount = amount;
            AttachmentId = "";
        }
    }

    /// <summary>
    /// Loot economy tables. Roll(minTier, rng) is deliberately generous (CODM-like):
    /// the floor is guaranteed and each higher tier has a real shot, so matches feel
    /// rich instead of starved. Ported from loot.gd / loot_container.gd / loot_crate.gd.
    /// </summary>
    public static class LootTable
    {
        // CODM-style spectrum: grey / green / blue / purple / orange / red / gold.
        private static readonly Color[] TierColors = new Color[]
        {
            new Color(0.72f, 0.72f, 0.72f), // Common
            new Color(0.25f, 0.90f, 0.45f), // Uncommon
            new Color(0.35f, 0.60f, 1.00f), // Rare
            new Color(0.70f, 0.35f, 1.00f), // Epic
            new Color(1.00f, 0.60f, 0.15f), // Legendary
            new Color(1.00f, 0.16f, 0.12f), // Mythic
            new Color(1.00f, 0.82f, 0.20f), // Relic
        };

        private static readonly string[] TierNames = new string[]
            { "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY", "MYTHIC", "RELIC" };

        // Caliber colors for ammo boxes (mirrors loot_models.gd CALIBER_COLORS).
        private static readonly System.Collections.Generic.Dictionary<string, Color> CaliberColors =
            new System.Collections.Generic.Dictionary<string, Color>
            {
                { "light",   new Color(0.95f, 0.85f, 0.40f) },
                { "medium",  new Color(0.95f, 0.65f, 0.25f) },
                { "heavy",   new Color(1.00f, 0.45f, 0.20f) },
                { "shell",   new Color(0.85f, 0.25f, 0.20f) },
                { "rocket",  new Color(0.60f, 0.60f, 0.65f) },
                { "grenade", new Color(0.35f, 0.55f, 0.30f) },
                { "smoke",   new Color(0.70f, 0.70f, 0.75f) },
                { "none",    new Color(0.70f, 0.70f, 0.70f) },
            };

        public static Color RarityColor(Rarity r)
        {
            return TierColors[Mathf.Clamp((int)r, 0, TierColors.Length - 1)];
        }

        public static string RarityName(Rarity r)
        {
            return TierNames[Mathf.Clamp((int)r, 0, TierNames.Length - 1)];
        }

        public static Color CaliberColor(string caliber)
        {
            if (string.IsNullOrEmpty(caliber)) caliber = "medium";
            Color c;
            return CaliberColors.TryGetValue(caliber.ToLowerInvariant(), out c) ? c : CaliberColors["medium"];
        }

        /// <summary>
        /// Maps world-builder spot tiers (1 = ground/common, 2 = upper/uncommon,
        /// 3 = POI ring/rare, 4+ = epic) onto the Rarity enum.
        /// </summary>
        public static Rarity RarityFromSpotTier(int spotTier)
        {
            if (spotTier <= 1) return Rarity.Common;
            if (spotTier == 2) return Rarity.Uncommon;
            if (spotTier == 3) return Rarity.Rare;
            return Rarity.Epic;
        }

        /// <summary>Maps a Rarity to the 0-5 integer gun tier GunPickup expects.</summary>
        public static int GunTierOf(Rarity r)
        {
            return Mathf.Clamp((int)r, 0, 5);
        }

        /// <summary>Ammo caliber names used by loot ("medium" duplicated = weighted).</summary>
        public static string RollCaliber(System.Random rng)
        {
            string[] cals = { "light", "medium", "medium", "heavy", "shell" };
            return cals[rng.Next(cals.Length)];
        }

        /// <summary>
        /// Generous CODM-like roll: guarantees at least minTier, with decaying weights
        /// upward (floor 100, +1: 55, +2: 26, +3: 12, +4: 5, +5: 2, +6: 0.8).
        /// </summary>
        public static LootItem Roll(Rarity minTier, System.Random rng)
        {
            if (rng == null) rng = new System.Random();
            int floor = Mathf.Clamp((int)minTier, 0, 6);
            float[] w = { 100f, 55f, 26f, 12f, 5f, 2f, 0.8f };
            float total = 0f;
            for (int i = 0; i <= 6 - floor; i++) total += w[i];
            float r = (float)rng.NextDouble() * total;
            int off = 0;
            for (int i = 0; i <= 6 - floor; i++)
            {
                r -= w[i];
                if (r <= 0f) { off = i; break; }
                off = i;
            }
            Rarity tier = (Rarity)(floor + off);
            return RollKind(tier, rng);
        }

        private static LootItem RollKind(Rarity tier, System.Random rng)
        {
            int t = (int)tier;
            // Kind weights shift with tier: rare loot only appears at higher tiers.
            float health = 30f, armor = 15f, ammo = 30f, cash = 15f;
            float frag = t >= 1 ? 8f : 4f;
            float smoke = t >= 1 ? 7f : 3f;
            float shard = t >= 2 ? 6f : 0f;
            float attach = t >= 2 ? 8f : 0f;
            float streak = t >= 3 ? 5f : 0f;
            float fuel = t >= 2 ? 5f : 0f;
            float total = health + armor + ammo + cash + frag + smoke + shard + attach + streak + fuel;
            float r = (float)rng.NextDouble() * total;

            LootKind kind = LootKind.Health;
            if ((r -= health) <= 0f) kind = LootKind.Health;
            else if ((r -= armor) <= 0f) kind = LootKind.Armor;
            else if ((r -= ammo) <= 0f) kind = LootKind.Ammo;
            else if ((r -= cash) <= 0f) kind = LootKind.Cash;
            else if ((r -= frag) <= 0f) kind = LootKind.Frag;
            else if ((r -= smoke) <= 0f) kind = LootKind.Smoke;
            else if ((r -= shard) <= 0f) kind = LootKind.Shard;
            else if ((r -= attach) <= 0f) kind = LootKind.Attachment;
            else if ((r -= streak) <= 0f) kind = LootKind.Scorestreak;
            else kind = LootKind.FuelCan;

            int amount = 1;
            switch (kind)
            {
                case LootKind.Health: amount = 40 + 10 * t + rng.Next(21); break;
                case LootKind.Armor: amount = t >= 3 ? 2 : 1; break;
                case LootKind.Ammo: amount = 60 + 15 * t + rng.Next(31); break;
                case LootKind.Cash: amount = 100 + 80 * t + rng.Next(101); break;
                case LootKind.Frag: amount = t >= 2 ? 2 : 1; break;
                case LootKind.Smoke: amount = t >= 2 ? 2 : 1; break;
                case LootKind.Shard: amount = 1; break;
                case LootKind.Scorestreak: amount = 1; break;
                case LootKind.FuelCan: amount = 1; break;
                case LootKind.Attachment: amount = 1; break;
            }

            var item = new LootItem(kind, tier, amount);
            return item;
        }
    }
}
