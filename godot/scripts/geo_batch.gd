class_name GeoBatch
extends RefCounted
## Batches static boxes/cylinders into a few MultiMeshInstance3D nodes.
## Technique: unit meshes + per-instance scale baked into transforms +
## per-instance color variation. ~10 draw calls for thousands of boxes.
## Collision is collected separately into one StaticBody3D.

var _unit_box: BoxMesh
var _unit_cyl: CylinderMesh
var _unit_rock: SphereMesh  # low-poly blob: boulders, canopies, bushes
var _boxes := {}  # Material -> {"t": Array[Transform3D], "c": PackedColorArray}
var _cyls := {}
var _rocks := {}
var _colliders: Array = []  # each: [size: Vector3, xform: Transform3D]


func _init() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	_unit_cyl = CylinderMesh.new()
	_unit_cyl.top_radius = 0.5
	_unit_cyl.bottom_radius = 0.5
	_unit_cyl.height = 1.0
	_unit_cyl.radial_segments = 10
	_unit_rock = SphereMesh.new()
	_unit_rock.radius = 0.5
	_unit_rock.height = 1.0
	_unit_rock.radial_segments = 7
	_unit_rock.rings = 4


func add_box(size: Vector3, xform: Transform3D, mat: Material, color: Color) -> void:
	var scaled := Transform3D(Basis.from_scale(size) * xform.basis, xform.origin)
	_push(_boxes, mat, scaled, color)


func add_cyl(radius: float, height: float, xform: Transform3D, mat: Material, color: Color) -> void:
	var scaled := Transform3D(
		Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)) * xform.basis,
		xform.origin)
	_push(_cyls, mat, scaled, color)


func add_collider(size: Vector3, xform: Transform3D) -> void:
	_colliders.append([size, xform])


func add_rock(size: Vector3, xform: Transform3D, mat: Material, color: Color, collide := false) -> void:
	var scaled := Transform3D(Basis.from_scale(size) * xform.basis, xform.origin)
	_push(_rocks, mat, scaled, color)
	if collide:
		# Approximate the blob with a box collider of the same footprint.
		_colliders.append([size, xform])


func _push(dict: Dictionary, mat: Material, t: Transform3D, color: Color) -> void:
	if not dict.has(mat):
		dict[mat] = {"t": [], "c": PackedColorArray()}
	var d: Dictionary = dict[mat]
	(d["t"] as Array).append(t)
	# PackedColorArray is a value type: append to a copy, then store back.
	var cols: PackedColorArray = d["c"]
	cols.append(color)
	d["c"] = cols


func build_visuals(parent: Node3D, aabb: AABB) -> int:
	var draws := 0
	draws += _build_mm(parent, _boxes, _unit_box, aabb)
	draws += _build_mm(parent, _cyls, _unit_cyl, aabb)
	draws += _build_mm(parent, _rocks, _unit_rock, aabb)
	return draws


func _build_mm(parent: Node3D, dict: Dictionary, mesh: Mesh, aabb: AABB) -> int:
	var n := 0
	for mat in dict.keys():
		var d: Dictionary = dict[mat]
		var ts: Array = d["t"]
		var cs: PackedColorArray = d["c"]
		if ts.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = ts.size()
		for i in range(ts.size()):
			mm.set_instance_transform(i, ts[i])
			mm.set_instance_color(i, cs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.custom_aabb = aabb
		parent.add_child(mmi)
		n += 1
	return n


func build_colliders(parent: Node3D) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "StaticColliders"
	for c in _colliders:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = c[0]
		cs.shape = shape
		cs.transform = c[1]
		sb.add_child(cs)
	parent.add_child(sb)
	return sb


func box_count() -> int:
	var n := 0
	for mat in _boxes.keys():
		n += ( _boxes[mat]["t"] as Array).size()
	for mat in _cyls.keys():
		n += (_cyls[mat]["t"] as Array).size()
	for mat in _rocks.keys():
		n += (_rocks[mat]["t"] as Array).size()
	return n


func collider_count() -> int:
	return _colliders.size()
