class_name AirportMap
extends Node3D
## Phase 9: Airport — Helicopter Wing (MMIA general-aviation style).
## Flat 140x140m airfield: enterable terminal (check-in counters, seats,
## flight board, kiosks, glass-front entrance), 18m control tower with
## enterable glass cab reached by switchback stairs + skybridge (loot hot
## zone), paved tarmac apron with painted markings, 3 parked helicopters
## with correct silhouettes (2 static main-rotor blades, tail boom, skids),
## 2 small planes, 2 enterable hangars (one with a blade-less maintenance
## heli), fuel truck, light towers, animated windsock, perimeter fence with
## gates, and a runway strip along the north edge. Seeded (SEED),
## merge-ready edges, GeoBatch static batching throughout.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261016

const POI_DEFS := [
	{"name": "Terminal", "pos": Vector3(-16, 0, -14)},
	{"name": "Control Tower", "pos": Vector3(4, 0, -6)},
	{"name": "Helipad Row", "pos": Vector3(42, 0.1, 17)},
	{"name": "Hangars", "pos": Vector3(22, 0, 62)},
]

var map_extent := MAP_EXTENT
var player_spawn := Vector3(0, 0.6, 60)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # terminal / tower / hangars (API compat)

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _clouds: Array = []
var _windsock: Node3D
var _beacon_mat: StandardMaterial3D
var _time := 0.0
var _placed: Array = []  # Vector2 points claimed by props (spacing)


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_runway()
	_build_taxiway()
	_build_apron()
	_build_terminal()
	_build_tower()
	_build_helicopters()
	_build_planes()
	_build_hangars()
	_build_fuel_truck()
	_build_light_towers()
	_build_windsock()
	_build_helipads()
	_build_fence()
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
	_mats["asphalt"] = _std(Color(0.23, 0.23, 0.24), 0.95)
	_mats["paint_white"] = _std(Color(0.92, 0.92, 0.90), 0.9)
	_mats["paint_yellow"] = _std(Color(0.95, 0.75, 0.15), 0.9)
	_mats["concrete"] = _std(Color(0.60, 0.59, 0.56))
	_mats["concrete_dark"] = _std(Color(0.44, 0.43, 0.41))
	_mats["wall"] = _std(Color(1, 1, 1), 0.9)        # per-instance tint
	_mats["trim"] = _std(Color(0.92, 0.90, 0.86), 0.85)
	_mats["roof"] = _std(Color(0.32, 0.32, 0.34), 0.9)
	_mats["metal"] = _std(Color(0.45, 0.47, 0.50), 0.5, 0.5)
	_mats["glass"] = _std(Color(0.10, 0.14, 0.18), 0.25, 0.6)  # dark tinted
	_mats["heli_body"] = _std(Color(1, 1, 1), 0.45, 0.35)      # per-instance livery
	_mats["heli_dark"] = _std(Color(0.16, 0.16, 0.17), 0.6, 0.3)
	_mats["crate"] = _std(Color(0.52, 0.40, 0.24), 0.9)
	_mats["wood"] = _std(Color(0.45, 0.33, 0.20), 0.9)
	_mats["wood_dark"] = _std(Color(0.30, 0.22, 0.13), 0.9)
	_mats["drum"] = _std(Color(1, 1, 1), 0.6, 0.4)   # per-instance colors
	_mats["tire"] = _std(Color(0.12, 0.12, 0.13), 0.95)
	_mats["seat"] = _std(Color(0.20, 0.35, 0.62), 0.85)
	_mats["screen"] = _std(Color(0.08, 0.16, 0.30), 0.4)
	var scr: StandardMaterial3D = _mats["screen"]
	scr.emission_enabled = true
	scr.emission = Color(0.25, 0.55, 1.0)
	scr.emission_energy_multiplier = 1.6
	_mats["sign"] = _std(Color(0.06, 0.14, 0.34), 0.5)
	var sign: StandardMaterial3D = _mats["sign"]
	sign.emission_enabled = true
	sign.emission = Color(0.15, 0.35, 0.85)
	sign.emission_energy_multiplier = 0.9
	var lamp := _std(Color(1.0, 0.9, 0.65), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.55)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp_head"] = lamp
	_mats["sock"] = _std(Color(1, 1, 1), 0.85)       # per-instance orange/white
	_beacon_mat = _std(Color(1.0, 0.15, 0.12), 0.5)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.1, 0.1)
	_beacon_mat.emission_energy_multiplier = 3.0


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


func _cyl_axis(radius: float, length: float, axis: Vector3, center: Vector3,
		frame: Transform3D, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	# Cylinder with its length axis along local X (Vector3.RIGHT) or local Z
	# (Vector3.BACK), centered at frame-local `center`. The rotation basis is
	# applied to the mesh only — the center is NOT rotated.
	var b := Basis(Vector3(0, 0, 1), PI * 0.5) if axis == Vector3.RIGHT \
		else Basis(Vector3(1, 0, 0), PI * 0.5)
	_cyl(radius, length, frame * Transform3D(b, center), mat, col, collide)


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
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc + w * 0.5 - 0.02, y0 + h * 0.5, 0)), tm, c, false)


func _window_band(frame: Transform3D, W: float, H: float, T: float, mat: StandardMaterial3D,
		col: Color, door_holes: Array) -> void:
	# Evenly spaced shoot-through windows plus extra door holes.
	var holes := []
	var n := maxi(2, int(W / 4.0))
	for i in range(n):
		var xc := -W * 0.5 + W * (float(i) + 0.5) / float(n)
		var blocked := false
		for dh in door_holes:
			if absf(xc - float(dh[0])) < (float(dh[2]) * 0.5 + 1.2):
				blocked = true
				break
		if not blocked:
			holes.append([xc, 1.1, 1.6, 1.5])
	for dh in door_holes:
		holes.append(dh)
	_wall_open(frame, W, H, T, holes, mat, col, true)
	for h in holes:
		_trim_opening(frame, float(h[0]), float(h[1]), float(h[2]), float(h[3]), T)


