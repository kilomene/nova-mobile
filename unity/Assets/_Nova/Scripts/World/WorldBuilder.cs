using System;
using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>
    /// Builds the entire NOVA WORLD at runtime — ONE continuous 690x690m battle royale
    /// map (no map-select UI anywhere; the 14 Lagos layouts exist only as districts of
    /// this single world). No scene-placed content required: everything spawns from
    /// code in Awake().
    ///
    /// Build order (ports world.gd _ready):
    ///   terrain + water tissue -> avenues (roads) -> canal bridges -> wilderness
    ///   scatter -> perimeter walls -> 14 districts -> world-POI loot rings.
    /// Static geometry is combined per material (WorldBatch, ~1 draw call each);
    /// colliders are merged under one parent per district / world tissue.
    /// </summary>
    public class WorldBuilder : MonoBehaviour
    {
        public static WorldBuilder Instance { get; private set; }

        // Aggregated gameplay data (world-space), filled during the build.
        public readonly List<LootSpot> LootSpots = new List<LootSpot>();
        public readonly List<Vector3> EnemySpawns = new List<Vector3>();
        public readonly List<Vector3> HousePositions = new List<Vector3>();
        public Vector3 PlayerSpawn = new Vector3(0f, 0.6f, 0f);

        public WorldMaterials Materials { get; private set; }

        private const float TissueR = 460f;   // tissue radius (includes water margins)
        private const float Cell = 20f;       // tissue cell size
        private const float WaterY = -0.55f;

        private static readonly float[] AveNS = { -180f, 0f, 180f };
        private static readonly float[] AveEW = { -180f, 0f };

        private readonly Dictionary<string, Action<RegionContext>> _districts =
            new Dictionary<string, Action<RegionContext>>();

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }
            Instance = this;
            RegisterDistricts();
            Build();
        }

        private void RegisterDistricts()
        {
            _districts["AIRBASE"] = RegionBuilders.BuildAirbase;
            _districts["AIRPORT"] = RegionBuilders.BuildAirport;
            _districts["BARRACKS"] = RegionBuilders.BuildBarracks;
            _districts["TRAIN STATION"] = RegionBuilders.BuildTrainStation;
            _districts["VALLEY"] = RegionBuilders.BuildValley;
            _districts["LEKKI"] = RegionBuilders.BuildLekki;
            _districts["COMPUTER VILLAGE"] = RegionBuilders.BuildComputerVillage;
            _districts["DOWNTOWN"] = RegionBuilders.BuildDowntown;
            _districts["MAKOKO"] = RegionBuilders.BuildMakoko;
            _districts["BANANA ISLAND"] = RegionBuilders.BuildBananaIsland;
            _districts["SHIP PORT"] = RegionBuilders.BuildShipPort;
            _districts["LAGOON BRIDGE"] = RegionBuilders.BuildLagoonBridge;
            _districts["DAM"] = RegionBuilders.BuildDam;
            _districts["STADIUM"] = RegionBuilders.BuildStadium;
        }

        private void Build()
        {
            Materials = WorldMaterials.Create();

            var root = new GameObject("NOVA_WORLD");
            root.transform.SetParent(transform, false);

            var tissue = new WorldBatch();
            BuildGroundWater(tissue);
            BuildRoads(tissue);
            BuildBridges(tissue);
            BuildWilderness(tissue);
            BuildPerimeter(tissue);
            var tissueGo = new GameObject("Tissue");
            tissueGo.transform.SetParent(root.transform, false);
            int tissueDraws = tissue.Build(tissueGo.transform, "Tissue");
            tissue.BuildColliders(tissueGo.transform, "TissueColliders");
            // Walkable terrain mesh collider.
            var terrainCollider = tissueGo.AddComponent<MeshCollider>();
            var tmf = tissueGo.GetComponent<MeshFilter>();
            if (tmf == null)
            {
                // Terrain lives in the Grass-bucket mesh; find it by name.
                foreach (Transform child in tissueGo.transform)
                {
                    if (child.name.EndsWith("Grass"))
                    {
                        terrainCollider.sharedMesh = child.GetComponent<MeshFilter>().sharedMesh;
                        break;
                    }
                }
            }

            int regionDraws = 0;
            foreach (var region in WorldData.Regions)
            {
                var go = new GameObject("District_" + region.Name.Replace(" ", "_"));
                go.transform.SetParent(root.transform, false);
                go.transform.position = new Vector3(region.Offset.x, 0f, region.Offset.y);

                // Stable per-district seed (FNV-1a of the name — System.String.GetHashCode
                // is randomized per process, so it must not seed the world layout).
                int seed = 20261014;
                foreach (char ch in region.Name) seed = (seed ^ ch) * 16777619;
                var ctx = new RegionContext
                {
                    Name = region.Name,
                    Origin = go.transform.position,
                    Root = go.transform,
                    Rng = new System.Random(seed),
                    Mats = Materials,
                    Batch = new WorldBatch(),
                };
                Action<RegionContext> builder;
                if (_districts.TryGetValue(region.Name, out builder))
                    builder(ctx);
                else
                    Debug.LogWarning("[WorldBuilder] no builder for district " + region.Name);

                regionDraws += ctx.Batch.Build(go.transform, "District");
                ctx.Batch.BuildColliders(go.transform);

                // Aggregate region-local gameplay data into world space.
                foreach (var ls in ctx.Loot)
                    LootSpots.Add(new LootSpot(ls.Kind, ls.Amount, ls.Position + ctx.Origin, ls.Tier));
                foreach (var es in ctx.EnemySpawns) EnemySpawns.Add(es + ctx.Origin);
                foreach (var hp in ctx.HousePositions) HousePositions.Add(hp + ctx.Origin);
            }

            // World-POI loot rings (8 per POI, tier 3 — ports _build_world_pois).
            string[] kinds = { "health", "armor", "ammo" };
            int[] amounts = { 40, 50, 60 };
            foreach (var poi in WorldData.Pois)
            {
                if (poi.Id.StartsWith("ab_") || poi.Id.StartsWith("ap_") || poi.Id.StartsWith("bk_") ||
                    poi.Id.StartsWith("ts_") || poi.Id.StartsWith("vc_") || poi.Id.StartsWith("lk_") ||
                    poi.Id.StartsWith("cv_") || poi.Id.StartsWith("dt_") || poi.Id.StartsWith("mk_") ||
                    poi.Id.StartsWith("bi_") || poi.Id.StartsWith("sp_") || poi.Id.StartsWith("lb_") ||
                    poi.Id.StartsWith("dm_") || poi.Id.StartsWith("st_"))
                    continue; // district POIs already got rings from their builders
                for (int k = 0; k < 8; k++)
                {
                    float a = Mathf.PI * 2f * k / 8f;
                    float rad = 6f + (k % 3) * 3f;
                    Vector3 lp = poi.Position + new Vector3(Mathf.Cos(a) * rad, 0.55f, Mathf.Sin(a) * rad);
                    LootSpots.Add(new LootSpot(kinds[k % 3], amounts[k % 3], lp, 3));
                }
            }

            // Day lighting: bright Lagos daytime sun + ambient.
            var sunGo = new GameObject("Sun");
            sunGo.transform.SetParent(root.transform, false);
            sunGo.AddComponent<DayLight>();

            // Water animation (scrolling material offset).
            var waterAnim = root.AddComponent<WaterAnimator>();
            waterAnim.WaterMaterial = Materials.Water;

            Debug.Log(string.Format(
                "[WorldBuilder] districts={0} enemies={1} loot={2} pois={3} tissue_draws={4} region_draws={5} low_tier={6}",
                WorldData.Regions.Length, EnemySpawns.Count, LootSpots.Count, WorldData.Pois.Length,
                tissueDraws, regionDraws, WorldQuality.IsLow));
        }

        // ---------------- tissue ----------------

        private static bool InRegionRect(float x, float z, float margin)
        {
            foreach (var r in WorldData.Regions)
                if (Mathf.Abs(x - r.Offset.x) <= WorldData.RegionHalf + margin &&
                    Mathf.Abs(z - r.Offset.y) <= WorldData.RegionHalf + margin)
                    return true;
            return false;
        }

        private static bool NearShore(float x, float z)
        {
            foreach (var r in WorldData.Regions)
            {
                if (!r.Shore) continue;
                float dx = Mathf.Abs(x - r.Offset.x), dz = Mathf.Abs(z - r.Offset.y);
                if (dx <= 92f && dz <= 92f && !(dx <= 70f && dz <= 70f)) return true;
            }
            return false;
        }

        private static bool IsWater(float x, float z)
        {
            if (z > 345f) return true;   // south lagoon
            if (x > 345f) return true;   // east harbor
            if (z > WorldData.CanalNorth && z < WorldData.CanalSouth && x > -340f && x < 340f)
                return true;            // grand canal
            float dx = (x - 90f) / 55f, dz = (z - 270f) / 40f;
            if (dx * dx + dz * dz < 1f) return true;  // wilderness lake
            return false;
        }

        private static bool OnRoad(float x, float z)
        {
            foreach (float ax in AveNS)
                if (Mathf.Abs(x - ax) < 6f && Mathf.Abs(z) < 345f) return true;
            foreach (float az in AveEW)
                if (Mathf.Abs(z - az) < 6f && Mathf.Abs(x) < 345f) return true;
            return false;
        }

        private static float Hash2(int x, int z)
        {
            int h = x * 374761393 + z * 668265263 + 1013904223;
            h = (h ^ (h >> 13)) * 1274126177;
            h ^= h >> 16;
            return (h & 0x7fffffff) / (float)0x7fffffff;
        }

        private static float ValueNoise(float x, float z)
        {
            int xi = Mathf.FloorToInt(x), zi = Mathf.FloorToInt(z);
            float xf = x - xi, zf = z - zi;
            float u = xf * xf * (3f - 2f * xf), v = zf * zf * (3f - 2f * zf);
            float a = Hash2(xi, zi), b = Hash2(xi + 1, zi);
            float c = Hash2(xi, zi + 1), d = Hash2(xi + 1, zi + 1);
            return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
        }

        /// <summary>
        /// Gentle wilderness height variation (±0.5m), flattened near roads so the
        /// avenue ribbons sit cleanly. Districts are skipped (they build their own
        /// flat ground).
        /// </summary>
        public static float TerrainHeight(float x, float z)
        {
            float h = (ValueNoise(x * 0.02f, z * 0.02f) - 0.5f) * 1.0f;
            float roadDist = 1e9f;
            foreach (float ax in AveNS) roadDist = Mathf.Min(roadDist, Mathf.Abs(x - ax));
            foreach (float az in AveEW) roadDist = Mathf.Min(roadDist, Mathf.Abs(z - az));
            if (roadDist < 10f) h *= roadDist / 10f;
            return h;
        }

        private void BuildGroundWater(WorldBatch batch)
        {
            int n = Mathf.RoundToInt(TissueR * 2f / Cell);
            var rng = new System.Random(777);
            for (int i = 0; i < n; i++)
            {
                for (int j = 0; j < n; j++)
                {
                    float cx = -TissueR + Cell * 0.5f + i * Cell;
                    float cz = -TissueR + Cell * 0.5f + j * Cell;
                    if (InRegionRect(cx, cz, 0f)) continue;
                    bool wet = IsWater(cx, cz) || NearShore(cx, cz);
                    float h = Cell * 0.5f;
                    if (wet)
                    {
                        batch.TerrainQuad(
                            new Vector3(cx - h, WaterY, cz - h), new Vector3(cx + h, WaterY, cz - h),
                            new Vector3(cx + h, WaterY, cz + h), new Vector3(cx - h, WaterY, cz + h),
                            Color.white, Color.white, Color.white, Color.white, Materials.Water);
                    }
                    else
                    {
                        float g = 0.85f + (float)rng.NextDouble() * 0.3f;
                        var tint = new Color(0.96f * g + 0.04f, 1.0f * g, 0.92f * g);
                        Vector3 a = new Vector3(cx - h, TerrainHeight(cx - h, cz - h), cz - h);
                        Vector3 b = new Vector3(cx + h, TerrainHeight(cx + h, cz - h), cz - h);
                        Vector3 c = new Vector3(cx + h, TerrainHeight(cx + h, cz + h), cz + h);
                        Vector3 d = new Vector3(cx - h, TerrainHeight(cx - h, cz + h), cz + h);
                        batch.TerrainQuad(a, b, c, d, tint, tint, tint, tint, Materials.Grass);
                    }
                }
            }
        }

        private void BuildRoads(WorldBatch batch)
        {
            float canalN = WorldData.CanalNorth, canalS = WorldData.CanalSouth;
            // North-south avenues (gap at the canal — bridges go there).
            foreach (float ax in AveNS)
            {
                float z = -340f;
                while (z < 340f)
                {
                    if (z < canalN - 20f || z >= canalS + 20f)
                        batch.RoadQuad(ax - 4f, ax + 4f, z, z + Cell, 0.06f, false, Materials.Road);
                    z += Cell;
                }
            }
            // East-west avenues.
            foreach (float az in AveEW)
            {
                float x = -340f;
                while (x < 340f)
                {
                    batch.RoadQuad(x, x + Cell, az - 4f, az + 4f, 0.06f, true, Materials.Road);
                    x += Cell;
                }
            }
        }

        private void Ramp(WorldBatch batch, float ax, float z0, float z1, bool flip)
        {
            // Sloped approach from road (y~0.1) to bridge deck (y~1.2).
            float length = z1 - z0, rise = 1.1f;
            float slopeLen = Mathf.Sqrt(length * length + rise * rise);
            float ang = Mathf.Atan2(rise, length) * Mathf.Rad2Deg;
            Vector3 mid = new Vector3(ax, 0.1f + rise * 0.5f, (z0 + z1) * 0.5f);
            var m = Matrix4x4.TRS(mid,
                Quaternion.AngleAxis(flip ? ang : -ang, Vector3.right), Vector3.one);
            batch.Box(new Vector3(10f, 0.4f, slopeLen + 1f), m, Materials.DeckGrey, Color.white);
            batch.Collider(new Vector3(10f, 0.4f, slopeLen + 1f), m);
        }

        private void BuildBridges(WorldBatch batch)
        {
            float zc = (WorldData.CanalNorth + WorldData.CanalSouth) * 0.5f;
            const float span = 52f;
            foreach (float ax in AveNS)
            {
                var deckM = Matrix4x4.TRS(new Vector3(ax, 0.8f, zc),
                    Quaternion.identity, Vector3.one);
                batch.Box(new Vector3(10f, 0.8f, span), deckM, Materials.DeckGrey, Color.white);
                batch.Collider(new Vector3(10f, 0.8f, span), deckM);
                batch.RoadQuad(ax - 4f, ax + 4f, zc - span * 0.5f, zc + span * 0.5f,
                    1.22f, false, Materials.Road);
                foreach (float side in new[] { -1f, 1f })
                {
                    float rx = ax + side * 4.8f;
                    var railM = Matrix4x4.TRS(new Vector3(rx, 1.75f, zc),
                        Quaternion.identity, Vector3.one);
                    batch.Box(new Vector3(0.4f, 1.1f, span), railM, Materials.Metal, Color.white);
                    batch.Collider(new Vector3(0.4f, 1.1f, span), railM);
                }
                foreach (float pz in new[] { zc - span * 0.25f, zc + span * 0.25f })
                {
                    foreach (float px in new[] { ax - 3.5f, ax + 3.5f })
                        batch.Cylinder(0.6f, 4f, 10,
                            Matrix4x4.TRS(new Vector3(px, -1.5f, pz), Quaternion.identity, Vector3.one),
                            Materials.DeckGrey, new Color(0.8f, 0.8f, 0.8f));
                }
                Ramp(batch, ax, zc - span * 0.5f - 14f, zc - span * 0.5f, false);
                Ramp(batch, ax, zc + span * 0.5f, zc + span * 0.5f + 14f, true);
            }
        }

        private void BuildWilderness(WorldBatch batch)
        {
            var rng = new System.Random(20261014);
            float density = WorldQuality.ScatterScale;
            const float c = 12f;
            int count = Mathf.RoundToInt(680f / c);
            for (int i = 0; i < count; i++)
            {
                for (int j = 0; j < count; j++)
                {
                    float cx = -340f + c * 0.5f + i * c;
                    float cz = -340f + c * 0.5f + j * c;
                    if (InRegionRect(cx, cz, 4f)) continue;
                    if (OnRoad(cx, cz)) continue;
                    if (IsWater(cx, cz) || NearShore(cx, cz)) continue;
                    float r = (float)rng.NextDouble();
                    float gy = TerrainHeight(cx, cz);
                    if (r < 0.10f * density)
                    {
                        // tree
                        float h = 2.4f + (float)rng.NextDouble() * 1.2f;
                        batch.Cylinder(0.22f, h, 8,
                            Matrix4x4.TRS(new Vector3(cx, gy + h * 0.5f, cz),
                                Quaternion.identity, Vector3.one),
                            Materials.Trunk, Color.white);
                        batch.Collider(new Vector3(0.5f, h, 0.5f),
                            Matrix4x4.TRS(new Vector3(cx, gy + h * 0.5f, cz),
                                Quaternion.identity, Vector3.one));
                        float cs = 2.2f + (float)rng.NextDouble() * 1.0f;
                        batch.Rock(new Vector3(cs, cs * 0.72f, cs),
                            Matrix4x4.TRS(new Vector3(cx, gy + h + 0.3f, cz),
                                Quaternion.identity, Vector3.one),
                            Materials.Foliage, Color.white, false, 0.28f);
                    }
                    else if (r < 0.16f * density)
                    {
                        float s = 1.5f + (float)rng.NextDouble() * 1.5f;
                        batch.Rock(new Vector3(s, s * 0.7f, s),
                            Matrix4x4.TRS(new Vector3(cx, gy + s * 0.3f, cz),
                                Quaternion.identity, Vector3.one),
                            Materials.RockM, new Color(0.9f, 0.88f, 0.85f), true, 0.35f);
                    }
                    else if (r < 0.24f * density)
                    {
                        batch.Rock(new Vector3(1.2f, 0.9f, 1.2f),
                            Matrix4x4.TRS(new Vector3(cx, gy + 0.4f, cz),
                                Quaternion.identity, Vector3.one),
                            Materials.Foliage, new Color(0.85f, 1f, 0.85f), false, 0.3f);
                    }
                }
            }
        }

        private void BuildPerimeter(WorldBatch batch)
        {
            // Invisible walls at the playable edge (inner face at 347).
            var id = Quaternion.identity;
            batch.Collider(new Vector3(700f, 30f, 2f), new Vector3(0f, 15f, 348f), id);
            batch.Collider(new Vector3(700f, 30f, 2f), new Vector3(0f, 15f, -348f), id);
            batch.Collider(new Vector3(2f, 30f, 700f), new Vector3(348f, 15f, 0f), id);
            batch.Collider(new Vector3(2f, 30f, 700f), new Vector3(-348f, 15f, 0f), id);
        }

        /// <summary>Ground height query for gameplay (player spawns, AI).</summary>
        public float GroundHeight(float x, float z)
        {
            if (InRegionRect(x, z, 0f)) return 0f; // districts are flat
            return TerrainHeight(x, z);
        }
    }
}
