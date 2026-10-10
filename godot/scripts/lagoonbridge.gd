extends Node3D
class_name LagoonBridgeMap
## Phase 10: Lagoon Bridge — "Third Mainland" style elevated highway bridge.
## A long elevated 6-lane deck (top y=6.0) spanning the 140m map edge-to-edge
## along the X axis, over open lagoon water (y=-1.0). Linear chokepoint combat
## along the deck: stalled cars + a bus as cover, toll plaza at x=-30, piers
## every ~18m, streetlights, railings, and a stair tower down to a small
## water-level dock (y=0.2) at x~+60 — the second playable level.
## Flat in the y sense once on a surface: NO ground_height(); spawns, loot and
## POIs bake the deck/dock height directly into y.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261017
const DECK_Y := 6.0
const DECK_HALF_W := 10.0
const WATER_Y := -1.0
const DOCK_Y := 0.2

var player_spawn := Vector3(-62, 6.6, 0)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # toll plaza + dock (API compat)
var map_extent := MAP_EXTENT

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _clouds: Array = []
var _time := 0.0
var _placed: Array = []  # Vector2 points already used by loot (spacing)
var _car_pos: Array = []  # Vector2 car/bus centers (loot clearance)


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_water()
	_build_deck()
	_build_piers()
	_build_railings()
	_build_lights()
	_build_toll()
	_build_cars()
	_build_stairs_dock()
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
	_mats["asphalt"] = _std(Color(0.16, 0.16, 0.17), 0.95)
	_mats["sidewalk"] = _std(Color(0.52, 0.51, 0.49), 0.9)
	_mats["mark_white"] = _std(Color(0.90, 0.90, 0.88), 0.7)
	_mats["mark_yellow"] = _std(Color(0.95, 0.75, 0.10), 0.7)
	_mats["concrete"] = _std(Color(0.60, 0.59, 0.56))
	_mats["concrete_dark"] = _std(Color(0.44, 0.43, 0.41))
	_mats["steel"] = _std(Color(0.55, 0.57, 0.60), 0.45, 0.6)
	_mats["steel_dark"] = _std(Color(0.25, 0.26, 0.28), 0.6, 0.4)
	_mats["glass"] = _std(Color(0.35, 0.55, 0.65), 0.2, 0.8)
	_mats["wood"] = _std(Color(0.45, 0.33, 0.20), 0.9)
	_mats["wood_dark"] = _std(Color(0.30, 0.22, 0.13), 0.9)
	_mats["rope"] = _std(Color(0.55, 0.48, 0.34), 0.95)
	_mats["carpaint"] = _std(Color(1, 1, 1), 0.35, 0.4)  # per-instance colors
	_mats["tire"] = _std(Color(0.08, 0.08, 0.08), 0.95)
	_mats["crate"] = _std(Color(0.52, 0.40, 0.24), 0.9)
	_mats["canoe"] = _std(Color(1, 1, 1), 0.9)  # per-instance hull browns
	var lamp := _std(Color(1.0, 0.88, 0.66), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.82, 0.55)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp"] = lamp
	var sign := _std(Color(0.10, 0.55, 0.22), 0.5)
	sign.emission_enabled = true
	sign.emission = Color(0.10, 0.70, 0.25)
	sign.emission_energy_multiplier = 1.5
	_mats["sign"] = sign


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


func _collide(size: Vector3, xform: Transform3D) -> void:
	_batch.add_collider(size, xform)


