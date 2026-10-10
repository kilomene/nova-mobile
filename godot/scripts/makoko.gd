extends Node3D
class_name MakokoMap
## Phase 2: full detailed Makoko village battle-royale map (seeded procedural).
## Dense stilt-house village on animated lagoon water. Self-contained scene:
## origin at village center, everything inside MAP_EXTENT square (merge-ready).

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const WATER_Y := -1.0
const SEED := 20261009

var player_spawn := Vector3(0, 0.6, 52.0)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []
var map_extent := MAP_EXTENT

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _houses: Array = []  # {"center", "yaw", "w", "d", "cluster"}
var _canoes: Array = []  # {"node", "base_y", "phase", "speed", "roll"}
var _clouds: Array = []
var _time := 0.0
var _canoe_mesh: ArrayMesh
var _canoe_mat: StandardMaterial3D

const CLUSTERS := [
	Vector2(-32, -30), Vector2(30, -30), Vector2(-30, 30),
	Vector2(32, 32), Vector2(0, 2),
]
const POIS := [
	{"name": "Main Dock", "pos": Vector3(0, 0, 50)},
	{"name": "Market Row", "pos": Vector3(-42, 0, -6)},
	{"name": "Old Shrine", "pos": Vector3(46, 0, -40)},
	{"name": "Canoe Yard", "pos": Vector3(-10, 0, -46)},
]


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_canoe_mesh = _make_canoe_mesh()
	_build_water()
	_build_pois()
	_build_houses()
	_build_walkways()
	_build_links()
	_build_props()
	_build_canoes()
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
	_mats["wood"] = _std(Color(0.46, 0.33, 0.21))
	_mats["wood_dark"] = _std(Color(0.30, 0.21, 0.13))
	_mats["wall_wood"] = _std(Color(0.55, 0.42, 0.28))
	_mats["wall_metal"] = _std(Color(0.52, 0.50, 0.48), 0.6, 0.35)
	_mats["roof"] = _std(Color(0.50, 0.30, 0.18), 0.6)
	_mats["trim"] = _std(Color(0.33, 0.23, 0.14))
	_mats["rope"] = _std(Color(0.58, 0.50, 0.34))
	_mats["leaf"] = _std(Color(0.24, 0.48, 0.20))
	_mats["sand"] = _std(Color(0.60, 0.52, 0.36))
	_mats["dark"] = _std(Color(0.10, 0.09, 0.08))
	_mats["accent_teal"] = _std(Color(0.15, 0.55, 0.55))
	_mats["accent_red"] = _std(Color(0.65, 0.20, 0.14))
	var lantern := _std(Color(1.0, 0.78, 0.45), 0.5)
	lantern.emission_enabled = true
	lantern.emission = Color(1.0, 0.62, 0.25)
	lantern.emission_energy_multiplier = 2.2
	_mats["lantern"] = lantern
	_canoe_mat = _std(Color(0.42, 0.30, 0.18))
	_canoe_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _varc(c: Color, amt := 0.12) -> Color:
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


