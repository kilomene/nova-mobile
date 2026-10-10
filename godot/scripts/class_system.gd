class_name ClassSystem
extends Node
## NOVA Mobile: battle royale class system.
## Attach one per actor (player or enemy). Data in ClassDefs; FX in ClassFX.
## Player actives: full implementations. Enemy actives: simple triggers.

signal cooldown_changed(frac: float)

var body = null  # NovaPlayer or NovaEnemy
var is_player := false
var class_id := ""
var def := {}
var prof := ""
var accent := Color.WHITE

var cd_left := 0.0
var cd_total := 30.0

var _t := 0.0
var _tick_slow := 0.0  # 1s AI tick accumulator
# --- passive / buff state ---
var _temp_hp := 0.0
var _revive_used := false
var _stand_used := false
var _disrupt_t := 0.0
var _overcharge_t := 0.0
var _deflect_t := 0.0
var _wraith_dmg_t := 0.0
# --- active entity state ---
var _hist: Array = []  # chronos: [{p, hp, armor}]
var _hist_t := 0.0
var _grappling := false
var _grapple_to := Vector3.ZERO
var _grapple_beam: MeshInstance3D = null
var _jet_t := 0.0
var _jet_kind := ""
var _comet_slam := false
var _beacon: Node3D = null
var _beacon_t := 0.0
var _beacon_pos := Vector3.ZERO
var _tar_t := 0.0
var _tar_pos := Vector3.ZERO
var _tar_node: Node3D = null
var _rad_t := 0.0
var _rad_pos := Vector3.ZERO
var _rad_heat := {}  # enemy instance id -> seconds inside
var _dome_t := 0.0
var _dome_pos := Vector3.ZERO
var _station_t := 0.0
var _station_pos := Vector3.ZERO
var _pads: Array = []  # {"node","pos"}
var _traps: Array = []  # {"node","pos","t"}
var _turret: Node3D = null
var _turret_t := 0.0
var _turret_cd := 0.0
var _mortar: Node3D = null
var _mortar_n := 0
var _mortar_t := 0.0
var _mortar_dur := 0.0
var _drone: Node3D = null
var _drone_t := 0.0
var _drone_pulse := 0.0
var _guard_t := 0.0  # phoenix guardian drone
var _guard_cd := 0.0
var _hound: CharacterBody3D = null
var _hound_t := 0.0
var _hound_hp := 30.0
var _hound_cd := 0.0
var _decoys: Array = []  # {"node","t","vel"}
var _strike_t := -1.0  # overlord pending strike
var _strike_pos := Vector3.ZERO
var _strike_n := 0
var _smoke_t := 0.0  # wildfire smoke tick
var _smoke_pos := Vector3.ZERO
var _jam_t := 0.0  # ghost jam bubble
var _jam_pos := Vector3.ZERO
var _wall: Node3D = null  # rampart wall (re-deployable)
var _btn: Button = null
var _btn_placed := false
var _x_was := false


func setup(b, cid: String, player_flag: bool) -> void:
	body = b
	is_player = player_flag
	class_id = cid
	def = ClassDefs.get_by_id(cid)
	prof = str(def.get("profession", ""))
	accent = def.get("accent", Color.WHITE)
	cd_total = float(def.get("cooldown", 30.0))
	# Passive cooldown reductions.
	if class_id == "quartermaster" or class_id == "gatekeeper":
		cd_total *= 0.8
	if class_id == "warden":
		cd_total *= 0.75
	cd_left = 0.0
	# Seed chronos history so rewind always has a valid anchor.
	var _arm := 0
	if body.get("armor") != null:
		_arm = int(body.get("armor"))
	_hist.push_front({"p": body.global_position, "hp": body.hp, "armor": _arm})
	# Instant passive effects.
	if is_player and class_id == "aegis":
		body.armor = mini(body.armor + 50, 150)
	# Class identity accent on the rig (shoulder patch in class color).
	var rig = null
	if body.has_method("rig"):
		rig = body.rig()
	elif body.get("_body_rig") != null:
		rig = body.get("_body_rig")
	if rig != null and rig.has_method("set_class_accent"):
		rig.set_class_accent(accent)
	if is_player:
		_make_ability_button()


func class_name_() -> String:
	return str(def.get("name", class_id))


# ------------------------------------------------------------------ HUD button
func _make_ability_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	body.add_child(layer)
	_btn = Button.new()
	_btn.text = "SKILL"
	_btn.custom_minimum_size = Vector2(96, 96)
	# setup() may run before the body enters the tree (main.gd pre-add_child),
	# so the viewport can be null — fall back to a sane default and reposition
	# on the first _process tick once a viewport exists.
	var vp := Vector2(960, 540)
	var _vp: Viewport = body.get_viewport()
	if _vp != null:
		vp = _vp.get_visible_rect().size
	_btn.position = Vector2(vp.x * 0.5 + 170, vp.y - 120)
	_btn.add_theme_font_size_override("font_size", 20)
	_btn.pressed.connect(try_activate)
	layer.add_child(_btn)
	_btn_placed = false


func _refresh_button() -> void:
	if _btn == null or not is_instance_valid(_btn):
		return
	if cd_left > 0.0:
		_btn.text = "SKILL\n%ds" % int(ceil(cd_left))
		_btn.modulate = Color(0.55, 0.55, 0.6)
	else:
		_btn.text = "SKILL\nREADY"
		_btn.modulate = Color(1, 1, 1)


# ------------------------------------------------------------------ activation
func cooldown_frac() -> float:
	if cd_total <= 0.0:
		return 1.0
	return clampf(1.0 - cd_left / cd_total, 0.0, 1.0)


