using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>Named point of interest on the world map (minimap labels, loot rings, spawn hints).</summary>
    public struct PoiInfo
    {
        public string Id;
        public string Name;
        public Vector3 Position;   // world-space
        public float Radius;       // gameplay radius around the point

        public PoiInfo(string id, string name, Vector3 position, float radius)
        {
            Id = id;
            Name = name;
            Position = position;
            Radius = radius;
        }
    }

    /// <summary>One of the 14 Lagos regions instanced on the world grid.</summary>
    public struct RegionDef
    {
        public string Name;
        public Vector2 Offset;     // region origin in world XZ
        public bool Shore;         // lagoon-shore region (extra water ring)

        public RegionDef(string name, float ox, float oz, bool shore)
        {
            Name = name;
            Offset = new Vector2(ox, oz);
            Shore = shore;
        }
    }

    /// <summary>
    /// Static world data ported from Godot world.gd (+ the 14 region scripts).
    /// POI positions are world-space: region POIs from each region script plus the
    /// region offset from world.gd's REGIONS table; the 6 world POIs come first,
    /// matching world.gd's build order (_build_world_pois runs before _aggregate).
    /// Radii are derived (not present in Godot): they match the loot-scatter ring
    /// each POI uses in its region script.
    /// </summary>
    public static class WorldData
    {
        public const float WorldSize = 690f;      // playable extent, matches MAP_EXTENT*2
        public const float RegionPitch = 180f;    // grid pitch between region origins
        public const float RegionHalf = 70f;      // half-size of a region footprint
        public const float CanalNorth = 168f;     // grand canal north edge (world z)
        public const float CanalSouth = 192f;     // grand canal south edge (world z)
        public const float WaterY = -0.55f;

        public static readonly RegionDef[] Regions = {
            new RegionDef("AIRBASE",        -270f, -270f, false),
            new RegionDef("AIRPORT",         -90f, -270f, false),
            new RegionDef("BARRACKS",         90f, -270f, false),
            new RegionDef("TRAIN STATION",   270f, -270f, false),
            new RegionDef("VALLEY",         -270f,  -90f, false),
            new RegionDef("LEKKI",           -90f,  -90f, false),
            new RegionDef("COMPUTER VILLAGE", 90f,  -90f, false),
            new RegionDef("DOWNTOWN",        270f,  -90f, false),
            new RegionDef("MAKOKO",         -270f,   90f, true),
            new RegionDef("BANANA ISLAND",   -90f,   90f, true),
            new RegionDef("SHIP PORT",        90f,   90f, true),
            new RegionDef("LAGOON BRIDGE",   270f,   90f, true),
            new RegionDef("DAM",            -270f,  270f, false),
            new RegionDef("STADIUM",         -90f,  270f, false),
        };

        public static readonly PoiInfo[] Pois = {
            // ---- world-level POIs (world.gd WORLD_POIS) ----
            new PoiInfo("grand_canal",        "Grand Canal",        new Vector3(30f, 0f, 150f),   18f),
            new PoiInfo("central_crossroads", "Central Crossroads", new Vector3(0f, 0f, 0f),       15f),
            new PoiInfo("lakeside_park",      "Lakeside Park",      new Vector3(150f, 0f, 270f),  18f),
            new PoiInfo("north_gate",         "North Gate",         new Vector3(0f, 0f, -330f),   12f),
            new PoiInfo("harbor_view",        "Harbor View",        new Vector3(330f, 0f, 90f),   15f),
            new PoiInfo("south_lagoon",       "South Lagoon",       new Vector3(-90f, 0f, 330f),  18f),
            // ---- AIRBASE (offset -270,-270) ----
            new PoiInfo("ab_bomber_row",      "Bomber Row",         new Vector3(-270f, 0f, -294f),   15f),
            new PoiInfo("ab_shelters",        "Hardened Shelters",  new Vector3(-287.5f, 0f, -245f), 12f),
            new PoiInfo("ab_command",         "Command",            new Vector3(-240f, 0f, -240f),   12f),
            new PoiInfo("ab_control_tower",   "Control Tower",      new Vector3(-218f, 0f, -264f),   10f),
            // ---- AIRPORT (offset -90,-270) ----
            new PoiInfo("ap_terminal",        "Terminal",           new Vector3(-106f, 0f, -284f), 15f),
            new PoiInfo("ap_control_tower",   "Control Tower",      new Vector3(-86f, 0f, -276f),  10f),
            new PoiInfo("ap_helipad_row",     "Helipad Row",        new Vector3(-48f, 0.1f, -253f),12f),
            new PoiInfo("ap_hangars",         "Hangars",            new Vector3(-68f, 0f, -208f),  15f),
            // ---- BARRACKS (offset 90,-270) ----
            new PoiInfo("bk_parade_ground",   "Parade Ground",      new Vector3(90f, 0f, -270f),  15f),
            new PoiInfo("bk_armory",          "Armory",             new Vector3(120f, 0f, -228f), 10f),
            new PoiInfo("bk_mess_hall",       "Mess Hall",          new Vector3(60f, 0f, -228f),  10f),
            new PoiInfo("bk_gatehouse",       "Gatehouse",          new Vector3(112f, 0f, -208f),  8f),
            // ---- TRAIN STATION (offset 270,-270) ----
            new PoiInfo("ts_main_hall",       "Main Hall",          new Vector3(270f, 0f, -280f), 12f),
            new PoiInfo("ts_platform_1",      "Platform 1",         new Vector3(250f, 1f, -262f), 10f),
            new PoiInfo("ts_the_train",       "The Train",          new Vector3(254.5f, 1f, -257f),12f),
            new PoiInfo("ts_footbridge",      "Footbridge",         new Vector3(310f, 5.2f, -253f), 8f),
            // ---- VALLEY (offset -270,-90) ----
            new PoiInfo("vc_hilltop_outpost", "Hilltop Outpost",    new Vector3(-230f, 0f, -134f),12f),
            new PoiInfo("vc_river_crossing",  "River Crossing",     new Vector3(-278f, 0f, -112f),10f),
            new PoiInfo("vc_valley_camp",     "Valley Camp",        new Vector3(-284f, 0f, -82f), 12f),
            new PoiInfo("vc_ruined_compound","Ruined Compound",     new Vector3(-250f, 0f, -124f),12f),
            // ---- LEKKI (offset -90,-90) ----
            new PoiInfo("lk_admiralty_mall",  "Admiralty Mall",     new Vector3(-132f, 0f, -60f), 12f),
            new PoiInfo("lk_estate_gate",     "Estate Gate",        new Vector3(-42f, 0f, -50f),  10f),
            new PoiInfo("lk_bridge_view",     "Bridge View",        new Vector3(-52f, 0f, -132f), 10f),
            new PoiInfo("lk_market_junction", "Market Junction",    new Vector3(-80f, 0f, -78f),  10f),
            // ---- COMPUTER VILLAGE (offset 90,-90) ----
            new PoiInfo("cv_tech_plaza",      "Tech Plaza",         new Vector3(90f, 0f, -110f),  12f),
            new PoiInfo("cv_phone_row",       "Phone Row",          new Vector3(50f, 0f, -82f),   10f),
            new PoiInfo("cv_repair_lane",     "Repair Lane",        new Vector3(130f, 0f, -82f),  10f),
            new PoiInfo("cv_gadget_mall",     "Gadget Mall",        new Vector3(90f, 0f, -117f),  12f),
            // ---- DOWNTOWN (offset 270,-90) ----
            new PoiInfo("dt_nova_tower",      "Nova Tower",         new Vector3(230f, 0f, -122f), 12f),
            new PoiInfo("dt_plaza",           "Plaza",              new Vector3(300f, 0f, -50f),  12f),
            new PoiInfo("dt_rooftop_row",     "Rooftop Row",        new Vector3(230f, 28.8f, -122f),10f),
            // ---- MAKOKO (offset -270,90) ----
            new PoiInfo("mk_main_dock",       "Main Dock",          new Vector3(-270f, 0f, 140f), 12f),
            new PoiInfo("mk_market_row",      "Market Row",         new Vector3(-312f, 0f, 84f),  12f),
            new PoiInfo("mk_old_shrine",      "Old Shrine",         new Vector3(-224f, 0f, 50f),  10f),
            new PoiInfo("mk_canoe_yard",      "Canoe Yard",         new Vector3(-280f, 0f, 44f),   10f),
            // ---- BANANA ISLAND (offset -90,90) ----
            new PoiInfo("bi_marina_bay",      "Marina Bay",         new Vector3(-128f, 0f, 130f), 12f),
            new PoiInfo("bi_sky_villa",       "Sky Villa",          new Vector3(-56f, 0f, 58f),   12f),
            new PoiInfo("bi_palm_boulevard",  "Palm Boulevard",     new Vector3(-90f, 0f, 80f),   12f),
            new PoiInfo("bi_yacht_club",      "Yacht Club",         new Vector3(-140f, 0f, 111f), 10f),
            // ---- SHIP PORT (offset 90,90) ----
            new PoiInfo("sp_container_yard",  "Container Yard",     new Vector3(83f, 0f, 100f),   15f),
            new PoiInfo("sp_crane_row",       "Crane Row",          new Vector3(122f, 0f, 85f),   12f),
            new PoiInfo("sp_the_ship",        "The Ship",           new Vector3(149f, 4f, 80f),   15f),
            new PoiInfo("sp_warehouses",      "Warehouses",         new Vector3(38f, 0f, 83f),    12f),
            // ---- LAGOON BRIDGE (offset 270,90) ----
            new PoiInfo("lb_toll_plaza",      "Toll Plaza",         new Vector3(240f, 6f, 90f),   10f),
            new PoiInfo("lb_mid_span",        "Mid-Span",           new Vector3(270f, 6f, 90f),   10f),
            new PoiInfo("lb_north_landing",   "North Landing",      new Vector3(210f, 6f, 90f),   10f),
            new PoiInfo("lb_south_dock",      "South Dock",         new Vector3(331f, 0.2f, 112f),10f),
            // ---- DAM (offset -270,270) ----
            new PoiInfo("dm_dam_crest",       "Dam Crest",          new Vector3(-270f, 24f, 225f), 12f),
            new PoiInfo("dm_control_room",    "Control Room",       new Vector3(-298f, 0f, 286f), 10f),
            new PoiInfo("dm_spillway",        "Spillway",           new Vector3(-270f, 0.2f, 237f),10f),
            // ---- STADIUM (offset -90,270) ----
            new PoiInfo("st_the_pitch",       "The Pitch",          new Vector3(-90f, 0f, 270f),  15f),
            new PoiInfo("st_north_stand",     "North Stand",        new Vector3(-90f, 12f, 220f), 12f),
            new PoiInfo("st_concourse",       "Concourse",          new Vector3(-45.5f, 0.15f, 270f),10f),
        };

        public static PoiInfo Get(string id)
        {
            for (int i = 0; i < Pois.Length; i++)
                if (Pois[i].Id == id) return Pois[i];
            return default;
        }

        /// <summary>World-space origin of a region by name.</summary>
        public static Vector3 RegionOrigin(string name)
        {
            for (int i = 0; i < Regions.Length; i++)
                if (Regions[i].Name == name)
                    return new Vector3(Regions[i].Offset.x, 0f, Regions[i].Offset.y);
            return Vector3.zero;
        }
    }
}
