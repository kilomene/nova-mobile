using System.Collections.Generic;

namespace NovaMobile.Squads
{
    /// <summary>
    /// Identity of one combatant in the 100-bot lobby.
    /// Exact contract shape from CONVENTIONS.md.
    /// </summary>
    public struct BotInfo
    {
        public string Callsign;
        public int SquadId;
        public int Slot;
    }

    /// <summary>
    /// The 100-combatant identity roster, ported exactly from bot_names.gd.
    /// Every bot in a BR match keeps one unique callsign for the whole match —
    /// killfeed, squad plates, and radio barks all use it.
    /// NOVA-original tactical callsigns.
    /// </summary>
    public static class BotNames
    {
        public static readonly string[] Callsigns = {
            "VIPER", "ANVIL", "GHOST", "REAPER", "FALCON", "COBRA", "JAGUAR",
            "PANTHER", "WOLF", "BEAR", "TIGER", "LION", "SHARK", "RAVEN",
            "HAWK", "EAGLE", "CONDOR", "PYTHON", "MAMBA", "SCORPION",
            "HORNET", "WASP", "BISON", "RHINO", "HIPPO", "CROCODILE",
            "LEOPARD", "CHEETAH", "HYENA", "VULTURE", "COYOTE", "BADGER",
            "OTTER", "WEASEL", "FERRET", "MONGOOSE", "JACKAL", "DINGO",
            "LYNX", "OCELOT", "CARACAL", "SERVAL", "CIVET", "GENET",
            "KUDU", "ORYX", "GAZELLE", "IMPALA", "SPRINGBOK", "ELAND",
            "BUFFALO", "WARTHOG", "AARDVARK", "PANGOLIN", "MEERKAT", "BAT",
            "OWL", "KITE", "HARRIER", "OSPREY", "BUZZARD", "GOSHAWK",
            "SPARROWHAWK", "KESTREL", "MERLIN", "PEREGRINE", "SAKER", "LANNER",
            "GYRFALCON", "TERN", "GULL", "PETREL", "ALBATROSS", "SHEARWATER",
            "GANNET", "CORMORANT", "HERON", "EGRET", "IBIS", "STORK",
            "CRANE", "FLAMINGO", "PELICAN", "SPOONBILL", "HAMERKOP", "SHOEBILL",
            "TURACO", "HORNBILL", "BEEEATER", "ROLLER", "KINGFISHER", "HOOPOE",
            "WOODPECKER", "BARBET", "HONEYGUIDE", "MOUSEBIRD", "TROGON", "CUCKOO",
            "COUCAL", "NOMAD",
        };

        /// <summary>Radio barks: short callouts bots (and allies) emit on the radio net.</summary>
        public static readonly string[] BarkEngage = {
            "Contact!", "Hostile spotted!", "Weapons free!", "Tango in sight!", "Engaging!"
        };
        public static readonly string[] BarkKill = {
            "Hostile down.", "Target neutralized.", "Splash one.", "Good hit."
        };
        public static readonly string[] BarkDowned = {
            "I'm hit! I'm hit!", "Man down!", "Taking fire!"
        };
        public static readonly string[] BarkRevive = {
            "Reviving!", "Got you — hold on!", "Patching you up!"
        };
        public static readonly string[] BarkRotate = {
            "Moving to zone!", "Rotate, rotate!", "Zone's moving — go!"
        };
        public static readonly string[] BarkGrenade = {
            "Frag out!", "Grenade!", "Throwing frag!"
        };
        public static readonly string[] BarkReloading = {
            "Reloading!", "Changing mags!", "Cover me!"
        };

        public static int Count() { return Callsigns.Length; }

        public static bool UniqueCheck()
        {
            var seen = new HashSet<string>();
            for (int i = 0; i < Callsigns.Length; i++)
            {
                if (!seen.Add(Callsigns[i])) return false;
            }
            return true;
        }

        /// <summary>
        /// Draw an unused callsign; falls back to a numbered OPERATIVE callsign
        /// if the roster is exhausted (keeps uniqueness).
        /// </summary>
        public static string Pick(System.Random rng, HashSet<string> used)
        {
            for (int i = 0; i < Callsigns.Length; i++)
            {
                string n = Callsigns[rng.Next(Callsigns.Length)];
                if (!used.Contains(n))
                {
                    used.Add(n);
                    return n;
                }
            }
            int k = used.Count;
            string fallback = "OPERATIVE-" + k;
            used.Add(fallback);
            return fallback;
        }

        public static string Bark(string[] pool, System.Random rng)
        {
            if (pool == null || pool.Length == 0) return "";
            return pool[rng.Next(pool.Length)];
        }
    }
}
