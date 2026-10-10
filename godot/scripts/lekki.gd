extends Node3D
class_name LekkiMap
## Phase 3: Lekki street map — upscale urban battle-royale map (seeded procedural).
## Wide commercial avenues, shop rows with signage, estate houses, office towers,
## and a cable-stayed bridge landmark over a lagoon channel.
## Self-contained scene: origin at map center, everything inside MAP_EXTENT
## square (merge-ready, same footprint as Makoko).

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261010

# Street layout (world units, meters).
const AVE_Z := 12.0      # main avenue centerline (east-west)
const AVE_HW := 6.0      # avenue half-width
const STB_X := -18.0     # cross street B (north-south)
const STC_X := 38.0      # cross street C (north-south, continues onto bridge)
const ST_HW := 4.5
const RIVER_S := -50.0    # lagoon channel south edge
const RIVER_N := -62.0    # lagoon channel north edge
const WATER_Y := -0.9

var player_spawn := Vector3(10, 0.6, 31.0)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # all buildings (API compat with tests)
var map_extent := MAP_EXTENT

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _buildings: Array = []  # {"center","yaw","w","d","kind"}
var _clouds: Array = []
var _time := 0.0

const POIS := [
	{"name": "Admiralty Mall", "pos": Vector3(-42, 0, 30)},
	{"name": "Estate Gate", "pos": Vector3(48, 0, 40)},
	{"name": "Bridge View", "pos": Vector3(38, 0, -42)},
	{"name": "Market Junction", "pos": Vector3(10, 0, 12)},
]
const SHOP_NAMES := ["MARKET", "PHARMACY", "EATERY", "BANK", "SALON",
	"PLAZA", "STORES", "CAFE", "TECH HUB", "BAKERY", "BARBER", "BOOKS"]


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_streets()
	_build_bridge()
	_build_pois()
	_build_blocks()
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
	_mats["concrete_dark"] = _std(Color(0.45, 0.44, 0.42))
	_mats["asphalt"] = _std(Color(0.23, 0.23, 0.25), 0.95)
	_mats["asphalt_old"] = _std(Color(0.30, 0.30, 0.31), 0.95)
	_mats["sidewalk"] = _std(Color(0.70, 0.68, 0.64))
	_mats["curb"] = _std(Color(0.55, 0.54, 0.51))
	_mats["wall_cream"] = _std(Color(0.82, 0.78, 0.70))
	_mats["wall_white"] = _std(Color(0.88, 0.87, 0.84))
	_mats["wall_terracotta"] = _std(Color(0.72, 0.45, 0.30))
	_mats["wall_grey"] = _std(Color(0.55, 0.57, 0.60))
	_mats["wall_glass"] = _std(Color(0.35, 0.48, 0.58), 0.25, 0.4)
	_mats["glass_dark"] = _std(Color(0.12, 0.16, 0.20), 0.15, 0.6)
	_mats["trim"] = _std(Color(0.30, 0.28, 0.26))
	_mats["roof_grey"] = _std(Color(0.42, 0.42, 0.44), 0.7)
	_mats["roof_red"] = _std(Color(0.55, 0.28, 0.18), 0.7)
	_mats["door_wood"] = _std(Color(0.40, 0.28, 0.16))
	_mats["metal"] = _std(Color(0.50, 0.52, 0.55), 0.5, 0.5)
	_mats["paint_white"] = _std(Color(0.90, 0.90, 0.88), 0.9)
	_mats["paint_yellow"] = _std(Color(0.85, 0.70, 0.15), 0.9)
	_mats["pylon"] = _std(Color(0.85, 0.86, 0.88), 0.6)
	_mats["cable"] = _std(Color(0.92, 0.93, 0.95), 0.4, 0.2)
	_mats["car_body"] = _std(Color(0.75, 0.75, 0.78), 0.35, 0.4)
	_mats["tire"] = _std(Color(0.08, 0.08, 0.09), 0.95)
	_mats["pole"] = _std(Color(0.25, 0.26, 0.28), 0.6, 0.3)
	_mats["leaf"] = _std(Color(0.22, 0.46, 0.20))
	_mats["trunk"] = _std(Color(0.35, 0.26, 0.17))
	_mats["soil"] = _std(Color(0.35, 0.27, 0.18))
	_mats["accent_orange"] = _std(Color(0.90, 0.45, 0.10))
	_mats["accent_blue"] = _std(Color(0.15, 0.35, 0.70))
	_mats["accent_green"] = _std(Color(0.15, 0.55, 0.30))
	_mats["accent_red"] = _std(Color(0.70, 0.18, 0.14))
	_mats["dark"] = _std(Color(0.10, 0.09, 0.08))
	_mats["water_bed"] = _std(Color(0.10, 0.14, 0.16))
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


func _cable(a: Vector3, b: Vector3, r := 0.06) -> void:
	var dv := b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dv.x, dv.z)
	var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
	_batch.add_cyl(r, length, Transform3D(basis, mid), _mats["cable"], Color(1, 1, 1))


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


# ---------------- ground / streets / water ----------------

func _ground_rect(x0: float, x1: float, z0: float, z1: float, top_y: float, mat: StandardMaterial3D) -> void:
	var sx := x1 - x0
	var sz := z1 - z0
	_box(Vector3(sx, 0.6, sz),
		_t3(Vector3((x0 + x1) * 0.5, top_y - 0.3, (z0 + z1) * 0.5)),
		mat, _varc(Color(1, 1, 1), 0.05), true)


func _build_ground() -> void:
	# Main landmass (south of the lagoon channel).
	_ground_rect(-70, 70, RIVER_S, 70, 0.0, _mats["concrete"])
	# North bank promenade strip.
	_ground_rect(-70, 70, -70, RIVER_N, 0.0, _mats["sidewalk"])
	# River bed.
	_box(Vector3(140, 0.4, RIVER_S - RIVER_N),
		_t3(Vector3(0, -1.7, (RIVER_S + RIVER_N) * 0.5)),
		_mats["water_bed"], Color(1, 1, 1), false)
	# Water surface (animated shader, same as Makoko).
	var water := MeshInstance3D.new()
	water.name = "LagoonWater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, RIVER_S - RIVER_N)
	water.mesh = pm
	water.position = Vector3(0, WATER_Y, (RIVER_S + RIVER_N) * 0.5)
	var wshader := load("res://shaders/water.gdshader") as Shader
	var wmat := ShaderMaterial.new()
	wmat.shader = wshader
	water.material_override = wmat
	add_child(water)
	# Retaining parapet walls along both channel edges (gap at bridge x in [34,42]).
	for z_edge in [RIVER_S, RIVER_N]:
		var segs := [[-70.0, 34.0], [42.0, 70.0]]
		for s in segs:
			var w: float = s[1] - s[0]
			_box(Vector3(w, 1.5, 0.4),
				_t3(Vector3((s[0] + s[1]) * 0.5, -0.35, z_edge)),
				_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), true)


