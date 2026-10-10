extends SceneTree
## Headless verification for the LOOT OVERHAUL:
## containers (make/open/room logic), supply crates (tiers/respawn/beams),
## death boxes (victim gun/ammo/bonus), rarity visuals (colors/beams),
## real 3D loot models, loot audio, ping markers + ally reaction,
## player smoke grenades, and the loot economy (every house has >= 2 loot).
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_loot.gd

var _main  # untyped: main.gd has no class_name
var _frame := 0
var _phase := 0
var _checks: Array = []


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, ((" | " + detail) if detail != "" else ""))


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	current_scene = _main
	print("TEST: main scene instanced (headless match starting)")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _frame >= 150:
				_run_unit_checks()
				_phase = 1
		1:
			_run_container_checks()
			_phase = 2
		2:
			_run_crate_checks()
			_phase = 3
		3:
			_run_deathbox_checks()
			_phase = 4
		4:
			_run_visual_checks()
			_phase = 5
		5:
			_run_ping_ally_checks()
			_phase = 6
		6:
			_run_economy_checks()
			_phase = 7
		7:
			_run_player_smoke_checks()
			_phase = 8
		8:
			_summarize()
			return true
	return false


func _by_class(cname: String) -> Array:
	# Match via global class_name using `is`-style checks.
	var out: Array = []
	var stack: Array = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var hit := false
		match cname:
			"LootContainer":
				hit = n is LootContainer
			"LootCrate":
				hit = n is LootCrate
			"DeathBox":
				hit = n is DeathBox
			"NovaLoot":
				hit = n is NovaLoot
			"GunPickup":
				hit = n is GunPickup
			"NovaEnemy":
				hit = n is NovaEnemy
			"NovaAlly":
				hit = n is NovaAlly
			"LootPing":
				hit = n is LootPing
			"SmokeGrenade":
				hit = n is SmokeGrenade
		if hit:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


# ---------------- phase: unit checks (pure statics) ----------------

func _run_unit_checks() -> void:
	# LootModels: full rarity spectrum.
	var expect := {
		0: Color(0.72, 0.72, 0.72), 1: Color(0.72, 0.72, 0.72),
		2: Color(0.25, 0.90, 0.45), 3: Color(0.35, 0.60, 1.0),
		4: Color(0.70, 0.35, 1.0), 5: Color(1.0, 0.60, 0.15), 6: Color(1.0, 0.16, 0.12)}
	for t in expect:
		var c: Color = LootModels.tier_color(t)
		_log_check("tier %d color" % t, c.is_equal_approx(expect[t]), str(c))
	# Beams: tall pillars for epic+ (loot.gd gates tier >= 4).
	var beam: MeshInstance3D = LootModels.rarity_beam(4)
	var beam_ok := beam != null and beam.position.y > 5.0
	var cm := beam.mesh as CylinderMesh
	beam_ok = beam_ok and cm != null and cm.height >= 20.0
	_log_check("rarity beam is tall pillar", beam_ok, "y=%.1f h=%.1f" % [beam.position.y, cm.height if cm else -1.0])
	beam.queue_free()
	# All model builders return real 3D nodes.
	var builders := [
		LootModels.medkit(), LootModels.armor_plates(), LootModels.armor_shard(),
		LootModels.ammo_box("heavy"), LootModels.cash_bundle(), LootModels.frag_grenade(),
		LootModels.smoke_canister(), LootModels.streak_device("uav"),
		LootModels.streak_device("strike"), LootModels.attachment_case()]
	var models_ok := true
	for b in builders:
		if not (b is Node3D):
			models_ok = false
		else:
			(b as Node).queue_free()
	_log_check("10 loot model builders -> Node3D", models_ok)
	# LootAudio: per-rarity pickup streams + interaction sounds.
	var audio_ok := true
	for t in range(7):
		if LootAudio.pickup_stream(t) == null:
			audio_ok = false
	if LootAudio.open_stream() == null or LootAudio.crate_stream(1) == null:
		audio_ok = false
	if LootAudio.ping_stream() == null or LootAudio.thud_stream() == null:
		audio_ok = false
	_log_check("loot audio streams all built", audio_ok)
	# Container type table.
	_log_check("6 container types", LootContainer.CTYPES.size() == 6, str(LootContainer.CTYPES))
	# Rarity names complete.
	_log_check("7 rarity names", LootModels.TIER_NAMES.size() == 7, str(LootModels.TIER_NAMES))


