class_name GunModels
extends RefCounted
## Procedural NOVA gun models: viewmodel (first-person) + simplified world model.
## All geometry from boxes/cylinders; shared PBR-ish materials. No external assets.
## Gun points along -Z; origin at receiver/trigger area.

static var _mats := {}


static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if key == "gunmetal":
		m.albedo_color = Color(0.16, 0.17, 0.19); m.metallic = 0.85; m.roughness = 0.38
	elif key == "black":
		m.albedo_color = Color(0.09, 0.09, 0.10); m.metallic = 0.15; m.roughness = 0.68
	elif key == "steel":
		m.albedo_color = Color(0.48, 0.50, 0.53); m.metallic = 0.9; m.roughness = 0.3
	elif key == "wood":
		m.albedo_color = Color(0.42, 0.26, 0.14); m.metallic = 0.0; m.roughness = 0.58
	elif key == "tan":
		m.albedo_color = Color(0.52, 0.44, 0.31); m.metallic = 0.05; m.roughness = 0.62
	elif key == "od":
		m.albedo_color = Color(0.28, 0.32, 0.22); m.metallic = 0.1; m.roughness = 0.6
	elif key == "grey":
		m.albedo_color = Color(0.35, 0.36, 0.38); m.metallic = 0.4; m.roughness = 0.5
	elif key == "white":
		m.albedo_color = Color(0.76, 0.76, 0.79); m.metallic = 0.2; m.roughness = 0.45
	elif key == "dark":
		m.albedo_color = Color(0.04, 0.04, 0.05); m.metallic = 0.3; m.roughness = 0.6
	elif key == "glass":
		m.albedo_color = Color(0.25, 0.55, 0.75); m.metallic = 0.1; m.roughness = 0.15
		m.emission_enabled = true; m.emission = Color(0.2, 0.5, 0.7)
		m.emission_energy_multiplier = 0.6
	elif key == "brass":
		m.albedo_color = Color(0.72, 0.55, 0.25); m.metallic = 0.9; m.roughness = 0.35
	elif key == "bronze":
		m.albedo_color = Color(0.45, 0.32, 0.18); m.metallic = 0.85; m.roughness = 0.42
	elif key == "graphite":
		m.albedo_color = Color(0.22, 0.23, 0.26); m.metallic = 0.7; m.roughness = 0.45
	elif key == "bluegrey":
		m.albedo_color = Color(0.30, 0.36, 0.44); m.metallic = 0.5; m.roughness = 0.5
	elif key == "carbon":
		m.albedo_color = Color(0.07, 0.07, 0.08); m.metallic = 0.35; m.roughness = 0.4
	elif key == "sand":
		m.albedo_color = Color(0.62, 0.54, 0.40); m.metallic = 0.05; m.roughness = 0.65
	else:
		m.albedo_color = Color(0.12, 0.12, 0.13); m.metallic = 0.5; m.roughness = 0.5
	_mats[key] = m
	return m


static func _body_mat(scheme: String) -> StandardMaterial3D:
	if scheme == "gunmetal":
		return _mat("gunmetal")
	if scheme == "tan" or scheme == "sand":
		return _mat("tan")
	if scheme == "od":
		return _mat("od")
	if scheme == "grey":
		return _mat("grey")
	if scheme == "white":
		return _mat("white")
	if scheme == "bronze":
		return _mat("bronze")
	if scheme == "graphite":
		return _mat("graphite")
	if scheme == "bluegrey":
		return _mat("bluegrey")
	return _mat("black")


static func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
	return mi


