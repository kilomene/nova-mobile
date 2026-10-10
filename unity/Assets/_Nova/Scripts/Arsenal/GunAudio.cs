using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Arsenal
{
    /// <summary>
    /// Procedural weapon audio, ported from Godot gun_audio.gd.
    /// One base sound per weapon class (dur/crack/body/bdecay/thump) modified by the
    /// gun's "sound" multipliers and its silent flag; per-gun clips are synthesized
    /// once at startup via ProcAudio and cached. Never synthesize per-shot at runtime.
    /// Brightness (crack) and duration derive from the gun class; play-time pitch
    /// comes from PitchFor(gunId).
    /// </summary>
    public static class GunAudio
    {
        private struct ClassSound
        {
            public float dur, crack, body, bdecay, thump;
        }

        private static readonly Dictionary<GunClass, ClassSound> ClassSounds =
            new Dictionary<GunClass, ClassSound>
            {
                { GunClass.AssaultRifle, new ClassSound { dur = 0.32f, crack = 900f,  body = 160f, bdecay = 22f, thump = 75f } },
                { GunClass.SMG,          new ClassSound { dur = 0.26f, crack = 1100f, body = 200f, bdecay = 26f, thump = 85f } },
                { GunClass.LMG,          new ClassSound { dur = 0.38f, crack = 750f,  body = 130f, bdecay = 18f, thump = 65f } },
                { GunClass.Sniper,       new ClassSound { dur = 0.55f, crack = 550f,  body = 100f, bdecay = 12f, thump = 55f } },
                { GunClass.Marksman,     new ClassSound { dur = 0.40f, crack = 700f,  body = 130f, bdecay = 16f, thump = 65f } },
                { GunClass.Shotgun,      new ClassSound { dur = 0.45f, crack = 500f,  body = 110f, bdecay = 14f, thump = 60f } },
                { GunClass.Pistol,       new ClassSound { dur = 0.24f, crack = 1300f, body = 230f, bdecay = 30f, thump = 95f } },
                { GunClass.Launcher,     new ClassSound { dur = 0.70f, crack = 300f,  body = 80f,  bdecay = 8f,  thump = 45f } },
                { GunClass.Melee,        new ClassSound { dur = 0.22f, crack = 2500f, body = 400f, bdecay = 40f, thump = 0f } },
            };

        /// <summary>Deterministic FNV-1a hash (stable across sessions, unlike string.GetHashCode).</summary>
        private static int StableHash(string s)
        {
            unchecked
            {
                uint h = 2166136261u;
                for (int i = 0; i < s.Length; i++)
                {
                    h ^= s[i];
                    h *= 16777619u;
                }
                return (int)(h % 900000u) + 7;
            }
        }

        /// <summary>Play-time pitch multiplier for this gun (from its pitch stat).</summary>
        public static float PitchFor(string gunId)
        {
            return GunData.GetExtended(gunId).Pitch;
        }

        /// <summary>Per-gun fire sound, lazily synthesized + cached per gun id.</summary>
        public static AudioClip ShotClip(string gunId)
        {
            GunSpec g = GunData.Get(gunId);
            if (g.Id == null) g = GunData.Get("m5");
            GunExtended e = GunData.GetExtended(g.Id);
            ClassSound p = ClassSounds[g.Class];
            float dur = p.dur * e.DurMult;
            float crack = p.crack * e.CrackMult;
            float body = p.body * e.BodyMult;
            float bdecay = p.bdecay * e.DecayMult;
            float thump = p.thump * e.ThumpMult;
            int seed = StableHash(gunId);
            const float TAU = Mathf.PI * 2f;

            if (e.Whoosh)
            {
                // Rocket launch: long band-swept whoosh instead of a gunshot crack.
                float wdur = 0.9f * e.DurMult;
                var wrng = new System.Random(seed);
                float wlp = 0f;
                return ProcAudio.Get("shot_" + g.Id, wdur, (t, d) =>
                {
                    float n = (float)wrng.NextDouble() * 2f - 1f;
                    wlp = wlp * 0.985f + n * 0.015f;
                    return wlp * Mathf.Sin(t * Mathf.PI / d) * 2.2f;
                });
            }
            if (e.Silent)
            {
                // Suppressed: heavy lowpass on the crack, shorter tail, soft thump.
                float mdur = dur * 0.8f;
                var mrng = new System.Random(seed);
                float lp = 0f, lp2 = 0f;
                return ProcAudio.Get("shot_" + g.Id, mdur, (t, d) =>
                {
                    float n = (float)mrng.NextDouble() * 2f - 1f;
                    lp = lp * 0.90f + n * 0.10f;
                    lp2 = lp2 * 0.97f + lp * 0.03f;
                    float v = lp2 * Mathf.Exp(-t * crack * 0.5f) * 1.1f;
                    v += Mathf.Sin(t * body * TAU) * Mathf.Exp(-t * bdecay * 1.4f) * 0.35f;
                    if (thump > 0f)
                        v += Mathf.Sin(t * thump * 0.6f * TAU) * Mathf.Exp(-t * 22f) * 0.4f;
                    return v;
                });
            }
            var rng = new System.Random(seed);
            float llp = 0f;
            bool whooshMelee = g.Class == GunClass.Melee;
            return ProcAudio.Get("shot_" + g.Id, dur, (t, d) =>
            {
                float n = (float)rng.NextDouble() * 2f - 1f;
                float v;
                if (whooshMelee)
                {
                    // Melee swing: band-swept noise swell.
                    llp = llp * 0.985f + n * 0.015f;
                    v = llp * Mathf.Sin(t * Mathf.PI / d) * 2.2f;
                }
                else
                {
                    v = n * Mathf.Exp(-t * crack) * 0.85f;
                    v += Mathf.Sin(t * body * TAU) * Mathf.Exp(-t * bdecay) * 0.55f;
                    if (thump > 0f)
                        v += Mathf.Sin(t * thump * TAU) * Mathf.Exp(-t * 18f) * 0.6f;
                }
                return v;
            });
        }

        /// <summary>Reload: two metallic clicks 0.12 s apart. Shared by all guns.</summary>
        public static AudioClip ReloadClip(string gunId)
        {
            const float TAU = Mathf.PI * 2f;
            var rng = new System.Random(4242);
            return ProcAudio.Get("reload_shared", 0.35f, (t, d) =>
            {
                float v = 0f;
                float[] clicks = { 0f, 0.14f };
                for (int k = 0; k < 2; k++)
                {
                    float dt = t - clicks[k];
                    if (dt > 0f && dt < 0.05f)
                    {
                        float n = (float)rng.NextDouble() * 2f - 1f;
                        v += n * Mathf.Exp(-dt * 160f) * 0.7f;
                        v += Mathf.Sin(dt * 2400f * TAU) * Mathf.Exp(-dt * 200f) * 0.3f;
                    }
                }
                return v;
            });
        }

        /// <summary>Dry-fire click (empty mag). Shared.</summary>
        public static AudioClip DryClip()
        {
            const float TAU = Mathf.PI * 2f;
            var rng = new System.Random(777);
            return ProcAudio.Get("dry_shared", 0.09f, (t, d) =>
            {
                float n = (float)rng.NextDouble() * 2f - 1f;
                float v = n * Mathf.Exp(-t * 220f) * 0.5f;
                v += Mathf.Sin(t * 1800f * TAU) * Mathf.Exp(-t * 260f) * 0.25f;
                return v;
            });
        }

        /// <summary>Explosion for rockets/grenades. Shared.</summary>
        public static AudioClip ExplosionClip()
        {
            const float TAU = Mathf.PI * 2f;
            var rng = new System.Random(9001);
            float lp = 0f;
            return ProcAudio.Get("explosion_shared", 1.1f, (t, d) =>
            {
                float n = (float)rng.NextDouble() * 2f - 1f;
                lp = lp * 0.92f + n * 0.08f;
                float v = lp * Mathf.Exp(-t * 5f) * 1.4f + n * Mathf.Exp(-t * 30f) * 0.5f;
                v += Mathf.Sin(t * 48f * TAU) * Mathf.Exp(-t * 7f) * 0.8f;
                return v;
            });
        }

        /// <summary>Pre-generate all per-gun clips at startup (call from a boot step).</summary>
        public static void Prewarm()
        {
            for (int i = 0; i < GunData.Guns.Length; i++)
            {
                ShotClip(GunData.Guns[i].Id);
                ReloadClip(GunData.Guns[i].Id);
            }
            DryClip();
            ExplosionClip();
        }
    }
}
