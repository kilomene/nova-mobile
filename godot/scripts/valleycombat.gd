extends Node3D
class_name ValleyCombatMap
## Phase 6: Valley Combat — terrain-based wilderness combat map, deliberately
## DIFFERENT from the four urban maps. Rural Lagos outskirts: procedural
## heightmap terrain (rolling hills, central valley, carved river), vertex-
## colored ground surfaces (grass/dirt/rock/sand), animated river water,
## wooden footbridge, rocks, sandbags, barricades, watchtowers, concrete
## ruins, and a military-style valley camp. Seeded procedural (SEED),
## merge-ready 140x140m.
##
## Ground-height integration: exposes ground_height(x, z) (bilinear interp of
## the height grid). All spawns/loot/props are placed on real terrain heights,
## and main.gd snaps spawns via ground_height when the map provides it.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261013
const WATER_Y := -0.4
const GRID_N := 96
const WORLD := 140.0
const STEP := WORLD / float(GRID_N)

const POIS := [
	{"name": "Hilltop Outpost", "pos": Vector3(40, 0, -44)},
	{"name": "River Crossing", "pos": Vector3(-8, 0, -22)},
	{"name": "Valley Camp", "pos": Vector3(-14, 0, 8)},
	{"name": "Ruined Compound", "pos": Vector3(20, 0, -34)},
]

var player_spawn := Vector3(-18, 3.0, 12)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # ruins/towers (API compat)
var map_extent := MAP_EXTENT

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _heights := PackedFloat32Array()
var _noise: FastNoiseLite
var _river_pts: Array = []  # Array[Vector2], resampled Catmull-Rom
var _hills: Array = []  # {"x","z","h","r"}
var _bridge_t := 0.45
var _bridge_pos := Vector2.ZERO
var _clouds: Array = []
var _time := 0.0
var _placed: Array = []  # Vector2 points already used by props (spacing)


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_setup_noise()
	_setup_river()
	_setup_hills()
	_compute_heights()
	_build_terrain()
	_build_river_water()
	_build_bridge()
	_build_rocks()
	_build_vegetation()
	_build_sandbags()
	_build_barricades()
	_build_watchtowers()
	_build_ruins()
	_build_camp()
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
	_mats["wood"] = _std(Color(0.45, 0.33, 0.20), 0.9)
	_mats["wood_dark"] = _std(Color(0.30, 0.22, 0.13), 0.9)
	_mats["concrete"] = _std(Color(0.60, 0.59, 0.56))
	_mats["concrete_dark"] = _std(Color(0.44, 0.43, 0.41))
	_mats["rock"] = _std(Color(1, 1, 1), 0.95)       # per-instance grey variation
	_mats["sandbag"] = _std(Color(1, 1, 1), 0.95)     # per-instance tan variation
	_mats["crate"] = _std(Color(0.52, 0.40, 0.24), 0.9)
	_mats["tent"] = _std(Color(1, 1, 1), 0.9)         # per-instance canvas colors
	_mats["trunk"] = _std(Color(0.40, 0.30, 0.19), 0.95)
	_mats["leaf"] = _std(Color(1, 1, 1), 0.95)        # per-instance green variation
	_mats["metal"] = _std(Color(0.45, 0.47, 0.50), 0.5, 0.5)
	_mats["rope"] = _std(Color(0.55, 0.48, 0.34), 0.95)
	var fire := _std(Color(1.0, 0.55, 0.15), 0.6)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.45, 0.10)
	fire.emission_energy_multiplier = 2.5
	_mats["fire"] = fire
	var lantern := _std(Color(1.0, 0.78, 0.45), 0.5)
	lantern.emission_enabled = true
	lantern.emission = Color(1.0, 0.62, 0.25)
	lantern.emission_energy_multiplier = 2.2
	_mats["lantern"] = lantern


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


