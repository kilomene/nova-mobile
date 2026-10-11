using UnityEngine;
using NovaMobile.Match;

namespace NovaMobile.Core
{
    /// <summary>
    /// Guarantees the game boots into the lobby even when the launch scene is
    /// empty: creates the MatchManager singleton before the first scene loads,
    /// whose Start() then shows the 3D lobby. Mirrors the
    /// DrivingHUD.AutoCreate pattern already used in this project.
    /// </summary>
    public static class NovaBootstrap
    {
        private static bool _done;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void Boot()
        {
            if (_done) return;
            _done = true;
            MatchManager.Ensure();
        }
    }
}