static func _cyl(root: Node3D, radius: float, height: float, pos: Vector3, mat: Material, axis: Vector3, segs: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	var q := Quaternion(Vector3.UP, axis.normalized())
	mi.basis = Basis(q)
	mi.position = pos
	root.add_child(mi)
	return mi


## Sight-line height above gun origin (for ADS centering).
static func sight_height(gun_id: String) -> float:
	var g := GunDefs.by_id(gun_id)
	var s: String = (g["model"] as Dictionary).get("sight", "iron")
	if s == "scope" or s == "scopelong" or s == "thermal":
		return 0.095
	if s == "holo" or s == "acog":
		return 0.085
	if s == "reddot":
		return 0.080
	return 0.072


## Build the first-person viewmodel. Returns {root, muzzle, eject}.
static func build_viewmodel(gun_id: String) -> Dictionary:
	var g := GunDefs.by_id(gun_id)
	var root := Node3D.new()
	root.name = "Viewmodel_" + gun_id
	var spec: Dictionary = g["model"]
	var cls: String = g["cls"]
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	var eject := Node3D.new()
	eject.name = "Eject"
	if cls == "melee":
		_build_melee(root, spec)
		muzzle.position = Vector3(0, 0.0, -0.4)
	elif cls == "pistol":
		_build_pistol(root, spec)
		var bl: float = 0.12 + float(spec.get("barrel", 0.12))
		muzzle.position = Vector3(0, 0.03, -bl - 0.02)
	elif cls == "launcher":
		_build_launcher(root, spec)
		muzzle.position = Vector3(0, 0.03, -0.62)
	else:
		_build_long_gun(root, spec)
		var bl2: float = float(spec.get("barrel", 0.4))
		var extra := 0.10
		if str(spec.get("muzzle", "")) == "suppressor" or str(spec.get("muzzle", "")) == "shroud":
			extra = 0.24
		muzzle.position = Vector3(0, 0.02, 0.17 + bl2 + extra)
	root.add_child(muzzle)
	eject.position = Vector3(0.06, 0.03, -0.02)
	root.add_child(eject)
	return {"root": root, "muzzle": muzzle, "eject": eject}


## Simplified ground model for loot pickups.
static func build_world_model(gun_id: String) -> Node3D:
	var g := GunDefs.by_id(gun_id)
	var root := Node3D.new()
	root.name = "Worldmodel_" + gun_id
	var spec: Dictionary = g["model"]
	var cls: String = g["cls"]
	var body := _body_mat(str(spec.get("body", "black")))
	var dark := _mat("dark")
	var z := Vector3.ZERO
	if cls == "melee":
		_build_melee(root, spec)
	elif cls == "pistol":
		var pstyle: String = str(spec.get("style", "service"))
		if pstyle == "crossbow":
			_box(root, Vector3(0.05, 0.07, 0.30), z, body, z)
			_box(root, Vector3(0.34, 0.025, 0.05), Vector3(0, 0.02, -0.12), dark, z)
		elif pstyle == "revolver":
			_box(root, Vector3(0.045, 0.07, 0.16), z, body, z)
			_cyl(root, 0.035, 0.07, Vector3(0, 0.01, -0.02), dark, Vector3.FORWARD, 10)
			_cyl(root, 0.016, 0.16, Vector3(0, 0.02, -0.12), dark, Vector3.FORWARD, 8)
		elif pstyle == "nailgun":
			_box(root, Vector3(0.07, 0.10, 0.22), z, body, z)
			_box(root, Vector3(0.03, 0.03, 0.24), Vector3(0, 0.065, 0.0), dark, z)
		else:
			_box(root, Vector3(0.05, 0.07, 0.22), z, body, z)
			_box(root, Vector3(0.045, 0.14, 0.06), Vector3(0, -0.09, 0.05), body, Vector3(0.2, 0, 0))
			_box(root, Vector3(0.02, 0.02, 0.05), Vector3(0, 0.05, -0.08), dark, z)
	elif cls == "launcher":
		_cyl(root, 0.055, 0.9, z, body, Vector3.FORWARD, 10)
		if str(spec.get("style", "rpg")) == "rpg7":
			# Warhead cone at the front so the ground pickup reads as an RPG.
			var wc := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.012
			wm.bottom_radius = 0.075
			wm.height = 0.20
			wm.radial_segments = 10
			wc.mesh = wm
			wc.material_override = dark
			wc.basis = Basis(Quaternion(Vector3.UP, Vector3.FORWARD))
			wc.position = Vector3(0, 0, -0.55)
			root.add_child(wc)
		_box(root, Vector3(0.05, 0.12, 0.08), Vector3(0, -0.1, 0.1), _mat("wood"), z)
	else:
		var bl: float = float(spec.get("barrel", 0.4))
		_box(root, Vector3(0.07, 0.10, 0.38), z, body, z)
		_cyl(root, 0.022, bl, Vector3(0, 0.02, 0.19 + bl * 0.5), _mat("gunmetal"), Vector3.FORWARD, 8)
		_box(root, Vector3(0.08, 0.09, 0.26), Vector3(0, 0.01, 0.28), body, z)
		_mag_world(root, spec, body)
		_box(root, Vector3(0.06, 0.12, 0.26), Vector3(0, -0.01, -0.32), body, z)
		var sight: String = str(spec.get("sight", "iron"))
		if sight == "scope" or sight == "scopelong":
			_cyl(root, 0.035, 0.24, Vector3(0, 0.10, -0.02), dark, Vector3.FORWARD, 8)
	root.rotation = Vector3(0, 0.6, 0)
	return root


static func _mag_world(root: Node3D, spec: Dictionary, body: Material) -> void:
	var kind: String = str(spec.get("mag", "straight"))
	var z := Vector3.ZERO
	if kind == "drum":
		_cyl(root, 0.10, 0.06, Vector3(0, -0.14, 0.06), body, Vector3.RIGHT, 10)
	elif kind == "box" or kind == "belt":
		_box(root, Vector3(0.13, 0.15, 0.17), Vector3(-0.1, -0.12, 0.02), body, z)
	elif kind == "pan":
		_cyl(root, 0.11, 0.045, Vector3(0, 0.10, 0.05), body, Vector3.UP, 10)
	elif kind == "helix" or kind == "helixunder":
		_cyl(root, 0.038, 0.30, Vector3(0, -0.06, 0.12), body, Vector3.FORWARD, 8)
	elif kind == "tube":
		_cyl(root, 0.028, 0.34, Vector3(0, -0.045, 0.32), _mat("gunmetal"), Vector3.FORWARD, 8)
	elif kind == "none" or kind == "internal":
		pass
	else:
		_box(root, Vector3(0.05, 0.2, 0.09), Vector3(0, -0.16, 0.06), body, Vector3(-0.15, 0, 0))


# ------------------------------------------------------------------ long guns
## Detailed viewmodel for ar / smg / lmg / sniper / marksman / shotgun.
static func _build_long_gun(root: Node3D, spec: Dictionary) -> void:
	var z := Vector3.ZERO
	var body := _body_mat(str(spec.get("body", "black")))
	var dark := _mat("dark")
	var steel := _mat("steel")
	var gunmetal := _mat("gunmetal")
	var wood := _mat("wood") if str(spec.get("accent", "none")) == "wood" else body
	var style: String = str(spec.get("style", "modular"))
	var bl: float = float(spec.get("barrel", 0.4))
	# --- receiver (style-shaped) ---
	var rl := 0.36
	var recv: String = str(spec.get("receiver", "std"))
	if style == "bullpup":
		rl = 0.46
		_box(root, Vector3(0.075, 0.105, rl), Vector3(0, 0.0, 0.02), body, z)
		_box(root, Vector3(0.06, 0.05, 0.10), Vector3(0, -0.075, -0.14), _mat("black"), z)  # buttpad
	elif style == "machine" or style == "rapid":
		_box(root, Vector3(0.06, 0.085, 0.30), Vector3(0, 0.0, 0.0), body, z)
		rl = 0.30
	elif recv == "slim":
		_box(root, Vector3(0.055, 0.08, rl), Vector3(0, 0.0, 0.0), body, z)
	elif recv == "boxy":
		_box(root, Vector3(0.085, 0.115, rl), Vector3(0, 0.005, 0.0), body, z)
	elif recv == "angular":
		_box(root, Vector3(0.07, 0.095, rl), Vector3(0, 0.0, 0.0), body, z)
		_box(root, Vector3(0.05, 0.06, rl * 0.5), Vector3(0, 0.03, rl * 0.2), body, Vector3(0.3, 0, 0))
	elif recv == "tube":
		_cyl(root, 0.042, rl, Vector3(0, 0.0, 0.0), body, Vector3.FORWARD, 10)
	else:
		_box(root, Vector3(0.068, 0.095, rl), Vector3(0, 0.0, 0.0), body, z)
	# top rail (skippable for sporter/vintage hunting looks)
	if bool(spec.get("toprail", true)):
		_box(root, Vector3(0.03, 0.012, rl * 0.8), Vector3(0, 0.054, 0.02), dark, z)
	# carry handle (retro)
	if bool(spec.get("carry_handle", false)):
		_box(root, Vector3(0.025, 0.05, 0.20), Vector3(0, 0.085, -0.02), body, z)
		_box(root, Vector3(0.025, 0.012, 0.16), Vector3(0, 0.115, -0.02), body, z)
	# revolving cylinder (Outlaw-style bolt sniper)
	if bool(spec.get("cylinder", false)):
		_cyl(root, 0.045, 0.10, Vector3(0, 0.0, -0.10), steel, Vector3.FORWARD, 12)
		for i in range(6):
			var a := float(i) * TAU / 6.0
			_box(root, Vector3(0.016, 0.016, 0.10),
				Vector3(cos(a) * 0.032, sin(a) * 0.032, -0.10), dark, z)
	# lever loop (lever-action)
	if bool(spec.get("lever", false)):
		_box(root, Vector3(0.012, 0.09, 0.05), Vector3(0, -0.13, -0.02), steel, z)
		_box(root, Vector3(0.012, 0.012, 0.09), Vector3(0, -0.175, -0.04), steel, z)
	# glowing accent (exotic guns: NA-45 primer ring etc.)
	var glow: String = str(spec.get("glow", "none"))
	if glow != "none":
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if glow == "amber":
			gm.albedo_color = Color(1.0, 0.7, 0.15)
		elif glow == "cyan":
			gm.albedo_color = Color(0.2, 0.9, 1.0)
		elif glow == "red":
			gm.albedo_color = Color(1.0, 0.2, 0.15)
		else:
			gm.albedo_color = Color(0.5, 1.0, 0.3)
		_box(root, Vector3(0.072, 0.02, 0.06), Vector3(0, 0.0, 0.10), gm, z)
	# ejection port (right side)
	_box(root, Vector3(0.005, 0.035, 0.09), Vector3(0.036, 0.012, 0.03), dark, z)
	# charging handle (rear top)
	_box(root, Vector3(0.05, 0.015, 0.03), Vector3(0, 0.055, -rl * 0.5 + 0.02), steel, z)
	# --- barrel + handguard ---
	var bstart := rl * 0.5
	if bool(spec.get("twinbarrel", false)):
		_cyl(root, 0.021, bl, Vector3(-0.035, 0.02, bstart + bl * 0.5), gunmetal, Vector3.FORWARD, 10)
		_cyl(root, 0.021, bl, Vector3(0.035, 0.02, bstart + bl * 0.5), gunmetal, Vector3.FORWARD, 10)
	else:
		_cyl(root, 0.021, bl, Vector3(0, 0.02, bstart + bl * 0.5), gunmetal, Vector3.FORWARD, 10)
	var hg_len: float = minf(bl * 0.55, 0.30)
	if style == "heavy" or style == "belt":
		hg_len = minf(bl * 0.6, 0.34)
	var hg_mat: Material = wood if str(spec.get("accent", "none")) == "wood" and (style == "piston" or style == "classic") else body
	_box(root, Vector3(0.075, 0.085, hg_len), Vector3(0, 0.015, bstart + hg_len * 0.5 + 0.02), hg_mat, z)
	# heatshield vents on some
	if _has_extra(spec, "heatshield"):
		for i in range(3):
			_box(root, Vector3(0.078, 0.012, 0.03), Vector3(0, 0.05, bstart + 0.08 + float(i) * 0.06), dark, z)
	# --- muzzle device ---
	_muzzle_device(root, spec, Vector3(0, 0.02, bstart + bl))
	# --- magazine ---
	_mag_detail(root, spec, body)
	# --- stock ---
	_stock_detail(root, spec, body, rl)
	# --- grip + trigger ---
	_box(root, Vector3(0.045, 0.13, 0.055), Vector3(0, -0.10, -0.07), _mat("black"), Vector3(0.35, 0, 0))
	_box(root, Vector3(0.012, 0.05, 0.02), Vector3(0, -0.075, -0.015), steel, Vector3(0.2, 0, 0))  # trigger
	_box(root, Vector3(0.05, 0.012, 0.11), Vector3(0, -0.105, -0.03), dark, z)  # trigger guard
	# --- sights / optic ---
	_sight_detail(root, spec, dark, steel)
	# --- extras ---
	var ex: Array = spec.get("extras", [])
	if ex.has("foregrip"):
		_box(root, Vector3(0.04, 0.11, 0.045), Vector3(0, -0.07, bstart + hg_len * 0.6), _mat("black"), Vector3(0.15, 0, 0))
	if ex.has("bipod"):
		_box(root, Vector3(0.015, 0.16, 0.015), Vector3(-0.05, -0.10, bstart + bl * 0.8), steel, Vector3(0, 0, 0.25))
		_box(root, Vector3(0.015, 0.16, 0.015), Vector3(0.05, -0.10, bstart + bl * 0.8), steel, Vector3(0, 0, -0.25))
	if ex.has("laser"):
		_box(root, Vector3(0.03, 0.03, 0.07), Vector3(0.05, 0.02, bstart + 0.10), dark, z)
	if ex.has("bayonet"):
		_box(root, Vector3(0.012, 0.03, 0.24), Vector3(0, -0.02, bstart + bl + 0.10), steel, z)
	if ex.has("carry"):
		_box(root, Vector3(0.025, 0.05, 0.24), Vector3(0, 0.085, -0.02), body, z)


static func _has_extra(spec: Dictionary, name: String) -> bool:
	var ex: Array = spec.get("extras", [])
	return ex.has(name)


static func _muzzle_device(root: Node3D, spec: Dictionary, tip: Vector3) -> void:
	var kind: String = str(spec.get("muzzle", "flash"))
	var z := Vector3.ZERO
	var gunmetal := _mat("gunmetal")
	var dark := _mat("dark")
	if kind == "suppressor":
		_cyl(root, 0.034, 0.20, tip + Vector3(0, 0, 0.10), dark, Vector3.FORWARD, 12)
		_cyl(root, 0.036, 0.03, tip + Vector3(0, 0, 0.02), gunmetal, Vector3.FORWARD, 12)
	elif kind == "comp":
		_box(root, Vector3(0.05, 0.05, 0.09), tip + Vector3(0, 0, 0.045), gunmetal, z)
		_box(root, Vector3(0.054, 0.02, 0.06), tip + Vector3(0, 0.01, 0.045), dark, z)
	elif kind == "brake":
		_box(root, Vector3(0.062, 0.062, 0.11), tip + Vector3(0, 0, 0.055), gunmetal, z)
		for i in range(2):
			_box(root, Vector3(0.066, 0.02, 0.03), tip + Vector3(0, 0.015, 0.03 + float(i) * 0.05), dark, z)
	elif kind == "linear":
		# Long linear compensator.
		_cyl(root, 0.032, 0.13, tip + Vector3(0, 0, 0.065), gunmetal, Vector3.FORWARD, 10)
		_cyl(root, 0.034, 0.02, tip + Vector3(0, 0, 0.01), dark, Vector3.FORWARD, 10)
	elif kind == "shroud":
		# Perforated barrel shroud (integrated-suppressor look).
		_cyl(root, 0.038, 0.22, tip + Vector3(0, 0, 0.11), dark, Vector3.FORWARD, 12)
		for i in range(3):
			_cyl(root, 0.040, 0.015, tip + Vector3(0, 0, 0.05 + float(i) * 0.06), gunmetal, Vector3.FORWARD, 12)
	elif kind == "none":
		pass
	else:  # flash hider: prongs
		_cyl(root, 0.026, 0.07, tip + Vector3(0, 0, 0.035), gunmetal, Vector3.FORWARD, 8)
		for i in range(3):
			var a := float(i) * TAU / 3.0
			_box(root, Vector3(0.012, 0.012, 0.05),
				tip + Vector3(cos(a) * 0.022, sin(a) * 0.022, 0.085), gunmetal, z)


static func _mag_detail(root: Node3D, spec: Dictionary, body: Material) -> void:
	var kind: String = str(spec.get("mag", "straight"))
	var z := Vector3.ZERO
	var dark := _mat("dark")
	if kind == "curved":
		_box(root, Vector3(0.052, 0.24, 0.095), Vector3(0, -0.16, 0.07), body, Vector3(-0.28, 0, 0))
		_box(root, Vector3(0.056, 0.03, 0.10), Vector3(0, -0.27, 0.10), dark, Vector3(-0.28, 0, 0))
	elif kind == "drum":
		_cyl(root, 0.095, 0.06, Vector3(0, -0.14, 0.06), body, Vector3.RIGHT, 14)
		_cyl(root, 0.03, 0.065, Vector3(0, -0.14, 0.06), dark, Vector3.RIGHT, 10)
	elif kind == "box":
		_box(root, Vector3(0.13, 0.16, 0.18), Vector3(-0.10, -0.13, 0.02), body, z)
		_box(root, Vector3(0.02, 0.05, 0.10), Vector3(-0.035, -0.06, 0.02), dark, z)  # feed tray
	elif kind == "tube":
		_cyl(root, 0.028, 0.36, Vector3(0, -0.048, 0.34), _mat("gunmetal"), Vector3.FORWARD, 10)
		_box(root, Vector3(0.05, 0.03, 0.06), Vector3(0, -0.048, 0.18), dark, z)  # pump
	elif kind == "stick":
		_box(root, Vector3(0.045, 0.17, 0.07), Vector3(0, -0.13, 0.05), body, Vector3(0.1, 0, 0))
	elif kind == "helix":
		# Helical top-mounted magazine (high-capacity, distinctive cylinder on top).
		_cyl(root, 0.038, 0.30, Vector3(0, 0.085, 0.02), body, Vector3.FORWARD, 10)
		_box(root, Vector3(0.03, 0.05, 0.06), Vector3(0, 0.03, 0.02), dark, z)
	elif kind == "helixunder":
		# Helical tube slung UNDER the barrel (Bizon-style).
		_cyl(root, 0.035, 0.34, Vector3(0, -0.062, 0.22), body, Vector3.FORWARD, 10)
		_box(root, Vector3(0.03, 0.05, 0.06), Vector3(0, -0.02, 0.06), dark, z)
	elif kind == "pan":
		# Flat pan magazine on top (WW-era LMG look).
		_cyl(root, 0.115, 0.045, Vector3(0, 0.10, 0.05), body, Vector3.UP, 14)
		_cyl(root, 0.03, 0.05, Vector3(0, 0.10, 0.05), dark, Vector3.UP, 10)
	elif kind == "belt":
		# Ammo belt draped into a side box.
		_box(root, Vector3(0.11, 0.13, 0.15), Vector3(-0.09, -0.11, 0.03), body, z)
		for i in range(4):
			_box(root, Vector3(0.02, 0.025, 0.05), Vector3(-0.03, -0.05 - float(i) * 0.008, 0.03), _mat("brass"), Vector3(0, 0, 0.5))
	elif kind == "casket":
		# Wide quad-stack magazine.
		_box(root, Vector3(0.085, 0.19, 0.10), Vector3(0, -0.14, 0.06), body, Vector3(-0.08, 0, 0))
		_box(root, Vector3(0.089, 0.03, 0.104), Vector3(0, -0.225, 0.075), dark, Vector3(-0.08, 0, 0))
	elif kind == "saddle":
		# Twin side-saddle tubes (shotgun).
		_cyl(root, 0.026, 0.30, Vector3(-0.045, -0.05, 0.30), _mat("gunmetal"), Vector3.FORWARD, 8)
		_cyl(root, 0.026, 0.30, Vector3(0.045, -0.05, 0.30), _mat("gunmetal"), Vector3.FORWARD, 8)
	elif kind == "internal" or kind == "none":
		pass
	else:  # straight
		_box(root, Vector3(0.048, 0.21, 0.085), Vector3(0, -0.15, 0.06), body, Vector3(-0.06, 0, 0))


static func _stock_detail(root: Node3D, spec: Dictionary, body: Material, rl: float) -> void:
	var kind: String = str(spec.get("stock", "fixed"))
	var z := Vector3.ZERO
	var rear := -rl * 0.5
	if kind == "bullpup" or kind == "none":
		_box(root, Vector3(0.06, 0.10, 0.06), Vector3(0, -0.01, rear - 0.02), _mat("black"), z)
	elif kind == "folding":
		_box(root, Vector3(0.045, 0.09, 0.22), Vector3(0.01, -0.01, rear - 0.11), body, Vector3(0, 0.06, 0))
		_box(root, Vector3(0.05, 0.11, 0.04), Vector3(0.01, -0.01, rear - 0.23), _mat("black"), z)
	elif kind == "skeleton":
		_box(root, Vector3(0.02, 0.03, 0.24), Vector3(-0.025, 0.02, rear - 0.12), body, z)
		_box(root, Vector3(0.02, 0.03, 0.24), Vector3(0.025, 0.02, rear - 0.12), body, z)
		_box(root, Vector3(0.07, 0.12, 0.04), Vector3(0, -0.01, rear - 0.25), _mat("black"), z)
	elif kind == "wire":
		_cyl(root, 0.011, 0.24, Vector3(-0.025, 0.0, rear - 0.12), _mat("steel"), Vector3.BACK, 8)
		_cyl(root, 0.011, 0.24, Vector3(0.025, 0.0, rear - 0.12), _mat("steel"), Vector3.BACK, 8)
		_box(root, Vector3(0.07, 0.10, 0.035), Vector3(0, -0.01, rear - 0.25), _mat("black"), z)
	elif kind == "brace":
		# Pistol brace: short + strap loop.
		_box(root, Vector3(0.05, 0.09, 0.14), Vector3(0, -0.01, rear - 0.07), body, z)
		_box(root, Vector3(0.055, 0.05, 0.05), Vector3(0, -0.01, rear - 0.16), _mat("black"), z)
	elif kind == "pdw":
		# Compact PDW sliding stock.
		_box(root, Vector3(0.04, 0.07, 0.16), Vector3(0, 0.0, rear - 0.08), body, z)
		_box(root, Vector3(0.055, 0.10, 0.03), Vector3(0, -0.01, rear - 0.17), _mat("black"), z)
	elif kind == "thumbhole":
		# Sniper thumbhole stock: solid with grip hole illusion.
		_box(root, Vector3(0.06, 0.13, 0.30), Vector3(0, -0.02, rear - 0.15), body, z)
		_box(root, Vector3(0.062, 0.05, 0.10), Vector3(0, -0.03, rear - 0.12), _mat("dark"), z)
		_box(root, Vector3(0.065, 0.13, 0.04), Vector3(0, -0.02, rear - 0.31), _mat("black"), z)
	elif kind == "chassis":
		# Precision chassis: angular + adjustable cheek + monopod rail.
		_box(root, Vector3(0.055, 0.09, 0.24), Vector3(0, 0.01, rear - 0.12), _mat("graphite"), Vector3(0, 0, 0))
		_box(root, Vector3(0.06, 0.04, 0.12), Vector3(0, 0.06, rear - 0.10), _mat("black"), z)
		_box(root, Vector3(0.06, 0.12, 0.04), Vector3(0, -0.01, rear - 0.26), _mat("black"), z)
	else:  # fixed
		_box(root, Vector3(0.055, 0.115, 0.26), Vector3(0, -0.015, rear - 0.13), body, z)
		_box(root, Vector3(0.06, 0.125, 0.035), Vector3(0, -0.015, rear - 0.27), _mat("black"), z)


static func _sight_detail(root: Node3D, spec: Dictionary, dark: Material, steel: Material) -> void:
	var kind: String = str(spec.get("sight", "iron"))
	var z := Vector3.ZERO
	var glass := _mat("glass")
	if kind == "iron":
		_box(root, Vector3(0.012, 0.035, 0.012), Vector3(-0.018, 0.075, -0.13), dark, z)
		_box(root, Vector3(0.012, 0.035, 0.012), Vector3(0.018, 0.075, -0.13), dark, z)
		_box(root, Vector3(0.05, 0.012, 0.02), Vector3(0, 0.06, -0.13), dark, z)
		_box(root, Vector3(0.01, 0.03, 0.01), Vector3(0, 0.075, 0.16), dark, z)  # front post
	elif kind == "reddot":
		_box(root, Vector3(0.05, 0.055, 0.09), Vector3(0, 0.085, -0.05), dark, z)
		_cyl(root, 0.02, 0.012, Vector3(0, 0.085, -0.095), glass, Vector3.BACK, 10)
		_box(root, Vector3(0.03, 0.03, 0.02), Vector3(0, 0.06, -0.05), dark, z)
	elif kind == "holo":
		_box(root, Vector3(0.06, 0.07, 0.11), Vector3(0, 0.09, -0.05), dark, z)
		_box(root, Vector3(0.045, 0.045, 0.005), Vector3(0, 0.09, -0.108), glass, z)
		_box(root, Vector3(0.03, 0.035, 0.02), Vector3(0, 0.06, -0.05), dark, z)
	elif kind == "scope" or kind == "scopelong":
		var sl := 0.30 if kind == "scopelong" else 0.22
		_cyl(root, 0.032, sl, Vector3(0, 0.095, -0.03), dark, Vector3.FORWARD, 12)
		_cyl(root, 0.036, 0.05, Vector3(0, 0.095, -0.03 - sl * 0.5), dark, Vector3.FORWARD, 12)
		_cyl(root, 0.028, 0.006, Vector3(0, 0.095, -0.03 - sl * 0.5 - 0.028), glass, Vector3.FORWARD, 12)
		_box(root, Vector3(0.025, 0.035, 0.03), Vector3(0, 0.068, -0.10), steel, z)
		_box(root, Vector3(0.025, 0.035, 0.03), Vector3(0, 0.068, 0.04), steel, z)
		_cyl(root, 0.012, 0.02, Vector3(0.04, 0.095, -0.03), steel, Vector3.RIGHT, 8)  # turret
	elif kind == "thermal":
		# Boxy thermal optic.
		_box(root, Vector3(0.065, 0.075, 0.16), Vector3(0, 0.095, -0.04), dark, z)
		_box(root, Vector3(0.05, 0.05, 0.01), Vector3(0, 0.095, -0.125), glass, z)
		_box(root, Vector3(0.03, 0.04, 0.03), Vector3(0, 0.062, -0.04), steel, z)
	elif kind == "acog":
		# Prism scope with fiber optic.
		_box(root, Vector3(0.045, 0.06, 0.14), Vector3(0, 0.09, -0.04), dark, z)
		_cyl(root, 0.026, 0.02, Vector3(0, 0.09, -0.115), glass, Vector3.FORWARD, 10)
		_box(root, Vector3(0.012, 0.02, 0.06), Vector3(0, 0.125, -0.04), steel, z)
		_box(root, Vector3(0.03, 0.035, 0.03), Vector3(0, 0.062, -0.04), steel, z)


# -------------------------------------------------------------------- pistols
static func _build_pistol(root: Node3D, spec: Dictionary) -> void:
	var z := Vector3.ZERO
	var body := _body_mat(str(spec.get("body", "black")))
	var dark := _mat("dark")
	var steel := _mat("steel")
	var gunmetal := _mat("gunmetal")
	var style: String = str(spec.get("style", "service"))
	var sl := 0.20  # slide length
	if style == "machine":
		sl = 0.24
	# slide
	_box(root, Vector3(0.052, 0.062, sl), Vector3(0, 0.03, -sl * 0.5 + 0.03), gunmetal, z)
	# slide serrations
	for i in range(3):
		_box(root, Vector3(0.056, 0.02, 0.012), Vector3(0, 0.03, 0.0 - float(i) * 0.025), dark, z)
	# frame
	_box(root, Vector3(0.046, 0.035, sl * 0.9), Vector3(0, -0.008, -sl * 0.5 + 0.03), body, z)
	# grip (angled)
	_box(root, Vector3(0.048, 0.15, 0.062), Vector3(0, -0.095, 0.055), body, Vector3(0.28, 0, 0))
	# trigger + guard
	_box(root, Vector3(0.012, 0.035, 0.018), Vector3(0, -0.045, -0.02), steel, Vector3(0.2, 0, 0))
	_box(root, Vector3(0.05, 0.01, 0.09), Vector3(0, -0.068, -0.015), dark, z)
	# sights
	_box(root, Vector3(0.01, 0.022, 0.01), Vector3(0, 0.07, -sl + 0.02), dark, z)
	_box(root, Vector3(0.03, 0.02, 0.012), Vector3(0, 0.068, 0.01), dark, z)
	# muzzle device
	var mz: String = str(spec.get("muzzle", "none"))
	var tip := Vector3(0, 0.03, -sl + 0.03)
	if mz == "suppressor":
		_cyl(root, 0.028, 0.16, tip + Vector3(0, 0, -0.08), dark, Vector3.FORWARD, 10)
	elif mz == "comp":
		_box(root, Vector3(0.055, 0.05, 0.05), tip + Vector3(0, 0, -0.025), gunmetal, z)
	elif mz == "brake":
		_box(root, Vector3(0.06, 0.065, 0.06), tip + Vector3(0, 0, -0.03), gunmetal, z)
	if style == "machine":
		# wire stock + extended mag
		_cyl(root, 0.009, 0.20, Vector3(-0.02, -0.02, 0.14), steel, Vector3.BACK, 6)
		_cyl(root, 0.009, 0.20, Vector3(0.02, -0.02, 0.14), steel, Vector3.BACK, 6)
		_box(root, Vector3(0.05, 0.09, 0.03), Vector3(0, -0.02, 0.25), _mat("black"), z)
		_box(root, Vector3(0.045, 0.20, 0.06), Vector3(0, -0.13, 0.055), body, Vector3(0.28, 0, 0))
	if style == "heavy":
		_box(root, Vector3(0.058, 0.07, sl), Vector3(0, 0.03, -sl * 0.5 + 0.03), body, z)  # fat slide
	if style == "revolver":
		# Revolver: frame + swing-out cylinder + long vent-rib barrel + hammer.
		_box(root, Vector3(0.045, 0.07, 0.16), Vector3(0, 0.01, 0.02), body, z)  # frame
		_cyl(root, 0.035, 0.07, Vector3(0, 0.02, -0.03), steel, Vector3.FORWARD, 12)  # cylinder
		for i in range(6):
			var a := float(i) * TAU / 6.0
			_box(root, Vector3(0.012, 0.012, 0.072),
				Vector3(cos(a) * 0.024, 0.02 + sin(a) * 0.024, -0.03), dark, z)
		_cyl(root, 0.016, 0.16, Vector3(0, 0.035, -0.14), gunmetal, Vector3.FORWARD, 8)  # barrel
		_box(root, Vector3(0.014, 0.02, 0.16), Vector3(0, 0.055, -0.14), dark, z)  # vent rib
		_box(root, Vector3(0.02, 0.05, 0.03), Vector3(0, 0.05, 0.10), steel, Vector3(-0.5, 0, 0))  # hammer
		_box(root, Vector3(0.05, 0.13, 0.07), Vector3(0, -0.09, 0.06), _mat("wood"), Vector3(0.25, 0, 0))  # wood grips
	if style == "burst":
		# Burst pistol: long slide, extended mag, selector switch.
		_box(root, Vector3(0.05, 0.06, 0.09), Vector3(0, -0.16, 0.055), body, Vector3(0.28, 0, 0))  # ext mag
		_box(root, Vector3(0.014, 0.014, 0.03), Vector3(0.032, 0.0, 0.03), steel, z)  # selector
	if style == "shorty":
		# Sawed-off double-barrel shotgun pistol: stubby twin barrels, break action.
		_cyl(root, 0.024, 0.16, Vector3(-0.02, 0.03, -0.10), gunmetal, Vector3.FORWARD, 8)
		_cyl(root, 0.024, 0.16, Vector3(0.02, 0.03, -0.10), gunmetal, Vector3.FORWARD, 8)
		_box(root, Vector3(0.06, 0.05, 0.10), Vector3(0, 0.0, 0.0), body, z)  # breech
		_box(root, Vector3(0.055, 0.06, 0.09), Vector3(0, -0.01, -0.06), _mat("wood"), z)  # wood forend
		_box(root, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.09, 0.05), _mat("wood"), Vector3(0.3, 0, 0))
	if style == "crossbow":
		# Compact crossbow: body + horizontal limbs + string + bolt + small scope.
		_box(root, Vector3(0.05, 0.07, 0.30), Vector3(0, 0.0, -0.05), body, z)
		_box(root, Vector3(0.34, 0.025, 0.05), Vector3(0, 0.02, -0.16), dark, z)  # limbs
		_box(root, Vector3(0.30, 0.006, 0.006), Vector3(0, 0.02, -0.13), steel, z)  # string
		_cyl(root, 0.008, 0.24, Vector3(0, 0.045, -0.12), _mat("wood"), Vector3.FORWARD, 6)  # bolt
		_box(root, Vector3(0.04, 0.05, 0.10), Vector3(0, 0.085, -0.02), dark, z)  # scope
		_box(root, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.09, 0.06), body, Vector3(0.3, 0, 0))
	if style == "fullauto":
		# Full-auto machine pistol: extended mag + foregrip nub.
		_box(root, Vector3(0.05, 0.09, 0.09), Vector3(0, -0.17, 0.055), body, Vector3(0.28, 0, 0))
		_box(root, Vector3(0.035, 0.06, 0.04), Vector3(0, -0.06, -0.10), _mat("black"), z)
	if style == "nailgun":
		# Industrial nail gun: boxy body, top nail strip, thick nosepiece.
		_box(root, Vector3(0.07, 0.10, 0.22), Vector3(0, 0.03, -0.04), _mat("graphite"), z)
		_box(root, Vector3(0.03, 0.03, 0.24), Vector3(0, 0.095, -0.04), steel, z)  # nail strip
		_cyl(root, 0.025, 0.10, Vector3(0, 0.03, -0.20), dark, Vector3.FORWARD, 8)  # nosepiece
		_box(root, Vector3(0.05, 0.13, 0.07), Vector3(0, -0.09, 0.05), _mat("black"), Vector3(0.25, 0, 0))


