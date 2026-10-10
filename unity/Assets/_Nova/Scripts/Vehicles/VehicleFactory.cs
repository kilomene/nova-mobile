using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Built vehicle model: root hierarchy plus the animated/painted parts the
    /// controller drives. Model forward = -Z (ported verbatim from Godot).
    /// Part groups are named for later art replacement: Body / Cabin / Details,
    /// Wheel_FL / Wheel_FR / ..., Turret, Gun, RotorMain, RotorTail, MountedGun.
    /// </summary>
    public sealed class VehicleModel
    {
        public VehicleType Type;
        public GameObject Root;
        public Transform Body;                 // visual root (banking applied here)
        public readonly List<Transform> WheelSpins = new List<Transform>();
        public readonly List<Transform> WheelSteers = new List<Transform>();
        public Transform RotorMain, RotorTail, Turret, Gun;
        public Vector3 SeatOffset, MuzzleOffset;
        public float Length, Width, Height;
        public readonly List<MeshRenderer> PaintRenderers = new List<MeshRenderer>();
        public string SkinName = "";
        public int SkinIndex;
    }

    /// <summary>
    /// Shared material templates ported from VehicleModels._mat() in Godot.
    /// Bodies use ProcTexture.VehiclePaint (paint + dirt speckle, tinted per skin).
    /// Glass is a real transparent material so cabins read through it.
    /// </summary>
    public static class VehicleMats
    {
        private struct Def
        {
            public Color Color;
            public float Metallic, Smoothness;
            public Color Emission;
            public float EmissionEnergy;
        }

        private static readonly Dictionary<string, Def> Defs = new Dictionary<string, Def>
        {
            { "paint_sedan",   new Def { Color = new Color(0.10f,0.22f,0.52f), Metallic = 0.75f, Smoothness = 0.68f } },
            { "paint_bike",    new Def { Color = new Color(0.55f,0.06f,0.08f), Metallic = 0.60f, Smoothness = 0.62f } },
            { "paint_truck",   new Def { Color = new Color(0.80f,0.82f,0.85f), Metallic = 0.30f, Smoothness = 0.50f } },
            { "paint_tank",    new Def { Color = new Color(0.25f,0.28f,0.16f), Metallic = 0.20f, Smoothness = 0.25f } },
            { "paint_heli",    new Def { Color = new Color(0.20f,0.22f,0.20f), Metallic = 0.45f, Smoothness = 0.45f } },
            { "paint_boat",    new Def { Color = new Color(0.86f,0.87f,0.88f), Metallic = 0.35f, Smoothness = 0.55f } },
            { "paint_hover",   new Def { Color = new Color(0.08f,0.09f,0.11f), Metallic = 0.80f, Smoothness = 0.70f } },
            { "paint_b2",      new Def { Color = new Color(0.05f,0.05f,0.06f), Metallic = 0.15f, Smoothness = 0.08f } },
            { "paint_suv",     new Def { Color = new Color(0.08f,0.22f,0.14f), Metallic = 0.70f, Smoothness = 0.65f } },
            { "paint_pickup",  new Def { Color = new Color(0.60f,0.25f,0.08f), Metallic = 0.60f, Smoothness = 0.60f } },
            { "paint_sport",   new Def { Color = new Color(0.70f,0.05f,0.05f), Metallic = 0.85f, Smoothness = 0.75f } },
            { "paint_atv",     new Def { Color = new Color(0.50f,0.08f,0.06f), Metallic = 0.40f, Smoothness = 0.50f } },
            { "paint_armored", new Def { Color = new Color(0.06f,0.06f,0.07f), Metallic = 0.50f, Smoothness = 0.20f } },
            { "paint_jeep",    new Def { Color = new Color(0.28f,0.30f,0.16f), Metallic = 0.25f, Smoothness = 0.30f } },
            { "bed_liner",     new Def { Color = new Color(0.09f,0.09f,0.10f), Metallic = 0.00f, Smoothness = 0.05f } },
            { "canvas",        new Def { Color = new Color(0.52f,0.47f,0.33f), Metallic = 0.00f, Smoothness = 0.05f } },
            { "rubber",        new Def { Color = new Color(0.05f,0.05f,0.05f), Metallic = 0.00f, Smoothness = 0.10f } },
            { "track",         new Def { Color = new Color(0.07f,0.07f,0.07f), Metallic = 0.35f, Smoothness = 0.20f } },
            { "metal_dark",    new Def { Color = new Color(0.18f,0.18f,0.20f), Metallic = 0.80f, Smoothness = 0.55f } },
            { "steel",         new Def { Color = new Color(0.45f,0.47f,0.50f), Metallic = 0.90f, Smoothness = 0.65f } },
            { "chrome",        new Def { Color = new Color(0.70f,0.72f,0.75f), Metallic = 1.00f, Smoothness = 0.85f } },
            { "deck_grey",     new Def { Color = new Color(0.35f,0.36f,0.38f), Metallic = 0.30f, Smoothness = 0.40f } },
            { "wood",          new Def { Color = new Color(0.50f,0.34f,0.18f), Metallic = 0.00f, Smoothness = 0.30f } },
            { "griptape",      new Def { Color = new Color(0.08f,0.08f,0.08f), Metallic = 0.00f, Smoothness = 0.05f } },
            { "urethane",      new Def { Color = new Color(0.85f,0.78f,0.62f), Metallic = 0.00f, Smoothness = 0.45f } },
            { "accent_orange", new Def { Color = new Color(0.85f,0.35f,0.08f), Metallic = 0.30f, Smoothness = 0.50f } },
            { "light_head",    new Def { Color = new Color(0.90f,0.95f,1.00f), Metallic = 0.00f, Smoothness = 0.50f, Emission = new Color(0.90f,0.95f,1.00f), EmissionEnergy = 2.0f } },
            { "light_tail",    new Def { Color = new Color(0.70f,0.05f,0.05f), Metallic = 0.00f, Smoothness = 0.50f, Emission = new Color(1.00f,0.08f,0.08f), EmissionEnergy = 2.0f } },
            { "glow_cyan",     new Def { Color = new Color(0.10f,0.80f,0.90f), Metallic = 0.00f, Smoothness = 0.50f, Emission = new Color(0.10f,0.85f,1.00f), EmissionEnergy = 3.0f } },
            { "glow_orange",   new Def { Color = new Color(0.90f,0.45f,0.10f), Metallic = 0.00f, Smoothness = 0.50f, Emission = new Color(1.00f,0.50f,0.10f), EmissionEnergy = 2.5f } },
            { "nav_red",       new Def { Color = new Color(0.60f,0.05f,0.05f), Metallic = 0.00f, Smoothness = 0.50f, Emission = new Color(1.00f,0.05f,0.05f), EmissionEnergy = 2.0f } },
            { "nav_green",     new Def { Color = new Color(0.05f,0.60f,0.10f), Metallic = 0.00f, Smoothness = 0.50f, Emission = new Color(0.05f,1.00f,0.15f), EmissionEnergy = 2.0f } },
            { "nav_white",     new Def { Color = new Color(0.90f,0.90f,0.90f), Metallic = 0.00f, Smoothness = 0.50f, Emission = new Color(1.00f,1.00f,1.00f), EmissionEnergy = 2.0f } },
        };

        private static readonly Dictionary<string, Material> Cache = new Dictionary<string, Material>();
        private static readonly Dictionary<string, Material> SkinCache = new Dictionary<string, Material>();
        private static Material _charred;
        private static Texture2D _paintTex;

        /// <summary>Shared paint texture: white base + grain + dirt speckle low on the body.</summary>
        public static Texture2D PaintTexture()
        {
            if (_paintTex == null)
                _paintTex = ProcTexture.VehiclePaint(Color.white, 256, 67);
            return _paintTex;
        }

        private static Material Make(Color color, float metallic, float smoothness,
            Color emission, float energy, bool transparent, Texture2D tex)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = color;
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Glossiness", smoothness);
            if (tex != null) m.SetTexture("_MainTex", tex);
            if (energy > 0f)
            {
                m.SetColor("_EmissionColor", emission * energy);
                m.EnableKeyword("_EMISSION");
            }
            if (transparent)
            {
                m.SetFloat("_Mode", 3f);
                m.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
                m.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                m.SetInt("_ZWrite", 0);
                m.DisableKeyword("_ALPHATEST_ON");
                m.EnableKeyword("_ALPHABLEND_ON");
                m.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                m.renderQueue = 3000;
            }
            return m;
        }

        public static Material Get(string key)
        {
            if (Cache.TryGetValue(key, out Material m)) return m;
            if (key == "glass")
            {
                // Real transparent cabin glass: dark tint, see-through.
                m = Make(new Color(0.10f, 0.16f, 0.22f, 0.42f), 0.9f, 0.9f,
                    Color.black, 0f, true, null);
                Cache[key] = m;
                return m;
            }
            if (!Defs.TryGetValue(key, out Def d))
                d = new Def { Color = new Color(0.12f, 0.12f, 0.13f), Metallic = 0.5f, Smoothness = 0.5f };
            m = Make(d.Color, d.Metallic, d.Smoothness, d.Emission, d.EmissionEnergy, false, null);
            Cache[key] = m;
            return m;
        }

        /// <summary>Per-(type, skin) shared paint material: paint texture tinted by skin color.</summary>
        public static Material Skin(VehicleType t, int idx)
        {
            string key = t + "_" + idx;
            if (SkinCache.TryGetValue(key, out Material m)) return m;
            SkinDef s = VehicleSkins.Get(t, idx);
            m = Make(s.Color, s.Metallic, s.Smoothness, Color.black, 0f, false, PaintTexture());
            SkinCache[key] = m;
            return m;
        }

        public static Material Charred()
        {
            if (_charred == null)
                _charred = Make(new Color(0.12f, 0.10f, 0.09f), 0f, 0.10f, Color.black, 0f, false, null);
            return _charred;
        }
    }

    /// <summary>
    /// Parametric vehicle model factory. Ports vehicle_models.gd 1:1 for part layout
    /// (positions/sizes verbatim; model forward = -Z), with the CODM visual pass:
    /// transparent glass cabins + simple interiors, named part groups (Body/Cabin/
    /// Wheel_FL...), canvas-covered cargo bed, jeep pintle gun, ATV underglow,
    /// and the shared paint+dirt texture on all body paint.
    /// Parts are combined per material into single meshes for draw-call sanity.
    /// </summary>
    public static class VehicleFactory
    {
        private const float R2D = 57.29578f;
        // Godot axis constants (Godot FORWARD = -Z, matching our model convention).
        private static readonly Vector3 AX_UP = Vector3.up;
        private static readonly Vector3 AX_RIGHT = Vector3.right;
        private static readonly Vector3 AX_FWD = new Vector3(0f, 0f, -1f);

        // Accumulates MeshBuilder parts per material key, then combines each key
        // into one child mesh under the pivot. Flush in named groups (Body/Cabin/...)
        // so art can replace parts 1:1 later.
        private sealed class B
        {
            public readonly Transform Parent;
            private readonly VehicleModel _model;
            private readonly string _paintKey;
            private readonly Dictionary<string, List<MeshBuilder.Part>> _parts = new Dictionary<string, List<MeshBuilder.Part>>();

            public B(Transform parent, VehicleModel model, string paintKey)
            {
                Parent = parent;
                _model = model;
                _paintKey = paintKey;
            }

            private void Add(string mat, MeshBuilder.Part p)
            {
                if (!_parts.TryGetValue(mat, out List<MeshBuilder.Part> l))
                {
                    l = new List<MeshBuilder.Part>();
                    _parts[mat] = l;
                }
                l.Add(p);
            }

            public void Box(string mat, Vector3 size, Vector3 center)
            {
                Add(mat, MeshBuilder.Box(size, center, Quaternion.identity));
            }

            public void Box(string mat, Vector3 size, Vector3 center, Vector3 eulerRad)
            {
                Add(mat, MeshBuilder.Box(size, center,
                    Quaternion.Euler(eulerRad.x * R2D, eulerRad.y * R2D, eulerRad.z * R2D)));
            }

            public void Cyl(string mat, float radius, float height, Vector3 center, Vector3 axis, int segs)
            {
                Quaternion q = axis.sqrMagnitude > 0.0001f
                    ? Quaternion.FromToRotation(Vector3.up, axis.normalized)
                    : Quaternion.identity;
                Add(mat, MeshBuilder.Cylinder(radius, height, segs,
                    Matrix4x4.TRS(center, q, Vector3.one)));
            }

            public void Sph(string mat, float radius, Vector3 center, int segs = 12, int rings = 8)
            {
                Add(mat, SpherePart(radius, center, segs, rings));
            }

            /// <summary>Flat emissive quad in the XZ plane (underglow etc.).</summary>
            public void QuadXZ(string mat, float size, Vector3 center)
            {
                Add(mat, MeshBuilder.GroundQuad(size, Matrix4x4.TRS(center, Quaternion.identity, Vector3.one)));
            }

            public void FlushGroup(string group)
            {
                foreach (var kv in _parts)
                {
                    Mesh mesh = MeshBuilder.Combine(kv.Value);
                    ApplyPlanarUV(mesh, 0.25f);
                    var go = new GameObject(group + "_" + kv.Key);
                    var mf = go.AddComponent<MeshFilter>();
                    mf.mesh = mesh;
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.sharedMaterial = VehicleMats.Get(kv.Key);
                    go.transform.SetParent(Parent, false);
                    if (_model != null && kv.Key == _paintKey)
                        _model.PaintRenderers.Add(mr);
                }
                _parts.Clear();
            }
        }

        /// <summary>
        /// MeshBuilder leaves UVs at zero; give every combined mesh planar UVs so the
        /// paint texture (dirt low on the body via v) actually maps.
        /// </summary>
        private static void ApplyPlanarUV(Mesh mesh, float tiling)
        {
            Vector3[] verts = mesh.vertices;
            var uv = new Vector2[verts.Length];
            for (int i = 0; i < verts.Length; i++)
                uv[i] = new Vector2((verts[i].x + verts[i].z) * tiling, verts[i].y * tiling);
            mesh.uv = uv;
        }

        private static MeshBuilder.Part SpherePart(float radius, Vector3 center, int segs, int rings)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int r = 0; r <= rings; r++)
            {
                float v = (float)r / rings;
                float phi = v * Mathf.PI;
                float y = Mathf.Cos(phi);
                float rr = Mathf.Sin(phi);
                for (int s = 0; s <= segs; s++)
                {
                    float u = (float)s / segs;
                    float theta = u * Mathf.PI * 2f;
                    Vector3 n = new Vector3(rr * Mathf.Cos(theta), y, rr * Mathf.Sin(theta));
                    verts.Add(center + n * radius);
                    normals.Add(n);
                    uvs.Add(new Vector2(u, v));
                }
            }
            for (int r = 0; r < rings; r++)
            {
                for (int s = 0; s < segs; s++)
                {
                    int a = r * (segs + 1) + s;
                    int b = a + segs + 1;
                    tris.Add(a); tris.Add(a + 1); tris.Add(b);
                    tris.Add(b); tris.Add(a + 1); tris.Add(b + 1);
                }
            }
            return new MeshBuilder.Part
            {
                Verts = verts.ToArray(), Tris = tris.ToArray(),
                Normals = normals.ToArray(), Uv = uvs.ToArray(), Matrix = Matrix4x4.identity
            };
        }

        // Wheel assembly: steer pivot -> spin pivot -> tire + hub meshes.
        // Tires are cylinders along local X so wheel spin = local rotation.x.
        private static void Wheel(VehicleModel m, B b, string name, float radius, float width, Vector3 pos,
            bool steer, string tireMat = "rubber", string hubMat = "steel", Action<B> extraTire = null)
        {
            var steerGo = new GameObject(name);
            steerGo.transform.SetParent(b.Parent, false);
            steerGo.transform.localPosition = pos;
            var spinGo = new GameObject(name + "_Spin");
            spinGo.transform.SetParent(steerGo.transform, false);
            var wb = new B(spinGo.transform, m, null);
            wb.Cyl(tireMat, radius, width, Vector3.zero, AX_RIGHT, 14);
            wb.Cyl(hubMat, radius * 0.55f, width + 0.03f, Vector3.zero, AX_RIGHT, 10);
            if (extraTire != null) extraTire(wb);
            wb.FlushGroup(name);
            if (steer) m.WheelSteers.Add(steerGo.transform);
            m.WheelSpins.Add(spinGo.transform);
        }

        private static GameObject Pivot(Transform parent, string name, Vector3 localPos)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            return go;
        }

        // Minimal cabin interior (dashboard + seats) so transparent glass shows a cabin, not a void.
        private static void CabinInterior(B b, float dashZ, float seatY, float seatZ, float halfWidth)
        {
            string D = "metal_dark";
            b.Box(D, new Vector3(halfWidth * 1.7f, 0.22f, 0.45f), new Vector3(0f, seatY + 0.35f, dashZ));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.5f, 0.18f, 0.5f), new Vector3(sx * halfWidth * 0.5f, seatY, seatZ));
                b.Box(D, new Vector3(0.5f, 0.55f, 0.16f), new Vector3(sx * halfWidth * 0.5f, seatY + 0.32f, seatZ + 0.3f));
            }
        }

        private static string PaintKey(VehicleType t)
        {
            switch (t)
            {
                case VehicleType.Sedan: return "paint_sedan";
                case VehicleType.SUV: return "paint_suv";
                case VehicleType.Pickup: return "paint_pickup";
                case VehicleType.SportsCar: return "paint_sport";
                case VehicleType.ATV: return "paint_atv";
                case VehicleType.ArmoredSUV: return "paint_armored";
                case VehicleType.Jeep: return "paint_jeep";
                case VehicleType.Motorcycle: return "paint_bike";
                case VehicleType.CargoTruck: return "paint_truck";
                case VehicleType.Tank: return "paint_tank";
                case VehicleType.Helicopter: return "paint_heli";
                case VehicleType.Boat: return "paint_boat";
                case VehicleType.HoverBike: return "paint_hover";
                case VehicleType.Skateboard: return "wood";
                case VehicleType.B2Bomber: return "paint_b2";
                default: return "paint_sedan";
            }
        }

        /// <summary>Build a full vehicle model. skinIndex &lt; 0 = random.</summary>
        public static VehicleModel Build(VehicleType type, int skinIndex = -1)
        {
            var model = new VehicleModel { Type = type };
            var root = new GameObject("Vehicle_" + type);
            model.Root = root;
            var body = new GameObject("Body");
            body.transform.SetParent(root.transform, false);
            model.Body = body.transform;
            var b = new B(body.transform, model, PaintKey(type));

            switch (type)
            {
                case VehicleType.Sedan: BuildSedan(model, b); break;
                case VehicleType.Motorcycle: BuildBike(model, b); break;
                case VehicleType.CargoTruck: BuildTruck(model, b); break;
                case VehicleType.Tank: BuildTank(model, b); break;
                case VehicleType.Helicopter: BuildHeli(model, b); break;
                case VehicleType.Boat: BuildBoat(model, b); break;
                case VehicleType.HoverBike: BuildHoverbike(model, b); break;
                case VehicleType.Skateboard: BuildSkateboard(model, b); break;
                case VehicleType.B2Bomber: BuildB2(model, b); break;
                case VehicleType.SUV: BuildSuv(model, b); break;
                case VehicleType.Pickup: BuildPickup(model, b); break;
                case VehicleType.SportsCar: BuildSportscar(model, b); break;
                case VehicleType.ATV: BuildAtv(model, b); break;
                case VehicleType.ArmoredSUV: BuildArmoredSuv(model, b); break;
                case VehicleType.Jeep: BuildJeep(model, b); break;
            }

            if (skinIndex < 0) skinIndex = VehicleSkins.RandomIndex(type);
            model.SkinIndex = skinIndex;
            model.SkinName = VehicleSkins.Get(type, skinIndex).Name;
            VehicleSkins.Apply(model, type, skinIndex);
            return model;
        }

        // ------------------------------------------------------------- sedan
        private static void BuildSedan(VehicleModel m, B b)
        {
            string P = "paint_sedan", G = "glass", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_FL", 0.34f, 0.24f, new Vector3(-0.78f, 0.34f, -1.45f), true, R, S);
            Wheel(m, b, "Wheel_FR", 0.34f, 0.24f, new Vector3(0.78f, 0.34f, -1.45f), true, R, S);
            Wheel(m, b, "Wheel_RL", 0.34f, 0.24f, new Vector3(-0.78f, 0.34f, 1.45f), false, R, S);
            Wheel(m, b, "Wheel_RR", 0.34f, 0.24f, new Vector3(0.78f, 0.34f, 1.45f), false, R, S);
            // Body shell.
            b.Box(P, new Vector3(1.8f, 0.62f, 4.6f), new Vector3(0f, 0.66f, 0f));
            b.Box(P, new Vector3(1.7f, 0.16f, 1.25f), new Vector3(0f, 0.99f, -1.55f));
            b.Box(P, new Vector3(1.7f, 0.18f, 1.05f), new Vector3(0f, 0.98f, 1.65f));
            b.Box(P, new Vector3(1.62f, 0.07f, 1.6f), new Vector3(0f, 1.46f, 0.35f)); // roof panel
            b.Box(D, new Vector3(1.82f, 0.28f, 0.3f), new Vector3(0f, 0.5f, -2.32f));
            b.Box(D, new Vector3(1.82f, 0.28f, 0.3f), new Vector3(0f, 0.5f, 2.32f));
            b.Box(D, new Vector3(1.0f, 0.18f, 0.08f), new Vector3(0f, 0.72f, -2.34f)); // grille
            b.Box("paint_truck", new Vector3(0.44f, 0.12f, 0.02f), new Vector3(0f, 0.62f, 2.48f)); // plate
            b.Box("light_head", new Vector3(0.42f, 0.14f, 0.08f), new Vector3(-0.6f, 0.82f, -2.31f));
            b.Box("light_head", new Vector3(0.42f, 0.14f, 0.08f), new Vector3(0.6f, 0.82f, -2.31f));
            b.Box("light_tail", new Vector3(0.4f, 0.14f, 0.08f), new Vector3(-0.6f, 0.85f, 2.31f));
            b.Box("light_tail", new Vector3(0.4f, 0.14f, 0.08f), new Vector3(0.6f, 0.85f, 2.31f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.1f, 0.05f, 0.12f), new Vector3(sx * 0.92f, 1.12f, -0.75f));
                b.Box(P, new Vector3(0.07f, 0.12f, 0.14f), new Vector3(sx * 1.0f, 1.16f, -0.75f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 0.91f, 0.9f, -0.5f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 0.91f, 0.9f, 0.55f));
            }
            b.FlushGroup("Body");
            // Cabin: transparent glasshouse + interior.
            b.Box(G, new Vector3(1.55f, 0.48f, 2.5f), new Vector3(0f, 1.21f, 0.15f));
            b.Box(G, new Vector3(1.45f, 0.52f, 0.06f), new Vector3(0f, 1.18f, -1.08f), new Vector3(-0.45f, 0f, 0f));
            b.Box(G, new Vector3(1.45f, 0.42f, 0.06f), new Vector3(0f, 1.16f, 1.38f), new Vector3(0.5f, 0f, 0f));
            CabinInterior(b, -0.85f, 0.85f, 0.35f, 0.9f);
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0.45f, 1.1f, 0.3f);
            m.MuzzleOffset = new Vector3(0f, 0.8f, -2.45f);
            m.Length = 4.6f; m.Width = 1.8f; m.Height = 1.45f;
        }

        // -------------------------------------------------------------- bike
        private static void BuildBike(VehicleModel m, B b)
        {
            string P = "paint_bike", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_F", 0.31f, 0.12f, new Vector3(0f, 0.31f, -0.72f), true, R, S);
            Wheel(m, b, "Wheel_R", 0.31f, 0.14f, new Vector3(0f, 0.31f, 0.68f), false, R, S);
            b.Box(D, new Vector3(0.1f, 0.08f, 0.6f), new Vector3(-0.12f, 0.35f, 0.42f));
            b.Box(D, new Vector3(0.1f, 0.08f, 0.6f), new Vector3(0.12f, 0.35f, 0.42f));
            b.Box(D, new Vector3(0.4f, 0.35f, 0.5f), new Vector3(0f, 0.45f, 0.1f));
            b.Box(P, new Vector3(0.12f, 0.12f, 0.9f), new Vector3(0f, 0.65f, -0.05f));
            b.Box(P, new Vector3(0.38f, 0.28f, 0.55f), new Vector3(0f, 0.82f, -0.15f));
            b.Box(P, new Vector3(0.3f, 0.1f, 0.4f), new Vector3(0f, 0.99f, -0.15f));
            b.Box(R, new Vector3(0.32f, 0.1f, 0.5f), new Vector3(0f, 0.85f, 0.45f));
            b.Cyl(S, 0.035f, 0.85f, new Vector3(-0.09f, 0.62f, -0.7f), new Vector3(0f, 1f, -0.25f), 8);
            b.Cyl(S, 0.035f, 0.85f, new Vector3(0.09f, 0.62f, -0.7f), new Vector3(0f, 1f, -0.25f), 8);
            b.Cyl(S, 0.025f, 0.6f, new Vector3(0f, 1.0f, -0.78f), AX_RIGHT, 8);
            b.Cyl(R, 0.038f, 0.15f, new Vector3(-0.3f, 1.0f, -0.78f), AX_RIGHT, 8);
            b.Cyl(R, 0.038f, 0.15f, new Vector3(0.3f, 1.0f, -0.78f), AX_RIGHT, 8);
            b.Cyl(D, 0.1f, 0.12f, new Vector3(0f, 0.95f, -0.82f), AX_FWD, 12);
            b.Sph("light_head", 0.085f, new Vector3(0f, 0.95f, -0.88f));
            b.Cyl(S, 0.045f, 1.1f, new Vector3(0.22f, 0.35f, 0.15f), AX_FWD, 10);
            b.Cyl(S, 0.07f, 0.28f, new Vector3(0.22f, 0.35f, 0.68f), AX_FWD, 10);
            b.Box(P, new Vector3(0.16f, 0.05f, 0.5f), new Vector3(0f, 0.6f, -0.72f));
            b.Box(P, new Vector3(0.2f, 0.05f, 0.45f), new Vector3(0f, 0.6f, 0.68f));
            b.Box("light_tail", new Vector3(0.12f, 0.08f, 0.05f), new Vector3(0f, 0.68f, 0.92f));
            b.FlushGroup("Body");
            m.SeatOffset = new Vector3(0f, 0.95f, 0.45f);
            m.MuzzleOffset = new Vector3(0f, 0.95f, -1.0f);
            m.Length = 2.1f; m.Width = 0.7f; m.Height = 1.15f;
        }

        // ------------------------------------------------------------- truck
        private static void BuildTruck(VehicleModel m, B b)
        {
            string P = "paint_truck", G = "glass", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_FL", 0.5f, 0.36f, new Vector3(-0.95f, 0.5f, -2.9f), true, R, S);
            Wheel(m, b, "Wheel_FR", 0.5f, 0.36f, new Vector3(0.95f, 0.5f, -2.9f), true, R, S);
            Wheel(m, b, "Wheel_RL1", 0.5f, 0.4f, new Vector3(-0.95f, 0.5f, 1.3f), false, R, S);
            Wheel(m, b, "Wheel_RR1", 0.5f, 0.4f, new Vector3(0.95f, 0.5f, 1.3f), false, R, S);
            Wheel(m, b, "Wheel_RL2", 0.5f, 0.4f, new Vector3(-0.95f, 0.5f, 2.5f), false, R, S);
            Wheel(m, b, "Wheel_RR2", 0.5f, 0.4f, new Vector3(0.95f, 0.5f, 2.5f), false, R, S);
            // Body: chassis + cab.
            b.Box(D, new Vector3(1.6f, 0.3f, 7.2f), new Vector3(0f, 0.75f, 0f));
            b.Box(P, new Vector3(2.3f, 1.5f, 2.2f), new Vector3(0f, 1.75f, -2.4f));
            b.Box(P, new Vector3(2.35f, 0.1f, 2.25f), new Vector3(0f, 2.55f, -2.4f));
            b.Box("chrome", new Vector3(1.8f, 0.5f, 0.1f), new Vector3(0f, 1.25f, -3.52f));
            b.Box(D, new Vector3(2.4f, 0.35f, 0.25f), new Vector3(0f, 0.75f, -3.55f));
            b.Box("light_head", new Vector3(0.35f, 0.25f, 0.08f), new Vector3(-0.85f, 1.1f, -3.52f));
            b.Box("light_head", new Vector3(0.35f, 0.25f, 0.08f), new Vector3(0.85f, 1.1f, -3.52f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.25f, 0.05f, 0.05f), new Vector3(sx * 1.28f, 2.1f, -3.1f));
                b.Box(D, new Vector3(0.06f, 0.3f, 0.18f), new Vector3(sx * 1.42f, 2.0f, -3.1f));
            }
            // Canvas-covered bed: low walls + tarp + straps (distinct from a hard box van).
            b.Box(P, new Vector3(2.35f, 0.9f, 4.6f), new Vector3(0f, 1.3f, 1.0f)); // bed walls
            b.Box("canvas", new Vector3(2.45f, 1.15f, 4.7f), new Vector3(0f, 2.15f, 1.0f)); // tarp
            b.Box("canvas", new Vector3(2.5f, 0.25f, 4.75f), new Vector3(0f, 2.78f, 1.0f)); // tarp crown
            for (int i = 0; i < 5; i++)
                b.Box(D, new Vector3(2.52f, 1.2f, 0.09f), new Vector3(0f, 2.15f, -0.95f + i * 0.98f)); // straps
            b.Box(D, new Vector3(2.0f, 1.0f, 0.08f), new Vector3(0f, 1.6f, 3.36f)); // rear gate
            b.Box("light_tail", new Vector3(0.25f, 0.3f, 0.06f), new Vector3(-1.0f, 1.1f, 3.38f));
            b.Box("light_tail", new Vector3(0.25f, 0.3f, 0.06f), new Vector3(1.0f, 1.1f, 3.38f));
            b.FlushGroup("Body");
            // Cabin: transparent windshield + side glass + interior.
            b.Box(G, new Vector3(2.0f, 0.7f, 0.08f), new Vector3(0f, 1.95f, -3.44f), new Vector3(-0.12f, 0f, 0f));
            b.Box(G, new Vector3(0.06f, 0.5f, 0.8f), new Vector3(-1.16f, 1.95f, -2.5f));
            b.Box(G, new Vector3(0.06f, 0.5f, 0.8f), new Vector3(1.16f, 1.95f, -2.5f));
            CabinInterior(b, -3.0f, 1.35f, -2.2f, 1.0f);
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0.55f, 2.0f, -2.6f);
            m.MuzzleOffset = new Vector3(0f, 1.2f, -3.8f);
            m.Length = 7.6f; m.Width = 2.4f; m.Height = 3.1f;
        }

        // -------------------------------------------------------------- tank
        private static void BuildTank(VehicleModel m, B b)
        {
            string P = "paint_tank", D = "metal_dark";
            b.Box("track", new Vector3(0.85f, 1.0f, 7.2f), new Vector3(-1.35f, 0.5f, 0f));
            b.Box("track", new Vector3(0.85f, 1.0f, 7.2f), new Vector3(1.35f, 0.5f, 0f));
            float[] wzs = { -2.8f, -1.4f, 0f, 1.4f, 2.8f };
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                for (int wi = 0; wi < wzs.Length; wi++)
                    b.Cyl(D, 0.32f, 0.92f, new Vector3(sx * 1.35f, 0.42f, wzs[wi]), AX_RIGHT, 12);
            }
            b.Box(P, new Vector3(0.95f, 0.12f, 7.3f), new Vector3(-1.35f, 1.06f, 0f));
            b.Box(P, new Vector3(0.95f, 0.12f, 7.3f), new Vector3(1.35f, 1.06f, 0f));
            b.Box(P, new Vector3(2.9f, 0.9f, 7.0f), new Vector3(0f, 1.35f, 0f));
            b.Box(P, new Vector3(2.9f, 0.25f, 1.8f), new Vector3(0f, 1.62f, -3.35f), new Vector3(0.6f, 0f, 0f));
            b.Box(P, new Vector3(2.7f, 0.25f, 6.8f), new Vector3(0f, 1.92f, 0f));
            b.Box(P, new Vector3(2.7f, 0.2f, 1.0f), new Vector3(0f, 2.05f, 3.0f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.2f, 0.28f, 0.15f), new Vector3(sx * 0.9f, 1.95f, -3.25f));
                b.Box("light_head", new Vector3(0.14f, 0.12f, 0.05f), new Vector3(sx * 0.9f, 1.95f, -3.34f));
            }
            b.FlushGroup("Body");
            // Turret (rotating).
            GameObject turret = Pivot(b.Parent, "Turret", new Vector3(0f, 2.05f, 0.4f));
            m.Turret = turret.transform;
            var tb = new B(turret.transform, m, PaintKey(m.Type));
            tb.Cyl(P, 1.05f, 0.25f, new Vector3(0f, 0.12f, 0f), AX_UP, 14);
            tb.Box(P, new Vector3(2.1f, 0.65f, 2.9f), new Vector3(0f, 0.55f, 0.1f));
            tb.Box(P, new Vector3(1.9f, 0.55f, 0.9f), new Vector3(0f, 0.52f, -1.3f), new Vector3(0.35f, 0f, 0f));
            tb.Cyl(D, 0.3f, 0.12f, new Vector3(0.55f, 0.95f, 0.6f), AX_UP, 12);
            tb.Box(D, new Vector3(0.25f, 0.2f, 0.35f), new Vector3(-0.55f, 0.95f, -0.5f));
            tb.Cyl(D, 0.02f, 1.2f, new Vector3(-0.8f, 1.4f, 1.2f), AX_UP, 6);
            tb.FlushGroup("Turret");
            // Gun (elevating barrel).
            GameObject gun = Pivot(turret.transform, "Gun", new Vector3(0f, 0.55f, -1.5f));
            m.Gun = gun.transform;
            var gb = new B(gun.transform, m, PaintKey(m.Type));
            gb.Box(D, new Vector3(0.5f, 0.5f, 0.4f), new Vector3(0f, 0f, -0.1f));
            gb.Cyl(D, 0.11f, 3.6f, new Vector3(0f, 0f, -2.0f), AX_FWD, 12);
            gb.Cyl(D, 0.16f, 0.4f, new Vector3(0f, 0f, -3.7f), AX_FWD, 12);
            gb.FlushGroup("Gun");
            m.SeatOffset = new Vector3(0f, 2.6f, 1.0f);
            m.MuzzleOffset = new Vector3(0f, 2.6f, -5.0f);
            m.Length = 7.6f; m.Width = 3.6f; m.Height = 2.7f;
        }

        // -------------------------------------------------------------- heli
        private static void BuildHeli(VehicleModel m, B b)
        {
            string P = "paint_heli", G = "glass", D = "metal_dark", S = "steel";
            // Body: skids, fuselage, tail.
            b.Cyl(D, 0.05f, 3.6f, new Vector3(-0.9f, 0.05f, 0f), AX_FWD, 8);
            b.Cyl(D, 0.05f, 3.6f, new Vector3(0.9f, 0.05f, 0f), AX_FWD, 8);
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Cyl(D, 0.04f, 0.95f, new Vector3(sx * 0.9f, 0.5f, -1.2f), new Vector3(sx * 0.15f, 1f, 0f), 6);
                b.Cyl(D, 0.04f, 0.95f, new Vector3(sx * 0.9f, 0.5f, 1.2f), new Vector3(sx * 0.15f, 1f, 0f), 6);
            }
            b.Box(P, new Vector3(1.6f, 0.5f, 4.5f), new Vector3(0f, 1.0f, 0.2f));
            b.Box(P, new Vector3(1.8f, 1.4f, 5.5f), new Vector3(0f, 1.9f, 0f));
            b.Box(P, new Vector3(1.7f, 1.1f, 1.5f), new Vector3(0f, 1.72f, -3.2f), new Vector3(-0.25f, 0f, 0f));
            b.Box(P, new Vector3(1.6f, 0.5f, 2.5f), new Vector3(0f, 2.75f, 0.3f));
            b.Cyl(D, 0.14f, 0.6f, new Vector3(-0.5f, 2.6f, 1.6f), AX_FWD, 10);
            b.Cyl(D, 0.14f, 0.6f, new Vector3(0.5f, 2.6f, 1.6f), AX_FWD, 10);
            b.Cyl(P, 0.28f, 3.0f, new Vector3(0f, 2.0f, 4.0f), AX_FWD, 10);
            b.Cyl(P, 0.18f, 2.5f, new Vector3(0f, 2.0f, 6.6f), AX_FWD, 10);
            b.Box(P, new Vector3(0.12f, 1.6f, 1.0f), new Vector3(0f, 2.8f, 7.2f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(P, new Vector3(1.4f, 0.12f, 0.8f), new Vector3(sx * 1.5f, 1.6f, -0.3f));
                b.Box(D, new Vector3(0.12f, 0.3f, 0.6f), new Vector3(sx * 1.5f, 1.4f, -0.3f));
                b.Cyl(S, 0.06f, 0.9f, new Vector3(sx * 1.5f - 0.35f, 1.35f, -0.55f), AX_FWD, 8);
                b.Cyl(S, 0.06f, 0.9f, new Vector3(sx * 1.5f + 0.35f, 1.35f, -0.55f), AX_FWD, 8);
            }
            b.Box("nav_red", new Vector3(0.12f, 0.1f, 0.12f), new Vector3(-2.25f, 1.6f, -0.3f));
            b.Box("nav_green", new Vector3(0.12f, 0.1f, 0.12f), new Vector3(2.25f, 1.6f, -0.3f));
            b.FlushGroup("Body");
            // Cabin: transparent cockpit + seats.
            b.Box(G, new Vector3(1.55f, 0.75f, 1.8f), new Vector3(0f, 2.05f, -2.5f));
            CabinInterior(b, -3.1f, 1.7f, -1.4f, 0.8f);
            b.FlushGroup("Cabin");
            // Tail rotor (spins on local X).
            GameObject rt = Pivot(b.Parent, "RotorTail", new Vector3(-0.16f, 2.6f, 7.3f));
            m.RotorTail = rt.transform;
            var rtb = new B(rt.transform, m, PaintKey(m.Type));
            rtb.Cyl(D, 0.08f, 0.24f, Vector3.zero, AX_RIGHT, 8);
            rtb.Box(D, new Vector3(0.06f, 1.0f, 0.14f), new Vector3(0f, 0.5f, 0f));
            rtb.Box(D, new Vector3(0.06f, 1.0f, 0.14f), new Vector3(0f, -0.5f, 0f));
            rtb.FlushGroup("RotorTail");
            // Main mast + rotor (spins on local Y).
            var mastB = new B(b.Parent, m, PaintKey(m.Type));
            mastB.Cyl(D, 0.12f, 0.8f, new Vector3(0f, 3.1f, 0.3f), AX_UP, 10);
            mastB.FlushGroup("Body");
            GameObject rm = Pivot(b.Parent, "RotorMain", new Vector3(0f, 3.55f, 0.3f));
            m.RotorMain = rm.transform;
            var rmb = new B(rm.transform, m, PaintKey(m.Type));
            rmb.Sph(D, 0.18f, Vector3.zero);
            rmb.Box(D, new Vector3(0.3f, 0.05f, 9.4f), Vector3.zero);
            rmb.Box(D, new Vector3(9.4f, 0.05f, 0.3f), Vector3.zero);
            rmb.FlushGroup("RotorMain");
            m.SeatOffset = new Vector3(0f, 2.0f, -0.8f);
            m.MuzzleOffset = new Vector3(0f, 1.8f, -4.1f);
            m.Length = 8.0f; m.Width = 2.2f; m.Height = 3.7f;
        }

        // -------------------------------------------------------------- boat
        private static void BuildBoat(VehicleModel m, B b)
        {
            string P = "paint_boat", G = "glass", D = "metal_dark", S = "steel";
            // V-hull.
            b.Box(P, new Vector3(2.0f, 0.5f, 6.5f), new Vector3(0f, 0.35f, 0.3f));
            b.Box(P, new Vector3(0.25f, 0.9f, 6.5f), new Vector3(-1.05f, 0.75f, 0.3f), new Vector3(0f, 0f, 0.15f));
            b.Box(P, new Vector3(0.25f, 0.9f, 6.5f), new Vector3(1.05f, 0.75f, 0.3f), new Vector3(0f, 0f, -0.15f));
            b.Box(P, new Vector3(2.3f, 0.9f, 0.25f), new Vector3(0f, 0.75f, 3.4f));
            b.Box(P, new Vector3(1.3f, 0.85f, 1.8f), new Vector3(0.55f, 0.7f, -3.4f), new Vector3(0f, 0.5f, 0f));
            b.Box(P, new Vector3(1.3f, 0.85f, 1.8f), new Vector3(-0.55f, 0.7f, -3.4f), new Vector3(0f, -0.5f, 0f));
            b.Box("accent_orange", new Vector3(2.36f, 0.15f, 6.6f), new Vector3(0f, 0.9f, 0.3f)); // stripe
            b.Box("deck_grey", new Vector3(1.9f, 0.1f, 6.2f), new Vector3(0f, 1.18f, 0.3f));
            b.Box(P, new Vector3(0.8f, 0.9f, 0.6f), new Vector3(0f, 1.65f, 0.6f)); // console
            b.Box(D, new Vector3(0.55f, 0.55f, 0.45f), new Vector3(0f, 1.5f, 1.15f)); // helm seat
            // Outboard motor.
            b.Box(P, new Vector3(0.55f, 0.5f, 0.6f), new Vector3(0f, 1.5f, 3.7f));
            b.Box(D, new Vector3(0.5f, 0.7f, 0.4f), new Vector3(0f, 1.0f, 3.7f));
            b.Cyl(D, 0.08f, 0.9f, new Vector3(0f, 0.45f, 3.78f), AX_UP, 8);
            // Bow rails + cleats.
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Cyl(S, 0.025f, 0.5f, new Vector3(sx * 0.8f, 1.45f, -2.6f), AX_UP, 6);
                b.Cyl(S, 0.025f, 0.5f, new Vector3(sx * 0.8f, 1.45f, -3.3f), AX_UP, 6);
                b.Cyl(S, 0.025f, 1.4f, new Vector3(sx * 0.8f, 1.7f, -2.95f), AX_FWD, 6);
                b.Box(S, new Vector3(0.12f, 0.06f, 0.05f), new Vector3(sx * 0.95f, 1.26f, -1.5f));
                b.Box(S, new Vector3(0.12f, 0.06f, 0.05f), new Vector3(sx * 0.95f, 1.26f, 1.5f));
            }
            b.FlushGroup("Body");
            // Cabin: transparent windshield.
            b.Box(G, new Vector3(0.9f, 0.45f, 0.06f), new Vector3(0f, 2.25f, 0.32f), new Vector3(-0.2f, 0f, 0f));
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0f, 1.7f, 1.15f);
            m.MuzzleOffset = new Vector3(0f, 1.0f, -4.2f);
            m.Length = 7.5f; m.Width = 2.6f; m.Height = 2.3f;
        }

        // ---------------------------------------------------------- hoverbike
        private static void BuildHoverbike(VehicleModel m, B b)
        {
            string P = "paint_hover", D = "metal_dark", R = "rubber";
            b.Box(P, new Vector3(0.5f, 0.3f, 1.6f), new Vector3(0f, 0.7f, 0f));
            b.Box(P, new Vector3(0.45f, 0.25f, 0.8f), new Vector3(0f, 0.62f, -1.0f), new Vector3(0.15f, 0f, 0f));
            b.Box(P, new Vector3(0.55f, 0.35f, 0.5f), new Vector3(0f, 0.72f, 0.9f));
            b.Box("glow_cyan", new Vector3(0.04f, 0.06f, 1.4f), new Vector3(-0.26f, 0.72f, 0f));
            b.Box("glow_cyan", new Vector3(0.04f, 0.06f, 1.4f), new Vector3(0.26f, 0.72f, 0f));
            b.Box(R, new Vector3(0.4f, 0.12f, 0.7f), new Vector3(0f, 0.92f, 0.25f)); // seat
            b.Box(D, new Vector3(0.08f, 0.35f, 0.08f), new Vector3(0f, 0.85f, -0.55f));
            b.Cyl(D, 0.03f, 0.7f, new Vector3(0f, 1.0f, -0.55f), AX_RIGHT, 8);
            b.Cyl(R, 0.04f, 0.16f, new Vector3(-0.32f, 1.0f, -0.55f), AX_RIGHT, 8);
            b.Cyl(R, 0.04f, 0.16f, new Vector3(0.32f, 1.0f, -0.55f), AX_RIGHT, 8);
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                for (int pi = 0; pi < 2; pi++)
                {
                    float pz = pi == 0 ? -0.7f : 0.7f;
                    b.Box(D, new Vector3(0.4f, 0.08f, 0.12f), new Vector3(sx * 0.2f, 0.45f, pz));
                    b.Box(D, new Vector3(0.36f, 0.1f, 0.5f), new Vector3(sx * 0.35f, 0.32f, pz));
                    b.Box("glow_cyan", new Vector3(0.3f, 0.12f, 0.45f), new Vector3(sx * 0.35f, 0.18f, pz));
                }
            }
            b.Cyl(D, 0.12f, 0.3f, new Vector3(0f, 0.7f, 1.2f), AX_FWD, 10);
            b.Cyl("glow_orange", 0.1f, 0.08f, new Vector3(0f, 0.7f, 1.38f), AX_FWD, 10);
            b.FlushGroup("Body");
            m.SeatOffset = new Vector3(0f, 1.05f, 0.25f);
            m.MuzzleOffset = new Vector3(0f, 0.7f, -1.45f);
            m.Length = 2.4f; m.Width = 0.9f; m.Height = 1.1f;
        }

        // ---------------------------------------------------------- skateboard
        private static void BuildSkateboard(VehicleModel m, B b)
        {
            string W = "wood", D = "metal_dark", U = "urethane";
            b.Box(W, new Vector3(0.21f, 0.03f, 0.8f), new Vector3(0f, 0.1f, 0f));
            b.Box("griptape", new Vector3(0.215f, 0.012f, 0.79f), new Vector3(0f, 0.118f, 0f));
            b.Box(W, new Vector3(0.21f, 0.03f, 0.12f), new Vector3(0f, 0.12f, -0.44f), new Vector3(-0.35f, 0f, 0f));
            b.Box(W, new Vector3(0.21f, 0.03f, 0.12f), new Vector3(0f, 0.12f, 0.44f), new Vector3(0.35f, 0f, 0f));
            b.Box(D, new Vector3(0.16f, 0.04f, 0.1f), new Vector3(0f, 0.07f, -0.28f));
            b.Box(D, new Vector3(0.16f, 0.04f, 0.1f), new Vector3(0f, 0.07f, 0.28f));
            b.FlushGroup("Body");
            // 4 urethane wheels: spin pivots only, no steering.
            string[] names = { "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" };
            int ni = 0;
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                float[] wzs = { -0.28f, 0.28f };
                for (int wi = 0; wi < 2; wi++)
                {
                    var spinGo = new GameObject(names[ni] + "_Spin");
                    spinGo.transform.SetParent(b.Parent, false);
                    spinGo.transform.localPosition = new Vector3(sx * 0.09f, 0.035f, wzs[wi]);
                    var wb = new B(spinGo.transform, m, null);
                    wb.Cyl(U, 0.028f, 0.03f, Vector3.zero, AX_RIGHT, 10);
                    wb.FlushGroup(names[ni]);
                    m.WheelSpins.Add(spinGo.transform);
                    ni++;
                }
            }
            m.SeatOffset = new Vector3(0f, 0.16f, 0f);
            m.MuzzleOffset = new Vector3(0f, 0.1f, -0.45f);
            m.Length = 0.8f; m.Width = 0.21f; m.Height = 0.14f;
        }

        // ----------------------------------------------------------------- b2
        private static void BuildB2(VehicleModel m, B b)
        {
            string P = "paint_b2", G = "glass", D = "metal_dark";
            b.Box(P, new Vector3(4.0f, 0.9f, 8.0f), new Vector3(0f, 1.0f, 0.5f)); // center body
            b.Box(P, new Vector3(1.6f, 0.75f, 3.2f), new Vector3(0.7f, 1.0f, -4.2f), new Vector3(0f, 0.4f, 0f));
            b.Box(P, new Vector3(1.6f, 0.75f, 3.2f), new Vector3(-0.7f, 1.0f, -4.2f), new Vector3(0f, -0.4f, 0f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(P, new Vector3(5.0f, 0.55f, 5.5f), new Vector3(sx * 4.5f, 1.0f, 1.5f), new Vector3(0f, -sx * 0.35f, 0f));
                b.Box(P, new Vector3(4.5f, 0.45f, 3.5f), new Vector3(sx * 8.3f, 1.0f, 2.8f), new Vector3(0f, -sx * 0.35f, 0f));
            }
            // W double-V trailing edge.
            b.Box(P, new Vector3(2.5f, 0.4f, 1.2f), new Vector3(1.5f, 1.0f, 4.6f), new Vector3(0f, 0.5f, 0f));
            b.Box(P, new Vector3(2.5f, 0.4f, 1.2f), new Vector3(-1.5f, 1.0f, 4.6f), new Vector3(0f, -0.5f, 0f));
            b.Box(P, new Vector3(1.2f, 0.35f, 0.8f), new Vector3(0f, 1.0f, 4.9f));
            b.Box(P, new Vector3(1.2f, 0.55f, 2.2f), new Vector3(2.2f, 1.4f, -1.5f)); // intakes
            b.Box(P, new Vector3(1.2f, 0.55f, 2.2f), new Vector3(-2.2f, 1.4f, -1.5f));
            b.Box(D, new Vector3(2.4f, 0.08f, 3.0f), new Vector3(0f, 0.58f, 0.8f)); // bomb bay doors
            b.Box("nav_red", new Vector3(0.15f, 0.1f, 0.15f), new Vector3(-10.4f, 1.0f, 3.6f));
            b.Box("nav_green", new Vector3(0.15f, 0.1f, 0.15f), new Vector3(10.4f, 1.0f, 3.6f));
            b.Box("nav_white", new Vector3(0.15f, 0.1f, 0.15f), new Vector3(0f, 1.0f, 5.3f));
            b.FlushGroup("Body");
            // Cockpit: transparent tinted hump.
            b.Box(G, new Vector3(1.4f, 0.35f, 1.6f), new Vector3(0f, 1.55f, -2.5f));
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0f, 1.7f, -2.3f);
            m.MuzzleOffset = new Vector3(0f, 0.5f, 0.8f);
            m.Length = 10.5f; m.Width = 21.0f; m.Height = 1.8f;
        }

        // ---------------------------------------------------------------- suv
        private static void BuildSuv(VehicleModel m, B b)
        {
            string P = "paint_suv", G = "glass", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_FL", 0.42f, 0.3f, new Vector3(-0.88f, 0.42f, -1.55f), true, R, S);
            Wheel(m, b, "Wheel_FR", 0.42f, 0.3f, new Vector3(0.88f, 0.42f, -1.55f), true, R, S);
            Wheel(m, b, "Wheel_RL", 0.42f, 0.3f, new Vector3(-0.88f, 0.42f, 1.55f), false, R, S);
            Wheel(m, b, "Wheel_RR", 0.42f, 0.3f, new Vector3(0.88f, 0.42f, 1.55f), false, R, S);
            // Body: tall shell + hood.
            b.Box(P, new Vector3(2.0f, 0.75f, 5.0f), new Vector3(0f, 0.85f, 0f));
            b.Box(P, new Vector3(1.9f, 0.15f, 1.2f), new Vector3(0f, 1.25f, -1.8f));
            b.Box(P, new Vector3(1.9f, 0.08f, 4.4f), new Vector3(0f, 1.97f, 0.1f)); // roof
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(P, new Vector3(0.1f, 0.58f, 0.12f), new Vector3(sx * 0.9f, 1.62f, -1.6f));
                b.Box(P, new Vector3(0.1f, 0.58f, 0.12f), new Vector3(sx * 0.9f, 1.62f, 0.1f));
                b.Box(P, new Vector3(0.1f, 0.58f, 0.12f), new Vector3(sx * 0.9f, 1.62f, 1.8f));
                b.Cyl(D, 0.04f, 3.6f, new Vector3(sx * 0.7f, 2.06f, 0.1f), AX_FWD, 8); // roof rail
                b.Box(D, new Vector3(0.08f, 0.08f, 0.08f), new Vector3(sx * 0.7f, 2.01f, -1.4f));
                b.Box(D, new Vector3(0.08f, 0.08f, 0.08f), new Vector3(sx * 0.7f, 2.01f, 0.1f));
                b.Box(D, new Vector3(0.08f, 0.08f, 0.08f), new Vector3(sx * 0.7f, 2.01f, 1.6f));
            }
            b.Cyl(R, 0.4f, 0.25f, new Vector3(0f, 1.3f, 2.55f), AX_FWD, 14); // spare
            b.Cyl(S, 0.22f, 0.28f, new Vector3(0f, 1.3f, 2.55f), AX_FWD, 10);
            b.Box(P, new Vector3(0.9f, 0.9f, 0.1f), new Vector3(0f, 1.3f, 2.44f)); // rear door
            b.Box(D, new Vector3(0.25f, 0.08f, 3.0f), new Vector3(-1.05f, 0.45f, 0f)); // running boards
            b.Box(D, new Vector3(0.25f, 0.08f, 3.0f), new Vector3(1.05f, 0.45f, 0f));
            b.Box(D, new Vector3(2.0f, 0.3f, 0.3f), new Vector3(0f, 0.55f, -2.52f));
            b.Box(D, new Vector3(2.0f, 0.3f, 0.3f), new Vector3(0f, 0.55f, 2.52f));
            b.Box(D, new Vector3(1.2f, 0.22f, 0.08f), new Vector3(0f, 0.95f, -2.52f)); // grille
            b.Box("light_head", new Vector3(0.45f, 0.16f, 0.08f), new Vector3(-0.65f, 0.95f, -2.52f));
            b.Box("light_head", new Vector3(0.45f, 0.16f, 0.08f), new Vector3(0.65f, 0.95f, -2.52f));
            b.Box("light_tail", new Vector3(0.4f, 0.16f, 0.08f), new Vector3(-0.65f, 1.0f, 2.52f));
            b.Box("light_tail", new Vector3(0.4f, 0.16f, 0.08f), new Vector3(0.65f, 1.0f, 2.52f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.1f, 0.05f, 0.12f), new Vector3(sx * 1.02f, 1.5f, -1.7f));
                b.Box(P, new Vector3(0.07f, 0.12f, 0.15f), new Vector3(sx * 1.1f, 1.54f, -1.7f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 1.01f, 1.15f, -0.9f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 1.01f, 1.15f, 0.1f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 1.01f, 1.15f, 1.1f));
            }
            b.FlushGroup("Body");
            // Cabin: big transparent glass band + windshield + interior.
            b.Box(G, new Vector3(1.87f, 0.55f, 4.0f), new Vector3(0f, 1.62f, 0.1f));
            b.Box(G, new Vector3(1.8f, 0.6f, 0.06f), new Vector3(0f, 1.6f, -2.0f), new Vector3(-0.35f, 0f, 0f));
            CabinInterior(b, -1.7f, 1.05f, -0.3f, 1.0f);
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0.5f, 1.5f, -0.5f);
            m.MuzzleOffset = new Vector3(0f, 1.0f, -2.65f);
            m.Length = 5.0f; m.Width = 2.0f; m.Height = 1.95f;
        }

        // ------------------------------------------------------------- pickup
        private static void BuildPickup(VehicleModel m, B b)
        {
            string P = "paint_pickup", G = "glass", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_FL", 0.42f, 0.3f, new Vector3(-0.88f, 0.42f, -1.7f), true, R, S);
            Wheel(m, b, "Wheel_FR", 0.42f, 0.3f, new Vector3(0.88f, 0.42f, -1.7f), true, R, S);
            Wheel(m, b, "Wheel_RL", 0.42f, 0.3f, new Vector3(-0.88f, 0.42f, 1.75f), false, R, S);
            Wheel(m, b, "Wheel_RR", 0.42f, 0.3f, new Vector3(0.88f, 0.42f, 1.75f), false, R, S);
            // Body: chassis + crew cab + hood.
            b.Box(D, new Vector3(1.7f, 0.3f, 5.0f), new Vector3(0f, 0.7f, 0f));
            b.Box(P, new Vector3(1.95f, 0.85f, 1.8f), new Vector3(0f, 1.45f, -1.5f));
            b.Box(P, new Vector3(2.0f, 0.08f, 1.85f), new Vector3(0f, 1.9f, -1.5f)); // cab roof
            b.Box(P, new Vector3(1.85f, 0.18f, 1.0f), new Vector3(0f, 1.02f, -2.9f)); // hood
            // Textured open cargo bed: liner floor, paint walls, dark rail caps.
            b.Box("bed_liner", new Vector3(1.9f, 0.12f, 2.6f), new Vector3(0f, 1.0f, 0.9f));
            b.Box(P, new Vector3(0.12f, 0.55f, 2.6f), new Vector3(-0.95f, 1.3f, 0.9f));
            b.Box(P, new Vector3(0.12f, 0.55f, 2.6f), new Vector3(0.95f, 1.3f, 0.9f));
            b.Box(P, new Vector3(1.9f, 0.55f, 0.12f), new Vector3(0f, 1.3f, -0.35f));
            b.Box(P, new Vector3(1.9f, 0.55f, 0.12f), new Vector3(0f, 1.3f, 2.15f)); // tailgate
            b.Box(D, new Vector3(0.16f, 0.06f, 2.6f), new Vector3(-0.95f, 1.6f, 0.9f));
            b.Box(D, new Vector3(0.16f, 0.06f, 2.6f), new Vector3(0.95f, 1.6f, 0.9f));
            // Roll bar behind cab.
            b.Cyl(D, 0.05f, 0.9f, new Vector3(-0.7f, 1.45f, -0.4f), AX_UP, 8);
            b.Cyl(D, 0.05f, 0.9f, new Vector3(0.7f, 1.45f, -0.4f), AX_UP, 8);
            b.Cyl(D, 0.05f, 1.4f, new Vector3(0f, 1.9f, -0.4f), AX_RIGHT, 8);
            b.Box(D, new Vector3(1.6f, 0.4f, 0.1f), new Vector3(0f, 0.95f, -3.42f)); // grille
            b.Box(D, new Vector3(2.0f, 0.3f, 0.25f), new Vector3(0f, 0.6f, -3.45f)); // bumper
            b.Box("light_head", new Vector3(0.4f, 0.16f, 0.08f), new Vector3(-0.7f, 0.95f, -3.42f));
            b.Box("light_head", new Vector3(0.4f, 0.16f, 0.08f), new Vector3(0.7f, 0.95f, -3.42f));
            b.Box("light_tail", new Vector3(0.3f, 0.2f, 0.06f), new Vector3(-0.8f, 1.1f, 2.22f));
            b.Box("light_tail", new Vector3(0.3f, 0.2f, 0.06f), new Vector3(0.8f, 1.1f, 2.22f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.1f, 0.05f, 0.12f), new Vector3(sx * 1.0f, 1.5f, -2.2f));
                b.Box(P, new Vector3(0.07f, 0.12f, 0.15f), new Vector3(sx * 1.08f, 1.54f, -2.2f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 0.99f, 1.35f, -1.2f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 0.99f, 1.35f, -1.9f));
            }
            b.FlushGroup("Body");
            // Cabin: transparent glasshouse + windshield + interior.
            b.Box(G, new Vector3(1.97f, 0.5f, 1.6f), new Vector3(0f, 1.55f, -1.5f));
            b.Box(G, new Vector3(1.9f, 0.55f, 0.06f), new Vector3(0f, 1.5f, -2.42f), new Vector3(-0.25f, 0f, 0f));
            CabinInterior(b, -2.2f, 1.05f, -1.3f, 1.0f);
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0.5f, 1.5f, -1.5f);
            m.MuzzleOffset = new Vector3(0f, 1.0f, -2.85f);
            m.Length = 5.4f; m.Width = 2.0f; m.Height = 1.9f;
        }

        // ---------------------------------------------------------- sportscar
        private static void BuildSportscar(VehicleModel m, B b)
        {
            string P = "paint_sport", G = "glass", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_FL", 0.32f, 0.34f, new Vector3(-0.85f, 0.32f, -1.35f), true, R, S);
            Wheel(m, b, "Wheel_FR", 0.32f, 0.34f, new Vector3(0.85f, 0.32f, -1.35f), true, R, S);
            Wheel(m, b, "Wheel_RL", 0.32f, 0.36f, new Vector3(-0.85f, 0.32f, 1.35f), false, R, S);
            Wheel(m, b, "Wheel_RR", 0.32f, 0.36f, new Vector3(0.85f, 0.32f, 1.35f), false, R, S);
            // Low aero body.
            b.Box(P, new Vector3(1.9f, 0.45f, 4.4f), new Vector3(0f, 0.55f, 0f));
            b.Box(P, new Vector3(1.8f, 0.28f, 0.9f), new Vector3(0f, 0.48f, -2.15f), new Vector3(0.25f, 0f, 0f));
            b.Box(P, new Vector3(1.55f, 0.06f, 1.2f), new Vector3(0f, 1.13f, 0.35f)); // roof
            b.Box(D, new Vector3(0.5f, 0.08f, 0.6f), new Vector3(0f, 0.8f, -1.2f)); // hood scoop
            b.Box(D, new Vector3(0.08f, 0.25f, 0.7f), new Vector3(-0.97f, 0.55f, 0.5f)); // intakes
            b.Box(D, new Vector3(0.08f, 0.25f, 0.7f), new Vector3(0.97f, 0.55f, 0.5f));
            // Rear spoiler.
            b.Box(D, new Vector3(0.08f, 0.25f, 0.3f), new Vector3(-0.6f, 0.95f, 1.95f));
            b.Box(D, new Vector3(0.08f, 0.25f, 0.3f), new Vector3(0.6f, 0.95f, 1.95f));
            b.Box(P, new Vector3(1.7f, 0.06f, 0.4f), new Vector3(0f, 1.08f, 1.95f));
            b.Box("light_head", new Vector3(0.4f, 0.1f, 0.06f), new Vector3(-0.55f, 0.62f, -2.28f), new Vector3(0f, 0.2f, 0f));
            b.Box("light_head", new Vector3(0.4f, 0.1f, 0.06f), new Vector3(0.55f, 0.62f, -2.28f), new Vector3(0f, -0.2f, 0f));
            b.Box("light_tail", new Vector3(1.2f, 0.1f, 0.06f), new Vector3(0f, 0.68f, 2.21f)); // tail bar
            b.Box(D, new Vector3(1.6f, 0.15f, 0.4f), new Vector3(0f, 0.3f, 2.15f)); // diffuser
            float[] fxs = { -0.6f, -0.2f, 0.2f, 0.6f };
            for (int fi = 0; fi < fxs.Length; fi++)
                b.Box(D, new Vector3(0.05f, 0.15f, 0.35f), new Vector3(fxs[fi], 0.32f, 2.15f));
            b.Cyl(S, 0.05f, 0.2f, new Vector3(-0.3f, 0.35f, 2.28f), AX_FWD, 8);
            b.Cyl(S, 0.05f, 0.2f, new Vector3(0.3f, 0.35f, 2.28f), AX_FWD, 8);
            b.Box(D, new Vector3(0.1f, 0.12f, 2.6f), new Vector3(-0.98f, 0.38f, 0f)); // skirts
            b.Box(D, new Vector3(0.1f, 0.12f, 2.6f), new Vector3(0.98f, 0.38f, 0f));
            b.FlushGroup("Body");
            // Cabin: transparent canopy + seat.
            b.Box(G, new Vector3(1.5f, 0.38f, 2.0f), new Vector3(0f, 0.95f, 0.2f));
            b.Box(D, new Vector3(0.5f, 0.15f, 0.5f), new Vector3(0f, 0.7f, 0.35f)); // seat
            b.Box(D, new Vector3(0.5f, 0.4f, 0.14f), new Vector3(0f, 0.9f, 0.62f));
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0.4f, 0.85f, 0.3f);
            m.MuzzleOffset = new Vector3(0f, 0.6f, -2.3f);
            m.Length = 4.4f; m.Width = 1.9f; m.Height = 1.15f;
        }

        // ---------------------------------------------------------------- atv
        private static void BuildAtv(VehicleModel m, B b)
        {
            string P = "paint_atv", D = "metal_dark", R = "rubber", S = "steel";
            // 4 fat knobby tires with lug blocks; front pair steers.
            string[] names = { "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" };
            float[] sxs = { -0.5f, 0.5f, -0.5f, 0.5f };
            float[] wzs = { -0.75f, -0.75f, 0.75f, 0.75f };
            for (int i = 0; i < 4; i++)
            {
                bool steer = wzs[i] < 0f;
                Wheel(m, b, names[i], 0.3f, 0.28f, new Vector3(sxs[i], 0.3f, wzs[i]), steer, R, S, wb =>
                {
                    wb.Box(R, new Vector3(0.3f, 0.07f, 0.1f), new Vector3(0f, 0.3f, 0f));
                    wb.Box(R, new Vector3(0.3f, 0.07f, 0.1f), new Vector3(0f, -0.3f, 0f));
                    wb.Box(R, new Vector3(0.3f, 0.1f, 0.07f), new Vector3(0f, 0f, 0.3f));
                    wb.Box(R, new Vector3(0.3f, 0.1f, 0.07f), new Vector3(0f, 0f, -0.3f));
                });
            }
            // Frame + plastic body.
            b.Box(D, new Vector3(0.5f, 0.25f, 1.6f), new Vector3(0f, 0.5f, 0f));
            b.Box(P, new Vector3(0.9f, 0.3f, 1.4f), new Vector3(0f, 0.7f, 0.1f));
            b.Box(P, new Vector3(0.85f, 0.25f, 0.6f), new Vector3(0f, 0.75f, -0.6f));
            b.Box(R, new Vector3(0.45f, 0.15f, 0.8f), new Vector3(0f, 0.9f, 0.35f)); // seat
            b.Box(D, new Vector3(0.08f, 0.35f, 0.08f), new Vector3(0f, 0.9f, -0.55f));
            b.Cyl(D, 0.03f, 0.7f, new Vector3(0f, 1.08f, -0.55f), AX_RIGHT, 8);
            b.Cyl(R, 0.04f, 0.16f, new Vector3(-0.32f, 1.08f, -0.55f), AX_RIGHT, 8);
            b.Cyl(R, 0.04f, 0.16f, new Vector3(0.32f, 1.08f, -0.55f), AX_RIGHT, 8);
            // Mudguards over all four wheels.
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(P, new Vector3(0.35f, 0.06f, 0.5f), new Vector3(sx * 0.5f, 0.62f, -0.75f));
                b.Box(P, new Vector3(0.35f, 0.06f, 0.5f), new Vector3(sx * 0.5f, 0.62f, 0.75f));
            }
            // Front + rear racks.
            for (int ri = 0; ri < 2; ri++)
            {
                float rz = ri == 0 ? -0.95f : 0.95f;
                b.Box(D, new Vector3(0.7f, 0.04f, 0.08f), new Vector3(-0.3f, 0.88f, rz));
                b.Box(D, new Vector3(0.7f, 0.04f, 0.08f), new Vector3(0.3f, 0.88f, rz));
                b.Box(D, new Vector3(0.08f, 0.04f, 0.5f), new Vector3(0f, 0.88f, rz));
            }
            b.Box("light_head", new Vector3(0.25f, 0.12f, 0.08f), new Vector3(0f, 0.85f, -1.0f));
            b.FlushGroup("Body");
            // Buggy underglow: emissive plane under the chassis.
            b.QuadXZ("glow_cyan", 1.1f, new Vector3(0f, 0.14f, 0f));
            b.FlushGroup("Underglow");
            m.SeatOffset = new Vector3(0f, 1.0f, 0.35f);
            m.MuzzleOffset = new Vector3(0f, 0.8f, -1.15f);
            m.Length = 2.2f; m.Width = 1.2f; m.Height = 1.2f;
        }

        // -------------------------------------------------------- armored_suv
        private static void BuildArmoredSuv(VehicleModel m, B b)
        {
            string P = "paint_armored", G = "glass", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_FL", 0.44f, 0.32f, new Vector3(-0.92f, 0.44f, -1.6f), true, R, D);
            Wheel(m, b, "Wheel_FR", 0.44f, 0.32f, new Vector3(0.92f, 0.44f, -1.6f), true, R, D);
            Wheel(m, b, "Wheel_RL", 0.44f, 0.32f, new Vector3(-0.92f, 0.44f, 1.6f), false, R, D);
            Wheel(m, b, "Wheel_RR", 0.44f, 0.32f, new Vector3(0.92f, 0.44f, 1.6f), false, R, D);
            // Boxy reinforced body.
            b.Box(P, new Vector3(2.1f, 1.0f, 5.2f), new Vector3(0f, 1.0f, 0f));
            b.Box(P, new Vector3(2.05f, 0.6f, 4.6f), new Vector3(0f, 1.8f, 0.1f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(P, new Vector3(0.12f, 0.52f, 0.14f), new Vector3(sx * 1.0f, 1.8f, -1.7f));
                b.Box(P, new Vector3(0.12f, 0.52f, 0.14f), new Vector3(sx * 1.0f, 1.8f, 0.1f));
                b.Box(P, new Vector3(0.12f, 0.52f, 0.14f), new Vector3(sx * 1.0f, 1.8f, 1.9f));
            }
            b.Cyl(D, 0.35f, 0.1f, new Vector3(0f, 2.15f, 0.5f), AX_UP, 12); // roof hatch
            b.Cyl(D, 0.02f, 1.0f, new Vector3(0.8f, 2.6f, 1.8f), AX_UP, 6); // antenna
            // Bullbar.
            b.Cyl(S, 0.05f, 0.8f, new Vector3(-0.6f, 0.8f, -2.7f), AX_UP, 8);
            b.Cyl(S, 0.05f, 0.8f, new Vector3(0.6f, 0.8f, -2.7f), AX_UP, 8);
            b.Cyl(S, 0.05f, 1.3f, new Vector3(0f, 1.1f, -2.7f), AX_RIGHT, 8);
            b.Box(D, new Vector3(2.15f, 0.35f, 0.3f), new Vector3(0f, 0.6f, -2.62f));
            b.Box(D, new Vector3(2.15f, 0.35f, 0.3f), new Vector3(0f, 0.6f, 2.62f));
            b.Box(D, new Vector3(0.08f, 0.4f, 4.0f), new Vector3(-1.06f, 0.6f, 0f));
            b.Box(D, new Vector3(0.08f, 0.4f, 4.0f), new Vector3(1.06f, 0.6f, 0f));
            b.Box("light_head", new Vector3(0.4f, 0.16f, 0.08f), new Vector3(-0.65f, 1.0f, -2.61f));
            b.Box("light_head", new Vector3(0.4f, 0.16f, 0.08f), new Vector3(0.65f, 1.0f, -2.61f));
            b.Box("light_tail", new Vector3(0.35f, 0.16f, 0.08f), new Vector3(-0.7f, 1.05f, 2.61f));
            b.Box("light_tail", new Vector3(0.35f, 0.16f, 0.08f), new Vector3(0.7f, 1.05f, 2.61f));
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.07f, 0.12f, 0.15f), new Vector3(sx * 1.08f, 1.7f, -1.6f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 1.06f, 1.3f, -0.9f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 1.06f, 1.3f, 0.1f));
                b.Box(D, new Vector3(0.04f, 0.04f, 0.22f), new Vector3(sx * 1.06f, 1.3f, 1.1f));
            }
            b.FlushGroup("Body");
            // Cabin: bulletproof glass band + windshield + interior.
            b.Box(G, new Vector3(2.07f, 0.45f, 4.0f), new Vector3(0f, 1.8f, 0.1f));
            b.Box(G, new Vector3(1.9f, 0.5f, 0.08f), new Vector3(0f, 1.8f, -2.0f), new Vector3(-0.2f, 0f, 0f));
            CabinInterior(b, -1.7f, 1.15f, -0.4f, 1.05f);
            b.FlushGroup("Cabin");
            m.SeatOffset = new Vector3(0.55f, 1.6f, -0.6f);
            m.MuzzleOffset = new Vector3(0f, 1.1f, -2.8f);
            m.Length = 5.2f; m.Width = 2.1f; m.Height = 2.1f;
        }

        // -------------------------------------------------------------- jeep
        private static void BuildJeep(VehicleModel m, B b)
        {
            string P = "paint_jeep", G = "glass", D = "metal_dark", R = "rubber", S = "steel";
            Wheel(m, b, "Wheel_FL", 0.4f, 0.3f, new Vector3(-0.85f, 0.4f, -1.35f), true, R, S);
            Wheel(m, b, "Wheel_FR", 0.4f, 0.3f, new Vector3(0.85f, 0.4f, -1.35f), true, R, S);
            Wheel(m, b, "Wheel_RL", 0.4f, 0.3f, new Vector3(-0.85f, 0.4f, 1.35f), false, R, S);
            Wheel(m, b, "Wheel_RR", 0.4f, 0.3f, new Vector3(0.85f, 0.4f, 1.35f), false, R, S);
            // Flat body panels + hood.
            b.Box(P, new Vector3(1.85f, 0.6f, 4.2f), new Vector3(0f, 0.75f, 0f));
            b.Box(P, new Vector3(1.75f, 0.12f, 1.2f), new Vector3(0f, 1.08f, -1.4f));
            b.Box(P, new Vector3(1.2f, 0.45f, 0.06f), new Vector3(0f, 0.85f, -2.11f)); // grille
            for (int i = 0; i < 7; i++)
                b.Box(D, new Vector3(0.08f, 0.4f, 0.06f), new Vector3(-0.45f + i * 0.15f, 0.85f, -2.14f));
            b.Cyl(D, 0.16f, 0.1f, new Vector3(-0.75f, 0.95f, -2.1f), AX_FWD, 12);
            b.Cyl(D, 0.16f, 0.1f, new Vector3(0.75f, 0.95f, -2.1f), AX_FWD, 12);
            b.Cyl("light_head", 0.13f, 0.12f, new Vector3(-0.75f, 0.95f, -2.12f), AX_FWD, 12);
            b.Cyl("light_head", 0.13f, 0.12f, new Vector3(0.75f, 0.95f, -2.12f), AX_FWD, 12);
            // Windshield frame (open top).
            b.Box(P, new Vector3(0.08f, 0.5f, 0.08f), new Vector3(-0.85f, 1.3f, -0.9f));
            b.Box(P, new Vector3(0.08f, 0.5f, 0.08f), new Vector3(0.85f, 1.3f, -0.9f));
            // Exposed roll cage.
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Cyl(D, 0.05f, 1.0f, new Vector3(sx * 0.8f, 1.5f, 0.2f), AX_UP, 8);
                b.Cyl(D, 0.05f, 1.0f, new Vector3(sx * 0.8f, 1.5f, 1.6f), AX_UP, 8);
                b.Cyl(D, 0.05f, 1.6f, new Vector3(sx * 0.8f, 2.0f, 0.9f), AX_FWD, 8);
            }
            // Seats.
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(D, new Vector3(0.55f, 0.18f, 0.5f), new Vector3(sx * 0.45f, 1.12f, 0.3f));
                b.Box(D, new Vector3(0.55f, 0.5f, 0.15f), new Vector3(sx * 0.45f, 1.35f, 0.6f));
            }
            // Jerry can on the back.
            b.Box("accent_orange", new Vector3(0.35f, 0.45f, 0.2f), new Vector3(0.5f, 1.25f, 1.95f));
            b.Box(D, new Vector3(0.08f, 0.06f, 0.08f), new Vector3(0.5f, 1.5f, 1.95f));
            // Fenders + rear bumper + taillights.
            for (int si = 0; si < 2; si++)
            {
                float sx = si == 0 ? -1f : 1f;
                b.Box(P, new Vector3(0.35f, 0.08f, 0.6f), new Vector3(sx * 0.85f, 0.85f, -1.35f));
                b.Box(P, new Vector3(0.35f, 0.08f, 0.6f), new Vector3(sx * 0.85f, 0.85f, 1.35f));
            }
            b.Box(D, new Vector3(1.9f, 0.25f, 0.25f), new Vector3(0f, 0.6f, 2.12f));
            b.Box("light_tail", new Vector3(0.2f, 0.15f, 0.06f), new Vector3(-0.7f, 0.85f, 2.12f));
            b.Box("light_tail", new Vector3(0.2f, 0.15f, 0.06f), new Vector3(0.7f, 0.85f, 2.12f));
            b.FlushGroup("Body");
            // Cabin: transparent windshield only (open top).
            b.Box(G, new Vector3(1.7f, 0.4f, 0.05f), new Vector3(0f, 1.32f, -0.9f));
            b.FlushGroup("Cabin");
            // Mounted gun (visual only, non-functional): pintle + gun + handles + ammo box.
            GameObject mg = Pivot(b.Parent, "MountedGun", new Vector3(0f, 1.05f, 1.15f));
            var mb = new B(mg.transform, m, PaintKey(m.Type));
            mb.Cyl(D, 0.07f, 0.75f, new Vector3(0f, 0.35f, 0f), AX_UP, 10); // pintle post
            mb.Box(D, new Vector3(0.28f, 0.32f, 0.95f), new Vector3(0f, 0.85f, 0f)); // receiver
            mb.Cyl(D, 0.05f, 1.5f, new Vector3(0f, 0.9f, -1.1f), AX_FWD, 10); // barrel
            mb.Cyl(D, 0.035f, 0.35f, new Vector3(-0.22f, 0.75f, 0.35f), new Vector3(-0.5f, -0.4f, 0.6f), 8); // handles
            mb.Cyl(D, 0.035f, 0.35f, new Vector3(0.22f, 0.75f, 0.35f), new Vector3(0.5f, -0.4f, 0.6f), 8);
            mb.Box("accent_orange", new Vector3(0.35f, 0.3f, 0.25f), new Vector3(-0.45f, 0.6f, 0.1f)); // ammo box
            mb.FlushGroup("MountedGun");
            m.SeatOffset = new Vector3(0.45f, 1.35f, 0.3f);
            m.MuzzleOffset = new Vector3(0f, 0.9f, -2.2f);
            m.Length = 4.2f; m.Width = 1.85f; m.Height = 1.85f;
        }
    }
}
