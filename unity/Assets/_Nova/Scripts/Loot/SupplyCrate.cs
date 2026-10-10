using System.Collections;
using UnityEngine;
using NovaMobile.Arsenal;
using NovaMobile.Core;
using NovaMobile.Player;

namespace NovaMobile.Loot
{
    /// <summary>
    /// Openable supply crate in 3 tiers: 0 standard (green), 1 rare (blue),
    /// 2 epic (orange). Touch to open -> lid flips -> loot burst flies out ->
    /// light-beam pillar for rare/epic (visible across the map, CODM-style).
    /// Respawns closed after 90 s. Ported from loot_crate.gd.
    /// </summary>
    [RequireComponent(typeof(SphereCollider))]
    public class SupplyCrate : MonoBehaviour
    {
        public const float RespawnDelay = 90f;

        public static readonly Color[] TierTints = new Color[]
        {
            new Color(0.25f, 0.90f, 0.45f),
            new Color(0.35f, 0.60f, 1.00f),
            new Color(1.00f, 0.60f, 0.15f),
        };
        public static readonly string[] TierLabels = { "SUPPLY", "RARE SUPPLY", "EPIC SUPPLY" };

        public int Tier;

        private bool _opened;
        private Transform _lid;
        private GameObject _beam;
        private TextMesh _label;
        private float _t;
        private float _respawnLeft;
        private readonly System.Random _rng = new System.Random();

        public static SupplyCrate Make(int tier)
        {
            var go = new GameObject("SupplyCrate_T" + Mathf.Clamp(tier, 0, 2));
            var c = go.AddComponent<SupplyCrate>();
            c.Tier = Mathf.Clamp(tier, 0, 2);
            return c;
        }

        private void Awake()
        {
            var col = GetComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 1.6f;
            Build();
        }

        private static Material CMat(Color c, float rough = 0.6f, float metal = 0.1f, float emit = 0f)
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

        private void AddBox(Transform parent, Vector3 size, Vector3 pos, Material mat)
        {
            var go = MeshBuilder.BuildObject("c",
                new System.Collections.Generic.List<MeshBuilder.Part>
                { MeshBuilder.Box(size, Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one)) }, mat);
            go.transform.SetParent(parent, false);
        }

        private void Build()
        {
            Color tint = TierTints[Tier];
            Material body = CMat(new Color(0.30f, 0.28f, 0.24f));
            Material trim = CMat(tint, 0.5f, 0f, 1.4f);
            float s = 0.9f + 0.25f * Tier;
            AddBox(transform, new Vector3(s, s * 0.7f, s), new Vector3(0f, s * 0.35f, 0f), body);
            AddBox(transform, new Vector3(s + 0.06f, 0.10f, s + 0.06f), new Vector3(0f, 0.08f, 0f), body);
            AddBox(transform, new Vector3(s + 0.02f, 0.06f, 0.08f), new Vector3(0f, s * 0.35f, s * 0.5f), trim);
            AddBox(transform, new Vector3(s + 0.02f, 0.06f, 0.08f), new Vector3(0f, s * 0.35f, -s * 0.5f), trim);

            _lid = new GameObject("Lid").transform;
            _lid.SetParent(transform, false);
            _lid.localPosition = new Vector3(0f, s * 0.7f, -s * 0.5f);
            AddBox(_lid, new Vector3(s, 0.10f, s), new Vector3(0f, 0.05f, s * 0.5f), body);
            AddBox(_lid, new Vector3(s * 0.5f, 0.04f, 0.12f), new Vector3(0f, 0.12f, s * 0.5f), trim);

            if (Tier >= 1)
            {
                _beam = LootModels.RarityBeam(Tier == 1 ? Rarity.Rare : Rarity.Legendary);
                _beam.transform.SetParent(transform, false);
                _beam.transform.localPosition = new Vector3(0f, s * 0.7f, 0f);
            }

            var labelGo = new GameObject("Label");
            labelGo.transform.SetParent(transform, false);
            labelGo.transform.localPosition = new Vector3(0f, s + 0.9f, 0f);
            _label = labelGo.AddComponent<TextMesh>();
            _label.anchor = TextAnchor.MiddleCenter;
            _label.alignment = TextAlignment.Center;
            _label.characterSize = 0.06f;
            _label.fontSize = 56;
            _label.color = tint;
            _label.text = TierLabels[Tier];
        }

