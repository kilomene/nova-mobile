extends Node3D
class_name SoldierRig
## Procedural soldier: Skeleton3D (~28 bones) with rigid body-part meshes
## parented to bones via BoneAttachment3D (mobile-appropriate, NOT skinned).
## ~1.8m adult, natural ~7.5-head proportions, slim athletic build.
## Tactical gear: plate carrier + pouches, helmet, goggles, balaclava,
## backpack (own bone for secondary motion), knee/elbow pads, gloves, boots.
## Ragdoll: PhysicalBoneSimulator3D + PhysicalBone3D per major bone;
## set_ragdoll(true) switches animated -> simulated with incoming momentum.

# Bone layout: name -> [parent_name, rest_pos, rest_euler]
# Character faces -Z. Left side = -X.
const BONE_DEFS := [
	["Hips", "", Vector3(0, 0.98, 0), Vector3.ZERO],
	["Spine", "Hips", Vector3(0, 0.12, 0), Vector3.ZERO],
	["Spine1", "Spine", Vector3(0, 0.14, 0), Vector3.ZERO],
	["Neck", "Spine1", Vector3(0, 0.20, 0), Vector3.ZERO],
	["Head", "Neck", Vector3(0, 0.08, 0), Vector3.ZERO],
	["ClavicleL", "Spine1", Vector3(-0.10, 0.16, 0), Vector3.ZERO],
	["ClavicleR", "Spine1", Vector3(0.10, 0.16, 0), Vector3.ZERO],
	["ShoulderL", "ClavicleL", Vector3(-0.11, 0.02, 0), Vector3.ZERO],
	["ShoulderR", "ClavicleR", Vector3(0.11, 0.02, 0), Vector3.ZERO],
	["UpperArmL", "ShoulderL", Vector3(-0.03, -0.02, 0), Vector3(0, 0, -0.10)],
	["UpperArmR", "ShoulderR", Vector3(0.03, -0.02, 0), Vector3(0, 0, 0.10)],
	["ForearmL", "UpperArmL", Vector3(0, -0.28, 0), Vector3(0.12, 0, 0)],
	["ForearmR", "UpperArmR", Vector3(0, -0.28, 0), Vector3(0.12, 0, 0)],
	["HandL", "ForearmL", Vector3(0, -0.26, 0), Vector3.ZERO],
	["HandR", "ForearmR", Vector3(0, -0.26, 0), Vector3.ZERO],
	["FingerL", "HandL", Vector3(0, -0.09, -0.01), Vector3.ZERO],
	["FingerR", "HandR", Vector3(0, -0.09, -0.01), Vector3.ZERO],
	["ThighL", "Hips", Vector3(-0.11, -0.04, 0), Vector3.ZERO],
	["ThighR", "Hips", Vector3(0.11, -0.04, 0), Vector3.ZERO],
	["ShinL", "ThighL", Vector3(0, -0.44, 0), Vector3.ZERO],
	["ShinR", "ThighR", Vector3(0, -0.44, 0), Vector3.ZERO],
	["FootL", "ShinL", Vector3(0, -0.42, 0), Vector3.ZERO],
	["FootR", "ShinR", Vector3(0, -0.42, 0), Vector3.ZERO],
	["ToeL", "FootL", Vector3(0, -0.03, -0.12), Vector3.ZERO],
	["ToeR", "FootR", Vector3(0, -0.03, -0.12), Vector3.ZERO],
	["VestPlate", "Spine", Vector3(0, 0.06, 0), Vector3.ZERO],
	["Backpack", "Spine1", Vector3(0, 0.06, 0.17), Vector3.ZERO],
	["Weapon", "HandR", Vector3(0, -0.02, -0.06), Vector3.ZERO],
]

# Bones that get a PhysicalBone3D for ragdoll (major masses only).
const PHYS_BONES := ["Hips", "Spine", "Spine1", "Neck", "Head",
	"UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "HandL", "HandR",
	"ThighL", "ThighR", "ShinL", "ShinR", "FootL", "FootR"]