func _stairs(frame: Transform3D, x0: float, run: float, width: float, zc: float, rise: float, y_base := 0.0) -> void:
	# Visual steps + one ramp collider (player walks up smoothly).
	var steps := 10
	for i in range(steps):
		var sx := x0 + run * (float(i) + 0.5) / float(steps)
		var sy := y_base + rise * (float(i) + 0.5) / float(steps)
		_box(Vector3(run / float(steps) + 0.05, 0.09, width),
			frame * _t3(Vector3(sx, sy - 0.045, zc)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.06), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var ramp := Transform3D(Basis(Vector3(0, 0, 1), ang),
		frame * Vector3(x0 + run * 0.5, y_base + rise * 0.5 - 0.06, zc))
	_batch.add_collider(Vector3(length, 0.12, width), ramp)


func _loft_slab(frame: Transform3D, w: float, d: float, y: float, hx0: float, hx1: float, hz: float, hzw: float) -> void:
	# Wooden upper-floor deck with a rectangular stairwell hole.
	var t := 0.18
	var y0 := y - t * 0.5
	if hx0 > -w * 0.5 + 0.05:
		var sw := hx0 + w * 0.5
		_box(Vector3(sw, t, d), frame * _t3(Vector3(-w * 0.5 + sw * 0.5, y0, 0)),
			_mats["wood"], Color(1, 1, 1), true)
	if w * 0.5 - hx1 > 0.05:
		var sw2 := w * 0.5 - hx1
		_box(Vector3(sw2, t, d), frame * _t3(Vector3(hx1 + sw2 * 0.5, y0, 0)),
			_mats["wood"], Color(1, 1, 1), true)
	var hw := hx1 - hx0
	var fz0 := -d * 0.5
	var fz1 := hz - hzw * 0.5
	var bz0 := hz + hzw * 0.5
	var bz1 := d * 0.5
	if fz1 - fz0 > 0.05:
		_box(Vector3(hw, t, fz1 - fz0), frame * _t3(Vector3((hx0 + hx1) * 0.5, y0, (fz0 + fz1) * 0.5)),
			_mats["wood"], Color(1, 1, 1), true)
	if bz1 - bz0 > 0.05:
		_box(Vector3(hw, t, bz1 - bz0), frame * _t3(Vector3((hx0 + hx1) * 0.5, y0, (bz0 + bz1) * 0.5)),
			_mats["wood"], Color(1, 1, 1), true)


func _lantern(frame: Transform3D, x: float, y: float, z: float) -> void:
	# Hanging oil lantern: cord + emissive glass (cheap, no real light cost).
	_box(Vector3(0.04, 0.5, 0.04), frame * _t3(Vector3(x, y + 0.35, z)),
		_mats["wood_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.28, 0.34, 0.28), frame * _t3(Vector3(x, y, z)),
		_mats["lantern"], Color(1, 1, 1), false)
	_box(Vector3(0.34, 0.06, 0.34), frame * _t3(Vector3(x, y + 0.2, z)),
		_mats["trim"], Color(1, 1, 1), false)


# ---------------- water / sky ----------------

func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(320, 320)
	pm.subdivide_width = 64
	pm.subdivide_depth = 64
	water.mesh = pm
	water.position = Vector3(0, WATER_Y, 0)
	var wshader := load("res://shaders/water.gdshader") as Shader
	var wmat := ShaderMaterial.new()
	wmat.shader = wshader
	water.material_override = wmat
	add_child(water)


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
		var s := _rng.randf_range(14.0, 26.0)
		mi.scale = Vector3(s, s * 0.22, s * 0.6)
		mi.position = Vector3(_rng.randf_range(-140, 140), _rng.randf_range(38, 55), _rng.randf_range(-140, 140))
		add_child(mi)
		_clouds.append({"node": mi, "speed": _rng.randf_range(0.4, 1.0)})


# ---------------- houses ----------------

func _build_houses() -> void:
	for ci in range(CLUSTERS.size()):
		var cc: Vector2 = CLUSTERS[ci]
		var placed := 0
		var attempts := 0
		while placed < 7 and attempts < 40:
			attempts += 1
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(4.0, 16.0)
			var p := Vector3(cc.x + cos(a) * r, 0, cc.y + sin(a) * r)
			if absf(p.x) > 58.0 or absf(p.z) > 58.0:
				continue
			var ok := true
			for h in _houses:
				if (h["center"] as Vector3).distance_to(p) < 8.0:
					ok = false
					break
			if ok:
				for poi in poi_list:
					if (poi["pos"] as Vector3).distance_to(p) < 11.0:
						ok = false
						break
			if not ok:
				continue
			var to_c := Vector3(cc.x, 0, cc.y) - p
			var yaw := atan2(to_c.x, to_c.z)
			_build_house(p, yaw, ci)
			placed += 1


func _build_house(center: Vector3, yaw: float, cluster := -1) -> void:
	var w: float = _pick([4.2, 5.0, 5.8])
	var d: float = _pick([4.2, 5.0, 5.8])
	var wh: float = _pick([2.7, 3.0, 3.3])
	var wall_mat: StandardMaterial3D = _mats["wall_wood"] if _rng.randf() < 0.68 else _mats["wall_metal"]
	var wcol := _varc(Color(1, 1, 1), 0.10)
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var t := 0.15
	# Larger houses sometimes get a two-story loft: stairs + furnished upper deck.
	var two_story := w >= 5.0 and d >= 5.0 and _rng.randf() < 0.5
	var gh1 := 2.5  # ground floor height (two-story only)
	var gh2 := 2.3  # loft height (two-story only)
	var wall_h := gh1 if two_story else wh
	# Floor.
	_box(Vector3(w + 0.6, 0.18, d + 0.6), frame * _t3(Vector3(0, -0.09, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	# Walls: front(+z) door, others window/solid.
	_wall(frame * _t3(Vector3(0, 0, d * 0.5)), w, wall_h, t, "door", wall_mat, wcol)
	_wall(frame * _t3(Vector3(0, 0, -d * 0.5)), w, wall_h, t,
		"window" if _rng.randf() < 0.7 else "solid", wall_mat, wcol)
	_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)), d, wall_h, t,
		"window", wall_mat, wcol)
	_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)), d, wall_h, t,
		"window" if _rng.randf() < 0.8 else "solid", wall_mat, wcol)
	# Corner boards.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(Vector3(0.16, wall_h, 0.16), frame * _t3(Vector3(cx * w * 0.5, wall_h * 0.5, cz * d * 0.5)),
				_mats["trim"], _varc(Color(1, 1, 1), 0.08), false)
	# Curtain panels flanking the front door (fabric, no collider).
	var fabric: Color = _pick([Color(0.70, 0.35, 0.25), Color(0.30, 0.50, 0.60), Color(0.75, 0.70, 0.40)])
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.35, 2.0, 0.08), frame * _t3(Vector3(sx * 1.0, 1.0, d * 0.5 + 0.12)),
			_mats["wall_wood"], fabric, false)
	if two_story:
		# Loft deck with stairwell hole (stairs along the back wall).
		var sx0 := -w * 0.5 + 0.5
		var srun := minf(w - 1.0, 3.2)
		var swd := 1.2
		var szc := -d * 0.5 + 1.0
		_loft_slab(frame, w, d, gh1, sx0, sx0 + srun, szc, swd)
		_stairs(frame, sx0, srun, swd, szc, gh1)
		# Loft walls: window band on all sides.
		_wall(frame * _t3(Vector3(0, gh1, d * 0.5)), w, gh2, t, "window", wall_mat, wcol)
		_wall(frame * _t3(Vector3(0, gh1, -d * 0.5)), w, gh2, t, "window", wall_mat, wcol)
		_wall(frame * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, gh1, 0)), d, gh2, t,
			"window", wall_mat, wcol)
		_wall(frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, gh1, 0)), d, gh2, t,
			"window", wall_mat, wcol)
		for cx2 in [-1.0, 1.0]:
			for cz2 in [-1.0, 1.0]:
				_box(Vector3(0.16, gh2, 0.16),
					frame * _t3(Vector3(cx2 * w * 0.5, gh1 + gh2 * 0.5, cz2 * d * 0.5)),
					_mats["trim"], _varc(Color(1, 1, 1), 0.08), false)
		_furnish_loft(frame, w, d, gh1)
		_lantern(frame, w * 0.2, gh1 + gh2 - 0.8, 0.0)
		# Roof sits on the loft.
		if _rng.randf() < 0.55:
			_roof_gable(frame, w, d, gh1 + gh2)
		else:
			_roof_shed(frame, w, d, gh1 + gh2)
	else:
		# Roof.
		if _rng.randf() < 0.55:
			_roof_gable(frame, w, d, wh)
		else:
			_roof_shed(frame, w, d, wh)
	# Hanging lantern in the ground floor.
	_lantern(frame, -w * 0.2, wall_h - 0.8, 0.0)
	# Stilts down into the water.
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var sp := frame * _t3(Vector3(sx * (w * 0.5 - 0.35), -0.75, sz * (d * 0.5 - 0.35)))
			_batch.add_cyl(0.13, 1.7, sp, _mats["wood_dark"], _varc(Color(1, 1, 1), 0.10))
	_furnish(frame, w, d)
	_houses.append({"center": center, "yaw": yaw, "w": w, "d": d, "cluster": cluster})
	house_positions.append(center)


