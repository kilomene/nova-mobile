extends Node3D
class_name TrainStationMap
## Phase 8: TRAIN STATION — Ebute Metta (Mobolaji Johnson style) (map #7, selector idx 6).
## Flat 140x140m: grand enterable station hall (ticket counters, queue
## barriers, kiosks, benches, departure board), 2 canopied platforms, 2
## full-length rail lines (visual only — no train collision, walkable across),
## a parked passenger train (locomotive + 4 ENTERABLE cars with seats, racks,
## loot), a walkable footbridge (stairs both ends + railings), parking lot
## with 8 cars, perimeter fence, and a front plaza. Seeded (SEED),
## merge-ready, clean origin. Ground is FLAT (y=0) — no ground_height().

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const SEED := 20261015

const POI_DEFS := [
	{"name": "Main Hall", "pos": Vector3(0, 0, -10)},
	{"name": "Platform 1", "pos": Vector3(-20, 1.0, 8)},
	{"name": "The Train", "pos": Vector3(-15.5, 1.0, 13)},
	{"name": "Footbridge", "pos": Vector3(40, 5.2, 17)},
]

const TRACK1_Z := 13.0
const TRACK2_Z := 20.0
const TRACK_LEN := 136.0

var map_extent := 70.0
var player_spawn := Vector3(0, 0.6, -40)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _clouds: Array = []
var _time := 0.0
var _placed: Array = []  # Vector2 points claimed by loot scatter


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_tracks()
	_build_station_hall()
	_build_platforms()
	_build_train()
	_build_footbridge()
	_build_parking()
	_build_fence()
	_build_plaza()
	_build_props()
	_build_clouds()
	_build_pois()
	_scatter_loot()
	_finalize()


# ---------------- materials ----------------

func _std(c: Color, rough := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	m.vertex_color_use_as_albedo = true
	return m


func _make_mats() -> void:
	_mats["terrain"] = _std(Color(1, 1, 1), 0.95)
	_mats["terrain"].vertex_color_use_as_albedo = true
	_mats["asphalt"] = _std(Color(0.30, 0.30, 0.32), 0.95)
	_mats["concrete"] = _std(Color(0.60, 0.59, 0.56))
	_mats["concrete_dark"] = _std(Color(0.42, 0.41, 0.39))
	_mats["wall_cream"] = _std(Color(1, 1, 1), 0.9)   # per-instance weathered cream
	_mats["trim"] = _std(Color(0.92, 0.90, 0.86), 0.85)
	_mats["roof_red"] = _std(Color(0.55, 0.22, 0.16), 0.9)
	_mats["metal"] = _std(Color(0.45, 0.47, 0.50), 0.5, 0.5)
	_mats["wood"] = _std(Color(0.45, 0.33, 0.20), 0.9)
	_mats["wood_dark"] = _std(Color(0.30, 0.22, 0.13), 0.9)
	_mats["crate"] = _std(Color(0.52, 0.40, 0.24), 0.9)
	_mats["ballast"] = _std(Color(1, 1, 1), 0.95)     # per-instance grey gravel
	_mats["rail"] = _std(Color(0.62, 0.63, 0.65), 0.35, 0.9)
	_mats["sleeper"] = _std(Color(1, 1, 1), 0.95)     # per-instance timber tone
	_mats["train_blue"] = _std(Color(1, 1, 1), 0.55, 0.25)  # per-instance livery blue
	_mats["train_white"] = _std(Color(0.92, 0.92, 0.90), 0.6, 0.1)
	_mats["train_dark"] = _std(Color(0.16, 0.17, 0.19), 0.6, 0.3)
	_mats["seat_blue"] = _std(Color(0.16, 0.28, 0.52), 0.9)
	_mats["glass_dark"] = _std(Color(0.10, 0.14, 0.18), 0.25, 0.6)
	_mats["car_paint"] = _std(Color(1, 1, 1), 0.5, 0.3)  # per-instance car colors
	_mats["tire"] = _std(Color(0.12, 0.12, 0.13), 0.95)
	_mats["fence_green"] = _std(Color(0.20, 0.38, 0.24), 0.8)
	_mats["sign_green"] = _std(Color(0.05, 0.35, 0.18), 0.7)
	_mats["rope"] = _std(Color(0.55, 0.48, 0.34), 0.95)
	_mats["counter"] = _std(Color(0.48, 0.36, 0.22), 0.7)
	_mats["sandbag"] = _std(Color(1, 1, 1), 0.95)   # per-instance tan variation
	var lamp := _std(Color(1.0, 0.9, 0.65), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.55)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp_head"] = lamp
	var board := _std(Color(1.0, 0.72, 0.25), 0.5)
	board.emission_enabled = true
	board.emission = Color(1.0, 0.65, 0.20)
	board.emission_energy_multiplier = 1.6
	_mats["board"] = board
	var head := _std(Color(1.0, 0.95, 0.80), 0.4)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.92, 0.70)
	head.emission_energy_multiplier = 2.5
	_mats["headlight"] = head


func _varc(c: Color, amt := 0.10) -> Color:
	var f := 1.0 + _rng.randf_range(-amt, amt)
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


# ---------------- batch helpers ----------------

func _t3(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)


func _box(size: Vector3, xform: Transform3D, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	_batch.add_box(size, xform, mat, col)
	if collide:
		_batch.add_collider(size, xform)


func _cyl(radius: float, height: float, xform: Transform3D, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	_batch.add_cyl(radius, height, xform, mat, col)
	if collide:
		_batch.add_collider(Vector3(radius * 2.0, height, radius * 2.0), xform)


# ---------------- walls with real openings ----------------

func _wall_open(frame: Transform3D, W: float, H: float, T: float, holes: Array,
		mat: StandardMaterial3D, col: Color, collide := true) -> void:
	# holes: Array of [x_center, y_bottom, w, h] in wall-local coords.
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


func _trim_opening(frame: Transform3D, xc: float, y0: float, w: float, h: float, T: float) -> void:
	var tm: StandardMaterial3D = _mats["trim"]
	var c := Color(1, 1, 1)
	_box(Vector3(w + 0.24, 0.12, T + 0.08), frame * _t3(Vector3(xc, y0 - 0.02, 0)), tm, c, false)
	_box(Vector3(w + 0.24, 0.12, T + 0.08), frame * _t3(Vector3(xc, y0 + h + 0.02, 0)), tm, c, false)
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc - w * 0.5 - 0.02, y0 + h * 0.5, 0)), tm, c, false)
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc + w * 0.5 + 0.02, y0 + h * 0.5, 0)), tm, c, false)


