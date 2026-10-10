class_name LootAudio
extends RefCounted
## Procedural loot audio: pickup blips pitched by rarity, container/crate
## opens, ping chirps, death-box thuds. All synthesized, cached.

const MIX_RATE := 22050

static var _cache := {}


static func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.stereo = false
	s.data = data
	return s


static func _write_s16(data: PackedByteArray, i: int, v: float) -> void:
	var s16 := int(clampf(v, -1.0, 1.0) * 32767.0)
	if s16 < 0:
		s16 += 65536
	data[i * 2] = s16 & 0xFF
	data[i * 2 + 1] = (s16 >> 8) & 0xFF


## Pickup blip: two-tone chime, pitch rises with rarity tier.
static func pickup_stream(tier: int) -> AudioStreamWAV:
	var key := "pickup_%d" % clampi(tier, 0, 6)
	if _cache.has(key):
		return _cache[key]
	var base := 520.0 + float(clampi(tier, 0, 6)) * 90.0
	var n := int(MIX_RATE * 0.22)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v := sin(t * base * TAU) * exp(-t * 18.0) * 0.5
		if t > 0.09:
			v += sin((t - 0.09) * base * 1.335 * TAU) * exp(-(t - 0.09) * 16.0) * 0.45
		_write_s16(data, i, v)
	var s := _make_stream(data)
	_cache[key] = s
	return s


## Container open: wooden creak + latch click.
static func open_stream() -> AudioStreamWAV:
	if _cache.has("open"):
		return _cache["open"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := int(MIX_RATE * 0.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		lp = lp * 0.93 + noise * 0.07
		var v := lp * exp(-t * 9.0) * 0.9
		if t > 0.22:
			v += sin((t - 0.22) * 1900.0 * TAU) * exp(-(t - 0.22) * 60.0) * 0.35
		_write_s16(data, i, v)
	var s := _make_stream(data)
	_cache["open"] = s
	return s


## Crate open: heavier thunk + rising shimmer, brighter for higher tiers.
static func crate_stream(tier: int) -> AudioStreamWAV:
	var key := "crate_%d" % clampi(tier, 0, 2)
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + tier
	var n := int(MIX_RATE * 0.6)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var shimmer := 1200.0 + float(tier) * 700.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		lp = lp * 0.90 + noise * 0.10
		var v := lp * exp(-t * 7.0) * 1.0
		v += sin(t * 90.0 * TAU) * exp(-t * 14.0) * 0.5
		v += sin(t * shimmer * TAU) * exp(-t * 5.0) * (0.10 + 0.12 * float(tier))
		_write_s16(data, i, v * 0.8)
	var s := _make_stream(data)
	_cache[key] = s
	return s


## Ping chirp: short double-blip.
static func ping_stream() -> AudioStreamWAV:
	if _cache.has("ping"):
		return _cache["ping"]
	var n := int(MIX_RATE * 0.18)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var f := 980.0 if t < 0.07 else 1320.0
		var v := sin(t * f * TAU) * exp(-t * 22.0) * 0.5
		_write_s16(data, i, v)
	var s := _make_stream(data)
	_cache["ping"] = s
	return s


## Death-box thud: low knock.
static func thud_stream() -> AudioStreamWAV:
	if _cache.has("thud"):
		return _cache["thud"]
	var n := int(MIX_RATE * 0.25)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v := sin(t * 110.0 * TAU) * exp(-t * 20.0) * 0.7
		v += sin(t * 65.0 * TAU) * exp(-t * 16.0) * 0.4
		_write_s16(data, i, v)
	var s := _make_stream(data)
	_cache["thud"] = s
	return s
