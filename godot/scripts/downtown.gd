extends Node3D
class_name DowntownMap
## Phase 13: Downtown — Nova Towers. High-rise city-core showpiece map.
## 6 enterable towers (5-9 stories, glass/concrete facades with per-instance
## tint variation): ground lobbies (reception, seating, columns), furnished
## office floors, switchback stairs floor-to-floor, rooftop access (parapets,
## AC units, loot; helipad on Nova Tower). Street grid with lane markings,
## sidewalks, streetlights, planters, parked cars, central plaza with fountain.
## Flat ground (y=0). Seeded, merge-ready, clean origin at map center.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261021
const FH := 3.2  # floor height

# Street layout.
const AVE_Z := 8.0
const AVE_HW := 5.0
const ST_X := -10.0
const ST_HW := 4.0

var player_spawn := Vector3(30, 0.6, 58)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []
var map_extent := MAP_EXTENT
var draw_calls := 0
var instance_total := 0
var collider_total := 0
var indoor_loot_count := 0

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _clouds: Array = []
var _time := 0.0

const TOWERS := [
	{"x": -40.0, "z": -32.0, "yaw": 0.0, "floors": 9, "w": 14.0, "d": 14.0,
		"tint": Color(0.55, 0.72, 0.88), "name": "NOVA TOWER", "helipad": true, "rich": true},
	{"x": 26.0, "z": -34.0, "yaw": 0.0, "floors": 7, "w": 12.0, "d": 12.0,
		"tint": Color(0.60, 0.80, 0.78), "name": "AZURI PLAZA", "helipad": false, "rich": false},
	{"x": 54.0, "z": -12.0, "yaw": -PI * 0.5, "floors": 6, "w": 11.0, "d": 11.0,
		"tint": Color(0.78, 0.76, 0.70), "name": "EKO COURT", "helipad": false, "rich": false},
	{"x": -42.0, "z": 42.0, "yaw": 0.0, "floors": 6, "w": 12.0, "d": 12.0,
		"tint": Color(0.88, 0.74, 0.55), "name": "MARINA HOUSE", "helipad": false, "rich": false},
	{"x": 10.0, "z": 42.0, "yaw": 0.0, "floors": 5, "w": 11.0, "d": 11.0,
		"tint": Color(0.90, 0.90, 0.92), "name": "IKOYI SUITES", "helipad": false, "rich": false},
	{"x": -26.0, "z": 20.0, "yaw": PI * 0.5, "floors": 5, "w": 10.0, "d": 10.0,
		"tint": Color(0.62, 0.64, 0.68), "name": "CENTRAL COURT", "helipad": false, "rich": false},
]


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_streets()
	_build_plaza()
	for td in TOWERS:
		_build_tower(float(td["x"]), float(td["z"]), float(td["yaw"]),
			int(td["floors"]), float(td["w"]), float(td["d"]),
			td["tint"], String(td["name"]), bool(td["helipad"]), bool(td["rich"]))
		house_positions.append(Vector3(float(td["x"]), 0, float(td["z"])))
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
	_mats["concrete"] = _std(Color(0.60, 0.59, 0.56))
	_mats["concrete_dark"] = _std(Color(0.42, 0.41, 0.39))
	_mats["asphalt"] = _std(Color(0.22, 0.22, 0.24), 0.95)
	_mats["sidewalk"] = _std(Color(0.70, 0.68, 0.64))
	_mats["paver"] = _std(Color(0.76, 0.72, 0.64), 0.9)
	_mats["paint_white"] = _std(Color(0.90, 0.90, 0.88), 0.9)
	_mats["paint_yellow"] = _std(Color(0.85, 0.70, 0.15), 0.9)
	_mats["facade"] = _std(Color(1, 1, 1), 0.3, 0.35)  # per-instance tint
	_mats["glass_dark"] = _std(Color(0.12, 0.16, 0.20), 0.15, 0.6)
	_mats["trim"] = _std(Color(0.30, 0.28, 0.26))
	_mats["wall_white"] = _std(Color(0.88, 0.87, 0.84))
	_mats["door_wood"] = _std(Color(0.40, 0.28, 0.16))
	_mats["metal"] = _std(Color(0.50, 0.52, 0.55), 0.5, 0.5)
	_mats["pole"] = _std(Color(0.25, 0.26, 0.28), 0.6, 0.3)
	_mats["sofa"] = _std(Color(0.55, 0.25, 0.20), 0.9)
	_mats["leaf"] = _std(Color(0.22, 0.46, 0.20))
	_mats["soil"] = _std(Color(0.35, 0.27, 0.18))
	_mats["helipad"] = _std(Color(0.30, 0.32, 0.34), 0.9)
	_mats["tire"] = _std(Color(0.08, 0.08, 0.09), 0.95)
	_mats["car_a"] = _std(Color(0.75, 0.75, 0.78), 0.35, 0.4)
	_mats["car_b"] = _std(Color(0.15, 0.15, 0.17), 0.35, 0.4)
	_mats["car_c"] = _std(Color(0.60, 0.14, 0.12), 0.35, 0.4)
	_mats["lamp_head"] = _emissive(Color(1.0, 0.88, 0.60), 2.0)
	_mats["strip_light"] = _emissive(Color(0.85, 0.92, 1.0), 2.4)
	_mats["screen"] = _emissive(Color(0.35, 0.75, 0.95), 1.6)