func _road_strip(x0: float, x1: float, z0: float, z1: float) -> void:
	# Asphalt ribbon slightly above ground + edge curbs.
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
	# Main avenue (Admiralty Way): east-west.
	_road_strip(-66, 66, AVE_Z - AVE_HW, AVE_Z + AVE_HW)
	_dashes_x(-64, 64, AVE_Z)
	_sidewalk(-66, 66, AVE_Z - AVE_HW - 3.0, AVE_Z - AVE_HW)
	_sidewalk(-66, 66, AVE_Z + AVE_HW, AVE_Z + AVE_HW + 3.0)
	# Cross street B.
	_road_strip(STB_X - ST_HW, STB_X + ST_HW, RIVER_S, 66)
	_dashes_z(RIVER_S + 2, 64, STB_X)
	_sidewalk(STB_X - ST_HW - 2.5, STB_X - ST_HW, RIVER_S, 66)
	_sidewalk(STB_X + ST_HW, STB_X + ST_HW + 2.5, RIVER_S, 66)
	# Cross street C (continues onto the bridge).
	_road_strip(STC_X - ST_HW, STC_X + ST_HW, RIVER_S, 66)
	_dashes_z(RIVER_S + 2, 64, STC_X)
	_sidewalk(STC_X - ST_HW - 2.5, STC_X - ST_HW, RIVER_S, 66)
	_sidewalk(STC_X + ST_HW, STC_X + ST_HW + 2.5, RIVER_S, 66)
	# Central roundabout on the avenue at x=10.
	var rc := Vector3(10, 0, AVE_Z)
	_batch.add_cyl(4.6, 0.35, _t3(rc + Vector3(0, 0.10, 0)),
		_mats["curb"], _varc(Color(1, 1, 1), 0.05))
	_batch.add_collider(Vector3(8.6, 0.5, 8.6), _t3(rc + Vector3(0, 0.1, 0)))
	# Monument: stepped obelisk.
	_box(Vector3(2.2, 0.5, 2.2), _t3(rc + Vector3(0, 0.5, 0)), _mats["concrete_dark"], Color(1, 1, 1), true)
	_box(Vector3(1.4, 3.2, 1.4), _t3(rc + Vector3(0, 2.3, 0)), _mats["wall_cream"], Color(1, 1, 1), true)
	_box(Vector3(0.9, 1.6, 0.9), _t3(rc + Vector3(0, 4.7, 0)), _mats["accent_orange"], Color(1, 1, 1), false)
	# Ring dashes around the island.
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p := rc + Vector3(cos(a) * 7.6, 0.055, sin(a) * 7.6)
		_box(Vector3(1.4, 0.02, 0.16),
			Transform3D(Basis(Vector3.UP, -a), p),
			_mats["paint_white"], Color(1, 1, 1), false)


# ---------------- cable-stayed bridge ----------------

func _build_bridge() -> void:
	var bx := STC_X  # bridge continues street C north across the lagoon
	var z0 := RIVER_N  # -62 north landing
	var z1 := RIVER_S  # -50 south landing
	var deck_w := 7.0
	var mid_z := (z0 + z1) * 0.5
	# Deck (top flush with street level).
	_box(Vector3(deck_w, 0.9, z1 - z0 + 4.0), _t3(Vector3(bx, -0.45, mid_z)),
		_mats["asphalt"], _varc(Color(1, 1, 1), 0.05), true)
	_dashes_z(z0 - 1.0, z1 + 1.0, bx)
	# Deck sidewalks + railings.
	for sx in [-1.0, 1.0]:
		_box(Vector3(1.6, 0.16, z1 - z0 + 4.0),
			_t3(Vector3(bx + sx * (deck_w * 0.5 - 0.8), 0.0, mid_z)),
			_mats["sidewalk"], Color(1, 1, 1), true)
		_box(Vector3(0.25, 1.0, z1 - z0 + 4.0),
			_t3(Vector3(bx + sx * (deck_w * 0.5 - 0.1), 0.5, mid_z)),
			_mats["pylon"], Color(1, 1, 1), true)
	# Pylon: two inclined legs meeting at the top (Lekki-Ikoyi style).
	var top := Vector3(bx, 25.0, mid_z)
	_strut(Vector3(bx - 3.4, 0, mid_z), top + Vector3(-0.5, 0, 0), 1.3, 1.8, _mats["pylon"])
	_strut(Vector3(bx + 3.4, 0, mid_z), top + Vector3(0.5, 0, 0), 1.3, 1.8, _mats["pylon"])
	_box(Vector3(2.6, 3.0, 2.2), _t3(top + Vector3(0, 1.0, 0)), _mats["pylon"], Color(1, 1, 1), false)
	# Pylon base block in the water.
	_box(Vector3(7.0, 2.2, 5.0), _t3(Vector3(bx, -1.4, mid_z)), _mats["concrete_dark"], Color(1, 1, 1), false)
	# Stay cables fanning to the deck (both directions).
	for dz in [-9.5, -6.5, 6.5, 9.5]:
		_cable(top + Vector3(0, -1.0, 0), Vector3(bx, 0.6, mid_z + dz))
	# Blue banner plates on the pylon (like the reference photo).
	_box(Vector3(0.7, 1.6, 0.15), _t3(Vector3(bx - 1.75, 12.0, mid_z)), _mats["accent_blue"], Color(1, 1, 1), false)
	_box(Vector3(0.7, 1.6, 0.15), _t3(Vector3(bx + 1.75, 12.0, mid_z)), _mats["accent_blue"], Color(1, 1, 1), false)
	# Streetlights on the bridge.
	for dz2 in [-7.0, 7.0]:
		_streetlight(Vector3(bx - deck_w * 0.5 + 0.6, 0, mid_z + dz2), 0.0, 5.5)


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
	var tm = _mats["trim"]
	var c := Color(1, 1, 1)
	_box(Vector3(w + 0.24, 0.12, T + 0.08), frame * _t3(Vector3(xc, y0 - 0.02, 0)), tm, c, false)
	_box(Vector3(w + 0.24, 0.12, T + 0.08), frame * _t3(Vector3(xc, y0 + h + 0.02, 0)), tm, c, false)
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc - w * 0.5 - 0.02, y0 + h * 0.5, 0)), tm, c, false)
	_box(Vector3(0.12, h + 0.24, T + 0.08), frame * _t3(Vector3(xc + w * 0.5 + 0.02, y0 + h * 0.5, 0)), tm, c, false)


func _window_wall(frame: Transform3D, W: float, H: float, T: float, mat: StandardMaterial3D, col: Color) -> void:
	# Evenly spaced window band (real see/shoot-through openings).
	var n := maxi(2, int(W / 3.0))
	var holes := []
	for i in range(n):
		var xc := -W * 0.5 + W * (float(i) + 0.5) / float(n)
		holes.append([xc, 1.1, 1.4, 1.3])
	_wall_open(frame, W, H, T, holes, mat, col, true)
	for h in holes:
		_trim_opening(frame, h[0], h[1], h[2], h[3], T)
		# dark glass inset set back (looks like glass from outside, still open)
		_box(Vector3(h[2], h[3], 0.04), frame * _t3(Vector3(h[0], h[1] + h[3] * 0.5, -T * 0.5 - 0.25)),
			_mats["glass_dark"], Color(1, 1, 1), false)