func _cyl(radius: float, height: float, xform: Transform3D, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	_batch.add_cyl(radius, height, xform, mat, col)
	if collide:
		_batch.add_collider(Vector3(radius * 2.0, height, radius * 2.0), xform)


func _rock(size: Vector3, yaw: float, pos: Vector3, mat: StandardMaterial3D, col: Color, collide := false) -> void:
	_batch.add_rock(size, Transform3D(Basis(Vector3.UP, yaw), pos), mat, col, collide)


func _gy(x: float, z: float) -> float:
	return ground_height(x, z)


# ---------------- terrain generation ----------------

func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.022
	_noise.fractal_octaves = 3
	_noise.fractal_gain = 0.5


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t \
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _setup_river() -> void:
	var ctrl := [
		Vector2(-52, -68), Vector2(-34, -46), Vector2(-12, -24),
		Vector2(4, -2), Vector2(-4, 22), Vector2(-24, 44), Vector2(-40, 68),
	]
	_river_pts.clear()
	for s in range(ctrl.size() - 1):
		var p0: Vector2 = ctrl[maxi(s - 1, 0)]
		var p1: Vector2 = ctrl[s]
		var p2: Vector2 = ctrl[s + 1]
		var p3: Vector2 = ctrl[mini(s + 2, ctrl.size() - 1)]
		for k in range(12):
			_river_pts.append(_catmull(p0, p1, p2, p3, float(k) / 12.0))
	_river_pts.append(ctrl[ctrl.size() - 1])


func _setup_hills() -> void:
	# Fixed hill peaks, verified clear of the river path.
	_hills = [
		{"x": 40.0, "z": -44.0, "h": 11.0, "r": 24.0},
		{"x": -48.0, "z": -12.0, "h": 9.0, "r": 22.0},
		{"x": 34.0, "z": 40.0, "h": 8.0, "r": 20.0},
	]


func _dist_to_river(x: float, z: float) -> float:
	var best := 1.0e9
	for s in range(_river_pts.size() - 1):
		var a: Vector2 = _river_pts[s]
		var b: Vector2 = _river_pts[s + 1]
		var abx := b.x - a.x
		var abz := b.y - a.y
		var denom := abx * abx + abz * abz
		var t := 0.0
		if denom > 0.0001:
			t = clampf(((x - a.x) * abx + (z - a.y) * abz) / denom, 0.0, 1.0)
		var dx := x - (a.x + abx * t)
		var dz := z - (a.y + abz * t)
		var d2 := dx * dx + dz * dz
		if d2 < best:
			best = d2
	return sqrt(best)


func _raw_height(x: float, z: float) -> float:
	var h := 3.0
	h += _noise.get_noise_2d(x, z) * 3.0
	for hill in _hills:
		var hx: float = hill["x"]
		var hz: float = hill["z"]
		var hh: float = hill["h"]
		var hr: float = hill["r"]
		var dx := x - hx
		var dz := z - hz
		h += hh * exp(-(dx * dx + dz * dz) / (hr * hr))
	var dr := _dist_to_river(x, z)
	h -= 3.0 * (1.0 - smoothstep(0.0, 25.0, dr))   # broad valley
	h -= 5.0 * (1.0 - smoothstep(0.0, 6.0, dr))    # river channel
	var e := maxf(absf(x), absf(z))
	h += 8.0 * smoothstep(60.0, 70.0, e)            # rim bowl at the edges
	return maxf(h, -4.5)


func _compute_heights() -> void:
	_heights.resize((GRID_N + 1) * (GRID_N + 1))
	for j in range(GRID_N + 1):
		for i in range(GRID_N + 1):
			var x := -70.0 + float(i) * STEP
			var z := -70.0 + float(j) * STEP
			_heights[j * (GRID_N + 1) + i] = _raw_height(x, z)


func ground_height(x: float, z: float) -> float:
	## Bilinear interpolation of the height grid — the single source of truth
	## for "where is the ground" used by spawns, props, loot, and tests.
	var fx := clampf((x + 70.0) / STEP, 0.0, float(GRID_N) - 0.001)
	var fz := clampf((z + 70.0) / STEP, 0.0, float(GRID_N) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var w := GRID_N + 1
	var h00: float = _heights[j * w + i]
	var h10: float = _heights[j * w + i + 1]
	var h01: float = _heights[(j + 1) * w + i]
	var h11: float = _heights[(j + 1) * w + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _grid_slope(i: int, j: int) -> float:
	var w := GRID_N + 1
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, GRID_N)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, GRID_N)
	var dx: float = _heights[j * w + i1] - _heights[j * w + i0]
	var dz: float = _heights[j1 * w + i] - _heights[j0 * w + i]
	return Vector2(dx, dz).length() / (float(i1 - i0 + j1 - j0) * 0.5 * STEP)


func _ground_color(h: float, slope: float, x: float, z: float) -> Color:
	var grass := Color(0.30, 0.52, 0.25)
	var dry := Color(0.55, 0.52, 0.30)
	var dirt := Color(0.55, 0.45, 0.31)
	var rock := Color(0.47, 0.45, 0.42)
	var sand := Color(0.68, 0.60, 0.45)
	var patch := 0.5 + 0.5 * _noise.get_noise_2d(x * 0.35 + 500.0, z * 0.35 - 500.0)
	var c := grass.lerp(dry, smoothstep(0.35, 0.75, patch) * 0.7)
	c = c.lerp(dirt, smoothstep(0.35, 0.60, slope))
	c = c.lerp(rock, smoothstep(0.60, 0.95, slope))
	var near_water := 1.0 - smoothstep(WATER_Y + 0.2, WATER_Y + 1.2, h)
	c = c.lerp(sand, near_water)
	var v := 0.93 + 0.14 * (0.5 + 0.5 * _noise.get_noise_2d(x * 1.7, z * 1.7))
	return Color(c.r * v, c.g * v, c.b * v)


func _build_terrain() -> void:
	var w := GRID_N + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	for j in range(w):
		for i in range(w):
			var x := -70.0 + float(i) * STEP
			var z := -70.0 + float(j) * STEP
			var h: float = _heights[j * w + i]
			var k := j * w + i
			verts[k] = Vector3(x, h, z)
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, GRID_N)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, GRID_N)
			var dhx: float = _heights[j * w + i1] - _heights[j * w + i0]
			var dhz: float = _heights[j1 * w + i] - _heights[j0 * w + i]
			var nx := -dhx / (float(i1 - i0) * STEP)
			var nz := -dhz / (float(j1 - j0) * STEP)
			normals[k] = Vector3(nx, 1.0, nz).normalized()
			colors[k] = _ground_color(h, _grid_slope(i, j), x, z)
	for j in range(GRID_N):
		for i in range(GRID_N):
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var d := c + 1
			# Winding: front faces (+Y) use clockwise order viewed from above.
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
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = _mats["terrain"]
	add_child(mi)
	# Collision: static concave trimesh from the same triangles.
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for t in range(indices.size()):
		faces[t] = verts[indices[t]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# Dark void-catcher plane far below (seen only past the rim at grazing angles).
	var voidm := PlaneMesh.new()
	voidm.size = Vector2(500, 500)
	var voidi := MeshInstance3D.new()
	voidi.mesh = voidm
	voidi.position = Vector3(0, -7.5, 0)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.05, 0.07, 0.06)
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	voidi.material_override = vmat
	add_child(voidi)


