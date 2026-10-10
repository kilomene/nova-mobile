class_name GunAudio
extends RefCounted
## Procedural weapon audio: all sounds synthesized in code as AudioStreamWAV.
## One base sound per weapon class + per-gun pitch via playback pitch_scale.
## No external audio files.

const MIX_RATE := 22050

# class -> {dur, crack (noise decay), body_freq, body_decay, thump}
const CLASS_SOUND := {
	"ar": {"dur": 0.32, "crack": 900.0, "body": 160.0, "bdecay": 22.0, "thump": 75.0},
	"smg": {"dur": 0.26, "crack": 1100.0, "body": 200.0, "bdecay": 26.0, "thump": 85.0},
	"lmg": {"dur": 0.38, "crack": 750.0, "body": 130.0, "bdecay": 18.0, "thump": 65.0},
	"sniper": {"dur": 0.55, "crack": 550.0, "body": 100.0, "bdecay": 12.0, "thump": 55.0},
	"marksman": {"dur": 0.40, "crack": 700.0, "body": 130.0, "bdecay": 16.0, "thump": 65.0},
	"shotgun": {"dur": 0.45, "crack": 500.0, "body": 110.0, "bdecay": 14.0, "thump": 60.0},
	"pistol": {"dur": 0.24, "crack": 1300.0, "body": 230.0, "bdecay": 30.0, "thump": 95.0},
	"launcher": {"dur": 0.70, "crack": 300.0, "body": 80.0, "bdecay": 8.0, "thump": 45.0},
	"melee": {"dur": 0.22, "crack": 2500.0, "body": 400.0, "bdecay": 40.0, "thump": 0.0},
}

static var _cache := {}


static func fire_stream(cls: String) -> AudioStreamWAV:
	var key := "fire_" + cls
	if _cache.has(key):
		return _cache[key]
	var p: Dictionary = CLASS_SOUND.get(cls, CLASS_SOUND["ar"])
	var s := _synthesize(float(p["dur"]), float(p["crack"]), float(p["body"]),
		float(p["bdecay"]), float(p["thump"]), cls == "melee")
	_cache[key] = s
	return s


