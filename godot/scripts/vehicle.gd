class_name NovaVehicle
extends CharacterBody3D
## NOVA Mobile: drivable vehicle — arcade physics per locomotion type,
## enter/exit, damage/destruction chain, and vehicle weapons
## (tank cannon, heli minigun, B2 bombs).

signal exploded(vehicle: NovaVehicle)
signal cannon_fired(vehicle: NovaVehicle)

var vid := "sedan"
var spec: Dictionary = {}
var driver = null  # NovaPlayer
var hp := 100.0
var max_hp := 100.0
var speed := 0.0  # signed forward speed
var destroyed := false
var flying := false  # heli / plane airborne state

var _parts: Dictionary = {}
var _model: Node3D = null
var _wheels: Array = []
var _steer: Array = []
var _cannon_cd := 0.0
var _bomb_cd := 0.0
var _bombs_left := 0
var _minigun_acc := 0.0
var _smoke: CPUParticles3D = null
var _fire: CPUParticles3D = null
var _smoking := false
var _burning := false
var _vy := 0.0  # heli vertical velocity
var _col: CollisionShape3D = null
# Nitro / lights / audio / skins.
var nitro := 100.0
var lights_on := false
var skin_idx := 0
var skin_name := ""
# Fuel: fuel-burning vehicles drain the tank; dry = engine dead (cover only).
var fuel := 0.0
var max_fuel := 0.0
var out_of_fuel := false
var _headlights: Array = []
var _audio_engine: AudioStreamPlayer3D = null
var _audio_one: AudioStreamPlayer3D = null
var _audio_skid: AudioStreamPlayer3D = null
var _thud_cd := 0.0


func _ready() -> void:
	spec = VehicleDefs.spec(vid)
	max_hp = float(spec["hp"])
	hp = max_hp
	max_fuel = float(spec.get("fuel_cap", 0.0))
	fuel = max_fuel  # spawn with a full tank
	_bombs_left = int(spec.get("bomb_count", 0))
	_parts = VehicleModels.build(vid)
	_model = _parts["root"]
	add_child(_model)
	_wheels = _parts.get("wheels", [])
	_steer = _parts.get("steer", [])
	_col = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(_parts.get("width", 2.0)), float(_parts.get("height", 1.5)), float(_parts.get("length", 4.5)))
	_col.shape = box
	_col.position.y = float(_parts.get("height", 1.5)) * 0.5
	add_child(_col)
	collision_layer = 2
	collision_mask = 1
	# Random paint job.
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	skin_idx = VehicleSkins.random_idx(vid, rng)
	skin_name = str(VehicleSkins.skin(vid, skin_idx)["name"])
	VehicleSkins.apply(_parts, vid, skin_idx)
	_build_headlights()
	_build_audio()


func _build_headlights() -> void:
	# Two spotlights at the front; toggled with L / LAMP button.
	var length := float(_parts.get("length", 4.5))
	var width := float(_parts.get("width", 2.0))
	for sx in [-1.0, 1.0]:
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.95, 0.85)
		sp.light_energy = 0.0
		sp.spot_range = 30.0
		sp.spot_angle = 28.0
		sp.position = Vector3(sx * width * 0.32, 0.9, -length * 0.48)
		sp.rotation.y = PI  # face -Z (forward)
		add_child(sp)
		_headlights.append(sp)


func toggle_lights() -> void:
	lights_on = not lights_on
	for sp in _headlights:
		(sp as SpotLight3D).light_energy = 3.0 if lights_on else 0.0


func _build_audio() -> void:
	var kind := VehicleAudio.engine_kind(vid)
	if kind != "":
		_audio_engine = AudioStreamPlayer3D.new()
		_audio_engine.stream = VehicleAudio.engine_loop(kind)
		_audio_engine.unit_size = 12.0
		_audio_engine.volume_db = -14.0
		add_child(_audio_engine)
		_audio_engine.play()
	_audio_one = AudioStreamPlayer3D.new()
	_audio_one.unit_size = 14.0
	add_child(_audio_one)
	_audio_skid = AudioStreamPlayer3D.new()
	_audio_skid.stream = VehicleAudio.skid_loop()
	_audio_skid.unit_size = 8.0
	_audio_skid.volume_db = -60.0
	add_child(_audio_skid)
	_audio_skid.play()


func honk() -> void:
	if _audio_one == null or destroyed:
		return
	_audio_one.stream = VehicleAudio.horn(VehicleAudio.horn_kind(vid))
	_audio_one.play()


