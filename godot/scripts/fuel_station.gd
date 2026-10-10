class_name FuelStation
extends Node3D
## NOVA Mobile: filling station POI — canopy with NOVA FUEL branding,
## exactly 3 explosive fuel pumps, enterable convenience store with loot,
## night lighting. Pumps + station detonate when shot (chain explosions).

signal station_destroyed(station: FuelStation)

var pumps: Array = []          # FuelPump
var hp := 220.0
var destroyed := false
var _store_spots: Array = []   # Vector3 world loot positions inside the store
var _sign: Label3D = null
var _t := 0.0


class FuelPump extends StaticBody3D:
	var hp := 60.0
	var destroyed := false
	var station = null  # FuelStation
	var _detonating := false
	var _body: MeshInstance3D = null
	var _screen_mat: StandardMaterial3D = null

	func _ready() -> void:
		add_to_group("enemies")  # bullets damage pumps (player._fire_hit)
		collision_layer = 1
		collision_mask = 0
		_build()

	func is_alive() -> bool:
		return not destroyed

	func take_damage(amount, from_pos: Vector3 = Vector3.ZERO, kind: String = "bullet", headshot: bool = false) -> void:
		if destroyed or _detonating:
			return
		hp -= float(amount)
		if _screen_mat != null:
			_screen_mat.emission = Color(1.0, 0.2, 0.1)  # hit flash
		if hp <= 0.0:
			_detonate()

	func _detonate() -> void:
		_detonating = true
		destroyed = true
		if _body != null:
			var charred := StandardMaterial3D.new()
			charred.albedo_color = Color(0.08, 0.08, 0.09)
			_body.set_surface_override_material(0, charred)
		remove_from_group("enemies")
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("fuel_explosion"):
			scene.fuel_explosion(global_position + Vector3(0, 1.0, 0), 9.0, 130.0, self)

	func _build() -> void:
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.8, 0.15, 0.08)
		red.roughness = 0.4
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.9, 0.9, 0.88)
		white.roughness = 0.5
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.12, 0.12, 0.13)
		# Island base.
		_add_box(Vector3(1.4, 0.25, 1.4), Vector3(0, 0.12, 0), white)
		# Pump body.
		_body = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 1.5, 0.5)
		_body.mesh = bm
		_body.set_surface_override_material(0, red)
		_body.position = Vector3(0, 1.0, 0)
		add_child(_body)
		# Screen (glows; flashes red when hit).
		_screen_mat = StandardMaterial3D.new()
		_screen_mat.albedo_color = Color(0.05, 0.1, 0.15)
		_screen_mat.emission_enabled = true
		_screen_mat.emission = Color(0.2, 0.7, 1.0)
		_screen_mat.emission_energy_multiplier = 1.4
		var scr := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.4, 0.3, 0.04)
		scr.mesh = sm
		scr.set_surface_override_material(0, _screen_mat)
		scr.position = Vector3(0, 1.35, 0.27)
		add_child(scr)
		# Nozzle + hose.
		_add_box(Vector3(0.12, 0.3, 0.12), Vector3(0.42, 1.1, 0), dark)
		var hose := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.035
		hm.bottom_radius = 0.035
		hm.height = 1.0
		hose.mesh = hm
		hose.set_surface_override_material(0, dark)
		hose.position = Vector3(0.42, 0.6, 0)
		hose.rotation.z = 0.15
		add_child(hose)
		# "FUEL" tag.
		var tag := Label3D.new()
		tag.text = "FUEL"
		tag.font_size = 64
		tag.pixel_size = 0.008
		tag.modulate = Color(1.0, 0.6, 0.1)
		tag.outline_size = 8
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 1.95, 0)
		add_child(tag)
		# Collision.
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.9, 1.7, 0.7)
		cs.shape = bs
		cs.position = Vector3(0, 1.0, 0)
		add_child(cs)

	func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.set_surface_override_material(0, mat)
		mi.position = pos
		add_child(mi)