func _stair_flight(frame: Transform3D, x0: float, run: float, width: float,
		rise: float, y_base := 0.0) -> void:
	# Visual steps + one ramp collider the player walks up smoothly.
	# frame maps local +x to the flight direction, local z to sideways.
	var steps := 12
	for i in range(steps):
		var sx := x0 + run * (float(i) + 0.5) / float(steps)
		var sy := y_base + rise * (float(i) + 0.5) / float(steps)
		_box(Vector3(run / float(steps) + 0.05, 0.09, width),
			frame * _t3(Vector3(sx, sy - 0.045, 0)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var local := Transform3D(Basis(Vector3(0, 0, 1), ang),
		Vector3(x0 + run * 0.5, y_base + rise * 0.5 - 0.06, 0))
	_batch.add_collider(Vector3(length, 0.12, width), frame * local)


func _landing(cx: float, cy: float, cz: float, w := 2.4, d := 2.2) -> void:
	# Flat landing slab with railings on both outer sides.
	_box(Vector3(w, 0.15, d), _t3(Vector3(cx, cy - 0.075, cz)),
		_mats["concrete"], Color(1, 1, 1), true)
	for sx in [-1.0, 1.0]:
		var rx := cx + float(sx) * (w * 0.5 - 0.03)
		_box(Vector3(0.07, 1.0, d), _t3(Vector3(rx, cy + 0.5, cz)),
			_mats["metal"], Color(0.7, 0.7, 0.72), true)


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


func _light_panel(frame: Transform3D, lx: float, lz: float, fy: float) -> void:
	# Emissive ceiling light: housing + glowing diffuser (batched, no real light).
	_box(Vector3(2.0, 0.08, 1.1), frame * _t3(Vector3(lx, fy, lz)),
		_mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(1.8, 0.05, 0.9), frame * _t3(Vector3(lx, fy - 0.055, lz)),
		_mats["lamp_head"], Color(1, 1, 1), false)


func _luggage_cart(frame: Transform3D, lx: float, lz: float, yaw: float) -> void:
	# Airport luggage trolley: frame + basket + 2 suitcases.
	var cf := frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, 0, lz))
	_box(Vector3(0.9, 0.08, 0.6), cf * _t3(Vector3(0, 0.45, 0)),
		_mats["metal"], Color(1, 1, 1), true)
	for sx in [-0.4, 0.4]:
		for sz in [-0.25, 0.25]:
			_box(Vector3(0.06, 0.9, 0.06), cf * _t3(Vector3(float(sx), 0.45, float(sz))),
				_mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(0.7, 0.4, 0.45), cf * _t3(Vector3(0, 0.7, 0)),
		_mats["heli_body"], Color(0.65, 0.15, 0.12), false)
	_box(Vector3(0.6, 0.35, 0.4), cf * _t3(Vector3(0.05, 1.05, 0)),
		_mats["heli_body"], Color(0.12, 0.25, 0.60), false)


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


# ---------------- ground / runway / taxiway / apron ----------------

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
	_batch.add_collider(Vector3(140.0, 0.4, 140.0), _t3(Vector3(0, -0.21, 0)))


func _build_runway() -> void:
	var rz := -58.0
	# Long asphalt band along the north edge.
	_box(Vector3(124, 0.08, 10), _t3(Vector3(0, 0.04, rz)),
		_mats["asphalt"], Color(1, 1, 1), true)
	var pw: StandardMaterial3D = _mats["paint_white"]
	# Edge lines.
	for e in [-4.5, 4.5]:
		_box(Vector3(124, 0.02, 0.25), _t3(Vector3(0, 0.10, rz + float(e))), pw, Color(1, 1, 1), false)
	# Centerline dashes.
	var x := -56.0
	while x <= 56.0:
		_box(Vector3(3.5, 0.02, 0.35), _t3(Vector3(x, 0.10, rz)), pw, Color(1, 1, 1), false)
		x += 8.0
	# Threshold piano keys at both ends.
	for ex in [-56.0, 56.0]:
		for k in range(6):
			_box(Vector3(4.0, 0.02, 0.6),
				_t3(Vector3(float(ex), 0.10, rz - 3.5 + float(k) * 1.4)),
				pw, Color(1, 1, 1), false)
	# Runway designator blocks near thresholds.
	for ex in [-50.0, 50.0]:
		_box(Vector3(2.2, 0.02, 2.6), _t3(Vector3(float(ex), 0.10, rz)), pw, Color(1, 1, 1), false)


func _build_taxiway() -> void:
	# Connects the runway to the apron.
	_box(Vector3(8, 0.08, 24), _t3(Vector3(-2, 0.04, -41)),
		_mats["asphalt"], Color(1, 1, 1), true)
	var py: StandardMaterial3D = _mats["paint_yellow"]
	var z := -50.0
	while z <= -32.0:
		_box(Vector3(0.3, 0.02, 2.5), _t3(Vector3(-2, 0.10, z)), py, Color(1, 1, 1), false)
		z += 5.0


func _build_apron() -> void:
	# Big paved tarmac apron east of the terminal.
	_box(Vector3(66, 0.08, 48), _t3(Vector3(25, 0.04, 2)),
		_mats["asphalt"], Color(1, 1, 1), true)
	var py: StandardMaterial3D = _mats["paint_yellow"]
	var pw: StandardMaterial3D = _mats["paint_white"]
	# Taxi line feeding the apron.
	_box(Vector3(0.35, 0.02, 18), _t3(Vector3(-2, 0.10, -13)), py, Color(1, 1, 1), false)
	_box(Vector3(24, 0.02, 0.35), _t3(Vector3(10, 0.10, -6)), py, Color(1, 1, 1), false)
	_box(Vector3(0.35, 0.02, 16), _t3(Vector3(22, 0.10, 2)), py, Color(1, 1, 1), false)
	# Aircraft parking boxes (white outlines) around the helicopter spots.
	for spot in [Vector2(18, -8), Vector2(34, -14), Vector2(30, 6)]:
		var hw := 8.0
		var hd := 6.0
		_box(Vector3(hw * 2, 0.02, 0.3), _t3(Vector3(spot.x, 0.10, spot.y - hd)), pw, Color(1, 1, 1), false)
		_box(Vector3(hw * 2, 0.02, 0.3), _t3(Vector3(spot.x, 0.10, spot.y + hd)), pw, Color(1, 1, 1), false)
		_box(Vector3(0.3, 0.02, hd * 2), _t3(Vector3(spot.x - hw, 0.10, spot.y)), pw, Color(1, 1, 1), false)
		_box(Vector3(0.3, 0.02, hd * 2), _t3(Vector3(spot.x + hw, 0.10, spot.y)), pw, Color(1, 1, 1), false)
	# Tie-down points: small dark discs.
	for td in [Vector2(10, -18), Vector2(26, -20), Vector2(44, -4), Vector2(14, 16),
			Vector2(48, 4), Vector2(6, 8), Vector2(28, 20), Vector2(52, 12)]:
		_cyl(0.25, 0.03, _t3(Vector3(float(td.x), 0.10, float(td.y))),
			_mats["metal"], Color(0.25, 0.25, 0.26), false)


# ---------------- terminal ----------------

