using System;
using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Economy
{
    /// <summary>
    /// BR airdrop system — ported from the airdrop events in Godot main.gd:
    /// random marked locations near POIs, a warning banner 12s before the
    /// plane arrives, a simple-mesh flyover, parachuted crate, tall colored
    /// smoke column, minimap marker hook, and tier-5 loot on landing.
    /// Late-game matches get extra simultaneous drops (mirrors Godot's
    /// phase >= 2 / phase >= 4 extra drops via elapsed match time).
    ///
    /// Hooks:
    ///   DropWarned(poiName)        — HUD warning banner ("⚠ AIRDROP INCOMING — X")
    ///   DropLaunched(Vector3)      — plane released (minimap sweep, SFX)
    ///   DropLanded(Vector3)        — minimap orange crate marker
    ///   LootSpawnRequested(payload)— Loot system spawns the tier-5 items; if no
    ///                                subscriber, Airdrop spawns simple fallback
    ///                                pickups itself (no silent no-loot).
    ///   TankDropLanded(Vector3)    — Vehicles system spawns the dropped tank
    ///                                (from the buy-station $10000 marker).
    ///
    /// BuyStation.TankDropRequested is subscribed automatically on enable.
    /// </summary>
    public struct AirdropLootItem
    {
        public string Kind;    // "health" | "armor" | "ammo" | "gun"
        public int Amount;
        public string GunId;   // gun pickups
        public int Tier;        // always 5 for airdrops

        public AirdropLootItem(string kind, int amount, string gunId, int tier)
        {
            Kind = kind; Amount = amount; GunId = gunId; Tier = tier;
        }
    }

    public struct AirdropPayload
    {
        public Vector3 Position;
        public AirdropLootItem[] Items;
    }

    public class Airdrop : MonoBehaviour
    {
        public const float FirstDropAt = 75f;      // seconds into the match
        public const float DropInterval = 80f;     // between drop waves
        public const float WarnLeadTime = 12f;     // banner before release
        public const float DropAltitude = 130f;
        public const float DescentSpeed = 14f;
        public const float SmokeLifetime = 60f;

        public static event Action<string> DropWarned;
        public static event Action<Vector3> DropLaunched;
        public static event Action<Vector3> DropLanded;
        public static event Action<AirdropPayload> LootSpawnRequested;
        public static event Action<Vector3> TankDropLanded;

        private class ActiveDrop
        {
            public GameObject Node;
            public GameObject Chute;
            public GameObject Smoke;
            public string Payload;   // "loot" | "tank"
            public bool Landed;
            public float SmokeTimer;
        }

        private readonly List<ActiveDrop> _drops = new List<ActiveDrop>();
        private readonly List<Vector3> _pending = new List<Vector3>();
        private readonly List<string> _pendingNames = new List<string>();
        private float _timer = FirstDropAt;
        private float _elapsed;
        private bool _warned;
        private System.Random _rng = new System.Random();
        private static Airdrop _instance;

        public static Airdrop Instance
        {
            get { return _instance; }
        }

        public int ActiveDropCount
        {
            get { return _drops.Count; }
        }

        private void Awake()
        {
            _instance = this;
            BuyStation.TankDropRequested += OnTankDropRequested;
        }

        private void OnDestroy()
        {
            BuyStation.TankDropRequested -= OnTankDropRequested;
            if (_instance == this) _instance = null;
        }

        /// <summary>Buy-station tank-drop marker: a tank airdropped nearby.</summary>
        private void OnTankDropRequested(Vector3 nearPos)
        {
            Vector3 p = nearPos + new Vector3(6f, DropAltitude, 6f);
            LaunchDrop(p, "tank");
        }

        private void Update()
        {
            float dt = Time.deltaTime;
            _elapsed += dt;
            _timer -= dt;

            if (_timer <= WarnLeadTime && !_warned)
            {
                _warned = true;
                PlanDrops();
            }
            if (_timer <= 0f)
            {
                _warned = false;
                _timer = DropInterval;
                for (int i = 0; i < _pending.Count; i++)
                    LaunchDrop(_pending[i], "loot");
                _pending.Clear();
                _pendingNames.Clear();
            }

            for (int i = _drops.Count - 1; i >= 0; i--)
            {
                ActiveDrop ad = _drops[i];
                if (ad.Landed)
                {
                    ad.SmokeTimer -= dt;
                    if (ad.SmokeTimer <= 0f)
                    {
                        if (ad.Smoke != null) Destroy(ad.Smoke);
                        _drops.RemoveAt(i);
                    }
                    continue;
                }
                ad.Node.transform.position -= new Vector3(0, DescentSpeed * dt, 0);
                float gy = GroundY(ad.Node.transform.position);
                if (ad.Node.transform.position.y <= gy + 0.9f)
                {
                    Vector3 p = ad.Node.transform.position;
                    p.y = gy + 0.9f;
                    ad.Node.transform.position = p;
                    ad.Landed = true;
                    if (ad.Chute != null) Destroy(ad.Chute);
                    DustBurst(p);
                    if (ad.Payload == "tank")
                    {
                        if (TankDropLanded != null) TankDropLanded(p);
                    }
                    else
                    {
                        SpawnAirdropLoot(p);
                    }
                    if (DropLanded != null) DropLanded(p);
                    ad.SmokeTimer = SmokeLifetime;
                }
            }
        }

        // ------------------------------------------------------------- planning

        private void PlanDrops()
        {
            _pending.Clear();
            _pendingNames.Clear();
            // Godot: 1 drop, +1 at zone phase 2, +1 at phase 4. Elapsed-time
            // mapping: extra drops at 4 and 8 minutes of match time.
            int count = 1;
            if (_elapsed >= 240f) count++;
            if (_elapsed >= 480f) count++;
            var pois = NovaMobile.World.WorldData.Pois;
            if (pois == null || pois.Length == 0) return;
            var used = new HashSet<string>();
            for (int i = 0; i < count; i++)
            {
                int pi = _rng.Next(0, pois.Length);
                var poi = pois[pi];
                if (used.Contains(poi.Name)) continue;
                used.Add(poi.Name);
                Vector3 pp = poi.Position;
                _pending.Add(new Vector3(
                    pp.x + (float)(_rng.NextDouble() * 24.0 - 12.0),
                    DropAltitude,
                    pp.z + (float)(_rng.NextDouble() * 24.0 - 12.0)));
                _pendingNames.Add(poi.Name);
                if (DropWarned != null) DropWarned(poi.Name);
            }
        }

        // -------------------------------------------------------------- launch

        /// <summary>Launch a drop at an explicit position (also used for tank drops).</summary>
        public void LaunchDrop(Vector3 dropPos, string payload)
        {
            // Flyover plane: crosses the sky, releases the crate mid-pass.
            var plane = new GameObject("DropPlane");
            var fus = GameObject.CreatePrimitive(PrimitiveType.Cube);
            fus.transform.SetParent(plane.transform, false);
            fus.transform.localScale = new Vector3(2f, 2f, 9f);
            var fmat = new Material(Shader.Find("Standard"));
            fmat.color = new Color(0.25f, 0.26f, 0.28f);
            fus.GetComponent<Renderer>().sharedMaterial = fmat;
            var wings = GameObject.CreatePrimitive(PrimitiveType.Cube);
            wings.transform.SetParent(plane.transform, false);
            wings.transform.localScale = new Vector3(14f, 0.4f, 2.2f);
            wings.GetComponent<Renderer>().sharedMaterial = fmat;

            Vector3 start = dropPos + new Vector3(-260f, 0f, 60f);
            Vector3 end = dropPos + new Vector3(260f, 0f, -60f);
            plane.transform.position = start;
            var fly = plane.AddComponent<PlaneFlyover>();
            fly.Init(start, end, 13f);

            var releaser = gameObject.AddComponent<DelayedCall>();
            releaser.Init(5.2f, () => ReleaseCrate(dropPos, payload));
            if (DropLaunched != null) DropLaunched(dropPos);
        }

        private void ReleaseCrate(Vector3 dropPos, string payload)
        {
            var crate = new GameObject("AirdropCrate");
            var body = GameObject.CreatePrimitive(PrimitiveType.Cube);
            body.transform.SetParent(crate.transform, false);
            body.transform.localScale = new Vector3(1.6f, 1.6f, 1.6f);
            var cmat = new Material(Shader.Find("Standard"));
            cmat.color = new Color(0.85f, 0.45f, 0.1f);
            cmat.EnableKeyword("_EMISSION");
            cmat.SetColor("_EmissionColor", new Color(0.85f, 0.45f, 0.1f) * 0.4f);
            body.GetComponent<Renderer>().sharedMaterial = cmat;
            crate.transform.position = dropPos;

            // Parachute canopy above the crate.
            var chute = GameObject.CreatePrimitive(PrimitiveType.Cube);
            chute.transform.SetParent(crate.transform, false);
            chute.transform.localScale = new Vector3(4.5f, 0.25f, 4.5f);
            chute.transform.localPosition = new Vector3(0, 3.2f, 0);
            var chmat = new Material(Shader.Find("Standard"));
            chmat.color = new Color(0.9f, 0.88f, 0.82f);
            chute.GetComponent<Renderer>().sharedMaterial = chmat;

            // Tall smoke column marks the drop (visible across the world).
            var smoke = new GameObject("DropSmoke");
            smoke.transform.position = new Vector3(dropPos.x, 35f, dropPos.z);
            var col = smoke.AddComponent<MeshFilter>();
            var cyl = new Mesh();
            BuildCylinder(cyl, 1.2f, 2.2f, 70f, 12);
            col.mesh = cyl;
            var mr = smoke.AddComponent<MeshRenderer>();
            var smat = new Material(Shader.Find("Unlit/Transparent"));
            smat.color = new Color(1.0f, 0.45f, 0.1f, 0.45f);
            mr.sharedMaterial = smat;

            _drops.Add(new ActiveDrop
            {
                Node = crate,
                Chute = chute,
                Smoke = smoke,
                Payload = payload,
                Landed = false,
            });
        }

        // ---------------------------------------------------------------- loot

        private void SpawnAirdropLoot(Vector3 pos)
        {
            // Airdrops always pack a heavy weapon — usually the RP-7.
            string gid = _rng.NextDouble() < 0.6 ? "rp7"
                : NovaMobile.Arsenal.GunData.RollGun(5, _rng);
            var payload = new AirdropPayload
            {
                Position = pos,
                Items = new AirdropLootItem[]
                {
                    new AirdropLootItem("health", 100, "", 5),
                    new AirdropLootItem("armor", 100, "", 5),
                    new AirdropLootItem("ammo", 120, "", 5),
                    new AirdropLootItem("gun", 1, gid, 5),
                },
            };
            if (LootSpawnRequested != null)
            {
                LootSpawnRequested(payload);
            }
            else
            {
                // Fallback: visible rarity-colored pickups so a landed crate
                // never sits empty when the Loot system isn't hooked yet.
                SpawnFallbackPickups(payload);
            }
        }

        private void SpawnFallbackPickups(AirdropPayload payload)
        {
            for (int i = 0; i < payload.Items.Length; i++)
            {
                var item = payload.Items[i];
                float ang = Mathf.PI * 2f * i / payload.Items.Length;
                Vector3 p = payload.Position + new Vector3(Mathf.Cos(ang) * 2.5f, 0.6f, Mathf.Sin(ang) * 2.5f);
                var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
                go.transform.position = p;
                go.transform.localScale = new Vector3(0.7f, 0.7f, 0.7f);
                var mat = new Material(Shader.Find("Standard"));
                mat.color = new Color(1.0f, 0.6f, 0.1f);
                mat.EnableKeyword("_EMISSION");
                mat.SetColor("_EmissionColor", new Color(1.0f, 0.6f, 0.1f) * 0.8f);
                go.GetComponent<Renderer>().sharedMaterial = mat;
                var pickup = go.AddComponent<AirdropPickup>();
                pickup.Init(item);
                var col = go.GetComponent<Collider>();
                if (col != null) col.isTrigger = true;
            }
        }

        private void DustBurst(Vector3 pos)
        {
            var dust = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            dust.transform.position = pos + new Vector3(0, 0.7f, 0);
            var dmat = new Material(Shader.Find("Unlit/Transparent"));
            dmat.color = new Color(0.75f, 0.68f, 0.55f, 0.55f);
            dust.GetComponent<Renderer>().sharedMaterial = dmat;
            var fx = dust.AddComponent<ExpandFade>();
            fx.Init(new Vector3(6f, 1.6f, 6f), 0.7f);
        }

        private static float GroundY(Vector3 p)
        {
            // Flat-world approximation (mirrors Godot's ground snap when no
            // heightfield sample is available). Terrain-aware height sampling
            // can replace this when the World system exposes it.
            return 0f;
        }

        private static void BuildCylinder(Mesh m, float topR, float botR, float h, int seg)
        {
            var verts = new List<Vector3>();
            var tris = new List<int>();
            for (int i = 0; i <= seg; i++)
            {
                float a = Mathf.PI * 2f * i / seg;
                float c = Mathf.Cos(a), s = Mathf.Sin(a);
                verts.Add(new Vector3(c * botR, -h / 2f, s * botR));
                verts.Add(new Vector3(c * topR, h / 2f, s * topR));
            }
            for (int i = 0; i < seg; i++)
            {
                int b = i * 2;
                tris.Add(b); tris.Add(b + 2); tris.Add(b + 1);
                tris.Add(b + 1); tris.Add(b + 2); tris.Add(b + 3);
            }
            m.vertices = verts.ToArray();
            m.triangles = tris.ToArray();
            m.RecalculateNormals();
            m.RecalculateBounds();
        }

        // ------------------------------------------------------------- helpers

        /// <summary>Plane flyover tween (no DOTween dependency).</summary>
        private class PlaneFlyover : MonoBehaviour
        {
            private Vector3 _a, _b;
            private float _dur, _t;

            public void Init(Vector3 a, Vector3 b, float dur)
            {
                _a = a; _b = b; _dur = dur; _t = 0f;
            }

            private void Update()
            {
                _t += Time.deltaTime;
                float k = Mathf.Clamp01(_t / _dur);
                transform.position = Vector3.Lerp(_a, _b, k);
                if (k >= 1f) Destroy(gameObject);
            }
        }

        /// <summary>One-shot delayed callback (replaces Godot tweens/timers).</summary>
        private class DelayedCall : MonoBehaviour
        {
            private float _delay;
            private Action _cb;
            private bool _fired;

            public void Init(float delay, Action cb)
            {
                _delay = delay; _cb = cb;
            }

            private void Update()
            {
                if (_fired) return;
                _delay -= Time.deltaTime;
                if (_delay <= 0f)
                {
                    _fired = true;
                    if (_cb != null) _cb();
                    Destroy(this);
                }
            }
        }

        /// <summary>Expanding, fading dust ring on landing.</summary>
        private class ExpandFade : MonoBehaviour
        {
            private Vector3 _target;
            private float _dur, _t;
            private Material _mat;

            public void Init(Vector3 targetScale, float dur)
            {
                _target = targetScale; _dur = dur; _t = 0f;
                _mat = GetComponent<Renderer>().sharedMaterial;
            }

            private void Update()
            {
                _t += Time.deltaTime;
                float k = Mathf.Clamp01(_t / _dur);
                transform.localScale = Vector3.Lerp(Vector3.one, _target, k);
                if (_mat != null)
                {
                    Color c = _mat.color;
                    c.a = 0.55f * (1f - k);
                    _mat.color = c;
                }
                if (k >= 1f) Destroy(gameObject);
            }
        }

        /// <summary>
        /// Fallback world pickup (used only when the Loot system has not
        /// subscribed to LootSpawnRequested). Grants cash-equivalent credit
        /// into CashPurse on touch and despawns.
        /// </summary>
        private class AirdropPickup : MonoBehaviour
        {
            private AirdropLootItem _item;
            private float _t;

            public void Init(AirdropLootItem item) { _item = item; }

            private void Update()
            {
                _t += Time.deltaTime;
                transform.position += new Vector3(0, Mathf.Sin(_t * 3f) * 0.15f * Time.deltaTime, 0);
                transform.Rotate(0, 60f * Time.deltaTime, 0);
            }

            private void OnTriggerEnter(Collider other)
            {
                if (!other.CompareTag("Player")) return;
                switch (_item.Kind)
                {
                    case "gun":
                        // The Loot system owns gun pickups; credit cash as a
                        // stand-in so the fallback never dead-ends the player.
                        CashPurse.Earn(500, "airdrop gun pickup (fallback)");
                        break;
                    default:
                        CashPurse.Earn(100, "airdrop " + _item.Kind + " (fallback)");
                        break;
                }
                Destroy(gameObject);
            }
        }
    }
}
