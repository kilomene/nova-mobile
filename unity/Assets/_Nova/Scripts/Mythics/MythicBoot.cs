using UnityEngine;

namespace NovaMobile.Mythics
{
    /// <summary>
    /// Boots the mythics system from code: installs the Arsenal fallback hooks,
    /// warms the shared theme materials, and builds the pooled FX. No scene or
    /// editor setup needed — the game boots from code.
    /// NOTE: the Nova/MythicSkin shader must ship in the build — add it to
    /// Project Settings > Graphics > Always Included Shaders (a CI/packaging
    /// step the coordinator owns; without it skins fall back with a warning).
    /// </summary>
    public static class MythicBoot
    {
        private static bool _done;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Boot()
        {
            if (_done) return;
            _done = true;
            MythicHooks.Install();
            MythicMaterials.Warm();
            MythicFx.Init();
        }
    }
}
