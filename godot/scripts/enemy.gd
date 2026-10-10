extends CharacterBody3D
class_name NovaEnemy

## NOVA Mobile: tactical bot combatant. Fights in 4-bot squads with focus
## fire, flanking, cover + peek-fire, grenades, revives, and zone rotation.
## Hard but fair: human-like reaction delay, honest miss chances, and only
## line-of-sight + hearing for target acquisition (no wallhacks, no aimbots).

signal killed(enemy: NovaEnemy)

const SPEED := 2.6
const ENGAGE_SPEED := 4.0
const FLANK_SPEED := 6.0
const ATTACK_RANGE := 26.0
const SHOT_INTERVAL := 1.7
const SHOT_DAMAGE := 9
const RESPAWN_DELAY := 4.0
const RAGDOLL_FADE_DELAY := 6.0

# Tactical brain states.
enum B { WANDER, ENGAGE, SUPPRESS, FLANK, COVER, PEEK, NADE, REVIVE_MATE, ROTATE }

var max_hp := 100
var hp := 100
var home_position := Vector3.ZERO
var wander_bounds := 30.0
var allow_respawn := true  # false in BR world mode (last-one-standing)
# --- squad identity ---
var squad_id := -1
var bot_name := "HOSTILE"
var reserved_online := false  # RESERVED_FOR_ONLINE slot (Phase 2 server)
var human_slot := -1  # 0=local player, 1..30 reserved, -1=AI bot
var squadman: SquadManager = null
# --- class system hooks ---
var class_id := ""
var class_sys = null  # ClassSystem (attached by main.gd)
var slow_mult := 1.0
var stun_t := 0.0
var jammed := false
var _marked_t := 0.0

var carry_gun_id := "m5"  # gun shown on the rig + dropped in the death box
var carry_gun_tier := 1
var skip_downed := false  # abstract/zone kills bypass the downed state
var _killer = null  # combatant (or null) — killfeed attribution
var _dead := false
var _downed := false
var _bleed_t := 0.0
var _engaged := false
var _kill_dir := Vector3.ZERO
var _kill_cause := "bullet"
var _exec_victim_variant := 0
var _launch := Vector3.ZERO
var _target := Vector3.ZERO  # wander target
var _idle_timer := 0.0
var _shot_timer := 0.0
var _flash_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rig: SoldierRig
var _anim: SoldierAnim
var _dying := false
var _ragdoll_t := 0.0
var _fade_t := 0.0
var _fading := false
var _respawn_t := 0.0
var _was_moving := false
var _slow_t := 0.0
var _jam_t := 0.0
var _investigate_pos := Vector3.ZERO
var _investigate_t := 0.0
# --- tactical brain ---
var _brain: int = B.WANDER
var _think_t := 0.0
var _tgt = null  # current hostile combatant
var _react_t := 0.0  # human-like reaction delay before first shot
var _no_los_t := 0.0  # how long the target has been unseen
var _cover_pos := Vector3.ZERO
var _cover_cd := 0.0
var _peek_t := 0.0
var _peek_hide := false
var _flank_pos := Vector3.ZERO
var _grenades := 1
var _smokes := 1
var _nade_cd := 0.0
var _revive_target = null
var _revive_t := 0.0
var _last_hurt_t := -99.0
var _last_hurt_from := Vector3.ZERO
var _bark_cd := 0.0

@onready var muzzle_flash: MeshInstance3D = $MuzzleFlash
@onready var col: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("enemies")
	home_position = global_position
	_target = _random_point()
	_rig = SoldierRig.new()
	_rig.name = "Rig"
	add_child(_rig)
	_rig.set_variant(randi() % SoldierRig.VARIANTS.size())
	_anim = SoldierAnim.new()
	_anim.setup(_rig)
	_anim.name = "Anim"
	add_child(_anim)
	_shot_timer = randf() * SHOT_INTERVAL
	_think_t = randf() * 0.4
	if randf() < 0.35:
		_grenades = 2


func rig() -> SoldierRig:
	return _rig


func anim() -> SoldierAnim:
	return _anim


func is_alive() -> bool:
	return not _dead


func is_downed() -> bool:
	return _downed