# --------------------------------------------------------------------- melee
static func _build_melee(root: Node3D, spec: Dictionary) -> void:
	var z := Vector3.ZERO
	var style: String = str(spec.get("style", "knife"))
	var steel := _mat("steel")
	var dark := _mat("dark")
	if style == "knife":
		_box(root, Vector3(0.035, 0.045, 0.13), Vector3(0, -0.02, 0.10), dark, z)          # handle
		_box(root, Vector3(0.045, 0.012, 0.02), Vector3(0, -0.02, 0.03), steel, z)         # guard
		_box(root, Vector3(0.028, 0.012, 0.24), Vector3(0, -0.02, -0.10), steel, z)        # blade
		_box(root, Vector3(0.020, 0.010, 0.10), Vector3(0, -0.02, -0.26), steel, z)        # tip taper
	elif style == "axe":
		_box(root, Vector3(0.04, 0.045, 0.55), Vector3(0, -0.02, -0.10), _mat("wood"), z)  # haft
		_box(root, Vector3(0.03, 0.16, 0.22), Vector3(0, 0.03, -0.36), steel, z)           # head
		_box(root, Vector3(0.032, 0.06, 0.06), Vector3(0, 0.03, -0.24), dark, z)          # poll
	else:  # katana
		_box(root, Vector3(0.032, 0.04, 0.28), Vector3(0, -0.02, 0.16), dark, z)          # tsuka
		_cyl(root, 0.045, 0.012, Vector3(0, -0.02, 0.015), _mat("brass"), Vector3.FORWARD, 10)  # tsuba
		_box(root, Vector3(0.024, 0.008, 0.55), Vector3(0, -0.015, -0.28), steel, z)      # blade
		_box(root, Vector3(0.018, 0.007, 0.18), Vector3(0, -0.012, -0.62), steel, z)      # tip
	if style == "bat":
		# Baseball bat: tapered barrel to thin handle with knob.
		_cyl(root, 0.035, 0.42, Vector3(0, -0.02, -0.18), _mat("wood"), Vector3.FORWARD, 10)
		_cyl(root, 0.016, 0.20, Vector3(0, -0.02, 0.10), _mat("wood"), Vector3.FORWARD, 8)
		_cyl(root, 0.028, 0.03, Vector3(0, -0.02, 0.21), _mat("wood"), Vector3.FORWARD, 8)
	if style == "shovel":
		# Entrenching tool: handle + flat spade blade.
		_cyl(root, 0.018, 0.45, Vector3(0, -0.02, 0.05), _mat("wood"), Vector3.FORWARD, 8)
		_box(root, Vector3(0.16, 0.015, 0.24), Vector3(0, -0.02, -0.28), steel, z)
		_box(root, Vector3(0.05, 0.05, 0.08), Vector3(0, -0.02, 0.28), dark, z)
	if style == "machete":
		# Broad heavy blade with clip point.
		_box(root, Vector3(0.035, 0.045, 0.14), Vector3(0, -0.02, 0.12), dark, z)
		_box(root, Vector3(0.075, 0.012, 0.42), Vector3(0, -0.015, -0.16), steel, z)
		_box(root, Vector3(0.05, 0.010, 0.10), Vector3(0, -0.012, -0.40), steel, Vector3(0, 0, 0.2))
	if style == "fists":
		# Prizefighters: dual weighted gauntlets (shown as one chunky fist pair).
		_box(root, Vector3(0.09, 0.09, 0.12), Vector3(-0.05, -0.02, -0.10), dark, z)
		_box(root, Vector3(0.09, 0.09, 0.12), Vector3(0.05, -0.02, -0.10), dark, z)
		_box(root, Vector3(0.095, 0.03, 0.125), Vector3(-0.05, 0.03, -0.10), steel, z)
		_box(root, Vector3(0.095, 0.03, 0.125), Vector3(0.05, 0.03, -0.10), steel, z)
	if style == "sticks":
		# Kali sticks: pair of rattan batons.
		_cyl(root, 0.016, 0.55, Vector3(-0.04, -0.02, -0.15), _mat("wood"), Vector3.FORWARD, 8)
		_cyl(root, 0.016, 0.55, Vector3(0.04, -0.02, -0.15), _mat("wood"), Vector3.FORWARD, 8)
	if style == "sai":
		# Sai: central spike + two side prongs, one per hand (shown pair).
		for sx in [-0.045, 0.045]:
			_box(root, Vector3(0.014, 0.014, 0.22), Vector3(sx, -0.02, -0.12), steel, z)
			_box(root, Vector3(0.010, 0.010, 0.10), Vector3(sx - 0.025, -0.02, -0.06), steel, z)
			_box(root, Vector3(0.010, 0.010, 0.10), Vector3(sx + 0.025, -0.02, -0.06), steel, z)
			_box(root, Vector3(0.03, 0.035, 0.10), Vector3(sx, -0.02, 0.04), dark, z)
	if style == "wrench":
		# Heavy wrench: handle + open jaw head.
		_box(root, Vector3(0.03, 0.025, 0.40), Vector3(0, -0.02, 0.02), steel, z)
		_box(root, Vector3(0.09, 0.03, 0.10), Vector3(0, -0.02, -0.22), steel, z)
		_box(root, Vector3(0.035, 0.032, 0.05), Vector3(-0.028, -0.02, -0.27), steel, z)
		_box(root, Vector3(0.035, 0.032, 0.05), Vector3(0.028, -0.02, -0.27), steel, z)


