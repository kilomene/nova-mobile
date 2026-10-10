using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// One-shot mythic FX, ported from the Godot KillFX / _burst / evolution_sting:
    /// theme-colored particle bursts, floating kill labels and milestone banners,
    /// reload &amp; draw flourishes, and the evolution sting audio.
    /// ParticleSystems and labels are pooled (mobile-first); bursts never allocate
    /// in the hot path. Init is called by MythicBoot; all play methods are no-ops
    /// until then.
    /// </summary>
    public static class MythicFx
    {
        private const int PoolSize = 6;
        private static readonly List<PoolItem> _pool = new List<PoolItem>();
        private static int _next;
        private static bool _ready;
        private static AudioSource _audio;

        private sealed class PoolItem : MonoBehaviour
        {
            public ParticleSystem Ps;
            public TextMesh Label;
            private float _t;
            private float _life;
            private float _rise;
            private bool _hasLabel;
            private Camera _cam;

            public void Fire(Vector3 pos, Color color, int count, float speed, float size, float life)
            {
                transform.position = pos;
                gameObject.SetActive(true);
                _hasLabel = false;
                Label.gameObject.SetActive(false);
                var main = Ps.main;
                main.startColor = color;
                main.startSpeed = new ParticleSystem.MinMaxCurve(speed * 0.5f, speed);
                main.startSize = new ParticleSystem.MinMaxCurve(size * 0.5f, size);
                main.startLifetime = life;
                _t = 0f;
                _life = life + 0.6f;
                _rise = 0f;
                Ps.Emit(count);
            }

            public void ShowLabel(string text, Color color, float charSize, float height, float life, float rise)
            {
                Label.gameObject.SetActive(true);
                Label.transform.localPosition = new Vector3(0f, height, 0f);
                Label.text = text;
                color.a = 1f;
                Label.color = color;
                Label.characterSize = charSize;
                _hasLabel = true;
                _rise = rise;
                if (life > _life) _life = life;
            }

            private void Update()
            {
                _t += Time.deltaTime;
                if (_hasLabel)
                {
                    if (_cam == null) _cam = Camera.main;
                    if (_cam != null) Label.transform.rotation = _cam.transform.rotation;
                    Label.transform.position += Vector3.up * _rise * Time.deltaTime;
                    Color c = Label.color;
                    c.a = Mathf.Clamp01(_life - _t);
                    Label.color = c;
                }
                if (_t >= _life)
                {
                    _hasLabel = false;
                    gameObject.SetActive(false);
                }
            }
        }

        public static void Init()
        {
            if (_ready) return;
            Shader psShader = Shader.Find("Particles/Standard Unlit");
            if (psShader == null)
            {
                Debug.LogError("[Mythics] Built-in particle shader missing; mythic FX disabled.");
                return;
            }
            var root = new GameObject("MythicFx");
            Object.DontDestroyOnLoad(root);
            var pmat = new Material(psShader);
            pmat.SetColor("_Color", Color.white);
            for (int i = 0; i < PoolSize; i++)
            {
                var go = new GameObject("MythicFxItem" + i);
                go.transform.SetParent(root.transform, false);
                var item = go.AddComponent<PoolItem>();
                var ps = go.AddComponent<ParticleSystem>();
                var main = ps.main;
                main.loop = false;
                main.playOnAwake = false;
                main.simulationSpace = ParticleSystemSimulationSpace.World;
                main.startLifetime = 0.9f;
                main.startSpeed = 5f;
                main.startSize = 0.1f;
                main.gravityModifier = 0.5f;
                main.maxParticles = 80;
                var shape = ps.shape;
                shape.enabled = true;
                shape.shapeType = ParticleSystemShapeType.Sphere;
                shape.radius = 0.15f;
                var em = ps.emission;
                em.enabled = true;
                em.rateOverTime = 0f;
                var rend = ps.GetComponent<ParticleSystemRenderer>();
                rend.sharedMaterial = pmat;
                var lgo = new GameObject("Label");
                lgo.transform.SetParent(go.transform, false);
                var tm = lgo.AddComponent<TextMesh>();
                tm.fontSize = 64;
                tm.anchor = TextAnchor.MiddleCenter;
                tm.alignment = TextAlignment.Center;
                lgo.SetActive(false);
                item.Ps = ps;
                item.Label = tm;
                go.SetActive(false);
                _pool.Add(item);
            }
            var ago = new GameObject("MythicAudio");
            ago.transform.SetParent(root.transform, false);
            _audio = ago.AddComponent<AudioSource>();
            _audio.playOnAwake = false;
            _ready = true;
        }

        private static PoolItem Next()
        {
            PoolItem item = _pool[_next];
            _next = (_next + 1) % PoolSize;
            return item;
        }

        /// <summary>Theme reload flourish: energy puff at the gun (14 particles).</summary>
        public static void PlayReloadFlourish(GameObject gunRoot, string themeId)
        {
            if (!_ready || gunRoot == null) return;
            MythicTheme t = MythicData.ThemeById(themeId);
            if (t.Id == null) return;
            Vector3 pos = gunRoot.transform.position + Vector3.up * 0.15f;
            Next().Fire(pos, t.Secondary, 14, 2.5f, 0.09f, 0.5f);
        }

        /// <summary>Theme draw flourish: brighter flash when the mythic is drawn.</summary>
        public static void PlayDrawFlourish(GameObject gunRoot, string themeId)
        {
            if (!_ready || gunRoot == null) return;
            MythicTheme t = MythicData.ThemeById(themeId);
            if (t.Id == null) return;
            Vector3 pos = gunRoot.transform.position + Vector3.up * 0.15f;
            Next().Fire(pos, t.Secondary, 22, 3.5f, 0.12f, 0.6f);
        }

        /// <summary>
        /// Mythic kill FX: theme-colored burst + floating kill counter at the
        /// victim position; milestone = "" or e.g. "AWAKENED" (big banner instead).
        /// </summary>
        public static void PlayKillFx(Vector3 pos, string themeId, int killNum, string milestone)
        {
            if (!_ready) return;
            MythicTheme t = MythicData.ThemeById(themeId);
            if (t.Id == null) return;
            bool big = !string.IsNullOrEmpty(milestone);
            PoolItem item = Next();
            item.Fire(pos, t.Primary, big ? 60 : 34, big ? 8f : 5.5f, big ? 0.16f : 0.11f, 0.9f);
            string text = big
                ? t.Name.ToUpperInvariant() + "\n" + milestone
                : "KILL #" + killNum;
            item.ShowLabel(text, t.Secondary, big ? 0.018f : 0.012f,
                big ? 1.6f : 1.2f, big ? 2.4f : 1.5f, 1.6f);
        }

        /// <summary>Rising shimmer sting for evolution milestones. Synthesized once, cached.</summary>
        public static AudioClip EvolutionSting()
        {
            return ProcAudio.Get("mythic_evo_sting", 0.6f, (t, d) =>
            {
                float phase = 2f * Mathf.PI * (500f * t + 700f * t * t / d);
                float env = Mathf.Exp(-3f * t);
                float s = Mathf.Sin(phase) * env + 0.4f * Mathf.Sin(phase * 2f) * env;
                return s * 0.9f;
            });
        }

        public static void PlaySting()
        {
            if (!_ready || _audio == null) return;
            _audio.PlayOneShot(EvolutionSting());
        }
    }
}
