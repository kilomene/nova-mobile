using System;
using System.Collections;
using UnityEngine;
using NovaMobile.Arsenal;
using NovaMobile.Classes;
using NovaMobile.Core;
using NovaMobile.Player;
using NovaMobile.Vehicles;

namespace NovaMobile.Loot
{
    /// <summary>
    /// Floating world pickup: health / armor / ammo / cash / frag / smoke / shard /
    /// scorestreak / fuel can / attachment. Real 3D models (no flat icons), tier glow
    /// ring, rarity beam for Epic+, magnet fly-to-player pickup animation,
    /// per-rarity pickup sounds, pingable. Consumables respawn; one-shot
    /// scorestreaks don't. Ported from loot.gd; implements Classes.ILootPickup so
    /// the Replicator ability can mirror it and LootPickupRegistry can find it.
    /// </summary>
    [RequireComponent(typeof(SphereCollider))]
    public class LootPickup : MonoBehaviour, ILootPickup
    {
        public const float RespawnDelay = 25f;

        // ---- ILootPickup ----
        GameObject ILootPickup.gameObject => gameObject;
        public string Kind => Item.Kind.ToString().ToLowerInvariant();
        public int Amount => Item.Amount;
        public int Tier => (int)Item.Rarity;

        public LootItem Item;
        public string Caliber = "medium";       // ammo only
        public string ScorestreakId = "uav";     // Scorestreak only: "uav" | "strike"

        /// <summary>Fired when taken: announcement text for the HUD feed.</summary>
        public Action<string> OnPickedUp;
        /// <summary>Match economy hooks (no cash wallet exists in the Player port yet).</summary>
        public static Action<int> OnCashCollected;
        /// <summary>Scorestreak hooks ("uav" | "strike") — UAV/strike systems subscribe.</summary>
        public static Action<string> OnScorestreak;
        /// <summary>Fuel canister stashed in inventory (not poured into a vehicle).</summary>
        public static Action<int> OnFuelCanStashed;
        /// <summary>Fired on every collect: name + rarity for the pickup card UI.</summary>
        public static Action<string, Rarity> OnPickupCard;

        private Transform _holder;
        private GameObject _beam;
        private TextMesh _label;
        private float _t;
        private bool _taken;
        private bool _flying;
        private PlayerController _flyTarget;
        private bool _pinged;
        private static int _respawnGen;

        public static LootPickup Make(LootItem item, string caliber = "medium", string scorestreakId = null)
        {
            var go = new GameObject("Loot_" + item.Kind);
            var p = go.AddComponent<LootPickup>();
            p.Item = item;
            p.Caliber = string.IsNullOrEmpty(caliber) ? "medium" : caliber;
            p.ScorestreakId = string.IsNullOrEmpty(scorestreakId)
                ? (NovaUtils.Range(0f, 1f) < 0.5f ? "uav" : "strike")
                : scorestreakId;
            return p;
        }

        private void Awake()
        {
            var col = GetComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 1.4f;

            _holder = new GameObject("ModelHolder").transform;
            _holder.SetParent(transform, false);
            _holder.localPosition = Vector3.zero;
            RebuildVisual();
        }

        private void OnEnable() { LootPickupRegistry.Register(this); }
        private void OnDisable() { LootPickupRegistry.Unregister(this); }

