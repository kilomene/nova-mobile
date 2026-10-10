extends Node3D
class_name StadiumMap
## Phase 15: Stadium. Oval football stadium: central grass pitch with markings
## and goals, blue running track, 12-segment tiered stands (2 tiers with bench
## seating, walkable ramps), enterable concourse ring underneath (kiosks,
## lamp strips, loot), players' tunnel through the south segment, 4 floodlight
## pylons with emissive heads, parking lot with cars, perimeter fence with
## gates + ticket booths. Flat ground (y=0). Seeded, merge-ready, clean origin.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261023
const SEG := 12
const EA := 40.0  # inner ellipse a (x)
const EB := 30.0  # inner ellipse b (z)
const SW := 18.2  # segment width

var player_spawn := Vector3(0, 0.6, 58)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []
var map_extent := MAP_EXTENT
var draw_calls := 0
var instance_total := 0
var collider_total := 0

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _clouds: Array = []
var _time := 0.0

const TUNNEL_SEG := 3  # south segment carries the players' tunnel
const STAIR_SEGS := [1, 4, 7, 10]  # walkway -> tier 1 stairs
const GATE_SEGS := [0, 3, 6, 9]  # outer-wall gates


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_pitch()
	_build_track()
	for i in range(SEG):
		_build_segment(i)
	_build_floodlights()
	_build_parking()
	_build_fence()
	_build_booths()
	_build_props()
	_build_pois()
	_build_clouds()
	_finalize()


# ---------------- materials ----------------

