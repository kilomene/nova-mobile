extends Node3D
class_name DamMap
## Phase 14: Dam + Reservoir. Massive concrete gravity dam spanning the north
## edge: stepped downstream face, crest walkway with railings/lamps, 4 spillway
## gate bays with discharge chute and stilling basin, animated reservoir behind
## the wall, enterable powerhouse hall (turbines, gantry crane) and control
## building (consoles, screens, 2 floors), access roads, rocky abutments and
## hillsides. Switchback stair tower climbs the downstream face to the crest.
## Flat ground (y=0). Seeded, merge-ready, clean origin at map center.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261022
const DAM_Z := -45.0
const CREST_Y := 24.0

var player_spawn := Vector3(0, 0.6, 55)
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


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_reservoir()
	_build_dam_wall()
	_build_spillway()
	_build_crest()
	_build_stair_tower()
	_build_powerhouse()
	_build_control_building()
	_build_roads()
	_build_rocks()
	_build_props()
	_build_pois()
	_scatter_loot()
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
	_mats["dam_face"] = _std(Color(1, 1, 1), 0.9)  # per-instance weathered tint
	_mats["asphalt"] = _std(Color(0.23, 0.23, 0.25), 0.95)
	_mats["paint_white"] = _std(Color(0.90, 0.90, 0.88), 0.9)
	_mats["paint_yellow"] = _std(Color(0.85, 0.70, 0.15), 0.9)
	_mats["wall_white"] = _std(Color(0.86, 0.85, 0.82))
	_mats["wall_grey"] = _std(Color(0.55, 0.57, 0.60))
	_mats["trim"] = _std(Color(0.30, 0.28, 0.26))
	_mats["door_wood"] = _std(Color(0.40, 0.28, 0.16))
	_mats["metal"] = _std(Color(0.50, 0.52, 0.55), 0.5, 0.5)
	_mats["gate"] = _std(Color(0.20, 0.32, 0.45), 0.45, 0.6)
	_mats["pole"] = _std(Color(0.25, 0.26, 0.28), 0.6, 0.3)
	_mats["rock"] = _std(Color(1, 1, 1), 0.95)  # per-instance grey-brown
	_mats["gravel"] = _std(Color(0.52, 0.49, 0.44), 0.95)
	_mats["tire"] = _std(Color(0.08, 0.08, 0.09), 0.95)
	_mats["lamp_head"] = _emissive(Color(1.0, 0.88, 0.60), 2.0)
	_mats["strip_light"] = _emissive(Color(0.85, 0.92, 1.0), 2.4)
	_mats["screen"] = _emissive(Color(0.35, 0.75, 0.95), 1.6)
	_mats["screen_green"] = _emissive(Color(0.35, 0.95, 0.45), 1.6)


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


func _strut(a: Vector3, b: Vector3, w: float, d: float, mat: StandardMaterial3D, collide := false) -> void:
	var dv := b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dv.x, dv.z)
	var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
	var xf := Transform3D(basis, mid)
	_box(Vector3(w, length, d), xf, mat, Color(1, 1, 1), collide)


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


func _trim_opening(frame: Transform3D, xc: float, y0: float, w: float, h: float, T: float) -> void:
	var tm = _mats["trim"]
	var c := Color(1, 1, 1)
	_box(Vector3(w + 0.24, 0.12, T + 0.08), frame * _t3(Vector3(xc, y0 - 0.02, 0)), tm, c, false)
	_box(Vector3(w + 0.24, 0.12, T + 0.08), frame * _t3(Vector3(xc, y0 + h + 0.02, 0)), tm, c, false)
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc - w * 0.5 - 0.02, y0 + h * 0.5, 0)), tm, c, false)
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc + w * 0.5 - 0.02, y0 + h * 0.5, 0)), tm, c, false)