func try_activate() -> bool:
	if body == null or not body.is_alive():
		return false
	if cd_left > 0.0:
		return false
	# Tar detonate / wall pickup / beacon blink: skill button re-triggers.
	if class_id == "pyre" and _tar_t > 0.0:
		_detonate_tar()
		return true
	if class_id == "rampart" and _wall != null and is_instance_valid(_wall):
		_recall_wall()
		return true
	if class_id == "gatekeeper" and _beacon != null and is_instance_valid(_beacon):
		_blink_to_beacon()
		return true
	if class_id == "comet" and _jet_t > 0.0:
		_comet_slam_start()
		return true
	if class_id == "valkyrie" and _jet_t > 0.0:
		_jet_t = 0.0
		return true
	if class_id == "trampoline" and _pads.size() > 0:
		_detonate_pads()
		return true
	var ok := _do_active()
	if ok:
		cd_left = cd_total
		if prof == "disrupt":
			_disrupt_t = 6.0
			_apply_disrupt_speed()
		cooldown_changed.emit(cooldown_frac())
		_refresh_button()
	return ok


func _do_active() -> bool:
	match class_id:
		"pathfinder": return _a_sensor_dart()
		"kennelmaster": return _a_hound()
		"saboteur": return _a_emp_drone()
		"skyhook": return _a_catapult()
		"ballista": return _a_mortar()
		"surgeon": return _a_heal_station()
		"quartermaster": return _a_supply()
		"aegis": return _a_dome()
		"phoenix": return _a_guardian()
		"replicator": return _a_mirror()
		"warden": return _a_trap()
		"chronos": return _a_rewind()
		"mirage": return _a_decoys()
		"wildfire": return _a_smoke()
		"ghost": return _a_jam()
		"bulwark": return _a_shockwave()
		"ventriloquist": return _a_phantom()
		"volt": return _a_lightning()
		"rampart": return _a_wall()
		"lastword": return _a_turret()
		"overlord": return _a_strike()
		"pyre": return _a_tar()
		"fallout": return _a_radiation()
		"spider": return _a_grapple()
		"wraith": return _a_camo()
		"comet": return _a_comet()
		"ronin": return _a_dash()
		"valkyrie": return _a_jetpack()
		"gatekeeper": return _a_beacon()
		"trampoline": return _a_pad()
	return false


# ------------------------------------------------------------------ modifiers
func modify_incoming_damage(amount: int, from_pos: Vector3, kind: String) -> int:
	var mult := 1.0
	if prof == "defense" and kind == "explosive":
		mult *= 0.65
	if prof == "defense" and kind == "zone":
		mult *= 0.75
	if class_id == "rampart" and kind != "bullet":
		mult *= 0.6
	if class_id == "bulwark" and kind == "explosive":
		mult *= 0.8
	if prof == "stealth" and kind == "bullet" and body.get("sprinting"):
		mult *= 0.85
	if _deflect_t > 0.0:
		mult *= 0.3
	if class_id == "aegis" and _dome_t > 0.0 and kind == "bullet":
		if body.global_position.distance_to(_dome_pos) <= 5.0:
			mult *= 0.5
	# Overheal temp HP absorbs first.
	var dmg := int(amount * mult)
	if _temp_hp > 0.0 and dmg > 0:
		var absorbed: int = mini(int(_temp_hp), dmg)
		_temp_hp -= absorbed
		dmg -= absorbed
	# Once-per-match survival passives.
	if is_player and body.hp - dmg <= 0:
		if class_id == "phoenix" and not _revive_used:
			_revive_used = true
			body.hp = 50
			ClassFX.ground_ring(_scene(), body.global_position, 3.0, 1.2, Color(0.25, 0.85, 0.45))
			return 0
		if class_id == "lastword" and not _stand_used:
			_stand_used = true
			body.hp = 25
			ClassFX.ground_ring(_scene(), body.global_position, 3.0, 1.2, Color(0.3, 0.6, 1.0))
			return 0
	return dmg


func modify_heal(n: int) -> int:
	var mult := 1.0
	if prof == "support":
		mult *= 1.4
	if class_id == "surgeon":
		mult *= 1.5
	return int(n * mult)


func outgoing_dmg_mult() -> float:
	var mult := 1.0
	if class_id == "volt":
		mult *= 1.1
	if _overcharge_t > 0.0:
		mult *= 1.3
	if _wraith_dmg_t > 0.0:
		mult *= 1.5
	return mult


func speed_bonus() -> float:
	var mult := 1.0
	if prof == "tracker":
		mult *= 1.1
	if class_id == "chronos":
		mult *= 1.1
	if class_id == "ventriloquist":
		mult *= 1.1
	return mult


func engage_range_mult() -> float:
	# How much later enemies notice THIS body (stealth).
	var mult := 1.0
	if prof == "stealth":
		mult *= 0.7
	if class_id == "spider":
		mult *= 0.65
	if class_id == "kennelmaster":
		mult *= 0.8
	return mult


# ------------------------------------------------------------------ helpers
func _scene() -> Node:
	var t: SceneTree = body.get_tree()
	if t.current_scene != null:
		return t.current_scene
	return t.root


func _enemies_near(pos: Vector3, radius: float) -> Array:
	var out := []
	for e in body.get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and e.has_method("is_alive") and e.is_alive():
			if (e as Node3D).global_position.distance_to(pos) <= radius:
				out.append(e)
	return out


func _ground_snap(p: Vector3) -> Vector3:
	var sc := _scene()
	if sc != null and sc.get("map") != null and (sc.get("map") as Node).has_method("ground_height"):
		var m = sc.get("map")
		return Vector3(p.x, m.ground_height(p.x, p.z), p.z)
	return p


func _aim_target(max_dist: float) -> Vector3:
	if not is_player or body.get("camera") == null:
		return body.global_position + Vector3(0, 0, -10)
	var cam: Camera3D = body.get("camera")
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist)
	q.exclude = [body]
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return from + dir * max_dist
	return hit["position"]