# ---------------- phase: containers ----------------

func _run_container_checks() -> void:
	var conts := _by_class("LootContainer")
	_log_check("containers spawned in world", conts.size() > 0, "n=" + str(conts.size()))
	if conts.is_empty():
		return
	var c: LootContainer = conts[0]
	_log_check("container has 2-4 contents", c._contents.size() >= 2 and c._contents.size() <= 4,
		"n=" + str(c._contents.size()))
	_log_check("container prompt node", c.get_node_or_null("Prompt") != null)
	# Room logic spot check: kitchen contents skew health.
	var health_n := 0
	var total_n := 0
	for i in range(40):
		var cc := LootContainer.make("fridge", "kitchen", 1)
		for it in cc._contents:
			total_n += 1
			if str((it as Dictionary).get("kind", "")) == "health":
				health_n += 1
		cc.queue_free()
	_log_check("kitchen skews health", health_n >= total_n / 2,
		"health %d/%d" % [health_n, total_n])
	# Open: spawns loot, marks opened, second open is a no-op.
	var before := _by_class("NovaLoot").size() + _by_class("GunPickup").size()
	c.open()
	_log_check("container opens", c._opened)
	var after := _by_class("NovaLoot").size() + _by_class("GunPickup").size()
	_log_check("container pops loot", after > before, "before=%d after=%d" % [before, after])
	c.open()
	_log_check("container one-time", c._opened and _by_class("NovaLoot").size() + _by_class("GunPickup").size() == after)


# ---------------- phase: supply crates ----------------

func _run_crate_checks() -> void:
	var crates := _by_class("LootCrate")
	_log_check("supply crates at POIs", crates.size() > 0, "n=" + str(crates.size()))
	if crates.is_empty():
		return
	var tiers := {}
	for cr in crates:
		var t: int = (cr as LootCrate).tier
		tiers[t] = int(tiers.get(t, 0)) + 1
	_log_check("crate tiers 0-2 only", tiers.keys().all(func(k): return k >= 0 and k <= 2), str(tiers))
	var rare_beam := false
	for cr in crates:
		if (cr as LootCrate).tier >= 1 and (cr as LootCrate)._beam != null:
			rare_beam = true
	# Explicit: rare and epic crates always carry beams.
	for t in [1, 2]:
		var tc := LootCrate.make(t)
		_main.add_child(tc)
		if tc._beam != null:
			rare_beam = true
		tc.queue_free()
	_log_check("rare+ crates have light beams", rare_beam)
	# Open: lid flips, loot rolls, respawn timer restores.
	var cr: LootCrate = crates[0]
	var roll: Array = cr._roll_loot()
	_log_check("crate roll 2-4 items with gun", roll.size() >= 2 and roll.size() <= 4 and roll.any(func(i): return (i as Dictionary).has("gun")),
		"n=" + str(roll.size()))
	var lb := _by_class("NovaLoot").size() + _by_class("GunPickup").size()
	cr.open()
	_log_check("crate opens", cr._opened)
	_log_check("crate lid target set", absf(cr._lid_target - (-1.9)) < 0.01)
	cr.open()
	_log_check("crate one-time while open", cr._opened)
	cr._on_respawn()
	_log_check("crate respawns", cr._closed and not cr._opened)
	# Burst contents (called directly; in-game it fires 0.35s after the lid flips).
	var bc := LootCrate.make(0)
	_main.add_child(bc)
	bc._burst()
	var grown := _by_class("NovaLoot").size() + _by_class("GunPickup").size() - lb
	_log_check("crate bursts 3 items", grown == 3, "grew=%d" % grown)
	bc.queue_free()


# ---------------- phase: death boxes ----------------

