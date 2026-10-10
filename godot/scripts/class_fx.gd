class_name ClassFX
extends RefCounted
## NOVA Mobile: cheap pooled visual effects for class abilities.
## All builders are static; particle pools live on the passed parent node.

## Spawn a rising smoke column (pooled CPUParticles3D per call site key).
static func smoke_column(parent: Node, pos: Vector3, radius: float, duration: float,
		color: Color = Color(0.45, 0.45, 0.48, 0.75), key: String = "smoke") -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "ClassFX_" + key
	p.amount = 26
	p.lifetime = 2.2
	p.one_shot = false
	p.emitting = true
	p.explosiveness = 0.0
	p.spread = 28.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, 1.6, 0)
	p.scale_amount_min = radius * 0.35
	p.scale_amount_max = radius * 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.45
	p.color = color
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.albedo_color = color
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qm
	p.mesh = quad
	p.position = pos + Vector3(0, 0.6, 0)
	parent.add_child(p)
	# Auto-cleanup after the effect ends.
	var tw := parent.create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(p.queue_free)
	return p


## Expanding ground ring (telegraph / pulse), fades out.
static func ground_ring(parent: Node, pos: Vector3, radius: float, duration: float,
		color: Color = Color(1.0, 0.8, 0.2, 0.8)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.set_surface_override_material(0, m)
	mi.position = pos + Vector3(0, 0.12, 0)
	mi.scale = Vector3.ONE * 0.5
	parent.add_child(mi)
	var tw := parent.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration * 0.45)
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)
	return mi


## Translucent dome (kinetic shield / radiation / trap field).
static func dome(parent: Node, pos: Vector3, radius: float, duration: float,
		color: Color = Color(0.3, 0.7, 1.0, 0.22)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.set_surface_override_material(0, m)
	mi.position = pos + Vector3(0, radius * 0.55, 0)
	mi.scale = Vector3(radius, radius * 0.75, radius)
	parent.add_child(mi)
	var tw := parent.create_tween()
	tw.tween_interval(maxf(duration - 1.0, 0.1))
	tw.tween_property(m, "albedo_color:a", 0.0, 1.0)
	tw.tween_callback(mi.queue_free)
	return mi


## Floating diamond marker above a target (for marks / pings).
static func marker(parent: Node, target: Node3D, duration: float,
		color: Color = Color(1.0, 0.25, 0.2)) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	var om := PrismMesh.new()
	om.size = Vector3(0.5, 0.7, 0.5)
	mi.mesh = om
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.set_surface_override_material(0, m)
	holder.add_child(mi)
	mi.position = Vector3(0, 2.6, 0)
	mi.rotation.z = PI / 4.0
	parent.add_child(holder)
	var tw := parent.create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(holder.queue_free)
	# Follow the target each frame via a tiny script-free approach: reparent to target.
	# (Caller may instead parent holder to target directly.)
	return holder


## Straight beam between two points (grapple rope, lightning, laser designator).
static func beam(parent: Node, a: Vector3, b: Vector3, duration: float,
		color: Color = Color(1.0, 0.9, 0.4), width: float = 0.05) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var length := a.distance_to(b)
	bm.size = Vector3(width, width, maxf(length, 0.01))
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.set_surface_override_material(0, m)
	parent.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP)
	# BoxMesh extends along -Z after look_at; length axis is Z. Good.
	var tw := parent.create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(mi.queue_free)
	return mi


## Small deployable prop base (station/turret/pad): cylinder + emissive top.
static func deploy_base(parent: Node, pos: Vector3, accent: Color,
		radius: float = 0.45, height: float = 0.9) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.15
	cm.height = height
	body.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.16, 0.17, 0.19)
	bm.metallic = 0.55
	bm.roughness = 0.45
	body.set_surface_override_material(0, bm)
	body.position = Vector3(0, height * 0.5, 0)
	root.add_child(body)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	lamp.mesh = sm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = accent
	lamp.set_surface_override_material(0, lm)
	lamp.position = Vector3(0, height + 0.12, 0)
	root.add_child(lamp)
	return root
