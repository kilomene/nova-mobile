using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Arsenal;
using NovaMobile.Classes;
using NovaMobile.Core;
using NovaMobile.World;

namespace NovaMobile.Loot
{
    /// <summary>
    /// Match-start loot population. Spawns every WorldBuilder.LootSpots entry as a
    /// real pickup (honoring the kind/amount the region builders specified), fills
    /// every Building.LootSockets, and guarantees the economy rule: every building
    /// gets >= 2 loot. Also the shared spawn path for containers, crates, death
    /// boxes, and the Replicator duplicate event.
    /// </summary>
    public static class LootSpawner
    {
        /// <summary>Spawn all match loot. Call once at match start, after WorldBuilder.</summary>
        public static void SpawnAll(WorldBuilder wb)
        {
            ReplicatorWire.Ensure();
            LootUI.Ensure(); // CODM NEARBY / BOX panels + pickup cards
            if (wb == null) return;
            var rng = new System.Random(20261010);
            foreach (var spot in wb.LootSpots)
                SpawnSpot(spot);
            FillBuildings(rng);
            SpawnSupplyCrates(rng);
        }

        /// <summary>One WorldBuilder LootSpot -> pickup, honoring kind/amount/tier.</summary>
        public static void SpawnSpot(LootSpot spot)
        {
            LootItem item;
            string caliber = "medium";
            if (TryParseKind(spot.Kind, out LootKind kind))
            {
                item = new LootItem(kind, LootTable.RarityFromSpotTier(spot.Tier), Mathf.Max(spot.Amount, 1));
                if (kind == LootKind.Ammo) caliber = "medium";
            }
            else
            {
                // Unknown kind string: roll generously from the spot tier.
                item = LootTable.Roll(LootTable.RarityFromSpotTier(spot.Tier), new System.Random());
            }
            SpawnLoot(item, spot.Position, caliber);
        }

        private static bool TryParseKind(string kind, out LootKind lk)
        {
            lk = LootKind.Health;
            if (string.IsNullOrEmpty(kind)) return false;
            switch (kind.ToLowerInvariant())
            {
                case "health": lk = LootKind.Health; return true;
                case "armor": lk = LootKind.Armor; return true;
                case "ammo": lk = LootKind.Ammo; return true;
                case "cash": lk = LootKind.Cash; return true;
                case "frag":
                case "grenade": lk = LootKind.Frag; return true;
                case "smoke": lk = LootKind.Smoke; return true;
                case "shard": lk = LootKind.Shard; return true;
                case "scorestreak":
                case "uav":
                case "strike": lk = LootKind.Scorestreak; return true;
                case "fuelcan":
                case "fuel": lk = LootKind.FuelCan; return true;
                case "attachment":
                case "attach": lk = LootKind.Attachment; return true;
                default: return false;
            }
        }

        /// <summary>
        /// The shared spawn path. Items carrying a GunId (weapon loot) spawn through
        /// Arsenal.GunPickup; attachments through GunPickup.MakeAttachment; everything
        /// else as a LootPickup. Positions are snapped to the ground.
        /// </summary>
        public static GameObject SpawnLoot(LootItem item, Vector3 pos, string caliber = "medium", string scorestreakId = null)
        {
            Vector3 gp = CombatHelper.GroundSnap(null, pos);
            gp.y += 0.55f;
            GameObject go;
            if (!string.IsNullOrEmpty(item.GunId))
            {
                var gun = GunPickup.Make(item.GunId, LootTable.GunTierOf(item.Rarity));
                go = gun.gameObject;
            }
            else if (item.Kind == LootKind.Attachment && !string.IsNullOrEmpty(item.AttachmentId))
            {
                go = GunPickup.MakeAttachment(item.AttachmentId).gameObject;
            }
            else
            {
                go = LootPickup.Make(item, caliber, scorestreakId).gameObject;
            }
            go.transform.position = gp;
            PopIn(go);
            return go;
        }

        /// <summary>Weapon loot entry point (containers, crates, death boxes).</summary>
        public static GameObject SpawnGun(string gunId, int tier, Vector3 pos)
        {
            var item = new LootItem(LootKind.Health, (Rarity)Mathf.Clamp(tier, 0, 6));
            item.GunId = string.IsNullOrEmpty(gunId) ? "m5" : gunId;
            return SpawnLoot(item, pos);
        }

        /// <summary>Attachment loot entry point.</summary>
        public static GameObject SpawnAttachment(string attachId, Vector3 pos)
        {
            var item = new LootItem(LootKind.Attachment, Rarity.Uncommon);
            item.AttachmentId = attachId;
            return SpawnLoot(item, pos);
        }

        // ---------------- match-start population ----------------