func _varc(c: Color, amt := 0.10) -> Color:
	var f := 1.0 + _rng.randf_range(-amt, amt)
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


func _pick(arr: Array):
	return arr[_rng.randi_range(0, arr.size() - 1)]


func _loot_kind() -> String:
	return _pick(["ammo", "ammo", "health", "armor", "health", "ammo"])


func _add_loot(kind: String, pos: Vector3, indoor := false) -> void:
	var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
	loot_spots.append([kind, amt, pos])
	if indoor:
		indoor_loot_count += 1


# ---------------- batch helpers ----------------

func _t3(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)


func _box(size: Vector3, xform: Transform3D, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	_batch.add_box(size, xform, mat, col)
	if collide:
		_batch.add_collider(size, xform)


func _strut(a: Vector3, b: Vector3, w: float, d: float, mat: StandardMaterial3D) -> void:
	var dv := b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dv.x, dv.z)
	var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
	_box(Vector3(w, length, d), Transform3D(basis, mid), mat, Color(1, 1, 1), false)


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
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc + w * 0.5 + 0.02, y0 + h * 0.5, 0)), tm, c, false)


func _window_wall(frame: Transform3D, W: float, H: float, T: float, mat: StandardMaterial3D, col: Color) -> void:
	var n := maxi(2, int(W / 3.0))
	var holes := []
	for i in range(n):
		var xc := -W * 0.5 + W * (float(i) + 0.5) / float(n)
		holes.append([xc, 1.0, 1.5, 1.4])
	_wall_open(frame, W, H, T, holes, mat, col, true)
	for h in holes:
		_trim_opening(frame, h[0], h[1], h[2], h[3], T)
		_box(Vector3(h[2], h[3], 0.04), frame * _t3(Vector3(h[0], h[1] + h[3] * 0.5, -T * 0.5 - 0.25)),
			_mats["glass_dark"], Color(1, 1, 1), false)


func _signboard(frame: Transform3D, w: float, y: float, text: String, col: Color) -> void:
	_box(Vector3(w, 1.0, 0.35), frame * _t3(Vector3(0, y, 0.18)), _mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(w - 0.3, 0.8, 0.38), frame * _t3(Vector3(0, y, 0.18)), _std(col, 0.6), Color(1, 1, 1), false)
	_label(text, frame * Vector3(0, y, 0.42), atan2(frame.basis.z.x, frame.basis.z.z), 0.5)


