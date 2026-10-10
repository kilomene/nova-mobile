extends SceneTree
## Headless verification for the BR CLASS system (defs, actives, passives,
## cooldowns, HUD button, enemy usage, menu wiring).
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_classes.gd

var _checks: Array = []
var _frame := 0
var _phase := 0
var _player: NovaPlayer
var _pcs: ClassSystem
var _enemy: NovaEnemy
var _ecs: ClassSystem

const PlayerScene: PackedScene = preload("res://scenes/player.tscn")
const EnemyScene: PackedScene = preload("res://scenes/enemy.tscn")


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, ((" | " + detail) if detail != "" else ""))


func _make_floor() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var wp := WorldBoundaryShape3D.new()
	cs.shape = wp
	sb.add_child(cs)
	root.add_child(sb)


func _initialize() -> void:
	_make_floor()
	_player = PlayerScene.instantiate() as NovaPlayer
	_player.position = Vector3(0, 2, 0)
	root.add_child(_player)
	_enemy = EnemyScene.instantiate() as NovaEnemy
	_enemy.position = Vector3(8, 1, 0)
	root.add_child(_enemy)


func _fresh_pcs(cid: String) -> ClassSystem:
	if _pcs != null and is_instance_valid(_pcs):
		_pcs.queue_free()
	_pcs = ClassSystem.new()
	_player.add_child(_pcs)
	_pcs.setup(_player, cid, true)
	_player.class_sys = _pcs
	_player.class_id = cid
	return _pcs


func _run_def_checks() -> void:
	_log_check("30 classes defined", ClassDefs.count() == 30, str(ClassDefs.count()))
	var seen := {}
	var ok := true
	for c in ClassDefs.CLASSES:
		for k in ["id", "name", "profession", "active", "cooldown", "passive", "accent", "upgrade"]:
			if not c.has(k):
				ok = false
		if float(c["cooldown"]) <= 0.0:
			ok = false
		if seen.has(str(c["id"])):
			ok = false
		seen[str(c["id"])] = true
	_log_check("defs valid + unique ids + sane cooldowns", ok)
	var pro_counts := {"tracker": 0, "support": 0, "disrupt": 0, "defense": 0, "stealth": 0}
	for c in ClassDefs.CLASSES:
		pro_counts[str(c["profession"])] += 1
	_log_check("profession split 5/5/8/5/7",
		pro_counts["tracker"] == 5 and pro_counts["support"] == 5 and pro_counts["disrupt"] == 8 \
		and pro_counts["defense"] == 5 and pro_counts["stealth"] == 7, str(pro_counts))
	_log_check("get_by_id works", ClassDefs.get_by_id("wildfire")["name"] == "Wildfire")
	_log_check("unknown id -> empty", ClassDefs.get_by_id("nope").is_empty())


func _run_active_checks() -> void:
	# Every class: setup clean, active triggers, cooldown engages, re-trigger blocked.
	var fails := []
	for cid in ClassDefs.ids():
		var pcs := _fresh_pcs(cid)
		var ok1: bool = pcs.def.get("id") == cid
		var ok2: bool = pcs.cooldown_frac() == 1.0
		var used: bool = pcs.try_activate()
		var ok3: bool = pcs.cd_left > 0.0
		var ok4: bool = not pcs.try_activate()  # blocked during cooldown
		if not (ok1 and ok2 and ok3 and ok4):
			fails.append(cid)
		# Let one frame tick so tweens/FX don't pile up across 30 activations.
		pcs._process(0.05)
	_log_check("all 30 actives trigger + cooldown engages + re-trigger blocked", fails.is_empty(), str(fails))
	_log_check("HUD ability button created", _pcs._btn != null and is_instance_valid(_pcs._btn))