func _rope(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.05:
		return
	var basis := Basis.looking_at(dir / len, Vector3.UP)
	_box(Vector3(0.05, 0.05, len), Transform3D(basis, (a + b) * 0.5),
		_mats["rope"], _varc(Color(1, 1, 1), 0.08), false)


func _light_panel(lx: float, lz: float, fy: float) -> void:
	# Emissive ceiling light: housing + glowing diffuser (batched, no real light).
	_box(Vector3(2.0, 0.08, 1.1), _t3(Vector3(lx, fy, lz)),
		_mats["steel_dark"], _varc(Color(1, 1, 1), 0.06), false)
	_box(Vector3(1.8, 0.05, 0.9), _t3(Vector3(lx, fy - 0.055, lz)),
		_mats["lamp"], Color(1, 1, 1), false)


# ---------------- water & void ----------------

func _build_water() -> void:
	# Big lagoon water plane at y=-1 covering the whole map (UVs feed the shader waves).
	var wm := PlaneMesh.new()
	wm.size = Vector2(140, 140)
	var mi := MeshInstance3D.new()
	mi.name = "LagoonWater"
	mi.mesh = wm
	mi.position = Vector3(0, WATER_Y, 0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/water.gdshader") as Shader
	mi.material_override = sm
	add_child(mi)
	# Dark void-catcher plane far below (seen through gaps at grazing angles).
	var voidm := PlaneMesh.new()
	voidm.size = Vector2(500, 500)
	var voidi := MeshInstance3D.new()
	voidi.mesh = voidm
	voidi.position = Vector3(0, -8.0, 0)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.03, 0.05, 0.08)
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	voidi.material_override = vmat
	add_child(voidi)


# ---------------- deck ----------------

func _build_deck() -> void:
	# Main asphalt slab: top exactly at DECK_Y.
	_box(Vector3(140, 0.6, 20), _t3(Vector3(0, DECK_Y - 0.3, 0)),
		_mats["asphalt"], _varc(Color(1, 1, 1), 0.06), false)
	# Single walkable slab collider for the whole deck.
	_collide(Vector3(140, 0.8, 20), _t3(Vector3(0, DECK_Y - 0.4, 0)))
	# Concrete fascia skirts under both edges (deck reads thick from the water).
	for sz in [-1.0, 1.0]:
		_box(Vector3(140, 1.4, 0.35), _t3(Vector3(0, DECK_Y - 0.7, sz * 9.82)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), false)
	# Curb strips, flush-ish but proud of the asphalt.
	for sz in [-1.0, 1.0]:
		_box(Vector3(140, 0.05, 1.5), _t3(Vector3(0, DECK_Y + 0.015, sz * 9.2)),
			_mats["sidewalk"], _varc(Color(1, 1, 1), 0.06), false)
	# Continuous edge lines.
	for sz in [-1.0, 1.0]:
		_box(Vector3(140, 0.025, 0.15), _t3(Vector3(0, DECK_Y + 0.0125, sz * 8.4)),
			_mats["mark_white"], Color(1, 1, 1), false)
	# Double yellow center divider.
	for sz in [-1.0, 1.0]:
		_box(Vector3(140, 0.025, 0.12), _t3(Vector3(0, DECK_Y + 0.0125, sz * 0.28)),
			_mats["mark_yellow"], Color(1, 1, 1), false)
	# White lane dashes between the 6 lanes (boundaries at z=-6,-3,3,6).
	for bz in [-6.0, -3.0, 3.0, 6.0]:
		for i in range(24):
			var x := -66.0 + float(i) * 5.5
			_box(Vector3(2.4, 0.025, 0.12), _t3(Vector3(x, DECK_Y + 0.0125, bz)),
				_mats["mark_white"], _varc(Color(1, 1, 1), 0.05), false)
	# Invisible guard walls along both deck edges (players/enemies can't walk off).
	_collide(Vector3(140, 2.2, 0.4), _t3(Vector3(0, DECK_Y + 1.1, -9.85)))
	# +z guard has a gap at x in [56, 64] for the dock stair tower.
	_collide(Vector3(126, 2.2, 0.4), _t3(Vector3(-7, DECK_Y + 1.1, 9.85)))
	_collide(Vector3(6, 2.2, 0.4), _t3(Vector3(67, DECK_Y + 1.1, 9.85)))
	# End guards at x=+-70 so nobody walks off the map ends.
	for sx in [-1.0, 1.0]:
		_collide(Vector3(0.4, 2.2, 20), _t3(Vector3(sx * 69.85, DECK_Y + 1.1, 0)))


func _build_piers() -> void:
	# Cylindrical concrete columns every ~18m, deck bottom down into the water.
	var xi := -63
	while xi <= 63:
		for pz in [-6.5, 6.5]:
			_cyl(1.0, 8.5, _t3(Vector3(xi, 1.25, pz)),
				_mats["concrete"], _varc(Color(1, 1, 1), 0.08), true)
			# Pier cap under the deck.
			_box(Vector3(2.6, 0.8, 2.6), _t3(Vector3(xi, DECK_Y - 0.7, pz)),
				_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.08), false)
		xi += 18


