using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace NovaMobile.Player
{
    /// <summary>
    /// CODM-style controller settings store, shared by FPSController, TouchHUD
    /// and SettingsMenu. Ported from control_settings.gd.
    /// Persisted as JSON in Application.persistentDataPath (never PlayerPrefs).
    /// Sensitivity model: multipliers applied on top of the base look speeds.
    /// </summary>
    public static class ControlSettings
    {
        public const string FileName = "nova_controls.json";

        // Camera / ADS / optic sensitivity multipliers.
        public static float CamSens = 1.0f;
        public static float AdsSens = 0.6f;
        public static float Zoom4Sens = 0.45f;
        public static float Zoom8Sens = 0.35f;
        public static bool InvertY = false;
        public static bool GyroEnabled = false;
        public static float GyroSens = 1.0f;
        public static bool AimAssist = true;
        public static float AssistStrength = 0.5f;
        // "advanced" (manual fire button) | "simple" (auto-fire on target).
        public static string FireMode = "advanced";
        public static bool Haptics = true;
        public static float HudOpacity = 1.0f;
        public static bool TiltSteering = false;
        // Graphics quality preset: 0 Low, 1 Balanced, 2 High, 3 Ultra.
        public static int QualityLevel = 1;

        [Serializable]
        public struct LayoutEntry
        {
            public string id;
            public float x; // center, screen fraction (x from left)
            public float y; // center, screen fraction (y from top)
            public float d; // diameter, fraction of screen height
        }

        [Serializable]
        private class SettingsData
        {
            public float camSens = 1.0f;
            public float adsSens = 0.6f;
            public float zoom4Sens = 0.45f;
            public float zoom8Sens = 0.35f;
            public bool invertY = false;
            public bool gyroEnabled = false;
            public float gyroSens = 1.0f;
            public bool aimAssist = true;
            public float assistStrength = 0.5f;
            public string fireMode = "advanced";
            public bool haptics = true;
            public float hudOpacity = 1.0f;
            public bool tiltSteering = false;
            public int qualityLevel = 1;
            public List<LayoutEntry> layout = new List<LayoutEntry>();
        }

        // Custom HUD layout overrides: button id -> entry. Empty = CODM default.
        private static readonly Dictionary<string, LayoutEntry> _layout =
            new Dictionary<string, LayoutEntry>();

        public static void ResetDefaults()
        {
            CamSens = 1.0f; AdsSens = 0.6f; Zoom4Sens = 0.45f; Zoom8Sens = 0.35f;
            InvertY = false; GyroEnabled = false; GyroSens = 1.0f;
            AimAssist = true; AssistStrength = 0.5f;
            FireMode = "advanced"; Haptics = true; HudOpacity = 1.0f;
            TiltSteering = false; QualityLevel = 1;
            // NOTE: layout intentionally NOT cleared here; use ClearLayout().
        }

        public static void ClearLayout() { _layout.Clear(); }

        public static void SetLayout(string id, float xFrac, float yFrac, float dFrac)
        {
            _layout[id] = new LayoutEntry { id = id, x = xFrac, y = yFrac, d = dFrac };
        }

        public static bool TryGetLayout(string id, out LayoutEntry entry)
        {
            return _layout.TryGetValue(id, out entry);
        }

        public static void SetValue(string key, float v)
        {
            switch (key)
            {
                case "cam_sens": CamSens = Mathf.Clamp(v, 0.2f, 3.0f); break;
                case "ads_sens": AdsSens = Mathf.Clamp(v, 0.1f, 2.0f); break;
                case "zoom4_sens": Zoom4Sens = Mathf.Clamp(v, 0.1f, 1.5f); break;
                case "zoom8_sens": Zoom8Sens = Mathf.Clamp(v, 0.1f, 1.5f); break;
                case "gyro_sens": GyroSens = Mathf.Clamp(v, 0.2f, 3.0f); break;
                case "assist_strength": AssistStrength = Mathf.Clamp(v, 0.0f, 1.0f); break;
                case "hud_opacity": HudOpacity = Mathf.Clamp(v, 0.3f, 1.0f); break;
            }
        }

        public static void SetValue(string key, bool v)
        {
            switch (key)
            {
                case "invert_y": InvertY = v; break;
                case "gyro_enabled": GyroEnabled = v; break;
                case "aim_assist": AimAssist = v; break;
                case "haptics": Haptics = v; break;
                case "tilt_steering": TiltSteering = v; break;
            }
        }

        public static void SetFireMode(string mode)
        {
            FireMode = (mode == "simple") ? "simple" : "advanced";
        }

        public static void SetQuality(int level)
        {
            QualityLevel = Mathf.Clamp(level, 0, 3);
        }

        private static string Path()
        {
            return System.IO.Path.Combine(Application.persistentDataPath, FileName);
        }

        public static void SaveAll()
        {
            try
            {
                var data = new SettingsData
                {
                    camSens = CamSens, adsSens = AdsSens, zoom4Sens = Zoom4Sens,
                    zoom8Sens = Zoom8Sens, invertY = InvertY,
                    gyroEnabled = GyroEnabled, gyroSens = GyroSens,
                    aimAssist = AimAssist, assistStrength = AssistStrength,
                    fireMode = FireMode, haptics = Haptics, hudOpacity = HudOpacity,
                    tiltSteering = TiltSteering, qualityLevel = QualityLevel,
                };
                foreach (var kv in _layout)
                    data.layout.Add(kv.Value);
                File.WriteAllText(Path(), JsonUtility.ToJson(data, true));
            }
            catch (Exception e)
            {
                Debug.LogWarning("[ControlSettings] Save failed: " + e.Message);
            }
        }

        public static void LoadAll()
        {
            ResetDefaults();
            _layout.Clear();
            try
            {
                string p = Path();
                if (!File.Exists(p)) return;
                var data = JsonUtility.FromJson<SettingsData>(File.ReadAllText(p));
                if (data == null) return;
                SetValue("cam_sens", data.camSens);
                SetValue("ads_sens", data.adsSens);
                SetValue("zoom4_sens", data.zoom4Sens);
                SetValue("zoom8_sens", data.zoom8Sens);
                SetValue("invert_y", data.invertY);
                SetValue("gyro_enabled", data.gyroEnabled);
                SetValue("gyro_sens", data.gyroSens);
                SetValue("aim_assist", data.aimAssist);
                SetValue("assist_strength", data.assistStrength);
                SetFireMode(data.fireMode);
                SetValue("haptics", data.haptics);
                SetValue("hud_opacity", data.hudOpacity);
                SetValue("tilt_steering", data.tiltSteering);
                SetQuality(data.qualityLevel);
                if (data.layout != null)
                {
                    foreach (var e in data.layout)
                    {
                        if (!string.IsNullOrEmpty(e.id))
                            _layout[e.id] = e;
                    }
                }
            }
            catch (Exception e)
            {
                Debug.LogWarning("[ControlSettings] Load failed: " + e.Message);
            }
        }
    }
}
