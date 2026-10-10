using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Player
{
    /// <summary>
    /// Icon ids for the touch HUD buttons. Mirrors hud_icons.gd glyph names.
    /// </summary>
    public enum HudIcon
    {
        None, Fire, Ads, Jump, Crouch, Prone, Grenade, Sprint, Reload, Swap,
        Armor, Skill, Inspect, Emote, Ping, Smoke, Nade, Gear
    }

    /// <summary>
    /// Procedural HUD artwork: rounded translucent button panels and white
    /// vector glyphs, all rasterized in code (no image assets). Ported from
    /// hud_icons.gd — same glyphs, same CODM orange accent.
    /// Textures are generated once and cached; safe to call from UI builders.
    /// </summary>
    public static class HudIcons
    {
        public static readonly Color Accent = new Color(1.0f, 0.60f, 0.12f, 1.0f);
        public static readonly Color Panel = new Color(0.02f, 0.03f, 0.05f, 0.55f);
        public static readonly Color IconWhite = new Color(1, 1, 1, 0.92f);

        private const int PanelSize = 256;
        private const int GlyphSize = 128;

        private static Texture2D _panelNormal;
        private static Texture2D _panelActive;
        private static Texture2D _joyBase;
        private static Texture2D _joyKnob;
        private static readonly Dictionary<HudIcon, Texture2D> _glyphs =
            new Dictionary<HudIcon, Texture2D>();

        // ------------------------------------------------------------------
        public static Texture2D PanelNormal()
        {
            if (_panelNormal == null)
                _panelNormal = MakeRoundedRect(PanelSize, new Color(1, 1, 1, 0.22f), Panel, radius: 44f, borderW: 5f);
            return _panelNormal;
        }

        public static Texture2D PanelActive()
        {
            if (_panelActive == null)
                _panelActive = MakeRoundedRect(PanelSize, Accent, Panel, radius: 44f, borderW: 8f);
            return _panelActive;
        }

        public static Texture2D JoystickBase()
        {
            if (_joyBase == null)
            {
                _joyBase = new Texture2D(PanelSize, PanelSize, TextureFormat.RGBA32, false);
                _joyBase.wrapMode = TextureWrapMode.Clamp;
                var c = PanelSize * 0.5f;
                var px = _joyBase.GetPixels32();
                for (int y = 0; y < PanelSize; y++)
                    for (int x = 0; x < PanelSize; x++)
                    {
                        float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                        Color col = new Color(0, 0, 0, 0);
                        if (d < c - 6) col = new Color(0.02f, 0.03f, 0.05f, 0.35f);
                        else if (d < c) col = new Color(1, 1, 1, 0.35f);
                        px[y * PanelSize + x] = col;
                    }
                _joyBase.SetPixels32(px);
                _joyBase.Apply(false, false);
            }
            return _joyBase;
        }

        public static Texture2D JoystickKnob()
        {
            if (_joyKnob == null)
            {
                _joyKnob = new Texture2D(PanelSize, PanelSize, TextureFormat.RGBA32, false);
                _joyKnob.wrapMode = TextureWrapMode.Clamp;
                var c = PanelSize * 0.5f;
                var px = _joyKnob.GetPixels32();
                for (int y = 0; y < PanelSize; y++)
                    for (int x = 0; x < PanelSize; x++)
                    {
                        float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                        Color col = new Color(0, 0, 0, 0);
                        if (d < c * 0.82f) col = new Color(1, 1, 1, 0.55f);
                        else if (d < c * 0.95f) col = new Color(1, 1, 1, 0.25f);
                        px[y * PanelSize + x] = col;
                    }
                _joyKnob.SetPixels32(px);
                _joyKnob.Apply(false, false);
            }
            return _joyKnob;
        }

        private static Texture2D _whitePixel;

        /// <summary>1x1 white pixel, for ticks and bars.</summary>
        public static Texture2D WhitePixel()
        {
            if (_whitePixel == null)
            {
                _whitePixel = new Texture2D(1, 1, TextureFormat.RGBA32, false);
                _whitePixel.SetPixel(0, 0, Color.white);
                _whitePixel.Apply(false, false);
            }
            return _whitePixel;
        }

        private static Texture2D _caret;

        /// <summary>Small downward triangle (compass center caret).</summary>
        public static Texture2D Caret()
        {
            if (_caret == null)
            {
                int s = 48;
                _caret = new Texture2D(s, s, TextureFormat.RGBA32, false);
                var px = _caret.GetPixels32();
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        // Downward triangle: |x - c| <= (y / s) * c.
                        float c = s * 0.5f;
                        bool inside = Mathf.Abs(x - c) <= (y / (float)s) * c && y < s;
                        px[y * s + x] = inside ? (Color32)Accent : new Color32(0, 0, 0, 0);
                    }
                _caret.SetPixels32(px);
                _caret.Apply(false, false);
            }
            return _caret;
        }

        private static Texture2D _crosshair;

        /// <summary>Center-screen crosshair: 4 arms + dot, white.</summary>
        public static Texture2D Crosshair()
        {
            if (_crosshair == null)
            {
                int s = 96;
                _crosshair = new Texture2D(s, s, TextureFormat.RGBA32, false);
                var px = _crosshair.GetPixels32();
                float c = s * 0.5f;
                float gap = 12f, arm = 26f, w = 4f;
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float dx = Mathf.Abs(x - c), dy = Mathf.Abs(y - c);
                        bool h = dy <= w * 0.5f && dx >= gap && dx <= gap + arm;
                        bool v = dx <= w * 0.5f && dy >= gap && dy <= gap + arm;
                        bool dot = dx * dx + dy * dy <= 9f;
                        px[y * s + x] = (h || v || dot)
                            ? new Color32(255, 255, 255, 235)
                            : new Color32(0, 0, 0, 0);
                    }
                _crosshair.SetPixels32(px);
                _crosshair.Apply(false, false);
            }
            return _crosshair;
        }

        private static Texture2D _circleMask;

        /// <summary>Solid white circle, used as a Mask sprite for the minimap.</summary>
        public static Texture2D CircleMask()
        {
            if (_circleMask == null)
            {
                int s = PanelSize;
                _circleMask = new Texture2D(s, s, TextureFormat.RGBA32, false);
                _circleMask.wrapMode = TextureWrapMode.Clamp;
                var c = s * 0.5f;
                var px = _circleMask.GetPixels32();
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                        px[y * s + x] = d <= c ? new Color(1, 1, 1, 1)
                                               : new Color(0, 0, 0, 0);
                    }
                _circleMask.SetPixels32(px);
                _circleMask.Apply(false, false);
            }
            return _circleMask;
        }

        public static Texture2D Glyph(HudIcon icon)
        {
            Texture2D t;
            if (_glyphs.TryGetValue(icon, out t)) return t;
            t = RasterizeGlyph(icon);
            _glyphs[icon] = t;
            return t;
        }

        // ------------------------------------------------------------------
        private static Texture2D MakeRoundedRect(int size, Color bg, Color border,
            float radius, float borderW)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
            tex.wrapMode = TextureWrapMode.Clamp;
            var px = tex.GetPixels32();
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float dx = Mathf.Min(x, size - 1 - x);
                    float dy = Mathf.Min(y, size - 1 - y);
                    // Signed distance to the rounded-rect edge (inside negative).
                    float qx = radius - dx, qy = radius - dy;
                    float corner = Mathf.Sqrt(Mathf.Max(qx, 0) * Mathf.Max(qx, 0)
                                           + Mathf.Max(qy, 0) * Mathf.Max(qy, 0));
                    float sd = (qx > 0 && qy > 0) ? (corner - radius) : -Mathf.Min(dx, dy);
                    Color col = new Color(0, 0, 0, 0);
                    if (sd < -1.5f)
                    {
                        col = sd < -borderW - 1.5f ? bg : border;
                    }
                    else if (sd < 1.5f)
                    {
                        float a = 1.0f - (sd + 1.5f) / 3.0f;
                        Color edge = sd < -borderW ? bg : border;
                        col = new Color(edge.r, edge.g, edge.b, edge.a * a);
                    }
                    px[y * size + x] = col;
                }
            tex.SetPixels32(px);
            tex.Apply(false, false);
            return tex;
        }

        // ---------------- glyph rasterizer ----------------
        private class Raster
        {
            private readonly int _s;
            private readonly Color32[] _px;
            public Raster(int s) { _s = s; _px = new Color32[s * s]; }
            private void Put(int x, int y, Color c)
            {
                if (x < 0 || y < 0 || x >= _s || y >= _s) return;
                _px[y * _s + x] = c;
            }
            public void Line(Vector2 a, Vector2 b, float w, Color c)
            {
                Vector2 d = b - a;
                float len = d.magnitude;
                int steps = Mathf.Max(1, (int)(len * 2f));
                float r = w * 0.5f;
                for (int i = 0; i <= steps; i++)
                {
                    Vector2 p = a + d * (i / (float)steps);
                    for (int oy = -(int)r; oy <= (int)r; oy++)
                        for (int ox = -(int)r; ox <= (int)r; ox++)
                            if (ox * ox + oy * oy <= r * r)
                                Put((int)p.x + ox, (int)p.y + oy, c);
                }
            }
            public void Circle(Vector2 c0, float r, float w, Color c)
            {
                int steps = Mathf.Max(24, (int)(r * 4f));
                Vector2 prev = c0 + new Vector2(r, 0);
                for (int i = 1; i <= steps; i++)
                {
                    float a = i / (float)steps * Mathf.PI * 2f;
                    Vector2 p = c0 + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * r;
                    Line(prev, p, w, c);
                    prev = p;
                }
            }
            public void FillCircle(Vector2 c0, float r, Color c)
            {
                for (int y = (int)(c0.y - r); y <= c0.y + r; y++)
                    for (int x = (int)(c0.x - r); x <= c0.x + r; x++)
                    {
                        float dx = x - c0.x, dy = y - c0.y;
                        if (dx * dx + dy * dy <= r * r) Put(x, y, c);
                    }
            }
            public void Rect(float x0, float y0, float w, float h, Color c)
            {
                for (int y = (int)y0; y < y0 + h; y++)
                    for (int x = (int)x0; x < x0 + w; x++)
                        Put(x, y, c);
            }
            public void Poly(Vector2[] pts, Color c)
            {
                for (int i = 1; i < pts.Length; i++)
                    Line(pts[i - 1], pts[i], 2f, c);
                Line(pts[pts.Length - 1], pts[0], 2f, c);
            }
            public void FillPoly(Vector2[] pts, Color c)
            {
                // Scanline fill over the polygon bounding box.
                float minY = pts[0].y, maxY = pts[0].y;
                foreach (var p in pts) { minY = Mathf.Min(minY, p.y); maxY = Mathf.Max(maxY, p.y); }
                for (int y = (int)minY; y <= (int)maxY; y++)
                {
                    var xs = new System.Collections.Generic.List<float>();
                    for (int i = 0; i < pts.Length; i++)
                    {
                        Vector2 a = pts[i], b = pts[(i + 1) % pts.Length];
                        if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y))
                            xs.Add(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x));
                    }
                    xs.Sort();
                    for (int i = 0; i + 1 < xs.Count; i += 2)
                        for (int x = (int)xs[i]; x <= (int)xs[i + 1]; x++)
                            Put(x, y, c);
                }
            }
            public Texture2D ToTexture()
            {
                var t = new Texture2D(_s, _s, TextureFormat.RGBA32, false);
                t.wrapMode = TextureWrapMode.Clamp;
                t.SetPixels32(_px);
                t.Apply(false, false);
                return t;
            }
        }

        private static Texture2D RasterizeGlyph(HudIcon icon)
        {
            int s = GlyphSize;
            var r = new Raster(s);
            var c = new Vector2(s * 0.5f, s * 0.5f);
            var wcol = IconWhite;
            float w = Mathf.Max(3f, s * 0.055f);
            switch (icon)
            {
                case HudIcon.Fire: // bullet: body + tip
                    {
                        float bw = s * 0.21f;
                        r.Rect(c.x - bw * 0.5f, c.y - s * 0.18f, bw, s * 0.45f, wcol);
                        r.FillPoly(new[] {
                            new Vector2(c.x - bw * 0.5f, c.y - s * 0.18f),
                            new Vector2(c.x + bw * 0.5f, c.y - s * 0.18f),
                            new Vector2(c.x, c.y - s * 0.42f) }, wcol);
                        r.Rect(c.x - bw * 0.5f, c.y + s * 0.27f, bw, s * 0.09f,
                            new Color(1, 1, 1, 0.45f));
                        break;
                    }
                case HudIcon.Ads: // scope: circle + cross
                    r.Circle(c, s * 0.31f, w, wcol);
                    r.Line(c + new Vector2(-s * 0.31f, 0), c + new Vector2(s * 0.31f, 0), w * 0.7f, wcol);
                    r.Line(c + new Vector2(0, -s * 0.31f), c + new Vector2(0, s * 0.31f), w * 0.7f, wcol);
                    r.FillCircle(c, w * 0.9f, Accent);
                    break;
                case HudIcon.Jump: // double chevron up
                    for (int k = 0; k < 2; k++)
                    {
                        float y = c.y + s * 0.18f - k * s * 0.21f;
                        r.Line(new Vector2(c.x - s * 0.27f, y), new Vector2(c.x, y - s * 0.19f), w, wcol);
                        r.Line(new Vector2(c.x + s * 0.27f, y), new Vector2(c.x, y - s * 0.19f), w, wcol);
                    }
                    break;
                case HudIcon.Crouch: // double chevron down
                    for (int k = 0; k < 2; k++)
                    {
                        float y = c.y - s * 0.18f + k * s * 0.21f;
                        r.Line(new Vector2(c.x - s * 0.27f, y), new Vector2(c.x, y + s * 0.19f), w, wcol);
                        r.Line(new Vector2(c.x + s * 0.27f, y), new Vector2(c.x, y + s * 0.19f), w, wcol);
                    }
                    break;
                case HudIcon.Prone: // lying figure
                    r.FillCircle(c + new Vector2(-s * 0.27f, -s * 0.07f), s * 0.11f, wcol);
                    r.Rect(c.x - s * 0.15f, c.y - s * 0.01f, s * 0.52f, s * 0.15f, wcol);
                    r.Line(new Vector2(c.x - s * 0.37f, c.y + s * 0.21f),
                           new Vector2(c.x + s * 0.37f, c.y + s * 0.21f), w * 0.7f, wcol);
                    break;
                case HudIcon.Grenade: // round body + lever + pin ring
                    r.FillCircle(c + new Vector2(0, s * 0.09f), s * 0.26f, wcol);
                    r.Line(c + new Vector2(-s * 0.15f, -s * 0.15f), c + new Vector2(s * 0.22f, -s * 0.22f), w, wcol);
                    r.Circle(c + new Vector2(s * 0.31f, -s * 0.26f), s * 0.10f, w * 0.8f, wcol);
                    break;
                case HudIcon.Sprint: // double chevron right
                    for (int k = 0; k < 2; k++)
                    {
                        float x = c.x - s * 0.18f + k * s * 0.21f;
                        r.Line(new Vector2(x, c.y - s * 0.27f), new Vector2(x + s * 0.19f, c.y), w, wcol);
                        r.Line(new Vector2(x + s * 0.19f, c.y), new Vector2(x, c.y + s * 0.27f), w, wcol);
                    }
                    break;
                case HudIcon.Reload: // circular arrow
                    {
                        float rr = s * 0.27f;
                        int steps = 40;
                        Vector2 prev = c + new Vector2(Mathf.Cos(0.6f), Mathf.Sin(0.6f)) * rr;
                        for (int i = 1; i <= steps; i++)
                        {
                            float a = 0.6f + (i / (float)steps) * (Mathf.PI * 2f - 0.8f);
                            Vector2 p = c + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * rr;
                            r.Line(prev, p, w, wcol);
                            prev = p;
                        }
                        Vector2 tip = c + new Vector2(Mathf.Cos(0.6f), Mathf.Sin(0.6f)) * rr;
                        r.Line(tip, tip + new Vector2(-s * 0.14f, s * 0.03f), w, wcol);
                        r.Line(tip, tip + new Vector2(-s * 0.03f, -s * 0.14f), w, wcol);
                        break;
                    }
                case HudIcon.Swap: // opposing up/down arrows
                    r.Line(new Vector2(c.x - s * 0.15f, c.y + s * 0.22f), new Vector2(c.x - s * 0.15f, c.y - s * 0.22f), w, wcol);
                    r.Line(new Vector2(c.x - s * 0.15f, c.y - s * 0.22f), new Vector2(c.x - s * 0.24f, c.y - s * 0.09f), w, wcol);
                    r.Line(new Vector2(c.x - s * 0.15f, c.y - s * 0.22f), new Vector2(c.x - s * 0.06f, c.y - s * 0.09f), w, wcol);
                    r.Line(new Vector2(c.x + s * 0.15f, c.y - s * 0.22f), new Vector2(c.x + s * 0.15f, c.y + s * 0.22f), w, wcol);
                    r.Line(new Vector2(c.x + s * 0.15f, c.y + s * 0.22f), new Vector2(c.x + s * 0.24f, c.y + s * 0.09f), w, wcol);
                    r.Line(new Vector2(c.x + s * 0.15f, c.y + s * 0.22f), new Vector2(c.x + s * 0.06f, c.y + s * 0.09f), w, wcol);
                    break;
                case HudIcon.Armor: // shield outline + plate line
                    r.Poly(new[] {
                        new Vector2(c.x, c.y - s * 0.31f),
                        new Vector2(c.x + s * 0.26f, c.y - s * 0.17f),
                        new Vector2(c.x + s * 0.26f, c.y + s * 0.07f),
                        new Vector2(c.x, c.y + s * 0.31f),
                        new Vector2(c.x - s * 0.26f, c.y + s * 0.07f),
                        new Vector2(c.x - s * 0.26f, c.y - s * 0.17f) }, wcol);
                    r.Line(c + new Vector2(-s * 0.14f, 0), c + new Vector2(s * 0.14f, 0), w * 0.8f, wcol);
                    break;
                case HudIcon.Skill: // star
                    {
                        var pts = new Vector2[10];
                        for (int k = 0; k < 10; k++)
                        {
                            float rr = (k % 2 == 0) ? s * 0.31f : s * 0.14f;
                            float a = -Mathf.PI * 0.5f + k * Mathf.PI / 5f;
                            pts[k] = c + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * rr;
                        }
                        r.FillPoly(pts, wcol);
                        break;
                    }
                case HudIcon.Inspect: // magnifier
                    r.Circle(c + new Vector2(-s * 0.07f, -s * 0.07f), s * 0.20f, w, wcol);
                    r.Line(c + new Vector2(s * 0.07f, s * 0.07f), c + new Vector2(s * 0.28f, s * 0.28f), w, wcol);
                    break;
                case HudIcon.Emote: // smiley
                    r.Circle(c, s * 0.28f, w, wcol);
                    r.FillCircle(c + new Vector2(-s * 0.10f, -s * 0.06f), w * 0.55f, wcol);
                    r.FillCircle(c + new Vector2(s * 0.10f, -s * 0.06f), w * 0.55f, wcol);
                    {
                        int steps = 16;
                        Vector2 prev = c + new Vector2(Mathf.Cos(0.7f), Mathf.Sin(0.7f)) * s * 0.16f;
                        for (int i = 1; i <= steps; i++)
                        {
                            float a = 0.7f + (i / (float)steps) * (Mathf.PI - 1.4f);
                            Vector2 p = c + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * s * 0.16f;
                            r.Line(prev, p, w * 0.8f, wcol);
                            prev = p;
                        }
                        break;
                    }
                case HudIcon.Ping: // diamond marker + dot
                    r.Poly(new[] {
                        new Vector2(c.x, c.y - s * 0.27f), new Vector2(c.x + s * 0.22f, c.y),
                        new Vector2(c.x, c.y + s * 0.27f), new Vector2(c.x - s * 0.22f, c.y) }, wcol);
                    r.FillCircle(c, s * 0.08f, wcol);
                    break;
                case HudIcon.Smoke: // canister + wavy smoke
                    r.Rect(c.x - s * 0.14f, c.y - s * 0.05f, s * 0.28f, s * 0.32f, wcol);
                    for (int k = 0; k < 3; k++)
                    {
                        float x = c.x - s * 0.15f + k * s * 0.15f;
                        r.Line(new Vector2(x, c.y - s * 0.12f), new Vector2(x + s * 0.06f, c.y - s * 0.22f), w * 0.7f, wcol);
                        r.Line(new Vector2(x + s * 0.06f, c.y - s * 0.22f), new Vector2(x - s * 0.02f, c.y - s * 0.31f), w * 0.7f, wcol);
                    }
                    break;
                case HudIcon.Nade: // frag: small circle + fins (selection icon)
                    r.FillCircle(c, s * 0.20f, wcol);
                    r.Line(new Vector2(c.x, c.y - s * 0.20f), new Vector2(c.x, c.y - s * 0.34f), w, wcol);
                    break;
                case HudIcon.Gear: // gear: 8 teeth + ring + hub
                    for (int k = 0; k < 8; k++)
                    {
                        float a = k * Mathf.PI / 4f;
                        Vector2 d = new Vector2(Mathf.Cos(a), Mathf.Sin(a));
                        r.Line(c + d * s * 0.21f, c + d * s * 0.31f, w * 1.1f, wcol);
                    }
                    r.Circle(c, s * 0.20f, w, wcol);
                    r.FillCircle(c, s * 0.07f, wcol);
                    break;
                default:
                    r.FillCircle(c, s * 0.15f, wcol);
                    break;
            }
            var tex = r.ToTexture();
            return tex;
        }
    }
}
