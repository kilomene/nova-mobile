using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Anything vehicle weapons/explosions can damage. Implemented by
    /// VehicleController, FuelStation/FuelPump; the Soldiers system will
    /// implement it for bots/players when ported.
    /// </summary>
    public interface IVehicleDamageable
    {
        bool IsAlive { get; }
        Transform Transform { get; }
        void TakeDamage(float amount, Vector3 fromPos, string kind);
    }

    /// <summary>
    /// Shared vehicle FX: pooled explosions (mesh flash + light + particles +
    /// boom audio), pooled falling bombs, smoke/fire emitters, ground-height query.
    /// Everything is pooled; nothing allocates in hot paths.
    /// </summary>
    public static class VehicleEffects
    {
        public const float WaterLevel = -0.15f;

        private static Transform _root;
        private static readonly List<PooledExplosion> _explosions = new List<PooledExplosion>();
        private static readonly List<PooledBomb> _bombs = new List<PooledBomb>();
        private static int _explIdx, _bombIdx;
        private static bool _ready;

        // Reused query buffers (no per-frame allocs).
        private static readonly Collider[] _overlapBuf = new Collider[48];
        private static RaycastHit _hit;

        /// <summary>Build pools. Call once at boot (idempotent).</summary>
        public static void Prewarm()
        {
            if (_ready) return;
            _ready = true;
            var rootGo = new GameObject("VehicleEffects");
            Object.DontDestroyOnLoad(rootGo);
            _root = rootGo.transform;
            for (int i = 0; i < 20; i++) _explosions.Add(CreateExplosion());
            for (int i = 0; i < 8; i++) _bombs.Add(CreateBomb());
        }

        // -------------------------------------------------------- explosions
        private sealed class PooledExplosion : MonoBehaviour
        {
            public MeshRenderer Flash;
            public Light Light;
            public ParticleSystem Particles;
            public OneShotAudio Audio;
            private float _t, _dur = 0.9f;
            private float _radius;

            public void Play(Vector3 pos, float radius, float damage, float boomVol = 1f)
            {
                _radius = radius;
                transform.position = pos;
                transform.localScale = Vector3.one * radius * 0.25f;
                _t = 0f;
                gameObject.SetActive(true);
                if (Particles != null) Particles.Play();
                if (Audio != null) Audio.Play(ProcAudio.Explosion("veh_boom", 1.2f), boomVol);
            }

            private void Update()
            {
                if (!gameObject.activeSelf) return;
                _t += Time.deltaTime;
                float k = Mathf.Clamp01(_t / _dur);
                float s = _radius * (0.25f + 1.4f * k);
                transform.localScale = Vector3.one * s;
                if (Light != null) Light.intensity = 6f * (1f - k);
                if (k >= 1f) gameObject.SetActive(false);
            }
        }

        private static PooledExplosion CreateExplosion()
        {
            var go = new GameObject("Explosion");
            go.transform.SetParent(_root, false);
            var pe = go.AddComponent<PooledExplosion>();
            var mf = go.AddComponent<MeshFilter>();
            // Unit sphere mesh (local helper; build-time only).
            mf.mesh = BuildSphereMesh(1f, 12, 8);
            var mr = go.AddComponent<MeshRenderer>();
            var flashMat = new Material(Shader.Find("Standard"));
            flashMat.color = new Color(1f, 0.55f, 0.15f, 0.85f);
            flashMat.SetColor("_EmissionColor", new Color(1f, 0.45f, 0.1f) * 3f);
            flashMat.EnableKeyword("_EMISSION");
            flashMat.SetFloat("_Mode", 3f);
            flashMat.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
            flashMat.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            flashMat.SetInt("_ZWrite", 0);
            flashMat.DisableKeyword("_ALPHATEST_ON");
            flashMat.EnableKeyword("_ALPHABLEND_ON");
            flashMat.DisableKeyword("_ALPHAPREMULTIPLY_ON");
            flashMat.renderQueue = 3000;
            mr.sharedMaterial = flashMat;
            pe.Flash = mr;
            var light = go.AddComponent<Light>();
            light.type = LightType.Point;
            light.color = new Color(1f, 0.55f, 0.2f);
            light.range = 18f;
            light.intensity = 0f;
            pe.Light = light;
            var ps = go.AddComponent<ParticleSystem>();
            var main = ps.main;
            main.startLifetime = 0.8f;
            main.startSpeed = 9f;
            main.startSize = 1.2f;
            main.maxParticles = 40;
            var emission = ps.emission;
            emission.SetBursts(new ParticleSystem.Burst[] { new ParticleSystem.Burst(0f, 40) });
            var shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Sphere;
            shape.radius = 1f;
            pe.Particles = ps;
            pe.Audio = go.AddComponent<OneShotAudio>();
            go.SetActive(false);
            return pe;
        }

        private static Mesh BuildSphereMesh(float radius, int segs, int rings)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int r = 0; r <= rings; r++)
            {
                float v = (float)r / rings;
                float phi = v * Mathf.PI;
                float y = Mathf.Cos(phi), rr = Mathf.Sin(phi);
                for (int s = 0; s <= segs; s++)
                {
                    float u = (float)s / segs;
                    float theta = u * Mathf.PI * 2f;
                    Vector3 n = new Vector3(rr * Mathf.Cos(theta), y, rr * Mathf.Sin(theta));
                    verts.Add(n * radius); normals.Add(n); uvs.Add(new Vector2(u, v));
                }
            }
            for (int r = 0; r < rings; r++)
                for (int s = 0; s < segs; s++)
                {
                    int a = r * (segs + 1) + s, b = a + segs + 1;
                    tris.Add(a); tris.Add(a + 1); tris.Add(b);
                    tris.Add(b); tris.Add(a + 1); tris.Add(b + 1);
                }
            var mesh = new Mesh();
            mesh.SetVertices(verts); mesh.SetNormals(normals); mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0); mesh.RecalculateBounds();
            return mesh;
        }

        /// <summary>Explosion: FX + AoE damage to every IVehicleDamageable in radius.</summary>
        public static void Explode(Vector3 pos, float radius, float damage, Object ignore = null)
        {
            Prewarm();
            PooledExplosion e = _explosions[_explIdx];
            _explIdx = (_explIdx + 1) % _explosions.Count;
            e.Play(pos, radius, damage);
            int n = Physics.OverlapSphereNonAlloc(pos, radius, _overlapBuf);
            for (int i = 0; i < n; i++)
            {
                Collider c = _overlapBuf[i];
                if (c == null) continue;
                var dmg = c.GetComponent<IVehicleDamageable>();
                if (dmg == null) continue;
                if (ignore != null && (dmg as Object) == ignore) continue;
                if (!dmg.IsAlive) continue;
                float dist = Vector3.Distance(dmg.Transform.position, pos);
                float fall = Mathf.Clamp01(1f - dist / Mathf.Max(radius, 0.01f));
                dmg.TakeDamage(damage * (0.35f + 0.65f * fall), pos, "explosive");
            }
        }

        // ------------------------------------------------------------- bombs
        private sealed class PooledBomb : MonoBehaviour
        {
            private float _vy;
            private float _radius, _damage;
            private bool _live;

            public void Drop(Vector3 pos, float radius, float damage)
            {
                transform.position = pos;
                _radius = radius; _damage = damage;
                _vy = 0f; _live = true;
                gameObject.SetActive(true);
            }

            private void Update()
            {
                if (!_live) return;
                _vy -= 22f * Time.deltaTime;
                Vector3 p = transform.position;
                p.y += _vy * Time.deltaTime;
                float gy = GroundHeight(p);
                if (p.y <= gy + 0.4f)
                {
                    _live = false;
                    gameObject.SetActive(false);
                    Explode(new Vector3(p.x, gy + 0.5f, p.z), _radius, _damage, this);
                    return;
                }
                transform.position = p;
            }
        }

        private static PooledBomb CreateBomb()
        {
            var go = new GameObject("Bomb");
            go.transform.SetParent(_root, false);
            var parts = new List<MeshBuilder.Part>
            {
                MeshBuilder.Box(new Vector3(0.5f, 0.9f, 0.5f), Vector3.zero, Quaternion.identity)
            };
            Mesh mesh = MeshBuilder.Combine(parts);
            var mf = go.AddComponent<MeshFilter>();
            mf.mesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = VehicleMats.Get("metal_dark");
            go.SetActive(false);
            return go.AddComponent<PooledBomb>();
        }

        public static void DropBomb(Vector3 pos, float radius, float damage)
        {
            Prewarm();
            PooledBomb b = _bombs[_bombIdx];
            _bombIdx = (_bombIdx + 1) % _bombs.Count;
            b.Drop(pos, radius, damage);
        }

        // ------------------------------------------------------- smoke/fire
        /// <summary>Attach a looping smoke emitter (damage feedback).</summary>
        public static ParticleSystem AttachSmoke(Transform parent, Vector3 localPos)
        {
            var go = new GameObject("SmokeFX");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            var ps = go.AddComponent<ParticleSystem>();
            var main = ps.main;
            main.loop = true;
            main.startLifetime = 1.2f;
            main.startSpeed = 3f;
            main.startSize = 0.9f;
            main.startColor = new Color(0.25f, 0.25f, 0.25f, 0.7f);
            main.maxParticles = 24;
            var emission = ps.emission;
            emission.rateOverTime = 18f;
            var shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Sphere;
            shape.radius = 0.6f;
            var vel = ps.velocityOverLifetime;
            vel.enabled = true;
            vel.y = 2.5f;
            ps.Play();
            return ps;
        }

        /// <summary>Attach a looping fire emitter (heavy damage feedback).</summary>
        public static ParticleSystem AttachFire(Transform parent, Vector3 localPos)
        {
            var go = new GameObject("FireFX");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            var ps = go.AddComponent<ParticleSystem>();
            var main = ps.main;
            main.loop = true;
            main.startLifetime = 0.7f;
            main.startSpeed = 2f;
            main.startSize = 0.8f;
            main.startColor = new Color(1f, 0.45f, 0.1f, 0.85f);
            main.maxParticles = 24;
            var emission = ps.emission;
            emission.rateOverTime = 22f;
            var shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Sphere;
            shape.radius = 0.5f;
            var vel = ps.velocityOverLifetime;
            vel.enabled = true;
            vel.y = 3f;
            // Additive-ish: use a bright emissive particle material.
            var mat = new Material(Shader.Find("Standard"));
            mat.SetColor("_EmissionColor", new Color(1f, 0.4f, 0.08f) * 2.5f);
            mat.EnableKeyword("_EMISSION");
            var pr = go.GetComponent<ParticleSystemRenderer>();
            pr.material = mat;
            ps.Play();
            return ps;
        }

        // ------------------------------------------------------------- query
        private static readonly RaycastHit[] _rayBuf = new RaycastHit[1];

        /// <summary>Terrain height at a world XZ. Raycasts down; falls back to y=0.</summary>
        public static float GroundHeight(Vector3 p)
        {
            int n = Physics.RaycastNonAlloc(new Ray(p + Vector3.up * 60f, Vector3.down), _rayBuf, 150f);
            if (n > 0) return _rayBuf[0].point.y;
            return 0f;
        }
    }
}
