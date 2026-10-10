class_name LootPing
extends Node3D
## World ping marker: double-tap loot (or press PING with crosshair on loot)
## to mark it — floating diamond + pulse ring, minimap blip, HUD feed entry.
## AI allies move toward high-tier (epic+) pings. Expires after 20 s.

const LIFE := 20.0

var label_text := "LOOT"
var tier := 0

var _t := 0.0
var _diamond: MeshInstance3D = null
var _ring: MeshInstance3D = null


static func make(text: String, t: int) -> LootPing:
	var p := LootPing.new()
	p.label_text = text
	p.tier = t
	return p


func _ready() -> void:
	var c: Color = LootModels.tier_color(tier)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	_diamond = MeshInstance3D.new()
	_diamond.name = "Diamond"
	var dm := BoxMesh.new()
	dm.size = Vector3(0.28, 0.28, 0.28)
	_diamond.mesh = dm
	_diamond.rotation = Vector3(0.6, 0.6, 0)
	_diamond.set_surface_override_material(0, m)
	_diamond.position = Vector3(0, 2.2, 0)
	add_child(_diamond)
	_ring = MeshInstance3D.new()
	_ring.name = "Pulse"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.62
	_ring.mesh = tm
	_ring.set_surface_override_material(0, m)
	_ring.position = Vector3(0, 0.15, 0)
	add_child(_ring)
	var lbl := Label3D.new()
	lbl.name = "Label"
	lbl.text = "◈ " + label_text.to_upper()
	lbl.font_size = 52
	lbl.pixel_size = 0.007
	lbl.modulate = c
	lbl.outline_size = 10
	lbl.position = Vector3(0, 3.0, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		_expire()
		return
	if _diamond != null:
		_diamond.rotation.y += delta * 2.5
		_diamond.position.y = 2.2 + sin(_t * 3.0) * 0.15
	if _ring != null:
		var s := 1.0 + 0.18 * sin(_t * 4.0)
		_ring.scale = Vector3(s, 1.0, s)


func _expire() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("on_ping_expired"):
		scene.on_ping_expired(self)
	queue_free()
