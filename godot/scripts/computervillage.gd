extends Node3D
class_name ComputerVillageMap
## Phase 4: Computer Village, Ikeja — dense electronics market district.
## Tight market streets packed with open-front tech shops, colorful hand-painted
## signboards, overhead wires, market umbrellas, a central plaza and the
## Gadget Mall landmark. Seeded procedural (SEED), merge-ready 140x140m.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261011

# Street layout (world units, meters).
const MAIN_Z := 8.0     # Otigba St: main market street (east-west)
const MAIN_HW := 3.0    # half-width
const XA := -20.0       # cross street A (north-south)
const XB := 20.0        # cross street B (north-south)
const X_HW := 2.75      # cross half-width
# Central plaza: x in [-14, 14], z in [-30, -10].

var player_spawn := Vector3(8, 0.6, 54.0)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # all shops (API compat with tests)
var map_extent := MAP_EXTENT

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _buildings: Array = []  # {"center","yaw","w","d","kind"}
var _clouds: Array = []
var _time := 0.0

const POIS := [
	{"name": "Tech Plaza", "pos": Vector3(0, 0, -20)},
	{"name": "Phone Row", "pos": Vector3(-40, 0, 8)},
	{"name": "Repair Lane", "pos": Vector3(40, 0, 8)},
	{"name": "Gadget Mall", "pos": Vector3(0, 0, -27)},
]
const SHOP_NAMES := ["TECH HUB", "PHONE CLINIC", "LAPTOP WORLD", "GADGET PLAZA",
	"MOBILE ZONE", "SIM & REPAIR", "DATA KING", "PHONE PALACE", "COMPUTER CARE",
	"ACCESSORIES+", "SCREEN FIX", "CHARGE POINT", "TABLET TOWN", "SOUND WAVE",
	"CAMERA CORNER", "NET GEAR", "FLASH DRIVE", "BATTERY BAY", "SMART SHOP",
	"DIGITAL DEN", "CHIP HOUSE", "WIFI WORLD"]
const SIGN_COLS := [Color(0.78, 0.12, 0.10), Color(0.10, 0.10, 0.12), Color(0.10, 0.30, 0.68),
	Color(0.90, 0.72, 0.10), Color(0.12, 0.55, 0.25), Color(0.85, 0.38, 0.08),
	Color(0.55, 0.12, 0.55), Color(0.10, 0.55, 0.60)]
const UMBRELLA_COLS := [Color(0.80, 0.15, 0.12), Color(0.15, 0.55, 0.25),
	Color(0.90, 0.75, 0.15), Color(0.15, 0.35, 0.70), Color(0.85, 0.45, 0.10)]


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_streets()
	_build_plaza()
	_build_shop_rows()
	_build_alley_walls()
	_build_warehouses()
	_build_mall()
	_build_arch()
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
	_mats["concrete"] = _std(Color(0.60, 0.58, 0.55))
	_mats["concrete_dark"] = _std(Color(0.44, 0.43, 0.41))
	_mats["asphalt"] = _std(Color(0.24, 0.24, 0.26), 0.95)
	_mats["asphalt_old"] = _std(Color(0.32, 0.31, 0.30), 0.95)
	_mats["plaza"] = _std(Color(0.66, 0.62, 0.57))
	_mats["wall_cream"] = _std(Color(0.80, 0.75, 0.66))
	_mats["wall_white"] = _std(Color(0.86, 0.85, 0.81))
	_mats["wall_yellow"] = _std(Color(0.78, 0.68, 0.45))
	_mats["wall_grey"] = _std(Color(0.55, 0.56, 0.58))
	_mats["wall_terracotta"] = _std(Color(0.70, 0.44, 0.30))
	_mats["wall_green"] = _std(Color(0.45, 0.55, 0.42))
	_mats["glass_dark"] = _std(Color(0.12, 0.16, 0.20), 0.15, 0.6)
	_mats["glass_counter"] = _std(Color(0.55, 0.70, 0.78), 0.1, 0.3)
	_mats["trim"] = _std(Color(0.28, 0.26, 0.24))
	_mats["door_wood"] = _std(Color(0.42, 0.30, 0.17))
	_mats["metal"] = _std(Color(0.50, 0.52, 0.55), 0.5, 0.5)
	_mats["pole"] = _std(Color(0.30, 0.24, 0.16), 0.9)
	_mats["wire"] = _std(Color(0.08, 0.08, 0.09), 0.9)
	_mats["tire"] = _std(Color(0.08, 0.08, 0.09), 0.95)
	_mats["paint_white"] = _std(Color(0.90, 0.90, 0.88), 0.9)
	_mats["sign_face"] = _std(Color(1, 1, 1), 0.6)      # per-instance brand colors
	_mats["awning"] = _std(Color(1, 1, 1), 0.8)         # per-instance canopy colors
	_mats["goods"] = _std(Color(1, 1, 1), 0.7)          # per-instance product colors
	_mats["umbrella"] = _std(Color(1, 1, 1), 0.75)      # per-instance canopy colors
	_mats["chair"] = _std(Color(1, 1, 1), 0.7)          # per-instance plastic colors
	_mats["tank"] = _std(Color(0.15, 0.35, 0.65), 0.6)
	_mats["keke"] = _std(Color(0.90, 0.75, 0.10), 0.5, 0.2)
	_mats["van"] = _std(Color(1, 1, 1), 0.45, 0.3)      # per-instance van colors
	_mats["cardboard"] = _std(Color(0.72, 0.58, 0.38), 0.9)
	_mats["barrel"] = _std(Color(1, 1, 1), 0.7)  # per-instance drum colors
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
	var dv := b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dv.x, dv.z)
	var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
	_box(Vector3(w, length, d), Transform3D(basis, mid), mat, Color(1, 1, 1), false)


func _wire(a: Vector3, b: Vector3) -> void:
	# Thin dark cable between two points (no collider).
	var dv := b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dv.x, dv.z)
	var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
	_batch.add_cyl(0.035, length, Transform3D(basis, mid), _mats["wire"], Color(1, 1, 1))


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


# ---------------- ground / streets / plaza ----------------

func _ground_rect(x0: float, x1: float, z0: float, z1: float, top_y: float, mat: StandardMaterial3D) -> void:
	var sx := x1 - x0
	var sz := z1 - z0
	_box(Vector3(sx, 0.6, sz),
		_t3(Vector3((x0 + x1) * 0.5, top_y - 0.3, (z0 + z1) * 0.5)),
		mat, _varc(Color(1, 1, 1), 0.05), true)