func _build_railings() -> void:
	# Visual steel railings along both edges; posts skip the stair gap on +z.
	for i in range(47):
		var x := -69.0 + float(i) * 3.0
		_box(Vector3(0.1, 1.0, 0.1), _t3(Vector3(x, DECK_Y + 0.5, -9.7)),
			_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
		if x < 56.0 or x > 64.0:
			_box(Vector3(0.1, 1.0, 0.1), _t3(Vector3(x, DECK_Y + 0.5, 9.7)),
				_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
	# Continuous top + mid rails; +z side split around the stair gap.
	for ry in [DECK_Y + 1.02, DECK_Y + 0.62]:
		_box(Vector3(140, 0.07, 0.07), _t3(Vector3(0, ry, -9.7)),
			_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
		_box(Vector3(126, 0.07, 0.07), _t3(Vector3(-7, ry, 9.7)),
			_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
		_box(Vector3(6, 0.07, 0.07), _t3(Vector3(67, ry, 9.7)),
			_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)


func _build_lights() -> void:
	# Streetlights every ~24m, alternating sides, arm reaching over the deck.
	var xs := [-56.0, -32.0, -8.0, 16.0, 40.0, 60.0]
	var k := 0
	for x in xs:
		var side := 1.0 if k % 2 == 0 else -1.0
		var pz := side * 8.6
		_cyl(0.12, 7.0, _t3(Vector3(x, DECK_Y + 3.5, pz)),
			_mats["steel_dark"], _varc(Color(1, 1, 1), 0.06), true)
		_box(Vector3(0.12, 0.12, 1.7), _t3(Vector3(x, DECK_Y + 6.85, pz - side * 0.8)),
			_mats["steel_dark"], _varc(Color(1, 1, 1), 0.06), false)
		_box(Vector3(0.7, 0.18, 0.4), _t3(Vector3(x, DECK_Y + 6.8, pz - side * 1.55)),
			_mats["lamp"], Color(1, 1, 1), false)
		k += 1


# ---------------- toll plaza ----------------

func _build_toll() -> void:
	var tx := -30.0
	# 4 booth islands with ENTERABLE kiosks (door on the west face).
	for bz in [-6.0, -2.0, 2.0, 6.0]:
		var bf := float(bz)
		_box(Vector3(4.5, 0.3, 1.8), _t3(Vector3(tx, DECK_Y + 0.15, bf)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.08), true)
		var by := DECK_Y + 0.3  # island top = booth floor
		var bh := 2.2
		# West wall with a real door opening (1.0 wide, 2.0 high).
		_box(Vector3(0.1, bh, 0.15), _t3(Vector3(tx - 1.1, by + bh * 0.5, bf - 0.575)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
		_box(Vector3(0.1, bh, 0.15), _t3(Vector3(tx - 1.1, by + bh * 0.5, bf + 0.575)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
		_box(Vector3(0.1, 0.2, 1.3), _t3(Vector3(tx - 1.1, by + 2.1, bf)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
		# East wall with a real window opening.
		_box(Vector3(0.1, 1.2, 1.3), _t3(Vector3(tx + 1.1, by + 0.6, bf)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
		_box(Vector3(0.1, 0.3, 1.3), _t3(Vector3(tx + 1.1, by + 2.05, bf)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
		_box(Vector3(0.06, 0.7, 1.34), _t3(Vector3(tx + 1.1, by + 1.55, bf)),
			_mats["glass"], Color(1, 1, 1), false)
		# North + south walls with small window openings.
		for sz in [-1.0, 1.0]:
			_box(Vector3(2.2, 1.3, 0.1), _t3(Vector3(tx, by + 0.65, bf + float(sz) * 0.6)),
				_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
			_box(Vector3(2.2, 0.3, 0.1), _t3(Vector3(tx, by + 2.05, bf + float(sz) * 0.6)),
				_mats["concrete"], _varc(Color(1, 1, 1), 0.06), true)
			_box(Vector3(0.6, 0.6, 0.06), _t3(Vector3(tx, by + 1.6, bf + float(sz) * 0.6)),
				_mats["glass"], Color(1, 1, 1), false)
		# Interior: desk + emissive ceiling light + loot.
		_box(Vector3(1.0, 0.75, 0.5), _t3(Vector3(tx + 0.4, by + 0.375, bf)),
			_mats["wood"], Color(1, 1, 1), true)
		_light_panel(tx, bf, by + 2.05)
		loot_spots.append(["ammo", 60, Vector3(tx - 0.4, DECK_Y + 0.55, bf)])
		# Kiosk roof.
		_box(Vector3(2.6, 0.14, 1.7), _t3(Vector3(tx, DECK_Y + 2.57, bf)),
			_mats["steel_dark"], _varc(Color(1, 1, 1), 0.06), false)
	# Overhead canopy on 4 columns.
	_box(Vector3(13, 0.5, 21), _t3(Vector3(tx, DECK_Y + 3.4, 0)),
		_mats["steel_dark"], _varc(Color(1, 1, 1), 0.05), false)
	# Walkable canopy roof (top at DECK_Y+3.65).
	_collide(Vector3(13, 0.6, 21), _t3(Vector3(tx, DECK_Y + 3.4, 0)))
	for cx in [tx - 5.0, tx + 5.0]:
		for cz in [-8.5, 8.5]:
			_cyl(0.35, 3.4, _t3(Vector3(cx, DECK_Y + 1.7, cz)),
				_mats["concrete"], _varc(Color(1, 1, 1), 0.08), true)
	# Stair tower: deck (y=6) up to the canopy roof (west edge, z=8.5).
	var stx0 := tx - 12.0
	var strun := 5.5
	var strise := 3.65
	var stzc := 8.5
	var ststeps := 12
	for i in range(ststeps):
		var sx := stx0 + strun * (float(i) + 0.5) / float(ststeps)
		var sy := DECK_Y + strise * (float(i) + 0.5) / float(ststeps)
		_box(Vector3(strun / float(ststeps) + 0.05, 0.09, 2.0),
			_t3(Vector3(sx, sy - 0.045, stzc)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), false)
	var stang := atan2(strise, strun)
	var stlen := sqrt(strun * strun + strise * strise)
	_collide(Vector3(stlen, 0.12, 2.0),
		Transform3D(Basis(Vector3(0, 0, 1), stang),
			Vector3(stx0 + strun * 0.5, DECK_Y + strise * 0.5 - 0.06, stzc)))
	# Support posts under the stair landing.
	for pxx in [tx - 8.0, tx - 6.8]:
		_box(Vector3(0.25, 3.65, 0.25), _t3(Vector3(float(pxx), DECK_Y + 1.82, stzc)),
			_mats["steel_dark"], _varc(Color(1, 1, 1), 0.06), true)
	# Railing around the canopy roof (gap at the stair landing, z 7.5..9.5).
	var cry := DECK_Y + 3.65
	for rz2 in [-10.5, 10.5]:
		_box(Vector3(13, 0.08, 0.08), _t3(Vector3(tx, cry + 1.0, float(rz2))),
			_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
	_box(Vector3(0.08, 0.08, 17.0), _t3(Vector3(tx - 6.5, cry + 1.0, -2.0)),
		_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
	_box(Vector3(0.08, 0.08, 1.0), _t3(Vector3(tx - 6.5, cry + 1.0, 10.0)),
		_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
	_box(Vector3(0.08, 0.08, 21), _t3(Vector3(tx + 6.5, cry + 1.0, 0)),
		_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
	for gx2 in [-6.5, 6.5]:
		for gz2 in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
			if float(gx2) < 0.0 and float(gz2) > 6.0:
				continue  # stair landing gap on the west edge
			_box(Vector3(0.09, 1.0, 0.09),
				_t3(Vector3(tx + float(gx2), cry + 0.5, float(gz2))),
				_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
	# Emissive light strips under the canopy.
	for lxx in [tx - 4.0, tx, tx + 4.0]:
		_light_panel(float(lxx), 0.0, DECK_Y + 3.05)
	# Green "TOLL" signs on both canopy faces (white dashes as lettering hint).
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.25, 1.7, 9), _t3(Vector3(tx + sx * 6.7, DECK_Y + 2.2, 0)),
			_mats["sign"], Color(1, 1, 1), false)
		for dz in [-3.0, 0.0, 3.0]:
			_box(Vector3(0.06, 0.25, 1.4), _t3(Vector3(tx + sx * 6.85, DECK_Y + 2.2, dz)),
				_mats["mark_white"], Color(1, 1, 1), false)
	# Concrete lane-divider barriers funneling into the plaza.
	for bx in [tx - 10.0, tx + 10.0]:
		for bz in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			_box(Vector3(1.8, 0.8, 0.35), _t3(Vector3(bx, DECK_Y + 0.4, bz)),
				_mats["concrete"], _varc(Color(1, 1, 1), 0.08), true)
	# Traffic barrels guiding lanes into the plaza.
	for bx2 in [-52.0, -46.0, -18.0, -12.0, 4.0, 10.0, 46.0, 52.0]:
		for bz2 in [-8.6, 8.6]:
			_cyl(0.3, 0.9, _t3(Vector3(float(bx2), DECK_Y + 0.45, float(bz2))),
				_mats["steel_dark"], Color(0.85, 0.35, 0.10), true)
	house_positions.append(Vector3(tx, DECK_Y, 0))


# ---------------- stalled vehicles (cover) ----------------

func _car(x: float, z: float, yaw_deg: float, col: Color) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(x, 0, z))
	# Body + cabin + glass band.
	_box(Vector3(4.4, 0.75, 1.9), frame * _t3(Vector3(0, DECK_Y + 0.85, 0)),
		_mats["carpaint"], col, false)
	_box(Vector3(2.3, 0.62, 1.7), frame * _t3(Vector3(-0.2, DECK_Y + 1.535, 0)),
		_mats["carpaint"], col.darkened(0.08), false)
	_box(Vector3(2.0, 0.32, 1.74), frame * _t3(Vector3(-0.2, DECK_Y + 1.535, 0)),
		_mats["glass"], Color(1, 1, 1), false)
	# Wheels: cylinder axis rotated to Z.
	for sx in [-1.4, 1.4]:
		for sz in [-0.85, 0.85]:
			_cyl(0.35, 0.3,
				frame * Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5),
					Vector3(sx, DECK_Y + 0.35, sz)),
				_mats["tire"], Color(1, 1, 1), false)
	# Single solid cover collider.
	_collide(Vector3(4.5, 2.0, 2.0), frame * _t3(Vector3(0, DECK_Y + 0.9, 0)))
	_car_pos.append(Vector2(x, z))


func _bus(x: float, z: float, yaw_deg: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(x, 0, z))
	var body_col := Color(0.92, 0.92, 0.90)
	_box(Vector3(11, 2.3, 2.5), frame * _t3(Vector3(0, DECK_Y + 1.35, 0)),
		_mats["carpaint"], body_col, false)
	# Window band + green stripe, proud of the body.
	_box(Vector3(11.04, 0.9, 2.54), frame * _t3(Vector3(0, DECK_Y + 2.1, 0)),
		_mats["glass"], Color(1, 1, 1), false)
	_box(Vector3(11.04, 0.5, 2.54), frame * _t3(Vector3(0, DECK_Y + 1.35, 0)),
		_mats["carpaint"], Color(0.10, 0.45, 0.20), false)
	_box(Vector3(11.1, 0.15, 2.6), frame * _t3(Vector3(0, DECK_Y + 2.575, 0)),
		_mats["carpaint"], body_col.darkened(0.12), false)
	for sx in [-3.6, 3.6]:
		for sz in [-1.05, 1.05]:
			_cyl(0.45, 0.35,
				frame * Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5),
					Vector3(sx, DECK_Y + 0.45, sz)),
				_mats["tire"], Color(1, 1, 1), false)
	_collide(Vector3(11.1, 2.9, 2.6), frame * _t3(Vector3(0, DECK_Y + 1.45, 0)))
	_car_pos.append(Vector2(x, z))


func _build_cars() -> void:
	var cars := [
		[-52.0, -4.5, 8.0, Color(0.75, 0.12, 0.10)],
		[-42.0, 4.0, -6.0, Color(0.12, 0.25, 0.65)],
		[-36.0, -5.0, 100.0, Color(0.88, 0.88, 0.86)],  # crashed, near-sideways
		[-24.0, 3.5, 5.0, Color(0.95, 0.75, 0.10)],
		[-12.0, -4.0, -10.0, Color(0.15, 0.45, 0.20)],
		[2.0, 4.5, 7.0, Color(0.08, 0.08, 0.09)],
		[12.0, -5.5, -75.0, Color(0.85, 0.40, 0.10)],  # crashed
		[30.0, 5.0, 6.0, Color(0.70, 0.72, 0.74)],
		[44.0, -4.0, -5.0, Color(0.45, 0.10, 0.12)],
		[54.0, 5.5, 12.0, Color(0.10, 0.55, 0.55)],
	]
	for c in cars:
		_car(float(c[0]), float(c[1]), float(c[2]), c[3])
	_bus(20.0, -3.5, 3.0)


# ---------------- dock stairs + south dock ----------------

func _build_stairs_dock() -> void:
	# Stair tower: from deck edge (z=10, y=6) down to the dock (z=18, y=0.2).
	var steps := 14
	var drop := (DECK_Y - DOCK_Y) / float(steps)
	for i in range(steps):
		var z := 10.8 + float(i) * 0.55
		var top := DECK_Y - float(i + 1) * drop
		_box(Vector3(3.0, 0.18, 0.62), _t3(Vector3(60, top - 0.09, z)),
			_mats["concrete"], _varc(Color(1, 1, 1), 0.06), false)
	# Angled walkable slab under the steps (39 deg, under the 45 deg floor limit).
	var ang := atan2(DECK_Y - DOCK_Y, 7.15)
	var slope := Transform3D(Basis(Vector3(1, 0, 0), ang), Vector3(60, 3.0, 14.3))
	_collide(Vector3(3.2, 0.25, 9.6), slope)
	# Side guard colliders + visual rails so nobody falls off the stairs.
	for gx in [58.35, 61.65]:
		_collide(Vector3(0.15, 1.3, 9.6),
			Transform3D(Basis(Vector3(1, 0, 0), ang), Vector3(gx, 3.6, 14.3)))
		_box(Vector3(0.1, 0.1, 9.6),
			Transform3D(Basis(Vector3(1, 0, 0), ang), Vector3(gx, 4.6, 14.3)),
			_mats["steel"], _varc(Color(1, 1, 1), 0.05), false)
	# Wooden dock platform, top at DOCK_Y.
	_box(Vector3(14, 0.25, 8), _t3(Vector3(61, DOCK_Y - 0.125, 22)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.10), false)
	_collide(Vector3(14, 0.5, 8), _t3(Vector3(61, DOCK_Y - 0.25, 22)))
	# Pilings down into the water.
	for px in [55.0, 61.0, 67.0]:
		for pz in [18.5, 25.5]:
			_cyl(0.18, 3.0, _t3(Vector3(px, 0.0, pz)),
				_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	# Mooring bollards.
	for bp in [[55.5, 19.0], [66.5, 19.0], [55.5, 25.0], [66.5, 25.0]]:
		_cyl(0.15, 0.7, _t3(Vector3(float(bp[0]), DOCK_Y + 0.35, float(bp[1]))),
			_mats["steel_dark"], _varc(Color(1, 1, 1), 0.06), true)
	# 3 canoes floating beside the dock + mooring ropes.
	var canoes := [[57.0, 29.0, 12.0], [61.0, 29.5, -8.0], [65.0, 29.0, 5.0]]
	for cn in canoes:
		var cx: float = cn[0]
		var cz: float = cn[1]
		var cyaw: float = cn[2]
		var hframe := Transform3D(Basis(Vector3.UP, deg_to_rad(cyaw)), Vector3(cx, 0, cz))
		_batch.add_rock(Vector3(3.4, 0.6, 1.1), hframe * _t3(Vector3(0, -0.72, 0)),
			_mats["canoe"], _varc(Color(0.42, 0.30, 0.17), 0.18))
		_box(Vector3(0.4, 0.08, 0.85), hframe * _t3(Vector3(0, -0.52, 0)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	_rope(Vector3(55.5, DOCK_Y + 0.5, 19.2), Vector3(57.0, -0.45, 28.2))
	_rope(Vector3(61.0, DOCK_Y + 0.5, 25.2), Vector3(61.0, -0.45, 28.7))
	_rope(Vector3(66.5, DOCK_Y + 0.5, 19.2), Vector3(65.0, -0.45, 28.2))
	# Supply crates on the dock.
	_box(Vector3(1.0, 1.0, 1.0), _t3(Vector3(63, DOCK_Y + 0.5, 20)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(1.0, 1.0, 1.0), _t3(Vector3(63, DOCK_Y + 0.5, 21.2)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(0.8, 0.8, 0.8), _t3(Vector3(63, DOCK_Y + 1.4, 20.6)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	house_positions.append(Vector3(61, DOCK_Y, 22))


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
	poi_list.append({"name": "Toll Plaza", "pos": Vector3(-30, DECK_Y, 0)})
	poi_list.append({"name": "Mid-Span", "pos": Vector3(0, DECK_Y, 0)})
	poi_list.append({"name": "North Landing", "pos": Vector3(-60, DECK_Y, 0)})
	poi_list.append({"name": "South Dock", "pos": Vector3(61, DOCK_Y, 22)})


func _clear_of_cars(x: float, z: float, radius: float) -> bool:
	for cp in _car_pos:
		var v: Vector2 = cp
		if v.distance_to(Vector2(x, z)) < radius:
			return false
	return true


func _claim(x: float, z: float, radius: float) -> bool:
	for q in _placed:
		var pq: Vector2 = q
		if pq.distance_to(Vector2(x, z)) < radius:
			return false
	_placed.append(Vector2(x, z))
	return true


func _loot_y_for(x: float, z: float) -> float:
	# Dock platform region sits at water level; everything else is the deck.
	if x >= 54.0 and x <= 68.0 and z >= 18.0 and z <= 26.0:
		return DOCK_Y + 0.55
	return DECK_Y + 0.55


func _on_deck(x: float, z: float) -> bool:
	return absf(x) <= 66.0 and absf(z) <= 8.6


func _on_dock(x: float, z: float) -> bool:
	return x >= 54.0 and x <= 68.0 and z >= 18.0 and z <= 26.0


func _scatter_loot() -> void:
	var kinds := ["health", "armor", "ammo"]
	var amounts := {"health": 40, "armor": 50, "ammo": 60}
	var idx := 0
	# Denser loot rings at each POI (deck POIs at deck height, South Dock at dock height).
	for p in poi_list:
		var pname: String = p["name"]
		var pp: Vector3 = p["pos"]
		for k in range(8):
			var a := TAU * float(k) / 8.0 + _rng.randf_range(-0.2, 0.2)
			var r := _rng.randf_range(3.0, 9.0)
			var lx := pp.x + cos(a) * r
			var lz := pp.z + sin(a) * r
			if pname == "South Dock":
				if not _on_dock(lx, lz):
					continue
			else:
				if not _on_deck(lx, lz):
					continue
				if not _clear_of_cars(lx, lz, 2.8):
					continue
			var kind: String = kinds[idx % 3]
			loot_spots.append([kind, int(amounts[kind]),
				Vector3(lx, _loot_y_for(lx, lz), lz)])
			idx += 1
	# General scatter along the deck.
	var tries := 0
	while loot_spots.size() < 72 and tries < 600:
		tries += 1
		var x := _rng.randf_range(-64, 64)
		var z := _rng.randf_range(-8, 8)
		if not _clear_of_cars(x, z, 3.2):
			continue
		if not _claim(x, z, 4.0):
			continue
		var kind2: String = kinds[idx % 3]
		loot_spots.append([kind2, int(amounts[kind2]), Vector3(x, DECK_Y + 0.55, z)])
		idx += 1
	# Loot on the dock platform too.
	tries = 0
	while loot_spots.size() < 80 and tries < 200:
		tries += 1
		var dx := _rng.randf_range(55, 67)
		var dz := _rng.randf_range(19, 25)
		if not _claim(dx, dz, 2.5):
			continue
		var kind3: String = kinds[idx % 3]
		loot_spots.append([kind3, int(amounts[kind3]), Vector3(dx, DOCK_Y + 0.55, dz)])
		idx += 1


func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -10, -85), Vector3(170, 60, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	enemy_spawns = [
		Vector3(-46, DECK_Y + 0.6, -1),
		Vector3(-18, DECK_Y + 0.6, -2),
		Vector3(8, DECK_Y + 0.6, 0),
		Vector3(36, DECK_Y + 0.6, -1),
		Vector3(50, DECK_Y + 0.6, -2),
		Vector3(61, DOCK_Y + 0.6, 22),
	]
	print("LagoonBridge built: instances=", _batch.box_count(), " draws=", draws,
		" colliders=", _batch.collider_count(), " loot=", loot_spots.size(),
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 110.0:
			cn.position.x = -110.0