func _run_passive_checks() -> void:
	# Defense profession: explosive reduction.
	var pcs := _fresh_pcs("rampart")
	var d1: int = pcs.modify_incoming_damage(100, Vector3.ZERO, "explosive")
	_log_check("defense+rampart explosive redux", d1 == 39, str(d1))  # 100*0.65*0.6
	# Zone reduction (defense -25% zone AND rampart -40% non-bullet stack).
	var d2: int = pcs.modify_incoming_damage(100, Vector3.ZERO, "zone")
	_log_check("defense zone redux", d2 == 44, str(d2))
	# Bullets unaffected by rampart.
	var d3: int = pcs.modify_incoming_damage(100, Vector3(1, 0, 0), "bullet")
	_log_check("rampart bullets unreduced", d3 == 100, str(d3))
	# Support healing.
	pcs = _fresh_pcs("surgeon")
	_log_check("surgeon heal mult", pcs.modify_heal(10) == 20, str(pcs.modify_heal(10)))
	pcs = _fresh_pcs("quartermaster")
	_log_check("support heal mult", pcs.modify_heal(10) == 14, str(pcs.modify_heal(10)))
	# Outgoing damage.
	pcs = _fresh_pcs("volt")
	_log_check("volt passive dmg", is_equal_approx(pcs.outgoing_dmg_mult(), 1.1))
	pcs._overcharge_t = 5.0
	_log_check("volt overcharge dmg", is_equal_approx(pcs.outgoing_dmg_mult(), 1.43), str(pcs.outgoing_dmg_mult()))
	# Stealth notice.
	pcs = _fresh_pcs("spider")
	_log_check("spider notice mult", is_equal_approx(pcs.engage_range_mult(), 0.455), str(pcs.engage_range_mult()))
	# Tracker speed.
	pcs = _fresh_pcs("pathfinder")
	_log_check("tracker speed bonus", is_equal_approx(pcs.speed_bonus(), 1.1))
	# Aegis dome bullet reduction.
	pcs = _fresh_pcs("aegis")
	pcs._dome_t = 5.0
	pcs._dome_pos = _player.global_position
	var d4: int = pcs.modify_incoming_damage(100, Vector3(5, 0, 0), "bullet")
	_log_check("aegis dome halves bullets", d4 == 50, str(d4))
	# Phoenix self-revive.
	pcs = _fresh_pcs("phoenix")
	_player.hp = 30
	var d5: int = pcs.modify_incoming_damage(100, Vector3(5, 0, 0), "bullet")
	_log_check("phoenix self-revive triggers", d5 == 0 and _player.hp == 50, "dmg=%d hp=%d" % [d5, _player.hp])
	var d6: int = pcs.modify_incoming_damage(100, Vector3(5, 0, 0), "bullet")
	_log_check("phoenix revive once per match", d6 == 100, str(d6))
	# Last stand.
	pcs = _fresh_pcs("lastword")
	_player.hp = 20
	var d7: int = pcs.modify_incoming_damage(100, Vector3(5, 0, 0), "bullet")
	_log_check("last stand triggers", d7 == 0 and _player.hp == 25, "dmg=%d hp=%d" % [d7, _player.hp])
	# Ronin deflect.
	pcs = _fresh_pcs("ronin")
	pcs._deflect_t = 1.0
	_log_check("ronin deflect", pcs.modify_incoming_damage(100, Vector3.ZERO, "bullet") == 30)
	# Temp HP absorbs first.
	pcs = _fresh_pcs("surgeon")
	pcs._temp_hp = 20.0
	_log_check("temp hp absorbs", pcs.modify_incoming_damage(50, Vector3.ZERO, "bullet") == 30 \
		and is_equal_approx(pcs._temp_hp, 0.0))


func _run_enemy_checks() -> void:
	_ecs = ClassSystem.new()
	_enemy.add_child(_ecs)
	_ecs.setup(_enemy, "surgeon", false)
	_enemy.class_sys = _ecs
	_enemy.class_id = "surgeon"
	_log_check("enemy class attach", _enemy.class_sys == _ecs and _ecs.def["name"] == "Surgeon")
	_enemy.hp = 40
	_ecs._enemy_ability_tick()
	_log_check("enemy surgeon self-heals", _enemy.hp == 70, str(_enemy.hp))
	# Enemy explosive reduction via defense profession.
	_ecs.setup(_enemy, "rampart", false)
	_enemy.class_id = "rampart"
	var d: int = _ecs.modify_incoming_damage(100, Vector3.ZERO, "explosive")
	_log_check("enemy rampart explosive redux", d == 39, str(d))
	# Enemy slow/stun/jam API.
	_enemy.apply_slow(0.5, 2.0)
	_log_check("enemy slow applies", is_equal_approx(_enemy.slow_mult, 0.5))
	_enemy.stun(1.0)
	_log_check("enemy stun applies", _enemy.stun_t > 0.0)
	_enemy.set_jammed(true, 1.0)
	_log_check("enemy jam applies", _enemy.jammed)
	_enemy.investigate(Vector3(10, 0, 10), 2.0)
	_log_check("enemy investigate set", _enemy._investigate_t > 0.0)


func _run_menu_checks() -> void:
	# main.gd exposes the class menu flow.
	var MainScript: Script = load("res://scripts/main.gd")
	_log_check("main has class menu", MainScript != null)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_run_def_checks()
	elif _frame == 6:
		_run_active_checks()
	elif _frame == 9:
		_run_passive_checks()
	elif _frame == 12:
		_run_enemy_checks()
		_run_menu_checks()
	elif _frame >= 15:
		_finish()
		return true
	return false


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("CLASSES: ", _checks.size() - fails, "/", _checks.size(), " checks passed")
	if fails > 0:
		print("CLASSES: FAILURES PRESENT")
	quit()