func _throw_arc_to(target: Vector3, arc_h: float, dur: float, on_land: Callable) -> void:
	var n := Node3D.new()
	_scene().add_child(n)
	n.global_position = body.global_position + Vector3(0, 1.4, 0)
	var tw := _scene().create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "global_position:x", target.x, dur)
	tw.tween_property(n, "global_position:z", target.z, dur)
	tw.tween_property(n, "global_position:y", target.y + arc_h, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(n, "global_position:y", target.y, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		on_land.call(target)
		n.queue_free()
	)


func _holo_soldier(pos: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	_scene().add_child(root)
	var cap := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.7
	cap.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cap.set_surface_override_material(0, m)
	cap.position = Vector3(0, 0.95, 0)
	root.add_child(cap)
	return root


# ------------------------------------------------------------------ TRACKER
func _a_sensor_dart() -> bool:
	var target := _aim_target(40.0)
	_throw_arc_to(target, 4.0, 0.6, func(land: Vector3) -> void:
		ClassFX.ground_ring(_scene(), land, 30.0, 1.5, Color(1.0, 0.72, 0.15, 0.7))
		for e in _enemies_near(land, 30.0):
			_mark_enemy(e, 8.0)
	)
	return true


func _mark_enemy(e: Node, dur: float) -> void:
	if float(e.get("_marked_t")) > 0.0:
		e.set("_marked_t", dur)
		return
	e.set("_marked_t", dur)
	var mk := ClassFX.marker(e, e, dur, Color(1.0, 0.25, 0.2))
	mk.position = Vector3.ZERO


## Called by the player when they damage an enemy (tracker marking).
func on_damaged_enemy(e: Node) -> void:
	if not is_player:
		return
	if prof == "tracker":
		_mark_enemy(e, 6.0 if class_id == "pathfinder" else 5.0)


func _a_hound() -> bool:
	_hound = CharacterBody3D.new()
	_hound.position = body.global_position + Vector3(1.5, 0.5, 0)
	_scene().add_child(_hound)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.6, 1.1)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.16, 0.18)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.4, 0.1)
	mi.set_surface_override_material(0, m)
	mi.position = Vector3(0, 0.45, 0)
	_hound.add_child(mi)
	_hound_t = 20.0
	_hound_hp = 30.0
	_hound_cd = 0.0
	return true


func _hound_tick(delta: float) -> void:
	if _hound == null or not is_instance_valid(_hound):
		_hound = null
		return
	_hound_t -= delta
	if _hound_t <= 0.0:
		_hound.queue_free()
		_hound = null
		return
	var best: Node3D = null
	var bd := 40.0
	for e in _enemies_near(_hound.global_position, 40.0):
		var d := (e as Node3D).global_position.distance_to(_hound.global_position)
		if d < bd:
			bd = d
			best = e
	if best == null:
		# Follow owner.
		var to: Vector3 = body.global_position - _hound.global_position
		to.y = 0.0
		if to.length() > 3.0:
			_hound.velocity = to.normalized() * 7.0
		else:
			_hound.velocity = Vector3.ZERO
	else:
		var to2: Vector3 = best.global_position - _hound.global_position
		to2.y = 0.0
		if to2.length() > 1.2:
			_hound.velocity = to2.normalized() * 8.5
		else:
			_hound.velocity = Vector3.ZERO
			_hound_cd -= delta
			if _hound_cd <= 0.0:
				_hound_cd = 0.8
				best.take_damage(8, best.global_position, "melee")
	_hound.velocity.y = -9.0
	_hound.move_and_slide()


func _a_emp_drone() -> bool:
	_drone = ClassFX.deploy_base(_scene(), body.global_position + Vector3(0, 2.0, 0), accent, 0.3, 0.4)
	_drone_t = 15.0
	_drone_pulse = 0.0
	return true


func _drone_tick(delta: float) -> void:
	if _drone == null or not is_instance_valid(_drone):
		_drone = null
		return
	_drone_t -= delta
	if _drone_t <= 0.0:
		_drone.queue_free()
		_drone = null
		return
	var best: Node3D = null
	var bd := 45.0
	for e in _enemies_near(_drone.global_position, 45.0):
		var d := (e as Node3D).global_position.distance_to(_drone.global_position)
		if d < bd:
			bd = d
			best = e
	if best != null:
		var want: Vector3 = best.global_position + Vector3(0, 3.0, 0)
		_drone.global_position = _drone.global_position.lerp(want, 2.0 * delta)
	_drone_pulse -= delta
	if _drone_pulse <= 0.0:
		_drone_pulse = 3.0
		ClassFX.ground_ring(_scene(), _drone.global_position, 12.0, 0.8, Color(0.4, 0.8, 1.0, 0.6))
		for e in _enemies_near(_drone.global_position, 12.0):
			if e.has_method("apply_slow"):
				e.apply_slow(0.5, 3.0)
			if e.get("_shot_timer") != null:
				e.set("_shot_timer", maxf(float(e.get("_shot_timer")), 2.0))


func _a_catapult() -> bool:
	var pad := ClassFX.deploy_base(_scene(), body.global_position, accent, 0.9, 0.25)
	var tw := _scene().create_tween()
	tw.tween_interval(25.0)
	tw.tween_callback(pad.queue_free)
	# Launch pad trigger: poll in _process via _pads list.
	_pads.append({"node": pad, "pos": pad.global_position, "kind": "skyhook", "t": 25.0})
	return true