func _build_river_water() -> void:
	var n := _river_pts.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var dist := 0.0
	var prev: Vector2 = _river_pts[0]
	var half_w := 4.2
	for s in range(n):
		var p: Vector2 = _river_pts[s]
		var q: Vector2 = _river_pts[mini(s + 1, n - 1)]
		var r: Vector2 = _river_pts[maxi(s - 1, 0)]
		var tang := (q - r)
		if tang.length() < 0.001:
			tang = Vector2(0, 1)
		tang = tang.normalized()
		var nor := Vector2(-tang.y, tang.x)
		if s > 0:
			dist += p.distance_to(prev)
		prev = p
		var l := Vector2(p.x - nor.x * half_w, p.y - nor.y * half_w)
		var rr := Vector2(p.x + nor.x * half_w, p.y + nor.y * half_w)
		verts.append(Vector3(l.x, WATER_Y, l.y))
		verts.append(Vector3(rr.x, WATER_Y, rr.y))
		uvs.append(Vector2(0, dist / 8.0))
		uvs.append(Vector2(1, dist / 8.0))
		if s < n - 1:
			var a := s * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "RiverWater"
	mi.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/water.gdshader") as Shader
	mi.material_override = sm
	add_child(mi)


# ---------------- river bridge ----------------

func _river_frame(idx: int) -> Dictionary:
	var n := _river_pts.size()
	var p: Vector2 = _river_pts[clampi(idx, 0, n - 1)]
	var q: Vector2 = _river_pts[mini(idx + 1, n - 1)]
	var r: Vector2 = _river_pts[maxi(idx - 1, 0)]
	var tang := q - r
	if tang.length() < 0.001:
		tang = Vector2(0, 1)
	tang = tang.normalized()
	return {"pos": p, "tangent": tang, "normal": Vector2(-tang.y, tang.x)}


