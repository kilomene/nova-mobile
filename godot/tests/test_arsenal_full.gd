extends SceneTree
## Full-arsenal expansion verification (137 guns).
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_arsenal_full.gd
## Checks: deep def validation (fields, model-spec vocabulary, burst_n, sound
## mods, projectile fields), model builds for ALL 137 guns within node budgets,
## per-gun audio synthesis spot checks, per-class pickup/swap/reload with NEW
## guns (exercising grenade-mode sniper/pistol, burst_n 2/4, lever, cylinder),
## loot roll coverage. No script errors.

var _checks: Array = []
var _frame := 0
var _phase := 0
var _player: NovaPlayer = null

const KNOWN_MAG := ["curved", "straight", "drum", "box", "tube", "stick",
	"internal", "none", "helix", "helixunder", "pan", "belt", "casket", "saddle"]
const KNOWN_STOCK := ["fixed", "folding", "skeleton", "bullpup", "wire", "none",
	"brace", "pdw", "thumbhole", "chassis"]
const KNOWN_SIGHT := ["iron", "reddot", "holo", "scope", "scopelong", "none",
	"thermal", "acog"]
const KNOWN_MUZZLE := ["flash", "suppressor", "comp", "brake", "none",
	"linear", "shroud"]
const KNOWN_BODY := ["black", "gunmetal", "tan", "od", "grey", "white", "sand",
	"bronze", "graphite", "bluegrey"]
const KNOWN_MODE := ["auto", "semi", "burst", "pump", "bolt", "melee",
	"rocket", "grenade"]
# One NEW gun per class to exercise new code paths.
const CLASS_TRIALS := {
	"ar": "av9", "smg": "bz64", "lmg": "dp27", "sniper": "na45",
	"marksman": "kb98", "shotgun": "r90", "pistol": "xb1",
	"melee": "sai", "launcher": "d13",
}


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _initialize() -> void:
	_run_static_checks()
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate() as NovaPlayer
	root.add_child(_player)
	print("TEST: player instanced for full-arsenal checks")


