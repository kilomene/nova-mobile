using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Player
{
    /// <summary>
    /// Throwable smoke canister: ballistic arc, pops a lingering smoke cloud
    /// on landing that blocks AI line-of-sight. Ported from smoke_grenade.gd.
    ///
    /// Pooled like FragGrenade. The AI system queries the static
    /// IsInSmoke(pos) / BlocksSight(a, b); the FX system hooks OnCloudSpawned
    /// to render the visible cloud.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    [RequireComponent(typeof(SphereCollider))]
    public class SmokeGrenade : MonoBehaviour
    {
        public const float CloudRadius = 6.0f;
        public const float CloudLife = 18.0f;
        private const int MaxClouds = 32;

        /// <summary>Fired when a cloud blooms (FX system renders it).</summary>
        public static event Action<Vector3, float, float> OnCloudSpawned;
        // pos, radius, lifeSeconds

        private struct Cloud
        {
            public Vector3 pos;
            public float radius;
            public float expires;
        }

        private static readonly List<Cloud> _clouds = new List<Cloud>(MaxClouds);
        private static readonly List<SmokeGrenade> _pool = new List<SmokeGrenade>();
        private static GameObject _poolRoot;
        private static Material _bodyMat;

        private Rigidbody _rb;
        private Transform _visual;
        private bool _landed;

        // ------------------------------------------------------------------
        public static SmokeGrenade Spawn(Vector3 from, Vector3 dir, float power,
            GameObject owner)
        {
            SmokeGrenade g = null;
            for (int i = 0; i < _pool.Count; i++)
            {
                if (!_pool[i].gameObject.activeSelf) { g = _pool[i]; break; }
            }
            if (g == null)
            {
                if (_poolRoot == null)
                    _poolRoot = new GameObject("SmokeGrenadePool");
                g = new GameObject("SmokeGrenade").AddComponent<SmokeGrenade>();
                g.transform.SetParent(_poolRoot.transform, false);
                _pool.Add(g);
            }
            g.transform.position = from;
            g.gameObject.SetActive(true);
            g._landed = false;
            g._visual.gameObject.SetActive(true);
            Vector3 v = (dir + Vector3.up * 0.35f).normalized * power;
            g._rb.linearVelocity = v;
            g._rb.angularVelocity = new Vector3(9f, 0f, 0f);
            g._rb.WakeUp();
            PurgeExpired();
            return g;
        }

        /// <summary>
        /// AI line-of-sight query: is this world position inside a live
        /// smoke cloud? Allocation-free.
        /// </summary>
        public static bool IsInSmoke(Vector3 pos)
        {
            PurgeExpired();
            float now = Time.time;
            for (int i = 0; i < _clouds.Count; i++)
            {
                var c = _clouds[i];
                if (c.expires <= now) continue;
                if ((pos - c.pos).sqrMagnitude < c.radius * c.radius)
                    return true;
            }
            return false;
        }

        /// <summary>
        /// Does any live cloud block the segment a-&gt;b? (segment-sphere test,
        /// same math as smoke_grenade.gd blocks_sight).
        /// </summary>
        public static bool BlocksSight(Vector3 a, Vector3 b)
        {
            PurgeExpired();
            float now = Time.time;
            for (int i = 0; i < _clouds.Count; i++)
            {
                var c = _clouds[i];
                if (c.expires <= now) continue;
                if (SegmentSphere(a, b, c.pos, c.radius))
                    return true;
            }
            return false;
        }

        private static bool SegmentSphere(Vector3 a, Vector3 b, Vector3 c, float r)
        {
            Vector3 ab = b - a;
            float t = Mathf.Clamp01(
                Vector3.Dot(c - a, ab) / Mathf.Max(ab.sqrMagnitude, 0.001f));
            return (a + ab * t - c).sqrMagnitude < r * r;
        }

        private static void PurgeExpired()
        {
            float now = Time.time;
            for (int i = _clouds.Count - 1; i >= 0; i--)
            {
                if (_clouds[i].expires <= now)
                    _clouds.RemoveAt(i);
            }
        }

        // ------------------------------------------------------------------
        private void Awake()
        {
            _rb = GetComponent<Rigidbody>();
            _rb.mass = 0.4f;
            _rb.linearDamping = 0.05f;
            _rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;

            var col = GetComponent<SphereCollider>();
            col.radius = 0.07f;

            if (_bodyMat == null)
            {
                _bodyMat = new Material(Shader.Find("Standard"));
                _bodyMat.color = new Color(0.55f, 0.57f, 0.60f);
                _bodyMat.SetFloat("_Metallic", 0.5f);
                _bodyMat.SetFloat("_Glossiness", 0.5f);
            }
            var parts = new List<MeshBuilder.Part>
            {
                MeshBuilder.Cylinder(0.06f, 0.16f, 10, Matrix4x4.identity)
            };
            var body = MeshBuilder.BuildObject("Canister", parts, _bodyMat);
            body.transform.SetParent(transform, false);
            _visual = body.transform;

            gameObject.SetActive(false);
        }

        private void OnCollisionEnter(Collision c)
        {
            if (!_landed) Land(c.contacts[0].point);
        }

        private void Update()
        {
            if (_landed) return;
            if (transform.position.y < -2f) Land(transform.position);
        }

        private void Land(Vector3 at)
        {
            _landed = true;
            Vector3 cloudPos = at + Vector3.up * 1.2f;
            if (_clouds.Count >= MaxClouds)
                _clouds.RemoveAt(0);
            _clouds.Add(new Cloud
            {
                pos = cloudPos,
                radius = CloudRadius,
                expires = Time.time + CloudLife
            });
            OnCloudSpawned?.Invoke(at, CloudRadius, CloudLife);
            gameObject.SetActive(false);
        }
    }
}
