using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.World
{
    /// <summary>
    /// Unity port of Godot's geo_batch.gd. Collects boxes / cylinders / low-poly
    /// rocks / terrain quads / road quads per material, then combines each material
    /// bucket into ONE Mesh (single draw call per material). Colliders are collected
    /// separately and built as BoxColliders under one parent, mirroring
    /// build_colliders(). All geometry is expressed in the batch's local space; the
    /// caller parents the built GameObjects wherever the content belongs.
    ///
    /// TEXTURING: UVs are authored in world units (uv = worldPos / tileMeters) so the
    /// ProcTexture slots tile correctly (Grass/Dirt ~8m, walls ~4m). Material texture
    /// scale stays 1, so real art can replace the procedural textures 1:1 later.
    /// Vertex colors carry per-instance tint variation on top of the textures.
    /// </summary>
    public sealed class WorldBatch
    {
        private sealed class Bucket
        {
            public readonly List<Vector3> V = new List<Vector3>(1024);
            public readonly List<Vector3> N = new List<Vector3>(1024);
            public readonly List<Vector2> Uv = new List<Vector2>(1024);
            public readonly List<Color> C = new List<Color>(1024);
            public readonly List<int> T = new List<int>(1536);
        }

        private struct ColliderBox
        {
            public Vector3 Size, Pos;
            public Quaternion Rot;
        }

        private readonly Dictionary<Material, Bucket> _buckets = new Dictionary<Material, Bucket>();
        private readonly List<ColliderBox> _colliders = new List<ColliderBox>();

        private Bucket GetBucket(Material mat)
        {
            Bucket b;
            if (!_buckets.TryGetValue(mat, out b))
            {
                b = new Bucket();
                _buckets[mat] = b;
            }
            return b;
        }

        private static void PushTri(Bucket b, Vector3 a, Vector3 b2, Vector3 c, Vector3 n,
            Color col, Vector2 uva, Vector2 uvb, Vector2 uvc)
        {
            int baseIdx = b.V.Count;
            b.V.Add(a); b.V.Add(b2); b.V.Add(c);
            b.N.Add(n); b.N.Add(n); b.N.Add(n);
            b.Uv.Add(uva); b.Uv.Add(uvb); b.Uv.Add(uvc);
            b.C.Add(col); b.C.Add(col); b.C.Add(col);
            b.T.Add(baseIdx); b.T.Add(baseIdx + 1); b.T.Add(baseIdx + 2);
        }

        private static void PushQuad(Bucket b, Vector3 a, Vector3 b2, Vector3 c, Vector3 d,
            Vector3 n, Color col, Vector2 uva, Vector2 uvb, Vector2 uvc, Vector2 uvd)
        {
            // a-b-c-d counter-clockwise seen from the normal side.
            PushTri(b, a, b2, c, n, col, uva, uvb, uvc);
            PushTri(b, a, c, d, n, col, uva, uvc, uvd);
        }

        private static void PushQuad(Bucket b, Vector3 a, Vector3 b2, Vector3 c, Vector3 d,
            Vector3 n, Color col)
        {
            PushQuad(b, a, b2, c, d, n, col, Vector2.zero, Vector2.right, Vector2.one, Vector2.up);
        }

        // World-unit UV from a world position, picking the two in-plane axes per face.
        private static Vector2 UvX(float z, float y, float tile) => new Vector2(z / tile, y / tile);
        private static Vector2 UvY(float x, float z, float tile) => new Vector2(x / tile, z / tile);
        private static Vector2 UvZ(float x, float y, float tile) => new Vector2(x / tile, y / tile);

        /// <summary>
        /// Solid box, flat-shaded, transformed by m. UVs tile every <paramref name="uvTile"/>
        /// world meters; for walls v=0 sits at y=0 so the Wall() grime gradient lands
        /// near the ground.
        /// </summary>
        public void Box(Vector3 size, Matrix4x4 m, Material mat, Color col,
            bool collide = false, float uvTile = 4f)
        {
            Bucket b = GetBucket(mat);
            Vector3 px = m.MultiplyPoint3x4(Vector3.zero);
            Vector3 ex = m.MultiplyVector(new Vector3(size.x * 0.5f, 0f, 0f));
            Vector3 ey = m.MultiplyVector(new Vector3(0f, size.y * 0.5f, 0f));
            Vector3 ez = m.MultiplyVector(new Vector3(0f, 0f, size.z * 0.5f));
            Vector3 nx = m.MultiplyVector(Vector3.right).normalized;
            Vector3 ny = m.MultiplyVector(Vector3.up).normalized;
            Vector3 nz = m.MultiplyVector(Vector3.forward).normalized;

            Vector3 c000 = px - ex - ey - ez, c100 = px + ex - ey - ez;
            Vector3 c110 = px + ex + ey - ez, c010 = px - ex + ey - ez;
            Vector3 c001 = px - ex - ey + ez, c101 = px + ex - ey + ez;
            Vector3 c111 = px + ex + ey + ez, c011 = px - ex + ey + ez;

            // +X / -X : uv from (z, y)
            PushQuad(b, c100, c110, c111, c101, nx, col,
                UvX(c100.z, c100.y, uvTile), UvX(c110.z, c110.y, uvTile),
                UvX(c111.z, c111.y, uvTile), UvX(c101.z, c101.y, uvTile));
            PushQuad(b, c001, c011, c010, c000, -nx, col,
                UvX(c001.z, c001.y, uvTile), UvX(c011.z, c011.y, uvTile),
                UvX(c010.z, c010.y, uvTile), UvX(c000.z, c000.y, uvTile));
            // +Y / -Y : uv from (x, z)
            PushQuad(b, c010, c011, c111, c110, ny, col,
                UvY(c010.x, c010.z, uvTile), UvY(c011.x, c011.z, uvTile),
                UvY(c111.x, c111.z, uvTile), UvY(c110.x, c110.z, uvTile));
            PushQuad(b, c000, c100, c101, c001, -ny, col,
                UvY(c000.x, c000.z, uvTile), UvY(c100.x, c100.z, uvTile),
                UvY(c101.x, c101.z, uvTile), UvY(c001.x, c001.z, uvTile));
            // +Z / -Z : uv from (x, y)
            PushQuad(b, c001, c101, c111, c011, nz, col,
                UvZ(c001.x, c001.y, uvTile), UvZ(c101.x, c101.y, uvTile),
                UvZ(c111.x, c111.y, uvTile), UvZ(c011.x, c011.y, uvTile));
            PushQuad(b, c100, c000, c010, c110, -nz, col,
                UvZ(c100.x, c100.y, uvTile), UvZ(c000.x, c000.y, uvTile),
                UvZ(c010.x, c010.y, uvTile), UvZ(c110.x, c110.y, uvTile));
            if (collide) Collider(size, m);
        }

        /// <summary>Cylinder along Y, capped. UV wraps around the side.</summary>
        public void Cylinder(float radius, float height, int segments, Matrix4x4 m,
            Material mat, Color col, bool collide = false, float uvTile = 4f)
        {
            Bucket b = GetBucket(mat);
            float h = height * 0.5f;
            float circumference = Mathf.PI * 2f * radius;
            Vector3 up = m.MultiplyVector(Vector3.up).normalized;
            Vector3 center = m.MultiplyPoint3x4(Vector3.zero);
            Vector3 topC = center + m.MultiplyVector(new Vector3(0f, h, 0f));
            Vector3 botC = center + m.MultiplyVector(new Vector3(0f, -h, 0f));
            Vector3 prevTop = default, prevBot = default, prevN = default;
            float prevU = 0f;
            for (int i = 0; i <= segments; i++)
            {
                float a = (float)i / segments * Mathf.PI * 2f;
                float u = circumference * i / segments / uvTile;
                Vector3 dir = new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a));
                Vector3 n = m.MultiplyVector(dir).normalized;
                Vector3 top = center + m.MultiplyVector(new Vector3(dir.x * radius, h, dir.z * radius));
                Vector3 bot = center + m.MultiplyVector(new Vector3(dir.x * radius, -h, dir.z * radius));
                float vTop = (center.y + h) / uvTile, vBot = (center.y - h) / uvTile;
                if (i > 0)
                {
                    // wound (bot, prevBot, prevTop, top): CCW seen from outside
                    PushQuad(b, bot, prevBot, prevTop, top, (prevN + n) * 0.5f, col,
                        new Vector2(u, vBot), new Vector2(prevU, vBot),
                        new Vector2(prevU, vTop), new Vector2(u, vTop));
                    PushTri(b, topC, top, prevTop, up, col,
                        new Vector2(u, vTop), new Vector2(u, vTop), new Vector2(prevU, vTop));
                    PushTri(b, botC, prevBot, bot, -up, col,
                        new Vector2(u, vBot), new Vector2(prevU, vBot), new Vector2(u, vBot));
                }
                prevTop = top; prevBot = bot; prevN = n; prevU = u;
            }
            if (collide) Collider(new Vector3(radius * 2f, height, radius * 2f), m);
        }

        private static float DeformHash(int i, int j, int k)
        {
            int h = i * 374761393 + j * 668265263 + k * 1442695041;
            h = (h ^ (h >> 13)) * 1274126177;
            h ^= h >> 16;
            return (h & 0x7fffffff) / (float)0x7fffffff;
        }

        /// <summary>
        /// Low-poly deformed blob (boulders, canopies, bushes) — Godot used a 7x4
        /// SphereMesh. <paramref name="deform"/> jitters the surface 0..1.
        /// </summary>
        public void Rock(Vector3 size, Matrix4x4 m, Material mat, Color col,
            bool collide = false, float deform = 0f)
        {
            Bucket b = GetBucket(mat);
            const int radial = 7, rings = 4;
            Vector3 center = m.MultiplyPoint3x4(Vector3.zero);
            Vector3[,] grid = new Vector3[radial + 1, rings + 1];
            for (int j = 0; j <= rings; j++)
            {
                float v = (float)j / rings;                    // 0 = bottom .. 1 = top
                float y = (v - 0.5f) * size.y;
                float ringR = Mathf.Sin(v * Mathf.PI) * 0.5f;  // 0 at poles
                for (int i = 0; i <= radial; i++)
                {
                    float a = (float)i / radial * Mathf.PI * 2f;
                    float wobble = 1f + (deform > 0f ? (DeformHash(i, j, 7) - 0.5f) * 2f * deform : 0f);
                    Vector3 local = new Vector3(Mathf.Cos(a) * ringR * size.x * wobble, y,
                        Mathf.Sin(a) * ringR * size.z * wobble);
                    grid[i, j] = m.MultiplyPoint3x4(local);
                }
            }
            for (int j = 0; j < rings; j++)
            {
                float v0 = (float)j / rings, v1 = (float)(j + 1) / rings;
                for (int i = 0; i < radial; i++)
                {
                    float u0 = (float)i / radial * 2f, u1 = (float)(i + 1) / radial * 2f;
                    Vector3 a = grid[i, j], b2 = grid[i + 1, j], c = grid[i + 1, j + 1], d = grid[i, j + 1];
                    Vector3 n = Vector3.Cross(b2 - a, d - a);
                    if (n.sqrMagnitude < 1e-8f) n = Vector3.up;
                    n.Normalize();
                    Vector3 mid = (a + b2 + c + d) * 0.25f - center;
                    if (Vector3.Dot(n, mid) < 0f) n = -n;
                    // wound (a, d, c, b2): CCW seen from outside
                    PushQuad(b, a, d, c, b2, n, col,
                        new Vector2(u0, v0), new Vector2(u0, v1),
                        new Vector2(u1, v1), new Vector2(u1, v0));
                }
            }
            if (collide) Collider(size, m);
        }

        /// <summary>
        /// Ground quad with per-corner heights and colors (terrain cells).
        /// Corners: a(-x,-z) b(+x,-z) c(+x,+z) d(-x,+z). UVs tile every
        /// <paramref name="uvTile"/> meters (8m for Grass/Dirt).
        /// </summary>
        public void TerrainQuad(Vector3 a, Vector3 b2, Vector3 c, Vector3 d,
            Color ca, Color cb, Color cc, Color cd, Material mat, float uvTile = 8f)
        {
            Bucket b = GetBucket(mat);
            Vector3 n = Vector3.Cross(b2 - a, d - a);
            if (n.sqrMagnitude < 1e-8f) n = Vector3.up;
            n.Normalize();
            if (n.y < 0f) n = -n;
            int baseIdx = b.V.Count;
            b.V.Add(a); b.V.Add(b2); b.V.Add(c); b.V.Add(d);
            b.N.Add(n); b.N.Add(n); b.N.Add(n); b.N.Add(n);
            b.Uv.Add(new Vector2(a.x / uvTile, a.z / uvTile));
            b.Uv.Add(new Vector2(b2.x / uvTile, b2.z / uvTile));
            b.Uv.Add(new Vector2(c.x / uvTile, c.z / uvTile));
            b.Uv.Add(new Vector2(d.x / uvTile, d.z / uvTile));
            b.C.Add(ca); b.C.Add(cb); b.C.Add(cc); b.C.Add(cd);
            // wound CCW seen from above (+Y)
            b.T.Add(baseIdx); b.T.Add(baseIdx + 3); b.T.Add(baseIdx + 2);
            b.T.Add(baseIdx); b.T.Add(baseIdx + 2); b.T.Add(baseIdx + 1);
        }

        /// <summary>
        /// Textured road ribbon. UVs fit the ProcTexture.Road() layout: u 0..1 across
        /// the road (edge lines + tire-wear bands), v tiling along its length.
        /// Wound CCW seen from above.
        /// </summary>
        public void RoadQuad(float x0, float x1, float z0, float z1, float y,
            bool alongX, Material mat)
        {
            Bucket b = GetBucket(mat);
            Vector3 a = new Vector3(x0, y, z0), b2 = new Vector3(x1, y, z0);
            Vector3 c = new Vector3(x1, y, z1), d = new Vector3(x0, y, z1);
            const float alongTile = 12f;
            Vector2 uva, uvb, uvc, uvd;
            if (alongX)
            {
                // width axis is z: u varies 0..1 across z, v tiles along x
                uva = new Vector2(0f, x0 / alongTile);
                uvb = new Vector2(0f, x1 / alongTile);
                uvc = new Vector2(1f, x1 / alongTile);
                uvd = new Vector2(1f, x0 / alongTile);
            }
            else
            {
                // width axis is x: u varies 0..1 across x, v tiles along z
                uva = new Vector2(0f, z0 / alongTile);
                uvb = new Vector2(1f, z0 / alongTile);
                uvc = new Vector2(1f, z1 / alongTile);
                uvd = new Vector2(0f, z1 / alongTile);
            }
            PushQuad(b, a, d, c, b2, Vector3.up, Color.white, uva, uvd, uvc, uvb);
        }

        /// <summary>Inject a MeshBuilder.Part into a bucket (for prisms / quads).</summary>
        public void Part(MeshBuilder.Part p, Material mat, Color col)
        {
            Bucket b = GetBucket(mat);
            int baseIdx = b.V.Count;
            b.V.AddRange(p.Verts);
            b.N.AddRange(p.Normals);
            b.Uv.AddRange(p.Uv);
            for (int i = 0; i < p.Verts.Length; i++) b.C.Add(col);
            foreach (int t in p.Tris) b.T.Add(baseIdx + t);
        }

        public void Collider(Vector3 size, Matrix4x4 m)
        {
            _colliders.Add(new ColliderBox
            {
                Size = size,
                Pos = m.GetColumn(3),
                Rot = Quaternion.LookRotation(m.GetColumn(2), m.GetColumn(1))
            });
        }

        public void Collider(Vector3 size, Vector3 pos, Quaternion rot)
        {
            _colliders.Add(new ColliderBox { Size = size, Pos = pos, Rot = rot });
        }

        public int ColliderCount => _colliders.Count;

        /// <summary>Build one GameObject per material bucket. Returns draw-call count.</summary>
        public int Build(Transform parent, string name)
        {
            int draws = 0;
            foreach (var kv in _buckets)
            {
                Bucket b = kv.Value;
                if (b.T.Count == 0) continue;
                var mesh = new Mesh();
                mesh.SetVertices(b.V);
                mesh.SetNormals(b.N);
                mesh.SetUVs(0, b.Uv);
                mesh.SetColors(b.C);
                mesh.SetTriangles(b.T, 0);
                mesh.RecalculateBounds();
                var go = new GameObject(name + "_" + kv.Key.name);
                go.transform.SetParent(parent, false);
                var mf = go.AddComponent<MeshFilter>();
                mf.sharedMesh = mesh;
                var mr = go.AddComponent<MeshRenderer>();
                mr.sharedMaterial = kv.Key;
                draws++;
            }
            return draws;
        }

        /// <summary>Build BoxColliders under one parent, mirroring GeoBatch.build_colliders().</summary>
        public void BuildColliders(Transform parent, string name = "StaticColliders")
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent, false);
            foreach (var c in _colliders)
            {
                var go = new GameObject("col");
                go.transform.SetParent(root.transform, false);
                go.transform.SetPositionAndRotation(c.Pos, c.Rot);
                var bc = go.AddComponent<BoxCollider>();
                bc.size = c.Size;
            }
        }

        public void Clear()
        {
            _buckets.Clear();
            _colliders.Clear();
        }
    }
}
