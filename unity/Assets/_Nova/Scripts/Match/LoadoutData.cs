using System;
using System.IO;
using UnityEngine;

namespace NovaMobile.Match
{
    /// <summary>
    /// Lobby loadout, persisted to JSON in persistentDataPath (never PlayerPrefs).
    /// Character + class + primary weapon/skin/attachments + secondary.
    /// Ported from main.gd's _char_idx / _class_id / _gs_gun / _gs_skin / _gs_attach.
    /// </summary>
    [Serializable]
    public class LoadoutData
    {
        /// <summary>0 = Sentinel (masked operator), 1 = Breacher (bare-faced shotgunner).</summary>
        public int CharacterVariant;
        public string ClassId = "pathfinder";
        public string PrimaryGunId = "m5";
        public int PrimarySkin;
        public string[] PrimaryAttachments = new string[0];
        public string SecondaryGunId = "";
        public int SecondarySkin;

        private static string Path
        {
            get { return System.IO.Path.Combine(Application.persistentDataPath, "nova_loadout.json"); }
        }

        public static LoadoutData Load()
        {
            try
            {
                if (File.Exists(Path))
                {
                    string json = File.ReadAllText(Path);
                    var d = JsonUtility.FromJson<LoadoutData>(json);
                    if (d != null)
                    {
                        if (d.PrimaryAttachments == null) d.PrimaryAttachments = new string[0];
                        if (string.IsNullOrEmpty(d.ClassId)) d.ClassId = "pathfinder";
                        if (string.IsNullOrEmpty(d.PrimaryGunId)) d.PrimaryGunId = "m5";
                        return d;
                    }
                }
            }
            catch (Exception e)
            {
                Debug.LogWarning("[LoadoutData] load failed: " + e.Message);
            }
            return new LoadoutData();
        }

        public void Save()
        {
            try { File.WriteAllText(Path, JsonUtility.ToJson(this, true)); }
            catch (Exception e) { Debug.LogWarning("[LoadoutData] save failed: " + e.Message); }
        }
    }
}