func _run_static_checks() -> void:
	var roster: Array = GunDefs.all()
	_log_check("roster == 137", roster.size() == 137, "n=" + str(roster.size()))
	# Deep def validation.
	var ok := true
	var bad := ""
	var names := {}
	for g in roster:
		var gid := str(g["id"])
		if names.has(gid):
			ok = false
			bad = gid + ":dup id"
		names[gid] = true
		if str(g["name"]) == "" or str(g["alias"]) == "":
			ok = false
			bad = gid + ":empty name/alias"
		if not KNOWN_MODE.has(str(g["mode"])):
			ok = false
			bad = gid + ":bad mode"
		var bn: int = int(g.get("burst_n", 3))
		if str(g["mode"]) == "burst" and (bn < 2 or bn > 6):
			ok = false
			bad = gid + ":burst_n"
		# Stat ranges.
		if float(g["damage"]) <= 0 or float(g["rpm"]) < 20 or float(g["rpm"]) > 1200:
			ok = false
			bad = gid + ":dmg/rpm"
		if int(g["mag"]) <= 0 or float(g["reload"]) < 0.4 or float(g["reload"]) > 6.0:
			ok = false
			bad = gid + ":mag/reload"
		if float(g["ads"]) < 0.1 or float(g["ads"]) > 0.8:
			ok = false
			bad = gid + ":ads"
		if float(g["move"]) < 0.7 or float(g["move"]) > 1.1:
			ok = false
			bad = gid + ":move"
		if str(g["cls"]) == "shotgun" and int(g.get("pellets", 0)) < 6:
			ok = false
			bad = gid + ":pellets"
		if (str(g["mode"]) == "rocket" or str(g["mode"]) == "grenade"):
			if float(g.get("blast", 0.0)) <= 0 or float(g.get("proj_speed", 0.0)) <= 0:
				ok = false
				bad = gid + ":proj fields"
		# Model-spec vocabulary.
		var spec: Dictionary = g["model"]
		if not KNOWN_MAG.has(str(spec.get("mag", "straight"))):
			ok = false
			bad = gid + ":mag vocab"
		if not KNOWN_STOCK.has(str(spec.get("stock", "fixed"))):
			ok = false
			bad = gid + ":stock vocab"
		if not KNOWN_SIGHT.has(str(spec.get("sight", "iron"))):
			ok = false
			bad = gid + ":sight vocab"
		if not KNOWN_MUZZLE.has(str(spec.get("muzzle", "flash"))):
			ok = false
			bad = gid + ":muzzle vocab"
		if not KNOWN_BODY.has(str(spec.get("body", "black"))):
			ok = false
			bad = gid + ":body vocab"
		# Sound mods sane.
		var sm: Dictionary = g.get("sound", {})
		for k in sm.keys():
			var v := float(sm[k])
			if v <= 0.0 or v > 3.0:
				ok = false
				bad = gid + ":sound mod " + str(k)
	_log_check("deep def validation (137)", ok, bad)
	# Per-gun audio synthesis: all classes + 2 sample guns per class.
	var aok := true
	var sample := {"ar": ["av9", "mg42"], "smg": ["fn9", "bz64"], "lmg": ["dp27", "ch9"],
		"sniper": ["na45", "ol6"], "marksman": ["kb98", "m1g"], "shotgun": ["r90", "hs21"],
		"pistol": ["xb1", "ng9"], "melee": ["sai", "bat"], "launcher": ["d13", "fj18"]}
	for cls in sample.keys():
		var s0: AudioStreamWAV = GunAudio.fire_stream(cls)
		if s0.data.size() < 1000:
			aok = false
		for gid in sample[cls]:
			var s: AudioStreamWAV = GunAudio.fire_stream_for(gid)
			if s.data.size() < 800:
				aok = false
	# Suppressed guns get the muffled path (different bytes than base class).
	var vs: AudioStreamWAV = GunAudio.fire_stream_for("vs12")
	var vb: AudioStreamWAV = GunAudio.fire_stream("sniper")
	if vs.data == vb.data:
		aok = false
	_log_check("per-gun audio synthesis", aok)
	# Model builds for ALL guns within budgets.
	var mok := true
	var worst := 0
	var worst_id := ""
	var wworst := 0
	var wworst_id := ""
	for g in roster:
		var gid := str(g["id"])
		var vm: Dictionary = GunModels.build_viewmodel(gid)
		var n: int = _count_nodes(vm["root"] as Node)
		if n > worst:
			worst = n
			worst_id = gid
		if n > 60:
			mok = false
		if (vm["root"] as Node).get_node_or_null("Muzzle") == null:
			mok = false
		var wm: Node = GunModels.build_world_model(gid)
		var wn: int = _count_nodes(wm)
		if wn > wworst:
			wworst = wn
			wworst_id = gid
		if wn > 28:
			mok = false
		vm["root"].queue_free()
		wm.queue_free()
	_log_check("137 viewmodels <= 60 nodes", mok, "worst=" + worst_id + ":" + str(worst))
	_log_check("137 world models <= 28 nodes", wworst <= 28, "worst=" + wworst_id + ":" + str(wworst))
	# Loot roll coverage: every class appears across tiers.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var seen := {}
	for t in range(6):
		for i in range(120):
			var gid2 := GunDefs.roll_gun(t, rng)
			var gg := GunDefs.by_id(gid2)
			if not gg.is_empty():
				seen[str(gg["cls"])] = true
	_log_check("roll_gun covers all classes", seen.size() == 9, str(seen.keys()))