func _build_terminal() -> void:
	var cx := -36.0
	var cz := -14.0
	var W := 26.0
	var D := 14.0
	var H := 5.0
	var T := 0.4
	var wall_col := Color(0.88, 0.86, 0.80)
	# Interior floor slab (thin, visual only — global ground carries collision).
	_box(Vector3(W - 0.8, 0.06, D - 0.8), _t3(Vector3(cx, 0.03, cz)),
		_mats["concrete"], Color(0.72, 0.70, 0.66), false)
	# East wall: glass-front entrance facing the tarmac (local +x -> world +z).
	var east := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx + W * 0.5, 0, cz))
	var doors := [[-4.0, 0.0, 1.8, 2.6], [0.0, 0.0, 1.8, 2.6], [4.0, 0.0, 1.8, 2.6]]
	_window_band(east, D, H, T, _mats["wall"], wall_col, doors)
	# West wall: windows + service door.
	var west := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx - W * 0.5, 0, cz))
	_window_band(west, D, H, T, _mats["wall"], wall_col, [[0.0, 0.0, 1.4, 2.4]])
	# North + south walls: window bands with exit doors.
	var north := Transform3D(Basis(), Vector3(cx, 0, cz - D * 0.5))
	_window_band(north, W, H, T, _mats["wall"], wall_col, [[6.0, 0.0, 1.6, 2.4]])
	var south := Transform3D(Basis(), Vector3(cx, 0, cz + D * 0.5))
	_window_band(south, W, H, T, _mats["wall"], wall_col,
		[[-6.0, 0.0, 1.8, 2.6], [6.0, 0.0, 1.8, 2.6]])
	# Interior columns.
	for px in [-42.0, -30.0]:
		for pz in [-18.0, -10.0]:
			_box(Vector3(0.5, H, 0.5), _t3(Vector3(float(px), H * 0.5, float(pz))),
				_mats["concrete_dark"], Color(1, 1, 1), true)
	# Check-in counter row with divider screens.
	var cfx := Transform3D(Basis(), Vector3(-40.0, 0, -18.5))
	_box(Vector3(8.0, 1.05, 0.7), cfx * _t3(Vector3(0, 0.525, 0)),
		_mats["wood"], Color(1, 1, 1), true)
	_box(Vector3(8.4, 0.08, 0.9), cfx * _t3(Vector3(0, 1.09, 0)),
		_mats["concrete_dark"], Color(1, 1, 1), false)
	for k in range(4):
		var dx := -3.0 + float(k) * 2.0
		_box(Vector3(0.06, 0.8, 0.7), cfx * _t3(Vector3(dx, 1.5, 0)),
			_mats["glass"], Color(1, 1, 1), false)
	# Rows of waiting seats.
	for row in [0, 1]:
		var rz2 := -12.0 + float(row) * 2.6
		for s in range(3):
			var sx := -41.0 + float(s) * 3.6
			_box(Vector3(3.2, 0.15, 0.55), _t3(Vector3(sx, 0.5, rz2)),
				_mats["seat"], _varc(Color(1, 1, 1), 0.08), true)
			_box(Vector3(3.2, 0.65, 0.12), _t3(Vector3(sx, 0.9, rz2 + 0.28)),
				_mats["seat"], _varc(Color(1, 1, 1), 0.08), false)
	# Flight-info board on the west wall interior.
	_box(Vector3(0.15, 2.2, 4.0), _t3(Vector3(cx - W * 0.5 + 0.35, 2.6, cz)),
		_mats["screen"], Color(1, 1, 1), false)
	for k in range(4):
		_box(Vector3(0.06, 0.16, 3.4), _t3(Vector3(cx - W * 0.5 + 0.45, 1.9 + float(k) * 0.45, cz)),
			_mats["paint_white"], Color(0.7, 0.85, 1.0), false)
	# Kiosks.
	for k in range(3):
		var kx := -31.0 + float(k) * 2.2
		_box(Vector3(0.7, 1.4, 0.5), _t3(Vector3(kx, 0.7, -9.5)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(0.5, 0.4, 0.06), _t3(Vector3(kx, 1.15, -9.72)),
			_mats["screen"], Color(1, 1, 1), false)
	# Ceiling light panels (emissive) on the ground floor.
	for lxp in [-40.0, -32.0]:
		for lzp in [-12.0, -16.0]:
			_light_panel(Transform3D.IDENTITY, float(lxp), float(lzp), 4.6)
	# --- Upper floor: slab with stairwell + stairs from the ground floor.
	var tf := Transform3D(Basis(), Vector3(cx, 0, cz))
	_stair_flight(Transform3D(Basis(), Vector3(-48, 0, -8)), 0, 7.0, 2.0, 5.0, 0.0)
	_slab_hole(tf, W, D, H, -8.5, -1.5, 6.0, 2.2)
	var ueast := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx + W * 0.5, H, cz))
	_window_band(ueast, D, H, T, _mats["wall"], wall_col, [])
	var uwest := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx - W * 0.5, H, cz))
	_window_band(uwest, D, H, T, _mats["wall"], wall_col, [])
	var unorth := Transform3D(Basis(), Vector3(cx, H, cz - D * 0.5))
	_window_band(unorth, W, H, T, _mats["wall"], wall_col, [])
	var usouth := Transform3D(Basis(), Vector3(cx, H, cz + D * 0.5))
	_window_band(usouth, W, H, T, _mats["wall"], wall_col, [])
	# Upper floor: waiting seats, kiosks, light panels, loot.
	for row in [0, 1]:
		var urz := -12.0 + float(row) * 2.6
		for s in range(3):
			var usx := -37.0 + float(s) * 3.6
			_box(Vector3(3.2, 0.15, 0.55), _t3(Vector3(usx, H + 0.5, urz)),
				_mats["seat"], _varc(Color(1, 1, 1), 0.08), true)
			_box(Vector3(3.2, 0.65, 0.12), _t3(Vector3(usx, H + 0.9, urz + 0.28)),
				_mats["seat"], _varc(Color(1, 1, 1), 0.08), false)
	for k2 in range(2):
		var ukx := -28.0 + float(k2) * 2.2
		_box(Vector3(0.7, 1.4, 0.5), _t3(Vector3(ukx, H + 0.7, -9.5)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(0.5, 0.4, 0.06), _t3(Vector3(ukx, H + 1.15, -9.72)),
			_mats["screen"], Color(1, 1, 1), false)
	for lxp2 in [-40.0, -32.0]:
		for lzp2 in [-12.0, -16.0]:
			_light_panel(Transform3D.IDENTITY, float(lxp2), float(lzp2), 2.0 * H - 0.4)
	for ulp in [Vector3(-35, H + 0.55, -12), Vector3(-33, H + 0.55, -16),
			Vector3(-39, H + 0.55, -15), Vector3(-31, H + 0.55, -11)]:
		var ukinds := ["health", "armor", "ammo"]
		loot_spots.append([ukinds[loot_spots.size() % 3], 50, ulp])
	# --- Roof: walkable slab with stairwell hole + stairs from the upper floor.
	_slab_hole(tf, W, D, 2.0 * H, 8.5, 13.0, -4.0, 2.2)
	_stair_flight(Transform3D(Basis(), Vector3(-30, 0, -18)), 0, 7.0, 2.0, 5.0, H)
	# Parapet + AC units on the new roof line.
	for e2 in [-1.0, 1.0]:
		var ef2: float = e2
		_box(Vector3(W + 1.0, 0.8, 0.25),
			_t3(Vector3(cx, 2.0 * H + 0.7, cz + ef2 * (D * 0.5 + 0.4))),
			_mats["wall"], wall_col, false)
		_box(Vector3(0.25, 0.8, D + 1.0),
			_t3(Vector3(cx + ef2 * (W * 0.5 + 0.4), 2.0 * H + 0.7, cz)),
			_mats["wall"], wall_col, false)
	for ax2 in [-8.0, 0.0, 8.0]:
		_box(Vector3(1.6, 0.9, 1.2), _t3(Vector3(cx + float(ax2), 2.0 * H + 0.75, cz - 2.0)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	# Rooftop loot (roof reachable via the upper stairs).
	loot_spots.append(["ammo", 60, Vector3(cx - 5, 2.0 * H + 0.55, cz + 3)])
	loot_spots.append(["health", 40, Vector3(cx + 5, 2.0 * H + 0.55, cz - 3)])
	# "DEPARTURES" sign over the east entrance + luggage carts inside.
	_box(Vector3(0.15, 1.0, 8.0), _t3(Vector3(cx + W * 0.5 + 0.28, H + 3.6, cz)),
		_mats["sign"], Color(1, 1, 1), false)
	_luggage_cart(Transform3D.IDENTITY, -38.0, -16.0, 0.4)
	_luggage_cart(Transform3D.IDENTITY, -34.0, -11.0, -0.3)
	house_positions.append(Vector3(cx, 0, cz))
	_claim(cx, cz, 20.0)
	# Interior loot.
	for lp in [Vector3(-33, 0.55, -18), Vector3(-39, 0.55, -12), Vector3(-31, 0.55, -11.5),
			Vector3(-44, 0.55, -16), Vector3(-36, 0.55, -9.8), Vector3(-42.5, 0.55, -10.5)]:
		var kinds := ["health", "armor", "ammo"]
		loot_spots.append([kinds[loot_spots.size() % 3], 50, lp])


# ---------------- control tower ----------------

func _build_tower() -> void:
	var tx := -2.0
	var tz := -20.0
	var cab_y := 18.0
	var wall_col := Color(0.80, 0.78, 0.72)
	# Solid concrete shaft, 4x4, 18m tall.
	_box(Vector3(4, cab_y, 4), _t3(Vector3(tx, cab_y * 0.5, tz)),
		_mats["concrete"], Color(1, 1, 1), true)
	# Vertical trim stripes, proud of the shaft faces.
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(0.12, cab_y - 1.0, 4.06), _t3(Vector3(tx + ef * 2.0, cab_y * 0.5, tz)),
			_mats["trim"], Color(1, 1, 1), false)
	# Exterior access panel (visual).
	_box(Vector3(0.1, 2.2, 1.2), _t3(Vector3(tx + 2.05, 1.1, tz + 1.0)),
		_mats["metal"], Color(0.5, 0.5, 0.52), false)
	# --- Switchback stairs: 4 flights x 4.5m rise, landings, then a skybridge.
	var north := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(tx, 0, 0))
	var south := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(tx, 0, 0))
	_stair_flight(north, 10.0, 8.0, 2.4, 4.5, 0.0)    # A: z -10 -> -18, y 0 -> 4.5
	_stair_flight(south, -18.0, 8.0, 2.4, 4.5, 4.5)   # B: z -18 -> -10, y 4.5 -> 9
	_stair_flight(north, 10.0, 8.0, 2.4, 4.5, 9.0)    # C: z -10 -> -18, y 9 -> 13.5
	_stair_flight(south, -18.0, 8.0, 2.4, 4.5, 13.5)  # D: z -18 -> -10, y 13.5 -> 18
	_landing(tx, 4.5, -17.0)
	_landing(tx, 9.0, -9.0)
	_landing(tx, 13.5, -17.0)
	_landing(tx, 18.0, -9.0)
	# Stair base pad.
	_box(Vector3(3.2, 0.08, 3.2), _t3(Vector3(tx, 0.04, -8.6)),
		_mats["concrete"], Color(1, 1, 1), false)
	# Handrail struts along each flight.
	var rail := [[-3.1, 1.0, -10.0, -3.1, 5.5, -18.0], [-0.9, 1.0, -10.0, -0.9, 5.5, -18.0],
		[-3.1, 5.5, -18.0, -3.1, 10.0, -10.0], [-0.9, 5.5, -18.0, -0.9, 10.0, -10.0],
		[-3.1, 10.0, -10.0, -3.1, 14.5, -18.0], [-0.9, 10.0, -10.0, -0.9, 14.5, -18.0],
		[-3.1, 14.5, -18.0, -3.1, 19.0, -10.0], [-0.9, 14.5, -18.0, -0.9, 19.0, -10.0]]
	for r in rail:
		_strut(Vector3(float(r[0]), float(r[1]), float(r[2])),
			Vector3(float(r[3]), float(r[4]), float(r[5])), 0.07, 0.07, _mats["metal"])
	# Skybridge from the top landing to the cab door.
	_box(Vector3(2.4, 0.15, 10.0), _t3(Vector3(tx, cab_y - 0.075, -13.0)),
		_mats["concrete"], Color(1, 1, 1), true)
	for sx in [-1.0, 1.0]:
		var rx := tx + float(sx) * 1.17
		_box(Vector3(0.07, 1.0, 10.0), _t3(Vector3(rx, cab_y + 0.5, -13.0)),
			_mats["metal"], Color(0.7, 0.7, 0.72), true)
	# --- Glass cab: floor, 4 window walls, consoles, roof, beacon.
	_box(Vector3(6, 0.3, 6), _t3(Vector3(tx, cab_y - 0.15, tz)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	var cab_walls := [
		[Transform3D(Basis(), Vector3(tx, cab_y, tz - 3.0)), [[-2.0, 0.8, 1.2, 1.4], [2.0, 0.8, 1.2, 1.4]]],
		[Transform3D(Basis(), Vector3(tx, cab_y, tz + 3.0)), [[0.0, 0.0, 1.4, 2.2], [-2.0, 0.8, 1.2, 1.4], [2.0, 0.8, 1.2, 1.4]]],
		[Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(tx - 3.0, cab_y, tz)), [[-1.5, 0.8, 1.2, 1.4], [1.5, 0.8, 1.2, 1.4]]],
		[Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(tx + 3.0, cab_y, tz)), [[-1.5, 0.8, 1.2, 1.4], [1.5, 0.8, 1.2, 1.4]]],
	]
	for cw in cab_walls:
		var fr: Transform3D = cw[0]
		var holes: Array = cw[1]
		_wall_open(fr, 6.0, 3.0, 0.25, holes, _mats["wall"], wall_col, true)
		for h in holes:
			_trim_opening(fr, float(h[0]), float(h[1]), float(h[2]), float(h[3]), 0.25)
	# Corner pillars.
	for px in [-2.9, 2.9]:
		for pz in [-2.9, 2.9]:
			_box(Vector3(0.35, 3.0, 0.35),
				_t3(Vector3(tx + float(px), cab_y + 1.5, tz + float(pz))),
				_mats["concrete_dark"], Color(1, 1, 1), true)
	# Consoles with glowing screens.
	for ca in [0.6, 2.5, 4.4]:
		var kx := tx + cos(float(ca)) * 1.7
		var kz := tz + sin(float(ca)) * 1.7
		var kyaw := -float(ca) + PI * 0.5
		var kf := Transform3D(Basis(Vector3.UP, kyaw), Vector3(kx, cab_y, kz))
		_box(Vector3(1.6, 0.75, 0.6), kf * _t3(Vector3(0, 0.375, 0)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(1.5, 0.7, 0.08),
			kf * Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(0, 1.0, 0.1)),
			_mats["screen"], Color(1, 1, 1), false)
	# Roof + beacon.
	_box(Vector3(6.6, 0.3, 6.6), _t3(Vector3(tx, cab_y + 3.15, tz)),
		_mats["roof"], Color(1, 1, 1), false)
	# Cab ceiling light (emissive).
	_light_panel(Transform3D.IDENTITY, tx, tz, cab_y + 2.6)
	_cyl(0.08, 1.2, _t3(Vector3(tx, cab_y + 3.9, tz)), _mats["metal"], Color(1, 1, 1), false)
	var rock_mesh_pos := Vector3(tx, cab_y + 4.6, tz)
	_batch.add_rock(Vector3(0.35, 0.35, 0.35), Transform3D(Basis(), rock_mesh_pos),
		_beacon_mat, Color(1, 1, 1), false)
	house_positions.append(Vector3(tx, 0, tz))
	_claim(tx, tz, 14.0)
	# Hot-zone loot inside the cab.
	for lp in [Vector3(tx - 1.6, cab_y + 0.55, tz - 1.2), Vector3(tx + 1.6, cab_y + 0.55, tz + 0.8),
			Vector3(tx, cab_y + 0.55, tz - 2.2), Vector3(tx - 2.2, cab_y + 0.55, tz + 1.8)]:
		loot_spots.append(["armor", 50, lp])
		loot_spots.append(["ammo", 60, Vector3(lp.x + 0.6, lp.y, lp.z + 0.4)])