# ----------------------------------------------------------------- launchers
static func _build_launcher(root: Node3D, spec: Dictionary) -> void:
	var z := Vector3.ZERO
	var style: String = str(spec.get("style", "rpg"))
	var body := _body_mat(str(spec.get("body", "black")))
	var dark := _mat("dark")
	var steel := _mat("steel")
	if style == "rpg":
		# main tube
		_cyl(root, 0.055, 0.95, Vector3(0, 0.03, -0.10), body, Vector3.FORWARD, 12)
		# warhead cone (front)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.055
		cm.height = 0.22
		cm.radial_segments = 12
		cone.mesh = cm
		cone.material_override = dark
		cone.basis = Basis(Quaternion(Vector3.UP, Vector3.FORWARD))
		cone.position = Vector3(0, 0.03, -0.68)
		root.add_child(cone)
		# rear nozzle
		_cyl(root, 0.075, 0.12, Vector3(0, 0.03, 0.42), dark, Vector3.FORWARD, 12)
		# wood grip + trigger
		_box(root, Vector3(0.05, 0.13, 0.06), Vector3(0, -0.09, -0.05), _mat("wood"), Vector3(0.3, 0, 0))
		_box(root, Vector3(0.012, 0.04, 0.02), Vector3(0, -0.06, -0.10), steel, z)
		# iron sight
		_box(root, Vector3(0.01, 0.05, 0.01), Vector3(0, 0.10, -0.30), dark, z)
		_box(root, Vector3(0.03, 0.03, 0.01), Vector3(0, 0.115, -0.30), dark, z)
	else:  # glauncher: chunky revolver-style GL
		_box(root, Vector3(0.075, 0.11, 0.34), Vector3(0, 0.0, 0.0), body, z)             # receiver
		_cyl(root, 0.035, 0.34, Vector3(0, 0.02, -0.32), _mat("gunmetal"), Vector3.FORWARD, 10)  # barrel
		_cyl(root, 0.075, 0.14, Vector3(0, -0.01, -0.05), dark, Vector3.FORWARD, 12)      # cylinder drum
		_box(root, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.10, 0.10), _mat("wood"), Vector3(0.3, 0, 0))  # grip
		_box(root, Vector3(0.055, 0.11, 0.22), Vector3(0, -0.01, 0.28), body, z)         # stock
		_box(root, Vector3(0.012, 0.04, 0.012), Vector3(0, 0.075, -0.44), dark, z)        # front sight
	if style == "rpg7":
		# NOVA RP-7 "Thunderhead": classic RPG language, original design.
		# Long launch tube + flared venturi + front-loaded finned warhead.
		_cyl(root, 0.055, 1.05, Vector3(0, 0.03, -0.08), body, Vector3.FORWARD, 12)  # tube
		var vent := MeshInstance3D.new()
		var vm := CylinderMesh.new()
		vm.top_radius = 0.055
		vm.bottom_radius = 0.09
		vm.height = 0.18
		vm.radial_segments = 12
		vent.mesh = vm
		vent.material_override = dark
		vent.basis = Basis(Quaternion(Vector3.UP, Vector3.FORWARD))
		vent.position = Vector3(0, 0.03, 0.50)
		root.add_child(vent)  # rear venturi flare
		_cyl(root, 0.065, 0.12, Vector3(0, 0.03, -0.66), dark, Vector3.FORWARD, 12)  # booster
		_cyl(root, 0.075, 0.14, Vector3(0, 0.03, -0.78), body, Vector3.FORWARD, 12)  # warhead body
		var nose := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.010
		nm.bottom_radius = 0.075
		nm.height = 0.18
		nm.radial_segments = 12
		nose.mesh = nm
		nose.material_override = dark
		nose.basis = Basis(Quaternion(Vector3.UP, Vector3.FORWARD))
		nose.position = Vector3(0, 0.03, -0.94)
		root.add_child(nose)  # conical nose
		for fx in [-0.10, 0.10]:
			_box(root, Vector3(0.006, 0.10, 0.14), Vector3(fx, 0.03, -0.72), dark, z)  # side fins
			_box(root, Vector3(0.10, 0.006, 0.14), Vector3(0, 0.03 + fx, -0.72), dark, z)  # top/bottom fins
		var wood := _mat("wood")
		_box(root, Vector3(0.13, 0.05, 0.22), Vector3(0, 0.035, -0.30), wood, z)  # front heat shield
		_box(root, Vector3(0.13, 0.05, 0.20), Vector3(0, 0.035, 0.18), wood, z)   # rear heat shield
		_cyl(root, 0.062, 0.03, Vector3(0, 0.03, -0.14), dark, Vector3.FORWARD, 12)  # tube bands
		_cyl(root, 0.062, 0.03, Vector3(0, 0.03, 0.32), dark, Vector3.FORWARD, 12)
		_box(root, Vector3(0.05, 0.14, 0.06), Vector3(0, -0.10, 0.02), wood, Vector3(0.3, 0, 0))  # pistol grip
		_box(root, Vector3(0.012, 0.045, 0.02), Vector3(0, -0.055, -0.03), steel, z)  # trigger
		_box(root, Vector3(0.012, 0.075, 0.012), Vector3(0, 0.115, -0.44), dark, z)  # flip-up front post
		_box(root, Vector3(0.012, 0.06, 0.012), Vector3(-0.02, 0.105, 0.02), dark, z)  # rear notch L
		_box(root, Vector3(0.012, 0.06, 0.012), Vector3(0.02, 0.105, 0.02), dark, z)   # rear notch R
		_box(root, Vector3(0.052, 0.012, 0.012), Vector3(0, 0.135, 0.02), dark, z)      # rear notch bar
	if style == "stinger":
		# MANPADS: long tube, gripstock, flip-up sight, seeker head.
		_cyl(root, 0.05, 1.05, Vector3(0, 0.03, -0.10), body, Vector3.FORWARD, 12)
		_cyl(root, 0.055, 0.10, Vector3(0, 0.03, -0.62), dark, Vector3.FORWARD, 12)  # seeker
		_box(root, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.09, 0.05), _mat("black"), Vector3(0.25, 0, 0))
		_box(root, Vector3(0.04, 0.10, 0.06), Vector3(0, 0.12, -0.20), dark, z)  # sight housing
		_cyl(root, 0.02, 0.02, Vector3(0, 0.12, -0.24), _mat("glass"), Vector3.FORWARD, 8)
		_cyl(root, 0.065, 0.10, Vector3(0, 0.03, 0.45), dark, Vector3.FORWARD, 12)  # rear nozzle
	if style == "disc":
		# Futuristic disc launcher: compact sci-fi body + spinning disc mag.
		_box(root, Vector3(0.09, 0.12, 0.30), Vector3(0, 0.0, 0.0), _mat("graphite"), z)
		_cyl(root, 0.09, 0.05, Vector3(0, 0.10, 0.02), dark, Vector3.UP, 14)  # disc mag
		_cyl(root, 0.07, 0.055, Vector3(0, 0.10, 0.02), _mat("steel"), Vector3.UP, 14)
		_box(root, Vector3(0.05, 0.05, 0.12), Vector3(0, 0.02, -0.20), dark, z)  # launch chute
		_box(root, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.10, 0.08), _mat("black"), Vector3(0.3, 0, 0))
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(0.2, 0.9, 1.0)
		_box(root, Vector3(0.095, 0.015, 0.02), Vector3(0, 0.0, 0.14), gm, z)  # glow strip