func _std(c: Color, rough := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	m.vertex_color_use_as_albedo = true
	return m


func _emissive(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := _std(Color(1, 1, 1), 0.5)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _make_mats() -> void:
	_mats["concrete"] = _std(Color(0.62, 0.61, 0.58))
	_mats["concrete_dark"] = _std(Color(0.44, 0.43, 0.41))
	_mats["asphalt"] = _std(Color(0.23, 0.23, 0.25), 0.95)
	_mats["grass"] = _std(Color(0.25, 0.52, 0.24), 0.95)
	_mats["grass_dark"] = _std(Color(0.20, 0.44, 0.20), 0.95)
	_mats["track"] = _std(Color(0.55, 0.22, 0.16), 0.9)
	_mats["paint_white"] = _std(Color(0.90, 0.90, 0.88), 0.9)
	_mats["wall_grey"] = _std(Color(0.58, 0.58, 0.60))
	_mats["trim"] = _std(Color(0.30, 0.28, 0.26))
	_mats["door_wood"] = _std(Color(0.40, 0.28, 0.16))
	_mats["metal"] = _std(Color(0.50, 0.52, 0.55), 0.5, 0.5)
	_mats["pole"] = _std(Color(0.25, 0.26, 0.28), 0.6, 0.3)
	_mats["seat_red"] = _std(Color(0.72, 0.16, 0.14), 0.8)
	_mats["seat_white"] = _std(Color(0.88, 0.87, 0.84), 0.8)
	_mats["seat_blue"] = _std(Color(0.16, 0.32, 0.68), 0.8)
	_mats["glass_dark"] = _std(Color(0.12, 0.16, 0.20), 0.15, 0.6)
	_mats["tire"] = _std(Color(0.08, 0.08, 0.09), 0.95)
	_mats["car_a"] = _std(Color(0.75, 0.75, 0.78), 0.35, 0.4)
	_mats["car_b"] = _std(Color(0.15, 0.15, 0.17), 0.35, 0.4)
	_mats["car_c"] = _std(Color(0.16, 0.32, 0.60), 0.35, 0.4)
	_mats["lamp_head"] = _emissive(Color(1.0, 0.88, 0.60), 2.0)
	_mats["strip_light"] = _emissive(Color(0.85, 0.92, 1.0), 2.4)
	_mats["flood_head"] = _emissive(Color(1.0, 0.97, 0.88), 3.5)


func _varc(c: Color, amt := 0.10) -> Color:
	var f := 1.0 + _rng.randf_range(-amt, amt)
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


func _pick(arr: Array):
	return arr[_rng.randi_range(0, arr.size() - 1)]


func _loot_kind() -> String:
	return _pick(["ammo", "ammo", "health", "armor", "health", "ammo"])


func _add_loot(kind: String, pos: Vector3) -> void:
	var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
	loot_spots.append([kind, amt, pos])


# ---------------- batch helpers ----------------

func _t3(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)


func _box(size: Vector3, xform: Transform3D, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	_batch.add_box(size, xform, mat, col)
	if collide:
		_batch.add_collider(size, xform)


func _label(text: String, pos: Vector3, yaw: float, size_m := 0.55, col := Color.WHITE) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = size_m / 96.0 * 1.6
	l.modulate = col
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.double_sided = true
	l.no_depth_test = false
	l.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(l)


func _wall_open(frame: Transform3D, W: float, H: float, T: float, holes: Array,
		mat: StandardMaterial3D, col: Color, collide := true) -> void:
	var sorted := holes.duplicate()
	sorted.sort_custom(func(a, b): return (a[0] as float) < (b[0] as float))
	var x0 := -W * 0.5
	for h in sorted:
		var hx: float = h[0]
		var hy: float = h[1]
		var hw: float = h[2]
		var hh: float = h[3]
		var seg_w := (hx - hw * 0.5) - x0
		if seg_w > 0.05:
			_box(Vector3(seg_w, H, T), frame * _t3(Vector3(x0 + seg_w * 0.5, H * 0.5, 0)), mat, col, collide)
		if hy > 0.05:
			_box(Vector3(hw, hy, T), frame * _t3(Vector3(hx, hy * 0.5, 0)), mat, col, collide)
		var top := hy + hh
		if H - top > 0.05:
			_box(Vector3(hw, H - top, T), frame * _t3(Vector3(hx, top + (H - top) * 0.5, 0)), mat, col, collide)
		x0 = hx + hw * 0.5
	var last_w := W * 0.5 - x0
	if last_w > 0.05:
		_box(Vector3(last_w, H, T), frame * _t3(Vector3(x0 + last_w * 0.5, H * 0.5, 0)), mat, col, collide)


func _seg_frame(i: int) -> Transform3D:
	var th := TAU * float(i) / float(SEG)
	var px := EA * cos(th)
	var pz := EB * sin(th)
	var yaw := atan2(cos(th), sin(th))  # local +z points outward
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(px, 0, pz))


func _slope_slab(frame: Transform3D, z0: float, y0: float, z1: float, y1: float,
		width: float, xc := 0.0, thick := 0.5) -> void:
	# Sloped slab whose TOP surface runs from (z0, y0) to (z1, y1).
	# Visual + collider: the walking surface of a stand tier.
	var run := z1 - z0
	var rise := y1 - y0
	var length := sqrt(run * run + rise * rise) + 0.4
	var ang := atan2(rise, run)
	var n := Vector3(0, cos(ang), sin(ang))  # surface normal after tilt
	var center := Vector3(xc, (y0 + y1) * 0.5, (z0 + z1) * 0.5) - n * (thick * 0.5)
	var local := Transform3D(Basis(Vector3(1, 0, 0), -ang), center)
	_box(Vector3(width, thick, length), frame * local,
		_mats["concrete"], _varc(Color(1, 1, 1), 0.04), true)


func _bench_row(frame: Transform3D, z0: float, y0: float, z1: float, y1: float,
		rows: int, width: float, xc: float, seat_mat: StandardMaterial3D) -> void:
	var run := z1 - z0
	var rise := y1 - y0
	for j in range(rows):
		var f := (float(j) + 0.5) / float(rows)
		var bz := z0 + run * f
		var by := y0 + rise * f
		_box(Vector3(width, 0.45, 0.55), frame * _t3(Vector3(xc, by + 0.20, bz)),
			seat_mat, _varc(Color(1, 1, 1), 0.08), false)


# ---------------- ground / pitch / track ----------------

func _build_ground() -> void:
	_box(Vector3(140, 0.6, 140), _t3(Vector3(0, -0.32, 0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.05), true)


func _build_pitch() -> void:
	# Grass with mowing stripes.
	_box(Vector3(64, 0.1, 40), _t3(Vector3(0, -0.03, 0)),
		_mats["grass"], Color(1, 1, 1), true)
	for s in range(8):
		if s % 2 == 0:
			continue
		_box(Vector3(8, 0.02, 40), _t3(Vector3(-28 + float(s) * 8.0, 0.03, 0)),
			_mats["grass_dark"], Color(1, 1, 1), false)
	# Markings.
	_box(Vector3(0.15, 0.02, 40), _t3(Vector3(0, 0.035, 0)), _mats["paint_white"], Color(1, 1, 1), false)
	for k in range(16):
		var a := TAU * float(k) / 16.0
		_box(Vector3(1.4, 0.02, 0.15),
			Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 9.0, 0.035, sin(a) * 9.0)),
			_mats["paint_white"], Color(1, 1, 1), false)
	for sx in [-1.0, 1.0]:
		var bx: float = sx * 30.0
		# Penalty box U (opening toward center).
		_box(Vector3(0.15, 0.02, 16), _t3(Vector3(bx - sx * 8.0, 0.035, 0)), _mats["paint_white"], Color(1, 1, 1), false)
		_box(Vector3(8, 0.02, 0.15), _t3(Vector3(bx - sx * 4.0, 0.035, 8)), _mats["paint_white"], Color(1, 1, 1), false)
		_box(Vector3(8, 0.02, 0.15), _t3(Vector3(bx - sx * 4.0, 0.035, -8)), _mats["paint_white"], Color(1, 1, 1), false)
		_box(Vector3(0.3, 0.02, 0.3), _t3(Vector3(bx - sx * 11.0, 0.035, 0)), _mats["paint_white"], Color(1, 1, 1), false)
	# Goals.
	for gx in [-1.0, 1.0]:
		var px: float = gx * 30.0
		for gz in [-3.65, 3.65]:
			_box(Vector3(0.14, 2.44, 0.14), _t3(Vector3(px, 1.22, gz)), _mats["paint_white"], Color(1, 1, 1), true)
		_box(Vector3(0.14, 0.14, 7.44), _t3(Vector3(px, 2.44, 0)), _mats["paint_white"], Color(1, 1, 1), false)
		# Net frame (open, no collide on the net planes).
		_box(Vector3(1.6, 0.1, 0.1), _t3(Vector3(px + gx * 0.8, 2.4, 0)), _mats["metal"], Color(1, 1, 1), false)
		for gz2 in [-3.65, 3.65]:
			_box(Vector3(1.7, 2.4, 0.06), _t3(Vector3(px + gx * 0.8, 1.2, gz2)),
				_mats["glass_dark"], Color(1, 1, 1, 0.5), false)
	# Pitch-side loot.
	for sp in [Vector3(20, 0, 14), Vector3(-20, 0, -14), Vector3(10, 0, -17),
			Vector3(-10, 0, 17), Vector3(28, 0, -8), Vector3(-28, 0, 8)]:
		_add_loot(_loot_kind(), Vector3(sp.x, 0.55, sp.z))


func _build_track() -> void:
	# Blue running track ring between pitch and walkway.
	for i in range(SEG):
		var frame := _seg_frame(i)
		_box(Vector3(SW + 1.0, 0.08, 5.5), frame * _t3(Vector3(0, 0.0, -5.25)),
			_mats["track"], _varc(Color(1, 1, 1), 0.06), true)
		for lx in [-SW * 0.5, SW * 0.5]:
			_box(Vector3(0.14, 0.02, 5.5), frame * _t3(Vector3(lx, 0.05, -5.25)),
				_mats["paint_white"], Color(1, 1, 1), false)


# ---------------- stands segments ----------------

func _build_segment(i: int) -> void:
	var frame := _seg_frame(i)
	var col := _varc(Color(1, 1, 1), 0.05)
	var seat_mat: StandardMaterial3D = [_mats["seat_red"], _mats["seat_white"], _mats["seat_blue"]][i % 3]
	var is_tunnel := i == TUNNEL_SEG
	var is_stair := i in STAIR_SEGS
	var is_gate := i in GATE_SEGS
	# Inner walkway ring quad (top y=0.06).
	_box(Vector3(SW + 1.0, 0.12, 2.5), frame * _t3(Vector3(0, 0.0, -1.25)),
		_mats["concrete"], col, true)
	# Guard wall on the pitch side (gap at tunnel / stair segments).
	if is_tunnel:
		_box(Vector3((SW + 1.0 - 5.5) * 0.5, 1.0, 0.18),
			frame * _t3(Vector3(-(5.5 + (SW + 1.0 - 5.5) * 0.5) * 0.5, 0.56, -2.4)),
			_mats["concrete_dark"], col, true)
		_box(Vector3((SW + 1.0 - 5.5) * 0.5, 1.0, 0.18),
			frame * _t3(Vector3((5.5 + (SW + 1.0 - 5.5) * 0.5) * 0.5, 0.56, -2.4)),
			_mats["concrete_dark"], col, true)
	elif is_stair:
		_box(Vector3((SW + 1.0 - 3.6) * 0.5, 1.0, 0.18),
			frame * _t3(Vector3(-(3.6 + (SW + 1.0 - 3.6) * 0.5) * 0.5, 0.56, -2.4)),
			_mats["concrete_dark"], col, true)
		_box(Vector3((SW + 1.0 - 3.6) * 0.5, 1.0, 0.18),
			frame * _t3(Vector3((3.6 + (SW + 1.0 - 3.6) * 0.5) * 0.5, 0.56, -2.4)),
			_mats["concrete_dark"], col, true)
	else:
		_box(Vector3(SW + 1.0, 1.0, 0.18), frame * _t3(Vector3(0, 0.56, -2.4)),
			_mats["concrete_dark"], col, true)
	# Tier 1: sloped slab (walkable) + bench rows.
	if is_tunnel:
		var hw := (SW - 5.5) * 0.5 - 0.2
		for side in [-1.0, 1.0]:
			var xc: float = side * (2.75 + (SW - 5.5) * 0.25)
			_slope_slab(frame, -0.5, 2.3, 9.2, 7.0, hw, xc)
			_bench_row(frame, -0.5, 2.3, 9.2, 7.0, 5, hw - 0.5, xc, seat_mat)
		# Gap walls above the tunnel.
		for gx in [-2.75, 2.75]:
			_box(Vector3(0.3, 4.5, 9.0), frame * _t3(Vector3(gx, 4.75, 4.5)),
				_mats["wall_grey"], col, true)
	else:
		_slope_slab(frame, -0.5, 2.3, 9.2, 7.0, SW - 0.4)
		_bench_row(frame, -0.5, 2.3, 9.2, 7.0, 5, SW - 1.0, 0.0, seat_mat)
	# Mid walkway (top y=7.0).
	if is_tunnel:
		for hx in [-1.0, 1.0]:
			_box(Vector3((SW - 5.5) * 0.5, 0.25, 2.0),
				frame * _t3(Vector3(hx * (2.75 + (SW - 5.5) * 0.25), 6.875, 10.0)),
				_mats["concrete"], col, true)
	else:
		_box(Vector3(SW + 1.0, 0.25, 2.0), frame * _t3(Vector3(0, 6.875, 10.0)),
			_mats["concrete"], col, true)
	# Tier 2 (continuous, even over the tunnel).
	_slope_slab(frame, 9.0, 6.6, 19.2, 12.0, SW - 0.4)
	_bench_row(frame, 9.0, 6.6, 19.2, 12.0, 5, SW - 1.0, 0.0, seat_mat)
	# Top walkway (top y=12.0) + outer wall.
	_box(Vector3(SW + 1.0, 0.25, 2.0), frame * _t3(Vector3(0, 11.875, 20.0)),
		_mats["concrete"], col, true)
	var wall_w := SW + 6.0
	if is_gate:
		var gw := 5.0 if is_tunnel else 4.0
		_wall_open(frame * _t3(Vector3(0, 0, 21.0)), wall_w, 13.5, 0.4,
			[[0, 0, gw, 3.2]], _mats["wall_grey"], col, true)
	else:
		_box(Vector3(wall_w, 13.5, 0.4), frame * _t3(Vector3(0, 6.75, 21.0)),
			_mats["wall_grey"], col, true)
	# Concourse (under tier 1) — or the players' tunnel.
	if is_tunnel:
		_build_tunnel(frame, col)
	else:
		_build_concourse(frame, col, is_stair)
	# Walkway -> tier 1 stairs.
	if is_stair:
		_stairs2(frame, -2.5, 1.5, 0.15, 3.4, 3.0)
	# Stand loot: a few on the mid/top walkways.
	for lz in [10.0, 20.0]:
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-SW * 0.35, SW * 0.35), 0, lz)
		var ly := 7.55 if lz < 15.0 else 12.55
		_add_loot(_loot_kind(), Vector3(lp.x, ly, lp.z))
	house_positions.append(frame.origin)