func _build_bridge() -> void:
	# Pick the crossing in the middle third with the most level banks.
	var n := _river_pts.size()
	var best := n / 2
	var best_d := 1.0e9
	for s in range(n / 3, 2 * n / 3):
		var f := _river_frame(s)
		var p: Vector2 = f["pos"]
		var nor: Vector2 = f["normal"]
		var hl := _gy(p.x - nor.x * 5.5, p.y - nor.y * 5.5)
		var hr := _gy(p.x + nor.x * 5.5, p.y + nor.y * 5.5)
		var d := absf(hl - hr)
		if d < best_d:
			best_d = d
			best = s
	_bridge_t = float(best) / float(n - 1)
	var f := _river_frame(best)
	var p: Vector2 = f["pos"]
	var nor: Vector2 = f["normal"]
	var yaw := atan2(nor.x, nor.y)
	var hl := _gy(p.x - nor.x * 5.5, p.y - nor.y * 5.5)
	var hr := _gy(p.x + nor.x * 5.5, p.y + nor.y * 5.5)
	var deck_y := maxf(hl, hr) + 0.7
	var span := 13.0
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y))
	# Deck planks.
	for k in range(11):
		var off := -span * 0.5 + span * (float(k) + 0.5) / 11.0
		_box(Vector3(2.4, 0.12, span / 11.0 + 0.05),
			frame * _t3(Vector3(0, deck_y, off)),
			_mats["wood"], _varc(Color(1, 1, 1), 0.12), false)
	# Deck slab collider (single, walkable).
	_batch.add_collider(Vector3(2.4, 0.25, span),
		frame * _t3(Vector3(0, deck_y - 0.06, 0)))
	# Support posts down to the riverbed.
	for sx in [-1.0, 1.0]:
		for off in [-span * 0.32, 0.0, span * 0.32]:
			var bx: float = p.x + nor.x * off
			var bz: float = p.y + nor.y * off
			var gy := _gy(bx, bz)
			var ph := deck_y - gy
			if ph > 0.2:
				_box(Vector3(0.28, ph, 0.28),
					_t3(Vector3(bx + sx * 0.9, gy + ph * 0.5, bz)),
					_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	# Railings.
	for sx in [-1.15, 1.15]:
		_box(Vector3(0.09, 0.09, span), frame * _t3(Vector3(sx, deck_y + 0.95, 0)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
		for k in range(7):
			var off := -span * 0.5 + span * float(k) / 6.0
			_box(Vector3(0.09, 0.95, 0.09), frame * _t3(Vector3(sx, deck_y + 0.48, off)),
				_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	# Bank ramps so players can walk on smoothly.
	for side in [-1.0, 1.0]:
		var bx: float = p.x + nor.x * side * 7.6
		var bz: float = p.y + nor.y * side * 7.6
		var gy := _gy(bx, bz)
		var ramp_len := 3.2
		var ang := atan2(deck_y - 0.1 - gy, ramp_len)
		var ramp := Transform3D(Basis(Vector3(1, 0, 0), -ang * side),
			frame * Vector3(side * (span * 0.5 + ramp_len * 0.5), (deck_y + gy) * 0.5 - 0.05, 0))
		_batch.add_collider(Vector3(2.4, 0.15, ramp_len + 0.6), ramp)
	# POI marker at the bridge.
	_bridge_pos = p
	poi_list.append({"name": "River Crossing", "pos": Vector3(p.x, deck_y, p.y)})
	_claim(p.x, p.y, 8.0)


# ---------------- spacing helper ----------------

func _claim(x: float, z: float, radius: float) -> bool:
	for q in _placed:
		var pq: Vector2 = q
		if pq.distance_to(Vector2(x, z)) < radius:
			return false
	_placed.append(Vector2(x, z))
	return true


func _clear_of_river(x: float, z: float, margin := 5.0) -> bool:
	return _dist_to_river(x, z) > margin


# ---------------- rocks & vegetation ----------------

func _build_rocks() -> void:
	var tries := 0
	var made := 0
	while made < 26 and tries < 300:
		tries += 1
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-62, 62)
		if not _clear_of_river(x, z, 6.0):
			continue
		if not _claim(x, z, 7.0):
			continue
		var s := _rng.randf_range(1.2, 3.4)
		var gy := _gy(x, z)
		var yaw := _rng.randf_range(0, TAU)
		var squash := _rng.randf_range(0.55, 0.9)
		var col := _varc(Color(0.55, 0.54, 0.52), 0.16)
		_rock(Vector3(s, s * squash, s * _rng.randf_range(0.7, 1.0)), yaw,
			Vector3(x, gy + s * squash * 0.18, z), _mats["rock"], col, s > 2.0)
		made += 1


func _tree(x: float, z: float) -> void:
	var gy := _gy(x, z)
	var yaw := _rng.randf_range(0, TAU)
	var th := _rng.randf_range(2.0, 2.8)
	_cyl(0.16, th, _t3(Vector3(x, gy + th * 0.5, z)),
		_mats["trunk"], _varc(Color(1, 1, 1), 0.15), true)
	var c1 := _varc(Color(0.24, 0.50, 0.22), 0.22)
	var c2 := _varc(Color(0.30, 0.56, 0.26), 0.22)
	_rock(Vector3(2.0, 1.5, 2.0), yaw, Vector3(x, gy + th + 0.7, z),
		_mats["leaf"], c1)
	_rock(Vector3(1.3, 1.0, 1.3), yaw + 0.7, Vector3(x, gy + th + 1.7, z),
		_mats["leaf"], c2)


func _build_vegetation() -> void:
	var tries := 0
	var trees := 0
	while trees < 52 and tries < 600:
		tries += 1
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-62, 62)
		if not _clear_of_river(x, z, 6.0):
			continue
		if not _claim(x, z, 5.0):
			continue
		_tree(x, z)
		trees += 1
	tries = 0
	var bushes := 0
	while bushes < 34 and tries < 400:
		tries += 1
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-62, 62)
		if not _clear_of_river(x, z, 5.0):
			continue
		if not _claim(x, z, 3.0):
			continue
		var s := _rng.randf_range(0.7, 1.4)
		_rock(Vector3(s, s * 0.7, s), _rng.randf_range(0, TAU),
			Vector3(x, _gy(x, z) + s * 0.25, z),
			_mats["leaf"], _varc(Color(0.26, 0.52, 0.24), 0.25))
		bushes += 1


# ---------------- fortifications ----------------

func _sandbag_wall(x: float, z: float, yaw: float, length := 3.6) -> void:
	var gy := _gy(x, z)
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, gy, z))
	var bag := Vector3(0.62, 0.30, 0.42)
	var n := int(length / 0.66)
	for row in range(2):
		for k in range(n):
			var off := -length * 0.5 + 0.66 * (float(k) + 0.5)
			var jog := 0.0 if row == 0 else 0.33
			_box(bag, frame * _t3(Vector3(off + jog, 0.16 + row * 0.30, _rng.randf_range(-0.03, 0.03))),
				_mats["sandbag"], _varc(Color(0.72, 0.64, 0.48), 0.12), false)
	_batch.add_collider(Vector3(length, 0.75, 0.55), frame * _t3(Vector3(0, 0.38, 0)))