# ---------------- helicopters ----------------

func _helicopter(frame: Transform3D, body_col: Color, accent_col: Color, blades := true) -> void:
	# Signature silhouette: rounded fuselage, dark cockpit glass, tapered tail
	# boom, tail rotor, 2 STATIC main-rotor blades, skid landing gear.
	var body: StandardMaterial3D = _mats["heli_body"]
	var dark: StandardMaterial3D = _mats["heli_dark"]
	var glass: StandardMaterial3D = _mats["glass"]
	var metal: StandardMaterial3D = _mats["metal"]
	# Skid tubes + struts.
	for sz in [-0.85, 0.85]:
		_cyl_axis(0.07, 3.4, Vector3.RIGHT, Vector3(0, 0.18, float(sz)), frame, dark, Color(1, 1, 1), true)
		for sx in [-0.9, 0.9]:
			_strut(frame * Vector3(float(sx), 0.2, float(sz)),
				frame * Vector3(float(sx), 0.8, float(sz) * 0.65), 0.09, 0.09, metal)
	# Fuselage (belly 0.5 -> roof 2.2) with collider — serves as cover.
	_box(Vector3(4.0, 1.7, 1.7), frame * _t3(Vector3(0, 1.35, 0)), body, body_col, true)
	# Rounded nose.
	_batch.add_rock(Vector3(1.5, 1.5, 1.5),
		frame * Transform3D(Basis(), Vector3(2.1, 1.3, 0)), body, body_col.darkened(0.12), false)
	# Cockpit glass: dark tinted front panels, proud of the nose.
	for gz in [-0.45, 0.45]:
		var gf := frame * Transform3D(Basis(Vector3.UP, -float(gz) * 0.9), Vector3(2.35, 1.75, float(gz)))
		_box(Vector3(0.85, 0.7, 0.07),
			gf * Transform3D(Basis(Vector3(1, 0, 0), -0.28), Vector3(0, 0, 0)),
			glass, Color(1, 1, 1), false)
	# Livery stripes, proud of the fuselage faces.
	for sz2 in [-0.88, 0.88]:
		_box(Vector3(3.9, 0.3, 0.05), frame * _t3(Vector3(0, 1.55, float(sz2))),
			body, accent_col, false)
	# Tapered tail boom: 3 shrinking segments, high enough to walk under.
	var boom_r := [0.26, 0.19, 0.13]
	for bi in range(3):
		_cyl_axis(float(boom_r[bi]), 1.8, Vector3.RIGHT,
			Vector3(-2.0 - float(bi) * 1.8, 2.15 + float(bi) * 0.03, 0),
			frame, body, body_col.darkened(0.05), false)
	# Vertical fin + tail rotor (static).
	_box(Vector3(0.9, 1.3, 0.12), frame * _t3(Vector3(-7.0, 2.6, 0)), body, accent_col, false)
	_cyl(0.09, 0.3, frame * Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(-7.0, 2.5, 0.22)),
		dark, Color(1, 1, 1), false)
	_box(Vector3(0.08, 1.2, 0.06), frame * _t3(Vector3(-7.0, 2.5, 0.32)), dark, Color(1, 1, 1), false)
	_box(Vector3(1.2, 0.08, 0.06), frame * _t3(Vector3(-7.0, 2.5, 0.32)), dark, Color(1, 1, 1), false)
	if blades:
		# Mast + hub + 2 long STATIC blades (one continuous bar reads as 2 blades).
		_cyl(0.12, 0.9, frame * _t3(Vector3(0.2, 2.6, 0)), dark, Color(1, 1, 1), false)
		_box(Vector3(0.5, 0.25, 0.5), frame * _t3(Vector3(0.2, 3.1, 0)), dark, Color(1, 1, 1), false)
		_box(Vector3(11.0, 0.07, 0.4), frame * _t3(Vector3(0.2, 3.22, 0)),
			dark, Color(0.9, 0.9, 0.9), false)
	else:
		# Maintenance: mast capped, cowling panels open, blades removed.
		_cyl(0.14, 0.25, frame * _t3(Vector3(0.2, 2.35, 0)), dark, Color(1, 1, 1), false)
		for pz in [-0.7, 0.7]:
			_box(Vector3(1.2, 0.06, 0.9),
				frame * Transform3D(Basis(Vector3(0, 0, 1), float(pz) * 0.5), Vector3(0.2, 2.35, float(pz))),
				body, body_col.darkened(0.2), false)


