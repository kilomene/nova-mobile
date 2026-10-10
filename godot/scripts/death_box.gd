class_name DeathBox
extends Area3D
## Enemy death crate: drops where an enemy died, containing what they
## carried — their gun + matching ammo + a random bonus item. Accent stripe
## in the victim's class color, name label. Touch to open -> contents pop out.

var victim_name := "HOSTILE"
var gun_id := "m5"
var gun_tier := 1
var caliber := "medium"
var accent := Color(0.8, 0.2, 0.2)
var opened := false

var _label: Label3D = null


static func make(vname: String, gid: String, gtier: int, cal: String, acc: Color) -> DeathBox:
	var d := DeathBox.new()
	d.victim_name = vname
	d.gun_id = gid
	d.gun_tier = gtier
	d.caliber = cal
	d.accent = acc
	var col := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.3
	col.shape = sp
	d.add_child(col)
	return d


func _ready() -> void:
	_build()
	body_entered.connect(_on_body_entered)


func _mat(color: Color, rough := 0.65, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _build() -> void:
	var dark := _mat(Color(0.16, 0.16, 0.18))
	var accm := _mat(accent, 0.5, 0.0, 1.0)
	# Low tactical case.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.85, 0.35, 0.6)
	body.mesh = bm
	body.position = Vector3(0, 0.18, 0)
	body.set_surface_override_material(0, dark)
	add_child(body)
	# Class-color accent stripe + corner lights.
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.87, 0.07, 0.62)
	stripe.mesh = sm
	stripe.position = Vector3(0, 0.30, 0)
	stripe.set_surface_override_material(0, accm)
	add_child(stripe)
	_label = Label3D.new()
	_label.text = victim_name.to_upper() + "'S PACK"
	_label.font_size = 44
	_label.pixel_size = 0.006
	_label.modulate = Color(1, 1, 1, 0.85)
	_label.outline_size = 8
	_label.position = Vector3(0, 0.95, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _on_body_entered(b: Node3D) -> void:
	if opened:
		return
	if b is NovaPlayer and (b as NovaPlayer).is_alive():
		open()


func open() -> void:
	if opened:
		return
	opened = true
	set_deferred("monitoring", false)
	if _label != null:
		_label.visible = false
	# Pop the lid visually (scale punch) + thud.
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.15, 0.7, 1.15), 0.12)
	tw.tween_property(self, "scale", Vector3.ONE, 0.18)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("play_loot_sound"):
		scene.play_loot_sound(LootAudio.thud_stream(), global_position)
	var tw2 := create_tween()
	tw2.tween_interval(0.15)
	tw2.tween_callback(_spill)


func _spill() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("spawn_deathbox_loot"):
		queue_free()
		return
	# Victim's gun + matching ammo + random bonus.
	scene.spawn_deathbox_loot({"gun": gun_id, "tier": gun_tier}, global_position + Vector3(0, 0.4, -0.9))
	scene.spawn_deathbox_loot({"kind": "ammo", "amount": 60, "tier": gun_tier, "caliber": caliber},
		global_position + Vector3(0.9, 0.4, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var bonus: Dictionary = {"kind": "health", "amount": 40, "tier": 1}
	var br := randf()
	if br < 0.18:
		bonus = {"kind": "shard", "amount": 1, "tier": 3}
	var r := rng.randf()
	if r < 0.3:
		bonus = {"kind": "armor", "amount": 1, "tier": 2}
	elif r < 0.55:
		bonus = {"kind": "cash", "amount": 200, "tier": 1}
	elif r < 0.7:
		bonus = {"kind": "grenade", "amount": 1, "tier": 1}
	scene.spawn_deathbox_loot(bonus, global_position + Vector3(-0.9, 0.4, 0.3))
	queue_free()


## Ping support.
func ping() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_loot_ping"):
		scene.spawn_loot_ping("DEATH BOX", 1, global_position)
