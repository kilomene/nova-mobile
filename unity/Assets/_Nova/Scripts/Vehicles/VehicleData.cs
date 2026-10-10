using UnityEngine;

namespace NovaMobile.Vehicles
{
    /// <summary>
    /// Vehicle roster. Enum order matches VehicleData.Specs order so Get() is O(1).
    /// Forward convention for every vehicle model: -Z (ported verbatim from Godot).
    /// </summary>
    public enum VehicleType
    {
        Sedan, SUV, Pickup, SportsCar, ATV, ArmoredSUV, CargoTruck, Jeep,
        Motorcycle, Tank, Helicopter, Boat, HoverBike, Skateboard, B2Bomber
    }

    public enum Locomotion { Ground, Water, Air, Hover, Plane }

    public enum VehicleWeapon { None, Cannon, Minigun, Bombs }

    /// <summary>Exact cross-system contract shape (see CONVENTIONS.md).</summary>
    public struct VehicleSpec
    {
        public VehicleType Type;
        public string Name;
        public float TopSpeed;      // m/s
        public float Acceleration;  // m/s^2
        public float TurnRate;      // rad/s at full speed
        public float FuelCapacity;  // litres-ish units; 0 = no fuel system
        public float FuelBurnRate;  // units per second at full throttle
        public int Seats;
        public float Health;        // max hull HP
        public bool UsesFuel;
    }

    /// <summary>
    /// Combat/handling params ported from vehicle_defs.gd that sit outside the
    /// cross-system contract (brakes, ram, weapons, nitro, locomotion).
    /// </summary>
    public struct VehicleExtra
    {
        public Locomotion Loco;
        public VehicleWeapon Weapon;
        public float Brake;
        public float RamDamage;
        public bool RamBreak;
        public bool Lean;            // bank into turns (bikes, ATV)
        public float HoverHeight;    // hover loco only
        public float NitroMult;
        // Cannon (tank)
        public float CannonDamage, CannonRadius, CannonCd;
        // Minigun (heli)
        public float MinigunDamage, MinigunRpm;
        // Bombs (B2)
        public float BombDamage, BombRadius;
        public int BombCount;
        public float BombCd, TakeoffSpeed;
    }