# mass per physical bone (kg, ~76 total)
const PHYS_MASS := {"Hips": 12.0, "Spine": 9.0, "Spine1": 9.0, "Neck": 2.0, "Head": 5.0,
	"UpperArmL": 2.5, "UpperArmR": 2.5, "ForearmL": 1.5, "ForearmR": 1.5,
	"HandL": 0.6, "HandR": 0.6, "ThighL": 8.0, "ThighR": 8.0,
	"ShinL": 4.0, "ShinR": 4.0, "FootL": 1.5, "FootR": 1.5}

# Gear variants: uniform, vest, helmet, backpack, pants tint.
# [FRAME] "hooded": the primary operator reference — light gray hooded
# jacket (hood UP, face in shadow), dark bulky plate carrier, cargo pants,
# rucksack. Hood/helmet visibility toggles per variant.
const VARIANTS := [
	{"name": "woodland", "uniform": Color(0.29, 0.32, 0.19), "vest": Color(0.23, 0.25, 0.16),
		"helmet": Color(0.25, 0.28, 0.17), "pack": Color(0.42, 0.38, 0.27), "pants": Color(0.26, 0.28, 0.18)},
	{"name": "desert", "uniform": Color(0.63, 0.55, 0.36), "vest": Color(0.54, 0.45, 0.31),
		"helmet": Color(0.60, 0.52, 0.34), "pack": Color(0.48, 0.40, 0.28), "pants": Color(0.58, 0.50, 0.33)},
	{"name": "blackops", "uniform": Color(0.14, 0.14, 0.16), "vest": Color(0.10, 0.10, 0.11),
		"helmet": Color(0.08, 0.08, 0.09), "pack": Color(0.16, 0.16, 0.18), "pants": Color(0.12, 0.12, 0.14)},
	{"name": "arctic", "uniform": Color(0.75, 0.77, 0.78), "vest": Color(0.62, 0.65, 0.66),
		"helmet": Color(0.80, 0.81, 0.82), "pack": Color(0.55, 0.57, 0.58), "pants": Color(0.70, 0.72, 0.73)},
	{"name": "hooded", "uniform": Color(0.72, 0.73, 0.75), "vest": Color(0.15, 0.15, 0.17),
		"helmet": Color(0.18, 0.18, 0.20), "pack": Color(0.30, 0.28, 0.25), "pants": Color(0.68, 0.69, 0.71),
		"hood": true, "bulky_vest": true},
	# NOVA default characters (selectable): original designs in CODM's
	# Special Ops 1 / 3 visual language.
	{"name": "sentinel", "uniform": Color(0.42, 0.46, 0.52), "vest": Color(0.16, 0.16, 0.18),
		"helmet": Color(0.42, 0.46, 0.52), "pack": Color(0.30, 0.30, 0.33), "pants": Color(0.40, 0.44, 0.50),
		"digi": true, "headgear": "helmet", "goggles": "red", "nvg": true, "boommic": true,
		"face": false, "shell_rig": false, "balaclava": Color(0.88, 0.88, 0.86)},
	{"name": "breacher", "uniform": Color(0.42, 0.46, 0.52), "vest": Color(0.16, 0.16, 0.18),
		"helmet": Color(0.55, 0.47, 0.32), "pack": Color(0.30, 0.30, 0.33), "pants": Color(0.40, 0.44, 0.50),
		"digi": true, "headgear": "cap", "goggles": "none", "nvg": false, "boommic": false,
		"face": true, "shell_rig": true, "cap_color": Color(0.58, 0.50, 0.34)},
]

static var _mat_templates := {}

