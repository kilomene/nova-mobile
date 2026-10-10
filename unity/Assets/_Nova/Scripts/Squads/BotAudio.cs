using UnityEngine;

namespace NovaMobile.Squads
{
    /// <summary>
    /// Small round-robin pool of 3D AudioSources for bot gunfire and barks.
    /// Mobile-first: avoids one AudioSource per bot (100 combatants) and never
    /// synthesizes clips at runtime (uses Arsenal's cached GunAudio clips).
    /// </summary>
    public static class BotAudio
    {
        private const int PoolSize = 10;
        private static AudioSource[] _pool;
        private static GameObject _root;
        private static int _cursor;

        private static void Ensure()
        {
            if (_pool != null) return;
            _root = new GameObject("BotAudioPool");
            Object.DontDestroyOnLoad(_root);
            _pool = new AudioSource[PoolSize];
            for (int i = 0; i < PoolSize; i++)
            {
                var go = new GameObject("BotVoice" + i);
                go.transform.SetParent(_root.transform, false);
                var src = go.AddComponent<AudioSource>();
                src.playOnAwake = false;
                src.spatialBlend = 1f;
                src.minDistance = 4f;
                src.maxDistance = 60f;
                src.rolloffMode = AudioRolloffMode.Linear;
                _pool[i] = src;
            }
            _cursor = 0;
        }

        public static void PlayAt(AudioClip clip, Vector3 pos, float volume = 1f, float pitch = 1f)
        {
            if (clip == null) return;
            Ensure();
            AudioSource src = _pool[_cursor];
            _cursor = (_cursor + 1) % PoolSize;
            src.transform.position = pos;
            src.pitch = pitch;
            src.PlayOneShot(clip, volume);
        }
    }
}