func _slab(frame: Transform3D, w: float, d: float, y: float, t := 0.25) -> void:
	_box(Vector3(w, t, d), frame * _t3(Vector3(0, y - t * 0.5, 0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.05), true)


func _stair_flight(frame: Transform3D, x0: float, run: float, width: float, rise: float, y_base := 0.0) -> void:
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
	# Handrails on both sides.
	for sz in [-width * 0.5, width * 0.5]:
		_strut(frame * Vector3(x0, y_base + 1.0, sz),
			frame * Vector3(x0 + run, y_base + rise + 1.0, sz), 0.07, 0.07, _mats["metal"])


func _landing(cx: float, cy: float, cz: float, w := 6.4, d := 2.6) -> void:
	_box(Vector3(w, 0.18, d), _t3(Vector3(cx, cy - 0.09, cz)),
		_mats["concrete"], Color(1, 1, 1), true)
	for sz in [-1.0, 1.0]:
		_box(Vector3(w, 1.0, 0.08), _t3(Vector3(cx, cy + 0.5, cz + sz * (d * 0.5 - 0.04))),
			_mats["metal"], Color(0.7, 0.7, 0.72), true)


# ---------------- ground / reservoir ----------------

func _build_ground() -> void:
	_box(Vector3(140, 0.6, 140), _t3(Vector3(0, -0.3, 0)),
		_mats["gravel"], _varc(Color(1, 1, 1), 0.05), true)


func _water_plane(w: float, d: float, pos: Vector3, pname: String) -> void:
	var water := MeshInstance3D.new()
	water.name = pname
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	water.mesh = pm
	water.position = pos
	var wshader := load("res://shaders/water.gdshader") as Shader
	var wmat := ShaderMaterial.new()
	wmat.shader = wshader
	water.material_override = wmat
	add_child(water)


func _build_reservoir() -> void:
	# Animated reservoir behind (north of) the dam wall.
	_water_plane(140, 20, Vector3(0, 20.0, -60), "ReservoirWater")
	# Far rock ridge closes the north edge.
	for i in range(9):
		var rx := -64.0 + float(i) * 16.0 + _rng.randf_range(-3.0, 3.0)
		var s := _rng.randf_range(7.0, 11.0)
		_batch.add_rock(Vector3(s, s * 0.9, s),
			_t3(Vector3(rx, 20.0 + s * 0.28, -68.0)),
			_mats["rock"], _varc(Color(0.45, 0.42, 0.38), 0.12), true)
	# Side banks.
	for i in range(5):
		var rz := -66.0 + float(i) * 4.5
		for sx in [-1.0, 1.0]:
			var s2 := _rng.randf_range(4.0, 7.0)
			_batch.add_rock(Vector3(s2, s2 * 0.8, s2),
				_t3(Vector3(sx * 67.0, 19.0 + s2 * 0.25, rz)),
				_mats["rock"], _varc(Color(0.45, 0.42, 0.38), 0.12), true)


# ---------------- dam wall / spillway / crest ----------------

func _build_dam_wall() -> void:
	var dz := DAM_Z
	# Stepped gravity profile (downstream face toward +z).
	_box(Vector3(124, 12, 10), _t3(Vector3(0, 6, dz)), _mats["dam_face"],
		_varc(Color(0.66, 0.65, 0.62), 0.05), true)
	_box(Vector3(124, 6, 7), _t3(Vector3(0, 15, dz)), _mats["dam_face"],
		_varc(Color(0.68, 0.67, 0.64), 0.05), true)
	_box(Vector3(124, 6, 4), _t3(Vector3(0, 21, dz)), _mats["dam_face"],
		_varc(Color(0.70, 0.69, 0.66), 0.05), true)
	# Vertical contraction joints on the downstream face.
	for i in range(11):
		var jx := -60.0 + float(i) * 12.0
		_box(Vector3(0.25, 23.5, 0.15), _t3(Vector3(jx, 11.75, dz + 5.02)),
			_mats["concrete_dark"], Color(1, 1, 1), false)
		_box(Vector3(0.25, 5.5, 0.15), _t3(Vector3(jx, 20.75, dz + 2.02)),
			_mats["concrete_dark"], Color(1, 1, 1), false)
	# Gallery inspection adits (dark insets, visual).
	for i in range(6):
		var ax := -50.0 + float(i) * 20.0
		_box(Vector3(2.2, 2.6, 0.2), _t3(Vector3(ax, 3.0, dz + 5.02)),
			_mats["trim"], Color(1, 1, 1), false)
	_label("NOVA DAM", Vector3(0, 14.5, dz + 5.3), 0.0, 1.1, Color(0.95, 0.95, 0.95))


func _build_spillway() -> void:
	var dz := DAM_Z
	# 4 gate bays centered on x=0: piers + closed steel gates on the face.
	for px in [-15.0, -5.0, 5.0, 15.0]:
		_box(Vector3(1.6, 10, 1.4), _t3(Vector3(px, 17, dz + 3.8)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), true)
	for gx in [-10.0, 0.0, 10.0]:
		# Dark recess + gate leaf.
		_box(Vector3(8.4, 8.5, 0.25), _t3(Vector3(gx, 16.2, dz + 3.55)),
			_mats["trim"], Color(1, 1, 1), false)
		_box(Vector3(7.6, 7.6, 0.5), _t3(Vector3(gx, 15.8, dz + 3.7)),
			_mats["gate"], _varc(Color(1, 1, 1), 0.08), false)
		# Gate ribs.
		for r in range(3):
			_box(Vector3(7.6, 0.3, 0.15), _t3(Vector3(gx, 13.2 + float(r) * 2.6, dz + 4.0)),
				_mats["metal"], Color(1, 1, 1), false)
	# Hoist deck beam across the bays.
	_box(Vector3(34, 1.6, 2.2), _t3(Vector3(0, 22.6, dz + 3.6)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	for gx2 in [-10.0, 0.0, 10.0]:
		_box(Vector3(1.2, 1.4, 1.2), _t3(Vector3(gx2, 23.9, dz + 3.6)),
			_mats["gate"], Color(1, 1, 1), false)
	# Discharge chute: sloped slab from the gates to the stilling basin.
	_strut(Vector3(-17, 12.0, dz + 3.5), Vector3(-17, 0.6, -27), 34, 0.8, _mats["concrete"], true)
	for sx in [-1.0, 1.0]:
		_strut(Vector3(sx * 17, 12.6, dz + 3.5), Vector3(sx * 17, 1.2, -27), 0.8, 1.4, _mats["concrete_dark"])
	# Stilling basin: apron + side walls + animated water strip.
	_box(Vector3(40, 0.4, 14), _t3(Vector3(0, 0.0, -33)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.05), true)
	for sx2 in [-1.0, 1.0]:
		_box(Vector3(0.8, 2.2, 14), _t3(Vector3(sx2 * 20.4, 1.1, -33)),
			_mats["concrete_dark"], Color(1, 1, 1), true)
	_water_plane(36, 9, Vector3(0, 0.45, -33), "BasinWater")


func _build_crest() -> void:
	var dz := DAM_Z
	# Crest walkway deck (top flush at CREST_Y).
	_box(Vector3(124, 0.5, 5), _t3(Vector3(0, CREST_Y - 0.25, dz)),
		_mats["asphalt"], _varc(Color(1, 1, 1), 0.05), true)
	_box(Vector3(120, 0.02, 0.18), _t3(Vector3(0, CREST_Y + 0.01, dz)),
		_mats["paint_white"], Color(1, 1, 1), false)
	# Railings both sides: posts + double rail.
	for sz in [-1.0, 1.0]:
		var rz: float = dz + sz * 2.4
		var x := -61.0
		while x < 61.5:
			_box(Vector3(0.09, 1.1, 0.09), _t3(Vector3(x, CREST_Y + 0.55, rz)),
				_mats["metal"], Color(1, 1, 1), false)
			x += 4.0
		_box(Vector3(124, 0.09, 0.09), _t3(Vector3(0, CREST_Y + 1.08, rz)),
			_mats["metal"], Color(1, 1, 1), true)
		_box(Vector3(124, 0.07, 0.07), _t3(Vector3(0, CREST_Y + 0.6, rz)),
			_mats["metal"], Color(1, 1, 1), false)
	# Crest lamp posts.
	var lx := -56.0
	while lx < 60.0:
		var frame := Transform3D(Basis(), Vector3(lx, CREST_Y, dz - 1.8))
		_batch.add_cyl(0.11, 5.5, frame * _t3(Vector3(0, 2.75, 0)), _mats["pole"], Color(1, 1, 1))
		_batch.add_collider(Vector3(0.25, 5.5, 0.25), frame * _t3(Vector3(0, 2.75, 0)))
		_box(Vector3(0.5, 0.2, 0.7), frame * _t3(Vector3(0, 5.4, 0.3)), _mats["lamp_head"], Color(1, 1, 1), false)
		lx += 16.0
	# Crest loot.
	for i in range(8):
		var cx := -52.0 + float(i) * 14.5 + _rng.randf_range(-2.0, 2.0)
		_add_loot(_loot_kind(), Vector3(cx, CREST_Y + 0.55, dz + _rng.randf_range(-1.2, 1.2)))


func _build_stair_tower() -> void:
	# Switchback stair tower on the downstream face: 6 flights x 4m rise.
	# Each flight runs along world z; frames map local +x to the run direction.
	var lane_a := 42.0
	var lane_b := 46.4
	var z0 := -38.0
	var z1 := -30.0
	var run := z1 - z0  # 8.0
	for t in range(6):
		var yb := 4.0 * float(t)
		if t % 2 == 0:
			# Lane A: z0 -> z1 (local +x maps to world +z).
			var fr := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(lane_a, 0, z0))
			_stair_flight(fr, 0.0, run, 2.4, 4.0, yb)
		else:
			# Lane B: z1 -> z0 (local +x maps to world -z).
			var fr2 := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(lane_b, 0, z1))
			_stair_flight(fr2, 0.0, run, 2.4, 4.0, yb)
		if t < 5:
			var lz := z1 if t % 2 == 0 else z0
			_landing(44.2, yb + 4.0, lz, 6.4, 2.6)
	# Support posts.
	for px in [lane_a - 1.4, lane_b + 1.4]:
		for pz in [z0 - 1.0, z1 + 1.0]:
			_box(Vector3(0.4, 24, 0.4), _t3(Vector3(px, 12, pz)),
				_mats["concrete_dark"], Color(1, 1, 1), true)
	# Bridge from the stair top to the crest walkway.
	_box(Vector3(7, 0.4, 6.5), _t3(Vector3(46.0, CREST_Y - 0.2, -40.2)),
		_mats["concrete"], Color(1, 1, 1), true)
	for sz in [-1.0, 1.0]:
		_box(Vector3(7, 1.0, 0.08), _t3(Vector3(46.0, CREST_Y + 0.5, -40.2 + sz * 3.2)),
			_mats["metal"], Color(0.7, 0.7, 0.72), true)


# ---------------- powerhouse ----------------

func _build_powerhouse() -> void:
	var cx := 32.0
	var cz := 14.0
	var w := 22.0
	var d := 16.0
	var h := 11.0
	var t := 0.3
	var frame := Transform3D(Basis(), Vector3(cx, 0, cz))
	var col := _varc(Color(1, 1, 1), 0.06)
	_slab(frame, w + 0.6, d + 0.6, 0.02)
	# West wall with two big turbine-hall doors.
	_wall_open(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, h, t, [[-3.5, 0, 4.2, 5.5], [3.5, 0, 4.2, 5.5]], _mats["wall_grey"], col, true)
	_trim_opening(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)), -3.5, 0, 4.2, 5.5, t)
	_trim_opening(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)), 3.5, 0, 4.2, 5.5, t)
	# Other walls: high window band.
	for sd in [[0, d * 0.5, 0.0], [0, -d * 0.5, 0.0]]:
		_wall_open(frame * _t3(Vector3(sd[0], 0, sd[1])), w, h, t,
			[[-w * 0.3, 6.5, 2.4, 2.4], [0, 6.5, 2.4, 2.4], [w * 0.3, 6.5, 2.4, 2.4]],
			_mats["wall_grey"], col, true)
	_wall_open(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, h, t, [[0, 0, 2.0, 3.0], [-d * 0.28, 6.5, 2.0, 2.2], [d * 0.28, 6.5, 2.0, 2.2]],
		_mats["wall_grey"], col, true)
	_label("POWERHOUSE", frame * Vector3(0, h + 0.8, -d * 0.5 - 0.3), PI, 0.8, Color(1.0, 0.85, 0.4))
	# Roof + vents.
	_slab(frame, w, d, h)
	for vx in [-w * 0.25, w * 0.25]:
		_batch.add_cyl(0.9, 2.2, frame * _t3(Vector3(vx, h + 1.1, 0)), _mats["metal"], Color(1, 1, 1))
		_batch.add_collider(Vector3(1.8, 2.2, 1.8), frame * _t3(Vector3(vx, h + 1.1, 0)))
	# Turbine-generator sets.
	for i in range(3):
		var tx := -6.0 + float(i) * 6.0
		_batch.add_cyl(2.2, 2.6, frame * _t3(Vector3(tx, 1.3, 0)), _mats["gate"], _varc(Color(1, 1, 1), 0.08))
		_batch.add_collider(Vector3(4.0, 2.6, 4.0), frame * _t3(Vector3(tx, 1.3, 0)))
		_batch.add_cyl(1.2, 1.8, frame * _t3(Vector3(tx, 3.5, 0)), _mats["metal"], Color(1, 1, 1))
		_batch.add_collider(Vector3(2.2, 1.8, 2.2), frame * _t3(Vector3(tx, 3.5, 0)))
	# Gantry crane: runway rails + bridge + hoist.
	for sz in [-d * 0.5 + 1.0, d * 0.5 - 1.0]:
		_box(Vector3(w - 1.0, 0.4, 0.4), frame * _t3(Vector3(0, 9.2, sz)), _mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(0.5, 0.5, d - 2.0), frame * _t3(Vector3(2.0, 9.6, 0)), _mats["paint_yellow"], Color(1, 1, 1), false)
	_box(Vector3(0.8, 1.2, 0.8), frame * _t3(Vector3(2.0, 8.8, 1.5)), _mats["trim"], Color(1, 1, 1), false)
	# Control consoles along the north wall.
	for k in range(3):
		var kx := -7.5 + float(k) * 4.5
		var kf := frame * Transform3D(Basis(Vector3.UP, PI), Vector3(kx, 0, -d * 0.5 + 1.2))
		_box(Vector3(1.8, 0.8, 0.7), kf * _t3(Vector3(0, 0.4, 0)), _mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(1.7, 0.8, 0.08),
			kf * Transform3D(Basis(Vector3(1, 0, 0), -0.3), Vector3(0, 1.15, 0.12)),
			_mats["screen"], Color(1, 1, 1), false)
	# Ceiling lamp panels.
	for lx in [-w * 0.3, 0.0, w * 0.3]:
		for lz in [-d * 0.25, d * 0.25]:
			_box(Vector3(1.8, 0.08, 1.0), frame * _t3(Vector3(lx, h - 0.15, lz)),
				_mats["strip_light"], Color(1, 1, 1), false)
	# Oil drums + crates (cover).
	for i in range(4):
		var dp: Vector3 = frame * Vector3(-w * 0.5 + 2.0 + float(i % 2) * 1.4, 0, d * 0.5 - 2.0 - float(i / 2) * 1.4)
		_batch.add_cyl(0.45, 1.1, _t3(Vector3(dp.x, 0.55, dp.z)), _mats["gate"], _varc(Color(1, 1, 1), 0.12))
		_batch.add_collider(Vector3(0.9, 1.1, 0.9), _t3(Vector3(dp.x, 0.55, dp.z)))
	# Interior loot.
	var spots := [Vector3(-8.5, 0, 5.5), Vector3(8.5, 0, 5.5), Vector3(0, 0, -5.0),
		Vector3(-4.0, 0, 2.5), Vector3(4.0, 0, 2.5), Vector3(-8.5, 0, -5.0),
		Vector3(8.5, 0, -5.0), Vector3(0, 0, 5.5)]
	for sp in spots:
		var wp: Vector3 = frame * sp
		_add_loot(_loot_kind(), Vector3(wp.x, 0.55, wp.z))
	house_positions.append(Vector3(cx, 0, cz))