var skel: Skeleton3D
var sim: PhysicalBoneSimulator3D
var rest_pose: Array = []  # Array[Transform3D], indexed by bone
var _mats := {}  # per-rig material instances
var _variant := 0
var _phys := {}  # bone name -> PhysicalBone3D
var _phys_shapes := []  # CollisionShape3D (disabled until ragdoll)
var _head_meshes: Array = []
var _hood_meshes: Array = []  # hooded-variant meshes (hidden unless variant has "hood")
var _helmet_meshes: Array = []  # helmet shell (hidden when hood up or cap worn)
var _goggles_dark: Array = []  # dark goggles + strap
var _goggles_red: Array = []  # red-lens goggles + strap (Sentinel)
var _cap_meshes: Array = []  # baseball cap (Breacher)
var _nvg_meshes: Array = []  # NVG mount (Sentinel)
var _boommic_meshes: Array = []  # headset boom mic (Sentinel)
var _face_meshes: Array = []  # visible face + hair + ears (Breacher)
var _shell_meshes: Array = []  # red shotgun shell row (Breacher)
var _balaclava_head: MeshInstance3D  # covered-face head sphere
var _ragdoll := false


static func _templates() -> Dictionary:
	if not _mat_templates.is_empty():
		return _mat_templates
	var defs := {
		"uniform": [Color(0.29, 0.32, 0.19), 0.92, 0.0],
		"vest": [Color(0.23, 0.25, 0.16), 0.88, 0.0],
		"helmet": [Color(0.25, 0.28, 0.17), 0.55, 0.0],
		"pack": [Color(0.42, 0.38, 0.27), 0.9, 0.0],
		"pants": [Color(0.26, 0.28, 0.18), 0.92, 0.0],
		"balaclava": [Color(0.09, 0.09, 0.10), 0.95, 0.0],
		"glove": [Color(0.13, 0.12, 0.10), 0.7, 0.0],
		"boot": [Color(0.16, 0.13, 0.10), 0.55, 0.0],
		"pad": [Color(0.12, 0.12, 0.13), 0.6, 0.0],
		"gunmetal": [Color(0.12, 0.12, 0.13), 0.38, 0.75],
		"metal": [Color(0.35, 0.35, 0.37), 0.35, 0.85],
		"glass": [Color(0.05, 0.08, 0.10), 0.15, 0.4],
		"lensred": [Color(0.50, 0.10, 0.05), 0.15, 0.3],
		"face": [Color(0.76, 0.60, 0.48), 0.75, 0.0],
		"hair": [Color(0.16, 0.12, 0.09), 0.9, 0.0],
		"cap": [Color(0.58, 0.50, 0.34), 0.9, 0.0],
		"shellred": [Color(0.55, 0.08, 0.06), 0.4, 0.2],
	}
	for k in defs.keys():
		var m := StandardMaterial3D.new()
		m.albedo_color = defs[k][0]
		m.roughness = defs[k][1]
		m.metallic = defs[k][2]
		if k == "glass":
			m.emission_enabled = true
			m.emission = Color(0.1, 0.25, 0.35)
			m.emission_energy_multiplier = 0.4
		if k == "lensred":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.25, 0.08)
			m.emission_energy_multiplier = 1.2
		_mat_templates[k] = m
	return _mat_templates


## Procedural blue-grey digital-camo pixel texture (shared, generated once).
static var _digi_tex: ImageTexture


static func _digi_texture() -> ImageTexture:
	if _digi_tex != null:
		return _digi_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tones := [Color(0.45, 0.49, 0.55), Color(0.30, 0.33, 0.40),
		Color(0.22, 0.24, 0.30), Color(0.62, 0.65, 0.70)]
	img.fill(tones[0])
	for i in range(260):
		var c: Color = tones[rng.randi_range(0, 3)]
		var x0 := rng.randi_range(0, 60)
		var y0 := rng.randi_range(0, 60)
		var w := rng.randi_range(2, 5)
		var h := rng.randi_range(2, 5)
		for px in range(x0, mini(x0 + w, 64)):
			for py in range(y0, mini(y0 + h, 64)):
				img.set_pixel(px, py, c)
	_digi_tex = ImageTexture.create_from_image(img)
	return _digi_tex


func _ready() -> void:
	_build_skeleton()
	_build_materials()
	_build_meshes()
	_build_physical_bones()
	set_variant(_variant)


func bone_index(bname: String) -> int:
	return skel.find_bone(bname)


func get_bone(bname: String) -> int:
	return skel.find_bone(bname)


