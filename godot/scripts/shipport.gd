extends Node3D
class_name ShipPortMap
## Phase 11: Ship Port — "Apapa" container terminal, deliberately industrial.
## Lagos' busiest port distilled into a combat arena: a dense container yard
## (colorful 40ft livery, stacked 1-3 high in laned rows), two ship-to-shore
## gantry cranes with climbable stair towers and lootable operator cabs, a
## moored cargo-ship hull section (deck y=4, accessible by ramp), two big
## enterable warehouses with real door/window openings, forklifts, yard
## trucks, light towers, and a guarded quay edge dropping to open water.
## Flat ground (y=0 on the quay; ship deck y=4 baked into spawns/loot):
## NO ground_height() — main.gd uses positions as-is.
## Seeded procedural (SEED), merge-ready 140x140m, clean origin.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261018
const WATER_Y := -1.5
const DECK_Y := 4.0

const CONTAINER_COLORS := [
	Color(0.78, 0.13, 0.10),  # red
	Color(0.10, 0.27, 0.66),  # blue
	Color(0.13, 0.52, 0.22),  # green
	Color(0.92, 0.72, 0.10),  # yellow
	Color(0.90, 0.42, 0.08),  # orange
]

var player_spawn := Vector3(-60, 0.6, 60)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3] (y baked, no lift added)
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # warehouses / ship / cranes (API compat)
var map_extent := MAP_EXTENT

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _clouds: Array = []
var _time := 0.0
var _placed: Array = []  # Vector2 points already used by loot (spacing)
var _open_pos: Array = []  # Vector2 centers of open containers (loot clearance)
var _li := 0  # loot kind cycler


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_water()
	_build_quay()
	_build_container_yard()
	_build_open_containers()
	_build_lookout_stairs()
	_build_cranes()
	_build_ship()
	_build_warehouses()
	_build_vehicles()
	_build_light_towers()
	_build_quay_edge()
	_build_gate_booth()
	_build_clouds()
	_build_pois()
	_scatter_loot()
	_finalize()


# ---------------- materials ----------------

func _std(rough := 0.85, metallic := 0.0) -> StandardMaterial3D:
	# All batched materials take their albedo from the per-instance color
	# (MultiMesh use_colors feeds COLOR; the flag below makes it the albedo).
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metallic
	return m


func _make_mats() -> void:
	_mats["quay"] = _std(0.95)
	_mats["concrete"] = _std(0.9)
	_mats["concrete_dark"] = _std(0.9)
	_mats["mark_white"] = _std(0.7)
	_mats["mark_yellow"] = _std(0.7)
	_mats["container"] = _std(0.55, 0.35)   # per-instance livery colors
	_mats["cont_trim"] = _std(0.6, 0.5)
	_mats["crane_white"] = _std(0.5, 0.3)
	_mats["crane_yellow"] = _std(0.5, 0.3)
	_mats["steel_dark"] = _std(0.6, 0.4)
	_mats["cable"] = _std(0.9)
	_mats["hull_black"] = _std(0.6, 0.3)
	_mats["deck_grey"] = _std(0.85)
	_mats["glass"] = _std(0.15, 0.8)
	_mats["wood"] = _std(0.9)
	_mats["crate"] = _std(0.9)
	_mats["forklift"] = _std(0.5, 0.2)       # per-instance safety yellows
	_mats["tire"] = _std(0.95)
	_mats["carpaint"] = _std(0.35, 0.4)      # per-instance truck colors
	_mats["rope"] = _std(0.95)
	_mats["warehouse_wall"] = _std(0.8)
	var lamp := _std(0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.55)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp_head"] = lamp


func _varc(c: Color, amt := 0.10) -> Color:
	var f := 1.0 + _rng.randf_range(-amt, amt)
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


func _pick(arr: Array) -> Color:
	return arr[_rng.randi_range(0, arr.size() - 1)]


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


func _strut(a: Vector3, b: Vector3, w: float, d: float, mat: StandardMaterial3D, col: Color) -> void:
	# Oriented box beam between two points (no collider).
	var dv := b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dv.x, dv.z)
	var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
	_box(Vector3(w, length, d), Transform3D(basis, mid), mat, col, false)


func _wall_open(frame: Transform3D, W: float, H: float, T: float, holes: Array,
		mat: StandardMaterial3D, col: Color, collide := true) -> void:
	# Wall with REAL openings. holes: Array of [x_center, y_bottom, w, h]
	# in wall-local coords (x along the wall, y up from its base).
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


func _stairs(frame: Transform3D, x0: float, run: float, width: float, zc: float, rise: float, y_base := 0.0) -> void:
	# Visual steps + one ramp collider (player walks up smoothly).
	# run may be negative (stairs descend toward +x); step width uses absf.
	var steps := 12
	var step_w := absf(run) / float(steps)
	for i in range(steps):
		var sx := x0 + run * (float(i) + 0.5) / float(steps)
		var sy := y_base + rise * (float(i) + 0.5) / float(steps)
		_box(Vector3(step_w + 0.05, 0.09, width),
			frame * _t3(Vector3(sx, sy - 0.045, zc)),
			_mats["concrete_dark"], Color(1, 1, 1), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var ramp := Transform3D(Basis(Vector3(0, 0, 1), ang),
		frame * Vector3(x0 + run * 0.5, y_base + rise * 0.5 - 0.06, zc))
	_batch.add_collider(Vector3(length, 0.12, width), ramp)
	# Handrail on the -z side.
	_strut(frame * Vector3(x0, y_base + 1.0, zc - width * 0.5),
		frame * Vector3(x0 + run, y_base + rise + 1.0, zc - width * 0.5),
		0.07, 0.07, _mats["steel_dark"], Color(1, 1, 1))


func _claim(x: float, z: float, radius: float) -> bool:
	for q in _placed:
		var qv: Vector2 = q
		if qv.distance_to(Vector2(x, z)) < radius:
			return false
	_placed.append(Vector2(x, z))
	return true


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


func _light_panel(lx: float, lz: float, fy: float) -> void:
	# Emissive ceiling light: housing + glowing diffuser (batched, no real light).
	_box(Vector3(2.0, 0.08, 1.1), _t3(Vector3(lx, fy, lz)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(1.8, 0.05, 0.9), _t3(Vector3(lx, fy - 0.055, lz)),
		_mats["lamp_head"], Color(1, 1, 1), false)

# ---------------- water & quay ----------------

func _build_water() -> void:
	var wm := PlaneMesh.new()
	wm.size = Vector2(140, 140)
	var mi := MeshInstance3D.new()
	mi.name = "HarbourWater"
	mi.mesh = wm
	mi.position = Vector3(0, WATER_Y, 0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/water.gdshader") as Shader
	mi.material_override = sm
	add_child(mi)
	# Dark void-catcher far below (seen through gaps at grazing angles).
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


func _build_quay() -> void:
	# Main concrete apron: x in [-70, 48], top exactly y=0.
	_box(Vector3(118, 0.5, 140), _t3(Vector3(-11, -0.25, 0)),
		_mats["quay"], _varc(Color(1, 1, 1), 0.05), false)
	_collide(Vector3(118, 0.6, 140), _t3(Vector3(-11, -0.3, 0)))
	# Quay wall face dropping to the water along x=48.
	_box(Vector3(0.5, 2.0, 140), _t3(Vector3(47.75, -1.0, 0)),
		_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.06), false)
	# Painted edge warning stripe (proud of the slab).
	_box(Vector3(0.5, 0.03, 140), _t3(Vector3(46.5, 0.015, 0)),
		_mats["mark_yellow"], Color(1, 1, 1), false)
	# Faded lane dashes down the main east-west driving lane.
	for i in range(20):
		var x := -62.0 + float(i) * 5.5
		_box(Vector3(2.4, 0.025, 0.15), _t3(Vector3(x, 0.0125, -52.0)),
			_mats["mark_white"], _varc(Color(1, 1, 1), 0.08), false)


# ---------------- container yard ----------------

func _in_plaza(cx: float, cz: float) -> bool:
	# Central open plaza: no stacks here (room for open containers + fights).
	return (cx == -14.0 or cx == 0.0 or cx == 14.0) and (cz == 4.0 or cz == 17.0)


func _container_at(cx: float, cz: float, lvl: int, yaw: float) -> void:
	# One 40ft box: 2.44 x 2.6 x 12.2, long axis along local Z.
	var base: Color = _pick(CONTAINER_COLORS)
	var col := _varc(base, 0.07)
	var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, float(lvl) * 2.6 + 1.3, cz))
	_box(Vector3(2.44, 2.6, 12.2), t, _mats["container"], col, false)
	# Door-end frames, proud of both ends.
	_box(Vector3(2.52, 2.68, 0.1), t * _t3(Vector3(0, 0, 6.08)),
		_mats["cont_trim"], Color(1, 1, 1), false)
	_box(Vector3(2.52, 2.68, 0.1), t * _t3(Vector3(0, 0, -6.08)),
		_mats["cont_trim"], Color(1, 1, 1), false)


