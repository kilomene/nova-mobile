using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Soldiers;

namespace NovaMobile.Match
{
    /// <summary>
    /// Recycles bot corpses: SoldierRig fires CorpseExpired 25s after death
    /// settles; the manager fades the corpse out and deactivates it into a
    /// free-list for reuse. Bot spawners (Squads system) call Register(rig).
    /// Ported from main.gd's corpse handling via enemy.gd death flow.
    /// </summary>
    public class CorpseManager : MonoBehaviour
    {
        public static CorpseManager Instance;

        private class Entry
        {
            public SoldierRig Rig;
            public float Fade;
            public bool Fading;
        }

        private readonly List<Entry> _entries = new List<Entry>(64);
        private readonly List<SoldierRig> _freeList = new List<SoldierRig>(64);

        public static CorpseManager Ensure()
        {
            if (Instance == null)
            {
                var go = new GameObject("CorpseManager");
                Instance = go.AddComponent<CorpseManager>();
            }
            return Instance;
        }

        private void OnDestroy() { if (Instance == this) Instance = null; }

        /// <summary>Called by whoever spawns a bot rig.</summary>
        public static void Register(SoldierRig rig)
        {
            if (rig == null) return;
            var mgr = Ensure();
            for (int i = 0; i < mgr._entries.Count; i++)
                if (mgr._entries[i].Rig == rig) return;
            var e = new Entry { Rig = rig };
            rig.CorpseExpired += mgr.OnCorpseExpired;
            mgr._entries.Add(e);
        }

        /// <summary>Reuse a recycled rig shell, or null when none is free.</summary>
        public static SoldierRig TryAcquire()
        {
            var mgr = Instance;
            if (mgr == null || mgr._freeList.Count == 0) return null;
            int last = mgr._freeList.Count - 1;
            var rig = mgr._freeList[last];
            mgr._freeList.RemoveAt(last);
            rig.gameObject.SetActive(true);
            return rig;
        }

        private void OnCorpseExpired(SoldierRig rig)
        {
            for (int i = 0; i < _entries.Count; i++)
            {
                if (_entries[i].Rig == rig)
                {
                    _entries[i].Fading = true;
                    _entries[i].Fade = 0f;
                    return;
                }
            }
        }

        private void Update()
        {
            for (int i = _entries.Count - 1; i >= 0; i--)
            {
                Entry e = _entries[i];
                if (e.Rig == null) { _entries.RemoveAt(i); continue; }
                if (!e.Fading) continue;
                e.Fade += Time.deltaTime / 2f; // 2s fade-out
                SetCorpseAlpha(e.Rig, 1f - e.Fade);
                if (e.Fade >= 1f)
                {
                    e.Rig.CorpseExpired -= OnCorpseExpired;
                    e.Rig.gameObject.SetActive(false);
                    SetCorpseAlpha(e.Rig, 1f); // restore for reuse
                    _freeList.Add(e.Rig);
                    _entries.RemoveAt(i);
                }
            }
        }

        private static readonly List<Material> ScratchMats = new List<Material>(32);

        private static void SetCorpseAlpha(SoldierRig rig, float a)
        {
            ScratchMats.Clear();
            var renderers = rig.GetComponentsInChildren<Renderer>();
            for (int i = 0; i < renderers.Length; i++)
            {
                var r = renderers[i];
                r.GetSharedMaterials(ScratchMats);
                for (int m = 0; m < ScratchMats.Count; m++)
                {
                    var mat = ScratchMats[m];
                    if (mat == null || mat.HasProperty("_Mode")) continue;
                    // Only touch materials that already support transparency.
                    if (mat.HasProperty("_Color"))
                    {
                        Color c = mat.color;
                        // Switch opaque materials to transparent blend once.
                        if (a < 1f && c.a >= 1f)
                        {
                            mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
                            mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                            mat.SetFloat("_ZWrite", 0f);
                            mat.renderQueue = 3000;
                        }
                        c.a = a;
                        mat.color = c;
                    }
                }
                ScratchMats.Clear();
            }
        }
    }
}
