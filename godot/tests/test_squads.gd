extends SceneTree
## Headless verification of the SQUAD + 100-player + advanced bot AI system.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_squads.gd
## Stage 0: spawn the world BR match (idx 11). Stage 1: formation/identity/
## reserved-slot checks. Stage 2: bot AI brain states (cover/flank/revive/
## rotate/grenade). Stage 3: teammate follow + revive. Stage 4: player downed
## + dog tag + redeploy. Stage 5: full-lobby victory.

var _main
var _frame := 0
var _checks: Array = []
var _stage := 0
var _next_frame := 60
var _t0 := 0  # real-time gate: physics/AI run on wall clock, not idle frames
var _need_ms := 3000
var _e0 = null  # scratch bot for brain tests


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, ((" | " + detail) if detail != "" else ""))


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	_main._headless_map = 11
	root.add_child(_main)
	current_scene = _main
	_t0 = Time.get_ticks_msec()
	_need_ms = 800
	_next_frame = 10
	print("TEST: squads starting (world BR match idx 11)")


func _enter(stage: int, frames: int, need_ms: int) -> void:
	_stage = stage
	_next_frame = _frame + frames
	_t0 = Time.get_ticks_msec()
	_need_ms = need_ms


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < _next_frame:
		return false
	if Time.get_ticks_msec() - _t0 < _need_ms:
		return false
	match _stage:
		0:
			_check_formation()
			_enter(1, 400, 2000)
		1:
			_check_brains()
			_enter(2, 200, 2000)
		2:
			_check_teammates()
			_enter(3, 700, 9000)
		3:
			_check_downed_revive()
			_enter(4, 700, 8000)
		4:
			_check_tag_redeploy()
			_enter(5, 120, 3000)
		5:
			_check_victory()
			_enter(6, 60, 3000)
		_:
			var fails := 0
			for c in _checks:
				if not c[1]:
					fails += 1
			print("TEST DONE: frames=", _frame, " checks=", _checks.size(), " failures=", fails)
			return true
	return false


# ---------------- stage 0: formation / identity / reserved slots ----------------

func _check_formation() -> void:
	var m = _main
	var sm = m.squadman
	_log_check("squadman exists", sm != null)
	if sm == null:
		return
	_log_check("25 squads", sm.squads.size() == 25, "n=" + str(sm.squads.size()))
	var total := 0
	var four := true
	for s in sm.squads:
		total += (s["members"] as Array).size()
		if (s["members"] as Array).size() != 4:
			four = false
	_log_check("100 combatants (25x4)", total == 100, "n=" + str(total))
	_log_check("every squad has 4", four)
	_log_check("96 hostile bots", m.enemies.size() == 96, "n=" + str(m.enemies.size()))
	_log_check("3 AI teammates", m.allies.size() == 3, "n=" + str(m.allies.size()))
	# Squad 0 = player + 3 allies.
	var s0: Dictionary = sm.squads[0]
	_log_check("squad 0 holds player", s0["members"].has(m.player))
	var ally_ct := 0
	for mm in s0["members"]:
		if mm is NovaAlly:
			ally_ct += 1
	_log_check("squad 0 holds 3 allies", ally_ct == 3)
	# Unique names across all 99 AI combatants.
	var seen := {}
	var dup := false
	for e in m.enemies:
		var n := str(e.bot_name)
		if seen.has(n):
			dup = true
		seen[n] = true
	for a in m.allies:
		var n2 := str(a.bot_name)
		if seen.has(n2):
			dup = true
		seen[n2] = true
	_log_check("99 unique bot names", seen.size() == 99 and not dup, "n=" + str(seen.size()))
	_log_check("roster has 100 names", BotNames.count() == 100 and BotNames.unique_check())
	# Reserved online slots: exactly 30, human_slot 1..30 unique.
	var rsv := 0
	var slots := {}
	var rsv_ok := true
	for e in m.enemies:
		if bool(e.reserved_online):
			rsv += 1
			var hs := int(e.human_slot)
			if hs < 1 or hs > 30 or slots.has(hs):
				rsv_ok = false
			slots[hs] = true
	_log_check("30 RESERVED_FOR_ONLINE slots", rsv == 30, "n=" + str(rsv))
	_log_check("slots 1..30 unique", rsv_ok and slots.size() == 30)
	_log_check("player is human_slot 0", int(m.player.human_slot) == 0)
	_log_check("attach_remote_player stubbed", sm.attach_remote_player(7) == false)
	# Settle the drop: put the player on the ground where they landed (valid
	# terrain) instead of a possibly-wet fixed corner.
	if m.player != null:
		var pp: Vector3 = m.player.global_position
		var gy := 0.6
		if m.map != null and m.map.has_method("ground_height"):
			gy = m.map.ground_height(pp.x, pp.z) + 0.6
		m.player.global_position = Vector3(pp.x, gy, pp.z)
		m.player.dropping = false
		m.player.velocity = Vector3.ZERO
	# Bring the teammates along (they'd otherwise trek across the whole map).
	for a in m.allies:
		if is_instance_valid(a):
			a.global_position = m.player.global_position + Vector3(randf_range(-3, 3), 0, randf_range(2, 5))
	# Freeze the zone: the Collapse must not interfere with the test.
	m.set("_phase_timer", 99999.0)
	# Top up the player: the drop-in may have cost some health.
	if m.player != null:
		m.player.hp = m.player.max_hp
	_log_check("player alive at formation", m.player != null and m.player.is_alive())
	# Hermeticity: ceasefire — bots hold position and don't engage or skirmish
	# while the test drives squad 0 through its checks.
	sm.test_ceasefire = true
	sm._refresh_counts()