func _build_ground() -> void:
	_ground_rect(-70, 70, -70, 70, 0.0, _mats["concrete"])
	# Perimeter wall (keeps the arena readable, cheap long boxes).
	var wh := 2.2
	for z in [-69.0, 69.0]:
		_box(Vector3(140, wh, 0.5), _t3(Vector3(0, wh * 0.5, z)),
			_mats["wall_terracotta"], _varc(Color(1, 1, 1), 0.08), true)
	for x in [-69.0, 69.0]:
		_box(Vector3(0.5, wh, 140), _t3(Vector3(x, wh * 0.5, 0)),
			_mats["wall_terracotta"], _varc(Color(1, 1, 1), 0.08), true)


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
	# Main market street (Otigba St), east-west.
	_road_strip(-66, 66, MAIN_Z - MAIN_HW, MAIN_Z + MAIN_HW)
	_dashes_x(-64, -24, MAIN_Z)
	_dashes_x(-16, 16, MAIN_Z)
	_dashes_x(24, 64, MAIN_Z)
	# Cross streets A and B (north-south).
	_road_strip(XA - X_HW, XA + X_HW, -62, 62)
	_road_strip(XB - X_HW, XB + X_HW, -62, 62)
	_dashes_z(-60, 2, XA)
	_dashes_z(14, 60, XA)
	_dashes_z(-60, 2, XB)
	_dashes_z(14, 60, XB)


func _build_plaza() -> void:
	# Central Tech Plaza: patterned paving.
	_box(Vector3(28, 0.10, 20), _t3(Vector3(0, -0.01, -20)),
		_mats["plaza"], _varc(Color(1, 1, 1), 0.04), false)
	# Paving grid lines.
	var gx := -14.0
	while gx <= 14.0:
		_box(Vector3(0.12, 0.02, 20), _t3(Vector3(gx, 0.05, -20)),
			_mats["concrete_dark"], Color(1, 1, 1), false)
		gx += 4.0
	var gz := -30.0
	while gz <= -10.0:
		_box(Vector3(28, 0.02, 0.12), _t3(Vector3(0, 0.05, gz)),
			_mats["concrete_dark"], Color(1, 1, 1), false)
		gz += 4.0


# ---------------- shops ----------------

func _register(center: Vector3, yaw: float, w: float, d: float, kind: String) -> void:
	_buildings.append({"center": center, "yaw": yaw, "w": w, "d": d, "kind": kind})
	house_positions.append(center)


func _front_center(front_coord: float, yaw: float, depth: float, along: float, axis: String) -> Vector3:
	# front_coord: world coord of the open front face. Returns shop center.
	if axis == "x":
		var zc := front_coord - depth * 0.5 if yaw < 0.1 and yaw > -0.1 else front_coord
		# yaw==0 faces +z (body toward -z); yaw==PI faces -z (body toward +z)
		if absf(yaw) < 0.1:
			zc = front_coord - depth * 0.5
		elif absf(yaw - PI) < 0.1:
			zc = front_coord + depth * 0.5
		return Vector3(along, 0, zc)
	else:
		var xc := front_coord
		if absf(yaw - PI * 0.5) < 0.1:  # faces +x, body toward -x
			xc = front_coord - depth * 0.5
		elif absf(yaw + PI * 0.5) < 0.1:  # faces -x, body toward +x
			xc = front_coord + depth * 0.5
		return Vector3(xc, 0, along)


func _shop_row_x(x0: float, x1: float, front_z: float, yaw: float) -> void:
	var x := x0
	while x < x1 - 5.5:
		var w := _rng.randf_range(6.5, 9.0)
		if x + w > x1:
			break
		var d := _rng.randf_range(5.5, 7.0)
		var c := _front_center(front_z, yaw, d, x + w * 0.5, "x")
		_build_shop(c, yaw, w, d)
		x += w + _rng.randf_range(0.15, 0.5)


func _shop_row_z(z0: float, z1: float, front_x: float, yaw: float) -> void:
	var z := z0
	while z < z1 - 5.5:
		var w := _rng.randf_range(6.5, 9.0)
		if z + w > z1:
			break
		var d := _rng.randf_range(5.5, 7.0)
		var c := _front_center(front_x, yaw, d, z + w * 0.5, "z")
		_build_shop(c, yaw, w, d)
		z += w + _rng.randf_range(0.15, 0.5)


