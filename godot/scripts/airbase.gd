class_name AirbaseMap
extends Node3D
## Phase 12 (FINAL MAP): Airbase — Stealth Wing (military air station).
## Flat 140x140m base: long runway strip along the south edge with full
## painted markings, 3 parked B2 stealth bombers (wide flat flying-wing
## planform built from ~12 stepped segments, W trailing edge, cockpit
## hump, engine intake humps; sealed, colliders as massive cover, loot
## rings around each), 2 enterable hardened aircraft shelters with arched
## roofs (tool benches, crates, parked drone silhouette, loot), enterable
## command building (radar room: consoles with emissive screens, big map
## table, chairs, interior lighting, loot), enterable control tower (shaft
## + switchback stairs + glass cab with window openings, stairs, loot in
## cab), fuel depot (4 tanks, pipes, berm walls, warning signs), tarmac
## cover (sandbag walls, military trucks/jeeps, crates, blast barriers),
## perimeter fence with 2 enterable guard booths and a main gate.
## Seeded (SEED), merge-ready edges, GeoBatch static batching throughout.
## Every batched material sets vertex_color_use_as_albedo so MultiMesh
## per-instance colors actually render.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 70.0
const SEED := 20261019

const POI_DEFS := [
	{"name": "Bomber Row", "pos": Vector3(0, 0, -24)},
	{"name": "Hardened Shelters", "pos": Vector3(-17.5, 0, 25)},
	{"name": "Command", "pos": Vector3(30, 0, 30)},
	{"name": "Control Tower", "pos": Vector3(52, 0, 6)},
]

var map_extent := MAP_EXTENT
var player_spawn := Vector3(0, 0.6, 58)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []  # shelters / command / tower / booths (API compat)

var _rng := RandomNumberGenerator.new()
var _batch
var _mats := {}
var _clouds: Array = []
var _beacon_mat: StandardMaterial3D
var _nav_green: StandardMaterial3D
var _time := 0.0
var _placed: Array = []  # Vector2 points claimed by props (spacing)
var _bomber_rects: Array = []  # [cx, cz, hx, hz] footprints (loot exclusion)


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_build_ground()
	_build_runway()
	_build_apron_taxiway()
	_build_bombers()
	_build_shelters()
	_build_command()
	_build_tower()
	_build_fuel_depot()
	_build_vehicles()
	_build_cover()
	_build_fence_booths()
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
	# MultiMesh per-instance colors must drive albedo or variation renders white.
	m.vertex_color_use_as_albedo = true
	return m


func _make_mats() -> void:
	_mats["terrain"] = _std(Color(1, 1, 1), 0.95)
	_mats["asphalt"] = _std(Color(1, 1, 1), 0.95)
	_mats["paint_white"] = _std(Color(1, 1, 1), 0.9)
	_mats["paint_yellow"] = _std(Color(1, 1, 1), 0.9)
	_mats["concrete"] = _std(Color(1, 1, 1), 0.9)
	_mats["concrete_dark"] = _std(Color(1, 1, 1), 0.9)
	_mats["wall"] = _std(Color(1, 1, 1), 0.9)
	_mats["trim"] = _std(Color(1, 1, 1), 0.85)
	_mats["roof"] = _std(Color(1, 1, 1), 0.9)
	_mats["metal"] = _std(Color(1, 1, 1), 0.5, 0.5)
	_mats["glass"] = _std(Color(1, 1, 1), 0.25, 0.6)   # per-instance dark tint
	_mats["bomber"] = _std(Color(1, 1, 1), 0.65, 0.15)  # per-instance dark matte grey
	_mats["crate"] = _std(Color(1, 1, 1), 0.9)
	_mats["wood"] = _std(Color(1, 1, 1), 0.9)
	_mats["drum"] = _std(Color(1, 1, 1), 0.6, 0.4)      # per-instance colors
	_mats["tire"] = _std(Color(1, 1, 1), 0.95)
	_mats["sandbag"] = _std(Color(1, 1, 1), 0.95)       # per-instance tan variation
	_mats["screen"] = _std(Color(1, 1, 1), 0.4)
	var scr: StandardMaterial3D = _mats["screen"]
	scr.emission_enabled = true
	scr.emission = Color(0.25, 0.55, 1.0)
	scr.emission_energy_multiplier = 1.6
	var mapscr := _std(Color(1, 1, 1), 0.4)
	mapscr.emission_enabled = true
	mapscr.emission = Color(0.3, 0.9, 0.45)
	mapscr.emission_energy_multiplier = 1.4
	_mats["map_screen"] = mapscr
	_mats["sign"] = _std(Color(1, 1, 1), 0.5)
	var sign: StandardMaterial3D = _mats["sign"]
	sign.emission_enabled = true
	sign.emission = Color(0.85, 0.75, 0.2)
	sign.emission_energy_multiplier = 0.9
	var lamp := _std(Color(1, 1, 1), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.7)
	lamp.emission_energy_multiplier = 2.0
	_mats["lamp_head"] = lamp
	_beacon_mat = _std(Color(1, 1, 1), 0.5)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.1, 0.1)
	_beacon_mat.emission_energy_multiplier = 3.0
	_nav_green = _std(Color(1, 1, 1), 0.5)
	_nav_green.emission_enabled = true
	_nav_green.emission = Color(0.1, 1.0, 0.2)
	_nav_green.emission_energy_multiplier = 3.0


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
	var b: Basis
	if axis == Vector3.RIGHT:
		b = Basis(Vector3(0, 0, 1), PI * 0.5)
	else:
		b = Basis(Vector3(1, 0, 0), PI * 0.5)
	_cyl(radius, length, frame * Transform3D(b, center), mat, col, collide)


func _strut(a: Vector3, b: Vector3, w: float, d: float, mat: StandardMaterial3D) -> void:
	# Oriented box beam between two points.
	var dv: Vector3 = b - a
	var length := dv.length()
	if length < 0.01:
		return
	var mid: Vector3 = (a + b) * 0.5
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
			_mats["concrete_dark"], _varc(Color(0.55, 0.54, 0.52), 0.06), false)
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var local := Transform3D(Basis(Vector3(0, 0, 1), ang),
		Vector3(x0 + run * 0.5, y_base + rise * 0.5 - 0.06, 0))
	_batch.add_collider(Vector3(length, 0.12, width), frame * local)


func _landing(cx: float, cy: float, cz: float, w := 2.4, d := 2.2) -> void:
	# Flat landing slab with railings on both outer sides.
	_box(Vector3(w, 0.15, d), _t3(Vector3(cx, cy - 0.075, cz)),
		_mats["concrete"], Color(0.60, 0.59, 0.56), true)
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
			_mats["concrete"], Color(0.60, 0.59, 0.56), true)
	if w * 0.5 - hx1 > 0.05:
		var sw2 := w * 0.5 - hx1
		_box(Vector3(sw2, t, d), frame * _t3(Vector3(hx1 + sw2 * 0.5, y0, 0)),
			_mats["concrete"], Color(0.60, 0.59, 0.56), true)
	var hw := hx1 - hx0
	var fz0 := -d * 0.5
	var fz1 := hz - hzw * 0.5
	var bz0 := hz + hzw * 0.5
	var bz1 := d * 0.5
	if fz1 - fz0 > 0.05:
		_box(Vector3(hw, t, fz1 - fz0), frame * _t3(Vector3((hx0 + hx1) * 0.5, y0, (fz0 + fz1) * 0.5)),
			_mats["concrete"], Color(0.60, 0.59, 0.56), true)
	if bz1 - bz0 > 0.05:
		_box(Vector3(hw, t, bz1 - bz0), frame * _t3(Vector3((hx0 + hx1) * 0.5, y0, (bz0 + bz1) * 0.5)),
			_mats["concrete"], Color(0.60, 0.59, 0.56), true)


