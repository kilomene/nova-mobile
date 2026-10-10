class_name SquadManager
extends Node
## NOVA Mobile: 100-combatant battle royale — 25 squads x 4.
## Squad tactics (focus fire, flanking, revives, zone rotation), throttled
## hostile targeting, and abstract resolution of far-away squad fights so the
## lobby keeps shrinking even where the player can't see.
##
## ONLINE ROADMAP (Phase 2 — dedicated server + realtime sync):
##   human_slot 0 = local player (NovaPlayer).
##   human_slot 1..30 = RESERVED_FOR_ONLINE. These 30 slots are
##   architecturally reserved for real network players. They run as AI today
##   (reserved_online=true) so every match is a full 100 combatants.
##   attach_remote_player(slot) is the server hook: the dedicated server will
##   claim a slot and drive that combatant instead of the AI.

const SQUAD_SIZE := 4
const SQUAD_COUNT := 25
const RESERVED_COUNT := 30  # human_slot 1..30

const SQUAD_NAMES := ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO",
	"FOXTROT", "GOLF", "HOTEL", "INDIA", "JULIET", "KILO", "LIMA",
	"MIKE", "NOVEMBER", "OSCAR", "PAPA", "QUEBEC", "ROMEO", "SIERRA",
	"TANGO", "UNIFORM", "VICTOR", "WHISKEY", "XRAY", "YANKEE"]

enum Order { REGROUP, ATTACK, DEFEND, ROTATE }

var main = null  # main.gd
var squads: Array = []  # {id,name,color,members,alive_n,centroid,order,order_pos,focus,roles}
var combatants: Array = []  # every NovaEnemy + NovaAlly + the NovaPlayer
var rng := RandomNumberGenerator.new()

var _squad_tick_i := 0
var _squad_tick_t := 0.0
var _abstract_t := 6.0
var _target_cache := {}  # bot -> {"tgt": combatant, "t": sec}
var _next_reserved := 1  # human_slot allocator for RESERVED_FOR_ONLINE
var test_ceasefire := false  # test hook: no target acquisition, no abstract skirmishes


## Which (squad_id, slot) pairs are reserved for real online players.
## Squad 0 is the local player's squad (player + 3 AI teammates).
## Squads 1..6 reserve 2 slots each (12); squads 7..24 reserve 1 each (18).
static func is_reserved_slot(squad_id: int, slot: int) -> bool:
	if squad_id == 0:
		return false
	if squad_id >= 1 and squad_id <= 6:
		return slot <= 1
	return slot == 0


## Build the 25 squads from main's spawned combatants.
## main.enemies: 96 hostile bots. main.allies: 3 teammates. main.player: you.
func organize(main_ref) -> void:
	main = main_ref
	rng.seed = 424242 + randi() % 100000
	combatants.clear()
	squads.clear()
	_target_cache.clear()
	_next_reserved = 1
	var used_names := {}
	# Squad 0: the local player + 3 AI teammates.
	var s0 := _new_squad(0)
	var p = main.player
	p.set("squad_id", 0)
	p.set("human_slot", 0)
	p.set("reserved_online", false)
	s0["members"].append(p)
	combatants.append(p)
	for i in range(main.allies.size()):
		var a = main.allies[i]
		a.set("squad_id", 0)
		a.set("bot_name", BotNames.pick(rng, used_names))
		a.set("human_slot", -1)
		a.set("reserved_online", false)
		a.set("callsign", str(a.get("bot_name")))
		a.set("squadman", self)
		s0["members"].append(a)
		combatants.append(a)
	squads.append(s0)
	# Squads 1..24: 4 hostile bots each.
	var ei := 0
	for sid in range(1, SQUAD_COUNT):
		var s := _new_squad(sid)
		for slot in range(SQUAD_SIZE):
			if ei >= main.enemies.size():
				break
			var e = main.enemies[ei]
			ei += 1
			e.set("squad_id", sid)
			e.set("bot_name", BotNames.pick(rng, used_names))
			if is_reserved_slot(sid, slot):
				e.set("reserved_online", true)
				e.set("human_slot", _next_reserved)
				_next_reserved += 1
			else:
				e.set("reserved_online", false)
				e.set("human_slot", -1)
			e.set("squadman", self)
			s["members"].append(e)
			combatants.append(e)
		squads.append(s)
	_refresh_counts()


func _new_squad(sid: int) -> Dictionary:
	var hue := float(sid) / float(SQUAD_COUNT)
	return {
		"id": sid, "name": SQUAD_NAMES[sid % SQUAD_NAMES.size()],
		"color": Color.from_hsv(hue, 0.65, 1.0),
		"members": [], "alive_n": 0, "centroid": Vector3.ZERO,
		"order": Order.REGROUP, "order_pos": Vector3.ZERO,
		"focus": null, "roles": {},
	}


func _refresh_counts() -> void:
	for s in squads:
		var n := 0
		var c := Vector3.ZERO
		for m in s["members"]:
			if is_instance_valid(m) and m.is_alive():
				n += 1
				c += (m as Node3D).global_position
		s["alive_n"] = n
		s["centroid"] = c / maxf(float(n), 1.0)


