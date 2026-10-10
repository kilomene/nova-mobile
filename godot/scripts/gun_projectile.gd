extends Area3D
class_name GunProjectile
## Rocket / grenade projectile. Explodes on impact or timeout.

var velocity := Vector3.ZERO
var gravity_factor := 1.0
var blast_radius := 4.0
var damage := 100.0
var life := 5.0
var owner_player: Node3D = null

var _t := 0.0
var _trail: MeshInstance3D
var _smoke_t := 0.0


static func launch(from: Vector3, dir: Vector3, speed: float, grav: float,
		blast: float, dmg: float, owner: Node3D) -> GunProjectile:
	var p := GunProjectile.new()
	p.velocity = dir * speed
	p.gravity_factor = grav
	p.blast_radius = blast
	p.damage = dmg
	p.owner_player = owner
	# visible tracer body
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.09, 0.45)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15)
	mi.set_surface_override_material(0, m)
	p.add_child(mi)
	p._trail = mi
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.3
	cs.shape = ss
	p.add_child(cs)
	p.global_position = from
	return p


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		explode()
		return
	velocity.y -= 9.8 * gravity_factor * delta
	global_position += velocity * delta
	if _trail != null and velocity.length() > 0.1:
		_trail.rotation.y = atan2(-velocity.x, -velocity.z)
	# Rocket smoke trail: small fading puffs left behind in flight.
	_smoke_t += delta
	if _smoke_t >= 0.07:
		_smoke_t = 0.0
		_spawn_smoke_puff()


func _spawn_smoke_puff() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.78, 0.80, 0.55)
	mi.material_override = m
	mi.position = global_position
	scene.add_child(mi)
	var tw := scene.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 3.2, 0.6)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(mi.queue_free)


func _on_body_entered(_b: Node3D) -> void:
	explode()


func explode() -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	# Radial damage to enemies.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and e.has_method("take_damage") and e.has_method("is_alive") and e.is_alive():
			var d: float = (e as Node3D).global_position.distance_to(global_position)
			if d <= blast_radius:
				var f := 1.0 - (d / blast_radius) * 0.6
				(e as Node).take_damage(int(damage * f), (e as Node3D).global_position, "explosive")
				if owner_player != null and owner_player.has_method("on_projectile_hit"):
					owner_player.on_projectile_hit(e)
	# Player self-damage at close range (rockets are dangerous).
	if owner_player != null and owner_player.has_method("take_damage"):
		var pd: float = owner_player.global_position.distance_to(global_position)
		if pd <= blast_radius * 0.7:
			owner_player.take_damage(int(damage * 0.4 * (1.0 - pd / blast_radius)), global_position, "explosive")
	# FX: expanding flash sphere + light, handled by scene if available.
	if scene != null and scene.has_method("spawn_explosion"):
		scene.spawn_explosion(global_position, blast_radius)
	elif scene != null and scene.has_method("spawn_impact"):
		scene.spawn_impact(global_position, Vector3.UP)
	if owner_player != null and owner_player.has_method("play_explosion_sound"):
		owner_player.play_explosion_sound()
	queue_free()