func _build_helicopters() -> void:
	var spots := [
		[18.0, -8.0, 0.3, Color(0.92, 0.92, 0.94), Color(0.80, 0.12, 0.12)],   # white/red
		[34.0, -14.0, -0.4, Color(0.32, 0.38, 0.22), Color(0.15, 0.16, 0.12)],  # military green
		[30.0, 6.0, 1.2, Color(0.95, 0.78, 0.12), Color(0.12, 0.12, 0.12)],     # yellow
	]
	for s in spots:
		var fr := Transform3D(Basis(Vector3.UP, float(s[2])), Vector3(float(s[0]), 0.08, float(s[1])))
		_helicopter(fr, s[3], s[4], true)
		_claim(float(s[0]), float(s[1]), 9.0)


# ---------------- small planes ----------------

func _plane(frame: Transform3D, body_col: Color) -> void:
	var body: StandardMaterial3D = _mats["heli_body"]
	var dark: StandardMaterial3D = _mats["heli_dark"]
	var glass: StandardMaterial3D = _mats["glass"]
	# Fuselage cylinder along +x with collider.
	_cyl_axis(0.65, 6.5, Vector3.RIGHT, Vector3(0, 1.3, 0), frame, body, body_col, true)
	_cyl_axis(0.7, 0.8, Vector3.RIGHT, Vector3(3.45, 1.3, 0), frame, dark, Color(1, 1, 1), false)
	# Propeller: spinner + 2 static blades in the y-z plane.
	_cyl_axis(0.15, 0.4, Vector3.RIGHT, Vector3(4.0, 1.3, 0), frame, dark, Color(1, 1, 1), false)
	_box(Vector3(0.1, 2.4, 0.3), frame * _t3(Vector3(4.35, 1.3, 0)), dark, Color(0.85, 0.85, 0.85), false)
	_box(Vector3(0.1, 0.3, 2.4), frame * _t3(Vector3(4.35, 1.3, 0)), dark, Color(0.85, 0.85, 0.85), false)
	# High wing — mounted above head height, walk underneath.
	_box(Vector3(2.0, 0.14, 9.5), frame * _t3(Vector3(-0.3, 2.25, 0)), body, body_col.darkened(0.08), false)
	# Cockpit windows.
	_box(Vector3(1.4, 0.5, 1.0), frame * _t3(Vector3(0.9, 1.85, 0)), glass, Color(1, 1, 1), false)
	# Tail: stabilizer + fin.
	_box(Vector3(1.2, 0.1, 3.2), frame * _t3(Vector3(-2.9, 1.7, 0)), body, body_col.darkened(0.08), false)
	_box(Vector3(1.0, 1.4, 0.12), frame * _t3(Vector3(-2.9, 2.2, 0)), body, body_col, false)
	# Landing gear: legs + wheels.
	for gz in [-0.9, 0.9]:
		_cyl(0.08, 0.8, frame * _t3(Vector3(0.8, 0.55, float(gz))), dark, Color(1, 1, 1), false)
		_box(Vector3(0.55, 0.55, 0.3), frame * _t3(Vector3(0.8, 0.28, float(gz))),
			_mats["tire"], Color(1, 1, 1), true)
	_cyl(0.06, 0.4, frame * _t3(Vector3(-2.9, 0.35, 0)), dark, Color(1, 1, 1), false)


