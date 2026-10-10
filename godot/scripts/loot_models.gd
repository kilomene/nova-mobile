class_name LootModels
extends RefCounted
## Real 3D models for ground loot (no flat icons): medkits, armor plates,
## ammo boxes (colored by caliber), cash bundles, grenades, smoke canisters,
## armor shards, scorestreak devices. Plus tier visuals: glow ring colors,
## floating rarity beams for epic+ (legendary/orange, mythic/red).

# 7-tier spectrum: grey / green / blue / purple / orange / red(mythic) — index 6.
const TIER_COLORS := [
	Color(0.72, 0.72, 0.72),  # 0 common grey
	Color(0.72, 0.72, 0.72),  # 1 common grey
	Color(0.25, 0.90, 0.45),  # 2 uncommon green
	Color(0.35, 0.60, 1.00),  # 3 rare blue
	Color(0.70, 0.35, 1.00),  # 4 epic purple
	Color(1.00, 0.60, 0.15),  # 5 legendary orange
	Color(1.00, 0.16, 0.12),  # 6 mythic red
]
const TIER_NAMES := ["COMMON", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY", "MYTHIC"]

# Caliber colors for ammo boxes.
const CALIBER_COLORS := {
	"light": Color(0.95, 0.85, 0.40),
	"medium": Color(0.95, 0.65, 0.25),
	"heavy": Color(1.00, 0.45, 0.20),
	"shell": Color(0.85, 0.25, 0.20),
	"rocket": Color(0.60, 0.60, 0.65),
	"grenade": Color(0.35, 0.55, 0.30),
	"smoke": Color(0.70, 0.70, 0.75),
	"none": Color(0.70, 0.70, 0.70),
}


static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier, 0, 6)]


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, 6)]


static func _mat(color: Color, emission_mult := 0.0, metallic := 0.0, rough := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission_mult > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_mult
	return m


static func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	if mat != null:
		mi.set_surface_override_material(0, mat)
	return mi


## White medkit box with a red cross.
static func medkit() -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(0.42, 0.26, 0.30), Vector3.ZERO, _mat(Color(0.92, 0.93, 0.95), 0.25)))
	var red := _mat(Color(0.85, 0.10, 0.12), 0.6)
	root.add_child(_box(Vector3(0.20, 0.06, 0.02), Vector3(0, 0.02, 0.16), red))
	root.add_child(_box(Vector3(0.06, 0.20, 0.02), Vector3(0, 0.02, 0.16), red))
	root.add_child(_box(Vector3(0.30, 0.05, 0.06), Vector3(0, 0.16, 0), _mat(Color(0.55, 0.56, 0.58), 0.0, 0.4)))
	return root


## Stack of two armor plates (blue-grey ceramic).
static func armor_plates() -> Node3D:
	var root := Node3D.new()
	var pm := _mat(Color(0.30, 0.45, 0.75), 0.55)
	root.add_child(_box(Vector3(0.36, 0.05, 0.28), Vector3(0, 0.0, 0), pm))
	var p2 := _box(Vector3(0.36, 0.05, 0.28), Vector3(0.03, 0.07, 0.02), pm)
	p2.rotation.y = 0.35
	root.add_child(p2)
	return root


## Single armor shard (small plate fragment, +25 armor).
static func armor_shard() -> Node3D:
	var root := Node3D.new()
	var shard := _box(Vector3(0.22, 0.04, 0.18), Vector3.ZERO, _mat(Color(0.35, 0.55, 0.9), 0.9))
	shard.rotation.y = 0.5
	root.add_child(shard)
	return root


## Ammo box colored by caliber, with bullet tips on top.
static func ammo_box(caliber: String) -> Node3D:
	var root := Node3D.new()
	var cc: Color = CALIBER_COLORS.get(caliber, Color(0.7, 0.7, 0.7))
	root.add_child(_box(Vector3(0.40, 0.22, 0.28), Vector3.ZERO, _mat(Color(0.45, 0.38, 0.25), 0.15)))
	var tipm := _mat(cc, 0.7, 0.6, 0.35)
	for i in range(4):
		var tip := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.028
		cm.height = 0.10
		tip.mesh = cm
		tip.position = Vector3(-0.12 + 0.08 * float(i), 0.16, 0)
		tip.set_surface_override_material(0, tipm)
		root.add_child(tip)
	return root


