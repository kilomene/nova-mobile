using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Vehicle paint jobs ported 1:1 from vehicle_skins.gd.
    /// Roughness is converted to Unity smoothness (1 - roughness).
    /// </summary>
    public struct SkinDef
    {
        public string Name;
        public Color Color;
        public float Metallic;
        public float Smoothness;
    }

    public static class VehicleSkins
    {
        private static readonly Dictionary<VehicleType, SkinDef[]> Table = new Dictionary<VehicleType, SkinDef[]>
        {
            { VehicleType.Sedan, new SkinDef[] {
                new SkinDef { Name = "Midnight",    Color = new Color(0.05f, 0.06f, 0.10f), Metallic = 0.7f, Smoothness = 0.65f },
                new SkinDef { Name = "Crimson",     Color = new Color(0.55f, 0.04f, 0.06f), Metallic = 0.6f, Smoothness = 0.70f },
                new SkinDef { Name = "Arctic",      Color = new Color(0.82f, 0.85f, 0.88f), Metallic = 0.4f, Smoothness = 0.60f },
                new SkinDef { Name = "Desert Camo", Color = new Color(0.55f, 0.48f, 0.32f), Metallic = 0.1f, Smoothness = 0.20f },
            } },
            { VehicleType.SUV, new SkinDef[] {
                new SkinDef { Name = "Onyx",      Color = new Color(0.04f, 0.04f, 0.05f), Metallic = 0.7f, Smoothness = 0.65f },
                new SkinDef { Name = "Forest",    Color = new Color(0.08f, 0.22f, 0.12f), Metallic = 0.5f, Smoothness = 0.55f },
                new SkinDef { Name = "Sandstorm", Color = new Color(0.72f, 0.62f, 0.42f), Metallic = 0.2f, Smoothness = 0.30f },
                new SkinDef { Name = "Chrome",    Color = new Color(0.85f, 0.87f, 0.90f), Metallic = 1.0f, Smoothness = 0.92f },
            } },
            { VehicleType.Pickup, new SkinDef[] {
                new SkinDef { Name = "Workhorse Red", Color = new Color(0.50f, 0.08f, 0.05f), Metallic = 0.4f, Smoothness = 0.50f },
                new SkinDef { Name = "Navy",          Color = new Color(0.05f, 0.12f, 0.28f), Metallic = 0.5f, Smoothness = 0.55f },
                new SkinDef { Name = "Mud Camo",      Color = new Color(0.35f, 0.30f, 0.20f), Metallic = 0.1f, Smoothness = 0.15f },
                new SkinDef { Name = "Sunset",        Color = new Color(0.75f, 0.35f, 0.08f), Metallic = 0.6f, Smoothness = 0.70f },
            } },
            { VehicleType.SportsCar, new SkinDef[] {
                new SkinDef { Name = "Rosso",   Color = new Color(0.65f, 0.03f, 0.04f), Metallic = 0.8f,  Smoothness = 0.80f },
                new SkinDef { Name = "Volt",    Color = new Color(0.55f, 0.80f, 0.05f), Metallic = 0.7f,  Smoothness = 0.75f },
                new SkinDef { Name = "Stealth", Color = new Color(0.03f, 0.03f, 0.04f), Metallic = 0.9f,  Smoothness = 0.85f },
                new SkinDef { Name = "Azure",   Color = new Color(0.05f, 0.25f, 0.65f), Metallic = 0.75f, Smoothness = 0.78f },
            } },
            { VehicleType.ATV, new SkinDef[] {
                new SkinDef { Name = "Olive",   Color = new Color(0.25f, 0.28f, 0.15f), Metallic = 0.2f, Smoothness = 0.30f },
                new SkinDef { Name = "Redline", Color = new Color(0.60f, 0.08f, 0.06f), Metallic = 0.3f, Smoothness = 0.45f },
                new SkinDef { Name = "Cobalt",  Color = new Color(0.06f, 0.20f, 0.50f), Metallic = 0.3f, Smoothness = 0.45f },
            } },
            { VehicleType.ArmoredSUV, new SkinDef[] {
                new SkinDef { Name = "Matte Black", Color = new Color(0.03f, 0.03f, 0.035f), Metallic = 0.4f, Smoothness = 0.30f },
                new SkinDef { Name = "Gunmetal",    Color = new Color(0.18f, 0.19f, 0.21f),  Metallic = 0.7f, Smoothness = 0.55f },
                new SkinDef { Name = "Desert Tan",  Color = new Color(0.60f, 0.52f, 0.36f),  Metallic = 0.2f, Smoothness = 0.25f },
            } },
            { VehicleType.Jeep, new SkinDef[] {
                new SkinDef { Name = "Army Green",   Color = new Color(0.16f, 0.22f, 0.12f), Metallic = 0.2f, Smoothness = 0.30f },
                new SkinDef { Name = "Rescue Orange", Color = new Color(0.70f, 0.30f, 0.05f), Metallic = 0.4f, Smoothness = 0.50f },
                new SkinDef { Name = "Ocean",        Color = new Color(0.05f, 0.25f, 0.45f), Metallic = 0.4f, Smoothness = 0.50f },
            } },
            { VehicleType.Motorcycle, new SkinDef[] {
                new SkinDef { Name = "Ninja Black", Color = new Color(0.03f, 0.03f, 0.04f), Metallic = 0.7f, Smoothness = 0.70f },
                new SkinDef { Name = "Flame",       Color = new Color(0.60f, 0.10f, 0.05f), Metallic = 0.6f, Smoothness = 0.65f },
                new SkinDef { Name = "Ice",         Color = new Color(0.70f, 0.80f, 0.88f), Metallic = 0.5f, Smoothness = 0.60f },
            } },
            { VehicleType.CargoTruck, new SkinDef[] {
                new SkinDef { Name = "Fleet White",    Color = new Color(0.80f, 0.80f, 0.82f), Metallic = 0.2f, Smoothness = 0.40f },
                new SkinDef { Name = "Logistics Blue", Color = new Color(0.06f, 0.18f, 0.45f), Metallic = 0.3f, Smoothness = 0.45f },
                new SkinDef { Name = "Hazard",         Color = new Color(0.65f, 0.45f, 0.05f), Metallic = 0.3f, Smoothness = 0.45f },
            } },
            { VehicleType.Tank, new SkinDef[] {
                new SkinDef { Name = "Woodland", Color = new Color(0.15f, 0.20f, 0.12f), Metallic = 0.3f, Smoothness = 0.25f },
                new SkinDef { Name = "Desert",   Color = new Color(0.58f, 0.50f, 0.34f), Metallic = 0.3f, Smoothness = 0.25f },
                new SkinDef { Name = "Arctic",   Color = new Color(0.75f, 0.78f, 0.80f), Metallic = 0.3f, Smoothness = 0.25f },
            } },
            { VehicleType.Helicopter, new SkinDef[] {
                new SkinDef { Name = "Gunship Grey", Color = new Color(0.20f, 0.21f, 0.23f), Metallic = 0.5f, Smoothness = 0.50f },
                new SkinDef { Name = "Rescue",       Color = new Color(0.65f, 0.12f, 0.08f), Metallic = 0.4f, Smoothness = 0.50f },
                new SkinDef { Name = "Stealth",      Color = new Color(0.04f, 0.04f, 0.05f), Metallic = 0.7f, Smoothness = 0.65f },
            } },
            { VehicleType.Boat, new SkinDef[] {
                new SkinDef { Name = "Coast Guard", Color = new Color(0.75f, 0.12f, 0.08f), Metallic = 0.3f, Smoothness = 0.50f },
                new SkinDef { Name = "Navy",        Color = new Color(0.10f, 0.16f, 0.30f), Metallic = 0.3f, Smoothness = 0.50f },
                new SkinDef { Name = "Pearl",       Color = new Color(0.85f, 0.86f, 0.88f), Metallic = 0.4f, Smoothness = 0.55f },
            } },
            { VehicleType.HoverBike, new SkinDef[] {
                new SkinDef { Name = "Neon",  Color = new Color(0.05f, 0.08f, 0.16f), Metallic = 0.8f, Smoothness = 0.75f },
                new SkinDef { Name = "Ghost", Color = new Color(0.80f, 0.82f, 0.85f), Metallic = 0.6f, Smoothness = 0.65f },
                new SkinDef { Name = "Viper", Color = new Color(0.10f, 0.35f, 0.08f), Metallic = 0.7f, Smoothness = 0.70f },
            } },
            { VehicleType.Skateboard, new SkinDef[] {
                new SkinDef { Name = "Street", Color = new Color(0.10f, 0.10f, 0.12f), Metallic = 0.2f, Smoothness = 0.30f },
                new SkinDef { Name = "Flame",  Color = new Color(0.55f, 0.12f, 0.05f), Metallic = 0.2f, Smoothness = 0.30f },
                new SkinDef { Name = "Wave",   Color = new Color(0.08f, 0.30f, 0.50f), Metallic = 0.2f, Smoothness = 0.30f },
            } },
            { VehicleType.B2Bomber, new SkinDef[] {
                new SkinDef { Name = "Spectre",    Color = new Color(0.03f, 0.03f, 0.04f), Metallic = 0.6f, Smoothness = 0.50f },
                new SkinDef { Name = "Ghost Grey", Color = new Color(0.25f, 0.26f, 0.28f), Metallic = 0.5f, Smoothness = 0.45f },
                new SkinDef { Name = "Night Ops",  Color = new Color(0.02f, 0.03f, 0.06f), Metallic = 0.8f, Smoothness = 0.70f },
            } },
        };

        private static readonly SkinDef Standard = new SkinDef
        {
            Name = "Standard", Color = new Color(0.20f, 0.20f, 0.22f), Metallic = 0.5f, Smoothness = 0.50f
        };

        public static int Count(VehicleType t)
        {
            return Table.TryGetValue(t, out SkinDef[] arr) ? arr.Length : 0;
        }

        public static SkinDef Get(VehicleType t, int idx)
        {
            if (!Table.TryGetValue(t, out SkinDef[] arr) || arr.Length == 0) return Standard;
            if (idx < 0) idx = 0;
            if (idx >= arr.Length) idx = arr.Length - 1;
            return arr[idx];
        }

        public static int RandomIndex(VehicleType t)
        {
            int c = Count(t);
            if (c <= 1) return 0;
            return UnityEngine.Random.Range(0, c);
        }

        /// <summary>Apply a paint job to every paint renderer of a built model.</summary>
        public static void Apply(VehicleModel model, VehicleType t, int idx)
        {
            if (model == null || model.PaintRenderers == null) return;
            Material mat = VehicleMats.Skin(t, idx);
            for (int i = 0; i < model.PaintRenderers.Count; i++)
            {
                MeshRenderer r = model.PaintRenderers[i];
                if (r != null) r.sharedMaterial = mat;
            }
        }
    }
}
