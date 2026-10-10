using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Arsenal
{
    /// <summary>
    /// Rocket / grenade projectile, ported from Godot gun_projectile.gd.
    /// Explodes on impact or timeout: radial falloff damage, owner self-damage at
    /// close range, smoke-trail puffs. Pooled — never instantiated per shot at
    /// runtime (static pool built from code; preallocate via Prewarm).
    /// </summary>
    public class GunProjectile : MonoBehaviour
    {
        public Vector3 Velocity;
        public float GravityFactor = 1f;
        public float BlastRadius = 4f;
        public float Damage = 100f;
        public float Life = 5f;
        public GameObject Owner;

        public static Action<Vector3, float> OnExplosionFx;
        public static Action ExplosionSound;

        private float _t;
        private float _smokeT;
        private Transform _trail;
        private bool _dead;

        // ---- static pool ----
        private static readonly Stack<GunProjectile> _pool = new Stack<GunProjectile>();
        private static Transform _poolRoot;
        private static bool _prefabBuilt;

        private static void EnsureRoot()
        {
            if (_poolRoot == null)
            {
                var go = new GameObject("GunProjectilePool");
                _poolRoot = go.transform;
                if (Application.isPlaying)
                    UnityEngine.Object.DontDestroyOnLoad(go);
            }
        }

        public static void Prewarm(int count = 8)
        {
            EnsureRoot();
            for (int i = 0; i < count; i++)
            {
                var p = Create();
                p.gameObject.SetActive(false);
                _pool.Push(p);
            }
            SmokePuff.Prewarm(24);
        }

        private static GunProjectile Create()
        {
            var go = new GameObject("GunProjectile");
            var p = go.AddComponent<GunProjectile>();
            // visible tracer body: orange box
            var body = new GameObject("Body");
            body.transform.SetParent(go.transform, false);
            var mf = body.AddComponent<MeshFilter>();
            mf.mesh = MeshBuilder.Combine(new List<MeshBuilder.Part>
            {
                MeshBuilder.Box(new Vector3(0.09f, 0.09f, 0.45f), Matrix4x4.identity)
            });
            var mr = body.AddComponent<MeshRenderer>();
            mr.material = GunFactory.EmissiveMat(new Color(1f, 0.55f, 0.15f));
            p._trail = body.transform;
            var col = go.AddComponent<SphereCollider>();
            col.radius = 0.3f;
            col.isTrigger = true;
            var rb = go.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.useGravity = false;
            go.transform.SetParent(_poolRoot, false);
            return p;
        }

        public static GunProjectile Launch(Vector3 from, Vector3 dir, float speed, float grav,
            float blast, float dmg, GameObject owner)
        {
            EnsureRoot();
            GunProjectile p = _pool.Count > 0 ? _pool.Pop() : Create();
            p.transform.SetParent(null, false);
            p.transform.position = from;
            p.Velocity = dir.normalized * speed;
            p.GravityFactor = grav;
            p.BlastRadius = blast;
            p.Damage = dmg;
            p.Owner = owner;
            p._t = 0f;
            p._smokeT = 0f;
            p._dead = false;
            p.gameObject.SetActive(true);
            return p;
        }

        private void Update()
        {
            if (_dead) return;
            _t += Time.deltaTime;
            if (_t >= Life) { Explode(); return; }
            Velocity.y -= 9.8f * GravityFactor * Time.deltaTime;
            transform.position += Velocity * Time.deltaTime;
            if (_trail != null && Velocity.sqrMagnitude > 0.01f)
                _trail.rotation = Quaternion.LookRotation(Velocity.normalized);
            _smokeT += Time.deltaTime;
            if (_smokeT >= 0.07f)
            {
                _smokeT = 0f;
                SmokePuff.Spawn(transform.position);
            }
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_dead) return;
            if (Owner != null && other.gameObject == Owner) return;
            Explode();
        }

        public void Explode()
        {
            if (_dead) return;
            _dead = true;
            Vector3 pos = transform.position;
            // Radial damage to damageables.
            Collider[] hits = Physics.OverlapSphere(pos, BlastRadius);
            for (int i = 0; i < hits.Length; i++)
            {
                var dmg = hits[i].GetComponentInParent<IDamageable>();
                if (dmg == null || !dmg.IsAlive) continue;
                if (Owner != null && hits[i].gameObject == Owner) continue; // handled below
                float d = Vector3.Distance(hits[i].transform.position, pos);
                if (d <= BlastRadius)
                {
                    float f = 1f - (d / BlastRadius) * 0.6f;
                    dmg.TakeDamage(Damage * f, pos, DamageCause.Explosion);
                }
            }
            // Owner self-damage at close range (rockets are dangerous).
            if (Owner != null)
            {
                var od = Owner.GetComponentInParent<IDamageable>();
                if (od != null && od.IsAlive)
                {
                    float pd = Vector3.Distance(Owner.transform.position, pos);
                    if (pd <= BlastRadius * 0.7f)
                        od.TakeDamage(Damage * 0.4f * (1f - pd / BlastRadius), pos, DamageCause.Explosion);
                }
            }
            if (OnExplosionFx != null) OnExplosionFx(pos, BlastRadius);
            if (ExplosionSound != null) ExplosionSound();
            gameObject.SetActive(false);
            transform.SetParent(_poolRoot, false);
            _pool.Push(this);
        }

        /// <summary>Smoke trail puff: pooled, grows and fades over 0.6 s.</summary>
        private class SmokePuff : MonoBehaviour
        {
            private static readonly Stack<SmokePuff> _puffs = new Stack<SmokePuff>();
            private static Transform _puffRoot;
            private static Mesh _puffMesh;
            private float _t;
            private Material _mat;
            private static readonly Color PuffColor = new Color(0.78f, 0.78f, 0.80f, 0.55f);

            public static void Prewarm(int count)
            {
                if (_puffRoot == null)
                {
                    _puffRoot = new GameObject("SmokePuffPool").transform;
                    if (Application.isPlaying)
                        UnityEngine.Object.DontDestroyOnLoad(_puffRoot.gameObject);
                }
                if (_puffMesh == null)
                {
                    _puffMesh = MeshBuilder.Combine(new List<MeshBuilder.Part>
                    {
                        MeshBuilder.Cylinder(0.12f, 0.24f, 8, Matrix4x4.identity)
                    });
                }
                for (int i = 0; i < count; i++)
                {
                    var p = CreatePuff();
                    p.gameObject.SetActive(false);
                    _puffs.Push(p);
                }
            }

            private static SmokePuff CreatePuff()
            {
                var go = new GameObject("SmokePuff");
                var p = go.AddComponent<SmokePuff>();
                var mf = go.AddComponent<MeshFilter>();
                mf.mesh = _puffMesh;
                var mr = go.AddComponent<MeshRenderer>();
                p._mat = new Material(Shader.Find("Standard"));
                p._mat.SetFloat("_Mode", 3f);
                p._mat.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
                p._mat.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                p._mat.SetInt("_ZWrite", 0);
                p._mat.DisableKeyword("_ALPHATEST_ON");
                p._mat.EnableKeyword("_ALPHABLEND_ON");
                p._mat.renderQueue = 3000;
                mr.material = p._mat;
                go.transform.SetParent(_puffRoot, false);
                return p;
            }

            public static void Spawn(Vector3 pos)
            {
                if (_puffRoot == null) Prewarm(24);
                SmokePuff p = _puffs.Count > 0 ? _puffs.Pop() : CreatePuff();
                p.transform.SetParent(null, false);
                p.transform.position = pos;
                p.transform.localScale = Vector3.one;
                p._t = 0f;
                p._mat.color = PuffColor;
                p.gameObject.SetActive(true);
            }

            private void Update()
            {
                _t += Time.deltaTime;
                float k = _t / 0.6f;
                if (k >= 1f)
                {
                    gameObject.SetActive(false);
                    transform.SetParent(_puffRoot, false);
                    _puffs.Push(this);
                    return;
                }
                transform.localScale = Vector3.one * (1f + k * 2.2f);
                Color c = PuffColor;
                c.a = PuffColor.a * (1f - k);
                _mat.color = c;
            }
        }
    }
}