func _light_panel(lx: float, lz: float, fy: float) -> void:
	# Emissive ceiling light: housing + glowing diffuser (batched, no real light).
	_box(Vector3(2.0, 0.08, 1.1), _t3(Vector3(lx, fy, lz)),
		_mats["metal"], Color(0.7, 0.7, 0.72), false)
	_box(Vector3(1.8, 0.05, 0.9), _t3(Vector3(lx, fy - 0.055, lz)),
		_mats["lamp_head"], Color(1, 1, 1), false)


func _claim(x: float, z: float, radius: float) -> bool:
	for q in _placed:
		var pq: Vector2 = q
		if pq.distance_to(Vector2(x, z)) < radius:
			return false
	_placed.append(Vector2(x, z))
	return true


func _in_bomber(x: float, z: float) -> bool:
	for r in _bomber_rects:
		if absf(x - float(r[0])) < float(r[2]) and absf(z - float(r[1])) < float(r[3]):
			return true
	return false


# ---------------- ground / runway / apron ----------------

func _build_ground() -> void:
	# Dry-grass military field, top at y=0 (collision = global ground plane).
	_box(Vector3(140, 1.0, 140), _t3(Vector3(0, -0.5, 0)),
		_mats["terrain"], Color(0.50, 0.48, 0.40), false)
	# One big walk collider for the flat ground.
	_batch.add_collider(Vector3(140.0, 0.4, 140.0), _t3(Vector3(0, -0.21, 0)))
	# Dirt patches for variation.
	for k in range(10):
		var px := _rng.randf_range(-60, 60)
		var pz := _rng.randf_range(-45, 60)
		if absf(pz) < 46.0 and absf(px) < 46.0:
			continue  # keep the apron area clean
		_cyl(_rng.randf_range(3.0, 7.0), 0.03, _t3(Vector3(px, 0.015, pz)),
			_mats["terrain"], _varc(Color(0.55, 0.50, 0.38), 0.12), false)


func _build_runway() -> void:
	# Runway strip along the south edge: z -62..-50, asphalt band top at 0.04.
	var asph: StandardMaterial3D = _mats["asphalt"]
	var pw: StandardMaterial3D = _mats["paint_white"]
	_box(Vector3(128, 0.04, 12), _t3(Vector3(0, 0.02, -56)),
		asph, Color(0.24, 0.24, 0.25), false)
	# Centerline dashes, proud of the asphalt.
	var x := -60.0
	while x <= 60.0:
		_box(Vector3(3.0, 0.02, 0.35), _t3(Vector3(x, 0.05, -56)), pw, Color(1, 1, 1), false)
		x += 6.0
	# Edge lines.
	for ez in [-61.5, -50.5]:
		_box(Vector3(128, 0.02, 0.25), _t3(Vector3(0, 0.05, float(ez))), pw, Color(1, 1, 1), false)
	# Threshold bars at both ends: 8 bars across the width.
	for tx in [-58.0, 58.0]:
		for k in range(8):
			var bz := -60.5 + float(k) * 1.3
			_box(Vector3(2.5, 0.02, 0.6), _t3(Vector3(float(tx), 0.05, bz)), pw, Color(1, 1, 1), false)
	# Touchdown zone markers: pairs of bars flanking the centerline.
	for tdx in [-45.0, -25.0, 25.0, 45.0]:
		for sz in [-58.5, -53.5]:
			_box(Vector3(1.8, 0.02, 0.5), _t3(Vector3(float(tdx), 0.05, float(sz))), pw, Color(1, 1, 1), false)
	# Blast pads at both runway ends (chevrons: simple angled bars).
	for bx in [-64.0, 64.0]:
		_box(Vector3(0.35, 0.02, 8.0),
			Transform3D(Basis(Vector3.UP, 0.6 * sign(float(bx))), Vector3(float(bx), 0.05, -56)),
			_mats["paint_yellow"], Color(1, 1, 1), false)


func _build_apron_taxiway() -> void:
	# Concrete apron under the bomber row + taxiway link to the runway.
	var asph: StandardMaterial3D = _mats["asphalt"]
	var conc: StandardMaterial3D = _mats["concrete"]
	var pw: StandardMaterial3D = _mats["paint_white"]
	_box(Vector3(92, 0.04, 22), _t3(Vector3(0, 0.02, -30)),
		conc, Color(0.58, 0.57, 0.54), false)
	_box(Vector3(10, 0.04, 12), _t3(Vector3(0, 0.02, -45)),
		asph, Color(0.26, 0.26, 0.27), false)
	# Taxiway centerline (yellow) from runway to apron.
	var z := -49.0
	while z <= -36.0:
		_box(Vector3(0.3, 0.02, 1.6), _t3(Vector3(0, 0.05, z)),
			_mats["paint_yellow"], Color(1, 1, 1), false)
		z += 3.2
	# Parking slot outlines on the apron (white corner ticks per bomber).
	for bx in [-40.0, -5.0, 30.0]:
		for sx in [-11.5, 11.5]:
			for sz2 in [-6.5, 6.5]:
				_box(Vector3(2.0, 0.02, 0.25),
					_t3(Vector3(float(bx) + float(sx), 0.05, -29.0 + float(sz2))),
					pw, Color(1, 1, 1), false)


func _loot_y_at(x: float, z: float) -> float:
	# Pavement tops sit at ~0.04; interior floors at 0.06; cab at 16.
	if x >= -46.0 and x <= 46.0 and z >= -41.0 and z <= -19.0:
		return 0.60
	if x >= -5.0 and x <= 5.0 and z >= -51.0 and z <= -39.0:
		return 0.60
	if x >= -64.0 and x <= 64.0 and z >= -62.0 and z <= -50.0:
		return 0.60
	if x >= 22.0 and x <= 38.0 and z >= 16.0 and z <= 28.0:
		return 0.61  # command interior floor
	if (x >= -37.0 and x <= -23.0 and z >= 19.0 and z <= 31.0) \
			or (x >= -12.0 and x <= 2.0 and z >= 19.0 and z <= 31.0):
		return 0.61  # shelter interiors
	return 0.55


# ---------------- B2 stealth bombers ----------------

