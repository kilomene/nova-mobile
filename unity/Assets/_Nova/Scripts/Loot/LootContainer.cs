using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Arsenal;
using NovaMobile.Core;
using NovaMobile.Player;
using NovaMobile.World;

namespace NovaMobile.Loot
{
    /// <summary>
    /// Searchable container inside buildings: drawer, crate, shelf, weapon rack,
    /// fridge, med-box. Touch to search -> open animation -> loot pops out.
    /// Contents follow room logic (kitchen = health, bedroom = armor/ammo,
    /// garage = attachments, armory = guns). One search per match.
    /// Ported from loot_container.gd.
    /// </summary>
    [RequireComponent(typeof(SphereCollider))]
    public class LootContainer : MonoBehaviour
    {
        public static readonly string[] CTypes =
            { "drawer", "crate", "shelf", "rack", "fridge", "medbox" };

        public string CType = "crate";
        /// <summary>kitchen | bedroom | garage | armory | general</summary>
        public string Room = "general";
        public int Tier = 1;

        private bool _opened;
        private Transform _lid;
        private TextMesh _label;
        private float _t;
        private readonly System.Random _rng = new System.Random();

        public static LootContainer Make(string ctype, string room, int tier)
        {
            var go = new GameObject("Container_" + ctype);
            var c = go.AddComponent<LootContainer>();
            c.CType = ctype;
            c.Room = room;
            c.Tier = Mathf.Clamp(tier, 0, 6);
            return c;
        }

        private void Awake()
        {
            var col = GetComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 1.4f;
            Build();
        }

        private void Update()
        {
            if (_opened || _label == null) return;
            _t += Time.deltaTime;
            Vector3 p = _label.transform.localPosition;
            p.y = 1.35f + Mathf.Sin(_t * 2.5f) * 0.06f;
            _label.transform.localPosition = p;
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_opened) return;
            var pc = other.GetComponentInParent<PlayerController>();
            if (pc == null || !pc.IsAlive) return;
            Open();
        }

        // ---------------- construction ----------------

        private static Material CMat(Color c, float rough = 0.7f, float metal = 0f, float emit = 0f)
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

