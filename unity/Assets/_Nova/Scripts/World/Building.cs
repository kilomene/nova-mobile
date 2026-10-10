using UnityEngine;

namespace NovaMobile.World
{
    /// <summary>
    /// Marker for a loot spawn socket inside a building. The Loot system finds these
    /// (via Building.LootSockets) and instantiates loot items at their positions.
    /// Tier biases the rarity roll, mirroring the tier field the Godot loot_spots carry.
    /// </summary>
    public class LootSpawnPoint : MonoBehaviour
    {
        [Tooltip("Rarity tier bias: 1 = ground floor/common, 2 = upper floor/roof.")]
        public int Tier = 1;
    }

    /// <summary>
    /// Enterable building produced by BuildingFactory. Contract shape per CONVENTIONS.md:
    /// LootSockets are filled by the Loot system; CoverPoints are AI cover anchors.
    /// Geometry is batched into the region's WorldBatch (no per-building renderers).
    /// </summary>
    public class Building : MonoBehaviour
    {
        public LootSpawnPoint[] LootSockets;
        public Transform[] CoverPoints;

        public BuildingArchetype Archetype;
        public float Width;
        public float Depth;
        public int Floors;
        public float FloorHeight;
    }
}
