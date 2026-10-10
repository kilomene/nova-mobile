extends Node3D
class_name BananaIslandMap
## Phase 5: Banana Island — luxury waterfront district.
## Grand modern mansions with pools and manicured lawns, palm-lined boulevard,
## waterfront promenade with marina + yachts, Sky Villa glass tower landmark,
## yacht club, helipad, fountain plaza. Seeded procedural (SEED),
## merge-ready 140x140m.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261012
const WATER_Y := -0.30

# Layout (world units, meters).
const BLVD_Z := -10.0   # palm-lined boulevard (east-west)
const BLVD_HW := 5.0
const ST_A := -30.0      # north-south streets
const ST_B := 30.0
const ST_HW := 3.5
# Water: z in [38, 70] (lagoon). Promenade deck: z in [30, 38].

var player_spawn := Vector3(-54, 0.6, -4.0)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # all villas (API compat with tests)
var map_extent := MAP_EXTENT

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _buildings: Array = []  # {"center","yaw","w","d","kind"}
var _clouds: Array = []
var _time := 0.0

const POIS := [
	{"name": "Marina Bay", "pos": Vector3(-38, 0, 40)},
	{"name": "Sky Villa", "pos": Vector3(34, 0, -32)},
	{"name": "Palm Boulevard", "pos": Vector3(0, 0, -10)},
	{"name": "Yacht Club", "pos": Vector3(-50, 0, 21)},
]
const VILLA_NAMES := ["VILLA SERENA", "PALM COURT", "LAGOON HOUSE", "CORAL VILLA",
	"AZURE PALMS", "ROYAL OASIS", "PEARL HOUSE", "SAHARA VILLA",
	"EMERALD COURT", "ONYX PALMS", "IVORY HOUSE", "TOPAZ VILLA"]
const CAR_COLS := [Color(0.08, 0.08, 0.10), Color(0.92, 0.92, 0.94),
	Color(0.65, 0.67, 0.70), Color(0.55, 0.08, 0.08), Color(0.08, 0.15, 0.35),
	Color(0.10, 0.10, 0.12), Color(0.75, 0.75, 0.78)]


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_water()
	_build_streets()
	_build_plaza()
	_build_promenade()
	_build_marina()
	_build_villas()
	_build_tower()
	_build_yacht_club()
	_build_monument()
	_build_helipad()
	_build_pois()
	_build_props()
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


func _make_mats() -> void:
	_mats["concrete"] = _std(Color(0.62, 0.60, 0.57))
	_mats["concrete_dark"] = _std(Color(0.46, 0.45, 0.43))
	_mats["asphalt"] = _std(Color(0.22, 0.22, 0.24), 0.95)
	_mats["plaza"] = _std(Color(0.70, 0.66, 0.60))
	_mats["wall_white"] = _std(Color(0.90, 0.89, 0.86))
	_mats["wall_cream"] = _std(Color(0.85, 0.80, 0.70))
	_mats["wall_grey"] = _std(Color(0.58, 0.59, 0.62))
	_mats["wall_sand"] = _std(Color(0.80, 0.72, 0.58))
	_mats["glass_dark"] = _std(Color(0.10, 0.16, 0.22), 0.12, 0.7)
	_mats["glass_blue"] = _std(Color(0.35, 0.55, 0.70), 0.1, 0.4)
	_mats["trim"] = _std(Color(0.25, 0.24, 0.23))
	_mats["door_dark"] = _std(Color(0.20, 0.16, 0.12))
	_mats["metal"] = _std(Color(0.50, 0.52, 0.55), 0.5, 0.5)
	_mats["pole"] = _std(Color(0.16, 0.16, 0.18), 0.6, 0.4)
	_mats["tire"] = _std(Color(0.08, 0.08, 0.09), 0.95)
	_mats["paint_white"] = _std(Color(0.92, 0.92, 0.90), 0.9)
	_mats["lawn"] = _std(Color(0.22, 0.48, 0.22), 0.95)
	_mats["hedge"] = _std(Color(0.16, 0.38, 0.16), 0.95)
	_mats["pool_water"] = _std(Color(0.15, 0.45, 0.70), 0.15, 0.3)
	_mats["trunk"] = _std(Color(0.42, 0.32, 0.20), 0.95)
	_mats["frond"] = _std(Color(0.18, 0.45, 0.18), 0.9)
	_mats["deck"] = _std(Color(0.55, 0.42, 0.28), 0.85)
	_mats["hull"] = _std(Color(0.94, 0.94, 0.96), 0.35, 0.2)
	_mats["sofa"] = _std(Color(1, 1, 1), 0.85)        # per-instance fabric colors
	_mats["car"] = _std(Color(1, 1, 1), 0.3, 0.5)     # per-instance car colors
	_mats["sign_face"] = _std(Color(1, 1, 1), 0.6)
	var lamp := _std(Color(1.0, 0.95, 0.80), 0.4)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.92, 0.70)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp_head"] = lamp
	var tube := _std(Color(0.95, 0.95, 0.90), 0.4)
	tube.emission_enabled = true
	tube.emission = Color(1.0, 0.98, 0.92)
	tube.emission_energy_multiplier = 1.6
	_mats["tubelight"] = tube


func _varc(c: Color, amt := 0.10) -> Color:
	var f := 1.0 + _rng.randf_range(-amt, amt)
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


func _pick(arr: Array):
	return arr[_rng.randi_range(0, arr.size() - 1)]


# ---------------- batch helpers ----------------

func _t3(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)