func _build_shop(center: Vector3, yaw: float, w: float, d: float) -> void:
	# Open-front tech shop: posts + lintel front (interior visible from street),
	# stocked interior, signboard + awning, solid upper floor (visual).
	var h1 := 3.2   # ground floor
	var h2 := 2.8   # upper floor
	var t := 0.22
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wall_mat: StandardMaterial3D = _pick([_mats["wall_cream"], _mats["wall_white"],
		_mats["wall_yellow"], _mats["wall_grey"], _mats["wall_terracotta"], _mats["wall_green"]])
	var col := _varc(Color(1, 1, 1), 0.07)
	# ~1 in 3 shops gets an enterable upper floor: stairs, furnished rooms,
	# lit interior, stairwell to a walkable roof.
	var upstairs_open := _rng.randf() < 0.35
	# Ground slab.
	_box(Vector3(w + 0.4, 0.25, d + 0.4), frame * _t3(Vector3(0, -0.105, 0)),
		_mats["concrete"], _varc(Color(1, 1, 1), 0.05), true)
	# Side + back walls (ground).
	_box(Vector3(t, h1, d), frame * _t3(Vector3(-w * 0.5, h1 * 0.5, 0)), wall_mat, col, true)
	_box(Vector3(t, h1, d), frame * _t3(Vector3(w * 0.5, h1 * 0.5, 0)), wall_mat, col, true)
	_box(Vector3(w, h1, t), frame * _t3(Vector3(0, h1 * 0.5, -d * 0.5)), wall_mat, col, true)
	# Open front: 3 posts + lintel beam.
	for px in [-w * 0.5 + 0.15, 0.0, w * 0.5 - 0.15]:
		_box(Vector3(0.25, h1, 0.25), frame * _t3(Vector3(px, h1 * 0.5, d * 0.5)),
			_mats["trim"], col, true)
	_box(Vector3(w, 0.6, 0.3), frame * _t3(Vector3(0, h1 - 0.3, d * 0.5)), wall_mat, col, true)
	# Mid slab (upper floor); enterable shops get a stairwell hole + stairs.
	var fy := h1 + 0.25
	var st_x := w * 0.5 - 1.9    # ground->upper stairs, right side, run along +z
	var st_z := -d * 0.5 + 0.8
	if upstairs_open:
		_slab_hole(frame, w, d, fy, st_x - 0.7, st_x + 0.7, st_z + 2.1, 4.4)
		_stairs_simple(frame, st_x, st_z, fy)
		_furnish_upstairs_cv(frame, w, d, fy, fy + h2)
	else:
		_box(Vector3(w, 0.25, d), frame * _t3(Vector3(0, h1 + 0.125, 0)),
			_mats["concrete"], col, true)
	# Upper floor walls: solid back/sides; front is window band (real openings)
	# for enterable shops, inset glass for sealed ones.
	_box(Vector3(w, h2, t), frame * _t3(Vector3(0, fy + h2 * 0.5, -d * 0.5)), wall_mat, col, true)
	_box(Vector3(t, h2, d), frame * _t3(Vector3(-w * 0.5, fy + h2 * 0.5, 0)), wall_mat, col, true)
	_box(Vector3(t, h2, d), frame * _t3(Vector3(w * 0.5, fy + h2 * 0.5, 0)), wall_mat, col, true)
	if upstairs_open:
		_wall_open(frame * _t3(Vector3(0, fy, d * 0.5)), w, h2, t,
			[[-w * 0.3, 1.0, 1.6, 1.3], [0.0, 1.0, 1.6, 1.3], [w * 0.3, 1.0, 1.6, 1.3]],
			wall_mat, col, true)
	else:
		_box(Vector3(w, h2, t), frame * _t3(Vector3(0, fy + h2 * 0.5, d * 0.5)), wall_mat, col, true)
		var nwin := maxi(2, int(w / 2.6))
		for i in range(nwin):
			var wx := -w * 0.5 + w * (float(i) + 0.5) / float(nwin)
			_box(Vector3(1.3, 1.1, 0.08),
				frame * _t3(Vector3(wx, fy + h2 * 0.55, d * 0.5 + t * 0.5 + 0.01)),
				_mats["glass_dark"], Color(1, 1, 1), false)
	# Roof slab + parapet + water tank (sometimes). Enterable shops get stairs
	# from the upper floor to a walkable roof (full parapet + roof loot).
	var ry := h1 + 0.25 + h2
	if upstairs_open:
		# Roof stairs stacked above the ground->upper run: from its landing,
		# back toward -z (yaw-PI frame). One stairwell zone; the rest of the
		# upper floor stays free for furniture.
		var landing := Vector3(st_x, fy, st_z + 4.2)
		var rframe := frame * Transform3D(Basis(Vector3.UP, PI), landing)
		_slab_hole(frame, w, d, ry + 0.22, st_x - 0.7, st_x + 0.7, st_z + 2.1, 4.4, 0.22)
		_stairs_simple(rframe, 0.0, 0.0, h2)
		_box(Vector3(w + 0.3, 0.9, 0.15), frame * _t3(Vector3(0, ry + 0.65, d * 0.5)), wall_mat, col, false)
		_box(Vector3(w + 0.3, 0.9, 0.15), frame * _t3(Vector3(0, ry + 0.65, -d * 0.5)), wall_mat, col, false)
		_box(Vector3(0.15, 0.9, d + 0.3), frame * _t3(Vector3(w * 0.5, ry + 0.65, 0)), wall_mat, col, false)
		_box(Vector3(0.15, 0.9, d + 0.3), frame * _t3(Vector3(-w * 0.5, ry + 0.65, 0)), wall_mat, col, false)
		var rkind: String = _pick(["ammo", "health", "armor"])
		var ramt := 60 if rkind == "ammo" else (40 if rkind == "health" else 50)
		var rlp: Vector3 = frame * Vector3(0.0, ry + 0.22, 1.8)
		loot_spots.append([rkind, ramt, Vector3(rlp.x, ry + 0.77, rlp.z)])
	else:
		_box(Vector3(w + 0.3, 0.22, d + 0.3), frame * _t3(Vector3(0, ry + 0.11, 0)),
			_mats["concrete_dark"], col, true)
		_box(Vector3(w + 0.3, 0.5, 0.15), frame * _t3(Vector3(0, ry + 0.45, d * 0.5)), wall_mat, col, false)
	if _rng.randf() < 0.45:
		_batch.add_cyl(0.75, 1.1, frame * _t3(Vector3(_rng.randf_range(-w * 0.25, w * 0.25), ry + 0.75, -d * 0.2)),
			_mats["tank"], _varc(Color(1, 1, 1), 0.1))
	# Satellite dish on the roof (sometimes; kept clear of the stairwell hole).
	if _rng.randf() < 0.4:
		var dx := _rng.randf_range(-w * 0.3, w * 0.3)
		if upstairs_open and absf(dx - st_x) < 1.2:
			dx = -st_x
		var dz := _rng.randf_range(-d * 0.25, d * 0.25)
		_box(Vector3(0.08, 0.9, 0.08), frame * _t3(Vector3(dx, ry + 0.65, dz)),
			_mats["metal"], _varc(Color(1, 1, 1), 0.1), false)
		var dish := Transform3D(Basis(Vector3(1, 0, 0), -0.7), frame * Vector3(dx, ry + 1.25, dz))
		_box(Vector3(0.9, 0.06, 0.9), dish, _mats["metal"], _varc(Color(1, 1, 1), 0.12), false)
	# AC unit on a side wall (sometimes).
	if _rng.randf() < 0.5:
		_box(Vector3(0.5, 0.4, 0.9), frame * _t3(Vector3(w * 0.5 + 0.28, h1 + 1.0, _rng.randf_range(-d * 0.25, d * 0.25))),
			_mats["metal"], _varc(Color(1, 1, 1), 0.1), false)
	_furnish_shop(frame, w, d, h1)
	# Signboard + name + awning.
	var scol: Color = _pick(SIGN_COLS)
	var sname: String = _pick(SHOP_NAMES)
	var sy := h1 + 0.9
	_box(Vector3(w * 0.85, 1.0, 0.32), frame * _t3(Vector3(0, sy, d * 0.5 + 0.16)),
		_mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(w * 0.85 - 0.25, 0.8, 0.34), frame * _t3(Vector3(0, sy, d * 0.5 + 0.16)),
		_mats["sign_face"], scol, false)
	_label(sname, frame * Vector3(0, sy, d * 0.5 + 0.36),
		atan2(frame.basis.z.x, frame.basis.z.z), 0.42)
	# Striped-look awning (single per-instance color).
	var acol: Color = _pick(UMBRELLA_COLS)
	var alocal := Transform3D(Basis(Vector3(1, 0, 0), 0.38), Vector3(0, 2.55, d * 0.5 + 0.85))
	_box(Vector3(w * 0.95, 0.07, 1.9), frame * alocal, _mats["awning"], acol, false)
	for sx in [-1.0, 1.0]:
		_strut(frame * Vector3(sx * w * 0.42, 1.95, d * 0.5 + 0.1),
			frame * Vector3(sx * w * 0.42, 2.62, d * 0.5 + 1.55), 0.05, 0.05, _mats["metal"])
	# Interior tube light (emissive, no real light cost).
	_box(Vector3(w * 0.5, 0.08, 0.12), frame * _t3(Vector3(0, h1 - 0.15, 0)),
		_mats["tubelight"], Color(1, 1, 1), false)
	_register(center, yaw, w, d, "shop")