# ---------------- control building ----------------

func _build_control_building() -> void:
	var cx := -28.0
	var cz := 16.0
	var w := 12.0
	var d := 9.0
	var fh := 3.4
	var t := 0.22
	var frame := Transform3D(Basis(), Vector3(cx, 0, cz))
	var col := _varc(Color(1, 1, 1), 0.06)
	_slab(frame, w + 0.5, d + 0.5, 0.02)
	# Ground floor: control room. Front (+z) with door + windows.
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, fh, t,
		[[0, 0, 1.8, 2.8], [-w * 0.32, 1.0, 2.2, 1.4], [w * 0.32, 1.0, 2.2, 1.4]],
		_mats["wall_white"], col, true)
	_trim_opening(frame * _t3(Vector3(0, 0, d * 0.5)), 0, 0, 1.8, 2.8, t)
	_wall_open(frame * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t,
		[[-w * 0.25, 1.0, 2.0, 1.4], [w * 0.25, 1.0, 2.0, 1.4]], _mats["wall_white"], col, true)
	for sx in [-1.0, 1.0]:
		_wall_open(frame * Transform3D(Basis(Vector3.UP, sx * PI * 0.5), Vector3(sx * w * 0.5, 0, 0)),
			d, fh, t, [[0, 1.0, 2.0, 1.4]], _mats["wall_white"], col, true)
	_label("CONTROL", frame * Vector3(0, fh + 0.5, d * 0.5 + 0.25), 0.0, 0.55, Color(0.4, 0.8, 1.0))
	# Console row with emissive screens + big map table.
	for k in range(4):
		var kx := -4.5 + float(k) * 3.0
		var kf := frame * Transform3D(Basis(Vector3.UP, PI), Vector3(kx, 0, -d * 0.5 + 1.1))
		_box(Vector3(1.6, 0.75, 0.6), kf * _t3(Vector3(0, 0.375, 0)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.08), true)
		_box(Vector3(1.5, 0.7, 0.08),
			kf * Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(0, 1.05, 0.1)),
			_mats["screen"] if k % 2 == 0 else _mats["screen_green"], Color(1, 1, 1), false)
		_box(Vector3(0.5, 0.5, 0.5), kf * _t3(Vector3(0, 0.25, 1.0)), _mats["trim"], Color(1, 1, 1), true)
	_box(Vector3(3.0, 0.9, 1.8), frame * _t3(Vector3(0, 0.45, 0.8)), _mats["door_wood"], col, true)
	_box(Vector3(2.8, 0.05, 1.6), frame * _t3(Vector3(0, 0.93, 0.8)), _mats["screen_green"], Color(1, 1, 1), false)
	# Ceiling panels.
	for lx in [-w * 0.28, w * 0.28]:
		for lz in [-d * 0.22, d * 0.22]:
			_box(Vector3(1.6, 0.07, 0.9), frame * _t3(Vector3(lx, fh - 0.12, lz)),
				_mats["strip_light"], Color(1, 1, 1), false)
	# Stairs to floor 2 along the east wall: flight x 1.4 -> 5.4, width 1.6 at z 0.
	_stair_flight(frame, w * 0.5 - 4.6, 4.0, 1.6, fh, 0.0)
	# Floor 2 slab with a stairwell opening over the flight footprint.
	var shx0 := w * 0.5 - 4.6
	var shx1 := shx0 + 4.0
	# Left of the hole (full depth).
	_box(Vector3(shx0 + w * 0.5, 0.25, d),
		frame * _t3(Vector3((shx0 - w * 0.5) * 0.5, fh - 0.125, 0)),
		_mats["concrete"], Color(1, 1, 1), true)
	# Right of the hole (full depth).
	_box(Vector3(w * 0.5 - shx1, 0.25, d),
		frame * _t3(Vector3((shx1 + w * 0.5) * 0.5, fh - 0.125, 0)),
		_mats["concrete"], Color(1, 1, 1), true)
	# Front/back strips over the hole width.
	for sz in [-1.0, 1.0]:
		var zw := d * 0.5 - 0.8
		_box(Vector3(shx1 - shx0, 0.25, zw),
			frame * _t3(Vector3((shx0 + shx1) * 0.5, fh - 0.125, sz * (0.8 + zw * 0.5))),
			_mats["concrete"], Color(1, 1, 1), true)
	# Floor 2 walls.
	_wall_open(frame * _t3(Vector3(0, fh, d * 0.5)), w, fh, t,
		[[-w * 0.25, 1.0, 2.0, 1.4], [w * 0.25, 1.0, 2.0, 1.4]], _mats["wall_white"], col, true)
	_wall_open(frame * _t3(Vector3(0, fh, -d * 0.5)), w, fh, t,
		[[0, 1.0, 2.0, 1.4]], _mats["wall_white"], col, true)
	for sx2 in [-1.0, 1.0]:
		_wall_open(frame * Transform3D(Basis(Vector3.UP, sx2 * PI * 0.5), Vector3(sx2 * w * 0.5, fh, 0)),
			d, fh, t, [[0, 1.0, 2.0, 1.4]], _mats["wall_white"], col, true)
	# Floor 2: desks + panels.
	for i in range(2):
		var df := frame * _t3(Vector3(-2.5 + float(i) * 5.0, fh, 0.5))
		_box(Vector3(1.7, 0.08, 0.85), df * _t3(Vector3(0, 0.76, 0)), _mats["door_wood"], col, false)
		_box(Vector3(1.6, 0.72, 0.75), df * _t3(Vector3(0, 0.36, 0)), _mats["door_wood"], col, true)
		_box(Vector3(2.0, 0.06, 0.5), df * _t3(Vector3(0, fh + 2.9, 0)), _mats["strip_light"], Color(1, 1, 1), false)
	# Roof + antenna.
	_slab(frame, w, d, fh * 2.0)
	_box(Vector3(w + 0.2, 0.9, 0.2), frame * _t3(Vector3(0, fh * 2.0 + 0.45, d * 0.5)), _mats["trim"], col, false)
	_box(Vector3(w + 0.2, 0.9, 0.2), frame * _t3(Vector3(0, fh * 2.0 + 0.45, -d * 0.5)), _mats["trim"], col, false)
	_batch.add_cyl(0.08, 6.0, frame * _t3(Vector3(w * 0.3, fh * 2.0 + 3.0, -d * 0.3)), _mats["pole"], Color(1, 1, 1))
	_box(Vector3(0.3, 0.3, 0.3), frame * _t3(Vector3(w * 0.3, fh * 2.0 + 6.1, -d * 0.3)),
		_mats["lamp_head"], Color(1, 1, 1), false)
	# Control-room loot.
	var spots := [Vector3(-5.0, 0, 2.8), Vector3(5.0, 0, 2.8), Vector3(0, 0, -3.0),
		Vector3(-2.5, 0, 2.8), Vector3(2.5, 0, -3.0), Vector3(-2.5, fh, 0.5),
		Vector3(2.5, fh, 0.5), Vector3(0, fh, -2.5)]
	for sp in spots:
		var wp: Vector3 = frame * sp
		_add_loot(_loot_kind(), Vector3(wp.x, sp.y + 0.55, wp.z))
	house_positions.append(Vector3(cx, 0, cz))