func _pads_tick(delta: float) -> void:
	for i in range(_pads.size() - 1, -1, -1):
		var p: Dictionary = _pads[i]
		p["t"] = float(p["t"]) - delta
		var nd: Node = p["node"]
		if float(p["t"]) <= 0.0 or nd == null or not is_instance_valid(nd):
			if nd != null and is_instance_valid(nd):
				nd.queue_free()
			_pads.remove_at(i)
			continue
		if not body.is_alive():
			continue
		var pp: Vector3 = p["pos"]
		if body.global_position.distance_to(pp) < 1.8 and body.get("dropping") == false:
			if str(p["kind"]) == "skyhook":
				var fwd: Vector3 = -body.global_transform.basis.z
				fwd.y = 0.0
				body.velocity = fwd.normalized() * 10.0 + Vector3(0, 17.0, 0)
				body.set("dropping", true)
				if body.has_method("show_chute"):
					body.show_chute(true)
				nd.queue_free()
				_pads.remove_at(i)
			elif str(p["kind"]) == "bounce":
				body.velocity.y = 19.5
				ClassFX.ground_ring(_scene(), pp, 2.5, 0.5, accent)
			# Enemies bounce too.
			for e in body.get_tree().get_nodes_in_group("enemies"):
				if e is CharacterBody3D and (e as Node3D).global_position.distance_to(pp) < 1.8:
					(e as CharacterBody3D).velocity.y = 16.0


func _a_mortar() -> bool:
	_mortar = ClassFX.deploy_base(_scene(), _ground_snap(body.global_position + Vector3(2.0, 0, 0)), accent, 0.5, 1.1)
	_mortar_n = 6
	_mortar_t = 0.5
	_mortar_dur = 12.0
	return true


func _mortar_tick(delta: float) -> void:
	if _mortar == null or not is_instance_valid(_mortar):
		_mortar = null
		return
	_mortar_dur -= delta
	if _mortar_dur <= 0.0 or _mortar_n <= 0:
		_mortar.queue_free()
		_mortar = null
		return
	_mortar_t -= delta
	if _mortar_t > 0.0:
		return
	_mortar_t = 1.3
	var foes := _enemies_near(_mortar.global_position, 45.0)
	if foes.is_empty():
		return
	_mortar_n -= 1
	var tgt: Node3D = foes[randi() % foes.size()]
	_throw_arc_to(tgt.global_position, 10.0, 0.9, func(land: Vector3) -> void:
		_scene().spawn_explosion(land, 3.0)
		for e in _enemies_near(land, 3.5):
			e.take_damage(25, land, "explosive")
	)


# ------------------------------------------------------------------ SUPPORT
func _a_heal_station() -> bool:
	_station_pos = _ground_snap(body.global_position)
	_station_t = 12.0
	ClassFX.deploy_base(_scene(), _station_pos, accent, 0.5, 1.0)
	ClassFX.dome(_scene(), _station_pos, 6.0, 12.0, Color(0.25, 0.85, 0.45, 0.14))
	return true


func _station_tick(delta: float) -> void:
	if _station_t <= 0.0:
		return
	_station_t -= delta
	if body.global_position.distance_to(_station_pos) <= 6.0 and body.is_alive():
		var before: int = body.hp
		body.hp = mini(body.hp + int(12.0 * delta) + 1, body.max_hp + 25)
		if body.hp > body.max_hp:
			_temp_hp = minf(_temp_hp + 4.0 * delta, 25.0)
		if body.hp != before and body.has_signal("health_changed"):
			body.emit_signal("health_changed", body.hp, body.max_hp, body.get("armor") if body.get("armor") != null else 0)


func _a_supply() -> bool:
	var LootScene: PackedScene = load("res://scenes/loot.tscn")
	for i in range(3):
		var l = LootScene.instantiate()
		l.kind = "armor" if i < 2 else "ammo"
		l.amount = 50 if i < 2 else 60
		l.tier = 2
		_scene().add_child(l)
		var off := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		l.position = _ground_snap(body.global_position + off) + Vector3(0, 0.55, 0)
	ClassFX.ground_ring(_scene(), body.global_position, 3.0, 1.0, accent)
	return true


func _a_dome() -> bool:
	_dome_pos = body.global_position
	_dome_t = 10.0
	ClassFX.dome(_scene(), _dome_pos, 5.0, 10.0, Color(0.3, 0.7, 1.0, 0.22))
	return true


func _a_guardian() -> bool:
	_guard_t = 15.0
	_guard_cd = 0.0
	ClassFX.deploy_base(_scene(), body.global_position + Vector3(0, 2.2, 0), accent, 0.25, 0.3)
	return true


func _guardian_tick(delta: float) -> void:
	if _guard_t <= 0.0:
		return
	_guard_t -= delta
	_guard_cd -= delta
	if _guard_cd > 0.0:
		return
	_guard_cd = 1.2
	var foes := _enemies_near(body.global_position, 30.0)
	if foes.is_empty():
		return
	var tgt: Node3D = foes[0]
	tgt.take_damage(12, tgt.global_position, "bullet")
	ClassFX.beam(_scene(), body.global_position + Vector3(0, 2.2, 0), tgt.global_position + Vector3(0, 1.2, 0), 0.25, accent, 0.04)


func _a_mirror() -> bool:
	var sc := _scene()
	var loots: Array = sc.get("loots") if sc.get("loots") != null else []
	var near := []
	for l in loots:
		if l is Node3D and is_instance_valid(l) and (l as Node3D).global_position.distance_to(body.global_position) < 12.0:
			near.append(l)
	near.sort_custom(func(a, b): return (a as Node3D).global_position.distance_to(body.global_position) < (b as Node3D).global_position.distance_to(body.global_position))
	var LootScene: PackedScene = load("res://scenes/loot.tscn")
	var n := 0
	for l in near:
		if n >= 3:
			break
		var c = LootScene.instantiate()
		c.kind = l.get("kind")
		c.amount = l.get("amount")
		c.tier = l.get("tier")
		_scene().add_child(c)
		c.position = (l as Node3D).global_position + Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1.5, 1.5))
		n += 1
	cd_left = maxf(0.0, cd_left - cd_total * 0.5)
	ClassFX.ground_ring(_scene(), body.global_position, 4.0, 1.0, accent)
	return true


