using System;
using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Classes
{
    /// <summary>
    /// Cheap pooled visual effects for class abilities, ported from class_fx.gd.
    /// All builders are static; pooled items live under a shared root and are
    /// returned automatically. Explosions are delegated to the owning system via
    /// RequestExplosion (the Match/World agent wires it to the real FX).
    /// </summary>
    public static class ClassFx
    {
        /// <summary>Wired by the Match/World system to the real explosion FX + damage.</summary>
        public static event Action<Vector3, float> RequestExplosion;

        public static void Explode(Vector3 pos, float radius) =>
            RequestExplosion?.Invoke(pos, radius);

        private static Transform _root;
        private static readonly Dictionary<string, Stack<FxItem>> Pools =
            new Dictionary<string, Stack<FxItem>>();

        private static Material _unlitTransparent;
        private static Material _unlitOpaque;
        private static Mesh _ringMesh;
        private static Mesh _diamondMesh;

        private static Transform Root
        {
            get
            {
                if (_root == null)
                {
                    var go = new GameObject("ClassFx");
                    _root = go.transform;
                }
                return _root;
            }
        }

        private static Material UnlitTransparent
        {
            get
            {
                if (_unlitTransparent == null)
                {
                    _unlitTransparent = new Material(Shader.Find("Unlit/Transparent"));
                }
                return _unlitTransparent;
            }
        }

        private static Material UnlitOpaque
        {
            get
            {
                if (_unlitOpaque == null)
                {
                    _unlitOpaque = new Material(Shader.Find("Unlit/Color"));
                }
                return _unlitOpaque;
            }
        }

        // ------------------------------------------------------------------
        // Builders
        // ------------------------------------------------------------------

        /// <summary>Expanding ground ring (telegraph / pulse), fades out.</summary>
        public static GameObject GroundRing(Vector3 pos, float radius, float duration, Color color)
        {
            var item = Rent("ring", () =>
            {
                var go = new GameObject("FxRing");
                var mf = go.AddComponent<MeshFilter>();
                mf.sharedMesh = RingMesh;
                var rend = go.AddComponent<MeshRenderer>();
                rend.sharedMaterial = UnlitTransparent;
                var fx = go.AddComponent<FxItem>();
                fx.Rend = rend;
                return fx;
            });
            item.transform.position = pos + Vector3.up * 0.12f;
            item.transform.rotation = Quaternion.identity;
            item.Play(duration, color, new Vector3(0.5f, 1f, 0.5f), new Vector3(radius, 1f, radius), true);
            return item.gameObject;
        }

        /// <summary>Translucent dome (kinetic shield / radiation / trap field).</summary>
        public static GameObject Dome(Vector3 pos, float radius, float duration, Color color)
        {
            var item = Rent("dome", () =>
            {
                var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
                go.name = "FxDome";
                UnityEngine.Object.Destroy(go.GetComponent<Collider>());
                var rend = go.GetComponent<Renderer>();
                rend.sharedMaterial = UnlitTransparent;
                var fx = go.AddComponent<FxItem>();
                fx.Rend = rend;
                return fx;
            });
            item.transform.position = pos + Vector3.up * radius * 0.55f;
            item.transform.rotation = Quaternion.identity;
            item.Play(duration, color,
                new Vector3(radius, radius * 0.75f, radius),
                new Vector3(radius, radius * 0.75f, radius), true);
            return item.gameObject;
        }

        /// <summary>Straight beam between two points (grapple rope, lightning, laser).</summary>
        public static GameObject Beam(Vector3 a, Vector3 b, float duration, Color color, float width = 0.05f)
        {
            var item = Rent("beam", () =>
            {
                var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                go.name = "FxBeam";
                UnityEngine.Object.Destroy(go.GetComponent<Collider>());
                var rend = go.GetComponent<Renderer>();
                rend.sharedMaterial = UnlitOpaque;
                var fx = go.AddComponent<FxItem>();
                fx.Rend = rend;
                return fx;
            });
            float len = Mathf.Max(Vector3.Distance(a, b), 0.01f);
            item.transform.position = (a + b) * 0.5f;
            item.transform.LookAt(b);
            item.Play(duration, color, new Vector3(width, width, len), new Vector3(width, width, len), false);
            return item.gameObject;
        }

        /// <summary>Floating diamond marker that follows a target (marks / pings).</summary>
        public static GameObject Marker(Transform target, float duration, Color color)
        {
            if (target == null) return null;
            var item = Rent("marker", () =>
            {
                var go = new GameObject("FxMarker");
                var mf = go.AddComponent<MeshFilter>();
                mf.sharedMesh = DiamondMesh;
                var rend = go.AddComponent<MeshRenderer>();
                rend.sharedMaterial = UnlitOpaque;
                var fx = go.AddComponent<FxItem>();
                fx.Rend = rend;
                return fx;
            });
            item.Follow = target;
            item.FollowOffset = new Vector3(0f, 2.6f, 0f);
            item.Spin = true;
            item.transform.position = target.position + item.FollowOffset;
            item.transform.rotation = Quaternion.Euler(0f, 0f, 45f);
            item.Play(duration, color, Vector3.one * 0.5f, Vector3.one * 0.5f, false);
            return item.gameObject;
        }

        /// <summary>Rising smoke column. Pooled particle system, auto-returned.</summary>
        public static GameObject SmokeColumn(Vector3 pos, float radius, float duration, Color color)
        {
            var item = Rent("smoke", () =>
            {
                var go = new GameObject("FxSmoke");
                var ps = go.AddComponent<ParticleSystem>();
                var fx = go.AddComponent<FxItem>();
                fx.Smoke = ps;
                ConfigureSmoke(ps);
                return fx;
            });
            item.transform.position = pos + Vector3.up * 0.6f;
            item.transform.rotation = Quaternion.identity;
            item.PlaySmoke(duration, radius, color);
            return item.gameObject;
        }

        /// <summary>
        /// Small deployable prop (station/turret/pad): cylinder + emissive lamp.
        /// NOT pooled — owned and destroyed by the ability. Fresh build per deploy
        /// (deploys are cooldown-gated and few).
        /// </summary>
        public static GameObject DeployBase(Vector3 pos, Color accent, float radius = 0.45f, float height = 0.9f)
        {
            var root = new GameObject("DeployBase");
            root.transform.position = pos;
            var body = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            body.name = "Base";
            UnityEngine.Object.Destroy(body.GetComponent<Collider>());
            body.transform.SetParent(root.transform, false);
            body.transform.localScale = new Vector3(radius * 2f, height, radius * 2f);
            body.transform.localPosition = new Vector3(0f, height * 0.5f, 0f);
            var bmat = new Material(Shader.Find("Standard"))
            {
                color = new Color(0.16f, 0.17f, 0.19f),
            };
            bmat.SetFloat("_Metallic", 0.55f);
            bmat.SetFloat("_Glossiness", 0.55f);
            body.GetComponent<Renderer>().sharedMaterial = bmat;
            var lamp = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            lamp.name = "Lamp";
            UnityEngine.Object.Destroy(lamp.GetComponent<Collider>());
            lamp.transform.SetParent(root.transform, false);
            lamp.transform.localScale = Vector3.one * 0.24f;
            lamp.transform.localPosition = new Vector3(0f, height + 0.12f, 0f);
            var lmat = new Material(Shader.Find("Unlit/Color")) { color = accent };
            lamp.GetComponent<Renderer>().sharedMaterial = lmat;
            return root;
        }

        /// <summary>Holographic soldier silhouette (decoys / echoes). Caller owns it.</summary>
        public static GameObject HoloSoldier(Vector3 pos, Color color)
        {
            var root = new GameObject("HoloSoldier");
            root.transform.position = pos;
            var cap = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            UnityEngine.Object.Destroy(cap.GetComponent<Collider>());
            cap.transform.SetParent(root.transform, false);
            cap.transform.localPosition = new Vector3(0f, 0.95f, 0f);
            cap.transform.localScale = new Vector3(0.7f, 1f, 0.7f);
            var mat = new Material(Shader.Find("Unlit/Transparent")) { color = color };
            cap.GetComponent<Renderer>().sharedMaterial = mat;
            return root;
        }

        /// <summary>Destroy a GameObject after `life` seconds (one-shot visuals).</summary>
        public static void DestroyAfter(GameObject go, float life)
        {
            if (go == null) return;
            var td = go.AddComponent<TimedDestroy>();
            td.Life = life;
        }

        // ------------------------------------------------------------------
        // Pool internals
        // ------------------------------------------------------------------

        private static FxItem Rent(string key, Func<FxItem> build)
        {
            if (!Pools.TryGetValue(key, out var stack))
            {
                stack = new Stack<FxItem>();
                Pools[key] = stack;
            }
            FxItem item = stack.Count > 0 ? stack.Pop() : build();
            item.PoolKey = key;
            item.transform.SetParent(Root, false);
            item.gameObject.SetActive(true);
            item.Follow = null;
            item.Spin = false;
            item.HoldManual = false;
            return item;
        }

        internal static void Return(FxItem item)
        {
            item.gameObject.SetActive(false);
            item.transform.SetParent(Root, false);
            if (Pools.TryGetValue(item.PoolKey, out var stack))
                stack.Push(item);
            else
                UnityEngine.Object.Destroy(item.gameObject);
        }

        private static Mesh RingMesh
        {
            get
            {
                if (_ringMesh == null) _ringMesh = BuildRingMesh(48, 0.92f, 1.0f);
                return _ringMesh;
            }
        }

        private static Mesh DiamondMesh
        {
            get
            {
                if (_diamondMesh == null) _diamondMesh = BuildDiamondMesh();
                return _diamondMesh;
            }
        }

        private static Mesh BuildRingMesh(int seg, float inner, float outer)
        {
            var verts = new Vector3[(seg + 1) * 2];
            var uvs = new Vector2[verts.Length];
            var tris = new int[seg * 6];
            for (int i = 0; i <= seg; i++)
            {
                float a = (float)i / seg * Mathf.PI * 2f;
                float c = Mathf.Cos(a), s = Mathf.Sin(a);
                verts[i * 2] = new Vector3(c * inner, 0f, s * inner);
                verts[i * 2 + 1] = new Vector3(c * outer, 0f, s * outer);
                uvs[i * 2] = new Vector2((float)i / seg, 0f);
                uvs[i * 2 + 1] = new Vector2((float)i / seg, 1f);
                if (i < seg)
                {
                    int b = i * 6, v = i * 2;
                    tris[b] = v; tris[b + 1] = v + 2; tris[b + 2] = v + 1;
                    tris[b + 3] = v + 1; tris[b + 4] = v + 2; tris[b + 5] = v + 3;
                }
            }
            var mesh = new Mesh { name = "FxRing" };
            mesh.vertices = verts;
            mesh.uv = uvs;
            mesh.triangles = tris;
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }

        private static Mesh BuildDiamondMesh()
        {
            var top = new Vector3(0f, 0.35f, 0f);
            var bottom = new Vector3(0f, -0.35f, 0f);
            var eq = new[]
            {
                new Vector3(0.25f, 0f, 0f), new Vector3(0f, 0f, 0.25f),
                new Vector3(-0.25f, 0f, 0f), new Vector3(0f, 0f, -0.25f),
            };
            var verts = new Vector3[6];
            verts[0] = top; verts[1] = bottom;
            for (int i = 0; i < 4; i++) verts[i + 2] = eq[i];
            var tris = new int[]
            {
                0,2,3, 0,3,4, 0,4,5, 0,5,2,
                1,3,2, 1,4,3, 1,5,4, 1,2,5,
            };
            var mesh = new Mesh { name = "FxDiamond" };
            mesh.vertices = verts;
            mesh.triangles = tris;
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }

        private static void ConfigureSmoke(ParticleSystem ps)
        {
            var main = ps.main;
            main.loop = false;
            main.playOnAwake = false;
            main.startLifetime = 2.2f;
            main.startSpeed = 0f;
            main.gravityModifier = 0f;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 128;
            var vel = ps.velocityOverLifetime;
            vel.enabled = true;
            vel.y = new ParticleSystem.MinMaxCurve(1.2f, 2.6f);
            var emission = ps.emission;
            emission.enabled = true;
            emission.rateOverTime = 14f;
            var shape = ps.shape;
            shape.enabled = true;
            shape.shapeType = ParticleSystemShapeType.Sphere;
            shape.radius = 1f;
            var sizeLife = ps.sizeOverLifetime;
            sizeLife.enabled = true;
            sizeLife.size = new ParticleSystem.MinMaxCurve(1f, 2.5f);
            var colLife = ps.colorOverLifetime;
            colLife.enabled = true;
            var grad = new Gradient();
            grad.SetKeys(
                new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                new[] { new GradientAlphaKey(0.75f, 0f), new GradientAlphaKey(0f, 1f) });
            colLife.color = new ParticleSystem.MinMaxGradient(grad);
        }
    }

    /// <summary>Pooled FX item: scale tween + fade + optional target follow, then auto-return.</summary>
    internal class FxItem : MonoBehaviour
    {
        public string PoolKey;
        public Renderer Rend;
        public ParticleSystem Smoke;
        public Transform Follow;
        public Vector3 FollowOffset;
        public bool Spin;
        /// <summary>When true, Update skips scale/fade/lifetime (caller owns the item).</summary>
        public bool HoldManual;

        private float _life;
        private float _maxLife;
        private Vector3 _startScale;
        private Vector3 _endScale;
        private bool _fade;
        private bool _isSmoke;
        private Color _baseColor = Color.white;
        private MaterialPropertyBlock _mpb;

        public void Play(float duration, Color color, Vector3 startScale, Vector3 endScale, bool fade)
        {
            _isSmoke = false;
            _life = _maxLife = Mathf.Max(duration, 0.01f);
            _baseColor = color;
            _startScale = startScale;
            _endScale = endScale;
            _fade = fade;
            transform.localScale = startScale;
            ApplyColor(color);
            enabled = true;
        }

        public void PlaySmoke(float duration, float radius, Color color)
        {
            _isSmoke = true;
            _life = _maxLife = Mathf.Max(duration + 2.4f, 0.01f);
            transform.localScale = Vector3.one;
            var ps = Smoke;
            var main = ps.main;
            main.duration = Mathf.Max(duration, 0.1f);
            var shape = ps.shape;
            shape.radius = radius * 0.45f;
            main.startSize = new ParticleSystem.MinMaxCurve(radius * 0.35f, radius * 0.7f);
            main.startColor = new ParticleSystem.MinMaxColor(color);
            ps.Play();
            enabled = true;
        }

        private void ApplyColor(Color c)
        {
            if (Rend == null) return;
            if (_mpb == null) _mpb = new MaterialPropertyBlock();
            Rend.GetPropertyBlock(_mpb);
            _mpb.SetColor("_Color", c);
            Rend.SetPropertyBlock(_mpb);
        }

        private void Update()
        {
            if (Follow != null)
            {
                transform.position = Follow.position + FollowOffset;
                if (Spin) transform.Rotate(0f, 120f * Time.deltaTime, 0f);
            }
            else if (Spin)
            {
                transform.Rotate(0f, 120f * Time.deltaTime, 0f);
            }
            if (HoldManual) return;
            _life -= Time.deltaTime;
            if (_isSmoke)
            {
                if (_life <= 0f)
                {
                    Smoke.Stop(true, ParticleSystemStopBehavior.StopEmitting);
                    ClassFx.Return(this);
                }
                return;
            }
            float k = 1f - Mathf.Clamp01(_life / _maxLife);
            transform.localScale = Vector3.Lerp(_startScale, _endScale, k);
            if (_fade)
            {
                Color c = _baseColor;
                c.a *= 1f - k;
                ApplyColor(c);
            }
            if (_life <= 0f)
            {
                Follow = null;
                ClassFx.Return(this);
            }
        }
    }

    internal class TimedDestroy : MonoBehaviour
    {
        public float Life = 1f;
        private void Update()
        {
            Life -= Time.deltaTime;
            if (Life <= 0f) Destroy(gameObject);
        }
    }
}