func _random_point() -> Vector3:
	var ext := 66.0
	var scene := get_tree().current_scene
	if scene != null and "map_extent" in scene:
		ext = float(scene.map_extent) - 4.0
	return Vector3(
		clampf(home_position.x + randf_range(-wander_bounds, wander_bounds), -ext, ext),
		global_position.y,
		clampf(home_position.z + randf_range(-wander_bounds, wander_bounds), -ext, ext)
	)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _downed:
		_downed_physics(delta)
		return
	var player := _get_player()
	var far := false
	if player != null:
		var _pd: float = global_position.distance_to(player.global_position)
		if _pd > 170.0:
			# Far LOD: settle only (saves CPU at world scale); anim holds pose.
			far = true
			_anim.set_lod(true)
			if not is_on_floor():
				velocity.y -= _gravity * delta
			else:
				velocity.y = -0.5
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			return
	_anim.set_lod(false)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.5
	# Buoyancy: spring toward the surface so enemies swim instead of sinking.
	if not is_on_floor() and global_position.y < 0.1:
		var depth := -0.25 - global_position.y
		var target_vy := clampf(depth * 9.0, -2.5, 3.0)
		velocity.y = move_toward(velocity.y, target_vy, 28.0 * delta)
	# Per-frame timers.
	if _react_t > 0.0:
		_react_t -= delta
	if _cover_cd > 0.0:
		_cover_cd -= delta
	if _nade_cd > 0.0:
		_nade_cd -= delta
	if _bark_cd > 0.0:
		_bark_cd -= delta
	# Staggered tactical think (cheap brains, expensive rays stay in move).
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.3 + randf() * 0.15
		_think()
	_move(delta)
	_animate(delta)
	if global_position.y < -6.0:
		# Fell through the world somehow: snap back home.
		global_position = home_position + Vector3(0, 0.5, 0)
		velocity = Vector3.ZERO
		_target = _random_point()
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			muzzle_flash.visible = false


func _downed_physics(delta: float) -> void:
	# Incapacitated: bleed out unless a squadmate revives.
	_bleed_t -= delta
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if _bleed_t <= 0.0:
		skip_downed = true
		_die("bullet")


## Tactical think (staggered): pick target, read squad orders, choose state.
func _think() -> void:
	var scene := get_tree().current_scene
	# --- target acquisition (throttled inside squadman.nearest_hostile) ---
	var new_tgt = null
	if squadman != null:
		new_tgt = squadman.nearest_hostile(self, ATTACK_RANGE + 14.0)
	else:
		new_tgt = _legacy_target()
	if new_tgt != _tgt:
		_tgt = new_tgt
		if _tgt != null:
			# Human-like reaction delay before the first shot.
			_react_t = randf_range(0.35, 0.7)
			_no_los_t = 0.0
	if _tgt != null and (not is_instance_valid(_tgt) or not _tgt.is_alive()):
		_tgt = null
	# --- squad orders ---
	var order := -1
	var role := ""
	if squadman != null:
		var s := squadman.squad_of(self)
		if not s.is_empty():
			order = int(s["order"])
			var roles: Dictionary = s["roles"]
			if roles.has(self):
				role = str(roles[self])
	# --- downed squadmate: nearest free buddy revives ---
	if role == "revive":
		var dm = squadman.downed_mate(self)
		if dm != null:
			_revive_target = dm
			_brain = B.REVIVE_MATE
			_revive_t = 0.0
			return
	_revive_target = null
	# --- zone rotation overrides everything (except revive) ---
	if order == SquadManager.Order.ROTATE:
		_brain = B.ROTATE
		return
	# --- combat ---
	if _tgt != null:
		var d: float = _flat_dist(_tgt.global_position)
		var los := _has_los_to(_tgt)
		if los:
			_no_los_t = 0.0
		else:
			_no_los_t += 0.35
		# Took fire recently and exposed: break for cover.
		if _cover_cd <= 0.0 and Time.get_ticks_msec() / 1000.0 - _last_hurt_t < 1.2 \
				and _brain != B.COVER and _brain != B.PEEK:
			_cover_pos = global_position + (global_position - _last_hurt_from).normalized() * 8.0
			_cover_pos.y = global_position.y
			_brain = B.COVER
			_cover_cd = 6.0
			_peek_t = 0.0
			_peek_hide = false
			return
		if role == "flank" and d > 10.0:
			# Wide arc around the target's flank.
			var to_t: Vector3 = _tgt.global_position - global_position
			to_t.y = 0.0
			var side := Vector3(-to_t.z, 0, to_t.x).normalized()
			if (global_position - _tgt.global_position).x * side.x < 0.0:
				side = -side
			_flank_pos = _tgt.global_position + side * 14.0 + to_t.normalized() * 4.0
			_brain = B.FLANK
			return
		if _brain == B.FLANK and d < 9.0:
			_brain = B.ENGAGE
		if _brain != B.FLANK and _brain != B.COVER and _brain != B.PEEK:
			# Grenade: entrenched/clustered target at mid range.
			if _grenades > 0 and _nade_cd <= 0.0 and d > 8.0 and d < 24.0 \
					and (_no_los_t > 2.0 or _clustered_target()):
				_brain = B.NADE
				return
			_brain = B.SUPPRESS if (role == "suppress" and not los) else B.ENGAGE
		return
	# --- no target: investigate focus squad, or wander ---
	_brain = B.WANDER
	if order == SquadManager.Order.ATTACK:
		var s2 := squadman.squad_of(self)
		var foe: Dictionary = s2.get("focus", {}) if not s2.is_empty() else {}
		if not foe.is_empty():
			investigate(foe["centroid"], 8.0)


