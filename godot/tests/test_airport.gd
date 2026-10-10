extends SceneTree
## Headless verification for the Phase 9 Airport Helicopter Wing map.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_barracks.gd
## Runs ~1000 frames: static checks (flat ground: no ground_height) + POI walk
## (teleport + settle, feet must be ON the ground: is_on_floor and
## y within tolerance of the POI pos.y).
## Zero script errors expected.

var _main  # untyped: main.gd has no class_name; dynamic access to .map/.player/etc.
var _frame := 0
var _checks: Array = []  # [name, ok]
var _poi_idx := 0
var _settle_frames := 0


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	_main._headless_map = 7  # select the Airport map via the map selector path
	root.add_child(_main)
	current_scene = _main
	print("TEST: main scene instanced (map idx 7 = Airport), current_scene set")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		_run_static_checks()
	if _frame == 10:
		_run_spawn_checks()
	if _frame == 15:
		_teleport_to_poi(0)
	if _frame > 15 and _frame < 1000 and _poi_idx < 4:
		_tick()
	if _frame >= 1000 or (_poi_idx >= 4 and _frame > 250):
		_finish()
		return true
	return false


func _run_static_checks() -> void:
	var map = _main.map
	_log_check("map instanced", map != null)
	_log_check("map is AirportMap", map != null and str(map.name) == "AirportMap",
		"name=" + str(map.name if map != null else "null"))
	_log_check("flat ground: no ground_height", map == null or not map.has_method("ground_height"))
	_log_check("pois == 4", map.poi_list.size() == 4,
		"pois=" + str(map.poi_list.size()))
	var names := []
	for p in map.poi_list:
		names.append(p["name"])
	_log_check("poi names", names.has("Terminal") and names.has("Control Tower")
		and names.has("Helipad Row") and names.has("Hangars"), str(names))
	_log_check("enemy spawns == 6", map.enemy_spawns.size() == 6,
		"spawns=" + str(map.enemy_spawns.size()))
	_log_check("enemies spawned == 6", _main.enemies.size() == 6,
		"enemies=" + str(_main.enemies.size()))
	_log_check("loot >= 60", map.loot_spots.size() >= 60,
		"loot=" + str(map.loot_spots.size()))
	_log_check("loot nodes spawned", _main.loots.size() >= map.loot_spots.size(),
		"nodes=" + str(_main.loots.size()))
	_log_check("player exists", _main.player != null)
	var mi_count := _count_mi(map)
	_log_check("mesh instances < 400 (batched)", mi_count < 400, "mi=" + str(mi_count))


func _run_spawn_checks() -> void:
	# Flat ground: spawns bake y directly (player +0.6 above ground).
	var sp: Vector3 = _main.player.global_position
	_log_check("player spawn height ~0.6", absf(sp.y - 0.6) < 0.8,
		"y=" + str(snappedf(sp.y, 0.01)))
	var all_ok := true
	for e in _main.enemies:
		var ep: Vector3 = e.global_position
		if absf(ep.y - 0.6) > 1.2:
			all_ok = false
	_log_check("enemy spawn heights ~0.6", all_ok)


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
	_teleport(Vector3(pos.x, pos.y + 1.2, pos.z))


func _tick() -> void:
	_settle_frames += 1
	if _settle_frames < 150:
		return
	var pname: String = _main.map.poi_list[_poi_idx]["name"]
	var ppos: Vector3 = _main.map.poi_list[_poi_idx]["pos"]
	var pp: Vector3 = _main.player.global_position
	var on_floor: bool = _main.player.is_on_floor()
	var dy := absf(pp.y - ppos.y)
	_log_check("feet on ground @ " + pname, on_floor and dy < 0.8,
		"y=" + str(snappedf(pp.y, 0.01)) + " poi_y=" + str(snappedf(ppos.y, 0.01))
		+ " floor=" + str(on_floor))
	_poi_idx += 1
	if _poi_idx < _main.map.poi_list.size():
		_teleport_to_poi(_poi_idx)


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("TEST DONE: frames=", _frame, " checks=", _checks.size(), " failures=", fails)