func _slab(frame: Transform3D, w: float, d: float, y: float, t := 0.25) -> void:
	_box(Vector3(w, t, d), frame * _t3(Vector3(0, y - t * 0.5, 0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.05), true)


func _slab_hole(frame: Transform3D, w: float, d: float, y: float, hx0: float, hx1: float, hz: float, hzw: float) -> void:
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


func _stairs2(frame: Transform3D, xa: float, xb: float, zc: float, ya: float, yb: float, width: float) -> void:
	# Stair flight from (xa, ya) to (xb, yb): visual steps + one ramp collider.
	var steps := 12
	var run := xb - xa
	var rise := yb - ya
	for i in range(steps):
		var f := (float(i) + 0.5) / float(steps)
		var sx := xa + run * f
		var sy := ya + rise * f
		_box(Vector3(absf(run) / float(steps) + 0.06, 0.09, width),
			frame * _t3(Vector3(sx, sy - 0.045, zc)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var ramp := Transform3D(Basis(Vector3(0, 0, 1), ang),
		frame * Vector3(xa + run * 0.5, ya + rise * 0.5 - 0.06, zc))
	_batch.add_collider(Vector3(length, 0.12, width), ramp)
	_strut(frame * Vector3(xa, ya + 1.0, zc - width * 0.5),
		frame * Vector3(xb, yb + 1.0, zc - width * 0.5), 0.06, 0.06, _mats["metal"])


func _hole_rails(frame: Transform3D, x0: float, x1: float, zc: float, fy: float) -> void:
	for sz in [-1.0, 1.0]:
		_box(Vector3(x1 - x0, 0.08, 0.08),
			frame * _t3(Vector3((x0 + x1) * 0.5, fy + 1.0, zc + sz * 1.18)),
			_mats["metal"], Color(1, 1, 1), false)
		for px in [x0 + 0.3, (x0 + x1) * 0.5, x1 - 0.3]:
			_box(Vector3(0.07, 1.0, 0.07),
				frame * _t3(Vector3(px, fy + 0.5, zc + sz * 1.18)),
				_mats["metal"], Color(1, 1, 1), false)


# ---------------- ground / streets ----------------

func _ground_rect(x0: float, x1: float, z0: float, z1: float, top_y: float, mat: StandardMaterial3D) -> void:
	var sx := x1 - x0
	var sz := z1 - z0
	_box(Vector3(sx, 0.6, sz),
		_t3(Vector3((x0 + x1) * 0.5, top_y - 0.3, (z0 + z1) * 0.5)),
		mat, _varc(Color(1, 1, 1), 0.05), true)


func _build_ground() -> void:
	_ground_rect(-70, 70, -70, 70, 0.0, _mats["concrete"])


func _road_strip(x0: float, x1: float, z0: float, z1: float) -> void:
	var sx := x1 - x0
	var sz := z1 - z0
	_box(Vector3(sx, 0.08, sz),
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


func _sidewalk(x0: float, x1: float, z0: float, z1: float) -> void:
	_box(Vector3(x1 - x0, 0.18, z1 - z0),
		_t3(Vector3((x0 + x1) * 0.5, 0.02, (z0 + z1) * 0.5)),
		_mats["sidewalk"], _varc(Color(1, 1, 1), 0.05), true)


func _build_streets() -> void:
	# East-west avenue.
	_road_strip(-66, 66, AVE_Z - AVE_HW, AVE_Z + AVE_HW)
	_dashes_x(-64, 64, AVE_Z)
	_sidewalk(-66, 66, AVE_Z - AVE_HW - 3.0, AVE_Z - AVE_HW)
	_sidewalk(-66, 66, AVE_Z + AVE_HW, AVE_Z + AVE_HW + 3.0)
	# North-south street.
	_road_strip(ST_X - ST_HW, ST_X + ST_HW, -66, 66)
	_dashes_z(-64, 64, ST_X)
	_sidewalk(ST_X - ST_HW - 2.5, ST_X - ST_HW, -66, 66)
	_sidewalk(ST_X + ST_HW, ST_X + ST_HW + 2.5, -66, 66)
	# Crosswalk stripes at the intersection.
	for i in range(6):
		_box(Vector3(0.5, 0.02, AVE_HW * 2.0),
			_t3(Vector3(ST_X - 6.5 + float(i) * 1.3, 0.055, AVE_Z)),
			_mats["paint_white"], Color(1, 1, 1), false)


# ---------------- plaza ----------------

func _build_plaza() -> void:
	var px := 30.0
	var pz := 40.0
	# Paved plaza.
	_box(Vector3(26, 0.16, 22), _t3(Vector3(px, 0.0, pz)),
		_mats["paver"], _varc(Color(1, 1, 1), 0.04), true)
	# Fountain: stepped base + tiers + animated water disc.
	var fc := Vector3(px, 0, pz)
	_batch.add_cyl(3.2, 0.9, _t3(fc + Vector3(0, 0.45, 0)), _mats["concrete_dark"], Color(1, 1, 1))
	_batch.add_collider(Vector3(6.0, 0.9, 6.0), _t3(fc + Vector3(0, 0.45, 0)))
	_batch.add_cyl(2.1, 0.7, _t3(fc + Vector3(0, 1.15, 0)), _mats["concrete"], Color(1, 1, 1))
	_batch.add_cyl(1.0, 1.3, _t3(fc + Vector3(0, 1.9, 0)), _mats["trim"], Color(1, 1, 1))
	var water := MeshInstance3D.new()
	water.name = "FountainWater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.6, 5.6)
	water.mesh = pm
	water.position = fc + Vector3(0, 0.95, 0)
	var wshader := load("res://shaders/water.gdshader") as Shader
	var wmat := ShaderMaterial.new()
	wmat.shader = wshader
	water.material_override = wmat
	add_child(water)
	# Benches + planters around the fountain.
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var bp := fc + Vector3(cos(a) * 7.5, 0, sin(a) * 7.5)
		var bf := Transform3D(Basis(Vector3.UP, -a + PI * 0.5), bp)
		_box(Vector3(2.2, 0.12, 0.55), bf * _t3(Vector3(0, 0.55, 0)), _mats["door_wood"], Color(1, 1, 1), true)
		for lx in [-0.9, 0.9]:
			_box(Vector3(0.12, 0.55, 0.5), bf * _t3(Vector3(lx, 0.27, 0)), _mats["concrete_dark"], Color(1, 1, 1), true)
	for i in range(6):
		var a2 := TAU * float(i) / 6.0
		_planter(fc + Vector3(cos(a2) * 10.5, 0.08, sin(a2) * 9.0))
	# Plaza lamps.
	for lx in [-9.0, 9.0]:
		_streetlight(Vector3(px + lx, 0, pz - 8.5), 0.0, 6.0)
		_streetlight(Vector3(px + lx, 0, pz + 8.5), PI, 6.0)
	_label("NOVA PLAZA", Vector3(px, 3.4, pz - 10.5), 0.0, 0.55, Color(1.0, 0.85, 0.4))


# ---------------- towers ----------------

func _build_tower(cx: float, cz: float, yaw: float, floors: int, w: float, d: float,
		tint: Color, tname: String, helipad: bool, rich: bool) -> void:
	var t := 0.25
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0, cz))
	var col := _varc(Color(1, 1, 1), 0.05)
	var fcol := _varc(tint, 0.08)
	_slab(frame, w + 0.6, d + 0.6, 0.02)
	# Corner fins, full height.
	for fx in [-1.0, 1.0]:
		for fz in [-1.0, 1.0]:
			_box(Vector3(0.5, FH * float(floors), 0.5),
				frame * _t3(Vector3(fx * (w * 0.5 + 0.12), FH * float(floors) * 0.5, fz * (d * 0.5 + 0.12))),
				_mats["trim"], col, false)
	# Lobby (floor 0): glass front with double door.
	var front := frame * _t3(Vector3(0, 0, d * 0.5))
	_wall_open(front, w, FH, t,
		[[0, 0, 2.6, 3.0], [-w * 0.32, 0.6, w * 0.24, 1.9], [w * 0.32, 0.6, w * 0.24, 1.9]],
		_mats["facade"], fcol, true)
	_trim_opening(front, 0, 0, 2.6, 3.0, t)
	_signboard(frame * _t3(Vector3(0, 0, d * 0.5)), w * 0.62, FH + 0.45, tname,
		Color(0.15, 0.35, 0.70))
	_window_wall(frame * _t3(Vector3(0, 0, -d * 0.5)), w, FH, t, _mats["facade"], fcol)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)),
		d, FH, t, _mats["facade"], fcol)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)),
		d, FH, t, _mats["facade"], fcol)
	_furnish_lobby(frame, w, d, rich)
	# Switchback stairs: one flight per floor transition, alternating direction.
	var x0 := -w * 0.5 + 1.0
	var run := w - 2.0
	var zc := -d * 0.5 + 1.5
	for tr in range(floors - 1):
		var ya := FH * float(tr)
		var yb := FH * float(tr + 1)
		if tr % 2 == 0:
			_stairs2(frame, x0, x0 + run, zc, ya, yb, 1.8)
		else:
			_stairs2(frame, x0 + run, x0, zc, ya, yb, 1.8)
	# Upper floors.
	for f in range(1, floors):
		var fy := FH * float(f)
		_slab_hole(frame, w, d, fy, x0, x0 + run, zc, 2.2)
		_hole_rails(frame, x0, x0 + run, zc, fy)
		_window_wall(frame * _t3(Vector3(0, fy, d * 0.5)), w, FH, t, _mats["facade"], fcol)
		_window_wall(frame * _t3(Vector3(0, fy, -d * 0.5)), w, FH, t, _mats["facade"], fcol)
		_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, fy, 0)),
			d, FH, t, _mats["facade"], fcol)
		_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, fy, 0)),
			d, FH, t, _mats["facade"], fcol)
		_furnish_office(frame, w, d, fy, x0, x0 + run, zc, rich and (f % 2 == 1))
	# Roof.
	var ry := FH * float(floors)
	_slab_hole(frame, w, d, ry, x0, x0 + run, zc, 2.2)
	_hole_rails(frame, x0, x0 + run, zc, ry)
	for px in [-1.0, 1.0]:
		_box(Vector3(w + 0.25, 1.1, 0.22), frame * _t3(Vector3(0, ry + 0.55, px * d * 0.5)),
			_mats["trim"], col, true)
		_box(Vector3(0.22, 1.1, d + 0.25), frame * _t3(Vector3(px * w * 0.5, ry + 0.55, 0)),
			_mats["trim"], col, true)
	for i in range(3):
		var ap: Vector3 = frame * Vector3(-w * 0.3 + float(i) * w * 0.28, 0, d * 0.18)
		_box(Vector3(1.2, 0.9, 0.9), _t3(Vector3(ap.x, ry + 0.45, ap.z)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.1), true)
	_batch.add_cyl(0.5, 1.6, frame * _t3(Vector3(w * 0.3, ry + 0.8, -d * 0.25)),
		_mats["metal"], Color(1, 1, 1))
	_batch.add_collider(Vector3(1.0, 1.6, 1.0), frame * _t3(Vector3(w * 0.3, ry + 0.8, -d * 0.25)))
	if helipad:
		var hp: Vector3 = frame * Vector3(0, 0, d * 0.10)
		_batch.add_cyl(4.2, 0.14, _t3(Vector3(hp.x, ry + 0.07, hp.z)), _mats["helipad"], Color(1, 1, 1))
		_batch.add_collider(Vector3(7.6, 0.2, 7.6), _t3(Vector3(hp.x, ry + 0.05, hp.z)))
		# Painted "H" from boxes.
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.5, 0.03, 2.4), _t3(Vector3(hp.x + sx * 0.9, ry + 0.16, hp.z)),
				_mats["paint_yellow"], Color(1, 1, 1), false)
		_box(Vector3(2.3, 0.03, 0.5), _t3(Vector3(hp.x, ry + 0.16, hp.z)),
			_mats["paint_yellow"], Color(1, 1, 1), false)
		for k in range(4):
			var a := TAU * float(k) / 4.0 + PI * 0.25
			_box(Vector3(0.3, 0.18, 0.3),
				_t3(Vector3(hp.x + cos(a) * 4.6, ry + 0.1, hp.z + sin(a) * 4.6)),
				_mats["lamp_head"], Color(1, 1, 1), false)
	# Rooftop loot (kept clear of the stairwell hole, in local space).
	var rloot := 3 if rich else 1
	for i in range(rloot):
		var rlx := _rng.randf_range(-w * 0.3, w * 0.3)
		var rlz := _rng.randf_range(-d * 0.28, d * 0.28)
		if rlx > x0 - 0.8 and rlx < x0 + run + 0.8 and absf(rlz - zc) < 1.6:
			rlz = zc + 3.4
		var rp: Vector3 = frame * Vector3(rlx, 0, rlz)
		_add_loot(_loot_kind(), Vector3(rp.x, ry + 0.55, rp.z), true)