func _box(size: Vector3, xform: Transform3D, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	_batch.add_box(size, xform, mat, col)
	if collide:
		_batch.add_collider(size, xform)


func _register(center: Vector3, yaw: float, w: float, d: float, kind: String) -> void:
	_buildings.append({"center": center, "yaw": yaw, "w": w, "d": d, "kind": kind})
	house_positions.append(center)


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


func _stairs_simple(frame: Transform3D, x: float, z: float, rise: float, y_base := 0.0) -> void:
	# Straight stair run along +z at local x, rising from y_base to y_base+rise.
	# Visual steps + one ramp collider (player walks up smoothly). NOTE: the
	# collider tilts about the X axis because the run ascends along +z
	# (the old Z-axis tilt was perpendicular to the steps).
	var run := 4.2
	var steps := 12
	for i in range(steps):
		var sz := z + run * (float(i) + 0.5) / float(steps)
		var sy := y_base + rise * (float(i) + 0.5) / float(steps)
		_box(Vector3(1.4, 0.10, run / float(steps) + 0.06),
			frame * _t3(Vector3(x, sy - 0.05, sz)), _mats["concrete_dark"],
			_varc(Color(1, 1, 1), 0.06), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var ramp := Transform3D(Basis(Vector3(1, 0, 0), -ang),
		frame * Vector3(x, y_base + rise * 0.5 - 0.06, z + run * 0.5))
	_batch.add_collider(Vector3(1.4, 0.12, length), ramp)


func _slab_hole(frame: Transform3D, w: float, d: float, y: float, hx0: float, hx1: float,
		hz: float, hzw: float, t := 0.25) -> void:
	# Floor slab with a rectangular stairwell hole (x from hx0..hx1, z centered hz width hzw).
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


func _label(text: String, pos: Vector3, yaw: float, size_m := 0.5, col := Color.WHITE) -> void:
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


# ---------------- ground / water / streets ----------------

func _ground_rect(x0: float, x1: float, z0: float, z1: float, top_y: float, mat: StandardMaterial3D) -> void:
	var sx := x1 - x0
	var sz := z1 - z0
	_box(Vector3(sx, 0.6, sz),
		_t3(Vector3((x0 + x1) * 0.5, top_y - 0.3, (z0 + z1) * 0.5)),
		mat, _varc(Color(1, 1, 1), 0.05), true)


func _build_ground() -> void:
	# Land mass: everything north of the lagoon (z < 38).
	_ground_rect(-70, 70, -70, 38, 0.0, _mats["concrete"])
	# Perimeter walls (north / east / west; south edge is the seawall + promenade).
	var wh := 2.2
	_box(Vector3(140, wh, 0.5), _t3(Vector3(0, wh * 0.5, -69.0)),
		_mats["wall_sand"], _varc(Color(1, 1, 1), 0.08), true)
	for x in [-69.0, 69.0]:
		_box(Vector3(0.5, wh, 140), _t3(Vector3(x, wh * 0.5, 0)),
			_mats["wall_sand"], _varc(Color(1, 1, 1), 0.08), true)
	# Seawall along the lagoon edge (z = 38), down into the water.
	_box(Vector3(140, 2.4, 0.6), _t3(Vector3(0, -0.9, 38.0)),
		_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), true)


func _build_water() -> void:
	# The lagoon: animated water south of the promenade.
	var water := MeshInstance3D.new()
	water.name = "Lagoon"
	var pm := PlaneMesh.new()
	pm.size = Vector2(340, 132)
	pm.subdivide_width = 48
	pm.subdivide_depth = 20
	water.mesh = pm
	water.position = Vector3(0, WATER_Y, 104.0)
	var wshader := load("res://shaders/water.gdshader") as Shader
	var wmat := ShaderMaterial.new()
	wmat.shader = wshader
	water.material_override = wmat
	add_child(water)


func _road_strip(x0: float, x1: float, z0: float, z1: float) -> void:
	var sx := x1 - x0
	var sz := z1 - z0
	_box(Vector3(sx, 0.08, sz),
		_t3(Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)),
		_mats["asphalt"], _varc(Color(1, 1, 1), 0.07), false)


func _dashes_x(x0: float, x1: float, z: float) -> void:
	var x := x0 + 2.0
	while x < x1 - 1.0:
		_box(Vector3(1.6, 0.02, 0.14), _t3(Vector3(x, 0.055, z)),
			_mats["paint_white"], Color(1, 1, 1), false)
		x += 4.5


func _dashes_z(z0: float, z1: float, x: float) -> void:
	var z := z0 + 2.0
	while z < z1 - 1.0:
		_box(Vector3(0.14, 0.02, 1.6), _t3(Vector3(x, 0.055, z)),
			_mats["paint_white"], Color(1, 1, 1), false)
		z += 4.5


func _build_streets() -> void:
	# Grand boulevard (east-west) + two cross streets.
	_road_strip(-66, 66, BLVD_Z - BLVD_HW, BLVD_Z + BLVD_HW)
	_dashes_x(-64, 64, BLVD_Z)
	_road_strip(ST_A - ST_HW, ST_A + ST_HW, -62, 30)
	_road_strip(ST_B - ST_HW, ST_B + ST_HW, -62, 30)
	_dashes_z(-60, 28, ST_A)
	_dashes_z(-60, 28, ST_B)
	# Sidewalks flanking the boulevard.
	for sz in [-1.0, 1.0]:
		_box(Vector3(132, 0.10, 2.2),
			_t3(Vector3(0, 0.01, BLVD_Z + sz * (BLVD_HW + 1.1))),
			_mats["plaza"], _varc(Color(1, 1, 1), 0.04), false)


func _build_plaza() -> void:
	# Palm Plaza: fountain square north of the boulevard.
	_box(Vector3(28, 0.10, 22), _t3(Vector3(0, -0.01, -34)),
		_mats["plaza"], _varc(Color(1, 1, 1), 0.04), false)
	# Fountain: basin + water + center column.
	_batch.add_cyl(4.2, 0.9, _t3(Vector3(0, 0.45, -34)), _mats["concrete_dark"], Color(1, 1, 1))
	_batch.add_collider(Vector3(8.4, 0.9, 8.4), _t3(Vector3(0, 0.45, -34)))
	_batch.add_cyl(3.7, 0.25, _t3(Vector3(0, 0.75, -34)), _mats["pool_water"], Color(1, 1, 1))
	_batch.add_cyl(0.5, 3.2, _t3(Vector3(0, 1.9, -34)), _mats["concrete"], Color(1, 1, 1))
	_batch.add_cyl(1.4, 0.35, _t3(Vector3(0, 3.5, -34)), _mats["concrete_dark"], Color(1, 1, 1))
	# Benches + planters around the plaza.
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var bp := Vector3(cos(a) * 10.5, 0, -34 + sin(a) * 8.5)
		_box(Vector3(2.0, 0.12, 0.6), _t3(bp + Vector3(0, 0.5, 0)),
			_mats["deck"], _varc(Color(1, 1, 1), 0.08), true)
		for sx in [-0.8, 0.8]:
			_box(Vector3(0.12, 0.5, 0.5), _t3(bp + Vector3(sx, 0.25, 0)),
				_mats["trim"], Color(1, 1, 1), false)
		var pp := Vector3(cos(a + PI * 0.25) * 12.5, 0, -34 + sin(a + PI * 0.25) * 9.5)
		_box(Vector3(1.2, 0.7, 1.2), _t3(pp + Vector3(0, 0.35, 0)),
			_mats["concrete_dark"], Color(1, 1, 1), true)
		_box(Vector3(0.9, 0.6, 0.9), _t3(pp + Vector3(0, 1.0, 0)),
			_mats["hedge"], _varc(Color(1, 1, 1), 0.1), false)


func _build_promenade() -> void:
	# Waterfront promenade deck along the lagoon (z in [30, 38]).
	_box(Vector3(132, 0.16, 8), _t3(Vector3(0, 0.02, 34)),
		_mats["plaza"], _varc(Color(1, 1, 1), 0.04), false)
	# Railing at the water's edge (z = 37.4): posts + two rails, all colliders.
	var px := -65.0
	while px <= 65.0:
		_box(Vector3(0.12, 1.1, 0.12), _t3(Vector3(px, 0.55, 37.4)),
			_mats["metal"], Color(1, 1, 1), true)
		px += 3.0
	_box(Vector3(132, 0.08, 0.08), _t3(Vector3(0, 1.08, 37.4)), _mats["metal"], Color(1, 1, 1), true)
	_box(Vector3(132, 0.06, 0.06), _t3(Vector3(0, 0.62, 37.4)), _mats["metal"], Color(1, 1, 1), false)
	# Upscale promenade lamps.
	px = -60.0
	while px <= 60.0:
		_promenade_lamp(Vector3(px, 0, 31.5))
		px += 15.0


