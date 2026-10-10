using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Squads
{
    /// <summary>
    /// CODM-style nameplates (visual bible §4): callsign text floating above
    /// each bot's head — RED for hostiles, GREEN for teammates.
    /// Mobile-first: one pooled TextMesh per bot (no uGUI canvases, no
    /// per-frame allocations); a single central Tick() billboards all active
    /// plates and culls them beyond plate range. Plates are claimed at bot
    /// build time and released when the bot is destroyed, so match restarts
    /// reuse the same 100 TextMeshes.
    /// </summary>
    public static class BotNameplate
    {
        private const int MaxPlates = 100;
        private const float HeadHeight = 2.1f;
        private const float CullDist = 120f; // CODM shows plates at engagement range

        private static readonly Color HostileRed = new Color(1f, 0.16f, 0.16f);
        private static readonly Color MateGreen = new Color(0.32f, 1f, 0.38f);

        private class Plate
        {
            public GameObject Go;
            public TextMesh Text;
            public BotAgent Agent;
            public bool Visible;
        }

        private static readonly List<Plate> _pool = new List<Plate>();
        private static readonly List<Plate> _active = new List<Plate>();
        private static GameObject _root;

        private static void EnsureRoot()
        {
            if (_root == null)
            {
                _root = new GameObject("NameplatePool");
                Object.DontDestroyOnLoad(_root);
            }
        }

        /// <summary>Claim a plate for a bot; parents it above the bot's head.</summary>
        public static void Attach(BotAgent agent)
        {
            if (agent == null) return;
            EnsureRoot();
            // Reuse an existing plate for this agent if present.
            for (int i = 0; i < _active.Count; i++)
                if (_active[i].Agent == agent) { _active[i].Visible = true; return; }

            Plate p = null;
            for (int i = 0; i < _pool.Count; i++)
            {
                if (_pool[i].Agent == null) { p = _pool[i]; break; }
            }
            if (p == null)
            {
                if (_pool.Count >= MaxPlates) return;
                p = new Plate();
                p.Go = new GameObject("Nameplate");
                p.Go.transform.SetParent(_root.transform, false);
                p.Text = p.Go.AddComponent<TextMesh>();
                p.Text.fontSize = 64;
                p.Text.characterSize = 0.022f;
                p.Text.anchor = TextAnchor.MiddleCenter;
                p.Text.alignment = TextAlignment.Center;
                var mr = p.Go.GetComponent<MeshRenderer>();
                mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                mr.receiveShadows = false;
                _pool.Add(p);
            }
            p.Agent = agent;
            p.Text.text = agent.Callsign;
            p.Text.color = agent.IsTeammate ? MateGreen : HostileRed;
            p.Go.transform.SetParent(agent.transform, false);
            p.Go.transform.localPosition = new Vector3(0f, HeadHeight, 0f);
            p.Go.SetActive(true);
            p.Visible = true;
            _active.Add(p);
        }

        /// <summary>Release the bot's plate back to the pool.</summary>
        public static void Detach(BotAgent agent)
        {
            if (agent == null) return;
            for (int i = _active.Count - 1; i >= 0; i--)
            {
                if (_active[i].Agent == agent)
                {
                    Plate p = _active[i];
                    _active.RemoveAt(i);
                    p.Agent = null;
                    p.Visible = false;
                    p.Go.transform.SetParent(_root != null ? _root.transform : null, false);
                    p.Go.SetActive(false);
                    return;
                }
            }
        }

        /// <summary>Show/hide a bot's plate without releasing it (death/revive).</summary>
        public static void SetVisible(BotAgent agent, bool visible)
        {
            if (agent == null) return;
            for (int i = 0; i < _active.Count; i++)
            {
                if (_active[i].Agent == agent)
                {
                    _active[i].Visible = visible;
                    _active[i].Go.SetActive(visible);
                    return;
                }
            }
        }

        /// <summary>
        /// Billboard all active plates toward the camera and cull beyond
        /// range. Called once per frame by SquadManager. No allocations.
        /// </summary>
        public static void Tick()
        {
            if (_active.Count == 0) return;
            Camera cam = Camera.main;
            if (cam == null) return;
            Vector3 camPos = cam.transform.position;
            Quaternion camRot = cam.transform.rotation;
            float cull2 = CullDist * CullDist;
            for (int i = 0; i < _active.Count; i++)
            {
                Plate p = _active[i];
                if (p.Agent == null) continue;
                bool inRange = (p.Agent.transform.position - camPos).sqrMagnitude <= cull2;
                bool show = p.Visible && inRange;
                if (p.Go.activeSelf != show) p.Go.SetActive(show);
                if (show) p.Go.transform.rotation = camRot;
            }
        }
    }
}
