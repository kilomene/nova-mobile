using System;
using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Core
{
    /// <summary>
    /// Procedural PCM audio synthesis. All clips are generated once at startup and cached —
    /// never synthesize inside gameplay. Sample rate 22050 keeps memory small on mobile.
    /// </summary>
    public static class ProcAudio
    {
        public const int SampleRate = 22050;
        private static readonly Dictionary<string, AudioClip> Cache = new Dictionary<string, AudioClip>();
        private static System.Random _rng = new System.Random(12345);

        public delegate float SampleFunc(float t, float duration);

        /// <summary>Generate (or fetch cached) a clip from a per-sample function.</summary>
        public static AudioClip Get(string key, float duration, SampleFunc fn)
        {
            if (Cache.TryGetValue(key, out AudioClip clip)) return clip;
            int n = Mathf.Max(1, Mathf.RoundToInt(duration * SampleRate));
            float[] data = new float[n];
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / SampleRate;
                data[i] = Mathf.Clamp(fn(t, duration), -1f, 1f);
            }
            clip = AudioClip.Create(key, n, 1, SampleRate, false);
            clip.SetData(data, 0);
            Cache[key] = clip;
            return clip;
        }

        // ---- building blocks ----

        public static float Sine(float freq, float t) { return Mathf.Sin(2f * Mathf.PI * freq * t); }

        public static float Noise()
        {
            return (float)_rng.NextDouble() * 2f - 1f;
        }

        /// <summary>Exponential decay envelope: 1 at t=0, ~0 at t=duration.</summary>
        public static float Decay(float t, float duration, float power = 3f)
        {
            float x = Mathf.Clamp01(t / duration);
            return Mathf.Pow(1f - x, power);
        }

        /// <summary>Gunshot: noise burst + low thump, pitch varies per gun via brightness.</summary>
        public static AudioClip Gunshot(string key, float brightness, float bodySeconds = 0.18f)
        {
            return Get("shot_" + key, bodySeconds, (t, d) =>
            {
                float n = Noise() * Decay(t, d, 4f);
                float thump = Sine(70f + brightness * 60f, t) * Decay(t, d, 6f) * 0.8f;
                float crack = Noise() * Decay(t, Mathf.Min(d, 0.03f), 2f) * brightness;
                return n * 0.5f + thump + crack * 0.6f;
            });
        }

        /// <summary>Engine loop: repeating firing pulses, pitch driven by rpm01 at play time via AudioSource.pitch.</summary>
        public static AudioClip EngineLoop(string key, float cylinders, float baseHz)
        {
            return Get("eng_" + key, 1f, (t, d) =>
            {
                float pulse = Mathf.Sin(2f * Mathf.PI * baseHz * cylinders * t);
                pulse = Mathf.Sign(pulse) * Mathf.Pow(Mathf.Abs(pulse), 0.7f);
                float rumble = Noise() * 0.25f;
                return (pulse * 0.6f + rumble) * 0.5f;
            });
        }

        /// <summary>Simple horn: two detuned square-ish tones.</summary>
        public static AudioClip Horn(string key, float freqA, float freqB, float seconds = 0.7f)
        {
            return Get("horn_" + key, seconds, (t, d) =>
            {
                float env = Mathf.Clamp01(t / 0.03f) * Mathf.Clamp01((d - t) / 0.08f);
                float a = Mathf.Sign(Sine(freqA, t)) * 0.35f;
                float b = Mathf.Sign(Sine(freqB, t)) * 0.35f;
                return (a + b) * env;
            });
        }

        /// <summary>UI click / pickup blip.</summary>
        public static AudioClip Blip(string key, float freq, float seconds = 0.08f)
        {
            return Get("blip_" + key, seconds, (t, d) => Sine(freq, t) * Decay(t, d, 2f));
        }

        /// <summary>Explosion: deep noise boom with sub thump.</summary>
        public static AudioClip Explosion(string key, float seconds = 1.2f)
        {
            return Get("expl_" + key, seconds, (t, d) =>
            {
                float n = Noise() * Decay(t, d, 2.5f);
                float sub = Sine(45f, t) * Decay(t, d, 3f);
                return (n * 0.7f + sub * 0.9f) * 0.8f;
            });
        }
    }
}
