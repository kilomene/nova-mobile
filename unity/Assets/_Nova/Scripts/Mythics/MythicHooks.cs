using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Arsenal;
using NovaMobile.Economy;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Installs the Mythics implementations into the Arsenal fallback hooks:
    /// GunsmithUI: SkinCountHook / SkinNameHook / SkinColorHook / SkinOwnershipHook;
    /// GunBehaviour: TracerColorHook; GunPickup: ApplySkinHook / SkinDisplayNameHook.
    /// Also tracks which skin index each gun id currently uses, so the tracer hook
    /// (which only receives the gun id) can resolve the themed tracer color.
    /// </summary>
    public static class MythicHooks
    {
        private static readonly Dictionary<string, int> _skinByGun = new Dictionary<string, int>();
        private static readonly Color DefaultTracer = new Color(1f, 0.85f, 0.5f);

        public static void Install()
        {
            GunsmithUI.SkinCountHook = gunId => MythicData.SkinCount(gunId);
            GunsmithUI.SkinNameHook = (gunId, idx) => MythicData.SkinDisplayName(gunId, idx);
            GunsmithUI.SkinColorHook = (gunId, idx) => MythicData.SkinPrimaryColor(gunId, idx);
            GunsmithUI.SkinOwnershipHook = skinId => NpWallet.OwnsSkin(skinId);
            GunPickup.ApplySkinHook = (go, gunId, idx) => SkinApplier.ApplyToModel(go, gunId, idx);
            GunPickup.SkinDisplayNameHook = (gunId, idx) => MythicData.SkinDisplayName(gunId, idx);
            GunBehaviour.TracerColorHook = gunId => TracerFor(gunId);
        }

        /// <summary>Record the active skin index for a gun id (called by SkinApplier).</summary>
        public static void RememberSkin(string gunId, int idx)
        {
            if (string.IsNullOrEmpty(gunId)) return;
            _skinByGun[gunId] = idx;
        }

        public static int SkinIdxFor(string gunId)
        {
            int idx;
            return _skinByGun.TryGetValue(gunId, out idx) ? idx : 0;
        }

        public static string ThemeIdFor(string gunId)
        {
            return MythicData.SkinThemeId(gunId, SkinIdxFor(gunId));
        }

        // Evolution brightens the tracer toward white as the stage climbs.
        private static Color TracerFor(string gunId)
        {
            int idx = SkinIdxFor(gunId);
            if (idx <= 0) return DefaultTracer;
            Color c = MythicData.TracerColor(gunId, idx);
            int stage = MythicEvolution.StageFor(gunId);
            return Color.Lerp(c, Color.white, 0.12f * stage);
        }
    }
}