    public static class VehicleData
    {
        // Ported 1:1 from vehicle_defs.gd SPECS (speed/accel/brake/turn/hp/fuel).
        // Seats: the Godot spec has no seat counts; sensible values chosen per body
        // size (see report). Everything else is verbatim.
        public static readonly VehicleSpec[] Specs = new VehicleSpec[]
        {
            new VehicleSpec { Type = VehicleType.Sedan,      Name = "NV-4 Sedan",            TopSpeed = 24f, Acceleration = 16f, TurnRate = 1.7f, FuelCapacity = 60f,  FuelBurnRate = 0.60f, Seats = 4, Health = 120f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.SUV,        Name = "GX-7 SUV",              TopSpeed = 21f, Acceleration = 12f, TurnRate = 1.4f, FuelCapacity = 70f,  FuelBurnRate = 0.80f, Seats = 6, Health = 200f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.Pickup,     Name = "PX-4 Pickup",           TopSpeed = 22f, Acceleration = 13f, TurnRate = 1.4f, FuelCapacity = 70f,  FuelBurnRate = 0.85f, Seats = 4, Health = 180f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.SportsCar,  Name = "VX-R Sport",            TopSpeed = 37f, Acceleration = 26f, TurnRate = 2.2f, FuelCapacity = 55f,  FuelBurnRate = 1.00f, Seats = 2, Health = 90f,  UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.ATV,        Name = "QD-4 Quad",             TopSpeed = 24f, Acceleration = 18f, TurnRate = 2.6f, FuelCapacity = 45f,  FuelBurnRate = 0.45f, Seats = 2, Health = 70f,  UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.ArmoredSUV, Name = "AX-9 Armored",          TopSpeed = 19f, Acceleration = 10f, TurnRate = 1.2f, FuelCapacity = 80f,  FuelBurnRate = 1.10f, Seats = 6, Health = 340f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.CargoTruck,Name = "HT-8 Hauler",           TopSpeed = 17f, Acceleration = 9f,  TurnRate = 1.1f, FuelCapacity = 90f,  FuelBurnRate = 1.20f, Seats = 2, Health = 260f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.Jeep,       Name = "WJ-3 Jeep",             TopSpeed = 20f, Acceleration = 14f, TurnRate = 1.8f, FuelCapacity = 60f,  FuelBurnRate = 0.65f, Seats = 4, Health = 110f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.Motorcycle, Name = "KV-2 Bike",             TopSpeed = 31f, Acceleration = 22f, TurnRate = 2.4f, FuelCapacity = 40f,  FuelBurnRate = 0.35f, Seats = 2, Health = 60f,  UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.Tank,       Name = "T-90 'Bulwark'",        TopSpeed = 11f, Acceleration = 7f,  TurnRate = 1.2f, FuelCapacity = 100f, FuelBurnRate = 1.60f, Seats = 3, Health = 500f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.Helicopter, Name = "AH-6 'Kestrel'",        TopSpeed = 26f, Acceleration = 14f, TurnRate = 1.8f, FuelCapacity = 80f,  FuelBurnRate = 1.80f, Seats = 4, Health = 220f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.Boat,       Name = "PB-12 Patrol Boat",     TopSpeed = 20f, Acceleration = 10f, TurnRate = 1.3f, FuelCapacity = 70f,  FuelBurnRate = 0.90f, Seats = 6, Health = 150f, UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.HoverBike,  Name = "HX-1 Hoverbike",         TopSpeed = 33f, Acceleration = 24f, TurnRate = 2.6f, FuelCapacity = 50f,  FuelBurnRate = 0.70f, Seats = 1, Health = 80f,  UsesFuel = true  },
            new VehicleSpec { Type = VehicleType.Skateboard, Name = "Street Deck",           TopSpeed = 13f, Acceleration = 18f, TurnRate = 3.0f, FuelCapacity = 0f,   FuelBurnRate = 0.00f, Seats = 1, Health = 40f,  UsesFuel = false },
            new VehicleSpec { Type = VehicleType.B2Bomber,   Name = "B-2 'Jaka' Stealth Bomber", TopSpeed = 55f, Acceleration = 12f, TurnRate = 0.9f, FuelCapacity = 0f, FuelBurnRate = 0.00f, Seats = 2, Health = 350f, UsesFuel = false },
        };

        private static readonly VehicleExtra[] Extras = new VehicleExtra[]
        {
            //                        loco               weapon                brake  ram   ramBreak lean  hoverH nitro
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 26f, RamDamage = 25f, RamBreak = false, Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 20f, RamDamage = 35f, RamBreak = false, Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 20f, RamDamage = 45f, RamBreak = true,  Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 34f, RamDamage = 20f, RamBreak = false, Lean = false, HoverHeight = 0f,   NitroMult = 1.7f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 24f, RamDamage = 15f, RamBreak = false, Lean = true,  HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 18f, RamDamage = 55f, RamBreak = true,  Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 16f, RamDamage = 60f, RamBreak = true,  Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 20f, RamDamage = 25f, RamBreak = false, Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 30f, RamDamage = 15f, RamBreak = false, Lean = true,  HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.Cannon,  Brake = 12f, RamDamage = 80f, RamBreak = true,  Lean = false, HoverHeight = 0f,   NitroMult = 1.5f,
                CannonDamage = 110f, CannonRadius = 6.5f, CannonCd = 3.0f },
            new VehicleExtra { Loco = Locomotion.Air,    Weapon = VehicleWeapon.Minigun, Brake = 18f, RamDamage = 40f, RamBreak = false, Lean = false, HoverHeight = 0f,   NitroMult = 1.5f,
                MinigunDamage = 14f, MinigunRpm = 900f },
            new VehicleExtra { Loco = Locomotion.Water,  Weapon = VehicleWeapon.None,    Brake = 12f, RamDamage = 20f, RamBreak = false, Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Hover,  Weapon = VehicleWeapon.None,    Brake = 30f, RamDamage = 15f, RamBreak = false, Lean = false, HoverHeight = 1.1f, NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Ground, Weapon = VehicleWeapon.None,    Brake = 22f, RamDamage = 5f,  RamBreak = false, Lean = false, HoverHeight = 0f,   NitroMult = 1.5f },
            new VehicleExtra { Loco = Locomotion.Plane,  Weapon = VehicleWeapon.Bombs,   Brake = 10f, RamDamage = 100f, RamBreak = false, Lean = false, HoverHeight = 0f,  NitroMult = 1.5f,
                BombDamage = 160f, BombRadius = 12f, BombCount = 6, BombCd = 1.2f, TakeoffSpeed = 30f },
        };