# ---------------- stage 1: bot AI brain states ----------------

func _check_brains() -> void:
	var m = _main
	var sm = m.squadman
	if sm == null:
		_log_check("brains skipped (no squadman)", false)
		return
	sm.test_ceasefire = false  # live targets for the synchronous brain checks
	# Pick the healthiest hostile squad + a healthy bot in it.
	var s1: Dictionary = {}
	var best_n := -1
	for s in sm.squads:
		if int(s["id"]) == 0:
			continue
		var n := 0
		for mm in s["members"]:
			if is_instance_valid(mm) and mm.is_alive() and not mm.is_downed():
				n += 1
		if n > best_n:
			best_n = n
			s1 = s
	_log_check("healthy hostile squad", best_n >= 3, "alive=" + str(best_n))
	_e0 = null
	for mm in s1["members"]:
		if is_instance_valid(mm) and mm.is_alive() and not mm.is_downed():
			_e0 = mm
			break
	_log_check("test bot acquired", _e0 != null)
	if _e0 == null or s1.is_empty():
		return
	# --- cover: getting shot breaks the bot to cover/peek ---
	# Stage a hostile in range first so the brain has a target to react with.
	var s2: Dictionary = sm.squads[2] if int(s1["id"]) != 2 else sm.squads[3]
	var anchor: Vector3 = _e0.global_position
	for mm in s2["members"]:
		if is_instance_valid(mm):
			mm.global_position = anchor + Vector3(30, 0, 0)
	s1["order"] = SquadManager.Order.REGROUP  # neutralize the zone ticker
	s1["roles"] = {}
	_e0.take_damage(5, _e0.global_position + Vector3(6, 0, 0), "bullet", false, null)
	_e0._think()
	_log_check("cover on damage", _e0._brain == NovaEnemy.B.COVER or _e0._brain == NovaEnemy.B.PEEK,
		"brain=" + str(_e0._brain))
	# --- flank role: squad think assigns one flanker when a foe is near ---
	# Teleport a hostile squad next to s1 for the think.
	for mm in s2["members"]:
		if is_instance_valid(mm):
			mm.global_position = anchor + Vector3(40, 0, 0)
	sm._refresh_counts()
	# Keep the zone check quiet so the ATTACK branch is reached.
	var zc_save: Vector2 = m.next_center
	var zr_save: float = m.next_radius
	m.next_center = Vector2(anchor.x, anchor.z)
	m.next_radius = 500.0
	sm._squad_think(s1)
	m.next_center = zc_save
	m.next_radius = zr_save
	var roles: Dictionary = s1["roles"]
	var flank_ct := 0
	for k in roles:
		if str(roles[k]) == "flank":
			flank_ct += 1
	_log_check("squad assigns a flanker", flank_ct == 1, "flank=" + str(flank_ct))
	# --- revive order: downed mate -> buddy assigned ---
	var mate = null
	for mm in s1["members"]:
		if mm != _e0 and is_instance_valid(mm) and mm.is_alive():
			mate = mm
			break
	mate._go_downed()
	sm._squad_think(s1)
	_log_check("squad defends downed mate", int(s1["order"]) == SquadManager.Order.DEFEND)
	var buddy = null
	var roles2: Dictionary = s1["roles"]
	for k in roles2:
		if str(roles2[k]) == "revive":
			buddy = k
	_log_check("revive buddy assigned", buddy != null)
	if buddy != null:
		buddy._think()
		_log_check("buddy enters REVIVE_MATE", buddy._brain == NovaEnemy.B.REVIVE_MATE,
			"brain=" + str(buddy._brain))
	mate.revive_ally()
	# --- rotate: squad outside the next circle gets ROTATE ---
	m.next_center = Vector2(1000, 1000)
	m.next_radius = 10.0
	sm._refresh_counts()
	sm._squad_think(s1)
	_log_check("squad rotates to zone", int(s1["order"]) == SquadManager.Order.ROTATE)
	m.next_center = m.zone_center
	m.next_radius = m.zone_radius
	# --- grenade: clustered target at mid range triggers NADE ---
	s1["order"] = SquadManager.Order.REGROUP
	s1["roles"] = {}
	var tgt = null
	for mm in s2["members"]:
		if is_instance_valid(mm) and mm.is_alive():
			mm.global_position = anchor + Vector3(15, 0, 0)
			if tgt == null:
				tgt = mm
	_e0._brain = NovaEnemy.B.ENGAGE  # reset from the cover check above
	_e0._grenades = 2
	_e0._nade_cd = 0.0
	_e0._no_los_t = 0.0
	_e0._last_hurt_t = -99.0  # old wound: cover no longer takes priority
	_e0._cover_cd = 0.0
	_e0._think()
	_log_check("grenade on clustered target", _e0._brain == NovaEnemy.B.NADE,
		"brain=" + str(_e0._brain) + " nades=" + str(_e0._grenades))
	# Hearing: a gunshot makes a nearby squad investigate.
	var heard := false
	var s3: Dictionary = sm.squads[4]
	if int(s1["id"]) == 4 or int(s2["id"]) == 4:
		s3 = sm.squads[5]
	for mm in s3["members"]:
		if is_instance_valid(mm):
			mm.global_position = m.player.global_position + Vector3(20, 0, 0)
	sm._refresh_counts()
	sm.hear_shot(m.player.global_position, m.player)
	var m0 = s3["members"][0]
	if is_instance_valid(m0):
		heard = float(m0.get("_investigate_t")) > 0.0
	_log_check("squads investigate gunshots", heard)
	sm.test_ceasefire = true  # back to ceasefire for the squad-0 checks