func _stairs2(frame: Transform3D, za: float, zb: float, ya: float, yb: float, width: float) -> void:
	# Stair flight along local z (walkway -> tier 1).
	var steps := 10
	var run := zb - za
	var rise := yb - ya
	for i in range(steps):
		var f := (float(i) + 0.5) / float(steps)
		_box(Vector3(width, 0.09, absf(run) / float(steps) + 0.06),
			frame * _t3(Vector3(0, ya + rise * f - 0.045, za + run * f)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var ramp := Transform3D(Basis(Vector3(1, 0, 0), -ang),
		frame * Vector3(0, ya + rise * 0.5 - 0.06, za + run * 0.5))
	_batch.add_collider(Vector3(width, 0.12, length), ramp)


func _build_concourse(frame: Transform3D, col: Color, wide_vomitory: bool) -> void:
	# Enterable concourse room under tier 1 (floor top y=0.15).
	_box(Vector3(SW, 0.15, 9.0), frame * _t3(Vector3(0, 0.075, 4.5)),
		_mats["concrete_dark"], col, true)
	# Front wall with vomitory openings to the walkway.
	if wide_vomitory:
		_wall_open(frame * _t3(Vector3(0, 0, 0.3)), SW, 2.5, 0.25,
			[[0, 0, 3.4, 2.5]], _mats["wall_grey"], col, true)
	else:
		_wall_open(frame * _t3(Vector3(0, 0, 0.3)), SW, 2.5, 0.25,
			[[-SW * 0.25, 0, 1.6, 2.2], [SW * 0.25, 0, 1.6, 2.2]], _mats["wall_grey"], col, true)
	# Side walls.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.25, 2.5, 9.0), frame * _t3(Vector3(sx * SW * 0.5, 1.25, 4.5)),
			_mats["wall_grey"], col, true)
	# Kiosk: counter + back shelf + sign.
	var kf := frame * _t3(Vector3(0, 0.15, 6.5))
	_box(Vector3(3.2, 1.05, 0.8), kf * _t3(Vector3(0, 0.525, 0)), _mats["door_wood"], col, true)
	_box(Vector3(3.2, 0.08, 0.8), kf * _t3(Vector3(0, 1.09, 0)), _mats["door_wood"], col, false)
	_box(Vector3(3.0, 1.8, 0.4), kf * _t3(Vector3(0, 0.9, 1.4)), _mats["door_wood"], col, true)
	for gi in range(4):
		_box(Vector3(0.35, 0.3, 0.3), kf * _t3(Vector3(-1.1 + float(gi) * 0.75, 1.35, 1.4)),
			_mats["seat_red"], _varc(Color(1, 1, 1), 0.15), false)
	_box(Vector3(3.4, 0.9, 0.15), kf * _t3(Vector3(0, 2.5, 0.6)), _mats["trim"], col, false)
	_label("SNACKS", kf * Vector3(0, 2.5, 0.72), atan2(kf.basis.z.x, kf.basis.z.z), 0.42,
		Color(1.0, 0.8, 0.3))
	# Ceiling lamp strips under the tier.
	for lx in [-SW * 0.28, 0.0, SW * 0.28]:
		_box(Vector3(0.5, 0.06, 2.4), frame * _t3(Vector3(lx, 2.32, 4.5)),
			_mats["strip_light"], Color(1, 1, 1), false)
	# Concourse loot (2 per room).
	for i in range(2):
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-SW * 0.35, SW * 0.35), 0.15,
			_rng.randf_range(1.5, 5.5))
		_add_loot(_loot_kind(), Vector3(lp.x, 0.7, lp.z))