static func reload_stream() -> AudioStreamWAV:
	if _cache.has("reload"):
		return _cache["reload"]
	# Two metallic clicks: short noise bursts with fast decay, 0.12s apart.
	var n := int(MIX_RATE * 0.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v := 0.0
		for c in [0.0, 0.14]:
			var dt: float = t - c
			if dt > 0.0 and dt < 0.05:
				v += (rng.randf() * 2.0 - 1.0) * exp(-dt * 160.0) * 0.7
				v += sin(dt * 2400.0 * TAU) * exp(-dt * 200.0) * 0.3
		_write_s16(data, i, clampf(v, -1.0, 1.0))
	var s := _make_stream(data)
	_cache["reload"] = s
	return s


static func dry_stream() -> AudioStreamWAV:
	if _cache.has("dry"):
		return _cache["dry"]
	var n := int(MIX_RATE * 0.09)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v := (rng.randf() * 2.0 - 1.0) * exp(-t * 220.0) * 0.5
		v += sin(t * 1800.0 * TAU) * exp(-t * 260.0) * 0.25
		_write_s16(data, i, clampf(v, -1.0, 1.0))
	var s := _make_stream(data)
	_cache["dry"] = s
	return s


static func explosion_stream() -> AudioStreamWAV:
	if _cache.has("explosion"):
		return _cache["explosion"]
	var n := int(MIX_RATE * 1.1)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var lp := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		lp = lp * 0.92 + noise * 0.08  # crude lowpass -> rumble
		var v := lp * exp(-t * 5.0) * 1.4 + noise * exp(-t * 30.0) * 0.5
		v += sin(t * 48.0 * TAU) * exp(-t * 7.0) * 0.8  # sub thump
		_write_s16(data, i, clampf(v, -1.0, 1.0))
	var s := _make_stream(data)
	_cache["explosion"] = s
	return s


static func swing_stream() -> AudioStreamWAV:
	# Whoosh: band-swept noise.
	return fire_stream("melee")


## Per-gun fire sound: class base params modified by the gun's "sound" mods
## ({dur, crack, body, decay, thump} multipliers, all optional) and its
## "silent" flag (muffled synthesis). Lazily synthesized + cached per gun id.
static func fire_stream_for(gun_id: String) -> AudioStreamWAV:
	var key := "gun_" + gun_id
	if _cache.has(key):
		return _cache[key]
	var g := GunDefs.by_id(gun_id)
	var cls: String = str(g.get("cls", "ar"))
	var p: Dictionary = CLASS_SOUND.get(cls, CLASS_SOUND["ar"])
	var sm: Dictionary = g.get("sound", {})
	var dur := float(p["dur"]) * float(sm.get("dur", 1.0))
	var crack := float(p["crack"]) * float(sm.get("crack", 1.0))
	var body := float(p["body"]) * float(sm.get("body", 1.0))
	var bdecay := float(p["bdecay"]) * float(sm.get("decay", 1.0))
	var thump := float(p["thump"]) * float(sm.get("thump", 1.0))
	var seed: int = absi(gun_id.hash()) % 900000 + 7
	var s: AudioStreamWAV
	if float(sm.get("whoosh", 0.0)) > 0.0:
		# Rocket launch: long band-swept whoosh instead of a gunshot crack.
		s = _synthesize_seed(0.9 * float(sm.get("dur", 1.0)), crack, body, bdecay, thump, true, seed)
	elif bool(g.get("silent", false)):
		s = _synthesize_muffled(dur, crack, body, bdecay, thump, seed)
	else:
		s = _synthesize_seed(dur, crack, body, bdecay, thump, false, seed)
	_cache[key] = s
	return s


## Suppressed variant: heavy lowpass on the crack, shorter tail, soft thump.
static func _synthesize_muffled(dur: float, crack: float, body: float,
		bdecay: float, thump: float, seed: int) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur * 0.8)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		lp = lp * 0.90 + noise * 0.10   # muffle the crack hard
		lp2 = lp2 * 0.97 + lp * 0.03
		var v := lp2 * exp(-t * crack * 0.5) * 1.1
		v += sin(t * body * TAU) * exp(-t * bdecay * 1.4) * 0.35
		if thump > 0.0:
			v += sin(t * thump * 0.6 * TAU) * exp(-t * 22.0) * 0.4
		_write_s16(data, i, clampf(v, -1.0, 1.0))
	return _make_stream(data)


static func _synthesize_seed(dur: float, crack: float, body: float, bdecay: float,
		thump: float, whoosh: bool, seed: int) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lp := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		var v := 0.0
		if whoosh:
			lp = lp * 0.985 + noise * 0.015
			v = lp * sin(t * PI / dur) * 2.2
		else:
			v = noise * exp(-t * crack) * 0.85
			v += sin(t * body * TAU) * exp(-t * bdecay) * 0.55
			if thump > 0.0:
				v += sin(t * thump * TAU) * exp(-t * 18.0) * 0.6
		_write_s16(data, i, clampf(v, -1.0, 1.0))
	return _make_stream(data)


static func _synthesize(dur: float, crack: float, body: float, bdecay: float,
		thump: float, whoosh: bool) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(crack) + int(body)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		var v := 0.0
		if whoosh:
			# band-swept noise swell
			lp = lp * 0.985 + noise * 0.015
			v = lp * sin(t * PI / dur) * 2.2
		else:
			v = noise * exp(-t * crack) * 0.85                       # crack
			v += sin(t * body * TAU) * exp(-t * bdecay) * 0.55        # body
			if thump > 0.0:
				v += sin(t * thump * TAU) * exp(-t * 18.0) * 0.6     # thump
		_write_s16(data, i, clampf(v, -1.0, 1.0))
	return _make_stream(data)


static func _write_s16(data: PackedByteArray, i: int, v: float) -> void:
	var s := int(clampf(v, -1.0, 1.0) * 32767.0)
	if s < 0:
		s += 65536
	data[i * 2] = s & 0xFF
	data[i * 2 + 1] = (s >> 8) & 0xFF


static func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.stereo = false
	s.data = data
	return s
