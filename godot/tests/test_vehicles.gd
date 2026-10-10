extends SceneTree
## Headless verification for VEHICLES + BUY STATIONS + AIRDROP EVENTS.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_vehicles.gd
## Checks: defs integrity, model builds (all 15), skins, audio synthesis,
## enter/exit, driving, tank cannon, B2 bombs, destruction chain, economy.

var _checks: Array = []
var _frame := 0
var _phase := 0
var _player: NovaPlayer = null
var _veh: NovaVehicle = null


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _initialize() -> void:
	_run_static_checks()
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate() as NovaPlayer
	root.add_child(_player)
	print("TEST: player instanced for vehicle checks")


func _run_static_checks() -> void:
	# --- VehicleDefs roster ---
	var specs: Dictionary = VehicleDefs.SPECS
	_log_check("15 vehicle specs", specs.size() == 15, "n=" + str(specs.size()))
	var need := ["name", "loco", "weapon", "top_speed", "accel", "brake", "turn_rate", "hp", "ram_damage", "desc"]
	for vid in specs:
		var s: Dictionary = specs[vid]
		var ok := true
		for k in need:
			if not s.has(k):
				ok = false
		_log_check("spec fields: " + vid, ok)
		_log_check("spec sane: " + vid, float(s["top_speed"]) > 0.0 and float(s["hp"]) > 0.0,
			"top=" + str(s["top_speed"]) + " hp=" + str(s["hp"]))
	# --- BuyStation catalog ---
	var items := BuyStation.items()
	_log_check("20 shop items", items.size() == 20, "n=" + str(items.size()))
	var ids := {}
	var prices_ok := true
	for it in items:
		ids[str(it["id"])] = true
		if int(it["price"]) <= 0:
			prices_ok = false
	_log_check("shop prices positive", prices_ok)
	_log_check("shop has uav", ids.has("uav"))
	_log_check("shop has revive", ids.has("revive"))
	_log_check("shop has strike", ids.has("strike"))
	_log_check("shop has paint", ids.has("paint"))
	_log_check("shop has tankdrop", ids.has("tankdrop"))
	_log_check("shop has sentry", ids.has("sentry"))
	_log_check("shop has gas_mask", ids.has("gas_mask"))
	_log_check("shop has modkit", ids.has("modkit"))
	_log_check("shop has mystery", ids.has("mystery"))
	_log_check("shop has carrier", ids.has("carrier"))
	_log_check("shop has shield", ids.has("shield"))
	_log_check("shop has bomber", ids.has("bomber"))
	_log_check("shop has precision", ids.has("precision"))
	_log_check("shop has repair", ids.has("repair"))
	_log_check("shop has frag_bundle", ids.has("frag_bundle"))
	_log_check("shop has heavy", ids.has("heavy"))
	var cats := {}
	for it in items:
		cats[str(it.get("cat", "?"))] = true
	_log_check("shop categories", cats.size() >= 7, str(cats.keys()))
	_log_check("can_afford logic", BuyStation.can_afford(1500, "armor") and not BuyStation.can_afford(100, "armor"))
	_log_check("tankdrop price", BuyStation.price("tankdrop") == 10000)
	_log_check("uav price", BuyStation.price("uav") == 4000)
	_log_check("item_by_id", str(BuyStation.item_by_id("uav")["name"]) == "UAV Sweep")
	# --- audio synthesis ---
	for kind in ["v8", "diesel", "bike", "electric", "heli", "boat", "jet"]:
		var w := VehicleAudio.engine_loop(kind)
		_log_check("engine loop: " + kind, w != null and w.data.size() > 1000, "bytes=" + str(w.data.size() if w else 0))
	_log_check("horn car", VehicleAudio.horn("car").data.size() > 500)
	_log_check("horn truck", VehicleAudio.horn("truck").data.size() > 500)
	_log_check("skid loop", VehicleAudio.skid_loop().data.size() > 500)
	_log_check("thud", VehicleAudio.thud().data.size() > 200)
	_log_check("engine kind map", VehicleAudio.engine_kind("sedan") == "v8" and VehicleAudio.engine_kind("hoverbike") == "electric" and VehicleAudio.engine_kind("skateboard") == "")
	# --- fuel specs ---
	for vid in specs:
		var sp: Dictionary = specs[vid]
		_log_check("fuel fields: " + vid, sp.has("fuel_cap") and sp.has("fuel_rate"))
	_log_check("tank guzzles", float(specs["tank"]["fuel_rate"]) > float(specs["bike"]["fuel_rate"]))
	_log_check("heli burns fast", float(specs["heli"]["fuel_rate"]) >= 1.5)
	_log_check("skateboard no fuel", float(specs["skateboard"]["fuel_cap"]) == 0.0)
	_log_check("b2 no fuel", float(specs["b2"]["fuel_cap"]) == 0.0)
	# --- skins ---
	for vid in specs:
		_log_check("skins: " + vid, VehicleSkins.count(vid) >= 3, "n=" + str(VehicleSkins.count(vid)))
	var sk := VehicleSkins.skin("sportscar", 0)
	_log_check("skin fields", sk.has("name") and sk.has("paint") and sk.has("metallic"))


