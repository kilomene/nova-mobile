using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using NovaMobile.Core;

namespace NovaMobile.Classes
{
    /// <summary>
    /// Static registries + allocation-free query helpers shared by all abilities.
    /// Enemy code should call EnemyRegistry.Register/Unregister on spawn/death;
    /// when empty, queries fall back to a tag scan ("Enemy" / "Player").
    /// </summary>
    public static class EnemyRegistry
    {
        private static readonly List<GameObject> Enemies = new List<GameObject>();

        public static void Register(GameObject go)
        {
            if (go != null && !Enemies.Contains(go)) Enemies.Add(go);
        }

        public static void Unregister(GameObject go) { Enemies.Remove(go); }

        /// <summary>Fill out with live IDamageables within radius of pos. No allocs.</summary>
        public static void Query(Vector3 pos, float radius, List<GameObject> outList)
        {
            outList.Clear();
            float r2 = radius * radius;
            for (int i = Enemies.Count - 1; i >= 0; i--)
            {
                GameObject go = Enemies[i];
                if (go == null) { Enemies.RemoveAt(i); continue; }
                var d = go.GetComponent<IDamageable>();
                if (d == null || !d.IsAlive) continue;
                if ((go.transform.position - pos).sqrMagnitude <= r2) outList.Add(go);
            }
            if (Enemies.Count == 0)
                QueryByTag(pos, radius, outList, "Enemy");
        }

        private static void QueryByTag(Vector3 pos, float radius, List<GameObject> outList, string tag)
        {
            GameObject[] found;
            try { found = GameObject.FindGameObjectsWithTag(tag); }
            catch (UnityException) { return; } // tag undefined: no fallback available
            float r2 = radius * radius;
            for (int i = 0; i < found.Length; i++)
            {
                GameObject go = found[i];
                var d = go.GetComponent<IDamageable>();
                if (d == null || !d.IsAlive) continue;
                if ((go.transform.position - pos).sqrMagnitude <= r2) outList.Add(go);
            }
        }
    }

    /// <summary>Enemy deployables (traps, turrets) for Saboteur's Engineer Sight.</summary>
    public static class DeployableRegistry
    {
        private struct Entry
        {
            public GameObject Go;
            public bool EnemyOwned;
        }

        private static readonly List<Entry> Items = new List<Entry>();

        public static void Register(GameObject go, bool enemyOwned = false)
        {
            if (go == null) return;
            for (int i = 0; i < Items.Count; i++)
                if (Items[i].Go == go) return;
            Items.Add(new Entry { Go = go, EnemyOwned = enemyOwned });
        }

        public static void Unregister(GameObject go)
        {
            for (int i = 0; i < Items.Count; i++)
                if (Items[i].Go == go || Items[i].Go == null) { Items.RemoveAt(i); return; }
        }

        public static void Query(Vector3 pos, float radius, List<GameObject> outList, bool enemyOnly = false)
        {
            outList.Clear();
            float r2 = radius * radius;
            for (int i = Items.Count - 1; i >= 0; i--)
            {
                GameObject go = Items[i].Go;
                if (go == null) { Items.RemoveAt(i); continue; }
                if (enemyOnly && !Items[i].EnemyOwned)
                {
                    // DeployableHealth components set EnemyOwned after AddComponent
                    // (OnEnable fires first), so prefer the live component flag.
                    var dh = go.GetComponent<DeployableHealth>();
                    if (dh == null || !dh.EnemyOwned) continue;
                }
                if ((go.transform.position - pos).sqrMagnitude <= r2) outList.Add(go);
            }
        }
    }

    /// <summary>Loot pickups for the Replicator mirror (Loot system registers).</summary>
    public static class LootPickupRegistry
    {
        private static readonly List<ILootPickup> Items = new List<ILootPickup>();
        public static void Register(ILootPickup p) { if (p != null && !Items.Contains(p)) Items.Add(p); }
        public static void Unregister(ILootPickup p) { Items.Remove(p); }

        public static void Query(Vector3 pos, float radius, List<ILootPickup> outList)
        {
            outList.Clear();
            float r2 = radius * radius;
            for (int i = Items.Count - 1; i >= 0; i--)
            {
                ILootPickup p = Items[i];
                if (p == null || p.gameObject == null) { Items.RemoveAt(i); continue; }
                if ((p.gameObject.transform.position - pos).sqrMagnitude <= r2) outList.Add(p);
            }
        }
    }