func _build_tunnel(frame: Transform3D, col: Color) -> void:
	# Players' tunnel: enterable corridor from the outer gate to the walkway.
	var tw := 5.5
	_box(Vector3(tw, 0.15, 23.5), frame * _t3(Vector3(0, 0.075, 9.25)),
		_mats["concrete_dark"], col, true)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.3, 2.6, 23.5), frame * _t3(Vector3(sx * tw * 0.5, 1.3, 9.25)),
			_mats["wall_grey"], col, true)
	# Ceiling under the tier gap.
	_box(Vector3(tw + 0.6, 0.25, 23.5), frame * _t3(Vector3(0, 2.72, 9.25)),
		_mats["concrete"], col, true)
	# Upper walls enclosing the tunnel void up to tier 2 (back half).
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.3, 4.6, 12.0), frame * _t3(Vector3(sx * tw * 0.5, 5.1, 15.0)),
			_mats["wall_grey"], col, true)
	for lz in [2.0, 9.25, 16.5]:
		_box(Vector3(2.2, 0.06, 0.6), frame * _t3(Vector3(0, 2.55, lz)),
			_mats["strip_light"], Color(1, 1, 1), false)
	# Tunnel mouth frame on the pitch side.
	_box(Vector3(tw + 1.2, 0.5, 0.6), frame * _t3(Vector3(0, 3.1, -2.5)),
		_mats["trim"], col, false)
	_label("TUNNEL", frame * Vector3(0, 3.7, -2.4), atan2(frame.basis.z.x, frame.basis.z.z), 0.5,
		Color(1.0, 0.85, 0.4))
	# Tunnel loot.
	for i in range(4):
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-1.8, 1.8), 0.15,
			_rng.randf_range(0.0, 18.0))
		_add_loot(_loot_kind(), Vector3(lp.x, 0.7, lp.z))


