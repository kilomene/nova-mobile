class_name VehicleModels
extends RefCounted
## Procedural NOVA vehicle models (models-only; driving/damage live in NovaVehicle).
## All geometry from boxes/cylinders/spheres; shared cached StandardMaterial3D templates.
## Forward = -Z. y = 0 at ground/water contact. No scripts attached to parts.

static var _mats := {}


static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"paint_sedan":
			m.albedo_color = Color(0.10, 0.22, 0.52); m.metallic = 0.75; m.roughness = 0.32
		"paint_bike":
			m.albedo_color = Color(0.55, 0.06, 0.08); m.metallic = 0.6; m.roughness = 0.38
		"paint_truck":
			m.albedo_color = Color(0.80, 0.82, 0.85); m.metallic = 0.3; m.roughness = 0.5
		"paint_tank":
			m.albedo_color = Color(0.25, 0.28, 0.16); m.metallic = 0.2; m.roughness = 0.75
		"paint_heli":
			m.albedo_color = Color(0.20, 0.22, 0.20); m.metallic = 0.45; m.roughness = 0.55
		"paint_boat":
			m.albedo_color = Color(0.86, 0.87, 0.88); m.metallic = 0.35; m.roughness = 0.45
		"paint_hover":
			m.albedo_color = Color(0.08, 0.09, 0.11); m.metallic = 0.8; m.roughness = 0.3
		"paint_b2":
			m.albedo_color = Color(0.05, 0.05, 0.06); m.metallic = 0.15; m.roughness = 0.92
		"paint_suv":
			m.albedo_color = Color(0.08, 0.22, 0.14); m.metallic = 0.7; m.roughness = 0.35
		"paint_pickup":
			m.albedo_color = Color(0.60, 0.25, 0.08); m.metallic = 0.6; m.roughness = 0.4
		"paint_sport":
			m.albedo_color = Color(0.70, 0.05, 0.05); m.metallic = 0.85; m.roughness = 0.25
		"paint_atv":
			m.albedo_color = Color(0.50, 0.08, 0.06); m.metallic = 0.4; m.roughness = 0.5
		"paint_armored":
			m.albedo_color = Color(0.06, 0.06, 0.07); m.metallic = 0.5; m.roughness = 0.8
		"paint_jeep":
			m.albedo_color = Color(0.28, 0.30, 0.16); m.metallic = 0.25; m.roughness = 0.7
		"bed_liner":
			m.albedo_color = Color(0.09, 0.09, 0.10); m.metallic = 0.0; m.roughness = 0.95
		"glass":
			m.albedo_color = Color(0.05, 0.08, 0.12); m.metallic = 0.9; m.roughness = 0.12
		"rubber":
			m.albedo_color = Color(0.05, 0.05, 0.05); m.metallic = 0.0; m.roughness = 0.9
		"track":
			m.albedo_color = Color(0.07, 0.07, 0.07); m.metallic = 0.35; m.roughness = 0.8
		"metal_dark":
			m.albedo_color = Color(0.18, 0.18, 0.20); m.metallic = 0.8; m.roughness = 0.45
		"steel":
			m.albedo_color = Color(0.45, 0.47, 0.50); m.metallic = 0.9; m.roughness = 0.35
		"chrome":
			m.albedo_color = Color(0.70, 0.72, 0.75); m.metallic = 1.0; m.roughness = 0.15
		"deck_grey":
			m.albedo_color = Color(0.35, 0.36, 0.38); m.metallic = 0.3; m.roughness = 0.6
		"wood":
			m.albedo_color = Color(0.50, 0.34, 0.18); m.metallic = 0.0; m.roughness = 0.7
		"griptape":
			m.albedo_color = Color(0.08, 0.08, 0.08); m.metallic = 0.0; m.roughness = 0.95
		"urethane":
			m.albedo_color = Color(0.85, 0.78, 0.62); m.metallic = 0.0; m.roughness = 0.55
		"accent_orange":
			m.albedo_color = Color(0.85, 0.35, 0.08); m.metallic = 0.3; m.roughness = 0.5
		"light_head":
			m.albedo_color = Color(0.9, 0.95, 1.0)
			m.emission_enabled = true; m.emission = Color(0.9, 0.95, 1.0)
			m.emission_energy_multiplier = 2.0
		"light_tail":
			m.albedo_color = Color(0.7, 0.05, 0.05)
			m.emission_enabled = true; m.emission = Color(1.0, 0.08, 0.08)
			m.emission_energy_multiplier = 2.0
		"glow_cyan":
			m.albedo_color = Color(0.1, 0.8, 0.9)
			m.emission_enabled = true; m.emission = Color(0.1, 0.85, 1.0)
			m.emission_energy_multiplier = 3.0
		"glow_orange":
			m.albedo_color = Color(0.9, 0.45, 0.1)
			m.emission_enabled = true; m.emission = Color(1.0, 0.5, 0.1)
			m.emission_energy_multiplier = 2.5
		"nav_red":
			m.albedo_color = Color(0.6, 0.05, 0.05)
			m.emission_enabled = true; m.emission = Color(1.0, 0.05, 0.05)
			m.emission_energy_multiplier = 2.0
		"nav_green":
			m.albedo_color = Color(0.05, 0.6, 0.1)
			m.emission_enabled = true; m.emission = Color(0.05, 1.0, 0.15)
			m.emission_energy_multiplier = 2.0
		"nav_white":
			m.albedo_color = Color(0.9, 0.9, 0.9)
			m.emission_enabled = true; m.emission = Color(1.0, 1.0, 1.0)
			m.emission_energy_multiplier = 2.0
		_:
			m.albedo_color = Color(0.12, 0.12, 0.13); m.metallic = 0.5; m.roughness = 0.5
	_mats[key] = m
	return m


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