    /// <summary>Launch-pad state shared by Skyhook (kind 0) and Trampoline (kind 1).</summary>
    public struct PadEntry
    {
        public GameObject Node;
        public Vector3 Pos;
        public float TimeLeft;
        public int Kind; // 0 = skyhook catapult, 1 = bounce pad
    }

    /// <summary>Allocation-free combat helpers used by ability implementations.</summary>
    public static class CombatHelper
    {
        private static readonly RaycastHit[] GroundHits = new RaycastHit[8];
        private static GameObject _playerCache;
        private static float _playerCacheT;

        /// <summary>
        /// Hostiles for an ability owner: enemies for a player-owned ability,
        /// the player for an enemy-owned ability.
        /// </summary>
        public static void QueryHostiles(ClassAbility ability, Vector3 pos, float radius, List<GameObject> outList)
        {
            outList.Clear();
            bool ownerIsPlayer = ability == null || ability.GetComponent<IClassBody>() == null
                || ability.GetComponent<IClassBody>().IsPlayer;
            if (ownerIsPlayer)
            {
                EnemyRegistry.Query(pos, radius, outList);
                return;
            }
            GameObject player = FindPlayer();
            if (player == null) return;
            var d = player.GetComponent<IDamageable>();
            if (d == null || !d.IsAlive) return;
            if ((player.transform.position - pos).sqrMagnitude <= radius * radius)
                outList.Add(player);
        }

        public static GameObject FindPlayer()
        {
            if (_playerCache != null) return _playerCache;
            if (Time.time - _playerCacheT < 2f) return null;
            _playerCacheT = Time.time;
            try { _playerCache = GameObject.FindGameObjectWithTag("Player"); }
            catch (UnityException) { _playerCache = null; }
            return _playerCache;
        }

        /// <summary>
        /// Snap a point to the ground below it (highest hit, ignoring the
        /// requester's own colliders). Falls back to y=0 when nothing is hit.
        /// </summary>
        public static Vector3 GroundSnap(GameObject requester, Vector3 p)
        {
            int n = Physics.RaycastNonAlloc(p + Vector3.up * 40f, Vector3.down,
                GroundHits, 80f, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
            IClassBody body = requester != null ? requester.GetComponent<IClassBody>() : null;
            bool found = false;
            float bestY = float.NegativeInfinity;
            for (int i = 0; i < n; i++)
            {
                Collider c = GroundHits[i].collider;
                if (c == null) continue;
                if (body != null)
                {
                    var hitBody = c.GetComponentInParent<IClassBody>();
                    if (ReferenceEquals(hitBody, body)) continue;
                }
                float y = GroundHits[i].point.y;
                if (y > bestY) { bestY = y; found = true; }
            }
            if (found) p.y = bestY;
            else p.y = 0f;
            return p;
        }

        /// <summary>Parabolic throw of a small tracer; onLand fires at the target point.</summary>
        public static void ThrowArc(MonoBehaviour runner, Vector3 from, Vector3 to,
            float arcH, float duration, Action<Vector3> onLand)
        {
            if (runner == null) { onLand?.Invoke(to); return; }
            runner.StartCoroutine(ThrowArcRoutine(from, to, arcH, duration, onLand));
        }

        private static IEnumerator ThrowArcRoutine(Vector3 from, Vector3 to,
            float arcH, float duration, Action<Vector3> onLand)
        {
            var vis = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            vis.name = "ClassArc";
            UnityEngine.Object.Destroy(vis.GetComponent<Collider>());
            vis.transform.localScale = Vector3.one * 0.22f;
            var rend = vis.GetComponent<Renderer>();
            var mat = new Material(Shader.Find("Unlit/Color")) { color = Color.white };
            rend.sharedMaterial = mat;
            float t = 0f;
            while (t < duration)
            {
                t += Time.deltaTime;
                float k = Mathf.Clamp01(t / duration);
                Vector3 p = Vector3.Lerp(from, to, k);
                p.y += 4f * arcH * k * (1f - k);
                vis.transform.position = p;
                yield return null;
            }
            UnityEngine.Object.Destroy(vis);
            UnityEngine.Object.Destroy(mat);
            onLand?.Invoke(to);
        }
    }
}
