using System;
using UnityEngine;

namespace NovaMobile.Classes
{
    /// <summary>
    /// Instantiates the concrete ability component for a class id.
    /// Attach one ability per actor; it wires itself to the IClassBody on the
    /// same GameObject and runs ApplyPassive() for instant match-start effects.
    /// </summary>
    public static class ClassAbilityRegistry
    {
        public static ClassAbility Attach(GameObject owner, string classId)
        {
            if (owner == null) throw new ArgumentNullException(nameof(owner));
            Type t = TypeFor(classId);
            var ability = (ClassAbility)owner.AddComponent(t);
            ability.ApplyPassive();
            return ability;
        }

        public static bool Has(string classId)
        {
            ClassSpec spec;
            return ClassData.TryGet(classId, out spec);
        }

        public static Type TypeFor(string classId)
        {
            switch (classId)
            {
                case "pathfinder": return typeof(PathfinderAbility);
                case "kennelmaster": return typeof(KennelmasterAbility);
                case "saboteur": return typeof(SaboteurAbility);
                case "skyhook": return typeof(SkyhookAbility);
                case "ballista": return typeof(BallistaAbility);
                case "surgeon": return typeof(SurgeonAbility);
                case "quartermaster": return typeof(QuartermasterAbility);
                case "aegis": return typeof(AegisAbility);
                case "phoenix": return typeof(PhoenixAbility);
                case "replicator": return typeof(ReplicatorAbility);
                case "warden": return typeof(WardenAbility);
                case "chronos": return typeof(ChronosAbility);
                case "mirage": return typeof(MirageAbility);
                case "wildfire": return typeof(WildfireAbility);
                case "ghost": return typeof(GhostAbility);
                case "bulwark": return typeof(BulwarkAbility);
                case "ventriloquist": return typeof(VentriloquistAbility);
                case "volt": return typeof(VoltAbility);
                case "rampart": return typeof(RampartAbility);
                case "lastword": return typeof(LastWordAbility);
                case "overlord": return typeof(OverlordAbility);
                case "pyre": return typeof(PyreAbility);
                case "fallout": return typeof(FalloutAbility);
                case "spider": return typeof(SpiderAbility);
                case "wraith": return typeof(WraithAbility);
                case "comet": return typeof(CometAbility);
                case "ronin": return typeof(RoninAbility);
                case "valkyrie": return typeof(ValkyrieAbility);
                case "gatekeeper": return typeof(GatekeeperAbility);
                case "trampoline": return typeof(TrampolineAbility);
                default: throw new ArgumentException("Unknown class id: " + classId, nameof(classId));
            }
        }
    }
}