func _furnish_shop(frame: Transform3D, w: float, d: float, h1: float) -> void:
	var c := _varc(Color(1, 1, 1), 0.08)
	# Glass display counter near the front.
	_box(Vector3(w * 0.55, 0.9, 0.7), frame * _t3(Vector3(0, 0.45, d * 0.5 - 1.1)),
		_mats["door_wood"], c, true)
	_box(Vector3(w * 0.55, 0.45, 0.74), frame * _t3(Vector3(0, 1.05, d * 0.5 - 1.1)),
		_mats["glass_counter"], Color(1, 1, 1), false)
	# Devices lined on the counter.
	for i in range(6):
		var gx := -w * 0.24 + i * w * 0.096
		_box(Vector3(0.28, 0.06, 0.4), frame * _t3(Vector3(gx, 1.30, d * 0.5 - 1.1)),
			_mats["goods"], _pick(SIGN_COLS), false)
	# Back wall shelves with stocked goods.
	for lvl in [1.1, 1.8]:
		_box(Vector3(w * 0.7, 0.07, 0.45), frame * _t3(Vector3(0, lvl, -d * 0.5 + 0.45)),
			_mats["door_wood"], c, false)
		for i in range(7):
			var gx2 := -w * 0.31 + i * w * 0.103
			var gs := _rng.randf_range(0.22, 0.34)
			_box(Vector3(gs, gs * 0.8, 0.3),
				frame * _t3(Vector3(gx2, lvl + 0.04 + gs * 0.4, -d * 0.5 + 0.45)),
				_mats["goods"], _pick(SIGN_COLS), false)
	# Side shelf unit.
	_box(Vector3(0.45, 0.07, 2.2), frame * _t3(Vector3(-w * 0.5 + 0.45, 1.4, 0)), _mats["door_wood"], c, false)
	_box(Vector3(0.45, 0.07, 2.2), frame * _t3(Vector3(-w * 0.5 + 0.45, 2.0, 0)), _mats["door_wood"], c, false)
	for i in range(4):
		_box(Vector3(0.3, 0.35, 0.35),
			frame * _t3(Vector3(-w * 0.5 + 0.45, 1.62, -0.8 + i * 0.55)),
			_mats["goods"], _pick(SIGN_COLS), false)
	# Indoor loot.
	var rolls := 1 + (1 if _rng.randf() < 0.35 else 0)
	for i in range(rolls):
		var kind: String = _pick(["ammo", "ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), 0.0,
			_rng.randf_range(-d * 0.15, d * 0.25))
		loot_spots.append([kind, amt, Vector3(lp.x, 0.55, lp.z)])


func _furnish_upstairs_cv(frame: Transform3D, w: float, d: float, fy: float, ceil_y: float) -> void:
	# Furnished upper floor for enterable shops: stock shelf, bed, crate,
	# ceiling tube light, and upstairs loot. Furniture stays in the middle
	# strip (x ~= 0), clear of the stair runs on both sides.
	var c := _varc(Color(1, 1, 1), 0.08)
	_box(Vector3(1.4, 0.07, 0.45), frame * _t3(Vector3(0, fy + 1.4, -d * 0.5 + 0.7)),
		_mats["door_wood"], c, false)
	for i in range(4):
		_box(Vector3(0.28, 0.3, 0.3),
			frame * _t3(Vector3(-0.5 + i * 0.34, fy + 1.58, -d * 0.5 + 0.7)),
			_mats["goods"], _pick(SIGN_COLS), false)
	_box(Vector3(0.95, 0.42, 1.9), frame * _t3(Vector3(0, fy + 0.21, d * 0.5 - 1.6)),
		_mats["door_wood"], c, true)
	_box(Vector3(0.9, 0.9, 0.9), frame * _t3(Vector3(0, fy + 0.45, -d * 0.5 + 1.6)),
		_mats["cardboard"], c, true)
	# Ceiling tube light (emissive, no real light cost).
	_box(Vector3(w * 0.4, 0.08, 0.12), frame * _t3(Vector3(0, ceil_y - 0.15, 0)),
		_mats["tubelight"], Color(1, 1, 1), false)
	# Upstairs loot.
	if _rng.randf() < 0.75:
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-0.4, 0.4), fy, d * 0.5 - 2.6)
		loot_spots.append([kind, amt, Vector3(lp.x, fy + 0.55, lp.z)])


func _build_shop_rows() -> void:
	# Main street, north side (front z=11, facing -z).
	_shop_row_x(-62.0, -26.0, 11.0, PI)
	_shop_row_x(-14.0, 14.0, 11.0, PI)
	_shop_row_x(26.0, 62.0, 11.0, PI)
	# Main street, south side (front z=5, facing +z).
	_shop_row_x(-62.0, -26.0, 5.0, 0.0)
	_shop_row_x(-14.0, 14.0, 5.0, 0.0)
	_shop_row_x(26.0, 62.0, 5.0, 0.0)
	# Cross street A, east side (front x=-17.25, facing -x).
	_shop_row_z(-44.0, -2.0, -17.25, -PI * 0.5)
	_shop_row_z(18.0, 50.0, -17.25, -PI * 0.5)
	# Cross street B, west side (front x=17.25, facing +x).
	_shop_row_z(-44.0, -2.0, 17.25, PI * 0.5)
	_shop_row_z(18.0, 50.0, 17.25, PI * 0.5)


