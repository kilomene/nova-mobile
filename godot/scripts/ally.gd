extends CharacterBody3D
class_name NovaAlly

## NOVA Mobile: AI teammate — follows the player in formation, engages the
## player's target, revives the downed player (5 s channel), pings high-tier
## loot, and calls out contacts on the radio net. Goes downed (bleed-out 30 s)
## instead of dying when the squad has a living mate.

signal killed(ally: NovaAlly)

const SPEED := 2.9
const ENGAGE_SPEED := 4.1
const FOLLOW_DIST := 3.2
const ATTACK_RANGE := 26.0
const SHOT_INTERVAL := 1.4
const SHOT_DAMAGE := 10

var max_hp := 100
var hp := 100
var _slot := 0
var _callsign := "ALLY"
# --- squad identity ---
var squad_id := 0
var bot_name := "ALLY"
var reserved_online := false
var human_slot := -1
var squadman: SquadManager = null

var _dead := false
var _downed := false
var _bleed_t := 0.0
var _rig: SoldierRig
var _anim: SoldierAnim
var _shot_timer := 0.0
var _idle_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_moving := false
var _investigate := Vector3.ZERO
var _investigate_t := 0.0
var _foe: NovaEnemy = null
var _bark_cd := 0.0
var _ping_cd := 0.0
var _revive_t := 0.0
var _revive_target = null  # downed player being revived
var _seen_shots := 0  # player's _shot_index last observed (target hand-off)

@onready var muzzle_flash: MeshInstance3D = $MuzzleFlash
@onready var col: CollisionShape3D = $CollisionShape3D


func setup(slot: int, vname: String) -> void:
	_slot = slot
	_callsign = vname
	bot_name = vname


func _ready() -> void:
	add_to_group("allies")
	_rig = SoldierRig.new()
	_rig.name = "Rig"
	add_child(_rig)
	_rig.set_variant(2)  # friendly gear tint
	_anim = SoldierAnim.new()
	_anim.setup(_rig)
	_anim.name = "Anim"
	add_child(_anim)
	_shot_timer = randf() * SHOT_INTERVAL


func is_alive() -> bool:
	return not _dead


func is_downed() -> bool:
	return _downed


func investigate(pos: Vector3) -> void:
	_investigate = pos
	_investigate_t = 6.0


func _get_player() -> NovaPlayer:
	var scene := get_tree().current_scene
	if scene != null and "player" in scene:
		var p = scene.get("player")
		if p is NovaPlayer:
			return p
	return null


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _downed:
		_downed_physics(delta)
		return
	var player := _get_player()
	if player == null or not player.is_alive():
		velocity.x = 0.0
		velocity.z = 0.0
		_anim.play("idle", 0.3)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.5
	# Buoyancy: spring toward the surface so allies swim instead of sinking.
	if not is_on_floor() and global_position.y < 0.1:
		var depth := -0.25 - global_position.y
		var target_vy := clampf(depth * 9.0, -2.5, 3.0)
		velocity.y = move_toward(velocity.y, target_vy, 28.0 * delta)
	if _bark_cd > 0.0:
		_bark_cd -= delta
	if _ping_cd > 0.0:
		_ping_cd -= delta
	var move_dir := Vector3.ZERO
	var engaging := false
	var aim_yaw := 0.0
	var scene := get_tree().current_scene
	# --- priority 1: revive the downed player ---
	if player.downed and not _dead:
		_revive_target = player
		var to_p: Vector3 = player.global_position - global_position
		to_p.y = 0.0
		if to_p.length() > 2.5:
			move_dir = to_p.normalized()
			_revive_t = 0.0
		else:
			_revive_t += delta
			rotation.y = lerp_angle(rotation.y, atan2(-to_p.x, -to_p.z), 8.0 * delta)
			if _revive_t >= 5.0:
				player.revive()
				_revive_t = 0.0
				_revive_target = null
				_bark(BotNames.BARK_REVIVE)
	else:
		_revive_target = null
		_revive_t = 0.0
	# --- priority 2: combat — prefer the player's target ---
	if _revive_target == null:
		_foe = _pick_foe(player, scene)
		if _foe != null:
			engaging = true
			var to_f: Vector3 = _foe.global_position - global_position
			to_f.y = 0.0
			var want_yaw := atan2(-to_f.x, -to_f.z)
			rotation.y = lerp_angle(rotation.y, want_yaw, 8.0 * delta)
			aim_yaw = wrapf(want_yaw - rotation.y, -PI, PI)
			_shot_timer -= delta
			if _shot_timer <= 0.0:
				_shot_timer = SHOT_INTERVAL * randf_range(0.85, 1.2)
				_ally_shoot(_foe)
			if to_f.length() > 8.0:
				move_dir = to_f.normalized()
		elif _investigate_t > 0.0:
			_investigate_t -= delta
			var to_i: Vector3 = _investigate - global_position
			to_i.y = 0.0
			if to_i.length() > 2.0:
				move_dir = to_i.normalized()
			else:
				_investigate_t = 0.0
		else:
			# --- priority 3: formation follow ---
			var back := player.global_transform.basis.z
			var side := player.global_transform.basis.x
			var lane: float = [2.2, -2.2, 3.6][_slot % 3]
			var want: Vector3 = player.global_position + back * FOLLOW_DIST + side * lane
			var to_p2: Vector3 = want - global_position
			to_p2.y = 0.0
			if to_p2.length() > 1.6:
				move_dir = to_p2.normalized()
			else:
				rotation.y = lerp_angle(rotation.y, player.rotation.y, 4.0 * delta)
			_ping_loot(player, scene)
	var spd := (ENGAGE_SPEED if engaging else SPEED)
	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd
	move_and_slide()
	if _revive_target != null:
		_anim.play("crouch_idle", 0.2)
		_anim.set_aim(0.0, 0.0, 0.0)
	elif engaging:
		_anim.play("run", 0.2, spd / 4.2)
		_anim.set_aim(1.0, aim_yaw, 0.0, false)
		_was_moving = true
	elif move_dir.length() > 0.01:
		var want_yaw2 := atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, want_yaw2, 6.0 * delta)
		_anim.play("walk", 0.25, spd / 2.9)
		_anim.set_aim(0.0, 0.0, 0.0)
		_was_moving = true
	else:
		if _was_moving:
			_anim.play("idle", 0.3)
			_was_moving = false
		_anim.set_aim(0.0, 0.0, 0.0)