func _bomber(frame: Transform3D) -> void:
	# Signature shape: wide flat FLYING WING. Planform built from 12 stepped
	# box segments: tapered nose -> widening center -> W (double-V) trailing
	# edge -> swept outer panels -> pointed tips. Reads as a bat wing from
	# above, low and flat from the side. Sealed: colliders make it cover.
	var dark: StandardMaterial3D = _mats["bomber"]
	var glass: StandardMaterial3D = _mats["glass"]
	var metal: StandardMaterial3D = _mats["metal"]
	var grey := Color(0.20, 0.21, 0.23)
	var segs := [
		# size(x w, y h, z d), local pos, yaw
		[Vector3(3.0, 0.9, 1.6), Vector3(0, 1.50, 5.2), 0.0],   # nose tip
		[Vector3(6.5, 0.9, 2.0), Vector3(0, 1.50, 4.0), 0.0],   # forward
		[Vector3(10.0, 0.9, 2.0), Vector3(0, 1.50, 2.6), 0.0],  # mid
		[Vector3(12.5, 0.9, 2.0), Vector3(0, 1.50, 1.0), 0.0],  # mid-aft
		[Vector3(13.5, 0.9, 1.8), Vector3(0, 1.50, -0.8), 0.0], # aft
		[Vector3(6.0, 0.9, 1.6), Vector3(0, 1.50, -2.4), 0.0],  # trailing center (W peak)
		[Vector3(4.0, 0.85, 1.4), Vector3(-4.9, 1.48, -2.7), -0.45],  # notch L
		[Vector3(4.0, 0.85, 1.4), Vector3(4.9, 1.48, -2.7), 0.45],    # notch R
		[Vector3(3.6, 0.8, 2.6), Vector3(-7.6, 1.45, -1.2), -0.3],    # outer L (swept)
		[Vector3(3.6, 0.8, 2.6), Vector3(7.6, 1.45, -1.2), 0.3],      # outer R (swept)
		[Vector3(2.2, 0.65, 1.6), Vector3(-10.1, 1.42, -2.0), -0.5], # tip L
		[Vector3(2.2, 0.65, 1.6), Vector3(10.1, 1.42, -2.0), 0.5],   # tip R
	]
	for s in segs:
		var sz: Vector3 = s[0]
		var lp: Vector3 = s[1]
		var yw: float = s[2]
		var xf := frame * Transform3D(Basis(Vector3.UP, yw), lp)
		_box(sz, xf, dark, _varc(grey, 0.10), false)
	# Cockpit hump near the nose + dark canopy strip, proud of the wing.
	_box(Vector3(2.4, 0.9, 2.0), frame * _t3(Vector3(0, 2.30, 4.4)),
		dark, _varc(grey, 0.06), false)
	_box(Vector3(1.8, 0.30, 0.9), frame * _t3(Vector3(0, 2.62, 5.0)),
		glass, Color(0.08, 0.11, 0.14), false)
	# Engine intake humps on top + dark intake mouths.
	for ex in [-3.0, 3.0]:
		_box(Vector3(2.6, 0.7, 2.2), frame * _t3(Vector3(float(ex), 2.10, 1.6)),
			dark, _varc(grey, 0.08), false)
		_box(Vector3(1.6, 0.40, 1.2), frame * _t3(Vector3(float(ex), 2.50, 0.8)),
			_mats["concrete_dark"], Color(0.10, 0.10, 0.11), false)
	# Landing gear: struts + wheels.
	for gx in [0.0, -3.5, 3.5]:
		var gz := 4.6 if float(gx) == 0.0 else 0.5
		_box(Vector3(0.3, 1.1, 0.3), frame * _t3(Vector3(float(gx), 0.55, float(gz))),
			metal, Color(0.45, 0.46, 0.48), false)
		_cyl_axis(0.28, 0.35, Vector3.RIGHT, Vector3(float(gx), 0.28, float(gz)),
			frame, _mats["tire"], Color(0.12, 0.12, 0.13), false)
	# Nav lights: red (port) / green (starboard) tips, emissive.
	_batch.add_rock(Vector3(0.22, 0.22, 0.22),
		frame * Transform3D(Basis(), Vector3(-11.2, 1.55, -2.4)),
		_beacon_mat, Color(1, 1, 1), false)
	_batch.add_rock(Vector3(0.22, 0.22, 0.22),
		frame * Transform3D(Basis(), Vector3(11.2, 1.55, -2.4)),
		_nav_green, Color(1, 1, 1), false)
	# Massive cover colliders (sealed: not enterable).
	_box(Vector3(12.0, 2.6, 10.0), frame * _t3(Vector3(0, 1.4, 1.5)),
		dark, Color(1, 1, 1), true)
	_box(Vector3(8.0, 2.4, 5.0), frame * _t3(Vector3(-7.5, 1.3, -1.2)),
		dark, Color(1, 1, 1), true)
	_box(Vector3(8.0, 2.4, 5.0), frame * _t3(Vector3(7.5, 1.3, -1.2)),
		dark, Color(1, 1, 1), true)


func _build_bombers() -> void:
	var spots := [Vector3(-40, 0, -28), Vector3(-5, 0, -30), Vector3(30, 0, -28)]
	for sp in spots:
		var spx: float = sp.x
		var spz: float = sp.z
		var frame := Transform3D(Basis(), Vector3(spx, 0, spz))
		_bomber(frame)
		_bomber_rects.append([spx, spz, 12.5, 7.5])
		_claim(spx, spz, 16.0)
		# Loot ring around each bomber.
		for k in range(6):
			var a: float = TAU * float(k) / 6.0 + _rng.randf_range(-0.2, 0.2)
			var r: float = _rng.randf_range(13.5, 15.0)
			var lx: float = spx + cos(a) * r
			var lz: float = spz + sin(a) * r
			var kind: String = ["health", "armor", "ammo"][loot_spots.size() % 3]
			loot_spots.append([kind, 50, Vector3(lx, _loot_y_at(lx, lz), lz)])


# ---------------- hardened aircraft shelters ----------------