func _promenade_lamp(pos: Vector3) -> void:
	_batch.add_cyl(0.10, 4.6, _t3(pos + Vector3(0, 2.3, 0)), _mats["pole"], Color(1, 1, 1))
	_batch.add_collider(Vector3(0.25, 4.6, 0.25), _t3(pos + Vector3(0, 2.3, 0)))
	_box(Vector3(0.08, 0.08, 1.2), _t3(pos + Vector3(0, 4.55, 0.5)), _mats["pole"], Color(1, 1, 1), false)
	_box(Vector3(0.5, 0.18, 0.9), _t3(pos + Vector3(0, 4.45, 1.0)),
		_mats["lamp_head"], Color(1, 1, 1), false)


# ---------------- marina ----------------

func _dock(x: float, z0: float, z1: float) -> void:
	# Wooden dock finger extending into the lagoon.
	var len := z1 - z0
	_box(Vector3(1.8, 0.18, len), _t3(Vector3(x, 0.12, (z0 + z1) * 0.5)),
		_mats["deck"], _varc(Color(1, 1, 1), 0.08), true)
	var z := z0 + 1.5
	while z < z1:
		for sx in [-0.75, 0.75]:
			_batch.add_cyl(0.14, 2.2, _t3(Vector3(x + sx, -0.9, z)), _mats["trunk"], Color(1, 1, 1))
		z += 4.0


func _yacht(pos: Vector3, yaw: float, hull_col: Color) -> void:
	# Simple luxury yacht: hull + bow taper + glass cabin + mast.
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_box(Vector3(2.6, 1.3, 7.0), frame * _t3(Vector3(0, -0.35, 0)),
		_mats["hull"], hull_col, false)
	var bow := Transform3D(Basis(Vector3(1, 0, 0), -0.45), frame * Vector3(0, -0.35, 4.1))
	_box(Vector3(2.6, 1.3, 2.2), bow, _mats["hull"], hull_col, false)
	_box(Vector3(2.7, 0.18, 7.2), frame * _t3(Vector3(0, 0.36, 0)),
		_mats["deck"], Color(1, 1, 1), false)
	_box(Vector3(2.0, 1.3, 3.2), frame * _t3(Vector3(0, 1.1, -0.6)),
		_mats["glass_blue"], Color(1, 1, 1), false)
	_box(Vector3(2.2, 0.15, 3.4), frame * _t3(Vector3(0, 1.82, -0.6)),
		_mats["hull"], hull_col, false)
	_batch.add_cyl(0.07, 5.0, frame * _t3(Vector3(0, 4.2, 1.4)), _mats["pole"], Color(1, 1, 1))


func _build_marina() -> void:
	# Marina corner: docks + 4 yachts moored in the lagoon.
	_dock(-46.0, 37.5, 50.0)
	_dock(-34.0, 37.5, 50.0)
	_yacht(Vector3(-49.5, -0.15, 46.0), 0.06, Color(0.96, 0.96, 0.98))
	_yacht(Vector3(-42.5, -0.15, 47.5), -0.05, Color(0.90, 0.92, 0.95))
	_yacht(Vector3(-37.5, -0.15, 46.0), 0.04, Color(0.94, 0.94, 0.97))
	_yacht(Vector3(-30.5, -0.15, 47.5), -0.06, Color(0.88, 0.90, 0.94))
	# Mooring bollards on the promenade.
	for bx in [-49.0, -43.0, -37.0, -31.0]:
		_batch.add_cyl(0.16, 0.7, _t3(Vector3(bx, 0.35, 36.6)), _mats["trim"], Color(1, 1, 1))
		_batch.add_collider(Vector3(0.35, 0.7, 0.35), _t3(Vector3(bx, 0.35, 36.6)))


# ---------------- villas ----------------

const _RESERVED := [
	[-66.0, 66.0, -16.0, -4.0],    # boulevard
	[-34.0, -26.0, -62.0, 30.0],   # street A
	[26.0, 34.0, -62.0, 30.0],     # street B
	[-16.0, 16.0, -46.0, -22.0],   # fountain plaza
	[-66.0, 66.0, 28.0, 38.0],     # promenade
	[-70.0, 70.0, 38.0, 70.0],     # lagoon water
	[-56.0, -26.0, 30.0, 52.0],    # marina working area
]

const _VILLA_CANDIDATES := [
	[Vector3(-52, 0, -52), 0.0], [Vector3(55, 0, -52), 0.0],
	[Vector3(-52, 0, -28), 0.0], [Vector3(55, 0, -28), 0.0],
	[Vector3(-52, 0, 12), PI], [Vector3(8, 0, 12), PI],
	[Vector3(55, 0, 12), PI],
]


func _rects_overlap(a: Array, b: Array) -> bool:
	return a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3]


func _build_villas() -> void:
	var placed: Array = []
	# Tower + yacht club plots are reserved first.
	placed.append([26.0, 42.0, -48.0, -32.0])   # Sky Villa tower (actual footprint)
	placed.append([-20.0, -8.0, 18.0, 26.0])    # yacht club (actual footprint)
	var ni := 0
	for cand in _VILLA_CANDIDATES:
		var c: Vector3 = cand[0]
		var yaw: float = cand[1]
		var w := _rng.randf_range(15.0, 18.0)
		var d := _rng.randf_range(13.0, 16.0)
		var plot := [c.x - w * 0.5 - 4.0, c.x + w * 0.5 + 4.0,
			c.z - d * 0.5 - 4.0, c.z + d * 0.5 + 4.0]
		if plot[0] < -69.5 or plot[1] > 69.5 or plot[2] < -69.5 or plot[3] > 69.5:
			continue
		var ok := true
		for r in _RESERVED:
			if _rects_overlap(plot, r):
				ok = false
				break
		if ok:
			for r in placed:
				if _rects_overlap(plot, r):
					ok = false
					break
		if not ok:
			continue
		placed.append(plot)
		_build_villa(c, yaw, w, d, VILLA_NAMES[ni % VILLA_NAMES.size()])
		ni += 1


