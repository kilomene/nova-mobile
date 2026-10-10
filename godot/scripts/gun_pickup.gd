extends Area3D
class_name GunPickup
## World pickup for guns (and attachment loot). Tier tints the glow ring.
## On touch: gives the gun to the player; the player's old gun swaps into
## this pickup (so nothing is ever lost).

var gun_id := "m5"
var tier := 0
var attach_id := ""  # if set, this pickup is an attachment, not a gun

const TIER_GLOW := [
	Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0.75), Color(0.25, 0.9, 0.45),
	Color(0.35, 0.6, 1.0), Color(0.7, 0.35, 1.0), Color(1.0, 0.6, 0.15),
]
const TIER_NAMES := ["COMMON", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]

var _t := 0.0
var _taken := false
var _pinged := false
var _beam: MeshInstance3D = null
var skin_idx := 0  # mythic skin on legendary+ pickups

@onready var model_holder: Node3D = $ModelHolder
@onready var ring: MeshInstance3D = $Ring
@onready var label: Label3D = $Label3D


static func make(gid: String, t: int) -> GunPickup:
	var gp := (load("res://scenes/gun_pickup.tscn") as PackedScene).instantiate() as GunPickup
	gp.gun_id = gid
	gp.tier = t
	return gp


static func make_attachment(aid: String) -> GunPickup:
	var gp := (load("res://scenes/gun_pickup.tscn") as PackedScene).instantiate() as GunPickup
	gp.attach_id = aid
	gp.tier = 2
	return gp


func _ready() -> void:
	_rebuild()
	if tier >= 4:
		_beam = LootModels.rarity_beam(tier)
		add_child(_beam)
	body_entered.connect(_on_body_entered)


func _rebuild() -> void:
	for c in model_holder.get_children():
		c.queue_free()
	if attach_id != "":
		var a := GunDefs.find_attach(attach_id)
		label.text = str(a.get("name", attach_id)).to_upper()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.10, 0.16)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.7, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.3, 0.7, 1.0)
		m.emission_energy_multiplier = 0.8
		mi.set_surface_override_material(0, m)
		mi.position = Vector3(0, 0.45, 0)
		model_holder.add_child(mi)
	else:
		var g := GunDefs.by_id(gun_id)
		var lbl: String = GunDefs.full_name(g) + "\n" + TIER_NAMES[clampi(tier, 0, 5)]
		# STK visibility on the pickup card.
		lbl += "\n" + GunDefs.stk_label(g)
		# Legendary+ pickups roll a mythic skin, shown on the world model.
		skin_idx = 0
		if tier >= 4:
			skin_idx = 1 + randi() % MythicSkins.SKINS_PER_GUN
			var skn := MythicSkins.skin_display_name(gun_id, skin_idx)
			if skn != "":
				lbl = skn + "\n" + lbl
		label.text = lbl.to_upper()
		var wm := GunModels.build_world_model(gun_id)
		MythicSkins.apply_to_model(wm, gun_id, skin_idx, 0)
		wm.position = Vector3(0, 0.45, 0)
		model_holder.add_child(wm)
	var glow: Color = TIER_GLOW[clampi(tier, 0, 5)]
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = glow
	var tmesh := TorusMesh.new()
	tmesh.inner_radius = 0.42
	tmesh.outer_radius = 0.5
	ring.mesh = tmesh
	ring.set_surface_override_material(0, rm)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	model_holder.rotation.y += delta * 1.2
	model_holder.position.y = 0.1 + sin(_t * 2.0) * 0.06
	if _beam != null:
		_beam.rotation.y += delta * 0.7


func _on_body_entered(b: Node3D) -> void:
	if _taken:
		return
	if b is NovaPlayer and b.is_alive():
		if attach_id != "":
			if b.attach_to_current(attach_id):
				_taken = true
				_announce(b, "Attached " + str(GunDefs.find_attach(attach_id).get("name", attach_id)))
				queue_free()
			return
		var old_id: String = b.give_gun(gun_id, tier)
		_announce(b, "Picked up " + GunDefs.full_name(GunDefs.by_id(gun_id)))
		if skin_idx > 0:
			b.set_skin_for(GunDefs.slot_of(str(GunDefs.by_id(gun_id)["cls"])), skin_idx)
		if old_id == "":
			_taken = true
			queue_free()
		else:
			# Swap: the dropped gun takes this pickup's place.
			gun_id = old_id
			tier = 0
			skin_idx = 0
			_rebuild()


func _announce(b: NovaPlayer, text: String) -> void:
	var scene := b.get_tree().current_scene
	if scene != null and scene.has_method("on_loot_taken"):
		scene.on_loot_taken(text)


## Ping support: called by main when the player pings this pickup.
func display_name() -> String:
	var g := GunDefs.by_id(gun_id)
	return str(GunDefs.full_name(g))


func ping() -> void:
	if _taken or _pinged:
		return
	_pinged = true
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_loot_ping"):
		scene.spawn_loot_ping(display_name(), tier, global_position)