# ------------------------------------------------------------------ DISRUPT
func _a_trap() -> bool:
	if _traps.size() >= 3:
		var old: Dictionary = _traps.pop_front()
		if old["node"] != null and is_instance_valid(old["node"]):
			(old["node"] as Node).queue_free()
	var pos: Vector3 = _ground_snap(body.global_position)
	var node := ClassFX.deploy_base(_scene(), pos, accent, 0.35, 0.5)
	ClassFX.dome(_scene(), pos, 4.0, 60.0, Color(0.75, 0.35, 1.0, 0.12))
	_traps.append({"node": node, "pos": pos, "t": 60.0})
	# Chain-link visual to nearby traps.
	for t2 in _traps:
		var p2: Vector3 = t2["pos"]
		if p2.distance_to(pos) > 0.1 and p2.distance_to(pos) < 9.0:
			ClassFX.beam(_scene(), pos + Vector3(0, 0.6, 0), p2 + Vector3(0, 0.6, 0), 60.0, accent, 0.03)
	return true


func _traps_tick(delta: float) -> void:
	for i in range(_traps.size() - 1, -1, -1):
		var t: Dictionary = _traps[i]
		t["t"] = float(t["t"]) - delta
		if float(t["t"]) <= 0.0:
			if t["node"] != null and is_instance_valid(t["node"]):
				(t["node"] as Node).queue_free()
			_traps.remove_at(i)
			continue
		var p: Vector3 = t["pos"]
		for e in _enemies_near(p, 4.0):
			if e.has_method("apply_slow"):
				e.apply_slow(0.5, 0.6)
			e.take_damage(int(8.0 * delta) + 1, p, "explosive")


func _a_rewind() -> bool:
	if _hist.is_empty():
		return false
	var h: Dictionary = _hist[0]
	body.global_position = h["p"]
	body.velocity = Vector3.ZERO
	body.hp = int(h["hp"])
	if body.get("armor") != null:
		body.set("armor", int(h["armor"]))
	if body.has_signal("health_changed"):
		body.emit_signal("health_changed", body.hp, body.max_hp, body.get("armor") if body.get("armor") != null else 0)
	# Time-echo decoy at departure point.
	var dec := _holo_soldier(body.global_position, Color(0.5, 0.8, 1.0, 0.5))
	_decoys.append({"node": dec, "t": 6.0, "vel": Vector3.ZERO, "echo": true})
	_hist.clear()
	ClassFX.ground_ring(_scene(), body.global_position, 3.0, 1.0, accent)
	return true


func _a_decoys() -> bool:
	for i in range(2):
		var ang := randf() * TAU
		var pos: Vector3 = body.global_position + Vector3(cos(ang) * 3.0, 0, sin(ang) * 3.0)
		var dec := _holo_soldier(_ground_snap(pos), Color(0.6, 0.9, 1.0, 0.45))
		var vel := Vector3(cos(ang + 1.2), 0, sin(ang + 1.2)) * 3.5
		_decoys.append({"node": dec, "t": 8.0, "vel": vel, "echo": false})
		# Enemies investigate the decoys.
		for e in _enemies_near(pos, 30.0):
			if e.has_method("investigate"):
				e.investigate(pos, 8.0)
	# Brief invisibility for the real user.
	if body.get("invisible_t") != null:
		body.set("invisible_t", 3.0)
	return true


func _decoys_tick(delta: float) -> void:
	for i in range(_decoys.size() - 1, -1, -1):
		var d: Dictionary = _decoys[i]
		d["t"] = float(d["t"]) - delta
		var nd: Node = d["node"]
		if float(d["t"]) <= 0.0 or nd == null or not is_instance_valid(nd):
			if nd != null and is_instance_valid(nd):
				# Mirage parting gift: destroyed decoys pop.
				if class_id == "mirage" and not bool(d.get("echo", false)):
					for e in _enemies_near((nd as Node3D).global_position, 3.0):
						e.take_damage(15, (nd as Node3D).global_position, "explosive")
					_scene().spawn_explosion((nd as Node3D).global_position, 2.0)
				nd.queue_free()
			_decoys.remove_at(i)
			continue
		var v: Vector3 = d["vel"]
		if v.length() > 0.01:
			(nd as Node3D).position += v * delta


func _a_smoke() -> bool:
	var target := _aim_target(25.0)
	_smoke_pos = _ground_snap(target)
	_smoke_t = 12.0
	ClassFX.smoke_column(_scene(), _smoke_pos, 8.0, 12.0, Color(0.5, 0.5, 0.52, 0.8), "wildfire")
	for e in _enemies_near(_smoke_pos, 8.0):
		_mark_enemy(e, 12.0)
	return true


func _smoke_tick(delta: float) -> void:
	if _smoke_t <= 0.0:
		return
	_smoke_t -= delta
	for e in _enemies_near(_smoke_pos, 8.0):
		if e.has_method("apply_slow"):
			# Wildfire user is immune to the slow; enemies are not.
			e.apply_slow(0.6, 0.6)


func _a_jam() -> bool:
	_jam_pos = body.global_position
	_jam_t = 10.0
	ClassFX.dome(_scene(), _jam_pos, 20.0, 10.0, Color(0.75, 0.35, 1.0, 0.1))
	return true


func _jam_tick(delta: float) -> void:
	if _jam_t <= 0.0:
		return
	_jam_t -= delta
	for e in _enemies_near(_jam_pos, 20.0):
		if e.get("_shot_timer") != null:
			e.set("_shot_timer", maxf(float(e.get("_shot_timer")), 1.0))
		if e.has_method("set_jammed"):
			e.set_jammed(true, 0.5)


func _a_shockwave() -> bool:
	ClassFX.ground_ring(_scene(), body.global_position, 8.0, 0.7, Color(1.0, 0.85, 0.3, 0.8))
	for e in _enemies_near(body.global_position, 8.0):
		var dir: Vector3 = ((e as Node3D).global_position - body.global_position)
		dir.y = 0.0
		(e as Node3D).global_position += dir.normalized() * 5.0
		if e.has_method("stun"):
			e.stun(3.0)
	return true