func _clustered_target() -> bool:
	# Target has allies bunched nearby: worth a frag.
	if _tgt == null or squadman == null:
		return false
	var ts := int(_tgt.get("squad_id"))
	var tp: Vector3 = _tgt.global_position
	var n := 0
	for c in squadman.combatants:
		if c != _tgt and is_instance_valid(c) and c.is_alive() \
				and int(c.get("squad_id")) == ts:
			if (c.global_position - tp).length() < 6.0:
				n += 1
	return n >= 1


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Per-frame movement + shooting by brain state.
func _move(delta: float) -> void:
	var move_dir := Vector3.ZERO
	var spd := SPEED
	var shooting := false
	match _brain:
		B.ENGAGE:
			if _tgt != null and is_instance_valid(_tgt):
				var to_t: Vector3 = _tgt.global_position - global_position
				to_t.y = 0.0
				var d := to_t.length()
				_face(to_t, delta, 8.0)
				if _has_los_to(_tgt):
					shooting = true
					# Strafe at mid range, hold at close range.
					if d > 14.0:
						move_dir = to_t.normalized()
						spd = ENGAGE_SPEED
					elif d < 5.0:
						move_dir = -to_t.normalized() * 0.6
						spd = SPEED
					else:
						var side := Vector3(-to_t.z, 0, to_t.x).normalized()
						move_dir = side * (1.0 if _strafe_dir() > 0.0 else -1.0)
						spd = SPEED * 0.8
				else:
					# Lost sight: push to last known position.
					move_dir = to_t.normalized()
					spd = ENGAGE_SPEED
		B.SUPPRESS:
			if _tgt != null and is_instance_valid(_tgt):
				var to_t2: Vector3 = _tgt.global_position - global_position
				to_t2.y = 0.0
				_face(to_t2, delta, 8.0)
				move_dir = to_t2.normalized()
				spd = ENGAGE_SPEED
				# Suppressive fire at the last known position (less accurate).
				shooting = _has_los_to(_tgt) or _no_los_t < 4.0
		B.FLANK:
			var to_f: Vector3 = _flank_pos - global_position
			to_f.y = 0.0
			if to_f.length() > 2.0:
				move_dir = to_f.normalized()
				spd = FLANK_SPEED
				_face(to_f, delta, 6.0)
			else:
				_brain = B.ENGAGE
			if _tgt != null and is_instance_valid(_tgt) and _has_los_to(_tgt) and _react_t <= 0.0:
				shooting = true
		B.COVER:
			var to_c: Vector3 = _cover_pos - global_position
			to_c.y = 0.0
			if to_c.length() > 1.5:
				move_dir = to_c.normalized()
				spd = ENGAGE_SPEED
				_face(to_c, delta, 6.0)
			else:
				_brain = B.PEEK
				_peek_t = 1.6
				_peek_hide = true
		B.PEEK:
			# Expose-shoot-hide rhythm: 1.1 s up firing, 1.6 s down hiding.
			_peek_t -= delta
			if _peek_t <= 0.0:
				_peek_hide = not _peek_hide
				_peek_t = 1.6 if _peek_hide else 1.1
			if _tgt != null and is_instance_valid(_tgt):
				var to_t3: Vector3 = _tgt.global_position - global_position
				to_t3.y = 0.0
				_face(to_t3, delta, 8.0)
				shooting = not _peek_hide and _has_los_to(_tgt)
			if _tgt == null:
				_brain = B.WANDER
		B.NADE:
			if _tgt != null and is_instance_valid(_tgt):
				var to_t4: Vector3 = _tgt.global_position - global_position
				to_t4.y = 0.0
				_face(to_t4, delta, 10.0)
				_throw_frag(_tgt.global_position)
			_brain = B.ENGAGE
			_nade_cd = 8.0
		B.REVIVE_MATE:
			if _revive_target != null and is_instance_valid(_revive_target) \
					and _revive_target.is_alive() and (_revive_target as NovaEnemy).is_downed():
				var to_r: Vector3 = (_revive_target as Node3D).global_position - global_position
				to_r.y = 0.0
				if to_r.length() > 2.5:
					move_dir = to_r.normalized()
					spd = ENGAGE_SPEED
					_face(to_r, delta, 6.0)
					_revive_t = 0.0
					# Smoke the revive if crossing open ground.
					if to_r.length() > 12.0 and _smokes > 0:
						_throw_smoke((_revive_target as Node3D).global_position)
				else:
					_revive_t += delta
					if _revive_t >= 5.0:
						(_revive_target as NovaEnemy).revive_ally()
						_bark(BotNames.BARK_REVIVE)
						_brain = B.WANDER
						_revive_target = null
			else:
				_brain = B.WANDER
				_revive_target = null
		B.ROTATE:
			var rp := Vector3.ZERO
			if squadman != null:
				var s := squadman.squad_of(self)
				if not s.is_empty():
					rp = s["order_pos"]
			var to_z: Vector3 = rp - global_position
			to_z.y = 0.0
			if to_z.length() > 4.0:
				move_dir = to_z.normalized()
				spd = FLANK_SPEED
				_face(to_z, delta, 6.0)
			else:
				_brain = B.WANDER
		_:
			# WANDER: walk to target, idle, pick a new one. Investigate sounds.
			if _investigate_t > 0.0:
				_investigate_t -= delta
				var to_i: Vector3 = _investigate_pos - global_position
				to_i.y = 0.0
				if to_i.length() > 1.5:
					move_dir = to_i.normalized()
					_face(to_i, delta, 5.0)
				else:
					_investigate_t = 0.0
			elif _idle_timer > 0.0:
				_idle_timer -= delta
			else:
				var to_t5: Vector3 = _target - global_position
				to_t5.y = 0.0
				if to_t5.length() < 1.5:
					_idle_timer = randf_range(1.0, 3.0)
					_target = _random_point()
				else:
					move_dir = to_t5.normalized()
					_face(to_t5, delta, 5.0)
	if stun_t > 0.0 or jammed:
		move_dir = Vector3.ZERO
		shooting = false
	velocity.x = move_dir.x * spd * slow_mult
	velocity.z = move_dir.z * spd * slow_mult
	move_and_slide()
	_engaged = shooting
	if shooting and _tgt != null and is_instance_valid(_tgt):
		_try_shoot(delta, _tgt)