func _shelter(cx: float, cz: float) -> void:
	# Enterable arched shelter: 14 wide, 12 deep, arch apex ~10.4m.
	# Open front faces +z.
	var frame := _t3(Vector3(cx, 0, cz))
	var shel_col := Color(0.55, 0.56, 0.50)
	var conc: StandardMaterial3D = _mats["concrete"]
	# Interior floor slab.
	_box(Vector3(13.2, 0.06, 11.2), frame * _t3(Vector3(0, 0.03, 0)),
		_mats["concrete_dark"], Color(0.50, 0.49, 0.46), false)
	# Side walls.
	for sx in [-6.75, 6.75]:
		_box(Vector3(0.5, 3.4, 12), frame * _t3(Vector3(float(sx), 1.7, 0)),
			conc, _varc(shel_col, 0.08), true)
	# Back wall.
	_box(Vector3(14, 3.4, 0.5), frame * _t3(Vector3(0, 1.7, -5.75)),
		conc, _varc(shel_col, 0.08), true)
	# Louver vents on the back wall exterior, proud.
	for vx in [-4.0, 0.0, 4.0]:
		_box(Vector3(1.6, 0.5, 0.08), frame * _t3(Vector3(float(vx), 2.4, -6.04)),
			_mats["metal"], Color(0.35, 0.36, 0.38), false)
	# Arched roof: 7 angled segments following a semicircle (R=7).
	for i in range(7):
		var a := PI * float(i) / 6.0
		var seg_x := 7.0 * cos(a)
		var seg_y := 3.4 + 7.0 * sin(a)
		var xf := frame * Transform3D(Basis(Vector3(0, 0, 1), a + PI * 0.5),
			Vector3(seg_x, seg_y, 0))
		_box(Vector3(3.8, 0.45, 12.6), xf, conc, _varc(shel_col, 0.08), true)
	# Front lintel beam (walk under it).
	_box(Vector3(14.6, 0.9, 0.7), frame * _t3(Vector3(0, 3.0, 5.9)),
		conc, _varc(shel_col, 0.08), true)
	# Interior strip light under the arch apex.
	_box(Vector3(0.3, 0.06, 10.0), frame * _t3(Vector3(0, 9.8, 0)),
		_mats["lamp_head"], Color(1, 1, 1), false)
	# Wall-mounted light panels (on the side walls) + tool rack + spare parts.
	_light_panel(cx - 5.5, cz - 2.0, 3.2)
	_light_panel(cx + 5.5, cz - 2.0, 3.2)
	for tx2 in [-6.2, -5.4]:
		_box(Vector3(0.12, 1.8, 0.12), frame * _t3(Vector3(float(tx2), 0.9, 4.8)),
			_mats["wood"], Color(0.40, 0.30, 0.18), true)
	for by2 in [0.6, 1.3]:
		_box(Vector3(1.0, 0.08, 0.25), frame * _t3(Vector3(-5.8, float(by2), 4.8)),
			_mats["wood"], Color(0.40, 0.30, 0.18), false)
	_box(Vector3(1.1, 0.9, 1.1), frame * _t3(Vector3(5.8, 0.45, 4.6)),
		_mats["crate"], _varc(Color(0.52, 0.40, 0.24), 0.12), true)
	_box(Vector3(0.9, 0.9, 0.9), frame * _t3(Vector3(5.8, 1.35, 4.6)),
		_mats["crate"], _varc(Color(0.52, 0.40, 0.24), 0.12), true)
	# Tool benches along the west interior wall.
	for bz in [-3.0, 0.5]:
		var bf := frame * _t3(Vector3(-5.4, 0, float(bz)))
		_box(Vector3(1.0, 0.12, 2.6), bf * _t3(Vector3(0, 0.9, 0)),
			_mats["wood"], Color(0.45, 0.33, 0.20), true)
		for lx in [-0.4, 0.4]:
			for lz in [-1.1, 1.1]:
				_box(Vector3(0.1, 0.84, 0.1), bf * _t3(Vector3(float(lx), 0.45, float(lz))),
					_mats["wood"], Color(0.40, 0.30, 0.18), false)
	# Crate stacks along the east wall.
	var crate: StandardMaterial3D = _mats["crate"]
	var cpos := [[4.8, -3.5], [5.6, -1.8], [4.6, 0.2], [5.4, 2.2]]
	for cp in cpos:
		var h := 1.2 + float(int(_rng.randf_range(0, 2))) * 1.2
		_box(Vector3(1.2, h, 1.2), frame * _t3(Vector3(float(cp[0]), h * 0.5, float(cp[1]))),
			crate, _varc(Color(0.52, 0.40, 0.24), 0.12), true)
	# Parked drone silhouette in the middle: fuselage + wings + tail.
	var df := frame * _t3(Vector3(0, 0, -1.0))
	var dgrey := Color(0.35, 0.36, 0.38)
	_box(Vector3(0.9, 0.6, 2.6), df * _t3(Vector3(0, 1.3, 0)),
		_mats["bomber"], dgrey, true)
	_box(Vector3(3.4, 0.12, 0.7), df * _t3(Vector3(0, 1.45, 0.3)),
		_mats["bomber"], dgrey.darkened(0.08), false)
	_box(Vector3(1.2, 0.5, 0.12), df * _t3(Vector3(0, 1.8, -1.1)),
		_mats["bomber"], dgrey.darkened(0.08), false)
	# Fuel drums.
	var drum: StandardMaterial3D = _mats["drum"]
	var dcols := [Color(0.55, 0.15, 0.12), Color(0.15, 0.35, 0.55), Color(0.55, 0.45, 0.15)]
	for di in range(3):
		_cyl(0.35, 0.9, frame * _t3(Vector3(-4.6 + float(di) * 0.85, 0.45, 4.2)),
			drum, dcols[di], true)
	# Interior loot.
	for lp in [Vector3(cx - 3.0, 0.61, cz - 2.5), Vector3(cx + 3.0, 0.61, cz + 2.0),
			Vector3(cx - 5.0, 0.61, cz + 3.5), Vector3(cx + 1.5, 0.61, cz - 4.0)]:
		var kind: String = ["health", "armor", "ammo"][loot_spots.size() % 3]
		loot_spots.append([kind, 50, lp])
	house_positions.append(Vector3(cx, 0, cz))
	_claim(cx, cz, 20.0)


func _build_shelters() -> void:
	_shelter(-30.0, 25.0)
	_shelter(-5.0, 25.0)


# ---------------- command building ----------------