# ---------------- floodlights / parking / fence / booths ----------------

func _floodlight(pos: Vector3) -> void:
	_batch.add_cyl(0.45, 26.0, _t3(pos + Vector3(0, 13.0, 0)), _mats["pole"],
		_varc(Color(1, 1, 1), 0.06))
	_batch.add_collider(Vector3(1.0, 26.0, 1.0), _t3(pos + Vector3(0, 13.0, 0)))
	# Head frame + 8 emissive lamps aimed at the pitch.
	var yaw := atan2(-pos.x, -pos.z)
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 26.0, 0))
	_box(Vector3(6.4, 0.5, 0.5), frame * _t3(Vector3(0, 0, 0)), _mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(6.4, 3.2, 0.25), frame * _t3(Vector3(0, -0.4, -0.35)), _mats["trim"], Color(1, 1, 1), false)
	for r in range(2):
		for c in range(4):
			_box(Vector3(1.2, 1.2, 0.3),
				frame * Transform3D(Basis(Vector3(1, 0, 0), 0.35), Vector3(-2.25 + float(c) * 1.5, 0.4 - float(r) * 1.5, 0.25)),
				_mats["flood_head"], Color(1, 1, 1), false)


func _build_floodlights() -> void:
	for fp in [Vector3(50, 0, 50), Vector3(-50, 0, 50), Vector3(50, 0, -50), Vector3(-50, 0, -50)]:
		_floodlight(fp)