func _run_player_checks() -> void:
	# One NEW gun per class: slot routing + equip.
	var rok := true
	for cls in CLASS_TRIALS.keys():
		var gid: String = CLASS_TRIALS[cls]
		_player.give_gun(gid, 2)
		var want_slot := GunDefs.slot_of(cls)
		if _player.cur_slot != want_slot:
			rok = false
		if str(_player.slots[want_slot]["id"]) != gid:
			rok = false
	_log_check("give_gun routing (9 new guns)", rok)
	# Grenade-mode sniper (NA-45) has blast + projectile fields live.
	_player.give_gun("na45", 3)
	var e := _player._eff()
	_log_check("na45 blast live", float(_player._def().get("blast", 0.0)) == 3.0)
	# Grenade-mode pistol (XB-1 crossbow) is silent.
	_player.give_gun("xb1", 3)
	_log_check("xb1 silent", bool(_player._eff()["silent"]))
	# Burst sizes respected.
	_player.give_gun("pk2", 0)
	_log_check("pk2 burst_n=2", int(_player._def().get("burst_n", 3)) == 2)
	_player.give_gun("sf4", 0)
	_log_check("sf4 burst_n=4", int(_player._def().get("burst_n", 3)) == 4)
	# Reload works on a new LMG (pan mag) and new shotgun (twin barrel).
	_player.give_gun("dp27", 0)
	_player._gun()["mag"] = 10
	_player.start_reload()
	_log_check("dp27 reload starts", _player._reloading)
	_player._reload_timer = 0.01
	_player._process(0.02)
	_log_check("dp27 reload fills", _player.cur_mag() == int(_player._eff()["mag"]))
	_player.give_gun("r90", 0)
	_player._gun()["mag"] = 2
	_player.start_reload()
	_player._reload_timer = 0.01
	_player._process(0.02)
	_log_check("r90 reload fills", _player.cur_mag() == int(_player._eff()["mag"]))
	# Melee new style has no reload.
	_player._equip_slot("melee", true)
	_player.give_gun("sai", 0)
	_player.start_reload()
	_log_check("sai no reload", not _player._reloading)
	# Attachments still apply on a new gun.
	_player.give_gun("gr56", 0)
	var had: float = _player._eff()["recv"]
	_log_check("attach on new gun", _player.attach_to_current("compensator"))
	_log_check("comp reduces recoil", float(_player._eff()["recv"]) < float(had))
	# Pickups build for new guns.
	var gp := GunPickup.make("mg42", 5)
	_log_check("mg42 pickup builds", gp != null and gp.gun_id == "mg42")
	gp.queue_free()
	var gp2 := GunPickup.make("fj18", 4)
	_log_check("fj18 pickup builds", gp2 != null and gp2.gun_id == "fj18")
	gp2.queue_free()
	# RP-7 Thunderhead: routing, def, whoosh audio, front-load reload, projectile.
	# (tier 0 here: tier 5 could roll "extended" and change effective mag.)
	_player.give_gun("rp7", 0)
	_log_check("rp7 routes to secondary", _player.cur_slot == GunDefs.slot_of("launcher"))
	var rd := GunDefs.by_id("rp7")
	_log_check("rp7 def", str(rd["mode"]) == "rocket" and float(rd["blast"]) == 5.5
		and str((rd["model"] as Dictionary).get("style")) == "rpg7"
		and int(rd["mag"]) == 1 and float(rd["reload"]) == 3.4)
	var ws := GunAudio.fire_stream_for("rp7")
	_log_check("rp7 whoosh audio", ws != null and ws.get_length() > 0.9)
	var gp3 := GunPickup.make("rp7", 5)
	_log_check("rp7 pickup builds", gp3 != null and gp3.gun_id == "rp7")
	gp3.queue_free()
	_player._gun()["mag"] = 0
	_player.start_reload()
	_log_check("rp7 reload starts", _player._reloading)
	_player._reload_timer = 0.01
	_player._process(0.02)
	_log_check("rp7 reload fills", _player.cur_mag() == int(_player._eff()["mag"]))
	# Rocket projectile: flies, trails smoke, explodes headless without errors.
	var rp := GunProjectile.launch(Vector3(0, 2, 0), Vector3(0, 0, -1), 55.0, 0.06, 5.5, 150.0, _player)
	root.add_child(rp)
	for i in range(10):
		rp._physics_process(0.05)
	_log_check("rp7 projectile flies", rp.global_position.z < -20.0)
	rp.explode()
	_log_check("rp7 projectile explodes", rp.is_queued_for_deletion())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5 and _phase == 0:
		_run_player_checks()
		_phase = 1
	if _frame >= 45:
		_finish()
		return true
	return false


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("ARSENAL_FULL: ", _checks.size() - fails, "/", _checks.size(), " checks passed")
	if fails > 0:
		print("ARSENAL_FULL: FAILURES PRESENT")
	quit()