func _wall(frame: Transform3D, W: float, H: float, T: float, kind: String, mat: StandardMaterial3D, col: Color) -> void:
	if kind == "solid":
		_box(Vector3(W, H, T), frame * _t3(Vector3(0, H * 0.5, 0)), mat, col, true)
		return
	if kind == "door":
		var dw := 1.2
		var dh := 2.2
		var sw := (W - dw) * 0.5
		_box(Vector3(sw, H, T), frame * _t3(Vector3(-W * 0.5 + sw * 0.5, H * 0.5, 0)), mat, col, true)
		_box(Vector3(sw, H, T), frame * _t3(Vector3(W * 0.5 - sw * 0.5, H * 0.5, 0)), mat, col, true)
		_box(Vector3(dw, H - dh, T), frame * _t3(Vector3(0, dh + (H - dh) * 0.5, 0)), mat, col, true)
		var tm = _mats["trim"]
		_box(Vector3(0.12, dh, T + 0.06), frame * _t3(Vector3(-dw * 0.5 - 0.06, dh * 0.5, 0)), tm, col, false)
		_box(Vector3(0.12, dh, T + 0.06), frame * _t3(Vector3(dw * 0.5 + 0.06, dh * 0.5, 0)), tm, col, false)
		_box(Vector3(dw + 0.24, 0.12, T + 0.06), frame * _t3(Vector3(0, dh + 0.06, 0)), tm, col, false)
		return
	# window opening (real hole to see/shoot through)
	var ww := 1.1
	var wh2 := 1.0
	var sill := 1.4
	var sw2 := (W - ww) * 0.5
	_box(Vector3(sw2, H, T), frame * _t3(Vector3(-W * 0.5 + sw2 * 0.5, H * 0.5, 0)), mat, col, true)
	_box(Vector3(sw2, H, T), frame * _t3(Vector3(W * 0.5 - sw2 * 0.5, H * 0.5, 0)), mat, col, true)
	_box(Vector3(ww, sill, T), frame * _t3(Vector3(0, sill * 0.5, 0)), mat, col, true)
	var top_h := H - sill - wh2
	if top_h > 0.05:
		_box(Vector3(ww, top_h, T), frame * _t3(Vector3(0, sill + wh2 + top_h * 0.5, 0)), mat, col, true)
	var tm2 = _mats["trim"]
	_box(Vector3(ww + 0.16, 0.1, T + 0.06), frame * _t3(Vector3(0, sill - 0.05, 0)), tm2, col, false)
	_box(Vector3(ww + 0.16, 0.1, T + 0.06), frame * _t3(Vector3(0, sill + wh2 + 0.05, 0)), tm2, col, false)
	_box(Vector3(0.1, wh2 + 0.2, T + 0.06), frame * _t3(Vector3(-ww * 0.5 - 0.05, sill + wh2 * 0.5, 0)), tm2, col, false)
	_box(Vector3(0.1, wh2 + 0.2, T + 0.06), frame * _t3(Vector3(ww * 0.5 + 0.05, sill + wh2 * 0.5, 0)), tm2, col, false)
	if _rng.randf() < 0.5:
		_box(Vector3(0.5, wh2, 0.06), frame * _t3(Vector3(-ww * 0.5 - 0.32, sill + wh2 * 0.5, 0.06)),
			_mats["wood_dark"], col, false)