func _build_villa(center: Vector3, yaw: float, w: float, d: float, vname: String) -> void:
	# Grand modern villa: perimeter wall + gate, lawn, pool, driveway,
	# 2-story glass-front house with furnished luxury interiors.
	var h1 := 3.6
	var h2 := 3.2
	var t := 0.24
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wm: StandardMaterial3D = _pick([_mats["wall_white"], _mats["wall_cream"], _mats["wall_sand"]])
	var col := _varc(Color(1, 1, 1), 0.05)
	var pw := w * 0.5 + 4.0
	var pd := d * 0.5 + 4.0
	# Lawn inside the plot.
	_box(Vector3(pw * 2, 0.06, pd * 2), frame * _t3(Vector3(0, 0.0, 0)),
		_mats["lawn"], _varc(Color(1, 1, 1), 0.08), false)
	# Perimeter wall with a front gate opening (gate on the driveway side).
	var gwh := 1.8
	var gate := 3.2
	_box(Vector3(pw * 2, gwh, t), frame * _t3(Vector3(0, gwh * 0.5, -pd)), wm, col, true)
	_box(Vector3(t, gwh, pd * 2), frame * _t3(Vector3(-pw, gwh * 0.5, 0)), wm, col, true)
	_box(Vector3(t, gwh, pd * 2), frame * _t3(Vector3(pw, gwh * 0.5, 0)), wm, col, true)
	var seg := (pw * 2 - gate) * 0.5
	_box(Vector3(seg, gwh, t), frame * _t3(Vector3(-(gate * 0.5 + seg * 0.5), gwh * 0.5, pd)), wm, col, true)
	_box(Vector3(seg, gwh, t), frame * _t3(Vector3(gate * 0.5 + seg * 0.5, gwh * 0.5, pd)), wm, col, true)
	for gx in [-gate * 0.5, gate * 0.5]:
		_box(Vector3(0.5, 2.4, 0.5), frame * _t3(Vector3(gx, 1.2, pd)), _mats["trim"], col, true)
	# Driveway from gate to the house.
	_box(Vector3(3.4, 0.08, pd - d * 0.5), frame * _t3(Vector3(0, 0.0, (pd + d * 0.5) * 0.5)),
		_mats["asphalt"], _varc(Color(1, 1, 1), 0.06), false)
	# House: ground slab.
	_box(Vector3(w + 0.4, 0.25, d + 0.4), frame * _t3(Vector3(0, -0.105, 0)),
		_mats["concrete"], col, true)
	# Ground floor: front = entrance door + full glass; sides = glass sliders; back solid.
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, h1, t,
		[[0, 0, 1.8, 2.7], [-w * 0.32, 0.7, 2.6, 1.8], [w * 0.32, 0.7, 2.6, 1.8]], wm, col, true)
	for gx2 in [-w * 0.32, w * 0.32]:
		_box(Vector3(2.6, 1.8, 0.08), frame * _t3(Vector3(gx2, 1.6, d * 0.5 - 0.02)),
			_mats["glass_blue"], Color(1, 1, 1), false)
	_wall_open(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), frame * Vector3(w * 0.5, 0, 0)),
		d, h1, t, [[0, 0.7, 3.0, 1.8]], wm, col, true)
	_box(Vector3(3.0, 1.8, 0.08),
		frame * Transform3D(Basis(Vector3.UP, PI * 0.5), frame * Vector3(w * 0.5 - 0.02, 1.6, 0)),
		_mats["glass_blue"], Color(1, 1, 1), false)
	_wall_open(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), frame * Vector3(-w * 0.5, 0, 0)),
		d, h1, t, [[0, 0.7, 3.0, 1.8]], wm, col, true)
	_box(Vector3(3.0, 1.8, 0.08),
		frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), frame * Vector3(-w * 0.5 + 0.02, 1.6, 0)),
		_mats["glass_blue"], Color(1, 1, 1), false)
	_box(Vector3(w, h1, t), frame * _t3(Vector3(0, h1 * 0.5, -d * 0.5)), wm, col, true)
	# Interior tube light.
	_box(Vector3(w * 0.4, 0.08, 0.12), frame * _t3(Vector3(0, h1 - 0.15, 0)),
		_mats["tubelight"], Color(1, 1, 1), false)
	# Mid slab with stairwell hole (the stairs arrive through it).
	var vst_x := w * 0.5 - 1.6
	var vst_z := -d * 0.5 + 1.0
	_slab_hole(frame, w, d, h1 + 0.25, vst_x - 0.7, vst_x + 0.7, vst_z + 2.1, 4.4)
	# Upper floor: window band front + sides, solid back.
	_wall_open(frame * _t3(Vector3(0, h1 + 0.25, d * 0.5)), w, h2, t,
		[[-w * 0.3, 1.0, 2.4, 1.5], [0, 1.0, 2.4, 1.5], [w * 0.3, 1.0, 2.4, 1.5]], wm, col, true)
	for gx3 in [-w * 0.3, 0.0, w * 0.3]:
		_box(Vector3(2.4, 1.5, 0.08), frame * _t3(Vector3(gx3, h1 + 0.25 + 1.75, d * 0.5 - 0.02)),
			_mats["glass_dark"], Color(1, 1, 1), false)
	for sz in [-1.0, 1.0]:
		_wall_open(frame * Transform3D(Basis(Vector3.UP, sz * PI * 0.5), frame * Vector3(sz * w * 0.5, h1 + 0.25, 0)),
			d, h2, t, [[0, 1.0, 2.4, 1.5]], wm, col, true)
	_box(Vector3(w, h2, t), frame * _t3(Vector3(0, h1 + 0.25 + h2 * 0.5, -d * 0.5)), wm, col, true)
	# Roof slab with stairwell hole + stairs from the upper floor (stacked above
	# the ground->upper run): the flat roof is walkable, with a full parapet,
	# rooftop loot, and a lounge chair.
	var ry := h1 + 0.25 + h2
	var rlanding := Vector3(vst_x, h1 + 0.25, vst_z + 4.2)
	var rframe := frame * Transform3D(Basis(Vector3.UP, PI), rlanding)
	_slab_hole(frame, w + 0.3, d + 0.3, ry + 0.22, vst_x - 0.7, vst_x + 0.7, vst_z + 2.1, 4.4, 0.22)
	_stairs_simple(rframe, 0.0, 0.0, h2)
	_box(Vector3(w + 0.3, 0.9, 0.15), frame * _t3(Vector3(0, ry + 0.65, d * 0.5)), wm, col, false)
	_box(Vector3(w + 0.3, 0.9, 0.15), frame * _t3(Vector3(0, ry + 0.65, -d * 0.5)), wm, col, false)
	_box(Vector3(0.15, 0.9, d + 0.3), frame * _t3(Vector3(w * 0.5, ry + 0.65, 0)), wm, col, false)
	_box(Vector3(0.15, 0.9, d + 0.3), frame * _t3(Vector3(-w * 0.5, ry + 0.65, 0)), wm, col, false)
	var rkind: String = _pick(["ammo", "health", "armor"])
	var ramt := 60 if rkind == "ammo" else (40 if rkind == "health" else 50)
	var rlp: Vector3 = frame * Vector3(0.0, ry + 0.22, 1.5)
	loot_spots.append([rkind, ramt, Vector3(rlp.x, ry + 0.77, rlp.z)])
	# Rooftop lounge chair.
	_box(Vector3(0.7, 0.25, 1.8), frame * _t3(Vector3(-w * 0.2, ry + 0.35, 1.5)),
		_mats["deck"], _varc(Color(1, 1, 1), 0.1), true)
	# Balcony: slab + railing on the upper front.
	_box(Vector3(5.0, 0.15, 1.6), frame * _t3(Vector3(0, h1 + 0.32, d * 0.5 + 0.8)), _mats["concrete"], col, true)
	for bx in [-2.4, -1.2, 0.0, 1.2, 2.4]:
		_box(Vector3(0.08, 1.0, 0.08), frame * _t3(Vector3(bx, h1 + 0.9, d * 0.5 + 1.55)), _mats["metal"], col, false)
	_box(Vector3(5.0, 0.08, 0.08), frame * _t3(Vector3(0, h1 + 1.38, d * 0.5 + 1.55)), _mats["metal"], col, false)
	# Stairs to floor 2 along the east wall.
	_stairs_simple(frame, vst_x, vst_z, h1 + 0.25)
	_furnish_villa(frame, w, d, h1, ry)
	# Infinity pool beside the house.
	var ppx := w * 0.5 + 2.6
	_box(Vector3(6.4, 0.5, 4.0), frame * _t3(Vector3(ppx, 0.25, -d * 0.25)),
		_mats["concrete"], col, true)
	_box(Vector3(5.8, 0.12, 3.4), frame * _t3(Vector3(ppx, 0.52, -d * 0.25)),
		_mats["pool_water"], Color(1, 1, 1), false)
	# Poolside loungers + umbrella.
	for i in range(2):
		var lx := ppx - 1.2 + float(i) * 2.4
		_box(Vector3(0.7, 0.25, 1.8), frame * _t3(Vector3(lx, 0.35, -d * 0.25 + 3.4)),
			_mats["deck"], _varc(Color(1, 1, 1), 0.1), true)
		_box(Vector3(0.7, 0.5, 0.5), frame * _t3(Vector3(lx, 0.55, -d * 0.25 + 4.2)),
			_mats["deck"], _varc(Color(1, 1, 1), 0.1), false)
	_umbrella(frame * Vector3(ppx, 0, -d * 0.25 - 3.4),
		_pick([Color(0.92, 0.92, 0.94), Color(0.06, 0.20, 0.45)]))
	# Facade AC units on the solid back wall.
	if _rng.randf() < 0.6:
		for i2 in range(_rng.randi_range(1, 2)):
			_box(Vector3(0.9, 0.6, 0.5),
				frame * _t3(Vector3(_rng.randf_range(-w * 0.3, w * 0.3), h1 + 1.5, -d * 0.5 - 0.32)),
				_mats["metal"], _varc(Color(1, 1, 1), 0.1), false)
	# Name plate at the gate.
	_box(Vector3(3.0, 0.6, 0.12), frame * _t3(Vector3(-gate * 0.5 - 2.2, 2.0, pd)),
		_mats["sign_face"], Color(0.10, 0.16, 0.30), false)
	_label(vname, frame * Vector3(-gate * 0.5 - 2.2, 2.0, pd + 0.1),
		atan2(frame.basis.z.x, frame.basis.z.z), 0.30)
	_register(center, yaw, w, d, "villa")