func _a_phantom() -> bool:
	var target := _aim_target(30.0)
	# Phantom firefight: enemies in 40m investigate the fake sounds.
	for e in _enemies_near(body.global_position, 40.0):
		if e.has_method("investigate"):
			e.investigate(_ground_snap(target), 8.0)
	ClassFX.ground_ring(_scene(), target, 4.0, 1.5, Color(0.75, 0.35, 1.0, 0.5))
	return true


func _a_lightning() -> bool:
	var struck := []
	var from: Vector3 = body.global_position
	for i in range(4):
		var best: Node3D = null
		var bd := 18.0
		for e in _enemies_near(from, 18.0):
			if e in struck:
				continue
			var d := (e as Node3D).global_position.distance_to(from)
			if d < bd:
				bd = d
				best = e
		if best == null:
			break
		struck.append(best)
		ClassFX.beam(_scene(), from + Vector3(0, 1.5, 0), best.global_position + Vector3(0, 1.2, 0), 0.4, Color(0.6, 0.8, 1.0), 0.08)
		best.take_damage(25, best.global_position, "explosive")
		if best.has_method("apply_slow"):
			best.apply_slow(0.5, 3.0)
		from = best.global_position
	_overcharge_t = 6.0
	return not struck.is_empty()


# ------------------------------------------------------------------ DEFENSE
func _a_wall() -> bool:
	var fwd: Vector3 = -body.global_transform.basis.z
	fwd.y = 0.0
	var pos: Vector3 = _ground_snap(body.global_position + fwd.normalized() * 2.5)
	_wall = Node3D.new()
	_wall.position = pos
	_scene().add_child(_wall)
	var sb := StaticBody3D.new()
	_wall.add_child(sb)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 2.2, 0.25)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.24, 0.3)
	m.metallic = 0.4
	mi.set_surface_override_material(0, m)
	mi.position = Vector3(0, 1.1, 0)
	_wall.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.2, 0.25)
	cs.shape = shape
	cs.position = Vector3(0, 1.1, 0)
	sb.add_child(cs)
	_wall.look_at(pos + fwd.normalized() * 5.0, Vector3.UP)
	# Flashbang pulse on deploy: stun nearby enemies' gunfire.
	for e in _enemies_near(pos, 10.0):
		if e.has_method("stun"):
			e.stun(4.0)
	ClassFX.ground_ring(_scene(), pos, 3.0, 0.8, Color(1.0, 1.0, 1.0, 0.9))
	return true


func _recall_wall() -> void:
	if _wall != null and is_instance_valid(_wall):
		_wall.queue_free()
	_wall = null
	cd_left = cd_total * 0.5
	_refresh_button()


func _a_turret() -> bool:
	var pos: Vector3 = _ground_snap(body.global_position + Vector3(2.0, 0, 0))
	_turret = ClassFX.deploy_base(_scene(), pos, accent, 0.5, 1.0)
	_turret_t = 60.0
	_turret_cd = 0.5
	return true


func _turret_tick(delta: float) -> void:
	if _turret == null or not is_instance_valid(_turret):
		_turret = null
		return
	_turret_t -= delta
	if _turret_t <= 0.0:
		_turret.queue_free()
		_turret = null
		return
	_turret_cd -= delta
	if _turret_cd > 0.0:
		return
	_turret_cd = 1.5
	var foes := _enemies_near(_turret.global_position, 30.0)
	if foes.is_empty():
		return
	var tgt: Node3D = foes[0]
	tgt.take_damage(12, tgt.global_position, "bullet")
	ClassFX.beam(_scene(), _turret.global_position + Vector3(0, 1.2, 0), tgt.global_position + Vector3(0, 1.0, 0), 0.2, Color(1.0, 0.8, 0.3), 0.05)


func _a_strike() -> bool:
	_strike_pos = _ground_snap(_aim_target(45.0))
	_strike_t = 2.0
	_strike_n = 5
	# Laser designator beam.
	ClassFX.beam(_scene(), body.global_position + Vector3(0, 1.5, 0), _strike_pos + Vector3(0, 8.0, 0), 2.0, Color(1.0, 0.2, 0.2), 0.06)
	return true


func _strike_tick(delta: float) -> void:
	if _strike_t < 0.0:
		return
	_strike_t -= delta
	if _strike_t > 0.0:
		return
	if _strike_n <= 0:
		_strike_t = -1.0
		return
	_strike_n -= 1
	_strike_t = 0.8
	var off := Vector3(randf_range(-6.0, 6.0), 0, randf_range(-6.0, 6.0))
	var p: Vector3 = _strike_pos + off
	_scene().spawn_explosion(p, 4.0)
	for e in _enemies_near(p, 5.0):
		e.take_damage(30, p, "explosive")


func _a_tar() -> bool:
	_tar_pos = _ground_snap(_aim_target(22.0))
	_tar_t = 12.0
	_tar_node = ClassFX.dome(_scene(), _tar_pos, 6.0, 12.0, Color(0.12, 0.1, 0.08, 0.55))
	return true


func _detonate_tar() -> void:
	if _tar_t <= 0.0:
		return
	_tar_t = 0.0
	if _tar_node != null and is_instance_valid(_tar_node):
		_tar_node.queue_free()
	_tar_node = null
	_scene().spawn_explosion(_tar_pos, 4.5)
	for e in _enemies_near(_tar_pos, 6.5):
		e.take_damage(40, _tar_pos, "explosive")
	cd_left = cd_total
	_refresh_button()


func _tar_tick(delta: float) -> void:
	if _tar_t <= 0.0:
		return
	_tar_t -= delta
	if _tar_t <= 0.0 and _tar_node != null and is_instance_valid(_tar_node):
		_tar_node.queue_free()
		_tar_node = null
		return
	for e in _enemies_near(_tar_pos, 6.0):
		if e.has_method("apply_slow"):
			e.apply_slow(0.4, 0.6)
		e.take_damage(int(6.0 * delta) + 1, _tar_pos, "explosive")


