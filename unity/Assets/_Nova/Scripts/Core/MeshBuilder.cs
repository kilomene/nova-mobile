using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Core
{
    /// <summary>
    /// Procedural mesh helpers. Builds simple solid meshes (boxes, cylinders, prisms, quads)
    /// and combines part lists into single meshes for batching. All allocation happens at
    /// build time; the returned Meshes are ready to assign to MeshFilters.
    /// </summary>
    public static class MeshBuilder
    {
        public struct Part
        {
            public Vector3[] Verts;
            public int[] Tris;
            public Vector3[] Normals;
            public Vector2[] Uv;
            public Matrix4x4 Matrix;
        }

        private static readonly Vector3[] BoxVerts = {
            new Vector3(-0.5f,-0.5f,-0.5f), new Vector3(0.5f,-0.5f,-0.5f),
            new Vector3(0.5f, 0.5f,-0.5f), new Vector3(-0.5f, 0.5f,-0.5f),
            new Vector3(-0.5f,-0.5f, 0.5f), new Vector3(0.5f,-0.5f, 0.5f),
            new Vector3(0.5f, 0.5f, 0.5f), new Vector3(-0.5f, 0.5f, 0.5f),
        };
        private static readonly int[] BoxTris = {
            0,2,1, 0,3,2,  4,5,6, 4,6,7,  0,1,5, 0,5,4,
            2,3,7, 2,7,6,  0,4,7, 0,7,3,  1,2,6, 1,6,5,
        };

        /// <summary>Unit box centered at origin, transformed by matrix.</summary>
        public static Part Box(Vector3 size, Vector3 center, Quaternion rot)
        {
            return Box(size, Matrix4x4.TRS(center, rot, Vector3.one));
        }

        public static Part Box(Vector3 size, Matrix4x4 m)
        {
            var verts = new Vector3[8];
            var normals = new Vector3[8];
            for (int i = 0; i < 8; i++)
            {
                verts[i] = m.MultiplyPoint3x4(new Vector3(BoxVerts[i].x * size.x, BoxVerts[i].y * size.y, BoxVerts[i].z * size.z));
                normals[i] = m.MultiplyVector(BoxVerts[i].normalized).normalized;
            }
            var uv = new Vector2[8];
            return new Part { Verts = verts, Tris = (int[])BoxTris.Clone(), Normals = normals, Uv = uv, Matrix = Matrix4x4.identity };
        }

        /// <summary>Cylinder along Y, centered at origin.</summary>
        public static Part Cylinder(float radius, float height, int segments, Matrix4x4 m)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var tris = new List<int>();
            for (int i = 0; i <= segments; i++)
            {
                float a = (float)i / segments * Mathf.PI * 2f;
                float x = Mathf.Cos(a) * radius, z = Mathf.Sin(a) * radius;
                int b = verts.Count;
                verts.Add(m.MultiplyPoint3x4(new Vector3(x, -height / 2f, z)));
                verts.Add(m.MultiplyPoint3x4(new Vector3(x, height / 2f, z)));
                Vector3 n = m.MultiplyVector(new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a))).normalized;
                normals.Add(n); normals.Add(n);
                if (i < segments)
                {
                    tris.Add(b); tris.Add(b + 2); tris.Add(b + 1);
                    tris.Add(b + 1); tris.Add(b + 2); tris.Add(b + 3);
                }
            }
            // caps
            int cb = verts.Count;
            verts.Add(m.MultiplyPoint3x4(new Vector3(0f, -height / 2f, 0f)));
            normals.Add(m.MultiplyVector(Vector3.down));
            verts.Add(m.MultiplyPoint3x4(new Vector3(0f, height / 2f, 0f)));
            normals.Add(m.MultiplyVector(Vector3.up));
            for (int i = 0; i < segments; i++)
            {
                // bottom cap fan (side bottom verts are even indices), top cap fan (odd indices)
                tris.Add(cb); tris.Add((i + 1) * 2); tris.Add(i * 2);
                tris.Add(cb + 1); tris.Add(i * 2 + 1); tris.Add((i + 1) * 2 + 1);
            }
            var uv = new Vector2[verts.Count];
            return new Part { Verts = verts.ToArray(), Tris = tris.ToArray(), Normals = normals.ToArray(), Uv = uv, Matrix = Matrix4x4.identity };
        }

        /// <summary>Flat quad in XZ plane (ground), centered at origin.</summary>
        public static Part GroundQuad(float size, Matrix4x4 m)
        {
            float h = size / 2f;
            var verts = new Vector3[] {
                m.MultiplyPoint3x4(new Vector3(-h, 0f, -h)),
                m.MultiplyPoint3x4(new Vector3(h, 0f, -h)),
                m.MultiplyPoint3x4(new Vector3(h, 0f, h)),
                m.MultiplyPoint3x4(new Vector3(-h, 0f, h)),
            };
            var n = m.MultiplyVector(Vector3.up).normalized;
            return new Part
            {
                Verts = verts,
                Tris = new int[] { 0, 1, 2, 0, 2, 3 },
                Normals = new Vector3[] { n, n, n, n },
                Uv = new Vector2[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) },
                Matrix = Matrix4x4.identity
            };
        }

        /// <summary>Combine parts into one Mesh (single material).</summary>
        public static Mesh Combine(List<Part> parts)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            foreach (var p in parts)
            {
                int baseIdx = verts.Count;
                verts.AddRange(p.Verts);
                normals.AddRange(p.Normals);
                uvs.AddRange(p.Uv);
                foreach (int t in p.Tris) tris.Add(baseIdx + t);
            }
            var mesh = new Mesh();
            mesh.SetVertices(verts);
            mesh.SetNormals(normals);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        /// <summary>Build a GameObject with MeshFilter+MeshRenderer from parts.</summary>
        public static GameObject BuildObject(string name, List<Part> parts, Material mat)
        {
            var go = new GameObject(name);
            var mf = go.AddComponent<MeshFilter>();
            mf.mesh = Combine(parts);
            var mr = go.AddComponent<MeshRenderer>();
            mr.material = mat;
            return go;
        }
    }
}