# ---------------- roads / rocks / props ----------------

func _road_strip(x0: float, x1: float, z0: float, z1: float) -> void:
	_box(Vector3(x1 - x0, 0.08, z1 - z0),
		_t3(Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)),
		_mats["asphalt"], _varc(Color(1, 1, 1), 0.06), false)


func _dashes_x(x0: float, x1: float, z: float) -> void:
	var x := x0 + 2.0
	while x < x1 - 1.0:
		_box(Vector3(2.0, 0.02, 0.16), _t3(Vector3(x, 0.055, z)),
			_mats["paint_white"], Color(1, 1, 1), false)
		x += 5.0


func _dashes_z(z0: float, z1: float, x: float) -> void:
	var z := z0 + 2.0
	while z < z1 - 1.0:
		_box(Vector3(0.16, 0.02, 2.0), _t3(Vector3(x, 0.055, z)),
			_mats["paint_white"], Color(1, 1, 1), false)
		z += 5.0


func _build_roads() -> void:
	# South access road.
	_road_strip(-4, 4, 6, 66)
	_dashes_z(8, 64, 0)
	# Dam toe road (east-west service road).
	_road_strip(-60, 60, -34, -28)
	_dashes_x(-58, 58, -31)
	# Powerhouse spur.
	_road_strip(24, 40, 4, 24)
	# Control building spur.
	_road_strip(-36, -20, 8, 24)