func _signboard(frame: Transform3D, w: float, y: float, text: String, col: Color) -> void:
	_box(Vector3(w, 1.0, 0.35), frame * _t3(Vector3(0, y, 0.18)), _mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(w - 0.3, 0.8, 0.38), frame * _t3(Vector3(0, y, 0.18)), _std(col, 0.6), Color(1, 1, 1), false)
	_label(text, frame * Vector3(0, y, 0.42), atan2(frame.basis.z.x, frame.basis.z.z), 0.5)


func _awning(frame: Transform3D, w: float, y: float, col: Color) -> void:
	var local := Transform3D(Basis(Vector3(1, 0, 0), 0.35), Vector3(0, y, 0.75))
	_box(Vector3(w, 0.08, 1.7), frame * local, _std(col, 0.8), Color(1, 1, 1), false)
	for sx in [-1.0, 1.0]:
		_strut(frame * Vector3(sx * w * 0.42, y - 0.75, 0.1),
			frame * Vector3(sx * w * 0.42, y + 0.05, 1.45), 0.05, 0.05, _mats["metal"])


func _slab(frame: Transform3D, w: float, d: float, y: float, t := 0.25) -> void:
	_box(Vector3(w, t, d), frame * _t3(Vector3(0, y - t * 0.5, 0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.05), true)


func _ceiling_light(frame: Transform3D, x: float, y: float, z: float, w: float) -> void:
	# Emissive ceiling light panel + trim housing (cheap, no real light cost).
	_box(Vector3(w, 0.08, 0.14), frame * _t3(Vector3(x, y, z)),
		_mats["tubelight"], Color(1, 1, 1), false)
	_box(Vector3(w + 0.12, 0.05, 0.24), frame * _t3(Vector3(x, y + 0.06, z)),
		_mats["trim"], Color(1, 1, 1), false)


func _slab_hole(frame: Transform3D, w: float, d: float, y: float, hx0: float, hx1: float, hz: float, hzw: float) -> void:
	# Floor slab with a rectangular stairwell hole (x from hx0..hx1, z centered hz width hzw).
	var t := 0.25
	var y0 := y - t * 0.5
	# Strips left/right of the hole (full depth).
	if hx0 > -w * 0.5 + 0.05:
		var sw := hx0 + w * 0.5
		_box(Vector3(sw, t, d), frame * _t3(Vector3(-w * 0.5 + sw * 0.5, y0, 0)),
			_mats["concrete"], Color(1, 1, 1), true)
	if w * 0.5 - hx1 > 0.05:
		var sw2 := w * 0.5 - hx1
		_box(Vector3(sw2, t, d), frame * _t3(Vector3(hx1 + sw2 * 0.5, y0, 0)),
			_mats["concrete"], Color(1, 1, 1), true)
	# Strips front/back of the hole (hole width only).
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
	# Handrail.
	_strut(frame * Vector3(x0, y_base + 1.0, zc - width * 0.5),
		frame * Vector3(x0 + run, y_base + rise + 1.0, zc - width * 0.5), 0.06, 0.06, _mats["metal"])


# ---------------- buildings ----------------

func _register(center: Vector3, yaw: float, w: float, d: float, kind: String) -> void:
	_buildings.append({"center": center, "yaw": yaw, "w": w, "d": d, "kind": kind})
	house_positions.append(center)


func _face_street(p: Vector3) -> float:
	var d_ave := absf(p.z - AVE_Z)
	var d_b := absf(p.x - STB_X) if p.z > RIVER_S else 1.0e9
	var d_c := absf(p.x - STC_X) if p.z > RIVER_S else 1.0e9
	if d_ave <= d_b and d_ave <= d_c:
		return 0.0 if p.z < AVE_Z else PI
	if d_b <= d_c:
		return -PI * 0.5 if p.x > STB_X else PI * 0.5
	return -PI * 0.5 if p.x > STC_X else PI * 0.5


func _build_shop(center: Vector3, yaw: float) -> void:
	# Two-story commercial: shopfront at street level, offices above. Fully enterable.
	var w := _rng.randf_range(8.0, 13.0)
	var d := _rng.randf_range(6.0, 7.5)
	var fh := 3.4  # floor height
	var t := 0.22
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wall_mat: StandardMaterial3D = _pick([_mats["wall_cream"], _mats["wall_white"], _mats["wall_terracotta"]])
	var col := _varc(Color(1, 1, 1), 0.07)
	# Ground slab.
	_slab(frame, w + 0.5, d + 0.5, 0.02)
	# Ground floor front: shopfront (door + wide display windows).
	var front_z := frame * _t3(Vector3(0, 0, d * 0.5))
	_wall_open(front_z, w, fh, t, [[0, 0, 1.9, 2.7], [-w * 0.30, 0.85, w * 0.30, 1.7], [w * 0.30, 0.85, w * 0.30, 1.7]],
		wall_mat, col, true)
	_trim_opening(front_z, 0, 0, 1.9, 2.7, t)
	# Signboard + awning above the shopfront.
	var sname: String = _pick(SHOP_NAMES)
	var scol: Color = _pick([_mats["accent_red"], _mats["accent_blue"], _mats["accent_green"], _mats["accent_orange"]]).albedo_color
	_signboard(frame * _t3(Vector3(0, 0, d * 0.5)), w * 0.8, fh + 0.35, sname, scol)
	_awning(frame * _t3(Vector3(0, 0, d * 0.5)), w * 0.9, 2.95, _pick([Color(0.75, 0.25, 0.15), Color(0.15, 0.35, 0.65), Color(0.85, 0.75, 0.25)]))
	# Other ground walls: windows.
	_window_wall(frame * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)), d, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)), d, fh, t, wall_mat, col)
	# Upper floor slab with stairwell hole (stairs along back-left).
	var sx0 := -w * 0.5 + 0.6
	var srun := 3.6
	var swd := 1.5
	_slab_hole(frame, w, d, fh, sx0, sx0 + srun, -d * 0.5 + 1.6, swd)
	_stairs(frame, sx0, srun, swd, -d * 0.5 + 1.6, fh)
	# Upper floor: window bands + corner boards.
	_window_wall(frame * _t3(Vector3(0, fh, d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * _t3(Vector3(0, fh, -d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, fh, 0)), d, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, fh, 0)), d, fh, t, wall_mat, col)
	# Roof: parapet + AC units. Roof slab has a stairwell hole: stairs from
	# floor 2 reach the roof (parapet already surrounds it).
	_box(Vector3(w + 0.3, 0.9, 0.25), frame * _t3(Vector3(0, fh * 2 + 0.45, d * 0.5)), _mats["trim"], col, false)
	_box(Vector3(w + 0.3, 0.9, 0.25), frame * _t3(Vector3(0, fh * 2 + 0.45, -d * 0.5)), _mats["trim"], col, false)
	_box(Vector3(0.25, 0.9, d), frame * _t3(Vector3(w * 0.5, fh * 2 + 0.45, 0)), _mats["trim"], col, false)
	_box(Vector3(0.25, 0.9, d), frame * _t3(Vector3(-w * 0.5, fh * 2 + 0.45, 0)), _mats["trim"], col, false)
	var rsx0 := w * 0.5 - 0.6 - 3.6
	_slab_hole(frame, w, d, fh * 2, rsx0, rsx0 + 3.6, -d * 0.5 + 1.6, 1.5)
	_stairs(frame, rsx0, 3.6, 1.5, -d * 0.5 + 1.6, fh, fh)
	_ceiling_light(frame, 0, fh - 0.29, 0, w * 0.5)
	_ceiling_light(frame, 0, fh * 2 - 0.29, 0, w * 0.5)
	# Rooftop loot.
	var rkind: String = _pick(["ammo", "health", "armor"])
	var ramt := 60 if rkind == "ammo" else (40 if rkind == "health" else 50)
	var rlp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), fh * 2,
		_rng.randf_range(-d * 0.3, d * 0.3))
	loot_spots.append([rkind, ramt, Vector3(rlp.x, fh * 2 + 0.55, rlp.z)])
	for i in range(_rng.randi_range(1, 2)):
		_box(Vector3(1.1, 0.8, 0.8),
			frame * _t3(Vector3(_rng.randf_range(-w * 0.3, w * 0.3), fh * 2 + 0.4, _rng.randf_range(-d * 0.25, d * 0.25))),
			_mats["metal"], _varc(Color(1, 1, 1), 0.1), true)
	_furnish_shop(frame, w, d)
	_furnish_upstairs(frame, w, d, fh)
	_register(center, yaw, w, d, "shop")