func _strafe_dir() -> float:
	return 1.0 if int(Time.get_ticks_msec() / 900 + global_position.x) % 2 == 0 else -1.0


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length() < 0.01:
		return
	var want_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want_yaw, rate * delta)


## Shooting with human-like reaction delay and honest miss chances.
func _try_shoot(delta: float, tgt) -> void:
	if _react_t > 0.0:
		return
	_shot_timer -= delta
	if _shot_timer > 0.0:
		return
	_shot_timer = SHOT_INTERVAL * randf_range(0.85, 1.25)
	muzzle_flash.global_position = _rig.muzzle_point()
	muzzle_flash.visible = true
	_flash_timer = maxf(_flash_timer, 0.08)
	_anim.add_jolt(0.9)
	var tp: Vector3 = (tgt as Node3D).global_position
	var d: float = _flat_dist(tp)
	var hit_p := clampf(0.72 - d * 0.016, 0.18, 0.72)
	# Moving targets and moving shooters are harder to hit.
	var tv := 0.0
	if tgt is NovaEnemy:
		tv = (tgt as NovaEnemy).velocity.length()
	elif tgt is NovaPlayer:
		tv = Vector2((tgt as NovaPlayer).velocity.x, (tgt as NovaPlayer).velocity.z).length()
	elif tgt is NovaAlly:
		tv = (tgt as NovaAlly).velocity.length()
	if tv > 4.0:
		hit_p *= 0.6
	if Vector2(velocity.x, velocity.z).length() > 3.0:
		hit_p *= 0.7
	if _brain == B.SUPPRESS and not _has_los_to(tgt):
		hit_p *= 0.35
	if randf() < hit_p:
		_deal_hit(tgt)
	else:
		# Near miss: kick up an impact beside the target (no free damage).
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("spawn_impact"):
			var off := Vector3(randf_range(-1.6, 1.6), randf_range(0.2, 1.4), randf_range(-1.6, 1.6))
			scene.spawn_impact(tp + Vector3(0, 1.2, 0) + off, Vector3.UP)


