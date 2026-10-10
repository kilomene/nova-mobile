class_name LootContainer
extends Area3D
## Searchable container inside buildings: drawers, crates, shelves, weapon
## racks, fridges, med-boxes. Touch to search -> open animation -> loot pops
## out. Contents follow room logic (kitchen=health, bedroom=armor/ammo,
## garage=attachments, armory=guns). One search per match.

const CTYPES := ["drawer", "crate", "shelf", "rack", "fridge", "medbox"]

var ctype := "crate"
var room := "general"  # kitchen | bedroom | garage | armory | general
var tier := 0
var opened := false

var _lid: Node3D = null
var _label: Label3D = null
var _t := 0.0


static func make(ct: String, rm: String, t: int) -> LootContainer:
	var c := LootContainer.new()
	c.ctype = ct
	c.room = rm
	c.tier = t
	var col := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.4
	col.shape = sp
	c.add_child(col)
	return c


func _ready() -> void:
	_build()
	body_entered.connect(_on_body_entered)


func _mat(color: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	if mat != null:
		mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


func _build() -> void:
	var wood := _mat(Color(0.45, 0.33, 0.20))
	var wood_dark := _mat(Color(0.32, 0.23, 0.14))
	var metal := _mat(Color(0.45, 0.47, 0.50), 0.4, 0.6)
	var white := _mat(Color(0.88, 0.89, 0.90), 0.5)
	var accent := _mat(LootModels.tier_color(maxi(tier, 2)), 0.5, 0.0, 0.8)
	match ctype:
		"drawer":
			# Dresser with a drawer front that slides out when opened.
			_box(self, Vector3(0.9, 0.7, 0.5), Vector3(0, 0.35, 0), wood)
			_lid = Node3D.new()
			_lid.position = Vector3(0, 0.45, 0.26)
			add_child(_lid)
			_box(_lid, Vector3(0.7, 0.22, 0.04), Vector3.ZERO, wood_dark)
			_box(_lid, Vector3(0.12, 0.03, 0.03), Vector3(0, 0, 0.03), metal)
		"fridge":
			# Tall fridge; door swings open.
			_box(self, Vector3(0.7, 1.5, 0.6), Vector3(0, 0.75, 0), white)
			_lid = Node3D.new()
			_lid.position = Vector3(-0.35, 0.75, 0.30)
			add_child(_lid)
			_box(_lid, Vector3(0.7, 1.5, 0.05), Vector3(0.35, 0, 0), _mat(Color(0.80, 0.82, 0.84), 0.45))
			_box(self, Vector3(0.04, 0.5, 0.04), Vector3(0.30, 0.75, 0.34), metal)
		"rack":
			# Weapon rack: posts + crossbar; guns lean on it.
			_box(self, Vector3(0.08, 1.1, 0.08), Vector3(-0.55, 0.55, 0), wood_dark)
			_box(self, Vector3(0.08, 1.1, 0.08), Vector3(0.55, 0.55, 0), wood_dark)
			_box(self, Vector3(1.2, 0.08, 0.08), Vector3(0, 1.0, 0), wood_dark)
			_box(self, Vector3(1.2, 0.06, 0.4), Vector3(0, 0.03, 0), wood)
			_lid = Node3D.new()
			add_child(_lid)  # rack "opens" by tipping its accent bar
			_box(_lid, Vector3(1.2, 0.05, 0.05), Vector3(0, 1.06, 0), accent)
		"shelf":
			# Open shelf unit.
			_box(self, Vector3(0.06, 1.3, 0.4), Vector3(-0.5, 0.65, 0), wood)
			_box(self, Vector3(0.06, 1.3, 0.4), Vector3(0.5, 0.65, 0), wood)
			_box(self, Vector3(1.05, 0.06, 0.4), Vector3(0, 0.45, 0), wood)
			_box(self, Vector3(1.05, 0.06, 0.4), Vector3(0, 0.9, 0), wood)
			_box(self, Vector3(1.05, 0.06, 0.45), Vector3(0, 0.03, 0), wood_dark)
			_lid = Node3D.new()
			add_child(_lid)
			_box(_lid, Vector3(1.05, 0.04, 0.42), Vector3(0, 1.32, 0), accent)
		"medbox":
			_box(self, Vector3(0.7, 0.5, 0.5), Vector3(0, 0.25, 0), white)
			var red := _mat(Color(0.85, 0.10, 0.12), 0.5, 0.0, 0.5)
			_box(self, Vector3(0.24, 0.07, 0.02), Vector3(0, 0.28, 0.26), red)
			_box(self, Vector3(0.07, 0.24, 0.02), Vector3(0, 0.28, 0.26), red)
			_lid = Node3D.new()
			_lid.position = Vector3(0, 0.5, -0.25)
			add_child(_lid)
			_box(_lid, Vector3(0.7, 0.06, 0.5), Vector3(0, 0.03, 0.25), white)
		_:
			# Wooden supply crate with flip lid.
			_box(self, Vector3(0.8, 0.55, 0.6), Vector3(0, 0.28, 0), wood)
			_box(self, Vector3(0.84, 0.08, 0.64), Vector3(0, 0.10, 0), wood_dark)
			_box(self, Vector3(0.84, 0.08, 0.64), Vector3(0, 0.45, 0), wood_dark)
			_lid = Node3D.new()
			_lid.position = Vector3(0, 0.55, -0.30)
			add_child(_lid)
			_box(_lid, Vector3(0.8, 0.08, 0.6), Vector3(0, 0.04, 0.30), wood)
			_box(_lid, Vector3(0.82, 0.03, 0.1), Vector3(0, 0.09, 0.30), accent)
	# Tier accent strip + prompt label.
	_box(self, Vector3(0.5, 0.04, 0.02), Vector3(0, 0.06, 0.32), accent)
	_label = Label3D.new()
	_label.text = "SEARCH"
	_label.font_size = 48
	_label.pixel_size = 0.006
	_label.modulate = Color(1, 1, 1, 0.9)
	_label.outline_size = 8
	_label.position = Vector3(0, 1.35, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _process(delta: float) -> void:
	if opened:
		return
	_t += delta
	if _label != null:
		_label.position.y = 1.35 + sin(_t * 2.5) * 0.06


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
	# Open animation per type.
	var tw := create_tween()
	tw.set_parallel(true)
	if _lid != null:
		match ctype:
			"drawer":
				tw.tween_property(_lid, "position:z", 0.55, 0.35).set_trans(Tween.TRANS_BACK)
			"fridge":
				tw.tween_property(_lid, "rotation:y", -1.9, 0.45).set_trans(Tween.TRANS_BACK)
			"rack", "shelf":
				tw.tween_property(_lid, "position:y", 0.35, 0.4)
			_:
				tw.tween_property(_lid, "rotation:x", -1.85, 0.5).set_trans(Tween.TRANS_BACK)
	_play_open_sound()
	# Spawn contents after the lid starts moving.
	var tw2 := create_tween()
	tw2.tween_interval(0.3)
	tw2.tween_callback(_spawn_contents)


func _play_open_sound() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("play_loot_sound"):
		scene.play_loot_sound(LootAudio.open_stream(), global_position)


func _spawn_contents() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("spawn_container_loot"):
		return
	var items := _roll_contents()
	var i := 0
	for it in items:
		var ang := TAU * float(i) / float(maxi(items.size(), 1))
		var pos := global_position + Vector3(cos(ang) * 1.1, 0.35, sin(ang) * 1.1)
		scene.spawn_container_loot(it, pos)
		i += 1


## Room-logic contents: list of {kind, amount, tier} or {gun, tier} dicts.
func _roll_contents() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var out: Array = []
	var n := 2 + rng.randi() % 2  # 2-3 items
	for i in range(n):
		out.append(_roll_one(rng))
	return out


func _roll_one(rng: RandomNumberGenerator) -> Dictionary:
	var t: int = clampi(tier + rng.randi() % 2, 0, 5)
	match room:
		"kitchen":
			return {"kind": "health", "amount": 40 + 20 * t, "tier": mini(t, 3)} if rng.randf() < 0.7 \
				else {"kind": "cash", "amount": 150 + 100 * t, "tier": t}
		"bedroom":
			var r := rng.randf()
			if r < 0.4:
				return {"kind": "armor", "amount": 1, "tier": t}
			if r < 0.75:
				return {"kind": "ammo", "amount": 60, "tier": t, "caliber": _pick_caliber(rng)}
			return {"kind": "cash", "amount": 120 + 80 * t, "tier": t}
		"garage":
			if rng.randf() < 0.45:
				return {"attach": GunDefs.ATTACH_LOOT[rng.randi() % GunDefs.ATTACH_LOOT.size()], "tier": 2}
			return {"kind": "ammo", "amount": 60, "tier": t, "caliber": _pick_caliber(rng)}
		"armory":
			if rng.randf() < 0.5:
				return {"gun": GunDefs.roll_gun(mini(t + 1, 5), rng), "tier": mini(t + 1, 5)}
			return {"kind": "ammo", "amount": 90, "tier": t, "caliber": _pick_caliber(rng)}
		_:
			var r2 := rng.randf()
			if r2 < 0.3:
				return {"kind": "health", "amount": 40, "tier": t}
			if r2 < 0.55:
				return {"kind": "ammo", "amount": 60, "tier": t, "caliber": _pick_caliber(rng)}
			if r2 < 0.7:
				return {"kind": "armor", "amount": 1, "tier": t}
			if r2 < 0.85:
				return {"kind": "cash", "amount": 100 + 60 * t, "tier": t}
			return {"kind": "grenade", "amount": 1, "tier": t}


func _pick_caliber(rng: RandomNumberGenerator) -> String:
	var cals := ["light", "medium", "medium", "heavy", "shell"]
	return cals[rng.randi() % cals.size()]