func _roof_gable(frame: Transform3D, w: float, d: float, wh: float) -> void:
	var rise := _rng.randf_range(1.0, 1.5)
	var run := d * 0.5 + 0.45
	var slope := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var rc := _varc(_pick([Color(0.58, 0.30, 0.16), Color(0.50, 0.50, 0.52),
		Color(0.38, 0.27, 0.18), Color(0.42, 0.48, 0.56)]), 0.10)
	for sgn in [1.0, -1.0]:
		var local := Transform3D(Basis(Vector3(1, 0, 0), sgn * ang), Vector3(0, wh + rise * 0.5, sgn * run * 0.5))
		_box(Vector3(w + 0.9, 0.12, slope + 0.25), frame * local, _mats["roof"], rc, false)
	_box(Vector3(w + 0.9, 0.14, 0.45), frame * _t3(Vector3(0, wh + rise + 0.03, 0)),
		_mats["trim"], rc, false)
	# dark attic inset (sized to fit under the slopes)
	_box(Vector3(w - 0.6, rise * 0.5, d * 0.52), frame * _t3(Vector3(0, wh + rise * 0.26, 0)),
		_mats["dark"], Color(1, 1, 1), false)


func _roof_shed(frame: Transform3D, w: float, d: float, wh: float) -> void:
	var drop := _rng.randf_range(0.7, 1.1)
	var slope := sqrt(d * d + drop * drop) + 0.6
	var ang := atan2(drop, d)
	var rc := _varc(_pick([Color(0.58, 0.30, 0.16), Color(0.50, 0.50, 0.52),
		Color(0.38, 0.27, 0.18)]), 0.10)
	var local := Transform3D(Basis(Vector3(1, 0, 0), ang), Vector3(0, wh + drop * 0.5 - 0.1, 0))
	_box(Vector3(w + 0.9, 0.12, slope), frame * local, _mats["roof"], rc, false)
	_box(Vector3(w + 0.9, 0.18, 0.1), frame * _t3(Vector3(0, wh - 0.05, d * 0.5 + 0.25)),
		_mats["trim"], rc, false)


func _furnish(frame: Transform3D, w: float, d: float) -> void:
	var wood = _mats["wood_dark"]
	var c := _varc(Color(1, 1, 1), 0.10)
	if _rng.randf() < 0.8:
		var bx := -w * 0.26
		var bz := -d * 0.30
		_box(Vector3(1.9, 0.42, 0.95), frame * _t3(Vector3(bx, 0.21, bz)), wood, c, true)
		_box(Vector3(0.45, 0.14, 0.65), frame * _t3(Vector3(bx - 0.6, 0.49, bz)),
			_mats["wall_wood"], c, false)
	if _rng.randf() < 0.7:
		var tx := w * 0.26
		var tz := -d * 0.28
		_box(Vector3(1.3, 0.09, 0.85), frame * _t3(Vector3(tx, 0.72, tz)), wood, c, true)
		for lx in [-0.55, 0.55]:
			for lz in [-0.32, 0.32]:
				_box(Vector3(0.09, 0.72, 0.09), frame * _t3(Vector3(tx + lx, 0.36, tz + lz)), wood, c, false)
	if _rng.randf() < 0.6:
		_box(Vector3(0.8, 0.8, 0.8), frame * _t3(Vector3(w * 0.5 - 0.75, 0.4, d * 0.1)),
			_mats["wood"], c, true)
	if _rng.randf() < 0.62:
		var lp: Vector3 = frame * Vector3(0.3, 0.0, -0.3)
		var kind: String = _pick(["health", "armor", "ammo", "ammo"])
		var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
		loot_spots.append([kind, amt, Vector3(lp.x, 0.55, lp.z)])


func _furnish_loft(frame: Transform3D, w: float, d: float, fy: float) -> void:
	var wood = _mats["wood_dark"]
	var c := _varc(Color(1, 1, 1), 0.10)
	# Bedroll + pillow.
	_box(Vector3(0.9, 0.18, 2.0), frame * _t3(Vector3(-w * 0.28, fy + 0.09, 0.3)), wood, c, false)
	_box(Vector3(0.5, 0.12, 0.6), frame * _t3(Vector3(-w * 0.28, fy + 0.24, -0.45)),
		_mats["wall_wood"], c, false)
	# Low table.
	_box(Vector3(1.2, 0.08, 0.8), frame * _t3(Vector3(w * 0.25, fy + 0.45, 0.2)), wood, c, true)
	for lx in [-0.5, 0.5]:
		for lz in [-0.3, 0.3]:
			_box(Vector3(0.08, 0.45, 0.08),
				frame * _t3(Vector3(w * 0.25 + lx, fy + 0.225, 0.2 + lz)), wood, c, false)
	# Shelf with stored goods.
	_box(Vector3(1.6, 0.07, 0.4), frame * _t3(Vector3(w * 0.2, fy + 1.5, -d * 0.5 + 0.35)), wood, c, false)
	for i in range(3):
		_box(Vector3(0.28, 0.26, 0.28),
			frame * _t3(Vector3(w * 0.2 - 0.5 + i * 0.5, fy + 1.66, -d * 0.5 + 0.35)),
			_mats["wall_wood"], _varc(Color(1, 1, 1), 0.12), false)
	# Loft loot.
	if _rng.randf() < 0.8:
		var kind: String = _pick(["ammo", "health", "armor"])
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lp2: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), fy,
			_rng.randf_range(-d * 0.25, d * 0.25))
		loot_spots.append([kind, amt, Vector3(lp2.x, fy + 0.55, lp2.z)])


