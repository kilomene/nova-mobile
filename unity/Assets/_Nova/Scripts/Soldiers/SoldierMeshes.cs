using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Soldiers
{
    /// <summary>
    /// Cached procedural primitives for soldier body/gear meshes, shared by every
    /// soldier instance (critical: ~75 meshes x up to 100 soldiers must not
    /// duplicate Mesh assets). All meshes carry proper UVs + normals so camo
    /// textures read correctly. Build-time only; no runtime allocation.
    /// </summary>
    public static class SoldierMeshes
    {
        private static readonly Dictionary<string, Mesh> _cache = new Dictionary<string, Mesh>();

        private static string F(float v) { return v.ToString("F3"); }

        private static Mesh Get(string key, System.Func<Mesh> build)
        {
            Mesh m;
            if (_cache.TryGetValue(key, out m)) return m;
            m = build();
            m.name = "soldier_" + key;
            _cache[key] = m;
            return m;
        }

        public static Mesh Box(Vector3 size)
        {
            string key = "box_" + F(size.x) + "_" + F(size.y) + "_" + F(size.z);
            return Get(key, () => BuildBox(size));
        }

        public static Mesh Sphere(float radius, int seg = 12)
        {
            string key = "sph_" + F(radius) + "_" + seg;
            return Get(key, () => BuildSphere(radius, seg));
        }

        public static Mesh Capsule(float radius, float height, int seg = 10)
        {
            string key = "cap_" + F(radius) + "_" + F(height) + "_" + seg;
            return Get(key, () => BuildCapsule(radius, height, seg));
        }

        public static Mesh Cylinder(float topR, float bottomR, float height, int seg = 10)
        {
            string key = "cyl_" + F(topR) + "_" + F(bottomR) + "_" + F(height) + "_" + seg;
            return Get(key, () => BuildCylinder(topR, bottomR, height, seg));
        }

        public static int CachedCount { get { return _cache.Count; } }

        // ------------------------------------------------------------- builders
        private static Mesh BuildBox(Vector3 s)
        {
            float x = s.x / 2f, y = s.y / 2f, z = s.z / 2f;
            // 4 verts per face: positions, outward normals, 0..1 UVs.
            Vector3[] p = {
                // -Z
                new Vector3(-x,-y,-z), new Vector3(x,-y,-z), new Vector3(x,y,-z), new Vector3(-x,y,-z),
                // +Z
                new Vector3(x,-y,z), new Vector3(-x,-y,z), new Vector3(-x,y,z), new Vector3(x,y,z),
                // -X
                new Vector3(-x,-y,z), new Vector3(-x,-y,-z), new Vector3(-x,y,-z), new Vector3(-x,y,z),
                // +X
                new Vector3(x,-y,-z), new Vector3(x,-y,z), new Vector3(x,y,z), new Vector3(x,y,-z),
                // -Y
                new Vector3(-x,-y,z), new Vector3(x,-y,z), new Vector3(x,-y,-z), new Vector3(-x,-y,-z),
                // +Y
                new Vector3(-x,y,-z), new Vector3(x,y,-z), new Vector3(x,y,z), new Vector3(-x,y,z),
            };
            Vector3[] n = {
                Vector3.back, Vector3.back, Vector3.back, Vector3.back,
                Vector3.forward, Vector3.forward, Vector3.forward, Vector3.forward,
                Vector3.left, Vector3.left, Vector3.left, Vector3.left,
                Vector3.right, Vector3.right, Vector3.right, Vector3.right,
                Vector3.down, Vector3.down, Vector3.down, Vector3.down,
                Vector3.up, Vector3.up, Vector3.up, Vector3.up,
            };
            var mesh = new Mesh();
            mesh.SetVertices(new List<Vector3>(p));
            mesh.SetNormals(new List<Vector3>(n));
            var uv = new List<Vector2>();
            for (int f = 0; f < 6; f++)
            {
                uv.Add(new Vector2(0, 0)); uv.Add(new Vector2(1, 0));
                uv.Add(new Vector2(1, 1)); uv.Add(new Vector2(0, 1));
            }
            mesh.SetUVs(0, uv);
            var tris = new List<int>();
            for (int f = 0; f < 6; f++)
            {
                int b = f * 4;
                tris.Add(b); tris.Add(b + 2); tris.Add(b + 1);
                tris.Add(b); tris.Add(b + 3); tris.Add(b + 2);
            }
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        private static Mesh BuildSphere(float r, int seg)
        {
            var verts = new List<Vector3>();
            var norms = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            int rings = seg / 2;
            for (int iy = 0; iy <= rings; iy++)
            {
                float v = (float)iy / rings;
                float phi = v * Mathf.PI;
                float sy = Mathf.Cos(phi), sr = Mathf.Sin(phi);
                for (int ix = 0; ix <= seg; ix++)
                {
                    float u = (float)ix / seg;
                    float theta = u * Mathf.PI * 2f;
                    Vector3 d = new Vector3(sr * Mathf.Cos(theta), sy, sr * Mathf.Sin(theta));
                    verts.Add(d * r);
                    norms.Add(d);
                    uvs.Add(new Vector2(u, v));
                }
            }
            for (int iy = 0; iy < rings; iy++)
                for (int ix = 0; ix < seg; ix++)
                {
                    int a = iy * (seg + 1) + ix, b = a + seg + 1;
                    tris.Add(a); tris.Add(b); tris.Add(a + 1);
                    tris.Add(a + 1); tris.Add(b); tris.Add(b + 1);
                }
            var mesh = new Mesh();
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        private static Mesh BuildCapsule(float r, float h, int seg)
        {
            var verts = new List<Vector3>();
            var norms = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            int capSeg = 4;
            int rings = capSeg * 2 + 2;
            for (int iy = 0; iy <= rings; iy++)
            {
                float ty = (float)iy / rings;
                float y, rad;
                if (ty < 0.25f)
                {
                    float a = (ty / 0.25f) * Mathf.PI * 0.5f;
                    y = -h / 2f - r * Mathf.Cos(a);
                    rad = r * Mathf.Sin(a);
                }
                else if (ty > 0.75f)
                {
                    float a = ((ty - 0.75f) / 0.25f) * Mathf.PI * 0.5f;
                    y = h / 2f + r * Mathf.Sin(a);
                    rad = r * Mathf.Cos(a);
                }
                else
                {
                    y = Mathf.Lerp(-h / 2f, h / 2f, (ty - 0.25f) / 0.5f);
                    rad = r;
                }
                for (int ix = 0; ix <= seg; ix++)
                {
                    float u = (float)ix / seg;
                    float theta = u * Mathf.PI * 2f;
                    float cx = Mathf.Cos(theta), sz = Mathf.Sin(theta);
                    verts.Add(new Vector3(cx * rad, y, sz * rad));
                    float cy = Mathf.Clamp(y, -h / 2f, h / 2f);
                    norms.Add(new Vector3(cx * rad, y - cy, sz * rad).normalized);
                    uvs.Add(new Vector2(u, ty));
                }
            }
            for (int iy = 0; iy < rings; iy++)
                for (int ix = 0; ix < seg; ix++)
                {
                    int a = iy * (seg + 1) + ix, b = a + seg + 1;
                    tris.Add(a); tris.Add(b); tris.Add(a + 1);
                    tris.Add(a + 1); tris.Add(b); tris.Add(b + 1);
                }
            var mesh = new Mesh();
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        private static Mesh BuildCylinder(float rt, float rb, float h, int seg)
        {
            var verts = new List<Vector3>();
            var norms = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int i = 0; i <= seg; i++)
            {
                float u = (float)i / seg;
                float a = u * Mathf.PI * 2f;
                float cx = Mathf.Cos(a), sz = Mathf.Sin(a);
                verts.Add(new Vector3(cx * rb, -h / 2f, sz * rb));
                verts.Add(new Vector3(cx * rt, h / 2f, sz * rt));
                Vector3 n = new Vector3(cx, 0f, sz).normalized;
                norms.Add(n); norms.Add(n);
                uvs.Add(new Vector2(u, 0f)); uvs.Add(new Vector2(u, 1f));
                if (i < seg)
                {
                    int b = i * 2;
                    tris.Add(b); tris.Add(b + 2); tris.Add(b + 1);
                    tris.Add(b + 1); tris.Add(b + 2); tris.Add(b + 3);
                }
            }
            int cb = verts.Count;
            verts.Add(new Vector3(0f, -h / 2f, 0f)); norms.Add(Vector3.down); uvs.Add(new Vector2(0.5f, 0.5f));
            verts.Add(new Vector3(0f, h / 2f, 0f)); norms.Add(Vector3.up); uvs.Add(new Vector2(0.5f, 0.5f));
            for (int i = 0; i < seg; i++)
            {
                tris.Add(cb); tris.Add((i + 1) * 2); tris.Add(i * 2);
                tris.Add(cb + 1); tris.Add(i * 2 + 1); tris.Add((i + 1) * 2 + 1);
            }
            var mesh = new Mesh();
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }
    }
}