class StationBody extends StaticBody3D:
	# Canopy hitbox: forwards bullet damage to the station (underground tanks).
	var station = null  # FuelStation

	func _ready() -> void:
		add_to_group("enemies")
		collision_layer = 1
		collision_mask = 0

	func is_alive() -> bool:
		return station == null or not station.destroyed

	func take_damage(amount, from_pos: Vector3 = Vector3.ZERO, kind: String = "bullet", headshot: bool = false) -> void:
		if station != null:
			station.take_damage(amount, from_pos, kind, headshot)


func _ready() -> void:
	_build()


func is_alive() -> bool:
	return not destroyed


func take_damage(amount, from_pos: Vector3 = Vector3.ZERO, kind: String = "bullet", headshot: bool = false) -> void:
	# The station's underground tanks: shooting the canopy area can set it off.
	if destroyed:
		return
	hp -= float(amount)
	if hp <= 0.0:
		destroyed = true
		station_destroyed.emit(self)
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("fuel_explosion"):
			scene.fuel_explosion(global_position + Vector3(0, 2.0, 0), 13.0, 170.0, null)


func nearest_pump(pos: Vector3, max_d: float) -> FuelPump:
	var best: FuelPump = null
	var best_d := max_d
	for p in pumps:
		var fp: FuelPump = p
		if fp.destroyed:
			continue
		var d: float = pos.distance_to(fp.global_position)
		if d < best_d:
			best_d = d
			best = fp
	return best


func store_loot_spots() -> Array:
	return _store_spots


func _process(delta: float) -> void:
	_t += delta
	if _sign != null and not destroyed:
		# Subtle neon flicker on the brand sign.
		var f := 0.92 + 0.08 * sin(_t * 7.0) * sin(_t * 3.1)
		_sign.modulate = Color(1.0 * f, 0.55 * f, 0.1 * f)


func _build() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.42, 0.42, 0.44)
	concrete.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.16, 0.17, 0.19)
	steel.metallic = 0.6
	steel.roughness = 0.45
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(1.0, 0.45, 0.05)
	accent.emission_enabled = true
	accent.emission = Color(1.0, 0.45, 0.05)
	accent.emission_energy_multiplier = 1.6
	var roofmat := StandardMaterial3D.new()
	roofmat.albedo_color = Color(0.2, 0.21, 0.23)
	roofmat.roughness = 0.6
	# Forecourt pad.
	_add_box(Vector3(18, 0.2, 13), Vector3(0, 0.1, 0), concrete)
	# Canopy pillars + roof.
	for sx in [-6.5, 6.5]:
		for sz in [-4.5, 4.5]:
			_add_box(Vector3(0.45, 5.2, 0.45), Vector3(sx, 2.6, sz), steel)
	_add_box(Vector3(15, 0.35, 10.5), Vector3(0, 5.35, 0), roofmat)
	_add_box(Vector3(15.2, 0.5, 10.7), Vector3(0, 5.05, 0), accent)  # glowing brand band
	# NOVA FUEL sign, both faces.
	for ry in [0.0, PI]:
		var sign := Label3D.new()
		sign.text = "NOVA FUEL"
		sign.font_size = 128
		sign.pixel_size = 0.02
		sign.modulate = Color(1.0, 0.55, 0.1)
		sign.outline_size = 16
		sign.outline_modulate = Color(0, 0, 0, 0.9)
		sign.double_sided = true
		sign.position = Vector3(0, 6.3, 0)
		sign.rotation.y = ry
		add_child(sign)
		if ry == 0.0:
			_sign = sign
	var price := Label3D.new()
	price.text = "$4.20 / L"
	price.font_size = 64
	price.pixel_size = 0.015
	price.modulate = Color(0.4, 1.0, 0.5)
	price.outline_size = 10
	price.double_sided = true
	price.position = Vector3(0, 5.55, 5.28)
	add_child(price)
	# Exactly 3 pumps in a row.
	for i in range(3):
		var pump := FuelPump.new()
		pump.station = self
		add_child(pump)
		pump.position = Vector3(-4.5 + float(i) * 4.5, 0.2, 0)
		pumps.append(pump)
	# Night lighting under the canopy.
	for lx in [-4.0, 4.0]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.65)
		light.light_energy = 1.6
		light.omni_range = 13.0
		light.position = Vector3(lx, 4.8, 0)
		add_child(light)
	# Convenience store (enterable) beside the forecourt.
	_build_store(steel, concrete, accent)
	# Station hitbox so the canopy/tanks can be shot too (forwards to station).
	var area_cs := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(15, 6, 10.5)
	area_cs.shape = area_box
	area_cs.position = Vector3(0, 3.0, 0)
	var body := StationBody.new()
	body.station = self
	body.add_child(area_cs)
	add_child(body)


