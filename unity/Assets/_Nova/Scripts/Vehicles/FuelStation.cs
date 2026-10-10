using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Filling station POI (ports fuel_station.gd): canopy with NOVA FUEL branding
    /// (TextMesh signage + emissive band, neon flicker), exactly 3 explosive fuel
    /// pumps, enterable convenience store with loot spots, night lighting.
    /// Pumps and the station detonate when shot (chain explosions via AoE).
    /// Hold-to-refuel: a stopped, occupied vehicle near a live pump refuels over
    /// ~10s (driver is exposed while IsRefueling — the vulnerability tradeoff).
    /// </summary>
    public class FuelStation : MonoBehaviour, IVehicleDamageable
    {
        public event Action<FuelStation> StationDestroyed;

        public float Hp = 220f;
        public bool Destroyed { get; private set; }

        private readonly List<FuelPump> _pumps = new List<FuelPump>();
        private TextMesh _sign;
        private float _t;
        private Vector3[] _storeSpots = new Vector3[0];

        bool IVehicleDamageable.IsAlive { get { return !Destroyed; } }
        Transform IVehicleDamageable.Transform { get { return transform; } }
        void IVehicleDamageable.TakeDamage(float amount, Vector3 fromPos, string kind)
        {
            TakeDamage(amount);
        }

        public static FuelStation Spawn(Vector3 pos, float yawDeg = 0f)
        {
            var go = new GameObject("FuelStation");
            var st = go.AddComponent<FuelStation>();
            go.transform.position = pos;
            go.transform.rotation = Quaternion.Euler(0f, yawDeg, 0f);
            return st;
        }

        private void Awake()
        {
            Build();
            var col = gameObject.AddComponent<BoxCollider>();
            col.size = new Vector3(15f, 6f, 10.5f);
            col.center = new Vector3(0f, 3f, 0f);
        }

        public void TakeDamage(float amount)
        {
            if (Destroyed) return;
            Hp -= amount;
            if (Hp <= 0f)
            {
                Destroyed = true;
                if (StationDestroyed != null) StationDestroyed(this);
                VehicleEffects.Explode(transform.position + Vector3.up * 2f, 13f, 170f, this);
            }
        }

        public FuelPump NearestPump(Vector3 pos, float maxD)
        {
            FuelPump best = null;
            float bestD = maxD;
            for (int i = 0; i < _pumps.Count; i++)
            {
                FuelPump p = _pumps[i];
                if (p == null || p.Destroyed) continue;
                float d = Vector3.Distance(pos, p.transform.position);
                if (d < bestD) { bestD = d; best = p; }
            }
            return best;
        }

        public Vector3[] StoreLootSpots() { return _storeSpots; }

        /// <summary>
        /// Call every frame while a vehicle wants to refuel. Returns true while
        /// fuel is flowing. Vehicle must be stopped, occupied, and near a live pump.
        /// </summary>
        public bool TryRefuelTick(VehicleController v)
        {
            if (v == null || v.Destroyed || !v.IsOccupied || !v.Spec.UsesFuel)
            {
                if (v != null) v.IsRefueling = false;
                return false;
            }
            FuelPump pump = NearestPump(v.transform.position, 4.5f);
            if (pump == null || Mathf.Abs(v.Speed) > 0.5f || !v.NeedsFuel())
            {
                v.IsRefueling = false;
                return false;
            }
            v.IsRefueling = true; // vulnerable: stationary with driver inside
            v.AddFuel(v.Spec.FuelCapacity / 10f * Time.deltaTime); // ~10s for a full tank
            return true;
        }

        private void Update()
        {
            _t += Time.deltaTime;
            if (_sign != null && !Destroyed)
            {
                float f = 0.92f + 0.08f * Mathf.Sin(_t * 7f) * Mathf.Sin(_t * 3.1f);
                _sign.color = new Color(1f * f, 0.55f * f, 0.1f * f);
            }
        }

        // ------------------------------------------------------------ build
        private sealed class Acc
        {
            private readonly Transform _parent;
            private readonly Dictionary<string, List<MeshBuilder.Part>> _parts = new Dictionary<string, List<MeshBuilder.Part>>();
            public Acc(Transform parent) { _parent = parent; }
            public void Box(string mat, Vector3 size, Vector3 pos)
            {
                if (!_parts.TryGetValue(mat, out List<MeshBuilder.Part> l))
                {
                    l = new List<MeshBuilder.Part>();
                    _parts[mat] = l;
                }
                l.Add(MeshBuilder.Box(size, pos, Quaternion.identity));
            }
            public void Flush()
            {
                foreach (var kv in _parts)
                {
                    var go = MeshBuilder.BuildObject("Station_" + kv.Key, kv.Value, VehicleMats.Get(kv.Key));
                    go.transform.SetParent(_parent, false);
                }
                _parts.Clear();
            }
        }

        private Material MakeMat(Color c, float metallic, float smooth, Color emission, float energy)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = c;
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Glossiness", smooth);
            if (energy > 0f)
            {
                m.SetColor("_EmissionColor", emission * energy);
                m.EnableKeyword("_EMISSION");
            }
            return m;
        }

        private TextMesh MakeSign(string text, int fontSize, float charSize, Color color, Vector3 pos, float rotY)
        {
            var go = new GameObject("Sign_" + text);
            go.transform.SetParent(transform, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(0f, rotY, 0f);
            var tm = go.AddComponent<TextMesh>();
            tm.text = text;
            tm.font = Resources.GetBuiltinResource<Font>("Arial.ttf");
            tm.fontSize = fontSize;
            tm.characterSize = charSize;
            tm.anchor = TextAnchor.MiddleCenter;
            tm.color = color;
            return tm;
        }

        private void Build()
        {
            var acc = new Acc(transform);
            // Forecourt pad.
            acc.Box("deck_grey", new Vector3(18f, 0.2f, 13f), new Vector3(0f, 0.1f, 0f));
            // Canopy pillars + roof.
            for (int xi = 0; xi < 2; xi++)
                for (int zi = 0; zi < 2; zi++)
                {
                    float sx = xi == 0 ? -6.5f : 6.5f;
                    float sz = zi == 0 ? -4.5f : 4.5f;
                    acc.Box("metal_dark", new Vector3(0.45f, 5.2f, 0.45f), new Vector3(sx, 2.6f, sz));
                }
            acc.Box("metal_dark", new Vector3(15f, 0.35f, 10.5f), new Vector3(0f, 5.35f, 0f));
            acc.Box("glow_orange", new Vector3(15.2f, 0.5f, 10.7f), new Vector3(0f, 5.05f, 0f)); // brand band
            acc.Flush();

            // NOVA FUEL signs, both faces + price board.
            _sign = MakeSign("NOVA FUEL", 128, 0.02f, new Color(1f, 0.55f, 0.1f), new Vector3(0f, 6.3f, 0f), 0f);
            MakeSign("NOVA FUEL", 128, 0.02f, new Color(1f, 0.55f, 0.1f), new Vector3(0f, 6.3f, 0f), 180f);
            MakeSign("$4.20 / L", 64, 0.015f, new Color(0.4f, 1f, 0.5f), new Vector3(0f, 5.55f, 5.28f), 0f);

            // Exactly 3 pumps in a row.
            for (int i = 0; i < 3; i++)
            {
                var pumpGo = new GameObject("FuelPump_" + (i + 1));
                pumpGo.transform.SetParent(transform, false);
                pumpGo.transform.localPosition = new Vector3(-4.5f + i * 4.5f, 0.2f, 0f);
                var pump = pumpGo.AddComponent<FuelPump>();
                _pumps.Add(pump);
            }

            // Night lighting under the canopy.
            for (int li = 0; li < 2; li++)
            {
                float lx = li == 0 ? -4f : 4f;
                var go = new GameObject("CanopyLight");
                go.transform.SetParent(transform, false);
                go.transform.localPosition = new Vector3(lx, 4.8f, 0f);
                var light = go.AddComponent<Light>();
                light.type = LightType.Point;
                light.color = new Color(1f, 0.85f, 0.65f);
                light.intensity = 1.6f;
                light.range = 13f;
            }

            BuildStore(acc);
            acc.Flush();

            // Loot spots inside the store (world space).
            float sx0 = 11.5f;
            _storeSpots = new Vector3[]
            {
                transform.TransformPoint(new Vector3(sx0 - 2.2f, 0f, 0.4f)),
                transform.TransformPoint(new Vector3(sx0 + 1.6f, 0f, -1.4f)),
                transform.TransformPoint(new Vector3(sx0 + 0.5f, 0f, 1.5f)),
                transform.TransformPoint(new Vector3(sx0 - 1.0f, 0f, -1.8f)),
            };
        }

        private void BuildStore(Acc acc)
        {
            float sx = 11.5f;
            var wallm = MakeMat(new Color(0.75f, 0.72f, 0.66f), 0f, 0.2f, Color.black, 0f);
            var glassm = MakeMat(new Color(0.1f, 0.2f, 0.3f, 0.6f), 0f, 0.5f, new Color(1f, 0.8f, 0.5f), 0.7f);
            // Register custom mats under temp keys via a local dictionary trick:
            // (Acc only knows VehicleMats keys, so build store customs directly.)
            var customs = new Dictionary<Material, List<MeshBuilder.Part>>();
            Action<Material, Vector3, Vector3> cbox = (mat, size, pos) =>
            {
                if (!customs.TryGetValue(mat, out List<MeshBuilder.Part> l))
                {
                    l = new List<MeshBuilder.Part>();
                    customs[mat] = l;
                }
                l.Add(MeshBuilder.Box(size, pos, Quaternion.identity));
            };
            cbox(wallm, new Vector3(7f, 0.2f, 5.5f), new Vector3(sx, 0.1f, 0f));       // floor
            acc.Box("metal_dark", new Vector3(7.4f, 0.3f, 5.9f), new Vector3(sx, 3.2f, 0f)); // roof
            acc.Box("glow_orange", new Vector3(7.5f, 0.4f, 6.0f), new Vector3(sx, 2.95f, 0f)); // trim
            cbox(wallm, new Vector3(7f, 3.0f, 0.25f), new Vector3(sx, 1.6f, -2.6f));    // back
            cbox(wallm, new Vector3(0.25f, 3.0f, 5.5f), new Vector3(sx - 3.4f, 1.6f, 0f)); // left
            cbox(wallm, new Vector3(0.25f, 3.0f, 5.5f), new Vector3(sx + 3.4f, 1.6f, 0f)); // right
            cbox(wallm, new Vector3(2.7f, 3.0f, 0.25f), new Vector3(sx - 2.15f, 1.6f, 2.6f)); // front-left
            cbox(wallm, new Vector3(2.7f, 3.0f, 0.25f), new Vector3(sx + 2.15f, 1.6f, 2.6f)); // front-right (door gap)
            cbox(glassm, new Vector3(2.2f, 1.2f, 0.1f), new Vector3(sx - 2.15f, 1.8f, 2.62f)); // window
            var woodm = MakeMat(new Color(0.4f, 0.28f, 0.16f), 0f, 0.3f, Color.black, 0f);
            cbox(woodm, new Vector3(2.4f, 1.0f, 0.7f), new Vector3(sx + 1.6f, 0.7f, -1.4f)); // counter
            acc.Box("metal_dark", new Vector3(0.5f, 1.8f, 3.0f), new Vector3(sx - 2.6f, 1.1f, 0.4f)); // shelves
            acc.Box("metal_dark", new Vector3(0.5f, 1.8f, 3.0f), new Vector3(sx - 1.8f, 1.1f, 0.4f));
            foreach (var kv in customs)
            {
                var go = MeshBuilder.BuildObject("Store_custom", kv.Value, kv.Key);
                go.transform.SetParent(transform, false);
            }
            var lampGo = new GameObject("StoreLight");
            lampGo.transform.SetParent(transform, false);
            lampGo.transform.localPosition = new Vector3(sx, 2.8f, 0f);
            var lamp = lampGo.AddComponent<Light>();
            lamp.type = LightType.Point;
            lamp.color = new Color(1f, 0.9f, 0.7f);
            lamp.intensity = 1.2f;
            lamp.range = 8f;
        }

        // ------------------------------------------------------------ pump
        /// <summary>One explosive fuel pump (ports FuelPump inner class).</summary>
        public class FuelPump : MonoBehaviour, IVehicleDamageable
        {
            public float Hp = 60f;
            public bool Destroyed { get; private set; }
            private bool _detonating;
            private Material _screenMat;
            private MeshRenderer _bodyRenderer;

            bool IVehicleDamageable.IsAlive { get { return !Destroyed; } }
            Transform IVehicleDamageable.Transform { get { return transform; } }
            void IVehicleDamageable.TakeDamage(float amount, Vector3 fromPos, string kind)
            {
                TakeDamage(amount);
            }

            private void Awake()
            {
                Build();
                var col = gameObject.AddComponent<BoxCollider>();
                col.size = new Vector3(0.9f, 1.7f, 0.7f);
                col.center = new Vector3(0f, 1f, 0f);
            }

            public void TakeDamage(float amount)
            {
                if (Destroyed || _detonating) return;
                Hp -= amount;
                if (_screenMat != null)
                {
                    _screenMat.SetColor("_EmissionColor", new Color(1f, 0.2f, 0.1f) * 2f); // hit flash
                    _screenMat.EnableKeyword("_EMISSION");
                }
                if (Hp <= 0f) Detonate();
            }

            private void Detonate()
            {
                _detonating = true;
                Destroyed = true;
                if (_bodyRenderer != null) _bodyRenderer.sharedMaterial = VehicleMats.Charred();
                // Chain: AoE damages sibling pumps + the station.
                VehicleEffects.Explode(transform.position + Vector3.up * 1f, 9f, 130f, this);
            }

            private void Build()
            {
                var parts = new Dictionary<string, List<MeshBuilder.Part>>();
                Action<string, Vector3, Vector3> box = (mat, size, pos) =>
                {
                    if (!parts.TryGetValue(mat, out List<MeshBuilder.Part> l))
                    {
                        l = new List<MeshBuilder.Part>();
                        parts[mat] = l;
                    }
                    l.Add(MeshBuilder.Box(size, pos, Quaternion.identity));
                };
                box("deck_grey", new Vector3(1.4f, 0.25f, 1.4f), new Vector3(0f, 0.12f, 0f)); // island
                box("accent_orange", new Vector3(0.7f, 1.5f, 0.5f), new Vector3(0f, 1f, 0f)); // body
                box("metal_dark", new Vector3(0.12f, 0.3f, 0.12f), new Vector3(0.42f, 1.1f, 0f)); // nozzle
                foreach (var kv in parts)
                {
                    var go = MeshBuilder.BuildObject("Pump_" + kv.Key, kv.Value, VehicleMats.Get(kv.Key));
                    go.transform.SetParent(transform, false);
                    if (kv.Key == "accent_orange") _bodyRenderer = go.GetComponent<MeshRenderer>();
                }
                // Screen: own material instance (glows, flashes red when hit).
                _screenMat = new Material(Shader.Find("Standard"));
                _screenMat.color = new Color(0.05f, 0.1f, 0.15f);
                _screenMat.SetColor("_EmissionColor", new Color(0.2f, 0.7f, 1f) * 1.4f);
                _screenMat.EnableKeyword("_EMISSION");
                var scrParts = new List<MeshBuilder.Part>
                {
                    MeshBuilder.Box(new Vector3(0.4f, 0.3f, 0.04f), new Vector3(0f, 1.35f, 0.27f), Quaternion.identity)
                };
                var scr = MeshBuilder.BuildObject("Pump_screen", scrParts, _screenMat);
                scr.transform.SetParent(transform, false);
                // Hose.
                var hoseParts = new List<MeshBuilder.Part>
                {
                    MeshBuilder.Cylinder(0.035f, 1.0f, 8, Matrix4x4.TRS(
                        new Vector3(0.42f, 0.6f, 0f), Quaternion.Euler(0f, 0f, 8.6f), Vector3.one))
                };
                var hose = MeshBuilder.BuildObject("Pump_hose", hoseParts, VehicleMats.Get("metal_dark"));
                hose.transform.SetParent(transform, false);
                // FUEL tag.
                var tagGo = new GameObject("PumpTag");
                tagGo.transform.SetParent(transform, false);
                tagGo.transform.localPosition = new Vector3(0f, 1.95f, 0f);
                var tag = tagGo.AddComponent<TextMesh>();
                tag.text = "FUEL";
                tag.font = Resources.GetBuiltinResource<Font>("Arial.ttf");
                tag.fontSize = 64;
                tag.characterSize = 0.008f;
                tag.anchor = TextAnchor.MiddleCenter;
                tag.color = new Color(1f, 0.6f, 0.1f);
            }
        }
    }
}
