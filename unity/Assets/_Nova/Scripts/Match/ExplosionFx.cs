using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Classes;
using NovaMobile.Core;

namespace NovaMobile.Match
{
    /// <summary>
    /// Real explosion FX, wired to Classes/ClassFx.RequestExplosion by the
    /// MatchManager: pooled fireball + shockwave ring + smoke + radial damage
    /// to IDamageable. DustBurst is a lighter variant for landings/impacts.
    /// Ported from main.gd spawn_explosion / _dust_burst.
    /// </summary>
    public static class ExplosionFx
    {
        private class Fx
        {
            public GameObject Go;
            public MeshRenderer Ball;
            public MeshRenderer Ring;
            public MeshRenderer Smoke;
            public Material BallMat;
            public Material RingMat;
            public Material SmokeMat;
            public float Age;
            public float Radius;
            public bool Active;
        }

        private const int PoolN = 10;
        private static readonly List<Fx> Pool = new List<Fx>(PoolN);
        private static Transform _root;
        private static Material _ballMat;
        private static Material _ringMat;
        private static Material _smokeMat;

        private static Transform Root
        {
            get
            {
                if (_root == null) _root = new GameObject("ExplosionFx").transform;
                return _root;
            }
        }

        private static void EnsureMats()
        {
            if (_ballMat != null) return;
            _ballMat = new Material(Shader.Find("Unlit/Transparent"));
            _ballMat.color = new Color(1f, 0.55f, 0.12f, 0.9f);
            _ringMat = new Material(Shader.Find("Unlit/Transparent"));
            _ringMat.color = new Color(1f, 0.8f, 0.4f, 0.8f);
            _smokeMat = new Material(Shader.Find("Unlit/Transparent"));
            _smokeMat.color = new Color(0.25f, 0.22f, 0.2f, 0.55f);
        }

        /// <summary>ClassFx.RequestExplosion target: (position, radius).</summary>
        public static void Spawn(Vector3 pos, float radius)
        {
            EnsureMats();
            Fx fx = null;
            for (int i = 0; i < Pool.Count; i++)
                if (!Pool[i].Active) { fx = Pool[i]; break; }
            if (fx == null)
            {
                if (Pool.Count >= PoolN) return;
                fx = BuildFx();
                Pool.Add(fx);
            }
            fx.Age = 0f; fx.Radius = radius; fx.Active = true;
            fx.Go.transform.position = pos;
            fx.Go.SetActive(true);

            // Radial damage with falloff (main.gd spawn_explosion behavior).
            float baseDmg = 60f + radius * 8f;
            Collider[] hits = Physics.OverlapSphere(pos, radius);
            for (int i = 0; i < hits.Length; i++)
            {
                var dmg = hits[i].GetComponentInParent<IDamageable>();
                if (dmg == null || !dmg.IsAlive) continue;
                float d = Vector3.Distance(hits[i].transform.position, pos);
                float fall = 1f - Mathf.Clamp01(d / radius);
                dmg.TakeDamage(baseDmg * (0.35f + 0.65f * fall), pos, DamageCause.Explosion);
            }
        }

        /// <summary>Light dust burst (airdrop landings, impacts). No damage.</summary>
        public static void DustBurst(Vector3 pos)
        {
            EnsureMats();
            Fx fx = null;
            for (int i = 0; i < Pool.Count; i++)
                if (!Pool[i].Active) { fx = Pool[i]; break; }
            if (fx == null)
            {
                if (Pool.Count >= PoolN) return;
                fx = BuildFx();
                Pool.Add(fx);
            }
            fx.Age = 0f; fx.Radius = 3f; fx.Active = true;
            fx.Go.transform.position = pos;
            fx.Ball.enabled = false; // dust only
            fx.Go.SetActive(true);
        }

        private static Fx BuildFx()
        {
            var go = new GameObject("Boom");
            go.transform.SetParent(Root, false);
            var fx = new Fx { Go = go };

            var ball = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            ball.transform.SetParent(go.transform, false);
            Object.Destroy(ball.GetComponent<Collider>());
            fx.Ball = ball.GetComponent<MeshRenderer>();
            fx.BallMat = new Material(_ballMat);
            fx.Ball.material = fx.BallMat;

            var ring = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            ring.transform.SetParent(go.transform, false);
            Object.Destroy(ring.GetComponent<Collider>());
            fx.Ring = ring.GetComponent<MeshRenderer>();
            fx.RingMat = new Material(_ringMat);
            fx.Ring.material = fx.RingMat;

            var smoke = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            smoke.transform.SetParent(go.transform, false);
            Object.Destroy(smoke.GetComponent<Collider>());
            fx.Smoke = smoke.GetComponent<MeshRenderer>();
            fx.SmokeMat = new Material(_smokeMat);
            fx.Smoke.material = fx.SmokeMat;

            go.SetActive(false);
            return fx;
        }

        /// <summary>Ticked by the MatchManager (static pool, no owner needed).</summary>
        public static void Tick(float dt)
        {
            for (int i = 0; i < Pool.Count; i++)
            {
                Fx fx = Pool[i];
                if (!fx.Active) continue;
                fx.Age += dt;
                float t = fx.Age;
                // Fireball: fast expand, quick fade.
                float bs = fx.Radius * (0.4f + t * 2.2f);
                fx.Ball.transform.localScale = new Vector3(bs, bs * 0.8f, bs);
                SetAlpha(fx.BallMat, 0.9f * (1f - t / 0.55f));
                // Shockwave ring: flat, expanding.
                float rs = fx.Radius * (0.6f + t * 5f);
                fx.Ring.transform.localScale = new Vector3(rs, 0.35f, rs);
                SetAlpha(fx.RingMat, 0.8f * (1f - t / 0.7f));
                // Smoke: rises and lingers.
                fx.Smoke.transform.localScale = new Vector3(rs * 0.6f, rs * 0.5f, rs * 0.6f);
                fx.Smoke.transform.position = fx.Go.transform.position + new Vector3(0f, t * 3f, 0f);
                SetAlpha(fx.SmokeMat, 0.55f * (1f - t / 1.4f));
                if (t >= 1.4f)
                {
                    fx.Active = false;
                    fx.Ball.enabled = true;
                    fx.Go.SetActive(false);
                }
            }
        }

        private static void SetAlpha(Material m, float a)
        {
            var c = m.color; c.a = Mathf.Max(0f, a); m.color = c;
        }
    }
}
