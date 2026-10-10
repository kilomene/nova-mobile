extends Node3D
class_name WorldMap
## NOVA WORLD — merged battle royale world.
## Instances every region scene on a 4x4 grid (pitch 180m) and stitches
## them together with avenues, a canal with bridges, shoreline water,
## and wilderness filler. Same public interface as single maps, so
## main.gd treats the world like any other map.

const GeoBatchT := preload("res://scripts/geo_batch.gd")

const MAP_EXTENT := 345.0
const SEED := 20261014
const PITCH := 180.0
const CELL := 20.0
const WORLD_R := 460.0  # tissue build radius (includes water margins)
const WATER_Y := -0.55

var player_spawn := Vector3(0, 0.6, 0)
var enemy_spawns: Array[Vector3] = []
var loot_spots: Array = []  # [kind, amount, Vector3, tier]
var poi_list: Array = []  # {"name", "pos"}
var house_positions: Array[Vector3] = []
var map_extent := MAP_EXTENT
var map_labels: Array = []  # {"name", "pos"} region names for the world minimap

var _rng := RandomNumberGenerator.new()
var _regions: Array = []  # {"name","node","ox","oz","shore"}
var _batch
var _mats := {}

const REGIONS := [
	{"name": "AIRBASE", "scene": "res://scenes/airbase.tscn", "ox": -270.0, "oz": -270.0},
	{"name": "AIRPORT", "scene": "res://scenes/airport.tscn", "ox": -90.0, "oz": -270.0},
	{"name": "BARRACKS", "scene": "res://scenes/barracks.tscn", "ox": 90.0, "oz": -270.0},
	{"name": "TRAIN STATION", "scene": "res://scenes/trainstation.tscn", "ox": 270.0, "oz": -270.0},
	{"name": "VALLEY", "scene": "res://scenes/valleycombat.tscn", "ox": -270.0, "oz": -90.0},
	{"name": "LEKKI", "scene": "res://scenes/lekki.tscn", "ox": -90.0, "oz": -90.0},
	{"name": "COMPUTER VILLAGE", "scene": "res://scenes/computervillage.tscn", "ox": 90.0, "oz": -90.0},
	{"name": "DOWNTOWN", "scene": "res://scenes/downtown.tscn", "ox": 270.0, "oz": -90.0},
	{"name": "MAKOKO", "scene": "res://scenes/makoko.tscn", "ox": -270.0, "oz": 90.0, "shore": true},
	{"name": "BANANA ISLAND", "scene": "res://scenes/bananaisland.tscn", "ox": -90.0, "oz": 90.0, "shore": true},
	{"name": "SHIP PORT", "scene": "res://scenes/shipport.tscn", "ox": 90.0, "oz": 90.0, "shore": true},
	{"name": "LAGOON BRIDGE", "scene": "res://scenes/lagoonbridge.tscn", "ox": 270.0, "oz": 90.0, "shore": true},
	{"name": "DAM", "scene": "res://scenes/dam.tscn", "ox": -270.0, "oz": 270.0},
	{"name": "STADIUM", "scene": "res://scenes/stadium.tscn", "ox": -90.0, "oz": 270.0},
]

const WORLD_POIS := [
	{"name": "Grand Canal", "pos": Vector3(30, 0, 150)},
	{"name": "Central Crossroads", "pos": Vector3(0, 0, 0)},
	{"name": "Lakeside Park", "pos": Vector3(150, 0, 270)},
	{"name": "North Gate", "pos": Vector3(0, 0, -330)},
	{"name": "Harbor View", "pos": Vector3(330, 0, 90)},
	{"name": "South Lagoon", "pos": Vector3(-90, 0, 330)},
]

const AVE_NS := [-180.0, 0.0, 180.0]  # north-south avenues (x positions)
const AVE_EW := [-180.0, 0.0]         # east-west avenues (z positions)
const CANAL_N := 168.0
const CANAL_S := 192.0


func _ready() -> void:
	_rng.seed = SEED
	_batch = GeoBatchT.new()
	_make_mats()
	_instance_regions()
	_build_ground_water()
	_build_roads()
	_build_bridges()
	_build_wilderness()
	_build_perimeter()
	_build_world_pois()
	_aggregate()
	_finalize()