func reroll_skin() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	skin_idx = VehicleSkins.random_idx(vid, rng)
	skin_name = str(VehicleSkins.skin(vid, skin_idx)["name"])
	VehicleSkins.apply(_parts, vid, skin_idx)


## Fuel: returns the effective throttle (0 when the tank runs dry).
## Idle sips, full throttle drinks.
func _apply_fuel(delta: float, throttle: float) -> float:
	if max_fuel <= 0.0 or destroyed:
		return throttle
	if out_of_fuel:
		return 0.0
	var rate := float(spec.get("fuel_rate", 0.6))
	fuel = maxf(0.0, fuel - rate * (0.25 + 0.75 * absf(throttle)) * delta)
	if fuel <= 0.01:
		out_of_fuel = true
		if driver != null:
			var hud = driver._get_hud() if driver.has_method("_get_hud") else null
			if hud != null and hud.has_method("add_killfeed"):
				hud.add_killfeed("OUT OF FUEL — find a filling station!")
		return 0.0
	return throttle


func refuel(amount: float) -> void:
	if max_fuel <= 0.0:
		return
	fuel = minf(max_fuel, fuel + amount)
	if fuel > 0.01:
		out_of_fuel = false


func needs_fuel() -> bool:
	return max_fuel > 0.0 and fuel < max_fuel - 1.0


func fuel_frac() -> float:
	if max_fuel <= 0.0:
		return 1.0
	return clampf(fuel / max_fuel, 0.0, 1.0)


func seat_position() -> Vector3:
	return to_global(_parts.get("seat", Vector3(0, 1.0, 0)))


func is_destroyed() -> bool:
	return destroyed


func enter(p) -> void:
	driver = p


func exit() -> Vector3:
	driver = null
	var side := global_transform.basis.x.normalized() * (float(_parts.get("width", 2.0)) * 0.5 + 1.2)
	return global_position + side + Vector3(0, 0.6, 0)


func _driver_input() -> Vector2:
	if driver == null:
		return Vector2.ZERO
	return driver.drive_move_input()


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	if _cannon_cd > 0.0:
		_cannon_cd -= delta
	if _bomb_cd > 0.0:
		_bomb_cd -= delta
	if driver == null:
		_parked(delta)
		return
	var loco := str(spec["loco"])
	match loco:
		"ground":
			_drive_ground(delta)
		"hover":
			_drive_hover(delta)
		"water":
			_drive_water(delta)
		"air":
			_drive_air(delta)
		"plane":
			_drive_plane(delta)
	_update_wheels(delta)
	_update_rotor(delta)
	_update_weapon_aim()


func _parked(_delta: float) -> void:
	# Parked vehicles sit still (rotor idle spin for heli looks alive).
	speed = 0.0


func _ground_height_at(p: Vector3) -> float:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("ground_height_at"):
		return scene.ground_height_at(p.x, p.z)
	if scene != null and "map" in scene and scene.map != null and scene.map.has_method("ground_height"):
		return scene.map.ground_height(p.x, p.z)
	return 0.0


func _drive_ground(delta: float) -> void:
	var inp := _driver_input()
	var top := float(spec["top_speed"])
	var throttle := -inp.y
	# Touch pedals override the joystick when pressed.
	if driver != null and driver.is_mobile:
		if driver.drive_gas:
			throttle = 1.0
		elif driver.drive_brake:
			throttle = -0.7
	# Nitro boost (N2O hold / Shift).
	var want_nitro := false
	if driver != null:
		want_nitro = driver.drive_nitro or (not driver.is_mobile and Input.is_key_pressed(KEY_SHIFT))
	if want_nitro and nitro > 1.0 and throttle > 0.1:
		top *= float(spec.get("nitro_mult", 1.5))
		nitro = maxf(nitro - 35.0 * delta, 0.0)
	else:
		nitro = minf(nitro + 12.0 * delta, 100.0)
	# Fuel: dry tank kills the throttle (engine dead, still rolls as cover).
	throttle = _apply_fuel(delta, throttle)
	var target := throttle * top
	var rate := float(spec["accel"]) if absf(target) > absf(speed) else float(spec["brake"])
	# Handbrake: hard stop + sharper rotation.
	var hbrake: bool = driver != null and (driver.drive_hbrake or (not driver.is_mobile and Input.is_key_pressed(KEY_SPACE)))
	if hbrake:
		rate = float(spec["brake"]) * 2.2
		speed = move_toward(speed, 0.0, rate * delta)
	else:
		speed = move_toward(speed, target, rate * delta)
	var steer := -inp.x
	var turn_mult := 1.7 if hbrake else 1.0
	var sf := clampf(absf(speed) / maxf(top, 1.0), 0.0, 1.0)
	rotation.y += steer * float(spec["turn_rate"]) * turn_mult * sf * signf(speed if absf(speed) > 0.5 else 1.0) * delta
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = -0.5
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	move_and_slide()
	_check_ram()
	# Bike lean into turns.
	if bool(spec.get("lean", false)) and _model != null:
		_model.rotation.z = lerpf(_model.rotation.z, steer * 0.35 * sf, 8.0 * delta)