func _build_rocks() -> void:
	# Rocky hillsides east and west + dam abutments.
	for i in range(14):
		var s := _rng.randf_range(2.5, 6.0)
		var p := Vector3(_rng.randf_range(48, 64), 0, _rng.randf_range(-20, 40))
		_batch.add_rock(Vector3(s, s * _rng.randf_range(0.6, 1.0), s),
			Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p + Vector3(0, s * 0.28, 0)),
			_mats["rock"], _varc(Color(0.48, 0.45, 0.40), 0.12), s > 3.5)
	for i in range(14):
		var s2 := _rng.randf_range(2.5, 6.0)
		var p2 := Vector3(_rng.randf_range(-64, -48), 0, _rng.randf_range(-20, 40))
		_batch.add_rock(Vector3(s2, s2 * _rng.randf_range(0.6, 1.0), s2),
			Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p2 + Vector3(0, s2 * 0.28, 0)),
			_mats["rock"], _varc(Color(0.48, 0.45, 0.40), 0.12), s2 > 3.5)
	# Abutments: big rocks where the dam meets the hillsides.
	for sx in [-1.0, 1.0]:
		for i in range(3):
			var s3 := _rng.randf_range(5.0, 8.0)
			_batch.add_rock(Vector3(s3, s3 * 0.9, s3),
				_t3(Vector3(sx * _rng.randf_range(60, 66), s3 * 0.3, DAM_Z + _rng.randf_range(-4, 4))),
				_mats["rock"], _varc(Color(0.45, 0.42, 0.38), 0.10), true)