func _build_command() -> void:
	# Enterable command building: radar room. 16x12m, H=4.5, doors north+south.
	var cx := 30.0
	var cz := 22.0
	var W := 16.0
	var D := 12.0
	var H := 4.5
	var T := 0.4
	var wall_col := Color(0.82, 0.80, 0.74)
	_box(Vector3(W - 0.8, 0.06, D - 0.8), _t3(Vector3(cx, 0.03, cz)),
		_mats["concrete_dark"], Color(0.55, 0.54, 0.51), false)
	var north := Transform3D(Basis(), Vector3(cx, 0, cz - D * 0.5))
	_window_band(north, W, H, T, _mats["wall"], wall_col, [[2.0, 0.0, 1.6, 2.4]])
	var south := Transform3D(Basis(), Vector3(cx, 0, cz + D * 0.5))
	_window_band(south, W, H, T, _mats["wall"], wall_col,
		[[-4.0, 0.0, 1.8, 2.6], [4.0, 0.0, 1.8, 2.6]])
	var east := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx + W * 0.5, 0, cz))
	_window_band(east, D, H, T, _mats["wall"], wall_col, [])
	var west := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx - W * 0.5, 0, cz))
	_window_band(west, D, H, T, _mats["wall"], wall_col, [])
	# Radar room interior: big map table with glowing map.
	var table := _t3(Vector3(cx, 0, cz))
	_box(Vector3(3.2, 0.12, 2.2), table * _t3(Vector3(0, 0.85, 0)),
		_mats["wood"], Color(0.45, 0.33, 0.20), true)
	_box(Vector3(2.9, 0.04, 1.9), table * _t3(Vector3(0, 0.93, 0)),
		_mats["map_screen"], Color(1, 1, 1), false)
	for lx in [-1.4, 1.4]:
		for lz in [-0.9, 0.9]:
			_box(Vector3(0.12, 0.8, 0.12), table * _t3(Vector3(float(lx), 0.42, float(lz))),
				_mats["metal"], Color(0.4, 0.4, 0.42), false)
	# Consoles with emissive screens along the north interior wall.
	for k in range(4):
		var kx := cx - 5.4 + float(k) * 3.0
		var kf := Transform3D(Basis(Vector3.UP, PI), Vector3(kx, 0, cz - D * 0.5 + 1.0))
		_box(Vector3(1.6, 0.75, 0.6), kf * _t3(Vector3(0, 0.375, 0)),
			_mats["metal"], _varc(Color(0.5, 0.5, 0.52), 0.08), true)
		_box(Vector3(1.5, 0.7, 0.08),
			kf * Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(0, 1.05, 0.1)),
			_mats["screen"], Color(1, 1, 1), false)
		_box(Vector3(0.55, 0.1, 0.5), kf * _t3(Vector3(0, 0.5, 1.1)),
			_mats["concrete_dark"], Color(0.25, 0.25, 0.27), true)
		_box(Vector3(0.55, 0.6, 0.1), kf * _t3(Vector3(0, 0.85, 1.32)),
			_mats["concrete_dark"], Color(0.25, 0.25, 0.27), false)
	# Ceiling lamp panels (interior lighting).
	for lp2 in [Vector3(cx - 3.0, H - 0.2, cz - 2.0), Vector3(cx + 3.0, H - 0.2, cz + 2.0)]:
		_box(Vector3(1.8, 0.06, 1.0), _t3(lp2), _mats["lamp_head"], Color(1, 1, 1), false)
	# --- Upper floor: stairs from the ground floor along the east wall.
	var ctf := Transform3D(Basis(), Vector3(cx, 0, cz))
	_stair_flight(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx + 6.0, 0, cz + 4.0)),
		0, 6.5, 2.0, 4.5, 0.0)
	_slab_hole(ctf, W, D, H, 4.5, 7.5, -2.5, 2.2)
	var un := Transform3D(Basis(), Vector3(cx, H, cz - D * 0.5))
	_window_band(un, W, H, T, _mats["wall"], wall_col, [])
	var us := Transform3D(Basis(), Vector3(cx, H, cz + D * 0.5))
	_window_band(us, W, H, T, _mats["wall"], wall_col, [])
	var ue := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx + W * 0.5, H, cz))
	_window_band(ue, D, H, T, _mats["wall"], wall_col, [])
	var uw := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx - W * 0.5, H, cz))
	_window_band(uw, D, H, T, _mats["wall"], wall_col, [])
	# Upper floor: ops desks, radar consoles, light panels, loot.
	for dxi in [-4.0, 0.0, 4.0]:
		_box(Vector3(1.8, 0.08, 0.9), _t3(Vector3(cx + float(dxi), H + 0.79, cz + 2.0)),
			_mats["wood"], Color(0.45, 0.33, 0.20), true)
		_box(Vector3(1.6, 0.75, 0.7), _t3(Vector3(cx + float(dxi), H + 0.375, cz + 2.0)),
			_mats["wood"], Color(0.40, 0.30, 0.18), false)
	for ccx in [-6.0, -4.0]:
		var ckf := Transform3D(Basis(Vector3.UP, PI), Vector3(cx + float(ccx), H, cz + 4.0))
		_box(Vector3(1.6, 0.75, 0.6), ckf * _t3(Vector3(0, 0.375, 0)),
			_mats["metal"], _varc(Color(0.5, 0.5, 0.52), 0.08), true)
		_box(Vector3(1.5, 0.7, 0.08),
			ckf * Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(0, 1.05, 0.1)),
			_mats["screen"], Color(1, 1, 1), false)
	_light_panel(cx - 3.0, cz - 2.0, 2.0 * H - 0.4)
	_light_panel(cx + 3.0, cz + 2.0, 2.0 * H - 0.4)
	for ulp in [Vector3(cx - 5.0, H + 0.61, cz + 3.0), Vector3(cx + 5.0, H + 0.61, cz + 3.0),
			Vector3(cx - 5.0, H + 0.61, cz + 1.0), Vector3(cx + 5.0, H + 0.61, cz + 1.0)]:
		var ukind: String = ["health", "armor", "ammo"][loot_spots.size() % 3]
		loot_spots.append([ukind, 50, ulp])
	# --- Roof: walkable slab with stairwell hole + stairs from the upper floor.
	_slab_hole(ctf, W, D, 2.0 * H, -2.0, 3.0, -4.0, 2.2)
	_stair_flight(Transform3D(Basis(), Vector3(cx - 6.0, 0, cz - 4.0)), 0, 6.5, 2.0, 4.5, 4.5)
	# Roof slab + parapet (raised for the new upper floor).
	_box(Vector3(W + 1.0, 0.35, D + 1.0), _t3(Vector3(cx, 2.0 * H + 0.175, cz)),
		_mats["roof"], Color(0.35, 0.35, 0.37), false)
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(W + 1.0, 0.7, 0.25),
			_t3(Vector3(cx, 2.0 * H + 0.7, cz + ef * (D * 0.5 + 0.4))),
			_mats["wall"], wall_col, false)
		_box(Vector3(0.25, 0.7, D + 1.0),
			_t3(Vector3(cx + ef * (W * 0.5 + 0.4), 2.0 * H + 0.7, cz)),
			_mats["wall"], wall_col, false)
	# Radome + antenna mast on the new roof.
	_batch.add_rock(Vector3(3.2, 2.2, 3.2), _t3(Vector3(cx + 4.0, 2.0 * H + 1.4, cz - 2.0)),
		_mats["trim"], Color(0.92, 0.90, 0.86), false)
	_cyl(0.12, 4.0, _t3(Vector3(cx - 4.0, 2.0 * H + 2.0, cz + 2.0)),
		_mats["metal"], Color(0.5, 0.5, 0.52), false)
	_batch.add_rock(Vector3(0.3, 0.3, 0.3), _t3(Vector3(cx - 4.0, 2.0 * H + 4.1, cz + 2.0)),
		_beacon_mat, Color(1, 1, 1), false)
	# Rooftop AC units + rooftop loot (roof reachable via the upper stairs).
	_box(Vector3(1.6, 0.9, 1.2), _t3(Vector3(cx - 6.0, 2.0 * H + 0.45, cz + 3.0)),
		_mats["metal"], _varc(Color(0.6, 0.6, 0.62), 0.08), false)
	_box(Vector3(1.6, 0.9, 1.2), _t3(Vector3(cx + 6.0, 2.0 * H + 0.45, cz + 3.0)),
		_mats["metal"], _varc(Color(0.6, 0.6, 0.62), 0.08), false)
	loot_spots.append(["ammo", 60, Vector3(cx - 5.0, 2.0 * H + 0.55, cz - 3.0)])
	loot_spots.append(["armor", 50, Vector3(cx + 5.0, 2.0 * H + 0.55, cz + 1.0)])
	# "COMMAND" sign over the north door.
	_box(Vector3(3.0, 0.8, 0.12), _t3(Vector3(cx + 2.0, 3.0, cz - D * 0.5 - 0.25)),
		_mats["concrete_dark"], Color(0.42, 0.41, 0.39), false)
	_box(Vector3(2.6, 0.5, 0.03), _t3(Vector3(cx + 2.0, 3.0, cz - D * 0.5 - 0.32)),
		_mats["lamp_head"], Color(1, 1, 1), false)
	# Interior loot.
	for lp3 in [Vector3(cx - 6.0, 0.61, cz - 3.5), Vector3(cx + 6.0, 0.61, cz - 3.5),
			Vector3(cx - 6.0, 0.61, cz + 3.5), Vector3(cx + 2.5, 0.61, cz + 4.5),
			Vector3(cx - 2.0, 0.61, cz + 1.5), Vector3(cx + 2.0, 0.61, cz - 1.5),
			Vector3(cx, 0.61, cz + 4.2), Vector3(cx - 4.5, 0.61, cz)]:
		var kind: String = ["health", "armor", "ammo"][loot_spots.size() % 3]
		loot_spots.append([kind, 50, lp3])
	house_positions.append(Vector3(cx, 0, cz))
	_claim(cx, cz, 18.0)


