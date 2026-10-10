class_name LootCrate
extends Area3D
## Openable supply crate in 3 tiers: 0 standard (green), 1 rare (blue),
## 2 epic (orange). Touch to open -> lid flips -> loot burst flies out ->
## light beam pillar for rare/epic (visible across the map, CODM-style).
## Respawns closed after 90 s.

const RESPAWN_DELAY := 90.0
const TIER_TINT := [Color(0.25, 0.90, 0.45), Color(0.35, 0.60, 1.00), Color(1.00, 0.60, 0.15)]
const TIER_LABEL := ["SUPPLY", "RARE SUPPLY", "EPIC SUPPLY"]

var tier := 0
var opened := false

var _lid: Node3D = null
var _beam: MeshInstance3D = null
var _label: Label3D = null
var _t := 0.0
var _respawn_left := 0.0


static func make(t: int) -> LootCrate:
	var c := LootCrate.new()
	c.tier = clampi(t, 0, 2)
	var col := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.6
	col.shape = sp
	c.add_child(col)
	return c


func _ready() -> void:
	_build()
	body_entered.connect(_on_body_entered)


func _mat(color: Color, rough := 0.6, metal := 0.1, emit := 0.0) -> StandardMaterial3D:
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
	var tint: Color = TIER_TINT[tier]
	var body := _mat(Color(0.30, 0.28, 0.24))
	var trim := _mat(tint, 0.5, 0.0, 1.4)
	# Crate body: bigger for higher tiers.
	var s := 0.9 + 0.25 * float(tier)
	_add_box(self, Vector3(s, s * 0.7, s), Vector3(0, s * 0.35, 0), body)
	_add_box(self, Vector3(s + 0.06, 0.10, s + 0.06), Vector3(0, 0.08, 0), body)
	_add_box(self, Vector3(s + 0.02, 0.06, 0.08), Vector3(0, s * 0.35, s * 0.5), trim)
	_add_box(self, Vector3(s + 0.02, 0.06, 0.08), Vector3(0, s * 0.35, -s * 0.5), trim)
	# Flip lid (hinged at back).
	_lid = Node3D.new()
	_lid.position = Vector3(0, s * 0.7, -s * 0.5)
	add_child(_lid)
	_add_box(_lid, Vector3(s, 0.10, s), Vector3(0, 0.05, s * 0.5), body)
	_add_box(_lid, Vector3(s * 0.5, 0.04, 0.12), Vector3(0, 0.12, s * 0.5), trim)
	# Light beam for rare/epic.
	if tier >= 1:
		_beam = LootModels.rarity_beam(3 if tier == 1 else 5)
		_beam.position.y = s * 0.7
		add_child(_beam)
	_label = Label3D.new()
	_label.text = TIER_LABEL[tier]
	_label.font_size = 56
	_label.pixel_size = 0.006
	_label.modulate = tint
	_label.outline_size = 8
	_label.position = Vector3(0, s + 0.9, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


func _process(delta: float) -> void:
	if opened:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_reset()
		return
	_t += delta
	if _label != null:
		_label.position.y += sin(_t * 2.0) * 0.002
	if _beam != null:
		_beam.rotation.y += delta * 0.8


func _on_body_entered(b: Node3D) -> void:
	if opened:
		return
	if b is NovaPlayer and (b as NovaPlayer).is_alive():
		open()


func open() -> void:
	if opened:
		return
	opened = true
	_respawn_left = RESPAWN_DELAY
	set_deferred("monitoring", false)
	if _label != null:
		_label.visible = false
	if _beam != null:
		_beam.visible = false
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -2.2, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_play_sound()
	var tw2 := create_tween()
	tw2.tween_interval(0.35)
	tw2.tween_callback(_burst)


func _play_sound() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("play_loot_sound"):
		scene.play_loot_sound(LootAudio.crate_stream(tier), global_position)


func _burst() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("spawn_crate_loot"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var n := 3 + tier  # 3/4/5 items
	for i in range(n):
		var ang := TAU * float(i) / float(n) + rng.randf() * 0.5
		var pos := global_position + Vector3(cos(ang) * (1.2 + 0.4 * tier), 0.4, sin(ang) * (1.2 + 0.4 * tier))
		scene.spawn_crate_loot(_roll_one(rng), pos)
	# Epic crates always drop a high-tier gun.
	if tier == 2:
		var gid: String = GunDefs.roll_gun(5, rng)
		scene.spawn_crate_loot({"gun": gid, "tier": 5}, global_position + Vector3(0, 0.4, -1.6))
		# Epic bonus: a scorestreak device + armor shards.
		var skind := "uav" if rng.randf() < 0.5 else "strike"
		scene.spawn_crate_loot({"kind": skind, "amount": 1, "tier": 5},
			global_position + Vector3(0.8, 0.4, 1.2))
		scene.spawn_crate_loot({"kind": "shard", "amount": 2, "tier": 4},
			global_position + Vector3(-0.8, 0.4, 1.2))


func _roll_one(rng: RandomNumberGenerator) -> Dictionary:
	var t: int = clampi(1 + tier + rng.randi() % 2, 0, 5)
	var r := rng.randf()
	if r < 0.25:
		return {"kind": "health", "amount": 60, "tier": t}
	if r < 0.45:
		return {"kind": "armor", "amount": 2, "tier": t}
	if r < 0.65:
		return {"kind": "ammo", "amount": 90, "tier": t, "caliber": "medium"}
	if r < 0.78:
		return {"kind": "cash", "amount": 300 + 200 * tier, "tier": t}
	if r < 0.88:
		return {"kind": "grenade", "amount": 2, "tier": t}
	if rng.randf() < 0.5:
		return {"attach": GunDefs.ATTACH_LOOT[rng.randi() % GunDefs.ATTACH_LOOT.size()], "tier": 3}
	return {"kind": "smoke", "amount": 2, "tier": t}


func _reset() -> void:
	opened = false
	set_deferred("monitoring", true)
	if _lid != null:
		_lid.rotation.x = 0.0
	if _label != null:
		_label.visible = true
	if _beam != null:
		_beam.visible = true


## Ping support.
func ping() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_loot_ping"):
		scene.spawn_loot_ping("SUPPLY CRATE", 2, global_position)