func _deck_container_at(cx: float, cz: float, lvl: int) -> void:
	# 40ft box sitting on the ship deck (base y=DECK_Y).
	var base: Color = _pick(CONTAINER_COLORS)
	var col := _varc(base, 0.07)
	var t := Transform3D(Basis(), Vector3(cx, DECK_Y + float(lvl) * 2.6 + 1.3, cz))
	_box(Vector3(2.44, 2.6, 12.2), t, _mats["container"], col, false)
	_box(Vector3(2.52, 2.68, 0.1), t * _t3(Vector3(0, 0, 6.08)),
		_mats["cont_trim"], Color(1, 1, 1), false)
	_box(Vector3(2.52, 2.68, 0.1), t * _t3(Vector3(0, 0, -6.08)),
		_mats["cont_trim"], Color(1, 1, 1), false)


func _stack(cx: float, cz: float, h: int, yaw: float) -> void:
	for lvl in range(h):
		_container_at(cx, cz, lvl, yaw)
	# One full-height collider per stack (covers the whole tower).
	_batch.add_collider(Vector3(2.5, float(h) * 2.6, 12.3),
		Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, float(h) * 1.3, cz)))


func _build_container_yard() -> void:
	var cols := [-28.0, -14.0, 0.0, 14.0, 28.0]
	var rows := [-48.0, -35.0, -22.0, -9.0, 4.0, 17.0, 30.0, 43.0]
	for cx in cols:
		for cz in rows:
			if _in_plaza(cx, cz):
				continue
			var h := 1
			if cx == 28.0 and cz == -22.0:
				h = 3  # stair-step composition by the lookout
			elif cx == 28.0 and cz == -9.0:
				h = 2  # the rooftop lookout stack (top y=5.2)
			elif cx == 28.0 and cz == 4.0:
				h = 1
			else:
				var r := _rng.randf()
				if r < 0.40:
					h = 1
				elif r < 0.75:
					h = 2
				else:
					h = 3
			_stack(cx, cz, h, 0.0)
			# Painted corner markers for the slot (proud of the slab).
			for mx in [-1.5, 1.5]:
				for mz in [-6.4, 6.4]:
					_box(Vector3(0.35, 0.03, 0.35),
						_t3(Vector3(cx + mx, 0.015, cz + mz)),
						_mats["mark_yellow"], Color(1, 1, 1), false)


func _open_container(cx: float, cz: float, yaw: float) -> void:
	# Enterable 40ft box: floor, roof, side walls, back wall; front end OPEN
	# with one door panel swung out. Interior fits a standing player.
	var base: Color = _pick(CONTAINER_COLORS)
	var col := _varc(base, 0.07)
	var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0, cz))
	# Floor (walkable).
	_box(Vector3(2.44, 0.15, 12.2), t * _t3(Vector3(0, 0.075, 0)),
		_mats["container"], col, true)
	# Roof.
	_box(Vector3(2.44, 0.12, 12.2), t * _t3(Vector3(0, 2.54, 0)),
		_mats["container"], col, false)
	# Side walls.
	_box(Vector3(0.08, 2.5, 12.2), t * _t3(Vector3(-1.18, 1.32, 0)),
		_mats["container"], col, true)
	_box(Vector3(0.08, 2.5, 12.2), t * _t3(Vector3(1.18, 1.32, 0)),
		_mats["container"], col, true)
	# Back wall (local -z end).
	_box(Vector3(2.44, 2.6, 0.08), t * _t3(Vector3(0, 1.3, -6.06)),
		_mats["container"], col, true)
	# Open door panel, swung outward.
	var dt := t * Transform3D(Basis(Vector3.UP, 1.1), Vector3(1.35, 1.3, 6.5))
	_box(Vector3(1.15, 2.5, 0.07), dt, _mats["cont_trim"], Color(1, 1, 1), false)
	# Header beam over the open end (proud).
	_box(Vector3(2.52, 0.14, 0.14), t * _t3(Vector3(0, 2.56, 6.06)),
		_mats["cont_trim"], Color(1, 1, 1), false)


func _build_open_containers() -> void:
	var spots := [
		[-17.0, 6.0, 0.3], [-7.0, 12.0, -0.2], [3.0, 4.0, 0.1],
		[12.0, 14.0, 0.5], [-2.0, 20.0, -0.4], [17.0, 2.0, 0.9],
	]
	for s in spots:
		var cx: float = s[0]
		var cz: float = s[1]
		var yaw: float = s[2]
		_open_container(cx, cz, yaw)
		_open_pos.append(Vector2(cx, cz))
		var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0, cz))
		# Emissive ceiling strip inside the container.
		_box(Vector3(1.2, 0.05, 0.7), _t3(Vector3(cx, 2.3, cz)),
			_mats["lamp_head"], Color(1, 1, 1), false)
		# Furnishing: crate deep inside + 2 loot caches.
		var cp: Vector3 = t * Vector3(0.5, 0.7, -3.5)
		_box(Vector3(1.1, 1.1, 1.1), _t3(cp), _mats["crate"],
			_varc(Color(1, 1, 1), 0.08), true)
		var l1: Vector3 = t * Vector3(-0.4, 0.55, 2.5)
		var l2: Vector3 = t * Vector3(0.5, 0.55, 0.2)
		var la: Array = _next_loot()
		_loot_at(str(la[0]), int(la[1]), l1)
		var lb: Array = _next_loot()
		_loot_at(str(lb[0]), int(lb[1]), l2)