        private void Update()
        {
            if (_opened)
            {
                _respawnLeft -= Time.deltaTime;
                if (_respawnLeft <= 0f) Reset();
                return;
            }
            _t += Time.deltaTime;
            if (_beam != null)
                _beam.transform.Rotate(0f, 0.8f * Time.deltaTime * Mathf.Rad2Deg, 0f);
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_opened) return;
            var pc = other.GetComponentInParent<PlayerController>();
            if (pc == null || !pc.IsAlive) return;
            Open();
        }

        public void Open()
        {
            if (_opened) return;
            _opened = true;
            _respawnLeft = RespawnDelay;
            GetComponent<SphereCollider>().enabled = false;
            if (_label != null) _label.gameObject.SetActive(false);
            if (_beam != null) _beam.SetActive(false);
            LootAudio.PlayAt(LootAudio.CrateClip(Tier), transform.position);
            StartCoroutine(LidRoutine());
        }

        private IEnumerator LidRoutine()
        {
            float dur = 0.45f, e = 0f;
            while (e < dur)
            {
                e += Time.deltaTime;
                float k = Mathf.Clamp01(e / dur);
                float ok = 1f + 1.4f * Mathf.Pow(k - 1f, 3f) + 0.4f * Mathf.Pow(k - 1f, 2f);
                _lid.localEulerAngles = new Vector3(-126f * ok, 0f, 0f);
                yield return null;
            }
            yield return new WaitForSeconds(0.1f);
            Burst();
        }

        private void Burst()
        {
            int n = 3 + Tier; // 3/4/5 items
            for (int i = 0; i < n; i++)
            {
                LootItem item = RollOne();
                float ang = Mathf.PI * 2f * i / n + (float)_rng.NextDouble() * 0.5f;
                float rad = 1.2f + 0.4f * Tier;
                Vector3 pos = transform.position + new Vector3(Mathf.Cos(ang) * rad, 0.4f, Mathf.Sin(ang) * rad);
                LootSpawner.SpawnLoot(item, pos, "medium");
            }
            if (Tier == 2)
            {
                // Epic always drops a tier-5 gun + scorestreak + armor.
                string gid = GunData.RollGun(5, _rng);
                LootSpawner.SpawnGun(gid, 5, transform.position + new Vector3(0f, 0.4f, -1.6f));
                string skind = _rng.NextDouble() < 0.5 ? "uav" : "strike";
                LootSpawner.SpawnLoot(new LootItem(LootKind.Scorestreak, Rarity.Legendary), transform.position + new Vector3(0.8f, 0.4f, 1.2f), "medium", skind);
                LootSpawner.SpawnLoot(new LootItem(LootKind.Shard, Rarity.Epic, 2), transform.position + new Vector3(-0.8f, 0.4f, 1.2f));
            }
        }

        private LootItem RollOne()
        {
            int t = Mathf.Clamp(1 + Tier + _rng.Next(2), 0, 5);
            Rarity rt = (Rarity)t;
            double r = _rng.NextDouble();
            if (r < 0.25) return new LootItem(LootKind.Health, rt, 60);
            if (r < 0.45) return new LootItem(LootKind.Armor, rt, 2);
            if (r < 0.65) return new LootItem(LootKind.Ammo, rt, 90);
            if (r < 0.78) return new LootItem(LootKind.Cash, rt, 300 + 200 * Tier);
            if (r < 0.88) return new LootItem(LootKind.Frag, rt, 2);
            var item = new LootItem(LootKind.Attachment, Rarity.Rare);
            item.AttachmentId = AttachmentData.AttachLoot[_rng.Next(AttachmentData.AttachLoot.Length)];
            if (_rng.NextDouble() < 0.5) return item;
            return new LootItem(LootKind.Smoke, rt, 2);
        }

        private void Reset()
        {
            _opened = false;
            GetComponent<SphereCollider>().enabled = true;
            if (_lid != null) _lid.localEulerAngles = Vector3.zero;
            if (_label != null) _label.gameObject.SetActive(true);
            if (_beam != null) _beam.SetActive(true);
        }

        /// <summary>Called by the match when the player pings this crate.</summary>
        public void Ping()
        {
            LootPing.Spawn("SUPPLY CRATE", Rarity.Uncommon, transform.position);
            LootAudio.PlayAt(LootAudio.PingClip(), transform.position);
        }
    }
}
