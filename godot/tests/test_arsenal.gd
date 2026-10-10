extends SceneTree
## Headless verification for THE ARSENAL (gun system).
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_arsenal.gd
## Checks: roster integrity, stat sanity, model builds, audio synthesis,
## inventory (give/swap/reload/attach), loot integration, no script errors.

var _checks: Array = []
var _frame := 0
var _phase := 0
var _player: NovaPlayer = null
var _main = null

const EXPECTED := {"ar": 32, "smg": 32, "lmg": 15, "sniper": 14, "marksman": 7,
	"shotgun": 12, "pistol": 10, "melee": 10, "launcher": 5}


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	_run_static_checks()
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate() as NovaPlayer
	root.add_child(_player)
	print("TEST: player instanced for arsenal checks")


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _run_static_checks() -> void:
	var roster: Array = GunDefs.all()
	_log_check("roster == 137", roster.size() == 137, "n=" + str(roster.size()))
	var ids := {}
	var dup := false
	var per_class := {}
	for g in roster:
		if ids.has(g["id"]):
			dup = true
		ids[g["id"]] = true
		per_class[g["cls"]] = int(per_class.get(g["cls"], 0)) + 1
	_log_check("ids unique", not dup)
	for cls in EXPECTED.keys():
		_log_check("class " + cls + " count", int(per_class.get(cls, 0)) == int(EXPECTED[cls]),
			"got=" + str(per_class.get(cls, 0)))
	# Stat sanity per gun.
	var sane := true
	var bad := ""
	for g in roster:
		if float(g["damage"]) <= 0 or float(g["rpm"]) < 20 or float(g["rpm"]) > 1200:
			sane = false; bad = str(g["id"]) + ":dmg/rpm"
		if int(g["mag"]) <= 0 or float(g["reload"]) < 0.4 or float(g["reload"]) > 6.0:
			sane = false; bad = str(g["id"]) + ":mag/reload"
		if float(g["ads"]) < 0.1 or float(g["ads"]) > 0.8:
			sane = false; bad = str(g["id"]) + ":ads"
		if float(g["move"]) < 0.7 or float(g["move"]) > 1.1:
			sane = false; bad = str(g["id"]) + ":move"
		if float(g["range_near"]) >= float(g["range_far"]) and str(g["cls"]) != "melee":
			sane = false; bad = str(g["id"]) + ":range"
		var slot: String = GunDefs.slot_of(str(g["cls"]))
		if not ["primary", "secondary", "melee"].has(slot):
			sane = false; bad = str(g["id"]) + ":slot"
	_log_check("stats sane (137 guns)", sane, bad)
	# Damage falloff.
	var kv := GunDefs.by_id("kv47")
	var d0: float = GunDefs.damage_at_range(kv, 10.0)
	var d1: float = GunDefs.damage_at_range(kv, 100.0)
	_log_check("falloff close==dmg", absf(d0 - 33.0) < 0.01, str(d0))
	_log_check("falloff far<dmg", d1 < d0 and d1 > 0.0, str(d1))
	# Attachments.
	var e0 := GunDefs.effective(kv, [])
	var e1 := GunDefs.effective(kv, ["suppressor"])
	_log_check("suppressor quiets", bool(e1["silent"]) and float(e1["recv"]) < float(e0["recv"]))
	var e2 := GunDefs.effective(kv, ["extended"])
	_log_check("extended mag+", int(e2["mag"]) == int(e0["mag"]) + 12)
	_log_check("find_attach", str(GunDefs.find_attach("reddot")["slot"]) == "optic")
	_log_check("attach_slot", GunDefs.attach_slot("foregrip") == "underbarrel")
	# roll_gun validity.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var ok := true
	for t in range(6):
		for i in range(40):
			if GunDefs.by_id(GunDefs.roll_gun(t, rng)).is_empty():
				ok = false
	_log_check("roll_gun valid (240 rolls)", ok)
	# Audio synthesis per class.
	var aok := true
	for cls in ["ar", "smg", "lmg", "sniper", "marksman", "shotgun", "pistol", "launcher", "melee"]:
		var s: AudioStreamWAV = GunAudio.fire_stream(cls)
		if s.data.size() < 1000:
			aok = false
	_log_check("audio per class", aok)
	_log_check("reload sound", GunAudio.reload_stream().data.size() > 500)
	_log_check("explosion sound", GunAudio.explosion_stream().data.size() > 5000)
	# Model builds for every gun.
	var mok := true
	var worst := 0
	var worst_id := ""
	for g in roster:
		var vm: Dictionary = GunModels.build_viewmodel(str(g["id"]))
		var n: int = _count_nodes(vm["root"] as Node)
		if n > worst:
			worst = n
			worst_id = str(g["id"])
		if n > 60:
			mok = false
		if (vm["root"] as Node).get_node_or_null("Muzzle") == null:
			mok = false
		var wm: Node = GunModels.build_world_model(str(g["id"]))
		if _count_nodes(wm) > 28:
			mok = false
		vm["root"].queue_free()
		wm.queue_free()
	_log_check("viewmodels <= 60 nodes", mok, "worst=" + worst_id + ":" + str(worst))
	_log_check("sight heights sane",
		GunModels.sight_height("lw9") > GunModels.sight_height("m5"))


