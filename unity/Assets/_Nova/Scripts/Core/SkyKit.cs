using UnityEngine;

namespace NovaMobile.Core
{
    /// <summary>
    /// One-call sky + atmosphere setup: gradient skybox (Nova/Sky), optional
    /// distance fog, and ambient tuning. Used by the lobby and the world.
    /// </summary>
    public static class SkyKit
    {
        /// <summary>Golden-hour Lagos preset (matches the approved lobby look).</summary>
        public static void ApplyGoldenHour(Camera cam, Vector3 sunDir)
        {
            Apply(cam,
                new Color(0.30f, 0.46f, 0.72f),   // zenith
                new Color(0.98f, 0.80f, 0.58f),   // horizon
                new Color(0.30f, 0.27f, 0.24f),   // below horizon
                sunDir,
                new Color(1f, 0.86f, 0.62f),
                true, new Color(0.92f, 0.78f, 0.62f), 40f, 220f);
        }

        /// <summary>Bright midday preset for the BR world.</summary>
        public static void ApplyMidday(Camera cam, Vector3 sunDir)
        {
            Apply(cam,
                new Color(0.22f, 0.44f, 0.78f),
                new Color(0.74f, 0.84f, 0.92f),
                new Color(0.35f, 0.34f, 0.30f),
                sunDir,
                new Color(1f, 0.96f, 0.88f),
                true, new Color(0.74f, 0.82f, 0.90f), 120f, 700f);
        }

        public static void Apply(Camera cam, Color top, Color horizon, Color bottom,
            Vector3 sunDir, Color sunColor, bool fog, Color fogColor,
            float fogNear, float fogFar)
        {
            var shader = Shader.Find("Nova/Sky");
            if (shader != null)
            {
                var mat = new Material(shader);
                mat.SetColor("_TopColor", top);
                mat.SetColor("_HorizonColor", horizon);
                mat.SetColor("_BottomColor", bottom);
                mat.SetVector("_SunDir", sunDir);
                mat.SetColor("_SunColor", sunColor);
                RenderSettings.skybox = mat;
            }
            if (cam != null) cam.clearFlags = CameraClearFlags.Skybox;

            RenderSettings.fog = fog;
            if (fog)
            {
                RenderSettings.fogMode = FogMode.Linear;
                RenderSettings.fogColor = fogColor;
                RenderSettings.fogStartDistance = fogNear;
                RenderSettings.fogEndDistance = fogFar;
            }
        }
    }
}