func _build_store(steel: Material, concrete: Material, accent: Material) -> void:
	# Small shop at x=+11.5: enterable through a door gap facing the pumps.
	var sx := 11.5
	var wallm := StandardMaterial3D.new()
	wallm.albedo_color = Color(0.75, 0.72, 0.66)
	wallm.roughness = 0.8
	var glassm := StandardMaterial3D.new()
	glassm.albedo_color = Color(0.1, 0.2, 0.3, 0.6)
	glassm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glassm.emission_enabled = true
	glassm.emission = Color(1.0, 0.8, 0.5)
	glassm.emission_energy_multiplier = 0.7
	# Floor + roof.
	_add_box(Vector3(7, 0.2, 5.5), Vector3(sx, 0.1, 0), concrete)
	_add_box(Vector3(7.4, 0.3, 5.9), Vector3(sx, 3.2, 0), steel)
	_add_box(Vector3(7.5, 0.4, 6.0), Vector3(sx, 2.95, 0), accent)
	# Walls: back + sides full; front split with a 1.6m door gap.
	_add_box(Vector3(7, 3.0, 0.25), Vector3(sx, 1.6, -2.6), wallm)   # back
	_add_box(Vector3(0.25, 3.0, 5.5), Vector3(sx - 3.4, 1.6, 0), wallm)  # left
	_add_box(Vector3(0.25, 3.0, 5.5), Vector3(sx + 3.4, 1.6, 0), wallm)  # right
	_add_box(Vector3(2.7, 3.0, 0.25), Vector3(sx - 2.15, 1.6, 2.6), wallm)  # front-left
	_add_box(Vector3(2.7, 3.0, 0.25), Vector3(sx + 2.15, 1.6, 2.6), wallm)  # front-right
	# Shop window (glowing) on the front.
	_add_box(Vector3(2.2, 1.2, 0.1), Vector3(sx - 2.15, 1.8, 2.62), glassm)
	# Interior: counter + shelves + warm light.
	var woodm := StandardMaterial3D.new()
	woodm.albedo_color = Color(0.4, 0.28, 0.16)
	_add_box(Vector3(2.4, 1.0, 0.7), Vector3(sx + 1.6, 0.7, -1.4), woodm)
	_add_box(Vector3(0.5, 1.8, 3.0), Vector3(sx - 2.6, 1.1, 0.4), steel)
	_add_box(Vector3(0.5, 1.8, 3.0), Vector3(sx - 1.8, 1.1, 0.4), steel)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.7)
	lamp.light_energy = 1.2
	lamp.omni_range = 8.0
	lamp.position = Vector3(sx, 2.8, 0)
	add_child(lamp)
	# Loot spots inside the store (world positions filled in by main.gd).
	_store_spots = [
		Vector3(sx - 2.2, 0.0, 0.4), Vector3(sx + 1.6, 0.0, -1.4),
		Vector3(sx + 0.5, 0.0, 1.5), Vector3(sx - 1.0, 0.0, -1.8),
	]


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	add_child(mi)
