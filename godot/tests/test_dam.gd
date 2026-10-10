extends SceneTree
## Headless verification for the Phase 14 Dam + Reservoir map.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_dam.gd
## Spawns the map scene directly (+ player/enemies/loot, mirroring main.gd),
## runs static checks, spawn checks, then a POI walk (teleport + settle,
## floors hold — incl. the Dam Crest POI at y=24). 700 frames, 18 checks.
## Zero script errors expected.

var _map
var _player
var _enemies: Array = []
var _loots: Array = []
var _frame := 0
var _checks: Array = []  # [name, ok]
var _poi_idx := 0
var _settle_frames := 0
var _spawned := false

const POI_OFFSETS := {
	"Dam Crest": Vector3.ZERO,
	"Control Room": Vector3(0, 0, 3),
	"Spillway": Vector3.ZERO,
}


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/dam.tscn")
	_map = ps.instantiate()
	root.add_child(_map)
	current_scene = _map
	print("TEST: dam scene instanced (actors spawn once map _ready ran)")


func _spawn_actors() -> void:
	# Mirrors main.gd's spawn logic for flat maps. Runs after the map's
	# _ready (which populates enemy_spawns/loot_spots) has fired.
	if _map.enemy_spawns.is_empty():
		return
	_spawned = true
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = _map.player_spawn + Vector3(0, 0.6, 0)
	root.add_child(_player)
	for sp in _map.enemy_spawns:
		var e = load("res://scenes/enemy.tscn").instantiate()
		root.add_child(e)
		e.position = sp + Vector3(0, 0.6, 0)
		e.home_position = e.position
		_enemies.append(e)
	for spec in _map.loot_spots:
		var l = load("res://scenes/loot.tscn").instantiate()
		root.add_child(l)
		l.position = spec[2] + Vector3(0, 0.55, 0)
		l.kind = spec[0]
		l.amount = spec[1]
		_loots.append(l)
	print("TEST: actors spawned (enemies=", _enemies.size(), " loot=", _loots.size(), ")")


func _process(_delta: float) -> bool:
	_frame += 1
	if not _spawned and _frame >= 2:
		_spawn_actors()
	if _frame == 5:
		_run_static_checks()
	if _frame == 80:
		_teleport_to_poi(0)
	if _frame > 80 and _frame < 540 and _poi_idx < 3:
		_tick()
	if _frame == 540:
		# Back to spawn for the settle checks.
		_teleport(_map.player_spawn + Vector3(0, 0.6, 0))
	if _frame == 640:
		_run_settle_checks()
	if _frame >= 700:
		_finish()
		return true
	return false


func _run_static_checks() -> void:
	_log_check("scene loads", _map != null)
	_log_check("class name DamMap", _map != null and str(_map.name) == "DamMap",
		"name=" + str(_map.name if _map != null else "null"))
	_log_check("map_extent == 70", _map.map_extent == 70.0, "extent=" + str(_map.map_extent))
	_log_check("flat ground: no ground_height", _map == null or not _map.has_method("ground_height"))
	_log_check("buildings == 2", _map.house_positions.size() == 2,
		"buildings=" + str(_map.house_positions.size()))
	_log_check("pois == 3", _map.poi_list.size() == 3,
		"pois=" + str(_map.poi_list.size()))
	var names := []
	for p in _map.poi_list:
		names.append(p["name"])
	_log_check("poi names", names.has("Dam Crest") and names.has("Control Room")
		and names.has("Spillway"), str(names))
	_log_check("enemy spawns == 6", _map.enemy_spawns.size() == 6,
		"spawns=" + str(_map.enemy_spawns.size()))
	_log_check("enemies spawned == 6", _enemies.size() == 6,
		"enemies=" + str(_enemies.size()))
	_log_check("player exists", _player != null)
	_log_check("loot >= 65", _map.loot_spots.size() >= 65,
		"loot=" + str(_map.loot_spots.size()))
	_log_check("loot nodes spawned", _loots.size() == _map.loot_spots.size(),
		"nodes=" + str(_loots.size()))
	_log_check("draw calls <= 40", _map.draw_calls <= 40,
		"draws=" + str(_map.draw_calls))
	var mi_count := _count_mi(_map)
	_log_check("mesh instances < 400 (batched)", mi_count < 400, "mi=" + str(mi_count))


func _run_settle_checks() -> void:
	# Late check: physics runs slower than render frames headless, so the
	# player/enemies need a few hundred frames to fall and settle.
	var sp: Vector3 = _player.global_position
	_log_check("player spawn settled ~0.6", absf(sp.y - 0.6) < 0.8,
		"y=" + str(snappedf(sp.y, 0.01)))
	var all_ok := true
	for e in _enemies:
		var ep: Vector3 = e.global_position
		# Crest spawns settle at y~24.6, ground spawns at y~0.6.
		var on_crest := ep.y > 20.0
		if not e.is_on_floor() or ep.y < -0.5 or absf(ep.x) > 66.0 or absf(ep.z) > 66.0:
			all_ok = false
		if on_crest and absf(ep.y - 24.6) > 1.5:
			all_ok = false
	_log_check("enemies settled (ground + crest)", all_ok)


func _count_mi(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_mi(ch)
	return c


func _teleport(p: Vector3) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = p
	_settle_frames = 0


func _teleport_to_poi(i: int) -> void:
	var pos: Vector3 = _map.poi_list[i]["pos"]
	var pname: String = _map.poi_list[i]["name"]
	var off: Vector3 = POI_OFFSETS.get(pname, Vector3.ZERO)
	_teleport(Vector3(pos.x + off.x, pos.y + 1.2 + off.y, pos.z + off.z))


func _tick() -> void:
	_settle_frames += 1
	if _settle_frames < 150:
		return
	var pname: String = _map.poi_list[_poi_idx]["name"]
	var ppos: Vector3 = _map.poi_list[_poi_idx]["pos"]
	var pp: Vector3 = _player.global_position
	var on_floor: bool = _player.is_on_floor()
	var dy := absf(pp.y - ppos.y)
	_log_check("floor holds @ " + pname, on_floor and dy < 0.8,
		"y=" + str(snappedf(pp.y, 0.01)) + " poi_y=" + str(snappedf(ppos.y, 0.01))
		+ " floor=" + str(on_floor))
	_poi_idx += 1
	if _poi_idx < _map.poi_list.size():
		_teleport_to_poi(_poi_idx)


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("TEST DONE: frames=", _frame, " checks=", _checks.size(), " failures=", fails)