func squad_of(c) -> Dictionary:
	var sid := int(c.get("squad_id"))
	if sid >= 0 and sid < squads.size():
		return squads[sid]
	return {}


func has_living_mate(bot) -> bool:
	var s := squad_of(bot)
	if s.is_empty():
		return false
	for m in s["members"]:
		if m != bot and is_instance_valid(m) and m.is_alive() and not m.is_downed():
			return true
	return false


func living_mates(bot) -> Array:
	var out := []
	var s := squad_of(bot)
	if s.is_empty():
		return out
	for m in s["members"]:
		if m != bot and is_instance_valid(m) and m.is_alive():
			out.append(m)
	return out


func downed_mate(bot):
	for m in living_mates(bot):
		if m.is_downed():
			return m
	return null


## Throttled nearest-hostile lookup (0.6 s cache per bot). No aimbot data:
## callers must still pass a line-of-sight check before engaging.
func nearest_hostile(bot, max_dist := 45.0):
	if test_ceasefire:
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if _target_cache.has(bot):
		var c: Dictionary = _target_cache[bot]
		var cc = c.get("tgt")
		if now - float(c.get("t", 0.0)) < 0.6 and is_instance_valid(cc) \
				and cc.is_alive() and _hostile(bot, cc):
			return cc
	var bs := int(bot.get("squad_id"))
	var bp: Vector3 = (bot as Node3D).global_position
	var best = null
	var best_d := max_dist
	for o in combatants:
		if o == bot or not is_instance_valid(o):
			continue
		if not o.is_alive():
			continue
		if int(o.get("squad_id")) == bs:
			continue
		if o.get("dropping") == true:
			continue  # don't shoot parachuters on the way in
		var dd: float = Vector2(
			(o as Node3D).global_position.x - bp.x,
			(o as Node3D).global_position.z - bp.z).length()
		if dd < best_d:
			best_d = dd
			best = o
	_target_cache[bot] = {"tgt": best, "t": now}
	return best


func _hostile(a, b) -> bool:
	return int(a.get("squad_id")) != int(b.get("squad_id"))


func alive_hostiles() -> int:
	var n := 0
	for c in combatants:
		if is_instance_valid(c) and c.is_alive() and int(c.get("squad_id")) != 0:
			n += 1
	return n


func alive_squads() -> int:
	var n := 0
	for s in squads:
		if int(s["alive_n"]) > 0:
			n += 1
	return n


func on_combatant_down(_c) -> void:
	_refresh_counts()


func on_combatant_dead(c) -> void:
	_target_cache.erase(c)
	_refresh_counts()
	# Victory: no hostile combatant left standing.
	if main != null and main.has_method("_squads_victory_check"):
		main._squads_victory_check()


## Gunfire attracts nearby squads (hearing, not wallhack: they investigate
## the position, they don't gain targets).
func hear_shot(pos: Vector3, shooter) -> void:
	var ssid := int(shooter.get("squad_id"))
	for s in squads:
		if int(s["id"]) == ssid:
			continue
		var d: float = Vector2(s["centroid"].x - pos.x, s["centroid"].z - pos.z).length()
		if d < 55.0:
			for m in s["members"]:
				if is_instance_valid(m) and m.is_alive() and m.has_method("investigate"):
					m.investigate(pos, 6.0)


func _process(delta: float) -> void:
	if main == null or bool(main.get("game_over")):
		return
	_squad_tick_t -= delta
	if _squad_tick_t <= 0.0:
		_squad_tick_t = 0.5
		_squad_think_tick()
	_abstract_t -= delta
	if _abstract_t <= 0.0:
		_abstract_t = 4.0
		_abstract_tick()


## Staggered squad brain: a few squads per tick, round-robin.
func _squad_think_tick() -> void:
	_refresh_counts()
	var n := squads.size()
	for k in range(5):
		var s: Dictionary = squads[(_squad_tick_i + k) % n]
		_squad_think(s)
	_squad_tick_i = (_squad_tick_i + 5) % n