func _build_house(center: Vector3, yaw: float) -> void:
	# Two-story modern estate house with compound wall. Fully enterable.
	var w := _rng.randf_range(7.0, 9.5)
	var d := _rng.randf_range(7.0, 9.5)
	var fh := 3.1
	var t := 0.22
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wall_mat: StandardMaterial3D = _pick([_mats["wall_cream"], _mats["wall_white"], _mats["wall_grey"]])
	var col := _varc(Color(1, 1, 1), 0.07)
	# Compound wall with gate opening on the street side (+z local faces street).
	var pw := w + 7.0
	var pd := d + 7.0
	var wh := 1.25
	var gate_w := 3.0
	_wall_open(frame * _t3(Vector3(0, 0, pd * 0.5)), pw, wh, 0.18, [[0, 0, gate_w, wh]], _mats["wall_terracotta"], col, true)
	_box(Vector3(0.5, 2.2, 0.5), frame * _t3(Vector3(-gate_w * 0.5 - 0.25, 1.1, pd * 0.5)), _mats["trim"], col, true)
	_box(Vector3(0.5, 2.2, 0.5), frame * _t3(Vector3(gate_w * 0.5 + 0.25, 1.1, pd * 0.5)), _mats["trim"], col, true)
	_wall_open(frame * _t3(Vector3(0, 0, -pd * 0.5)), pw, wh, 0.18, [], _mats["wall_terracotta"], col, true)
	for sx in [-1.0, 1.0]:
		var side := frame * Transform3D(Basis(Vector3.UP, sx * PI * 0.5), Vector3(sx * pw * 0.5, 0, 0))
		_wall_open(side, pd, wh, 0.18, [], _mats["wall_terracotta"], col, true)
	# House proper.
	_slab(frame, w + 0.4, d + 0.4, 0.02)
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, fh, t, [[0, 0, 1.3, 2.4], [-w * 0.28, 1.0, 1.5, 1.3], [w * 0.28, 1.0, 1.5, 1.3]],
		wall_mat, col, true)
	_trim_opening(frame * _t3(Vector3(0, 0, d * 0.5)), 0, 0, 1.3, 2.4, t)
	_window_wall(frame * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)), d, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)), d, fh, t, wall_mat, col)
	# Stairs + upper slab.
	var sx0 := -w * 0.5 + 0.6
	_slab_hole(frame, w, d, fh, sx0, sx0 + 3.4, -d * 0.5 + 1.6, 1.4)
	_stairs(frame, sx0, 3.4, 1.4, -d * 0.5 + 1.6, fh)
	# Upper floor + balcony on the street face.
	_window_wall(frame * _t3(Vector3(0, fh, d * 0.5)), w, fh, t, wall_mat, col)
	# Curtain panels flanking the upper front windows (fabric, no collider).
	var nwin := maxi(2, int(w / 3.0))
	var fabric: Color = _pick([Color(0.75, 0.70, 0.60), Color(0.55, 0.35, 0.30), Color(0.35, 0.45, 0.55)])
	for i in range(nwin):
		var wxc := -w * 0.5 + w * (float(i) + 0.5) / float(nwin)
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.3, 1.5, 0.08),
				frame * _t3(Vector3(wxc + sx * 0.85, fh + 1.75, d * 0.5 + 0.14)),
				_mats["wall_cream"], fabric, false)
	# Facade AC unit on the upper front.
	if _rng.randf() < 0.6:
		_box(Vector3(0.9, 0.6, 0.5),
			frame * _t3(Vector3(_rng.randf_range(-w * 0.3, w * 0.3), fh + 1.35, d * 0.5 + 0.32)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.1), false)
	_ceiling_light(frame, 0, fh - 0.29, 0, w * 0.45)
	_ceiling_light(frame, 0, fh * 2 - 0.29, 0, w * 0.45)
	_window_wall(frame * _t3(Vector3(0, fh, -d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, fh, 0)), d, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, fh, 0)), d, fh, t, wall_mat, col)
	_box(Vector3(w * 0.7, 0.15, 1.6), frame * _t3(Vector3(0, fh + 0.08, d * 0.5 + 0.8)), _mats["concrete_dark"], col, true)
	for bx2 in [-w * 0.35, 0.0, w * 0.35]:
		_box(Vector3(0.08, 0.9, 0.08), frame * _t3(Vector3(bx2, fh + 0.6, d * 0.5 + 1.55)), _mats["metal"], col, false)
	_box(Vector3(w * 0.7, 0.08, 0.08), frame * _t3(Vector3(0, fh + 1.05, d * 0.5 + 1.55)), _mats["metal"], col, false)
	# Gable roof (concrete tile red).
	_roof_gable(frame, w, d, fh * 2)
	_furnish_home(frame, w, d)
	_furnish_upstairs(frame, w, d, fh)
	_register(center, yaw, w, d, "house")


func _roof_gable(frame: Transform3D, w: float, d: float, base_y: float) -> void:
	var rise := _rng.randf_range(1.2, 1.7)
	var run := d * 0.5 + 0.5
	var slope := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var rc := _varc(_pick([_mats["roof_red"], _mats["roof_grey"]]).albedo_color, 0.08)
	for sgn in [1.0, -1.0]:
		var local := Transform3D(Basis(Vector3(1, 0, 0), sgn * ang), Vector3(0, base_y + rise * 0.5, sgn * run * 0.5))
		_box(Vector3(w + 0.8, 0.14, slope + 0.2), frame * local, _mats["roof_red"], rc, false)
	_box(Vector3(w + 0.8, 0.16, 0.5), frame * _t3(Vector3(0, base_y + rise + 0.02, 0)), _mats["trim"], rc, false)
	# Gable end triangles (filled with wall boxes stepped).
	for sgn2 in [1.0, -1.0]:
		for i in range(4):
			var f := float(i) / 4.0
			var ww := w * (1.0 - f) - 0.3
			if ww < 0.4:
				continue
			_box(Vector3(ww, rise * 0.26, 0.18),
				frame * _t3(Vector3(0, base_y + rise * f + rise * 0.12, sgn2 * (d * 0.5 - 0.05 - f * 0.4)) ),
				_mats["wall_cream"], rc, false)


