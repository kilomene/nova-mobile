extends Area3D
class_name NovaLoot
## Floating pickup: health / armor / ammo / cash / grenade / smoke / shard /
## uav / strike. Real 3D models (no flat icons), tier glow + rarity beams for
## epic+, fly-to-player pickup animation, per-rarity pickup sounds, pingable.
## Respawns after a delay (consumables); one-shot items don't respawn.

var kind := "health"  # health|armor|ammo|cash|grenade|smoke|shard|uav|strike|fuelcan
var amount := 40
var tier := 0  # 0=common … 5=legendary, 6=mythic
var caliber := ""  # ammo caliber override; "" = current gun's caliber

const RESPAWN_DELAY := 25.0
const PING_RANGE := 34.0

var _t := 0.0
var _taken := false
var _flying := false
var _fly_target: Node3D = null
var _pinged := false

@onready var mesh: MeshInstance3D = $Mesh
var _holder: Node3D = null
var _beam: MeshInstance3D = null


func _ready() -> void:
	_holder = Node3D.new()
	_holder.name = "ModelHolder"
	add_child(_holder)
	_rebuild_visual()
	# Rarity beam for epic+.
	if tier >= 4:
		_beam = LootModels.rarity_beam(tier)
		add_child(_beam)
	body_entered.connect(_on_body_entered)


func display_name() -> String:
	match kind:
		"health":
			return "MEDKIT"
		"armor":
			return "ARMOR PLATES x%d" % amount
		"ammo":
			var cal := caliber if caliber != "" else "AMMO"
			return "%s AMMO x%d" % [cal.to_upper(), amount]
		"cash":
			return "CASH $%d" % amount
		"grenade":
			return "FRAG GRENADE x%d" % amount
		"smoke":
			return "SMOKE x%d" % amount
		"shard":
			return "ARMOR SHARD"
		"uav":
			return "UAV SWEEP"
		"strike":
			return "CLUSTER STRIKE"
		"fuelcan":
			return "FUEL CANISTER"
	return kind.to_upper()


func _rebuild_visual() -> void:
	for c in _holder.get_children():
		c.queue_free()
	var model: Node3D = null
	match kind:
		"health":
			model = LootModels.medkit()
		"armor":
			model = LootModels.armor_plates()
		"shard":
			model = LootModels.armor_shard()
		"ammo":
			model = LootModels.ammo_box(caliber if caliber != "" else "medium")
		"cash":
			model = LootModels.cash_bundle()
		"grenade":
			model = LootModels.frag_grenade()
		"smoke":
			model = LootModels.smoke_canister()
		"uav":
			model = LootModels.streak_device("uav")
		"strike":
			model = LootModels.streak_device("strike")
		"fuelcan":
			model = _fuel_can_model()
		_:
			model = LootModels.cash_bundle()
	model.position = Vector3(0, 0.55, 0)
	_holder.add_child(model)
	# Tier glow ring under the item.
	var ring := LootModels.tier_ring(maxi(tier, 1 if kind == "health" else 0))
	ring.position = Vector3(0, 0.06, 0)
	_holder.add_child(ring)
	mesh.visible = false  # legacy box hidden; models carry the visuals


func _process(delta: float) -> void:
	if _taken and not _flying:
		return
	_t += delta
	if _flying and _fly_target != null and is_instance_valid(_fly_target):
		# Fly to the player, then apply.
		var tp: Vector3 = _fly_target.global_position + Vector3(0, 1.0, 0)
		global_position = global_position.lerp(tp, minf(delta * 10.0, 1.0))
		_holder.rotation.y += delta * 9.0
		if global_position.distance_to(tp) < 0.6:
			_flying = false
			_apply(_fly_target)
		return
	if not _taken:
		_holder.rotation.y += delta * 1.6
		_holder.position.y = sin(_t * 2.2) * 0.1
		if _beam != null:
			_beam.rotation.y += delta * 0.7


func _on_body_entered(b: Node3D) -> void:
	if _taken or _flying:
		return
	if b is NovaPlayer and (b as NovaPlayer).is_alive():
		_taken = true
		_flying = true
		_fly_target = b
		set_deferred("monitoring", false)
		_play_pickup_sound()


func _play_pickup_sound() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("play_loot_sound"):
		scene.play_loot_sound(LootAudio.pickup_stream(tier), global_position)


func _apply(b: NovaPlayer) -> void:
	match kind:
		"health":
			b.heal(amount)
		"armor":
			for i in range(maxi(amount, 1)):
				b.add_armor_plate()
		"ammo":
			if caliber != "":
				b.add_ammo_caliber(caliber, amount)
			else:
				b.add_ammo(amount)
		"cash":
			b.add_cash(amount)
		"grenade":
			b.add_grenades(amount)
		"smoke":
			b.add_smoke(amount)
		"shard":
			b.add_armor(25)
		"uav":
			_trigger_uav(b)
		"strike":
			_trigger_strike(b)
		"fuelcan":
			_apply_fuelcan(b)
	visible = false
	_pinged = false
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("on_loot_taken"):
		scene.on_loot_taken(display_name())
	# Consumables respawn; one-shot scorestreaks don't.
	if kind == "uav" or kind == "strike":
		queue_free()
		return
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	_taken = false
	visible = true
	monitoring = true


func _trigger_uav(_b: NovaPlayer) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("trigger_uav_pickup"):
		scene.trigger_uav_pickup()


func _trigger_strike(_b: NovaPlayer) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("trigger_strike_pickup"):
		scene.trigger_strike_pickup()


func _fuel_can_model() -> Node3D:
	# Red jerry can, built inline (no LootModels dependency).
	var root := Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.12, 0.08)
	red.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.16)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.5, 0.22)
	body.mesh = bm
	body.set_surface_override_material(0, red)
	root.add_child(body)
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.3, 0.06, 0.06)
	handle.mesh = hm
	handle.set_surface_override_material(0, dark)
	handle.position = Vector3(0, 0.28, 0)
	root.add_child(handle)
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 0.06
	cap.mesh = cm
	cap.set_surface_override_material(0, dark)
	cap.position = Vector3(0.1, 0.28, 0)
	root.add_child(cap)
	return root


func _apply_fuelcan(b: NovaPlayer) -> void:
	var v = b.in_vehicle
	if v != null and v.needs_fuel():
		v.refuel(35.0)
		var scene := get_tree().current_scene
		if scene != null and "hud" in scene and scene.hud != null and scene.hud.has_method("add_killfeed"):
			scene.hud.add_killfeed("+35 FUEL poured in")
	else:
		b.fuel_cans = mini(b.fuel_cans + 1, 2)


## Ping support: called by main when the player pings this loot.
func ping() -> void:
	if _taken or _pinged:
		return
	_pinged = true
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_loot_ping"):
		scene.spawn_loot_ping(display_name(), tier, global_position)
