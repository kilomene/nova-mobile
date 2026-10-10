using System;
using UnityEngine;

namespace NovaMobile.Classes
{
    /// <summary>
    /// Class identity + gameplay data. The first five fields are the exact cross-system
    /// contract from CONVENTIONS.md; the rest is gameplay data ported from class_defs.gd.
    /// </summary>
    public struct ClassSpec
    {
        // ---- contract fields (CONVENTIONS.md) ----
        public string Id;
        public string Name;
        public string ActiveName;
        public string PassiveName;
        public string Description;

        // ---- extended gameplay data (from class_defs.gd) ----
        public string Profession;      // tracker | support | disrupt | defense | stealth
        public string Tagline;
        public string ActiveDesc;
        public string PassiveDesc;
        public string UpgradeDesc;     // future class-leveling hook (not built)
        public float Cooldown;         // base active cooldown, seconds
        public Color Accent;
    }

    /// <summary>All 30 NOVA BR class definitions, ported faithfully from class_defs.gd.</summary>
    public static class ClassData
    {
        public static readonly string[] Professions =
            { "tracker", "support", "disrupt", "defense", "stealth" };

        public static string ProfessionDisplayName(string prof)
        {
            switch (prof)
            {
                case "tracker": return "TRACKER";
                case "support": return "SUPPORT";
                case "disrupt": return "DISRUPT";
                case "defense": return "DEFENSE";
                case "stealth": return "STEALTH";
                default: return prof.ToUpperInvariant();
            }
        }

        public static Color ProfessionColor(string prof)
        {
            switch (prof)
            {
                case "tracker": return new Color(1.0f, 0.72f, 0.15f);
                case "support": return new Color(0.25f, 0.85f, 0.45f);
                case "disrupt": return new Color(0.75f, 0.35f, 1.0f);
                case "defense": return new Color(0.3f, 0.6f, 1.0f);
                case "stealth": return new Color(0.65f, 0.65f, 0.7f);
                default: return Color.white;
            }
        }

        /// <summary>Profession-wide always-on passive (stacks with the class passive).</summary>
        public static string ProfessionPassive(string prof)
        {
            switch (prof)
            {
                case "tracker": return "Enemies you damage are marked for 5s. +10% move speed.";
                case "support": return "Healing 40% stronger. Health regen starts 2s sooner.";
                case "disrupt": return "+15% move speed for 6s after using your skill.";
                case "defense": return "-35% explosive damage. -25% zone damage.";
                case "stealth": return "Enemies notice you 30% later. -15% damage taken while sprinting.";
                default: return "";
            }
        }