func _build_tower(center: Vector3, yaw: float) -> void:
	# 4-5 story office block: grand enterable lobby + stairs to floor 2; facade above.
	var w := _rng.randf_range(10.0, 13.0)
	var d := _rng.randf_range(10.0, 13.0)
	var fh := 3.4
	var t := 0.25
	var floors := _rng.randi_range(4, 5)
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wall_mat: StandardMaterial3D = _pick([_mats["wall_grey"], _mats["wall_white"], _mats["wall_cream"]])
	var col := _varc(Color(1, 1, 1), 0.06)
	_slab(frame, w + 0.6, d + 0.6, 0.02)
	# Lobby: tall glass front.
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, fh + 0.8, t,
		[[0, 0, 2.4, 3.0], [-w * 0.32, 0.7, w * 0.28, 2.2], [w * 0.32, 0.7, w * 0.28, 2.2]],
		wall_mat, col, true)
	_box(Vector3(w * 0.9, 0.5, 0.3), frame * _t3(Vector3(0, fh + 1.05, d * 0.5 + 0.1)),
		_mats["accent_blue"], Color(1, 1, 1), false)
	_label("NOVA TOWER", frame * Vector3(0, fh + 1.05, d * 0.5 + 0.28),
		atan2(frame.basis.z.x, frame.basis.z.z), 0.45)
	_window_wall(frame * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)), d, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)), d, fh, t, wall_mat, col)
	# Lobby columns + reception.
	for cx in [-w * 0.3, w * 0.3]:
		_box(Vector3(0.5, fh, 0.5), frame * _t3(Vector3(cx, fh * 0.5, 0)), _mats["concrete_dark"], col, true)
	_box(Vector3(3.2, 1.1, 0.9), frame * _t3(Vector3(0, 0.55, -d * 0.5 + 1.4)), _mats["door_wood"], col, true)
	_ceiling_light(frame, 0, fh - 0.29, 0, w * 0.5)
	# Stairs to floor 2 along the east wall.
	var sx0 := w * 0.5 - 4.2
	_slab_hole(frame, w, d, fh, sx0, sx0 + 3.6, 0.0, 1.6)
	_stairs(frame, sx0, 3.6, 1.6, 0.0, fh)
	# Floor 2: window bands, enterable.
	_window_wall(frame * _t3(Vector3(0, fh, d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * _t3(Vector3(0, fh, -d * 0.5)), w, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, fh, 0)), d, fh, t, wall_mat, col)
	_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, fh, 0)), d, fh, t, wall_mat, col)
	_ceiling_light(frame, 0, fh * 2 - 0.29, 0, w * 0.5)
	_furnish_upstairs(frame, w, d, fh)
	# Upper facade floors (window bands, sealed).
	for f in range(2, floors):
		var fy := fh * float(f)
		_slab(frame, w, d, fy)
		_window_wall(frame * _t3(Vector3(0, fy, d * 0.5)), w, fh, t, wall_mat, col)
		_window_wall(frame * _t3(Vector3(0, fy, -d * 0.5)), w, fh, t, wall_mat, col)
		_window_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, fy, 0)), d, fh, t, wall_mat, col)
		_window_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, fy, 0)), d, fh, t, wall_mat, col)
	# Roof slab + parapet + plant.
	_slab(frame, w, d, fh * float(floors))
	var ry := fh * float(floors)
	_box(Vector3(w + 0.3, 1.0, 0.25), frame * _t3(Vector3(0, ry + 0.5, d * 0.5)), _mats["trim"], col, false)
	_box(Vector3(w + 0.3, 1.0, 0.25), frame * _t3(Vector3(0, ry + 0.5, -d * 0.5)), _mats["trim"], col, false)
	_box(Vector3(1.6, 1.2, 1.6), frame * _t3(Vector3(-w * 0.25, ry + 0.6, -d * 0.2)), _mats["metal"], col, true)
	_batch.add_cyl(0.9, 2.0, frame * _t3(Vector3(w * 0.25, ry + 1.0, d * 0.2)), _mats["wall_cream"], col)
	_batch.add_collider(Vector3(1.8, 2.0, 1.8), frame * _t3(Vector3(w * 0.25, ry + 1.0, d * 0.2)))
	# Lobby loot.
	for i in range(3):
		var kind: String = _pick(["health", "armor", "ammo"])
		var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.35, w * 0.35), 0.0, _rng.randf_range(-1.0, 2.0))
		loot_spots.append([kind, amt, Vector3(lp.x, 0.55, lp.z)])
	_register(center, yaw, w, d, "tower")


# ---------------- interiors ----------------

func _furnish_shop(frame: Transform3D, w: float, d: float) -> void:
	var c := _varc(Color(1, 1, 1), 0.08)
	# Counter along the back.
	_box(Vector3(w * 0.5, 1.05, 0.7), frame * _t3(Vector3(0, 0.525, -d * 0.5 + 1.2)), _mats["door_wood"], c, true)
	# Shelf rows.
	for sz in [-0.5, 1.2]:
		_box(Vector3(w * 0.55, 0.08, 0.5), frame * _t3(Vector3(0, 1.5, sz)), _mats["door_wood"], c, false)
		for lx in [-1.0, 1.0]:
			_box(Vector3(0.08, 1.5, 0.5), frame * _t3(Vector3(lx * w * 0.27, 0.75, sz)), _mats["door_wood"], c, true)
		for i in range(5):
			_box(Vector3(0.35, 0.3, 0.35),
				frame * _t3(Vector3(-w * 0.24 + i * w * 0.12, 1.7, sz + _rng.randf_range(-0.08, 0.08))),
				_mats["accent_orange"], _varc(Color(1, 1, 1), 0.15), false)
	# Indoor loot (40% indoors rule).
	for i in range(2):
		var kind: String = _pick(["ammo", "ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.35, w * 0.35), 0.0, _rng.randf_range(-d * 0.2, d * 0.3))
		loot_spots.append([kind, amt, Vector3(lp.x, 0.55, lp.z)])


func _furnish_home(frame: Transform3D, w: float, d: float) -> void:
	var c := _varc(Color(1, 1, 1), 0.08)
	_box(Vector3(2.0, 0.45, 1.1), frame * _t3(Vector3(-w * 0.25, 0.225, -d * 0.28)), _mats["door_wood"], c, true)
	_box(Vector3(1.3, 0.09, 0.9), frame * _t3(Vector3(w * 0.24, 0.72, -d * 0.26)), _mats["door_wood"], c, true)
	for lx in [-0.55, 0.55]:
		for lz in [-0.32, 0.32]:
			_box(Vector3(0.09, 0.72, 0.09), frame * _t3(Vector3(w * 0.24 + lx, 0.36, -d * 0.26 + lz)),
				_mats["door_wood"], c, false)
	_box(Vector3(0.9, 0.9, 0.9), frame * _t3(Vector3(w * 0.5 - 0.9, 0.45, d * 0.15)), _mats["concrete_dark"], c, true)
	if _rng.randf() < 0.75:
		var kind: String = _pick(["health", "armor", "ammo"])
		var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), 0.0, 0.5)
		loot_spots.append([kind, amt, Vector3(lp.x, 0.55, lp.z)])