func _run_player_checks() -> void:
	# Starting loadout.
	_log_check("start primary m5", str(_player.slots["primary"]["id"]) == "m5")
	_log_check("start secondary p9", str(_player.slots["secondary"]["id"]) == "p9")
	_log_check("start melee knife", str(_player.slots["melee"]["id"]) == "knife")
	_log_check("weapon signal name", _player.cur_weapon_name() == "M5 \"Sentinel\"")
	# Give one gun of every class; verify slot routing + equip.
	var trials := {"kv47": "primary", "mp9": "primary", "mg60": "primary",
		"lw9": "primary", "mk14": "primary", "p12": "primary",
		"d50": "secondary", "rl4": "secondary", "axe": "melee"}
	var rok := true
	for gid in trials.keys():
		var old: String = _player.give_gun(gid, 3)
		if _player.cur_slot != str(trials[gid]):
			rok = false
		if str(_player.slots[str(trials[gid])]["id"]) != gid:
			rok = false
		if old == "":
			rok = false  # every slot had a starter gun
	_log_check("give_gun routing (9 classes)", rok)
	# Swap cycle.
	_player.swap_slot(1)
	_log_check("swap to secondary", _player.cur_slot == "secondary")
	_player.swap_slot(2)
	_log_check("swap to melee", _player.cur_slot == "melee")
	_player.cycle_weapon()
	_log_check("cycle wraps to primary", _player.cur_slot == "primary")
	# Reload consumes reserve.
	_player._gun()["mag"] = 5
	var before: int = _player.cur_reserve()
	_player.start_reload()
	_log_check("reload started", _player._reloading)
	# Fast-forward the reload timer manually.
	_player._reload_timer = 0.01
	_player._process(0.02)
	_log_check("reload finished", not _player._reloading)
	_log_check("reload filled mag", _player.cur_mag() == int(_player._eff()["mag"]),
		"mag=" + str(_player.cur_mag()))
	_log_check("reload spent reserve", _player.cur_reserve() < before)
	# Attachment on current gun (fresh tier-0 gun: no pre-kitted attachments).
	_player.give_gun("m5", 0)
	var had: float = _player._eff()["recv"]
	_log_check("attach foregrip", _player.attach_to_current("foregrip"))
	_log_check("foregrip reduces recoil", float(_player._eff()["recv"]) < float(had))
	_log_check("attach replace same slot", _player.attach_to_current("laser"))
	var atts: Array = _player._gun()["attach"]
	var lasers := 0
	for a in atts:
		if GunDefs.attach_slot(str(a)) == "underbarrel":
			lasers += 1
	_log_check("one per slot", lasers == 1, str(atts))
	# Melee has no reload; launcher reloads.
	_player._equip_slot("melee", true)
	_player.start_reload()
	_log_check("melee no reload", not _player._reloading)
	# Damage helpers.
	var lw := GunDefs.by_id("lw9")
	_log_check("sniper one-tap", GunDefs.damage_at_range(lw, 50.0) >= 90.0)
	# Gun pickup scene builds.
	var gp := GunPickup.make("sr8", 4)
	_log_check("pickup builds", gp != null and gp.gun_id == "sr8")
	gp.queue_free()
	var ga := GunPickup.make_attachment("suppressor")
	_log_check("attach pickup builds", ga != null and ga.attach_id == "suppressor")
	ga.queue_free()


func _run_world_checks() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	_main._headless_map = 11  # NOVA WORLD: tiered loot spots
	root.add_child(_main)
	current_scene = _main
	print("TEST: main scene instanced for gun-spawn checks")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5 and _phase == 0:
		_run_player_checks()
		_phase = 1
	if _frame == 10 and _phase == 1:
		_run_world_checks()
		_phase = 2
	if _frame == 20 and _phase == 2:
		var n := 0
		for c in _main.get_children():
			if c is GunPickup:
				n += 1
		_log_check("gun pickups spawned", n >= 8, "n=" + str(n))
		var tiers := {}
		for c in _main.get_children():
			if c is GunPickup and (c as GunPickup).attach_id == "":
				tiers[(c as GunPickup).tier] = true
		_log_check("pickup tiers vary", tiers.size() >= 2, str(tiers.keys()))
		_phase = 3
	if _frame >= 60:
		_finish()
		return true
	return false


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("ARSENAL: ", _checks.size() - fails, "/", _checks.size(), " checks passed")
	if fails > 0:
		print("ARSENAL: FAILURES PRESENT")
	quit()