        /// <summary>
        /// Fill every Building.LootSockets with rolled loot (socket Tier biases the
        /// roll), then enforce the economy guarantee: every building ends up with
        /// >= 2 loot pickups within 9 m of its center.
        /// </summary>
        public static void FillBuildings(System.Random rng)
        {
            var buildings = Object.FindObjectsByType<Building>(FindObjectsSortMode.None);
            var scratch = new List<ILootPickup>(64);
            foreach (var b in buildings)
            {
                if (b == null) continue;
                if (b.LootSockets != null)
                {
                    foreach (var s in b.LootSockets)
                    {
                        if (s == null) continue;
                        LootItem item = LootTable.Roll(LootTable.RarityFromSpotTier(s.Tier), rng);
                        if (item.Kind == LootKind.Attachment)
                            item.AttachmentId = AttachmentData.AttachLoot[rng.Next(AttachmentData.AttachLoot.Length)];
                        SpawnLoot(item, s.transform.position,
                            item.Kind == LootKind.Ammo ? LootTable.RollCaliber(rng) : "medium");
                    }
                }
                // Economy guarantee: >= 2 loot within 9 m of the building center.
                Vector3 center = b.transform.position;
                LootPickupRegistry.Query(center, 9f, scratch);
                int need = Mathf.Max(0, 2 - scratch.Count);
                for (int i = 0; i < need; i++)
                {
                    LootKind[] kinds = { LootKind.Health, LootKind.Ammo, LootKind.Armor, LootKind.Cash };
                    LootKind k = kinds[rng.Next(kinds.Length)];
                    int amt = k == LootKind.Ammo ? 60 : k == LootKind.Cash ? 120 : 40;
                    var filler = new LootItem(k, Rarity.Common, amt);
                    Vector3 pos = center + new Vector3(
                        (float)rng.NextDouble() * 6f - 3f, 0.5f,
                        (float)rng.NextDouble() * 6f - 3f);
                    SpawnLoot(filler, pos);
                }
            }
        }

        /// <summary>Supply crates scattered at POIs: 45% of POIs, tier-weighted (8% epic).</summary>
        public static void SpawnSupplyCrates(System.Random rng)
        {
            foreach (var poi in WorldData.Pois)
            {
                if (rng.NextDouble() > 0.45) continue;
                double r = rng.NextDouble();
                int t = r > 0.92 ? 2 : r > 0.70 ? 1 : 0;
                var crate = SupplyCrate.Make(t);
                Vector3 off = new Vector3(
                    4f + (float)rng.NextDouble() * 5f, 0f,
                    4f + (float)rng.NextDouble() * 5f);
                Vector3 gp = CombatHelper.GroundSnap(null, poi.Position + off);
                crate.transform.position = gp;
            }
        }

        // ---------------- pop-in ----------------

        private static LootRunner _runner;

        private static void PopIn(GameObject go)
        {
            if (_runner == null)
            {
                var rgo = new GameObject("LootRunner");
                Object.DontDestroyOnLoad(rgo);
                _runner = rgo.AddComponent<LootRunner>();
            }
            _runner.StartCoroutine(PopRoutine(go));
        }

        private static IEnumerator PopRoutine(GameObject go)
        {
            if (go == null) yield break;
            go.transform.localScale = Vector3.one * 0.3f;
            float e = 0f;
            while (e < 0.28f && go != null)
            {
                e += Time.deltaTime;
                float k = Mathf.Clamp01(e / 0.28f);
                float ok = 1f + 1.4f * Mathf.Pow(k - 1f, 3f) + 0.4f * Mathf.Pow(k - 1f, 2f);
                go.transform.localScale = Vector3.one * Mathf.Max(0.01f, ok);
                yield return null;
            }
            if (go != null) go.transform.localScale = Vector3.one;
        }

        private sealed class LootRunner : MonoBehaviour { }
    }

    /// <summary>
    /// Wires the Classes system's Replicator.RequestDuplicateLoot static event:
    /// when the Replicator ability mirrors loot, spawn a real duplicate pickup
    /// of the same item at the requested position.
    /// </summary>
    public static class ReplicatorWire
    {
        private static bool _wired;

        /// <summary>Idempotent: safe to call from SpawnAll and lazily.</summary>
        public static void Ensure()
        {
            if (_wired) return;
            _wired = true;
            ReplicatorAbility.RequestDuplicateLoot += OnRequestDuplicate;
        }

        private static void OnRequestDuplicate(ILootPickup src, Vector3 pos)
        {
            if (src == null || src.gameObject == null) return;
            var lp = src as LootPickup;
            if (lp == null) return; // only real loot pickups duplicate (not gun pickups)
            LootSpawner.SpawnLoot(lp.Item, pos, lp.Caliber, lp.ScorestreakId);
        }
    }
}