func _build_lookout_stairs() -> void:
	# Stair tower to the top of the 2-high stack at (28, -9): 5.2m lookout.
	# Flight 1: ground -> landing at 2.6. Flight 2: landing -> stack top 5.2.
	_stairs(Transform3D.IDENTITY, 39.5, -8.0, 2.0, -9.0, 2.6, 0.0)
	# Landing platform.
	_box(Vector3(2.6, 0.2, 2.6), _t3(Vector3(31.5, 2.5, -9.0)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	# Support posts under the platform.
	for px in [30.5, 32.5]:
		for pz in [-10.0, -8.0]:
			_box(Vector3(0.22, 2.5, 0.22), _t3(Vector3(px, 1.25, pz)),
				_mats["steel_dark"], Color(1, 1, 1), false)
	# Platform guard rails.
	for pz in [-10.2, -7.8]:
		_box(Vector3(2.6, 0.08, 0.08), _t3(Vector3(31.5, 3.5, pz)),
			_mats["steel_dark"], Color(1, 1, 1), false)
	for px in [30.3, 32.7]:
		_box(Vector3(0.08, 1.0, 0.08), _t3(Vector3(px, 3.0, -9.0)),
			_mats["steel_dark"], Color(1, 1, 1), false)
	_stairs(Transform3D.IDENTITY, 30.5, -3.0, 2.0, -9.0, 2.6, 2.6)
	# Lookout loot on the container top (y=5.2).
	var la: Array = _next_loot()
	_loot_at(str(la[0]), int(la[1]), Vector3(27.0, 5.75, -10.0))
	var lb: Array = _next_loot()
	_loot_at(str(lb[0]), int(lb[1]), Vector3(29.0, 5.75, -8.0))

# ---------------- gantry cranes ----------------

func _build_cranes() -> void:
	_crane(-20.0)
	_crane(0.0)
	house_positions.append(Vector3(32, 0, -20))
	house_positions.append(Vector3(32, 0, 0))


func _crane(zc: float) -> void:
	# Ship-to-shore signature: 4 legs (~18m), portal beams, machinery house,
	# 46m boom reaching over the quay edge and the ship, operator cab on a
	# stair tower, hanging cables + spreader bar.
	var white: StandardMaterial3D = _mats["crane_white"]
	var yellow: StandardMaterial3D = _mats["crane_yellow"]
	var dark: StandardMaterial3D = _mats["steel_dark"]
	# Legs + foot pads.
	for lx in [24.0, 40.0]:
		for lz in [zc - 6.0, zc + 6.0]:
			_box(Vector3(1.4, 18.0, 1.4), _t3(Vector3(lx, 9.0, lz)),
				white, _varc(Color(1, 1, 1), 0.05), true)
			_box(Vector3(3.0, 0.6, 3.0), _t3(Vector3(lx, 0.3, lz)),
				_mats["concrete_dark"], Color(1, 1, 1), false)
		# X cross-braces between the leg pair (high: players walk under).
		_strut(Vector3(lx, 6.0, zc - 6.0), Vector3(lx, 14.0, zc + 6.0),
			0.35, 0.35, white, Color(1, 1, 1))
		_strut(Vector3(lx, 6.0, zc + 6.0), Vector3(lx, 14.0, zc - 6.0),
			0.35, 0.35, white, Color(1, 1, 1))
	# Portal beams across the top.
	_box(Vector3(1.6, 1.6, 14.5), _t3(Vector3(24.0, 17.2, zc)), white, Color(1, 1, 1), false)
	_box(Vector3(1.6, 1.6, 14.5), _t3(Vector3(40.0, 17.2, zc)), white, Color(1, 1, 1), false)
	_box(Vector3(17.6, 1.6, 1.6), _t3(Vector3(32.0, 17.2, zc - 6.0)), white, Color(1, 1, 1), false)
	_box(Vector3(17.6, 1.6, 1.6), _t3(Vector3(32.0, 17.2, zc + 6.0)), white, Color(1, 1, 1), false)
	# Machinery house.
	_box(Vector3(7.0, 3.2, 5.5), _t3(Vector3(32.0, 19.6, zc)),
		yellow, _varc(Color(1, 1, 1), 0.05), true)
	# Boom: landside x=18 out over the ship to x=64.
	_box(Vector3(46.0, 1.8, 2.6), _t3(Vector3(41.0, 18.6, zc)),
		yellow, _varc(Color(1, 1, 1), 0.05), false)
	# Tie rods from the machinery house to boom tip and back end.
	_strut(Vector3(32.0, 21.2, zc), Vector3(62.0, 19.6, zc), 0.18, 0.18, dark, Color(1, 1, 1))
	_strut(Vector3(32.0, 21.2, zc), Vector3(20.0, 19.6, zc), 0.18, 0.18, dark, Color(1, 1, 1))
	# Trolley + hanging cables + spreader bar (over the ship side).
	_box(Vector3(2.5, 1.0, 3.0), _t3(Vector3(54.0, 17.2, zc)), dark, Color(1, 1, 1), false)
	_box(Vector3(0.09, 9.0, 0.09), _t3(Vector3(54.0, 13.1, zc - 0.9)),
		_mats["cable"], Color(1, 1, 1), false)
	_box(Vector3(0.09, 9.0, 0.09), _t3(Vector3(54.0, 13.1, zc + 0.9)),
		_mats["cable"], Color(1, 1, 1), false)
	_box(Vector3(0.6, 0.6, 6.5), _t3(Vector3(54.0, 8.4, zc)),
		yellow, Color(1, 1, 1), false)
	_build_cab(zc)
	# Access stair (ground -> y=8) + walkway to the cab door.
	_stairs(Transform3D.IDENTITY, 30.0, 10.0, 2.0, zc + 8.0, 8.0, 0.0)
	_box(Vector3(2.2, 0.25, 6.5), _t3(Vector3(40.0, 7.875, zc + 4.9)), dark, Color(1, 1, 1), true)
	for rz in [zc + 1.9, zc + 7.9]:
		_box(Vector3(2.2, 0.08, 0.08), _t3(Vector3(40.0, 8.95, rz)), white, Color(1, 1, 1), false)
	for px in [38.95, 41.05]:
		for pz in [zc + 2.2, zc + 4.9, zc + 7.6]:
			_box(Vector3(0.08, 1.0, 0.08), _t3(Vector3(px, 8.5, pz)), white, Color(1, 1, 1), false)
	# Support posts under the walkway.
	_box(Vector3(0.25, 7.8, 0.25), _t3(Vector3(39.2, 3.9, zc + 4.9)), dark, Color(1, 1, 1), false)
	_box(Vector3(0.25, 7.8, 0.25), _t3(Vector3(40.8, 3.9, zc + 4.9)), dark, Color(1, 1, 1), false)


func _build_cab(zc: float) -> void:
	# Operator cab hanging under the boom at (40, 8, zc): floor y=8.0,
	# window band facing the ship (+x, real openings), door on +z.
	var white: StandardMaterial3D = _mats["crane_white"]
	_box(Vector3(3.6, 0.25, 3.6), _t3(Vector3(40.0, 7.875, zc)),
		_mats["steel_dark"], Color(1, 1, 1), true)
	var H := 2.6
	_wall_open(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(41.8, 8.0, zc)),
		3.6, H, 0.15, [[-0.9, 1.0, 1.2, 1.2], [0.9, 1.0, 1.2, 1.2]],
		white, Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(38.2, 8.0, zc)),
		3.6, H, 0.15, [], white, Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(), Vector3(40.0, 8.0, zc + 1.8)),
		3.6, H, 0.15, [[0.0, 0.0, 1.6, 2.2]], white, Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(), Vector3(40.0, 8.0, zc - 1.8)),
		3.6, H, 0.15, [], white, Color(1, 1, 1), true)
	# Roof + hangers up to the boom.
	_box(Vector3(4.0, 0.25, 4.0), _t3(Vector3(40.0, 10.72, zc)), white, Color(1, 1, 1), false)
	_box(Vector3(0.3, 7.0, 0.3), _t3(Vector3(40.0, 14.2, zc - 1.2)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.3, 7.0, 0.3), _t3(Vector3(40.0, 14.2, zc + 1.2)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	# Control console + hot-zone loot.
	_box(Vector3(1.2, 0.9, 0.6), _t3(Vector3(41.0, 8.45, zc)),
		_mats["steel_dark"], Color(1, 1, 1), true)
	# Cab ceiling light (emissive).
	_light_panel(40.0, zc, 10.4)
	var la: Array = _next_loot()
	_loot_at(str(la[0]), int(la[1]), Vector3(39.3, 8.55, zc))
	var lb: Array = _next_loot()
	_loot_at(str(lb[0]), int(lb[1]), Vector3(40.7, 8.55, zc))


# ---------------- cargo ship ----------------

func _build_ship() -> void:
	# Hull section moored at the quay: x in [50, 68], z in [-30, 10],
	# deck plate top at DECK_Y=4.0. Gangway gap in the quay-side hull wall
	# at z in [0.5, 3.5] for the access ramp.
	var hull: StandardMaterial3D = _mats["hull_black"]
	_box(Vector3(18.0, 5.5, 30.5), _t3(Vector3(59.0, 1.25, -14.75)), hull, Color(1, 1, 1), true)
	_box(Vector3(18.0, 5.5, 6.5), _t3(Vector3(59.0, 1.25, 6.75)), hull, Color(1, 1, 1), true)
	# Low filler under the gangway gap (no see-through below the ramp).
	_box(Vector3(18.0, 2.0, 3.0), _t3(Vector3(59.0, -0.5, 2.0)), hull, Color(1, 1, 1), false)
	# Bow taper wedge at the north end (rotation on the mesh only).
	_box(Vector3(14.0, 5.0, 9.0),
		Transform3D(Basis(Vector3.UP, 0.45), Vector3(59.0, 1.5, 12.0)),
		hull, Color(1, 1, 1), false)
	# Deck plate + walkable collider.
	_box(Vector3(18.0, 0.3, 40.0), _t3(Vector3(59.0, 3.85, -10.0)),
		_mats["deck_grey"], Color(1, 1, 1), false)
	_collide(Vector3(18.0, 0.5, 40.0), _t3(Vector3(59.0, 3.75, -10.0)))
	# Draft marks, proud of the quay-side hull face.
	for dz in [-22.0, 2.0]:
		for dy in [0.5, 1.5, 2.5, 3.5]:
			_box(Vector3(0.06, 0.1, 2.0), _t3(Vector3(49.94, dy, dz)),
				_mats["mark_white"], Color(1, 1, 1), false)
	# Name board on the bow quarter.
	_box(Vector3(0.06, 1.0, 6.0), _t3(Vector3(49.94, 2.2, -18.0)),
		_mats["mark_white"], Color(1, 1, 1), false)
	# Bulwark railings around the deck (gap at the ramp landing z in [0, 4]).
	_box(Vector3(0.25, 1.2, 30.0), _t3(Vector3(50.1, 4.6, -15.0)), hull, Color(1, 1, 1), true)
	_box(Vector3(0.25, 1.2, 6.0), _t3(Vector3(50.1, 4.6, 7.0)), hull, Color(1, 1, 1), true)
	_box(Vector3(0.25, 1.2, 40.0), _t3(Vector3(67.9, 4.6, -10.0)), hull, Color(1, 1, 1), true)
	_box(Vector3(18.0, 1.2, 0.25), _t3(Vector3(59.0, 4.6, -29.9)), hull, Color(1, 1, 1), true)
	_box(Vector3(18.0, 1.2, 0.25), _t3(Vector3(59.0, 4.6, 9.9)), hull, Color(1, 1, 1), true)
	# Bulwark cap rails (proud).
	_box(Vector3(0.35, 0.1, 30.0), _t3(Vector3(50.1, 5.25, -15.0)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.35, 0.1, 40.0), _t3(Vector3(67.9, 5.25, -10.0)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	# Containers stacked on deck.
	for dx in [56.0, 63.0]:
		for dz in [-22.0, -12.0, -2.0]:
			var h := 1 + _rng.randi_range(0, 1)
			for lvl in range(h):
				_deck_container_at(dx, dz, lvl)
			_batch.add_collider(Vector3(2.5, float(h) * 2.6, 12.3),
				_t3(Vector3(dx, DECK_Y + float(h) * 1.3, dz)))
	_build_deckhouse()
	# Access ramp: quay (44, 0, 2) up through the gangway gap to deck (52, 4, 2).
	_stairs(Transform3D.IDENTITY, 44.0, 8.0, 2.4, 2.0, 4.0, 0.0)
	# Mooring lines from quay bollards to the hull.
	_strut(Vector3(47.5, 0.8, -26.0), Vector3(51.0, 3.2, -26.0),
		0.12, 0.12, _mats["rope"], Color(1, 1, 1))
	_strut(Vector3(47.5, 0.8, 6.0), Vector3(51.0, 3.2, 6.0),
		0.12, 0.12, _mats["rope"], Color(1, 1, 1))
	# Tire fenders on the quay-side hull face.
	for fz in [-24.0, -16.0, -4.0, 4.0]:
		_cyl(0.35, 0.5, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(49.85, 0.5, fz)),
			_mats["tire"], Color(1, 1, 1), false)
	# Foremast on the foredeck.
	_cyl(0.09, 6.0, _t3(Vector3(59.0, 7.0, -28.0)), _mats["steel_dark"], Color(1, 1, 1), false)
	_strut(Vector3(59.0, 9.5, -28.0), Vector3(59.0, 9.5, -24.5), 0.07, 0.07,
		_mats["steel_dark"], Color(1, 1, 1))
	house_positions.append(Vector3(59, 0, -10))

func _build_deckhouse() -> void:
	# Deckhouse at the north end of the deck: 7 x 6 footprint, base y=4.0,
	# walls h=4.5 with a real door (faces the deck, -z) and window openings.
	var white: StandardMaterial3D = _mats["crane_white"]
	var H := 4.5
	_wall_open(Transform3D(Basis(), Vector3(59.0, 4.0, 3.5)),
		7.0, H, 0.2, [[0.0, 0.0, 1.6, 2.6], [-2.2, 1.4, 1.4, 1.2], [2.2, 1.4, 1.4, 1.2]],
		white, Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(), Vector3(59.0, 4.0, 9.5)),
		7.0, H, 0.2, [[-1.8, 2.6, 1.0, 1.0], [0.0, 2.6, 1.0, 1.0], [1.8, 2.6, 1.0, 1.0]],
		white, Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(62.5, 4.0, 6.5)),
		6.0, H, 0.2, [[0.0, 3.0, 2.0, 0.8]], white, Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(55.5, 4.0, 6.5)),
		6.0, H, 0.2, [[0.0, 3.0, 2.0, 0.8]], white, Color(1, 1, 1), true)
	# Internal stairs (ground -> upper bridge deck).
	_stairs(Transform3D.IDENTITY, 61.5, -5.0, 1.8, 6.5, 3.5, 4.0)
	# Upper floor slab with stairwell hole (bridge deck at y=7.5).
	var df := Transform3D(Basis(), Vector3(59.0, 4.0, 6.5))
	_slab_hole(df, 7.0, 6.0, 3.5, 0.5, 2.5, 0.0, 1.8)
	# Bridge deck walls: wide window bands, 2.8 high.
	_wall_open(df * _t3(Vector3(0, 3.5, -3.0)), 7.0, 2.8, 0.2,
		[[-2.2, 1.2, 1.4, 1.0], [0.0, 1.2, 1.4, 1.0], [2.2, 1.2, 1.4, 1.0]],
		white, Color(1, 1, 1), true)
	_wall_open(df * _t3(Vector3(0, 3.5, 3.0)), 7.0, 2.8, 0.2,
		[[-2.2, 1.2, 1.4, 1.0], [0.0, 1.2, 1.4, 1.0], [2.2, 1.2, 1.4, 1.0]],
		white, Color(1, 1, 1), true)
	_wall_open(df * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(3.5, 3.5, 0)), 6.0, 2.8, 0.2,
		[[0.0, 1.2, 2.0, 1.0]], white, Color(1, 1, 1), true)
	_wall_open(df * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-3.5, 3.5, 0)), 6.0, 2.8, 0.2,
		[[0.0, 1.2, 2.0, 1.0]], white, Color(1, 1, 1), true)
	# Bridge consoles with glowing screens + chart table.
	for ccx in [-1.8, 1.8]:
		_box(Vector3(1.6, 0.75, 0.6), df * _t3(Vector3(float(ccx), 3.875, -1.8)),
			_mats["steel_dark"], Color(1, 1, 1), true)
		_box(Vector3(1.5, 0.7, 0.08),
			df * Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(float(ccx), 4.55, -1.7)),
			_mats["lamp_head"], Color(0.7, 0.85, 1.0), false)
	_box(Vector3(2.4, 0.08, 1.4), df * _t3(Vector3(0.0, 4.29, 1.2)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	# Bridge deck ceiling light + loot.
	_light_panel(59.0, 6.5, 10.0)
	var l2a: Array = _next_loot()
	_loot_at(str(l2a[0]), int(l2a[1]), Vector3(57.5, 8.05, 5.0))
	var l2b: Array = _next_loot()
	_loot_at(str(l2b[0]), int(l2b[1]), Vector3(60.5, 8.05, 7.5))
	# Roof + funnel (raised for the new bridge deck).
	_box(Vector3(7.6, 0.3, 6.6), _t3(Vector3(59.0, 10.45, 6.5)), white, Color(1, 1, 1), false)
	_cyl(1.0, 3.0, _t3(Vector3(59.0, 12.0, 7.5)), _mats["hull_black"], Color(1, 1, 1), false)
	_cyl(1.05, 0.6, _t3(Vector3(59.0, 13.2, 7.5)), _mats["steel_dark"], Color(1, 1, 1), false)
	# Bridge loot inside (moved clear of the stairs).
	var la: Array = _next_loot()
	_loot_at(str(la[0]), int(la[1]), Vector3(57.5, 4.55, 4.5))


# ---------------- warehouses ----------------

func _warehouse(cx: float, cz: float) -> void:
	# 24 x 12 industrial warehouse, walls h=7, big door on the +x face,
	# high window slits on the sides (real openings, no glass).
	var W := 24.0
	var D := 12.0
	var H := 7.0
	var T := 0.35
	var wall: StandardMaterial3D = _mats["warehouse_wall"]
	# Interior floor paint (proud of the slab).
	_box(Vector3(W - 1.0, 0.03, D - 1.0), _t3(Vector3(cx, 0.015, cz)),
		_mats["concrete_dark"], Color(1, 1, 1), false)
	# Front (+x): 6m x 5m roller door opening.
	_wall_open(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx + W * 0.5, 0, cz)),
		D, H, T, [[0.0, 0.0, 6.0, 5.0]], wall, Color(1, 1, 1), true)
	# Back (-x): solid.
	_wall_open(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx - W * 0.5, 0, cz)),
		D, H, T, [], wall, Color(1, 1, 1), true)
	# Sides: high window slits.
	_wall_open(Transform3D(Basis(), Vector3(cx, 0, cz + D * 0.5)),
		W, H, T, [[-6.0, 4.5, 2.0, 1.2], [0.0, 4.5, 2.0, 1.2], [6.0, 4.5, 2.0, 1.2]],
		wall, Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(), Vector3(cx, 0, cz - D * 0.5)),
		W, H, T, [[-6.0, 4.5, 2.0, 1.2], [0.0, 4.5, 2.0, 1.2], [6.0, 4.5, 2.0, 1.2]],
		wall, Color(1, 1, 1), true)
	# Mezzanine office: slab x cx-12..cx-2, z cz-6..cz+6, top y=3.5.
	_box(Vector3(10.0, 0.25, 12.0), _t3(Vector3(cx - 7.0, 3.375, cz)),
		_mats["concrete_dark"], Color(1, 1, 1), true)
	for mcx in [-12.0, -2.0]:
		for mcz in [-6.0, 6.0]:
			_box(Vector3(0.3, 3.5, 0.3),
				_t3(Vector3(cx + float(mcx), 1.75, cz + float(mcz))),
				_mats["concrete_dark"], Color(1, 1, 1), true)
	# Stairs up from the warehouse floor to the mezz east edge.
	_stairs(Transform3D.IDENTITY, cx - 7.0, 5.0, 2.0, cz + 4.5, 3.5, 0.0)
	# Railing: east edge (gap at the stairs), north + south edges.
	_box(Vector3(0.08, 0.08, 9.5), _t3(Vector3(cx - 2.0, 4.5, cz - 1.25)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(10.0, 0.08, 0.08), _t3(Vector3(cx - 7.0, 4.5, cz - 6.0)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(10.0, 0.08, 0.08), _t3(Vector3(cx - 7.0, 4.5, cz + 6.0)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	for i in range(6):
		_box(Vector3(0.07, 1.0, 0.07),
			_t3(Vector3(cx - 11.0 + float(i) * 1.8, 4.0, cz - 6.0)),
			_mats["steel_dark"], Color(1, 1, 1), false)
	# Mezz office: desk, crates, loot.
	_box(Vector3(1.8, 0.08, 0.9), _t3(Vector3(cx - 7.0, 4.29, cz)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	_box(Vector3(1.6, 0.75, 0.7), _t3(Vector3(cx - 7.0, 3.875, cz)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), false)
	_box(Vector3(0.9, 0.9, 0.9), _t3(Vector3(cx - 4.0, 3.95, cz + 3.0)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.08), true)
	var mla: Array = _next_loot()
	_loot_at(str(mla[0]), int(mla[1]), Vector3(cx - 9.0, 4.05, cz - 3.0))
	var mlb: Array = _next_loot()
	_loot_at(str(mlb[0]), int(mlb[1]), Vector3(cx - 4.5, 4.05, cz + 1.0))
	# Roof access stairs (mezzanine -> roof).
	_stairs(Transform3D.IDENTITY, cx - 11.0, 5.0, 2.0, cz - 4.5, 3.5, 3.5)
	# Flat roof slab (walkable) with stairwell hole + parapet.
	var wframe := Transform3D(Basis(), Vector3(cx, 0, cz))
	_slab_hole(wframe, W, D, H, -8.5, -5.5, -4.5, 2.0)
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(W + 0.4, 0.8, 0.25),
			_t3(Vector3(cx, H + 0.4, cz + ef * (D * 0.5 + 0.075))),
			wall, Color(1, 1, 1), true)
		_box(Vector3(0.25, 0.8, D + 0.4),
			_t3(Vector3(cx + ef * (W * 0.5 + 0.075), H + 0.4, cz)),
			wall, Color(1, 1, 1), true)
	# Rooftop loot (roof reachable via the mezzanine stairs).
	var rla: Array = _next_loot()
	_loot_at(str(rla[0]), int(rla[1]), Vector3(cx + 6.0, H + 0.55, cz + 3.0))
	var rlb: Array = _next_loot()
	_loot_at(str(rlb[0]), int(rlb[1]), Vector3(cx - 2.0, H + 0.55, cz - 3.0))
	# "WAREHOUSE" sign over the +x door.
	_box(Vector3(0.12, 0.8, 6.0), _t3(Vector3(cx + W * 0.5 + 0.25, 5.6, cz)),
		_mats["concrete_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.03, 0.5, 5.4), _t3(Vector3(cx + W * 0.5 + 0.32, 5.6, cz)),
		_mats["lamp_head"], Color(1, 1, 1), false)
	# Emissive ceiling light panels (kept clear of the roof stairwell).
	for lxx in [-2.0, 6.0]:
		for lzz in [-3.0, 3.0]:
			_light_panel(cx + float(lxx), cz + float(lzz), 6.6)
	# Raised monitor strip with louver vents.
	_box(Vector3(W * 0.7, 1.4, 4.0), _t3(Vector3(cx, H + 1.0, cz)), wall, Color(1, 1, 1), false)
	for i in range(6):
		var lx := cx - W * 0.3 + float(i) * (W * 0.6 / 5.0)
		_box(Vector3(0.9, 0.8, 0.1), _t3(Vector3(lx, H + 1.0, cz + 2.02)),
			_mats["steel_dark"], Color(1, 1, 1), false)
	# Corner pilasters (proud).
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.6, H, 0.6),
				_t3(Vector3(cx + sx * (W * 0.5 - 0.1), H * 0.5, cz + sz * (D * 0.5 - 0.1))),
				_mats["concrete_dark"], Color(1, 1, 1), false)
	# Door canopy.
	_box(Vector3(3.0, 0.25, 8.0), _t3(Vector3(cx + W * 0.5 + 1.4, 5.3, cz)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	house_positions.append(Vector3(cx, 0, cz))


func _pallet_cluster(px: float, pz: float) -> void:
	# 2x2 pallets, two high (visual cover, no colliders: low).
	for ox in [-0.7, 0.7]:
		for oz in [-0.7, 0.7]:
			_box(Vector3(1.2, 0.14, 1.2), _t3(Vector3(px + ox, 0.07, pz + oz)),
				_mats["wood"], _varc(Color(1, 1, 1), 0.08), false)
			_box(Vector3(1.1, 0.8, 1.1), _t3(Vector3(px + ox, 0.54, pz + oz)),
				_mats["crate"], _varc(Color(1, 1, 1), 0.08), false)
			_box(Vector3(1.1, 0.8, 1.1), _t3(Vector3(px + ox, 1.34, pz + oz)),
				_mats["crate"], _varc(Color(1, 1, 1), 0.08), false)


func _build_warehouses() -> void:
	_warehouse(-52.0, -42.0)
	_warehouse(-52.0, 28.0)
	# W1 interior: pallets, crates, parked forklift (forklifts built later).
	_pallet_cluster(-58.0, -44.0)
	_pallet_cluster(-46.0, -44.0)
	for i in range(3):
		_box(Vector3(1.0, 1.0, 1.0), _t3(Vector3(-47.0 + float(i) * 1.1, 0.5, -39.0)),
			_mats["crate"], _varc(Color(1, 1, 1), 0.08), true)
	# W1: oil drum row along the back wall.
	var drum_cols := [Color(0.75, 0.25, 0.15), Color(0.20, 0.35, 0.60), Color(0.55, 0.45, 0.15)]
	for di2 in range(3):
		_cyl(0.35, 0.9, _t3(Vector3(-60.0 + float(di2) * 0.85, 0.45, -46.5)),
			_mats["crate"], drum_cols[di2 % 3], true)
	# W2 interior.
	_pallet_cluster(-58.0, 24.0)
	_pallet_cluster(-46.0, 32.0)
	for i in range(3):
		_box(Vector3(1.0, 1.0, 1.0), _t3(Vector3(-47.0 + float(i) * 1.1, 0.5, 31.0)),
			_mats["crate"], _varc(Color(1, 1, 1), 0.08), true)
	# W2: oil drum row along the back wall.
	for di3 in range(3):
		_cyl(0.35, 0.9, _t3(Vector3(-60.0 + float(di3) * 0.85, 0.45, 32.5)),
			_mats["crate"], drum_cols[di3 % 3], true)
	# Interior loot (5 per warehouse).
	for lp in [[-60.0, -38.0], [-45.0, -45.0], [-52.0, -46.0], [-58.0, -40.0], [-46.0, -37.0]]:
		var la: Array = _next_loot()
		_loot_at(str(la[0]), int(la[1]), Vector3(float(lp[0]), 0.55, float(lp[1])))
	for lp in [[-60.0, 32.0], [-45.0, 25.0], [-52.0, 24.0], [-58.0, 30.0], [-46.0, 33.0]]:
		var lb: Array = _next_loot()
		_loot_at(str(lb[0]), int(lb[1]), Vector3(float(lp[0]), 0.55, float(lp[1])))


# ---------------- vehicles & props ----------------

func _forklift(x: float, z: float, yaw: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var ycol := _varc(Color(0.95, 0.65, 0.08), 0.06)
	# Body.
	_box(Vector3(1.6, 0.9, 2.2), t * _t3(Vector3(0, 0.75, 0.3)),
		_mats["forklift"], ycol, true)
	# Cab posts + roof.
	for px in [-0.7, 0.7]:
		for pz in [-0.4, 0.9]:
			_box(Vector3(0.08, 1.0, 0.08), t * _t3(Vector3(px, 1.7, pz)),
				_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(1.6, 0.08, 1.5), t * _t3(Vector3(0, 2.24, 0.25)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	# Mast (front = local -z) + forks.
	_box(Vector3(0.12, 2.6, 0.12), t * _t3(Vector3(-0.5, 1.3, -0.85)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.12, 2.6, 0.12), t * _t3(Vector3(0.5, 1.3, -0.85)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(1.1, 0.12, 0.12), t * _t3(Vector3(0, 2.5, -0.85)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.15, 0.08, 1.2), t * _t3(Vector3(-0.3, 0.12, -1.5)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.15, 0.08, 1.2), t * _t3(Vector3(0.3, 0.12, -1.5)),
		_mats["steel_dark"], Color(1, 1, 1), false)
	# Wheels.
	for wx in [-0.75, 0.75]:
		for wz in [-0.5, 0.9]:
			_cyl(0.28, 0.2,
				t * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(wx, 0.28, wz)),
				_mats["tire"], Color(1, 1, 1), false)


func _truck(x: float, z: float, yaw: float) -> void:
	# Yard tractor + skeletal trailer carrying a 40ft box.
	var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var cabcol := _varc(_pick([Color(0.75, 0.12, 0.10), Color(0.10, 0.30, 0.60)]), 0.06)
	# Cab (front = local +z).
	_box(Vector3(2.4, 2.0, 2.2), t * _t3(Vector3(0, 1.5, 4.2)),
		_mats["carpaint"], cabcol, true)
	_box(Vector3(2.0, 0.8, 0.1), t * _t3(Vector3(0, 1.9, 5.32)),
		_mats["glass"], Color(0.7, 0.85, 0.9), false)
	# Chassis + flatbed.
	_box(Vector3(2.5, 0.5, 9.0), t * _t3(Vector3(0, 0.9, -1.0)),
		_mats["steel_dark"], Color(1, 1, 1), true)
	# 40ft box riding the trailer.
	var base: Color = _pick(CONTAINER_COLORS)
	_box(Vector3(2.44, 2.6, 9.5), t * _t3(Vector3(0, 2.45, -1.0)),
		_mats["container"], _varc(base, 0.07), false)
	# Wheels (3 axles).
	for wz in [3.4, -1.5, -3.5]:
		for wx in [-1.1, 1.1]:
			_cyl(0.42, 0.3,
				t * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(wx, 0.42, wz)),
				_mats["tire"], Color(1, 1, 1), false)


func _build_vehicles() -> void:
	_forklift(-57.0, -44.0, 0.5)   # W1 interior
	_forklift(-48.0, 26.0, -0.4)   # W2 interior
	_forklift(20.0, -38.0, 2.2)    # yard
	_truck(38.0, 24.0, 0.15)
	_truck(38.0, -34.0, -0.1)


func _build_light_towers() -> void:
	for lt in [[-21.0, -52.0], [-21.0, 52.0], [7.0, -52.0], [7.0, 52.0], [38.0, -44.0], [38.0, 44.0]]:
		var lx: float = lt[0]
		var lz: float = lt[1]
		_cyl(0.14, 9.5, _t3(Vector3(lx, 4.75, lz)),
			_mats["steel_dark"], Color(1, 1, 1), true)
		_box(Vector3(2.0, 0.18, 0.5), _t3(Vector3(lx, 9.6, lz)),
			_mats["steel_dark"], Color(1, 1, 1), false)
		_box(Vector3(0.7, 0.35, 0.4), _t3(Vector3(lx - 0.55, 9.32, lz)),
			_mats["lamp_head"], Color(1, 1, 1), false)
		_box(Vector3(0.7, 0.35, 0.4), _t3(Vector3(lx + 0.55, 9.32, lz)),
			_mats["lamp_head"], Color(1, 1, 1), false)


func _build_quay_edge() -> void:
	# Guarded quay edge: visual railing + invisible guard wall (ship zone excluded).
	for seg in [[-70.0, -30.0], [10.0, 70.0]]:
		var z0: float = seg[0]
		var z1: float = seg[1]
		var zc := (z0 + z1) * 0.5
		var ln := z1 - z0
		var n := int(ln / 3.0)
		for i in range(n + 1):
			var pz := z0 + ln * float(i) / float(n)
			_box(Vector3(0.12, 1.1, 0.12), _t3(Vector3(47.5, 0.55, pz)),
				_mats["steel_dark"], Color(1, 1, 1), false)
		_box(Vector3(0.08, 0.08, ln), _t3(Vector3(47.5, 1.05, zc)),
			_mats["steel_dark"], Color(1, 1, 1), false)
		_box(Vector3(0.08, 0.08, ln), _t3(Vector3(47.5, 0.65, zc)),
			_mats["steel_dark"], Color(1, 1, 1), false)
		_collide(Vector3(0.4, 1.6, ln), _t3(Vector3(47.5, 0.8, zc)))
	# Bollards along the edge (skip the ship zone) + coiled ropes.
	var bz := -66.0
	var alt := false
	while bz <= 66.0:
		if bz < -32.0 or bz > 12.0:
			_cyl(0.28, 0.9, _t3(Vector3(46.8, 0.45, bz)),
				_mats["steel_dark"], Color(1, 1, 1), true)
			if alt:
				_cyl(0.6, 0.25, _t3(Vector3(45.9, 0.125, bz + 1.6)),
					_mats["rope"], _varc(Color(1, 1, 1), 0.08), false)
			alt = not alt
		bz += 8.0
	# Loose pallets in the apron.
	for pp in [[36.0, -8.0], [34.0, 18.0], [42.0, 2.0]]:
		_box(Vector3(1.2, 0.14, 1.2), _t3(Vector3(float(pp[0]), 0.07, float(pp[1]))),
			_mats["wood"], _varc(Color(1, 1, 1), 0.08), false)


func _build_gate_booth() -> void:
	# Gatehouse by the player spawn: 3x3, window bands (real openings), door.
	var bx := -58.0
	var bz := 52.0
	_wall_open(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(bx + 1.5, 0, bz)),
		3.0, 2.8, 0.15, [[0.0, 0.0, 1.0, 2.2]], _mats["concrete"], Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(bx - 1.5, 0, bz)),
		3.0, 2.8, 0.15, [], _mats["concrete"], Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(), Vector3(bx, 0, bz + 1.5)),
		3.0, 2.8, 0.15, [[0.0, 1.0, 2.0, 1.2]], _mats["concrete"], Color(1, 1, 1), true)
	_wall_open(Transform3D(Basis(), Vector3(bx, 0, bz - 1.5)),
		3.0, 2.8, 0.15, [[0.0, 1.0, 2.0, 1.2]], _mats["concrete"], Color(1, 1, 1), true)
	_box(Vector3(3.8, 0.2, 3.8), _t3(Vector3(bx, 2.9, bz)),
		_mats["concrete_dark"], Color(1, 1, 1), false)
	# Barrier arm + post.
	_box(Vector3(0.15, 0.15, 6.0), _t3(Vector3(bx + 4.0, 1.1, bz + 3.0)),
		_mats["mark_white"], Color(1, 1, 1), false)
	_box(Vector3(0.4, 1.2, 0.4), _t3(Vector3(bx + 4.0, 0.6, bz)),
		_mats["steel_dark"], Color(1, 1, 1), true)


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


# ---------------- pois & loot ----------------

func _build_pois() -> void:
	poi_list = [
		{"name": "Container Yard", "pos": Vector3(-7, 0.0, 10)},
		{"name": "Crane Row", "pos": Vector3(32, 0.0, -5)},
		{"name": "The Ship", "pos": Vector3(59, 4.0, -10)},
		{"name": "Warehouses", "pos": Vector3(-52, 0.0, -7)},
	]


func _next_loot() -> Array:
	var kinds := ["health", "armor", "ammo"]
	var amounts := {"health": 40, "armor": 50, "ammo": 60}
	var k: String = kinds[_li % 3]
	_li += 1
	return [k, int(amounts[k])]


func _loot_at(kind: String, amount: int, pos: Vector3) -> void:
	loot_spots.append([kind, amount, pos])


func _near_open(x: float, z: float, radius: float) -> bool:
	for q in _open_pos:
		var qv: Vector2 = q
		if qv.distance_to(Vector2(x, z)) < radius:
			return true
	return false


func _ring_loot(center: Vector3, y: float, attempts: int) -> void:
	for k in range(attempts):
		var a := TAU * float(k) / float(attempts) + _rng.randf_range(-0.2, 0.2)
		var r := _rng.randf_range(3.0, 8.0)
		var lx := center.x + cos(a) * r
		var lz := center.z + sin(a) * r
		if absf(lx) > 66.0 or absf(lz) > 66.0:
			continue
		if not _claim(lx, lz, 2.5):
			continue
		if _near_open(lx, lz, 2.0):
			continue
		var la: Array = _next_loot()
		_loot_at(str(la[0]), int(la[1]), Vector3(lx, y, lz))


func _clear_for_loot(x: float, z: float) -> bool:
	# Reject points inside container stacks, warehouses, crane legs, ship/water.
	if x > 46.0:
		return false
	for cx in [-28.0, -14.0, 0.0, 14.0, 28.0]:
		for cz in [-48.0, -35.0, -22.0, -9.0, 4.0, 17.0, 30.0, 43.0]:
			if _in_plaza(cx, cz):
				continue
			if absf(x - cx) < 2.2 and absf(z - cz) < 7.2:
				return false
	if absf(x + 52.0) < 13.5 and (absf(z + 42.0) < 7.5 or absf(z - 28.0) < 7.5):
		return false
	for lx in [24.0, 40.0]:
		for zc in [-20.0, 0.0]:
			for lz in [zc - 6.0, zc + 6.0]:
				if absf(x - lx) < 1.6 and absf(z - lz) < 1.6:
					return false
	return _claim(x, z, 3.0)


func _scatter_loot() -> void:
	# Dense rings at the two ground-level POIs (open areas).
	_ring_loot(Vector3(-7, 0, 10), 0.55, 10)
	_ring_loot(Vector3(-52, 0, -7), 0.55, 10)
	# Crane Row: hand-placed (clear of legs + stairs).
	for lp in [[28.0, -10.0], [28.0, 2.0], [36.0, -2.0], [28.0, 10.0],
			[27.0, -18.0], [37.0, 12.0], [32.0, -20.0], [32.0, -24.0]]:
		var la: Array = _next_loot()
		_loot_at(str(la[0]), int(la[1]), Vector3(float(lp[0]), 0.55, float(lp[1])))
	# Ship deck (y=4.0) + foredeck.
	for lp in [[59.5, -26.0], [59.5, -17.0], [59.5, -7.0], [59.5, 3.0],
			[52.5, -17.0], [52.5, -7.0], [65.5, -17.0], [65.5, -7.0]]:
		var lb: Array = _next_loot()
		_loot_at(str(lb[0]), int(lb[1]), Vector3(float(lp[0]), 4.55, float(lp[1])))
	# Scattered yard caches.
	for lp in [[-21.0, -40.0], [-7.0, -25.0], [7.0, 25.0], [21.0, 40.0],
			[-35.0, 10.0], [35.0, -30.0], [20.0, -45.0], [-20.0, 48.0]]:
		if not _claim(float(lp[0]), float(lp[1]), 3.0):
			continue
		var lc: Array = _next_loot()
		_loot_at(str(lc[0]), int(lc[1]), Vector3(float(lp[0]), 0.55, float(lp[1])))
	# Top up to the target band (open containers 12 + cabs 4 + deckhouse 1 +
	# lookout 2 + warehouses 10 already placed during the build).
	var tries := 0
	while loot_spots.size() < 68 and tries < 400:
		tries += 1
		var x := _rng.randf_range(-62.0, 44.0)
		var z := _rng.randf_range(-62.0, 62.0)
		if not _clear_for_loot(x, z):
			continue
		var ld: Array = _next_loot()
		_loot_at(str(ld[0]), int(ld[1]), Vector3(x, 0.55, z))


func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -10, -85), Vector3(170, 60, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	player_spawn = Vector3(-60, 0.6, 60)
	enemy_spawns = [
		Vector3(-20, 0.6, -30),
		Vector3(10, 0.6, 30),
		Vector3(32, 0.6, -25),
		Vector3(59, 4.6, -6),
		Vector3(-49, 0.6, -39),
		Vector3(-55, 0.6, 30),
	]
	print("ShipPort built: instances=", _batch.box_count(), " draws=", draws,
		" colliders=", _batch.collider_count(), " loot=", loot_spots.size(),
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 110.0:
			cn.position.x = -110.0
