using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Match
{
    /// <summary>
    /// World-space marker feeds for the minimap. Other systems (World loot,
    /// Vehicles, Squads, Loot) push positions here; Minimap renders them.
    /// All lists are reused (no per-frame allocation).
    /// </summary>
    public static class MatchMarkers
    {
        public static readonly List<Vector3> BuyStations = new List<Vector3>(16);
        public static readonly List<Vector3> FuelStations = new List<Vector3>(16);
        public static readonly List<Vector3> Airdrops = new List<Vector3>(8);
        public static readonly List<Transform> Teammates = new List<Transform>(8);
        public static readonly List<Transform> Enemies = new List<Transform>(64);

        public struct Ping
        {
            public Vector3 Pos;
            public Color Color;
        }
        public static readonly List<Ping> Pings = new List<Ping>(16);

        /// <summary>UAV sweep active: show all enemies (else only nearby).</summary>
        public static bool UavActive;

        public static void AddBuyStation(Vector3 p) { if (!BuyStations.Contains(p)) BuyStations.Add(p); }
        public static void AddFuelStation(Vector3 p) { if (!FuelStations.Contains(p)) FuelStations.Add(p); }
        public static void AddAirdrop(Vector3 p) { if (Airdrops.Count < 8) Airdrops.Add(p); }
        public static void RemoveAirdrop(Vector3 p) { Airdrops.Remove(p); }
        public static void AddPing(Vector3 p, Color c)
        {
            if (Pings.Count >= 16) Pings.RemoveAt(0);
            Pings.Add(new Ping { Pos = p, Color = c });
        }
        public static void RegisterTeammate(Transform t) { if (t != null && !Teammates.Contains(t)) Teammates.Add(t); }
        public static void UnregisterTeammate(Transform t) { Teammates.Remove(t); }
        public static void RegisterEnemy(Transform t) { if (t != null && !Enemies.Contains(t)) Enemies.Add(t); }
        public static void UnregisterEnemy(Transform t) { Enemies.Remove(t); }

        public static void Clear()
        {
            BuyStations.Clear(); FuelStations.Clear(); Airdrops.Clear();
            Teammates.Clear(); Enemies.Clear(); Pings.Clear();
            UavActive = false;
        }
    }
}
