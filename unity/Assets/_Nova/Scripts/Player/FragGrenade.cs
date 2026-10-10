using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Player
{
    /// <summary>
    /// Throwable fragmentation grenade: cookable fuse, ballistic arc with
    /// bounces (Rigidbody physics), AoE explosion with distance falloff.
    /// Ported from frag_grenade.gd.
    ///
    /// Instances are pooled (mobile-first: no Instantiate in combat). Damage
    /// goes through IDamageable so bots, vehicles and the player all react.
    /// FX/audio hook: subscribe to OnDetonated.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    [RequireComponent(typeof(SphereCollider))]
    public class FragGrenade : MonoBehaviour
    {
        public const float Fuse = 2.0f;
        public const float BlastRadius = 5.5f;
        public const float Damage = 130.0f;
        private const int MaxBounces = 3;

        /// <summary>Fired on detonation (FX / audio systems hook this).</summary>
        public static event Action<Vector3, float> OnDetonated;

        private static readonly List<FragGrenade> _pool = new List<FragGrenade>();
        private static GameObject _poolRoot;
        private static Material _bodyMat;

        private Rigidbody _rb;
        private Transform _visual;
        private float _fuseLeft;
        private int _bounces;
        private bool _exploded;
        private GameObject _owner;

        // ------------------------------------------------------------------
        /// <summary>
        /// Throw a grenade. cookTime shortens the fuse (min 0.15 s), exactly
        /// like the Godot cook mechanic.
        /// </summary>
        public static FragGrenade Spawn(Vector3 from, Vector3 dir, float power,
            float cookTime, GameObject owner)
        {
            FragGrenade g = null;
            for (int i = 0; i < _pool.Count; i++)
            {
                if (!_pool[i].gameObject.activeSelf) { g = _pool[i]; break; }
            }
            if (g == null)
            {
                if (_poolRoot == null)
                    _poolRoot = new GameObject("FragGrenadePool");
                g = new GameObject("FragGrenade").AddComponent<FragGrenade>();
                g.transform.SetParent(_poolRoot.transform, false);
                _pool.Add(g);
            }
            g.transform.position = from;
            g.gameObject.SetActive(true);
            g._owner = owner;
            g._fuseLeft = Mathf.Max(Fuse - cookTime, 0.15f);
            g._bounces = 0;
            g._exploded = false;
            g._visual.localScale = Vector3.one;
            Vector3 v = (dir + Vector3.up * 0.18f).normalized * power;
            g._rb.velocity = v;
            g._rb.angularVelocity = new Vector3(9f, 7f, 5f);
            g._rb.WakeUp();
            return g;
        }

        private void Awake()
        {
            _rb = GetComponent<Rigidbody>();
            _rb.mass = 0.4f;
            _rb.drag = 0.05f;
            _rb.angularDrag = 0.5f;
            _rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;

            var col = GetComponent<SphereCollider>();
            col.radius = 0.06f;
            var phys = new PhysicMaterial("FragBounce")
            {
                bounciness = 0.45f,
                bounceCombine = PhysicMaterialCombine.Maximum,
                dynamicFriction = 0.4f,
                staticFriction = 0.4f
            };
            col.material = phys;

            if (_bodyMat == null)
            {
                _bodyMat = new Material(Shader.Find("Standard"));
                _bodyMat.color = new Color(0.20f, 0.28f, 0.16f);
                _bodyMat.SetFloat("_Metallic", 0.35f);
                _bodyMat.SetFloat("_Glossiness", 0.45f);
            }
            var parts = new List<MeshBuilder.Part>
            {
                MeshBuilder.Box(new Vector3(0.09f, 0.07f, 0.09f),
                    Vector3.zero, Quaternion.identity)
            };
            var body = MeshBuilder.BuildObject("Body", parts, _bodyMat);
            body.transform.SetParent(transform, false);
            _visual = body.transform;

            gameObject.SetActive(false);
        }

        private void OnCollisionEnter(Collision c)
        {
            if (_exploded) return;
            _bounces++;
            if (_bounces >= MaxBounces)
            {
                // Stop bouncing, roll to rest.
                _rb.drag = 2.5f;
                _rb.angularDrag = 4f;
            }
            if (_rb.velocity.magnitude < 1.2f)
                _rb.velocity = Vector3.zero;
        }

        private void Update()
        {
            if (_exploded) return;
            _fuseLeft -= Time.deltaTime;
            if (_fuseLeft <= 0f)
            {
                Explode();
                return;
            }
            // Blink faster as the fuse runs out (matches Godot tween pulse).
            if (_fuseLeft < 0.6f && _visual != null)
            {
                float s = 1f + 0.25f * Mathf.Sin(Time.time * 30f);
                _visual.localScale = new Vector3(s, s, s);
            }
            if (transform.position.y < -30f) Explode();
        }

        private void Explode()
        {
            if (_exploded) return;
            _exploded = true;
            Vector3 pos = transform.position;

            var hits = Physics.OverlapSphere(pos, BlastRadius,
                ~0, QueryTriggerInteraction.Ignore);
            for (int i = 0; i < hits.Length; i++)
            {
                var dmg = hits[i].GetComponent<IDamageable>();
                if (dmg == null || !dmg.IsAlive) continue;
                float d = Vector3.Distance(hits[i].transform.position, pos);
                if (d > BlastRadius) continue;
                float falloff = 1f - (d / BlastRadius) * 0.6f;
                float amount = Damage * falloff;
                if (hits[i].gameObject == _owner)
                    amount = Damage * 0.4f * (1f - d / BlastRadius); // self-damage
                dmg.TakeDamage(amount, pos, DamageCause.Explosion);
            }

            OnDetonated?.Invoke(pos, BlastRadius);
            gameObject.SetActive(false);
        }
    }
}