# ---------------- control tower ----------------

func _build_tower() -> void:
	var tx := 52.0
	var tz := -2.0
	var cab_y := 16.0
	var wall_col := Color(0.80, 0.78, 0.72)
	# Solid concrete shaft, 4x4, 16m tall.
	_box(Vector3(4, cab_y, 4), _t3(Vector3(tx, cab_y * 0.5, tz)),
		_mats["concrete"], Color(0.62, 0.61, 0.58), true)
	# Vertical trim stripes, proud of the shaft faces.
	for e in [-1.0, 1.0]:
		var ef: float = e
		_box(Vector3(0.12, cab_y - 1.0, 4.06), _t3(Vector3(tx + ef * 2.0, cab_y * 0.5, tz)),
			_mats["trim"], Color(0.92, 0.90, 0.86), false)
	# Switchback stairs: 4 flights x 4m rise, two lanes (x 50.8 / 53.2).
	var flights := [
		[50.8, PI * 0.5, 5.0, 8.0, 0.0],
		[53.2, -PI * 0.5, -13.0, 8.0, 4.0],
		[50.8, PI * 0.5, 5.0, 8.0, 8.0],
		[53.2, -PI * 0.5, -13.0, 8.0, 12.0],
	]
	for f in flights:
		var lane: float = f[0]
		var fr := Transform3D(Basis(Vector3.UP, float(f[1])), Vector3(lane, 0, 0))
		_stair_flight(fr, float(f[2]), float(f[3]), 2.4, 4.0, float(f[4]))
		# Handrail struts along both sides of the flight.
		for sz in [-1.13, 1.13]:
			_strut(fr * Vector3(float(f[2]) + 0.5, float(f[4]) + 1.0, float(sz)),
				fr * Vector3(float(f[2]) + float(f[3]) - 0.5, float(f[4]) + 5.0, float(sz)),
				0.07, 0.07, _mats["metal"])
	# Landings at each switchback (wide slabs joining the two lanes).
	_landing(52.0, 4.0, -14.1, 5.0, 2.4)
	_landing(52.0, 8.0, -4.4, 5.0, 2.4)
	_landing(52.0, 12.0, -14.1, 5.0, 2.4)
	_landing(52.0, 16.0, -4.4, 5.0, 2.4)
	# Stair base pad.
	_box(Vector3(3.2, 0.08, 3.2), _t3(Vector3(50.8, 0.04, -4.0)),
		_mats["concrete"], Color(0.60, 0.59, 0.56), false)
	# --- Glass cab: floor, 4 window walls, consoles, roof, beacon.
	_box(Vector3(6, 0.3, 6), _t3(Vector3(tx, cab_y - 0.15, tz)),
		_mats["concrete_dark"], Color(0.40, 0.39, 0.37), true)
	var cab_walls := [
		[Transform3D(Basis(), Vector3(tx, cab_y, tz - 3.0)), [[1.2, 0.0, 1.4, 2.2], [-2.0, 0.8, 1.2, 1.4], [2.0, 0.8, 1.2, 1.4]]],
		[Transform3D(Basis(), Vector3(tx, cab_y, tz + 3.0)), [[-2.0, 0.8, 1.2, 1.4], [2.0, 0.8, 1.2, 1.4]]],
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
				_mats["concrete_dark"], Color(0.42, 0.41, 0.39), true)
	# Consoles with glowing screens facing the runway.
	for ca in [0.6, 2.5, 4.4]:
		var kx := tx + cos(float(ca)) * 1.7
		var kz := tz + sin(float(ca)) * 1.7
		var kyaw := -float(ca) + PI * 0.5
		var kf := Transform3D(Basis(Vector3.UP, kyaw), Vector3(kx, cab_y, kz))
		_box(Vector3(1.6, 0.75, 0.6), kf * _t3(Vector3(0, 0.375, 0)),
			_mats["metal"], _varc(Color(0.5, 0.5, 0.52), 0.08), true)
		_box(Vector3(1.5, 0.7, 0.08),
			kf * Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(0, 1.0, 0.1)),
			_mats["screen"], Color(1, 1, 1), false)
	# Roof + beacon mast.
	_box(Vector3(6.6, 0.3, 6.6), _t3(Vector3(tx, cab_y + 3.15, tz)),
		_mats["roof"], Color(0.35, 0.35, 0.37), false)
	# Cab ceiling light (emissive).
	_light_panel(tx, tz, cab_y + 2.6)
	_cyl(0.08, 1.2, _t3(Vector3(tx, cab_y + 3.9, tz)), _mats["metal"], Color(1, 1, 1), false)
	_batch.add_rock(Vector3(0.35, 0.35, 0.35), _t3(Vector3(tx, cab_y + 4.6, tz)),
		_beacon_mat, Color(1, 1, 1), false)
	# Hot-zone loot inside the cab.
	for lp in [Vector3(tx - 1.6, cab_y + 0.55, tz - 1.2), Vector3(tx + 1.6, cab_y + 0.55, tz + 0.8),
			Vector3(tx, cab_y + 0.55, tz - 2.2), Vector3(tx - 2.2, cab_y + 0.55, tz + 1.8)]:
		loot_spots.append(["armor", 50, lp])
		loot_spots.append(["ammo", 60, Vector3(lp.x + 0.6, lp.y, lp.z + 0.4)])
	house_positions.append(Vector3(tx, 0, tz))
	_claim(tx, tz, 16.0)


# ---------------- fuel depot ----------------