func _furnish_villa(frame: Transform3D, w: float, d: float, h1: float, ry: float) -> void:
	var c := _varc(Color(1, 1, 1), 0.08)
	var fabric: Color = _pick([Color(0.75, 0.70, 0.62), Color(0.30, 0.42, 0.55),
		Color(0.55, 0.30, 0.28), Color(0.35, 0.45, 0.35)])
	# Living room: L-sofa + coffee table.
	_box(Vector3(3.2, 0.7, 1.1), frame * _t3(Vector3(-w * 0.22, 0.35, d * 0.18)), _mats["sofa"], fabric, true)
	_box(Vector3(1.1, 0.7, 2.4), frame * _t3(Vector3(-w * 0.22 - 1.6, 0.35, d * 0.18 - 0.6)), _mats["sofa"], fabric, true)
	_box(Vector3(1.6, 0.4, 0.9), frame * _t3(Vector3(-w * 0.22, 0.2, d * 0.18 - 1.5)),
		_mats["door_dark"], c, true)
	# Dining: table + 4 chairs.
	_box(Vector3(2.4, 0.12, 1.2), frame * _t3(Vector3(w * 0.2, 0.78, d * 0.15)), _mats["door_dark"], c, true)
	_box(Vector3(0.12, 0.75, 1.1), frame * _t3(Vector3(w * 0.2 - 1.0, 0.375, d * 0.15)), _mats["door_dark"], c, true)
	_box(Vector3(0.12, 0.75, 1.1), frame * _t3(Vector3(w * 0.2 + 1.0, 0.375, d * 0.15)), _mats["door_dark"], c, true)
	for cx in [-0.8, 0.8]:
		for cz in [-0.45, 0.45]:
			_box(Vector3(0.45, 0.08, 0.45), frame * _t3(Vector3(w * 0.2 + cx, 0.5, d * 0.15 + cz * 2.2)),
				_mats["sofa"], fabric, true)
	# Kitchen: counter run along the back wall + wall cabinets.
	_box(Vector3(w * 0.5, 0.95, 0.7), frame * _t3(Vector3(0, 0.475, -d * 0.5 + 0.6)),
		_mats["concrete_dark"], c, true)
	_box(Vector3(w * 0.5, 0.5, 0.5), frame * _t3(Vector3(0, 2.2, -d * 0.5 + 0.5)),
		_mats["door_dark"], c, false)
	# Upstairs: 2 beds + wardrobe.
	for bx in [-w * 0.22, w * 0.22]:
		_box(Vector3(2.2, 0.5, 3.0), frame * _t3(Vector3(bx, h1 + 0.5, -d * 0.18)),
			_mats["door_dark"], c, true)
		_box(Vector3(2.0, 0.25, 2.6), frame * _t3(Vector3(bx, h1 + 0.85, -d * 0.18)),
			_mats["sofa"], Color(0.92, 0.90, 0.86), false)
	_box(Vector3(1.2, 2.0, 0.6), frame * _t3(Vector3(0, h1 + 1.25, -d * 0.5 + 0.5)),
		_mats["door_dark"], c, true)
	# Upstairs ceiling tube light (emissive, no real light cost).
	_box(Vector3(w * 0.35, 0.08, 0.12), frame * _t3(Vector3(0, ry - 0.15, 0)),
		_mats["tubelight"], Color(1, 1, 1), false)
	# Curtain panels flanking the middle upper-front window (fabric, no collider).
	var vfab: Color = _pick([Color(0.85, 0.82, 0.72), Color(0.60, 0.70, 0.75), Color(0.75, 0.65, 0.55)])
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.35, 1.7, 0.1), frame * _t3(Vector3(sx * 1.35, h1 + 2.0, d * 0.5 + 0.12)),
			_mats["wall_cream"], vfab, false)
	# Indoor loot (ground floor).
	for i in range(2):
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), 0.0,
			_rng.randf_range(-d * 0.2, d * 0.2))
		loot_spots.append([kind, amt, Vector3(lp.x, 0.55, lp.z)])


# ---------------- Sky Villa tower ----------------

var _tower_center := Vector3(34, 0, -40)
var _tower_roof_y := 0.0