func _car(pos: Vector3, yaw: float, mat: StandardMaterial3D) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_box(Vector3(4.4, 0.72, 1.9), frame * _t3(Vector3(0, 0.62, 0)), mat, Color(1, 1, 1), true)
	_box(Vector3(1.1, 0.5, 1.85), frame * _t3(Vector3(1.65, 0.55, 0)), mat, Color(1, 1, 1), false)
	_box(Vector3(2.3, 0.62, 1.72), frame * _t3(Vector3(-0.25, 1.18, 0)), _mats["glass_dark"], Color(1, 1, 1), true)
	_box(Vector3(2.34, 0.18, 1.76), frame * _t3(Vector3(-0.25, 1.55, 0)), mat, Color(1, 1, 1), false)
	for sx in [-1.45, 1.45]:
		for sz in [-0.95, 0.95]:
			var wg := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), frame * Vector3(sx, 0.36, sz))
			_batch.add_cyl(0.36, 0.28, wg, _mats["tire"], Color(1, 1, 1))


func _build_parking() -> void:
	# North parking lot.
	_box(Vector3(76, 0.1, 18), _t3(Vector3(0, 0.0, -57)),
		_mats["asphalt"], _varc(Color(1, 1, 1), 0.05), true)
	for i in range(10):
		var bx := -34.0 + float(i) * 7.5
		_box(Vector3(0.14, 0.02, 16), _t3(Vector3(bx, 0.06, -57)), _mats["paint_white"], Color(1, 1, 1), false)
	var car_mats := [_mats["car_a"], _mats["car_b"], _mats["car_c"]]
	for i in range(10):
		var cx := -30.0 + float(i) * 6.8
		var cz := -52.5 if i % 2 == 0 else -61.5
		_car(Vector3(cx, 0.05, cz), PI * 0.5 if i % 2 == 0 else -PI * 0.5, car_mats[i % 3])
	# Lamp posts.
	for lx in [-30.0, -10.0, 10.0, 30.0]:
		var frame := Transform3D(Basis(), Vector3(lx, 0, -48.5))
		_batch.add_cyl(0.12, 7.0, frame * _t3(Vector3(0, 3.5, 0)), _mats["pole"], Color(1, 1, 1))
		_batch.add_collider(Vector3(0.28, 7.0, 0.28), frame * _t3(Vector3(0, 3.5, 0)))
		_box(Vector3(0.5, 0.2, 0.8), frame * _t3(Vector3(0, 6.9, 0)), _mats["lamp_head"], Color(1, 1, 1), false)
	# Parking loot.
	for i in range(8):
		_add_loot(_loot_kind(), Vector3(_rng.randf_range(-34, 34), 0.6, _rng.randf_range(-63, -51)))