static func _sph(root: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	return mi


## Collect body-paint meshes: every MeshInstance3D under root whose
## material_override is one of the given body-paint materials.
static func _paint_meshes(root: Node3D, mats: Array) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and mats.has((n as MeshInstance3D).material_override):
			out.append(n)
		for ch in n.get_children():
			stack.append(ch)
	return out


## Wheel assembly: steer pivot -> spin pivot -> tire + hub. Returns {steer, spin}.
## Tires are cylinders along local X so spin = rotation.x (driven by NovaVehicle).
static func _wheel(root: Node3D, radius: float, width: float, pos: Vector3, tire_mat: Material, hub_mat: Material) -> Dictionary:
	var steer := Node3D.new()
	steer.name = "Steer"
	steer.position = pos
	root.add_child(steer)
	var spin := Node3D.new()
	spin.name = "Spin"
	steer.add_child(spin)
	_cyl(spin, radius, width, Vector3.ZERO, tire_mat, Vector3.RIGHT, 14)
	_cyl(spin, radius * 0.55, width + 0.03, Vector3.ZERO, hub_mat, Vector3.RIGHT, 10)
	return {"steer": steer, "spin": spin}


## Build a vehicle. Returns {root, wheels, steer, rotor_main, rotor_tail, turret,
## gun, seat, muzzle, length, width, height}.
static func build(vehicle_id: String) -> Dictionary:
	var d: Dictionary
	match vehicle_id:
		"sedan":
			d = _build_sedan()
		"bike":
			d = _build_bike()
		"truck":
			d = _build_truck()
		"tank":
			d = _build_tank()
		"heli":
			d = _build_heli()
		"boat":
			d = _build_boat()
		"hoverbike":
			d = _build_hoverbike()
		"skateboard":
			d = _build_skateboard()
		"b2":
			d = _build_b2()
		"suv":
			d = _build_suv()
		"pickup":
			d = _build_pickup()
		"sportscar":
			d = _build_sportscar()
		"atv":
			d = _build_atv()
		"armored_suv":
			d = _build_armored_suv()
		"jeep":
			d = _build_jeep()
		_:
			d = _build_sedan()
			(d["root"] as Node3D).name = "Vehicle_unknown_" + vehicle_id
	d["id"] = vehicle_id
	return d


static func _empty() -> Dictionary:
	return {
		"root": null, "wheels": [], "steer": [],
		"rotor_main": null, "rotor_tail": null, "turret": null, "gun": null,
		"seat": Vector3.ZERO, "muzzle": Vector3.ZERO,
		"length": 0.0, "width": 0.0, "height": 0.0,
		"paint": [],
	}


# ---------------------------------------------------------------- sedan ----
static func _build_sedan() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_sedan"
	d["root"] = root
	var paint := _mat("paint_sedan")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# Wheels: r=0.34 at y=0.34; front pair steer.
	var wfl := _wheel(root, 0.34, 0.24, Vector3(-0.78, 0.34, -1.45), rubber, steel)
	var wfr := _wheel(root, 0.34, 0.24, Vector3(0.78, 0.34, -1.45), rubber, steel)
	var wrl := _wheel(root, 0.34, 0.24, Vector3(-0.78, 0.34, 1.45), rubber, steel)
	var wrr := _wheel(root, 0.34, 0.24, Vector3(0.78, 0.34, 1.45), rubber, steel)
	d["wheels"] = [wfl["spin"], wfr["spin"], wrl["spin"], wrr["spin"]]
	d["steer"] = [wfl["steer"], wfr["steer"]]
	# Main body shell.
	_box(root, Vector3(1.8, 0.62, 4.6), Vector3(0, 0.66, 0), paint, z)
	# Hood + trunk sculpt.
	_box(root, Vector3(1.7, 0.16, 1.25), Vector3(0, 0.99, -1.55), paint, z)
	_box(root, Vector3(1.7, 0.18, 1.05), Vector3(0, 0.98, 1.65), paint, z)
	# Glasshouse.
	_box(root, Vector3(1.55, 0.48, 2.5), Vector3(0, 1.21, 0.15), glass, z)
	# Roof panel.
	_box(root, Vector3(1.62, 0.07, 1.6), Vector3(0, 1.46, 0.35), paint, z)
	# Sloped windshield + rear window.
	_box(root, Vector3(1.45, 0.52, 0.06), Vector3(0, 1.18, -1.08), glass, Vector3(-0.45, 0, 0))
	_box(root, Vector3(1.45, 0.42, 0.06), Vector3(0, 1.16, 1.38), glass, Vector3(0.5, 0, 0))
	# Bumpers, grille, plates.
	_box(root, Vector3(1.82, 0.28, 0.3), Vector3(0, 0.5, -2.32), dark, z)
	_box(root, Vector3(1.82, 0.28, 0.3), Vector3(0, 0.5, 2.32), dark, z)
	_box(root, Vector3(1.0, 0.18, 0.08), Vector3(0, 0.72, -2.34), dark, z)
	_box(root, Vector3(0.44, 0.12, 0.02), Vector3(0, 0.62, 2.48), _mat("paint_truck"), z)
	# Headlights + taillights (emissive).
	_box(root, Vector3(0.42, 0.14, 0.08), Vector3(-0.6, 0.82, -2.31), _mat("light_head"), z)
	_box(root, Vector3(0.42, 0.14, 0.08), Vector3(0.6, 0.82, -2.31), _mat("light_head"), z)
	_box(root, Vector3(0.4, 0.14, 0.08), Vector3(-0.6, 0.85, 2.31), _mat("light_tail"), z)
	_box(root, Vector3(0.4, 0.14, 0.08), Vector3(0.6, 0.85, 2.31), _mat("light_tail"), z)
	# Side mirrors + stalks.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.1, 0.05, 0.12), Vector3(sx * 0.92, 1.12, -0.75), dark, z)
		_box(root, Vector3(0.07, 0.12, 0.14), Vector3(sx * 1.0, 1.16, -0.75), paint, z)
	# Door handles (4-door).
	for sx in [-1.0, 1.0]:
		for dz in [-0.5, 0.55]:
			_box(root, Vector3(0.04, 0.04, 0.22), Vector3(sx * 0.91, 0.9, dz), dark, z)
	d["seat"] = Vector3(0.45, 1.1, 0.3)
	d["muzzle"] = Vector3(0, 0.8, -2.45)
	d["length"] = 4.6
	d["width"] = 1.8
	d["height"] = 1.45
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------------ bike ----
static func _build_bike() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_bike"
	d["root"] = root
	var paint := _mat("paint_bike")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# Wheels: front steer.
	var wf := _wheel(root, 0.31, 0.12, Vector3(0, 0.31, -0.72), rubber, steel)
	var wr := _wheel(root, 0.31, 0.14, Vector3(0, 0.31, 0.68), rubber, steel)
	d["wheels"] = [wf["spin"], wr["spin"]]
	d["steer"] = [wf["steer"]]
	# Swingarm + engine + frame.
	_box(root, Vector3(0.1, 0.08, 0.6), Vector3(-0.12, 0.35, 0.42), dark, z)
	_box(root, Vector3(0.1, 0.08, 0.6), Vector3(0.12, 0.35, 0.42), dark, z)
	_box(root, Vector3(0.4, 0.35, 0.5), Vector3(0, 0.45, 0.1), dark, z)
	_box(root, Vector3(0.12, 0.12, 0.9), Vector3(0, 0.65, -0.05), paint, z)
	# Fuel tank sculpt.
	_box(root, Vector3(0.38, 0.28, 0.55), Vector3(0, 0.82, -0.15), paint, z)
	_box(root, Vector3(0.3, 0.1, 0.4), Vector3(0, 0.99, -0.15), paint, z)
	# Seat.
	_box(root, Vector3(0.32, 0.1, 0.5), Vector3(0, 0.85, 0.45), rubber, z)
	# Front fork (raked).
	_cyl(root, 0.035, 0.85, Vector3(-0.09, 0.62, -0.7), steel, Vector3(0, 1, -0.25), 8)
	_cyl(root, 0.035, 0.85, Vector3(0.09, 0.62, -0.7), steel, Vector3(0, 1, -0.25), 8)
	# Handlebar + grips.
	_cyl(root, 0.025, 0.6, Vector3(0, 1.0, -0.78), steel, Vector3.RIGHT, 8)
	_cyl(root, 0.038, 0.15, Vector3(-0.3, 1.0, -0.78), rubber, Vector3.RIGHT, 8)
	_cyl(root, 0.038, 0.15, Vector3(0.3, 1.0, -0.78), rubber, Vector3.RIGHT, 8)
	# Headlight (round, emissive) + housing.
	_cyl(root, 0.1, 0.12, Vector3(0, 0.95, -0.82), dark, Vector3.FORWARD, 12)
	_sph(root, 0.085, Vector3(0, 0.95, -0.88), _mat("light_head"))
	# Exhaust pipe + muffler.
	_cyl(root, 0.045, 1.1, Vector3(0.22, 0.35, 0.15), steel, Vector3.FORWARD, 10)
	_cyl(root, 0.07, 0.28, Vector3(0.22, 0.35, 0.68), steel, Vector3.FORWARD, 10)
	# Fenders.
	_box(root, Vector3(0.16, 0.05, 0.5), Vector3(0, 0.6, -0.72), paint, z)
	_box(root, Vector3(0.2, 0.05, 0.45), Vector3(0, 0.6, 0.68), paint, z)
	# Taillight.
	_box(root, Vector3(0.12, 0.08, 0.05), Vector3(0, 0.68, 0.92), _mat("light_tail"), z)
	d["seat"] = Vector3(0, 0.95, 0.45)
	d["muzzle"] = Vector3(0, 0.95, -1.0)
	d["length"] = 2.1
	d["width"] = 0.7
	d["height"] = 1.15
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ----------------------------------------------------------------- truck ----
static func _build_truck() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_truck"
	d["root"] = root
	var paint := _mat("paint_truck")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var chrome := _mat("chrome")
	var z := Vector3.ZERO
	# 6 wheels: front axle steers, rear dual axles.
	var wf1 := _wheel(root, 0.5, 0.36, Vector3(-0.95, 0.5, -2.9), rubber, steel)
	var wf2 := _wheel(root, 0.5, 0.36, Vector3(0.95, 0.5, -2.9), rubber, steel)
	var wr1 := _wheel(root, 0.5, 0.4, Vector3(-0.95, 0.5, 1.3), rubber, steel)
	var wr2 := _wheel(root, 0.5, 0.4, Vector3(0.95, 0.5, 1.3), rubber, steel)
	var wr3 := _wheel(root, 0.5, 0.4, Vector3(-0.95, 0.5, 2.5), rubber, steel)
	var wr4 := _wheel(root, 0.5, 0.4, Vector3(0.95, 0.5, 2.5), rubber, steel)
	d["wheels"] = [wf1["spin"], wf2["spin"], wr1["spin"], wr2["spin"], wr3["spin"], wr4["spin"]]
	d["steer"] = [wf1["steer"], wf2["steer"]]
	# Chassis.
	_box(root, Vector3(1.6, 0.3, 7.2), Vector3(0, 0.75, 0), dark, z)
	# Cab.
	_box(root, Vector3(2.3, 1.5, 2.2), Vector3(0, 1.75, -2.4), paint, z)
	_box(root, Vector3(2.35, 0.1, 2.25), Vector3(0, 2.55, -2.4), paint, z)
	# Windshield + side glass.
	_box(root, Vector3(2.0, 0.7, 0.08), Vector3(0, 1.95, -3.44), glass, Vector3(-0.12, 0, 0))
	_box(root, Vector3(0.06, 0.5, 0.8), Vector3(-1.16, 1.95, -2.5), glass, z)
	_box(root, Vector3(0.06, 0.5, 0.8), Vector3(1.16, 1.95, -2.5), glass, z)
	# Grille + bumper + headlights.
	_box(root, Vector3(1.8, 0.5, 0.1), Vector3(0, 1.25, -3.52), chrome, z)
	_box(root, Vector3(2.4, 0.35, 0.25), Vector3(0, 0.75, -3.55), dark, z)
	_box(root, Vector3(0.35, 0.25, 0.08), Vector3(-0.85, 1.1, -3.52), _mat("light_head"), z)
	_box(root, Vector3(0.35, 0.25, 0.08), Vector3(0.85, 1.1, -3.52), _mat("light_head"), z)
	# Mirrors.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.25, 0.05, 0.05), Vector3(sx * 1.28, 2.1, -3.1), dark, z)
		_box(root, Vector3(0.06, 0.3, 0.18), Vector3(sx * 1.42, 2.0, -3.1), dark, z)
	# Cargo box + panel ribs.
	_box(root, Vector3(2.35, 2.0, 4.6), Vector3(0, 1.85, 1.0), paint, z)
	for i in range(6):
		_box(root, Vector3(2.42, 2.02, 0.07), Vector3(0, 1.85, -0.9 + float(i) * 0.85), dark, z)
	# Rear doors + taillights.
	_box(root, Vector3(2.0, 1.8, 0.06), Vector3(0, 1.85, 3.32), dark, z)
	_box(root, Vector3(0.25, 0.3, 0.06), Vector3(-1.0, 1.1, 3.33), _mat("light_tail"), z)
	_box(root, Vector3(0.25, 0.3, 0.06), Vector3(1.0, 1.1, 3.33), _mat("light_tail"), z)
	d["seat"] = Vector3(0.55, 2.0, -2.6)
	d["muzzle"] = Vector3(0, 1.2, -3.8)
	d["length"] = 7.6
	d["width"] = 2.4
	d["height"] = 3.1
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------------ tank ----
static func _build_tank() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_tank"
	d["root"] = root
	var paint := _mat("paint_tank")
	var dark := _mat("metal_dark")
	var trackm := _mat("track")
	var z := Vector3.ZERO
	# Tracks: dark tread boxes with road wheels.
	_box(root, Vector3(0.85, 1.0, 7.2), Vector3(-1.35, 0.5, 0), trackm, z)
	_box(root, Vector3(0.85, 1.0, 7.2), Vector3(1.35, 0.5, 0), trackm, z)
	for sx in [-1.0, 1.0]:
		for wz in [-2.8, -1.4, 0.0, 1.4, 2.8]:
			_cyl(root, 0.32, 0.92, Vector3(sx * 1.35, 0.42, wz), dark, Vector3.RIGHT, 12)
	# Track fenders.
	_box(root, Vector3(0.95, 0.12, 7.3), Vector3(-1.35, 1.06, 0), paint, z)
	_box(root, Vector3(0.95, 0.12, 7.3), Vector3(1.35, 1.06, 0), paint, z)
	# Hull + glacis plate + deck.
	_box(root, Vector3(2.9, 0.9, 7.0), Vector3(0, 1.35, 0), paint, z)
	_box(root, Vector3(2.9, 0.25, 1.8), Vector3(0, 1.62, -3.35), paint, Vector3(0.6, 0, 0))
	_box(root, Vector3(2.7, 0.25, 6.8), Vector3(0, 1.92, 0), paint, z)
	_box(root, Vector3(2.7, 0.2, 1.0), Vector3(0, 2.05, 3.0), paint, z)
	# Headlight guards + lights.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.2, 0.28, 0.15), Vector3(sx * 0.9, 1.95, -3.25), dark, z)
		_box(root, Vector3(0.14, 0.12, 0.05), Vector3(sx * 0.9, 1.95, -3.34), _mat("light_head"), z)
	# Turret (rotating part).
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 2.05, 0.4)
	root.add_child(turret)
	d["turret"] = turret
	_cyl(turret, 1.05, 0.25, Vector3(0, 0.12, 0), paint, Vector3.UP, 14)
	_box(turret, Vector3(2.1, 0.65, 2.9), Vector3(0, 0.55, 0.1), paint, z)
	_box(turret, Vector3(1.9, 0.55, 0.9), Vector3(0, 0.52, -1.3), paint, Vector3(0.35, 0, 0))
	# Commander hatch + sight + antenna.
	_cyl(turret, 0.3, 0.12, Vector3(0.55, 0.95, 0.6), dark, Vector3.UP, 12)
	_box(turret, Vector3(0.25, 0.2, 0.35), Vector3(-0.55, 0.95, -0.5), dark, z)
	_cyl(turret, 0.02, 1.2, Vector3(-0.8, 1.4, 1.2), dark, Vector3.UP, 6)
	# Gun (elevating barrel).
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0, 0.55, -1.5)
	turret.add_child(gun)
	d["gun"] = gun
	_box(gun, Vector3(0.5, 0.5, 0.4), Vector3(0, 0, -0.1), dark, z)
	_cyl(gun, 0.11, 3.6, Vector3(0, 0, -2.0), dark, Vector3.FORWARD, 12)
	_cyl(gun, 0.16, 0.4, Vector3(0, 0, -3.7), dark, Vector3.FORWARD, 12)
	d["seat"] = Vector3(0, 2.6, 1.0)
	d["muzzle"] = Vector3(0, 2.6, -5.0)
	d["length"] = 7.6
	d["width"] = 3.6
	d["height"] = 2.7
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------------ heli ----
static func _build_heli() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_heli"
	d["root"] = root
	var paint := _mat("paint_heli")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# Landing skids (y=0 at skid contact).
	_cyl(root, 0.05, 3.6, Vector3(-0.9, 0.05, 0), dark, Vector3.FORWARD, 8)
	_cyl(root, 0.05, 3.6, Vector3(0.9, 0.05, 0), dark, Vector3.FORWARD, 8)
	for sx in [-1.0, 1.0]:
		for sz in [-1.2, 1.2]:
			_cyl(root, 0.04, 0.95, Vector3(sx * 0.9, 0.5, sz), dark, Vector3(sx * 0.15, 1, 0), 6)
	# Belly + fuselage + nose.
	_box(root, Vector3(1.6, 0.5, 4.5), Vector3(0, 1.0, 0.2), paint, z)
	_box(root, Vector3(1.8, 1.4, 5.5), Vector3(0, 1.9, 0), paint, z)
	_box(root, Vector3(1.7, 1.1, 1.5), Vector3(0, 1.72, -3.2), paint, Vector3(-0.25, 0, 0))
	# Tinted cockpit glass.
	_box(root, Vector3(1.55, 0.75, 1.8), Vector3(0, 2.05, -2.5), glass, z)
	# Engine deck + exhausts.
	_box(root, Vector3(1.6, 0.5, 2.5), Vector3(0, 2.75, 0.3), paint, z)
	_cyl(root, 0.14, 0.6, Vector3(-0.5, 2.6, 1.6), dark, Vector3.FORWARD, 10)
	_cyl(root, 0.14, 0.6, Vector3(0.5, 2.6, 1.6), dark, Vector3.FORWARD, 10)
	# Tail boom + fin.
	_cyl(root, 0.28, 3.0, Vector3(0, 2.0, 4.0), paint, Vector3.FORWARD, 10)
	_cyl(root, 0.18, 2.5, Vector3(0, 2.0, 6.6), paint, Vector3.FORWARD, 10)
	_box(root, Vector3(0.12, 1.6, 1.0), Vector3(0, 2.8, 7.2), paint, z)
	# Tail rotor (spins on local X).
	var rt := Node3D.new()
	rt.name = "RotorTail"
	rt.position = Vector3(-0.16, 2.6, 7.3)
	root.add_child(rt)
	d["rotor_tail"] = rt
	_cyl(rt, 0.08, 0.24, z, dark, Vector3.RIGHT, 8)
	_box(rt, Vector3(0.06, 1.0, 0.14), Vector3(0, 0.5, 0), dark, z)
	_box(rt, Vector3(0.06, 1.0, 0.14), Vector3(0, -0.5, 0), dark, z)
	# Main mast + rotor (spins on local Y).
	_cyl(root, 0.12, 0.8, Vector3(0, 3.1, 0.3), dark, Vector3.UP, 10)
	var rm := Node3D.new()
	rm.name = "RotorMain"
	rm.position = Vector3(0, 3.55, 0.3)
	root.add_child(rm)
	d["rotor_main"] = rm
	_sph(rm, 0.18, z, dark)
	_box(rm, Vector3(0.3, 0.05, 9.4), z, dark, z)
	_box(rm, Vector3(9.4, 0.05, 0.3), z, dark, z)
	# Stub wings + pylons + rocket tubes.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(1.4, 0.12, 0.8), Vector3(sx * 1.5, 1.6, -0.3), paint, z)
		_box(root, Vector3(0.12, 0.3, 0.6), Vector3(sx * 1.5, 1.4, -0.3), dark, z)
		for ox in [-0.35, 0.35]:
			_cyl(root, 0.06, 0.9, Vector3(sx * 1.5 + ox, 1.35, -0.55), steel, Vector3.FORWARD, 8)
	# Nav lights.
	_box(root, Vector3(0.12, 0.1, 0.12), Vector3(-2.25, 1.6, -0.3), _mat("nav_red"), z)
	_box(root, Vector3(0.12, 0.1, 0.12), Vector3(2.25, 1.6, -0.3), _mat("nav_green"), z)
	d["seat"] = Vector3(0, 2.0, -0.8)
	d["muzzle"] = Vector3(0, 1.8, -4.1)
	d["length"] = 8.0
	d["width"] = 2.2
	d["height"] = 3.7
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------------ boat ----
static func _build_boat() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_boat"
	d["root"] = root
	var paint := _mat("paint_boat")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var steel := _mat("steel")
	var accent := _mat("accent_orange")
	var z := Vector3.ZERO
	# V-hull: bottom, flared sides, transom, angled bow.
	_box(root, Vector3(2.0, 0.5, 6.5), Vector3(0, 0.35, 0.3), paint, z)
	_box(root, Vector3(0.25, 0.9, 6.5), Vector3(-1.05, 0.75, 0.3), paint, Vector3(0, 0, 0.15))
	_box(root, Vector3(0.25, 0.9, 6.5), Vector3(1.05, 0.75, 0.3), paint, Vector3(0, 0, -0.15))
	_box(root, Vector3(2.3, 0.9, 0.25), Vector3(0, 0.75, 3.4), paint, z)
	_box(root, Vector3(1.3, 0.85, 1.8), Vector3(0.55, 0.7, -3.4), paint, Vector3(0, 0.5, 0))
	_box(root, Vector3(1.3, 0.85, 1.8), Vector3(-0.55, 0.7, -3.4), paint, Vector3(0, -0.5, 0))
	# Accent stripe.
	_box(root, Vector3(2.36, 0.15, 6.6), Vector3(0, 0.9, 0.3), accent, z)
	# Deck.
	_box(root, Vector3(1.9, 0.1, 6.2), Vector3(0, 1.18, 0.3), _mat("deck_grey"), z)
	# Center console + windshield + helm seat.
	_box(root, Vector3(0.8, 0.9, 0.6), Vector3(0, 1.65, 0.6), paint, z)
	_box(root, Vector3(0.9, 0.45, 0.06), Vector3(0, 2.25, 0.32), glass, Vector3(-0.2, 0, 0))
	_box(root, Vector3(0.55, 0.55, 0.45), Vector3(0, 1.5, 1.15), dark, z)
	# Outboard motor.
	_box(root, Vector3(0.55, 0.5, 0.6), Vector3(0, 1.5, 3.7), paint, z)
	_box(root, Vector3(0.5, 0.7, 0.4), Vector3(0, 1.0, 3.7), dark, z)
	_cyl(root, 0.08, 0.9, Vector3(0, 0.45, 3.78), dark, Vector3.UP, 8)
	# Bow rail: posts + top rails.
	for sx in [-1.0, 1.0]:
		for rz in [-2.6, -3.3]:
			_cyl(root, 0.025, 0.5, Vector3(sx * 0.8, 1.45, rz), steel, Vector3.UP, 6)
		_cyl(root, 0.025, 1.4, Vector3(sx * 0.8, 1.7, -2.95), steel, Vector3.FORWARD, 6)
	# Cleats.
	for sx in [-1.0, 1.0]:
		for cz in [-1.5, 1.5]:
			_box(root, Vector3(0.12, 0.06, 0.05), Vector3(sx * 0.95, 1.26, cz), steel, z)
	d["seat"] = Vector3(0, 1.7, 1.15)
	d["muzzle"] = Vector3(0, 1.0, -4.2)
	d["length"] = 7.5
	d["width"] = 2.6
	d["height"] = 2.3
	d["paint"] = _paint_meshes(root, [paint])
	return d