func _downed_physics(delta: float) -> void:
	# Incapacitated teammate: bleed out; the player revives by standing close.
	_bleed_t -= delta
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if _bleed_t <= 0.0:
		_die()


func _pick_foe(player: NovaPlayer, scene) -> NovaEnemy:
	# Engage the player's target when they're shooting; otherwise nearest
	# visible hostile. Call out new contacts on the radio.
	if squadman != null and bool(squadman.get("test_ceasefire")):
		return null
	var foes: Array = []
	if scene != null and scene.get("enemies") != null:
		foes = scene.enemies
	var player_foe: NovaEnemy = null
	if int(player.get("_shot_index")) != _seen_shots:
		_seen_shots = int(player.get("_shot_index"))
		# Player is firing: engage the hostile nearest to the player.
		var pb := 40.0
		for e in foes:
			if e == null or not is_instance_valid(e) or not e.is_alive():
				continue
			var d: float = player.global_position.distance_to(e.global_position)
			if d < pb:
				pb = d
				player_foe = e
	if player_foe != null and _has_los(player_foe):
		_callout(player_foe)
		return player_foe
	var best: NovaEnemy = null
	var bd := ATTACK_RANGE
	for e in foes:
		if e == null or not is_instance_valid(e) or not e.is_alive():
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < bd and _has_los(e):
			bd = d
			best = e
	if best != null and best != _foe:
		_callout(best)
	return best


func _callout(e: NovaEnemy) -> void:
	if _bark_cd > 0.0:
		return
	_bark_cd = 14.0
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("bot_bark"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		scene.bot_bark(_callsign, "%s — %s" % [BotNames.bark(BotNames.BARK_ENGAGE, rng), e.bot_name])


func _bark(pool: Array) -> void:
	if _bark_cd > 0.0:
		return
	_bark_cd = 9.0
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("bot_bark"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		scene.bot_bark(_callsign, BotNames.bark(pool, rng))


func _ping_loot(player: NovaPlayer, scene) -> void:
	if _ping_cd > 0.0 or scene == null:
		return
	_ping_cd = 25.0
	var loots: Array = scene.get("loots") if scene.get("loots") != null else []
	for l in loots:
		if l == null or not is_instance_valid(l):
			continue
		if l is NovaLoot and int(l.get("tier")) >= 3:
			var d: float = player.global_position.distance_to(l.global_position)
			if d < 45.0:
				var scene2 := get_tree().current_scene
				if scene2 != null and scene2.has_method("bot_bark"):
					scene2.bot_bark(_callsign, "Ping — %s nearby." % str(l.display_name()))
				return


func _has_los(e: NovaEnemy) -> bool:
	var from := global_position + Vector3(0, 1.5, 0)
	var to := e.global_position + Vector3(0, 1.2, 0)
	if SmokeGrenade.blocks_sight(from, to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit["collider"] == e


func _ally_shoot(e: NovaEnemy) -> void:
	muzzle_flash.visible = true
	_anim.add_jolt(0.8)
	e.take_damage(SHOT_DAMAGE, global_position, "bullet", false, self)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_muzzle"):
		scene.spawn_muzzle(muzzle_flash.global_position)


func take_damage(amount: float, point: Vector3 = Vector3.ZERO, killer = null) -> void:
	if _dead:
		return
	hp -= amount
	_anim.play_action("hit_F")
	if hp <= 0:
		if squadman != null and squadman.has_living_mate(self):
			_go_downed(killer)
		else:
			_die(killer)


func _go_downed(_killer) -> void:
	_downed = true
	_bleed_t = 30.0
	_foe = null
	_revive_target = null
	_anim.play("prone_idle", 0.3)
	_anim.set_aim(0.0, 0.0, 0.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("bot_bark"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		scene.bot_bark(_callsign, BotNames.bark(BotNames.BARK_DOWNED, rng))


func revive_ally() -> void:
	if _dead or not _downed:
		return
	_downed = false
	hp = 50
	_anim.play("idle", 0.2)


## Redeploy after death: drop back in near the given position, full health.
func respawn_at(pos: Vector3) -> void:
	_rig.set_ragdoll(false)
	_anim.set_ragdoll_done()
	visible = true
	global_position = pos + Vector3(0, 0.6, 0)
	velocity = Vector3.ZERO
	hp = max_hp
	_dead = false
	_downed = false
	_foe = null
	_revive_target = null
	col.disabled = false
	_anim.play("idle", 0.1)


func _die(_killer = null) -> void:
	_dead = true
	_downed = false
	killed.emit(self)
	col.set_deferred("disabled", true)
	_anim.play_action("death")
	_rig.set_ragdoll(true, velocity * 0.4)
	_anim.notify_ragdoll()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("on_ally_down"):
		scene.on_ally_down(self)