func _a_radiation() -> bool:
	_rad_pos = _ground_snap(body.global_position)
	_rad_t = 15.0
	_rad_heat.clear()
	ClassFX.dome(_scene(), _rad_pos, 7.0, 15.0, Color(0.4, 1.0, 0.3, 0.16))
	return true


func _rad_tick(delta: float) -> void:
	if _rad_t <= 0.0:
		return
	_rad_t -= delta
	var seen := {}
	for e in _enemies_near(_rad_pos, 7.0):
		var id: int = e.get_instance_id()
		seen[id] = true
		_rad_heat[id] = float(_rad_heat.get(id, 0.0)) + delta
		var dps := 10.0 + 5.0 * float(_rad_heat[id])
		e.take_damage(int(dps * delta) + 1, _rad_pos, "zone")
	for id in _rad_heat.keys():
		if not seen.has(id):
			_rad_heat.erase(id)


# ------------------------------------------------------------------ STEALTH
func _a_grapple() -> bool:
	var target := _aim_target(40.0)
	_grapple_to = target
	_grappling = true
	_grapple_beam = ClassFX.beam(_scene(), body.global_position + Vector3(0, 1.5, 0), target, 30.0, Color(0.8, 0.8, 0.85), 0.04)
	return true


func _grapple_physics(delta: float) -> void:
	if not _grappling:
		return
	var to: Vector3 = _grapple_to - body.global_position
	if to.length() < 2.0:
		_grappling = false
		if _grapple_beam != null and is_instance_valid(_grapple_beam):
			_grapple_beam.queue_free()
		_grapple_beam = null
		# Spider drop attack: landing on an enemy from above.
		for e in _enemies_near(body.global_position, 3.0):
			e.take_damage(75, (e as Node3D).global_position, "melee")
		return
	body.velocity = to.normalized() * 24.0
	if _grapple_beam != null and is_instance_valid(_grapple_beam):
		_grapple_beam.queue_free()
		_grapple_beam = ClassFX.beam(_scene(), body.global_position + Vector3(0, 1.5, 0), _grapple_to, 0.2, Color(0.8, 0.8, 0.85), 0.04)


func _a_camo() -> bool:
	if body.get("invisible_t") != null:
		body.set("invisible_t", 8.0)
	_wraith_dmg_t = 0.0
	return true


func _a_comet() -> bool:
	body.velocity.y = 14.0
	_jet_t = 4.0
	_jet_kind = "comet"
	_comet_slam = false
	return true


func _comet_slam_start() -> void:
	_comet_slam = true
	body.velocity = Vector3(0, -30.0, 0)


func _a_dash() -> bool:
	var dir: Vector3 = -body.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var from: Vector3 = body.global_position
	body.global_position = _ground_snap(from + dir * 12.0) + Vector3(0, 0.1, 0)
	ClassFX.ground_ring(_scene(), from, 2.0, 0.5, accent)
	# Damage enemies along the dash path, chain up to 3.
	var hit := 0
	var chain_from: Vector3 = body.global_position
	for i in range(3):
		var best: Node3D = null
		var bd := 10.0
		for e in _enemies_near(chain_from, 10.0):
			var d := (e as Node3D).global_position.distance_to(chain_from)
			if d < bd:
				bd = d
				best = e
		if best == null:
			break
		best.take_damage(50, best.global_position, "melee")
		hit += 1
		chain_from = best.global_position
		var d2: Vector3 = (best.global_position - body.global_position)
		d2.y = 0.0
		if d2.length() > 0.5 and hit < 3:
			body.global_position = _ground_snap(best.global_position - d2.normalized() * 2.0) + Vector3(0, 0.1, 0)
	_deflect_t = 1.5
	return true


func _a_jetpack() -> bool:
	_jet_t = 6.0
	_jet_kind = "valkyrie"
	return true


func _jet_physics(delta: float) -> void:
	if _jet_t <= 0.0:
		return
	_jet_t -= delta
	if _jet_kind == "valkyrie":
		var dir: Vector3 = -body.global_transform.basis.z
		body.velocity = dir * 8.0 + Vector3(0, 2.5, 0)
		if _jet_t <= 0.0:
			body.velocity = Vector3.ZERO
	elif _jet_kind == "comet":
		# Nitrogen air control: soften falls, allow steering.
		if not body.is_on_floor():
			body.velocity.y = maxf(body.velocity.y, -3.0)
		if _comet_slam and body.is_on_floor():
			_comet_slam = false
			_jet_t = 0.0
			_scene().spawn_explosion(body.global_position, 3.0)
			for e in _enemies_near(body.global_position, 5.0):
				e.take_damage(30, body.global_position, "explosive")
			ClassFX.ground_ring(_scene(), body.global_position, 5.0, 0.8, accent)


func _a_beacon() -> bool:
	var target := _aim_target(20.0)
	_beacon_pos = _ground_snap(target)
	_beacon = ClassFX.deploy_base(_scene(), _beacon_pos, accent, 0.35, 0.8)
	_beacon_t = 30.0
	return true


func _blink_to_beacon() -> void:
	if _beacon == null or not is_instance_valid(_beacon):
		return
	var keep: Vector3 = body.velocity
	body.global_position = _beacon_pos + Vector3(0, 0.6, 0)
	body.velocity = keep
	ClassFX.ground_ring(_scene(), _beacon_pos, 2.5, 0.8, accent)
	_beacon.queue_free()
	_beacon = null
	_beacon_t = 0.0
	cd_left = cd_total
	_refresh_button()


func _a_pad() -> bool:
	var pos: Vector3 = _ground_snap(body.global_position + Vector3(1.5, 0, 0))
	var pad := ClassFX.deploy_base(_scene(), pos, accent, 0.9, 0.25)
	_pads.append({"node": pad, "pos": pos, "kind": "bounce", "t": 40.0})
	return true