## Cash bundle: banded green stack.
static func cash_bundle() -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(0.34, 0.12, 0.24), Vector3.ZERO, _mat(Color(0.15, 0.55, 0.25), 0.5)))
	root.add_child(_box(Vector3(0.36, 0.035, 0.26), Vector3(0, 0.01, 0), _mat(Color(0.85, 0.80, 0.60), 0.2)))
	return root


## Frag grenade: dark sphere body + lever + pin ring.
static func frag_grenade() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	body.mesh = sm
	body.set_surface_override_material(0, _mat(Color(0.20, 0.28, 0.16), 0.2, 0.35))
	root.add_child(body)
	root.add_child(_box(Vector3(0.10, 0.03, 0.03), Vector3(0, 0.11, 0), _mat(Color(0.5, 0.5, 0.52), 0.0, 0.7)))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.025
	tm.outer_radius = 0.045
	ring.mesh = tm
	ring.position = Vector3(0.07, 0.12, 0)
	ring.set_surface_override_material(0, _mat(Color(0.6, 0.6, 0.62), 0.0, 0.8))
	root.add_child(ring)
	return root


## Smoke canister: grey cylinder with colored band.
static func smoke_canister() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 0.20
	body.mesh = cm
	body.set_surface_override_material(0, _mat(Color(0.55, 0.57, 0.60), 0.15, 0.5))
	root.add_child(body)
	var band := MeshInstance3D.new()
	var bm2 := CylinderMesh.new()
	bm2.top_radius = 0.072
	bm2.bottom_radius = 0.072
	bm2.height = 0.06
	band.mesh = bm2
	band.position = Vector3(0, 0.05, 0)
	band.set_surface_override_material(0, _mat(Color(0.75, 0.75, 0.78), 0.7))
	root.add_child(band)
	return root


## Scorestreak devices: UAV drone / cluster-strike designator.
static func streak_device(kind: String) -> Node3D:
	var root := Node3D.new()
	if kind == "uav":
		# Tiny quad-rotor drone.
		root.add_child(_box(Vector3(0.22, 0.06, 0.22), Vector3.ZERO, _mat(Color(0.25, 0.28, 0.32), 0.4, 0.5)))
		var rm := _mat(Color(0.2, 0.8, 1.0), 1.2)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var rotor := MeshInstance3D.new()
				var dm := CylinderMesh.new()
				dm.top_radius = 0.09
				dm.bottom_radius = 0.09
				dm.height = 0.015
				rotor.mesh = dm
				rotor.position = Vector3(0.14 * sx, 0.05, 0.14 * sz)
				rotor.set_surface_override_material(0, rm)
				root.add_child(rotor)
	else:
		# Strike designator: dark case + red laser dot.
		root.add_child(_box(Vector3(0.26, 0.10, 0.18), Vector3.ZERO, _mat(Color(0.18, 0.18, 0.20), 0.3, 0.4)))
		root.add_child(_box(Vector3(0.05, 0.05, 0.05), Vector3(0, 0.08, 0), _mat(Color(1.0, 0.1, 0.1), 2.0)))
	return root


## Attachment in a foam-lined case.
static func attachment_case() -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(0.30, 0.12, 0.22), Vector3.ZERO, _mat(Color(0.16, 0.17, 0.20), 0.2, 0.3)))
	root.add_child(_box(Vector3(0.24, 0.04, 0.16), Vector3(0, 0.05, 0), _mat(Color(0.30, 0.55, 0.85), 0.9)))
	return root


## Vertical rarity beam pillar (epic+). Tall, translucent, visible far away.
static func rarity_beam(tier: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.55
	cm.height = 26.0
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c: Color = tier_color(tier)
	m.albedo_color = Color(c.r, c.g, c.b, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mi.set_surface_override_material(0, m)
	mi.position = Vector3(0, 13.0, 0)
	return mi


## Tier glow ring (flat torus on the ground).
static func tier_ring(tier: int, radius := 0.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.08
	tm.outer_radius = radius
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = tier_color(tier)
	mi.set_surface_override_material(0, m)
	return mi