func _build_alley_walls() -> void:
	# Weathered rear walls along the empty sides of the cross streets (service alleys).
	var col := _varc(Color(1, 1, 1), 0.08)
	for fx in [-22.75, 22.75]:
		for seg in [[-44.0, -2.0], [18.0, 50.0]]:
			var z0: float = seg[0]
			var z1: float = seg[1]
			_box(Vector3(0.25, 2.4, z1 - z0), _t3(Vector3(fx, 1.2, (z0 + z1) * 0.5)),
				_mats["wall_grey"], col, true)
			# Occasional gate + poster boards.
			if _rng.randf() < 0.7:
				var gz := _rng.randf_range(z0 + 4.0, z1 - 4.0)
				_box(Vector3(0.3, 1.8, 2.2), _t3(Vector3(fx, 0.9, gz)),
					_mats["trim"], _varc(Color(1, 1, 1), 0.1), true)
				_box(Vector3(0.34, 1.0, 1.4), _t3(Vector3(fx, 1.5, gz + 2.6)),
					_mats["sign_face"], _pick(SIGN_COLS), false)
	# Oil drums in the service alleys.
	for i in range(10):
		var bx := (-22.75 if i % 2 == 0 else 22.75) + _rng.randf_range(-1.0, 1.0)
		var bz := _rng.randf_range(-40.0, 48.0)
		var bcol: Color = _pick([Color(0.55, 0.30, 0.16), Color(0.35, 0.42, 0.55),
			Color(0.50, 0.50, 0.52), Color(0.60, 0.55, 0.30)])
		_batch.add_cyl(0.42, 1.0, _t3(Vector3(bx, 0.5, bz)), _mats["barrel"], bcol)
		_batch.add_collider(Vector3(0.84, 1.0, 0.84), _t3(Vector3(bx, 0.5, bz)))


func _build_warehouses() -> void:
	# Big storage sheds filling the back blocks (cover + loot).
	var spots := [
		Vector3(-45, 0, 34), Vector3(-45, 0, -38), Vector3(45, 0, 34),
		Vector3(45, 0, -38), Vector3(-8, 0, -52), Vector3(30, 0, -52),
		Vector3(-30, 0, 56), Vector3(38, 0, 58),
	]
	for sp in spots:
		var w := _rng.randf_range(10.0, 14.0)
		var d := _rng.randf_range(8.0, 11.0)
		var h := _rng.randf_range(3.6, 4.6)
		var yaw := 0.0 if _rng.randf() < 0.5 else PI * 0.5
		var frame := Transform3D(Basis(Vector3.UP, yaw), sp)
		var wm: StandardMaterial3D = _pick([_mats["wall_grey"], _mats["wall_terracotta"], _mats["wall_cream"]])
		var col := _varc(Color(1, 1, 1), 0.08)
		_box(Vector3(w + 0.4, 0.25, d + 0.4), frame * _t3(Vector3(0, -0.105, 0)),
			_mats["concrete"], col, true)
		# Walls with a wide loading door on one face.
		_box(Vector3(w, h, 0.25), frame * _t3(Vector3(0, h * 0.5, -d * 0.5)), wm, col, true)
		_box(Vector3(0.25, h, d), frame * _t3(Vector3(-w * 0.5, h * 0.5, 0)), wm, col, true)
		_box(Vector3(0.25, h, d), frame * _t3(Vector3(w * 0.5, h * 0.5, 0)), wm, col, true)
		var dw := 3.4
		_box(Vector3((w - dw) * 0.5, h, 0.25), frame * _t3(Vector3(-(dw * 0.5 + (w - dw) * 0.25), h * 0.5, d * 0.5)), wm, col, true)
		_box(Vector3((w - dw) * 0.5, h, 0.25), frame * _t3(Vector3(dw * 0.5 + (w - dw) * 0.25, h * 0.5, d * 0.5)), wm, col, true)
		_box(Vector3(w, h - 2.8, 0.25), frame * _t3(Vector3(0, 2.8 + (h - 2.8) * 0.5, d * 0.5)), wm, col, true)
		# Roof.
		_box(Vector3(w + 0.6, 0.18, d + 0.6), frame * _t3(Vector3(0, h + 0.09, 0)),
			_mats["concrete_dark"], col, false)
		# Crates inside + loot.
		for i in range(5):
			var s := _rng.randf_range(0.9, 1.3)
			var cp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.35, w * 0.35), 0, _rng.randf_range(-d * 0.3, d * 0.2))
			_box(Vector3(s, s, s), _t3(Vector3(cp.x, s * 0.5, cp.z)),
				_mats["door_wood"], _varc(Color(1, 1, 1), 0.12), true)
		if _rng.randf() < 0.8:
			var kind: String = _pick(["ammo", "health", "armor"])
			var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
			var lp2: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), 0, 0.5)
			loot_spots.append([kind, amt, Vector3(lp2.x, 0.55, lp2.z)])
		_register(sp, yaw, w, d, "warehouse")


# ---------------- Gadget Mall landmark ----------------

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


