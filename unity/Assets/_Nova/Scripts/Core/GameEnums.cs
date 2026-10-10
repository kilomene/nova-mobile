using UnityEngine;

namespace NovaMobile.Core
{
    /// <summary>Shared enums used across systems.</summary>
    public enum TeamId { None = 0, Squad0 = 1 }

    public enum DamageCause { Bullet, Headshot, Explosion, Zone, Melee, Vehicle }

    /// <summary>Attach a pooled one-shot audio player to a GameObject.</summary>
    [RequireComponent(typeof(AudioSource))]
    public class OneShotAudio : MonoBehaviour
    {
        private AudioSource _src;

        private void Awake()
        {
            _src = GetComponent<AudioSource>();
            _src.playOnAwake = false;
            _src.spatialBlend = 1f;
        }

        public void Play(AudioClip clip, float volume = 1f, float pitch = 1f)
        {
            _src.pitch = pitch;
            _src.PlayOneShot(clip, volume);
        }
    }

    /// <summary>Shared materials cache (unlit vertex-ish simple materials for procedural meshes).</summary>
    public static class NovaMaterials
    {
        private static Material _opaque;
        private static Material _transparent;
        private static Material _emissive;

        public static Material Opaque
        {
            get
            {
                if (_opaque == null)
                {
                    _opaque = new Material(Shader.Find("Standard"));
                    _opaque.color = Color.white;
                }
                return _opaque;
            }
        }

        public static Material Transparent
        {
            get
            {
                if (_transparent == null)
                {
                    _transparent = new Material(Shader.Find("Standard"));
                    _transparent.SetFloat("_Mode", 3f);
                    _transparent.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
                    _transparent.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                    _transparent.SetInt("_ZWrite", 0);
                    _transparent.DisableKeyword("_ALPHATEST_ON");
                    _transparent.EnableKeyword("_ALPHABLEND_ON");
                    _transparent.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                    _transparent.renderQueue = 3000;
                    _transparent.color = new Color(1f, 1f, 1f, 0.5f);
                }
                return _transparent;
            }
        }

        public static Material Emissive(Color c)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = c;
            m.SetColor("_EmissionColor", c);
            m.EnableKeyword("_EMISSION");
            return m;
        }
    }
}