func _squad_think(s: Dictionary) -> void:
	var alive := []
	for m in s["members"]:
		if is_instance_valid(m) and m.is_alive() and not m.is_downed():
			alive.append(m)
	if alive.is_empty():
		return
	var centroid := Vector3.ZERO
	for m in alive:
		centroid += (m as Node3D).global_position
	centroid /= float(alive.size())
	s["centroid"] = centroid
	var sid := int(s["id"])
	# 1) Downed mate -> nearest free buddy revives, squad defends.
	var dm = null
	for m in s["members"]:
		if is_instance_valid(m) and m.is_alive() and m.is_downed():
			dm = m
			break
	if dm != null and alive.size() >= 2:
		var buddy = null
		var bd := 1e9
		for m in alive:
			var d: float = ((m as Node3D).global_position - (dm as Node3D).global_position).length()
			if d < bd:
				bd = d
				buddy = m
		s["order"] = Order.DEFEND
		s["roles"] = {buddy: "revive"}
		return
	# 2) Zone: rotate early if the centroid is outside the next circle.
	var zc: Vector2 = main.next_center
	var zr: float = main.next_radius
	var flat := Vector2(centroid.x, centroid.z)
	if flat.distance_to(zc) > zr and sid != 0:
		s["order"] = Order.ROTATE
		var to_in: Vector2 = (zc - flat).normalized()
		s["order_pos"] = Vector3(flat.x + to_in.x * 25.0, 0, flat.y + to_in.y * 25.0)
		s["roles"] = {}
		return
	# 3) Nearest hostile squad -> attack with focus fire + a flanker.
	var foe = null
	var foe_d := 1e9
	for o in squads:
		if int(o["id"]) == sid or int(o["alive_n"]) <= 0:
			continue
		var d: float = Vector2(o["centroid"].x - centroid.x, o["centroid"].z - centroid.z).length()
		if d < foe_d:
			foe_d = d
			foe = o
	if foe != null and foe_d < 75.0:
		s["order"] = Order.ATTACK
		s["focus"] = foe
		# Flanker: the member with the best lateral offset vs the foe.
		var fdir: Vector2 = (Vector2(foe["centroid"].x, foe["centroid"].z) - flat).normalized()
		var flank = null
		var best_lat := -1.0
		for m in alive:
			var mp: Vector3 = (m as Node3D).global_position
			var rel := Vector2(mp.x - centroid.x, mp.z - centroid.z)
			var lat: float = absf(rel.x * -fdir.y + rel.y * fdir.x)
			if lat > best_lat:
				best_lat = lat
				flank = m
		var roles := {}
		for m in alive:
			roles[m] = "flank" if m == flank and alive.size() >= 3 else "suppress"
		s["roles"] = roles
		return
	# 4) Default: regroup / hold.
	s["order"] = Order.REGROUP
	s["order_pos"] = centroid
	s["roles"] = {}


## Abstract resolution for far-away squad fights: the lobby must keep
## shrinking even where the player can't see. Never touches squad 0.
func _abstract_tick() -> void:
	if test_ceasefire:
		return
	if main == null:
		return
	var pp: Vector3 = main.player.global_position if main.player != null else Vector3.ZERO
	_refresh_counts()
	# Zone attrition for bots caught outside the current circle.
	var zc: Vector2 = main.zone_center
	var zr: float = main.zone_radius
	for c in combatants:
		if not is_instance_valid(c) or not c.is_alive():
			continue
		if int(c.get("squad_id")) == 0:
			continue
		if not (c is NovaEnemy):
			continue
		var cp: Vector3 = (c as Node3D).global_position
		if Vector2(cp.x, cp.z).distance_to(zc) > zr:
			c.set("skip_downed", true)
			c.take_damage(12, cp, "zone", false, null)
			c.set("skip_downed", false)
	# Pairwise skirmishes between close hostile squads, far from the player.
	for i in range(squads.size()):
		var a: Dictionary = squads[i]
		if int(a["id"]) == 0 or int(a["alive_n"]) <= 0:
			continue
		var ad: float = Vector2(a["centroid"].x - pp.x, a["centroid"].z - pp.z).length()
		if ad < 220.0:
			continue  # near the player: real AI handles it
		for j in range(i + 1, squads.size()):
			var b: Dictionary = squads[j]
			if int(b["id"]) == 0 or int(b["alive_n"]) <= 0:
				continue
			var dd: float = Vector2(
				a["centroid"].x - b["centroid"].x,
				a["centroid"].z - b["centroid"].z).length()
			if dd > 90.0:
				continue
			_abstract_skirmish(a, b)


func _abstract_skirmish(a: Dictionary, b: Dictionary) -> void:
	# Strength = alive members + jitter. Loser loses one member, finally.
	var sa: float = float(a["alive_n"]) + rng.randf() * 1.5
	var sb: float = float(b["alive_n"]) + rng.randf() * 1.5
	var loser: Dictionary = b if sa >= sb else a
	var winner: Dictionary = a if sa >= sb else b
	var victim = null
	for m in loser["members"]:
		if is_instance_valid(m) and m.is_alive() and not m.is_downed():
			victim = m
			break
	if victim == null:
		return
	var killer = null
	for m in winner["members"]:
		if is_instance_valid(m) and m.is_alive():
			killer = m
			break
	victim.set("skip_downed", true)
	victim.take_damage(9999, (victim as Node3D).global_position, "bullet", false, killer)
	victim.set("skip_downed", false)


## Phase 2 hook: the dedicated server claims a reserved slot and drives that
## combatant with real player input instead of the AI. Returns false until
## the server exists — the slot keeps running as AI.
func attach_remote_player(human_slot: int) -> bool:
	# TODO(Phase 2): server calls this with slot 1..30; on true, the matching
	# combatant's AI brain is disabled and its input is fed from the network.
	return false
