extends SceneTree
## Headless verification for the Phase 5 Banana Island luxury waterfront map.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_bananaisland.gd
## Runs ~900 frames: static checks + POI walk (teleport + settle, floors hold).
## Zero script errors expected.

var _main  # untyped: main.gd has no class_name; dynamic access to .map/.player/etc.
var _frame := 0
var _checks: Array = []  # [name, ok]
var _poi_idx := 0
var _settle_frames := 0

const POI_OFFSETS := {
	"Marina Bay": Vector3(0, 0, -3),
	"Sky Villa": Vector3(0, 0, 8),
	"Palm Boulevard": Vector3(0, 0, 4),
	"Yacht Club": Vector3(0, 0, 8),
}


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	_main._headless_map = 3  # select the Banana Island map via the map selector path
	root.add_child(_main)
	current_scene = _main
	print("TEST: main scene instanced (map idx 3 = BananaIsland), current_scene set")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		_run_static_checks()
	if _frame == 10:
		_teleport_to_poi(0)
	if _frame > 10 and _frame < 900 and _poi_idx < 4:
		_tick()
	if _frame >= 900 or (_poi_idx >= 4 and _frame > 200):
		_finish()
		return true
	return false


func _run_static_checks() -> void:
	var map = _main.map
	_log_check("map instanced", map != null)
	_log_check("map is BananaIslandMap", map != null and str(map.name) == "BananaIslandMap",
		"name=" + str(map.name if map != null else "null"))
	_log_check("buildings >= 8", map.house_positions.size() >= 8,
		"buildings=" + str(map.house_positions.size()))
	_log_check("pois == 4", map.poi_list.size() == 4,
		"pois=" + str(map.poi_list.size()))
	var names := []
	for p in map.poi_list:
		names.append(p["name"])
	_log_check("poi names", names.has("Marina Bay") and names.has("Sky Villa")
		and names.has("Palm Boulevard") and names.has("Yacht Club"), str(names))
	_log_check("enemy spawns == 6", map.enemy_spawns.size() == 6,
		"spawns=" + str(map.enemy_spawns.size()))
	_log_check("enemies spawned == 6", _main.enemies.size() == 6,
		"enemies=" + str(_main.enemies.size()))
	var all_inside := true
	for sp in map.enemy_spawns:
		if not (absf(sp.x) < 68.0 and absf(sp.z) < 68.0):
			all_inside = false
	_log_check("enemy spawns inside map", all_inside)
	_log_check("loot >= 60", map.loot_spots.size() >= 60,
		"loot=" + str(map.loot_spots.size()))
	_log_check("loot nodes spawned", _main.loots.size() >= map.loot_spots.size(),
		"nodes=" + str(_main.loots.size()))
	_log_check("player exists", _main.player != null)
	_log_check("player spawn sane",
		_main.map.player_spawn.distance_to(Vector3(-54, 0.6, -4)) < 4.0,
		"spawn=" + str(_main.map.player_spawn))
	var mi_count := _count_mi(map)
	_log_check("mesh instances < 400 (batched)", mi_count < 400, "mi=" + str(mi_count))


func _count_mi(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_mi(ch)
	return c


func _teleport(p: Vector3) -> void:
	var player = _main.player
	player.velocity = Vector3.ZERO
	player.global_position = p
	_settle_frames = 0


func _teleport_to_poi(i: int) -> void:
	var pos: Vector3 = _main.map.poi_list[i]["pos"]
	var pname: String = _main.map.poi_list[i]["name"]
	var off: Vector3 = POI_OFFSETS.get(pname, Vector3.ZERO)
	_teleport(Vector3(pos.x + off.x, 1.2, pos.z + off.z))


func _tick() -> void:
	_settle_frames += 1
	if _settle_frames < 150:
		return
	var pname: String = _main.map.poi_list[_poi_idx]["name"]
	var y2: float = _main.player.global_position.y
	var on_floor: bool = _main.player.is_on_floor()
	_log_check("floor holds @ " + pname, on_floor and y2 > -0.2 and y2 < 0.4,
		"y=" + str(snappedf(y2, 0.01)) + " floor=" + str(on_floor))
	_poi_idx += 1
	if _poi_idx < _main.map.poi_list.size():
		_teleport_to_poi(_poi_idx)


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("TEST DONE: frames=", _frame, " checks=", _checks.size(), " failures=", fails)
