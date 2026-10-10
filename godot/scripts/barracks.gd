extends Node3D
class_name BarracksMap
## Phase 7: Military Barracks — Nigerian Army cantonment (map #6, selector idx 5).
## Flat 140x140m: central parade ground, four enterable two-story barrack
## blocks (dorm rooms with beds/lockers/crates), reinforced armory (hot zone,
## dense loot), officers' mess hall (tables/benches), gatehouse + main gate
## with flanking watchtowers, perimeter wall, flag-pole plaza, training
## obstacle course, parked military trucks/jeeps. Seeded (SEED), merge-ready,
## clean origin. Ground is FLAT (y=0) — no ground_height(); y baked into spawns.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const SEED := 20261014

const POI_DEFS := [
	{"name": "Parade Ground", "pos": Vector3(0, 0, 0)},
	{"name": "Armory", "pos": Vector3(30, 0, 42)},
	{"name": "Mess Hall", "pos": Vector3(-30, 0, 42)},
	{"name": "Gatehouse", "pos": Vector3(22, 0, 62)},
]

var map_extent := 70.0
var player_spawn := Vector3(0, 0.6, -30)
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
	_build_parade()
	_build_flag_plaza()
	_build_perimeter()
	_build_gate_complex()
	_build_barracks()
	_build_armory()
	_build_mess_hall()
	_build_obstacle_course()
	_build_vehicles()
	_build_lamps()
	_build_sandbags()
	_build_crates()
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
	_mats["parade"] = _std(Color(0.62, 0.61, 0.58), 0.9)
	_mats["concrete"] = _std(Color(0.60, 0.59, 0.56))
	_mats["concrete_dark"] = _std(Color(0.42, 0.41, 0.39))
	_mats["wall_tan"] = _std(Color(1, 1, 1), 0.9)      # per-instance weathered tan
	_mats["wall_armory"] = _std(Color(1, 1, 1), 0.9)   # per-instance grey-green
	_mats["trim"] = _std(Color(0.92, 0.90, 0.86), 0.85)
	_mats["roof"] = _std(Color(0.32, 0.32, 0.34), 0.9)
	_mats["wood"] = _std(Color(0.45, 0.33, 0.20), 0.9)
	_mats["wood_dark"] = _std(Color(0.30, 0.22, 0.13), 0.9)
	_mats["crate"] = _std(Color(0.52, 0.40, 0.24), 0.9)
	_mats["mattress"] = _std(Color(0.78, 0.76, 0.70), 0.95)
	_mats["locker"] = _std(Color(0.35, 0.42, 0.38), 0.6, 0.3)
	_mats["metal"] = _std(Color(0.45, 0.47, 0.50), 0.5, 0.5)
	_mats["sandbag"] = _std(Color(1, 1, 1), 0.95)      # per-instance tan variation
	_mats["canvas"] = _std(Color(0.42, 0.44, 0.30), 0.95)
	_mats["tire"] = _std(Color(0.12, 0.12, 0.13), 0.95)
	_mats["truck_green"] = _std(Color(1, 1, 1), 0.7, 0.2)  # per-instance olive
	_mats["truck_dark"] = _std(Color(0.16, 0.18, 0.16), 0.4, 0.2)
	_mats["water_tank"] = _std(Color(0.20, 0.35, 0.55), 0.6)
	_mats["flag"] = _std(Color(1, 1, 1), 0.8)          # per-instance stripe color
	var lamp := _std(Color(1.0, 0.9, 0.65), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.55)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp_head"] = lamp


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


func _strut(a: Vector3, b: Vector3, w: float, d: float, mat: StandardMaterial3D) -> void:
	# Oriented box beam between two points.
	var dv := b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dv.x, dv.z)
	var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
	_box(Vector3(w, length, d), Transform3D(basis, mid), mat, Color(1, 1, 1), false)


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


func _high_windows(frame: Transform3D, W: float, H: float, T: float, mat: StandardMaterial3D, col: Color) -> void:
	# Small high window slits (armory) — real openings.
	var n := maxi(2, int(W / 4.0))
	var holes := []
	for i in range(n):
		var xc := -W * 0.5 + W * (float(i) + 0.5) / float(n)
		holes.append([xc, 2.3, 1.2, 0.9])
	_wall_open(frame, W, H, T, holes, mat, col, true)


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


func _stairs(frame: Transform3D, x0: float, run: float, width: float, zc: float, rise: float, y_base := 0.0) -> void:
	# Visual steps + one ramp collider (player walks up smoothly).
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
	_strut(frame * Vector3(x0, y_base + 1.0, zc - width * 0.5),
		frame * Vector3(x0 + run, y_base + rise + 1.0, zc - width * 0.5), 0.06, 0.06, _mats["metal"])


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

func _bed(frame: Transform3D, lx: float, lz: float, yaw: float) -> void:
	var bf := frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, 0, lz))
	_box(Vector3(1.0, 0.45, 2.1), bf * _t3(Vector3(0, 0.225, 0)),
		_mats["wood_dark"], Color(1, 1, 1), true)
	_box(Vector3(0.92, 0.22, 2.0), bf * _t3(Vector3(0, 0.56, 0)),
		_mats["mattress"], Color(1, 1, 1), false)
	_box(Vector3(0.6, 0.12, 0.4), bf * _t3(Vector3(0, 0.72, -0.75)),
		_mats["mattress"], Color(0.9, 0.9, 0.9), false)