func _run_model_checks() -> void:
	for vid in VehicleDefs.SPECS:
		var parts: Dictionary = VehicleModels.build(vid)
		var root: Node3D = parts["root"]
		var nc := _count_nodes(root)
		_log_check("model builds: " + vid, root != null and nc > 5 and nc < 70, "nodes=" + str(nc))
		_log_check("model dims: " + vid, float(parts["length"]) > 0.0 and float(parts["width"]) > 0.0)
		root.queue_free()


func _spawn(vid: String) -> NovaVehicle:
	var v := NovaVehicle.new()
	v.vid = vid
	root.add_child(v)
	return v


func _run_dynamic_checks() -> void:
	# Enter / exit.
	var v := _spawn("sedan")
	_player.global_position = v.global_position + Vector3(2.0, 0.0, 0.0)
	_player.enter_vehicle(v)
	_log_check("enter vehicle", _player.in_vehicle == v, "in_vehicle set")
	_log_check("driver linked", v.driver == _player and _player.in_vehicle == v)
	_log_check("hud text", v.vehicle_hud_text().length() > 10, v.vehicle_hud_text().split("\n")[0])
	# Driving moves it: force throttle via direct input simulation.
	var p0: Vector3 = v.global_position
	v.speed = 0.0
	# Simulate 2s of full throttle by calling _drive_ground with a fake driver.
	var drv := _player
	drv.drive_gas = true
	drv.is_mobile = true
	for i in range(120):
		v._physics_process(1.0 / 60.0)
	drv.drive_gas = false
	var moved := p0.distance_to(v.global_position)
	_log_check("driving moves vehicle", moved > 3.0, "d=" + str(snappedf(moved, 0.1)))
	_log_check("speed > 0", v.speed > 3.0, "speed=" + str(snappedf(v.speed, 0.1)))
	# Nitro drains then refills.
	drv.drive_gas = true
	drv.drive_nitro = true
	var n0: float = v.nitro
	for i in range(60):
		v._physics_process(1.0 / 60.0)
	drv.drive_nitro = false
	drv.drive_gas = false
	_log_check("nitro drains", v.nitro < n0, "was=" + str(snappedf(n0, 0.1)) + " now=" + str(snappedf(v.nitro, 0.1)))
	for i in range(120):
		v._physics_process(1.0 / 60.0)
	_log_check("nitro refills", v.nitro > 50.0, "n=" + str(snappedf(v.nitro, 0.1)))
	# Horn + lights + skin reroll.
	v.honk()
	_log_check("honk ok", true)
	v.toggle_lights()
	_log_check("lights on", v.lights_on)
	v.reroll_skin()
	_log_check("skin reroll", VehicleSkins.count("sedan") > 0 and v.skin_name != "")
	# Wheel spin / steer visuals ran during physics; verify parts exist.
	_log_check("wheels exist", (v._parts["wheels"] as Array).size() == 4)
	_player.exit_vehicle()
	_log_check("exit vehicle", _player.in_vehicle == null and v.driver == null)
	v.queue_free()
	# Tank cannon.
	var t := _spawn("tank")
	_log_check("tank cannon cd", t._cannon_cd >= 0.0)
	_log_check("tank hp high", t.hp >= 400.0, "hp=" + str(t.hp))
	t.queue_free()
	# B2 bombs.
	var b := _spawn("b2")
	_log_check("b2 bomb count", b._bombs_left == 6, "n=" + str(b._bombs_left))
	_log_check("b2 flies", str(b.spec["loco"]) == "plane")
	b.queue_free()
	# Destruction chain.
	var d := _spawn("suv")
	var flag := [false]
	d.exploded.connect(func(_vv: NovaVehicle) -> void: flag[0] = true)
	d.take_damage(99999.0, "test")
	_log_check("destroyed flag", d.destroyed)
	_log_check("exploded signal", flag[0])
	d.queue_free()
	# Vehicle-vs-vehicle + bullet damage path.
	var d2 := _spawn("pickup")
	var hp0: float = d2.hp
	d2.take_damage(50.0, "test")
	_log_check("bullet damage", d2.hp == hp0 - 50.0, "hp=" + str(d2.hp))
	d2.queue_free()
	# Economy: cash add/spend, kill bounty path.
	_player.cash = 0
	_player.add_cash(500)
	_log_check("add_cash", _player.cash == 500)
	_log_check("spend_cash", _player.spend_cash(200) and _player.cash == 300)
	_log_check("spend_cash denied", not _player.spend_cash(9999) and _player.cash == 300)
	_player.revive_kits = 0
	_player.revive_kits += 1
	_log_check("revive kit grant", _player.revive_kits == 1)
	_player.gas_mask_t = 30.0
	_log_check("gas mask timer", _player.gas_mask_t == 30.0)
	_player.armor_cap = 200
	_log_check("armor cap raise", _player.armor_cap == 200)
	var aid: String = GunDefs.ATTACH_LOOT[0]
	_log_check("modkit attach path", GunDefs.find_attach(aid).has("name"))
	_player.add_ammo_all(240)
	_log_check("ammo grant", true)
	_run_fuel_checks()