func _furnish_lobby(frame: Transform3D, w: float, d: float, rich: bool) -> void:
	var c := _varc(Color(1, 1, 1), 0.08)
	for qx in [-w * 0.3, w * 0.3]:
		_box(Vector3(0.55, FH, 0.55), frame * _t3(Vector3(qx, FH * 0.5, 0)),
			_mats["concrete_dark"], c, true)
	# Reception desk (L).
	_box(Vector3(3.4, 1.1, 0.9), frame * _t3(Vector3(0, 0.55, -d * 0.5 + 1.6)),
		_mats["door_wood"], c, true)
	_box(Vector3(0.9, 1.1, 2.2), frame * _t3(Vector3(1.7, 0.55, -d * 0.5 + 2.6)),
		_mats["door_wood"], c, true)
	# Seating cluster.
	for i in range(4):
		var a := TAU * float(i) / 4.0 + 0.4
		var sp: Vector3 = frame * Vector3(cos(a) * 3.0, 0, 1.6 + sin(a) * 1.7)
		_box(Vector3(0.8, 0.5, 0.8), _t3(Vector3(sp.x, 0.25, sp.z)),
			_mats["sofa"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(1.4, 0.4, 0.8), frame * _t3(Vector3(0, 0.2, 1.6)), _mats["door_wood"], c, true)
	# Ceiling lamp panels.
	for lx in [-w * 0.25, w * 0.25]:
		for lz in [-d * 0.2, d * 0.25]:
			_box(Vector3(1.6, 0.08, 0.9), frame * _t3(Vector3(lx, FH - 0.1, lz)),
				_mats["lamp_head"], Color(1, 1, 1), false)
	# Directory board.
	_box(Vector3(1.8, 1.2, 0.1), frame * _t3(Vector3(-w * 0.5 + 0.6, 1.7, 0)),
		_mats["screen"], Color(1, 1, 1), false)
	var nl := 3 if rich else 1
	for i in range(nl):
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.35, w * 0.35), 0,
			_rng.randf_range(-d * 0.1, d * 0.3))
		_add_loot(_loot_kind(), Vector3(lp.x, 0.55, lp.z), true)