        public static readonly ClassSpec[] Classes = {
            // ---------------- TRACKER ----------------
            new ClassSpec { Id = "pathfinder", Name = "Pathfinder", Profession = "tracker",
                Tagline = "Recon specialist — nothing hides for long.",
                ActiveName = "Sensor Dart", Cooldown = 35f,
                ActiveDesc = "Fire a sensor dart: on landing it scans 30m and marks every enemy — live pings with a countdown, visible through walls.",
                PassiveName = "Bloodhound",
                PassiveDesc = "+20% ADS speed. Damaged enemies stay marked 6s.",
                Description = "Recon specialist — nothing hides for long.",
                Accent = new Color(1.0f, 0.72f, 0.15f),
                UpgradeDesc = "Upgraded: scan radius 45m, marks also reveal enemy class icons." },
            new ClassSpec { Id = "kennelmaster", Name = "Kennelmaster", Profession = "tracker",
                Tagline = "Two guns are good. Fangs are better.",
                ActiveName = "Cyber-Hound", Cooldown = 50f,
                ActiveDesc = "Deploy a cyber-hound that hunts the nearest enemy for 20s — fast, loud, and very bitey. Enemies prioritize it over you.",
                PassiveName = "Pheromone Field",
                PassiveDesc = "Enemies engage you 20% later while your hound is active.",
                Description = "Two guns are good. Fangs are better.",
                Accent = new Color(1.0f, 0.72f, 0.15f),
                UpgradeDesc = "Upgraded: two hounds, 30s duration, hounds explode for 20 damage when killed." },
            new ClassSpec { Id = "saboteur", Name = "Saboteur", Profession = "tracker",
                Tagline = "Their toys stop working around you.",
                ActiveName = "EMP Drone", Cooldown = 55f,
                ActiveDesc = "Launch a drone that seeks the nearest enemy and pulses EMP for 15s — slows them 50% and silences their gunfire in bursts.",
                PassiveName = "Engineer Sight",
                PassiveDesc = "Enemy traps, turrets and deployables glow red through walls.",
                Description = "Their toys stop working around you.",
                Accent = new Color(1.0f, 0.72f, 0.15f),
                UpgradeDesc = "Upgraded: drone also disables enemy class skills for 6s." },
            new ClassSpec { Id = "skyhook", Name = "Skyhook", Profession = "tracker",
                Tagline = "Why walk around the mountain.",
                ActiveName = "Catapult Pad", Cooldown = 45f,
                ActiveDesc = "Drop a launch pad: step on it to blast 25m skyward and steer a dive-bomb glide — slam down for an AoE stun.",
                PassiveName = "Extended Glide",
                PassiveDesc = "Drop-in gliding is 30% faster and more responsive.",
                Description = "Why walk around the mountain.",
                Accent = new Color(1.0f, 0.72f, 0.15f),
                UpgradeDesc = "Upgraded: landing slam stuns 4s and the pad can be reused twice." },
            new ClassSpec { Id = "ballista", Name = "Ballista", Profession = "tracker",
                Tagline = "Artillery with a targeting computer.",
                ActiveName = "Smart Mortar", Cooldown = 60f,
                ActiveDesc = "Deploy a smart mortar: 6 guided shells arc onto the nearest visible enemy over 8s. Destroyable (60 HP).",
                PassiveName = "Demolitions",
                PassiveDesc = "+25% explosive damage (rockets, grenades, RP-7).",
                Description = "Artillery with a targeting computer.",
                Accent = new Color(1.0f, 0.72f, 0.15f),
                UpgradeDesc = "Upgraded: 10 shells, anti-vehicle lock-on, smoke-screen mode." },
            // ---------------- SUPPORT ----------------
            new ClassSpec { Id = "surgeon", Name = "Surgeon", Profession = "support",
                Tagline = "Patch up. Push forward.",
                ActiveName = "Trauma Station", Cooldown = 40f,
                ActiveDesc = "Deploy a station healing 12 HP/s in 6m for 12s — cleanses slows and over-heals into temporary bonus HP.",
                PassiveName = "Master Healer",
                PassiveDesc = "All healing 50% stronger. Regen starts even sooner.",
                Description = "Patch up. Push forward.",
                Accent = new Color(0.25f, 0.85f, 0.45f),
                UpgradeDesc = "Upgraded: station also repairs armor and revives 50% faster nearby." },
            new ClassSpec { Id = "quartermaster", Name = "Quartermaster", Profession = "support",
                Tagline = "Logistics wins firefights.",
                ActiveName = "Supply Drop", Cooldown = 45f,
                ActiveDesc = "Call in 3 supply packs: +50 armor plates and bonus ammo each. Yours to share.",
                PassiveName = "Deep Pockets",
                PassiveDesc = "Skill recharges 20% faster. +1 grenade capacity, +50% ammo from pickups.",
                Description = "Logistics wins firefights.",
                Accent = new Color(0.25f, 0.85f, 0.45f),
                UpgradeDesc = "Upgraded: packs also grant a free skill-charge refill." },
            new ClassSpec { Id = "aegis", Name = "Aegis", Profession = "support",
                Tagline = "Bring a wall to a gunfight.",
                ActiveName = "Kinetic Dome", Cooldown = 50f,
                ActiveDesc = "Raise a 5m kinetic dome for 10s: -50% bullet damage inside. Yours. Theirs? No.",
                PassiveName = "Bulwark Start",
                PassiveDesc = "Begin every match with 50 armor plated.",
                Description = "Bring a wall to a gunfight.",
                Accent = new Color(0.25f, 0.85f, 0.45f),
                UpgradeDesc = "Upgraded: dome reflects 30% damage back and becomes mobile." },
            new ClassSpec { Id = "phoenix", Name = "Phoenix", Profession = "support",
                Tagline = "Death is a suggestion.",
                ActiveName = "Guardian Drone", Cooldown = 55f,
                ActiveDesc = "Launch a guardian drone that orbits you for 15s, shredding the nearest enemy on sight.",
                PassiveName = "Second Life",
                PassiveDesc = "Once per match, lethal damage revives you at 50 HP instead of killing you.",
                Description = "Death is a suggestion.",
                Accent = new Color(0.25f, 0.85f, 0.45f),
                UpgradeDesc = "Upgraded: drone lasts 25s; self-revive restores full HP + brief speed." },
            new ClassSpec { Id = "replicator", Name = "Replicator", Profession = "support",
                Tagline = "One man's loot is everyone's loot.",
                ActiveName = "Tactical Mirror", Cooldown = 60f,
                ActiveDesc = "Deploy a mirror that duplicates the 3 nearest loot pickups — and instantly halves your remaining skill cooldown.",
                PassiveName = "Lucky Scavenger",
                PassiveDesc = "+25% ammo from pickups. 20% chance gun rolls come out a tier hotter.",
                Description = "One man's loot is everyone's loot.",
                Accent = new Color(0.25f, 0.85f, 0.45f),
                UpgradeDesc = "Upgraded: bank one duplicate for later; mirror also copies armor." },
            // ---------------- DISRUPT ----------------
            new ClassSpec { Id = "warden", Name = "Warden", Profession = "disrupt",
                Tagline = "This hallway is closed.",
                ActiveName = "Arc Trap", Cooldown = 30f,
                ActiveDesc = "Place a high-voltage trap (chain up to 3): enemies inside are slowed 50% and zapped 8 dps for 10s.",
                PassiveName = "Overclock",
                PassiveDesc = "Skill recharges 25% faster.",
                Description = "This hallway is closed.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: traps link into a chain-lightning web; add alarm + EMP variants." },
            new ClassSpec { Id = "chronos", Name = "Chronos", Profession = "disrupt",
                Tagline = "That never happened.",
                ActiveName = "Time Rewind", Cooldown = 55f,
                ActiveDesc = "Snap back to where — and how healthy — you were 8 seconds ago. Leaves a time-echo decoy at your departure point.",
                PassiveName = "Temporal Flow",
                PassiveDesc = "+10% move speed. You just walk like you own time.",
                Description = "That never happened.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: rewind 12s; echo decoy shoots fake tracers." },
            new ClassSpec { Id = "mirage", Name = "Mirage", Profession = "disrupt",
                Tagline = "Now you see me. Now you don't. Now you see someone else.",
                ActiveName = "Holo Decoys", Cooldown = 40f,
                ActiveDesc = "Spawn 2 holographic decoys with scripted behavior (one flees, one returns fire with fake tracers) while you turn invisible for 3s.",
                PassiveName = "Parting Gift",
                PassiveDesc = "Destroyed decoys detonate for 15 damage.",
                Description = "Now you see me. Now you don't. Now you see someone else.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: 3 decoys; invisibility lasts 5s and muffles reloads." },
            new ClassSpec { Id = "wildfire", Name = "Wildfire", Profession = "disrupt",
                Tagline = "Smoke that bites back.",
                ActiveName = "Hunter Smoke", Cooldown = 35f,
                ActiveDesc = "Launch a canister 25m: 8m smoke cloud for 12s that slows enemies 40% and MARKS them through the haze.",
                PassiveName = "Smoke Runner",
                PassiveDesc = "You move 20% faster in smoke and ignore its slow.",
                Description = "Smoke that bites back.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: selectable payloads — flash-smoke blinds, EMP-smoke kills drones, heal-smoke buffs allies." },
            new ClassSpec { Id = "ghost", Name = "Ghost", Profession = "disrupt",
                Tagline = "You never saw the signal die.",
                ActiveName = "Signal Jam", Cooldown = 45f,
                ActiveDesc = "20m jam bubble for 10s: enemies inside stop engaging and wander, their gadgets die. Spoofs fake blips on their senses.",
                PassiveName = "Clean Signal",
                PassiveDesc = "Immune to enemy jams and EMP slows.",
                Description = "You never saw the signal die.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: hijack one enemy gadget inside the bubble." },
            new ClassSpec { Id = "bulwark", Name = "Bulwark", Profession = "disrupt",
                Tagline = "The room disagrees with you.",
                ActiveName = "Shockwave Pulse", Cooldown = 30f,
                ActiveDesc = "Radial shockwave: hurls enemies back 8m and stuns their gunfire for 3s. Room cleared.",
                PassiveName = "Immovable",
                PassiveDesc = "Immune to knockback. -20% explosive damage.",
                Description = "The room disagrees with you.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: aimable cone or 360°; reflects projectiles back." },
            new ClassSpec { Id = "ventriloquist", Name = "Ventriloquist", Profession = "disrupt",
                Tagline = "Did you hear that? No? Exactly.",
                ActiveName = "Phantom Firefight", Cooldown = 35f,
                ActiveDesc = "Plant a phantom sound source anywhere in 30m: enemies hear a full firefight and rotate to investigate for 8s.",
                PassiveName = "Quick Tongue",
                PassiveDesc = "+10% move speed.",
                Description = "Did you hear that? No? Exactly.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: also fakes your minimap signature; two phantoms at once." },
            new ClassSpec { Id = "volt", Name = "Volt", Profession = "disrupt",
                Tagline = "Weather advisory: you.",
                ActiveName = "Chain Lightning", Cooldown = 40f,
                ActiveDesc = "Lightning arcs across up to 4 clustered enemies (25 dmg + 3s slow) — then overcharges your weapon with shock rounds for 6s.",
                PassiveName = "Live Wire",
                PassiveDesc = "+10% weapon damage.",
                Description = "Weather advisory: you.",
                Accent = new Color(0.75f, 0.35f, 1.0f),
                UpgradeDesc = "Upgraded: arcs to 6 targets; overcharge also chains on hit." },
            // ---------------- DEFENSE ----------------
            new ClassSpec { Id = "rampart", Name = "Rampart", Profession = "defense",
                Tagline = "Cover, on demand.",
                ActiveName = "Aegis Wall", Cooldown = 40f,
                ActiveDesc = "Slam down a 3m ballistic wall (120 HP, blocks sightlines) that flashbangs nearby enemies on deploy. Pick it up, move it, re-place it.",
                PassiveName = "Reinforced",
                PassiveDesc = "-40% non-bullet damage (explosives, zone ticks, melee).",
                Description = "Cover, on demand.",
                Accent = new Color(0.3f, 0.6f, 1.0f),
                UpgradeDesc = "Upgraded: one-way firing wall — you shoot out, they can't shoot in." },
            new ClassSpec { Id = "lastword", Name = "Last Word", Profession = "defense",
                Tagline = "The argument-ender.",
                ActiveName = "Sentry Turret", Cooldown = 60f,
                ActiveDesc = "Deploy an auto-turret (100 HP, 60s): tracks and shreds the nearest enemy while you keep moving.",
                PassiveName = "Last Stand",
                PassiveDesc = "Once per match, lethal damage leaves you at 25 HP instead of killing you.",
                Description = "The argument-ender.",
                Accent = new Color(0.3f, 0.6f, 1.0f),
                UpgradeDesc = "Upgraded: twin barrels; Last Stand keeps your full primary." },
            new ClassSpec { Id = "overlord", Name = "Overlord", Profession = "defense",
                Tagline = "Danger close? Good.",
                ActiveName = "Cluster Strike", Cooldown = 75f,
                ActiveDesc = "Paint a target with the laser designator: 2s later, 5 airstrikes walk a 12m zone over 4s. Devastating in late zones.",
                PassiveName = "Fly Swatter",
                PassiveDesc = "+50% launcher reload speed. +15% launcher damage.",
                Description = "Danger close? Good.",
                Accent = new Color(0.3f, 0.6f, 1.0f),
                UpgradeDesc = "Upgraded: selectable patterns — cluster, precision single, smoke barrage." },
            new ClassSpec { Id = "pyre", Name = "Pyre", Profession = "defense",
                Tagline = "The floor is lava. Literally.",
                ActiveName = "Tar Bag", Cooldown = 35f,
                ActiveDesc = "Hurl a tar bag: 6m pool slows enemies 60% and burns 6 dps. Detonate it on command for a 40-damage fireburst.",
                PassiveName = "Firebug",
                PassiveDesc = "+20% area damage. Your own flames never hurt you.",
                Description = "The floor is lava. Literally.",
                Accent = new Color(0.3f, 0.6f, 1.0f),
                UpgradeDesc = "Upgraded: tar sticks to vehicles and wrecks their handling." },
            new ClassSpec { Id = "fallout", Name = "Fallout", Profession = "defense",
                Tagline = "Enter the hot zone. It's yours.",
                ActiveName = "Radiation Zone", Cooldown = 45f,
                ActiveDesc = "Dose a 7m zone for 15s: 10 dps ramping +5/s the longer enemies linger. You are immune — fight inside your own storm.",
                PassiveName = "Lead Lining",
                PassiveDesc = "-25% zone damage. Your radiation never touches you.",
                Description = "Enter the hot zone. It's yours.",
                Accent = new Color(0.3f, 0.6f, 1.0f),
                UpgradeDesc = "Upgraded: hot core melts armor first; zone follows you slowly." },
            // ---------------- STEALTH ----------------
            new ClassSpec { Id = "spider", Name = "Spider", Profession = "stealth",
                Tagline = "Walls are just suggestions.",
                ActiveName = "Grapple Hook", Cooldown = 25f,
                ActiveDesc = "Fire a hook up to 40m and get yanked to it — rooftops, towers, ridgelines. Drop onto an enemy from above for 75 melee damage.",
                PassiveName = "Dead Silence",
                PassiveDesc = "Enemies notice you 35% later.",
                Description = "Walls are just suggestions.",
                Accent = new Color(0.65f, 0.65f, 0.7f),
                UpgradeDesc = "Upgraded: 3 charges; silent takedown bonus on grapple kills." },
            new ClassSpec { Id = "wraith", Name = "Wraith", Profession = "stealth",
                Tagline = "You felt watched. You were wrong.",
                ActiveName = "Active Camo", Cooldown = 45f,
                ActiveDesc = "Near-invisibility for 8s. Move freely — firing breaks it. They can't hit what they can't see.",
                PassiveName = "Ghost Rounds",
                PassiveDesc = "First 3s after camo breaks: +50% damage.",
                Description = "You felt watched. You were wrong.",
                Accent = new Color(0.65f, 0.65f, 0.7f),
                UpgradeDesc = "Upgraded: no footprints, muffled reloads, 12s duration." },
            new ClassSpec { Id = "comet", Name = "Comet", Profession = "stealth",
                Tagline = "Gravity is negotiable.",
                ActiveName = "Nitrogen Leap", Cooldown = 30f,
                ActiveDesc = "Blast 12m skyward on nitrogen with full air control for 4s — then ground-slam for 30 AoE damage in 5m.",
                PassiveName = "Light Frame",
                PassiveDesc = "+20% jump height. -50% fall damage.",
                Description = "Gravity is negotiable.",
                Accent = new Color(0.65f, 0.65f, 0.7f),
                UpgradeDesc = "Upgraded: air-dodge charges; slam keeps full firing accuracy." },
            new ClassSpec { Id = "ronin", Name = "Ronin", Profession = "stealth",
                Tagline = "One cut. Maybe three.",
                ActiveName = "Katana Dash", Cooldown = 30f,
                ActiveDesc = "12m blade dash through enemies (50 dmg each, chains up to 3 targets). For 1.5s after, incoming bullets are deflected.",
                PassiveName = "Iaido",
                PassiveDesc = "+25% melee damage. +2m melee lunge.",
                Description = "One cut. Maybe three.",
                Accent = new Color(0.65f, 0.65f, 0.7f),
                UpgradeDesc = "Upgraded: each kill refunds a dash charge; deflected bullets fly back." },
            new ClassSpec { Id = "valkyrie", Name = "Valkyrie", Profession = "stealth",
                Tagline = "Air superiority, personal scale.",
                ActiveName = "Jetpack", Cooldown = 50f,
                ActiveDesc = "6s of true flight toward your aim — hover-ADS mid-air, then slam-cancel into a silent slide landing.",
                PassiveName = "Soft Landing",
                PassiveDesc = "No landing recovery. -50% fall damage.",
                Description = "Air superiority, personal scale.",
                Accent = new Color(0.65f, 0.65f, 0.7f),
                UpgradeDesc = "Upgraded: fuel management; hover-aim mode; silent landings." },
            new ClassSpec { Id = "gatekeeper", Name = "Gatekeeper", Profession = "stealth",
                Tagline = "Be nowhere. Then be there.",
                ActiveName = "Blink Beacon", Cooldown = 40f,
                ActiveDesc = "Throw a beacon up to 20m; trigger again within 30s to blink to it, keeping your momentum for trick plays.",
                PassiveName = "Attuned",
                PassiveDesc = "Skill recharges 20% faster.",
                Description = "Be nowhere. Then be there.",
                Accent = new Color(0.65f, 0.65f, 0.7f),
                UpgradeDesc = "Upgraded: 3 linked beacons; beacon throwable like a grenade." },
            new ClassSpec { Id = "trampoline", Name = "Trampoline", Profession = "stealth",
                Tagline = "The floor sends its regards.",
                ActiveName = "Bounce Pad", Cooldown = 30f,
                ActiveDesc = "Deploy a pad that launches anyone 15m skyward — you, teammates, enemies. Remote-detonate it to launch enemies on demand.",
                PassiveName = "Spring Loaded",
                PassiveDesc = "Your pads launch you 30% higher. -50% fall damage.",
                Description = "The floor sends its regards.",
                Accent = new Color(0.65f, 0.65f, 0.7f),
                UpgradeDesc = "Upgraded: adjustable angle/power; catch-net mode saves falling teammates." },
        };

        public static ClassSpec Get(string id)
        {
            for (int i = 0; i < Classes.Length; i++)
                if (Classes[i].Id == id) return Classes[i];
            return default(ClassSpec);
        }

        public static bool TryGet(string id, out ClassSpec spec)
        {
            for (int i = 0; i < Classes.Length; i++)
                if (Classes[i].Id == id) { spec = Classes[i]; return true; }
            spec = default(ClassSpec);
            return false;
        }

        public static string[] Ids()
        {
            var ids = new string[Classes.Length];
            for (int i = 0; i < Classes.Length; i++) ids[i] = Classes[i].Id;
            return ids;
        }

        public static int Count => Classes.Length;
    }
}
