class_name DogTag
extends Area3D
## NOVA Mobile: fallen teammate's dog tag. Walk over it to carry it, then
## REDEPLOY the teammate at any buy station (CODM-style redeploy).

signal picked(tag: DogTag)

var tag_name := "ALLY"
var _t := 0.0
var _mesh: MeshInstance3D
var _label: Label3D


static func make(vname: String) -> DogTag:
	var d := DogTag.new()
	d.tag_name = vname
	return d


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.6
	cs.shape = sp
	add_child(cs)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.02, 0.44)
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.25)
	mat.metallic = 0.9
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 0.7
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)
	_label = Label3D.new()
	_label.text = "◈ " + tag_name
	_label.font_size = 48
	_label.pixel_size = 0.012
	_label.modulate = Color(1.0, 0.85, 0.35)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 0.9, 0)
	add_child(_label)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	if _mesh != null:
		_mesh.position.y = 0.35 + sin(_t * 2.4) * 0.12
		_mesh.rotation.y = _t * 1.8


func _on_body(b: Node3D) -> void:
	if b is NovaPlayer and (b as NovaPlayer).is_alive() and not (b as NovaPlayer).downed:
		(b as NovaPlayer).carry_tag(tag_name)
		picked.emit(self)
		queue_free()