func _build_fuel_depot() -> void:
	# 4 large fuel tanks inside a berm rectangle: x 9..39, z 38..54.
	var tank: StandardMaterial3D = _mats["metal"]
	var berm: StandardMaterial3D = _mats["concrete"]
	var tank_col := Color(0.68, 0.62, 0.50)
	_box(Vector3(30, 1.3, 0.7), _t3(Vector3(24, 0.65, 38)), berm, Color(0.55, 0.54, 0.51), true)
	_box(Vector3(30, 1.3, 0.7), _t3(Vector3(24, 0.65, 54)), berm, Color(0.55, 0.54, 0.51), true)
	_box(Vector3(0.7, 1.3, 16.7), _t3(Vector3(9, 0.65, 46)), berm, Color(0.55, 0.54, 0.51), true)
	_box(Vector3(0.7, 1.3, 16.7), _t3(Vector3(39, 0.65, 46)), berm, Color(0.55, 0.54, 0.51), true)
	# Warning signs on the berm: yellow plates + red stripe, proud of the face.
	for sx in [16.0, 24.0, 32.0]:
		_box(Vector3(1.2, 0.8, 0.06), _t3(Vector3(float(sx), 0.85, 37.62)),
			_mats["sign"], Color(1, 1, 1), false)
		_box(Vector3(1.2, 0.15, 0.07), _t3(Vector3(float(sx), 0.35, 37.62)),
			_mats["paint_white"], Color(0.85, 0.15, 0.12), false)
	# Tanks: cylinders with domed caps, stencil band.
	var tanks := [Vector3(16, 0, 44), Vector3(24, 0, 44), Vector3(32, 0, 44), Vector3(24, 0, 50)]
	for tp in tanks:
		_cyl(2.2, 5.0, _t3(Vector3(tp.x, 2.5, tp.z)), tank, _varc(tank_col, 0.08), true)
		_batch.add_rock(Vector3(4.4, 1.0, 4.4), _t3(Vector3(tp.x, 5.2, tp.z)),
			tank, _varc(tank_col, 0.08).darkened(0.1), false)
		_box(Vector3(4.45, 0.5, 4.45), _t3(Vector3(tp.x, 3.6, tp.z)),
			_mats["paint_white"], Color(0.75, 0.2, 0.15), false)
	# Connecting pipes at tank bases + valve boxes.
	var idf := Transform3D(Basis(), Vector3.ZERO)
	_cyl_axis(0.18, 20.4, Vector3.RIGHT, Vector3(24, 0.6, 44), idf,
		_mats["metal"], Color(0.45, 0.44, 0.42), true)
	_cyl_axis(0.18, 6.0, Vector3.BACK, Vector3(24, 0.6, 47), idf,
		_mats["metal"], Color(0.45, 0.44, 0.42), true)
	for vx in [20.0, 28.0]:
		_box(Vector3(0.6, 0.9, 0.6), _t3(Vector3(float(vx), 0.45, 44)),
			_mats["metal"], Color(0.40, 0.38, 0.36), true)
	# Spare drums + pallet by the depot gate.
	var drum: StandardMaterial3D = _mats["drum"]
	for ddi in range(3):
		_cyl(0.35, 0.9, _t3(Vector3(12.0 + float(ddi) * 0.85, 0.45, 50.0)),
			drum, [Color(0.55, 0.15, 0.12), Color(0.15, 0.35, 0.55), Color(0.55, 0.45, 0.15)][ddi], true)
	_claim(24, 46, 20.0)


# ---------------- vehicles ----------------

func _truck(frame: Transform3D) -> void:
	# Military cargo truck: cab + canvas-covered bed, 6 wheels.
	var metal: StandardMaterial3D = _mats["metal"]
	var tire: StandardMaterial3D = _mats["tire"]
	var olive := Color(0.32, 0.36, 0.24)
	_box(Vector3(2.4, 0.5, 6.4), frame * _t3(Vector3(0, 0.85, 0)),
		metal, _varc(olive, 0.08), false)
	_box(Vector3(2.4, 1.5, 1.7), frame * _t3(Vector3(0, 1.9, 2.3)),
		metal, _varc(olive, 0.08), true)
	_box(Vector3(1.9, 0.6, 0.08), frame * _t3(Vector3(0, 2.0, 3.16)),
		_mats["glass"], Color(0.10, 0.13, 0.16), false)
	_box(Vector3(2.4, 1.1, 4.2), frame * _t3(Vector3(0, 1.7, -0.9)),
		metal, _varc(olive, 0.08), true)
	_box(Vector3(2.5, 0.25, 4.3), frame * _t3(Vector3(0, 2.38, -0.9)),
		_mats["sandbag"], Color(0.55, 0.52, 0.44), false)
	for wx in [-1.15, 1.15]:
		for wz in [2.2, -0.6, -2.2]:
			_cyl_axis(0.5, 0.35, Vector3.BACK, Vector3(float(wx), 0.5, float(wz)),
				frame, tire, Color(0.13, 0.13, 0.14), false)
	_box(Vector3(2.5, 2.4, 6.5), frame * _t3(Vector3(0, 1.2, 0)),
		metal, Color(1, 1, 1), true)


func _jeep(frame: Transform3D) -> void:
	var metal: StandardMaterial3D = _mats["metal"]
	var olive := Color(0.34, 0.38, 0.25)
	_box(Vector3(1.8, 0.7, 3.4), frame * _t3(Vector3(0, 0.8, 0)),
		metal, _varc(olive, 0.08), true)
	_box(Vector3(1.8, 0.55, 1.0), frame * _t3(Vector3(0, 1.35, 0.9)),
		metal, _varc(olive, 0.08), false)
	_box(Vector3(1.6, 0.5, 0.06), frame * _t3(Vector3(0, 1.35, 1.42)),
		_mats["glass"], Color(0.10, 0.13, 0.16), false)
	_box(Vector3(1.7, 0.15, 1.6), frame * _t3(Vector3(0, 1.5, -0.7)),
		_mats["sandbag"], Color(0.50, 0.47, 0.40), false)
	for wx in [-0.95, 0.95]:
		for wz in [1.15, -1.15]:
			_cyl_axis(0.42, 0.3, Vector3.BACK, Vector3(float(wx), 0.42, float(wz)),
				frame, _mats["tire"], Color(0.13, 0.13, 0.14), false)


func _build_vehicles() -> void:
	_truck(Transform3D(Basis(Vector3.UP, 0.3), Vector3(8, 0, -18)))
	_claim(8, -18, 8.0)
	_truck(Transform3D(Basis(Vector3.UP, -0.25), Vector3(-52, 0, -20)))
	_claim(-52, -20, 8.0)
	_jeep(Transform3D(Basis(Vector3.UP, 1.2), Vector3(44, 0, -24)))
	_claim(44, -24, 6.0)
	_jeep(Transform3D(Basis(Vector3.UP, -0.8), Vector3(-20, 0, 40)))
	_claim(-20, 40, 6.0)


# ---------------- tarmac cover ----------------

func _sandbag_wall(cx: float, cz: float, yaw: float, two_high := false) -> void:
	var fr := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0, cz))
	var sb: StandardMaterial3D = _mats["sandbag"]
	_box(Vector3(3.2, 1.0, 0.8), fr * _t3(Vector3(0, 0.5, 0)),
		sb, _varc(Color(0.62, 0.56, 0.44), 0.10), true)
	if two_high:
		_box(Vector3(3.0, 0.5, 0.7), fr * _t3(Vector3(0, 1.25, 0)),
			sb, _varc(Color(0.62, 0.56, 0.44), 0.10), true)
	_claim(cx, cz, 3.5)


func _blast_barrier(cx: float, cz: float, yaw := 0.0) -> void:
	_box(Vector3(2.2, 1.2, 0.7), Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0.6, cz)),
		_mats["concrete"], _varc(Color(0.62, 0.61, 0.58), 0.08), true)
	_claim(cx, cz, 3.0)


func _crate_cluster(cx: float, cz: float) -> void:
	var crate: StandardMaterial3D = _mats["crate"]
	for k in range(4):
		var ox := _rng.randf_range(-1.6, 1.6)
		var oz := _rng.randf_range(-1.6, 1.6)
		var h := 1.2
		if k > 1:
			h = 2.4  # stacked
		_box(Vector3(1.2, h, 1.2), _t3(Vector3(cx + ox, h * 0.5, cz + oz)),
			crate, _varc(Color(0.52, 0.40, 0.24), 0.12), true)
	_claim(cx, cz, 4.0)