func _drive_hover(delta: float) -> void:
	_drive_ground(delta)
	# Hover: float above terrain, glide over water and small bumps.
	var gy := _ground_height_at(global_position)
	var target_y := maxf(gy, -0.2) + float(spec.get("hover_h", 1.1))
	global_position.y = lerpf(global_position.y, target_y, 6.0 * delta)
	velocity.y = 0.0


func _drive_water(delta: float) -> void:
	var gy := _ground_height_at(global_position)
	if gy > 0.25:
		speed = move_toward(speed, 0.0, 20.0 * delta)  # beached
		return
	_drive_ground(delta)
	global_position.y = lerpf(global_position.y, -0.15, 6.0 * delta)
	velocity.y = 0.0


func _drive_air(delta: float) -> void:
	var inp := _driver_input()
	var top := float(spec["top_speed"])
	# Vertical: jump = up, crouch = down.
	var up := 0.0
	if driver.drive_up_held():
		up += 1.0
	if driver.drive_down_held():
		up -= 1.0
	_vy = move_toward(_vy, up * 9.0, 22.0 * delta)
	var wish := Vector3(inp.x, 0.0, inp.y)
	if wish.length() > 0.01:
		wish = (global_transform.basis * wish).normalized()
		var yaw_target := atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, yaw_target, 3.0 * delta)
	var planar := Vector2(wish.x, wish.z)
	var spd := planar.length() * top
	# Fuel: a dry heli can't climb or cruise (autorotates down gently).
	if max_fuel > 0.0:
		var burn := clampf(planar.length() + absf(up), 0.0, 1.5)
		_apply_fuel(delta, burn)
		if out_of_fuel:
			up = 0.0
			spd = 0.0
			_vy = move_toward(_vy, -3.0, 10.0 * delta)
	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * spd
	velocity.z = fwd.z * spd
	velocity.y = _vy
	# Gentle ground collision: don't sink below terrain.
	var gy := _ground_height_at(global_position)
	if global_position.y < gy + 0.8 and _vy < 0.0:
		velocity.y = 0.0
		global_position.y = gy + 0.8
	move_and_slide()


func _drive_plane(delta: float) -> void:
	var inp := _driver_input()
	var top := float(spec["top_speed"])
	var takeoff := float(spec.get("takeoff_speed", 30.0))
	if not flying:
		# Runway roll.
		speed = move_toward(speed, top, float(spec["accel"]) * delta)
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		velocity = fwd.normalized() * speed
		velocity.y = -0.5
		move_and_slide()
		if speed >= takeoff and inp.y < -0.3:
			flying = true
		_check_ram()
		return
	# Airborne: arcade flight.
	speed = move_toward(speed, top, 6.0 * delta)
	rotation.y += -inp.x * float(spec["turn_rate"]) * delta
	var pitch_in := -inp.y
	rotation.x = clampf(lerpf(rotation.x, pitch_in * 0.45, 3.0 * delta), -0.6, 0.6)
	var fwd3 := -global_transform.basis.z
	velocity = fwd3 * speed
	move_and_slide()
	# Touchdown / crash.
	if is_on_floor() or is_on_wall():
		var impact := speed
		flying = false
		rotation.x = 0.0
		if impact > 40.0:
			take_damage(120.0, "crash")


func _update_wheels(delta: float) -> void:
	var spin := speed * delta / 0.35
	for w in _wheels:
		(w as Node3D).rotation.x += spin
	var inp := _driver_input()
	for s in _steer:
		(s as Node3D).rotation.y = lerpf((s as Node3D).rotation.y, -inp.x * 0.45, 10.0 * delta)


func _update_rotor(delta: float) -> void:
	var rm: Node3D = _parts.get("rotor_main")
	if rm != null:
		var target := 25.0 if (driver != null or str(spec["loco"]) == "air") else 0.0
		rm.rotation.y += lerpf(0.0, target, 1.0) * delta * 8.0
	var rt: Node3D = _parts.get("rotor_tail")
	if rt != null:
		rt.rotation.x += 30.0 * delta