func _window_wall(frame: Transform3D, W: float, H: float, T: float, mat: StandardMaterial3D, col: Color, trim := true) -> void:
	# Evenly spaced window band — REAL see/shoot-through openings, no glass.
	var n := maxi(2, int(W / 3.0))
	var holes := []
	for i in range(n):
		var xc := -W * 0.5 + W * (float(i) + 0.5) / float(n)
		holes.append([xc, 1.1, 1.4, 1.3])
	_wall_open(frame, W, H, T, holes, mat, col, true)
	if trim:
		for h in holes:
			_trim_opening(frame, float(h[0]), float(h[1]), float(h[2]), float(h[3]), T)


func _stairs(frame: Transform3D, x0: float, run: float, width: float, zc: float, rise: float, y_base := 0.0) -> void:
	# Visual steps + one ramp collider (player walks up/down smoothly).
	var steps := 12
	for i in range(steps):
		var sx := x0 + run * (float(i) + 0.5) / float(steps)
		var sy := y_base + rise * (float(i) + 0.5) / float(steps)
		_box(Vector3(run / float(steps) + 0.05, 0.09, width),
			frame * _t3(Vector3(sx, sy - 0.045, zc)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var ramp := Transform3D(Basis(Vector3(0, 0, 1), ang),
		frame * Vector3(x0 + run * 0.5, y_base + rise * 0.5 - 0.06, zc))
	_batch.add_collider(Vector3(length, 0.12, width), ramp)


func _hash2(x: float, z: float) -> float:
	var s := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return s - floor(s)


func _claim(x: float, z: float, radius: float) -> bool:
	for q in _placed:
		var pq: Vector2 = q
		if pq.distance_to(Vector2(x, z)) < radius:
			return false
	_placed.append(Vector2(x, z))
	return true


# ---------------- furniture ----------------

func _bench(frame: Transform3D, lx: float, lz: float, yaw := 0.0) -> void:
	var bf := frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, 0, lz))
	_box(Vector3(2.2, 0.10, 0.55), bf * _t3(Vector3(0, 0.48, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	_box(Vector3(2.2, 0.55, 0.10), bf * _t3(Vector3(0, 0.85, -0.26)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), false)
	for sx in [-0.95, 0.95]:
		_box(Vector3(0.10, 0.48, 0.50), bf * _t3(Vector3(float(sx), 0.24, 0)),
			_mats["wood_dark"], Color(1, 1, 1), false)


func _lamp(x: float, z: float, y_base := 0.0) -> void:
	_cyl(0.09, 5.0, _t3(Vector3(x, y_base + 2.5, z)), _mats["metal"], Color(1, 1, 1), true)
	_box(Vector3(0.5, 0.25, 0.5), _t3(Vector3(x, y_base + 5.1, z)),
		_mats["lamp_head"], Color(1, 1, 1), false)


func _crate_at(frame: Transform3D, lx: float, lz: float, s := 0.9, y_base := 0.0) -> void:
	_box(Vector3(s, s, s), frame * _t3(Vector3(lx, y_base + s * 0.5, lz)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.12), true)


func _light_panel(frame: Transform3D, lx: float, lz: float, fy: float) -> void:
	# Emissive ceiling light: housing + glowing diffuser (batched, no real light).
	_box(Vector3(2.0, 0.08, 1.1), frame * _t3(Vector3(lx, fy, lz)),
		_mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(1.8, 0.05, 0.9), frame * _t3(Vector3(lx, fy - 0.055, lz)),
		_mats["lamp_head"], Color(1, 1, 1), false)


func _slab_hole(frame: Transform3D, w: float, d: float, y: float, hx0: float, hx1: float, hz: float, hzw: float) -> void:
	# Floor slab with a rectangular stairwell hole (x from hx0..hx1, z centered hz width hzw).
	var t := 0.25
	var y0 := y - t * 0.5
	if hx0 > -w * 0.5 + 0.05:
		var sw := hx0 + w * 0.5
		_box(Vector3(sw, t, d), frame * _t3(Vector3(-w * 0.5 + sw * 0.5, y0, 0)),
			_mats["concrete"], Color(1, 1, 1), true)
	if w * 0.5 - hx1 > 0.05:
		var sw2 := w * 0.5 - hx1
		_box(Vector3(sw2, t, d), frame * _t3(Vector3(hx1 + sw2 * 0.5, y0, 0)),
			_mats["concrete"], Color(1, 1, 1), true)
	var hw := hx1 - hx0
	var fz0 := -d * 0.5
	var fz1 := hz - hzw * 0.5
	var bz0 := hz + hzw * 0.5
	var bz1 := d * 0.5
	if fz1 - fz0 > 0.05:
		_box(Vector3(hw, t, fz1 - fz0), frame * _t3(Vector3((hx0 + hx1) * 0.5, y0, (fz0 + fz1) * 0.5)),
			_mats["concrete"], Color(1, 1, 1), true)
	if bz1 - bz0 > 0.05:
		_box(Vector3(hw, t, bz1 - bz0), frame * _t3(Vector3((hx0 + hx1) * 0.5, y0, (bz0 + bz1) * 0.5)),
			_mats["concrete"], Color(1, 1, 1), true)


func _luggage_stack(frame: Transform3D, lx: float, lz: float) -> void:
	# Pile of suitcases: colorful small boxes.
	var cols := [Color(0.65, 0.15, 0.12), Color(0.12, 0.25, 0.60),
		Color(0.15, 0.45, 0.20), Color(0.55, 0.40, 0.15)]
	for i in range(4):
		var ox := _rng.randf_range(-0.5, 0.5)
		var oz := _rng.randf_range(-0.4, 0.4)
		var sy := 0.22 + float(i / 2) * 0.42
		_box(Vector3(0.75, 0.4, 0.55), frame * _t3(Vector3(lx + ox, sy, lz + oz)),
			_mats["wood"], cols[i % 4], true)

# ---------------- ground / tracks ----------------

func _ground_color(x: float, z: float) -> Color:
	var dirt := Color(0.48, 0.42, 0.31)
	var grass := Color(0.32, 0.47, 0.25)
	var h1 := _hash2(x * 0.08, z * 0.08)
	var h2 := _hash2(x * 0.9 + 37.0, z * 0.9 - 11.0)
	var c := dirt.lerp(grass, smoothstep(0.45, 0.75, h1))
	var v := 0.92 + 0.16 * h2
	return Color(c.r * v, c.g * v, c.b * v)


func _build_ground() -> void:
	var n := 20
	var step := 140.0 / float(n)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for j in range(n + 1):
		for i in range(n + 1):
			var x := -70.0 + float(i) * step
			var z := -70.0 + float(j) * step
			verts.append(Vector3(x, 0.0, z))
			normals.append(Vector3.UP)
			colors.append(_ground_color(x, z))
	for j in range(n):
		for i in range(n):
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = _mats["terrain"]
	add_child(mi)
	# One big walk collider for the flat ground.
	_batch.add_collider(Vector3(140.0, 0.4, 140.0), _t3(Vector3(0, -0.21, 0)))


func _build_track(tz: float) -> void:
	# Ballast: slightly raised gravel strip (visual only).
	_box(Vector3(TRACK_LEN, 0.10, 3.6), _t3(Vector3(0, 0.05, tz)),
		_mats["ballast"], _varc(Color(0.34, 0.33, 0.31), 0.12), false)
	# Sleepers: batched small timber boxes (visual only).
	var n := int(TRACK_LEN / 0.8)
	for i in range(n):
		var x := -TRACK_LEN * 0.5 + 0.8 * (float(i) + 0.5)
		_box(Vector3(0.26, 0.08, 2.3), _t3(Vector3(x, 0.14, tz)),
			_mats["sleeper"], _varc(Color(0.36, 0.28, 0.18), 0.14), false)
	# Rails: long thin metallic boxes — visual only, NO collision, walkable.
	for rv in [-0.75, 0.75]:
		var rx: float = rv
		_box(Vector3(TRACK_LEN, 0.14, 0.08), _t3(Vector3(0, 0.25, tz + rx)),
			_mats["rail"], Color(1, 1, 1), false)


func _build_tracks() -> void:
	_build_track(TRACK1_Z)
	_build_track(TRACK2_Z)


# ---------------- station hall ----------------

func _build_station_hall() -> void:
	var x := 0.0
	var z := -14.0
	var w := 24.0
	var d := 16.0
	var h := 5.0
	var t := 0.35
	var frame := Transform3D(Basis(), Vector3(x, 0, z))
	var wall: StandardMaterial3D = _mats["wall_cream"]
	var col := _varc(Color(0.88, 0.82, 0.66), 0.08)
	# Front (north, plaza side): 2 big doors + window band, all real openings.
	var front_holes := []
	for dx in [-6.0, 6.0]:
		front_holes.append([dx, 0.0, 2.4, 3.4])
	for wx in [-10.9, -8.7, -2.5, 2.5, 8.7, 10.9]:
		front_holes.append([wx, 1.2, 1.6, 1.4])
	_wall_open(frame * _t3(Vector3(0, 0, -d * 0.5)), w, h, t, front_holes, wall, col)
	_trim_opening(frame * _t3(Vector3(0, 0, -d * 0.5)), -6.0, 0.0, 2.4, 3.4, t)
	_trim_opening(frame * _t3(Vector3(0, 0, -d * 0.5)), 6.0, 0.0, 2.4, 3.4, t)
	# Back (south, platform side): 2 doors + window band.
	var back_holes := []
	for dx2 in [-6.0, 6.0]:
		back_holes.append([dx2, 0.0, 2.4, 3.4])
	for wx2 in [-10.9, -8.7, -2.5, 2.5, 8.7, 10.9]:
		back_holes.append([wx2, 1.2, 1.6, 1.4])
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, h, t, back_holes, wall, col)
	_trim_opening(frame * _t3(Vector3(0, 0, d * 0.5)), -6.0, 0.0, 2.4, 3.4, t)
	_trim_opening(frame * _t3(Vector3(0, 0, d * 0.5)), 6.0, 0.0, 2.4, 3.4, t)
	# Side walls: window bands (real openings).
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, h, t, wall, col, false)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, h, t, wall, col, false)
	# Gabled roof: ridge along x at y=9, eaves at y=5 (z=±8.5).
	var slope := sqrt(8.5 * 8.5 + 4.0 * 4.0) + 0.3
	var ang := atan2(4.0, 8.5)
	var roof: StandardMaterial3D = _mats["roof_red"]
	var rcol := _varc(Color(1, 1, 1), 0.08)
	for sgn in [-1.0, 1.0]:
		var s: float = sgn
		var panel := frame * Transform3D(Basis(Vector3(1, 0, 0), s * ang),
			Vector3(0, 7.0, s * 4.25))
		_box(Vector3(w + 1.2, 0.18, slope), panel, roof, rcol, false)
	_box(Vector3(w + 1.2, 0.14, 0.7), frame * _t3(Vector3(0, 9.02, 0)),
		roof, rcol, false)
	# Gable ends: stepped infill triangles.
	for ex in [-1.0, 1.0]:
		var ef: float = ex
		_box(Vector3(0.3, 1.35, 14.3), frame * _t3(Vector3(ef * w * 0.5, 5.65, 0)),
			wall, col, true)
		_box(Vector3(0.3, 1.35, 8.7), frame * _t3(Vector3(ef * w * 0.5, 6.95, 0)),
			wall, col, true)
		_box(Vector3(0.3, 1.4, 3.0), frame * _t3(Vector3(ef * w * 0.5, 8.3, 0)),
			wall, col, true)
	# Interior floor slab (visual).
	_box(Vector3(w - 0.6, 0.08, d - 0.6), frame * _t3(Vector3(0, 0.04, 0)),
		_mats["concrete"], Color(1, 1, 1), false)
	# Ticket counters: long counter along the back interior.
	var ctr: StandardMaterial3D = _mats["counter"]
	_box(Vector3(8.0, 1.05, 0.7), frame * _t3(Vector3(0, 0.525, 5.2)),
		ctr, _varc(Color(1, 1, 1), 0.08), true)
	_box(Vector3(8.4, 0.08, 1.0), frame * _t3(Vector3(0, 1.09, 5.2)),
		_mats["wood_dark"], Color(1, 1, 1), false)
	for wx3 in [-3.0, -1.0, 1.0, 3.0]:
		_box(Vector3(0.5, 0.5, 0.08), frame * _t3(Vector3(wx3, 1.35, 5.2)),
			_mats["glass_dark"], Color(1, 1, 1), false)
	# Queue barriers: 3 lanes of posts + rope in front of the counters.
	for lane in [-2.4, 0.0, 2.4]:
		var lz: float = lane
		for px in [-1.1, 1.1]:
			_cyl(0.05, 1.0, frame * _t3(Vector3(lz + float(px), 0.5, 3.6)),
				_mats["metal"], Color(1, 1, 1), false)
		var rope := frame * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5),
			Vector3(lz, 0.88, 3.6))
		_cyl(0.03, 2.2, rope, _mats["rope"], Color(1, 1, 1), false)
	# Benches inside the hall.
	_bench(frame, -8.5, -2.0, 0.0)
	_bench(frame, 8.5, -2.0, 0.0)
	_bench(frame, -8.5, 1.5, PI)
	_bench(frame, 8.5, 1.5, PI)
	# Kiosks: 2 small booths with counters + sign boards.
	for kx in [-8.0, 8.0]:
		var kf := frame * _t3(Vector3(float(kx), 0, -4.5))
		_box(Vector3(2.6, 1.0, 1.8), kf * _t3(Vector3(0, 0.5, 0)),
			ctr, _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(2.8, 0.08, 2.0), kf * _t3(Vector3(0, 1.04, 0)),
			_mats["wood_dark"], Color(1, 1, 1), false)
		for px2 in [-1.2, 1.2]:
			for pz2 in [-0.8, 0.8]:
				_box(Vector3(0.10, 1.6, 0.10),
					kf * _t3(Vector3(float(px2), 1.8, float(pz2))),
					_mats["wood_dark"], Color(1, 1, 1), false)
		_box(Vector3(3.0, 0.12, 2.2), kf * _t3(Vector3(0, 2.65, 0)),
			_mats["roof_red"], _varc(Color(1, 1, 1), 0.08), false)
		_box(Vector3(2.4, 0.6, 0.08), kf * _t3(Vector3(0, 2.2, 1.05)),
			_mats["sign_green"], Color(1, 1, 1), false)
	# Departure board: hanging dark panel + emissive amber rows.
	_box(Vector3(20.0, 0.25, 0.3), frame * _t3(Vector3(0, 4.5, 0)),
		_mats["wood_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.08, 0.8, 0.08), frame * _t3(Vector3(-2.4, 4.0, 0)),
		_mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(0.08, 0.8, 0.08), frame * _t3(Vector3(2.4, 4.0, 0)),
		_mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(6.0, 2.2, 0.15), frame * _t3(Vector3(0, 2.6, 0)),
		_mats["concrete_dark"], Color(1, 1, 1), false)
	for r in range(8):
		_box(Vector3(5.4, 0.12, 0.03),
			frame * _t3(Vector3(0, 3.45 - float(r) * 0.24, 0.09)),
			_mats["board"], Color(1, 1, 1), false)
	# Mezzanine: partial upper floor along the back wall (stairs, railing,
	# seating, loot). Slab x -4.5..5.5, z 2..8, top y=3.0.
	_box(Vector3(10.0, 0.25, 6.0), frame * _t3(Vector3(0.5, 2.875, 5.0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
	for cx2 in [-4.5, 5.5]:
		for cz2 in [2.4, 7.4]:
			_box(Vector3(0.3, 2.9, 0.3),
				frame * _t3(Vector3(float(cx2), 1.45, float(cz2))),
				_mats["concrete_dark"], Color(1, 1, 1), true)
	# Stairs up: ground (world x=-9) to the mezz west edge.
	_stairs(Transform3D.IDENTITY, -9.0, 4.5, 2.0, -9.0, 3.0, 0.0)
	# Railing: west edge (gap at the stairs landing), north + east edges.
	for rz in [2.75, 6.75]:
		var px := -4.5
		_box(Vector3(0.08, 1.0, 1.5), frame * _t3(Vector3(px, 3.5, float(rz))),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
	_box(Vector3(0.08, 0.08, 1.5), frame * _t3(Vector3(-4.5, 4.0, 2.75)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	_box(Vector3(0.08, 0.08, 1.5), frame * _t3(Vector3(-4.5, 4.0, 6.75)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	_box(Vector3(10.0, 0.08, 0.08), frame * _t3(Vector3(0.5, 4.0, 2.0)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	_box(Vector3(0.08, 0.08, 6.0), frame * _t3(Vector3(5.5, 4.0, 5.0)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	for i in range(7):
		_box(Vector3(0.07, 1.0, 0.07),
			frame * _t3(Vector3(-4.5 + float(i) * 1.65, 3.5, 2.0)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	# Seating + loot on the mezzanine.
	var mf := frame * _t3(Vector3(0.5, 3.0, 5.0))
	_bench(mf, -2.5, -1.0, 0.0)
	_bench(mf, 2.5, 1.0, PI)
	_add_loot_y("ammo", 60, frame * Vector3(-2.5, 3.55, -9.0))
	_add_loot_y("health", 40, frame * Vector3(3.5, 3.55, -9.0))
	# Ceiling light panels (emissive): hall ceiling + under the mezzanine.
	for lxp in [-6.0, 6.0]:
		for lzp in [-3.0, 3.0]:
			_light_panel(frame, float(lxp), float(lzp), 4.35)
	_light_panel(frame, -2.0, 5.0, 2.6)
	_light_panel(frame, 3.0, 5.0, 2.6)
	# "EBUTE METTA" sign over the front doors.
	_box(Vector3(10.0, 1.2, 0.2), frame * _t3(Vector3(0, 4.1, -d * 0.5 - 0.15)),
		_mats["sign_green"], Color(1, 1, 1), false)
	# Luggage stacks near the counters.
	_luggage_stack(frame, -6.5, 6.5)
	_luggage_stack(frame, 6.5, 6.5)
	_luggage_stack(frame, -9.5, 4.0)
	# Loot inside the hall.
	_add_loot_y("health", 40, frame * Vector3(-8.5, 0.55, 3.0))
	_add_loot_y("ammo", 60, frame * Vector3(8.5, 0.55, 3.0))
	_add_loot_y("armor", 50, frame * Vector3(0.0, 0.55, -3.0))
	_add_loot_y("ammo", 60, frame * Vector3(-4.0, 0.55, 5.2))
	_add_loot_y("health", 40, frame * Vector3(4.0, 0.55, 5.2))
	_add_loot_y("armor", 50, frame * Vector3(-8.0, 0.55, -4.5))
	house_positions.append(Vector3(x, 0, z))

# ---------------- platforms ----------------

func _platform(cz: float, width: float, num: int) -> void:
	var length := 120.0
	var top := 1.0
	# Raised slab (collider).
	_box(Vector3(length, top, width), _t3(Vector3(0, top * 0.5, cz)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
	# Hanging platform number sign (emissive board + white dashes).
	_box(Vector3(0.08, 1.2, 0.08), _t3(Vector3(0, top + 3.9, cz + width * 0.22)),
		_mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(3.2, 1.0, 0.14), _t3(Vector3(0, top + 3.2, cz + width * 0.22)),
		_mats["sign_green"], Color(1, 1, 1), false)
	for i in range(num):
		_box(Vector3(0.5, 0.5, 0.03),
			_t3(Vector3(-0.8 + float(i) * 0.9, top + 3.2, cz + width * 0.22 - 0.09)),
			_mats["lamp_head"], Color(1, 1, 1), false)
	# Platform edge safety line (visual).
	_box(Vector3(length, 0.03, 0.35), _t3(Vector3(0, top + 0.015, cz - width * 0.5 + 0.3)),
		_mats["trim"], Color(1, 1, 1), false)
	# Canopy: columns + flat roof panels over the inner strip.
	var coly := top + 2.1
	for i in range(13):
		var px := -60.0 + float(i) * 10.0
		_box(Vector3(0.28, 4.2, 0.28), _t3(Vector3(px, coly, cz + width * 0.22)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(10.6, 0.12, width + 1.4),
			_t3(Vector3(-60.0 + float(i) * 10.0 + 5.0, top + 4.3, cz + width * 0.22)),
			_mats["roof_red"], _varc(Color(1, 1, 1), 0.08), false)
	# Benches + lamps along the platform.
	for i in range(6):
		var px2 := -50.0 + float(i) * 20.0
		var bf := Transform3D(Basis(), Vector3(px2, top, cz - width * 0.15))
		_bench(bf, 0, 0, 0.0)
		_lamp(px2 + 10.0, cz + width * 0.5 - 0.4, top)
	# End ramps (walkable) at both ends.
	for ev in [-1.0, 1.0]:
		var e: float = ev
		var fx := e * 65.0
		var yaw := 0.0 if e < 0.0 else PI
		_stairs(Transform3D(Basis(Vector3.UP, yaw), Vector3(fx, 0, cz)), 0.0, 5.0, 3.0, 0.0, top)
	house_positions.append(Vector3(0, 0, cz))


func _build_platforms() -> void:
	_platform(8.0, 4.0, 1)    # Platform 1 (north of the tracks)
	_platform(26.0, 6.0, 2)   # Platform 2 (south of the tracks)
	# Loot on the platforms.
	for px in [-40.0, -10.0, 25.0, 50.0]:
		_add_loot_y("ammo", 60, Vector3(float(px), 1.55, 8.0))
	_add_loot_y("health", 40, Vector3(-25.0, 1.55, 8.0))
	_add_loot_y("armor", 50, Vector3(15.0, 1.55, 8.0))
	for px2 in [-30.0, 5.0, 40.0]:
		_add_loot_y("health", 40, Vector3(float(px2), 1.55, 26.0))
	_add_loot_y("armor", 50, Vector3(-5.0, 1.55, 26.0))


# ---------------- train ----------------

func _bogie(frame: Transform3D, lx: float) -> void:
	var bf := frame * _t3(Vector3(lx, 0, 0))
	_box(Vector3(2.2, 0.9, 2.4), bf * _t3(Vector3(0, 0.55, 0)),
		_mats["train_dark"], Color(1, 1, 1), false)
	for wx in [-0.75, 0.75]:
		for wz in [-1.0, 1.0]:
			_cyl(0.42, 0.25,
				bf * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5),
					Vector3(float(wx), 0.42, float(wz))),
				_mats["train_dark"], _varc(Color(1, 1, 1), 0.1), false)


func _train_car(cx: float, cz: float) -> void:
	var L := 10.0
	var W := 3.0
	var base_y := 1.0   # floor level
	var wall_h := 2.5
	var frame := Transform3D(Basis(), Vector3(cx, 0, cz))
	var body: StandardMaterial3D = _mats["train_blue"]
	var bcol := _varc(Color(0.10, 0.24, 0.55), 0.10)
	# Floor (walkable collider).
	_box(Vector3(L, 0.25, W), frame * _t3(Vector3(0, base_y - 0.125, 0)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	# Bogies + wheels.
	_bogie(frame, -L * 0.5 + 1.6)
	_bogie(frame, L * 0.5 - 1.6)
	# Side walls with REAL door openings (near the ends) and window band.
	var holes := []
	holes.append([-3.5, 0.0, 1.4, 2.0])
	holes.append([3.5, 0.0, 1.4, 2.0])
	for wx in [-2.4, -1.2, 0.0, 1.2, 2.4]:
		holes.append([wx, 0.8, 1.2, 0.8])
	var wall_frame := frame * _t3(Vector3(0, base_y, 0))
	_wall_open(wall_frame * _t3(Vector3(0, 0, W * 0.5)), L, wall_h, 0.15,
		holes, body, bcol, true)
	_wall_open(wall_frame * _t3(Vector3(0, 0, -W * 0.5)), L, wall_h, 0.15,
		holes, body, bcol, true)
	# End walls with a small window opening.
	var end_holes := [[0.0, 1.4, 1.0, 0.7]]
	_wall_open(wall_frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(L * 0.5, 0, 0)),
		W, wall_h, 0.15, end_holes, body, bcol, true)
	_wall_open(wall_frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-L * 0.5, 0, 0)),
		W, wall_h, 0.15, end_holes, body, bcol, true)
	# Roof + white livery stripe.
	_box(Vector3(L + 0.5, 0.16, W + 0.4), frame * _t3(Vector3(0, base_y + wall_h + 0.08, 0)),
		_mats["train_white"], Color(1, 1, 1), false)
	_box(Vector3(L - 0.4, 0.35, W + 0.2), frame * _t3(Vector3(0, base_y + 1.9, 0)),
		_mats["train_white"], Color(1, 1, 1), false)
	# Interior: rows of seats (visual) + overhead racks.
	var seat: StandardMaterial3D = _mats["seat_blue"]
	for rx in [-3.6, -1.8, 0.0, 1.8, 3.6]:
		for sz in [-0.85, 0.85]:
			var scol := _varc(Color(1, 1, 1), 0.12)
			_box(Vector3(0.55, 0.5, 0.55),
				frame * _t3(Vector3(float(rx), base_y + 0.25, float(sz))),
				seat, scol, false)
			_box(Vector3(0.55, 0.7, 0.14),
				frame * _t3(Vector3(float(rx), base_y + 0.85, float(sz) - signf(float(sz)) * 0.3)),
				seat, scol, false)
	for rz in [-1.1, 1.1]:
		_box(Vector3(L - 1.0, 0.06, 0.5), frame * _t3(Vector3(0, base_y + 2.1, float(rz))),
			_mats["wood_dark"], Color(1, 1, 1), false)
	# Emissive ceiling light strips down the car.
	for lx2 in [-2.5, 2.5]:
		_light_panel(frame, float(lx2), 0.0, base_y + 2.35)
	# Loot inside the car.
	var kinds := ["ammo", "health", "armor"]
	_add_loot_y(kinds[int(absf(cx)) % 3], 60, frame * Vector3(-2.0, base_y + 0.55, 0))
	_add_loot_y("health", 40, frame * Vector3(2.0, base_y + 0.55, 0))
	house_positions.append(Vector3(cx, 0, cz))


func _locomotive(cx: float, cz: float) -> void:
	var L := 8.0
	var frame := Transform3D(Basis(), Vector3(cx, 0, cz))
	var body: StandardMaterial3D = _mats["train_blue"]
	var bcol := _varc(Color(0.08, 0.20, 0.48), 0.08)
	# Underframe + bogies.
	_box(Vector3(L, 0.5, 2.8), frame * _t3(Vector3(0, 0.85, 0)),
		_mats["train_dark"], Color(1, 1, 1), false)
	_bogie(frame, -L * 0.5 + 1.5)
	_bogie(frame, L * 0.5 - 1.5)
	# Cab (rear half) with window band openings on the sides.
	var cab_h := 2.7
	var cab_holes := []
	for wx in [-0.9, 0.9]:
		cab_holes.append([wx, 1.5, 1.0, 0.8])
	var cab_frame := frame * _t3(Vector3(-1.75, 1.1, 0))
	_wall_open(cab_frame * _t3(Vector3(0, 0, 1.325)), 4.5, cab_h, 0.15,
		cab_holes, body, bcol, true)
	_wall_open(cab_frame * _t3(Vector3(0, 0, -1.325)), 4.5, cab_h, 0.15,
		cab_holes, body, bcol, true)
	_wall_open(cab_frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(2.25, 0, 0)),
		2.65, cab_h, 0.15, [[0.0, 1.5, 1.2, 0.8]], body, bcol, true)
	_wall_open(cab_frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-2.25, 0, 0)),
		2.65, cab_h, 0.15, [[0.0, 0.0, 1.2, 2.2]], body, bcol, true)
	_box(Vector3(4.5, 0.2, 2.65), cab_frame * _t3(Vector3(0, -0.1, 0)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	_box(Vector3(4.7, 0.16, 3.0), cab_frame * _t3(Vector3(0, cab_h + 0.08, 0)),
		_mats["train_white"], Color(1, 1, 1), false)
	# Sloped nose (front half): rotated hood + windshield + headlight.
	var nose := frame * Transform3D(Basis(Vector3(0, 0, 1), -0.30),
		Vector3(2.1, 1.9, 0))
	_box(Vector3(3.6, 1.7, 2.7), nose, body, bcol, true)
	var shield := frame * Transform3D(Basis(Vector3(0, 0, 1), -0.55),
		Vector3(0.6, 2.9, 0))
	_box(Vector3(0.9, 1.1, 2.4), shield, _mats["glass_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.15, 0.3, 0.5), frame * _t3(Vector3(3.95, 1.5, 0)),
		_mats["headlight"], Color(1, 1, 1), false)
	# White stripe along the cab.
	_box(Vector3(4.6, 0.35, 2.86), frame * _t3(Vector3(-1.75, 2.6, 0)),
		_mats["train_white"], Color(1, 1, 1), false)
	# Cab ceiling light (emissive).
	_light_panel(frame, -1.75, 0.0, 3.55)
	_add_loot_y("armor", 50, frame * Vector3(-1.75, 1.65, 0))
	house_positions.append(Vector3(cx, 0, cz))


func _build_train() -> void:
	# Parked on track 1 (z=13): locomotive + 4 cars, nose pointing +x.
	_locomotive(-42.0, TRACK1_Z)
	_train_car(-32.4, TRACK1_Z)
	_train_car(-21.8, TRACK1_Z)
	_train_car(-11.2, TRACK1_Z)
	_train_car(-0.6, TRACK1_Z)


# ---------------- footbridge ----------------

func _build_footbridge() -> void:
	var bx := 40.0
	var deck_y := 5.2
	var z0 := 9.0
	var z1 := 25.0
	var span := z1 - z0
	var zmid := (z0 + z1) * 0.5
	# Deck (walkable collider) + edge curbs.
	_box(Vector3(2.4, 0.18, span), _t3(Vector3(bx, deck_y - 0.09, zmid)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
	# Support columns down to the ground.
	for pz in [11.0, 17.0, 23.0]:
		_box(Vector3(0.35, deck_y, 0.35), _t3(Vector3(bx - 0.8, deck_y * 0.5, pz)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(0.35, deck_y, 0.35), _t3(Vector3(bx + 0.8, deck_y * 0.5, pz)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
	# Railings: posts + double rails on both sides.
	for sx in [-1.15, 1.15]:
		for k in range(9):
			var pz2 := z0 + span * float(k) / 8.0
			_box(Vector3(0.09, 1.0, 0.09), _t3(Vector3(bx + float(sx), deck_y + 0.5, pz2)),
				_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
		for ry in [0.55, 1.0]:
			_box(Vector3(0.08, 0.08, span), _t3(Vector3(bx + float(sx), deck_y + float(ry), zmid)),
				_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	# Stairs A: ground (z=1) up to the deck (z=9).
	_stairs(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(bx, 0, 1.0)),
		0.0, 8.0, 2.4, 0.0, deck_y)
	# Stairs B: deck (z=25) down onto Platform 2 (top y=1.0, z=29).
	_stairs(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(bx, deck_y, z1)),
		0.0, 4.0, 2.4, 0.0, -(deck_y - 1.0))
	house_positions.append(Vector3(bx, 0, zmid))

# ---------------- parking lot ----------------

func _car(x: float, z: float, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var paint := _varc(Color(0.55, 0.60, 0.65), 0.35)
	_box(Vector3(4.2, 0.65, 1.8), frame * _t3(Vector3(0, 0.62, 0)),
		_mats["car_paint"], paint, false)
	_box(Vector3(2.2, 0.55, 1.6), frame * _t3(Vector3(-0.2, 1.2, 0)),
		_mats["car_paint"], paint.darkened(0.08), false)
	_box(Vector3(2.0, 0.4, 1.62), frame * _t3(Vector3(-0.2, 1.22, 0)),
		_mats["glass_dark"], Color(1, 1, 1), false)
	_batch.add_collider(Vector3(4.3, 1.5, 1.9), frame * _t3(Vector3(0, 0.75, 0)))
	for wx in [-1.35, 1.35]:
		for wz in [-0.85, 0.85]:
			_cyl(0.34, 0.25,
				frame * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5),
					Vector3(float(wx), 0.34, float(wz))),
				_mats["tire"], Color(0.9, 0.9, 0.9), false)


func _build_parking() -> void:
	_box(Vector3(100.0, 0.06, 24.0), _t3(Vector3(0, 0.03, 46.0)),
		_mats["asphalt"], Color(1, 1, 1), false)
	var spots := [
		[-36.0, 40.0, 0.0], [-28.0, 40.0, 0.0], [-20.0, 40.0, 0.0],
		[-12.0, 40.0, 0.0], [12.0, 52.0, PI], [20.0, 52.0, PI],
		[28.0, 52.0, PI], [36.0, 52.0, PI],
	]
	for s in spots:
		_car(float(s[0]), float(s[1]), float(s[2]))
	house_positions.append(Vector3(0, 0, 46))


# ---------------- perimeter fence ----------------

func _fence_run(x0: float, z0: float, x1: float, z1: float) -> void:
	var dx := x1 - x0
	var dz := z1 - z0
	var length := sqrt(dx * dx + dz * dz)
	var yaw := atan2(dx, dz)
	var frame := Transform3D(Basis(Vector3.UP, yaw),
		Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5))
	var n := maxi(1, int(length / 4.0))
	for i in range(n + 1):
		var off := -length * 0.5 + length * float(i) / float(n)
		_box(Vector3(0.12, 2.2, 0.12), frame * _t3(Vector3(off, 1.1, 0)),
			_mats["fence_green"], _varc(Color(1, 1, 1), 0.1), false)
	for ry in [0.9, 1.8]:
		_box(Vector3(length, 0.08, 0.06), frame * _t3(Vector3(0, float(ry), 0)),
			_mats["fence_green"], _varc(Color(1, 1, 1), 0.1), false)
	_batch.add_collider(Vector3(length, 2.0, 0.3), frame * _t3(Vector3(0, 1.0, 0)))


func _build_fence() -> void:
	var e := 66.0
	_fence_run(-e, -e, -8.0, -e)   # north, west of the main gate
	_fence_run(8.0, -e, e, -e)     # north, east of the main gate
	_fence_run(-e, e, e, e)        # south
	_fence_run(e, -e, e, e)        # east
	_fence_run(-e, -e, -e, e)      # west
	# Main gate: pillars + station sign.
	for gx in [-8.6, 8.6]:
		_box(Vector3(1.2, 3.4, 1.2), _t3(Vector3(float(gx), 1.7, -e)),
			_mats["concrete_dark"], Color(1, 1, 1), true)
	_box(Vector3(18.4, 1.4, 0.3), _t3(Vector3(0, 3.6, -e)),
		_mats["sign_green"], Color(1, 1, 1), false)


# ---------------- plaza ----------------

func _build_plaza() -> void:
	_box(Vector3(56.0, 0.08, 30.0), _t3(Vector3(0, 0.04, -38.0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.05), false)
	var pf := Transform3D(Basis(), Vector3.ZERO)
	for bx in [-18.0, -6.0, 6.0, 18.0]:
		_bench(pf, float(bx), -34.0, 0.0)
		_bench(pf, float(bx), -44.0, PI)
	for lx in [-24.0, -8.0, 8.0, 24.0]:
		_lamp(float(lx), -50.0)


# ---------------- props: crates / sandbags / clouds ----------------

func _sandbag_wall(x: float, z: float, yaw: float, length := 3.6) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var bag := Vector3(0.62, 0.30, 0.42)
	var n := int(length / 0.66)
	for row in range(2):
		for k in range(n):
			var off := -length * 0.5 + 0.66 * (float(k) + 0.5)
			var jog := 0.0 if row == 0 else 0.33
			_box(bag, frame * _t3(Vector3(off + jog, 0.16 + float(row) * 0.30,
				_rng.randf_range(-0.03, 0.03))),
				_mats["sandbag"], _varc(Color(0.72, 0.64, 0.48), 0.12), false)
	_batch.add_collider(Vector3(length, 0.75, 0.55), frame * _t3(Vector3(0, 0.38, 0)))

func _build_props() -> void:
	# Crates: hand-placed in known-open spots.
	var spots := [
		[-46.0, -2.0, 0.0], [-44.5, -2.0, 0.9], [46.0, 2.0, 0.0],
		[-52.0, 34.0, 0.0], [52.0, 34.0, 0.0], [-30.0, -30.0, 0.0],
		[30.0, -30.0, 0.0], [-58.0, 46.0, 0.0], [58.0, 46.0, 0.0],
		[14.0, -14.0, 0.0], [-14.0, -14.0, 0.0], [0.0, 34.0, 0.0],
	]
	var pf := Transform3D(Basis(), Vector3.ZERO)
	for s in spots:
		_crate_at(pf, float(s[0]), float(s[1]), 0.9, float(s[2]))
	# Sandbag walls guarding the footbridge stairs + hall corners.
	_sandbag_wall(36.0, 4.0, 0.3)
	_sandbag_wall(44.0, 4.0, -0.3)
	_sandbag_wall(-14.0, -4.0, 0.8)
	_sandbag_wall(14.0, -4.0, -0.8)


func _build_clouds() -> void:
	var cm := SphereMesh.new()
	cm.radius = 1.0
	cm.height = 2.0
	cm.radial_segments = 12
	cm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.96, 0.96, 0.98)
	for k in range(6):
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		mi.scale = Vector3(_rng.randf_range(10, 22), _rng.randf_range(2.0, 3.2),
			_rng.randf_range(6, 10))
		mi.position = Vector3(_rng.randf_range(-90, 90),
			_rng.randf_range(42, 55), _rng.randf_range(-90, 90))
		add_child(mi)
		_clouds.append({"node": mi, "speed": _rng.randf_range(0.4, 1.1)})


# ---------------- pois / loot / finalize ----------------

func _build_pois() -> void:
	for p in POI_DEFS:
		poi_list.append(p)


func _add_loot(kind: String, amount: int, x: float, z: float) -> void:
	loot_spots.append([kind, amount, Vector3(x, 0.55, z)])


func _add_loot_y(kind: String, amount: int, pos: Vector3) -> void:
	loot_spots.append([kind, amount, pos])


func _scatter_loot() -> void:
	var kinds := ["health", "armor", "ammo"]
	var amounts := {"health": 40, "armor": 50, "ammo": 60}
	var idx := 0
	# Denser loot rings at each POI.
	for p in poi_list:
		var pp: Vector3 = p["pos"]
		for k in range(8):
			var a := TAU * float(k) / 8.0 + _rng.randf_range(-0.2, 0.2)
			var r := _rng.randf_range(3.0, 9.0)
			var lx := pp.x + cos(a) * r
			var lz := pp.z + sin(a) * r
			if absf(lx) > 64.0 or absf(lz) > 64.0:
				continue
			var kind: String = kinds[idx % 3]
			_add_loot(kind, int(amounts[kind]), lx, lz)
			idx += 1
	# Keep general scatter clear of the big structures.
	for bc in [[0.0, -14.0], [0.0, 8.0], [0.0, 26.0], [-42.0, 13.0],
			[-32.0, 13.0], [-22.0, 13.0], [-12.0, 13.0], [-1.0, 13.0],
			[40.0, 17.0], [0.0, 46.0], [0.0, -38.0]]:
		_claim(float(bc[0]), float(bc[1]), 10.0)
	var tries := 0
	while loot_spots.size() < 80 and tries < 600:
		tries += 1
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-62, 62)
		if not _claim(x, z, 4.0):
			continue
		var kind2: String = kinds[idx % 3]
		_add_loot(kind2, int(amounts[kind2]), x, z)
		idx += 1


func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -10, -85), Vector3(170, 60, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	enemy_spawns = [
		Vector3(-24, 0.6, -48),
		Vector3(24, 0.6, -48),
		Vector3(-34, 1.6, 7),
		Vector3(54, 1.6, 26),
		Vector3(20, 0.6, 46),
		Vector3(58, 0.6, -20),
	]
	print("TrainStation built: instances=", _batch.box_count(), " draws=", draws,
		" colliders=", _batch.collider_count(), " loot=", loot_spots.size(),
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 110.0:
			cn.position.x = -110.0
