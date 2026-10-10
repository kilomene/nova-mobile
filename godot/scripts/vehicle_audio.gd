class_name VehicleAudio
## NOVA Mobile: procedural vehicle audio — engine loops (RPM-pitched),
## horns, skid, collision thud. All synthesized, no audio files.

const RATE := 22050

static var _cache := {}


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := clampf(samples[i], -1.0, 1.0)
		var s := int(v * 32767.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _noise(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(-1.0, 1.0)


## 1.0s seamless engine loop. Pitch via player.pitch_scale = 0.7 + rpm*0.9.
static func engine_loop(kind: String) -> AudioStreamWAV:
	if _cache.has("eng_" + kind):
		return _cache["eng_" + kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) & 0x7fffffff
	var n := RATE  # 1 second
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.0
		match kind:
			"v8":
				var p := fmod(t * 55.0, 1.0)
				v = (2.0 * p - 1.0) * 0.55 + (2.0 * fmod(t * 110.0, 1.0) - 1.0) * 0.28 \
					+ (2.0 * fmod(t * 165.0, 1.0) - 1.0) * 0.14 + _noise(rng) * 0.08
			"diesel":
				var sq := 1.0 if sin(TAU * 45.0 * t) > 0.0 else -1.0
				var clatter := 0.7 + 0.3 * sin(TAU * 23.0 * t)
				v = sq * 0.5 * clatter + (2.0 * fmod(t * 90.0, 1.0) - 1.0) * 0.2 + _noise(rng) * 0.1
			"bike":
				v = (2.0 * fmod(t * 110.0, 1.0) - 1.0) * 0.5 \
					+ (2.0 * fmod(t * 220.0, 1.0) - 1.0) * 0.25 + _noise(rng) * 0.06
			"electric":
				v = sin(TAU * 220.0 * t) * 0.45 + sin(TAU * 440.0 * t) * 0.22 \
					+ sin(TAU * 880.0 * t) * 0.1
			"heli":
				var gate := 0.35 + 0.65 * (0.5 + 0.5 * sin(TAU * 13.0 * t)) ** 2.0
				v = gate * (_noise(rng) * 0.5 + sin(TAU * 50.0 * t) * 0.3)
			"boat":
				lp = lp * 0.92 + _noise(rng) * 0.08
				v = (2.0 * fmod(t * 65.0, 1.0) - 1.0) * 0.45 + lp * 2.2
			"jet":
				var swell := 0.6 + 0.4 * sin(TAU * 2.0 * t)
				lp = lp * 0.96 + _noise(rng) * 0.04
				v = (lp * 3.0 + sin(TAU * 1200.0 * t) * 0.06) * swell
			_:
				v = sin(TAU * 80.0 * t) * 0.3
		s[i] = v * 0.5
	var w := _wav(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_cache["eng_" + kind] = w
	return w


## 0.7s two-tone horn. kind: vehicle class horn style.
static func horn(kind: String) -> AudioStreamWAV:
	if _cache.has("horn_" + kind):
		return _cache["horn_" + kind]
	var f1 := 392.0
	var f2 := 494.0
	match kind:
		"truck":
			f1 = 233.0
			f2 = 311.0
		"bike":
			f1 = 660.0
			f2 = 660.0
		"tank":
			f1 = 147.0
			f2 = 196.0
		"boat":
			f1 = 311.0
			f2 = 415.0
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var env := minf(t / 0.03, 1.0) * minf((0.7 - t) / 0.15, 1.0)
		s[i] = (sin(TAU * f1 * t) * 0.4 + sin(TAU * f2 * t) * 0.4) * env * 0.6
	var w := _wav(s)
	_cache["horn_" + kind] = w
	return w


## 0.8s loopable tire skid.
static func skid_loop() -> AudioStreamWAV:
	if _cache.has("skid"):
		return _cache["skid"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var n := int(RATE * 0.8)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in range(n):
		lp = lp * 0.86 + _noise(rng) * 0.14
		s[i] = lp * 2.4
	var w := _wav(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_cache["skid"] = w
	return w


## 0.3s collision thud.
static func thud() -> AudioStreamWAV:
	if _cache.has("thud"):
		return _cache["thud"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var f := 90.0 - 55.0 * (t / 0.3)
		var env := exp(-t * 14.0)
		s[i] = (sin(TAU * f * t) * 0.7 + _noise(rng) * 0.25) * env * 0.7
	var w := _wav(s)
	_cache["thud"] = w
	return w


## Engine kind per vehicle id.
static func engine_kind(vid: String) -> String:
	match vid:
		"sedan", "suv", "pickup", "sportscar", "jeep":
			return "v8"
		"truck", "armored_suv", "tank":
			return "diesel"
		"bike", "atv":
			return "bike"
		"hoverbike":
			return "electric"
		"heli":
			return "heli"
		"boat":
			return "boat"
		"b2":
			return "jet"
	return ""


## Horn style per vehicle id.
static func horn_kind(vid: String) -> String:
	match vid:
		"truck", "tank", "armored_suv":
			return "truck"
		"bike", "atv", "hoverbike", "skateboard":
			return "bike"
		"boat":
			return "boat"
		"tank":
			return "tank"
	return "car"