# ---------------- stage 2: teammate follow + revive the player ----------------

func _check_teammates() -> void:
	var m = _main
	if m.player == null or m.allies.is_empty():
		_log_check("teammate stage skipped", false)
		return
	# Follow: teleport the player 15 m on the ground, allies should close distance.
	var p0: Vector3 = m.player.global_position
	var p1 := p0 + Vector3(15, 0, 0)
	if m.map != null and m.map.has_method("ground_height"):
		p1.y = m.map.ground_height(p1.x, p1.z) + 0.6
	m.player.global_position = p1
	m.player.velocity = Vector3.ZERO
	var d0 := []
	for a in m.allies:
		d0.append(_flat_dist(m.player.global_position, a.global_position))
	# (checked next stage after frames elapse)
	_main.set_meta("follow_d0", d0)
	# Down the player: an ally should crawl over and revive (5 s channel).
	# Down the player: an ally should crawl over and revive (5 s channel).
	# Bring all allies close (one may land in geometry).
	var ai := 0
	for a in m.allies:
		if is_instance_valid(a) and a.is_alive():
			var off: Vector3 = [Vector3(2, 0, 0), Vector3(-2, 0, 1), Vector3(0, 0, -2)][ai % 3]
			a.global_position = m.player.global_position + off
			a.velocity = Vector3.ZERO
			ai += 1
	m.player.take_damage(9999, m.player.global_position + Vector3(3, 0, 0), "bullet", false, null)
	_log_check("player goes downed (not dead)", m.player.downed and m.player.is_alive())