func _streetlight(pos: Vector3, yaw: float, h := 7.5) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_batch.add_cyl(0.13, h, frame * _t3(Vector3(0, h * 0.5, 0)), _mats["pole"], _varc(Color(1, 1, 1), 0.08))
	_batch.add_collider(Vector3(0.3, h, 0.3), frame * _t3(Vector3(0, h * 0.5, 0)))
	_box(Vector3(0.12, 0.12, 2.2), frame * _t3(Vector3(0, h - 0.1, 1.0)), _mats["pole"], Color(1, 1, 1), false)
	_box(Vector3(0.5, 0.22, 0.9), frame * _t3(Vector3(0, h - 0.2, 2.0)), _mats["lamp_head"], Color(1, 1, 1), false)


func _crate(pos: Vector3) -> void:
	var s := _rng.randf_range(1.0, 1.4)
	_box(Vector3(s, s, s), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), pos + Vector3(0, s * 0.5, 0)),
		_mats["door_wood"], _varc(Color(1, 1, 1), 0.12), true)


func _build_props() -> void:
	# Streetlights along the toe road and access road.
	var x := -56.0
	while x < 58.0:
		_streetlight(Vector3(x, 0, -27.0), 0.0)
		x += 16.0
	var z := 10.0
	while z < 62.0:
		_streetlight(Vector3(5.2, 0, z), -PI * 0.5)
		z += 18.0
	# Crates near buildings (cover).
	for i in range(10):
		var bx: float = _pick([32.0, -28.0])
		var bz: float = _pick([14.0, 16.0])
		_crate(Vector3(bx + _rng.randf_range(-14, 14), 0, bz + _rng.randf_range(10, 16)))
	# Warning signs at the spillway.
	for sx in [-22.0, 22.0]:
		_box(Vector3(0.12, 2.2, 0.12), _t3(Vector3(sx, 1.1, -25.5)), _mats["pole"], Color(1, 1, 1), true)
		_box(Vector3(1.6, 1.0, 0.08), _t3(Vector3(sx, 2.4, -25.5)), _mats["paint_yellow"], Color(1, 1, 1), false)
	_label("DANGER", Vector3(-22, 2.4, -25.4), 0.0, 0.35, Color(0.9, 0.1, 0.1))
	_label("DANGER", Vector3(22, 2.4, -25.4), 0.0, 0.35, Color(0.9, 0.1, 0.1))
	# Spillway / apron / roadside loot.
	var spots := [
		Vector3(-14, 0, -31), Vector3(14, 0, -31), Vector3(0, 0, -36),
		Vector3(-30, 0, -30), Vector3(30, 0, -30), Vector3(-44, 0, -30),
		Vector3(44, 0, -30), Vector3(8, 0, 30), Vector3(-8, 0, 40),
		Vector3(20, 0, 26), Vector3(-20, 0, 26), Vector3(52, 0, 10),
		Vector3(-52, 0, 10), Vector3(0, 0, 48), Vector3(12, 0, 8),
	]
	for sp in spots:
		_add_loot(_loot_kind(), Vector3(sp.x, 0.55, sp.z))


