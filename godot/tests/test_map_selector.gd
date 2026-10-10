extends SceneTree
## Headless verification that the pre-match map selector switches maps cleanly.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_map_selector.gd
## Spawns main with each map idx in turn, verifies, frees it cleanly.

var _main
var _old
var _frame := 0
var _checks: Array = []
var _stage := 0  # even = check stage, odd = freed stage; stage/2 = map idx
var _next_frame := 60

const MAPS := [
	{"idx": 0, "node": "MakokoMap"},
	{"idx": 1, "node": "LekkiMap"},
	{"idx": 2, "node": "ComputerVillageMap"},
	{"idx": 3, "node": "BananaIslandMap"},
	{"idx": 4, "node": "ValleyCombatMap"},
	{"idx": 5, "node": "BarracksMap"},
	{"idx": 6, "node": "TrainStationMap"},
	{"idx": 7, "node": "AirportMap"},
	{"idx": 8, "node": "LagoonBridgeMap"},
	{"idx": 9, "node": "ShipPortMap"},
	{"idx": 10, "node": "AirbaseMap"},
	{"idx": 11, "node": "WorldMap", "world": true},
	{"idx": 12, "node": "DowntownMap"},
	{"idx": 13, "node": "DamMap"},
	{"idx": 14, "node": "StadiumMap"},
]


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	_spawn(0)
	print("TEST: selector test started (11 maps)")


func _spawn(idx: int) -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	_main._headless_map = idx
	root.add_child(_main)
	current_scene = _main


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < _next_frame:
		return false
	var map_i := _stage / 2
	if _stage % 2 == 0:
		# Check stage: verify the map loaded.
		var want: String = MAPS[map_i]["node"]
		var got := str(_main.map.name) if _main.map != null else "null"
		_log_check("selector idx %d -> %s" % [int(MAPS[map_i]["idx"]), want],
			_main.map != null and got == want, "name=" + got)
		var is_world: bool = bool(MAPS[map_i].get("world", false))
		if is_world:
			_log_check("%s: 96 enemies + player (world, 25x4 squads)" % want,
				_main.enemies.size() == 96 and _main.player != null)
			_log_check("%s: pois >= 44 (world)" % want, _main.map.poi_list.size() >= 44)
		else:
			_log_check("%s: 6 enemies + player" % want,
				_main.enemies.size() == 6 and _main.player != null)
			_log_check("%s: pois >= 3" % want, _main.map.poi_list.size() >= 3)
		_old = _main
		_main.queue_free()
		_main = null
		current_scene = null
		_stage += 1
		_next_frame = _frame + 60
	else:
		# Freed stage: old match must be gone; spawn the next map (or finish).
		_log_check("match %d freed" % map_i, not is_instance_valid(_old))
		_stage += 1
		if _stage / 2 >= MAPS.size():
			_finish()
			return true
		_spawn(int(MAPS[_stage / 2]["idx"]))
		_next_frame = _frame + 60
	return false


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("TEST DONE: frames=", _frame, " checks=", _checks.size(), " failures=", fails)