func _build_mall() -> void:
	# Two-story glass-front electronics mall on the plaza's south edge.
	var center := Vector3(0, 0, -38)
	var w := 18.0
	var d := 12.0
	var fh := 3.4
	var t := 0.25
	var frame := Transform3D(Basis(), center)  # faces +z (toward plaza)
	var wm: StandardMaterial3D = _mats["wall_white"]
	var col := _varc(Color(1, 1, 1), 0.05)
	_box(Vector3(w + 0.6, 0.25, d + 0.6), frame * _t3(Vector3(0, -0.105, 0)),
		_mats["concrete"], col, true)
	# Glass front: mullions + dark glass insets, wide open entrance.
	_wall_open(frame * _t3(Vector3(0, 0, d * 0.5)), w, fh, t,
		[[-w * 0.38, 0.9, 2.6, 1.9], [-w * 0.18, 0.9, 2.6, 1.9], [w * 0.18, 0.9, 2.6, 1.9],
			[w * 0.38, 0.9, 2.6, 1.9], [0, 0, 3.0, 3.0]],
		wm, col, true)
	for gx in [-w * 0.38, -w * 0.18, w * 0.18, w * 0.38]:
		_box(Vector3(2.6, 1.9, 0.06), frame * _t3(Vector3(gx, 1.85, d * 0.5 - 0.1)),
			_mats["glass_dark"], Color(1, 1, 1), false)
	# Big roof sign.
	_box(Vector3(12.0, 1.6, 0.4), frame * _t3(Vector3(0, fh * 2 + 1.6, d * 0.5 - 0.4)),
		_mats["trim"], Color(1, 1, 1), false)
	_box(Vector3(11.6, 1.3, 0.44), frame * _t3(Vector3(0, fh * 2 + 1.6, d * 0.5 - 0.4)),
		_mats["sign_face"], Color(0.10, 0.30, 0.68), false)
	_label("GADGET MALL", frame * Vector3(0, fh * 2 + 1.6, d * 0.5 - 0.12), 0.0, 0.55,
		Color(1.0, 0.85, 0.2))
	for sx in [-5.0, 5.0]:
		_box(Vector3(0.3, 1.8, 0.3), frame * _t3(Vector3(sx, fh * 2 + 0.2, d * 0.5 - 0.4)),
			_mats["metal"], col, false)
	# Side + back walls with window strips.
	for sz in [-1.0, 1.0]:
		_wall_open(frame * Transform3D(Basis(Vector3.UP, sz * PI * 0.5), Vector3(sz * w * 0.5, 0, 0)),
			d, fh, t, [[0, 1.0, 2.0, 1.4]], wm, col, true)
	_wall_open(frame * _t3(Vector3(0, 0, -d * 0.5)), w, fh, t, [[0, 1.0, 2.4, 1.4]], wm, col, true)
	# Interior: display islands + shelves.
	for ix in [-5.5, 0.0, 5.5]:
		_box(Vector3(3.4, 0.95, 1.2), frame * _t3(Vector3(ix, 0.475, 1.0)),
			_mats["door_wood"], col, true)
		_box(Vector3(3.4, 0.5, 1.24), frame * _t3(Vector3(ix, 1.2, 1.0)),
			_mats["glass_counter"], Color(1, 1, 1), false)
		for i in range(5):
			_box(Vector3(0.35, 0.3, 0.4),
				frame * _t3(Vector3(ix - 1.3 + i * 0.65, 1.6, 1.0)),
				_mats["goods"], _pick(SIGN_COLS), false)
	# Stairs along the east wall to floor 2.
	_stairs_simple(frame, w * 0.5 - 1.2, d * 0.5 - 1.0, fh)
	_box(Vector3(w, 0.25, d), frame * _t3(Vector3(0, fh + 0.125, 0)), _mats["concrete"], col, true)
	# Floor 2: window band front, more goods.
	_wall_open(frame * _t3(Vector3(0, fh + 0.25, d * 0.5)), w, fh, t,
		[[-w * 0.3, 1.0, 2.2, 1.5], [0, 1.0, 2.2, 1.5], [w * 0.3, 1.0, 2.2, 1.5]], wm, col, true)
	for sz2 in [-1.0, 1.0]:
		_box(Vector3(w, fh, t), frame * _t3(Vector3(0, fh + 0.25 + fh * 0.5, sz2 * d * 0.5)), wm, col, true)
	_box(Vector3(t, fh, d), frame * _t3(Vector3(-w * 0.5, fh + 0.25 + fh * 0.5, 0)), wm, col, true)
	_box(Vector3(t, fh, d), frame * _t3(Vector3(w * 0.5, fh + 0.25 + fh * 0.5, 0)), wm, col, true)
	for ix2 in [-4.0, 4.0]:
		_box(Vector3(3.0, 1.6, 0.5), frame * _t3(Vector3(ix2, fh + 0.25 + 0.8, -2.0)),
			_mats["door_wood"], col, true)
		for i in range(4):
			_box(Vector3(0.4, 0.35, 0.35),
				frame * _t3(Vector3(ix2 - 1.0 + i * 0.7, fh + 0.25 + 1.8, -2.0)),
				_mats["goods"], _pick(SIGN_COLS), false)
	# Ceiling tube light on floor 2 (emissive, no real light cost).
	_box(Vector3(w * 0.4, 0.08, 0.12), frame * _t3(Vector3(0, fh * 2 + 0.1, 0)),
		_mats["tubelight"], Color(1, 1, 1), false)
	# Roof + parapet.
	_box(Vector3(w + 0.4, 0.22, d + 0.4), frame * _t3(Vector3(0, fh * 2 + 0.36, 0)),
		_mats["concrete_dark"], col, true)
	_box(Vector3(w + 0.4, 0.6, 0.15), frame * _t3(Vector3(0, fh * 2 + 0.75, d * 0.5)), wm, col, false)
	# Dense loot inside (both floors).
	for i in range(8):
		var kind: String = _pick(["ammo", "ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var fy := 0.0 if i < 5 else fh + 0.25
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.4, w * 0.4), fy,
			_rng.randf_range(-d * 0.3, d * 0.3))
		loot_spots.append([kind, amt, Vector3(lp.x, fy + 0.55, lp.z)])
	poi_list.append({"name": "Gadget Mall", "pos": Vector3(0, 0, -30)})
	_register(center, 0.0, w, d, "mall")


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


func _build_arch() -> void:
	# "COMPUTER VILLAGE — IKEJA" entry arch over the main street (west end).
	var ax := -62.0
	var col := Color(1, 1, 1)
	for sz in [-1.0, 1.0]:
		_box(Vector3(0.8, 7.0, 0.8), _t3(Vector3(ax, 3.5, MAIN_Z + sz * (MAIN_HW + 1.2))),
			_mats["trim"], col, true)
	_box(Vector3(0.9, 1.4, 11.0), _t3(Vector3(ax, 7.2, MAIN_Z)),
		_mats["trim"], col, false)
	_box(Vector3(0.94, 1.1, 10.6), _t3(Vector3(ax, 7.2, MAIN_Z)),
		_mats["sign_face"], Color(0.78, 0.12, 0.10), false)
	_label("COMPUTER VILLAGE", Vector3(ax + 0.55, 7.35, MAIN_Z), PI * 0.5, 0.5, Color(1, 1, 1))
	_label("IKEJA • LAGOS", Vector3(ax + 0.55, 6.85, MAIN_Z), PI * 0.5, 0.32, Color(1.0, 0.85, 0.3))
	_label("COMPUTER VILLAGE", Vector3(ax - 0.55, 7.35, MAIN_Z), -PI * 0.5, 0.5, Color(1, 1, 1))
	# Hanging banners across the main street.
	for bx in [-40.0, 0.0, 40.0]:
		_wire(Vector3(bx, 6.2, MAIN_Z - MAIN_HW - 3.2), Vector3(bx, 6.2, MAIN_Z + MAIN_HW + 3.2))
		_box(Vector3(4.6, 0.9, 0.06), _t3(Vector3(bx, 5.6, MAIN_Z)),
			_mats["sign_face"], _pick(SIGN_COLS), false)
		_label(_pick(["PHONE CLINIC", "TECH HUB", "GADGET PLAZA"]), Vector3(bx, 5.6, MAIN_Z + 0.08), 0.0, 0.34)


# ---------------- POIs ----------------

