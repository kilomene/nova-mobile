using UnityEngine;

namespace NovaMobile.Core
{
    /// <summary>
    /// Procedural textures generated once at startup. Gives the world/characters/vehicles
    /// a textured medium-tier look with zero art assets; structured so real art can
    /// replace these 1:1 later (same material slots / tiling).
    /// </summary>
    public static class ProcTexture
    {
        // Deterministic hash-based value noise.
        private static float Hash(int x, int y, int seed)
        {
            int h = x * 374761393 + y * 668265263 + seed * 1442695041;
            h = (h ^ (h >> 13)) * 1274126177;
            h ^= h >> 16;
            return (h & 0x7fffffff) / (float)0x7fffffff;
        }

        private static float ValueNoise(float x, float y, int seed)
        {
            int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
            float xf = x - xi, yf = y - yi;
            float u = xf * xf * (3f - 2f * xf), v = yf * yf * (3f - 2f * yf);
            float a = Hash(xi, yi, seed), b = Hash(xi + 1, yi, seed);
            float c = Hash(xi, yi + 1, seed), d = Hash(xi + 1, yi + 1, seed);
            return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
        }

        private static float Fbm(float x, float y, int seed)
        {
            return ValueNoise(x, y, seed) * 0.6f
                 + ValueNoise(x * 2.7f, y * 2.7f, seed + 7) * 0.28f
                 + ValueNoise(x * 6.1f, y * 6.1f, seed + 13) * 0.12f;
        }

        private static Texture2D Make(int size, System.Func<float, float, Color> fn)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGB24, false);
            tex.wrapMode = TextureWrapMode.Repeat;
            tex.filterMode = FilterMode.Bilinear;
            var cols = new Color[size * size];
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                    cols[y * size + x] = fn((float)x / size, (float)y / size);
            tex.SetPixels(cols);
            tex.Apply(false, true);
            return tex;
        }

        private static Color Lerp(Color a, Color b, float t)
        {
            return new Color(
                a.r + (b.r - a.r) * t,
                a.g + (b.g - a.g) * t,
                a.b + (b.b - a.b) * t);
        }

        /// <summary>Grass with dry patches and dirt speckles. Tile ~8m.</summary>
        public static Texture2D Grass(int size = 256, int seed = 11)
        {
            Color green = new Color(0.32f, 0.48f, 0.20f);
            Color dry = new Color(0.55f, 0.50f, 0.28f);
            Color dirt = new Color(0.45f, 0.35f, 0.22f);
            return Make(size, (u, v) =>
            {
                float n = Fbm(u * 9f, v * 9f, seed);
                float patch = Fbm(u * 3f + 40f, v * 3f, seed + 3);
                Color c = Lerp(green, dry, Mathf.Clamp01((n - 0.35f) * 2.2f));
                if (patch > 0.72f) c = Lerp(c, dirt, (patch - 0.72f) * 3f);
                float grain = Hash((int)(u * size), (int)(v * size), seed + 5);
                return c * (0.92f + grain * 0.16f);
            });
        }

        /// <summary>Bare dirt / ground. Tile ~8m.</summary>
        public static Texture2D Dirt(int size = 256, int seed = 23)
        {
            Color a = new Color(0.48f, 0.38f, 0.24f);
            Color b = new Color(0.36f, 0.27f, 0.17f);
            return Make(size, (u, v) =>
            {
                float n = Fbm(u * 7f, v * 7f, seed);
                float grain = Hash((int)(u * size), (int)(v * size), seed + 5);
                return Lerp(a, b, n) * (0.9f + grain * 0.2f);
            });
        }

        /// <summary>Asphalt with center dashes, edge lines and tire-wear darkening. Tile along road.</summary>
        public static Texture2D Road(int size = 256, int seed = 37)
        {
            Color asphalt = new Color(0.23f, 0.23f, 0.25f);
            Color line = new Color(0.85f, 0.78f, 0.55f);
            Color wear = new Color(0.16f, 0.16f, 0.17f);
            return Make(size, (u, v) =>
            {
                float grain = Hash((int)(u * size), (int)(v * size), seed);
                Color c = asphalt * (0.92f + grain * 0.16f);
                // tire wear bands at u ~0.3 and 0.7
                float w1 = Mathf.Exp(-Mathf.Pow((u - 0.30f) * 9f, 2f));
                float w2 = Mathf.Exp(-Mathf.Pow((u - 0.70f) * 9f, 2f));
                c = Lerp(c, wear, Mathf.Clamp01((w1 + w2) * 0.55f));
                // edge lines
                if (u < 0.045f || u > 0.955f) c = Lerp(c, line, 0.85f);
                // center dashes (v repeats)
                float dash = Mathf.Repeat(v * 6f, 1f);
                if (u > 0.485f && u < 0.515f && dash < 0.55f) c = Lerp(c, line, 0.9f);
                return c;
            });
        }

        /// <summary>Plaster/concrete wall with subtle grime near the bottom (v=0).</summary>
        public static Texture2D Wall(Color baseColor, int size = 256, int seed = 51)
        {
            return Make(size, (u, v) =>
            {
                float n = Fbm(u * 5f, v * 5f, seed);
                float grain = Hash((int)(u * size), (int)(v * size), seed + 5);
                Color c = baseColor * (0.9f + n * 0.2f) * (0.94f + grain * 0.12f);
                float grime = Mathf.Clamp01((0.22f - v) * 4f) * 0.35f;
                return c * (1f - grime);
            });
        }

        /// <summary>Vehicle paint: base color with dirt speckle low on the body.</summary>
        public static Texture2D VehiclePaint(Color baseColor, int size = 256, int seed = 67)
        {
            return Make(size, (u, v) =>
            {
                float grain = Hash((int)(u * size), (int)(v * size), seed);
                Color c = baseColor * (0.94f + grain * 0.12f);
                float dirt = Mathf.Clamp01((0.3f - v) * 3f) * Fbm(u * 8f, v * 8f, seed + 2);
                return Lerp(c, new Color(0.35f, 0.28f, 0.18f), dirt * 0.5f);
            });
        }

        /// <summary>Simple camo blobs from a palette.</summary>
        public static Texture2D Camo(Color[] palette, int size = 256, int seed = 83)
        {
            return Make(size, (u, v) =>
            {
                float n = Fbm(u * 4f, v * 4f, seed);
                int idx = Mathf.Clamp(Mathf.FloorToInt(n * palette.Length), 0, palette.Length - 1);
                float grain = Hash((int)(u * size), (int)(v * size), seed + 5);
                return palette[idx] * (0.92f + grain * 0.16f);
            });
        }

        /// <summary>Leaf canopy noise.</summary>
        public static Texture2D Foliage(int size = 128, int seed = 97)
        {
            Color a = new Color(0.22f, 0.42f, 0.16f);
            Color b = new Color(0.35f, 0.55f, 0.20f);
            return Make(size, (u, v) =>
            {
                float n = Fbm(u * 6f, v * 6f, seed);
                float grain = Hash((int)(u * size), (int)(v * size), seed + 5);
                return Lerp(a, b, n) * (0.85f + grain * 0.3f);
            });
        }

        /// <summary>Water surface noise (used scrolling via material offset).</summary>
        public static Texture2D Water(int size = 128, int seed = 113)
        {
            Color a = new Color(0.10f, 0.28f, 0.42f);
            Color b = new Color(0.16f, 0.38f, 0.52f);
            return Make(size, (u, v) =>
            {
                float n = Fbm(u * 5f, v * 5f, seed);
                return Lerp(a, b, n);
            });
        }
    }
}