func _build_sandbags() -> void:
	var spots := [
		[12.0, -18.0, 0.4], [-30.0, -30.0, 1.2], [28.0, 12.0, 2.2],
		[-6.0, 34.0, 0.9], [44.0, 8.0, 1.8], [-44.0, 22.0, 0.2],
		[8.0, -44.0, 2.8], [-18.0, -8.0, 1.0], [36.0, -20.0, 0.6],
		[-36.0, 48.0, 2.4], [20.0, 44.0, 1.5], [-52.0, -34.0, 0.8],
		[48.0, -34.0, 1.1], [-8.0, -38.0, 0.3], [14.0, 28.0, 2.0],
		[-40.0, -2.0, 1.4],
	]
	for s in spots:
		var sx: float = s[0]
		var sz: float = s[1]
		var syaw: float = s[2]
		if not _clear_of_river(sx, sz, 5.0):
			continue
		if not _claim(sx, sz, 4.0):
			continue
		_sandbag_wall(sx, sz, syaw)


func _barricade(x: float, z: float, yaw: float) -> void:
	var gy := _gy(x, z)
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, gy, z))
	_box(Vector3(1.1, 1.1, 1.1), frame * _t3(Vector3(-0.6, 0.55, 0)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(1.1, 1.1, 1.1), frame * _t3(Vector3(0.6, 0.55, 0.15)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(0.9, 0.9, 0.9), frame * _t3(Vector3(0.0, 1.55, 0.05)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)


func _build_barricades() -> void:
	var tries := 0
	var made := 0
	while made < 9 and tries < 200:
		tries += 1
		var x := _rng.randf_range(-58, 58)
		var z := _rng.randf_range(-58, 58)
		if not _clear_of_river(x, z, 5.0):
			continue
		if not _claim(x, z, 6.0):
			continue
		_barricade(x, z, _rng.randf_range(0, TAU))
		made += 1


func _watchtower(x: float, z: float, yaw: float) -> void:
	var gy := _gy(x, z)
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, gy, z))
	var plat_y := 4.2
	# Legs.
	for sx in [-1.3, 1.3]:
		for sz in [-1.3, 1.3]:
			_box(Vector3(0.28, plat_y, 0.28), frame * _t3(Vector3(sx, plat_y * 0.5, sz)),
				_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), true)
	# Platform + railing (enterable via ramp).
	_box(Vector3(3.4, 0.25, 3.4), frame * _t3(Vector3(0, plat_y, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.08), true)
	for i in range(4):
		var a := float(i) * PI * 0.5
		var px := cos(a) * 1.62
		var pz := sin(a) * 1.62
		_box(Vector3(0.08, 0.9, 0.08), frame * _t3(Vector3(px, plat_y + 0.55, pz)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
		_box(Vector3(3.3, 0.08, 0.08), frame * Transform3D(Basis(Vector3.UP, -a), Vector3.ZERO) * _t3(Vector3(px, plat_y + 1.0, pz)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	# Roof on posts.
	for sx in [-1.4, 1.4]:
		for sz in [-1.4, 1.4]:
			_box(Vector3(0.18, 1.6, 0.18), frame * _t3(Vector3(sx, plat_y + 1.9, sz)),
				_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	_box(Vector3(4.0, 0.16, 4.0), frame * _t3(Vector3(0, plat_y + 2.75, 0)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.1), false)
	# Access ramp (walkable).
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
	house_positions.append(Vector3(x, gy, z))


func _build_watchtowers() -> void:
	# Tower 1 crowns the tallest hill (Hilltop Outpost POI).
	_watchtower(40.0, -44.0, 0.3)
	poi_list.append({"name": "Hilltop Outpost",
		"pos": Vector3(40.0, _gy(40.0, -44.0), -44.0)})
	_claim(40.0, -44.0, 9.0)
	# Tower 2 guards the south approach.
	var tx := -20.0
	var tz := 52.0
	if _clear_of_river(tx, tz, 6.0) and _claim(tx, tz, 8.0):
		_watchtower(tx, tz, 2.1)


# ---------------- ruined structures ----------------

func _broken_wall(frame: Transform3D, ax: float, az: float, bx: float, bz: float, base_h: float) -> void:
	var length := Vector2(bx - ax, bz - az).length()
	var n := maxi(int(length / 2.0), 1)
	var ang := atan2(bx - ax, bz - az)
	for k in range(n):
		if _rng.randf() < 0.22:
			continue  # collapsed chunk = breach gap
		var tm := (float(k) + 0.5) / float(n)
		var mx := lerpf(ax, bx, tm)
		var mz := lerpf(az, bz, tm)
		var h := base_h * _rng.randf_range(0.35, 1.0)
		var xf := frame * Transform3D(Basis(Vector3.UP, ang), Vector3(mx, h * 0.5, mz))
		_box(Vector3(0.35, h, length / float(n) + 0.05), xf,
			_mats["concrete"], _varc(Color(1, 1, 1), 0.12), true)


func _ruin_stairs(frame: Transform3D, x0: float, run: float, width: float, zc: float, rise: float) -> void:
	# Concrete stair run along +x: visual steps + one ramp collider.
	var steps := 10
	for i in range(steps):
		var sx := x0 + run * (float(i) + 0.5) / float(steps)
		var sy := rise * (float(i) + 0.5) / float(steps)
		_box(Vector3(run / float(steps) + 0.05, 0.12, width),
			frame * _t3(Vector3(sx, sy - 0.06, zc)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.08), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var ramp := Transform3D(Basis(Vector3(0, 0, 1), ang),
		frame * Vector3(x0 + run * 0.5, rise * 0.5 - 0.06, zc))
	_batch.add_collider(Vector3(length, 0.12, width), ramp)


func _slab_hole_v(frame: Transform3D, w: float, d: float, y: float,
		hx0: float, hx1: float, hz: float, hzw: float) -> void:
	# Concrete upper-floor slab with a rectangular stairwell hole.
	var t := 0.22
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


func _ruin2(x: float, z: float, yaw: float, w: float, d: float) -> void:
	# Two-story ruined structure: broken ground walls, interior stairs to a
	# partial upper floor (stairwell hole), broken upper walls, loot upstairs.
	var gy := _gy(x, z)
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, gy, z))
	var uh := 2.8  # upper floor height
	# Broken ground walls (taller to carry a second story).
	_broken_wall(frame, -w * 0.5, -d * 0.5, w * 0.5, -d * 0.5, 3.0)
	_broken_wall(frame, -w * 0.5, d * 0.5, w * 0.5, d * 0.5, 2.6)
	_broken_wall(frame, -w * 0.5, -d * 0.5, -w * 0.5, d * 0.5, 2.8)
	_broken_wall(frame, w * 0.5, -d * 0.5, w * 0.5, d * 0.5, 2.4)
	# Interior stairs along the north wall.
	var sx0 := -w * 0.5 + 0.8
	var szc := -d * 0.5 + 1.4
	_slab_hole_v(frame, w, d, uh, sx0, sx0 + 3.6, szc, 1.4)
	_ruin_stairs(frame, sx0, 3.6, 1.4, szc, uh)
	# Broken upper walls.
	var uframe := Transform3D(frame.basis, frame.origin + Vector3(0, uh, 0))
	_broken_wall(uframe, -w * 0.5, -d * 0.5, w * 0.5, -d * 0.5, 1.8)
	_broken_wall(uframe, -w * 0.5, d * 0.5, w * 0.5, d * 0.5, 1.6)
	_broken_wall(uframe, -w * 0.5, -d * 0.5, -w * 0.5, d * 0.5, 1.7)
	_broken_wall(uframe, w * 0.5, -d * 0.5, w * 0.5, d * 0.5, 1.5)
	# Fallen slab chunks + crates on the ground floor.
	for k in range(3):
		var px := _rng.randf_range(-w * 0.3, w * 0.3)
		var pz := _rng.randf_range(0.0, d * 0.3)
		_box(Vector3(_rng.randf_range(1.2, 2.2), 0.22, _rng.randf_range(1.0, 1.8)),
			frame * Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)),
				Vector3(px, 0.35, pz)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(1.0, 1.0, 1.0), frame * _t3(Vector3(w * 0.3, 0.5, d * 0.25)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	# Hanging lantern on the ground floor (emissive, no real light cost).
	_box(Vector3(0.04, 0.6, 0.04), frame * _t3(Vector3(0, 2.3, 0.5)),
		_mats["wood_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.3, 0.36, 0.3), frame * _t3(Vector3(0, 1.95, 0.5)),
		_mats["lantern"], Color(1, 1, 1), false)
	# Crates + loot on the upper floor.
	_box(Vector3(0.9, 0.9, 0.9), frame * _t3(Vector3(-w * 0.3, uh + 0.45, d * 0.25)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	for k in range(2):
		var kind: String = ["ammo", "health", "armor"][k % 3]
		var amt := 60 if kind == "ammo" else (40 if kind == "health" else 50)
		var lp: Vector3 = frame * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), uh,
			_rng.randf_range(-d * 0.2, d * 0.3))
		loot_spots.append([kind, amt, Vector3(lp.x, uh + 0.55, lp.z)])
	house_positions.append(Vector3(x, gy, z))
	_claim(x, z, 9.0)


func _ruin(x: float, z: float, yaw: float, w: float, d: float) -> void:
	var gy := _gy(x, z)
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, gy, z))
	# Broken perimeter walls (concrete), entry gaps appear randomly.
	_broken_wall(frame, -w * 0.5, -d * 0.5, w * 0.5, -d * 0.5, 2.6)
	_broken_wall(frame, -w * 0.5, d * 0.5, w * 0.5, d * 0.5, 2.2)
	_broken_wall(frame, -w * 0.5, -d * 0.5, -w * 0.5, d * 0.5, 2.4)
	_broken_wall(frame, w * 0.5, -d * 0.5, w * 0.5, d * 0.5, 2.0)
	# Fallen slab chunks inside.
	for k in range(3):
		var px := _rng.randf_range(-w * 0.3, w * 0.3)
		var pz := _rng.randf_range(-d * 0.3, d * 0.3)
		_box(Vector3(_rng.randf_range(1.2, 2.2), 0.22, _rng.randf_range(1.0, 1.8)),
			frame * Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)),
				Vector3(px, 0.35, pz)),
			_mats["concrete_dark"], _varc(Color(1, 1, 1), 0.1), true)
	# Sparse furnishings: crates + a table.
	_box(Vector3(1.0, 1.0, 1.0),
		frame * _t3(Vector3(w * 0.25, 0.5, d * 0.2)),
		_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	_box(Vector3(1.6, 0.08, 0.9),
		frame * _t3(Vector3(-w * 0.2, 0.75, -d * 0.15)),
		_mats["wood"], _varc(Color(1, 1, 1), 0.1), false)
	for lx in [-0.7, 0.7]:
		for lz in [-0.35, 0.35]:
			_box(Vector3(0.08, 0.75, 0.08),
				frame * _t3(Vector3(-w * 0.2 + lx, 0.38, -d * 0.15 + lz)),
				_mats["wood_dark"], _varc(Color(1, 1, 1), 0.08), false)
	house_positions.append(Vector3(x, gy, z))
	_claim(x, z, 9.0)


func _build_ruins() -> void:
	var spots := [
		[20.0, -34.0, 0.5, 9.0, 7.5],
		[27.0, -27.0, 2.2, 7.0, 6.0],
		[13.0, -41.0, 1.1, 8.0, 6.5],
	]
	for si in range(spots.size()):
		var s: Array = spots[si]
		var sx: float = s[0]
		var sz: float = s[1]
		if not _clear_of_river(sx, sz, 6.0):
			continue
		if si == 0:
			_ruin2(sx, sz, float(s[2]), float(s[3]), float(s[4]))
		else:
			_ruin(sx, sz, float(s[2]), float(s[3]), float(s[4]))


# ---------------- valley camp ----------------

func _tent(x: float, z: float, yaw: float, col: Color) -> void:
	var gy := _gy(x, z)
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, gy, z))
	var tilt := 0.95
	for side in [-1.0, 1.0]:
		var panel := frame * Transform3D(Basis(Vector3(1, 0, 0), side * tilt),
			Vector3(0, 0.95, side * 0.62))
		_box(Vector3(3.2, 0.07, 1.55), panel, _mats["tent"], col, false)
		_batch.add_collider(Vector3(3.2, 0.6, 1.55), panel)
	_box(Vector3(2.5, 1.3, 0.07), frame * _t3(Vector3(0, 0.65, -1.45)),
		_mats["tent"], col.darkened(0.15), false)
	# Hanging lantern (emissive, no real light cost).
	_box(Vector3(0.04, 0.6, 0.04), frame * _t3(Vector3(0, 1.9, 0)),
		_mats["wood_dark"], Color(1, 1, 1), false)
	_box(Vector3(0.3, 0.36, 0.3), frame * _t3(Vector3(0, 1.55, 0)),
		_mats["lantern"], Color(1, 1, 1), false)
	# Bedroll inside (visible through the open front).
	_box(Vector3(0.8, 0.18, 1.9), frame * _t3(Vector3(0.3, 0.32, 0)),
		_mats["wood_dark"], _varc(Color(1, 1, 1), 0.1), false)


