extends Node3D
class_name FragGrenade
## Throwable fragmentation grenade: ballistic arc, ground bounce, 2.0s fuse,
## AoE explosion (damages enemies + player at close range). Reuses the
## explosion FX/sound patterns from gun_projectile.gd.

const FUSE := 2.0
const BLAST_RADIUS := 5.5
const DAMAGE := 130.0

var velocity := Vector3.ZERO
var fuse := FUSE
var owner_player: Node3D = null
var _t := 0.0
var _bounces := 0
var _mesh: MeshInstance3D


static func throw_from(from: Vector3, dir: Vector3, power: float, cook_time: float,
		owner: Node3D) -> FragGrenade:
	var g := FragGrenade.new()
	g.velocity = (dir + Vector3(0, 0.18, 0)).normalized() * power
	g.fuse = maxf(FUSE - cook_time, 0.15)
	g.owner_player = owner
	g.global_position = from
	return g


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.10
	_mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.28, 0.16)
	m.roughness = 0.55
	m.metallic = 0.35
	_mesh.set_surface_override_material(0, m)
	add_child(_mesh)
	# Short fuse tick while cooking already elapsed: blink faster near boom.
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_mesh, "scale", Vector3.ONE * 1.25, 0.25)
	tw.tween_property(_mesh, "scale", Vector3.ONE, 0.25)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= fuse:
		explode()
		return
	velocity.y -= 9.8 * delta
	var step: Vector3 = velocity * delta
	var from := global_position
	# Ground probe: short raycast down from the next position.
	var probe := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.1, 0),
		from + step + Vector3(0, -0.12, 0))
	probe.exclude = [self]
	if owner_player != null:
		probe.exclude.append(owner_player)
	var hit := get_world_3d().direct_space_state.intersect_ray(probe)
	if not hit.is_empty() and _bounces < 3:
		var n: Vector3 = hit["normal"]
		global_position = hit["position"] + n * 0.06
		var vn := velocity.dot(n)
		if vn < 0.0:
			velocity -= n * vn * 1.55  # bounce, lose energy
		velocity *= 0.55
		_bounces += 1
		if velocity.length() < 1.2:
			velocity = Vector3.ZERO
	else:
		global_position = from + step
	_mesh.rotation += Vector3(9.0, 7.0, 5.0) * delta


func explode() -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	# Radial damage to enemies (falloff like gun_projectile).
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and e.has_method("take_damage") and e.has_method("is_alive") and e.is_alive():
			var d: float = (e as Node3D).global_position.distance_to(global_position)
			if d <= BLAST_RADIUS:
				var f := 1.0 - (d / BLAST_RADIUS) * 0.6
				(e as Node).take_damage(int(DAMAGE * f), (e as Node3D).global_position, "explosive")
				if owner_player != null and owner_player.has_method("on_projectile_hit"):
					owner_player.on_projectile_hit(e)
	# Self-damage at close range.
	if owner_player != null and owner_player.has_method("take_damage"):
		var pd: float = owner_player.global_position.distance_to(global_position)
		if pd <= BLAST_RADIUS * 0.7:
			owner_player.take_damage(int(DAMAGE * 0.4 * (1.0 - pd / BLAST_RADIUS)), global_position, "explosive")
	if scene != null and scene.has_method("spawn_explosion"):
		scene.spawn_explosion(global_position, BLAST_RADIUS)
	elif scene != null and scene.has_method("spawn_impact"):
		scene.spawn_impact(global_position, Vector3.UP)
	if owner_player != null and owner_player.has_method("play_explosion_sound"):
		owner_player.play_explosion_sound()
	queue_free()
