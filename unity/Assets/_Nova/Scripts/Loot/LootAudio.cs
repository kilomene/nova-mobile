using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Loot
{
    /// <summary>
    /// Procedural loot audio: pickup blips pitched by rarity, container opens,
    /// crate opens (brighter per tier), ping chirps, death-box thuds.
    /// All clips synthesized once at startup via Core.ProcAudio and cached —
    /// never synthesized at runtime. Ported from loot_audio.gd.
    /// </summary>
    public static class LootAudio
    {
        /// <summary>Play a pre-generated clip at a world position (3D one-shot).</summary>
        public static void PlayAt(AudioClip clip, Vector3 pos, float volume = 1f)
        {
            if (clip != null) AudioSource.PlayClipAtPoint(clip, pos, volume);
        }

        /// <summary>Pickup blip: two-tone chime, pitch rises with rarity.</summary>
        public static AudioClip PickupClip(Rarity rarity)
        {
            int tier = Mathf.Clamp((int)rarity, 0, 6);
            float baseHz = 520f + tier * 90f;
            return ProcAudio.Get("loot_pickup_" + tier, 0.22f, (t, d) =>
            {
                float v = ProcAudio.Sine(baseHz, t) * Mathf.Exp(-t * 18f) * 0.5f;
                if (t > 0.09f)
                {
                    float t2 = t - 0.09f;
                    v += ProcAudio.Sine(baseHz * 1.335f, t2) * Mathf.Exp(-t2 * 16f) * 0.45f;
                }
                return v;
            });
        }

        /// <summary>Container open: wooden creak + latch click.</summary>
        public static AudioClip OpenClip()
        {
            return ProcAudio.Get("loot_open", 0.35f, (t, d) =>
            {
                // Low-passed noise creak; lp state carried through closure.
                // (ProcAudio calls samples in order, so a closure filter is valid.)
                float v = CreakLp(t, d);
                if (t > 0.22f)
                {
                    float t2 = t - 0.22f;
                    v += ProcAudio.Sine(1900f, t2) * Mathf.Exp(-t2 * 60f) * 0.35f;
                }
                return v;
            });
        }

        private static float _creakLp;
        private static float _creakLastT = -1f;

        private static float CreakLp(float t, float d)
        {
            if (t < _creakLastT) _creakLp = 0f; // new generation pass
            _creakLastT = t;
            float noise = ProcAudio.Noise();
            _creakLp = _creakLp * 0.93f + noise * 0.07f;
            return _creakLp * Mathf.Exp(-t * 9f) * 0.9f;
        }

        /// <summary>Crate open: heavier thunk + rising shimmer, brighter for higher tiers.</summary>
        public static AudioClip CrateClip(int crateTier)
        {
            int tier = Mathf.Clamp(crateTier, 0, 2);
            float shimmer = 1200f + tier * 700f;
            return ProcAudio.Get("loot_crate_" + tier, 0.6f, (t, d) =>
            {
                float v = CrateLp(t, d) * 1.0f;
                v += ProcAudio.Sine(90f, t) * Mathf.Exp(-t * 14f) * 0.5f;
                v += ProcAudio.Sine(shimmer, t) * Mathf.Exp(-t * 5f) * (0.10f + 0.12f * tier);
                return v * 0.8f;
            });
        }

        private static float _crateLp;
        private static float _crateLastT = -1f;

        private static float CrateLp(float t, float d)
        {
            if (t < _crateLastT) _crateLp = 0f;
            _crateLastT = t;
            float noise = ProcAudio.Noise();
            _crateLp = _crateLp * 0.90f + noise * 0.10f;
            return _crateLp * Mathf.Exp(-t * 7f);
        }

        /// <summary>Ping chirp: short double-blip.</summary>
        public static AudioClip PingClip()
        {
            return ProcAudio.Get("loot_ping", 0.18f, (t, d) =>
            {
                float f = t < 0.07f ? 980f : 1320f;
                return ProcAudio.Sine(f, t) * Mathf.Exp(-t * 22f) * 0.5f;
            });
        }

        /// <summary>Death-box thud: low knock.</summary>
        public static AudioClip ThudClip()
        {
            return ProcAudio.Get("loot_thud", 0.25f, (t, d) =>
            {
                float v = ProcAudio.Sine(110f, t) * Mathf.Exp(-t * 20f) * 0.7f;
                v += ProcAudio.Sine(65f, t) * Mathf.Exp(-t * 16f) * 0.4f;
                return v;
            });
        }
    }
}
