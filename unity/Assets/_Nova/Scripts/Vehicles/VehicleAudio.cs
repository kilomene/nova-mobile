using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Procedural vehicle audio, ported 1:1 from vehicle_audio.gd synthesis recipes.
    /// All clips are generated once (Prewarm / static ctor) and cached — never at runtime.
    /// Engine pitch follows RPM via AudioSource.pitch = 0.7 + rpm01 * 1.1.
    /// </summary>
    public static class VehicleAudio
    {
        private const int Rate = ProcAudio.SampleRate;

        // Horn style indices (matches VehicleController.HornIndex).
        public const int HornCar = 0;
        public const int HornTruck = 1;
        public const int HornBike = 2;
        public const int HornTank = 3;
        public const int HornBoat = 4;

        private static bool _warmed;

        /// <summary>Pre-generate every engine loop, horn, skid and thud. Idempotent.</summary>
        public static void Prewarm()
        {
            if (_warmed) return;
            _warmed = true;
            string[] kinds = { "v8", "diesel", "bike", "electric", "heli", "boat", "jet" };
            for (int i = 0; i < kinds.Length; i++) EngineLoop(kinds[i]);
            for (int i = 0; i < 5; i++) HornClip(i);
            SkidLoop();
            Thud();
        }

        private static System.Random Seeded(string key)
        {
            int h = 0;
            for (int i = 0; i < key.Length; i++) h = h * 31 + key[i];
            return new System.Random(h & 0x7fffffff);
        }

        private static float Noise(System.Random rng)
        {
            return (float)rng.NextDouble() * 2f - 1f;
        }

        private static float Saw(float freq, float t)
        {
            float p = (t * freq) % 1f;
            return 2f * p - 1f;
        }

        /// <summary>1.0s seamless engine loop. Pitch at play time via AudioSource.pitch.</summary>
        public static AudioClip EngineLoop(string kind)
        {
            var rng = Seeded("eng_" + kind);
            float lp = 0f;
            return ProcAudio.Get("veh_eng_" + kind, 1f, (t, d) =>
            {
                float v;
                switch (kind)
                {
                    case "v8":
                        v = Saw(55f, t) * 0.55f + Saw(110f, t) * 0.28f + Saw(165f, t) * 0.14f + Noise(rng) * 0.08f;
                        break;
                    case "diesel":
                        float sq = Mathf.Sin(2f * Mathf.PI * 45f * t) > 0f ? 1f : -1f;
                        float clatter = 0.7f + 0.3f * Mathf.Sin(2f * Mathf.PI * 23f * t);
                        v = sq * 0.5f * clatter + Saw(90f, t) * 0.2f + Noise(rng) * 0.1f;
                        break;
                    case "bike":
                        v = Saw(110f, t) * 0.5f + Saw(220f, t) * 0.25f + Noise(rng) * 0.06f;
                        break;
                    case "electric":
                        v = Mathf.Sin(2f * Mathf.PI * 220f * t) * 0.45f
                          + Mathf.Sin(2f * Mathf.PI * 440f * t) * 0.22f
                          + Mathf.Sin(2f * Mathf.PI * 880f * t) * 0.1f;
                        break;
                    case "heli":
                        float gate = 0.35f + 0.65f * Mathf.Pow(0.5f + 0.5f * Mathf.Sin(2f * Mathf.PI * 13f * t), 2f);
                        v = gate * (Noise(rng) * 0.5f + Mathf.Sin(2f * Mathf.PI * 50f * t) * 0.3f);
                        break;
                    case "boat":
                        lp = lp * 0.92f + Noise(rng) * 0.08f;
                        v = Saw(65f, t) * 0.45f + lp * 2.2f;
                        break;
                    case "jet":
                        float swell = 0.6f + 0.4f * Mathf.Sin(2f * Mathf.PI * 2f * t);
                        lp = lp * 0.96f + Noise(rng) * 0.04f;
                        v = (lp * 3f + Mathf.Sin(2f * Mathf.PI * 1200f * t) * 0.06f) * swell;
                        break;
                    default:
                        v = Mathf.Sin(2f * Mathf.PI * 80f * t) * 0.3f;
                        break;
                }
                return v * 0.5f;
            });
        }

        /// <summary>0.7s two-tone horn by style index.</summary>
        public static AudioClip HornClip(int style)
        {
            float f1 = 392f, f2 = 494f;
            switch (style)
            {
                case HornTruck: f1 = 233f; f2 = 311f; break;
                case HornBike: f1 = 660f; f2 = 660f; break;
                case HornTank: f1 = 147f; f2 = 196f; break;
                case HornBoat: f1 = 311f; f2 = 415f; break;
            }
            float a = f1, b = f2;
            return ProcAudio.Get("veh_horn_" + style, 0.7f, (t, d) =>
            {
                float env = Mathf.Clamp01(t / 0.03f) * Mathf.Clamp01((d - t) / 0.15f);
                return (Mathf.Sin(2f * Mathf.PI * a * t) * 0.4f
                      + Mathf.Sin(2f * Mathf.PI * b * t) * 0.4f) * env * 0.6f;
            });
        }

        /// <summary>0.8s loopable tire skid.</summary>
        public static AudioClip SkidLoop()
        {
            var rng = Seeded("skid");
            float lp = 0f;
            return ProcAudio.Get("veh_skid", 0.8f, (t, d) =>
            {
                lp = lp * 0.86f + Noise(rng) * 0.14f;
                return lp * 2.4f;
            });
        }

        /// <summary>0.3s collision thud.</summary>
        public static AudioClip Thud()
        {
            var rng = Seeded("thud");
            return ProcAudio.Get("veh_thud", 0.3f, (t, d) =>
            {
                float f = 90f - 55f * (t / d);
                float env = Mathf.Exp(-t * 14f);
                return (Mathf.Sin(2f * Mathf.PI * f * t) * 0.7f + Noise(rng) * 0.25f) * env * 0.7f;
            });
        }

        /// <summary>Engine-loop kind per vehicle type (ports engine_kind()).</summary>
        public static string EngineKindFor(VehicleType t)
        {
            switch (t)
            {
                case VehicleType.Sedan:
                case VehicleType.SUV:
                case VehicleType.Pickup:
                case VehicleType.SportsCar:
                case VehicleType.Jeep:
                    return "v8";
                case VehicleType.CargoTruck:
                case VehicleType.ArmoredSUV:
                case VehicleType.Tank:
                    return "diesel";
                case VehicleType.Motorcycle:
                case VehicleType.ATV:
                    return "bike";
                case VehicleType.HoverBike:
                    return "electric";
                case VehicleType.Helicopter:
                    return "heli";
                case VehicleType.Boat:
                    return "boat";
                case VehicleType.B2Bomber:
                    return "jet";
                default:
                    return ""; // Skateboard: silent (player-pushed)
            }
        }

        /// <summary>Horn style index per vehicle type (ports horn_kind()).</summary>
        public static int HornIndexFor(VehicleType t)
        {
            switch (t)
            {
                case VehicleType.CargoTruck:
                case VehicleType.Tank:
                case VehicleType.ArmoredSUV:
                    return HornTruck; // tank matches "truck" first, like the GDScript match
                case VehicleType.Motorcycle:
                case VehicleType.ATV:
                case VehicleType.HoverBike:
                case VehicleType.Skateboard:
                    return HornBike;
                case VehicleType.Boat:
                    return HornBoat;
                default:
                    return HornCar;
            }
        }
    }
}