func _update_weapon_aim() -> void:
	# Tank turret follows the driver's camera yaw.
	if str(spec["weapon"]) != "cannon" or driver == null:
		return
	var turret: Node3D = _parts.get("turret")
	if turret == null:
		return
	var want: float = driver.yaw - rotation.y
	turret.rotation.y = lerp_angle(turret.rotation.y, want, 6.0 * get_physics_process_delta_time())


func driver_wants_fire() -> bool:
	if driver == null or destroyed:
		return false
	return driver.wants_fire()


func _process(delta: float) -> void:
	if destroyed:
		return
	var w := str(spec["weapon"])
	if w == "none" or driver == null:
		return
	if w == "minigun":
		if driver_wants_fire():
			_minigun_acc += delta
			var interval := 60.0 / float(spec.get("minigun_rpm", 900.0))
			while _minigun_acc >= interval:
				_minigun_acc -= interval
				_fire_minigun()
		else:
			_minigun_acc = 0.0
	elif w == "cannon":
		if driver_wants_fire() and _cannon_cd <= 0.0:
			_cannon_cd = float(spec.get("cannon_cd", 3.0))
			_fire_cannon()
	elif w == "bombs":
		if driver_wants_fire() and _bomb_cd <= 0.0 and _bombs_left > 0:
			_bomb_cd = float(spec.get("bomb_cd", 1.2))
			_bombs_left -= 1
			_drop_bomb()
	_update_audio(delta)


func _aim_point(max_dist: float) -> Vector3:
	var from: Vector3 = driver.global_position + Vector3(0, 1.6, 0)
	var dir: Vector3 = -driver.global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist)
	params.collision_mask = 1 | 4
	params.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return from + dir * max_dist
	return hit["position"]


func _enemies_in_radius(pos: Vector3, radius: float) -> Array:
	var out := []
	var scene := get_tree().current_scene
	if scene == null or not ("enemies" in scene):
		return out
	for e in scene.enemies:
		if e != null and is_instance_valid(e) and e.is_alive():
			if e.global_position.distance_to(pos) <= radius:
				out.append(e)
	return out


func _fire_cannon() -> void:
	var dmg := float(spec.get("cannon_damage", 110.0))
	var rad := float(spec.get("cannon_radius", 6.5))
	var turret: Node3D = _parts.get("turret")
	var from := global_position + Vector3(0, 2.2, 0)
	if turret != null:
		from = turret.global_position + Vector3(0, 0.6, 0)
	var dir: Vector3 = -driver.global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
	params.collision_mask = 1
	params.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var impact: Vector3 = from + dir * 120.0
	if not hit.is_empty():
		impact = hit["position"]
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_explosion"):
		scene.spawn_explosion(impact, rad)
	for e in _enemies_in_radius(impact, rad):
		e.take_damage(int(dmg), impact, "explosive")
	_play_boom()


func _fire_minigun() -> void:
	var target := _aim_point(90.0)
	for e in _enemies_in_radius(target, 2.5):
		e.take_damage(int(float(spec.get("minigun_damage", 14.0))), target, "bullet")
	# Tracer flash from nose.
	_play_crack()


func _drop_bomb() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var bomb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.9, 0.5)
	bomb.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.16)
	bomb.material_override = mat
	var bay: Vector3 = _parts.get("muzzle", Vector3.ZERO)
	bomb.global_position = to_global(bay)
	scene.add_child(bomb)
	var tw := scene.create_tween()
	tw.tween_property(bomb, "global_position:y", _ground_height_at(bomb.global_position) + 0.5, 1.6)
	tw.tween_callback(_detonate_bomb.bind(bomb))


func _detonate_bomb(bomb: Node3D) -> void:
	if not is_instance_valid(bomb):
		return
	var pos: Vector3 = bomb.global_position
	bomb.queue_free()
	var scene := get_tree().current_scene
	var rad := float(spec.get("bomb_radius", 12.0))
	var dmg := float(spec.get("bomb_damage", 160.0))
	if scene != null and scene.has_method("spawn_explosion"):
		scene.spawn_explosion(pos, rad)
	for e in _enemies_in_radius(pos, rad):
		e.take_damage(int(dmg), pos, "explosive")


func _check_ram() -> void:
	if absf(speed) < 8.0:
		return
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var c := col.get_collider()
		if c != null and c.has_method("is_alive") and c.has_method("take_damage") and not (c is NovaVehicle):
			# Don't ram the driver.
			if driver != null and c == driver:
				continue
			c.take_damage(int(float(spec.get("ram_damage", 25))), global_position, "ram")
			speed *= 0.6


