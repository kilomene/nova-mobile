class_name BuyStation
extends Node3D
## NOVA Mobile: buy station kiosk — CODM-style shop.
## Interaction + UI are driven by main.gd / hud.gd; this builds the kiosk.

# Full researched inventory — mirrors CODM BR buy stations (Season 5: Primal
# Reckoning): equipment, plate carriers, ammo, weapons, scorestreaks,
# gun mods, tank drop markers — plus NOVA-original vehicle services.
# Prices follow the classic COD buy-station economy.
const SHOP_ITEMS := [
	{"id": "frag_bundle", "cat": "EQUIPMENT", "name": "Frag Grenades ×3", "price": 400, "desc": "+3 cookable frags"},
	{"id": "medkit", "cat": "EQUIPMENT", "name": "Field Medkit", "price": 500, "desc": "Full heal"},
	{"id": "gas_mask", "cat": "EQUIPMENT", "name": "Gas Mask", "price": 3000, "desc": "30s collapse immunity"},
	{"id": "shield", "cat": "EQUIPMENT", "name": "Shield Turret", "price": 2000, "desc": "Deployable cover wall"},
	{"id": "armor", "cat": "PLATES", "name": "Armor Plate Bundle", "price": 1500, "desc": "Full armor refill"},
	{"id": "carrier", "cat": "PLATES", "name": "Juggernaut Carrier", "price": 2500, "desc": "+50 max armor, this match"},
	{"id": "ammo", "cat": "AMMO", "name": "Ammo Box", "price": 2000, "desc": "+240 all reserve ammo"},
	{"id": "mystery", "cat": "WEAPONS", "name": "Mystery Weapon", "price": 4000, "desc": "Random tier-4/5 gun"},
	{"id": "heavy", "cat": "WEAPONS", "name": "Thunderhead RP-7", "price": 6000, "desc": "Guaranteed heavy launcher"},
	{"id": "uav", "cat": "STREAKS", "name": "UAV Sweep", "price": 4000, "desc": "Reveal all enemies 25s"},
	{"id": "strike", "cat": "STREAKS", "name": "Cluster Strike", "price": 3000, "desc": "Missile barrage"},
	{"id": "precision", "cat": "STREAKS", "name": "Precision Airstrike", "price": 3500, "desc": "One massive blast"},
	{"id": "sentry", "cat": "STREAKS", "name": "Sentry Gun", "price": 4000, "desc": "Auto-turret, 60s"},
	{"id": "bomber", "cat": "STREAKS", "name": "'Jaka' Bomb Run", "price": 8000, "desc": "B2 carpet-bombs aim line"},
	{"id": "modkit", "cat": "GUN MODS", "name": "Gunsmith Mod Kit", "price": 1500, "desc": "Random attachment fitted"},
	{"id": "tankdrop", "cat": "TANK DROP", "name": "Tank Drop Marker", "price": 10000, "desc": "Tank airdropped nearby"},
	{"id": "repair", "cat": "VEHICLE", "name": "Vehicle Repair", "price": 1500, "desc": "Full repair (while driving)"},
	{"id": "paint", "cat": "VEHICLE", "name": "Paint Job", "price": 400, "desc": "New paint (while driving)"},
	{"id": "revive", "cat": "SURVIVAL", "name": "Self-Revive Kit", "price": 4500, "desc": "Revive yourself once"},
	{"id": "redeploy", "cat": "SURVIVAL", "name": "Redeploy Teammate", "price": 2000, "desc": "Drop a tagged teammate back in"},
]

const INTERACT_RADIUS := 4.0

var _t := 0.0
var _sign: Label3D = null


static func items() -> Array:
	return SHOP_ITEMS


static func price(item_id: String) -> int:
	for it in SHOP_ITEMS:
		if str(it["id"]) == item_id:
			return int(it["price"])
	return 0


static func item_by_id(item_id: String) -> Dictionary:
	for it in SHOP_ITEMS:
		if str(it["id"]) == item_id:
			return it
	return {}


static func can_afford(cash: int, item_id: String) -> bool:
	return cash >= price(item_id)


func _ready() -> void:
	_build_kiosk()


func _build_kiosk() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.15)
	dark.roughness = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.1, 0.5, 0.2)
	accent.emission_enabled = true
	accent.emission = Color(0.1, 0.9, 0.3)
	accent.emission_energy_multiplier = 1.2
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.02, 0.05, 0.08)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.2, 0.8, 1.0)
	screen_mat.emission_energy_multiplier = 0.9
	# Base + posts + canopy.
	_add_box(Vector3(2.4, 0.25, 1.6), Vector3(0, 0.12, 0), dark)
	_add_box(Vector3(0.18, 2.6, 0.18), Vector3(-1.0, 1.4, -0.6), dark)
	_add_box(Vector3(0.18, 2.6, 0.18), Vector3(1.0, 1.4, -0.6), dark)
	_add_box(Vector3(0.18, 2.6, 0.18), Vector3(-1.0, 1.4, 0.6), dark)
	_add_box(Vector3(0.18, 2.6, 0.18), Vector3(1.0, 1.4, 0.6), dark)
	_add_box(Vector3(2.8, 0.18, 2.0), Vector3(0, 2.75, 0), accent)
	# Counter + screen terminal.
	_add_box(Vector3(2.0, 1.0, 0.7), Vector3(0, 0.75, 0.3), dark)
	_add_box(Vector3(1.2, 0.8, 0.08), Vector3(0, 1.7, -0.35), screen_mat)
	# Floating "$" sign.
	_sign = Label3D.new()
	_sign.text = "$"
	_sign.font_size = 128
	_sign.pixel_size = 0.012
	_sign.modulate = Color(0.3, 1.0, 0.4)
	_sign.outline_size = 12
	_sign.outline_modulate = Color(0, 0, 0, 0.9)
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(0, 3.6, 0)
	add_child(_sign)
	# Light so it reads at a distance.
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.45)
	light.light_energy = 1.2
	light.omni_range = 9.0
	light.position = Vector3(0, 3.0, 0)
	add_child(light)
	# Interaction area.
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = INTERACT_RADIUS
	cs.shape = sph
	cs.position.y = 1.0
	area.add_child(cs)
	add_child(area)


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	if _sign != null:
		_sign.position.y = 3.6 + sin(_t * 2.0) * 0.15