func _build_tower() -> void:
	# Signature glass tower: 7 stories, lobby, roof pool + helipad.
	var center := _tower_center
	var w := 16.0
	var d := 16.0
	var fh := 3.2
	var floors := 7
	var t := 0.25
	var frame := Transform3D(Basis(), center)
	var col := _varc(Color(1, 1, 1), 0.05)
	_box(Vector3(w + 0.6, 0.3, d + 0.6), frame * _t3(Vector3(0, -0.12, 0)),
		_mats["concrete"], col, true)
	var y := 0.0
	# Lobby floor (taller) with glass entrance.
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, 4.2, t,
		[[0, 0, 3.4, 3.2], [-w * 0.32, 0.8, 2.6, 2.2], [w * 0.32, 0.8, 2.6, 2.2]],
		_mats["wall_white"], col, true)
	for gx in [-w * 0.32, w * 0.32]:
		_box(Vector3(2.6, 2.2, 0.08), frame * _t3(Vector3(gx, 1.9, d * 0.5 - 0.02)),
			_mats["glass_blue"], Color(1, 1, 1), false)
	_box(Vector3(w, 4.2, t), frame * _t3(Vector3(0, 2.1, -d * 0.5)), _mats["wall_white"], col, true)
	for sz in [-1.0, 1.0]:
		_wall_open(frame * Transform3D(Basis(Vector3.UP, sz * PI * 0.5), frame * Vector3(sz * w * 0.5, 0, 0)),
			d, 4.2, t, [[0, 0.8, 3.0, 2.2]], _mats["wall_white"], col, true)
	# Reception desk + lobby loot.
	_box(Vector3(3.0, 1.1, 1.0), frame * _t3(Vector3(-3.0, 0.55, -3.0)), _mats["door_dark"], col, true)
	for i in range(3):
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		loot_spots.append([kind, amt, center + Vector3(_rng.randf_range(-6, 6), 0.55, _rng.randf_range(-5, 5))])
	y = 4.2
	_slab_hole(frame, w, d, y + 0.25, w * 0.5 - 2.3, w * 0.5 - 0.9, -d * 0.5 + 3.1, 4.4)
	# Lobby ceiling tube light (emissive, no real light cost).
	_box(Vector3(w * 0.35, 0.08, 0.12), frame * _t3(Vector3(0, y - 0.15, 0)),
		_mats["tubelight"], Color(1, 1, 1), false)
	# Upper floors: slab + glass band on all four sides + corner columns.
	for f in range(1, floors):
		for sz2 in [-1.0, 1.0]:
			_wall_open(frame * _t3(Vector3(0, y + 0.25, sz2 * d * 0.5)), w, fh, t,
				[[-w * 0.3, 0.9, 2.4, 1.6], [0, 0.9, 2.4, 1.6], [w * 0.3, 0.9, 2.4, 1.6]],
				_mats["wall_white"], col, true)
			for gx2 in [-w * 0.3, 0.0, w * 0.3]:
				_box(Vector3(2.4, 1.6, 0.08), frame * _t3(Vector3(gx2, y + 0.25 + 1.7, sz2 * (d * 0.5 - 0.02))),
					_mats["glass_dark"], Color(1, 1, 1), false)
		for sx in [-1.0, 1.0]:
			_wall_open(frame * Transform3D(Basis(Vector3.UP, sx * PI * 0.5), frame * Vector3(sx * w * 0.5, y + 0.25, 0)),
				d, fh, t, [[0, 0.9, 2.4, 1.6]], _mats["wall_white"], col, true)
		y += fh + 0.25
		_box(Vector3(w, 0.25, d), frame * _t3(Vector3(0, y + 0.125, 0)), _mats["concrete"], col, true)
	# Floor 2 interior (enterable unit): sofa + bed + kitchenette + loot.
	var fy := 4.45
	_box(Vector3(3.0, 0.7, 1.1), frame * _t3(Vector3(-4.0, fy + 0.35, 2.0)), _mats["sofa"],
		Color(0.35, 0.45, 0.35), true)
	_box(Vector3(2.2, 0.5, 3.0), frame * _t3(Vector3(4.0, fy + 0.25, -2.0)), _mats["door_dark"], col, true)
	_box(Vector3(2.0, 0.25, 2.6), frame * _t3(Vector3(4.0, fy + 0.6, -2.0)), _mats["sofa"],
		Color(0.92, 0.90, 0.86), false)
	_stairs_simple(frame, w * 0.5 - 1.6, -d * 0.5 + 1.0, 4.45)
	for i in range(4):
		var kind2: String = _pick(["ammo", "health", "armor"])
		var amt2 := 60 if kind2 == "ammo" else (40 if kind2 == "health" else 50)
		loot_spots.append([kind2, amt2, center + Vector3(_rng.randf_range(-6, 6), fy + 0.55, _rng.randf_range(-5, 5))])
	# Floor 2 ceiling tube light.
	_box(Vector3(w * 0.35, 0.08, 0.12), frame * _t3(Vector3(0, fy + 3.05, 0)),
		_mats["tubelight"], Color(1, 1, 1), false)
	# Roof: parapet + pool + "SKY VILLA" sign. Helipad added by _build_helipad().
	_box(Vector3(w + 0.3, 0.22, d + 0.3), frame * _t3(Vector3(0, y + 0.36, 0)),
		_mats["concrete_dark"], col, true)
	_box(Vector3(w + 0.3, 0.8, 0.15), frame * _t3(Vector3(0, y + 0.85, d * 0.5)), _mats["wall_white"], col, false)
	_box(Vector3(7.0, 0.5, 4.4), frame * _t3(Vector3(-3.4, y + 0.72, 0)),
		_mats["concrete"], col, true)
	_box(Vector3(6.4, 0.12, 3.8), frame * _t3(Vector3(-3.4, y + 1.0, 0)),
		_mats["pool_water"], Color(1, 1, 1), false)
	_box(Vector3(11.0, 1.5, 0.4), frame * _t3(Vector3(0, y + 3.4, d * 0.5 - 0.3)),
		_mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(10.6, 1.2, 0.44), frame * _t3(Vector3(0, y + 3.4, d * 0.5 - 0.3)),
		_mats["sign_face"], Color(0.08, 0.12, 0.30), false)
	_label("SKY VILLA", frame * Vector3(0, y + 3.4, d * 0.5 - 0.02), 0.0, 0.5, Color(1.0, 0.85, 0.3))
	_tower_roof_y = y + 0.47
	_register(center, 0.0, w, d, "tower")