func _campfire(x: float, z: float) -> void:
	var gy := _gy(x, z)
	for k in range(8):
		var a := TAU * float(k) / 8.0
		_rock(Vector3(0.35, 0.3, 0.35), a,
			Vector3(x + cos(a) * 0.9, gy + 0.12, z + sin(a) * 0.9),
			_mats["rock"], _varc(Color(0.5, 0.5, 0.5), 0.1))
	for k in range(3):
		var a := TAU * float(k) / 3.0 + 0.4
		_cyl(0.09, 1.1,
			Transform3D(Basis(Vector3(0, 0, 1), 0.5) * Basis(Vector3.UP, a),
				Vector3(x, gy + 0.25, z)),
			_mats["wood_dark"], _varc(Color(1, 1, 1), 0.1))
	_cyl(0.32, 0.14, _t3(Vector3(x, gy + 0.2, z)), _mats["fire"], Color(1, 1, 1))


func _build_camp() -> void:
	var cx := -14.0
	var cz := 8.0
	var gy := _gy(cx, cz)
	var tent_cols := [Color(0.45, 0.47, 0.32), Color(0.62, 0.58, 0.45),
		Color(0.45, 0.47, 0.32), Color(0.50, 0.42, 0.30)]
	var i := 0
	for a in [0.5, 2.0, 3.6, 5.1]:
		var tx := cx + cos(a) * 7.0
		var tz := cz + sin(a) * 7.0
		_tent(tx, tz, -a + PI * 0.5, tent_cols[i % 4])
		_claim(tx, tz, 4.0)
		i += 1
	_campfire(cx, cz)
	# Supply crates around the camp.
	for k in range(5):
		var px := cx + _rng.randf_range(-9.0, 9.0)
		var pz := cz + _rng.randf_range(-9.0, 9.0)
		if _clear_of_river(px, pz, 4.0) and _claim(px, pz, 2.0):
			_box(Vector3(0.9, 0.9, 0.9),
				_t3(Vector3(px, _gy(px, pz) + 0.45, pz)),
				_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	# Water barrels + extra crate stacks at the camp.
	for k2 in range(3):
		var bx := cx + _rng.randf_range(-8.0, 8.0)
		var bz := cz + _rng.randf_range(-8.0, 8.0)
		if _clear_of_river(bx, bz, 4.0) and _claim(bx, bz, 2.0):
			_cyl(0.4, 1.0, _t3(Vector3(bx, _gy(bx, bz) + 0.5, bz)),
				_mats["metal"], _varc(Color(0.35, 0.45, 0.60), 0.15), true)
	for k3 in range(2):
		var qx := cx + _rng.randf_range(-8.0, 8.0)
		var qz := cz + _rng.randf_range(-8.0, 8.0)
		if _clear_of_river(qx, qz, 4.0) and _claim(qx, qz, 2.5):
			var qy := _gy(qx, qz)
			_box(Vector3(1.0, 1.0, 1.0), _t3(Vector3(qx, qy + 0.5, qz)),
				_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
			_box(Vector3(0.8, 0.8, 0.8),
				Transform3D(Basis(Vector3.UP, 0.4), Vector3(qx + 0.2, qy + 1.4, qz)),
				_mats["crate"], _varc(Color(1, 1, 1), 0.1), true)
	# Banner pole.
	_cyl(0.06, 3.2, _t3(Vector3(cx + 4.0, gy + 1.6, cz - 4.0)),
		_mats["metal"], _varc(Color(1, 1, 1), 0.08))
	_box(Vector3(1.3, 0.8, 0.05),
		_t3(Vector3(cx + 4.7, gy + 2.6, cz - 4.0)),
		_mats["tent"], Color(0.75, 0.25, 0.15), false)
	_claim(cx, cz, 11.0)
	poi_list.append({"name": "Valley Camp", "pos": Vector3(cx, gy, cz)})


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
	# Hilltop Outpost + River Crossing were registered by their builders.
	poi_list.append({"name": "Ruined Compound",
		"pos": Vector3(20, _gy(20, -34), -34)})


func _add_loot(kind: String, amount: int, x: float, z: float) -> void:
	loot_spots.append([kind, amount, Vector3(x, _gy(x, z) + 0.55, z)])


func _scatter_loot() -> void:
	var kinds := ["health", "armor", "ammo"]
	var amounts := {"health": 40, "armor": 50, "ammo": 60}
	var idx := 0
	for p in poi_list:
		var pp: Vector3 = p["pos"]
		for k in range(8):
			var a := TAU * float(k) / 8.0 + _rng.randf_range(-0.2, 0.2)
			var r := _rng.randf_range(3.0, 9.0)
			var lx := pp.x + cos(a) * r
			var lz := pp.z + sin(a) * r
			if absf(lx) > 66.0 or absf(lz) > 66.0:
				continue
			if not _clear_of_river(lx, lz, 3.5):
				continue
			var kind: String = kinds[idx % 3]
			_add_loot(kind, int(amounts[kind]), lx, lz)
			idx += 1
	var tries := 0
	while loot_spots.size() < 72 and tries < 500:
		tries += 1
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-62, 62)
		if not _clear_of_river(x, z, 3.5):
			continue
		if not _claim(x, z, 4.0):
			continue
		var kind2: String = kinds[idx % 3]
		_add_loot(kind2, int(amounts[kind2]), x, z)
		idx += 1


func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -10, -85), Vector3(170, 50, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	player_spawn = Vector3(-24, _gy(-24, 2) + 0.6, 2)
	enemy_spawns = [
		Vector3(40, _gy(40, -44) + 0.6, -44),
		Vector3(24, _gy(24, -30) + 0.6, -30),
		Vector3(_bridge_pos.x + 8.0, _gy(_bridge_pos.x + 8.0, _bridge_pos.y) + 0.6, _bridge_pos.y),
		Vector3(-8, _gy(-8, 52) + 0.6, 52),
		Vector3(-52, _gy(-52, -52) + 0.6, -52),
		Vector3(30, _gy(30, 20) + 0.6, 20),
	]
	print("ValleyCombat built: hills=", _hills.size(), " river_pts=", _river_pts.size(),
		" instances=", _batch.box_count(), " draws=", draws,
		" colliders=", _batch.collider_count(), " loot=", loot_spots.size(),
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 110.0:
			cn.position.x = -110.0