        private void RebuildVisual()
        {
            for (int i = _holder.childCount - 1; i >= 0; i--)
                Destroy(_holder.GetChild(i).gameObject);

            GameObject model = null;
            switch (Item.Kind)
            {
                case LootKind.Health: model = LootModels.Medkit(); break;
                case LootKind.Armor: model = LootModels.ArmorPlates(); break;
                case LootKind.Shard: model = LootModels.ArmorShard(); break;
                case LootKind.Ammo: model = LootModels.AmmoBox(Caliber); break;
                case LootKind.Cash: model = LootModels.CashBundle(); break;
                case LootKind.Frag: model = LootModels.FragGrenade(); break;
                case LootKind.Smoke: model = LootModels.SmokeCanister(); break;
                case LootKind.Scorestreak: model = LootModels.StreakDevice(ScorestreakId); break;
                case LootKind.FuelCan: model = LootModels.FuelCan(); break;
                case LootKind.Attachment: model = LootModels.AttachmentCase(); break;
            }
            if (model != null)
            {
                model.transform.SetParent(_holder, false);
                model.transform.localPosition = new Vector3(0f, 0.55f, 0f);
            }

            // Tier glow ring (health always shows at least Uncommon).
            Rarity ringR = (Item.Kind == LootKind.Health && Item.Rarity == Rarity.Common)
                ? Rarity.Uncommon : Item.Rarity;
            var ring = LootModels.TierRing(ringR);
            ring.transform.SetParent(_holder, false);
            ring.transform.localPosition = new Vector3(0f, 0.06f, 0f);

            // Rarity beam for Epic+.
            if (Item.Rarity >= Rarity.Epic)
            {
                _beam = LootModels.RarityBeam(Item.Rarity);
                _beam.transform.SetParent(transform, false);
                _beam.transform.localPosition = Vector3.zero;
            }

            var labelGo = new GameObject("Label");
            labelGo.transform.SetParent(transform, false);
            labelGo.transform.localPosition = new Vector3(0f, 1.15f, 0f);
            _label = labelGo.AddComponent<TextMesh>();
            _label.anchor = TextAnchor.MiddleCenter;
            _label.alignment = TextAlignment.Center;
            _label.characterSize = 0.05f;
            _label.fontSize = 44;
            _label.color = LootTable.RarityColor(Item.Rarity);
            _label.text = DisplayName();
        }

        public string DisplayName()
        {
            switch (Item.Kind)
            {
                case LootKind.Health: return "MEDKIT";
                case LootKind.Armor: return "ARMOR PLATES x" + Item.Amount;
                case LootKind.Ammo:
                    return Caliber.ToUpperInvariant() + " AMMO x" + Item.Amount;
                case LootKind.Cash: return "CASH $" + Item.Amount;
                case LootKind.Frag: return "FRAG GRENADE x" + Item.Amount;
                case LootKind.Smoke: return "SMOKE x" + Item.Amount;
                case LootKind.Shard: return "ARMOR SHARD";
                case LootKind.Scorestreak: return ScorestreakId == "uav" ? "UAV SWEEP" : "CLUSTER STRIKE";
                case LootKind.FuelCan: return "FUEL CANISTER";
                case LootKind.Attachment:
                    AttachmentMod a;
                    string n = AttachmentData.TryGet(Item.AttachmentId, out a) ? a.Name : Item.AttachmentId;
                    return "ATTACHMENT: " + n.ToUpperInvariant();
                default: return Item.Kind.ToString().ToUpperInvariant();
            }
        }

        private void Update()
        {
            if (_taken && !_flying) return;
            _t += Time.deltaTime;

            if (_flying)
            {
                if (_flyTarget == null || !_flyTarget.IsAlive) { ResetIdle(); return; }
                Vector3 tp = _flyTarget.transform.position + new Vector3(0f, 1.0f, 0f);
                transform.position = Vector3.Lerp(transform.position, tp,
                    Mathf.Min(Time.deltaTime * 10f, 1f));
                _holder.Rotate(0f, 9f * Time.deltaTime * Mathf.Rad2Deg, 0f);
                if (Vector3.Distance(transform.position, tp) < 0.6f)
                {
                    _flying = false;
                    Apply(_flyTarget);
                }
                return;
            }

            _holder.Rotate(0f, 1.6f * Time.deltaTime * Mathf.Rad2Deg, 0f);
            Vector3 p = _holder.position;
            p.y = Mathf.Sin(_t * 2.2f) * 0.1f;
            _holder.position = p;
            if (_beam != null)
                _beam.transform.Rotate(0f, 0.7f * Time.deltaTime * Mathf.Rad2Deg, 0f);
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_taken || _flying) return;
            var pc = other.GetComponentInParent<PlayerController>();
            TakeBy(pc);
        }

        /// <summary>
        /// Start the magnet fly-to-player collect. Called by the trigger and by the
        /// NEARBY panel's tap-to-pickup.
        /// </summary>
        public void TakeBy(PlayerController pc)
        {
            if (_taken || _flying) return;
            if (pc == null || !pc.IsAlive) return;
            _taken = true;
            _flying = true;
            _flyTarget = pc;
            var col = GetComponent<SphereCollider>();
            col.enabled = false;
            LootAudio.PlayAt(LootAudio.PickupClip(Item.Rarity), transform.position);
        }