func _build_yacht_club() -> void:
	# Two-story glass clubhouse near the marina.
	var center := Vector3(-14, 0, 22)
	var w := 12.0
	var d := 8.0
	var fh := 3.2
	var t := 0.22
	var frame := Transform3D(Basis(), center)
	var col := _varc(Color(1, 1, 1), 0.05)
	_box(Vector3(w + 0.4, 0.25, d + 0.4), frame * _t3(Vector3(0, -0.105, 0)),
		_mats["concrete"], col, true)
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, fh, t,
		[[0, 0, 3.0, 2.8], [-w * 0.35, 0.8, 2.4, 1.8], [w * 0.35, 0.8, 2.4, 1.8]],
		_mats["wall_white"], col, true)
	for gx in [-w * 0.35, w * 0.35]:
		_box(Vector3(2.4, 1.8, 0.08), frame * _t3(Vector3(gx, 1.7, d * 0.5 - 0.02)),
			_mats["glass_blue"], Color(1, 1, 1), false)
	_box(Vector3(w, fh, t), frame * _t3(Vector3(0, fh * 0.5, -d * 0.5)), _mats["wall_white"], col, true)
	for sz in [-1.0, 1.0]:
		_box(Vector3(t, fh, d), frame * _t3(Vector3(sz * w * 0.5, fh * 0.5, 0)), _mats["wall_white"], col, true)
	_box(Vector3(4.0, 1.0, 1.4), frame * _t3(Vector3(-2.5, 0.5, 0)), _mats["door_dark"], col, true)
	_box(Vector3(w, 0.25, d), frame * _t3(Vector3(0, fh + 0.125, 0)), _mats["concrete"], col, true)
	_box(Vector3(w, 1.4, t), frame * _t3(Vector3(0, fh + 0.25 + 0.7, d * 0.5)), _mats["wall_white"], col, true)
	_box(Vector3(w, 1.4, t), frame * _t3(Vector3(0, fh + 0.25 + 0.7, -d * 0.5)), _mats["wall_white"], col, true)
	_box(Vector3(w + 0.3, 0.22, d + 0.3), frame * _t3(Vector3(0, fh + 0.25 + 1.5, 0)),
		_mats["concrete_dark"], col, true)
	_box(Vector3(9.0, 1.2, 0.4), frame * _t3(Vector3(0, fh + 3.0, d * 0.5 - 0.2)),
		_mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(8.6, 0.95, 0.44), frame * _t3(Vector3(0, fh + 3.0, d * 0.5 - 0.2)),
		_mats["sign_face"], Color(0.06, 0.20, 0.45), false)
	_label("YACHT CLUB", frame * Vector3(0, fh + 3.0, d * 0.5 + 0.08), 0.0, 0.42, Color(1, 1, 1))
	for i in range(4):
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		loot_spots.append([kind, amt, center + Vector3(_rng.randf_range(-4.5, 4.5), 0.55, _rng.randf_range(-2.5, 2.5))])
	_register(center, 0.0, w, d, "yachtclub")


# ---------------- monument / helipad ----------------

func _build_monument() -> void:
	# "BANANA ISLAND" entry monument at the west end of the boulevard.
	var mx := -62.0
	var col := Color(1, 1, 1)
	for sz in [-1.0, 1.0]:
		_box(Vector3(1.0, 6.0, 1.0), _t3(Vector3(mx, 3.0, BLVD_Z + sz * 4.0)),
			_mats["concrete_dark"], col, true)
	_box(Vector3(1.1, 1.6, 10.5), _t3(Vector3(mx, 6.6, BLVD_Z)),
		_mats["concrete_dark"], col, false)
	_box(Vector3(1.14, 1.2, 10.1), _t3(Vector3(mx, 6.6, BLVD_Z)),
		_mats["sign_face"], Color(0.06, 0.20, 0.45), false)
	_label("BANANA ISLAND", Vector3(mx + 0.65, 6.75, BLVD_Z), PI * 0.5, 0.5, Color(1.0, 0.85, 0.3))
	_label("LAGOS' FINEST ADDRESS", Vector3(mx + 0.65, 6.25, BLVD_Z), PI * 0.5, 0.28, Color(1, 1, 1))
	_label("BANANA ISLAND", Vector3(mx - 0.65, 6.75, BLVD_Z), -PI * 0.5, 0.5, Color(1.0, 0.85, 0.3))


func _build_helipad() -> void:
	# Helipad on the Sky Villa roof (real luxury towers have one).
	var c := _tower_center + Vector3(3.4, _tower_roof_y, 0)
	_batch.add_cyl(5.0, 0.16, _t3(c + Vector3(0, 0.08, 0)), _mats["asphalt"], Color(1, 1, 1))
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var rp := c + Vector3(cos(a) * 4.2, 0.18, sin(a) * 4.2)
		var b := Basis(Vector3.UP, -a + PI * 0.5)
		_box(Vector3(1.4, 0.03, 0.3), Transform3D(b, rp), _mats["paint_white"], Color(1, 1, 1), false)
	var h := Label3D.new()
	h.text = "H"
	h.font_size = 96
	h.pixel_size = 0.055
	h.modulate = Color(1.0, 0.85, 0.3)
	h.outline_size = 10
	h.outline_modulate = Color(0, 0, 0, 0.8)
	h.double_sided = true
	h.transform = Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), c + Vector3(0, 0.22, 0))
	add_child(h)


# ---------------- POIs ----------------

func _build_pois() -> void:
	for poi in POIS:
		var pname: String = poi["name"]
		var ppos: Vector3 = poi["pos"]
		poi_list.append({"name": pname, "pos": ppos})
		match pname:
			"Marina Bay":
				_poi_marina(ppos)
			"Sky Villa":
				_poi_skyvilla(ppos)
			"Palm Boulevard":
				_poi_boulevard(ppos)
			"Yacht Club":
				_poi_yachtclub(ppos)
		for i in range(4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, 7.0)
			var kind: String = _pick(["health", "armor", "ammo", "ammo"])
			var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
			loot_spots.append([kind, amt, ppos + Vector3(cos(a) * r, 0.55, sin(a) * r)])


func _poi_marina(ppos: Vector3) -> void:
	# Sign totem + rope fence dressing on the promenade by the docks.
	_box(Vector3(0.4, 4.6, 0.4), _t3(ppos + Vector3(0, 2.3, -2.0)), _mats["pole"], Color(1, 1, 1), true)
	_box(Vector3(3.2, 1.2, 0.25), _t3(ppos + Vector3(0, 4.9, -2.0)),
		_mats["sign_face"], Color(0.06, 0.20, 0.45), false)
	_label("MARINA BAY", ppos + Vector3(0, 4.9, -1.85), 0.0, 0.42, Color(1, 1, 1))


func _poi_skyvilla(ppos: Vector3) -> void:
	# Forecourt: planters + flag poles in front of the tower.
	for i in range(3):
		var pp := ppos + Vector3(-8.0 + i * 8.0, 0, 4.0)
		_box(Vector3(1.4, 0.8, 1.4), _t3(pp + Vector3(0, 0.4, 0)),
			_mats["concrete_dark"], Color(1, 1, 1), true)
		_box(Vector3(1.1, 0.7, 1.1), _t3(pp + Vector3(0, 1.15, 0)),
			_mats["hedge"], _varc(Color(1, 1, 1), 0.1), false)
		_batch.add_cyl(0.06, 6.0, _t3(pp + Vector3(2.2, 3.0, 0)), _mats["pole"], Color(1, 1, 1))
		_box(Vector3(1.1, 0.7, 0.06), _t3(pp + Vector3(2.75, 5.5, 0)),
			_mats["sign_face"], _pick([Color(0.10, 0.35, 0.15), Color(1, 1, 1), Color(0.80, 0.15, 0.12)]), false)