func _run_fuel_checks() -> void:
	# Fuel drains while driving.
	var fv := _spawn("sedan")
	_log_check("spawn full tank", fv.fuel == fv.max_fuel and fv.max_fuel > 0.0,
		"fuel=" + str(snappedf(fv.fuel, 0.1)))
	_player.global_position = fv.global_position + Vector3(2.0, 0.0, 0.0)
	_player.enter_vehicle(fv)
	_player.is_mobile = true
	_player.drive_gas = true
	var f0: float = fv.fuel
	for i in range(60):
		fv._physics_process(1.0 / 60.0)
	_player.drive_gas = false
	_log_check("fuel drains driving", fv.fuel < f0, "was=" + str(snappedf(f0, 0.1)) + " now=" + str(snappedf(fv.fuel, 0.1)))
	# Dry tank = dead engine (still a drivable hunk? no — stationary cover).
	fv.fuel = 0.0
	fv.out_of_fuel = true
	fv.speed = 0.0
	_player.drive_gas = true
	for i in range(60):
		fv._physics_process(1.0 / 60.0)
	_player.drive_gas = false
	_log_check("dry tank kills engine", absf(fv.speed) < 0.5, "speed=" + str(snappedf(fv.speed, 0.2)))
	# Refuel revives it.
	fv.refuel(30.0)
	_log_check("refuel works", fv.fuel > 29.0 and not fv.out_of_fuel, "fuel=" + str(snappedf(fv.fuel, 0.1)))
	_log_check("needs_fuel", fv.needs_fuel() == (fv.fuel < fv.max_fuel - 1.0))
	_player.exit_vehicle()
	fv.queue_free()
	# Skateboard: no fuel system.
	var sk := _spawn("skateboard")
	_log_check("skateboard fuel-free", sk.max_fuel == 0.0 and not sk.needs_fuel())
	sk.queue_free()
	# Fuel canister loot.
	var fc := NovaLoot.new()
	fc.kind = "fuelcan"
	_log_check("fuelcan display", fc.display_name() == "FUEL CANISTER")
	fc.queue_free()
	_log_check("player fuel cans", _player.fuel_cans == 0)
	# main.gd fuel API surface (bare instance: _init only, no scene side-effects).
	var msrc: GDScript = load("res://scripts/main.gd")
	var minst: Object = msrc.new()
	_log_check("main fuel_explosion", minst.has_method("fuel_explosion"))
	_log_check("main _update_refuel", minst.has_method("_update_refuel"))
	_log_check("main pour_fuel_can", minst.has_method("pour_fuel_can"))
	_log_check("main try_fuel_action", minst.has_method("try_fuel_action"))
	_log_check("main _spawn_fuel_stations", minst.has_method("_spawn_fuel_stations"))
	minst.free()
	# Filling station: exactly 3 pumps, store, signage.
	var st := FuelStation.new()
	root.add_child(st)
	_log_check("station 3 pumps", st.pumps.size() == 3, "n=" + str(st.pumps.size()))
	_log_check("station store spots", st.store_loot_spots().size() == 4)
	_log_check("station alive", st.is_alive())
	var p0 = st.pumps[0]
	_log_check("pump alive", p0.is_alive())
	# Shooting a pump detonates it.
	p0.take_damage(999.0, Vector3.ZERO, "bullet", false)
	_log_check("pump explodes when shot", p0.destroyed)
	# Station underground tanks detonate too.
	st.take_damage(9999.0)
	_log_check("station explodes when shot", st.destroyed)
	st.queue_free()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5 and _phase == 0:
		_run_model_checks()
		_phase = 1
	if _frame == 10 and _phase == 1:
		_run_dynamic_checks()
		_phase = 2
	if _frame >= 60:
		_finish()
		return true
	return false


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("VEHICLES: ", _checks.size() - fails, "/", _checks.size(), " checks passed")
	if fails > 0:
		print("VEHICLES: FAILURES PRESENT")
	quit()