func _build_fence() -> void:
	# Perimeter fence rectangle at +-63 with 4 gate gaps.
	var e := 63.0
	var sides := [
		{"from": Vector3(-e, 0, e), "to": Vector3(e, 0, e), "gate": Vector3(0, 0, e)},
		{"from": Vector3(-e, 0, -e), "to": Vector3(e, 0, -e), "gate": Vector3(0, 0, -e)},
		{"from": Vector3(e, 0, -e), "to": Vector3(e, 0, e), "gate": Vector3(e, 0, 0)},
		{"from": Vector3(-e, 0, -e), "to": Vector3(-e, 0, e), "gate": Vector3(-e, 0, 0)},
	]
	for sd in sides:
		var a: Vector3 = sd["from"]
		var b: Vector3 = sd["to"]
		var g: Vector3 = sd["gate"]
		var n := 16
		for k in range(n + 1):
			var p: Vector3 = a.lerp(b, float(k) / float(n))
			if p.distance_to(g) < 3.5:
				continue  # gate gap
			_box(Vector3(0.14, 2.4, 0.14), _t3(p + Vector3(0, 1.2, 0)),
				_mats["pole"], Color(1, 1, 1), false)
		for k in range(n):
			var p0: Vector3 = a.lerp(b, float(k) / float(n))
			var p1: Vector3 = a.lerp(b, float(k + 1) / float(n))
			var mid := (p0 + p1) * 0.5
			if mid.distance_to(g) < 4.5:
				continue
			var seg := p1 - p0
			var yaw := atan2(seg.x, seg.z)
			var frame := Transform3D(Basis(Vector3.UP, yaw), mid)
			_box(Vector3(seg.length(), 1.9, 0.06), frame * _t3(Vector3(0, 1.25, 0)),
				_mats["glass_dark"], Color(0.6, 0.62, 0.65, 0.85), true)
			_box(Vector3(seg.length(), 0.08, 0.08), frame * _t3(Vector3(0, 2.25, 0)),
				_mats["metal"], Color(1, 1, 1), false)


func _build_booths() -> void:
	# Ticket booths beside each gate.
	var booths := [
		{"p": Vector3(8, 0, 63), "yaw": 0.0},
		{"p": Vector3(8, 0, -63), "yaw": PI},
		{"p": Vector3(63, 0, 8), "yaw": -PI * 0.5},
		{"p": Vector3(-63, 0, 8), "yaw": PI * 0.5},
	]
	for bd in booths:
		var bp: Vector3 = bd["p"]
		var frame := Transform3D(Basis(Vector3.UP, float(bd["yaw"])), bp)
		var w := 2.6
		var d := 2.6
		var h := 2.7
		var col := _varc(Color(1, 1, 1), 0.06)
		_box(Vector3(w + 0.4, 0.15, d + 0.4), frame * _t3(Vector3(0, 0.075, 0)),
			_mats["concrete"], col, true)
		_wall_open(frame * _t3(Vector3(0, 0.15, d * 0.5)), w, h, 0.15,
			[[0, 0.9, 1.8, 1.0]], _mats["wall_grey"], col, true)
		_wall_open(frame * _t3(Vector3(0, 0.15, -d * 0.5)), w, h, 0.15,
			[[0, 0, 1.0, 2.2]], _mats["wall_grey"], col, true)
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.15, h, d), frame * _t3(Vector3(sx * w * 0.5, 0.15 + h * 0.5, 0)),
				_mats["wall_grey"], col, true)
		_box(Vector3(w + 0.5, 0.18, d + 0.5), frame * _t3(Vector3(0, 0.15 + h + 0.09, 0)),
			_mats["trim"], col, false)
		_box(Vector3(2.2, 0.7, 0.12), frame * _t3(Vector3(0, 0.15 + h + 0.55, d * 0.5 + 0.1)),
			_mats["seat_red"], Color(1, 1, 1), false)
		_label("TICKETS", frame * Vector3(0, 0.15 + h + 0.55, d * 0.5 + 0.18),
			float(bd["yaw"]), 0.35, Color(1, 1, 1))
		var lp: Vector3 = frame * Vector3(0, 0, 2.2)
		_add_loot(_loot_kind(), Vector3(lp.x, 0.7, lp.z))
		house_positions.append(bp)