func bone_count() -> int:
	return skel.get_bone_count()


func rig_height() -> float:
	# Approximate standing height: head bone (global rest) + helmet.
	var hp: Vector3 = skel.get_bone_global_rest(bone_index("Head")).origin
	return hp.y + 0.30


func aim_point() -> Vector3:
	# Chest height — where shooters aim (global rest; stable reference).
	var t: Transform3D = skel.get_bone_global_rest(bone_index("Spine1"))
	return t.origin + Vector3(0, 0.06, 0)


func muzzle_point() -> Vector3:
	var t: Transform3D = skel.get_bone_global_pose(bone_index("Weapon"))
	return t.origin + t.basis.z * -0.55


func attach_to_bone(bname: String, node: Node) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bname
	skel.add_child(att)
	att.add_child(node)
	return att


## Class identity accent: small emissive shoulder patch in the class color.
var _accent_mesh: MeshInstance3D = null

func set_class_accent(c: Color) -> void:
	if _accent_mesh == null:
		_accent_mesh = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.06, 0.02)
		_accent_mesh.mesh = bm
		_accent_mesh.position = Vector3(0.02, 0.05, -0.14)
		attach_to_bone("ClavicleL", _accent_mesh)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	_accent_mesh.set_surface_override_material(0, m)
	_accent_mesh.visible = true


func _set_group(arr: Array, on: bool) -> void:
	for mi in arr:
		(mi as MeshInstance3D).visible = on


func _any_visible(arr: Array) -> bool:
	for mi in arr:
		if (mi as MeshInstance3D).visible:
			return true
	return false


## Visibility snapshot of all gear groups (used by tests).
func gear_state() -> Dictionary:
	return {
		"hood": _any_visible(_hood_meshes),
		"helmet": _any_visible(_helmet_meshes),
		"cap": _any_visible(_cap_meshes),
		"goggles_dark": _any_visible(_goggles_dark),
		"goggles_red": _any_visible(_goggles_red),
		"face": _any_visible(_face_meshes),
		"nvg": _any_visible(_nvg_meshes),
		"boommic": _any_visible(_boommic_meshes),
		"shell_rig": _any_visible(_shell_meshes),
	}


func set_variant(i: int) -> void:
	_variant = clampi(i, 0, VARIANTS.size() - 1)
	var v: Dictionary = VARIANTS[_variant]
	# Digital-camo texture on uniform + helmet when the variant has "digi".
	var um: StandardMaterial3D = _mats["uniform"]
	var hlm: StandardMaterial3D = _mats["helmet"]
	if bool(v.get("digi", false)):
		var dt := _digi_texture()
		for m in [um, hlm]:
			m.albedo_texture = dt
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.albedo_color = Color(1, 1, 1)
	else:
		um.albedo_texture = null
		um.albedo_color = v["uniform"]
		hlm.albedo_texture = null
		hlm.albedo_color = v["helmet"]
	(_mats["vest"] as StandardMaterial3D).albedo_color = v["vest"]
	(_mats["pack"] as StandardMaterial3D).albedo_color = v["pack"]
	(_mats["pants"] as StandardMaterial3D).albedo_color = v["pants"]
	# Balaclava color (Sentinel: white).
	(_mats["balaclava"] as StandardMaterial3D).albedo_color = v.get(
		"balaclava", (_templates()["balaclava"] as StandardMaterial3D).albedo_color)
	# Cap color (Breacher: tan).
	if v.has("cap_color"):
		(_mats["cap"] as StandardMaterial3D).albedo_color = v["cap_color"]
	var hood: bool = bool(v.get("hood", false))
	var headgear: String = str(v.get("headgear", "helmet"))
	var goggles: String = str(v.get("goggles", "dark"))
	var face_on: bool = bool(v.get("face", false))
	var helmet_on: bool = (not hood) and headgear == "helmet"
	_set_group(_hood_meshes, hood)
	_set_group(_helmet_meshes, helmet_on)
	_set_group(_cap_meshes, (not hood) and headgear == "cap")
	_set_group(_goggles_dark, helmet_on and goggles == "dark")
	_set_group(_goggles_red, helmet_on and goggles == "red")
	# Covered face (balaclava head) vs visible face.
	if _balaclava_head != null:
		_balaclava_head.visible = not face_on
	_set_group(_face_meshes, face_on)
	_set_group(_nvg_meshes, helmet_on and bool(v.get("nvg", false)))
	_set_group(_boommic_meshes, bool(v.get("boommic", false)))
	_set_group(_shell_meshes, bool(v.get("shell_rig", false)))