func take_damage(amount: float, kind: String = "bullet") -> void:
	if destroyed:
		return
	hp -= amount
	if hp <= max_hp * 0.5 and not _smoking:
		_smoking = true
		_smoke = _make_fx(Color(0.25, 0.25, 0.25, 0.7))
	if hp <= max_hp * 0.25 and not _burning:
		_burning = true
		_fire = _make_fx(Color(1.0, 0.45, 0.1, 0.8))
	if hp <= 0.0:
		_explode()


func _make_fx(col: Color) -> CPUParticles3D:
	var cp := CPUParticles3D.new()
	cp.amount = 24
	cp.lifetime = 1.2
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cp.emission_sphere_radius = 0.6
	cp.direction = Vector3(0, 1, 0)
	cp.spread = 25.0
	cp.initial_velocity_min = 1.5
	cp.initial_velocity_max = 4.0
	cp.gravity = Vector3(0, 2.5, 0)
	cp.scale_amount_min = 0.4
	cp.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = m
	cp.draw_pass_1 = quad
	cp.position = Vector3(0, 1.2, 0)
	add_child(cp)
	cp.emitting = true
	return cp


func _explode() -> void:
	destroyed = true
	var scene := get_tree().current_scene
	var pos := global_position + Vector3(0, 1.0, 0)
	if scene != null and scene.has_method("spawn_explosion"):
		scene.spawn_explosion(pos, 6.0)
	for e in _enemies_in_radius(pos, 6.0):
		e.take_damage(80, pos, "explosive")
	if driver != null:
		var d = driver
		var exit_pos: Vector3 = exit()
		d.exit_vehicle()
		d.global_position = exit_pos
		d.take_damage(40, pos, "explosive")
	# Burnt wreck: darken model, stop driving.
	if _model != null:
		var charred := StandardMaterial3D.new()
		charred.albedo_color = Color(0.12, 0.10, 0.09)
		charred.roughness = 0.9
		_char_material(_model, charred)
	if _smoke != null:
		_smoke.emitting = false
	if _fire != null:
		_fire.emitting = false
	exploded.emit(self)


func _char_material(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).set_surface_override_material(0, mat)
	for c in n.get_children():
		_char_material(c, mat)


func _update_audio(_delta: float) -> void:
	if _thud_cd > 0.0:
		_thud_cd -= _delta
	# Engine: RPM-pitched loop, volume follows throttle.
	if _audio_engine != null:
		var top := maxf(float(spec.get("top_speed", 20.0)), 1.0)
		var rpm01 := clampf(absf(speed) / top, 0.0, 1.0)
		if str(spec["loco"]) == "air":
			rpm01 = clampf(0.55 + absf(_vy) / 18.0, 0.0, 1.0)
		_audio_engine.pitch_scale = 0.7 + rpm01 * 1.1
		var want_db := -60.0
		if driver != null and not destroyed and not out_of_fuel:
			want_db = -20.0 + rpm01 * 10.0
		_audio_engine.volume_db = lerpf(_audio_engine.volume_db, want_db, 4.0 * _delta)
	# Skid: lateral slide at speed.
	if _audio_skid != null:
		var skid := 0.0
		if driver != null and str(spec["loco"]) in ["ground", "hover"]:
			var fwd := -global_transform.basis.z
			var lat := velocity - fwd * velocity.dot(fwd)
			if absf(speed) > 10.0 and lat.length() > 3.0:
				skid = clampf(lat.length() / 8.0, 0.0, 1.0)
		_audio_skid.volume_db = lerpf(_audio_skid.volume_db, -60.0 + skid * 42.0, 6.0 * _delta)
	# Collision thud on hard impacts.
	if _thud_cd <= 0.0 and get_slide_collision_count() > 0 and absf(speed) > 12.0:
		_thud_cd = 0.4
		if _audio_one != null:
			_audio_one.stream = VehicleAudio.thud()
			_audio_one.play()
		speed *= 0.55


func _play_boom() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("play_boom_at"):
		scene.play_boom_at(global_position)


func _play_crack() -> void:
	pass  # minigun crack handled by rapid enemy-style hits; kept quiet for perf


func vehicle_hud_text() -> String:
	var s := "%s [%s]\n%d km/h  |  HULL %d/%d" % [str(spec["name"]), skin_name, int(absf(speed) * 3.6), int(maxf(hp, 0.0)), int(max_hp)]
	if max_fuel > 0.0:
		s += "  |  FUEL %d%%" % int(fuel_frac() * 100.0)
	if str(spec["weapon"]) == "bombs":
		s += "\nBOMBS: %d" % _bombs_left
	return s
