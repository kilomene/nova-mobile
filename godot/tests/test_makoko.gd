extends SceneTree
## Headless verification for the Phase 2 Makoko map.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_makoko.gd
## Runs ~700 frames, walks the player across POIs (teleport + settle),
## verifies floors hold, water floats, loot exists, enemies spawn.

var _main  # untyped: main.gd has no class_name; dynamic access to .map/.player/etc.
var _frame := 0
var _checks: Array = []  # [name, ok]
var _poi_idx := 0
var _settle_frames := 0
var _phase := 0  # 0 = poi walk, 1 = swim settle, 2 = done


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	# Critical: player.gd / enemy.gd / loot.gd read map_extent, player, etc.
	# via get_tree().current_scene — without this the harness leaves it null
	# and the player falls back to prototype bounds (ext=34).
	current_scene = _main
	print("TEST: main scene instanced, current_scene set")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		_run_static_checks()
	if _frame == 10:
		_teleport_to_poi(0)
	if _frame > 10 and _frame < 1100 and _phase < 2:
		_tick()
	if _frame >= 1100:
		_finish()
		return true
	return false


func _run_static_checks() -> void:
	var map = _main.map
	_log_check("map instanced", map != null)
	_log_check("houses >= 25", map.house_positions.size() >= 25,
		"houses=" + str(map.house_positions.size()))
	_log_check("pois == 4", map.poi_list.size() == 4,
		"pois=" + str(map.poi_list.size()))
	var names := []
	for p in map.poi_list:
		names.append(p["name"])
	_log_check("poi names", names.has("Main Dock") and names.has("Market Row")
		and names.has("Old Shrine") and names.has("Canoe Yard"), str(names))
	_log_check("enemy spawns == 6", map.enemy_spawns.size() == 6,
		"spawns=" + str(map.enemy_spawns.size()))
	_log_check("enemies spawned == 6", _main.enemies.size() == 6,
		"enemies=" + str(_main.enemies.size()))
	# enemy spawns must sit on house floors, not open water
	var all_housed := true
	for sp in map.enemy_spawns:
		var near_house := false
		for hc in map.house_positions:
			if Vector2(sp.x - hc.x, sp.z - hc.z).length() < 6.0:
				near_house = true
				break
		if not near_house:
			all_housed = false
	_log_check("enemy spawns on floors", all_housed)
	_log_check("loot >= 20", map.loot_spots.size() >= 20,
		"loot=" + str(map.loot_spots.size()))
	_log_check("loot nodes spawned", _main.loots.size() >= map.loot_spots.size(),
		"nodes=" + str(_main.loots.size()))
	_log_check("player exists", _main.player != null)
	_log_check("player spawn on dock",
		_main.map.player_spawn.distance_to(Vector3(0, 0.6, 52)) < 4.0,
		"spawn=" + str(_main.map.player_spawn))
	var mi_count := _count_mi(map)
	_log_check("mesh instances < 400 (batched)", mi_count < 400, "mi=" + str(mi_count))


func _count_mi(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_mi(ch)
	return c


func _teleport_to_poi(i: int) -> void:
	var p: Vector3 = _main.map.poi_list[i]["pos"]
	var pname: String = _main.map.poi_list[i]["name"]
	var off := Vector3.ZERO
	if pname == "Market Row":
		off = Vector3(0, 0, 2.5)  # avoid landing on a stall table
	var player = _main.player
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x + off.x, 1.2, p.z + off.z)
	_settle_frames = 0


func _tick() -> void:
	if _phase == 1:
		_settle_frames += 1
		if _settle_frames >= 150:
			var y: float = _main.player.global_position.y
			_log_check("water buoyancy (floats)", y > -0.45 and y < -0.05,
				"y=" + str(snappedf(y, 0.01)))
			_phase = 2
		return
	_settle_frames += 1
	if _settle_frames < 150:
		return
	var pname: String = _main.map.poi_list[_poi_idx]["name"]
	var y2: float = _main.player.global_position.y
	var on_floor: bool = _main.player.is_on_floor()
	_log_check("floor holds @ " + pname, on_floor and y2 > -0.2 and y2 < 0.4,
		"y=" + str(snappedf(y2, 0.01)) + " floor=" + str(on_floor))
	_poi_idx += 1
	if _poi_idx >= _main.map.poi_list.size():
		_phase = 1
		_settle_frames = 0
		var player = _main.player
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(62, 0.5, 62)  # open water
	else:
		_teleport_to_poi(_poi_idx)


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("TEST DONE: frames=", _frame, " checks=", _checks.size(), " failures=", fails)