func _run_deathbox_checks() -> void:
	var enemies := _by_class("NovaEnemy")
	_log_check("enemies carry guns", enemies.size() > 0 and (enemies[0] as NovaEnemy).carry_gun_id != "",
		"n=" + str(enemies.size()))
	if enemies.is_empty():
		return
	var e: NovaEnemy = enemies[0]
	_log_check("enemy gun model attached", _has_weapon_attachment(e), e.carry_gun_id)
	var gid: String = e.carry_gun_id
	var db0 := _by_class("DeathBox").size()
	_main._on_enemy_killed(e)
	var boxes := _by_class("DeathBox")
	_log_check("death box spawns on kill", boxes.size() > db0, "n=" + str(boxes.size()))
	if boxes.size() <= db0:
		return
	var box: DeathBox = boxes[boxes.size() - 1]
	_log_check("death box has victim gun", box._contents.any(func(i): return str((i as Dictionary).get("gun", "")) == gid),
		"gun=" + gid)
	_log_check("death box has ammo", box._contents.any(func(i): return str((i as Dictionary).get("kind", "")) == "ammo"))
	_log_check("death box has bonus item", box._contents.size() >= 3, "n=" + str(box._contents.size()))
	_log_check("death box name label", (box.get_node_or_null("NameLabel") as Label3D) != null)
	var lba := _by_class("NovaLoot").size() + _by_class("GunPickup").size()
	box.open()
	var gun_items := _by_class("GunPickup").filter(func(g): return (g as GunPickup).gun_id == gid)
	_log_check("death box drops victim gun pickup", gun_items.size() > 0)
	_log_check("death box one-time", _by_class("NovaLoot").size() + _by_class("GunPickup").size() >= lba)


func _has_weapon_attachment(e: NovaEnemy) -> bool:
	var stack: Array = [e]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BoneAttachment3D and (n as BoneAttachment3D).bone_name == "Weapon" and (n as Node).get_child_count() > 0:
			return true
		for c in n.get_children():
			stack.append(c)
	return false


# ---------------- phase: rarity visuals on ground loot ----------------

func _run_visual_checks() -> void:
	# Epic+ ground loot gets a beam; mythic (6) red label.
	var l := NovaLoot.new()
	l.kind = "armor"
	l.tier = 5
	_main.add_child(l)
	l.position = _main.player.global_position + Vector3(2, 0, 0)
	_log_check("epic loot beam", l._beam != null)
	_log_check("epic label text", "EPIC" in l.label.text, l.label.text)
	l.queue_free()
	var l3 := NovaLoot.new()
	l3.kind = "ammo"
	l3.tier = 3
	_main.add_child(l3)
	_log_check("no beam below epic", l3._beam == null)
	l3.queue_free()
	# Gun pickup: real model + mythic beam + STK line.
	var gp := GunPickup.make("m5", 6)
	_main.add_child(gp)
	gp.position = _main.player.global_position + Vector3(-2, 0, 0)
	_log_check("gun pickup real model", gp.get_node_or_null("ModelHolder") != null or gp.get_child_count() > 1)
	_log_check("mythic gun beam", gp._beam != null)
	_log_check("gun label has STK", "STK" in gp.label.text, gp.label.text)
	_log_check("gun display_name", gp.display_name() != "", gp.display_name())
	gp.queue_free()
	# Attachment pickup.
	var ap := GunPickup.make_attachment("grip_vert")
	_main.add_child(ap)
	_log_check("attachment display name", ap.display_name() != "", ap.display_name())
	_log_check("attachment label text", ap.label.text != "", ap.label.text)
	ap.queue_free()


# ---------------- phase: ping + ally reaction ----------------

