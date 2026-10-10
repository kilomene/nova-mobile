using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>
    /// Bright Lagos daytime lighting: one directional sun + flat ambient.
    /// Created by WorldBuilder; feeds the ambient term to the Nova/VertexLit shader
    /// via the _NovaAmbient global (kept in sync with RenderSettings).
    /// </summary>
    [ExecuteInEditMode]
    public class DayLight : MonoBehaviour
    {
        [Tooltip("Sun elevation in degrees.")]
        public float SunElevation = 62f;
        [Tooltip("Sun azimuth in degrees.")]
        public float SunAzimuth = 135f;
        public float SunIntensity = 1.25f;
        public Color SunColor = new Color(1f, 0.97f, 0.90f);
        public Color AmbientColor = new Color(0.62f, 0.68f, 0.74f);
        public Color SkyColor = new Color(0.55f, 0.75f, 0.95f);

        private Light _sun;

        private void Awake()
        {
            Setup();
        }

        private void OnValidate()
        {
            Setup();
        }

        public void Setup()
        {
            _sun = GetComponent<Light>();
            if (_sun == null) _sun = gameObject.AddComponent<Light>();
            _sun.type = LightType.Directional;
            _sun.color = SunColor;
            _sun.intensity = SunIntensity;
            _sun.shadows = LightShadows.Soft;
            _sun.shadowResolution = UnityEngine.Rendering.LightShadowResolution.Medium;
            _sun.shadowBias = 0.05f;
            // Mobile-friendly: shadows only near the action.
            QualitySettings.shadowDistance = 120f;
            transform.rotation = Quaternion.Euler(SunElevation, SunAzimuth, 0f);

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = AmbientColor;
            RenderSettings.ambientIntensity = 1f;
            Camera cam = Camera.main;
            if (cam != null)
            {
                cam.clearFlags = CameraClearFlags.SolidColor;
                cam.backgroundColor = SkyColor;
            }
            Shader.SetGlobalColor("_NovaAmbient", AmbientColor);
        }
    }
}
