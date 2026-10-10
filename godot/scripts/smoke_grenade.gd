class_name SmokeGrenade
extends Node3D
## Throwable smoke canister: ballistic arc, pops a lingering smoke cloud on
## landing that blocks AI line-of-sight (enemies can't see through it).

const CLOUD_RADIUS := 6.0
const CLOUD_LIFE := 18.0

var velocity := Vector3.ZERO
var _landed := false
var _t := 0.0
var _mesh: MeshInstance3D = null

static var clouds: Array = []  # {pos, radius, ttl} — read by enemy LOS


static func throw_from(from: Vector3, dir: Vector3, power: float, owner: Node3D) -> SmokeGrenade:
	var g := SmokeGrenade.new()
	g.velocity = (dir + Vector3(0, 0.35, 0)).normalized() * power
	g.global_position = from
	return g


static func blocks_sight(a: Vector3, b: Vector3) -> bool:
	for c in clouds:
		var d: Dictionary = c
		if float(d["ttl"]) <= 0.0:
			continue
		var p: Vector3 = d["pos"]
		var r: float = float(d["radius"])
		if _seg_sphere(a, b, p, r):
			return true
	return false


static func _seg_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return (a + ab * t - c).length() < r


static func _tick_clouds(delta: float) -> void:
	for i in range(clouds.size() - 1, -1, -1):
		var d: Dictionary = clouds[i]
		d["ttl"] = float(d["ttl"]) - delta
		if float(d["ttl"]) <= 0.0:
			clouds.remove_at(i)


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 0.16
	_mesh.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.57, 0.60)
	m.metallic = 0.5
	m.roughness = 0.5
	_mesh.set_surface_override_material(0, m)
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	SmokeGrenade._tick_clouds(delta)
	if _landed:
		_t += delta
		if _t > 1.2:
			queue_free()
		return
	velocity.y -= 9.8 * delta
	var from := global_position
	var to := from + velocity * delta
	var probe := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.1, 0), to + Vector3(0, -0.1, 0))
	probe.exclude = [self]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(probe)
	if not hit.is_empty():
		_land(Vector3(hit["position"]))
		return
	global_position = to
	_mesh.rotation.x += delta * 9.0
	if to.y < -2.0:
		_land(to)


func _land(at: Vector3) -> void:
	_landed = true
	global_position = at + Vector3(0, 0.1, 0)
	if _mesh != null:
		_mesh.visible = false
	clouds.append({"pos": at + Vector3(0, 1.2, 0), "radius": CLOUD_RADIUS, "ttl": CLOUD_LIFE})
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_smoke_cloud"):
		scene.spawn_smoke_cloud(at, CLOUD_RADIUS, CLOUD_LIFE)