func _furnish_office(frame: Transform3D, w: float, d: float, fy: float,
		hx0: float, hx1: float, zc: float, rich: bool) -> void:
	var c := _varc(Color(1, 1, 1), 0.08)
	# Partition with door gap.
	_wall_open(frame * _t3(Vector3(0, fy, 0.6)), w * 0.7, 2.6, 0.12,
		[[1.2, 0, 1.1, 2.2]], _mats["wall_white"], c, true)
	# Desks with monitors + chairs.
	for i in range(3):
		var dx := -w * 0.28 + float(i) * w * 0.28
		var dz := d * 0.22 if i % 2 == 0 else -d * 0.18
		var df := frame * _t3(Vector3(dx, fy, dz))
		_box(Vector3(1.7, 0.08, 0.85), df * _t3(Vector3(0, 0.76, 0)), _mats["door_wood"], c, false)
		_box(Vector3(1.6, 0.72, 0.75), df * _t3(Vector3(0, 0.36, 0)), _mats["door_wood"], c, true)
		_box(Vector3(0.5, 0.08, 0.5), df * _t3(Vector3(0, 0.5, 0.85)), _mats["concrete_dark"], c, true)
		_box(Vector3(0.5, 0.6, 0.08), df * _t3(Vector3(0, 0.85, 1.08)), _mats["concrete_dark"], c, false)
		_box(Vector3(0.55, 0.36, 0.05),
			df * Transform3D(Basis(Vector3(1, 0, 0), -0.15), Vector3(0, 1.05, -0.15)),
			_mats["screen"], Color(1, 1, 1), false)
	# Filing cabinets along the back.
	for i in range(2):
		_box(Vector3(0.9, 1.4, 0.5),
			frame * _t3(Vector3(-w * 0.32 + float(i) * 1.1, fy + 0.7, -d * 0.5 + 0.6)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.1), true)
	# Ceiling light strips.
	for sx in [-w * 0.22, w * 0.22]:
		_box(Vector3(2.2, 0.06, 0.5), frame * _t3(Vector3(sx, fy + FH - 0.12, 0)),
			_mats["strip_light"], Color(1, 1, 1), false)
	# Office loot (kept clear of the stairwell hole).
	var n := 2 if rich else 1
	for i in range(n):
		var lx := _rng.randf_range(-w * 0.32, w * 0.32)
		var lz := _rng.randf_range(-d * 0.3, d * 0.3)
		if lx > hx0 - 0.6 and lx < hx1 + 0.6 and absf(lz - zc) < 1.5:
			lz = zc + 3.2
		var lp: Vector3 = frame * Vector3(lx, 0, lz)
		_add_loot(_loot_kind(), Vector3(lp.x, fy + 0.55, lp.z), true)