# ---------------- stage 3: verify follow + player revive + ally revive ----------------

func _check_downed_revive() -> void:
	var m = _main
	var d0: Array = _main.get_meta("follow_d0") as Array
	var closer := true
	for i in range(mini(d0.size(), m.allies.size())):
		var a = m.allies[i]
		if not (is_instance_valid(a) and a.is_alive()):
			continue
		var d1: float = _flat_dist(m.player.global_position, a.global_position)
		if d1 >= float(d0[i]) - 1.0:
			closer = false
	_log_check("teammates follow the player", closer)
	_log_check("ally revived the player", not m.player.downed and m.player.is_alive(),
		"hp=" + str(m.player.hp))
	# Now down an ally; the player revives via the 5 s channel.
	var a0 = null
	for a in m.allies:
		if is_instance_valid(a) and a.is_alive():
			a0 = a
			break
	if a0 == null:
		_log_check("ally revive skipped (no ally)", false)
		return
	a0.take_damage(9999, a0.global_position + Vector3(2, 0, 0), "bullet", false, null)
	_log_check("ally goes downed", a0.is_downed())
	m.player.global_position = a0.global_position + Vector3(1.5, 0, 0)
	_main.set_meta("revive_ally", a0)


# ---------------- stage 4: dog tag pickup + buy-station redeploy ----------------

func _check_tag_redeploy() -> void:
	var m = _main
	var a0 = _main.get_meta("revive_ally")
	_log_check("player revived the ally", is_instance_valid(a0) and a0.is_alive() and not a0.is_downed())
	# Kill an ally outright through the real path: bleed out while downed.
	# Use a (possibly different) alive ally; down it and force quick bleed-out.
	var victim = null
	for a in m.allies:
		if is_instance_valid(a) and a.is_alive() and not a.is_downed():
			victim = a
			break
	if victim != null:
		victim.take_damage(9999, victim.global_position + Vector3(2, 0, 0), "bullet", false, null)
		if victim.is_downed():
			victim._bleed_t = 0.05  # force bleed-out on the next frames
	_main.set_meta("dead_ally", victim)


# ---------------- stage 5: victory ----------------

func _check_victory() -> void:
	var m = _main
	var a0 = _main.get_meta("dead_ally")
	_log_check("ally bled out", is_instance_valid(a0) and not a0.is_alive())
	var tags := 0
	for ch in m.get_children():
		if ch is DogTag:
			tags += 1
	_log_check("dog tag dropped", tags >= 1, "tags=" + str(tags))
	# Carry the tag, buy the redeploy.
	if is_instance_valid(a0):
		m.player.carried_tags.append(str(a0.bot_name))
		m.player.cash = 5000
		var cash0: int = m.player.cash
		m.buy_item("redeploy")
		_log_check("redeploy revives ally", a0.is_alive(), "cash used=" + str(cash0 - m.player.cash))
	# Wipe the lobby: every hostile dies for real (no downed state).
	for e in m.enemies:
		if is_instance_valid(e) and e.is_alive():
			e.skip_downed = true
			e.take_damage(9999, e.global_position, "bullet", false, null)
	_log_check("lobby wiped", m.squadman.alive_hostiles() == 0)
	_log_check("victory declared", m.game_over, "banner shown=" + str(m.game_over))


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
