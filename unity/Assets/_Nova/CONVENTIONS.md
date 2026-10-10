# NOVA Mobile — Unity Port: Conventions & Cross-System Contracts

Target: **Unity 6 (6000.0.x LTS)**, C# (block-scoped namespaces, C# 9 max — no file-scoped namespaces),
.NET Standard 2.1 API. Built-in Render Pipeline. **No Unity Editor available in this environment**:
every `.cs` file must be complete and compile-clean against the Unity 6 runtime API by care.
**No invented APIs. No `UnityEditor` references in runtime code** (editor-only code goes under
`Assets/_Nova/Editor/`).

## Layout

- `Assets/_Nova/Scripts/<System>/` — one folder per system (Core, World, Player, Arsenal, Mythics,
  Soldiers, Classes, Vehicles, Economy, Loot, Squads, Match, UI).
- `Assets/_Nova/Shaders/` — ShaderLab `.shader` files (unlit/custom style, pipeline-agnostic).
- Namespaces: `NovaMobile.<System>` (e.g. `NovaMobile.Arsenal`). File name == class name.
- No `.asmdef` — everything compiles into the default assembly; use namespaces to avoid collisions.

## Hard rules

1. **Mobile-first**: object pooling for anything spawned repeatedly (projectiles, loot, particles,
   bots); no per-frame allocations in hot paths; no LINQ in `Update`/`FixedUpdate`.
2. **Input**: legacy `UnityEngine.Input` API only (`Input.touches`, `Input.GetTouch`,
   `Input.acceleration`, `Input.gyro`). Do NOT use the Input System package.
3. **UI**: uGUI only (`UnityEngine.UI`). HUD elements anchored by screen fraction via
   `RectTransform.anchorMin/anchorMax`; use `CanvasScaler` (Scale With Screen Size).
4. **Procedural meshes**: build with `Mesh` + `vertices`/`triangles`/`normals`/`uv` arrays,
   then `RecalculateBounds()`. Share materials. See `Core/MeshBuilder`.
5. **Procedural audio**: generate `AudioClip`s at startup via `Core/ProcAudio` (PCM synthesis),
   cache in static dictionaries. Never synthesize per-shot at runtime.
6. **Data over editor**: all content lives in static C# data tables (ported faithfully from the
   Godot `*_defs.gd` files). No ScriptableObjects required, no scene-placed content required —
   the game must boot from code.
7. **No TODO stubs in shipped code.** If a sub-feature cannot be ported cleanly, implement the
   closest faithful version and note the gap in your final report — do not leave empty methods
   that other systems call.
8. **Do NOT touch**: the Godot project (`../project/` — read-only reference), the Flutterwave
   connector/skill, any live keys. Store/economy code stays in TEST mode.
9. Persistence: `Application.persistentDataPath` + JSON (no PlayerPrefs for wallets).

## Cross-system contracts (implement EXACTLY these shapes)

### Arsenal (`NovaMobile.Arsenal`)
```csharp
public enum GunClass { AssaultRifle, SMG, LMG, Sniper, Marksman, Shotgun, Pistol, Launcher, Melee }
public enum AmmoType { Light, Medium, Heavy, Shell, Rocket, Grenade, None }
public struct GunModelSpec {
    public string Style, Mag, Stock, Sight, Muzzle, Body, Accent;
    public float Barrel; public string[] Extras;
}
public struct GunSpec {
    public string Id, Name; public GunClass Class; public AmmoType Ammo;
    public float Damage, HeadMult, Rpm, Range, Recoil, AdsTime, MoveMult;
    public int MagSize; public float ReloadTime; public GunModelSpec Model;
}
public static class GunData {
    public static readonly GunSpec[] Guns;          // all 137, ported from gun_defs.gd
    public static GunSpec Get(string id);
    public static int ShotsToKill(GunSpec g, bool headshot, bool armored);
}
public static class GunFactory {
    // Builds a full gun GameObject; named child parts for mythic accents.
    public static GameObject BuildGun(GunSpec spec, bool firstPerson);
}
public static class GunAudio {
    public static AudioClip ShotClip(string gunId);
    public static AudioClip ReloadClip(string gunId);
}
```