func _deal_hit(tgt) -> void:
	if tgt is NovaPlayer:
		(tgt as NovaPlayer).take_damage(SHOT_DAMAGE, global_position, "bullet", false, self)
	elif tgt is NovaEnemy:
		(tgt as NovaEnemy).take_damage(SHOT_DAMAGE, global_position, "bullet", false, self)
	elif tgt is NovaAlly:
		(tgt as NovaAlly).take_damage(SHOT_DAMAGE, global_position, self)


func _throw_frag(at: Vector3) -> void:
	if _grenades <= 0:
		return
	_grenades -= 1
	_anim.play_action("grenade_throw")
	_bark(BotNames.BARK_GRENADE)
	var from := global_position + Vector3(0, 1.5, 0)
	var to := at + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	var dir: Vector3 = (to - from).normalized()
	var dist := _flat_dist(at)
	var g := FragGrenade.throw_from(from, dir, dist * 0.85 + 5.0, 0.0, self)
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(g)


func _throw_smoke(at: Vector3) -> void:
	if _smokes <= 0:
		return
	_smokes -= 1
	_anim.play_action("grenade_throw")
	var from := global_position + Vector3(0, 1.5, 0)
	var dir: Vector3 = ((at + Vector3(0, 0.5, 0)) - from).normalized()
	var g := SmokeGrenade.throw_from(from, dir, 12.0, self)
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(g)