# -------------------------------------------------------------- hoverbike ----
static func _build_hoverbike() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_hoverbike"
	d["root"] = root
	var paint := _mat("paint_hover")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var cyan := _mat("glow_cyan")
	var orange := _mat("glow_orange")
	var z := Vector3.ZERO
	# Central body + sculpted nose + rear cowl.
	_box(root, Vector3(0.5, 0.3, 1.6), Vector3(0, 0.7, 0), paint, z)
	_box(root, Vector3(0.45, 0.25, 0.8), Vector3(0, 0.62, -1.0), paint, Vector3(0.15, 0, 0))
	_box(root, Vector3(0.55, 0.35, 0.5), Vector3(0, 0.72, 0.9), paint, z)
	# Accent light strips.
	_box(root, Vector3(0.04, 0.06, 1.4), Vector3(-0.26, 0.72, 0), cyan, z)
	_box(root, Vector3(0.04, 0.06, 1.4), Vector3(0.26, 0.72, 0), cyan, z)
	# Seat.
	_box(root, Vector3(0.4, 0.12, 0.7), Vector3(0, 0.92, 0.25), rubber, z)
	# Handlebars: stem + bar + grips.
	_box(root, Vector3(0.08, 0.35, 0.08), Vector3(0, 0.85, -0.55), dark, z)
	_cyl(root, 0.03, 0.7, Vector3(0, 1.0, -0.55), dark, Vector3.RIGHT, 8)
	_cyl(root, 0.04, 0.16, Vector3(-0.32, 1.0, -0.55), rubber, Vector3.RIGHT, 8)
	_cyl(root, 0.04, 0.16, Vector3(0.32, 1.0, -0.55), rubber, Vector3.RIGHT, 8)
	# 4 repulsor pads (emissive cyan) + housings + arms.
	for sx in [-1.0, 1.0]:
		for pz in [-0.7, 0.7]:
			_box(root, Vector3(0.4, 0.08, 0.12), Vector3(sx * 0.2, 0.45, pz), dark, z)
			_box(root, Vector3(0.36, 0.1, 0.5), Vector3(sx * 0.35, 0.32, pz), dark, z)
			_box(root, Vector3(0.3, 0.12, 0.45), Vector3(sx * 0.35, 0.18, pz), cyan, z)
	# Rear thruster + glow.
	_cyl(root, 0.12, 0.3, Vector3(0, 0.7, 1.2), dark, Vector3.FORWARD, 10)
	_cyl(root, 0.1, 0.08, Vector3(0, 0.7, 1.38), orange, Vector3.FORWARD, 10)
	d["seat"] = Vector3(0, 1.05, 0.25)
	d["muzzle"] = Vector3(0, 0.7, -1.45)
	d["length"] = 2.4
	d["width"] = 0.9
	d["height"] = 1.1
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------- skateboard ----
static func _build_skateboard() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_skateboard"
	d["root"] = root
	var wood := _mat("wood")
	var grip := _mat("griptape")
	var dark := _mat("metal_dark")
	var ure := _mat("urethane")
	var z := Vector3.ZERO
	# Deck + griptape + kicked nose/tail.
	_box(root, Vector3(0.21, 0.03, 0.8), Vector3(0, 0.1, 0), wood, z)
	_box(root, Vector3(0.215, 0.012, 0.79), Vector3(0, 0.118, 0), grip, z)
	_box(root, Vector3(0.21, 0.03, 0.12), Vector3(0, 0.12, -0.44), wood, Vector3(-0.35, 0, 0))
	_box(root, Vector3(0.21, 0.03, 0.12), Vector3(0, 0.12, 0.44), wood, Vector3(0.35, 0, 0))
	# Trucks.
	_box(root, Vector3(0.16, 0.04, 0.1), Vector3(0, 0.07, -0.28), dark, z)
	_box(root, Vector3(0.16, 0.04, 0.1), Vector3(0, 0.07, 0.28), dark, z)
	# 4 urethane wheels (spin pivots only; no steering).
	var spins: Array = []
	for sx in [-1.0, 1.0]:
		for wz in [-0.28, 0.28]:
			var spin := Node3D.new()
			spin.name = "Spin"
			spin.position = Vector3(sx * 0.09, 0.035, wz)
			root.add_child(spin)
			_cyl(spin, 0.028, 0.03, z, ure, Vector3.RIGHT, 10)
			spins.append(spin)
	d["wheels"] = spins
	d["seat"] = Vector3(0, 0.16, 0)
	d["muzzle"] = Vector3(0, 0.1, -0.45)
	d["length"] = 0.8
	d["width"] = 0.21
	d["height"] = 0.14
	d["paint"] = _paint_meshes(root, [wood])
	return d