### Vehicles (`NovaMobile.Vehicles`)
```csharp
public enum VehicleType { Sedan, SUV, Pickup, SportsCar, ATV, ArmoredSUV, CargoTruck, Jeep,
    Motorcycle, Tank, Helicopter, Boat, HoverBike, Skateboard, B2Bomber }
public struct VehicleSpec {
    public VehicleType Type; public string Name;
    public float TopSpeed, Acceleration, TurnRate, FuelCapacity, FuelBurnRate;
    public int Seats; public float Health; public bool UsesFuel;
}
public static class VehicleData {
    public static readonly VehicleSpec[] Specs;    // all 15, from vehicle_defs.gd
    public static VehicleSpec Get(VehicleType t);
}
public class VehicleController : MonoBehaviour {
    public VehicleSpec Spec; public float Fuel, Health01 = 1f;
    public bool IsOccupied; public int HornIndex;
    public void Enter(); public void Exit(); public void AddFuel(float a);
}
```

### Classes (`NovaMobile.Classes`)
```csharp
public struct ClassSpec { public string Id, Name; public string ActiveName, PassiveName, Description; }
public static class ClassData {
    public static readonly ClassSpec[] Classes;    // all 30, from class_defs.gd
    public static ClassSpec Get(string id);
}
public abstract class ClassAbility : MonoBehaviour {
    public abstract string ClassId { get; }
    public abstract float Cooldown { get; }
    public abstract bool TryActivate();            // active ability
    public virtual void ApplyPassive() {}          // passive hooks
}
```

### Loot (`NovaMobile.Loot`)
```csharp
public enum Rarity { Common, Uncommon, Rare, Epic, Legendary, Mythic, Relic }  // 7 tiers
public enum LootKind { Health, Armor, Ammo, Cash, Frag, Smoke, Shard, Scorestreak, FuelCan, Attachment }
public struct LootItem {
    public LootKind Kind; public Rarity Rarity; public string GunId; // gunId for weapon loot
    public int Amount; public string AttachmentId;
}
public static class LootTable {
    public static Color RarityColor(Rarity r);
    public static LootItem Roll(Rarity minTier, System.Random rng);
}
```

### Squads (`NovaMobile.Squads`)
```csharp
public struct BotInfo { public string Callsign; public int SquadId; public int Slot; }
public static class BotNames {
    public static readonly string[] Callsigns;     // 100 unique, from bot_names.gd
}
public enum BotBrainState { Wander, Engage, Suppress, Flank, Cover, Peek, Nade, ReviveMate, Rotate }
```

### Economy (`NovaMobile.Economy`)
```csharp
public struct NpPack { public string Id; public int Np; public int Ngn; public float Usd; }
public static class StoreData {
    public static readonly NpPack[] NpPacks;       // 5 packs, from store_defs.gd
    public static readonly DrawDef[] Draws;        // 3 lucky draws
    public static readonly BundleDef[] Bundles;    // 3 bundles
}
public static class NpWallet {
    public static int Balance { get; }
    public static bool Spend(int amount, string reason);
    public static void Add(int amount, string reason);
    public static bool OwnsSkin(string skinId);
    public static void UnlockSkin(string skinId);
}
```

### World (`NovaMobile.World`)
```csharp
public struct PoiInfo { public string Id, Name; public Vector3 Position; public float Radius; }
public static class WorldData {
    public const float WorldSize = 690f;
    public static readonly PoiInfo[] Pois;         // 59 POIs, from world.gd
}
public class Building : MonoBehaviour {
    public LootSpawnPoint[] LootSockets;           // loot system fills these
    public Transform[] CoverPoints;
}
```

### Match (`NovaMobile.Match`)
```csharp
public enum MatchPhase { Lobby, Drop, Combat, Victory, Defeat }
public class MatchManager : MonoBehaviour {        // singleton, DontDestroyOnLoad
    public static MatchManager Instance;
    public MatchPhase Phase;
    public int AliveCount;
}
```

## Game flow (Zenas, hard requirements)

- **One continuous world**: all 14 regions are districts of a single 690×690m NOVA WORLD.
  NO map-selection screen anywhere.
- **Lobby loadout, no pre-match screens**: character, class, weapons, skins, attachments are
  all configured in the main-menu LOADOUT (persisted). Tapping START goes straight into the
  match and the drop-in. `ClassSelectUI` / `GunsmithUI` are lobby panels, never pre-match.
- TPP over-shoulder camera (not first-person). HUD: minimap top-right, compass strip top-center,
  killfeed top-left, class skill button per Player HUD.

## Reporting

Each system agent's final report must list: files created, what was ported faithfully,
what was simplified/changed and why, what remains undone, and any contract deviations.
