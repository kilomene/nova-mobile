extends SceneTree
## Headless verification of the merged NOVA WORLD battle royale map.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_world.gd
## Stage 0: structural checks on the world scene. Stage 1: full match via main idx 11.

var _world
var _main
var _frame := 0
var _checks: Array = []
var _stage := 0
var _next_frame := 60

const KNOWN_REGIONS := ["AIRBASE", "AIRPORT", "BARRACKS", "TRAIN STATION", "VALLEY",
	"LEKKI", "COMPUTER VILLAGE", "MAKOKO", "BANANA ISLAND", "SHIP PORT", "LAGOON BRIDGE"]
const WORLD_POI_NAMES := ["Grand Canal", "Central Crossroads", "Lakeside Park",
	"North Gate", "Harbor View", "South Lagoon"]


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/world.tscn")
	_world = ps.instantiate()
	root.add_child(_world)
	current_scene = _world
	print("TEST: world structural checks starting")


func _names(a: Array) -> Array:
	var out := []
	for e in a:
		out.append(str(e["name"]))
	return out


func _check_structure() -> void:
	var w = _world
	_log_check("world class == WorldMap", str(w.get_script().resource_path) == "res://scripts/world.gd",
		"script=" + str(w.get_script().resource_path))
	_log_check("regions >= 11", w._regions.size() >= 11, "regions=" + str(w._regions.size()))
	var labels := _names(w.map_labels)
	var missing := []
	for rn in KNOWN_REGIONS:
		if not labels.has(rn):
			missing.append(rn)
	_log_check("all 11 known regions present", missing.is_empty(), "missing=" + str(missing))
	_log_check("map_extent == 345", w.map_extent == 345.0, "extent=" + str(w.map_extent))
	_log_check("enemy_spawns == 16", w.enemy_spawns.size() == 16, "n=" + str(w.enemy_spawns.size()))
	_log_check("loot in [300, 700]", w.loot_spots.size() >= 300 and w.loot_spots.size() <= 700,
		"loot=" + str(w.loot_spots.size()))
	_log_check("pois >= 44", w.poi_list.size() >= 44, "pois=" + str(w.poi_list.size()))
	var pnames := _names(w.poi_list)
	var pmissing := []
	for pn in WORLD_POI_NAMES:
		if not pnames.has(pn):
			pmissing.append(pn)
	_log_check("6 world POIs present", pmissing.is_empty(), "missing=" + str(pmissing))
	# ground_height delegation: valley region local vs world coords.
	var valley_node = null
	for rg in w._regions:
		if str(rg["name"]) == "VALLEY":
			valley_node = rg["node"]
	var gh_ok := false
	if valley_node != null:
		var a: float = valley_node.ground_height(10.0, -20.0)
		var b: float = w.ground_height(-270.0 + 10.0, -90.0 - 20.0)
		gh_ok = absf(a - b) < 0.01
	_log_check("ground_height delegates to regions", gh_ok)
	_log_check("ground_height(0,0) == 0 (gap)", w.ground_height(0.0, 0.0) == 0.0)
	# Loot tiers present.
	var tiered := 0
	for spec in w.loot_spots:
		if spec.size() > 3 and int(spec[3]) > 0:
			tiered += 1
	_log_check("loot tiers assigned", tiered > 100, "tiered=" + str(tiered))
	_log_check("map_labels >= 11", w.map_labels.size() >= 11, "labels=" + str(w.map_labels.size()))
	# Region offsets sane (Makoko at its grid slot).
	var mok := false
	for rg in w._regions:
		if str(rg["name"]) == "MAKOKO":
			mok = absf(float(rg["ox"]) + 270.0) < 0.01 and absf(float(rg["oz"]) - 90.0) < 0.01
	_log_check("Makoko at (-270, 90)", mok)


func _spawn_match() -> void:
	_world.queue_free()
	_world = null
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	_main._headless_map = 11
	root.add_child(_main)
	current_scene = _main
	print("TEST: world match (idx 11) starting")


func _check_match() -> void:
	var m = _main
	_log_check("match map == WorldMap", m.map != null and str(m.map.name) == "WorldMap",
		"name=" + (str(m.map.name) if m.map != null else "null"))
	_log_check("drop-in active", m.player != null and m.player.dropping, "dropping=" + str(m.player.dropping if m.player else "?"))
	_log_check("world zone radius 430", m.zone_radius == 430.0, "r=" + str(m.zone_radius))
	_log_check("96 enemies (24 squads x 4)", m.enemies.size() == 96, "n=" + str(m.enemies.size()))
	_log_check("3 AI teammates", m.allies.size() == 3, "n=" + str(m.allies.size()))
	_log_check("squadman organized 25 squads", m.squadman != null and m.squadman.squads.size() == 25,
		"n=" + (str(m.squadman.squads.size()) if m.squadman != null else "null"))
	var norespawn := true
	for e in m.enemies:
		if e.allow_respawn:
			norespawn = false
	_log_check("enemies no-respawn in world", norespawn)
	_log_check("hud world_mode", m.hud.world_mode, "world_mode=" + str(m.hud.world_mode))
	_log_check("hud map_labels >= 11", m.hud.map_labels.size() >= 11, "n=" + str(m.hud.map_labels.size()))
	_log_check("loot spawned", m.loots.size() >= 300, "loots=" + str(m.loots.size()))
	# Shorten the drop to verify landing quickly.
	if m.player != null:
		m.player.global_position.y = 30.0


func _check_landed() -> void:
	var m = _main
	var landed: bool = m.player != null and not m.player.dropping
	_log_check("player landed from drop", landed,
		"y=" + ("%.1f" % m.player.global_position.y) if m.player != null else "no player")
	var alive_ok: bool = m.player != null and m.player.is_alive()
	_log_check("player alive after landing", alive_ok)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < _next_frame:
		return false
	if _stage == 0:
		_check_structure()
		_stage = 1
		_spawn_match()
		_next_frame = _frame + 40  # catch the BR drop-in mid-air (headless physics catch-up lands fast)
	elif _stage == 1:
		_check_match()
		_stage = 2
		_next_frame = _frame + 300
	elif _stage == 2:
		_check_landed()
		_stage = 3
		_next_frame = _frame + 400
	else:
		var fails := 0
		for c in _checks:
			if not c[1]:
				fails += 1
		print("TEST DONE: frames=", _frame, " checks=", _checks.size(), " failures=", fails)
		return true
	return false