        private void Box(Vector3 size, Vector3 pos, Material mat, Transform parent = null)
        {
            var go = MeshBuilder.BuildObject("c",
                new List<MeshBuilder.Part> { MeshBuilder.Box(size, Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one)) }, mat);
            go.transform.SetParent(parent != null ? parent : transform, false);
        }

        private void Build()
        {
            Material wood = CMat(new Color(0.45f, 0.33f, 0.20f));
            Material woodDark = CMat(new Color(0.32f, 0.23f, 0.14f));
            Material metal = CMat(new Color(0.45f, 0.47f, 0.50f), 0.4f, 0.6f);
            Material white = CMat(new Color(0.88f, 0.89f, 0.90f), 0.5f);
            Material accent = CMat(LootTable.RarityColor((Rarity)Mathf.Max(Tier, 2)), 0.5f, 0f, 0.8f);

            switch (CType)
            {
                case "drawer":
                    Box(new Vector3(0.9f, 0.7f, 0.5f), new Vector3(0f, 0.35f, 0f), wood);
                    _lid = new GameObject("DrawerFront").transform;
                    _lid.SetParent(transform, false);
                    _lid.localPosition = new Vector3(0f, 0.45f, 0.26f);
                    Box(new Vector3(0.7f, 0.22f, 0.04f), Vector3.zero, woodDark, _lid);
                    Box(new Vector3(0.12f, 0.03f, 0.03f), new Vector3(0f, 0f, 0.03f), metal, _lid);
                    break;
                case "fridge":
                    Box(new Vector3(0.7f, 1.5f, 0.6f), new Vector3(0f, 0.75f, 0f), white);
                    _lid = new GameObject("FridgeDoor").transform;
                    _lid.SetParent(transform, false);
                    _lid.localPosition = new Vector3(-0.35f, 0.75f, 0.30f);
                    Box(new Vector3(0.7f, 1.5f, 0.05f), new Vector3(0.35f, 0f, 0f), CMat(new Color(0.80f, 0.82f, 0.84f), 0.45f), _lid);
                    Box(new Vector3(0.04f, 0.5f, 0.04f), new Vector3(0.30f, 0.75f, 0.34f), metal);
                    break;
                case "rack":
                    Box(new Vector3(0.08f, 1.1f, 0.08f), new Vector3(-0.55f, 0.55f, 0f), woodDark);
                    Box(new Vector3(0.08f, 1.1f, 0.08f), new Vector3(0.55f, 0.55f, 0f), woodDark);
                    Box(new Vector3(1.2f, 0.08f, 0.08f), new Vector3(0f, 1.0f, 0f), woodDark);
                    Box(new Vector3(1.2f, 0.06f, 0.4f), new Vector3(0f, 0.03f, 0f), wood);
                    _lid = new GameObject("RackBar").transform;
                    _lid.SetParent(transform, false);
                    Box(new Vector3(1.2f, 0.05f, 0.05f), new Vector3(0f, 1.06f, 0f), accent, _lid);
                    break;
                case "shelf":
                    Box(new Vector3(0.06f, 1.3f, 0.4f), new Vector3(-0.5f, 0.65f, 0f), wood);
                    Box(new Vector3(0.06f, 1.3f, 0.4f), new Vector3(0.5f, 0.65f, 0f), wood);
                    Box(new Vector3(1.05f, 0.06f, 0.4f), new Vector3(0f, 0.45f, 0f), wood);
                    Box(new Vector3(1.05f, 0.06f, 0.4f), new Vector3(0f, 0.9f, 0f), wood);
                    Box(new Vector3(1.05f, 0.06f, 0.45f), new Vector3(0f, 0.03f, 0f), woodDark);
                    _lid = new GameObject("ShelfTop").transform;
                    _lid.SetParent(transform, false);
                    Box(new Vector3(1.05f, 0.04f, 0.42f), new Vector3(0f, 1.32f, 0f), accent, _lid);
                    break;
                case "medbox":
                    Box(new Vector3(0.7f, 0.5f, 0.5f), new Vector3(0f, 0.25f, 0f), white);
                    Material red = CMat(new Color(0.85f, 0.10f, 0.12f), 0.5f, 0f, 0.5f);
                    Box(new Vector3(0.24f, 0.07f, 0.02f), new Vector3(0f, 0.28f, 0.26f), red);
                    Box(new Vector3(0.07f, 0.24f, 0.02f), new Vector3(0f, 0.28f, 0.26f), red);
                    _lid = new GameObject("MedboxLid").transform;
                    _lid.SetParent(transform, false);
                    _lid.localPosition = new Vector3(0f, 0.5f, -0.25f);
                    Box(new Vector3(0.7f, 0.06f, 0.5f), new Vector3(0f, 0.03f, 0.25f), white, _lid);
                    break;
                default: // wooden supply crate with flip lid
                    Box(new Vector3(0.8f, 0.55f, 0.6f), new Vector3(0f, 0.28f, 0f), wood);
                    Box(new Vector3(0.84f, 0.08f, 0.64f), new Vector3(0f, 0.10f, 0f), woodDark);
                    Box(new Vector3(0.84f, 0.08f, 0.64f), new Vector3(0f, 0.45f, 0f), woodDark);
                    _lid = new GameObject("CrateLid").transform;
                    _lid.SetParent(transform, false);
                    _lid.localPosition = new Vector3(0f, 0.55f, -0.30f);
                    Box(new Vector3(0.8f, 0.08f, 0.6f), new Vector3(0f, 0.04f, 0.30f), wood, _lid);
                    Box(new Vector3(0.82f, 0.03f, 0.1f), new Vector3(0f, 0.09f, 0.30f), accent, _lid);
                    break;
            }

            // Tier accent strip + prompt label.
            Box(new Vector3(0.5f, 0.04f, 0.02f), new Vector3(0f, 0.06f, 0.32f), accent);
            var labelGo = new GameObject("SearchLabel");
            labelGo.transform.SetParent(transform, false);
            labelGo.transform.localPosition = new Vector3(0f, 1.35f, 0f);
            _label = labelGo.AddComponent<TextMesh>();
            _label.anchor = TextAnchor.MiddleCenter;
            _label.alignment = TextAlignment.Center;
            _label.characterSize = 0.06f;
            _label.fontSize = 48;
            _label.color = new Color(1f, 1f, 1f, 0.9f);
            _label.text = "SEARCH";
        }

        // ---------------- opening ----------------

        public void Open()
        {
            if (_opened) return;
            _opened = true;
            GetComponent<SphereCollider>().enabled = false;
            if (_label != null) _label.gameObject.SetActive(false);
            LootAudio.PlayAt(LootAudio.OpenClip(), transform.position);
            StartCoroutine(OpenRoutine());
        }

        private IEnumerator OpenRoutine()
        {
            if (_lid != null)
            {
                float dur = 0.45f;
                float e = 0f;
                Vector3 startPos = _lid.localPosition;
                Vector3 startRot = _lid.localEulerAngles;
                while (e < dur)
                {
                    e += Time.deltaTime;
                    float k = Mathf.Clamp01(e / dur);
                    // Ease-out-back-ish overshoot.
                    float ok = 1f + 1.4f * Mathf.Pow(k - 1f, 3f) + 0.4f * Mathf.Pow(k - 1f, 2f);
                    switch (CType)
                    {
                        case "drawer":
                            _lid.localPosition = startPos + new Vector3(0f, 0f, 0.29f * ok);
                            break;
                        case "fridge":
                            _lid.localEulerAngles = startRot + new Vector3(0f, -109f * ok, 0f);
                            break;
                        case "rack":
                        case "shelf":
                            _lid.localPosition = startPos + new Vector3(0f, 0.35f * ok, 0f);
                            break;
                        default:
                            _lid.localEulerAngles = startRot + new Vector3(-106f * ok, 0f, 0f);
                            break;
                    }
                    yield return null;
                }
            }
            yield return new WaitForSeconds(0.15f);
            SpawnContents();
        }

        // ---------------- room-logic contents ----------------

        private struct Rolled
        {
            public LootItem Item;
            public string GunId;
            public int GunTier;
            public string Caliber;
            public string AttachId;
            public bool IsGun;
            public bool IsAttach;
        }

        private void SpawnContents()
        {
            int n = 2 + _rng.Next(2); // 2-3 items
            for (int i = 0; i < n; i++)
            {
                Rolled r = RollOne();
                float ang = Mathf.PI * 2f * i / Mathf.Max(n, 1);
                Vector3 pos = transform.position + new Vector3(Mathf.Cos(ang) * 1.1f, 0.35f, Mathf.Sin(ang) * 1.1f);
                if (r.IsGun)
                    LootSpawner.SpawnGun(r.GunId, r.GunTier, pos);
                else if (r.IsAttach)
                    LootSpawner.SpawnAttachment(r.AttachId, pos);
                else
                    LootSpawner.SpawnLoot(r.Item, pos, r.Caliber);
            }
        }

        private Rolled RollOne()
        {
            var r = new Rolled();
            int t = Mathf.Clamp(Tier + _rng.Next(2), 0, 5);
            Rarity rt = (Rarity)t;
            double roll = _rng.NextDouble();
            switch (Room)
            {
                case "kitchen":
                    if (roll < 0.7)
                    {
                        r.Item = new LootItem(LootKind.Health, (Rarity)Mathf.Min(t, 3), 40 + 20 * t);
                    }
                    else r.Item = new LootItem(LootKind.Cash, rt, 150 + 100 * t);
                    break;
                case "bedroom":
                    if (roll < 0.4)
                        r.Item = new LootItem(LootKind.Armor, rt, 1);
                    else if (roll < 0.75)
                    {
                        r.Item = new LootItem(LootKind.Ammo, rt, 60);
                        r.Caliber = PickCaliber();
                    }
                    else r.Item = new LootItem(LootKind.Cash, rt, 120 + 80 * t);
                    break;
                case "garage":
                    if (roll < 0.45)
                    {
                        r.IsAttach = true;
                        r.AttachId = AttachmentData.AttachLoot[_rng.Next(AttachmentData.AttachLoot.Length)];
                    }
                    else
                    {
                        r.Item = new LootItem(LootKind.Ammo, rt, 60);
                        r.Caliber = PickCaliber();
                    }
                    break;
                case "armory":
                    if (roll < 0.5)
                    {
                        r.IsGun = true;
                        r.GunTier = Mathf.Min(t + 1, 5);
                        r.GunId = GunData.RollGun(r.GunTier, _rng);
                    }
                    else
                    {
                        r.Item = new LootItem(LootKind.Ammo, rt, 90);
                        r.Caliber = PickCaliber();
                    }
                    break;
                default:
                    if (roll < 0.3)
                        r.Item = new LootItem(LootKind.Health, rt, 40);
                    else if (roll < 0.55)
                    {
                        r.Item = new LootItem(LootKind.Ammo, rt, 60);
                        r.Caliber = PickCaliber();
                    }
                    else if (roll < 0.7)
                        r.Item = new LootItem(LootKind.Armor, rt, 1);
                    else if (roll < 0.85)
                        r.Item = new LootItem(LootKind.Cash, rt, 100 + 60 * t);
                    else r.Item = new LootItem(LootKind.Frag, rt, 1);
                    break;
            }
            if (r.Caliber == null) r.Caliber = "medium";
            return r;
        }

        private string PickCaliber()
        {
            return LootTable.RollCaliber(_rng);
        }

        /// <summary>Called by the match when the player pings this container.</summary>
        public void Ping()
        {
            LootPing.Spawn("CONTAINER", (Rarity)Mathf.Clamp(Tier, 0, 6), transform.position);
            LootAudio.PlayAt(LootAudio.PingClip(), transform.position);
        }

        /// <summary>Archetype -> room mapping for BuildingFactory buildings.</summary>
        public static string RoomFor(BuildingArchetype arch)
        {
            switch (arch)
            {
                case BuildingArchetype.House: return "bedroom";
                case BuildingArchetype.Shop: return "general";
                case BuildingArchetype.Warehouse: return "garage";
                case BuildingArchetype.Tower: return "armory";
                default: return "general";
            }
        }
    }
}
