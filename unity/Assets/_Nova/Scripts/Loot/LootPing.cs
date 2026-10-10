using System;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Loot
{
    /// <summary>
    /// World ping marker: floating diamond + pulse ring + label. Spawns when the
    /// player double-taps loot (or pings with the crosshair on it). 20 s life.
    /// Static events let the Squads AI (and minimap/HUD) listen without a hard
    /// dependency. Ported from loot_ping.gd.
    /// </summary>
    public class LootPing : MonoBehaviour
    {
        public const float Life = 20f;

        public string LabelText = "LOOT";
        public Rarity Tier = Rarity.Common;

        /// <summary>Raised on spawn: position + rarity. Squads AI investigates Epic+.</summary>
        public static event Action<Vector3, Rarity> OnPingSpawned;
        /// <summary>Raised on expiry so minimap blips can be removed.</summary>
        public static event Action<LootPing> OnPingExpired;

        private Transform _diamond;
        private Transform _ring;
        private float _t;

        public static LootPing Spawn(string text, Rarity tier, Vector3 pos)
        {
            var go = new GameObject("LootPing");
            var p = go.AddComponent<LootPing>();
            p.LabelText = text;
            p.Tier = tier;
            go.transform.position = pos;
            if (OnPingSpawned != null) OnPingSpawned(pos, tier);
            return p;
        }

        private void Awake()
        {
            Color c = LootTable.RarityColor(Tier);
            var unlit = new Material(Shader.Find("Unlit/Color") ?? Shader.Find("Standard"));
            unlit.color = c;

            var dGo = new GameObject("Diamond");
            dGo.transform.SetParent(transform, false);
            dGo.transform.localPosition = new Vector3(0f, 2.2f, 0f);
            dGo.transform.localRotation = Quaternion.Euler(34f, 34f, 0f);
            var dmf = dGo.AddComponent<MeshFilter>();
            dmf.mesh = MeshBuilderCombine(new Vector3(0.28f, 0.28f, 0.28f));
            var dmr = dGo.AddComponent<MeshRenderer>();
            dmr.material = unlit;
            _diamond = dGo.transform;

            var rGo = new GameObject("Pulse");
            rGo.transform.SetParent(transform, false);
            rGo.transform.localPosition = new Vector3(0f, 0.15f, 0f);
            var rmf = rGo.AddComponent<MeshFilter>();
            rmf.mesh = LootModels.TorusMesh(0.56f, 0.06f);
            var rmr = rGo.AddComponent<MeshRenderer>();
            rmr.material = unlit;
            _ring = rGo.transform;

            var labelGo = new GameObject("Label");
            labelGo.transform.SetParent(transform, false);
            labelGo.transform.localPosition = new Vector3(0f, 3.0f, 0f);
            var label = labelGo.AddComponent<TextMesh>();
            label.anchor = TextAnchor.MiddleCenter;
            label.alignment = TextAlignment.Center;
            label.characterSize = 0.07f;
            label.fontSize = 52;
            label.color = c;
            label.text = "◈ " + LabelText.ToUpperInvariant();
        }

        private static Mesh MeshBuilderCombine(Vector3 size)
        {
            return MeshBuilder.Combine(
                new List<MeshBuilder.Part>
                {
                    MeshBuilder.Box(size, Matrix4x4.identity)
                });
        }

        private void Update()
        {
            _t += Time.deltaTime;
            if (_t >= Life)
            {
                if (OnPingExpired != null) OnPingExpired(this);
                Destroy(gameObject);
                return;
            }
            if (_diamond != null)
            {
                _diamond.Rotate(0f, 2.5f * Time.deltaTime * Mathf.Rad2Deg, 0f);
                Vector3 p = _diamond.localPosition;
                p.y = 2.2f + Mathf.Sin(_t * 3f) * 0.15f;
                _diamond.localPosition = p;
            }
            if (_ring != null)
            {
                float s = 1f + 0.18f * Mathf.Sin(_t * 4f);
                _ring.localScale = new Vector3(s, 1f, s);
            }
        }
    }
}