func variant_name() -> String:
	return str(VARIANTS[_variant]["name"])


## Hide head/helmet/goggles from the player's own camera (layer 2) while
## keeping shadow casting on — for the FPP body.
func hide_head_from_camera() -> void:
	for mi in _head_meshes:
		(mi as MeshInstance3D).layers = 2


func set_ragdoll(on: bool, incoming := Vector3.ZERO) -> void:
	_ragdoll = on
	if on:
		for s in _phys_shapes:
			(s as CollisionShape3D).set_deferred("disabled", false)
		sim.active = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		for bname in _phys.keys():
			var pb: PhysicalBone3D = _phys[bname]
			# Setting linear_velocity wakes the bone (no `sleeping` on PhysicalBone3D).
			pb.linear_velocity = incoming + Vector3(
				rng.randf_range(-1.2, 1.2), rng.randf_range(0.5, 2.0), rng.randf_range(-1.2, 1.2))
			pb.angular_velocity = Vector3(
				rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
	else:
		sim.active = false
		for s in _phys_shapes:
			(s as CollisionShape3D).set_deferred("disabled", true)


func is_ragdoll() -> bool:
	return _ragdoll


func simulator_active() -> bool:
	return sim.active if sim != null else false


# ------------------------------------------------------------- construction
func _build_skeleton() -> void:
	skel = Skeleton3D.new()
	skel.name = "Skeleton"
	add_child(skel)
	for d in BONE_DEFS:
		var idx := skel.add_bone(str(d[0]))
		if str(d[1]) != "":
			skel.set_bone_parent(idx, skel.find_bone(str(d[1])))
		var t := Transform3D(Basis.from_euler(d[3] as Vector3), d[2] as Vector3)
		skel.set_bone_rest(idx, t)
	rest_pose.clear()
	for i in range(skel.get_bone_count()):
		rest_pose.append(skel.get_bone_rest(i))


func _build_materials() -> void:
	_mats.clear()
	for k in _templates().keys():
		_mats[k] = (_templates()[k] as StandardMaterial3D).duplicate()


func _mi(mesh: Mesh, mat_key: String, bname: String, pos: Vector3,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, _mats[mat_key])
	var att := BoneAttachment3D.new()
	att.bone_name = bname
	skel.add_child(att)
	att.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	return c


func _build_meshes() -> void:
	# --- legs ---
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		_mi(_cap(0.088, 0.36), "pants", "Thigh" + side, Vector3(0, -0.20, 0))
		_mi(_cap(0.070, 0.36), "pants", "Shin" + side, Vector3(0, -0.20, 0))
		_mi(_box(0.11, 0.10, 0.06), "pad", "Shin" + side, Vector3(0, -0.045, -0.085))  # knee pad
		_mi(_box(0.11, 0.10, 0.27), "boot", "Foot" + side, Vector3(0, -0.055, -0.055))  # boot
		_mi(_box(0.105, 0.075, 0.10), "boot", "Toe" + side, Vector3(0, -0.06, -0.03))  # toe cap
		if side == "R":
			_mi(_box(0.08, 0.17, 0.07), "pad", "ThighR", Vector3(0.105, -0.14, 0.03))  # thigh holster
	# --- pelvis / torso ---
	_mi(_box(0.32, 0.22, 0.24), "pants", "Hips", Vector3(0, -0.03, 0))
	_mi(_box(0.335, 0.06, 0.25), "metal", "Hips", Vector3(0, 0.075, 0))  # belt
	_mi(_box(0.30, 0.20, 0.22), "uniform", "Spine", Vector3(0, 0.05, 0))
	_mi(_box(0.36, 0.26, 0.24), "uniform", "Spine1", Vector3(0, 0.08, 0))
	# --- plate carrier vest + pouches ---
	_mi(_box(0.335, 0.30, 0.29), "vest", "VestPlate", Vector3(0, 0.07, -0.005))
	_mi(_box(0.24, 0.26, 0.045), "vest", "VestPlate", Vector3(0, 0.07, -0.155))  # front plate
	_mi(_box(0.24, 0.22, 0.045), "vest", "VestPlate", Vector3(0, 0.07, 0.15))  # back plate
	for i in range(3):
		_mi(_box(0.075, 0.10, 0.055), "pack", "VestPlate",
			Vector3(-0.095 + 0.095 * i, -0.045, -0.165))  # mag pouches
	_mi(_box(0.09, 0.07, 0.05), "pack", "VestPlate", Vector3(0.13, 0.10, -0.16))  # radio pouch
	# --- backpack (own bone: secondary motion) ---
	_mi(_box(0.30, 0.36, 0.15), "pack", "Backpack", Vector3(0, 0.03, 0.09))
	_mi(_cap(0.055, 0.30), "pack", "Backpack", Vector3(0, 0.24, 0.09), Vector3(PI * 0.5, 0, 0))  # bedroll
	# --- arms ---
	for side in ["L", "R"]:
		_mi(_cap(0.060, 0.26), "uniform", "UpperArm" + side, Vector3(0, -0.14, 0))  # sleeve
		_mi(_box(0.10, 0.09, 0.10), "uniform", "Shoulder" + side, Vector3(0, 0.0, 0))  # deltoid
		_mi(_cap(0.050, 0.24), "uniform", "Forearm" + side, Vector3(0, -0.13, 0))  # sleeve
		_mi(_box(0.085, 0.075, 0.085), "pad", "Forearm" + side, Vector3(0, -0.015, 0.035))  # elbow pad
		_mi(_box(0.070, 0.115, 0.050), "glove", "Hand" + side, Vector3(0, -0.055, 0))  # glove
		_mi(_box(0.060, 0.070, 0.045), "glove", "Finger" + side, Vector3(0, -0.035, 0))  # fingers
	# --- neck / head ---
	# Balaclava neck + covered-face head sphere (Sentinel: tinted white via variant).
	_mi(_cap(0.05, 0.10), "balaclava", "Neck", Vector3(0, 0.02, 0))
	_balaclava_head = _mi(_sph(0.105), "balaclava", "Head", Vector3(0, 0.10, -0.01),
		Vector3.ZERO, Vector3(1, 1.15, 1.05))
	_head_meshes.append(_balaclava_head)
	# Helmet shell (toggled by headgear == "helmet").
	var helm := _mi(_sph(0.135), "helmet", "Head", Vector3(0, 0.155, 0.015),
		Vector3.ZERO, Vector3(1.02, 0.78, 1.08))
	_head_meshes.append(helm)
	_helmet_meshes.append(helm)
	var brim := _mi(_box(0.20, 0.035, 0.03), "helmet", "Head", Vector3(0, 0.10, 0.10))  # helmet rear brim
	_head_meshes.append(brim)
	_helmet_meshes.append(brim)
	# Dark goggles + strap.
	var gog := _mi(_box(0.165, 0.062, 0.055), "glass", "Head", Vector3(0, 0.115, -0.098))
	_head_meshes.append(gog)
	_goggles_dark.append(gog)
	var strap := _mi(_box(0.21, 0.03, 0.21), "pad", "Head", Vector3(0, 0.115, 0.0))  # goggle strap
	_head_meshes.append(strap)
	_goggles_dark.append(strap)
	# Red-lens goggles (Sentinel): dark frame + emissive red-orange lenses.
	var rg_frame := _mi(_box(0.175, 0.075, 0.05), "pad", "Head", Vector3(0, 0.115, -0.096))
	_head_meshes.append(rg_frame)
	_goggles_red.append(rg_frame)
	var rg_lens := _mi(_box(0.150, 0.052, 0.022), "lensred", "Head", Vector3(0, 0.115, -0.118))
	_head_meshes.append(rg_lens)
	_goggles_red.append(rg_lens)
	var rg_strap := _mi(_box(0.21, 0.03, 0.21), "pad", "Head", Vector3(0, 0.115, 0.0))
	_head_meshes.append(rg_strap)
	_goggles_red.append(rg_strap)
	# NVG mount (Sentinel): front mount block + flip arm + binocular housing.
	var nvg_mount := _mi(_box(0.06, 0.05, 0.045), "gunmetal", "Head", Vector3(0, 0.195, -0.10))
	_head_meshes.append(nvg_mount)
	_nvg_meshes.append(nvg_mount)
	var nvg_arm := _mi(_box(0.03, 0.035, 0.07), "gunmetal", "Head", Vector3(0, 0.175, -0.125))
	_nvg_meshes.append(nvg_arm)
	var nvg_binoc := _mi(_box(0.12, 0.055, 0.05), "gunmetal", "Head", Vector3(0, 0.155, -0.145))
	_nvg_meshes.append(nvg_binoc)
	# Boom-mic headset (Sentinel): side module + boom + mic tip.
	var hs_mod := _mi(_box(0.05, 0.065, 0.035), "pad", "Head", Vector3(0.115, 0.10, -0.01))
	_head_meshes.append(hs_mod)
	_boommic_meshes.append(hs_mod)
	var hs_boom := _mi(_cyl(0.008, 0.008, 0.15), "pad", "Head", Vector3(0.10, 0.055, -0.075),
		Vector3(PI * 0.5, 0, 0))
	_boommic_meshes.append(hs_boom)
	var hs_tip := _mi(_box(0.028, 0.028, 0.035), "gunmetal", "Head", Vector3(0.10, 0.055, -0.145))
	_boommic_meshes.append(hs_tip)
	# Baseball cap (Breacher): tan dome + front brim + patch.
	var cap_dome := _mi(_sph(0.125), "cap", "Head", Vector3(0, 0.155, 0.01),
		Vector3.ZERO, Vector3(1.0, 0.62, 1.05))
	_head_meshes.append(cap_dome)
	_cap_meshes.append(cap_dome)
	var cap_brim := _mi(_box(0.20, 0.025, 0.15), "cap", "Head", Vector3(0, 0.125, -0.155))
	_head_meshes.append(cap_brim)
	_cap_meshes.append(cap_brim)
	var cap_patch := _mi(_box(0.06, 0.045, 0.012), "pad", "Head", Vector3(0, 0.16, -0.108))
	_cap_meshes.append(cap_patch)
	# Visible face (Breacher): skin head + short hair + ears. Clean, no uncanny detail.
	var face_head := _mi(_sph(0.102), "face", "Head", Vector3(0, 0.10, -0.012),
		Vector3.ZERO, Vector3(1, 1.12, 1.02))
	_head_meshes.append(face_head)
	_face_meshes.append(face_head)
	var face_hair := _mi(_sph(0.108), "hair", "Head", Vector3(0, 0.135, 0.028),
		Vector3.ZERO, Vector3(1.02, 0.82, 1.04))
	_head_meshes.append(face_hair)
	_face_meshes.append(face_hair)
	for ex in [-1.0, 1.0]:
		var ear := _mi(_box(0.03, 0.05, 0.022), "face", "Head", Vector3(0.10 * ex, 0.09, 0.0))
		_head_meshes.append(ear)
		_face_meshes.append(ear)
	# Red shotgun-shell row on the chest rig (Breacher signature).
	var shell_strip := _mi(_box(0.21, 0.022, 0.03), "pad", "VestPlate", Vector3(0, 0.115, -0.185))
	_shell_meshes.append(shell_strip)
	for i in range(6):
		var shell := _mi(_cyl(0.016, 0.016, 0.075), "shellred", "VestPlate",
			Vector3(-0.078 + 0.031 * i, 0.115, -0.20), Vector3(PI * 0.5, 0, 0))
		_shell_meshes.append(shell)
	# --- [FRAME] hooded variant: hood UP over the head (face in shadow),
	# drape over the shoulders; dark bulky plate carrier ~1.5x torso width.
	# Built always, hidden unless the variant has "hood".
	var hood_dome := _mi(_sph(0.148), "uniform", "Head", Vector3(0, 0.135, 0.008),
		Vector3.ZERO, Vector3(1.04, 1.08, 1.10))
	_hood_meshes.append(hood_dome)
	_head_meshes.append(hood_dome)
	var hood_drape := _mi(_cyl(0.10, 0.21, 0.24), "uniform", "Head", Vector3(0, -0.06, 0.02))
	_hood_meshes.append(hood_drape)
	_head_meshes.append(hood_drape)
	var vest_bulky := _mi(_box(0.44, 0.34, 0.335), "vest", "VestPlate", Vector3(0, 0.07, -0.005))
	_hood_meshes.append(vest_bulky)
	for mi in _hood_meshes:
		(mi as MeshInstance3D).visible = false
	# --- held rifle (parented to Weapon bone on right hand) ---
	_mi(_box(0.065, 0.10, 0.52), "gunmetal", "Weapon", Vector3(0, 0.01, -0.22))
	_mi(_box(0.05, 0.14, 0.09), "gunmetal", "Weapon", Vector3(0, -0.07, -0.10))  # grip
	_mi(_box(0.045, 0.16, 0.07), "gunmetal", "Weapon", Vector3(0, -0.10, -0.24))  # magazine
	_mi(_box(0.06, 0.09, 0.16), "gunmetal", "Weapon", Vector3(0, 0.02, 0.02))  # stock
	_mi(_box(0.03, 0.03, 0.10), "gunmetal", "Weapon", Vector3(0, 0.035, -0.46))  # barrel


func _build_physical_bones() -> void:
	for bname in PHYS_BONES:
		var idx := skel.find_bone(bname)
		if idx < 0:
			continue
		var pb := PhysicalBone3D.new()
		pb.name = bname  # matched to the bone by name
		pb.mass = float(PHYS_MASS.get(bname, 3.0))
		pb.friction = 0.8
		pb.linear_damp = 0.25
		pb.angular_damp = 1.4
		pb.gravity_scale = 1.0
		pb.can_sleep = true
		pb.collision_layer = 4
		pb.collision_mask = 1  # world only: never bone-vs-bone
		# Joints: PIN everywhere (4.3 exposes no cone/hinge angle properties;
		# pins keep the ragdoll connected and explosion-free; limbs still
		# tumble naturally via per-bone masses + damping).
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
		var cs := CollisionShape3D.new()
		cs.shape = _phys_shape_for(bname)
		cs.disabled = true  # enabled only during ragdoll
		pb.add_child(cs)
		_phys_shapes.append(cs)
		skel.add_child(pb)
		_phys[bname] = pb
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "RagdollSim"
	sim.active = false
	skel.add_child(sim)


func _phys_shape_for(bname: String) -> Shape3D:
	if bname in ["Hips", "Spine", "Spine1"]:
		var b := BoxShape3D.new()
		b.size = Vector3(0.34, 0.30, 0.26) if bname != "Hips" else Vector3(0.34, 0.24, 0.26)
		return b
	if bname == "Head":
		var s := SphereShape3D.new()
		s.radius = 0.14
		return s
	var c := CapsuleShape3D.new()
	if bname.begins_with("UpperArm") or bname.begins_with("Forearm"):
		c.radius = 0.07
		c.height = 0.30
	elif bname.begins_with("Hand"):
		c.radius = 0.06
		c.height = 0.16
	elif bname.begins_with("Thigh"):
		c.radius = 0.10
		c.height = 0.46
	elif bname.begins_with("Shin"):
		c.radius = 0.08
		c.height = 0.44
	else:  # Foot, Neck
		c.radius = 0.07
		c.height = 0.20
	return c