func _fish_rack(center: Vector3, yaw: float) -> void:
	# A-frame rack with hanging dried fish (small boxes).
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wood = _mats["wood_dark"]
	for sx in [-1.0, 1.0]:
		var leg := frame * Transform3D(Basis(Vector3(0, 0, 1), sx * 0.3), Vector3(sx * 0.9, 0.9, 0))
		_box(Vector3(0.1, 2.0, 0.1), leg, wood, _varc(Color(1, 1, 1), 0.10), true)
	_box(Vector3(2.2, 0.08, 0.08), frame * _t3(Vector3(0, 1.7, 0)), wood, Color(1, 1, 1), false)
	for i in range(4):
		var fx := -0.75 + float(i) * 0.5
		_box(Vector3(0.03, 0.25, 0.03), frame * _t3(Vector3(fx, 1.55, 0)), _mats["rope"], Color(1, 1, 1), false)
		_box(Vector3(0.10, 0.35, 0.06), frame * _t3(Vector3(fx, 1.3, 0)),
			_mats["accent_teal"], _varc(Color(1, 1, 1), 0.15), false)


# ---------------- walkways / docks / bridges ----------------

func _walkway(a: Vector3, b: Vector3, width := 1.7) -> void:
	var dir := b - a
	dir.y = 0.0
	var length := dir.length()
	if length < 1.0:
		return
	dir = dir.normalized()
	var yaw := atan2(dir.x, dir.z)
	var start := a + dir * 2.6
	var finish := b - dir * 2.6
	var span := start.distance_to(finish)
	if span < 1.0:
		return
	var mid := (start + finish) * 0.5
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0.0, mid.z))
	var wood = _mats["wood"]
	var z := -span * 0.5
	while z < span * 0.5:
		_box(Vector3(width, 0.07, 0.42), frame * _t3(Vector3(0, -0.035, z)),
			wood, _varc(Color(1, 1, 1), 0.12), false)
		z += 0.55
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.14, 0.16, span), frame * _t3(Vector3(sx * (width * 0.5 - 0.05), -0.12, 0)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	var n := int(span / 3.0) + 1
	for i in range(n + 1):
		var pz := -span * 0.5 + span * float(i) / float(n)
		for sx2 in [-1.0, 1.0]:
			var pp := frame * _t3(Vector3(sx2 * (width * 0.5 - 0.05), -0.9, pz))
			_batch.add_cyl(0.11, 1.7, pp, _mats["wood_dark"], _varc(Color(1, 1, 1), 0.10))
	_batch.add_collider(Vector3(width, 0.5, span),
		Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, -0.25, mid.z)))


