using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Portable fuel canister loot pickup (LootKind.FuelCan). Jerrycan mesh built
    /// procedurally; bobs and slowly spins; touching a vehicle pours FuelAmount
    /// into its tank. Spawned by the Loot system at loot points.
    /// </summary>
    public class FuelCan : MonoBehaviour
    {
        public float FuelAmount = 25f;

        private float _baseY;
        private float _t;
        private bool _collected;

        public static FuelCan Spawn(Vector3 pos, float amount = 25f)
        {
            var go = new GameObject("FuelCan");
            var can = go.AddComponent<FuelCan>();
            can.FuelAmount = amount;
            go.transform.position = pos;
            return can;
        }

        private void Awake()
        {
            Build();
            var col = gameObject.AddComponent<SphereCollider>();
            col.radius = 1.2f;
            col.isTrigger = true;
            _baseY = transform.position.y;
        }

        /// <summary>Pour this can into a vehicle's tank. Returns fuel actually added.</summary>
        public float Collect(VehicleController v)
        {
            if (_collected || v == null || v.Destroyed || !v.Spec.UsesFuel) return 0f;
            _collected = true;
            float before = v.Fuel;
            v.AddFuel(FuelAmount);
            Destroy(gameObject);
            return v.Fuel - before;
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_collected) return;
            var vc = other.GetComponent<VehicleController>();
            if (vc != null && !vc.Destroyed && vc.NeedsFuel())
                Collect(vc);
        }

        private void Update()
        {
            _t += Time.deltaTime;
            Vector3 p = transform.position;
            p.y = _baseY + Mathf.Sin(_t * 2f) * 0.12f;
            transform.position = p;
            transform.Rotate(0f, 55f * Time.deltaTime, 0f);
        }

        private void Build()
        {
            var parts = new List<MeshBuilder.Part>
            {
                // Jerrycan body.
                MeshBuilder.Box(new Vector3(0.35f, 0.45f, 0.2f), new Vector3(0f, 0.32f, 0f), Quaternion.identity),
                // Handle bar.
                MeshBuilder.Box(new Vector3(0.3f, 0.06f, 0.08f), new Vector3(0f, 0.58f, 0f), Quaternion.identity),
                // Cap.
                MeshBuilder.Box(new Vector3(0.08f, 0.06f, 0.08f), new Vector3(0.1f, 0.56f, 0f), Quaternion.identity),
            };
            Mesh mesh = MeshBuilder.Combine(parts);
            var mf = gameObject.AddComponent<MeshFilter>();
            mf.mesh = mesh;
            var mr = gameObject.AddComponent<MeshRenderer>();
            mr.sharedMaterial = VehicleMats.Get("accent_orange");
            // Glow ring so it reads as loot.
            var ringParts = new List<MeshBuilder.Part>
            {
                MeshBuilder.Cylinder(0.32f, 0.03f, 24, Matrix4x4.TRS(
                    new Vector3(0f, 0.05f, 0f), Quaternion.identity, Vector3.one))
            };
            var ring = MeshBuilder.BuildObject("FuelCan_ring", ringParts, VehicleMats.Get("glow_orange"));
            ring.transform.SetParent(transform, false);
        }
    }
}