        private void ResetIdle()
        {
            _taken = false;
            _flying = false;
            _flyTarget = null;
            GetComponent<SphereCollider>().enabled = true;
        }

        private void Apply(PlayerController b)
        {
            switch (Item.Kind)
            {
                case LootKind.Health:
                    b.Heal(Item.Amount);
                    break;
                case LootKind.Armor:
                    for (int i = 0; i < Mathf.Max(Item.Amount, 1); i++) b.AddArmorPlate();
                    break;
                case LootKind.Ammo:
                    var gb = b.GetComponentInChildren<GunBehaviour>();
                    if (gb == null) gb = b.GetComponentInParent<GunBehaviour>();
                    if (gb != null) gb.AddAmmo(CaliberToAmmo(Caliber), Item.Amount);
                    break;
                case LootKind.Cash:
                    if (OnCashCollected != null) OnCashCollected(Item.Amount);
                    break;
                case LootKind.Frag:
                    b.AddGrenades(Item.Amount);
                    break;
                case LootKind.Smoke:
                    b.AddSmoke(Item.Amount);
                    break;
                case LootKind.Shard:
                    b.AddArmorPlate(); // no partial-plate API in the Player port; closest faithful apply
                    break;
                case LootKind.Scorestreak:
                    if (OnScorestreak != null) OnScorestreak(ScorestreakId);
                    break;
                case LootKind.FuelCan:
                    ApplyFuelCan(b);
                    break;
                case LootKind.Attachment:
                    var carrier = b.GetComponentInParent<IGunCarrier>();
                    if (carrier == null) carrier = b.GetComponent<IGunCarrier>();
                    if (carrier != null && !string.IsNullOrEmpty(Item.AttachmentId))
                        carrier.AttachToCurrent(Item.AttachmentId);
                    break;
            }

            if (OnPickedUp != null) OnPickedUp(DisplayName());
            if (OnPickupCard != null) OnPickupCard(DisplayName(), Item.Rarity);
            gameObject.SetActive(false);
            _pinged = false;

            // Consumables respawn; one-shot scorestreaks don't.
            if (Item.Kind == LootKind.Scorestreak)
            {
                Destroy(gameObject);
                return;
            }
            StartCoroutine(RespawnRoutine(++_respawnGen));
        }

        private IEnumerator RespawnRoutine(int gen)
        {
            yield return new WaitForSeconds(RespawnDelay);
            if (gen != _respawnGen) yield break;
            ResetIdle();
            gameObject.SetActive(true);
        }

        private void ApplyFuelCan(PlayerController b)
        {
            // Pour into a nearby thirsty vehicle, else stash as an inventory canister.
            VehicleController best = null;
            float bestD2 = 16f;
            var all = GameObject.FindObjectsByType<VehicleController>(FindObjectsSortMode.None);
            foreach (var v in all)
            {
                if (v == null || v.Destroyed || !v.Spec.UsesFuel || !v.NeedsFuel()) continue;
                float d2 = (v.transform.position - b.transform.position).sqrMagnitude;
                if (d2 < bestD2) { bestD2 = d2; best = v; }
            }
            if (best != null)
            {
                best.AddFuel(35f);
                if (OnPickedUp != null) OnPickedUp("+35 FUEL poured in");
            }
            else if (OnFuelCanStashed != null)
            {
                OnFuelCanStashed(1);
            }
        }

        public static AmmoType CaliberToAmmo(string caliber)
        {
            if (string.IsNullOrEmpty(caliber)) return AmmoType.Medium;
            switch (caliber.ToLowerInvariant())
            {
                case "light": return AmmoType.Light;
                case "heavy": return AmmoType.Heavy;
                case "shell": return AmmoType.Shell;
                case "rocket": return AmmoType.Rocket;
                case "grenade": return AmmoType.Grenade;
                default: return AmmoType.Medium;
            }
        }

        /// <summary>Called by the match when the player pings this pickup.</summary>
        public void Ping()
        {
            if (_taken || _pinged) return;
            _pinged = true;
            LootPing.Spawn(DisplayName(), Item.Rarity, transform.position);
            LootAudio.PlayAt(LootAudio.PingClip(), transform.position);
        }
    }
}