# ---------------- POIs ----------------

func _build_pois() -> void:
	var defs := [
		{"name": "Dam Crest", "pos": Vector3(0, CREST_Y, DAM_Z)},
		{"name": "Control Room", "pos": Vector3(-28, 0, 16)},
		{"name": "Spillway", "pos": Vector3(0, 0.2, -33)},
	]
	for dd in defs:
		poi_list.append({"name": String(dd["name"]), "pos": dd["pos"]})
		var pp: Vector3 = dd["pos"]
		for i in range(4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, 7.0)
			_add_loot(_loot_kind(), pp + Vector3(cos(a) * r, 0.55, sin(a) * r))


func _scatter_loot() -> void:
	# Top up to ~70 loot spots at valid outdoor positions.
	var want := 70
	var attempts := 0
	while loot_spots.size() < want and attempts < 800:
		attempts += 1
		var p := Vector3(_rng.randf_range(-62.0, 62.0), 0, _rng.randf_range(-38.0, 62.0))
		if p.z > -52.0 and p.z < -38.0 and absf(p.x) < 64.0:
			continue  # dam wall footprint
		if absf(p.x - 32.0) < 13.0 and absf(p.z - 14.0) < 10.0:
			continue  # powerhouse
		if absf(p.x + 28.0) < 8.0 and absf(p.z - 16.0) < 6.5:
			continue  # control building
		if absf(p.x) < 22.0 and p.z > -42.0 and p.z < -24.0:
			continue  # spillway apron/chute (already stocked)
		_add_loot(_loot_kind(), Vector3(p.x, 0.55, p.z))


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
		Vector3(-30, CREST_Y + 0.6, DAM_Z), Vector3(30, CREST_Y + 0.6, DAM_Z),
		Vector3(0, 0.6, -31), Vector3(18, 0.6, 14),
		Vector3(-28, 0.6, 8), Vector3(10, 0.6, 50),
	]
	print("Dam built: instances=", instance_total,
		" draws=", draw_calls, " colliders=", collider_total,
		" loot=", loot_spots.size(), " pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 160.0:
			cn.position.x = -160.0