# ---------------------------------------------------------------------- b2 ----
static func _build_b2() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_b2"
	d["root"] = root
	var paint := _mat("paint_b2")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var z := Vector3.ZERO
	# Center body.
	_box(root, Vector3(4.0, 0.9, 8.0), Vector3(0, 1.0, 0.5), paint, z)
	# Pointed nose: two swept angled panels meeting at the tip.
	_box(root, Vector3(1.6, 0.75, 3.2), Vector3(0.7, 1.0, -4.2), paint, Vector3(0, 0.4, 0))
	_box(root, Vector3(1.6, 0.75, 3.2), Vector3(-0.7, 1.0, -4.2), paint, Vector3(0, -0.4, 0))
	# Swept wing mid + outer panels (21 m span).
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(5.0, 0.55, 5.5), Vector3(sx * 4.5, 1.0, 1.5), paint, Vector3(0, -sx * 0.35, 0))
		_box(root, Vector3(4.5, 0.45, 3.5), Vector3(sx * 8.3, 1.0, 2.8), paint, Vector3(0, -sx * 0.35, 0))
	# W double-V trailing edge.
	_box(root, Vector3(2.5, 0.4, 1.2), Vector3(1.5, 1.0, 4.6), paint, Vector3(0, 0.5, 0))
	_box(root, Vector3(2.5, 0.4, 1.2), Vector3(-1.5, 1.0, 4.6), paint, Vector3(0, -0.5, 0))
	_box(root, Vector3(1.2, 0.35, 0.8), Vector3(0, 1.0, 4.9), paint, z)
	# Cockpit hump (dark tinted).
	_box(root, Vector3(1.4, 0.35, 1.6), Vector3(0, 1.55, -2.5), glass, z)
	# Engine intake humps.
	_box(root, Vector3(1.2, 0.55, 2.2), Vector3(2.2, 1.4, -1.5), paint, z)
	_box(root, Vector3(1.2, 0.55, 2.2), Vector3(-2.2, 1.4, -1.5), paint, z)
	# Bomb bay doors (bomb exit below).
	_box(root, Vector3(2.4, 0.08, 3.0), Vector3(0, 0.58, 0.8), dark, z)
	# Nav lights: red left, green right, white tail.
	_box(root, Vector3(0.15, 0.1, 0.15), Vector3(-10.4, 1.0, 3.6), _mat("nav_red"), z)
	_box(root, Vector3(0.15, 0.1, 0.15), Vector3(10.4, 1.0, 3.6), _mat("nav_green"), z)
	_box(root, Vector3(0.15, 0.1, 0.15), Vector3(0, 1.0, 5.3), _mat("nav_white"), z)
	d["seat"] = Vector3(0, 1.7, -2.3)
	d["muzzle"] = Vector3(0, 0.5, 0.8)
	d["length"] = 10.5
	d["width"] = 21.0
	d["height"] = 1.8
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------------- suv ----
static func _build_suv() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_suv"
	d["root"] = root
	var paint := _mat("paint_suv")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# Chunky off-road tires; front pair steers.
	var wfl := _wheel(root, 0.42, 0.3, Vector3(-0.88, 0.42, -1.55), rubber, steel)
	var wfr := _wheel(root, 0.42, 0.3, Vector3(0.88, 0.42, -1.55), rubber, steel)
	var wrl := _wheel(root, 0.42, 0.3, Vector3(-0.88, 0.42, 1.55), rubber, steel)
	var wrr := _wheel(root, 0.42, 0.3, Vector3(0.88, 0.42, 1.55), rubber, steel)
	d["wheels"] = [wfl["spin"], wfr["spin"], wrl["spin"], wrr["spin"]]
	d["steer"] = [wfl["steer"], wfr["steer"]]
	# Tall body + high greenhouse.
	_box(root, Vector3(2.0, 0.75, 5.0), Vector3(0, 0.85, 0), paint, z)
	_box(root, Vector3(1.9, 0.15, 1.2), Vector3(0, 1.25, -1.8), paint, z)  # hood
	# Big glass band + roof.
	_box(root, Vector3(1.87, 0.55, 4.0), Vector3(0, 1.62, 0.1), glass, z)
	_box(root, Vector3(1.9, 0.08, 4.4), Vector3(0, 1.97, 0.1), paint, z)
	_box(root, Vector3(1.8, 0.6, 0.06), Vector3(0, 1.6, -2.0), glass, Vector3(-0.35, 0, 0))
	# Pillars.
	for sx in [-1.0, 1.0]:
		for pz in [-1.6, 0.1, 1.8]:
			_box(root, Vector3(0.1, 0.58, 0.12), Vector3(sx * 0.9, 1.62, pz), paint, z)
	# Roof rails.
	for sx in [-1.0, 1.0]:
		_cyl(root, 0.04, 3.6, Vector3(sx * 0.7, 2.06, 0.1), dark, Vector3.FORWARD, 8)
		for fz in [-1.4, 0.1, 1.6]:
			_box(root, Vector3(0.08, 0.08, 0.08), Vector3(sx * 0.7, 2.01, fz), dark, z)
	# Spare wheel on rear door.
	_cyl(root, 0.4, 0.25, Vector3(0, 1.3, 2.55), rubber, Vector3.FORWARD, 14)
	_cyl(root, 0.22, 0.28, Vector3(0, 1.3, 2.55), steel, Vector3.FORWARD, 10)
	_box(root, Vector3(0.9, 0.9, 0.1), Vector3(0, 1.3, 2.44), paint, z)  # rear door
	# Running boards.
	_box(root, Vector3(0.25, 0.08, 3.0), Vector3(-1.05, 0.45, 0), dark, z)
	_box(root, Vector3(0.25, 0.08, 3.0), Vector3(1.05, 0.45, 0), dark, z)
	# Bumpers, grille, lights.
	_box(root, Vector3(2.0, 0.3, 0.3), Vector3(0, 0.55, -2.52), dark, z)
	_box(root, Vector3(2.0, 0.3, 0.3), Vector3(0, 0.55, 2.52), dark, z)
	_box(root, Vector3(1.2, 0.22, 0.08), Vector3(0, 0.95, -2.52), dark, z)
	_box(root, Vector3(0.45, 0.16, 0.08), Vector3(-0.65, 0.95, -2.52), _mat("light_head"), z)
	_box(root, Vector3(0.45, 0.16, 0.08), Vector3(0.65, 0.95, -2.52), _mat("light_head"), z)
	_box(root, Vector3(0.4, 0.16, 0.08), Vector3(-0.65, 1.0, 2.52), _mat("light_tail"), z)
	_box(root, Vector3(0.4, 0.16, 0.08), Vector3(0.65, 1.0, 2.52), _mat("light_tail"), z)
	# Mirrors + door handles.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.1, 0.05, 0.12), Vector3(sx * 1.02, 1.5, -1.7), dark, z)
		_box(root, Vector3(0.07, 0.12, 0.15), Vector3(sx * 1.1, 1.54, -1.7), paint, z)
		for dz in [-0.9, 0.1, 1.1]:
			_box(root, Vector3(0.04, 0.04, 0.22), Vector3(sx * 1.01, 1.15, dz), dark, z)
	d["seat"] = Vector3(0.5, 1.5, -0.5)
	d["muzzle"] = Vector3(0, 1.0, -2.65)
	d["length"] = 5.0
	d["width"] = 2.0
	d["height"] = 1.95
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ---------------------------------------------------------------- pickup ----
static func _build_pickup() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_pickup"
	d["root"] = root
	var paint := _mat("paint_pickup")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var liner := _mat("bed_liner")
	var z := Vector3.ZERO
	# Off-road tires; front pair steers.
	var wfl := _wheel(root, 0.42, 0.3, Vector3(-0.88, 0.42, -1.7), rubber, steel)
	var wfr := _wheel(root, 0.42, 0.3, Vector3(0.88, 0.42, -1.7), rubber, steel)
	var wrl := _wheel(root, 0.42, 0.3, Vector3(-0.88, 0.42, 1.75), rubber, steel)
	var wrr := _wheel(root, 0.42, 0.3, Vector3(0.88, 0.42, 1.75), rubber, steel)
	d["wheels"] = [wfl["spin"], wfr["spin"], wrl["spin"], wrr["spin"]]
	d["steer"] = [wfl["steer"], wfr["steer"]]
	# Chassis + crew cab.
	_box(root, Vector3(1.7, 0.3, 5.0), Vector3(0, 0.7, 0), dark, z)
	_box(root, Vector3(1.95, 0.85, 1.8), Vector3(0, 1.45, -1.5), paint, z)
	_box(root, Vector3(1.97, 0.5, 1.6), Vector3(0, 1.55, -1.5), glass, z)
	_box(root, Vector3(2.0, 0.08, 1.85), Vector3(0, 1.9, -1.5), paint, z)
	_box(root, Vector3(1.9, 0.55, 0.06), Vector3(0, 1.5, -2.42), glass, Vector3(-0.25, 0, 0))
	# Hood.
	_box(root, Vector3(1.85, 0.18, 1.0), Vector3(0, 1.02, -2.9), paint, z)
	# Open cargo bed: liner floor, walls, tailgate.
	_box(root, Vector3(1.9, 0.12, 2.6), Vector3(0, 1.0, 0.9), liner, z)
	_box(root, Vector3(0.12, 0.55, 2.6), Vector3(-0.95, 1.3, 0.9), paint, z)
	_box(root, Vector3(0.12, 0.55, 2.6), Vector3(0.95, 1.3, 0.9), paint, z)
	_box(root, Vector3(1.9, 0.55, 0.12), Vector3(0, 1.3, -0.35), paint, z)
	_box(root, Vector3(1.9, 0.55, 0.12), Vector3(0, 1.3, 2.15), paint, z)
	# Bed rail caps.
	_box(root, Vector3(0.16, 0.06, 2.6), Vector3(-0.95, 1.6, 0.9), dark, z)
	_box(root, Vector3(0.16, 0.06, 2.6), Vector3(0.95, 1.6, 0.9), dark, z)
	# Roll bar behind cab.
	_cyl(root, 0.05, 0.9, Vector3(-0.7, 1.45, -0.4), dark, Vector3.UP, 8)
	_cyl(root, 0.05, 0.9, Vector3(0.7, 1.45, -0.4), dark, Vector3.UP, 8)
	_cyl(root, 0.05, 1.4, Vector3(0, 1.9, -0.4), dark, Vector3.RIGHT, 8)
	# Grille, bumper, lights.
	_box(root, Vector3(1.6, 0.4, 0.1), Vector3(0, 0.95, -3.42), dark, z)
	_box(root, Vector3(2.0, 0.3, 0.25), Vector3(0, 0.6, -3.45), dark, z)
	_box(root, Vector3(0.4, 0.16, 0.08), Vector3(-0.7, 0.95, -3.42), _mat("light_head"), z)
	_box(root, Vector3(0.4, 0.16, 0.08), Vector3(0.7, 0.95, -3.42), _mat("light_head"), z)
	_box(root, Vector3(0.3, 0.2, 0.06), Vector3(-0.8, 1.1, 2.22), _mat("light_tail"), z)
	_box(root, Vector3(0.3, 0.2, 0.06), Vector3(0.8, 1.1, 2.22), _mat("light_tail"), z)
	# Mirrors + handles.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.1, 0.05, 0.12), Vector3(sx * 1.0, 1.5, -2.2), dark, z)
		_box(root, Vector3(0.07, 0.12, 0.15), Vector3(sx * 1.08, 1.54, -2.2), paint, z)
		_box(root, Vector3(0.04, 0.04, 0.22), Vector3(sx * 0.99, 1.35, -1.2), dark, z)
		_box(root, Vector3(0.04, 0.04, 0.22), Vector3(sx * 0.99, 1.35, -1.9), dark, z)
	d["seat"] = Vector3(0.5, 1.5, -1.5)
	d["muzzle"] = Vector3(0, 1.0, -2.85)
	d["length"] = 5.4
	d["width"] = 2.0
	d["height"] = 1.9
	d["paint"] = _paint_meshes(root, [paint])
	return d


