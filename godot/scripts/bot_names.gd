class_name BotNames
extends RefCounted
## NOVA Mobile: the 100-combatant identity roster. Every bot in a BR match
## keeps one unique callsign for the whole match — killfeed, squad plates,
## and radio barks all use it. NOVA-original tactical callsigns.

const NAMES := [
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
]

## Radio barks: short callouts bots (and allies) emit on the radio net.
## Shown in the killfeed with the speaker's callsign.
const BARK_ENGAGE := ["Contact!", "Hostile spotted!", "Weapons free!",
	"Tango in sight!", "Engaging!"]
const BARK_KILL := ["Hostile down.", "Target neutralized.", "Splash one.",
	"Good hit."]
const BARK_DOWNED := ["I'm hit! I'm hit!", "Man down!", "Taking fire!"]
const BARK_REVIVE := ["Reviving!", "Got you — hold on!", "Patching you up!"]
const BARK_ROTATE := ["Moving to zone!", "Rotate, rotate!", "Zone's moving — go!"]
const BARK_GRENADE := ["Frag out!", "Grenade!", "Throwing frag!"]
const BARK_RELOADING := ["Reloading!", "Changing mags!", "Cover me!"]


static func count() -> int:
	return NAMES.size()


static func unique_check() -> bool:
	var seen := {}
	for n in NAMES:
		if seen.has(n):
			return false
		seen[n] = true
	return true


static func pick(rng: RandomNumberGenerator, used: Dictionary) -> String:
	# Draw an unused name; falls back to a numbered callsign if exhausted.
	for i in range(NAMES.size()):
		var idx := rng.randi() % NAMES.size()
		var n: String = NAMES[idx]
		if not used.has(n):
			used[n] = true
			return n
	var k := used.size()
	used["OPERATIVE-%d" % k] = true
	return "OPERATIVE-%d" % k


static func bark(pool: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	return str(pool[rng.randi() % pool.size()])