func _furnish_upstairs(frame: Transform3D, w: float, d: float, fy: float) -> void:
	var c := _varc(Color(1, 1, 1), 0.08)
	# Partition into 2 rooms.
	_wall_open(frame * _t3(Vector3(0, fy, 0)), w, 2.8, 0.15, [[-w * 0.2, 0, 1.2, 2.2]], _mats["wall_white"], c, true)
	_box(Vector3(1.6, 0.45, 1.0), frame * _t3(Vector3(-w * 0.3, fy + 0.225, -d * 0.25)), _mats["door_wood"], c, true)
	_box(Vector3(1.2, 0.75, 0.8), frame * _t3(Vector3(w * 0.28, fy + 0.375, d * 0.2)), _mats["concrete_dark"], c, true)
	# Wardrobe + sofa (extra variety).
	_box(Vector3(1.2, 2.0, 0.6), frame * _t3(Vector3(w * 0.32, fy + 1.0, d * 0.5 - 0.9)),
		_mats["door_wood"], c, true)
	var fabric: Color = _pick([Color(0.70, 0.65, 0.55), Color(0.35, 0.45, 0.55), Color(0.55, 0.35, 0.30)])
	_box(Vector3(1.8, 0.55, 0.9), frame * _t3(Vector3(-w * 0.32, fy + 0.275, d * 0.25)),
		_mats["wall_grey"], fabric, true)
	if _rng.randf() < 0.7:
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), fy, _rng.randf_range(-d * 0.3, d * 0.3))
		loot_spots.append([kind, amt, Vector3(lp.x, fy + 0.55, lp.z)])


# ---------------- POIs ----------------

func _build_pois() -> void:
	for poi in POIS:
		var pname: String = poi["name"]
		var ppos: Vector3 = poi["pos"]
		poi_list.append({"name": pname, "pos": ppos})
		match pname:
			"Admiralty Mall":
				_poi_mall(ppos)
			"Estate Gate":
				_poi_estate(ppos)
			"Bridge View":
				_poi_bridge_view(ppos)
			"Market Junction":
				_poi_market_junction(ppos)
		for i in range(4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, 7.0)
			var kind: String = _pick(["health", "armor", "ammo", "ammo"])
			var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
			loot_spots.append([kind, amt, ppos + Vector3(cos(a) * r, 0.55, sin(a) * r)])


func _poi_mall(ppos: Vector3) -> void:
	# Two shop rows facing a courtyard.
	for row in [-1.0, 1.0]:
		for i in range(3):
			var bp := ppos + Vector3(-11.0 + i * 11.0, 0, row * 7.5)
			_build_shop(bp, 0.0 if row < 0.0 else PI)
	# Courtyard planter + fountain-ish center.
	_box(Vector3(4.0, 0.7, 4.0), _t3(ppos + Vector3(0, 0.35, 0)), _mats["soil"], Color(1, 1, 1), true)
	for i in range(5):
		_box(Vector3(0.5, _rng.randf_range(0.8, 1.4), 0.5),
			_t3(ppos + Vector3(_rng.randf_range(-1.4, 1.4), 0.9, _rng.randf_range(-1.4, 1.4))),
			_mats["leaf"], _varc(Color(1, 1, 1), 0.15), false)
	for i in range(2):
		_car(ppos + Vector3(-6.0 + i * 12.0, 0, 0), _rng.randf_range(-0.15, 0.15),
			_pick([Color(0.8, 0.8, 0.82), Color(0.15, 0.15, 0.17), Color(0.65, 0.15, 0.12)]))


func _poi_estate(ppos: Vector3) -> void:
	# Gated compound: wall, gate pillars, booth, 3 houses, palms.
	var pw := 26.0
	var pd := 20.0
	var frame := Transform3D(Basis(), ppos)
	var col := _varc(Color(1, 1, 1), 0.06)
	_wall_open(frame * _t3(Vector3(0, 0, -pd * 0.5)), pw, 1.6, 0.2, [[0, 0, 4.0, 1.6]], _mats["wall_terracotta"], col, true)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.7, 2.8, 0.7), frame * _t3(Vector3(sx * 2.3, 1.4, -pd * 0.5)), _mats["trim"], col, true)
	_label("LEKKI ESTATE", frame * Vector3(0, 2.4, -pd * 0.5 - 0.25), PI, 0.5, Color(0.95, 0.85, 0.6))
	_wall_open(frame * _t3(Vector3(0, 0, pd * 0.5)), pw, 1.6, 0.2, [], _mats["wall_terracotta"], col, true)
	for sx2 in [-1.0, 1.0]:
		var side := frame * Transform3D(Basis(Vector3.UP, sx2 * PI * 0.5), Vector3(sx2 * pw * 0.5, 0, 0))
		_wall_open(side, pd, 1.6, 0.2, [], _mats["wall_terracotta"], col, true)
	# Security booth by the gate.
	_box(Vector3(2.4, 2.4, 2.4), _t3(ppos + Vector3(4.5, 1.2, -pd * 0.5 + 1.6)), _mats["wall_cream"], col, true)
	_box(Vector3(2.8, 0.15, 2.8), _t3(ppos + Vector3(4.5, 2.5, -pd * 0.5 + 1.6)), _mats["roof_grey"], col, false)
	# Three estate houses inside.
	for i in range(3):
		var hp := ppos + Vector3(-8.0 + i * 8.0, 0, 3.5)
		_build_house(hp, 0.0)
	for i in range(4):
		_palm(ppos + Vector3(-10.0 + i * 6.5, 0, -6.0))


func _poi_bridge_view(ppos: Vector3) -> void:
	# South landing plaza: paving, kiosk, viewpoint railing, palms.
	_box(Vector3(16, 0.14, 10), _t3(ppos + Vector3(0, 0.0, 2.0)), _mats["sidewalk"],
		_varc(Color(1, 1, 1), 0.04), true)
	# Kiosk.
	var kf := Transform3D(Basis(Vector3.UP, PI), ppos + Vector3(-4.5, 0, 3.0))
	_box(Vector3(3.0, 2.5, 2.4), kf * _t3(Vector3(0, 1.25, 0)), _mats["wall_cream"], Color(1, 1, 1), true)
	_box(Vector3(3.6, 0.15, 3.0), kf * _t3(Vector3(0, 2.6, 0)), _mats["accent_orange"], Color(1, 1, 1), false)
	_signboard(kf, 2.6, 2.0, "KIO SK", Color(0.9, 0.45, 0.1))
	# Viewpoint railing at the channel edge.
	for i in range(7):
		var rp := Vector3(32.0 + i * 2.0, 0, RIVER_S - 0.6)
		_box(Vector3(0.1, 1.0, 0.1), _t3(rp + Vector3(0, 0.5, 0)), _mats["metal"], Color(1, 1, 1), false)
	_box(Vector3(13.0, 0.08, 0.08), _t3(Vector3(38.0, 1.0, RIVER_S - 0.6)), _mats["metal"], Color(1, 1, 1), false)
	for i in range(3):
		_palm(ppos + Vector3(2.0 + i * 3.0, 0, 5.5))