func _bark(pool: Array) -> void:
	if _bark_cd > 0.0:
		return
	_bark_cd = 9.0
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("bot_bark"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		scene.bot_bark(bot_name, BotNames.bark(pool, rng))


func _animate(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.4
	var spd := Vector2(velocity.x, velocity.z).length()
	if _brain == B.PEEK and _peek_hide:
		_anim.play("crouch_idle", 0.2)
		_anim.set_aim(0.0, 0.0, 0.0)
		_was_moving = false
	elif _brain == B.COVER:
		_anim.play("crouch_walk", 0.2, spd / 2.6)
		_anim.set_aim(0.0, 0.0, 0.0)
		_was_moving = true
	elif _engaged:
		_anim.play("run", 0.2, spd / 4.2)
		var want_yaw := rotation.y
		if _tgt != null and is_instance_valid(_tgt):
			var to_t: Vector3 = (_tgt as Node3D).global_position - global_position
			want_yaw = atan2(-to_t.x, -to_t.z)
		_anim.set_aim(1.0, wrapf(want_yaw - rotation.y, -PI, PI), 0.0, false)
		_was_moving = true
	elif moving:
		var rate := spd / 2.6
		if _brain == B.FLANK or _brain == B.ROTATE:
			_anim.play("run_onehand", 0.2, spd / 4.2)
		else:
			_anim.play("walk", 0.25, rate)
		_anim.set_aim(0.0, 0.0, 0.0)
		_was_moving = true
	else:
		if _was_moving:
			_anim.play("idle", 0.3)
			_was_moving = false
		_anim.set_aim(0.0, 0.0, 0.0)


func _legacy_target():
	# Single-map mode (no squads): the player, as before.
	var p := _get_player()
	if p != null and p.is_alive() and not p.dropping:
		if _flat_dist(p.global_position) < ATTACK_RANGE + 14.0:
			return p
	return null


func _get_player() -> NovaPlayer:
	var scene := get_tree().current_scene
	if scene != null and "player" in scene:
		var p = scene.get("player")
		if p is NovaPlayer:
			return p
	return null


func _has_los(player: NovaPlayer) -> bool:
	return _has_los_to(player)


func _has_los_to(tgt) -> bool:
	var from := global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = (tgt as Node3D).global_position + Vector3(0, 1.2, 0)
	if SmokeGrenade.blocks_sight(from, to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit["collider"] == tgt


func is_engaged() -> bool:
	return _engaged


func is_headshot(point: Vector3) -> bool:
	# Head zone: upper ~0.35 m of the 1.82 m rig.
	return point.y >= global_position.y + 1.47


func take_damage(amount: int, point: Vector3 = Vector3.ZERO, kind: String = "bullet",
		headshot: bool = false, killer = null) -> void:
	if _dead:
		return
	if killer != null:
		_killer = killer
	if class_sys != null:
		amount = class_sys.modify_incoming_damage(amount, point, kind)
	hp -= amount
	# Getting shot: remember it (cover brain) unless already committed.
	if kind == "bullet" and point != Vector3.ZERO:
		_last_hurt_t = Time.get_ticks_msec() / 1000.0
		_last_hurt_from = point
	# Blood spray at the hit point (CODM-style, tasteful).
	var scene := get_tree().current_scene
	if point != Vector3.ZERO and scene != null and scene.has_method("spawn_blood"):
		var bdir: Vector3 = (point - global_position)
		bdir.y = 0.0
		scene.spawn_blood(point, bdir.normalized() if bdir.length() > 0.01 else Vector3.ZERO)
	# Directional hit flinch.
	var fwd := -global_transform.basis.z
	var to: Vector3 = point - global_position
	var cname := "hit_F"
	if to.length() > 0.01:
		var d := to.normalized().dot(fwd)
		var side := (-global_transform.basis.x).dot(to.normalized())
		if d > 0.5:
			cname = "hit_F"
		elif d < -0.5:
			cname = "hit_B"
		elif side > 0.0:
			cname = "hit_L"
		else:
			cname = "hit_R"
	_anim.play_action(cname)
	if hp <= 0:
		_kill_dir = to.normalized() if to.length() > 0.01 else -fwd
		if not skip_downed and squadman != null and squadman.has_living_mate(self):
			_go_downed()
		else:
			_die(kind, headshot)


func _go_downed() -> void:
	# Incapacitated but revivable: squadmate may bring them back.
	_downed = true
	_bleed_t = 20.0
	_tgt = null
	_brain = B.WANDER
	_anim.play("prone_idle", 0.3)
	_anim.set_aim(0.0, 0.0, 0.0)
	if squadman != null:
		squadman.on_combatant_down(self)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("bot_bark"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		scene.bot_bark(bot_name, BotNames.bark(BotNames.BARK_DOWNED, rng))


func revive_ally() -> void:
	if _dead or not _downed:
		return
	_downed = false
	hp = 40
	_brain = B.WANDER
	_target = _random_point()
	_anim.play("idle", 0.2)


func killer_name() -> String:
	if _killer == null or not is_instance_valid(_killer):
		return ""
	if _killer is NovaPlayer:
		return "YOU"
	return str(_killer.get("bot_name")) if _killer.get("bot_name") != null else "HOSTILE"


## Cause + direction aware death: animated reaction beat, then ragdoll
## with momentum AWAY from the shot. Explosives launch the body.
func _die(kind: String = "bullet", headshot: bool = false) -> void:
	_dead = true
	_downed = false
	_dying = true
	killed.emit(self)
	col.set_deferred("disabled", true)
	_kill_cause = kind
	var clip := "death"
	var beat := 0.30  # pre-ragdoll animated reaction (sells weight)
	_launch = Vector3.ZERO
	match kind:
		"explosive":
			clip = "death_explosive"
			beat = 0.05  # near-instant launch
			_launch = -_kill_dir * 7.0 + Vector3(0, 4.5, 0)
		"melee", "execution":
			clip = "death_fwd"
			_launch = _kill_dir * 2.0 + Vector3(0, 0.5, 0)
		"zone":
			clip = "death_kneel"
		_:
			if headshot:
				clip = "death_head"
				_launch = -_kill_dir * 2.5 + Vector3(0, 1.2, 0)
			else:
				# Directional variety: fall away from the shot, or sideways/kneel/stumble.
				var r := randf()
				if r < 0.30:
					clip = "death"
				elif r < 0.50:
					clip = "death_fwd"
				elif r < 0.65:
					clip = "death_side"
				elif r < 0.80:
					clip = "death_kneel"
				else:
					clip = "death_stumble"
				_launch = -_kill_dir * 3.0 + Vector3(0, 0.8, 0)
	_anim.play_action(clip)
	_ragdoll_t = beat
	# BR mode: bodies persist (last-one-standing battlefield); else 6 s.
	_fade_t = 25.0 if not allow_respawn else RAGDOLL_FADE_DELAY
	_fading = true
	if squadman != null:
		squadman.on_combatant_dead(self)


## Stealth-execution victim: synced takedown with the attacker's clip.
## Instant silent kill tagged with the execution cause; the body holds its
## death pose through the 1.45 s sync beat, then ragdolls.
func play_execution_victim(variant: int) -> void:
	_exec_victim_variant = variant
	if _dead:
		return
	_kill_dir = -global_transform.basis.z  # crumple forward, away from attacker
	_die("execution")
	_ragdoll_t = 1.45  # hold the pose through the synced takedown


func _process(delta: float) -> void:
	# Class system timers.
	if stun_t > 0.0:
		stun_t -= delta
	if _slow_t > 0.0:
		_slow_t -= delta
		if _slow_t <= 0.0:
			slow_mult = 1.0
	if _jam_t > 0.0:
		_jam_t -= delta
		if _jam_t <= 0.0:
			jammed = false
	if _marked_t > 0.0:
		_marked_t -= delta
	if _dying and not _rig.is_ragdoll():
		_ragdoll_t -= delta
		if _ragdoll_t <= 0.0:
			_rig.set_ragdoll(true, _launch + velocity * 0.5)
			_anim.notify_ragdoll()
	if _fading:
		_fade_t -= delta
		var a := clampf(_fade_t / 1.0, 0.0, 1.0)
		_set_body_transparency(1.0 - a)
		if _fade_t <= 0.0:
			_fading = false
			visible = false
			if allow_respawn:
				_respawn_t = RESPAWN_DELAY
	if _respawn_t > 0.0:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_respawn()


func _set_body_transparency(t: float) -> void:
	for ch in _rig.skel.get_children():
		for mi in ch.get_children():
			if mi is MeshInstance3D:
				(mi as MeshInstance3D).transparency = t


func _respawn() -> void:
	_rig.set_ragdoll(false)
	_anim.set_ragdoll_done()
	_set_body_transparency(0.0)
	visible = true
	global_position = home_position + Vector3(randf_range(-3.0, 3.0), 0.5, randf_range(-3.0, 3.0))
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	hp = max_hp
	_dead = false
	_dying = false
	_downed = false
	_killer = null
	_tgt = null
	_brain = B.WANDER
	_target = _random_point()
	_idle_timer = 0.0
	col.disabled = false
	slow_mult = 1.0
	stun_t = 0.0
	jammed = false
	_investigate_t = 0.0
	_grenades = 1
	_anim.play("idle", 0.1)


# --- class system API (called by ClassSystem) ---
func apply_slow(mult: float, dur: float) -> void:
	if _slow_t > 0.0:
		slow_mult = minf(slow_mult, mult)
	else:
		slow_mult = mult
	_slow_t = maxf(_slow_t, dur)


func stun(dur: float) -> void:
	stun_t = maxf(stun_t, dur)


func set_jammed(v: bool, dur: float) -> void:
	jammed = v
	_jam_t = maxf(_jam_t, dur)


func investigate(pos: Vector3, dur: float) -> void:
	_investigate_pos = pos
	_investigate_t = dur