func _build_cover() -> void:
	# Sandbag lines along the apron edge.
	var x := -48.0
	while x <= 48.0:
		_sandbag_wall(x + _rng.randf_range(-1.0, 1.0), -14.0 + _rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-0.2, 0.2), _rng.randf() < 0.4)
		x += 12.0
	# Blast barriers guarding the runway ends and depot corners.
	_blast_barrier(-56, -48, 0.2)
	_blast_barrier(56, -48, -0.15)
	_blast_barrier(6, 36, 0.1)
	_blast_barrier(42, 36, -0.1)
	_blast_barrier(-16, 10, 0.35)
	_blast_barrier(18, 8, -0.3)
	# Crate clusters near shelters and command.
	_crate_cluster(-22, 34)
	_crate_cluster(12, 30)
	_crate_cluster(38, 30)
	_crate_cluster(44, -32)


# ---------------- perimeter fence + guard booths ----------------

func _guard_booth(bx: float, bz: float) -> void:
	# Small enterable booth: 2.6x2.6, H=2.7, door faces the base (-z side).
	var W := 2.6
	var H := 2.7
	var T := 0.25
	var col := Color(0.78, 0.76, 0.70)
	var north := Transform3D(Basis(), Vector3(bx, 0, bz - W * 0.5))  # faces base
	_window_band(north, W, H, T, _mats["wall"], col, [[0.0, 0.0, 1.0, 2.2]])
	var south := Transform3D(Basis(), Vector3(bx, 0, bz + W * 0.5))
	_window_band(south, W, H, T, _mats["wall"], col, [])
	var east := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(bx + W * 0.5, 0, bz))
	_window_band(east, W, H, T, _mats["wall"], col, [])
	var west := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(bx - W * 0.5, 0, bz))
	_window_band(west, W, H, T, _mats["wall"], col, [])
	_box(Vector3(W + 0.6, 0.25, W + 0.6), _t3(Vector3(bx, H + 0.125, bz)),
		_mats["roof"], Color(0.35, 0.35, 0.37), false)
	# Desk + loot inside.
	_box(Vector3(1.4, 0.75, 0.5), _t3(Vector3(bx, 0.375, bz + 0.6)),
		_mats["wood"], Color(0.45, 0.33, 0.20), true)
	# Booth ceiling light (emissive).
	_light_panel(bx, bz, 2.5)
	for k in range(2):
		var kind: String = ["health", "armor", "ammo"][loot_spots.size() % 3]
		loot_spots.append([kind, 50, Vector3(bx - 0.5 + float(k), 0.55, bz - 0.4)])
	house_positions.append(Vector3(bx, 0, bz))
	_claim(bx, bz, 6.0)


func _build_fence_booths() -> void:
	# Perimeter fence at +/-66: posts + panels (visual), invisible edge walls
	# for collision, gate gap on the south side at x -4.5..4.5.
	var post_mat: StandardMaterial3D = _mats["metal"]
	var panel_mat: StandardMaterial3D = _mats["concrete_dark"]
	var e := 66.0
	var x := -66.0
	while x <= 66.0:
		for z in [-e, e]:
			_box(Vector3(0.15, 2.4, 0.15), _t3(Vector3(x, 1.2, float(z))), post_mat,
				_varc(Color(0.6, 0.6, 0.62), 0.08), false)
		x += 6.0
	var z2 := -66.0
	while z2 <= 66.0:
		for xx in [-e, e]:
			_box(Vector3(0.15, 2.4, 0.15), _t3(Vector3(float(xx), 1.2, z2)), post_mat,
				_varc(Color(0.6, 0.6, 0.62), 0.08), false)
		z2 += 6.0
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
	# Gate frames + open gate doors.
	for gx in [-3.2, 3.2]:
		_box(Vector3(0.3, 3.0, 0.3), _t3(Vector3(float(gx), 1.5, e)), post_mat, Color(1, 1, 1), true)
	for gx2 in [-5.6, 5.6]:
		_box(Vector3(2.6, 1.8, 0.08),
			Transform3D(Basis(Vector3.UP, 0.9 * sign(float(gx2))), Vector3(float(gx2), 1.3, e + 1.4)),
			panel_mat, Color(0.40, 0.42, 0.45), false)
	# Edge-wall colliders (south split for the gate).
	_box(Vector3(140, 3, 0.5), _t3(Vector3(0, 1.5, -e)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(61.5, 3, 0.5), _t3(Vector3(-35.25, 1.5, e)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(61.5, 3, 0.5), _t3(Vector3(35.25, 1.5, e)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(0.5, 3, 140), _t3(Vector3(e, 1.5, 0)), panel_mat, Color(1, 1, 1), true)
	_box(Vector3(0.5, 3, 140), _t3(Vector3(-e, 1.5, 0)), panel_mat, Color(1, 1, 1), true)
	# Two guard booths flanking the main gate (enterable).
	_guard_booth(-7.5, 63.5)
	_guard_booth(7.5, 63.5)


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


func _scatter_loot() -> void:
	var kinds := ["health", "armor", "ammo"]
	var idx := loot_spots.size()
	# Denser loot rings at each POI (skipping bomber footprints and claims).
	for p in poi_list:
		var pp: Vector3 = p["pos"]
		for k in range(8):
			var a := TAU * float(k) / 8.0 + _rng.randf_range(-0.2, 0.2)
			var r := _rng.randf_range(3.0, 9.0)
			var lx := pp.x + cos(a) * r
			var lz := pp.z + sin(a) * r
			if absf(lx) > 64.0 or absf(lz) > 64.0:
				continue
			if _in_bomber(lx, lz):
				continue
			var kind: String = kinds[idx % 3]
			loot_spots.append([kind, 50, Vector3(lx, _loot_y_at(lx, lz), lz)])
			idx += 1
	# General scatter, kept clear of structures and aircraft.
	var tries := 0
	while loot_spots.size() < 86 and tries < 600:
		tries += 1
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-62, 62)
		if _in_bomber(x, z):
			continue
		if not _claim(x, z, 4.0):
			continue
		var kind2: String = kinds[idx % 3]
		loot_spots.append([kind2, 50, Vector3(x, _loot_y_at(x, z), z)])
		idx += 1


func _finalize() -> void:
	var aabb := AABB(Vector3(-85, -10, -85), Vector3(170, 60, 170))
	var draws: int = _batch.build_visuals(self, aabb)
	_batch.build_colliders(self)
	enemy_spawns = [
		Vector3(-22, 0.6, 18),
		Vector3(30, 0.6, 12),
		Vector3(52, 0.6, 6),
		Vector3(2, 0.6, -40),
		Vector3(6, 0.6, 46),
		Vector3(-10, 0.6, 54),
	]
	print("Airbase built: instances=", _batch.box_count(), " draws=", draws,
		" colliders=", _batch.collider_count(), " loot=", loot_spots.size(),
		" pois=", poi_list.size())


func _process(delta: float) -> void:
	_time += delta
	for cl in _clouds:
		var cn: MeshInstance3D = cl["node"]
		cn.position.x += float(cl["speed"]) * delta
		if cn.position.x > 110.0:
			cn.position.x = -110.0
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 2.0 + 2.0 * (0.5 + 0.5 * sin(_time * 4.0))