func _locker(frame: Transform3D, lx: float, lz: float, yaw: float) -> void:
	var lf := frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, 0, lz))
	_box(Vector3(1.6, 2.0, 0.5), lf * _t3(Vector3(0, 1.0, 0)),
		_mats["locker"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(0.04, 1.8, 0.03), lf * _t3(Vector3(0, 1.0, 0.26)),
		_mats["metal"], Color(1, 1, 1), false)


func _crate_at(frame: Transform3D, lx: float, lz: float, s := 0.9, y_base := 0.0) -> void:
	_box(Vector3(s, s, s), frame * _t3(Vector3(lx, y_base + s * 0.5, lz)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.12), true)


func _light_panel(frame: Transform3D, lx: float, lz: float, fy: float) -> void:
	# Emissive ceiling light: housing + glowing diffuser (batched, no real light).
	_box(Vector3(2.0, 0.08, 1.1), frame * _t3(Vector3(lx, fy, lz)),
		_mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(1.8, 0.05, 0.9), frame * _t3(Vector3(lx, fy - 0.055, lz)),
		_mats["lamp_head"], Color(1, 1, 1), false)


func _ac_unit(frame: Transform3D, lx: float, lz: float, fy: float) -> void:
	# Rooftop AC condenser: box + dark fan grille face.
	_box(Vector3(1.1, 0.8, 0.8), frame * _t3(Vector3(lx, fy + 0.4, lz)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(0.7, 0.5, 0.06), frame * _t3(Vector3(lx, fy + 0.4, lz + 0.42)),
		_mats["concrete_dark"], Color(1, 1, 1), false)


func _sign_board(frame: Transform3D, lx: float, fy: float, lz: float, w: float) -> void:
	# Glowing sign board with white lettering dashes (proud of the facade).
	_box(Vector3(w, 0.8, 0.12), frame * _t3(Vector3(lx, fy, lz)),
		_mats["concrete_dark"], Color(1, 1, 1), false)
	for i in range(3):
		_box(Vector3(0.9, 0.16, 0.03),
			frame * _t3(Vector3(lx - w * 0.28 + float(i) * w * 0.28, fy, lz + 0.07)),
			_mats["lamp_head"], Color(1, 1, 1), false)


func _table_set(frame: Transform3D, lx: float, lz: float) -> void:
	var tf := frame * _t3(Vector3(lx, 0, lz))
	_box(Vector3(2.4, 0.08, 1.0), tf * _t3(Vector3(0, 0.74, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	for sx in [-1.05, 1.05]:
		for sz in [-0.4, 0.4]:
			_box(Vector3(0.09, 0.72, 0.09),
				tf * _t3(Vector3(float(sx), 0.36, float(sz))),
				_mats["wood_dark"], Color(1, 1, 1), false)
	for bz in [-0.95, 0.95]:
		_box(Vector3(2.2, 0.45, 0.35), tf * _t3(Vector3(0, 0.225, float(bz))),
			_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)


func _rack(frame: Transform3D, lx: float, lz: float, yaw: float) -> void:
	var rf := frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, 0, lz))
	for px in [-1.0, 1.0]:
		_box(Vector3(0.12, 1.8, 0.12), rf * _t3(Vector3(float(px), 0.9, 0)),
			_mats["wood_dark"], Color(1, 1, 1), true)
	for by in [0.5, 1.3]:
		_box(Vector3(2.2, 0.08, 0.3), rf * _t3(Vector3(0, float(by), 0)),
			_mats["wood_dark"], Color(1, 1, 1), false)
	for i in range(4):
		var rx := -0.75 + float(i) * 0.5
		var tilt := Transform3D(Basis(Vector3(1, 0, 0), 0.18), Vector3(rx, 0.85, 0.05))
		_box(Vector3(0.09, 1.3, 0.16), rf * tilt,
			_mats["metal"], Color(0.9, 0.9, 0.9), false)


# ---------------- ground / parade / flag ----------------

func _ground_color(x: float, z: float) -> Color:
	var dirt := Color(0.50, 0.44, 0.32)
	var grass := Color(0.33, 0.48, 0.26)
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


func _build_parade() -> void:
	var s := 32.0
	_box(Vector3(s, 0.12, s), _t3(Vector3(0, 0.06, 0)),
		_mats["parade"], Color(1, 1, 1), true)
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(s, 0.02, 0.4), _t3(Vector3(0, 0.13, ef * (s * 0.5 - 0.4))),
			_mats["trim"], Color(1, 1, 1), false)
		_box(Vector3(0.4, 0.02, s), _t3(Vector3(ef * (s * 0.5 - 0.4), 0.13, 0)),
			_mats["trim"], Color(1, 1, 1), false)
	# Center emblem ring.
	_cyl(3.0, 0.03, _t3(Vector3(0, 0.135, 0)), _mats["trim"], Color(1, 1, 1), false)


func _build_flag_plaza() -> void:
	var px := 0.0
	var pz := -22.0
	_cyl(6.0, 0.1, _t3(Vector3(px, 0.05, pz)),
		_mats["parade"], Color(0.95, 0.95, 0.95), true)
	_cyl(0.09, 10.0, _t3(Vector3(px, 5.0, pz)),
		_mats["metal"], Color(1, 1, 1), true)
	# Nigerian flag: green-white-green vertical stripes.
	var cols := [Color(0.0, 0.45, 0.18), Color(0.95, 0.95, 0.95), Color(0.0, 0.45, 0.18)]
	for i in range(3):
		_box(Vector3(0.85, 1.5, 0.05),
			_t3(Vector3(px + 0.5 + float(i) * 0.85, 8.9, pz)),
			_mats["flag"], cols[i], false)


# ---------------- perimeter / gate ----------------

func _wall_run(x0: float, z0: float, x1: float, z1: float, h := 3.0, t := 0.4) -> void:
	var dx := x1 - x0
	var dz := z1 - z0
	var length := sqrt(dx * dx + dz * dz)
	var yaw := atan2(dx, dz)
	var n := maxi(1, int(length / 8.0))
	var seg := length / float(n)
	var frame := Transform3D(Basis(Vector3.UP, yaw),
		Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5))
	for i in range(n):
		var off := -length * 0.5 + seg * (float(i) + 0.5)
		_box(Vector3(seg + 0.08, h, t), frame * _t3(Vector3(off, h * 0.5, 0)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.08), true)


func _build_perimeter() -> void:
	var e := 66.0
	_wall_run(-e, -e, e, -e)            # north
	_wall_run(-e, e, -3.2, e)           # south, west of gate
	_wall_run(3.2, e, e, e)             # south, east of gate
	_wall_run(e, -e, e, e)              # east
	_wall_run(-e, -e, -e, e)            # west
	for cx in [-e, e]:
		for cz in [-e, e]:
			_box(Vector3(1.0, 3.8, 1.0),
				_t3(Vector3(float(cx), 1.9, float(cz))),
				_mats["concrete_dark"], Color(1, 1, 1), true)


func _watchtower(x: float, z: float, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var plat_y := 4.2
	for sx in [-1.3, 1.3]:
		for sz in [-1.3, 1.3]:
			_box(Vector3(0.28, plat_y, 0.28),
				frame * _t3(Vector3(float(sx), plat_y * 0.5, float(sz))),
				_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), true)
	_box(Vector3(3.4, 0.25, 3.4), frame * _t3(Vector3(0, plat_y, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	for i in range(4):
		var a := float(i) * PI * 0.5
		var px := cos(a) * 1.62
		var pz := sin(a) * 1.62
		_box(Vector3(0.08, 0.9, 0.08), frame * _t3(Vector3(px, plat_y + 0.55, pz)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
		_box(Vector3(3.3, 0.08, 0.08),
			frame * Transform3D(Basis(Vector3.UP, -a), Vector3.ZERO) * _t3(Vector3(px, plat_y + 1.0, pz)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	for sx in [-1.4, 1.4]:
		for sz in [-1.4, 1.4]:
			_box(Vector3(0.18, 1.6, 0.18),
				frame * _t3(Vector3(float(sx), plat_y + 1.9, float(sz))),
				_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	_box(Vector3(4.0, 0.16, 4.0), frame * _t3(Vector3(0, plat_y + 2.75, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.1), false)
	var run := 7.0
	var ang := atan2(plat_y - 0.1, run)
	var ramp := frame * Transform3D(Basis(Vector3(1, 0, 0), ang),
		Vector3(0, plat_y * 0.5 - 0.05, 1.7 + run * 0.5))
	var ramp_len := sqrt(run * run + plat_y * plat_y)
	_batch.add_collider(Vector3(1.5, 0.15, ramp_len), ramp)
	for k in range(9):
		var t := (float(k) + 0.5) / 9.0
		_box(Vector3(1.5, 0.08, 0.7),
			frame * _t3(Vector3(0, 0.15 + t * (plat_y - 0.25), 1.7 + t * run)),
			_mats["wood"], _varc(Color(1, 1, 1), 0.1), false)
	house_positions.append(Vector3(x, 0, z))


func _gatehouse(x: float, z: float, yaw: float) -> void:
	var w := 6.0
	var d := 5.0
	var fh := 3.0
	var t := 0.25
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var wall: StandardMaterial3D = _mats["wall_tan"]
	var col := _varc(Color(0.84, 0.76, 0.60), 0.08)
	# Ground floor: door on the south wall + window bands elsewhere.
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, fh, t,
		[[-1.9, 1.1, 1.2, 1.2], [0.0, 0.0, 1.5, 2.5], [1.9, 1.1, 1.2, 1.2]],
		wall, col)
	_trim_opening(frame * _t3(Vector3(0, 0, d * 0.5)), 0.0, 0.0, 1.5, 2.5, t)
	_window_wall(frame * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, wall, col, false)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	# Desk + crate inside.
	_box(Vector3(1.8, 0.08, 0.9), frame * _t3(Vector3(0.4, 0.78, 1.2)),
		_mats["wood"], Color(1, 1, 1), true)
	for sx in [-0.75, 0.75]:
		for sz in [-0.3, 0.3]:
			_box(Vector3(0.08, 0.76, 0.08),
				frame * _t3(Vector3(0.4 + float(sx), 0.38, 1.2 + float(sz))),
				_mats["wood_dark"], Color(1, 1, 1), false)
	_crate_at(frame, -1.8, -1.5)
	# Upper floor.
	_slab_hole(frame, w, d, fh, -1.0, 1.0, 0.0, 1.8)
	_stairs(frame, -2.5, 3.5, 1.8, 0.0, fh)
	var up := frame * _t3(Vector3(0, fh, 0))
	_window_wall(up * _t3(Vector3(0, 0, d * 0.5)), w, fh, t, wall, col, false)
	_window_wall(up * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, wall, col, false)
	_window_wall(up * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	_window_wall(up * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	# Roof slab with stairwell hole (roof access stairs from the upper floor).
	_slab_hole(frame, w, d, 2.0 * fh, 0.5, 2.5, 0.0, 1.6)
	_stairs(frame, -2.5, 5.0, 1.6, 0.0, fh, fh)
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(w + 0.3, 0.7, 0.22),
			frame * _t3(Vector3(0, 2.0 * fh + 0.35, ef * (d * 0.5 + 0.05))),
			wall, col, true)
		_box(Vector3(0.22, 0.7, d + 0.3),
			frame * _t3(Vector3(ef * (w * 0.5 + 0.05), 2.0 * fh + 0.35, 0)),
			wall, col, true)
	# Ceiling light panels (emissive) on both floors + rooftop loot.
	_light_panel(frame, 0.0, 0.0, fh - 0.28)
	_light_panel(frame, 0.0, 0.0, 2.0 * fh - 0.28)
	_add_loot_y("armor", 50, frame * Vector3(1.8, 2.0 * fh + 0.55, 1.5))
	_add_loot_y("health", 40, frame * Vector3(-1.5, 0.55, 1.5))
	_add_loot_y("ammo", 60, frame * Vector3(1.8, 0.55, -1.5))
	_add_loot_y("armor", 50, up * Vector3(-1.5, 0.55, 0.5))
	_add_loot_y("ammo", 60, up * Vector3(1.5, 0.55, -0.5))
	house_positions.append(Vector3(x, 0, z))


func _build_gate_complex() -> void:
	# Gate posts framing the 6.4m opening in the south wall.
	for px in [-3.8, 3.8]:
		_box(Vector3(1.2, 4.2, 1.2), _t3(Vector3(float(px), 2.1, 66.0)),
			_mats["concrete_dark"], Color(1, 1, 1), true)
		_box(Vector3(1.5, 0.3, 1.5), _t3(Vector3(float(px), 4.35, 66.0)),
			_mats["trim"], Color(1, 1, 1), false)
	_gatehouse(16.0, 62.0, 0.0)
	_watchtower(-9.0, 62.5, 0.2)
	_watchtower(9.0, 62.5, -0.2)


# ---------------- barrack blocks ----------------

func _barrack(x: float, z: float, yaw: float) -> void:
	var w := 16.0
	var d := 8.0
	var fh := 3.2
	var t := 0.3
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var wall: StandardMaterial3D = _mats["wall_tan"]
	var col := _varc(Color(0.82, 0.74, 0.58), 0.10)
	# Ground floor: front door + windows, window bands elsewhere.
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, fh, t,
		[[-5.0, 1.1, 1.4, 1.3], [0.0, 0.0, 1.6, 2.6], [5.0, 1.1, 1.4, 1.3]],
		wall, col)
	_trim_opening(frame * _t3(Vector3(0, 0, d * 0.5)), 0.0, 0.0, 1.6, 2.6, t)
	_window_wall(frame * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, wall, col, false)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	# Interior partition with door (two dorm rooms).
	_wall_open(frame * _t3(Vector3(3.5, 0, 0)), d, fh, 0.2,
		[[0.0, 0.0, 1.4, 2.4]], wall, col)
	# Ground floor furniture.
	_bed(frame, -6.0, 2.4, PI * 0.5)
	_bed(frame, -6.0, -2.4, PI * 0.5)
	_bed(frame, -2.5, 2.4, PI * 0.5)
	_bed(frame, 5.5, 2.4, -PI * 0.5)
	_bed(frame, 5.5, -2.4, -PI * 0.5)
	_locker(frame, -4.5, -3.4, 0.0)
	_locker(frame, -2.5, -3.4, 0.0)
	_locker(frame, 5.5, 3.4, PI)
	_crate_at(frame, 0.5, -3.2)
	_crate_at(frame, 1.6, -3.2)
	_crate_at(frame, 1.05, -3.2, 0.7, 0.9)
	# Upper floor slab with stairwell + stairs.
	_slab_hole(frame, w, d, fh, -1.25, 1.25, 0.0, 2.2)
	_stairs(frame, -3.75, 5.0, 2.2, 0.0, fh)
	var up := frame * _t3(Vector3(0, fh, 0))
	_window_wall(up * _t3(Vector3(0, 0, d * 0.5)), w, fh, t, wall, col, false)
	_window_wall(up * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, wall, col, false)
	_window_wall(up * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	_window_wall(up * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, fh, t, wall, col, false)
	_wall_open(up * _t3(Vector3(3.5, 0, 0)), d, fh, 0.2,
		[[0.0, 0.0, 1.4, 2.4]], wall, col)
	_bed(up, -6.0, 2.4, PI * 0.5)
	_bed(up, -6.0, -2.4, PI * 0.5)
	_bed(up, 5.5, 2.6, -PI * 0.5)
	_locker(up, -4.5, -3.4, 0.0)
	_locker(up, -2.5, -3.4, 0.0)
	_crate_at(up, 5.5, -3.2)
	_crate_at(up, 6.6, -3.2)
	# Ceiling light panels (emissive) on both floors.
	_light_panel(frame, -4.0, 0.0, fh - 0.28)
	_light_panel(frame, 4.0, 0.0, fh - 0.28)
	_light_panel(frame, -4.0, 0.0, 2.0 * fh - 0.28)
	_light_panel(frame, 4.0, 0.0, 2.0 * fh - 0.28)
	# Roof slab with stairwell hole (roof access stairs from the upper floor).
	_slab_hole(frame, w, d, 2.0 * fh, 5.5, 8.0, 0.0, 2.2)
	_stairs(frame, 3.0, 5.0, 2.2, 0.0, fh, fh)
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(w + 0.4, 0.8, 0.25),
			frame * _t3(Vector3(0, 2.0 * fh + 0.4, ef * (d * 0.5 + 0.075))),
			wall, col, true)
		_box(Vector3(0.25, 0.8, d + 0.4),
			frame * _t3(Vector3(ef * (w * 0.5 + 0.075), 2.0 * fh + 0.4, 0)),
			wall, col, true)
	var tx := -w * 0.25
	for sx in [-0.9, 0.9]:
		for sz in [-0.9, 0.9]:
			_box(Vector3(0.15, 0.7, 0.15),
				frame * _t3(Vector3(tx + float(sx), 2.0 * fh + 0.35, float(sz))),
				_mats["metal"], Color(1, 1, 1), false)
	_cyl(1.2, 2.0, frame * _t3(Vector3(tx, 2.0 * fh + 1.6, 0)),
		_mats["water_tank"], Color(1, 1, 1), true)
	# Rooftop AC units + rooftop loot (roof reachable via the upper stairs).
	_ac_unit(frame, -1.0, -2.6, 2.0 * fh)
	_ac_unit(frame, -1.0, 2.6, 2.0 * fh)
	_add_loot_y("ammo", 60, frame * Vector3(-5.5, 2.0 * fh + 0.55, -2.2))
	_add_loot_y("health", 40, frame * Vector3(-5.5, 2.0 * fh + 0.55, 2.2))
	# Loot inside (ground + upper floors).
	_add_loot_y("health", 40, frame * Vector3(-5.0, 0.55, 0.0))
	_add_loot_y("ammo", 60, frame * Vector3(5.5, 0.55, -1.0))
	_add_loot_y("armor", 50, up * Vector3(-5.0, 0.55, 0.0))
	_add_loot_y("ammo", 60, up * Vector3(5.5, 0.55, 1.0))
	house_positions.append(Vector3(x, 0, z))


func _build_barracks() -> void:
	_barrack(-34.0, -18.0, 0.8)
	_barrack(34.0, -18.0, -0.8)
	_barrack(-34.0, 26.0, 2.35)
	_barrack(34.0, 26.0, -2.35)


# ---------------- armory (hot zone) ----------------

func _build_armory() -> void:
	var x := 30.0
	var z := 52.0
	var w := 14.0
	var d := 10.0
	var h := 3.6
	var t := 0.45
	var frame := Transform3D(Basis(), Vector3(x, 0, z))
	var wall: StandardMaterial3D = _mats["wall_armory"]
	var col := _varc(Color(0.55, 0.58, 0.52), 0.08)
	# Front (north, -z): wide armored door + high windows.
	_wall_open(frame * _t3(Vector3(0, 0, -d * 0.5)), w, h, t,
		[[-4.5, 2.3, 1.2, 0.9], [0.0, 0.0, 2.4, 3.0], [4.5, 2.3, 1.2, 0.9]],
		wall, col)
	_trim_opening(frame * _t3(Vector3(0, 0, -d * 0.5)), 0.0, 0.0, 2.4, 3.0, t)
	_high_windows(frame * _t3(Vector3(0, 0, d * 0.5)), w, h, t, wall, col)
	_high_windows(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, h, t, wall, col)
	_high_windows(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, h, t, wall, col)
	# Weapon racks + ammo crate stacks inside.
	_rack(frame, -4.0, 2.5, 0.0)
	_rack(frame, 0.0, 2.5, 0.0)
	_rack(frame, 4.0, 2.5, 0.0)
	_crate_at(frame, -5.5, -2.5)
	_crate_at(frame, -5.5, -2.5, 0.9, 0.9)
	_crate_at(frame, 5.5, -2.5)
	_crate_at(frame, 5.5, -2.5, 0.9, 0.9)
	_crate_at(frame, -5.5, 0.5)
	_crate_at(frame, 5.5, 0.5)
	# Upper floor: slab with stairwell + stairs from ground.
	_slab_hole(frame, w, d, h, -1.25, 1.25, 0.0, 2.0)
	_stairs(frame, -3.75, 5.0, 2.0, 0.0, h)
	var up := frame * _t3(Vector3(0, h, 0))
	_high_windows(up * _t3(Vector3(0, 0, d * 0.5)), w, h, t, wall, col)
	_high_windows(up * _t3(Vector3(0, 0, -d * 0.5)), w, h, t, wall, col)
	_high_windows(up * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, h, t, wall, col)
	_high_windows(up * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, h, t, wall, col)
	# Upper floor: weapon racks + crate stacks.
	_rack(up, -4.0, 2.5, 0.0)
	_rack(up, 4.0, 2.5, 0.0)
	_crate_at(up, -5.5, -2.5)
	_crate_at(up, 5.5, -2.5)
	_crate_at(up, -5.5, -2.5, 0.9, 0.9)
	# Ceiling light panels (emissive) on both floors.
	_light_panel(frame, -3.5, 0.0, h - 0.28)
	_light_panel(frame, 3.5, 0.0, h - 0.28)
	_light_panel(frame, -3.5, 0.0, 2.0 * h - 0.28)
	_light_panel(frame, 3.5, 0.0, 2.0 * h - 0.28)
	# Roof slab with stairwell hole (roof access stairs from the upper floor).
	_slab_hole(frame, w, d, 2.0 * h, 4.5, 7.0, 0.0, 2.0)
	_stairs(frame, 2.0, 5.0, 2.0, 0.0, h, h)
	# Roof + parapet (raised for the new upper floor).
	_box(Vector3(w + 0.4, 0.25, d + 0.4), frame * _t3(Vector3(0, 2.0 * h - 0.125, 0)),
		_mats["roof"], Color(1, 1, 1), true)
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(w + 0.4, 0.7, 0.3),
			frame * _t3(Vector3(0, 2.0 * h + 0.35, ef * (d * 0.5 + 0.1))),
			wall, col, true)
		_box(Vector3(0.3, 0.7, d + 0.4),
			frame * _t3(Vector3(ef * (w * 0.5 + 0.1), 2.0 * h + 0.35, 0)),
			wall, col, true)
	# "ARMORY" sign over the front door.
	_sign_board(frame, 0.0, h - 0.35, -d * 0.5 - 0.25, 5.0)
	# Rooftop AC unit + rooftop loot (roof reachable via the upper stairs).
	_ac_unit(frame, -4.5, -3.0, 2.0 * h)
	_add_loot_y("ammo", 60, frame * Vector3(-4.5, 2.0 * h + 0.55, 3.0))
	_add_loot_y("armor", 50, frame * Vector3(4.5, 2.0 * h + 0.55, -3.0))
	# Dense loot: the hot zone (ground + upper floors).
	var spots := [
		[-4.0, 1.2, "ammo"], [-2.0, 1.2, "ammo"], [0.0, 1.2, "ammo"],
		[2.0, 1.2, "ammo"], [4.0, 1.2, "ammo"], [-4.0, 4.0, "armor"],
		[0.0, 4.0, "armor"], [4.0, 4.0, "health"], [-5.5, -1.0, "ammo"],
		[5.5, -1.0, "ammo"], [-2.5, -3.5, "health"], [2.5, -3.5, "armor"],
	]
	for s in spots:
		var sx: float = s[0]
		var sz: float = s[1]
		var sk: String = s[2]
		var amt := 60 if sk == "ammo" else (50 if sk == "armor" else 40)
		_add_loot_y(sk, amt, frame * Vector3(sx, 0.55, sz))
		_add_loot_y(sk, amt, up * Vector3(sx, 0.55, sz))
	house_positions.append(Vector3(x, 0, z))


# ---------------- officers' mess hall ----------------

func _build_mess_hall() -> void:
	var x := -30.0
	var z := 52.0
	var w := 22.0
	var d := 9.0
	var h := 3.4
	var t := 0.3
	var frame := Transform3D(Basis(), Vector3(x, 0, z))
	var wall: StandardMaterial3D = _mats["wall_tan"]
	var col := _varc(Color(0.85, 0.78, 0.62), 0.08)
	# Front (north, -z): door + big window band (real openings).
	_wall_open(frame * _t3(Vector3(0, 0, -d * 0.5)), w, h, t,
		[[-7.0, 1.0, 1.8, 1.4], [-3.5, 1.0, 1.8, 1.4], [0.0, 0.0, 1.6, 2.6],
			[3.5, 1.0, 1.8, 1.4], [7.0, 1.0, 1.8, 1.4]],
		wall, col)
	_trim_opening(frame * _t3(Vector3(0, 0, -d * 0.5)), 0.0, 0.0, 1.6, 2.6, t)
	_window_wall(frame * _t3(Vector3(0, 0, d * 0.5)), w, h, t, wall, col, false)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, h, t, wall, col, false)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, h, t, wall, col, false)
	# Long dining hall: 5 table sets + serving counter.
	for i in range(5):
		_table_set(frame, -8.0 + float(i) * 4.0, 0.5)
	_box(Vector3(8.0, 1.0, 0.8), frame * _t3(Vector3(0, 0.5, -3.2)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	_box(Vector3(8.4, 0.08, 1.0), frame * _t3(Vector3(0, 1.04, -3.2)),
		_mats["metal"], Color(1, 1, 1), false)
	# Serving dishes lined up on the counter.
	for dx in [-3.0, -1.5, 0.0, 1.5, 3.0]:
		_cyl(0.28, 0.18, frame * _t3(Vector3(float(dx), 1.17, -3.2)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	# "MESS HALL" sign over the front door.
	_sign_board(frame, 0.0, h - 0.35, -d * 0.5 - 0.25, 6.0)
	# Ceiling light panels (emissive) down the hall.
	for lx in [-7.5, -2.5, 2.5, 7.5]:
		_light_panel(frame, float(lx), 0.0, h - 0.28)
	# Roof + parapet.
	_box(Vector3(w + 0.4, 0.25, d + 0.4), frame * _t3(Vector3(0, h - 0.125, 0)),
		_mats["roof"], Color(1, 1, 1), true)
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(w + 0.4, 0.7, 0.3),
			frame * _t3(Vector3(0, h + 0.35, ef * (d * 0.5 + 0.1))),
			wall, col, true)
		_box(Vector3(0.3, 0.7, d + 0.4),
			frame * _t3(Vector3(ef * (w * 0.5 + 0.1), h + 0.35, 0)),
			wall, col, true)
	# Rooftop AC units (visual: roof not accessible, parapet all round).
	_ac_unit(frame, -6.0, 0.0, h)
	_ac_unit(frame, 6.0, 0.0, h)
	var spots := [
		[0.0, 2.5, "health"], [-6.0, -1.5, "ammo"], [6.0, -1.5, "ammo"],
		[-9.5, 2.5, "armor"], [9.5, 2.5, "health"], [0.0, -2.0, "armor"],
	]
	for s in spots:
		var sx: float = s[0]
		var sz: float = s[1]
		var sk: String = s[2]
		var amt := 60 if sk == "ammo" else (50 if sk == "armor" else 40)
		_add_loot_y(sk, amt, frame * Vector3(sx, 0.55, sz))
	house_positions.append(Vector3(x, 0, z))


# ---------------- obstacle course ----------------

func _build_obstacle_course() -> void:
	var frame := Transform3D(Basis(Vector3.UP, 0.3), Vector3(-50, 0, -50))
	# Low vault walls.
	for i in range(4):
		_box(Vector3(2.4, 1.0, 0.4),
			frame * _t3(Vector3(-6.0 + float(i) * 4.0, 0.5, 0)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.08), true)
	# Tire stacks.
	for ts in [[8.0, -6.0], [8.0, 0.0], [8.0, 6.0]]:
		var tx: float = ts[0]
		var tz: float = ts[1]
		for k in range(3):
			_cyl(0.38, 0.28, frame * _t3(Vector3(tx, 0.14 + float(k) * 0.28, tz)),
				_mats["tire"], _varc(Color(1, 1, 1), 0.1), false)
		_batch.add_collider(Vector3(0.85, 0.9, 0.85),
			frame * _t3(Vector3(tx, 0.45, tz)))
	# Rope climb frame: 4 legs, crossbar, hanging ropes.
	for px in [-2.5, 2.5]:
		for pz in [-1.2, 1.2]:
			_strut(frame * Vector3(float(px) * 1.4, 0, float(pz) * 1.6),
				frame * Vector3(float(px), 4.2, 0), 0.14, 0.14, _mats["wood_dark"])
	_strut(frame * Vector3(-2.5, 4.2, 0), frame * Vector3(2.5, 4.2, 0),
		0.12, 0.12, _mats["wood_dark"])
	for i in range(3):
		_cyl(0.035, 3.8, frame * _t3(Vector3(-1.5 + float(i) * 1.5, 2.3, 0)),
			_mats["canvas"], Color(1, 1, 1), false)
	# Balance beam.
	for bx in [-2.0, 2.0]:
		_box(Vector3(0.3, 0.6, 0.3), frame * _t3(Vector3(float(bx), 0.3, 8.0)),
			_mats["wood_dark"], Color(1, 1, 1), true)
	_box(Vector3(5.0, 0.15, 0.3), frame * _t3(Vector3(0, 0.675, 8.0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)


# ---------------- vehicles ----------------

func _truck(x: float, z: float, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var green := _varc(Color(0.32, 0.36, 0.22), 0.10)
	_box(Vector3(4.6, 0.5, 2.2), frame * _t3(Vector3(0, 1.05, 0)),
		_mats["truck_green"], green, false)
	_box(Vector3(1.7, 1.5, 2.1), frame * _t3(Vector3(2.9, 1.45, 0)),
		_mats["truck_green"], green, false)
	_box(Vector3(0.1, 0.7, 1.8), frame * _t3(Vector3(3.72, 1.75, 0)),
		_mats["truck_dark"], Color(1, 1, 1), false)
	_box(Vector3(3.2, 1.3, 2.0), frame * _t3(Vector3(-0.4, 2.0, 0)),
		_mats["canvas"], _varc(Color(1, 1, 1), 0.1), false)
	_batch.add_collider(Vector3(5.6, 2.6, 2.2), frame * _t3(Vector3(0.4, 1.3, 0)))
	for wx in [-1.6, 0.2, 1.9]:
		for wz in [-1.1, 1.1]:
			_cyl(0.5, 0.35,
				frame * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5),
					Vector3(float(wx), 0.5, float(wz))),
				_mats["tire"], Color(0.9, 0.9, 0.9), false)


func _jeep(x: float, z: float, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var green := _varc(Color(0.32, 0.36, 0.22), 0.10)
	_box(Vector3(2.8, 0.7, 1.7), frame * _t3(Vector3(0, 0.85, 0)),
		_mats["truck_green"], green, false)
	_box(Vector3(1.0, 0.5, 1.6), frame * _t3(Vector3(1.6, 1.1, 0)),
		_mats["truck_green"], green, false)
	_box(Vector3(0.08, 0.4, 1.4), frame * _t3(Vector3(2.08, 1.3, 0)),
		_mats["truck_dark"], Color(1, 1, 1), false)
	for sz in [-0.45, 0.45]:
		_box(Vector3(0.6, 0.4, 0.5), frame * _t3(Vector3(-0.3, 1.35, float(sz))),
			_mats["truck_dark"], Color(1, 1, 1), false)
	for sx in [-0.8, 0.2]:
		for sz in [-0.7, 0.7]:
			_strut(frame * Vector3(float(sx), 1.2, float(sz)),
				frame * Vector3(float(sx), 2.0, float(sz)), 0.07, 0.07, _mats["metal"])
	_strut(frame * Vector3(-0.8, 2.0, -0.7), frame * Vector3(-0.8, 2.0, 0.7),
		0.07, 0.07, _mats["metal"])
	_strut(frame * Vector3(0.2, 2.0, -0.7), frame * Vector3(0.2, 2.0, 0.7),
		0.07, 0.07, _mats["metal"])
	_batch.add_collider(Vector3(2.9, 1.6, 1.7), frame * _t3(Vector3(0, 0.8, 0)))
	for wx in [-0.95, 0.95]:
		for wz in [-0.85, 0.85]:
			_cyl(0.42, 0.3,
				frame * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5),
					Vector3(float(wx), 0.42, float(wz))),
				_mats["tire"], Color(0.9, 0.9, 0.9), false)


func _build_vehicles() -> void:
	_truck(14.0, -34.0, PI * 0.5)
	_truck(22.0, -34.0, PI * 0.5)
	_truck(30.0, -34.0, PI * 0.5)
	_jeep(14.0, -40.0, PI * 0.5)
	_jeep(22.0, -40.0, PI * 0.5)


# ---------------- lamps / sandbags / crates / clouds ----------------

func _lamp(x: float, z: float) -> void:
	_cyl(0.09, 5.0, _t3(Vector3(x, 2.5, z)), _mats["metal"], Color(1, 1, 1), true)
	_box(Vector3(0.5, 0.25, 0.5), _t3(Vector3(x, 5.1, z)),
		_mats["lamp_head"], Color(1, 1, 1), false)


func _build_lamps() -> void:
	for lp in [[20.0, 20.0], [-20.0, 20.0], [20.0, -20.0], [-20.0, -20.0],
			[6.0, 58.0], [-6.0, 58.0], [-30.0, 44.0], [30.0, 44.0]]:
		_lamp(float(lp[0]), float(lp[1]))


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


func _build_sandbags() -> void:
	for s in [[-6.0, 60.0, 0.3], [6.0, 60.0, -0.3],
			[24.0, 44.0, 0.0], [36.0, 44.0, 0.0],
			[-20.0, 20.0, 0.8], [20.0, -20.0, -0.8]]:
		_sandbag_wall(float(s[0]), float(s[1]), float(s[2]))


func _build_crates() -> void:
	# [x, z, y_base] — hand-placed in known-open spots.
	var spots := [
		[10.0, -34.0, 0.0], [12.0, -36.0, 0.0], [34.0, -34.0, 0.0],
		[-14.0, -14.0, 0.12], [14.0, 14.0, 0.12],
		[-4.0, 56.0, 0.0], [-4.0, 56.0, 0.9], [5.0, 50.0, 0.0],
		[-44.0, -44.0, 0.0], [38.0, 50.0, 0.0], [-14.0, 50.0, 0.0],
		[6.0, -24.0, 0.0], [-34.0, -32.0, 0.0], [34.0, -32.0, 0.0],
		[-34.0, 38.0, 0.0], [34.0, 38.0, 0.0],
	]
	for s in spots:
		_box(Vector3(0.9, 0.9, 0.9),
			_t3(Vector3(float(s[0]), float(s[2]) + 0.45, float(s[1]))),
			_mats["crate"], _varc(Color(1, 1, 1), 0.12), true)
	# Ground water tank near the mess hall.
	_cyl(1.5, 2.5, _t3(Vector3(-14.0, 1.25, 56.0)),
		_mats["water_tank"], Color(1, 1, 1), true)


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
	# General scatter, kept clear of buildings.
	for bc in [[-34.0, -18.0], [34.0, -18.0], [-34.0, 26.0], [34.0, 26.0],
			[30.0, 52.0], [-30.0, 52.0], [16.0, 62.0], [0.0, 0.0],
			[0.0, -22.0], [-50.0, -50.0], [22.0, -34.0]]:
		_claim(float(bc[0]), float(bc[1]), 10.0)
	var tries := 0
	while loot_spots.size() < 90 and tries < 600:
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
		Vector3(12, 0.6, 12),
		Vector3(-12, 0.6, -12),
		Vector3(-38, 0.6, -58),
		Vector3(30, 0.6, 42),
		Vector3(-30, 0.6, 42),
		Vector3(0, 0.6, 56),
	]
	print("Barracks built: instances=", _batch.box_count(), " draws=", draws,
		" colliders=", _batch.collider_count(), " loot=", loot_spots.size(),
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 110.0:
			cn.position.x = -110.0