func _dock(center: Vector3, w: float, d: float, yaw := 0.0) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	_box(Vector3(w, 0.22, d), frame * _t3(Vector3(0, -0.11, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	var z := -d * 0.5 + 0.4
	while z < d * 0.5:
		_box(Vector3(w, 0.02, 0.06), frame * _t3(Vector3(0, 0.005, z)),
			_mats["wood_dark"], Color(1, 1, 1), false)
		z += 0.8
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var pp := frame * _t3(Vector3(cx * (w * 0.5 - 0.4), -0.9, cz * (d * 0.5 - 0.4)))
			_batch.add_cyl(0.14, 1.9, pp, _mats["wood_dark"], _varc(Color(1, 1, 1), 0.10))
	# mooring posts + ropes on the water side
	for i in range(3):
		var mx := -w * 0.5 + w * float(i) / 2.0
		var mp := frame * _t3(Vector3(mx, 0.35, d * 0.5 + 0.6))
		_batch.add_cyl(0.12, 1.5, mp, _mats["wood_dark"], _varc(Color(1, 1, 1), 0.10))
		if i > 0:
			var prev := frame * _t3(Vector3(-w * 0.5 + w * float(i - 1) / 2.0, 0.9, d * 0.5 + 0.6))
			_rope(prev.origin, mp.origin)


func _rope(a: Vector3, b: Vector3) -> void:
	var segs := 5
	for i in range(segs):
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := a.lerp(b, t0)
		p0.y -= sin(t0 * PI) * 0.35
		var p1 := a.lerp(b, t1)
		p1.y -= sin(t1 * PI) * 0.35
		var mid := (p0 + p1) * 0.5
		var dv := p1 - p0
		var length := dv.length()
		if length < 0.01:
			continue
		var yaw := atan2(dv.x, dv.z)
		var pitch := acos(clampf(dv.y / length, -1.0, 1.0))
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch)
		_batch.add_cyl(0.03, length + 0.05, Transform3D(basis, mid), _mats["rope"], Color(1, 1, 1))


func _build_walkways() -> void:
	for ci in range(CLUSTERS.size()):
		var members: Array = []
		for h in _houses:
			if int(h["cluster"]) == ci:
				members.append(h)
		for i in range(1, members.size()):
			var a: Vector3 = members[i]["center"]
			var best := -1
			var best_d := 1.0e9
			for j in range(i):
				var dd: float = a.distance_to(members[j]["center"])
				if dd < best_d:
					best_d = dd
					best = j
			if best >= 0 and best_d < 18.0:
				_walkway(a, members[best]["center"])


func _link_clusters(a: int, b: int) -> void:
	var best_a := -1
	var best_b := -1
	var best_d := 1.0e9
	for i in range(_houses.size()):
		if int(_houses[i]["cluster"]) != a:
			continue
		for j in range(_houses.size()):
			if int(_houses[j]["cluster"]) != b:
				continue
			var dd: float = (_houses[i]["center"] as Vector3).distance_to(_houses[j]["center"])
			if dd < best_d:
				best_d = dd
				best_a = i
				best_b = j
	if best_a >= 0 and best_d < 34.0:
		_walkway(_houses[best_a]["center"], _houses[best_b]["center"], 2.2)


func _link_poi(poi_pos: Vector3, cluster: int) -> void:
	var best := -1
	var best_d := 1.0e9
	for i in range(_houses.size()):
		if int(_houses[i]["cluster"]) != cluster:
			continue
		var dd: float = (_houses[i]["center"] as Vector3).distance_to(poi_pos)
		if dd < best_d:
			best_d = dd
			best = i
	if best >= 0 and best_d < 30.0:
		_walkway(poi_pos, _houses[best]["center"], 2.0)


func _build_links() -> void:
	_link_clusters(0, 4)
	_link_clusters(1, 4)
	_link_clusters(2, 4)
	_link_clusters(3, 4)
	_link_poi(Vector3(0, 0, 50), 3)
	_link_poi(Vector3(-42, 0, -6), 2)
	_link_poi(Vector3(46, 0, -40), 1)
	_link_poi(Vector3(-10, 0, -46), 0)


# ---------------- POIs ----------------

func _build_pois() -> void:
	for poi in POIS:
		var pname: String = poi["name"]
		var ppos: Vector3 = poi["pos"]
		poi_list.append({"name": pname, "pos": ppos})
		match pname:
			"Main Dock":
				_poi_main_dock(ppos)
			"Market Row":
				_poi_market(ppos)
			"Old Shrine":
				_poi_shrine(ppos)
			"Canoe Yard":
				_poi_canoe_yard(ppos)
		for i in range(4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(2.0, 6.0)
			var kind: String = _pick(["health", "armor", "ammo", "ammo"])
			var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
			loot_spots.append([kind, amt, ppos + Vector3(cos(a) * r, 0.55, sin(a) * r)])


func _poi_main_dock(ppos: Vector3) -> void:
	_dock(ppos, 12.0, 8.0)
	player_spawn = Vector3(ppos.x, 0.6, ppos.z + 2.0)
	# crates on the dock
	for i in range(4):
		var s := _rng.randf_range(1.0, 1.4)
		_box(Vector3(s, s, s),
			_t3(ppos + Vector3(-4.0 + i * 2.2, s * 0.5, -2.5)),
			_mats["wood"], _varc(Color(1, 1, 1), 0.10), true)
	# moored canoes
	for i in range(3):
		_add_canoe(Vector3(ppos.x - 8.0 + i * 3.0, WATER_Y + 0.12, ppos.z + 7.5),
			_rng.randf() * TAU, true)


func _poi_market(ppos: Vector3) -> void:
	_dock(ppos, 24.0, 7.0)
	for i in range(5):
		_stall(ppos + Vector3(-9.0 + i * 4.5, 0, 0.5), _rng.randf_range(-0.1, 0.1))


func _stall(center: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	var wood = _mats["wood_dark"]
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(Vector3(0.12, 2.3, 0.12), frame * _t3(Vector3(cx * 1.3, 1.15, cz * 1.0)),
				wood, _varc(Color(1, 1, 1), 0.10), true)
	var cc := _varc(_pick([Color(0.75, 0.45, 0.20), Color(0.30, 0.55, 0.60), Color(0.70, 0.65, 0.30)]), 0.08)
	_box(Vector3(3.2, 0.08, 2.6), frame * Transform3D(Basis(Vector3(1, 0, 0), 0.08), Vector3(0, 2.42, 0)),
		_mats["roof"], cc, false)
	_box(Vector3(2.4, 0.10, 1.4), frame * _t3(Vector3(0, 0.85, 0)), wood, _varc(Color(1, 1, 1), 0.10), true)
	_box(Vector3(2.2, 0.75, 1.2), frame * _t3(Vector3(0, 0.42, 0)), wood, _varc(Color(1, 1, 1), 0.10), false)
	for i in range(4):
		var gc := _varc(_pick([Color(0.80, 0.30, 0.20), Color(0.90, 0.70, 0.20),
			Color(0.30, 0.60, 0.30), Color(0.85, 0.85, 0.85)]), 0.10)
		_box(Vector3(0.3, 0.25, 0.3),
			frame * _t3(Vector3(-0.8 + i * 0.55, 1.02, _rng.randf_range(-0.3, 0.3))),
			_mats["wood"], gc, false)


func _poi_shrine(ppos: Vector3) -> void:
	_build_house(ppos + Vector3(0, 0, 2), 0.0, -1)
	# accent posts + fence ring
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var fp := ppos + Vector3(cos(a) * 5.5, 0, sin(a) * 5.5)
		_box(Vector3(0.14, 1.6, 0.14), _t3(fp + Vector3(0, 0.8, 0)),
			_mats["accent_teal"], _varc(Color(1, 1, 1), 0.08), true)
		var na := TAU * float(i + 1) / 8.0
		var np := ppos + Vector3(cos(na) * 5.5, 0, sin(na) * 5.5)
		_rope(fp + Vector3(0, 1.45, 0), np + Vector3(0, 1.45, 0))
	# colored banner
	_box(Vector3(2.2, 0.5, 0.08), _t3(ppos + Vector3(0, 2.6, 4.6)),
		_mats["accent_red"], Color(1, 1, 1), false)


func _poi_canoe_yard(ppos: Vector3) -> void:
	_dock(ppos, 14.0, 8.0)
	for r in range(2):
		_canoe_rack(ppos + Vector3(-3.5 + r * 7.0, 0, -1.0), 0.0, 3)
	for i in range(4):
		_add_canoe(Vector3(ppos.x - 9.0 + i * 2.6, WATER_Y + 0.12, ppos.z + 7.0),
			_rng.randf_range(-0.4, 0.4), true)


func _canoe_rack(center: Vector3, yaw: float, count := 3) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), center)
	for sz in [-1.6, 1.6]:
		for sx in [-1.0, 1.0]:
			var leg := frame * Transform3D(Basis(Vector3(0, 0, 1), sx * 0.35), Vector3(sx * 0.9, 0.55, sz))
			_box(Vector3(0.12, 1.4, 0.12), leg, _mats["wood_dark"], _varc(Color(1, 1, 1), 0.10), true)
		_box(Vector3(2.2, 0.12, 0.12), frame * _t3(Vector3(0, 1.05, sz)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.10), false)
	for i in range(count):
		var off := (float(i) - float(count - 1) * 0.5) * 0.75
		var xf := frame * Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3(0, 0, 1), 0.45),
			Vector3(off, 1.15, 0))
		_add_canoe_node(xf, false)


