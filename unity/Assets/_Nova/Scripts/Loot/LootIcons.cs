using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Loot
{
    /// <summary>Icon kinds for the loot UI panels (mirrors the CODM reference frames).</summary>
    public enum LootIconKind
    {
        Gun, Ammo, Health, Armor, Frag, Smoke, Attachment, Scorestreak, FuelCan, Cash
    }

    /// <summary>
    /// Procedural 64x64 item icons for the NEARBY / BOX panels and pickup cards.
    /// Pixel-drawn once at startup and cached — no art assets needed. Structured so
    /// real art can replace these 1:1 later (same lookup by LootIconKind).
    /// </summary>
    public static class LootIcons
    {
        public const int Size = 64;
        private static readonly Dictionary<LootIconKind, Texture2D> Cache =
            new Dictionary<LootIconKind, Texture2D>();

        public static Texture2D Get(LootIconKind kind)
        {
            Texture2D t;
            if (Cache.TryGetValue(kind, out t)) return t;
            var px = new Pix();
            switch (kind)
            {
                case LootIconKind.Gun: DrawGun(px); break;
                case LootIconKind.Ammo: DrawAmmo(px); break;
                case LootIconKind.Health: DrawHealth(px); break;
                case LootIconKind.Armor: DrawArmor(px); break;
                case LootIconKind.Frag: DrawFrag(px); break;
                case LootIconKind.Smoke: DrawSmoke(px); break;
                case LootIconKind.Attachment: DrawAttachment(px); break;
                case LootIconKind.Scorestreak: DrawStreak(px); break;
                case LootIconKind.FuelCan: DrawFuel(px); break;
                case LootIconKind.Cash: DrawCash(px); break;
            }
            t = px.Build();
            Cache[kind] = t;
            return t;
        }

        public static LootIconKind ForKind(LootKind kind)
        {
            switch (kind)
            {
                case LootKind.Health: return LootIconKind.Health;
                case LootKind.Armor:
                case LootKind.Shard: return LootIconKind.Armor;
                case LootKind.Ammo: return LootIconKind.Ammo;
                case LootKind.Cash: return LootIconKind.Cash;
                case LootKind.Frag: return LootIconKind.Frag;
                case LootIconKind.Smoke: return LootIconKind.Smoke;
                case LootKind.Scorestreak: return LootIconKind.Scorestreak;
                case LootKind.FuelCan: return LootIconKind.FuelCan;
                case LootKind.Attachment: return LootIconKind.Attachment;
                default: return LootIconKind.Ammo;
            }
        }

        // ---- pixel canvas ----

        private sealed class Pix
        {
            private readonly Color[] _c = new Color[Size * Size];

            public void Rect(int x0, int y0, int w, int h, Color c)
            {
                for (int y = y0; y < y0 + h; y++)
                    for (int x = x0; x < x0 + w; x++)
                        if (x >= 0 && y >= 0 && x < Size && y < Size)
                            _c[y * Size + x] = c;
            }

            public void Circle(int cx, int cy, int r, Color c)
            {
                for (int y = cy - r; y <= cy + r; y++)
                    for (int x = cx - r; x <= cx + r; x++)
                    {
                        int dx = x - cx, dy = y - cy;
                        if (dx * dx + dy * dy <= r * r && x >= 0 && y >= 0 && x < Size && y < Size)
                            _c[y * Size + x] = c;
                    }
            }

            public Texture2D Build()
            {
                var t = new Texture2D(Size, Size, TextureFormat.RGBA32, false);
                t.filterMode = FilterMode.Point;
                t.SetPixels(_c);
                t.Apply(false, true);
                return t;
            }
        }

        // ---- icons (y=0 is bottom) ----

        private static void DrawGun(Pix p)
        {
            Color dark = new Color(0.16f, 0.16f, 0.18f, 1f);
            p.Rect(10, 26, 34, 8, dark);   // body
            p.Rect(44, 29, 12, 3, dark);   // barrel
            p.Rect(4, 28, 8, 6, dark);     // stock
            p.Rect(20, 18, 5, 9, dark);    // grip
            p.Rect(30, 34, 8, 4, dark);    // sight
            p.Rect(24, 34, 3, 8, new Color(0.9f, 0.6f, 0.15f, 1f)); // accent
        }

        private static void DrawAmmo(Pix p)
        {
            Color box = new Color(0.45f, 0.38f, 0.25f, 1f);
            Color tip = new Color(0.95f, 0.65f, 0.25f, 1f);
            p.Rect(12, 12, 40, 20, box);
            for (int i = 0; i < 4; i++)
            {
                int x = 16 + i * 10;
                p.Rect(x, 32, 6, 10, tip);
                p.Rect(x + 1, 40, 4, 4, tip);
            }
        }

        private static void DrawHealth(Pix p)
        {
            Color white = new Color(0.92f, 0.93f, 0.95f, 1f);
            Color red = new Color(0.85f, 0.10f, 0.12f, 1f);
            p.Rect(10, 18, 44, 28, white);
            p.Rect(26, 24, 12, 16, red);
            p.Rect(21, 29, 22, 6, red);
        }

        private static void DrawArmor(Pix p)
        {
            Color plate = new Color(0.30f, 0.45f, 0.85f, 1f);
            p.Rect(16, 14, 32, 30, plate);
            p.Rect(20, 44, 24, 8, plate);
            p.Rect(20, 24, 24, 4, new Color(0.55f, 0.70f, 1f, 1f));
        }

        private static void DrawFrag(Pix p)
        {
            p.Circle(30, 26, 14, new Color(0.20f, 0.28f, 0.16f, 1f));
            p.Rect(26, 40, 10, 4, new Color(0.5f, 0.5f, 0.52f, 1f));
            p.Circle(44, 42, 5, new Color(0.6f, 0.6f, 0.62f, 1f));
        }

        private static void DrawSmoke(Pix p)
        {
            p.Rect(24, 12, 16, 36, new Color(0.55f, 0.57f, 0.60f, 1f));
            p.Rect(24, 30, 16, 8, new Color(0.75f, 0.75f, 0.78f, 1f));
        }

        private static void DrawAttachment(Pix p)
        {
            p.Rect(10, 20, 44, 24, new Color(0.16f, 0.17f, 0.20f, 1f));
            p.Rect(16, 28, 32, 8, new Color(0.30f, 0.55f, 0.85f, 1f));
        }

        private static void DrawStreak(Pix p)
        {
            Color body = new Color(0.25f, 0.28f, 0.32f, 1f);
            Color rotor = new Color(0.2f, 0.8f, 1f, 1f);
            p.Rect(24, 24, 16, 16, body);
            p.Circle(18, 44, 6, rotor);
            p.Circle(46, 44, 6, rotor);
            p.Circle(18, 20, 6, rotor);
            p.Circle(46, 20, 6, rotor);
        }

        private static void DrawFuel(Pix p)
        {
            p.Rect(20, 10, 24, 40, new Color(0.75f, 0.12f, 0.08f, 1f));
            p.Rect(20, 50, 24, 6, new Color(0.15f, 0.15f, 0.16f, 1f));
            p.Rect(38, 50, 8, 8, new Color(0.15f, 0.15f, 0.16f, 1f));
        }

        private static void DrawCash(Pix p)
        {
            p.Rect(10, 20, 44, 24, new Color(0.15f, 0.55f, 0.25f, 1f));
            p.Rect(10, 28, 44, 8, new Color(0.85f, 0.80f, 0.60f, 1f));
        }
    }
}