func _detonate_pads() -> void:
	for p in _pads:
		var pp: Vector3 = p["pos"]
		ClassFX.ground_ring(_scene(), pp, 3.0, 0.6, accent)
		for e in body.get_tree().get_nodes_in_group("enemies"):
			if e is CharacterBody3D and (e as Node3D).global_position.distance_to(pp) < 2.5:
				(e as CharacterBody3D).velocity.y = 17.0
		var nd: Node = p["node"]
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	_pads.clear()
	cd_left = cd_total
	_refresh_button()


# ------------------------------------------------------------------ per-frame
func _process(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	_t += delta
	# Cooldown.
	if cd_left > 0.0:
		cd_left = maxf(0.0, cd_left - delta)
		_refresh_button()
	# Timers.
	_disrupt_t = maxf(0.0, _disrupt_t - delta)
	_overcharge_t = maxf(0.0, _overcharge_t - delta)
	_deflect_t = maxf(0.0, _deflect_t - delta)
	_wraith_dmg_t = maxf(0.0, _wraith_dmg_t - delta)
	if _dome_t > 0.0:
		_dome_t -= delta
	_temp_hp = maxf(0.0, _temp_hp - 5.0 * delta)
	# Wraith camo break: firing ends invisibility, arms the damage buff.
	if is_player and class_id == "wraith" and body.get("invisible_t") != null:
		if float(body.get("invisible_t")) > 0.0 and bool(body.get("_was_firing")):
			body.set("invisible_t", 0.0)
			_wraith_dmg_t = 3.0
	# Chronos history (8s ring buffer). Safe armor read: enemies have no armor var.
	if class_id == "chronos" and is_player and body.is_alive():
		_hist_t -= delta
		if _hist_t <= 0.0:
			_hist_t = 0.5
			var _harm := 0
			if body.get("armor") != null:
				_harm = int(body.get("armor"))
			_hist.push_front({"p": body.global_position, "hp": body.hp, "armor": _harm})
			while _hist.size() > 16:
				_hist.pop_back()
	# Ability button: reposition once a real viewport exists.
	if not _btn_placed and _btn != null and is_instance_valid(_btn):
		var _bv: Viewport = get_viewport()
		if _bv != null:
			var _bvp: Vector2 = _bv.get_visible_rect().size
			_btn.position = Vector2(_bvp.x * 0.5 + 170, _bvp.y - 120)
			_btn_placed = true
	# Support profession: steady bonus regen.
	if is_player and prof == "support" and body.is_alive() and body.hp < body.max_hp:
		var bonus := 10.0 if class_id == "surgeon" else 6.0
		body.hp = mini(body.hp + int(bonus * delta) + 1, body.max_hp)
	# Disrupt profession speed bonus.
	_apply_disrupt_speed()
	# Ability entity ticks.
	_station_tick(delta)
	_turret_tick(delta)
	_mortar_tick(delta)
	_drone_tick(delta)
	_guardian_tick(delta)
	_hound_tick(delta)
	_traps_tick(delta)
	_decoys_tick(delta)
	_smoke_tick(delta)
	_jam_tick(delta)
	_strike_tick(delta)
	_tar_tick(delta)
	_rad_tick(delta)
	_pads_tick(delta)
	if _beacon_t > 0.0:
		_beacon_t -= delta
		if _beacon_t <= 0.0 and _beacon != null and is_instance_valid(_beacon):
			_beacon.queue_free()
			_beacon = null
	# Desktop hotkey.
	if is_player and Input.is_key_pressed(KEY_X):
		if not _x_was:
			_x_was = true
			try_activate()
	else:
		_x_was = false
	# Enemy simple ability AI.
	if not is_player:
		_tick_slow -= delta
		if _tick_slow <= 0.0:
			_tick_slow = 1.0
			_enemy_ability_tick()


func _physics_process(delta: float) -> void:
	if body == null or not is_instance_valid(body) or not body.is_alive():
		return
	_grapple_physics(delta)
	_jet_physics(delta)
	if _hound != null and is_instance_valid(_hound):
		pass  # hound moves in _hound_tick via velocity + move_and_slide


func _apply_disrupt_speed() -> void:
	if not is_player or body.get("class_speed_mult") == null:
		return
	var want := speed_bonus()
	if _disrupt_t > 0.0:
		want *= 1.15
	body.set("class_speed_mult", want)


func _enemy_ability_tick() -> void:
	# Simple class usage for AI enemies.
	if not body.is_alive():
		return
	var p: Variant = _enemy_player()
	match class_id:
		"surgeon":
			if body.hp < 50 and cd_left <= 0.0:
				cd_left = 30.0
				body.hp = mini(body.hp + 30, 100)
		"wildfire":
			if body.hp < 40 and cd_left <= 0.0:
				cd_left = 35.0
				ClassFX.smoke_column(_scene(), body.global_position, 5.0, 8.0, Color(0.5, 0.5, 0.52, 0.8), "e-smoke")
		"warden":
			if p != null and (p as Node3D).global_position.distance_to(body.global_position) < 8.0 and cd_left <= 0.0:
				cd_left = 20.0
				_a_trap()
		"ballista":
			if p != null and cd_left <= 0.0:
				cd_left = 12.0
				var tgt := (p as Node3D).global_position
				ClassFX.ground_ring(_scene(), tgt, 3.0, 1.0, Color(1.0, 0.4, 0.2, 0.7))
				_throw_arc_to(tgt, 8.0, 1.0, func(land: Vector3) -> void:
					_scene().spawn_explosion(land, 2.5)
					if p != null and is_instance_valid(p) and (p as Node3D).global_position.distance_to(land) < 3.0:
						p.take_damage(15, land, "explosive")
				)


func _enemy_player():
	var sc := _scene()
	if sc != null and sc.get("player") != null:
		return sc.get("player")
	return null