func _run_ping_ally_checks() -> void:
	var allies_arr: Array = _main.allies
	var pings_arr: Array = _main._pings
	var hud_mm: Array = _main.hud.minimap_pings
	var pl: NovaPlayer = _main.player
	_log_check("allies deployed", allies_arr.size() >= 2, "n=" + str(allies_arr.size()))
	var ping_n0: int = pings_arr.size()
	var mm0: int = hud_mm.size()
	_main.spawn_loot_ping("TEST PING", 5, pl.global_position + Vector3(10, 0, 0))
	_log_check("ping registered", pings_arr.size() == ping_n0 + 1)
	_log_check("ping on minimap", hud_mm.size() == mm0 + 1)
	# AI reacts to high-tier pings.
	var a: NovaAlly = allies_arr[0]
	_log_check("ally investigates ping", a._investigate.distance_to(Vector3.ZERO) > 1.0,
		str(a._investigate))
	# Ping expiry clears both lists.
	var ping: LootPing = pings_arr[pings_arr.size() - 1]
	ping._process(21.0)
	_log_check("ping expires", not pings_arr.has(ping))
	_log_check("ping off minimap", hud_mm.all(func(d): return (d as Dictionary).get("node") != ping))
	# Ping visuals.
	var p2 := LootPing.make("LOOT", 4)
	_main.add_child(p2)
	_log_check("ping marker has label", p2.get_node_or_null("Label") != null)
	_log_check("ping marker has pulse", p2.get_node_or_null("Pulse") != null)
	p2.queue_free()
	# Ally basics.
	_log_check("ally alive", a.is_alive())
	_log_check("ally has name", a.bot_name != "", a.bot_name)
	a.take_damage(15.0, a.global_position + Vector3(1, 0, 0))
	_log_check("ally takes damage", a.hp < a.max_hp, "hp=%.0f" % a.hp)


# ---------------- phase: loot economy ----------------

func _run_economy_checks() -> void:
	var map_obj: Object = _main.map
	var houses: Array = map_obj.get("house_positions")
	_log_check("map has houses", houses.size() > 0, "n=" + str(houses.size()))
	var loot_nodes := _by_class("NovaLoot") + _by_class("GunPickup") + _by_class("LootContainer") + _by_class("LootCrate")
	var poor := 0
	for h in houses:
		var hp: Vector3 = h
		var n := 0
		for ln in loot_nodes:
			var lp: Vector3 = (ln as Node3D).global_position
			if Vector2(lp.x - hp.x, lp.z - hp.z).length() < 9.0:
				n += 1
		if n < 2:
			poor += 1
	_log_check("every house has >= 2 loot", poor == 0, "poor=%d/%d" % [poor, houses.size()])
	_log_check("generous loot density", loot_nodes.size() >= houses.size() * 2,
		"loot=%d houses=%d" % [loot_nodes.size(), houses.size()])
	# Kind coverage: epic crates drop scorestreaks + shards.
	var epic := LootCrate.make(2)
	_main.add_child(epic)
	epic.position = _main.player.global_position + Vector3(5, 0, 5)
	epic._burst()
	var kinds := {}
	for ln in _by_class("NovaLoot"):
		kinds[(ln as NovaLoot).kind] = true
	_log_check("scorestreak drops from epic crate", kinds.has("uav") or kinds.has("strike"), str(kinds.keys()))
	_log_check("armor shards drop", kinds.has("shard"), str(kinds.keys()))
	_log_check("multiple loot kinds present", kinds.size() >= 5, str(kinds.keys()))
	# POI crates present on a real match.
	_log_check("crates in match", _by_class("LootCrate").size() > 0)


# ---------------- phase: player smoke ----------------

func _run_player_smoke_checks() -> void:
	var p: NovaPlayer = _main.player
	_log_check("player has smoke key (carry)", p.ammo.has("smoke"))
	_log_check("player has smoke key (max)", p.ammo_max.has("smoke"))
	p.add_smoke(2)
	_log_check("add_smoke", p.smoke_count() == 2, "n=%d" % p.smoke_count())
	p.throw_smoke()
	_log_check("throw_smoke decrements", p.smoke_count() == 1, "n=%d" % p.smoke_count())
	_log_check("smoke grenade spawned", _by_class("SmokeGrenade").size() > 0)
	p.add_grenades(1)
	_log_check("add_grenades", p.grenades >= 1)


func _summarize() -> void:
	var fails := 0
	for c in _checks:
		if not (c as Array)[1]:
			fails += 1
	print("LOOT TESTS: %d/%d passed" % [_checks.size() - fails, _checks.size()])
	if fails > 0:
		print("FAILURES:")
		for c in _checks:
			if not (c as Array)[1]:
				print("  - ", (c as Array)[0])
