using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.World
{
    /// <summary>
    /// Shared world materials, generated once by WorldBuilder. Procedural textures come
    /// from Core/ProcTexture — each material below documents its texture slot and tile
    /// size so real art can replace the procedural textures 1:1 later (same material
    /// names, same _MainTex slots, same world-unit UV tiling; see WorldBatch).
    /// Texture resolution steps down on the Low quality tier (WorldQuality).
    /// </summary>
    public sealed class WorldMaterials
    {
        // Structural
        public Material Wall, Trim, Concrete, ConcreteDark, Wood, WoodDark;
        // Roads
        public Material Road, AsphaltPlain, PaintWhite, PaintYellow, Curb, Sidewalk;
        // Nature
        public Material Grass, Dirt, Sand, Trunk, Foliage, RockM;
        // Metal / roofs / glass
        public Material Metal, SteelDark, RoofRed, RoofGrey, GlassDark, Emissive;
        // Water (offset scrolled by WaterAnimator)
        public Material Water;
        // Port dressing
        public Material ContainerRed, ContainerBlue, ContainerGreen, ContainerOrange, ContainerYellow;
        public Material HullBlack, DeckGrey, CraneYellow, CraneWhite;

        private static Material Lit(Shader s, string name, Color tint, Texture2D tex = null)
        {
            var m = new Material(s);
            m.name = name;
            m.SetColor("_Color", tint);
            if (tex != null) m.SetTexture("_MainTex", tex);
            return m;
        }

        public static WorldMaterials Create()
        {
            Shader lit = Shader.Find("Nova/VertexLit");
            Shader emissive = Shader.Find("Nova/Emissive");
            Shader water = Shader.Find("Nova/Water");
            if (lit == null) lit = Shader.Find("Standard");
            if (emissive == null) emissive = Shader.Find("Standard");

            int big = WorldQuality.TextureSize(256);
            int small = WorldQuality.TextureSize(128);

            // Procedural texture slots (1:1 replaceable by real art later).
            Texture2D grassTex = ProcTexture.Grass(big);          // tile ~8m
            Texture2D dirtTex = ProcTexture.Dirt(big);            // tile ~8m
            Texture2D roadTex = ProcTexture.Road(big);            // u 0..1 across road, v tiles ~12m along
            Texture2D plasterTex = ProcTexture.Wall(new Color(0.90f, 0.88f, 0.84f), big); // tile ~4m, grime at v=0
            Texture2D concreteTex = ProcTexture.Wall(new Color(0.64f, 0.62f, 0.59f), big); // tile ~4m
            Texture2D concreteDarkTex = ProcTexture.Wall(new Color(0.45f, 0.44f, 0.42f), big);
            Texture2D asphaltPlainTex = ProcTexture.Wall(new Color(0.20f, 0.20f, 0.22f), big);
            Texture2D foliageTex = ProcTexture.Foliage(small);
            Texture2D waterTex = ProcTexture.Water(small);

            var m = new WorldMaterials();
            // Structural: plaster texture tinted per building via vertex colors.
            m.Wall = Lit(lit, "Wall_Plaster", Color.white, plasterTex);
            m.Trim = Lit(lit, "Trim", new Color(0.30f, 0.28f, 0.26f));
            m.Concrete = Lit(lit, "Concrete", Color.white, concreteTex);
            m.ConcreteDark = Lit(lit, "ConcreteDark", Color.white, concreteDarkTex);
            m.Wood = Lit(lit, "Wood", new Color(0.62f, 0.45f, 0.29f), plasterTex);
            m.WoodDark = Lit(lit, "WoodDark", new Color(0.38f, 0.27f, 0.17f));
            // Roads: Road() carries lane markings, center dashes, tire-wear bands.
            m.Road = Lit(lit, "Road_Asphalt", Color.white, roadTex);
            m.AsphaltPlain = Lit(lit, "AsphaltPlain", Color.white, asphaltPlainTex);
            m.PaintWhite = Lit(lit, "PaintWhite", new Color(0.92f, 0.92f, 0.90f));
            m.PaintYellow = Lit(lit, "PaintYellow", new Color(0.90f, 0.72f, 0.12f));
            m.Curb = Lit(lit, "Curb", Color.white, concreteDarkTex);
            m.Sidewalk = Lit(lit, "Sidewalk", Color.white, concreteTex);
            // Nature.
            m.Grass = Lit(lit, "Grass", Color.white, grassTex);
            m.Dirt = Lit(lit, "Dirt", Color.white, dirtTex);
            m.Sand = Lit(lit, "Sand", new Color(0.85f, 0.76f, 0.58f), dirtTex);
            m.Trunk = Lit(lit, "Trunk", new Color(0.36f, 0.25f, 0.15f));
            m.Foliage = Lit(lit, "Foliage", Color.white, foliageTex);
            m.RockM = Lit(lit, "Rock", new Color(0.72f, 0.70f, 0.66f), dirtTex);
            // Metal / roofs / glass.
            m.Metal = Lit(lit, "Metal", new Color(0.55f, 0.57f, 0.60f));
            m.SteelDark = Lit(lit, "SteelDark", new Color(0.24f, 0.25f, 0.27f));
            m.RoofRed = Lit(lit, "RoofRed", new Color(0.60f, 0.33f, 0.22f), concreteDarkTex);
            m.RoofGrey = Lit(lit, "RoofGrey", new Color(0.45f, 0.45f, 0.47f), concreteDarkTex);
            m.GlassDark = Lit(lit, "GlassDark", new Color(0.12f, 0.16f, 0.20f));
            // Emissive bits (lamps, signs, window glow): cheap, no real lights.
            m.Emissive = new Material(emissive);
            m.Emissive.name = "Emissive";
            m.Emissive.SetColor("_Color", new Color(1f, 0.9f, 0.65f));
            // Water: noise texture, offset scrolled by WaterAnimator.
            m.Water = water != null ? new Material(water) : Lit(lit, "WaterFallback", new Color(0.10f, 0.30f, 0.45f));
            m.Water.name = "Water";
            m.Water.SetTexture("_MainTex", waterTex);
            // Port dressing: painted metal, flat colors (detail pass can add textures later).
            m.ContainerRed = Lit(lit, "ContainerRed", new Color(0.72f, 0.17f, 0.13f));
            m.ContainerBlue = Lit(lit, "ContainerBlue", new Color(0.13f, 0.31f, 0.63f));
            m.ContainerGreen = Lit(lit, "ContainerGreen", new Color(0.15f, 0.51f, 0.29f));
            m.ContainerOrange = Lit(lit, "ContainerOrange", new Color(0.86f, 0.46f, 0.11f));
            m.ContainerYellow = Lit(lit, "ContainerYellow", new Color(0.86f, 0.71f, 0.16f));
            m.HullBlack = Lit(lit, "HullBlack", new Color(0.11f, 0.12f, 0.14f));
            m.DeckGrey = Lit(lit, "DeckGrey", Color.white, concreteDarkTex);
            m.CraneYellow = Lit(lit, "CraneYellow", new Color(0.89f, 0.69f, 0.13f));
            m.CraneWhite = Lit(lit, "CraneWhite", new Color(0.86f, 0.87f, 0.89f));
            return m;
        }
    }
}