# ---------------- props ----------------

func _streetlight(pos: Vector3, yaw: float, h := 7.5) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_batch.add_cyl(0.13, h, frame * _t3(Vector3(0, h * 0.5, 0)), _mats["pole"], _varc(Color(1, 1, 1), 0.08))
	_batch.add_collider(Vector3(0.3, h, 0.3), frame * _t3(Vector3(0, h * 0.5, 0)))
	_box(Vector3(0.12, 0.12, 2.2), frame * _t3(Vector3(0, h - 0.1, 1.0)), _mats["pole"], Color(1, 1, 1), false)
	_box(Vector3(0.5, 0.22, 0.9), frame * _t3(Vector3(0, h - 0.2, 2.0)), _mats["lamp_head"], Color(1, 1, 1), false)


func _planter(pos: Vector3) -> void:
	_box(Vector3(1.3, 0.65, 1.3), _t3(pos + Vector3(0, 0.32, 0)), _mats["concrete_dark"],
		_varc(Color(1, 1, 1), 0.08), true)
	_box(Vector3(1.0, 0.15, 1.0), _t3(pos + Vector3(0, 0.68, 0)), _mats["soil"], Color(1, 1, 1), false)
	for i in range(3):
		_box(Vector3(0.4, _rng.randf_range(0.5, 0.9), 0.4),
			_t3(pos + Vector3(_rng.randf_range(-0.3, 0.3), 0.9, _rng.randf_range(-0.3, 0.3))),
			_mats["leaf"], _varc(Color(1, 1, 1), 0.15), false)


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
	_box(Vector3(0.08, 0.18, 0.35), frame * _t3(Vector3(2.21, 0.62, -0.6)), _mats["lamp_head"], Color(1, 1, 1), false)
	_box(Vector3(0.08, 0.18, 0.35), frame * _t3(Vector3(2.21, 0.62, 0.6)), _mats["lamp_head"], Color(1, 1, 1), false)