func _build_planes() -> void:
	var p1 := Transform3D(Basis(Vector3.UP, 0.5), Vector3(-12, 0, 40))
	_plane(p1, Color(0.85, 0.85, 0.88))
	_claim(-12, 40, 8.0)
	var p2 := Transform3D(Basis(Vector3.UP, -0.8), Vector3(52, 0, 38))
	_plane(p2, Color(0.75, 0.20, 0.15))
	_claim(52, 38, 8.0)


# ---------------- hangars ----------------

func _hangar(cx: float, cz: float, maintenance_heli: bool) -> void:
	var W := 24.0
	var D := 18.0
	var H := 6.0
	var T := 0.4
	var wall_col := Color(0.72, 0.74, 0.70)
	# Front (south) wall with a huge open doorway; doors slid open to the sides.
	var front := Transform3D(Basis(), Vector3(cx, 0, cz + D * 0.5))
	_wall_open(front, W, H, T, [[0.0, 0.0, 16.0, 5.2]], _mats["wall"], wall_col, true)
	_box(Vector3(W, 0.8, T), front * _t3(Vector3(0, 5.6, 0)), _mats["wall"], wall_col, false)
	for dx in [-11.8, 11.8]:
		_box(Vector3(7.6, 5.2, 0.15), front * _t3(Vector3(float(dx), 2.6, 0.6)),
			_mats["metal"], Color(0.55, 0.57, 0.60), true)
	# Back wall with a personnel door.
	var back := Transform3D(Basis(), Vector3(cx, 0, cz - D * 0.5))
	_wall_open(back, W, H, T, [[8.0, 0.0, 1.2, 2.2]], _mats["wall"], wall_col, true)
	# Side walls with high window slits (real openings).
	for sx in [-1.0, 1.0]:
		var side := Transform3D(Basis(Vector3.UP, -PI * 0.5 * float(sx)),
			Vector3(cx + float(sx) * W * 0.5, 0, cz))
		var holes := []
		for i in range(4):
			holes.append([-6.0 + float(i) * 4.0, 3.8, 1.5, 1.2])
		_wall_open(side, D, H, T, holes, _mats["wall"], wall_col, true)
	# Gable ends: stepped boxes above front/back walls.
	for gz in [cz + D * 0.5, cz - D * 0.5]:
		_box(Vector3(20, 1.0, T), _t3(Vector3(cx, 6.5, float(gz))), _mats["wall"], wall_col, false)
		_box(Vector3(13, 1.0, T), _t3(Vector3(cx, 7.5, float(gz))), _mats["wall"], wall_col, false)
		_box(Vector3(6, 1.0, T), _t3(Vector3(cx, 8.5, float(gz))), _mats["wall"], wall_col, false)
	# Gabled roof: two slanted slabs, ridge along x at y=9.
	var ang := atan2(3.0, 9.0)
	for rz2 in [-1.0, 1.0]:
		var panel := Transform3D(Basis(Vector3(1, 0, 0), float(rz2) * ang),
			Vector3(cx, 7.5, cz + float(rz2) * 4.55))
		_box(Vector3(W + 1.0, 0.18, 9.55), panel, _mats["roof"], Color(1, 1, 1), false)
	# Interior: crates, tool benches, oil drums.
	var inf := Transform3D(Basis(), Vector3(cx, 0, cz))
	for cp in [[-8.0, -5.0], [-7.0, -4.0], [8.5, -5.5], [7.5, -4.5]]:
		_box(Vector3(0.9, 0.9, 0.9), inf * _t3(Vector3(float(cp[0]), 0.45, float(cp[1]))),
			_mats["crate"], _varc(Color(1, 1, 1), 0.12), true)
	for bp in [[-5.0, 5.0], [5.0, 5.0]]:
		var bx2 := float(bp[0])
		var bz2 := float(bp[1])
		_box(Vector3(2.2, 0.1, 0.9), inf * _t3(Vector3(bx2, 0.85, bz2)),
			_mats["wood"], Color(1, 1, 1), true)
		for lx in [-0.9, 0.9]:
			_box(Vector3(0.1, 0.85, 0.8), inf * _t3(Vector3(bx2 + float(lx), 0.425, bz2)),
				_mats["wood_dark"], Color(1, 1, 1), false)
		_box(Vector3(0.5, 0.25, 0.3), inf * _t3(Vector3(bx2 - 0.5, 1.02, bz2)),
			_mats["metal"], Color(0.6, 0.6, 0.62), false)
		_box(Vector3(0.9, 0.12, 0.4), inf * _t3(Vector3(bx2 + 0.5, 0.96, bz2)),
			_mats["wood_dark"], Color(1, 1, 1), false)
	var drum_cols := [Color(0.75, 0.25, 0.15), Color(0.20, 0.35, 0.60),
		Color(0.75, 0.60, 0.15), Color(0.30, 0.55, 0.30)]
	var di := 0
	for dp in [[-9.5, 2.0], [-9.5, 3.2], [9.5, 2.5], [-8.3, 2.6]]:
		_cyl(0.32, 0.95, inf * _t3(Vector3(float(dp[0]), 0.475, float(dp[1]))),
			_mats["drum"], drum_cols[di % 4], true)
		di += 1
	# Mezzanine office: slab x cx-2..cx+8, z cz-9..cz-3, top y=3.2.
	_box(Vector3(10.0, 0.25, 6.0), _t3(Vector3(cx + 3.0, 3.075, cz - 6.0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
	for mcx in [-2.0, 8.0]:
		for mcz in [-9.0, -3.0]:
			_box(Vector3(0.3, 3.2, 0.3),
				_t3(Vector3(cx + float(mcx), 1.6, cz + float(mcz))),
				_mats["concrete_dark"], Color(1, 1, 1), true)
	# Stairs up from the hangar floor to the mezz west edge.
	_stair_flight(Transform3D(Basis(), Vector3(cx - 7.0, 0, cz - 6.0)), 0, 5.0, 2.0, 3.2, 0.0)
	# Railing: west edge (gap at stairs), south + east edges.
	for rz3 in [-8.0, -4.0]:
		_box(Vector3(0.08, 1.0, 2.0), _t3(Vector3(cx - 2.0, 3.7, cz + float(rz3))),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
	_box(Vector3(10.0, 0.08, 0.08), _t3(Vector3(cx + 3.0, 4.2, cz - 3.0)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	_box(Vector3(0.08, 0.08, 6.0), _t3(Vector3(cx + 8.0, 4.2, cz - 6.0)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	for i in range(6):
		_box(Vector3(0.07, 1.0, 0.07),
			_t3(Vector3(cx - 1.0 + float(i) * 1.8, 3.7, cz - 3.0)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), false)
	# Mezz office: desk, crates, spare drums, loot.
	_box(Vector3(1.8, 0.08, 0.9), _t3(Vector3(cx + 4.0, 3.99, cz - 6.0)),
		_mats["wood"], Color(1, 1, 1), true)
	_box(Vector3(1.6, 0.75, 0.7), _t3(Vector3(cx + 4.0, 3.575, cz - 6.0)),
		_mats["wood_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.9, 0.9, 0.9), _t3(Vector3(cx + 6.5, 3.65, cz - 7.5)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.12), true)
	_cyl(0.32, 0.95, _t3(Vector3(cx - 0.5, 3.675, cz - 7.5)),
		_mats["drum"], drum_cols[di % 4], true)
	loot_spots.append(["ammo", 60, Vector3(cx + 1.5, 3.75, cz - 6.0)])
	loot_spots.append(["health", 40, Vector3(cx + 5.5, 3.75, cz - 4.5)])
	# Emissive ceiling light panels in the hangar.
	_light_panel(Transform3D.IDENTITY, cx - 6.0, cz, 5.6)
	_light_panel(Transform3D.IDENTITY, cx + 6.0, cz, 5.6)
	if maintenance_heli:
		# Second helicopter under maintenance: rotor blades removed, cowling open.
		var hf := Transform3D(Basis(Vector3.UP, 0.25), Vector3(cx + 1.0, 0, cz - 1.0))
		_helicopter(hf, Color(0.88, 0.88, 0.90), Color(0.20, 0.35, 0.60), false)
		_box(Vector3(0.9, 0.9, 0.9), inf * _t3(Vector3(cx - 3.0, 0.45, cz - 1.0)),
			_mats["crate"], _varc(Color(1, 1, 1), 0.12), true)
	house_positions.append(Vector3(cx, 0, cz))
	_claim(cx, cz, 16.0)
	# Interior loot.
	for lp in [Vector3(cx - 8, 0.55, cz + 5), Vector3(cx + 8, 0.55, cz - 5),
			Vector3(cx - 5, 0.55, cz - 6), Vector3(cx + 5, 0.55, cz + 6)]:
		loot_spots.append([["health", "armor", "ammo"][loot_spots.size() % 3], 50, lp])


func _build_hangars() -> void:
	_hangar(8.0, 45.0, true)
	_hangar(36.0, 45.0, false)


# ---------------- fuel truck ----------------

func _build_fuel_truck() -> void:
	var fr := Transform3D(Basis(Vector3.UP, 0.4), Vector3(12, 0.08, -2))
	var dark: StandardMaterial3D = _mats["heli_dark"]
	# Chassis + cab.
	_box(Vector3(6.5, 0.5, 2.2), fr * _t3(Vector3(0, 0.75, 0)), dark, Color(1, 1, 1), true)
	_box(Vector3(1.8, 1.7, 2.2), fr * _t3(Vector3(2.2, 1.6, 0)),
		_mats["heli_body"], Color(0.90, 0.90, 0.92), true)
	_box(Vector3(0.15, 0.8, 1.8), fr * _t3(Vector3(3.05, 1.75, 0)),
		_mats["glass"], Color(1, 1, 1), false)
	# Tanker cylinder.
	_cyl_axis(1.05, 4.2, Vector3.RIGHT, Vector3(-0.8, 1.75, 0), fr,
		_mats["metal"], Color(0.80, 0.78, 0.72), true)
	_cyl(0.3, 0.25, fr * _t3(Vector3(-0.8, 2.9, 0)),
		_mats["metal"], Color(0.6, 0.6, 0.62), false)
	# Wheels (axles along z).
	for wx in [2.2, -0.5, -1.8]:
		for wz in [-1.15, 1.15]:
			_cyl_axis(0.45, 0.3, Vector3.BACK, Vector3(float(wx), 0.45, float(wz)), fr,
				_mats["tire"], Color(1, 1, 1), false)
	_claim(12, -2, 7.0)


# ---------------- light towers / windsock / helipads / fence ----------------

func _build_light_towers() -> void:
	for lt in [Vector2(-2, -30), Vector2(50, -14), Vector2(50, 22), Vector2(-2, 26)]:
		var lx := float(lt.x)
		var lz := float(lt.y)
		_cyl(0.12, 9.0, _t3(Vector3(lx, 4.5, lz)), _mats["metal"],
			_varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(1.6, 0.15, 0.4), _t3(Vector3(lx, 9.1, lz)),
			_mats["metal"], Color(1, 1, 1), false)
		for hx in [-0.55, 0.55]:
			_box(Vector3(0.45, 0.3, 0.35), _t3(Vector3(lx + float(hx), 8.9, lz)),
				_mats["lamp_head"], Color(1, 1, 1), false)
		_claim(lx, lz, 2.5)


func _build_windsock() -> void:
	var wx := -14.0
	var wz := 32.0
	_cyl(0.08, 6.5, _t3(Vector3(wx, 3.25, wz)), _mats["metal"],
		_varc(Color(1, 1, 1), 0.08), true)
	_windsock = Node3D.new()
	_windsock.name = "Windsock"
	_windsock.position = Vector3(wx, 6.1, wz)
	add_child(_windsock)
	# Sock: 3 shrinking segments, alternating orange/white (own node: animated).
	var radii := [0.28, 0.21, 0.14]
	var cols := [Color(1.0, 0.45, 0.10), Color(0.95, 0.95, 0.95), Color(1.0, 0.45, 0.10)]
	for i in range(3):
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radii[i] * 0.85
		cm.bottom_radius = radii[i]
		cm.height = 0.7
		cm.radial_segments = 10
		seg.mesh = cm
		var sm := StandardMaterial3D.new()
		sm.albedo_color = cols[i]
		sm.roughness = 0.85
		seg.material_override = sm
		# Lay along +x: rotate the MESH node about z.
		seg.rotation.z = -PI * 0.5
		seg.position = Vector3(0.45 + float(i) * 0.68, 0, 0)
		_windsock.add_child(seg)
	_claim(wx, wz, 2.5)


func _build_helipads() -> void:
	# Painted helipad circles (flat, visual only — no collision lips).
	var pads := [Vector2(36, 12), Vector2(46, 18), Vector2(36, 22)]
	for p in pads:
		var px := float(p.x)
		var pz := float(p.y)
		_cyl(3.0, 0.02, _t3(Vector3(px, 0.11, pz)), _mats["paint_yellow"], Color(1, 1, 1), false)
		_cyl(2.65, 0.02, _t3(Vector3(px, 0.12, pz)), _mats["asphalt"], Color(1, 1, 1), false)
		var pw: StandardMaterial3D = _mats["paint_white"]
		_box(Vector3(0.35, 0.015, 1.8), _t3(Vector3(px - 0.55, 0.13, pz)), pw, Color(1, 1, 1), false)
		_box(Vector3(0.35, 0.015, 1.8), _t3(Vector3(px + 0.55, 0.13, pz)), pw, Color(1, 1, 1), false)
		_box(Vector3(1.45, 0.015, 0.35), _t3(Vector3(px, 0.13, pz)), pw, Color(1, 1, 1), false)


func _build_fence() -> void:
	# Perimeter fence at +/-66: posts + mesh panels (visual), plus cheap
	# invisible edge walls for collision with a gate gap on the south side.
	var post_mat: StandardMaterial3D = _mats["metal"]
	var panel_mat: StandardMaterial3D = _mats["concrete_dark"]
	var e := 66.0
	# Posts + panels along all four edges.
	var x := -66.0
	while x <= 66.0:
		for z in [-e, e]:
			_box(Vector3(0.15, 2.4, 0.15), _t3(Vector3(x, 1.2, float(z))), post_mat,
				_varc(Color(1, 1, 1), 0.08), false)
		x += 6.0
	var z2 := -66.0
	while z2 <= 66.0:
		for xx in [-e, e]:
			_box(Vector3(0.15, 2.4, 0.15), _t3(Vector3(float(xx), 1.2, z2)), post_mat,
				_varc(Color(1, 1, 1), 0.08), false)
		z2 += 6.0
	# Panels: 4 edges (skip the south gate span x -3..3).
	var px := -63.0
	while px < 63.0:
		if absf(px) > 4.5:
			_box(Vector3(5.9, 1.8, 0.06), _t3(Vector3(px, 1.3, e)), panel_mat, Color(0.35, 0.37, 0.40), false)
		_box(Vector3(5.9, 1.8, 0.06), _t3(Vector3(px, 1.3, -e)), panel_mat, Color(0.35, 0.37, 0.40), false)
		px += 6.0
	var pz := -63.0
	while pz < 63.0:
		_box(Vector3(0.06, 1.8, 5.9), _t3(Vector3(e, 1.3, pz)), panel_mat, Color(0.35, 0.37, 0.40), false)
		_box(Vector3(0.06, 1.8, 5.9), _t3(Vector3(-e, 1.3, pz)), panel_mat, Color(0.35, 0.37, 0.40), false)
		pz += 6.0
	# Gate frames at the south gate + open gate doors (visual).
	for gx in [-3.2, 3.2]:
		_box(Vector3(0.3, 3.0, 0.3), _t3(Vector3(float(gx), 1.5, e)), post_mat, Color(1, 1, 1), true)
	for gx2 in [-5.6, 5.6]:
		_box(Vector3(2.6, 1.8, 0.08),
			Transform3D(Basis(Vector3.UP, 0.9 * sign(float(gx2))), Vector3(float(gx2), 1.3, e + 1.4)),
			panel_mat, Color(0.40, 0.42, 0.45), false)
	# Edge-wall colliders (south split for the gate).
	_box(Vector3(140, 3, 0.5), _t3(Vector3(0, 1.5, -e)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(63, 3, 0.5), _t3(Vector3(-34.5, 1.5, e)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(63, 3, 0.5), _t3(Vector3(34.5, 1.5, e)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(0.5, 3, 140), _t3(Vector3(e, 1.5, 0)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(0.5, 3, 140), _t3(Vector3(-e, 1.5, 0)), panel_mat, Color(1, 1, 1), true)


# ---------------- clouds / pois / loot / finalize ----------------

func _build_clouds() -> void:
	var cm := SphereMesh.new()
	cm.radius = 1.0
	cm.height = 2.0
	cm.radial_segments = 12
	cm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.96, 0.96, 0.98)
	for k in range(8):
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		mi.scale = Vector3(_rng.randf_range(10, 22), _rng.randf_range(2.0, 3.2),
			_rng.randf_range(6, 10))
		mi.position = Vector3(_rng.randf_range(-90, 90),
			_rng.randf_range(42, 55), _rng.randf_range(-90, 90))
		add_child(mi)
		_clouds.append({"node": mi, "speed": _rng.randf_range(0.4, 1.1)})


func _build_pois() -> void:
	for p in POI_DEFS:
		poi_list.append(p)


func _loot_y_at(x: float, z: float) -> float:
	# Pavement tops sit at 0.08; everything else is bare ground.
	if x >= -8.0 and x <= 58.0 and z >= -22.0 and z <= 26.0:
		return 0.63
	if x >= -62.0 and x <= 62.0 and z >= -63.0 and z <= -53.0:
		return 0.63
	if x >= -6.0 and x <= 2.0 and z >= -53.0 and z <= -29.0:
		return 0.63
	return 0.55


func _scatter_loot() -> void:
	var kinds := ["health", "armor", "ammo"]
	var amounts := {"health": 40, "armor": 50, "ammo": 60}
	var idx := loot_spots.size()
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
			loot_spots.append([kind, int(amounts[kind]), Vector3(lx, _loot_y_at(lx, lz), lz)])
			idx += 1
	# General scatter, kept clear of buildings and aircraft.
	for bc in [[-36.0, -14.0], [-2.0, -20.0], [8.0, 45.0], [36.0, 45.0],
			[18.0, -8.0], [34.0, -14.0], [30.0, 6.0], [-12.0, 40.0], [52.0, 38.0],
			[12.0, -2.0], [-14.0, 32.0], [42.0, 17.0]]:
		_claim(float(bc[0]), float(bc[1]), 9.0)
	var tries := 0
	while loot_spots.size() < 84 and tries < 600:
		tries += 1
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-62, 62)
		if not _claim(x, z, 4.0):
			continue
		var kind2: String = kinds[idx % 3]
		loot_spots.append([kind2, int(amounts[kind2]), Vector3(x, _loot_y_at(x, z), z)])
		idx += 1


func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -10, -85), Vector3(170, 60, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	enemy_spawns = [
		Vector3(-16, 0.6, -4),
		Vector3(8, 0.6, -14),
		Vector3(44, 0.7, 8),
		Vector3(22, 0.6, 62),
		Vector3(40, 0.7, -58),
		Vector3(-30, 0.6, 40),
	]
	print("Airport built: instances=", _batch.box_count(), " draws=", draws,
		" colliders=", _batch.collider_count(), " loot=", loot_spots.size(),
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 110.0:
			cn.position.x = -110.0
	if _windsock != null:
		_windsock.rotation.y = 0.6 + sin(_time * 1.3) * 0.25
		_windsock.rotation.z = sin(_time * 2.1) * 0.08
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 2.0 + 2.0 * (0.5 + 0.5 * sin(_time * 4.0))