func _poi_boulevard(ppos: Vector3) -> void:
	# Central planter feature on the boulevard.
	_box(Vector3(6.0, 0.8, 2.4), _t3(ppos + Vector3(0, 0.4, 0)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	_box(Vector3(5.6, 0.6, 2.0), _t3(ppos + Vector3(0, 1.1, 0)),
		_mats["hedge"], _varc(Color(1, 1, 1), 0.1), false)
	_palm(ppos + Vector3(-4.5, 0, 0))
	_palm(ppos + Vector3(4.5, 0, 0))


func _poi_yachtclub(ppos: Vector3) -> void:
	# Terrace with umbrellas in front of the clubhouse.
	for i in range(2):
		var up := ppos + Vector3(-3.0 + i * 6.0, 0, 6.5)
		_umbrella(up, _pick([Color(0.92, 0.92, 0.94), Color(0.06, 0.20, 0.45)]))


func _umbrella(pos: Vector3, col: Color) -> void:
	_batch.add_cyl(0.06, 2.3, _t3(pos + Vector3(0, 1.15, 0)), _mats["pole"], _varc(Color(1, 1, 1), 0.08))
	_batch.add_collider(Vector3(0.15, 2.3, 0.15), _t3(pos + Vector3(0, 1.15, 0)))
	_batch.add_cyl(1.7, 0.14, _t3(pos + Vector3(0, 2.32, 0)), _mats["sign_face"], col)


# ---------------- props ----------------

func _palm(pos: Vector3) -> void:
	var h := _rng.randf_range(4.0, 5.5)
	_batch.add_cyl(0.16, h, _t3(pos + Vector3(0, h * 0.5, 0)),
		_mats["trunk"], _varc(Color(1, 1, 1), 0.1))
	_batch.add_collider(Vector3(0.35, h, 0.35), _t3(pos + Vector3(0, h * 0.5, 0)))
	var top := pos + Vector3(0, h, 0)
	for i in range(5):
		var a := TAU * float(i) / 5.0 + _rng.randf_range(-0.2, 0.2)
		var L := _rng.randf_range(2.2, 2.8)
		var dir := Vector3(cos(a), 0, sin(a))
		var basis := Basis(Vector3.UP, a) * Basis(Vector3(0, 0, 1), -0.5)
		_box(Vector3(L, 0.06, 0.34), Transform3D(basis, top + dir * (L * 0.42) - Vector3(0, 0.35, 0)),
			_mats["frond"], _varc(Color(1, 1, 1), 0.12), false)
	_batch.add_cyl(0.28, 0.35, _t3(top + Vector3(0, 0.1, 0)), _mats["trunk"], Color(1, 1, 1))


func _street_lamp(pos: Vector3) -> void:
	_batch.add_cyl(0.09, 5.6, _t3(pos + Vector3(0, 2.8, 0)), _mats["pole"], Color(1, 1, 1))
	_batch.add_collider(Vector3(0.22, 5.6, 0.22), _t3(pos + Vector3(0, 2.8, 0)))
	_box(Vector3(0.07, 0.07, 1.0), _t3(pos + Vector3(0, 5.55, 0.45)), _mats["pole"], Color(1, 1, 1), false)
	_box(Vector3(0.45, 0.16, 0.7), _t3(pos + Vector3(0, 5.45, 0.85)),
		_mats["lamp_head"], Color(1, 1, 1), false)


func _car(pos: Vector3, yaw: float, col: Color) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_box(Vector3(1.9, 0.75, 4.6), frame * _t3(Vector3(0, 0.68, 0)), _mats["car"], col, true)
	_box(Vector3(1.7, 0.62, 2.4), frame * _t3(Vector3(0, 1.32, -0.2)), _mats["glass_dark"], Color(1, 1, 1), false)
	for sx in [-0.85, 0.85]:
		for sz in [1.5, -1.5]:
			var wg := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), frame * Vector3(sx, 0.36, sz))
			_batch.add_cyl(0.36, 0.28, wg, _mats["tire"], Color(1, 1, 1))


func _build_props() -> void:
	# Palms along the boulevard (skip street crossings).
	var x := -60.0
	while x <= 60.0:
		if absf(x - ST_A) > 7.0 and absf(x - ST_B) > 7.0:
			_palm(Vector3(x, 0, BLVD_Z - BLVD_HW - 2.4))
			_palm(Vector3(x + 4.0, 0, BLVD_Z + BLVD_HW + 2.4))
		x += 10.0
	# Palms on the promenade (skip the marina working area).
	x = -58.0
	while x <= 62.0:
		if x < -58.0 or x > -24.0:
			_palm(Vector3(x, 0, 31.2))
		x += 12.0
	# Upscale street lamps along the boulevard.
	x = -56.0
	while x <= 56.0:
		if absf(x - ST_A) > 6.0 and absf(x - ST_B) > 6.0:
			_street_lamp(Vector3(x, 0, BLVD_Z - BLVD_HW - 1.2))
		x += 16.0
	# Hedge rows on the boulevard sidewalks.
	x = -58.0
	while x <= 58.0:
		if absf(x - ST_A) > 6.0 and absf(x - ST_B) > 6.0:
			_box(Vector3(3.2, 0.7, 0.8), _t3(Vector3(x, 0.35, BLVD_Z + BLVD_HW + 1.2)),
				_mats["hedge"], _varc(Color(1, 1, 1), 0.1), false)
		x += 6.0
	# Luxury cars: boulevard parking + villa driveways + yacht club.
	_car(Vector3(-40, 0, BLVD_Z + 3.2), 0.03, CAR_COLS[0])
	_car(Vector3(-12, 0, BLVD_Z - 3.2), PI - 0.04, CAR_COLS[1])
	_car(Vector3(18, 0, BLVD_Z + 3.2), -0.02, CAR_COLS[2])
	_car(Vector3(46, 0, BLVD_Z - 3.2), PI + 0.05, CAR_COLS[3])
	_car(Vector3(-52, 0, 6.5), 0.1, CAR_COLS[4])
	_car(Vector3(8, 0, 17.5), PI - 0.08, CAR_COLS[5])
	_car(Vector3(-14, 0, 28.5), 0.06, CAR_COLS[6])
	# Street loot.
	for i in range(18):
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lx := _rng.randf_range(-58.0, 58.0)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var lz := BLVD_Z + side * _rng.randf_range(1.5, BLVD_HW - 1.0)
		loot_spots.append([kind, amt, Vector3(lx, 0.55, lz)])
	for i in range(8):
		var kind2: String = _pick(["ammo", "health", "armor"])
		var amt2 := 60 if kind2 == "ammo" else (40 if kind2 == "health" else 50)
		loot_spots.append([kind2, amt2, Vector3(_rng.randf_range(-58.0, 58.0), 0.55, 33.0)])


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
	var aabb := AABB(Vector3(-85, -6, -85), Vector3(170, 40, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	enemy_spawns = [
		Vector3(-40, 0.6, -10), Vector3(20, 0.6, -10), Vector3(8, 0.6, -26),
		Vector3(-20, 0.6, 33), Vector3(12, 0.6, 33), Vector3(-48, 0.6, 26),
	]
	print("BananaIsland built: buildings=", _buildings.size(), " instances=", _batch.box_count(),
		" draws=", draws, " colliders=", _batch.collider_count(),
		" loot=", loot_spots.size(), " pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 160.0:
			cn.position.x = -160.0