# ---------------- props ----------------

func _build_props() -> void:
	# crates near houses
	for i in range(18):
		var h: Dictionary = _houses[_rng.randi_range(0, _houses.size() - 1)]
		var c: Vector3 = h["center"]
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(3.5, 5.5)
		var p := Vector3(c.x + cos(a) * r, 0, c.z + sin(a) * r)
		if absf(p.x) > 62.0 or absf(p.z) > 62.0:
			continue
		var s := _rng.randf_range(1.1, 1.5)
		var yaw := _rng.randf() * TAU
		_box(Vector3(s, s, s), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, s * 0.5, 0)),
			_mats["wood"], _varc(Color(1, 1, 1), 0.12), true)
		if _rng.randf() < 0.3:
			var s2 := s * 0.7
			_box(Vector3(s2, s2, s2),
				Transform3D(Basis(Vector3.UP, yaw + 0.4), p + Vector3(0, s + s2 * 0.5, 0)),
				_mats["wood"], _varc(Color(1, 1, 1), 0.12), true)
	# barrels
	for i in range(12):
		var h2: Dictionary = _houses[_rng.randi_range(0, _houses.size() - 1)]
		var c2: Vector3 = h2["center"]
		var a2 := _rng.randf() * TAU
		var r2 := _rng.randf_range(3.0, 5.0)
		var p2 := Vector3(c2.x + cos(a2) * r2, 0.55, c2.z + sin(a2) * r2)
		if absf(p2.x) > 62.0 or absf(p2.z) > 62.0:
			continue
		_batch.add_cyl(0.45, 1.1, _t3(p2),
			_mats["roof"], _varc(_pick([Color(0.55, 0.30, 0.16), Color(0.35, 0.42, 0.55), Color(0.50, 0.50, 0.52)]), 0.10))
		_batch.add_collider(Vector3(0.85, 1.1, 0.85), _t3(p2))
	# mud islands with palms
	for ip in [Vector3(-52, 0, 18), Vector3(54, 0, 8), Vector3(20, 0, -54)]:
		_batch.add_cyl(5.0, 0.9, _t3(ip + Vector3(0, -0.3, 0)), _mats["sand"], _varc(Color(1, 1, 1), 0.08))
		_batch.add_collider(Vector3(8.5, 0.9, 8.5), _t3(ip + Vector3(0, -0.3, 0)))
		for i in range(4):
			_palm(ip + Vector3(_rng.randf_range(-3, 3), 0.15, _rng.randf_range(-3, 3)))
	# Fish drying racks near houses.
	for i in range(8):
		var h3: Dictionary = _houses[_rng.randi_range(0, _houses.size() - 1)]
		var c3: Vector3 = h3["center"]
		var a3 := _rng.randf() * TAU
		var p3 := Vector3(c3.x + cos(a3) * _rng.randf_range(3.0, 5.0), 0,
			c3.z + sin(a3) * _rng.randf_range(3.0, 5.0))
		if absf(p3.x) > 62.0 or absf(p3.z) > 62.0:
			continue
		_fish_rack(p3, _rng.randf() * TAU)
	# Lantern posts on the main dock.
	for lx in [-5.0, 5.0]:
		var pp := Vector3(lx, 0, 50.0)
		_box(Vector3(0.12, 2.6, 0.12), _t3(pp + Vector3(0, 1.3, 0)),
			_mats["wood_dark"], Color(1, 1, 1), true)
		_box(Vector3(0.3, 0.36, 0.3), _t3(pp + Vector3(0, 2.75, 0)),
			_mats["lantern"], Color(1, 1, 1), false)
	# extra outdoor loot near clusters
	for ci in CLUSTERS:
		for i in range(2):
			var p := Vector3(ci.x + _rng.randf_range(-12, 12), 0.55, ci.y + _rng.randf_range(-12, 12))
			var near := false
			for h in _houses:
				if (h["center"] as Vector3).distance_to(p) < 7.0:
					near = true
					break
			if not near:
				continue
			var kind: String = _pick(["health", "armor", "ammo", "ammo"])
			var amt := 40 if kind == "health" else (50 if kind == "armor" else 60)
			loot_spots.append([kind, amt, p])


