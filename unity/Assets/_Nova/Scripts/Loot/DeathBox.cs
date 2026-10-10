using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Arsenal;
using NovaMobile.Core;
using NovaMobile.Player;

namespace NovaMobile.Loot
{
    /// <summary>
    /// Enemy death crate: drops where an enemy died, containing what they carried —
    /// their exact gun + matching ammo + a random bonus. Accent stripe in the
    /// victim's class color, name label. Touch to open -> the CODM-style BOX panel
    /// (Weapon / Attachment / Medicine sections); tap an entry to take it.
    /// Ported from death_box.gd; panel layout per the CODM visual bible §8.
    /// </summary>
    [RequireComponent(typeof(SphereCollider))]
    public class DeathBox : MonoBehaviour
    {
        public string VictimName = "HOSTILE";
        public string GunId = "m5";
        public int GunTier = 1;
        public string Caliber = "medium";
        public Color Accent = new Color(0.8f, 0.2f, 0.2f);

        private bool _opened;
        private TextMesh _label;

        /// <summary>Spawn a death box for a killed enemy.</summary>
        public static DeathBox Spawn(string victimName, string gunId, int ammo, Color classColor, Vector3 position)
        {
            var go = new GameObject("DeathBox_" + victimName);
            var d = go.AddComponent<DeathBox>();
            d.VictimName = string.IsNullOrEmpty(victimName) ? "HOSTILE" : victimName;
            d.GunId = string.IsNullOrEmpty(gunId) ? "m5" : gunId;
            d.Accent = classColor;
            GunSpec g = GunData.Get(d.GunId);
            d.Caliber = AmmoToCaliber(g.Ammo);
            d.GunTier = LootTable.GunTierOf(RarityFromGun(g));
            d.AmmoAmount = Mathf.Max(ammo, 0);
            go.transform.position = position;
            return d;
        }

        private int AmmoAmount = 60;

        private static string AmmoToCaliber(AmmoType a)
        {
            switch (a)
            {
                case AmmoType.Light: return "light";
                case AmmoType.Heavy: return "heavy";
                case AmmoType.Shell: return "shell";
                case AmmoType.Rocket: return "rocket";
                case AmmoType.Grenade: return "grenade";
                default: return "medium";
            }
        }

        private static Rarity RarityFromGun(GunSpec g)
        {
            // Heavier gun classes read as higher-tier loot.
            switch (g.Class)
            {
                case GunClass.Sniper:
                case GunClass.LMG: return Rarity.Rare;
                case GunClass.Launcher: return Rarity.Epic;
                default: return Rarity.Uncommon;
            }
        }

        private void Awake()
        {
            var col = GetComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 1.3f;
            Build();
        }

        private static Material CMat(Color c, float rough = 0.65f, float metal = 0f, float emit = 0f)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = c;
            m.SetFloat("_Metallic", metal);
            m.SetFloat("_Glossiness", 1f - rough);
            if (emit > 0f)
            {
                m.EnableKeyword("_EMISSION");
                m.SetColor("_EmissionColor", c * emit);
            }
            return m;
        }