# -------------------------------------------------------------- sportscar ----
static func _build_sportscar() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_sportscar"
	d["root"] = root
	var paint := _mat("paint_sport")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# Low-profile wide tires; front pair steers.
	var wfl := _wheel(root, 0.32, 0.34, Vector3(-0.85, 0.32, -1.35), rubber, steel)
	var wfr := _wheel(root, 0.32, 0.34, Vector3(0.85, 0.32, -1.35), rubber, steel)
	var wrl := _wheel(root, 0.32, 0.36, Vector3(-0.85, 0.32, 1.35), rubber, steel)
	var wrr := _wheel(root, 0.32, 0.36, Vector3(0.85, 0.32, 1.35), rubber, steel)
	d["wheels"] = [wfl["spin"], wfr["spin"], wrl["spin"], wrr["spin"]]
	d["steer"] = [wfl["steer"], wfr["steer"]]
	# Low aerodynamic body + tapered nose.
	_box(root, Vector3(1.9, 0.45, 4.4), Vector3(0, 0.55, 0), paint, z)
	_box(root, Vector3(1.8, 0.28, 0.9), Vector3(0, 0.48, -2.15), paint, Vector3(0.25, 0, 0))
	# Cabin glass + roof.
	_box(root, Vector3(1.5, 0.38, 2.0), Vector3(0, 0.95, 0.2), glass, z)
	_box(root, Vector3(1.55, 0.06, 1.2), Vector3(0, 1.13, 0.35), paint, z)
	# Hood scoop + side air intakes.
	_box(root, Vector3(0.5, 0.08, 0.6), Vector3(0, 0.8, -1.2), dark, z)
	_box(root, Vector3(0.08, 0.25, 0.7), Vector3(-0.97, 0.55, 0.5), dark, z)
	_box(root, Vector3(0.08, 0.25, 0.7), Vector3(0.97, 0.55, 0.5), dark, z)
	# Rear spoiler.
	_box(root, Vector3(0.08, 0.25, 0.3), Vector3(-0.6, 0.95, 1.95), dark, z)
	_box(root, Vector3(0.08, 0.25, 0.3), Vector3(0.6, 0.95, 1.95), dark, z)
	_box(root, Vector3(1.7, 0.06, 0.4), Vector3(0, 1.08, 1.95), paint, z)
	# Aggressive headlights + full-width taillight bar.
	_box(root, Vector3(0.4, 0.1, 0.06), Vector3(-0.55, 0.62, -2.28), _mat("light_head"), Vector3(0, 0.2, 0))
	_box(root, Vector3(0.4, 0.1, 0.06), Vector3(0.55, 0.62, -2.28), _mat("light_head"), Vector3(0, -0.2, 0))
	_box(root, Vector3(1.2, 0.1, 0.06), Vector3(0, 0.68, 2.21), _mat("light_tail"), z)
	# Rear diffuser + fins + exhausts.
	_box(root, Vector3(1.6, 0.15, 0.4), Vector3(0, 0.3, 2.15), dark, z)
	for fx in [-0.6, -0.2, 0.2, 0.6]:
		_box(root, Vector3(0.05, 0.15, 0.35), Vector3(fx, 0.32, 2.15), dark, z)
	_cyl(root, 0.05, 0.2, Vector3(-0.3, 0.35, 2.28), steel, Vector3.FORWARD, 8)
	_cyl(root, 0.05, 0.2, Vector3(0.3, 0.35, 2.28), steel, Vector3.FORWARD, 8)
	# Side skirts.
	_box(root, Vector3(0.1, 0.12, 2.6), Vector3(-0.98, 0.38, 0), dark, z)
	_box(root, Vector3(0.1, 0.12, 2.6), Vector3(0.98, 0.38, 0), dark, z)
	d["seat"] = Vector3(0.4, 0.85, 0.3)
	d["muzzle"] = Vector3(0, 0.6, -2.3)
	d["length"] = 4.4
	d["width"] = 1.9
	d["height"] = 1.15
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------------- atv ----
static func _build_atv() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_atv"
	d["root"] = root
	var paint := _mat("paint_atv")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# 4 fat knobby tires with lug blocks; front pair steers.
	var spins: Array = []
	var steers: Array = []
	for sx in [-1.0, 1.0]:
		for wz in [-0.75, 0.75]:
			var w := _wheel(root, 0.3, 0.28, Vector3(sx * 0.5, 0.3, wz), rubber, steel)
			spins.append(w["spin"])
			if wz < 0.0:
				steers.append(w["steer"])
			var spin: Node3D = w["spin"]
			_box(spin, Vector3(0.3, 0.07, 0.1), Vector3(0, 0.3, 0), rubber, z)
			_box(spin, Vector3(0.3, 0.07, 0.1), Vector3(0, -0.3, 0), rubber, z)
			_box(spin, Vector3(0.3, 0.1, 0.07), Vector3(0, 0, 0.3), rubber, z)
			_box(spin, Vector3(0.3, 0.1, 0.07), Vector3(0, 0, -0.3), rubber, z)
	d["wheels"] = spins
	d["steer"] = steers
	# Frame + plastic body + front cowl.
	_box(root, Vector3(0.5, 0.25, 1.6), Vector3(0, 0.5, 0), dark, z)
	_box(root, Vector3(0.9, 0.3, 1.4), Vector3(0, 0.7, 0.1), paint, z)
	_box(root, Vector3(0.85, 0.25, 0.6), Vector3(0, 0.75, -0.6), paint, z)
	# Seat.
	_box(root, Vector3(0.45, 0.15, 0.8), Vector3(0, 0.9, 0.35), rubber, z)
	# Handlebars.
	_box(root, Vector3(0.08, 0.35, 0.08), Vector3(0, 0.9, -0.55), dark, z)
	_cyl(root, 0.03, 0.7, Vector3(0, 1.08, -0.55), dark, Vector3.RIGHT, 8)
	_cyl(root, 0.04, 0.16, Vector3(-0.32, 1.08, -0.55), rubber, Vector3.RIGHT, 8)
	_cyl(root, 0.04, 0.16, Vector3(0.32, 1.08, -0.55), rubber, Vector3.RIGHT, 8)
	# Mudguards over all four wheels.
	for sx in [-1.0, 1.0]:
		for wz in [-0.75, 0.75]:
			_box(root, Vector3(0.35, 0.06, 0.5), Vector3(sx * 0.5, 0.62, wz), paint, z)
	# Front + rear racks.
	for rz in [-0.95, 0.95]:
		_box(root, Vector3(0.7, 0.04, 0.08), Vector3(-0.3, 0.88, rz), dark, z)
		_box(root, Vector3(0.7, 0.04, 0.08), Vector3(0.3, 0.88, rz), dark, z)
		_box(root, Vector3(0.08, 0.04, 0.5), Vector3(0, 0.88, rz), dark, z)
	# Small headlight.
	_box(root, Vector3(0.25, 0.12, 0.08), Vector3(0, 0.85, -1.0), _mat("light_head"), z)
	d["seat"] = Vector3(0, 1.0, 0.35)
	d["muzzle"] = Vector3(0, 0.8, -1.15)
	d["length"] = 2.2
	d["width"] = 1.2
	d["height"] = 1.2
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------ armored_suv ----
static func _build_armored_suv() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_armored_suv"
	d["root"] = root
	var paint := _mat("paint_armored")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# Run-flat tires (dark hubs); front pair steers.
	var wfl := _wheel(root, 0.44, 0.32, Vector3(-0.92, 0.44, -1.6), rubber, dark)
	var wfr := _wheel(root, 0.44, 0.32, Vector3(0.92, 0.44, -1.6), rubber, dark)
	var wrl := _wheel(root, 0.44, 0.32, Vector3(-0.92, 0.44, 1.6), rubber, dark)
	var wrr := _wheel(root, 0.44, 0.32, Vector3(0.92, 0.44, 1.6), rubber, dark)
	d["wheels"] = [wfl["spin"], wfr["spin"], wrl["spin"], wrr["spin"]]
	d["steer"] = [wfl["steer"], wfr["steer"]]
	# Boxy reinforced body.
	_box(root, Vector3(2.1, 1.0, 5.2), Vector3(0, 1.0, 0), paint, z)
	_box(root, Vector3(2.05, 0.6, 4.6), Vector3(0, 1.8, 0.1), paint, z)
	# Bulletproof glass band with thick frames + pillars.
	_box(root, Vector3(2.07, 0.45, 4.0), Vector3(0, 1.8, 0.1), glass, z)
	for sx in [-1.0, 1.0]:
		for pz in [-1.7, 0.1, 1.9]:
			_box(root, Vector3(0.12, 0.52, 0.14), Vector3(sx * 1.0, 1.8, pz), paint, z)
	_box(root, Vector3(1.9, 0.5, 0.08), Vector3(0, 1.8, -2.0), glass, Vector3(-0.2, 0, 0))
	# Roof hatch + antenna.
	_cyl(root, 0.35, 0.1, Vector3(0, 2.15, 0.5), dark, Vector3.UP, 12)
	_cyl(root, 0.02, 1.0, Vector3(0.8, 2.6, 1.8), dark, Vector3.UP, 6)
	# Bullbar.
	_cyl(root, 0.05, 0.8, Vector3(-0.6, 0.8, -2.7), steel, Vector3.UP, 8)
	_cyl(root, 0.05, 0.8, Vector3(0.6, 0.8, -2.7), steel, Vector3.UP, 8)
	_cyl(root, 0.05, 1.3, Vector3(0, 1.1, -2.7), steel, Vector3.RIGHT, 8)
	# Armored bumpers + side skirts.
	_box(root, Vector3(2.15, 0.35, 0.3), Vector3(0, 0.6, -2.62), dark, z)
	_box(root, Vector3(2.15, 0.35, 0.3), Vector3(0, 0.6, 2.62), dark, z)
	_box(root, Vector3(0.08, 0.4, 4.0), Vector3(-1.06, 0.6, 0), dark, z)
	_box(root, Vector3(0.08, 0.4, 4.0), Vector3(1.06, 0.6, 0), dark, z)
	# Recessed headlights + taillights.
	_box(root, Vector3(0.4, 0.16, 0.08), Vector3(-0.65, 1.0, -2.61), _mat("light_head"), z)
	_box(root, Vector3(0.4, 0.16, 0.08), Vector3(0.65, 1.0, -2.61), _mat("light_head"), z)
	_box(root, Vector3(0.35, 0.16, 0.08), Vector3(-0.7, 1.05, 2.61), _mat("light_tail"), z)
	_box(root, Vector3(0.35, 0.16, 0.08), Vector3(0.7, 1.05, 2.61), _mat("light_tail"), z)
	# Mirrors + handles.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.07, 0.12, 0.15), Vector3(sx * 1.08, 1.7, -1.6), dark, z)
		for dz in [-0.9, 0.1, 1.1]:
			_box(root, Vector3(0.04, 0.04, 0.22), Vector3(sx * 1.06, 1.3, dz), dark, z)
	d["seat"] = Vector3(0.55, 1.6, -0.6)
	d["muzzle"] = Vector3(0, 1.1, -2.8)
	d["length"] = 5.2
	d["width"] = 2.1
	d["height"] = 2.1
	d["paint"] = _paint_meshes(root, [paint])
	return d


