using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>
    /// The 14 Lagos districts that form the ONE continuous NOVA WORLD (no map select;
    /// regions are never standalone). Each builder works in region-local space
    /// (origin at the district center) and mirrors its Godot region script's layout:
    /// signature landmarks at faithful positions/dimensions, POI loot rings, and
    /// spawn points. WorldBuilder offsets everything into world space.
    /// Detail counts (props, scatter) are reduced vs Godot for mobile draw-call
    /// budgets; landmarks and gameplay geometry are faithful.
    /// </summary>
    public static partial class RegionBuilders
    {
        // ---------------- shared small builders ----------------

        private static void Walkway(RegionContext ctx, Vector3 a, Vector3 b, float width)
        {
            Vector3 dv = b - a; dv.y = 0f;
            float len = dv.magnitude;
            if (len < 0.5f) return;
            float yaw = Mathf.Atan2(dv.x, dv.z) * Mathf.Rad2Deg;
            Vector3 mid = (a + b) * 0.5f; mid.y = 0.15f;
            var m = Matrix4x4.TRS(mid, Quaternion.Euler(0f, yaw, 0f), Vector3.one);
            ctx.Batch.Box(new Vector3(width, 0.12f, len), m, ctx.Mats.Wood, Color.white, true);
            int n = Mathf.Max(2, Mathf.RoundToInt(len / 3f));
            for (int i = 0; i <= n; i++)
            {
                Vector3 p = a + dv * (i / (float)n);
                ctx.Batch.Cylinder(0.09f, 2.2f, 8,
                    Matrix4x4.TRS(new Vector3(p.x, -0.7f, p.z), Quaternion.identity, Vector3.one),
                    ctx.Mats.WoodDark, Color.white);
            }
        }

        private static void Canoe(RegionContext ctx, Vector3 pos, float yawDeg)
        {
            var f = Matrix4x4.TRS(pos, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);
            var t = Matrix4x4.identity;
            ctx.Batch.Box(new Vector3(0.9f, 0.45f, 3.2f), f * t, ctx.Mats.WoodDark, Color.white);
            foreach (float s in new[] { 1f, -1f })
            {
                var end = f * Matrix4x4.TRS(new Vector3(0f, 0.1f, s * 1.9f),
                    Quaternion.AngleAxis(s * -18f, Vector3.right), Vector3.one);
                ctx.Batch.Box(new Vector3(0.7f, 0.35f, 1.0f), end, ctx.Mats.WoodDark, Color.white);
            }
            ctx.Batch.Box(new Vector3(0.7f, 0.08f, 0.3f),
                f * Matrix4x4.TRS(new Vector3(0f, 0.28f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.Wood, Color.white);
        }

        private static Building House(RegionContext ctx, Vector3 pos, float yawDeg,
            float w, float d, int floors, Color wall)
        {
            var spec = BuildingSpec.House(w, d, floors, wall, ctx.Ri(1, 1000000));
            var b = BuildingFactory.Build(ctx.Batch, spec, ctx.Root, pos, yawDeg, ctx.Mats, ctx.Rng);
            ctx.HousePositions.Add(pos);
            return b;
        }

        private static void DockPlatform(RegionContext ctx, Vector3 pos, float w, float d)
        {
            var t = Matrix4x4.identity;
            ctx.Batch.Box(new Vector3(w, 0.18f, d),
                Matrix4x4.TRS(pos + new Vector3(0f, 0.05f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.Wood, Color.white, true);
            for (int ix = -1; ix <= 1; ix++)
                for (int iz = -1; iz <= 1; iz++)
                    ctx.Batch.Cylinder(0.11f, 2.0f, 8,
                        Matrix4x4.TRS(pos + new Vector3(ix * w * 0.4f, -0.8f, iz * d * 0.4f),
                            Quaternion.identity, Vector3.one), ctx.Mats.WoodDark, Color.white);
        }

        // ================= MAKOKO — stilt village on the lagoon =================

        public static void BuildMakoko(RegionContext ctx)
        {
            RegionKit.WaterPlane(ctx, 150f, 150f, new Vector3(0f, -1f, 0f));
            Vector2[] clusters = {
                new Vector2(-32f, -30f), new Vector2(30f, -30f), new Vector2(-30f, 30f),
                new Vector2(32f, 32f), new Vector2(0f, 2f)
            };
            Color[] wallCols = {
                new Color(0.72f, 0.55f, 0.36f), new Color(0.62f, 0.60f, 0.58f),
                new Color(0.68f, 0.50f, 0.33f)
            };
            var placed = new System.Collections.Generic.List<Vector3>();
            for (int ci = 0; ci < clusters.Length; ci++)
            {
                int count = 0, attempts = 0;
                Vector3 prev = default; bool hasPrev = false;
                while (count < 6 && attempts < 30)
                {
                    attempts++;
                    float a = ctx.Rf() * Mathf.PI * 2f;
                    float r = ctx.RfRange(4f, 16f);
                    Vector3 p = new Vector3(clusters[ci].x + Mathf.Cos(a) * r, 0f,
                        clusters[ci].y + Mathf.Sin(a) * r);
                    if (Mathf.Abs(p.x) > 58f || Mathf.Abs(p.z) > 58f) continue;
                    bool ok = true;
                    foreach (var h in placed)
                        if (Vector3.Distance(h, p) < 8f) { ok = false; break; }
                    if (!ok) continue;
                    placed.Add(p);
                    float yaw = Mathf.Atan2(clusters[ci].x - p.x, clusters[ci].y - p.z) * Mathf.Rad2Deg;
                    var spec = BuildingSpec.House(ctx.RfRange(4.2f, 5.8f), ctx.RfRange(4.2f, 5.8f),
                        ctx.Rf() < 0.4f ? 2 : 1, ctx.Pick(wallCols), ctx.Ri(1, 1000000));
                    spec.Stilts = true;
                    BuildingFactory.Build(ctx.Batch, spec, ctx.Root, p, yaw, ctx.Mats, ctx.Rng);
                    ctx.HousePositions.Add(p);
                    if (hasPrev && Vector3.Distance(prev, p) < 18f) Walkway(ctx, prev, p, 1.7f);
                    prev = p; hasPrev = true;
                    count++;
                }
            }
            // Link cluster centers (port of _build_links).
            for (int ci = 0; ci < 4; ci++)
                Walkway(ctx, new Vector3(clusters[ci].x, 0f, clusters[ci].y),
                    new Vector3(clusters[4].x, 0f, clusters[4].y), 2.2f);

            // POIs.
            DockPlatform(ctx, new Vector3(0f, 0f, 50f), 12f, 8f);            // Main Dock
            for (int i = 0; i < 4; i++)
                RegionKit.CrateStack(ctx, new Vector3(-4f + i * 2.2f, 0.1f, 47.5f), ctx.RfRange(1f, 1.4f));
            for (int i = 0; i < 3; i++)
                Canoe(ctx, new Vector3(-8f + i * 3f, -0.85f, 57.5f), ctx.Rf() * 360f);
            ctx.PlayerSpawn = new Vector3(0f, 0.6f, 52f);

            DockPlatform(ctx, new Vector3(-42f, 0f, -6f), 24f, 7f);          // Market Row
            for (int i = 0; i < 5; i++)
                RegionKit.Stall(ctx, new Vector3(-51f + i * 4.5f, 0.15f, -5.5f), ctx.RfRange(-6f, 6f));

            House(ctx, new Vector3(46f, 0f, -38f), 0f, 5f, 5f, 1,           // Old Shrine
                new Color(0.70f, 0.42f, 0.25f));

            DockPlatform(ctx, new Vector3(-10f, 0f, -46f), 10f, 6f);         // Canoe Yard
            for (int i = 0; i < 3; i++)
                Canoe(ctx, new Vector3(-13f + i * 3f, -0.85f, -46f), 90f + ctx.RfRange(-10f, 10f));
            for (int i = 0; i < 4; i++)
                RegionKit.Palm(ctx, ctx.RfRange(-60f, 60f), ctx.RfRange(-60f, 60f), -0.9f);

            foreach (var poi in new[] {
                new Vector3(0f, 0f, 50f), new Vector3(-42f, 0f, -6f),
                new Vector3(46f, 0f, -40f), new Vector3(-10f, 0f, -46f) })
                ctx.AddLootRing(poi, 0.65f, 6, 2);

            ctx.EnemySpawns.Add(new Vector3(-30f, 0.6f, -30f));
            ctx.EnemySpawns.Add(new Vector3(30f, 0.6f, 30f));
        }

        // ================= LEKKI — upscale urban, cable-stayed bridge =================

        public static void BuildLekki(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -50f, 70f, 0f, ctx.Mats.Concrete, Color.white);
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, -62f, 0f, ctx.Mats.Sidewalk, Color.white);
            RegionKit.WaterPlane(ctx, 140f, 12f, new Vector3(0f, -0.9f, -56f)); // lagoon channel
            // Parapet walls along the channel (gap at the bridge x in [34,42]).
            foreach (float ze in new[] { -50f, -62f })
            {
                RegionKit.Box(ctx, new Vector3(104f, 1.5f, 0.4f), new Vector3(-18f, -0.35f, ze),
                    ctx.Mats.ConcreteDark, Color.white, true);
                RegionKit.Box(ctx, new Vector3(28f, 1.5f, 0.4f), new Vector3(56f, -0.35f, ze),
                    ctx.Mats.ConcreteDark, Color.white, true);
            }
            // Streets.
            RegionKit.RoadStrip(ctx, -66f, 66f, 6f, 18f);          // Admiralty Way (z=12)
            RegionKit.RoadStrip(ctx, -22.5f, -13.5f, -50f, 66f);   // cross street B
            RegionKit.RoadStrip(ctx, 33.5f, 42.5f, -50f, 66f);     // cross street C -> bridge
            // Roundabout monument at (10,12).
            RegionKit.Cyl(ctx, 4.6f, 0.35f, new Vector3(10f, 0.1f, 12f), ctx.Mats.Curb, Color.white);
            ctx.Batch.Collider(new Vector3(8.6f, 0.5f, 8.6f), new Vector3(10f, 0.1f, 12f), Quaternion.identity);
            RegionKit.Box(ctx, new Vector3(2.2f, 0.5f, 2.2f), new Vector3(10f, 0.5f, 12f),
                ctx.Mats.ConcreteDark, Color.white, true);
            RegionKit.Box(ctx, new Vector3(1.4f, 3.2f, 1.4f), new Vector3(10f, 2.3f, 12f),
                ctx.Mats.Wall, new Color(0.85f, 0.80f, 0.70f), true);
            // Cable-stayed bridge over the channel at x=38 (Lekki-Ikoyi style).
            {
                float bx = 38f;
                RegionKit.Box(ctx, new Vector3(7f, 0.9f, 16f), new Vector3(bx, -0.45f, -56f),
                    ctx.Mats.AsphaltPlain, Color.white, true);
                foreach (float sx in new[] { -1f, 1f })
                {
                    // inclined pylon legs meeting at the top
                    BuildingFactory.Strut(ctx.Batch,
                        new Vector3(bx + sx * 3f, 0f, -56f), new Vector3(bx, 17f, -56f),
                        0.8f, 0.8f, ctx.Mats.Concrete, Color.white);
                    // stay cables fan to the deck
                    for (int i = 0; i < 4; i++)
                    {
                        float dz = -62f + i * 4f;
                        BuildingFactory.Strut(ctx.Batch,
                            new Vector3(bx, 16f, -56f), new Vector3(bx + sx * 2.8f, 0.2f, dz),
                            0.07f, 0.07f, ctx.Mats.Metal, Color.white);
                    }
                    RegionKit.Box(ctx, new Vector3(0.25f, 1f, 16f),
                        new Vector3(bx + sx * 3.4f, 0.5f, -56f), ctx.Mats.Concrete, Color.white, true);
                }
            }
            // Shop rows along the avenue.
            string[] signs = { "MARKET", "PHARMACY", "EATERY", "BANK", "SALON", "PLAZA",
                "STORES", "CAFE", "TECH HUB", "BAKERY", "BARBER", "BOOKS" };
            Color[] signCols = {
                new Color(0.78f, 0.12f, 0.10f), new Color(0.10f, 0.30f, 0.68f),
                new Color(0.90f, 0.72f, 0.10f), new Color(0.12f, 0.55f, 0.25f)
            };
            int si = 0;
            for (int i = 0; i < 4; i++)
            {
                float x = -48f + i * 14f;
                var specN = BuildingSpec.Shop(9f, 6f, 2, new Color(0.85f, 0.81f, 0.73f),
                    ctx.Ri(1, 1000000), signs[si % signs.Length], signCols[si % signCols.Length]);
                BuildingFactory.Build(ctx.Batch, specN, ctx.Root, new Vector3(x, 0f, 24f), 180f,
                    ctx.Mats, ctx.Rng); si++;
                var specS = BuildingSpec.Shop(9f, 6f, 1, new Color(0.88f, 0.87f, 0.84f),
                    ctx.Ri(1, 1000000), signs[si % signs.Length], signCols[si % signCols.Length]);
                BuildingFactory.Build(ctx.Batch, specS, ctx.Root, new Vector3(x + 5f, 0f, -2f), 0f,
                    ctx.Mats, ctx.Rng); si++;
            }
            // Admiralty Mall (POI): big 2-floor retail block.
            var mall = BuildingSpec.Shop(22f, 12f, 2, new Color(0.80f, 0.78f, 0.74f),
                ctx.Ri(1, 1000000), "ADMIRALTY MALL", new Color(0.15f, 0.35f, 0.70f));
            BuildingFactory.Build(ctx.Batch, mall, ctx.Root, new Vector3(-42f, 0f, 30f), 0f,
                ctx.Mats, ctx.Rng);
            // Estate houses.
            for (int i = 0; i < 6; i++)
                House(ctx, new Vector3(-50f + i * 20f, 0f, 44f + (i % 2) * 8f), 180f,
                    ctx.RfRange(7f, 9f), ctx.RfRange(6f, 8f), 2,
                    new Color(0.85f, 0.80f, 0.70f));
            // Office tower.
            var tower = BuildingSpec.Tower(14f, 14f, 5, new Color(0.75f, 0.78f, 0.82f),
                ctx.Ri(1, 1000000), false);
            BuildingFactory.Build(ctx.Batch, tower, ctx.Root, new Vector3(-20f, 0f, -28f), 0f,
                ctx.Mats, ctx.Rng);
            // Props.
            for (float x = -60f; x <= 60f; x += 20f)
            {
                RegionKit.Streetlight(ctx, new Vector3(x, 0f, 20f), 180f);
                RegionKit.Streetlight(ctx, new Vector3(x + 10f, 0f, 4f), 0f);
            }
            for (int i = 0; i < 6; i++)
                RegionKit.Car(ctx, new Vector3(-55f + i * 22f, 0.06f, 12f + (i % 2 == 0 ? 3.5f : -3.5f)),
                    i % 2 == 0 ? 90f : -90f, ctx.Pick(new[] {
                        Color.white, Color.black, new Color(0.7f, 0.1f, 0.1f), new Color(0.1f, 0.2f, 0.5f) }));
            for (int i = 0; i < 10; i++)
                RegionKit.Palm(ctx, ctx.RfRange(-64f, 64f), ctx.RfRange(24f, 60f));

            foreach (var poi in new[] {
                new Vector3(-42f, 0f, 30f), new Vector3(48f, 0f, 40f),
                new Vector3(38f, 0f, -42f), new Vector3(10f, 0f, 12f) })
                ctx.AddLootRing(poi, 0.55f, 6, 2);

            ctx.PlayerSpawn = new Vector3(10f, 0.6f, 31f);
            ctx.EnemySpawns.Add(new Vector3(-40f, 0.6f, -20f));
            ctx.EnemySpawns.Add(new Vector3(40f, 0.6f, 40f));
        }

        // ================= COMPUTER VILLAGE — tech market =================

        public static void BuildComputerVillage(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Concrete, Color.white);
            // Main street (Otigba St) + cross streets.
            RegionKit.RoadStrip(ctx, -66f, 66f, 5f, 11f);
            RegionKit.RoadStrip(ctx, -23f, -17f, -50f, 60f);
            RegionKit.RoadStrip(ctx, 17f, 23f, -50f, 60f);
            // Entry arch "COMPUTER VILLAGE".
            {
                float ax = -62f;
                foreach (float sz in new[] { -1f, 1f })
                    RegionKit.Box(ctx, new Vector3(0.8f, 7f, 0.8f),
                        new Vector3(ax, 3.5f, 8f + sz * 4.2f), ctx.Mats.Trim, Color.white, true);
                RegionKit.Box(ctx, new Vector3(0.9f, 1.4f, 11f), new Vector3(ax, 7.2f, 8f),
                    ctx.Mats.Trim, Color.white);
                RegionKit.Box(ctx, new Vector3(0.94f, 1.1f, 10.6f), new Vector3(ax, 7.2f, 8f),
                    ctx.Mats.Emissive, new Color(0.78f, 0.12f, 0.10f));
                // hanging banners across the street
                foreach (float bx in new[] { -40f, 0f, 40f })
                {
                    RegionKit.Box(ctx, new Vector3(4.6f, 0.9f, 0.06f), new Vector3(bx, 5.6f, 8f),
                        ctx.Mats.Emissive, ctx.Pick(new[] {
                            new Color(0.78f, 0.12f, 0.10f), new Color(0.10f, 0.30f, 0.68f),
                            new Color(0.90f, 0.72f, 0.10f) }));
                }
            }
            // Shop rows: north side (front z=11, facing -z), south side (front z=5, facing +z).
            string[] signs = { "TECH HUB", "PHONE CLINIC", "LAPTOP WORLD", "GADGET PLAZA",
                "MOBILE ZONE", "SIM & REPAIR", "DATA KING", "PHONE PALACE", "SCREEN FIX",
                "CHARGE POINT", "TABLET TOWN", "SOUND WAVE" };
            Color[] signCols = {
                new Color(0.78f, 0.12f, 0.10f), new Color(0.10f, 0.10f, 0.12f),
                new Color(0.10f, 0.30f, 0.68f), new Color(0.90f, 0.72f, 0.10f),
                new Color(0.12f, 0.55f, 0.25f)
            };
            int si = 0;
            float[][] segs = { new[] { -58f, -28f }, new[] { -10f, 10f }, new[] { 30f, 58f } };
            foreach (var s in segs)
            {
                for (float x = s[0]; x + 6f <= s[1]; x += 7.5f)
                {
                    var n = BuildingSpec.Shop(6f, 4.5f, 2, new Color(0.84f, 0.80f, 0.72f),
                        ctx.Ri(1, 1000000), signs[si % signs.Length], signCols[si % signCols.Length]);
                    BuildingFactory.Build(ctx.Batch, n, ctx.Root, new Vector3(x + 3f, 0f, 15.5f), 180f,
                        ctx.Mats, ctx.Rng); si++;
                    var st = BuildingSpec.Shop(6f, 4.5f, 2, new Color(0.80f, 0.78f, 0.74f),
                        ctx.Ri(1, 1000000), signs[si % signs.Length], signCols[si % signCols.Length]);
                    BuildingFactory.Build(ctx.Batch, st, ctx.Root, new Vector3(x + 3f, 0f, 0.5f), 0f,
                        ctx.Mats, ctx.Rng); si++;
                }
            }
            // Tech Plaza (patterned paving) + Gadget Mall.
            RegionKit.Box(ctx, new Vector3(28f, 0.1f, 20f), new Vector3(0f, 0.0f, -20f),
                ctx.Mats.Sidewalk, Color.white);
            var mall = BuildingSpec.Shop(24f, 14f, 2, new Color(0.82f, 0.80f, 0.76f),
                ctx.Ri(1, 1000000), "GADGET MALL", new Color(0.10f, 0.30f, 0.68f));
            BuildingFactory.Build(ctx.Batch, mall, ctx.Root, new Vector3(0f, 0f, -38f), 0f,
                ctx.Mats, ctx.Rng);
            // Warehouses.
            var wh1 = BuildingSpec.Warehouse(16f, 10f, new Color(0.70f, 0.68f, 0.64f), ctx.Ri(1, 1000000));
            BuildingFactory.Build(ctx.Batch, wh1, ctx.Root, new Vector3(-45f, 0f, -42f), 0f, ctx.Mats, ctx.Rng);
            var wh2 = BuildingSpec.Warehouse(16f, 10f, new Color(0.66f, 0.64f, 0.60f), ctx.Ri(1, 1000000));
            BuildingFactory.Build(ctx.Batch, wh2, ctx.Root, new Vector3(45f, 0f, -42f), 0f, ctx.Mats, ctx.Rng);
            // Props: utility poles, crates, keke (3-wheel taxi boxes).
            for (float x = -56f; x <= 56f; x += 16f)
            {
                RegionKit.Cyl(ctx, 0.12f, 7f, new Vector3(x, 3.5f, 13.5f), ctx.Mats.WoodDark, Color.white);
                if (ctx.Rf() < 0.6f) RegionKit.CrateStack(ctx, new Vector3(x + 3f, 0f, 14.5f));
            }
            for (int i = 0; i < 3; i++)
            {
                var f = Matrix4x4.TRS(new Vector3(-30f + i * 30f, 0f, 8f),
                    Quaternion.Euler(0f, 90f, 0f), Vector3.one);
                ctx.Batch.Box(new Vector3(1.4f, 1.1f, 2.6f), f, ctx.Mats.ContainerYellow, Color.white, true);
                ctx.Batch.Box(new Vector3(1.2f, 0.7f, 1.2f),
                    f * Matrix4x4.TRS(new Vector3(0f, 1.6f, 0.2f), Quaternion.identity, Vector3.one),
                    ctx.Mats.Trim, Color.white);
            }

            foreach (var poi in new[] {
                new Vector3(0f, 0f, -20f), new Vector3(-40f, 0f, 8f),
                new Vector3(40f, 0f, 8f), new Vector3(0f, 0f, -27f) })
                ctx.AddLootRing(poi, 0.55f, 6, 2);

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, 40f);
            ctx.EnemySpawns.Add(new Vector3(-50f, 0.6f, -30f));
            ctx.EnemySpawns.Add(new Vector3(50f, 0.6f, 30f));
        }

        // ================= BANANA ISLAND — luxury waterfront =================

        public static void BuildBananaIsland(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Grass, Color.white);
            // Lagoon water on the south + east edges.
            RegionKit.WaterPlane(ctx, 150f, 40f, new Vector3(0f, -0.55f, 85f));
            RegionKit.WaterPlane(ctx, 40f, 150f, new Vector3(85f, -0.55f, 0f));
            // Marina: docks + yachts.
            for (int i = 0; i < 3; i++)
            {
                float dx = -52f + i * 14f;
                DockPlatform(ctx, new Vector3(dx, 0f, 62f), 4f, 22f);
                // yacht: hull + cabin
                var f = Matrix4x4.TRS(new Vector3(dx + 4.5f, -0.2f, 62f),
                    Quaternion.Euler(0f, 90f, 0f), Vector3.one);
                var t = Matrix4x4.identity;
                ctx.Batch.Box(new Vector3(2.6f, 1.2f, 9f), f * t, ctx.Mats.Metal,
                    ctx.Pick(new[] { Color.white, new Color(0.1f, 0.15f, 0.35f), new Color(0.7f, 0.1f, 0.1f) }));
                ctx.Batch.Box(new Vector3(2.0f, 1.1f, 3.5f),
                    f * Matrix4x4.TRS(new Vector3(0f, 1.1f, -0.5f), Quaternion.identity, Vector3.one),
                    ctx.Mats.GlassDark, Color.white);
            }
            // Villas (large 2-floor houses).
            string[] villaSpots = { "-30,-20", "10,-34", "-8,8", "30,4" };
            foreach (var vs in villaSpots)
            {
                var xy = vs.Split(',');
                float vx = float.Parse(xy[0]), vz = float.Parse(xy[1]);
                House(ctx, new Vector3(vx, 0f, vz), ctx.Rf() * 360f, 11f, 9f, 2,
                    new Color(0.90f, 0.87f, 0.80f));
                // patio slab
                RegionKit.Box(ctx, new Vector3(6f, 0.15f, 5f), new Vector3(vx + 8f, 0.07f, vz),
                    ctx.Mats.Sidewalk, Color.white, true);
            }
            // Sky Villa signature glass tower: 7 floors + helipad.
            var tower = BuildingSpec.Tower(16f, 16f, 7, new Color(0.80f, 0.86f, 0.92f),
                ctx.Ri(1, 1000000), true);
            BuildingFactory.Build(ctx.Batch, tower, ctx.Root, new Vector3(34f, 0f, -32f), 0f,
                ctx.Mats, ctx.Rng);
            // Yacht club.
            var club = BuildingSpec.Shop(12f, 8f, 2, new Color(0.88f, 0.85f, 0.78f),
                ctx.Ri(1, 1000000), "YACHT CLUB", new Color(0.10f, 0.30f, 0.60f));
            BuildingFactory.Build(ctx.Batch, club, ctx.Root, new Vector3(-50f, 0f, 21f), 90f,
                ctx.Mats, ctx.Rng);
            // Palm boulevard.
            RegionKit.RoadStrip(ctx, -60f, 60f, -13f, -7f);
            for (float x = -56f; x <= 56f; x += 8f)
            {
                RegionKit.Palm(ctx, x, -16f);
                RegionKit.Palm(ctx, x + 4f, -4f);
            }
            // Monument + promenade lamps + cars.
            RegionKit.Box(ctx, new Vector3(2f, 6f, 2f), new Vector3(0f, 3f, -10f),
                ctx.Mats.Concrete, Color.white, true);
            RegionKit.Box(ctx, new Vector3(3f, 0.6f, 3f), new Vector3(0f, 0.3f, -10f),
                ctx.Mats.ConcreteDark, Color.white, true);
            for (float x = -48f; x <= 48f; x += 16f)
                RegionKit.Streetlight(ctx, new Vector3(x, 0f, -7f), 0f, 6f);
            for (int i = 0; i < 5; i++)
                RegionKit.Car(ctx, new Vector3(-40f + i * 20f, 0.06f, -10f), 90f,
                    ctx.Pick(new[] { Color.black, Color.white, new Color(0.7f, 0.7f, 0.72f) }));

            foreach (var poi in new[] {
                new Vector3(-38f, 0f, 40f), new Vector3(34f, 0f, -32f),
                new Vector3(0f, 0f, -10f), new Vector3(-50f, 0f, 21f) })
                ctx.AddLootRing(poi, 0.55f, 6, 2);

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, 30f);
            ctx.EnemySpawns.Add(new Vector3(-40f, 0.6f, -40f));
            ctx.EnemySpawns.Add(new Vector3(40f, 0.6f, 20f));
        }

        // ================= VALLEY — hills, river, ruins =================

        private static readonly Vector2[] RiverCtrl = {
            new Vector2(-52f, -68f), new Vector2(-34f, -46f), new Vector2(-12f, -24f),
            new Vector2(4f, -2f), new Vector2(-4f, 22f), new Vector2(-24f, 44f),
            new Vector2(-40f, 68f)
        };

        private static float DistToRiver(float x, float z)
        {
            float best = 1e9f;
            for (int s = 0; s < RiverCtrl.Length - 1; s++)
            {
                Vector2 a = RiverCtrl[s], b = RiverCtrl[s + 1];
                Vector2 ab = b - a;
                float t = Mathf.Clamp01(Vector2.Dot(new Vector2(x - a.x, z - a.y), ab) / ab.sqrMagnitude);
                Vector2 p = a + ab * t;
                float d = Vector2.Distance(new Vector2(x, z), p);
                if (d < best) best = d;
            }
            return best;
        }

        private static float ValleyHeight(float x, float z)
        {
            float h = 3f;
            h += Mathf.Sin(x * 0.11f) * Mathf.Cos(z * 0.13f) * 1.5f;
            float[][] hills = {
                new[] { 40f, -44f, 11f, 24f }, new[] { -48f, -12f, 9f, 22f },
                new[] { 34f, 40f, 8f, 20f }
            };
            foreach (var hl in hills)
            {
                float dx = x - hl[0], dz = z - hl[1];
                h += hl[2] * Mathf.Exp(-(dx * dx + dz * dz) / (hl[3] * hl[3]));
            }
            float dr = DistToRiver(x, z);
            h -= 3.5f * (1f - Mathf.Clamp01(dr / 25f)); // broad valley carve
            if (dr < 5f) h = Mathf.Min(h, -0.4f);       // riverbed
            return h;
        }

        public static void BuildValley(RegionContext ctx)
        {
            // Displaced terrain grid (10m cells).
            const float cell = 10f;
            for (float x = -70f; x < 70f; x += cell)
            {
                for (float z = -70f; z < 70f; z += cell)
                {
                    Vector3 a = new Vector3(x, ValleyHeight(x, z), z);
                    Vector3 b = new Vector3(x + cell, ValleyHeight(x + cell, z), z);
                    Vector3 c = new Vector3(x + cell, ValleyHeight(x + cell, z + cell), z + cell);
                    Vector3 d = new Vector3(x, ValleyHeight(x, z + cell), z + cell);
                    float hAvg = (a.y + b.y + c.y + d.y) * 0.25f;
                    Color tint = hAvg > 6f
                        ? new Color(0.75f, 0.72f, 0.65f)   // rocky peaks
                        : new Color(0.95f, 1f, 0.9f);
                    ctx.Batch.TerrainQuad(a, b, c, d, tint, tint, tint, tint, ctx.Mats.Grass);
                    if (DistToRiver(x + cell * 0.5f, z + cell * 0.5f) < 4.5f)
                        RegionKit.WaterPlane(ctx, cell, cell,
                            new Vector3(x + cell * 0.5f, 0.25f, z + cell * 0.5f));
                }
            }
            // Bridge over the river at the crossing POI (-8,-22).
            {
                Vector3 p0 = new Vector3(-16f, 0f, -30f), p1 = new Vector3(0f, 0f, -14f);
                Vector3 dv = p1 - p0; dv.y = 0f;
                float len = dv.magnitude;
                float yaw = Mathf.Atan2(dv.x, dv.z) * Mathf.Rad2Deg;
                float gy = ValleyHeight(-8f, -22f) + 1.2f;
                var m = Matrix4x4.TRS(new Vector3(-8f, gy, -22f),
                    Quaternion.Euler(0f, yaw, 0f), Vector3.one);
                ctx.Batch.Box(new Vector3(3.5f, 0.4f, len), m, ctx.Mats.Wood, Color.white, true);
                foreach (float s in new[] { -1f, 1f })
                    ctx.Batch.Box(new Vector3(0.15f, 1f, len),
                        m * Matrix4x4.TRS(new Vector3(s * 1.7f, 0.7f, 0f), Quaternion.identity, Vector3.one),
                        ctx.Mats.WoodDark, Color.white, true);
            }
            // Watchtowers, ruins, sandbags, camp.
            RegionKit.Watchtower(ctx, 40f, -44f, 0f);
            RegionKit.Watchtower(ctx, -48f, -12f, 90f);
            for (int i = 0; i < 3; i++)
            {
                float rx = 20f + i * 8f - 8f, rz = -34f + (i % 2) * 10f;
                float ry = ValleyHeight(rx, rz);
                // ruined compound: broken wall stubs
                for (int k = 0; k < 5; k++)
                    RegionKit.Box(ctx, new Vector3(ctx.RfRange(2f, 4f), ctx.RfRange(0.8f, 2f), 0.4f),
                        new Vector3(rx + ctx.RfRange(-4f, 4f), ry + 0.5f, rz + ctx.RfRange(-4f, 4f)),
                        ctx.Mats.ConcreteDark, Color.white, true, ctx.Rf() * 180f);
                ctx.AddLoot("ammo", 60, new Vector3(rx, ry + 0.55f, rz), 2);
            }
            RegionKit.SandbagWall(ctx, -8f, -18f, 20f);
            RegionKit.SandbagWall(ctx, -12f, 8f, -30f);
            // Valley camp: tents + campfire.
            for (int i = 0; i < 3; i++)
            {
                Vector3 tp = new Vector3(-18f + i * 5f, 0f, 8f);
                tp.y = ValleyHeight(tp.x, tp.z);
                var tm = Matrix4x4.TRS(tp, Quaternion.Euler(0f, i * 40f, 0f), Vector3.one);
                foreach (float s in new[] { -1f, 1f })
                    ctx.Batch.Box(new Vector3(3f, 0.12f, 2.6f),
                        tm * Matrix4x4.TRS(new Vector3(0f, 1.05f, s * 1.05f),
                            Quaternion.AngleAxis(s * -38f, Vector3.right), Vector3.one),
                        ctx.Mats.Wood, new Color(0.55f, 0.45f, 0.30f));
                ctx.Batch.Collider(new Vector3(2.6f, 1.8f, 2.6f),
                    tm * Matrix4x4.TRS(new Vector3(0f, 0.9f, 0f), Quaternion.identity, Vector3.one));
            }
            {
                Vector3 fp = new Vector3(-14f, ValleyHeight(-14f, 14f), 14f);
                for (int i = 0; i < 6; i++)
                {
                    float a = Mathf.PI * 2f * i / 6f;
                    ctx.Batch.Rock(new Vector3(0.5f, 0.4f, 0.5f),
                        Matrix4x4.TRS(fp + new Vector3(Mathf.Cos(a) * 0.8f, 0.2f, Mathf.Sin(a) * 0.8f),
                            Quaternion.identity, Vector3.one), ctx.Mats.RockM, Color.white);
                }
                RegionKit.Box(ctx, new Vector3(0.4f, 0.3f, 0.4f), fp + new Vector3(0f, 0.35f, 0f),
                    ctx.Mats.Emissive, new Color(1f, 0.5f, 0.15f));
            }
            // Vegetation + rocks scatter (density steps down on Low).
            float density = WorldQuality.ScatterScale;
            for (int i = 0; i < 60 * density; i++)
            {
                float x = ctx.RfRange(-68f, 68f), z = ctx.RfRange(-68f, 68f);
                if (DistToRiver(x, z) < 7f) continue;
                float r = ctx.Rf();
                if (r < 0.45f) RegionKit.Tree(ctx, x, z, ValleyHeight(x, z));
                else if (r < 0.65f)
                {
                    float s = ctx.RfRange(1.2f, 2.6f);
                    ctx.Batch.Rock(new Vector3(s, s * 0.7f, s),
                        Matrix4x4.TRS(new Vector3(x, ValleyHeight(x, z) + s * 0.3f, z),
                            Quaternion.identity, Vector3.one),
                        ctx.Mats.RockM, Color.white, true, 0.3f);
                }
            }

            foreach (var poi in new[] {
                new Vector3(40f, 0f, -44f), new Vector3(-8f, 0f, -22f),
                new Vector3(-14f, 0f, 8f), new Vector3(20f, 0f, -34f) })
                ctx.AddLootRing(new Vector3(poi.x, ValleyHeight(poi.x, poi.z) + 0.55f, poi.z), 0f, 6, 2);

            ctx.PlayerSpawn = new Vector3(-18f, ValleyHeight(-18f, 12f) + 0.6f, 12f);
            ctx.EnemySpawns.Add(new Vector3(30f, ValleyHeight(30f, -30f) + 0.6f, -30f));
            ctx.EnemySpawns.Add(new Vector3(-40f, ValleyHeight(-40f, 20f) + 0.6f, 20f));
        }

        // ================= BARRACKS — military base =================

        public static void BuildBarracks(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Dirt, Color.white);
            // Perimeter wall (h=3) with a south gate gap at x in [18,26].
            foreach (var wall in new[] {
                new { x0 = -66f, x1 = 66f, z0 = -66f, z1 = -66f },
                new { x0 = -66f, x1 = 66f, z0 = 66f, z1 = 66f },
                new { x0 = -66f, x1 = -66f, z0 = -66f, z1 = 66f },
                new { x0 = 66f, x1 = 66f, z0 = -66f, z1 = 66f } })
            {
                float cx = (wall.x0 + wall.x1) * 0.5f, cz = (wall.z0 + wall.z1) * 0.5f;
                float w = Mathf.Max(wall.x1 - wall.x0, 0.4f), d = Mathf.Max(wall.z1 - wall.z0, 0.4f);
                if (Mathf.Approximately(cz, 66f))
                {
                    // south wall with gate gap
                    RegionKit.Box(ctx, new Vector3(84f, 3f, 0.4f), new Vector3(-24f, 1.5f, 66f),
                        ctx.Mats.Concrete, Color.white, true);
                    RegionKit.Box(ctx, new Vector3(40f, 3f, 0.4f), new Vector3(46f, 1.5f, 66f),
                        ctx.Mats.Concrete, Color.white, true);
                }
                else
                    RegionKit.Box(ctx, new Vector3(w, 3f, d), new Vector3(cx, 1.5f, cz),
                        ctx.Mats.Concrete, Color.white, true);
            }
            // Parade ground + flag.
            RegionKit.Box(ctx, new Vector3(40f, 0.12f, 30f), new Vector3(0f, 0.02f, 0f),
                ctx.Mats.Sidewalk, Color.white, true);
            RegionKit.Cyl(ctx, 0.1f, 12f, new Vector3(0f, 6f, 0f), ctx.Mats.Metal, Color.white);
            RegionKit.Box(ctx, new Vector3(2.4f, 1.5f, 0.05f), new Vector3(1.25f, 10.8f, 0f),
                ctx.Mats.ContainerGreen, Color.white);
            // Gatehouse.
            House(ctx, new Vector3(22f, 0f, 62f), 180f, 6f, 5f, 2, new Color(0.80f, 0.72f, 0.56f));
            // Barrack blocks (16x8, 2 floors).
            House(ctx, new Vector3(-25f, 0f, -20f), 0f, 16f, 8f, 2, new Color(0.80f, 0.72f, 0.56f));
            House(ctx, new Vector3(25f, 0f, -20f), 0f, 16f, 8f, 2, new Color(0.78f, 0.70f, 0.54f));
            // Armory + mess hall.
            var armory = BuildingSpec.Warehouse(12f, 8f, new Color(0.55f, 0.57f, 0.60f), ctx.Ri(1, 1000000));
            BuildingFactory.Build(ctx.Batch, armory, ctx.Root, new Vector3(30f, 0f, 42f), 0f,
                ctx.Mats, ctx.Rng);
            House(ctx, new Vector3(-30f, 0f, 42f), 0f, 14f, 8f, 1, new Color(0.82f, 0.74f, 0.58f));
            // Obstacle course.
            for (int i = 0; i < 4; i++)
            {
                RegionKit.Box(ctx, new Vector3(0.4f, 2.2f, 3f),
                    new Vector3(-52f + i * 5f, 1.1f, -2f), ctx.Mats.Wood, Color.white, true);
                RegionKit.Box(ctx, new Vector3(3f, 0.5f, 0.5f),
                    new Vector3(-50f + i * 5f, 0.25f, 4f), ctx.Mats.WoodDark, Color.white, true);
            }
            // Watchtowers, sandbags, vehicles, lamps.
            RegionKit.Watchtower(ctx, -58f, -58f, 45f);
            RegionKit.Watchtower(ctx, 58f, -58f, -45f);
            RegionKit.SandbagWall(ctx, 14f, 58f, 0f);
            RegionKit.SandbagWall(ctx, 30f, 58f, 0f);
            for (int i = 0; i < 3; i++)
                RegionKit.Car(ctx, new Vector3(-10f + i * 12f, 0.06f, 20f), 0f,
                    new Color(0.25f, 0.30f, 0.22f));
            for (int i = 0; i < 6; i++)
                RegionKit.Streetlight(ctx, new Vector3(-40f + i * 16f, 0f, -40f), 0f, 8f);
            for (int i = 0; i < 4; i++)
                RegionKit.CrateStack(ctx, new Vector3(36f + (i % 2) * 2f, 0f, 30f + (i / 2) * 2f));

            foreach (var poi in new[] {
                new Vector3(0f, 0f, 0f), new Vector3(30f, 0f, 42f),
                new Vector3(-30f, 0f, 42f), new Vector3(22f, 0f, 62f) })
                ctx.AddLootRing(poi, 0.55f, 6, 2);

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, -30f);
            ctx.EnemySpawns.Add(new Vector3(-40f, 0.6f, 40f));
            ctx.EnemySpawns.Add(new Vector3(40f, 0.6f, -40f));
        }

        // ================= TRAIN STATION =================

        private static void Track(RegionContext ctx, float tz, float len)
        {
            // rails
            foreach (float off in new[] { -0.75f, 0.75f })
                RegionKit.Box(ctx, new Vector3(len, 0.12f, 0.08f),
                    new Vector3(0f, 0.22f, tz + off), ctx.Mats.SteelDark, Color.white);
            // sleepers
            for (float x = -len / 2f; x <= len / 2f; x += 1.6f)
                RegionKit.Box(ctx, new Vector3(0.3f, 0.08f, 2.2f),
                    new Vector3(x, 0.12f, tz), ctx.Mats.WoodDark, Color.white);
            // ballast bed
            RegionKit.Box(ctx, new Vector3(len, 0.08f, 3.4f), new Vector3(0f, 0.02f, tz),
                ctx.Mats.Dirt, Color.white);
        }

        public static void BuildTrainStation(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Concrete, Color.white);
            Track(ctx, 13f, 136f);
            Track(ctx, 20f, 136f);
            // Station hall 24x16 h=5 at (0,-14), gabled roof, real door/window openings.
            {
                float w = 24f, d = 16f, h = 5f, t = 0.35f;
                var frame = Matrix4x4.TRS(new Vector3(0f, 0f, -14f), Quaternion.identity, Vector3.one);
                var id = Matrix4x4.identity;
                var holes = new System.Collections.Generic.List<BuildingFactory.Hole>();
                // (built via WallOpen through a small local shim)
                BuildHallWalls(ctx, frame, id, w, d, h, t);
                // gabled roof: ridge along x at y=9
                float slope = Mathf.Sqrt(8.5f * 8.5f + 4f * 4f) + 0.3f;
                float ang = Mathf.Atan2(4f, 8.5f) * Mathf.Rad2Deg;
                foreach (float s in new[] { -1f, 1f })
                {
                    var rm = frame * Matrix4x4.TRS(new Vector3(0f, 5f + 2f, s * 4.25f),
                        Quaternion.AngleAxis(s * ang, Vector3.right), Vector3.one);
                    ctx.Batch.Box(new Vector3(w + 1f, 0.15f, slope), rm, ctx.Mats.RoofRed, Color.white);
                }
                ctx.HousePositions.Add(new Vector3(0f, 0f, -14f));
                ctx.AddLoot("ammo", 60, new Vector3(-6f, 0.55f, -14f), 1);
                ctx.AddLoot("health", 40, new Vector3(6f, 0.55f, -14f), 1);
            }
            // Platforms.
            RegionKit.Box(ctx, new Vector3(120f, 1f, 6f), new Vector3(0f, 0.5f, 6.5f),
                ctx.Mats.Sidewalk, Color.white, true);
            RegionKit.Box(ctx, new Vector3(120f, 1f, 6f), new Vector3(0f, 0.5f, 26.5f),
                ctx.Mats.Sidewalk, Color.white, true);
            // Train: locomotive + 4 cars on track 1.
            BuildTrainCar(ctx, -42f, 13f, true);
            for (int i = 0; i < 4; i++) BuildTrainCar(ctx, -32.4f + i * 10.6f, 13f, false);
            // Footbridge over the tracks at x=40.
            {
                RegionKit.Box(ctx, new Vector3(3f, 0.3f, 30f), new Vector3(40f, 5.2f, 16.5f),
                    ctx.Mats.Concrete, Color.white, true);
                foreach (float s in new[] { -1f, 1f })
                    RegionKit.Box(ctx, new Vector3(0.15f, 1.1f, 30f),
                        new Vector3(40f + s * 1.5f, 5.9f, 16.5f), ctx.Mats.Metal, Color.white, true);
                foreach (float ze in new[] { 1.5f, 31.5f })
                    BuildingFactory.Stairs(ctx.Batch, Matrix4x4.TRS(new Vector3(40f, 0f, ze),
                        Quaternion.Euler(0f, ze < 16f ? 180f : 0f, 0f), Vector3.one),
                        -4f, 8f, 2.4f, 0f, 5.2f, 0f, ctx.Mats.ConcreteDark, ctx.Mats.Metal);
                ctx.AddLoot("ammo", 60, new Vector3(40f, 5.75f, 17f), 2);
            }
            // Parking + fence + plaza.
            RegionKit.Box(ctx, new Vector3(40f, 0.08f, 24f), new Vector3(-40f, 0.02f, -44f),
                ctx.Mats.AsphaltPlain, Color.white);
            for (int i = 0; i < 5; i++)
                RegionKit.Car(ctx, new Vector3(-54f + i * 8f, 0.06f, -44f), 0f, Color.white);
            for (float x = -66f; x <= 66f; x += 8f)
                RegionKit.Box(ctx, new Vector3(0.15f, 1.6f, 0.15f), new Vector3(x, 0.8f, -64f),
                    ctx.Mats.Metal, Color.white);
            RegionKit.Box(ctx, new Vector3(40f, 0.12f, 20f), new Vector3(20f, 0.02f, -48f),
                ctx.Mats.Sidewalk, Color.white);

            foreach (var poi in new[] {
                new Vector3(0f, 0f, -10f), new Vector3(-20f, 1f, 8f),
                new Vector3(-15.5f, 1f, 13f), new Vector3(40f, 5.2f, 17f) })
                ctx.AddLootRing(poi, 0.55f, 5, 1);

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, -40f);
            ctx.EnemySpawns.Add(new Vector3(-50f, 0.6f, 30f));
            ctx.EnemySpawns.Add(new Vector3(50f, 0.6f, -30f));
        }

        private static void BuildHallWalls(RegionContext ctx, Matrix4x4 frame, Matrix4x4 id,
            float w, float d, float h, float t)
        {
            var wallMat = ctx.Mats.Wall;
            var col = new Color(0.90f, 0.84f, 0.68f);
            // front/back: 2 doors + window band
            foreach (float s in new[] { -1f, 1f })
            {
                var holes = new System.Collections.Generic.List<BuildingFactory.Hole>
                {
                    new BuildingFactory.Hole { Xc = -6f, Y0 = 0f, W = 2.4f, H = 3.4f },
                    new BuildingFactory.Hole { Xc = 6f, Y0 = 0f, W = 2.4f, H = 3.4f },
                };
                foreach (float wx in new[] { -10.9f, -8.7f, -2.5f, 2.5f, 8.7f, 10.9f })
                    holes.Add(new BuildingFactory.Hole { Xc = wx, Y0 = 1.2f, W = 1.6f, H = 1.4f });
                BuildingFactory.WallOpen(ctx.Batch, frame * Matrix4x4.TRS(
                    new Vector3(0f, 0f, s * d * 0.5f), Quaternion.identity, Vector3.one),
                    w, h, t, holes, wallMat, col);
            }
            // sides: window bands
            BuildingFactory.WindowWall(ctx.Batch, frame * Matrix4x4.TRS(
                new Vector3(w * 0.5f, 0f, 0f), Quaternion.Euler(0f, 90f, 0f), Vector3.one),
                d, h, t, wallMat, col, ctx.Mats);
            BuildingFactory.WindowWall(ctx.Batch, frame * Matrix4x4.TRS(
                new Vector3(-w * 0.5f, 0f, 0f), Quaternion.Euler(0f, -90f, 0f), Vector3.one),
                d, h, t, wallMat, col, ctx.Mats);
            // floor
            ctx.Batch.Box(new Vector3(w, 0.2f, d),
                frame * Matrix4x4.TRS(new Vector3(0f, -0.1f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.Concrete, Color.white, true);
        }

        private static void BuildTrainCar(RegionContext ctx, float cx, float cz, bool loco)
        {
            float len = loco ? 10f : 9.6f;
            var f = Matrix4x4.TRS(new Vector3(cx, 0f, cz), Quaternion.identity, Vector3.one);
            var id = Matrix4x4.identity;
            Color body = loco ? new Color(0.15f, 0.25f, 0.45f) : new Color(0.70f, 0.68f, 0.62f);
            ctx.Batch.Box(new Vector3(len, 2.6f, 2.9f),
                f * Matrix4x4.TRS(new Vector3(0f, 1.7f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.Metal, body, true);
            ctx.Batch.Box(new Vector3(len * 0.9f, 0.5f, 2.95f),
                f * Matrix4x4.TRS(new Vector3(0f, 0.45f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.HullBlack, Color.white, true);
            // window band
            for (int i = 0; i < 6; i++)
                ctx.Batch.Box(new Vector3(1.1f, 0.8f, 0.06f),
                    f * Matrix4x4.TRS(new Vector3(-len * 0.4f + i * len * 0.16f, 2.1f, 1.46f),
                        Quaternion.identity, Vector3.one), ctx.Mats.GlassDark, Color.white);
            ctx.Batch.Box(new Vector3(len + 0.4f, 0.25f, 3.2f),
                f * Matrix4x4.TRS(new Vector3(0f, 3.1f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.RoofGrey, Color.white);
            if (loco)
            {
                ctx.Batch.Box(new Vector3(2.2f, 1.6f, 2.9f),
                    f * Matrix4x4.TRS(new Vector3(len * 0.32f, 3.6f, 0f), Quaternion.identity, Vector3.one),
                    ctx.Mats.Metal, body, true);
                ctx.Batch.Box(new Vector3(1.6f, 0.7f, 0.06f),
                    f * Matrix4x4.TRS(new Vector3(len * 0.32f, 3.9f, 1.46f), Quaternion.identity, Vector3.one),
                    ctx.Mats.GlassDark, Color.white);
            }
        }
    }
}

namespace NovaMobile.World
{
    public static partial class RegionBuilders
    {
        // ================= AIRPORT =================

        private static void Runway(RegionContext ctx, float rz)
        {
            RegionKit.Box(ctx, new Vector3(124f, 0.08f, 10f), new Vector3(0f, 0.02f, rz),
                ctx.Mats.AsphaltPlain, Color.white, true);
            foreach (float e in new[] { -4.5f, 4.5f })
                RegionKit.Box(ctx, new Vector3(124f, 0.02f, 0.25f), new Vector3(0f, 0.08f, rz + e),
                    ctx.Mats.PaintWhite, Color.white);
            for (float x = -56f; x <= 56f; x += 8f)
                RegionKit.Box(ctx, new Vector3(3.5f, 0.02f, 0.35f), new Vector3(x, 0.08f, rz),
                    ctx.Mats.PaintWhite, Color.white);
            foreach (float ex in new[] { -56f, 56f })
                for (int k = 0; k < 6; k++)
                    RegionKit.Box(ctx, new Vector3(4f, 0.02f, 0.6f),
                        new Vector3(ex, 0.08f, rz - 3.5f + k * 1.4f), ctx.Mats.PaintWhite, Color.white);
        }

        public static void BuildAirport(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Dirt, Color.white);
            Runway(ctx, -58f);
            // Taxiway + apron.
            RegionKit.RoadStrip(ctx, -6f, 2f, -53f, -29f);
            RegionKit.Box(ctx, new Vector3(66f, 0.08f, 48f), new Vector3(25f, 0.02f, 2f),
                ctx.Mats.AsphaltPlain, Color.white, true);
            // Terminal: 36x18, 2 floors, glass front.
            {
                var frame = Matrix4x4.TRS(new Vector3(-16f, 0f, -14f), Quaternion.identity, Vector3.one);
                var id = Matrix4x4.identity;
                var col = new Color(0.86f, 0.87f, 0.88f);
                var holes = new System.Collections.Generic.List<BuildingFactory.Hole>
                {
                    new BuildingFactory.Hole { Xc = 0f, Y0 = 0f, W = 4f, H = 3.6f },
                    new BuildingFactory.Hole { Xc = -12f, Y0 = 1f, W = 6f, H = 2f },
                    new BuildingFactory.Hole { Xc = 12f, Y0 = 1f, W = 6f, H = 2f },
                };
                BuildingFactory.WallOpen(ctx.Batch, frame * Matrix4x4.TRS(
                    new Vector3(0f, 0f, 9f), Quaternion.identity, Vector3.one),
                    36f, 4f, 0.3f, holes, ctx.Mats.Wall, col);
                BuildingFactory.WindowWall(ctx.Batch, frame * Matrix4x4.TRS(
                    new Vector3(0f, 4f, 9f), Quaternion.identity, Vector3.one),
                    36f, 3.4f, 0.3f, ctx.Mats.GlassDark, Color.white, ctx.Mats);
                BuildingFactory.WindowWall(ctx.Batch, frame * Matrix4x4.TRS(
                    new Vector3(0f, 0f, -9f), Quaternion.identity, Vector3.one),
                    36f, 4f, 0.3f, ctx.Mats.Wall, col, ctx.Mats);
                BuildingFactory.Slab(ctx.Batch, frame, 36f, 18f, 4.1f, ctx.Mats.Concrete);
                BuildingFactory.WindowWall(ctx.Batch, frame * Matrix4x4.TRS(
                    new Vector3(0f, 4.1f, -9f), Quaternion.identity, Vector3.one),
                    36f, 3.4f, 0.3f, ctx.Mats.GlassDark, Color.white, ctx.Mats);
                BuildingFactory.Slab(ctx.Batch, frame, 36f, 18f, 7.6f, ctx.Mats.Concrete);
                ctx.Batch.Box(new Vector3(37f, 0.3f, 19f),
                    frame * Matrix4x4.TRS(new Vector3(0f, 7.8f, 0f), Quaternion.identity, Vector3.one),
                    ctx.Mats.RoofGrey, Color.white);
                ctx.HousePositions.Add(new Vector3(-16f, 0f, -14f));
                ctx.AddLoot("armor", 50, new Vector3(-16f, 0.55f, -14f), 1);
                ctx.AddLoot("ammo", 60, new Vector3(-10f, 4.65f, -14f), 2);
            }
            // Control tower: 4x4 shaft 18m + glass cab + roof.
            {
                RegionKit.Box(ctx, new Vector3(4f, 18f, 4f), new Vector3(4f, 9f, -6f),
                    ctx.Mats.Concrete, Color.white, true);
                RegionKit.Box(ctx, new Vector3(6f, 2.6f, 6f), new Vector3(4f, 19.3f, -6f),
                    ctx.Mats.GlassDark, Color.white, true);
                RegionKit.Box(ctx, new Vector3(6.6f, 0.4f, 6.6f), new Vector3(4f, 20.8f, -6f),
                    ctx.Mats.RoofGrey, Color.white);
                // external switchback stairs (visual)
                for (int s = 0; s < 4; s++)
                    BuildingFactory.Stairs(ctx.Batch,
                        Matrix4x4.TRS(new Vector3(4f, 0f, -6f), Quaternion.Euler(0f, s * 90f, 0f), Vector3.one),
                        2.5f, 5f, 2f, 5.5f + (s % 2) * 2f, 4.5f, s * 4.5f,
                        ctx.Mats.ConcreteDark, ctx.Mats.Metal);
                ctx.AddLoot("ammo", 60, new Vector3(4f, 21.2f, -6f), 2);
            }
            // Hangars (arched profile from angled segments).
            foreach (float hx in new[] { 14f, 34f })
            {
                var f = Matrix4x4.TRS(new Vector3(hx, 0f, 62f), Quaternion.identity, Vector3.one);
                var id = Matrix4x4.identity;
                foreach (float s in new[] { -1f, 1f })
                    ctx.Batch.Box(new Vector3(0.5f, 4f, 14f),
                        f * Matrix4x4.TRS(new Vector3(s * 7f, 2f, 0f), Quaternion.identity, Vector3.one),
                        ctx.Mats.Metal, Color.white, true);
                for (int i = 0; i < 5; i++)
                {
                    float a = Mathf.PI * (i + 0.5f) / 5f;
                    float sx = Mathf.Cos(a) * 7f, sy = 4f + Mathf.Sin(a) * 4f;
                    var seg = f * Matrix4x4.TRS(new Vector3(sx, sy, 0f),
                        Quaternion.AngleAxis((a - Mathf.PI * 0.5f) * Mathf.Rad2Deg, Vector3.forward),
                        Vector3.one);
                    ctx.Batch.Box(new Vector3(4.6f, 0.3f, 14.5f), seg, ctx.Mats.RoofGrey, Color.white);
                }
                // big open front (no front wall) + back wall
                ctx.Batch.Box(new Vector3(14.5f, 4f, 0.5f),
                    f * Matrix4x4.TRS(new Vector3(0f, 2f, -7f), Quaternion.identity, Vector3.one),
                    ctx.Mats.Metal, Color.white, true);
            }
            // Helicopters + planes (props).
            foreach (var hp in new[] { new Vector3(18f, 0f, -8f), new Vector3(34f, 0f, -14f) })
                BuildHelicopter(ctx, hp);
            foreach (var pp in new[] { new Vector3(30f, 0f, 6f), new Vector3(48f, 0f, 10f) })
                BuildPlane(ctx, pp, 25f);
            // Fuel truck, light towers, windsock, fence, helipads.
            RegionKit.Car(ctx, new Vector3(-2f, 0.06f, -34f), 0f, new Color(0.8f, 0.2f, 0.15f));
            foreach (var lp in new[] {
                new Vector3(-60f, 0f, -60f), new Vector3(60f, 0f, -60f),
                new Vector3(-60f, 0f, 60f), new Vector3(60f, 0f, 60f) })
            {
                RegionKit.Cyl(ctx, 0.15f, 18f, lp + new Vector3(0f, 9f, 0f), ctx.Mats.SteelDark, Color.white);
                RegionKit.Box(ctx, new Vector3(1.2f, 0.5f, 0.6f), lp + new Vector3(0f, 18f, 0f),
                    ctx.Mats.Emissive, Color.white);
            }
            RegionKit.Cyl(ctx, 0.08f, 6f, new Vector3(-58f, 3f, -50f), ctx.Mats.Metal, Color.white);
            var sock = Matrix4x4.TRS(new Vector3(-58f, 5.8f, -49.2f),
                Quaternion.AngleAxis(-70f, Vector3.right), Vector3.one);
            ctx.Batch.Cylinder(0.35f, 1.6f, 8, sock, ctx.Mats.ContainerOrange, Color.white);
            foreach (var hp2 in new[] { new Vector3(42f, 0f, 17f), new Vector3(52f, 0f, 17f) })
            {
                ctx.Batch.Cylinder(5f, 0.16f, 16,
                    Matrix4x4.TRS(hp2 + new Vector3(0f, 0.08f, 0f), Quaternion.identity, Vector3.one),
                    ctx.Mats.AsphaltPlain, Color.white);
                RegionKit.Box(ctx, new Vector3(2.3f, 0.03f, 0.5f), hp2 + new Vector3(0f, 0.18f, 0f),
                    ctx.Mats.PaintYellow, Color.white);
            }

            foreach (var poi in new[] {
                new Vector3(-16f, 0f, -14f), new Vector3(4f, 0f, -6f),
                new Vector3(42f, 0.1f, 17f), new Vector3(22f, 0f, 62f) })
                ctx.AddLootRing(poi, 0.55f, 6, 2);

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, 60f);
            ctx.EnemySpawns.Add(new Vector3(-50f, 0.6f, -40f));
            ctx.EnemySpawns.Add(new Vector3(50f, 0.6f, 40f));
        }

        private static void BuildHelicopter(RegionContext ctx, Vector3 pos)
        {
            var f = Matrix4x4.TRS(pos, Quaternion.Euler(0f, 30f, 0f), Vector3.one);
            var id = Matrix4x4.identity;
            ctx.Batch.Box(new Vector3(1.8f, 1.6f, 4.5f),
                f * Matrix4x4.TRS(new Vector3(0f, 1.4f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.Metal, new Color(0.75f, 0.75f, 0.78f), true);
            ctx.Batch.Box(new Vector3(0.5f, 0.5f, 4f),
                f * Matrix4x4.TRS(new Vector3(0f, 1.6f, 4f), Quaternion.identity, Vector3.one),
                ctx.Mats.Metal, Color.white);
            ctx.Batch.Box(new Vector3(8f, 0.08f, 0.35f),
                f * Matrix4x4.TRS(new Vector3(0f, 2.5f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.HullBlack, Color.white);
            ctx.Batch.Box(new Vector3(0.08f, 1.8f, 0.35f),
                f * Matrix4x4.TRS(new Vector3(0f, 1.6f, 5.8f), Quaternion.identity, Vector3.one),
                ctx.Mats.HullBlack, Color.white);
            foreach (float s in new[] { -1f, 1f })
                ctx.Batch.Box(new Vector3(0.15f, 0.9f, 3f),
                    f * Matrix4x4.TRS(new Vector3(s * 0.9f, 0.45f, 0f), Quaternion.identity, Vector3.one),
                    ctx.Mats.SteelDark, Color.white, true);
        }

        private static void BuildPlane(RegionContext ctx, Vector3 pos, float yawDeg)
        {
            var f = Matrix4x4.TRS(pos, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);
            var id = Matrix4x4.identity;
            ctx.Batch.Cylinder(1.1f, 12f, 12,
                f * Matrix4x4.TRS(new Vector3(0f, 1.6f, 0f), Quaternion.Euler(90f, 0f, 0f), Vector3.one),
                ctx.Mats.Metal, Color.white, true);
            ctx.Batch.Box(new Vector3(16f, 0.25f, 2.2f),
                f * Matrix4x4.TRS(new Vector3(0f, 1.7f, 0.5f), Quaternion.identity, Vector3.one),
                ctx.Mats.Metal, Color.white);
            ctx.Batch.Box(new Vector3(2.2f, 2.2f, 0.25f),
                f * Matrix4x4.TRS(new Vector3(0f, 2.8f, -5.5f), Quaternion.identity, Vector3.one),
                ctx.Mats.Metal, Color.white);
            ctx.Batch.Box(new Vector3(1.6f, 0.5f, 1.2f),
                f * Matrix4x4.TRS(new Vector3(0f, 2.3f, 4.5f), Quaternion.identity, Vector3.one),
                ctx.Mats.GlassDark, Color.white);
        }

        // ================= LAGOON BRIDGE — 140m deck over the lagoon =================

        public static void BuildLagoonBridge(RegionContext ctx)
        {
            const float deckY = 6f;
            RegionKit.WaterPlane(ctx, 150f, 150f, new Vector3(0f, -0.55f, 0f));
            // Main deck: top exactly at deckY.
            RegionKit.Box(ctx, new Vector3(140f, 0.6f, 20f), new Vector3(0f, deckY - 0.3f, 0f),
                ctx.Mats.AsphaltPlain, Color.white);
            ctx.Batch.Collider(new Vector3(140f, 0.8f, 20f), new Vector3(0f, deckY - 0.4f, 0f),
                Quaternion.identity);
            // Textured driving surface with lane markings.
            ctx.Batch.RoadQuad(-70f, 70f, -8f, 8f, deckY + 0.02f, true, ctx.Mats.Road);
            // Fascia skirts + curbs.
            foreach (float sz in new[] { -1f, 1f })
            {
                RegionKit.Box(ctx, new Vector3(140f, 1.4f, 0.35f),
                    new Vector3(0f, deckY - 0.7f, sz * 9.82f), ctx.Mats.ConcreteDark, Color.white);
                RegionKit.Box(ctx, new Vector3(140f, 0.05f, 1.5f),
                    new Vector3(0f, deckY + 0.015f, sz * 9.2f), ctx.Mats.Curb, Color.white);
            }
            // Piers.
            foreach (float px in new[] { -60f, -20f, 20f, 60f })
                foreach (float pz in new[] { -6f, 6f })
                    RegionKit.Cyl(ctx, 1f, 9f, new Vector3(px, 1f, pz), ctx.Mats.Concrete, Color.white);
            // Railings.
            foreach (float sz in new[] { -1f, 1f })
            {
                for (float x = -69f; x <= 69f; x += 6f)
                    RegionKit.Box(ctx, new Vector3(0.15f, 1.1f, 0.15f),
                        new Vector3(x, deckY + 0.55f, sz * 9.6f), ctx.Mats.Metal, Color.white);
                RegionKit.Box(ctx, new Vector3(140f, 0.12f, 0.12f),
                    new Vector3(0f, deckY + 1.1f, sz * 9.6f), ctx.Mats.Metal, Color.white, true);
            }
            // Light poles.
            for (float x = -63f; x <= 63f; x += 18f)
            {
                RegionKit.Cyl(ctx, 0.09f, 7f, new Vector3(x, deckY + 3.5f, -9.6f),
                    ctx.Mats.SteelDark, Color.white);
                RegionKit.Box(ctx, new Vector3(0.5f, 0.18f, 0.7f),
                    new Vector3(x, deckY + 7f, -9.3f), ctx.Mats.Emissive, Color.white);
            }
            // Toll plaza at (-30, deck).
            {
                RegionKit.Box(ctx, new Vector3(30f, 0.25f, 26f), new Vector3(-30f, deckY + 6f, 0f),
                    ctx.Mats.RoofGrey, Color.white);
                foreach (float px in new[] { -40f, -20f })
                    foreach (float pz in new[] { -10f, 10f })
                        RegionKit.Box(ctx, new Vector3(0.4f, 6f, 0.4f),
                            new Vector3(px, deckY + 3f, pz), ctx.Mats.Concrete, Color.white, true);
                for (int i = 0; i < 4; i++)
                {
                    float bx = -40f + i * 6.7f;
                    var bf = Matrix4x4.TRS(new Vector3(bx, deckY, 0f), Quaternion.identity, Vector3.one);
                    var id = Matrix4x4.identity;
                    ctx.Batch.Box(new Vector3(2.2f, 2.5f, 2.2f),
                        bf * Matrix4x4.TRS(new Vector3(0f, 1.25f, 0f), Quaternion.identity, Vector3.one),
                        ctx.Mats.Wall, new Color(0.85f, 0.83f, 0.80f), true);
                    ctx.Batch.Box(new Vector3(2.3f, 0.8f, 0.1f),
                        bf * Matrix4x4.TRS(new Vector3(0f, 1.7f, 1.12f), Quaternion.identity, Vector3.one),
                        ctx.Mats.GlassDark, Color.white);
                    ctx.AddLoot("ammo", 60, new Vector3(bx, deckY + 0.55f, 2f), 1);
                }
            }
            // Parked cars + bus on the deck.
            for (int i = 0; i < 4; i++)
                RegionKit.Car(ctx, new Vector3(-10f + i * 14f, deckY + 0.05f, -4.5f), 90f,
                    ctx.Pick(new[] { Color.white, Color.black, new Color(0.7f, 0.1f, 0.1f) }));
            {
                var f = Matrix4x4.TRS(new Vector3(30f, deckY, 4.5f),
                    Quaternion.Euler(0f, 90f, 0f), Vector3.one);
                var id = Matrix4x4.identity;
                ctx.Batch.Box(new Vector3(2.6f, 2.8f, 11f),
                    f * Matrix4x4.TRS(new Vector3(0f, 1.9f, 0f), Quaternion.identity, Vector3.one),
                    ctx.Mats.ContainerYellow, Color.white, true);
                for (int i = 0; i < 5; i++)
                    ctx.Batch.Box(new Vector3(0.06f, 0.9f, 1.4f),
                        f * Matrix4x4.TRS(new Vector3(1.32f, 2.2f, -4f + i * 2f),
                            Quaternion.identity, Vector3.one), ctx.Mats.GlassDark, Color.white);
            }
            // South dock: stairs down + platform.
            DockPlatform(ctx, new Vector3(61f, 0.2f, 22f), 10f, 8f);
            BuildingFactory.Stairs(ctx.Batch, Matrix4x4.TRS(new Vector3(58f, 0.2f, 12f),
                Quaternion.Euler(0f, 0f, 0f), Vector3.one),
                0f, 8f, 3f, 0f, deckY - 0.4f, 0.2f, ctx.Mats.ConcreteDark, ctx.Mats.Metal);

            foreach (var poi in new[] {
                new Vector3(-30f, deckY, 0f), new Vector3(0f, deckY, 0f),
                new Vector3(-60f, deckY, 0f), new Vector3(61f, 0.2f, 22f) })
                ctx.AddLootRing(poi, 0.55f, 5, 2);

            ctx.PlayerSpawn = new Vector3(0f, deckY + 0.6f, 0f);
            ctx.EnemySpawns.Add(new Vector3(-50f, deckY + 0.6f, 0f));
            ctx.EnemySpawns.Add(new Vector3(50f, deckY + 0.6f, 0f));
        }

        // ================= SHIP PORT — container terminal =================

        private static void Container(RegionContext ctx, Vector3 pos, float yawDeg, Material mat)
        {
            var f = Matrix4x4.TRS(pos, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);
            var id = Matrix4x4.identity;
            ctx.Batch.Box(new Vector3(6.1f, 2.6f, 2.44f),
                f * Matrix4x4.TRS(new Vector3(0f, 1.3f, 0f), Quaternion.identity, Vector3.one),
                mat, Color.white, true);
            // door ribs
            for (int i = 0; i < 4; i++)
                ctx.Batch.Box(new Vector3(0.08f, 2.4f, 2.3f),
                    f * Matrix4x4.TRS(new Vector3(-2.5f + i * 1.6f, 1.3f, 0f),
                        Quaternion.identity, Vector3.one), ctx.Mats.SteelDark, Color.white);
        }

        private static void Crane(RegionContext ctx, float zc)
        {
            foreach (float lx in new[] { 24f, 40f })
            {
                foreach (float lz in new[] { zc - 6f, zc + 6f })
                {
                    RegionKit.Box(ctx, new Vector3(1.4f, 18f, 1.4f), new Vector3(lx, 9f, lz),
                        ctx.Mats.CraneWhite, Color.white, true);
                    RegionKit.Box(ctx, new Vector3(3f, 0.6f, 3f), new Vector3(lx, 0.3f, lz),
                        ctx.Mats.ConcreteDark, Color.white);
                }
                BuildingFactory.Strut(ctx.Batch,
                    new Vector3(lx, 6f, zc - 6f), new Vector3(lx, 14f, zc + 6f),
                    0.35f, 0.35f, ctx.Mats.CraneWhite, Color.white);
                BuildingFactory.Strut(ctx.Batch,
                    new Vector3(lx, 6f, zc + 6f), new Vector3(lx, 14f, zc - 6f),
                    0.35f, 0.35f, ctx.Mats.CraneWhite, Color.white);
            }
            RegionKit.Box(ctx, new Vector3(17.6f, 1.6f, 1.6f), new Vector3(32f, 17.2f, zc - 6f),
                ctx.Mats.CraneWhite, Color.white);
            RegionKit.Box(ctx, new Vector3(17.6f, 1.6f, 1.6f), new Vector3(32f, 17.2f, zc + 6f),
                ctx.Mats.CraneWhite, Color.white);
            RegionKit.Box(ctx, new Vector3(7f, 3.2f, 5.5f), new Vector3(32f, 19.6f, zc),
                ctx.Mats.CraneYellow, Color.white, true);
            // boom out over the ship
            RegionKit.Box(ctx, new Vector3(46f, 1.8f, 2.6f), new Vector3(41f, 18.6f, zc),
                ctx.Mats.CraneYellow, Color.white);
            BuildingFactory.Strut(ctx.Batch, new Vector3(32f, 21.2f, zc), new Vector3(62f, 19.6f, zc),
                0.18f, 0.18f, ctx.Mats.SteelDark, Color.white);
            // trolley + cables + spreader
            RegionKit.Box(ctx, new Vector3(2.5f, 1f, 3f), new Vector3(54f, 17.2f, zc),
                ctx.Mats.SteelDark, Color.white);
            RegionKit.Box(ctx, new Vector3(0.09f, 9f, 0.09f), new Vector3(54f, 13.1f, zc - 0.9f),
                ctx.Mats.SteelDark, Color.white);
            RegionKit.Box(ctx, new Vector3(0.09f, 9f, 0.09f), new Vector3(54f, 13.1f, zc + 0.9f),
                ctx.Mats.SteelDark, Color.white);
            RegionKit.Box(ctx, new Vector3(0.6f, 0.6f, 6.5f), new Vector3(54f, 8.4f, zc),
                ctx.Mats.CraneYellow, Color.white);
            ctx.HousePositions.Add(new Vector3(32f, 0f, zc));
        }

        public static void BuildShipPort(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 40f, -70f, 70f, 0f, ctx.Mats.Concrete, Color.white);
            RegionKit.WaterPlane(ctx, 40f, 150f, new Vector3(58f, -0.55f, 0f)); // harbor
            // Quay edge.
            RegionKit.Box(ctx, new Vector3(0.8f, 2.5f, 140f), new Vector3(40f, -0.6f, 0f),
                ctx.Mats.ConcreteDark, Color.white, true);
            // Container yard stacks.
            Material[] cmats = { ctx.Mats.ContainerRed, ctx.Mats.ContainerBlue, ctx.Mats.ContainerGreen,
                ctx.Mats.ContainerOrange, ctx.Mats.ContainerYellow };
            for (int ix = 0; ix < 5; ix++)
                for (int iz = 0; iz < 4; iz++)
                {
                    float cx = -30f + ix * 9f, cz = -8f + iz * 12f;
                    int h = ctx.Ri(1, 4);
                    for (int l = 0; l < h; l++)
                        Container(ctx, new Vector3(cx, l * 2.6f, cz), (ix + iz) % 2 == 0 ? 0f : 90f,
                            cmats[(ix * 3 + iz + l) % cmats.Length]);
                    if (ctx.Rf() < 0.5f) ctx.AddLoot("ammo", 60, new Vector3(cx + 4f, 0.55f, cz), 1);
                }
            // Cranes.
            Crane(ctx, -5f);
            Crane(ctx, 15f);
            // The ship: hull + deckhouse + deck containers.
            {
                RegionKit.Box(ctx, new Vector3(18f, 5.5f, 30.5f), new Vector3(59f, 1.25f, -14.75f),
                    ctx.Mats.HullBlack, Color.white, true);
                RegionKit.Box(ctx, new Vector3(18f, 0.3f, 40f), new Vector3(59f, 3.85f, -10f),
                    ctx.Mats.DeckGrey, Color.white);
                ctx.Batch.Collider(new Vector3(18f, 0.5f, 40f), new Vector3(59f, 3.75f, -10f),
                    Quaternion.identity);
                // deckhouse tower
                RegionKit.Box(ctx, new Vector3(10f, 12f, 8f), new Vector3(59f, 10f, -26f),
                    ctx.Mats.Wall, Color.white, true);
                for (int i = 0; i < 3; i++)
                    RegionKit.Box(ctx, new Vector3(10.1f, 0.9f, 0.1f),
                        new Vector3(59f, 8f + i * 2.5f, -21.9f), ctx.Mats.GlassDark, Color.white);
                for (int i = 0; i < 4; i++)
                    Container(ctx, new Vector3(55f + (i % 2) * 8f, 4f, -8f + (i / 2) * 8f), 0f,
                        cmats[i % cmats.Length]);
                ctx.AddLoot("armor", 50, new Vector3(59f, 4.55f, -10f), 2);
            }
            // Warehouses.
            var wh1 = BuildingSpec.Warehouse(20f, 12f, new Color(0.68f, 0.66f, 0.62f), ctx.Ri(1, 1000000));
            BuildingFactory.Build(ctx.Batch, wh1, ctx.Root, new Vector3(-52f, 0f, -7f), 0f,
                ctx.Mats, ctx.Rng);
            var wh2 = BuildingSpec.Warehouse(20f, 12f, new Color(0.64f, 0.62f, 0.58f), ctx.Ri(1, 1000000));
            BuildingFactory.Build(ctx.Batch, wh2, ctx.Root, new Vector3(-52f, 0f, 18f), 0f,
                ctx.Mats, ctx.Rng);
            // Open containers (enterable loot spots).
            for (int i = 0; i < 3; i++)
            {
                float ox = -20f + i * 12f, oz = 34f;
                var f = Matrix4x4.TRS(new Vector3(ox, 0f, oz), Quaternion.Euler(0f, i * 30f, 0f),
                    Vector3.one);
                var id = Matrix4x4.identity;
                ctx.Batch.Box(new Vector3(6.1f, 0.25f, 2.44f),
                    f * Matrix4x4.TRS(new Vector3(0f, 0.12f, 0f), Quaternion.identity, Vector3.one),
                    cmats[i % cmats.Length], Color.white, true);
                ctx.Batch.Box(new Vector3(6.1f, 0.25f, 2.44f),
                    f * Matrix4x4.TRS(new Vector3(0f, 2.5f, 0f), Quaternion.identity, Vector3.one),
                    cmats[i % cmats.Length], Color.white);
                ctx.Batch.Box(new Vector3(0.15f, 2.6f, 2.44f),
                    f * Matrix4x4.TRS(new Vector3(-3f, 1.3f, 0f), Quaternion.identity, Vector3.one),
                    cmats[i % cmats.Length], Color.white, true);
                ctx.Batch.Box(new Vector3(6.1f, 2.6f, 0.15f),
                    f * Matrix4x4.TRS(new Vector3(0f, 1.3f, -1.15f), Quaternion.identity, Vector3.one),
                    cmats[i % cmats.Length], Color.white, true);
                ctx.AddLoot("health", 40, new Vector3(ox, 0.55f, oz), 1);
            }
            // Vehicles, light towers, gate booth.
            for (int i = 0; i < 3; i++)
                RegionKit.Car(ctx, new Vector3(-10f + i * 14f, 0.06f, 44f), 90f, Color.white);
            foreach (var lp in new[] { new Vector3(-40f, 0f, -40f), new Vector3(20f, 0f, -40f),
                new Vector3(-40f, 0f, 40f), new Vector3(20f, 0f, 40f) })
            {
                RegionKit.Cyl(ctx, 0.15f, 16f, lp + new Vector3(0f, 8f, 0f), ctx.Mats.SteelDark, Color.white);
                RegionKit.Box(ctx, new Vector3(1.4f, 0.5f, 0.6f), lp + new Vector3(0f, 16f, 0f),
                    ctx.Mats.Emissive, Color.white);
            }
            House(ctx, new Vector3(-62f, 0f, 52f), 0f, 4f, 4f, 1, new Color(0.85f, 0.83f, 0.80f));

            foreach (var poi in new[] {
                new Vector3(-7f, 0f, 10f), new Vector3(32f, 0f, -5f),
                new Vector3(59f, 4f, -10f), new Vector3(-52f, 0f, -7f) })
                ctx.AddLootRing(poi, 0.55f, 6, 2);

            ctx.PlayerSpawn = new Vector3(-40f, 0.6f, 50f);
            ctx.EnemySpawns.Add(new Vector3(0f, 0.6f, -40f));
            ctx.EnemySpawns.Add(new Vector3(-50f, 0.6f, 0f));
        }

        // ================= AIRBASE — B2 bombers =================

        private static void Bomber(RegionContext ctx, Vector3 pos, float yawDeg)
        {
            var frame = Matrix4x4.TRS(pos, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);
            var id = Matrix4x4.identity;
            Color grey = new Color(0.20f, 0.21f, 0.23f);
            // Flying-wing planform: 12 stepped box segments (ported from airbase.gd).
            float[][] segs = {
                new[] { 3.0f, 0.9f, 1.6f, 0f, 1.50f, 5.2f, 0f },
                new[] { 6.5f, 0.9f, 2.0f, 0f, 1.50f, 4.0f, 0f },
                new[] { 10.0f, 0.9f, 2.0f, 0f, 1.50f, 2.6f, 0f },
                new[] { 12.5f, 0.9f, 2.0f, 0f, 1.50f, 1.0f, 0f },
                new[] { 13.5f, 0.9f, 1.8f, 0f, 1.50f, -0.8f, 0f },
                new[] { 6.0f, 0.9f, 1.6f, 0f, 1.50f, -2.4f, 0f },
                new[] { 4.0f, 0.85f, 1.4f, -4.9f, 1.48f, -2.7f, -0.45f },
                new[] { 4.0f, 0.85f, 1.4f, 4.9f, 1.48f, -2.7f, 0.45f },
                new[] { 3.6f, 0.8f, 2.6f, -7.6f, 1.45f, -1.2f, -0.3f },
                new[] { 3.6f, 0.8f, 2.6f, 7.6f, 1.45f, -1.2f, 0.3f },
                new[] { 2.2f, 0.65f, 1.6f, -10.1f, 1.42f, -2.0f, -0.5f },
                new[] { 2.2f, 0.65f, 1.6f, 10.1f, 1.42f, -2.0f, 0.5f },
            };
            foreach (var s in segs)
            {
                var xf = frame * Matrix4x4.TRS(new Vector3(s[3], s[4], s[5]),
                    Quaternion.Euler(0f, s[6] * Mathf.Rad2Deg, 0f), Vector3.one);
                ctx.Batch.Box(new Vector3(s[0], s[1], s[2]), xf, ctx.Mats.HullBlack, grey);
            }
            // cockpit hump + canopy
            ctx.Batch.Box(new Vector3(2.4f, 0.9f, 2.0f),
                frame * Matrix4x4.TRS(new Vector3(0f, 2.30f, 4.4f), Quaternion.identity, Vector3.one),
                ctx.Mats.HullBlack, grey);
            ctx.Batch.Box(new Vector3(1.8f, 0.30f, 0.9f),
                frame * Matrix4x4.TRS(new Vector3(0f, 2.62f, 5.0f), Quaternion.identity, Vector3.one),
                ctx.Mats.GlassDark, Color.white);
            // landing gear
            foreach (float gx in new[] { 0f, -3.5f, 3.5f })
            {
                float gz = gx == 0f ? 4.6f : 0.5f;
                RegionKit.Box(ctx, new Vector3(0.3f, 1.1f, 0.3f),
                    pos + new Vector3(gx, 0.55f, gz), ctx.Mats.Metal, Color.white);
            }
            // sealed cover colliders
            ctx.Batch.Collider(new Vector3(12f, 2.6f, 10f),
                frame * Matrix4x4.TRS(new Vector3(0f, 1.4f, 1.5f), Quaternion.identity, Vector3.one));
            ctx.HousePositions.Add(pos);
        }

        private static void Shelter(RegionContext ctx, float cx, float cz)
        {
            var frame = Matrix4x4.TRS(new Vector3(cx, 0f, cz), Quaternion.identity, Vector3.one);
            var id = Matrix4x4.identity;
            Color col = new Color(0.55f, 0.56f, 0.50f);
            ctx.Batch.Box(new Vector3(13.2f, 0.06f, 11.2f),
                frame * Matrix4x4.TRS(new Vector3(0f, 0.03f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.ConcreteDark, Color.white);
            foreach (float sx in new[] { -6.75f, 6.75f })
                ctx.Batch.Box(new Vector3(0.5f, 3.4f, 12f),
                    frame * Matrix4x4.TRS(new Vector3(sx, 1.7f, 0f), Quaternion.identity, Vector3.one),
                    ctx.Mats.Concrete, col, true);
            ctx.Batch.Box(new Vector3(14f, 3.4f, 0.5f),
                frame * Matrix4x4.TRS(new Vector3(0f, 1.7f, -5.75f), Quaternion.identity, Vector3.one),
                ctx.Mats.Concrete, col, true);
            // arched roof: 7 angled segments (R=7)
            for (int i = 0; i < 7; i++)
            {
                float a = Mathf.PI * i / 6f;
                float segX = 7f * Mathf.Cos(a), segY = 3.4f + 7f * Mathf.Sin(a);
                var xf = frame * Matrix4x4.TRS(new Vector3(segX, segY, 0f),
                    Quaternion.AngleAxis((a + Mathf.PI * 0.5f) * Mathf.Rad2Deg, Vector3.forward),
                    Vector3.one);
                ctx.Batch.Box(new Vector3(3.8f, 0.45f, 12.6f), xf, ctx.Mats.Concrete, col, true);
            }
            ctx.Batch.Box(new Vector3(14.6f, 0.9f, 0.7f),
                frame * Matrix4x4.TRS(new Vector3(0f, 3f, 5.9f), Quaternion.identity, Vector3.one),
                ctx.Mats.Concrete, col, true);
            ctx.Batch.Box(new Vector3(0.3f, 0.06f, 10f),
                frame * Matrix4x4.TRS(new Vector3(0f, 9.8f, 0f), Quaternion.identity, Vector3.one),
                ctx.Mats.Emissive, Color.white);
            ctx.AddLoot("ammo", 60, new Vector3(cx - 3f, 0.55f, cz), 1);
            ctx.AddLoot("armor", 50, new Vector3(cx + 3f, 0.55f, cz), 1);
            ctx.HousePositions.Add(new Vector3(cx, 0f, cz));
        }

        public static void BuildAirbase(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Dirt, Color.white);
            Runway(ctx, -58f);
            RegionKit.RoadStrip(ctx, -6f, 2f, -53f, -29f);
            // Bomber row.
            Bomber(ctx, new Vector3(-40f, 0f, -28f), 0f);
            Bomber(ctx, new Vector3(-5f, 0f, -30f), 8f);
            Bomber(ctx, new Vector3(30f, 0f, -28f), -6f);
            // Hardened shelters (enterable).
            Shelter(ctx, -17.5f, 25f);
            Shelter(ctx, -2.5f, 25f);
            Shelter(ctx, 12.5f, 25f);
            // Command building + control tower.
            House(ctx, new Vector3(30f, 0f, 30f), 0f, 14f, 10f, 2, new Color(0.78f, 0.74f, 0.66f));
            {
                RegionKit.Box(ctx, new Vector3(4f, 14f, 4f), new Vector3(52f, 7f, 6f),
                    ctx.Mats.Concrete, Color.white, true);
                RegionKit.Box(ctx, new Vector3(5.5f, 2.4f, 5.5f), new Vector3(52f, 15.2f, 6f),
                    ctx.Mats.GlassDark, Color.white, true);
                RegionKit.Box(ctx, new Vector3(6f, 0.4f, 6f), new Vector3(52f, 16.6f, 6f),
                    ctx.Mats.RoofGrey, Color.white);
                BuildingFactory.Stairs(ctx.Batch, Matrix4x4.identity,
                    46f, 6f, 2f, 12f, 14f, 0f, ctx.Mats.ConcreteDark, ctx.Mats.Metal);
            }
            // Fuel depot: 3 tanks + berm.
            foreach (float tx in new[] { -50f, -42f, -34f })
            {
                RegionKit.Cyl(ctx, 3f, 6f, new Vector3(tx, 3f, 48f), ctx.Mats.Metal, Color.white, true, 14);
                RegionKit.Box(ctx, new Vector3(8f, 1f, 8f), new Vector3(tx, 0.5f, 48f),
                    ctx.Mats.ConcreteDark, Color.white);
            }
            // Cover: sandbags, blast barriers, crates.
            RegionKit.SandbagWall(ctx, -20f, -10f, 15f);
            RegionKit.SandbagWall(ctx, 10f, -12f, -20f);
            for (int i = 0; i < 4; i++)
                RegionKit.Box(ctx, new Vector3(3.5f, 1.2f, 0.5f),
                    new Vector3(-8f + i * 6f, 0.6f, 40f), ctx.Mats.Concrete, Color.white, true, 10f);
            // Vehicles + guard booths + fence.
            for (int i = 0; i < 2; i++)
                RegionKit.Car(ctx, new Vector3(20f + i * 10f, 0.06f, 48f), 90f,
                    new Color(0.25f, 0.30f, 0.22f));
            foreach (var bp in new[] { new Vector3(-30f, 0f, 58f), new Vector3(30f, 0f, 58f) })
                House(ctx, bp, 0f, 3.5f, 3.5f, 1, new Color(0.80f, 0.78f, 0.74f));
            for (float x = -66f; x <= 66f; x += 8f)
            {
                RegionKit.Box(ctx, new Vector3(0.15f, 2.2f, 0.15f), new Vector3(x, 1.1f, 64f),
                    ctx.Mats.Metal, Color.white);
                RegionKit.Box(ctx, new Vector3(0.15f, 2.2f, 0.15f), new Vector3(x, 1.1f, -64f),
                    ctx.Mats.Metal, Color.white);
            }

            foreach (var poi in new[] {
                new Vector3(0f, 0f, -24f), new Vector3(-17.5f, 0f, 25f),
                new Vector3(30f, 0f, 30f), new Vector3(52f, 0f, 6f) })
                ctx.AddLootRing(poi, 0.55f, 6, 2);

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, 58f);
            ctx.EnemySpawns.Add(new Vector3(-50f, 0.6f, 10f));
            ctx.EnemySpawns.Add(new Vector3(45f, 0.6f, -45f));
        }

        // ================= DOWNTOWN — Nova Towers =================

        public static void BuildDowntown(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Concrete, Color.white);
            RegionKit.RoadStrip(ctx, -66f, 66f, -4f, 4f);
            RegionKit.RoadStrip(ctx, -4f, 4f, -66f, 66f);
            // Nova Tower: 9 floors + helipad.
            var nova = BuildingSpec.Tower(16f, 16f, 9, new Color(0.72f, 0.78f, 0.86f),
                ctx.Ri(1, 1000000), true);
            BuildingFactory.Build(ctx.Batch, nova, ctx.Root, new Vector3(-40f, 0f, -32f), 0f,
                ctx.Mats, ctx.Rng);
            // Office towers.
            var t2 = BuildingSpec.Tower(12f, 12f, 6, new Color(0.80f, 0.82f, 0.84f),
                ctx.Ri(1, 1000000), false);
            BuildingFactory.Build(ctx.Batch, t2, ctx.Root, new Vector3(20f, 0f, -40f), 0f,
                ctx.Mats, ctx.Rng);
            var t3 = BuildingSpec.Tower(12f, 12f, 5, new Color(0.76f, 0.72f, 0.68f),
                ctx.Ri(1, 1000000), false);
            BuildingFactory.Build(ctx.Batch, t3, ctx.Root, new Vector3(45f, 0f, 12f), 0f,
                ctx.Mats, ctx.Rng);
            // Plaza with fountain.
            RegionKit.Box(ctx, new Vector3(30f, 0.12f, 24f), new Vector3(30f, 0.02f, 40f),
                ctx.Mats.Sidewalk, Color.white, true);
            RegionKit.Cyl(ctx, 4f, 0.8f, new Vector3(30f, 0.4f, 40f), ctx.Mats.Concrete, Color.white, true, 16);
            RegionKit.Cyl(ctx, 3.2f, 0.3f, new Vector3(30f, 0.75f, 40f), ctx.Mats.Water, Color.white, false, 16);
            RegionKit.Cyl(ctx, 0.3f, 2.5f, new Vector3(30f, 1.6f, 40f), ctx.Mats.Concrete, Color.white);
            // Rooftop-row shops (low commercial strip).
            for (int i = 0; i < 3; i++)
            {
                var s = BuildingSpec.Shop(10f, 7f, 2, new Color(0.84f, 0.81f, 0.74f),
                    ctx.Ri(1, 1000000), new[] { "NOVA MART", "SKY CAFE", "PLAZA BITES" }[i],
                    new Color(0.15f, 0.35f, 0.70f));
                BuildingFactory.Build(ctx.Batch, s, ctx.Root, new Vector3(-8f + i * 16f, 0f, 52f), 180f,
                    ctx.Mats, ctx.Rng);
            }
            // Props.
            for (float x = -60f; x <= 60f; x += 15f)
            {
                RegionKit.Streetlight(ctx, new Vector3(x, 0f, 6.5f), 180f);
                RegionKit.Streetlight(ctx, new Vector3(x + 7f, 0f, -6.5f), 0f);
            }
            for (int i = 0; i < 6; i++)
            {
                RegionKit.Box(ctx, new Vector3(1.6f, 0.7f, 1.6f),
                    new Vector3(-50f + i * 20f, 0.35f, 28f), ctx.Mats.ConcreteDark, Color.white, true);
                ctx.Batch.Rock(new Vector3(1.3f, 1f, 1.3f),
                    Matrix4x4.TRS(new Vector3(-50f + i * 20f, 1.2f, 28f), Quaternion.identity, Vector3.one),
                    ctx.Mats.Foliage, Color.white, false, 0.25f);
            }
            for (int i = 0; i < 6; i++)
                RegionKit.Car(ctx, new Vector3(-48f + i * 18f, 0.06f, i % 2 == 0 ? 2.8f : -2.8f),
                    90f, ctx.Pick(new[] { Color.black, Color.white, new Color(0.6f, 0.1f, 0.1f) }));
            for (int i = 0; i < 5; i++)
                RegionKit.Box(ctx, new Vector3(2f, 0.8f, 0.4f),
                    new Vector3(-20f + i * 10f, 0.4f, 8f), ctx.Mats.PaintWhite, Color.white, true, 15f);

            ctx.AddLootRing(new Vector3(-40f, 0f, -32f), 0.55f, 6, 2);
            ctx.AddLootRing(new Vector3(30f, 0f, 40f), 0.55f, 6, 2);
            ctx.AddLoot("armor", 50, new Vector3(-40f, 29.4f, -32f), 2); // rooftop row

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, 20f);
            ctx.EnemySpawns.Add(new Vector3(-50f, 0.6f, -50f));
            ctx.EnemySpawns.Add(new Vector3(50f, 0.6f, 50f));
        }

        // ================= DAM =================

        public static void BuildDam(RegionContext ctx)
        {
            const float damZ = -45f, crestY = 24f;
            RegionKit.GroundRect(ctx, -70f, 70f, -45f, 70f, 0f, ctx.Mats.Dirt, Color.white);
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, -75f, 0f, ctx.Mats.Dirt, Color.white);
            // Reservoir (north of the wall) + stilling basin (south).
            RegionKit.WaterPlane(ctx, 150f, 30f, new Vector3(0f, 0.5f, -60f));
            RegionKit.WaterPlane(ctx, 36f, 9f, new Vector3(0f, 0.45f, -33f));
            // Stepped gravity dam wall.
            RegionKit.Box(ctx, new Vector3(124f, 12f, 10f), new Vector3(0f, 6f, damZ),
                ctx.Mats.Concrete, Color.white, true);
            RegionKit.Box(ctx, new Vector3(124f, 6f, 7f), new Vector3(0f, 15f, damZ),
                ctx.Mats.Concrete, Color.white, true);
            RegionKit.Box(ctx, new Vector3(124f, 6f, 4f), new Vector3(0f, 21f, damZ),
                ctx.Mats.Concrete, Color.white, true);
            for (int i = 0; i < 11; i++)
            {
                float jx = -60f + i * 12f;
                RegionKit.Box(ctx, new Vector3(0.25f, 23.5f, 0.15f),
                    new Vector3(jx, 11.75f, damZ + 5.02f), ctx.Mats.ConcreteDark, Color.white);
            }
            // Spillway: piers + closed gates.
            foreach (float px in new[] { -15f, -5f, 5f, 15f })
                RegionKit.Box(ctx, new Vector3(1.6f, 10f, 1.4f), new Vector3(px, 17f, damZ + 3.8f),
                    ctx.Mats.ConcreteDark, Color.white, true);
            foreach (float gx in new[] { -10f, 0f, 10f })
            {
                RegionKit.Box(ctx, new Vector3(7.6f, 7.6f, 0.5f), new Vector3(gx, 15.8f, damZ + 3.7f),
                    ctx.Mats.SteelDark, Color.white);
                for (int r = 0; r < 3; r++)
                    RegionKit.Box(ctx, new Vector3(7.6f, 0.3f, 0.15f),
                        new Vector3(gx, 13.2f + r * 2.6f, damZ + 4f), ctx.Mats.Metal, Color.white);
            }
            // Crest walkway + railings + lamps.
            RegionKit.Box(ctx, new Vector3(124f, 0.5f, 5f), new Vector3(0f, crestY - 0.25f, damZ),
                ctx.Mats.AsphaltPlain, Color.white, true);
            RegionKit.Box(ctx, new Vector3(120f, 0.02f, 0.18f), new Vector3(0f, crestY + 0.01f, damZ),
                ctx.Mats.PaintWhite, Color.white);
            foreach (float sz in new[] { -1f, 1f })
            {
                float rz = damZ + sz * 2.4f;
                for (float x = -61f; x < 61.5f; x += 4f)
                    RegionKit.Box(ctx, new Vector3(0.09f, 1.1f, 0.09f),
                        new Vector3(x, crestY + 0.55f, rz), ctx.Mats.Metal, Color.white);
                RegionKit.Box(ctx, new Vector3(124f, 0.09f, 0.09f),
                    new Vector3(0f, crestY + 1.08f, rz), ctx.Mats.Metal, Color.white, true);
            }
            for (float lx = -56f; lx < 60f; lx += 16f)
            {
                RegionKit.Cyl(ctx, 0.11f, 5.5f, new Vector3(lx, crestY + 2.75f, damZ - 1.8f),
                    ctx.Mats.SteelDark, Color.white);
                RegionKit.Box(ctx, new Vector3(0.5f, 0.2f, 0.7f),
                    new Vector3(lx, crestY + 5.4f, damZ - 1.5f), ctx.Mats.Emissive, Color.white);
            }
            for (int i = 0; i < 8; i++)
                ctx.AddLoot("ammo", 60,
                    new Vector3(-52f + i * 14.5f + ctx.RfRange(-2f, 2f), crestY + 0.55f,
                        damZ + ctx.RfRange(-1.2f, 1.2f)), 2);
            // Powerhouse + control building.
            var ph = BuildingSpec.Warehouse(16f, 10f, new Color(0.66f, 0.64f, 0.60f), ctx.Ri(1, 1000000));
            BuildingFactory.Build(ctx.Batch, ph, ctx.Root, new Vector3(34f, 0f, 12f), 0f,
                ctx.Mats, ctx.Rng);
            House(ctx, new Vector3(-28f, 0f, 16f), 0f, 10f, 8f, 2, new Color(0.80f, 0.78f, 0.74f));
            // Stair tower up to the crest (visual switchback).
            for (int s = 0; s < 5; s++)
                BuildingFactory.Stairs(ctx.Batch, Matrix4x4.TRS(new Vector3(-64f, 0f, -30f + s * 2f),
                    Quaternion.Euler(0f, 90f, 0f), Vector3.one),
                    0f, 6f, 2.2f, 0f, crestY / 5f, s * crestY / 5f,
                    ctx.Mats.ConcreteDark, ctx.Mats.Metal);
            // Access road + rocks.
            RegionKit.RoadStrip(ctx, -66f, 66f, 20f, 26f);
            float density = WorldQuality.ScatterScale;
            for (int i = 0; i < 30 * density; i++)
            {
                float x = ctx.RfRange(-68f, 68f), z = ctx.RfRange(-40f, 68f);
                float s = ctx.RfRange(1.5f, 3.5f);
                ctx.Batch.Rock(new Vector3(s, s * 0.7f, s),
                    Matrix4x4.TRS(new Vector3(x, s * 0.3f, z), Quaternion.identity, Vector3.one),
                    ctx.Mats.RockM, Color.white, true, 0.35f);
            }

            foreach (var poi in new[] {
                new Vector3(0f, crestY, damZ), new Vector3(-28f, 0f, 16f),
                new Vector3(0f, 0.2f, -33f) })
                ctx.AddLootRing(poi, 0.55f, 5, 1);

            ctx.PlayerSpawn = new Vector3(-40f, 0.6f, 30f);
            ctx.EnemySpawns.Add(new Vector3(40f, 0.6f, 30f));
            ctx.EnemySpawns.Add(new Vector3(0f, crestY + 0.6f, damZ));
        }

        // ================= STADIUM =================

        private static void StandTier(RegionContext ctx, Vector3 center, float yawDeg, float width,
            float z0, float y0, float z1, float y1, Material mat)
        {
            float run = z1 - z0, rise = y1 - y0;
            float len = Mathf.Sqrt(run * run + rise * rise);
            float ang = Mathf.Atan2(rise, run) * Mathf.Rad2Deg;
            var yaw = Matrix4x4.TRS(center, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);
            var m = yaw * Matrix4x4.TRS(new Vector3(0f, (y0 + y1) * 0.5f, (z0 + z1) * 0.5f),
                Quaternion.AngleAxis(-ang, Vector3.right), Vector3.one);
            ctx.Batch.Box(new Vector3(width, 0.4f, len + 1f), m, mat, Color.white, true);
            int rows = 5;
            for (int i = 0; i < rows; i++)
            {
                float t = (i + 0.5f) / rows;
                var bm = yaw * Matrix4x4.TRS(new Vector3(0f, y0 + rise * t + 0.45f, z0 + run * t),
                    Quaternion.identity, Vector3.one);
                ctx.Batch.Box(new Vector3(width, 0.45f, 0.6f), bm,
                    (i % 2 == 0) ? ctx.Mats.ContainerRed : ctx.Mats.PaintWhite, Color.white);
            }
        }

        private static void Stand(RegionContext ctx, Vector3 center, float yawDeg, float width)
        {
            // Two tiers + outer wall (ports stadium.gd _build_segment, simplified).
            StandTier(ctx, center, yawDeg, width, -2.5f, 2.3f, 7.2f, 7f, ctx.Mats.Concrete);
            StandTier(ctx, center, yawDeg, width, 9f, 6.6f, 19.2f, 12f, ctx.Mats.Concrete);
            var yaw = Matrix4x4.TRS(center, Quaternion.Euler(0f, yawDeg, 0f), Vector3.one);
            ctx.Batch.Box(new Vector3(width + 6f, 13.5f, 0.4f),
                yaw * Matrix4x4.TRS(new Vector3(0f, 6.75f, 21f), Quaternion.identity, Vector3.one),
                ctx.Mats.Concrete, Color.white, true);
            ctx.Batch.Box(new Vector3(width + 1f, 0.25f, 2f),
                yaw * Matrix4x4.TRS(new Vector3(0f, 11.875f, 20f), Quaternion.identity, Vector3.one),
                ctx.Mats.Concrete, Color.white, true);
        }

        public static void BuildStadium(RegionContext ctx)
        {
            RegionKit.GroundRect(ctx, -70f, 70f, -70f, 70f, 0f, ctx.Mats.Dirt, Color.white);
            // Pitch + track.
            RegionKit.Box(ctx, new Vector3(70f, 0.06f, 50f), new Vector3(0f, 0.0f, 0f),
                ctx.Mats.Grass, Color.white, true);
            RegionKit.Box(ctx, new Vector3(86f, 0.05f, 6f), new Vector3(0f, 0.02f, -31f),
                ctx.Mats.Dirt, Color.white);
            RegionKit.Box(ctx, new Vector3(86f, 0.05f, 6f), new Vector3(0f, 0.02f, 31f),
                ctx.Mats.Dirt, Color.white);
            RegionKit.Box(ctx, new Vector3(6f, 0.05f, 56f), new Vector3(-41f, 0.02f, 0f),
                ctx.Mats.Dirt, Color.white);
            RegionKit.Box(ctx, new Vector3(6f, 0.05f, 56f), new Vector3(41f, 0.02f, 0f),
                ctx.Mats.Dirt, Color.white);
            // Pitch markings.
            RegionKit.Box(ctx, new Vector3(70f, 0.02f, 0.3f), new Vector3(0f, 0.06f, -25f),
                ctx.Mats.PaintWhite, Color.white);
            RegionKit.Box(ctx, new Vector3(70f, 0.02f, 0.3f), new Vector3(0f, 0.06f, 25f),
                ctx.Mats.PaintWhite, Color.white);
            RegionKit.Box(ctx, new Vector3(0.3f, 0.02f, 50f), new Vector3(0f, 0.06f, 0f),
                ctx.Mats.PaintWhite, Color.white);
            // Four stands.
            Stand(ctx, new Vector3(0f, 0f, -38f), 0f, 76f);
            Stand(ctx, new Vector3(0f, 0f, 38f), 180f, 76f);
            Stand(ctx, new Vector3(-50f, 0f, 0f), 90f, 56f);
            Stand(ctx, new Vector3(50f, 0f, 0f), -90f, 56f);
            // Players' tunnel (north stand).
            RegionKit.Box(ctx, new Vector3(5.5f, 3.2f, 8f), new Vector3(0f, 1.6f, -36f),
                ctx.Mats.ConcreteDark, Color.white, true);
            // Floodlights.
            foreach (var fp in new[] {
                new Vector3(-58f, 0f, -58f), new Vector3(58f, 0f, -58f),
                new Vector3(-58f, 0f, 58f), new Vector3(58f, 0f, 58f) })
            {
                RegionKit.Cyl(ctx, 0.25f, 26f, fp + new Vector3(0f, 13f, 0f), ctx.Mats.SteelDark, Color.white);
                RegionKit.Box(ctx, new Vector3(4f, 2f, 0.6f), fp + new Vector3(0f, 26.5f, 0f),
                    ctx.Mats.SteelDark, Color.white);
                RegionKit.Box(ctx, new Vector3(3.6f, 1.6f, 0.1f), fp + new Vector3(0f, 26.5f, 0.35f),
                    ctx.Mats.Emissive, Color.white);
            }
            // Parking, fence, ticket booths.
            RegionKit.Box(ctx, new Vector3(50f, 0.08f, 20f), new Vector3(0f, 0.02f, -62f),
                ctx.Mats.AsphaltPlain, Color.white);
            for (int i = 0; i < 5; i++)
                RegionKit.Car(ctx, new Vector3(-20f + i * 10f, 0.06f, -62f), 0f, Color.white);
            for (float x = -66f; x <= 66f; x += 8f)
            {
                RegionKit.Box(ctx, new Vector3(0.15f, 2f, 0.15f), new Vector3(x, 1f, 66f),
                    ctx.Mats.Metal, Color.white);
                RegionKit.Box(ctx, new Vector3(0.15f, 2f, 0.15f), new Vector3(x, 1f, -66f),
                    ctx.Mats.Metal, Color.white);
            }
            for (int i = 0; i < 4; i++)
            {
                var s = BuildingSpec.Shop(4f, 3f, 1, new Color(0.85f, 0.83f, 0.80f),
                    ctx.Ri(1, 1000000), "TICKETS", new Color(0.78f, 0.12f, 0.10f));
                BuildingFactory.Build(ctx.Batch, s, ctx.Root,
                    new Vector3(-30f + i * 20f, 0f, 60f), 180f, ctx.Mats, ctx.Rng);
            }
            ctx.AddLootRing(new Vector3(0f, 0f, 0f), 0.55f, 8, 2);
            ctx.AddLootRing(new Vector3(0f, 0f, -50f), 12.55f, 4, 2);

            ctx.PlayerSpawn = new Vector3(0f, 0.6f, 0f);
            ctx.EnemySpawns.Add(new Vector3(-40f, 0.6f, -20f));
            ctx.EnemySpawns.Add(new Vector3(40f, 0.6f, 20f));
        }
    }
}