func _make_mats() -> void:
	_mats["ground"] = _std(Color(0.3, 0.42, 0.2), 1.0)
	_mats["asphalt"] = _std(Color(0.16, 0.16, 0.18), 0.95)
	_mats["dash"] = _std(Color(0.9, 0.85, 0.6), 0.8)
	_mats["deck"] = _std(Color(0.45, 0.45, 0.47), 0.9)
	_mats["railing"] = _std(Color(0.6, 0.62, 0.65), 0.5)
	_mats["trunk"] = _std(Color(0.35, 0.22, 0.12), 1.0)
	_mats["leaf"] = _std(Color(0.25, 0.5, 0.2), 1.0)
	_mats["rockm"] = _std(Color(0.5, 0.48, 0.45), 1.0)
	_mats["bushm"] = _std(Color(0.2, 0.42, 0.18), 1.0)
	var wsm := ShaderMaterial.new()
	wsm.shader = load("res://shaders/water.gdshader") as Shader
	_mats["water"] = wsm


func _std(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


func _instance_regions() -> void:
	for r in REGIONS:
		var spath: String = r["scene"]
		if not ResourceLoader.exists(spath):
			push_warning("WORLD: region scene missing, skipped: " + spath)
			continue
		var ps: PackedScene = load(spath) as PackedScene
		var node: Node3D = ps.instantiate() as Node3D
		var ox: float = r["ox"]
		var oz: float = r["oz"]
		node.position = Vector3(ox, 0.0, oz)
		add_child(node)
		_regions.append({
			"name": str(r["name"]), "node": node,
			"ox": ox, "oz": oz,
			"shore": bool(r.get("shore", false)),
		})


func _in_region_rect(x: float, z: float, margin: float) -> bool:
	for rg in _regions:
		if absf(x - float(rg["ox"])) <= 70.0 + margin and absf(z - float(rg["oz"])) <= 70.0 + margin:
			return true
	return false


func _near_shore(x: float, z: float) -> bool:
	for rg in _regions:
		if bool(rg["shore"]):
			var dx := absf(x - float(rg["ox"]))
			var dz := absf(z - float(rg["oz"]))
			if dx <= 92.0 and dz <= 92.0 and not (dx <= 70.0 and dz <= 70.0):
				return true
	return false


func _is_water(x: float, z: float) -> bool:
	if z > 345.0:
		return true  # south lagoon
	if x > 345.0:
		return true  # east harbor
	if z > CANAL_N and z < CANAL_S and x > -340.0 and x < 340.0:
		return true  # grand canal
	var dx := (x - 90.0) / 55.0
	var dz := (z - 270.0) / 40.0
	if dx * dx + dz * dz < 1.0:
		return true  # wilderness lake
	return false


func _on_road(x: float, z: float) -> bool:
	for ax in AVE_NS:
		if absf(x - float(ax)) < 6.0 and absf(z) < 345.0:
			return true
	for az in AVE_EW:
		if absf(z - float(az)) < 6.0 and absf(x) < 345.0:
			return true
	return false


func _build_ground_water() -> void:
	var n := int(WORLD_R * 2.0 / CELL)
	for i in range(n):
		for j in range(n):
			var cx := -WORLD_R + CELL * 0.5 + float(i) * CELL
			var cz := -WORLD_R + CELL * 0.5 + float(j) * CELL
			if _in_region_rect(cx, cz, 0.0):
				continue
			var wet := _is_water(cx, cz) or _near_shore(cx, cz)
			if wet:
				var wxf := Transform3D(Basis(), Vector3(cx, WATER_Y - 0.1, cz))
				_batch.add_box(Vector3(CELL, 0.2, CELL), wxf, _mats["water"], Color(1, 1, 1))
			else:
				var g := 0.85 + _rng.randf() * 0.3
				var gy := Transform3D(Basis(), Vector3(cx, -0.5, cz))
				_batch.add_box(Vector3(CELL, 1.0, CELL), gy, _mats["ground"], Color(0.3 * g, 0.44 * g, 0.2 * g))


func _road_seg(center: Vector3, size: Vector3) -> void:
	_batch.add_box(size, Transform3D(Basis(), center + Vector3(0, 0.06, 0)), _mats["asphalt"], Color(1, 1, 1))


func _build_roads() -> void:
	# North-south avenues (with a gap at the canal — bridges go there).
	for ax_v in AVE_NS:
		var ax: float = ax_v
		var z := -340.0
		while z < 340.0:
			if z < CANAL_N - 20.0 or z >= CANAL_S + 20.0:
				_road_seg(Vector3(ax, 0, z + CELL * 0.5), Vector3(8, 0.12, CELL))
			z += CELL
		var dz := -336.0
		while dz < 336.0:
			if dz < CANAL_N - 20.0 or dz >= CANAL_S + 20.0:
				_batch.add_box(Vector3(0.35, 0.03, 2.5),
					Transform3D(Basis(), Vector3(ax, 0.14, dz)), _mats["dash"], Color(1, 1, 1))
			dz += 6.0
	# East-west avenues.
	for az_v in AVE_EW:
		var az: float = az_v
		var x := -340.0
		while x < 340.0:
			_road_seg(Vector3(x + CELL * 0.5, 0, az), Vector3(CELL, 0.12, 8))
			x += CELL
		var dx := -336.0
		while dx < 336.0:
			_batch.add_box(Vector3(2.5, 0.03, 0.35),
				Transform3D(Basis(), Vector3(dx, 0.14, az)), _mats["dash"], Color(1, 1, 1))
			dx += 6.0


func _ramp(ax: float, z0: float, z1: float, flip: bool) -> void:
	# Sloped approach ramp from road (y~0.1) to bridge deck (y~1.2).
	# flip=false: rises toward +z (south approach). flip=true: rises toward -z.
	var length := z1 - z0
	var rise := 1.1
	var slope_len := sqrt(length * length + rise * rise)
	var ang := atan2(rise, length)
	var mid := Vector3(ax, 0.1 + rise * 0.5, (z0 + z1) * 0.5)
	var basis := Basis.from_euler(Vector3(ang if flip else -ang, 0.0, 0.0))
	var xf := Transform3D(basis, mid)
	_batch.add_box(Vector3(10, 0.4, slope_len + 1.0), xf, _mats["deck"], Color(1, 1, 1))
	_batch.add_collider(Vector3(10, 0.4, slope_len + 1.0), xf)


func _build_bridges() -> void:
	var zc := (CANAL_N + CANAL_S) * 0.5
	var span := 52.0
	for ax_v in AVE_NS:
		var ax: float = ax_v
		# Deck over the canal.
		var deck_xf := Transform3D(Basis(), Vector3(ax, 0.8, zc))
		_batch.add_box(Vector3(10, 0.8, span), deck_xf, _mats["deck"], Color(1, 1, 1))
		_batch.add_collider(Vector3(10, 0.8, span), deck_xf)
		for side in [-1.0, 1.0]:
			var rx: float = ax + side * 4.8
			_batch.add_box(Vector3(0.4, 1.1, span),
				Transform3D(Basis(), Vector3(rx, 1.75, zc)), _mats["railing"], Color(1, 1, 1))
			_batch.add_collider(Vector3(0.4, 1.1, span),
				Transform3D(Basis(), Vector3(rx, 1.75, zc)))
		for pz in [zc - span * 0.25, zc + span * 0.25]:
			_batch.add_cyl(0.6, 4.0,
				Transform3D(Basis(), Vector3(ax - 3.5, -1.5, pz)), _mats["deck"], Color(0.8, 0.8, 0.8))
			_batch.add_cyl(0.6, 4.0,
				Transform3D(Basis(), Vector3(ax + 3.5, -1.5, pz)), _mats["deck"], Color(0.8, 0.8, 0.8))
		# Approach ramps (south rises toward +z, north rises toward -z).
		_ramp(ax, zc - span * 0.5 - 14.0, zc - span * 0.5, false)
		_ramp(ax, zc + span * 0.5, zc + span * 0.5 + 14.0, true)


func _build_wilderness() -> void:
	var c := 12.0
	var count := int(680.0 / c)
	for i in range(count):
		for j in range(count):
			var cx := -340.0 + c * 0.5 + float(i) * c
			var cz := -340.0 + c * 0.5 + float(j) * c
			if _in_region_rect(cx, cz, 4.0):
				continue
			if _on_road(cx, cz):
				continue
			if _is_water(cx, cz) or _near_shore(cx, cz):
				continue
			var r := _rng.randf()
			if r < 0.10:
				_tree(cx, cz)
			elif r < 0.16:
				var s := 1.5 + _rng.randf() * 1.5
				_batch.add_rock(Vector3(s, s * 0.7, s),
					Transform3D(Basis(), Vector3(cx, s * 0.3, cz)),
					_mats["rockm"], Color(0.9, 0.88, 0.85), true)
			elif r < 0.24:
				_batch.add_rock(Vector3(1.2, 0.9, 1.2),
					Transform3D(Basis(), Vector3(cx, 0.4, cz)),
					_mats["bushm"], Color(0.9, 1.0, 0.9), false)


func _tree(cx: float, cz: float) -> void:
	var h := 2.4 + _rng.randf() * 1.2
	_batch.add_cyl(0.22, h, Transform3D(Basis(), Vector3(cx, h * 0.5, cz)), _mats["trunk"], Color(1, 1, 1))
	_batch.add_collider(Vector3(0.5, h, 0.5), Transform3D(Basis(), Vector3(cx, h * 0.5, cz)))
	var cs := 2.2 + _rng.randf() * 1.0
	_batch.add_rock(Vector3(cs, cs * 0.8, cs),
		Transform3D(Basis(), Vector3(cx, h + cs * 0.3, cz)),
		_mats["leaf"], Color(0.85 + _rng.randf() * 0.3, 1.0, 0.85), false)


func _build_perimeter() -> void:
	# Invisible walls at the playable edge (inner face at 347 = clamp limit).
	_batch.add_collider(Vector3(700, 30, 2), Transform3D(Basis(), Vector3(0, 15, 348)))
	_batch.add_collider(Vector3(700, 30, 2), Transform3D(Basis(), Vector3(0, 15, -348)))
	_batch.add_collider(Vector3(2, 30, 700), Transform3D(Basis(), Vector3(348, 15, 0)))
	_batch.add_collider(Vector3(2, 30, 700), Transform3D(Basis(), Vector3(-348, 15, 0)))


func _build_world_pois() -> void:
	var kinds := ["health", "armor", "ammo"]
	var amounts := [40, 50, 60]
	for poi in WORLD_POIS:
		var pname: String = poi["name"]
		var ppos: Vector3 = poi["pos"]
		poi_list.append({"name": pname, "pos": ppos})
		map_labels.append({"name": pname, "pos": ppos})
		for k in range(8):
			var ang := TAU * float(k) / 8.0
			var rad := 6.0 + float(k % 3) * 3.0
			var lp := ppos + Vector3(cos(ang) * rad, 0.55, sin(ang) * rad)
			loot_spots.append([kinds[k % 3], amounts[k % 3], lp, 3])


func _aggregate() -> void:
	for rg in _regions:
		var node = rg["node"]
		var off := Vector3(float(rg["ox"]), 0.0, float(rg["oz"]))
		var spots: Array = node.loot_spots
		var n: int = spots.size()
		var keep: int = mini(n, 30)
		for k in range(keep):
			var spec: Array = spots[int(float(k) * float(n) / float(maxi(keep, 1)))]
			var tier := 1 + (k % 2)
			loot_spots.append([spec[0], spec[1], spec[2] + off, tier])
		for p in node.poi_list:
			poi_list.append({"name": str(p["name"]), "pos": p["pos"] + off})
		for h in node.house_positions:
			var hv: Vector3 = h
			house_positions.append(hv + off)
		map_labels.append({"name": str(rg["name"]), "pos": off})
	# Enemy spawns: one per region, plus two extra for the first regions = 16.
	var first: Array[Vector3] = []
	var extra: Array[Vector3] = []
	var ri := 0
	for rg in _regions:
		var node = rg["node"]
		var off := Vector3(float(rg["ox"]), 0.0, float(rg["oz"]))
		if node.enemy_spawns.size() > 0:
			var sp: Vector3 = node.enemy_spawns[0]
			first.append(sp + off)
		else:
			first.append(off + Vector3(0, 0.6, 0))
		if ri < 2 and node.enemy_spawns.size() > 1:
			var sp2: Vector3 = node.enemy_spawns[1]
			extra.append(sp2 + off)
		ri += 1
	enemy_spawns = first + extra


func ground_height(x: float, z: float) -> float:
	for rg in _regions:
		var lx: float = x - float(rg["ox"])
		var lz: float = z - float(rg["oz"])
		if absf(lx) <= 70.0 and absf(lz) <= 70.0:
			var node = rg["node"]
			if node.has_method("ground_height"):
				return node.ground_height(lx, lz)
			return 0.0
	return 0.0


func _finalize() -> void:
	var draws: int = _batch.build_visuals(self, AABB(Vector3(-460, -60, -460), Vector3(920, 140, 920)))
	_batch.build_colliders(self)
	print("WORLD: regions=", _regions.size(), " enemies=", enemy_spawns.size(),
		" loot=", loot_spots.size(), " pois=", poi_list.size(), " tissue_draws=", draws)