func _build_pois() -> void:
	for poi in POIS:
		var pname: String = poi["name"]
		if pname == "Gadget Mall":
			continue  # already registered by _build_mall
		var ppos: Vector3 = poi["pos"]
		poi_list.append({"name": pname, "pos": ppos})
		match pname:
			"Tech Plaza":
				_poi_plaza(ppos)
			"Phone Row":
				_poi_phone_row(ppos)
			"Repair Lane":
				_poi_repair_lane(ppos)
		for i in range(4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, 7.0)
			var kind: String = _pick(["health", "armor", "ammo", "ammo"])
			var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
			loot_spots.append([kind, amt, ppos + Vector3(cos(a) * r, 0.55, sin(a) * r)])


func _poi_plaza(ppos: Vector3) -> void:
	# Kiosks + umbrellas + chairs: the busy heart of the market.
	for i in range(4):
		var kp := ppos + Vector3(-9.0 + i * 6.0, 0, 4.5)
		_kiosk(kp, _rng.randf_range(-0.2, 0.2))
	for i in range(8):
		var a := TAU * float(i) / 8.0 + 0.2
		var up := ppos + Vector3(cos(a) * 10.5, 0, sin(a) * 10.5)
		_umbrella(up, _pick(UMBRELLA_COLS))
		for j in range(2):
			_chair(up + Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.6, 1.6)),
				_rng.randf() * TAU, _pick([Color(0.15, 0.35, 0.70), Color(0.80, 0.15, 0.12), Color(0.15, 0.60, 0.30)]))
	# Central sign totem.
	_box(Vector3(0.5, 5.0, 0.5), _t3(ppos + Vector3(0, 2.5, -6.0)), _mats["pole"], Color(1, 1, 1), true)
	_box(Vector3(3.4, 1.4, 0.3), _t3(ppos + Vector3(0, 5.4, -6.0)), _mats["sign_face"],
		Color(0.10, 0.30, 0.68), false)
	_label("TECH PLAZA", ppos + Vector3(0, 5.4, -5.8), 0.0, 0.45)


func _poi_phone_row(ppos: Vector3) -> void:
	# Extra stalls + umbrellas crowding the west main street.
	for i in range(3):
		_stall(ppos + Vector3(-8.0 + i * 8.0, 0, -4.6), 0.0)
		_umbrella(ppos + Vector3(-8.0 + i * 8.0, 0, 4.8), _pick(UMBRELLA_COLS))
	_wire(Vector3(ppos.x - 10, 6.0, MAIN_Z - 6.0), Vector3(ppos.x - 10, 6.0, MAIN_Z + 6.0))


func _poi_repair_lane(ppos: Vector3) -> void:
	# Workbenches + tool crates along the east main street.
	for i in range(3):
		var bp := ppos + Vector3(-8.0 + i * 8.0, 0, 4.8)
		_box(Vector3(2.2, 0.9, 1.0), _t3(bp + Vector3(0, 0.45, 0)),
			_mats["door_wood"], _varc(Color(1, 1, 1), 0.1), true)
		_box(Vector3(0.5, 0.25, 0.4), _t3(bp + Vector3(-0.6, 1.02, 0)),
			_mats["goods"], _pick(SIGN_COLS), false)
		_box(Vector3(0.4, 0.2, 0.3), _t3(bp + Vector3(0.5, 1.0, 0.1)),
			_mats["metal"], Color(1, 1, 1), false)
		_umbrella(bp + Vector3(0, 0, -3.4), _pick(UMBRELLA_COLS))
	_wire(Vector3(ppos.x + 8, 6.0, MAIN_Z - 6.0), Vector3(ppos.x + 8, 6.0, MAIN_Z + 6.0))


func _kiosk(center: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var c := _varc(Color(1, 1, 1), 0.08)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(Vector3(0.12, 2.4, 0.12), frame * _t3(Vector3(cx * 1.2, 1.2, cz * 0.9)),
				_mats["door_wood"], c, false)
	_box(Vector3(3.0, 0.1, 2.4), frame * Transform3D(Basis(Vector3(1, 0, 0), 0.10), Vector3(0, 2.55, 0)),
		_mats["awning"], _pick(UMBRELLA_COLS), false)
	_box(Vector3(2.4, 0.95, 1.2), frame * _t3(Vector3(0, 0.475, 0)), _mats["door_wood"], c, true)
	for i in range(5):
		_box(Vector3(0.3, 0.28, 0.3),
			frame * _t3(Vector3(-0.9 + i * 0.45, 1.1, _rng.randf_range(-0.2, 0.2))),
			_mats["goods"], _pick(SIGN_COLS), false)
	_box(Vector3(2.0, 0.5, 0.08), frame * _t3(Vector3(0, 1.9, 0.95)),
		_mats["sign_face"], _pick(SIGN_COLS), false)


func _stall(center: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var c := _varc(Color(1, 1, 1), 0.10)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(Vector3(0.12, 2.3, 0.12), frame * _t3(Vector3(cx * 1.3, 1.15, cz * 1.0)),
				_mats["door_wood"], c, true)
	_box(Vector3(3.2, 0.08, 2.6), frame * Transform3D(Basis(Vector3(1, 0, 0), 0.08), Vector3(0, 2.42, 0)),
		_mats["awning"], _pick(UMBRELLA_COLS), false)
	_box(Vector3(2.4, 0.10, 1.4), frame * _t3(Vector3(0, 0.85, 0)), _mats["door_wood"], c, true)
	for i in range(4):
		_box(Vector3(0.3, 0.25, 0.3),
			frame * _t3(Vector3(-0.8 + i * 0.55, 1.02, _rng.randf_range(-0.3, 0.3))),
			_mats["goods"], _pick(SIGN_COLS), false)


func _umbrella(pos: Vector3, col: Color) -> void:
	_batch.add_cyl(0.06, 2.3, _t3(pos + Vector3(0, 1.15, 0)), _mats["pole"], _varc(Color(1, 1, 1), 0.08))
	_batch.add_collider(Vector3(0.15, 2.3, 0.15), _t3(pos + Vector3(0, 1.15, 0)))
	_batch.add_cyl(1.7, 0.14, _t3(pos + Vector3(0, 2.32, 0)), _mats["umbrella"], col)


func _chair(pos: Vector3, yaw: float, col: Color) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	_box(Vector3(0.45, 0.06, 0.45), frame * _t3(Vector3(0, 0.45, 0)), _mats["chair"], col, true)
	_box(Vector3(0.45, 0.5, 0.06), frame * _t3(Vector3(0, 0.72, -0.20)), _mats["chair"], col, false)
	for sx in [-0.18, 0.18]:
		for sz in [-0.18, 0.18]:
			_box(Vector3(0.05, 0.45, 0.05), frame * _t3(Vector3(sx, 0.225, sz)), _mats["chair"], col, false)


# ---------------- props ----------------

func _utility_pole(pos: Vector3) -> void:
	var h := 7.0
	_batch.add_cyl(0.14, h, _t3(pos + Vector3(0, h * 0.5, 0)), _mats["pole"], _varc(Color(1, 1, 1), 0.1))
	_batch.add_collider(Vector3(0.3, h, 0.3), _t3(pos + Vector3(0, h * 0.5, 0)))
	_box(Vector3(1.6, 0.12, 0.12), _t3(pos + Vector3(0, h - 0.6, 0)), _mats["pole"], Color(1, 1, 1), false)


func _keke(pos: Vector3, yaw: float) -> void:
	# Keke-napep tricycle: yellow body, canopy, 3 wheels.
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	var c := _varc(Color(1, 1, 1), 0.06)
	_box(Vector3(1.5, 0.7, 2.6), frame * _t3(Vector3(0, 0.75, 0)), _mats["keke"], c, true)
	_box(Vector3(1.5, 0.5, 0.9), frame * _t3(Vector3(0, 1.35, 0.8)), _mats["glass_dark"], c, false)
	for sx in [-0.7, 0.7]:
		for sz in [-0.6, 0.6]:
			_box(Vector3(0.08, 0.9, 0.08), frame * _t3(Vector3(sx, 1.55, sz)), _mats["trim"], c, false)
	_box(Vector3(1.7, 0.08, 2.8), frame * _t3(Vector3(0, 2.02, 0)), _mats["keke"], c, false)
	for wx in [-0.75, 0.75]:
		var wg := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), frame * Vector3(wx, 0.32, -0.85))
		_batch.add_cyl(0.32, 0.22, wg, _mats["tire"], Color(1, 1, 1))
	var wf := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), frame * Vector3(0, 0.32, 1.15))
	_batch.add_cyl(0.32, 0.22, wf, _mats["tire"], Color(1, 1, 1))