        private void Build()
        {
            Material dark = CMat(new Color(0.16f, 0.16f, 0.18f));
            Material accm = CMat(Accent, 0.5f, 0f, 1f);
            var bodyGo = MeshBuilder.BuildObject("body",
                new List<MeshBuilder.Part> { MeshBuilder.Box(new Vector3(0.85f, 0.35f, 0.6f), Matrix4x4.TRS(new Vector3(0f, 0.18f, 0f), Quaternion.identity, Vector3.one)) }, dark);
            bodyGo.transform.SetParent(transform, false);
            var stripeGo = MeshBuilder.BuildObject("stripe",
                new List<MeshBuilder.Part> { MeshBuilder.Box(new Vector3(0.87f, 0.07f, 0.62f), Matrix4x4.TRS(new Vector3(0f, 0.30f, 0f), Quaternion.identity, Vector3.one)) }, accm);
            stripeGo.transform.SetParent(transform, false);

            var labelGo = new GameObject("Label");
            labelGo.transform.SetParent(transform, false);
            labelGo.transform.localPosition = new Vector3(0f, 0.95f, 0f);
            _label = labelGo.AddComponent<TextMesh>();
            _label.anchor = TextAnchor.MiddleCenter;
            _label.alignment = TextAlignment.Center;
            _label.characterSize = 0.055f;
            _label.fontSize = 44;
            _label.color = new Color(1f, 1f, 1f, 0.85f);
            _label.text = VictimName.ToUpperInvariant() + "'S PACK";
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_opened) return;
            var pc = other.GetComponentInParent<PlayerController>();
            if (pc == null || !pc.IsAlive) return;
            Open(pc);
        }

        public void Open(PlayerController pc)
        {
            if (_opened || pc == null) return;
            _opened = true;
            GetComponent<SphereCollider>().enabled = false;
            if (_label != null) _label.gameObject.SetActive(false);
            LootAudio.PlayAt(LootAudio.ThudClip(), transform.position);
            StartCoroutine(PopRoutine());
            ShowBoxPanel(pc);
        }

        private IEnumerator PopRoutine()
        {
            float e = 0f;
            while (e < 0.12f)
            {
                e += Time.deltaTime;
                float k = Mathf.Clamp01(e / 0.12f);
                transform.localScale = new Vector3(1f + 0.15f * k, 1f - 0.3f * k, 1f + 0.15f * k);
                yield return null;
            }
            e = 0f;
            while (e < 0.18f)
            {
                e += Time.deltaTime;
                float k = Mathf.Clamp01(e / 0.18f);
                transform.localScale = Vector3.Lerp(new Vector3(1.15f, 0.7f, 1.15f), Vector3.one, k);
                yield return null;
            }
            transform.localScale = Vector3.one;
        }

        private void ShowBoxPanel(PlayerController pc)
        {
            var entries = new List<LootUI.BoxEntry>();
            GunSpec g = GunData.Get(GunId);
            Rarity gunRarity = (Rarity)Mathf.Clamp(GunTier, 0, 6);

            // Weapon: the victim's exact gun.
            entries.Add(new LootUI.BoxEntry
            {
                Section = "Weapon",
                Title = GunData.FullName(g),
                Desc = "Basic " + g.Class,
                Tier = gunRarity,
                Icon = LootIconKind.Gun,
                Take = () =>
                {
                    var carrier = pc.GetComponentInParent<IGunCarrier>();
                    if (carrier == null) carrier = pc.GetComponent<IGunCarrier>();
                    if (carrier != null) carrier.GiveGun(GunId, GunTier);
                }
            });

            // Attachment: a trophy attachment from the victim's kit.
            string aid = AttachmentData.AttachLoot[Random.Range(0, AttachmentData.AttachLoot.Length)];
            AttachmentMod am;
            string aname = AttachmentData.TryGet(aid, out am) ? am.Name : aid;
            string adesc = AttachmentData.TryGet(aid, out am) ? AttachmentData.ModDescription(am) : "";
            entries.Add(new LootUI.BoxEntry
            {
                Section = "Attachment",
                Title = aname,
                Desc = adesc,
                Tier = Rarity.Uncommon,
                Icon = LootIconKind.Attachment,
                Take = () =>
                {
                    var carrier = pc.GetComponentInParent<IGunCarrier>();
                    if (carrier == null) carrier = pc.GetComponent<IGunCarrier>();
                    if (carrier != null) carrier.AttachToCurrent(aid);
                }
            });

            // MAGAZINE: matching ammo.
            int ammoAmt = Mathf.Max(AmmoAmount, 60);
            entries.Add(new LootUI.BoxEntry
            {
                Section = "MAGAZINE",
                Title = Caliber.ToUpperInvariant() + " AMMO x" + ammoAmt,
                Desc = ammoAmt + " rounds",
                Tier = Rarity.Common,
                Icon = LootIconKind.Ammo,
                Take = () =>
                {
                    var gb = pc.GetComponentInChildren<GunBehaviour>();
                    if (gb == null) gb = pc.GetComponentInParent<GunBehaviour>();
                    if (gb != null) gb.AddAmmo(LootPickup.CaliberToAmmo(Caliber), ammoAmt);
                }
            });

            // Medicine: random bonus (health / armor / shard / grenade / cash).
            var rng = new System.Random();
            double r = rng.NextDouble();
            if (r < 0.30)
            {
                entries.Add(new LootUI.BoxEntry
                {
                    Section = "Medicine", Title = "Armor Plates",
                    Desc = "Armor Repair — increases HP by 50",
                    Tier = Rarity.Uncommon, Icon = LootIconKind.Armor,
                    Take = () => pc.AddArmorPlate()
                });
            }
            else if (r < 0.48)
            {
                entries.Add(new LootUI.BoxEntry
                {
                    Section = "Medicine", Title = "Armor Shard",
                    Desc = "Armor Repair — increases HP by 50",
                    Tier = Rarity.Rare, Icon = LootIconKind.Armor,
                    Take = () => pc.AddArmorPlate()
                });
            }
            else if (r < 0.66)
            {
                entries.Add(new LootUI.BoxEntry
                {
                    Section = "Medicine", Title = "Medkit",
                    Desc = "Restores 40 HP",
                    Tier = Rarity.Common, Icon = LootIconKind.Health,
                    Take = () => pc.Heal(40)
                });
            }
            else if (r < 0.84)
            {
                entries.Add(new LootUI.BoxEntry
                {
                    Section = "Medicine", Title = "Frag Grenade",
                    Desc = "Throwable explosive",
                    Tier = Rarity.Common, Icon = LootIconKind.Frag,
                    Take = () => pc.AddGrenades(1)
                });
            }
            else
            {
                entries.Add(new LootUI.BoxEntry
                {
                    Section = "Medicine", Title = "Cash $200",
                    Desc = "Spend at buy stations",
                    Tier = Rarity.Common, Icon = LootIconKind.Cash,
                    Take = () => { if (LootPickup.OnCashCollected != null) LootPickup.OnCashCollected(200); }
                });
            }

            if (LootUI.Instance != null)
                LootUI.Instance.ShowBox(VictimName.ToUpperInvariant() + "'S PACK", entries);
        }

        /// <summary>Called by the match when the player pings this box.</summary>
        public void Ping()
        {
            LootPing.Spawn("DEATH BOX", Rarity.Uncommon, transform.position);
            LootAudio.PlayAt(LootAudio.PingClip(), transform.position);
        }
    }
}