func _palm(pos: Vector3) -> void:
	var h := _rng.randf_range(3.2, 4.5)
	var lean := _rng.randf_range(0.0, 0.12)
	var segs := 4
	var sh := h / segs
	for i in range(segs):
		var c := pos + Vector3(lean * i * sh, sh * 0.5 + i * sh, 0)
		_batch.add_cyl(0.16 - 0.02 * i, sh + 0.15, _t3(c), _mats["wood_dark"], _varc(Color(1, 1, 1), 0.10))
	var top := pos + Vector3(lean * segs * sh, h, 0)
	for i in range(7):
		var a := TAU * float(i) / 7.0 + _rng.randf_range(-0.2, 0.2)
		var yaw := atan2(cos(a), sin(a))
		var tilt := _rng.randf_range(0.45, 0.85)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), tilt)
		var mid := top + Vector3(cos(a) * 0.95, 0.15 - tilt * 0.35, sin(a) * 0.95)
		_box(Vector3(0.55, 0.05, 2.1), Transform3D(b, mid), _mats["leaf"], _varc(Color(1, 1, 1), 0.15), false)


# ---------------- canoes ----------------

func _make_canoe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections := 7
	var length := 4.4
	var beam := 0.95
	var prof := [
		Vector2(0.55, -0.50), Vector2(0.15, -0.32), Vector2(0.0, 0.0),
		Vector2(0.15, 0.32), Vector2(0.55, 0.50),
	]
	var pts: Array = []
	for i in range(sections):
		var t := float(i) / float(sections - 1)
		var x := (t - 0.5) * length
		var w := 0.12 + 0.88 * pow(sin(t * PI), 0.7)
		var rise := (1.0 - sin(t * PI)) * 0.38
		var row: Array = []
		for p in prof:
			row.append(Vector3(x, p.x + rise, p.y * beam * w))
		pts.append(row)
	for i in range(sections - 1):
		for j in range(4):
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	for e in [0, sections - 1]:
		var ctr := Vector3.ZERO
		for p in pts[e]:
			ctr += p
		ctr /= 5.0
		for j in range(4):
			var p0: Vector3 = pts[e][j]
			var p1: Vector3 = pts[e][j + 1]
			if e == 0:
				_tri(st, ctr, p1, p0)
			else:
				_tri(st, ctr, p0, p1)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_uv(Vector2.ZERO)
	st.add_vertex(a)
	st.set_uv(Vector2.ZERO)
	st.add_vertex(b)
	st.set_uv(Vector2.ZERO)
	st.add_vertex(c)


func _add_canoe_node(xform: Transform3D, bob: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _canoe_mesh
	mi.material_override = _canoe_mat
	mi.transform = xform
	add_child(mi)
	# bench thwart (spans the hull width)
	var b1 := Transform3D(Basis(Vector3.UP, xform.basis.get_euler().y), xform.origin + Vector3(0, 0.42, 0))
	_box(Vector3(0.28, 0.07, 0.8), b1, _mats["wood_dark"], Color(1, 1, 1), false)
	if bob:
		_canoes.append({
			"node": mi, "base_y": xform.origin.y,
			"phase": _rng.randf() * TAU, "speed": _rng.randf_range(0.7, 1.2),
			"roll": 0.0,
		})


func _add_canoe(pos: Vector3, yaw: float, bob: bool) -> void:
	_add_canoe_node(Transform3D(Basis(Vector3.UP, yaw), pos), bob)


func _build_canoes() -> void:
	# a few extra floating canoes scattered on the waterways
	for i in range(6):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(20.0, 45.0)
		var p := Vector3(cos(a) * r, WATER_Y + 0.12, sin(a) * r)
		var near_house := false
		for h in _houses:
			if (h["center"] as Vector3).distance_to(p) < 12.0:
				near_house = true
				break
		if near_house:
			_add_canoe(p, _rng.randf() * TAU, true)


# ---------------- finalize ----------------

func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -6, -85), Vector3(170, 40, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	var esp := [Vector2(-32, -30), Vector2(30, -30), Vector2(-30, 30),
		Vector2(32, 32), Vector2(0, 2), Vector2(0, 50)]
	# Snap enemy spawns onto house floors (never open water): nearest unused
	# house to each cluster point, just inside its door.
	var used: Array = []
	for p in esp:
		var best_h := {}
		var best_d := 1.0e9
		for h in _houses:
			if used.has(h):
				continue
			var hc: Vector3 = h["center"]
			var dd := Vector2(hc.x - p.x, hc.z - p.y).length()
			if dd < best_d:
				best_d = dd
				best_h = h
		if not best_h.is_empty() and best_d < 25.0:
			used.append(best_h)
			var bc: Vector3 = best_h["center"]
			var byaw: float = best_h["yaw"]
			var door_dir := Vector3(sin(byaw), 0.0, cos(byaw))
			enemy_spawns.append(bc + door_dir * 1.8 + Vector3(0, 0.6, 0))
		else:
			enemy_spawns.append(Vector3(p.x, 0.6, p.y))
	print("Makoko built: houses=", _houses.size(), " instances=", _batch.box_count(),
		" draws=", draws, " colliders=", _batch.collider_count(),
		" loot=", loot_spots.size(), " pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for c in _canoes:
		var n: MeshInstance3D = c["node"]
		n.position.y = float(c["base_y"]) + sin(_time * float(c["speed"]) + float(c["phase"])) * 0.07
		n.rotation.z = sin(_time * float(c["speed"]) * 0.8 + float(c["phase"])) * 0.03
		n.rotation.x = sin(_time * float(c["speed"]) * 0.6 + float(c["phase"]) * 1.7) * 0.02
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 160.0:
			cn.position.x = -160.0