func _poi_market_junction(ppos: Vector3) -> void:
	# Market stalls around the roundabout + bus stop shelter.
	for i in range(5):
		var a := TAU * float(i) / 5.0 + 0.3
		_stall(ppos + Vector3(cos(a) * 13.5, 0, sin(a) * 13.5), -a + PI * 0.5)
	# Bus stop on the avenue's south sidewalk.
	var bf := Transform3D(Basis(), ppos + Vector3(16.0, 0.12, 8.6))
	for sx in [-1.6, 1.6]:
		for sz in [-0.9, 0.9]:
			_box(Vector3(0.12, 2.4, 0.12), bf * _t3(Vector3(sx, 1.2, sz)), _mats["metal"], Color(1, 1, 1), true)
	_box(Vector3(4.0, 0.12, 2.4), bf * _t3(Vector3(0, 2.5, 0)), _mats["accent_blue"], Color(1, 1, 1), false)
	_box(Vector3(3.8, 1.1, 0.06), bf * _t3(Vector3(0, 1.35, -1.05)), _mats["glass_dark"], Color(1, 1, 1), false)
	_box(Vector3(3.4, 0.08, 0.5), bf * _t3(Vector3(0, 0.55, 0.4)), _mats["door_wood"], Color(1, 1, 1), true)
	_label("BUS STOP", bf * Vector3(0, 2.15, 1.15), 0.0, 0.32)


func _stall(center: Vector3, yaw: float) -> void:
	# Open market stall (adapted from Makoko's pattern, concrete-town colors).
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wood = _mats["door_wood"]
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(Vector3(0.12, 2.3, 0.12), frame * _t3(Vector3(cx * 1.3, 1.15, cz * 1.0)),
				wood, _varc(Color(1, 1, 1), 0.10), true)
	var cc := _varc(_pick([Color(0.75, 0.45, 0.20), Color(0.30, 0.55, 0.60), Color(0.70, 0.65, 0.30)]), 0.08)
	_box(Vector3(3.2, 0.08, 2.6), frame * Transform3D(Basis(Vector3(1, 0, 0), 0.08), Vector3(0, 2.42, 0)),
		_mats["roof_grey"], cc, false)
	_box(Vector3(2.4, 0.10, 1.4), frame * _t3(Vector3(0, 0.85, 0)), wood, _varc(Color(1, 1, 1), 0.10), true)
	for i in range(4):
		var gc := _varc(_pick([Color(0.80, 0.30, 0.20), Color(0.90, 0.70, 0.20),
			Color(0.30, 0.60, 0.30), Color(0.85, 0.85, 0.85)]), 0.10)
		_box(Vector3(0.3, 0.25, 0.3),
			frame * _t3(Vector3(-0.8 + i * 0.55, 1.02, _rng.randf_range(-0.3, 0.3))),
			wood, gc, false)


# ---------------- city blocks ----------------

func _on_road(p: Vector3, margin := 3.5) -> bool:
	if absf(p.z - AVE_Z) < AVE_HW + margin and absf(p.x) < 68.0:
		return true
	if absf(p.x - STB_X) < ST_HW + margin and p.z > RIVER_S - 2.0:
		return true
	if absf(p.x - STC_X) < ST_HW + margin and p.z > RIVER_S - 2.0:
		return true
	if Vector2(p.x - 10.0, p.z - AVE_Z).length() < 11.5:
		return true
	return false


func _near_poi(p: Vector3, r: float) -> bool:
	for poi in poi_list:
		if (poi["pos"] as Vector3).distance_to(p) < r:
			return true
	return false


func _near_building(p: Vector3, w: float, gap: float) -> bool:
	for b in _buildings:
		var bc: Vector3 = b["center"]
		var bw: float = b["w"]
		var bd: float = b["d"]
		if absf(bc.x - p.x) < (bw + w) * 0.5 + gap and absf(bc.z - p.z) < (bd + w) * 0.5 + gap:
			return true
	return false


func _build_blocks() -> void:
	var kinds := ["shop", "shop", "shop", "house", "house", "house", "tower"]
	var placed := 0
	var attempts := 0
	while placed < 24 and attempts < 500:
		attempts += 1
		var p := Vector3(_rng.randf_range(-60.0, 60.0), 0, _rng.randf_range(-44.0, 62.0))
		if p.z < -44.0:
			continue
		if _on_road(p, 4.0):
			continue
		if _near_poi(p, 13.0):
			continue
		var kind: String = _pick(kinds)
		var w := 12.0 if kind == "tower" else 9.0
		if _near_building(p, w, 3.5):
			continue
		if p.distance_to(player_spawn) < 7.0:
			continue
		var yaw := _face_street(p)
		match kind:
			"shop":
				_build_shop(p, yaw)
			"house":
				_build_house(p, yaw)
			"tower":
				_build_tower(p, yaw)
		placed += 1


# ---------------- props ----------------

func _streetlight(pos: Vector3, yaw: float, h := 7.5) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_batch.add_cyl(0.13, h, frame * _t3(Vector3(0, h * 0.5, 0)), _mats["pole"], _varc(Color(1, 1, 1), 0.08))
	_batch.add_collider(Vector3(0.3, h, 0.3), frame * _t3(Vector3(0, h * 0.5, 0)))
	_box(Vector3(0.12, 0.12, 2.2), frame * _t3(Vector3(0, h - 0.1, 1.0)), _mats["pole"], Color(1, 1, 1), false)
	_box(Vector3(0.5, 0.22, 0.9), frame * _t3(Vector3(0, h - 0.2, 2.0)), _mats["trim"], Color(1, 1, 1), false)


func _car(pos: Vector3, yaw: float, col: Color) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	var body_mat := _std(col, 0.35, 0.4)
	_box(Vector3(4.4, 0.72, 1.9), frame * _t3(Vector3(0, 0.62, 0)), body_mat, Color(1, 1, 1), true)
	_box(Vector3(1.1, 0.5, 1.85), frame * _t3(Vector3(1.65, 0.55, 0)), body_mat, Color(1, 1, 1), false)
	_box(Vector3(2.3, 0.62, 1.72), frame * _t3(Vector3(-0.25, 1.18, 0)), _mats["glass_dark"], Color(1, 1, 1), true)
	_box(Vector3(2.34, 0.18, 1.76), frame * _t3(Vector3(-0.25, 1.55, 0)), body_mat, Color(1, 1, 1), false)
	for sx in [-1.45, 1.45]:
		for sz in [-0.95, 0.95]:
			var wg := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5),
				frame * Vector3(sx, 0.36, sz))
			_batch.add_cyl(0.36, 0.28, wg, _mats["tire"], Color(1, 1, 1))
	# headlights
	_box(Vector3(0.08, 0.18, 0.35), frame * _t3(Vector3(2.21, 0.62, -0.6)), _mats["paint_white"], Color(1, 1, 1), false)
	_box(Vector3(0.08, 0.18, 0.35), frame * _t3(Vector3(2.21, 0.62, 0.6)), _mats["paint_white"], Color(1, 1, 1), false)