# ------------------------------------------------------------------ jeep ----
static func _build_jeep() -> Dictionary:
	var d := _empty()
	var root := Node3D.new()
	root.name = "Vehicle_jeep"
	d["root"] = root
	var paint := _mat("paint_jeep")
	var glass := _mat("glass")
	var dark := _mat("metal_dark")
	var rubber := _mat("rubber")
	var steel := _mat("steel")
	var z := Vector3.ZERO
	# Off-road tires; front pair steers.
	var wfl := _wheel(root, 0.4, 0.3, Vector3(-0.85, 0.4, -1.35), rubber, steel)
	var wfr := _wheel(root, 0.4, 0.3, Vector3(0.85, 0.4, -1.35), rubber, steel)
	var wrl := _wheel(root, 0.4, 0.3, Vector3(-0.85, 0.4, 1.35), rubber, steel)
	var wrr := _wheel(root, 0.4, 0.3, Vector3(0.85, 0.4, 1.35), rubber, steel)
	d["wheels"] = [wfl["spin"], wfr["spin"], wrl["spin"], wrr["spin"]]
	d["steer"] = [wfl["steer"], wfr["steer"]]
	# Flat body panels + hood.
	_box(root, Vector3(1.85, 0.6, 4.2), Vector3(0, 0.75, 0), paint, z)
	_box(root, Vector3(1.75, 0.12, 1.2), Vector3(0, 1.08, -1.4), paint, z)
	# 7-slot grille.
	_box(root, Vector3(1.2, 0.45, 0.06), Vector3(0, 0.85, -2.11), paint, z)
	for i in range(7):
		_box(root, Vector3(0.08, 0.4, 0.06), Vector3(-0.45 + float(i) * 0.15, 0.85, -2.14), dark, z)
	# Round headlights.
	_cyl(root, 0.16, 0.1, Vector3(-0.75, 0.95, -2.1), dark, Vector3.FORWARD, 12)
	_cyl(root, 0.16, 0.1, Vector3(0.75, 0.95, -2.1), dark, Vector3.FORWARD, 12)
	_cyl(root, 0.13, 0.12, Vector3(-0.75, 0.95, -2.12), _mat("light_head"), Vector3.FORWARD, 12)
	_cyl(root, 0.13, 0.12, Vector3(0.75, 0.95, -2.12), _mat("light_head"), Vector3.FORWARD, 12)
	# Windshield frame + glass (open top).
	_box(root, Vector3(0.08, 0.5, 0.08), Vector3(-0.85, 1.3, -0.9), paint, z)
	_box(root, Vector3(0.08, 0.5, 0.08), Vector3(0.85, 1.3, -0.9), paint, z)
	_box(root, Vector3(1.7, 0.4, 0.05), Vector3(0, 1.32, -0.9), glass, z)
	# Exposed roll cage.
	for sx in [-1.0, 1.0]:
		_cyl(root, 0.05, 1.0, Vector3(sx * 0.8, 1.5, 0.2), dark, Vector3.UP, 8)
		_cyl(root, 0.05, 1.0, Vector3(sx * 0.8, 1.5, 1.6), dark, Vector3.UP, 8)
		_cyl(root, 0.05, 1.6, Vector3(sx * 0.8, 2.0, 0.9), dark, Vector3.FORWARD, 8)
	# Seats.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.55, 0.18, 0.5), Vector3(sx * 0.45, 1.12, 0.3), dark, z)
		_box(root, Vector3(0.55, 0.5, 0.15), Vector3(sx * 0.45, 1.35, 0.6), dark, z)
	# Jerry can on the back.
	_box(root, Vector3(0.35, 0.45, 0.2), Vector3(0.5, 1.25, 1.95), _mat("accent_orange"), z)
	_box(root, Vector3(0.08, 0.06, 0.08), Vector3(0.5, 1.5, 1.95), dark, z)
	# Fenders + rear bumper + taillights.
	for sx in [-1.0, 1.0]:
		for wz in [-1.35, 1.35]:
			_box(root, Vector3(0.35, 0.08, 0.6), Vector3(sx * 0.85, 0.85, wz), paint, z)
	_box(root, Vector3(1.9, 0.25, 0.25), Vector3(0, 0.6, 2.12), dark, z)
	_box(root, Vector3(0.2, 0.15, 0.06), Vector3(-0.7, 0.85, 2.12), _mat("light_tail"), z)
	_box(root, Vector3(0.2, 0.15, 0.06), Vector3(0.7, 0.85, 2.12), _mat("light_tail"), z)
	d["seat"] = Vector3(0.45, 1.35, 0.3)
	d["muzzle"] = Vector3(0, 0.9, -2.2)
	d["length"] = 4.2
	d["width"] = 1.85
	d["height"] = 1.85
	d["paint"] = _paint_meshes(root, [paint])
	return d