func _barrier(pos: Vector3, yaw: float) -> void:
	_box(Vector3(2.0, 0.8, 0.5), Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.4, 0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
	_box(Vector3(2.0, 0.15, 0.56), Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.87, 0)),
		_mats["paint_yellow"], Color(1, 1, 1), false)


func _build_props() -> void:
	# Streetlights along the avenue (staggered) and the NS street.
	var x := -60.0
	var side := 1.0
	while x < 62.0:
		_streetlight(Vector3(x, 0, AVE_Z + side * (AVE_HW + 1.6)), 0.0 if side > 0.0 else PI)
		side = -side
		x += 16.0
	var z := -56.0
	while z < 60.0:
		_streetlight(Vector3(ST_X - ST_HW - 1.4, 0, z), PI * 0.5)
		_streetlight(Vector3(ST_X + ST_HW + 1.4, 0, z + 10.0), -PI * 0.5)
		z += 24.0
	# Parked cars.
	var car_mats := [_mats["car_a"], _mats["car_b"], _mats["car_c"]]
	var spots := [
		[Vector3(-48, 0, AVE_Z - AVE_HW + 1.7), 0.0], [Vector3(-24, 0, AVE_Z + AVE_HW - 1.7), PI],
		[Vector3(4, 0, AVE_Z - AVE_HW + 1.7), 0.0], [Vector3(44, 0, AVE_Z + AVE_HW - 1.7), PI],
		[Vector3(58, 0, AVE_Z - AVE_HW + 1.7), 0.0], [Vector3(ST_X - ST_HW + 1.5, 0, -30), PI * 0.5],
		[Vector3(ST_X + ST_HW - 1.5, 0, 28), -PI * 0.5],
	]
	for i in range(spots.size()):
		var sp: Array = spots[i]
		_car(sp[0], sp[1], car_mats[i % 3])
	# Planters along sidewalks.
	for i in range(10):
		var px := -55.0 + float(i) * 12.0
		_planter(Vector3(px, 0.12, AVE_Z + AVE_HW + 1.5))
		_planter(Vector3(px + 6.0, 0.12, AVE_Z - AVE_HW - 1.5))
	# Concrete barriers guarding the plaza corners.
	_barrier(Vector3(16, 0, 28), 0.3)
	_barrier(Vector3(44, 0, 28), -0.3)
	_barrier(Vector3(16, 0, 52), -0.3)
	_barrier(Vector3(44, 0, 52), 0.3)
	# Crates near towers (cover).
	for i in range(12):
		var td: Dictionary = TOWERS[_rng.randi_range(0, TOWERS.size() - 1)]
		var a := _rng.randf() * TAU
		var p := Vector3(float(td["x"]) + cos(a) * _rng.randf_range(10.0, 14.0), 0,
			float(td["z"]) + sin(a) * _rng.randf_range(10.0, 14.0))
		if absf(p.x) > 63.0 or absf(p.z) > 63.0:
			continue
		if absf(p.z - AVE_Z) < AVE_HW + 1.0 and absf(p.x) < 66.0:
			continue
		if absf(p.x - ST_X) < ST_HW + 1.0:
			continue
		var s := _rng.randf_range(1.0, 1.5)
		_box(Vector3(s, s, s), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p + Vector3(0, s * 0.5, 0)),
			_mats["door_wood"], _varc(Color(1, 1, 1), 0.12), true)