# ---------------- props / pois ----------------

func _streetlight(pos: Vector3, yaw: float, h := 7.5) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_batch.add_cyl(0.13, h, frame * _t3(Vector3(0, h * 0.5, 0)), _mats["pole"], _varc(Color(1, 1, 1), 0.08))
	_batch.add_collider(Vector3(0.3, h, 0.3), frame * _t3(Vector3(0, h * 0.5, 0)))
	_box(Vector3(0.12, 0.12, 2.2), frame * _t3(Vector3(0, h - 0.1, 1.0)), _mats["pole"], Color(1, 1, 1), false)
	_box(Vector3(0.5, 0.22, 0.9), frame * _t3(Vector3(0, h - 0.2, 2.0)), _mats["lamp_head"], Color(1, 1, 1), false)


func _build_props() -> void:
	# Streetlights around the stadium apron.
	for i in range(8):
		var a := TAU * float(i) / 8.0 + PI / 8.0
		_streetlight(Vector3(cos(a) * 58.0, 0, sin(a) * 58.0), -a + PI * 0.5)
	# Cones and barriers near gates (cover).
	for gp in [Vector3(0, 0, 63), Vector3(0, 0, -63), Vector3(63, 0, 0), Vector3(-63, 0, 0)]:
		for k in range(3):
			var off := Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
			_box(Vector3(1.8, 0.7, 0.45), _t3(gp + off + Vector3(0, 0.35, 0)),
				_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
	# Gate loot.
	for gp2 in [Vector3(0, 0, 60), Vector3(0, 0, -60), Vector3(60, 0, 0), Vector3(-60, 0, 0)]:
		_add_loot(_loot_kind(), Vector3(gp2.x + _rng.randf_range(-2, 2), 0.55, gp2.z + _rng.randf_range(-2, 2)))


func _build_pois() -> void:
	var defs := [
		{"name": "The Pitch", "pos": Vector3(0, 0, 0)},
		{"name": "North Stand", "pos": Vector3(0, 12.0, -50)},
		{"name": "Concourse", "pos": Vector3(44.5, 0.15, 0)},
	]
	for dd in defs:
		poi_list.append({"name": String(dd["name"]), "pos": dd["pos"]})
		var pp: Vector3 = dd["pos"]
		for i in range(3):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(2.5, 5.5)
			_add_loot(_loot_kind(), pp + Vector3(cos(a) * r, 0.55, sin(a) * r))


func _build_clouds() -> void:
	var cm := SphereMesh.new()
	cm.radius = 1.0
	cm.height = 2.0
	cm.radial_segments = 12
	cm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.98, 0.97, 0.95, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(7):
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		var s := _rng.randf_range(16.0, 30.0)
		mi.scale = Vector3(s, s * 0.20, s * 0.55)
		mi.position = Vector3(_rng.randf_range(-140, 140), _rng.randf_range(42, 60), _rng.randf_range(-140, 140))
		add_child(mi)
		_clouds.append({"node": mi, "speed": _rng.randf_range(0.4, 1.0)})


# ---------------- finalize ----------------

func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -6, -85), Vector3(170, 60, 170))
	draw_calls = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	instance_total = _batch.box_count()
	collider_total = _batch.collider_count()
	enemy_spawns = [
		Vector3(28, 0.6, 16), Vector3(-28, 0.6, -16), Vector3(44.5, 0.6, 8),
		Vector3(0, 0.6, -57), Vector3(0, 0.6, 34), Vector3(8, 0.6, -58),
	]
	print("Stadium built: instances=", instance_total,
		" draws=", draw_calls, " colliders=", collider_total,
		" loot=", loot_spots.size(), " pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 160.0:
			cn.position.x = -160.0