func _billboard(pos: Vector3, yaw: float, line1: String, line2: String) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	for sx in [-2.6, 2.6]:
		_box(Vector3(0.35, 7.0, 0.35), frame * _t3(Vector3(sx, 3.5, 0)), _mats["pole"], Color(1, 1, 1), true)
	_box(Vector3(8.0, 3.2, 0.25), frame * _t3(Vector3(0, 8.2, 0)), _mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(7.7, 2.9, 0.28), frame * _t3(Vector3(0, 8.2, 0)), _mats["accent_blue"], Color(1, 1, 1), false)
	_label(line1, frame * Vector3(0, 8.55, 0.2), yaw, 0.62, Color(1.0, 0.75, 0.2))
	_label(line2, frame * Vector3(0, 7.75, 0.2), yaw, 0.4)


func _planter(pos: Vector3) -> void:
	_box(Vector3(1.3, 0.65, 1.3), _t3(pos + Vector3(0, 0.32, 0)), _mats["concrete_dark"],
		_varc(Color(1, 1, 1), 0.08), true)
	for i in range(3):
		_box(Vector3(0.45, _rng.randf_range(0.5, 0.9), 0.45),
			_t3(pos + Vector3(_rng.randf_range(-0.3, 0.3), 0.85, _rng.randf_range(-0.3, 0.3))),
			_mats["leaf"], _varc(Color(1, 1, 1), 0.15), false)


func _palm(pos: Vector3) -> void:
	var h := _rng.randf_range(3.4, 4.8)
	var lean := _rng.randf_range(0.0, 0.10)
	var segs := 4
	var sh := h / segs
	for i in range(segs):
		var c := pos + Vector3(lean * i * sh, sh * 0.5 + i * sh, 0)
		_batch.add_cyl(0.17 - 0.02 * i, sh + 0.15, _t3(c), _mats["trunk"], _varc(Color(1, 1, 1), 0.10))
	_batch.add_collider(Vector3(0.4, h, 0.4), _t3(pos + Vector3(0, h * 0.5, 0)))
	var top := pos + Vector3(lean * segs * sh, h, 0)
	for i in range(7):
		var a := TAU * float(i) / 7.0 + _rng.randf_range(-0.2, 0.2)
		var yaw := atan2(cos(a), sin(a))
		var tilt := _rng.randf_range(0.45, 0.85)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), tilt)
		var mid := top + Vector3(cos(a) * 0.95, 0.15 - tilt * 0.35, sin(a) * 0.95)
		_box(Vector3(0.55, 0.05, 2.1), Transform3D(b, mid), _mats["leaf"], _varc(Color(1, 1, 1), 0.15), false)


func _build_props() -> void:
	# Streetlights along the avenue (staggered sides) and cross streets.
	var x := -60.0
	var side := 1.0
	while x < 62.0:
		if Vector2(x - 10.0, 0.0).length() > 10.0:  # skip roundabout
			_streetlight(Vector3(x, 0, AVE_Z + side * (AVE_HW + 1.6)), 0.0 if side > 0.0 else PI)
			side = -side
		x += 16.0
	var z := -40.0
	while z < 60.0:
		_streetlight(Vector3(STB_X - ST_HW - 1.4, 0, z), PI * 0.5)
		_streetlight(Vector3(STC_X + ST_HW + 1.4, 0, z + 8.0), -PI * 0.5)
		z += 24.0
	# Parked cars along the avenue + near POIs.
	var car_cols := [Color(0.8, 0.8, 0.82), Color(0.15, 0.15, 0.17), Color(0.65, 0.15, 0.12),
		Color(0.15, 0.3, 0.6), Color(0.75, 0.75, 0.78), Color(0.2, 0.2, 0.22)]
	var car_spots := [
		[Vector3(-52, 0, AVE_Z - AVE_HW + 1.6), 0.0], [Vector3(-30, 0, AVE_Z + AVE_HW - 1.6), PI],
		[Vector3(28, 0, AVE_Z - AVE_HW + 1.6), 0.0], [Vector3(52, 0, AVE_Z + AVE_HW - 1.6), PI],
		[Vector3(STB_X - ST_HW + 1.4, 0, -20), PI * 0.5], [Vector3(STB_X + ST_HW - 1.4, 0, 34), -PI * 0.5],
		[Vector3(STC_X - ST_HW + 1.4, 0, 8), PI * 0.5], [Vector3(-38, 0, 20), 0.3],
		[Vector3(24, 0, 44), -0.4], [Vector3(-8, 0, -32), 1.2],
	]
	for i in range(car_spots.size()):
		var sp: Array = car_spots[i]
		_car(sp[0], sp[1], _pick(car_cols))
	# Billboards.
	_billboard(Vector3(-54, 0, AVE_Z - AVE_HW - 6.0), 0.0, "NOVA MOBILE", "BATTLE ROYALE")
	_billboard(Vector3(56, 0, 30), -PI * 0.5, "LEKKI", "ADMIRALTY WAY")
	# Planters along sidewalks.
	for i in range(12):
		var px := -58.0 + i * 10.5
		if Vector2(px - 10.0, 0.0).length() < 10.0:
			continue
		_planter(Vector3(px, 0.12, AVE_Z + AVE_HW + 1.5))
	# Palms: promenade + scattered.
	for i in range(8):
		_palm(Vector3(-56.0 + i * 16.0, 0, -66.0))
	for i in range(6):
		_palm(Vector3(_rng.randf_range(-55, 55), 0, _rng.randf_range(48, 60)))
	# Crates near shops (cover).
	for i in range(14):
		if _buildings.is_empty():
			break
		var b: Dictionary = _buildings[_rng.randi_range(0, _buildings.size() - 1)]
		var c: Vector3 = b["center"]
		var a := _rng.randf() * TAU
		var p := Vector3(c.x + cos(a) * _rng.randf_range(5.0, 8.0), 0, c.z + sin(a) * _rng.randf_range(5.0, 8.0))
		if absf(p.x) > 63.0 or absf(p.z) > 63.0 or p.z < -46.0 or _on_road(p, 1.0):
			continue
		var s := _rng.randf_range(1.0, 1.4)
		_box(Vector3(s, s, s), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p + Vector3(0, s * 0.5, 0)),
			_mats["door_wood"], _varc(Color(1, 1, 1), 0.12), true)


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
	# Enemy spawns: on streets near POIs (all solid ground).
	enemy_spawns = [
		Vector3(-36, 0.6, 22), Vector3(44, 0.6, 30), Vector3(33, 0.6, -38),
		Vector3(16, 0.6, 20), Vector3(-14, 0.6, -24), Vector3(22, 0.6, 52),
	]
	print("Lekki built: buildings=", _buildings.size(), " instances=", _batch.box_count(),
		" draws=", draws, " colliders=", _batch.collider_count(),
		" loot=", loot_spots.size(), " pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 160.0:
			cn.position.x = -160.0