# ---------------- POIs / loot ----------------

func _on_road(p: Vector3) -> bool:
	if absf(p.z - AVE_Z) < AVE_HW + 1.0 and absf(p.x) < 68.0:
		return true
	if absf(p.x - ST_X) < ST_HW + 1.0:
		return true
	return false


func _near_tower(p: Vector3, gap: float) -> bool:
	for td in TOWERS:
		if absf(float(td["x"]) - p.x) < float(td["w"]) * 0.5 + gap \
				and absf(float(td["z"]) - p.z) < float(td["d"]) * 0.5 + gap:
			return true
	return false


func _build_pois() -> void:
	var defs := [
		{"name": "Nova Tower", "pos": Vector3(-40, 0, -32)},
		{"name": "Plaza", "pos": Vector3(30, 0, 40)},
		{"name": "Rooftop Row", "pos": Vector3(-40, FH * 9.0, -32)},
	]
	for dd in defs:
		poi_list.append({"name": String(dd["name"]), "pos": dd["pos"]})
		var pp: Vector3 = dd["pos"]
		for i in range(4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, 7.0)
			_add_loot(_loot_kind(), pp + Vector3(cos(a) * r, 0.55, sin(a) * r), false)


func _scatter_loot() -> void:
	# Top up to ~85 loot spots at valid outdoor positions.
	var want := 85
	var attempts := 0
	while loot_spots.size() < want and attempts < 600:
		attempts += 1
		var p := Vector3(_rng.randf_range(-62.0, 62.0), 0, _rng.randf_range(-62.0, 62.0))
		if _on_road(p):
			continue
		if _near_tower(p, 1.5):
			continue
		if Vector2(p.x - 30.0, p.z - 40.0).length() < 14.0:
			continue  # plaza handled separately
		_add_loot(_loot_kind(), Vector3(p.x, 0.55, p.z), false)


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
		Vector3(-8, 0.6, 8), Vector3(20, 0.6, 8), Vector3(48, 0.6, 8),
		Vector3(30, 0.6, 30), Vector3(-40, 0.6, -18), Vector3(-20, 0.6, 42),
	]
	print("Downtown built: towers=", TOWERS.size(), " instances=", instance_total,
		" draws=", draw_calls, " colliders=", collider_total,
		" loot=", loot_spots.size(), " indoor_loot=", indoor_loot_count,
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 160.0:
			cn.position.x = -160.0