func _van(pos: Vector3, yaw: float, col: Color) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	var c := Color(1, 1, 1)
	_box(Vector3(2.0, 1.3, 1.9), frame * _t3(Vector3(0, 0.95, 1.9)), _mats["van"], col, true)
	_box(Vector3(1.8, 0.7, 0.1), frame * _t3(Vector3(0, 1.35, 2.86)), _mats["glass_dark"], c, false)
	_box(Vector3(2.1, 2.1, 3.4), frame * _t3(Vector3(0, 1.35, -0.4)), _mats["van"], _varc(col, 0.05), true)
	for sx in [-0.95, 0.95]:
		for sz in [1.9, -1.4]:
			var wg := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), frame * Vector3(sx, 0.4, sz))
			_batch.add_cyl(0.4, 0.3, wg, _mats["tire"], Color(1, 1, 1))


func _crate_stack(pos: Vector3) -> void:
	var n := _rng.randi_range(2, 3)
	for i in range(n):
		var s := _rng.randf_range(0.8, 1.1)
		_box(Vector3(s, s, s),
			Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), pos + Vector3(0, s * (0.5 + i), 0)),
			_mats["door_wood"], _varc(Color(1, 1, 1), 0.12), true)
	var nb := _rng.randi_range(2, 4)
	for i in range(nb):
		var bs := _rng.randf_range(0.4, 0.6)
		_box(Vector3(bs, bs * 0.7, bs),
			Transform3D(Basis(Vector3.UP, _rng.randf() * TAU),
				pos + Vector3(_rng.randf_range(1.0, 1.8), bs * 0.35, _rng.randf_range(-0.8, 0.8))),
			_mats["cardboard"], _varc(Color(1, 1, 1), 0.1), true)


func _build_props() -> void:
	# Utility poles + tangled wires along the main street.
	var prev_n := Vector3.ZERO
	var prev_s := Vector3.ZERO
	var has_prev := false
	var x := -56.0
	while x < 58.0:
		var pn := Vector3(x, 0, MAIN_Z - MAIN_HW - 1.6)
		var ps := Vector3(x, 0, MAIN_Z + MAIN_HW + 1.6)
		_utility_pole(pn)
		_utility_pole(ps)
		if has_prev:
			_wire(prev_n + Vector3(0, 6.4, 0), pn + Vector3(0, 6.4, 0))
			_wire(prev_s + Vector3(0, 6.4, 0), ps + Vector3(0, 6.4, 0))
			_wire(pn + Vector3(0, 6.8, 0), ps + Vector3(0, 6.8, 0))  # across the street
			_wire(prev_n + Vector3(0, 6.1, 0), ps + Vector3(0, 6.1, 0))  # diagonal tangle
		prev_n = pn
		prev_s = ps
		has_prev = true
		x += 19.0
	# Keke-napep tricycles parked on the main street.
	_keke(Vector3(-52, 0, MAIN_Z - 1.2), 0.1)
	_keke(Vector3(-50, 0, MAIN_Z + 1.4), PI - 0.15)
	_keke(Vector3(48, 0, MAIN_Z - 1.2), -0.1)
	_keke(Vector3(30, 0, MAIN_Z + 1.5), PI + 0.2)
	# Delivery vans.
	_van(Vector3(-28, 0, MAIN_Z - 1.6), 0.05, Color(0.92, 0.92, 0.94))
	_van(Vector3(56, 0, MAIN_Z + 1.6), PI - 0.08, Color(0.75, 0.78, 0.82))
	# Crate stacks + boxes along shop fronts.
	for i in range(12):
		var sx := _rng.randf_range(-58.0, 58.0)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var sz := MAIN_Z + side * (MAIN_HW + _rng.randf_range(1.2, 2.2))
		_crate_stack(Vector3(sx, 0, sz))
	# Street loot.
	for i in range(12):
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lx := _rng.randf_range(-58.0, 58.0)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var lz := MAIN_Z + side * _rng.randf_range(0.5, MAIN_HW - 0.5)
		loot_spots.append([kind, amt, Vector3(lx, 0.55, lz)])


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
		Vector3(-40, 0.6, 8), Vector3(40, 0.6, 8), Vector3(-20, 0.6, -14),
		Vector3(20, 0.6, 30), Vector3(0, 0.6, 44), Vector3(-20, 0.6, 44),
	]
	print("ComputerVillage built: buildings=", _buildings.size(), " instances=", _batch.box_count(),
		" draws=", draws, " colliders=", _batch.collider_count(),
		" loot=", loot_spots.size(), " pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 160.0:
			cn.position.x = -160.0