        public static VehicleSpec Get(VehicleType t)
        {
            int i = (int)t;
            if (i >= 0 && i < Specs.Length) return Specs[i];
            return Specs[0];
        }

        public static VehicleExtra Extra(VehicleType t)
        {
            int i = (int)t;
            if (i >= 0 && i < Extras.Length) return Extras[i];
            return Extras[0];
        }
    }

    /// <summary>
    /// Vehicle spawn table ported from vehicle_defs.gd WORLD_SPAWNS / MAP_SPAWNS.
    /// The World system matches Region/PoiFragment against POI names.
    /// </summary>
    public struct VehicleSpawnEntry
    {
        public string Region;
        public VehicleType Type;
        public string PoiFragment;
    }

    public struct MapSpawnEntry
    {
        public int MapIndex;
        public VehicleType Type;
        public string PoiFragment;
    }

    public static class VehicleSpawnTable
    {
        public static readonly VehicleSpawnEntry[] WorldSpawns = new VehicleSpawnEntry[]
        {
            new VehicleSpawnEntry { Region = "LEKKI",            Type = VehicleType.Sedan,      PoiFragment = "Admiralty" },
            new VehicleSpawnEntry { Region = "LEKKI",            Type = VehicleType.Motorcycle, PoiFragment = "Bridge View" },
            new VehicleSpawnEntry { Region = "COMPUTER VILLAGE", Type = VehicleType.Sedan,      PoiFragment = "Tech Plaza" },
            new VehicleSpawnEntry { Region = "BANANA ISLAND",    Type = VehicleType.Sedan,      PoiFragment = "Palm Boulevard" },
            new VehicleSpawnEntry { Region = "BANANA ISLAND",    Type = VehicleType.Boat,       PoiFragment = "Marina" },
            new VehicleSpawnEntry { Region = "MAKOKO",           Type = VehicleType.Boat,       PoiFragment = "Main Dock" },
            new VehicleSpawnEntry { Region = "MAKOKO",           Type = VehicleType.Boat,       PoiFragment = "Canoe Yard" },
            new VehicleSpawnEntry { Region = "SHIP PORT",        Type = VehicleType.CargoTruck, PoiFragment = "Container Yard" },
            new VehicleSpawnEntry { Region = "SHIP PORT",        Type = VehicleType.Boat,       PoiFragment = "The Ship" },
            new VehicleSpawnEntry { Region = "BARRACKS",         Type = VehicleType.Tank,       PoiFragment = "Parade Ground" },
            new VehicleSpawnEntry { Region = "BARRACKS",         Type = VehicleType.CargoTruck, PoiFragment = "Gatehouse" },
            new VehicleSpawnEntry { Region = "AIRPORT",          Type = VehicleType.Helicopter, PoiFragment = "Helipad" },
            new VehicleSpawnEntry { Region = "AIRBASE",          Type = VehicleType.B2Bomber,   PoiFragment = "Bomber Row" },
            new VehicleSpawnEntry { Region = "AIRBASE",          Type = VehicleType.Helicopter, PoiFragment = "Control Tower" },
            new VehicleSpawnEntry { Region = "VALLEY",           Type = VehicleType.HoverBike,  PoiFragment = "Valley Camp" },
            new VehicleSpawnEntry { Region = "VALLEY",           Type = VehicleType.Skateboard, PoiFragment = "Hilltop" },
            new VehicleSpawnEntry { Region = "DOWNTOWN",         Type = VehicleType.Sedan,      PoiFragment = "Nova Tower" },
            new VehicleSpawnEntry { Region = "DOWNTOWN",         Type = VehicleType.Helicopter, PoiFragment = "Sky Villa" },
            new VehicleSpawnEntry { Region = "DAM",              Type = VehicleType.Boat,       PoiFragment = "Reservoir" },
            new VehicleSpawnEntry { Region = "STADIUM",          Type = VehicleType.Skateboard, PoiFragment = "Stadium" },
            new VehicleSpawnEntry { Region = "TRAIN STATION",    Type = VehicleType.Sedan,      PoiFragment = "Main Hall" },
            new VehicleSpawnEntry { Region = "LAGOON BRIDGE",    Type = VehicleType.Sedan,      PoiFragment = "Toll Plaza" },
            new VehicleSpawnEntry { Region = "LEKKI",            Type = VehicleType.SUV,        PoiFragment = "Estate Gate" },
            new VehicleSpawnEntry { Region = "LEKKI",            Type = VehicleType.SportsCar,  PoiFragment = "Admiralty Mall" },
            new VehicleSpawnEntry { Region = "BANANA ISLAND",    Type = VehicleType.SUV,        PoiFragment = "Sky Villa" },
            new VehicleSpawnEntry { Region = "VALLEY",           Type = VehicleType.ATV,        PoiFragment = "Ruined Compound" },
            new VehicleSpawnEntry { Region = "VALLEY",           Type = VehicleType.Jeep,       PoiFragment = "River Crossing" },
            new VehicleSpawnEntry { Region = "BARRACKS",         Type = VehicleType.ArmoredSUV, PoiFragment = "Armory" },
            new VehicleSpawnEntry { Region = "SHIP PORT",        Type = VehicleType.Pickup,     PoiFragment = "Warehouses" },
            new VehicleSpawnEntry { Region = "DOWNTOWN",         Type = VehicleType.SportsCar,  PoiFragment = "Nova Tower" },
            new VehicleSpawnEntry { Region = "COMPUTER VILLAGE", Type = VehicleType.Pickup,     PoiFragment = "Gadget Mall" },
        };

        public static readonly MapSpawnEntry[] MapSpawns = new MapSpawnEntry[]
        {
            new MapSpawnEntry { MapIndex = 8,  Type = VehicleType.Helicopter, PoiFragment = "Helipad" },
            new MapSpawnEntry { MapIndex = 9,  Type = VehicleType.CargoTruck, PoiFragment = "Container" },
            new MapSpawnEntry { MapIndex = 10, Type = VehicleType.B2Bomber,   PoiFragment = "Bomber" },
            new MapSpawnEntry { MapIndex = 10, Type = VehicleType.Tank,       PoiFragment = "Parade" },
            new MapSpawnEntry { MapIndex = 5,  Type = VehicleType.Tank,       PoiFragment = "Parade" },
            new MapSpawnEntry { MapIndex = 3,  Type = VehicleType.Boat,       PoiFragment = "Marina" },
            new MapSpawnEntry { MapIndex = 0,  Type = VehicleType.Boat,       PoiFragment = "Dock" },
            new MapSpawnEntry { MapIndex = 7,  Type = VehicleType.Sedan,      PoiFragment = "Toll" },
        };
    }
}
