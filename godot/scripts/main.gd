extends Node3D
## NOVA Mobile: main game — instances the Makoko map scene, spawns actors,
## runs the Collapse zone, loot pickups, HUD wiring, and quality scaling.

const MakokoScene: PackedScene = preload("res://scenes/makoko.tscn")
const LekkiScene: PackedScene = preload("res://scenes/lekki.tscn")
const ComputerVillageScene: PackedScene = preload("res://scenes/computervillage.tscn")
const BananaIslandScene: PackedScene = preload("res://scenes/bananaisland.tscn")
const ValleyCombatScene: PackedScene = preload("res://scenes/valleycombat.tscn")
const BarracksScene: PackedScene = preload("res://scenes/barracks.tscn")
const TrainStationScene: PackedScene = preload("res://scenes/trainstation.tscn")
const AirportScene: PackedScene = preload("res://scenes/airport.tscn")
const LagoonBridgeScene: PackedScene = preload("res://scenes/lagoonbridge.tscn")
const ShipPortScene: PackedScene = preload("res://scenes/shipport.tscn")
const AirbaseScene: PackedScene = preload("res://scenes/airbase.tscn")
const WorldScene: PackedScene = preload("res://scenes/world.tscn")
const DowntownScene: PackedScene = preload("res://scenes/downtown.tscn")
const DamScene: PackedScene = preload("res://scenes/dam.tscn")
const StadiumScene: PackedScene = preload("res://scenes/stadium.tscn")
const PlayerScene: PackedScene = preload("res://scenes/player.tscn")
const EnemyScene: PackedScene = preload("res://scenes/enemy.tscn")
const LootScene: PackedScene = preload("res://scenes/loot.tscn")
const AllyScene: PackedScene = preload("res://scenes/ally.tscn")
const GunPickupScene: PackedScene = preload("res://scenes/gun_pickup.tscn")
const MAP_NAMES := ["MAKOKO — Floating Village", "LEKKI — Admiralty Streets",
	"COMPUTER VILLAGE — Ikeja Tech Market", "BANANA ISLAND — Luxury Waterfront",
	"VALLEY COMBAT — Wilderness Zone", "BARRACKS — Cantonment",
	"TRAIN STATION — Ebute Metta", "AIRPORT — Helicopter Wing",
	"LAGOON BRIDGE — Third Mainland",
	"SHIP PORT — Apapa",
	"AIRBASE — Stealth Wing",
	"NOVA WORLD — Battle Royale",
	"DOWNTOWN — Nova Towers",
	"DAM — Reservoir",
	"STADIUM — National Stadium"]

## Selectable default characters (SoldierRig variant indices).
const CHAR_NAMES := ["SENTINEL — Masked Operator", "BREACHER — Bare-Faced Shotgunner"]
const CHAR_DESCS := ["Digital-camo helmet · red-lens goggles · white balaclava",
	"Tan cap · visible face · red shell rig"]
const CHAR_VARIANTS := [5, 6]
var _char_idx := 5  # SoldierRig variant for the player (default: Sentinel)
var _class_id := "pathfinder"  # ClassDefs id from the class-select screen

var map  # MakokoMap / LekkiMap (untyped: not in editor class cache for headless runs)
var _map_idx := 0
var _headless_map := 0  # set on the instance before add_child in headless tests to pick the map
var map_extent := 70.0
var player: NovaPlayer
var enemies: Array = []
var loots: Array = []
var hud: CanvasLayer
var time_alive := 0.0

# Collapse (battle royale zone).
var zone_center := Vector2.ZERO
var zone_radius := 70.0
var next_center := Vector2.ZERO
var next_radius := 70.0
var _phase := 0
var _phase_state := "wait"
var _phase_timer := 0.0
var _shrink_from := 70.0
var _shrink_from_c := Vector2.ZERO
var _zone_acc := 0.0
const PHASES := [
	{"wait": 25.0, "shrink": 30.0, "radius": 44.0},
	{"wait": 18.0, "shrink": 25.0, "radius": 26.0},
	{"wait": 14.0, "shrink": 20.0, "radius": 12.0},
	{"wait": 12.0, "shrink": 15.0, "radius": 3.0},
]
const ZONE_DPS := [2, 5, 10, 16]
# World-scale battle royale zone (NOVA WORLD).
const WORLD_PHASES := [
	{"wait": 45.0, "shrink": 60.0, "radius": 300.0},
	{"wait": 35.0, "shrink": 50.0, "radius": 190.0},
	{"wait": 30.0, "shrink": 45.0, "radius": 110.0},
	{"wait": 25.0, "shrink": 40.0, "radius": 55.0},
	{"wait": 20.0, "shrink": 30.0, "radius": 25.0},
	{"wait": 15.0, "shrink": 25.0, "radius": 3.0},
]
const WORLD_DPS := [2, 4, 8, 12, 16, 20]
var _world_mode := false
var _phases: Array = PHASES
var _dps: Array = ZONE_DPS
var _airdrop_timer := 75.0
var _airdrops: Array = []  # {"node","smoke","landed"}
var _airdrop_warned := false
var _pending_drops: Array = []  # Vector3 list, planned at warning time
var game_over := false
var kills := 0
# Vehicles + economy.
var vehicles: Array = []      # NovaVehicle
var buy_stations: Array = []  # BuyStation
var _e_held := false
var _v_held := false
var _l_held := false
var _near_vehicle: NovaVehicle = null
var _near_station: BuyStation = null
var fuel_stations: Array = []  # FuelStation
var _refuel_pump = null
var _f_held := false

var allies: Array = []          # NovaAlly squadmates
var squadman: SquadManager = null  # 25 x 4 combatant registry (world BR mode)
var _ally_revive_t := {}  # NovaAlly -> float (player revive channel)
var _pings: Array = []          # active LootPing markers
var _loot_audio_pool: Array = []
var _loot_audio_idx := 0
var _tap_last_t := -1.0
var _tap_last_pos := Vector2.ZERO

var _menu: CanvasLayer
var _match_started := false
var _settings_menu: SettingsMenu = null

var _zone_wall: MeshInstance3D
var _zone_mat: ShaderMaterial
var _impact_mesh: SphereMesh


func _ready() -> void:
	randomize()
	ControlSettings.load_all()
	_impact_mesh = SphereMesh.new()
	_impact_mesh.radius = 0.06
	_impact_mesh.height = 0.12
	$HUD.visible = false
	if DisplayServer.get_name() == "headless":
		# Headless runs (tests) skip the menu and go straight in.
		start_match(_headless_map)
	else:
		_show_map_menu()


func _show_map_menu() -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 20
	add_child(_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	var title := Label.new()
	title.text = "NOVA MOBILE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "BATTLE ROYALE — SELECT MAP"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vb.add_child(sub)
	for i in range(MAP_NAMES.size()):
		var b := Button.new()
		b.text = MAP_NAMES[i]
		b.custom_minimum_size = Vector2(440, 64)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(_on_map_button.bind(i))
		vb.add_child(b)
	var sb := Button.new()
	sb.text = "⚙  SETTINGS"
	sb.custom_minimum_size = Vector2(440, 56)
	sb.add_theme_font_size_override("font_size", 24)
	sb.add_theme_color_override("font_color", Color(1.0, 0.60, 0.12))
	sb.pressed.connect(open_settings)
	vb.add_child(sb)
	var stb := Button.new()
	stb.text = "🛒  STORE  ·  ◈ %d NP" % StoreWallet.balance()
	stb.custom_minimum_size = Vector2(440, 56)
	stb.add_theme_font_size_override("font_size", 24)
	stb.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	stb.pressed.connect(_open_store)
	vb.add_child(stb)


func _open_store() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_menu = StoreMenu.new()
	add_child(_menu)
	_menu.closed.connect(_on_store_closed)


func _on_store_closed() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_show_map_menu()


func _on_map_button(idx: int) -> void:
	_map_idx = idx
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_show_character_menu()


func _show_character_menu() -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 20
	add_child(_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	var title := Label.new()
	title.text = "NOVA MOBILE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "SELECT YOUR SOLDIER"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vb.add_child(sub)
	for i in range(CHAR_NAMES.size()):
		var b := Button.new()
		b.text = CHAR_NAMES[i] + "\n" + CHAR_DESCS[i]
		b.custom_minimum_size = Vector2(520, 92)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_on_character_button.bind(i))
		vb.add_child(b)


func _on_character_button(i: int) -> void:
	_char_idx = CHAR_VARIANTS[i]
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_show_class_menu()


func _show_class_menu() -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 20
	add_child(_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	cc.add_child(vb)
	var title := Label.new()
	title.text = "NOVA MOBILE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "SELECT YOUR CLASS"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vb.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 420)
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for c in ClassDefs.CLASSES:
		var b := Button.new()
		var pc: Color = ClassDefs.PROFESSION_COLORS[str(c["profession"])]
		b.text = "%s\n[%s] %s (%ds)" % [str(c["name"]), ClassDefs.PROFESSION_NAMES[str(c["profession"])], str(c["active"]), int(c["cooldown"])]
		b.tooltip_text = "%s\nPassive: %s — %s" % [str(c["active_desc"]), str(c["passive"]), str(c["passive_desc"])]
		b.custom_minimum_size = Vector2(300, 76)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", pc)
		b.pressed.connect(_on_class_button.bind(str(c["id"])))
		grid.add_child(b)


func _on_class_button(cid: String) -> void:
	_class_id = cid
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_show_gunsmith_menu()


## Gunsmith: pick primary gun, mythic skin, attachments. Then drop-in.
var _gs_gun := "m5"
var _gs_skin := 0
var _gs_attach: Array = []


func _show_gunsmith_menu() -> void:
	_menu = GunsmithMenu.new()
	_menu.layer = 20
	add_child(_menu)
	_menu.deployed.connect(_on_gunsmith_deployed)


func _on_gunsmith_deployed(gid: String, skin: int, attach: Array) -> void:
	_gs_gun = gid
	_gs_skin = skin
	_gs_attach = attach.duplicate()
	if _menu != null:
		_menu.queue_free()
		_menu = null
	start_match(_map_idx)


func start_match(idx: int) -> void:
	_map_idx = idx
	$HUD.visible = true
	if idx == 0:
		map = MakokoScene.instantiate()
	elif idx == 1:
		map = LekkiScene.instantiate()
	elif idx == 2:
		map = ComputerVillageScene.instantiate()
	elif idx == 3:
		map = BananaIslandScene.instantiate()
	elif idx == 4:
		map = ValleyCombatScene.instantiate()
	elif idx == 5:
		map = BarracksScene.instantiate()
	elif idx == 6:
		map = TrainStationScene.instantiate()
	elif idx == 7:
		map = AirportScene.instantiate()
	elif idx == 8:
		map = LagoonBridgeScene.instantiate()
	elif idx == 9:
		map = ShipPortScene.instantiate()
	elif idx == 10:
		map = AirbaseScene.instantiate()
	elif idx == 11:
		map = WorldScene.instantiate()
	elif idx == 12:
		map = DowntownScene.instantiate()
	elif idx == 13:
		map = DamScene.instantiate()
	elif idx == 14:
		map = StadiumScene.instantiate()
	else:
		map = ValleyCombatScene.instantiate()
	add_child(map)
	map_extent = map.map_extent
	_world_mode = (idx == 11)
	_phases = WORLD_PHASES if _world_mode else PHASES
	_dps = WORLD_DPS if _world_mode else ZONE_DPS
	if _world_mode:
		zone_radius = 430.0
		next_radius = 430.0
		_phase_timer = float(WORLD_PHASES[0]["wait"])
	else:
		_phase_timer = float(PHASES[0]["wait"])
	_build_zone_wall()
	_spawn_player()
	_spawn_enemies()
	_spawn_loot()
	_spawn_guns()
	_spawn_vehicles()
	_spawn_buy_stations()
	_spawn_cash()
	_spawn_fuel_stations()
	_spawn_fuel_cans()
	_spawn_loot_containers()
	_spawn_supply_crates()
	_spawn_allies()
	_spawn_squads()
	_setup_hud()
	apply_quality(1)
	_match_started = true


func _snap_to_ground(p: Vector3, lift: float) -> Vector3:
	# Terrain maps (Valley Combat) expose ground_height(x, z); flat maps don't.
	# Sampling here makes spawning work for any future terrain map too.
	if map != null and map.has_method("ground_height"):
		return Vector3(p.x, map.ground_height(p.x, p.z) + lift, p.z)
	return p


func _spawn_player() -> void:
	player = PlayerScene.instantiate() as NovaPlayer
	player.char_variant = _char_idx  # from the character-select screen
	player.class_id = _class_id  # from the class-select screen
	player.set_starting_primary(_gs_gun, _gs_skin, _gs_attach)  # gunsmith
	var pcs := ClassSystem.new()
	pcs.name = "ClassSystem"
	player.add_child(pcs)
	pcs.setup(player, _class_id, true)
	player.class_sys = pcs
	if _world_mode and map.poi_list.size() > 0:
		# Battle royale drop-in: skydive above a random POI.
		var poi: Dictionary = map.poi_list[randi() % map.poi_list.size()]
		var pp: Vector3 = poi["pos"]
		player.position = Vector3(pp.x + randf_range(-15.0, 15.0), 170.0, pp.z + randf_range(-15.0, 15.0))
		add_child(player)
		player.dropping = true
		player.show_chute(true)
	else:
		player.position = _snap_to_ground(map.player_spawn, 0.6)
		add_child(player)
	player.died.connect(_on_player_died)


func _spawn_enemies() -> void:
	if _world_mode:
		_spawn_br_squads()  # 96 hostile bots in 24 squads of 4
		return
	for sp in map.enemy_spawns:
		_spawn_enemy_at(sp)


## Spawn one hostile bot at a position (single-map modes).
func _spawn_enemy_at(sp: Vector3) -> void:
	var e := EnemyScene.instantiate() as NovaEnemy
	e.allow_respawn = not _world_mode  # BR world: dead stays dead (last-one-standing)
	add_child(e)
	var esp: Vector3 = _snap_to_ground(sp, 0.6)
	e.position = esp
	e.home_position = esp
	# Carried gun: visible on the rig, dropped in the death box.
	var erng := RandomNumberGenerator.new()
	erng.seed = 777 + enemies.size()
	e.carry_gun_id = GunDefs.roll_gun(1 + erng.randi() % 3, erng)
	e.carry_gun_tier = 1 + erng.randi() % 3
	var wm := GunModels.build_world_model(e.carry_gun_id)
	wm.scale = Vector3.ONE * 0.9
	e.rig().attach_to_bone("Weapon", wm)
	# AI enemies get classes too (simple ability usage).
	var ecid: String = ClassDefs.ids()[randi() % ClassDefs.count()]
	var ecs := ClassSystem.new()
	ecs.name = "ClassSystem"
	e.add_child(ecs)
	ecs.setup(e, ecid, false)
	e.class_sys = ecs
	e.class_id = ecid
	e.killed.connect(_on_enemy_killed)
	enemies.append(e)


## Battle royale drop: 24 hostile squads x 4 bots = 96, spread across the
## world like a real drop. Names/identities are assigned by the SquadManager.
func _spawn_br_squads() -> void:
	var bases: Array = []
	for sp in map.enemy_spawns:
		bases.append(sp)
	for p in map.poi_list:
		if bases.size() >= 24:
			break
		bases.append(p["pos"])
	while bases.size() < 24:
		var refb: Vector3 = bases[bases.size() % 24] if not bases.is_empty() else Vector3.ZERO
		bases.append(refb + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30)))
	var srng := RandomNumberGenerator.new()
	srng.seed = 31337
	for sq in range(24):
		var base: Vector3 = bases[sq % bases.size()]
		for slot in range(4):
			var off := Vector3(srng.randf_range(-8, 8), 0, srng.randf_range(-8, 8))
			_spawn_enemy_at(base + off)


func _spawn_loot() -> void:
	for spec in map.loot_spots:
		var l := LootScene.instantiate() as NovaLoot
		# Set kind/tier BEFORE add_child so _ready builds the right material.
		l.kind = spec[0]
		l.amount = spec[1]
		if spec.size() > 3:
			l.tier = int(spec[3])
		add_child(l)
		l.position = _snap_to_ground(spec[2], 0.55)
		loots.append(l)


func get_player_spawn() -> Vector3:
	return map.player_spawn


## Spawn gun pickups across the map: tier-weighted, sampled from loot spots.
func _spawn_guns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010 + _map_idx
	var spots: Array = map.loot_spots
	if spots.is_empty():
		return
	var count := mini(56, maxi(12, spots.size() / 6))
	var used := {}
	for i in range(count):
		var idx := rng.randi() % spots.size()
		if used.has(idx):
			continue
		used[idx] = true
		var spec: Array = spots[idx]
		var tier := int(spec[3]) if spec.size() > 3 else 0
		# 8% of gun spawns are attachment pickups instead.
		if rng.randf() < 0.08:
			var gp := GunPickupScene.instantiate() as GunPickup
			gp.attach_id = GunDefs.ATTACH_LOOT[rng.randi() % GunDefs.ATTACH_LOOT.size()]
			add_child(gp)
			gp.position = _snap_to_ground(spec[2], 0.4)
			continue
		var gid := GunDefs.roll_gun(tier, rng)
		var gp2 := GunPickupScene.instantiate() as GunPickup
		gp2.gun_id = gid
		gp2.tier = tier
		add_child(gp2)
		var off := Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
		gp2.position = _snap_to_ground(spec[2] + off, 0.4)


## Explosion FX for launcher projectiles.
func spawn_explosion(pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 4.0
	light.omni_range = radius * 3.0
	light.position = pos + Vector3(0, 1.0, 0)
	add_child(light)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 1.6, 0.35)
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)
	tw.tween_callback(light.queue_free)


func _setup_hud() -> void:
	hud = $HUD
	hud.player = player
	hud.enemies = enemies
	hud.zone_center = zone_center
	hud.zone_radius = zone_radius
	hud.next_center = next_center
	hud.next_radius = next_radius
	hud.world_mode = _world_mode
	if _world_mode:
		hud.world_extent = 345.0
		var ml = map.get("map_labels")
		hud.map_labels = ml if ml != null else []
	player.ammo_changed.connect(hud.update_ammo)
	player.health_changed.connect(hud.update_health)
	player.weapon_changed.connect(hud.update_weapon)
	player.refresh_weapon_hud()
	player.hit_confirmed.connect(_on_hit_confirmed)
	hud.allies = allies
	hud.update_score(0, enemies.size())


func _on_hit_confirmed(kill: bool) -> void:
	hud.show_hitmarker(kill)
	hud.notify_fired()


func on_enemy_damaged(_collider: Node, _was_alive: bool) -> void:
	# Hitmarker is driven by hit_confirmed; kept for API compatibility.
	pass


func on_loot_taken(kind: String) -> void:
	hud.add_killfeed("Picked up " + kind)


func spawn_impact(point: Vector3, n: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _impact_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.4)
	mi.material_override = mat
	mi.position = point + n * 0.05
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.5, 0.18)
	tw.tween_callback(mi.queue_free)


# --- pooled blood spray (CODM-style, tasteful) ---
var _blood_pool: Array = []
const BLOOD_POOL_N := 8


func _blood_puff() -> CPUParticles3D:
	for p in _blood_pool:
		if not (p as CPUParticles3D).emitting:
			return p
	if _blood_pool.size() >= BLOOD_POOL_N:
		return _blood_pool[0]
	var cp := CPUParticles3D.new()
	cp.amount = 14
	cp.one_shot = true
	cp.explosiveness = 0.85
	cp.lifetime = 0.5
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cp.emission_sphere_radius = 0.08
	cp.direction = Vector3(0, 0.6, 0)
	cp.spread = 45.0
	cp.initial_velocity_min = 1.2
	cp.initial_velocity_max = 3.2
	cp.gravity = Vector3(0, -9.0, 0)
	cp.scale_amount_min = 0.05
	cp.scale_amount_max = 0.12
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.55, 0.05, 0.05, 0.9)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = bmat
	cp.draw_pass_1 = quad
	cp.emitting = false
	add_child(cp)
	_blood_pool.append(cp)
	return cp


func spawn_blood(point: Vector3, dir: Vector3) -> void:
	var cp := _blood_puff()
	cp.global_position = point
	var d := dir
	d.y = 0.35
	cp.direction = d.normalized() if d.length() > 0.01 else Vector3(0, 0.6, 0)
	cp.restart()


func _build_zone_wall() -> void:
	var shader := load("res://shaders/zone_wall.gdshader") as Shader
	_zone_mat = ShaderMaterial.new()
	_zone_mat.shader = shader
	_zone_wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 40.0
	cyl.radial_segments = 48
	_zone_wall.mesh = cyl
	_zone_wall.material_override = _zone_mat
	_zone_wall.position = Vector3(0, 12, 0)
	add_child(_zone_wall)


func _process(delta: float) -> void:
	if not _match_started or game_over:
		return
	time_alive += delta
	_update_zone(delta)
	_update_zone_wall()
	hud.update_match_time(time_alive)
	if _world_mode:
		_update_airdrops(delta)
		_update_squad_revives(delta)
	_update_interact()
	_update_refuel(delta)
	_update_veh_minimap()


## The player revives downed teammates by standing close (5 s channel).
func _update_squad_revives(delta: float) -> void:
	if player == null or not player.is_alive() or player.downed:
		_ally_revive_t.clear()
		return
	for a in allies:
		if not is_instance_valid(a) or not a.is_alive() or not a.is_downed():
			_ally_revive_t.erase(a)
			continue
		var d: float = player.global_position.distance_to(a.global_position)
		if d < 2.5:
			var t: float = float(_ally_revive_t.get(a, 0.0)) + delta
			_ally_revive_t[a] = t
			hud.show_hint("REVIVING %s… %.0f%%" % [str(a.bot_name), t / 5.0 * 100.0])
			if t >= 5.0:
				a.revive_ally()
				_ally_revive_t.erase(a)
				hud.show_hint("")
				hud.add_killfeed("%s revived" % str(a.bot_name))
		else:
			_ally_revive_t.erase(a)



func _update_airdrops(delta: float) -> void:
	_airdrop_timer -= delta
	if _airdrop_timer <= 12.0 and not _airdrop_warned:
		_airdrop_warned = true
		_plan_drops()  # warning banner 12s before the plane arrives
	if _airdrop_timer <= 0.0:
		_airdrop_warned = false
		_airdrop_timer = 80.0
		for pos in _pending_drops:
			_launch_drop(pos)
		_pending_drops.clear()
	for ad in _airdrops:
		if bool(ad["landed"]):
			continue
		var n: Node3D = ad["node"]
		n.position.y -= 14.0 * delta
		var gy: float = _snap_to_ground(Vector3(n.position.x, 0.0, n.position.z), 0.0).y
		if n.position.y <= gy + 0.9:
			n.position.y = gy + 0.9
			ad["landed"] = true
			var chute: Node3D = ad.get("chute")
			if chute != null and is_instance_valid(chute):
				chute.queue_free()  # canopy collapses on landing
			_dust_burst(n.position)
			if str(ad.get("payload", "loot")) == "tank":
				_spawn_dropped_tank(n.position)
			else:
				_burst_airdrop_loot(n.position)
			var smoke: Node3D = ad["smoke"]
			var tw := create_tween()
			tw.tween_interval(60.0)
			tw.tween_callback(smoke.queue_free)


func _dust_burst(pos: Vector3) -> void:
	# Quick expanding dust ring when the crate slams down.
	var dust := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 1.0
	dm.height = 1.4
	dust.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.75, 0.68, 0.55, 0.55)
	dust.set_surface_override_material(0, dmat)
	dust.position = pos + Vector3(0, 0.7, 0)
	add_child(dust)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dust, "scale", Vector3(6.0, 1.6, 6.0), 0.7)
	tw.tween_property(dmat, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(dust.queue_free)


func _burst_airdrop_loot(pos: Vector3) -> void:
	var kinds := ["health", "armor", "ammo"]
	var amounts := [100, 100, 120]
	for i in range(3):
		var l := LootScene.instantiate() as NovaLoot
		l.kind = kinds[i]
		l.amount = amounts[i]
		l.tier = 5
		add_child(l)
		var ang := TAU * float(i) / 3.0
		l.position = _snap_to_ground(pos + Vector3(cos(ang) * 2.5, 0.0, sin(ang) * 2.5), 0.55)
		loots.append(l)
	# Airdrops always pack a heavy weapon — usually the RP-7.
	var gid := "rp7" if randf() < 0.6 else GunDefs.roll_gun(5, RandomNumberGenerator.new())
	var gp := GunPickupScene.instantiate() as GunPickup
	gp.gun_id = gid
	gp.tier = 5
	add_child(gp)
	gp.position = _snap_to_ground(pos + Vector3(0, 0, -2.5), 0.4)
	hud.add_killfeed("AIRDROP LANDED — top-tier loot")


func _update_zone(delta: float) -> void:
	if _phase >= _phases.size():
		_apply_zone_damage(20.0 * delta)
		_push_zone_to_hud()
		return
	var ph: Dictionary = _phases[_phase]
	_phase_timer -= delta
	if _phase_state == "wait":
		hud.update_zone_text("ZONE SHRINKS IN %ds" % int(ceil(maxf(_phase_timer, 0.0))))
		if _phase_timer <= 0.0:
			_phase_state = "shrink"
			_phase_timer = float(ph["shrink"])
			_shrink_from = zone_radius
			_shrink_from_c = zone_center
			next_radius = float(ph["radius"])
			var max_off := maxf(0.0, zone_radius - next_radius)
			next_center = zone_center + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * max_off * 0.4
			hud.add_killfeed("ZONE SHRINKING")
	else:
		var total: float = float(ph["shrink"])
		var t := 1.0 - clampf(_phase_timer / total, 0.0, 1.0)
		zone_radius = lerpf(_shrink_from, next_radius, t)
		zone_center = _shrink_from_c.lerp(next_center, t)
		hud.update_zone_text("GET TO THE ZONE")
		_apply_zone_damage(float(_dps[_phase]) * delta)
		if _phase_timer <= 0.0:
			_phase += 1
			_phase_state = "wait"
			_phase_timer = float(_phases[_phase]["wait"]) if _phase < _phases.size() else 9999.0
	_push_zone_to_hud()


func _push_zone_to_hud() -> void:
	hud.zone_center = zone_center
	hud.zone_radius = zone_radius
	hud.next_center = next_center
	hud.next_radius = next_radius


func _apply_zone_damage(amount: float) -> void:
	if player.dropping:
		return  # no zone damage while skydiving in
	if player.gas_mask_t > 0.0:
		return  # gas mask: collapse immunity
	var flat := Vector2(player.position.x, player.position.z)
	if flat.distance_to(zone_center) > zone_radius:
		_zone_acc += amount
		var d := int(_zone_acc)
		if d >= 1:
			_zone_acc -= d
			player.take_damage(d, Vector3.ZERO, "zone")


func _update_zone_wall() -> void:
	_zone_wall.position = Vector3(zone_center.x, 12, zone_center.y)
	_zone_wall.scale = Vector3(zone_radius, 1, zone_radius)


func _alive_count() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			n += 1
	return n


func _on_enemy_killed(_e: NovaEnemy) -> void:
	_spawn_death_box(_e)
	var kn := _e.killer_name()
	var vn := str(_e.bot_name)
	if kn != "":
		hud.add_killfeed("%s eliminated %s" % [kn, vn])
	else:
		hud.add_killfeed("%s eliminated" % vn)
	var by_player := kn == "YOU"
	if by_player:
		kills += 1
		hud.update_score(kills, _alive_count())
		# Cash bounty per kill.
		if player != null and is_instance_valid(player):
			player.cash += 200
			hud.update_cash(player.cash)
		# Mythic kill FX + evolution (only when the player runs a mythic skin).
		if player != null and is_instance_valid(player):
			var _sk: int = player.cur_skin()
			if _sk > 0:
				var _gid := player.cur_gun_id()
				var _res: Dictionary = player.register_mythic_kill()
				MythicSkins.play_killfx(self, _e.global_position + Vector3(0, 1.0, 0),
					MythicSkins.skin_theme(_gid, _sk), int(_res["kills"]), str(_res["milestone"]))
	else:
		hud.update_score(kills, _alive_count())
	if _world_mode:
		_squads_victory_check()
		return
	var any_alive := false
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			any_alive = true
			break
	if not any_alive:
		game_over = true
		hud.add_killfeed("VICTORY — LAST ONE STANDING")
		hud.show_end_banner("VICTORY — #1 OF %d" % (kills + 1))
		if player != null and player.has_method("play_victory"):
			player.play_victory()


## BR victory: no hostile combatant left standing (squad 0 wins).
func _squads_victory_check() -> void:
	if game_over or not _world_mode or squadman == null:
		return
	if squadman.alive_hostiles() > 0:
		return
	game_over = true
	var alive_mates := 0
	for a in allies:
		if is_instance_valid(a) and a.is_alive():
			alive_mates += 1
	hud.add_killfeed("VICTORY — SQUAD ALPHA LAST STANDING")
	hud.show_end_banner("VICTORY — #1 OF 25 (%d alive)" % (alive_mates + 1))
	if player != null and player.has_method("play_victory"):
		player.play_victory()


func _on_player_died() -> void:
	if game_over:
		return
	if _world_mode and squadman != null:
		# Teammates still standing: spectate — they can still win or redeploy you.
		var mate_alive := false
		for a in allies:
			if is_instance_valid(a) and a.is_alive():
				mate_alive = true
				break
		if mate_alive:
			hud.add_killfeed("YOU DIED — spectating squad (a teammate can carry your tag)")
			hud.show_end_banner("ELIMINATED — SPECTATING SQUAD")
			return
	game_over = true
	hud.add_killfeed("YOU DIED — #%d" % (kills + 1))
	hud.show_end_banner("YOU DIED — #%d" % (kills + 1))


# ================= LOOT OVERHAUL =================

## Pooled 3D positional audio for loot interactions.
func play_loot_sound(stream: AudioStream, pos: Vector3) -> void:
	if stream == null:
		return
	while _loot_audio_pool.size() < 8:
		var ap := AudioStreamPlayer3D.new()
		ap.max_distance = 40.0
		ap.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(ap)
		_loot_audio_pool.append(ap)
	var p: AudioStreamPlayer3D = _loot_audio_pool[_loot_audio_idx % _loot_audio_pool.size()]
	_loot_audio_idx += 1
	p.global_position = pos
	p.stream = stream
	p.play()


## Interpret a loot item dict into a world pickup with a spawn pop.
## {kind, amount, tier, caliber} -> NovaLoot | {gun, tier} -> GunPickup |
## {attach, tier} -> attachment GunPickup.
func _spawn_loot_item(item: Dictionary, pos: Vector3) -> void:
	var gp: Vector3 = _snap_to_ground(pos, 0.4)
	if item.has("gun"):
		var pickup := GunPickupScene.instantiate() as GunPickup
		pickup.gun_id = str(item["gun"])
		pickup.tier = int(item.get("tier", 0))
		add_child(pickup)
		pickup.position = gp
		_pop_in(pickup)
		loots.append(pickup)
	elif item.has("attach"):
		var ap := GunPickup.make_attachment(str(item["attach"]))
		add_child(ap)
		ap.position = gp
		_pop_in(ap)
		loots.append(ap)
	else:
		var l := LootScene.instantiate() as NovaLoot
		l.kind = str(item.get("kind", "health"))
		l.amount = int(item.get("amount", 40))
		l.tier = int(item.get("tier", 0))
		if item.has("caliber"):
			l.caliber = str(item["caliber"])
		add_child(l)
		l.position = _snap_to_ground(pos, 0.55)
		_pop_in(l)
		loots.append(l)


func _pop_in(n: Node3D) -> void:
	n.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func spawn_container_loot(item: Dictionary, pos: Vector3) -> void:
	_spawn_loot_item(item, pos)


func spawn_crate_loot(item: Dictionary, pos: Vector3) -> void:
	_spawn_loot_item(item, pos)


func spawn_deathbox_loot(item: Dictionary, pos: Vector3) -> void:
	_spawn_loot_item(item, pos)


## House loot: searchable containers in every enterable building, room-logic
## contents. Guarantees every house has at least 2 loot sources.
func _spawn_loot_containers() -> void:
	if map == null:
		return
	var houses: Array = map.get("house_positions")
	if houses == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337 + _map_idx
	var rooms := ["kitchen", "bedroom", "garage", "general", "bedroom", "general"]
	var hi := 0
	for h in houses:
		var hp: Vector3 = h
		var room: String = rooms[hi % rooms.size()]
		hi += 1
		var n := 1 + rng.randi() % 2  # 1-2 containers per house
		for i in range(n):
			var ct: String = LootContainer.CTYPES[rng.randi() % LootContainer.CTYPES.size()]
			# Room-logic container types.
			if room == "kitchen" and rng.randf() < 0.6:
				ct = "fridge" if rng.randf() < 0.5 else "medbox"
			elif room == "garage" and rng.randf() < 0.6:
				ct = "crate" if rng.randf() < 0.5 else "shelf"
			elif room == "bedroom" and rng.randf() < 0.5:
				ct = "drawer"
			var c := LootContainer.make(ct, room, 1 + rng.randi() % 3)
			add_child(c)
			var off := Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
			c.position = _snap_to_ground(hp + off, 0.1)
			c.rotation.y = rng.randf() * TAU
		# Economy guarantee: every house has >= 2 loot sources nearby.
		var near := 0
		for spec in map.loot_spots:
			var sp: Vector3 = spec[2]
			if Vector2(sp.x - hp.x, sp.z - hp.z).length() < 9.0:
				near += 1
		var need := maxi(0, 2 - near - n)
		for k in range(need):
			var kinds := ["health", "ammo", "armor", "cash"]
			var kk: String = kinds[rng.randi() % kinds.size()]
			var amt := 40
			if kk == "ammo":
				amt = 60
			elif kk == "cash":
				amt = 120
			var item := {"kind": kk, "amount": amt, "tier": rng.randi() % 3}
			var pos := hp + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
			_spawn_loot_item(item, pos)


## Supply crates at POIs: tier-weighted, epic crates glow across the map.
func _spawn_supply_crates() -> void:
	if map == null:
		return
	var pois: Array = map.get("poi_list")
	if pois == null or pois.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 90909 + _map_idx
	for poi in pois:
		if rng.randf() > 0.45:
			continue
		var pp: Vector3 = (poi as Dictionary)["pos"]
		var r := rng.randf()
		var t := 0
		if r > 0.92:
			t = 2
		elif r > 0.70:
			t = 1
		var crate := LootCrate.make(t)
		add_child(crate)
		var off := Vector3(rng.randf_range(4.0, 9.0), 0, rng.randf_range(4.0, 9.0))
		crate.position = _snap_to_ground(pp + off, 0.1)
		crate.rotation.y = rng.randf() * TAU


## Two AI squadmates drop with the player.
func _spawn_allies() -> void:
	var names := ["NOMAD", "HAVOC", "JOLT"]
	var count := 3 if _world_mode else 2
	for i in range(count):
		var a := AllyScene.instantiate() as NovaAlly
		add_child(a)
		var base: Vector3 = player.global_position if player != null else Vector3.ZERO
		a.position = _snap_to_ground(base + Vector3(-3.0 + 3.0 * float(i), 0, 3.0), 0.6)
		a.setup(i, names[i % names.size()])
		a.killed.connect(_on_ally_killed)
		allies.append(a)
	if _world_mode:
		if hud != null:
			hud.add_killfeed("Squad ALPHA deployed — NOMAD, HAVOC, JOLT")
	else:
		if hud != null:
			hud.add_killfeed("Squadmates NOMAD and HAVOC deployed")


## Squad system: build the 25 x 4 combatant registry (world mode only).
func _spawn_squads() -> void:
	if not _world_mode:
		return
	squadman = SquadManager.new()
	squadman.name = "SquadManager"
	add_child(squadman)
	squadman.organize(self)
	hud.add_killfeed("100 combatants deployed — 25 squads")


func _on_ally_killed(a: NovaAlly) -> void:
	hud.add_killfeed(str(a.bot_name) + " is out of the fight")


## An ally was downed (revivable): drop their dog tag at their position.
func on_ally_down(a: NovaAlly) -> void:
	var tag := DogTag.make(str(a.bot_name))
	add_child(tag)
	tag.position = a.global_position + Vector3(0, 0.4, 0)
	hud.add_killfeed(str(a.bot_name) + " is DOWN — revive or carry their tag")


func on_player_fired(pos: Vector3) -> void:
	if squadman != null:
		squadman.hear_shot(pos, player)


func bot_bark(who: String, text: String) -> void:
	if hud != null:
		hud.add_killfeed("%s: %s" % [who, text])


## Enemy death box: what they carried — gun + ammo + bonus.
func _spawn_death_box(e: NovaEnemy) -> void:
	var gid: String = str(e.get("carry_gun_id"))
	var g := GunDefs.by_id(gid)
	var acc := Color(0.8, 0.2, 0.2)
	var cid: String = str(e.get("class_id"))
	if cid != "":
		var cd := ClassDefs.get_by_id(cid)
		if not cd.is_empty() and cd.has("accent"):
			acc = cd["accent"]
	var box := DeathBox.make("HOSTILE", gid, int(e.get("carry_gun_tier")), str(g.get("ammo", "medium")), acc)
	add_child(box)
	box.position = _snap_to_ground(e.global_position, 0.25)
	play_loot_sound(LootAudio.thud_stream(), box.position)


# ---------------- ping system ----------------

## Crosshair ping (PING button / P key): raycast from the camera.
func try_ping() -> void:
	if player == null or game_over:
		return
	var cam := player.camera
	var from: Vector3 = cam.global_transform.origin
	var dir := -cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 45.0)
	query.exclude = [player]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Object = null
	var at: Vector3 = from + dir * 20.0
	if not hit.is_empty():
		target = hit["collider"]
		at = hit["position"]
	if target != null and (target is NovaLoot or target is GunPickup or target is LootCrate or target is DeathBox):
		(target as Node).call("ping")
		play_loot_sound(LootAudio.ping_stream(), at)
	else:
		spawn_loot_ping("MARK", 0, at)
		play_loot_sound(LootAudio.ping_stream(), at)


## Double-tap on a loot item in the 3D world (touch screens).
func _try_tap_ping(screen_pos: Vector2) -> void:
	if player == null or game_over:
		return
	var cam := player.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0)
	query.exclude = [player]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var target: Object = hit["collider"]
	if target is NovaLoot or target is GunPickup or target is LootCrate or target is DeathBox:
		(target as Node).call("ping")
		play_loot_sound(LootAudio.ping_stream(), hit["position"])


func spawn_loot_ping(text: String, tier: int, pos: Vector3) -> void:
	var p := LootPing.make(text, tier)
	add_child(p)
	p.position = _snap_to_ground(pos, 0.2)
	_pings.append(p)
	hud.minimap_pings.append({"pos": p.position, "tier": tier, "node": p})
	hud.add_killfeed("◈ Pinged " + text)
	# AI squadmates investigate high-tier pings.
	if tier >= 4:
		for a in allies:
			if a != null and is_instance_valid(a) and (a as NovaAlly).is_alive():
				(a as NovaAlly).investigate(p.position)


func on_ping_expired(ping: LootPing) -> void:
	_pings.erase(ping)
	for i in range(hud.minimap_pings.size() - 1, -1, -1):
		var d: Dictionary = hud.minimap_pings[i]
		if d.get("node") == ping:
			hud.minimap_pings.remove_at(i)


# ---------------- scorestreak pickups ----------------

func trigger_uav_pickup() -> void:
	hud.reveal_uav(25.0)
	hud.add_killfeed("UAV SWEEP — enemies revealed")


func trigger_strike_pickup() -> void:
	call_airstrike()
	hud.add_killfeed("CLUSTER STRIKE inbound!")


func spawn_smoke_cloud(pos: Vector3, radius: float, life: float) -> void:
	ClassFX.smoke_column(self, pos + Vector3(0, 0.8, 0), radius, life)


func _input(event: InputEvent) -> void:
	if _match_started and event.is_action_pressed("ui_cancel"):
		cycle_quality()
	if _match_started and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_P:
			try_ping()
	if _match_started and event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var now := Time.get_ticks_msec() / 1000.0
		var pp := (event as InputEventScreenTouch).position
		if now - _tap_last_t < 0.35 and pp.distance_to(_tap_last_pos) < 48.0:
			_try_tap_ping(pp)
			_tap_last_t = -1.0
		else:
			_tap_last_t = now
			_tap_last_pos = pp


## Open the CODM-style settings screen (pre-match from the map menu, or
## in-match via the HUD gear button).
func open_settings() -> void:
	if _settings_menu != null and is_instance_valid(_settings_menu):
		return
	_settings_menu = SettingsMenu.new()
	if _match_started and hud != null:
		_settings_menu.hud = hud
	add_child(_settings_menu)
	_settings_menu.open()


func cycle_quality() -> void:
	var q := int($WorldEnvironment.get_meta("quality", 1)) + 1
	if q > 2:
		q = 0
	apply_quality(q)


func apply_quality(q: int) -> void:
	$WorldEnvironment.set_meta("quality", q)
	var env := $WorldEnvironment.environment as Environment
	var sun := $Sun as DirectionalLight3D
	var label := "GFX: BALANCED"
	match q:
		0:  # Performance
			env.glow_enabled = false
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 60.0
			get_viewport().scaling_3d_scale = 0.8
			label = "GFX: PERFORMANCE"
		1:  # Balanced
			env.glow_enabled = true
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 100.0
			get_viewport().scaling_3d_scale = 1.0
			label = "GFX: BALANCED"
		2:  # Ultra
			env.glow_enabled = true
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 160.0
			get_viewport().scaling_3d_scale = 1.0
			label = "GFX: ULTRA"
	hud.set_gfx_label(label)


# ================= vehicles + economy + airdrop events =================

func ground_height_at(x: float, z: float) -> float:
	if map != null and map.has_method("ground_height"):
		return map.ground_height(x, z)
	return 0.0


func _poi_named(fragment: String) -> Dictionary:
	if map == null or map.poi_list.is_empty():
		return {}
	var fl := fragment.to_lower()
	for p in map.poi_list:
		if fl in str(p["name"]).to_lower():
			return p
	return map.poi_list[randi() % map.poi_list.size()]


func _spawn_vehicles() -> void:
	var defs: Array = []
	if _world_mode:
		defs = VehicleDefs.WORLD_SPAWNS
	else:
		defs = VehicleDefs.MAP_SPAWNS.get(_map_idx, [])
	for sd in defs:
		var vid := str(sd["type"])
		var p := _poi_named(str(sd["poi"]))
		if p.is_empty():
			continue
		var pp: Vector3 = p["pos"]
		var v := NovaVehicle.new()
		v.vid = vid
		add_child(v)
		var gx := pp.x + randf_range(-10.0, 10.0)
		var gz := pp.z + randf_range(-10.0, 10.0)
		v.position = Vector3(gx, ground_height_at(gx, gz) + 0.3, gz)
		v.rotation.y = randf() * TAU
		v.cannon_fired.connect(_on_vehicle_cannon.bind(v))
		v.exploded.connect(_on_vehicle_exploded.bind(v))
		vehicles.append(v)


func _spawn_buy_stations() -> void:
	var picks: Array = []
	if _world_mode and map.poi_list.size() >= 12:
		var step := maxi(map.poi_list.size() / 16, 1)
		var i := 0
		while picks.size() < 16 and i < map.poi_list.size():
			picks.append(map.poi_list[i])
			i += step
	else:
		for p in map.poi_list:
			picks.append(p)
			if picks.size() >= 2:
				break
	for p in picks:
		var pp: Vector3 = p["pos"]
		var st := BuyStation.new()
		add_child(st)
		var gx := pp.x + randf_range(-6.0, 6.0)
		var gz := pp.z + randf_range(-6.0, 6.0)
		st.position = Vector3(gx, ground_height_at(gx, gz), gz)
		buy_stations.append(st)


func _spawn_cash() -> void:
	# Cash bundles scattered at loot spots.
	if map == null:
		return
	var spots: Array = map.loot_spots
	var n := maxi(spots.size() / 6, 8)
	for i in range(n):
		var sp: Vector3 = spots[randi() % maxi(spots.size(), 1)][2]
		var l := LootScene.instantiate() as NovaLoot
		l.kind = "cash"
		l.amount = [150, 200, 250, 300, 400][randi() % 5]
		l.tier = 2
		add_child(l)
		l.position = _snap_to_ground(sp + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)), 0.55)
		loots.append(l)
	# Safes: big cash at spread POIs.
	if map.poi_list.size() > 0:
		for i in range(maxi(map.poi_list.size() / 8, 1)):
			var p: Dictionary = map.poi_list[(i * 7 + 3) % map.poi_list.size()]
			var pp: Vector3 = p["pos"]
			var l := LootScene.instantiate() as NovaLoot
			l.kind = "cash"
			l.amount = 1500
			l.tier = 5
			add_child(l)
			l.position = _snap_to_ground(pp + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0)), 0.55)
			loots.append(l)


func play_boom_at(pos: Vector3) -> void:
	var ap := AudioStreamPlayer3D.new()
	ap.stream = GunAudio.explosion_stream()
	ap.unit_size = 20.0
	add_child(ap)
	ap.global_position = pos
	ap.play()
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(ap.queue_free)


func _on_vehicle_cannon(v: NovaVehicle) -> void:
	play_boom_at(v.global_position + Vector3(0, 1.0, 0))


func _on_vehicle_exploded(v: NovaVehicle) -> void:
	play_boom_at(v.global_position)
	hud.add_killfeed("VEHICLE DESTROYED")
	# A burning wreck can cook off nearby fuel pumps.
	for st in fuel_stations:
		if st == null or not is_instance_valid(st):
			continue
		for p in st.pumps:
			if not p.destroyed and p.global_position.distance_to(v.global_position) < 8.0:
				p.take_damage(150.0)


func _update_interact() -> void:
	if player == null or not is_instance_valid(player) or game_over:
		return
	if player.in_vehicle != null:
		hud.hide_prompt()
		return
	# Nearest vehicle / station within reach.
	_near_vehicle = null
	_near_station = null
	var best := 4.5
	for v in vehicles:
		if v == null or not is_instance_valid(v) or v.destroyed:
			continue
		var d := player.global_position.distance_to(v.global_position)
		if d < best:
			best = d
			_near_vehicle = v
	best = 4.0
	for st in buy_stations:
		if st == null or not is_instance_valid(st):
			continue
		var d := player.global_position.distance_to(st.global_position)
		if d < best:
			best = d
			_near_station = st
	if _near_vehicle != null:
		hud.show_prompt("[E] DRIVE %s" % str(VehicleDefs.SPECS[_near_vehicle.vid]["name"]))
	elif _near_station != null:
		hud.show_prompt("[E] BUY STATION")
	else:
		hud.hide_prompt()
	# Desktop keys: E enter/interact, H horn, V camera, L lights.
	var e_down := Input.is_key_pressed(KEY_E)
	if e_down and not _e_held:
		interact_pressed()
	_e_held = e_down
	if player.in_vehicle != null:
		if Input.is_key_pressed(KEY_H):
			player.in_vehicle.honk()
		if Input.is_key_pressed(KEY_V) and not _v_held:
			player.veh_cam_mode = 1 - player.veh_cam_mode
		_v_held = Input.is_key_pressed(KEY_V)
		if Input.is_key_pressed(KEY_L) and not _l_held:
			player.in_vehicle.toggle_lights()
		_l_held = Input.is_key_pressed(KEY_L)


func interact_pressed() -> void:
	if player == null or not is_instance_valid(player) or game_over:
		return
	if hud.is_shop_open():
		hud.close_shop()
		return
	if player.in_vehicle != null:
		player.exit_vehicle()
		return
	if _near_vehicle != null:
		player.enter_vehicle(_near_vehicle)
		hud.show_vehicle(_near_vehicle)
	elif _near_station != null:
		hud.open_shop()


func buy_item(item_id: String) -> void:
	if player == null or not is_instance_valid(player):
		return
	var it := BuyStation.item_by_id(item_id)
	if it.is_empty():
		return
	if not BuyStation.can_afford(player.cash, item_id):
		hud.add_killfeed("NOT ENOUGH CASH")
		return
	# Vehicle-only items need a driven vehicle.
	if item_id in ["repair", "paint"] and player.in_vehicle == null:
		hud.add_killfeed("MUST BE DRIVING")
		return
	player.cash -= int(it["price"])
	match str(it["id"]):
		"frag_bundle":
			player.ammo["grenade"] = mini(int(player.ammo["grenade"]) + 3, 12)
			hud.set_grenade_count(int(player.ammo["grenade"]))
			hud.add_killfeed("+3 FRAG GRENADES")
		"medkit":
			player.heal(100)
			hud.add_killfeed("HEALED")
		"gas_mask":
			player.gas_mask_t = 30.0
			hud.add_killfeed("GAS MASK on — 30s collapse immunity")
		"shield":
			deploy_shield()
			hud.add_killfeed("SHIELD TURRET deployed")
		"armor":
			player.armor = player.armor_cap
			hud.add_killfeed("ARMOR PLATES equipped")
		"carrier":
			player.armor_cap = 200
			player.armor = 200
			hud.add_killfeed("JUGGERNAUT CARRIER — max armor 200")
		"ammo":
			player.add_ammo_all(240)
			hud.add_killfeed("+240 reserve ammo")
		"mystery":
			var gid := GunDefs.roll_gun(5 if randf() < 0.5 else 4, RandomNumberGenerator.new())
			player.give_gun(gid, 5)
			hud.add_killfeed("MYSTERY WEAPON: " + str(GunDefs.by_id(gid).get("name", gid)))
		"heavy":
			player.give_gun("rp7", 5)
			hud.add_killfeed("RP-7 'THUNDERHEAD' acquired")
		"uav":
			hud.reveal_uav(25.0)
			hud.add_killfeed("UAV sweep — enemies revealed")
		"strike":
			call_airstrike()
			hud.add_killfeed("CLUSTER STRIKE inbound!")
		"precision":
			call_precision()
			hud.add_killfeed("PRECISION AIRSTRIKE inbound!")
		"sentry":
			deploy_sentry()
			hud.add_killfeed("SENTRY GUN deployed")
		"bomber":
			call_bomber_run()
			hud.add_killfeed("'JAKA' BOMB RUN inbound!")
		"modkit":
			var aid: String = GunDefs.ATTACH_LOOT[randi() % GunDefs.ATTACH_LOOT.size()]
			if player.attach_to_current(aid):
				hud.add_killfeed("MOD FITTED: " + str(GunDefs.find_attach(aid).get("name", aid)))
			else:
				hud.add_killfeed("MOD KIT failed")
		"tankdrop":
			_plan_tank_drop()
			hud.add_killfeed("TANK DROP ordered — mark inbound")
		"repair":
			player.in_vehicle.hp = player.in_vehicle.max_hp
			player.in_vehicle._smoke_t = 0.0
			player.in_vehicle._fire_t = 0.0
			hud.add_killfeed("VEHICLE fully repaired")
		"paint":
			player.in_vehicle.reroll_skin()
			hud.add_killfeed("New paint: " + player.in_vehicle.skin_name)
		"revive":
			player.revive_kits += 1
			hud.add_killfeed("SELF-REVIVE kit (+1)")
		"redeploy":
			_redeploy_teammate()
	hud.update_cash(player.cash)


## REDEPLOY: spend a carried dog tag to drop a dead teammate back in.
func _redeploy_teammate() -> void:
	if player.carried_tags.is_empty():
		player.cash += BuyStation.price("redeploy")  # refund
		hud.add_killfeed("NO DOG TAG — carry a fallen teammate's tag first")
		return
	var tag_name: String = str(player.carried_tags.pop_back())
	var target: NovaAlly = null
	for a in allies:
		if is_instance_valid(a) and str(a.bot_name) == tag_name and not a.is_alive():
			target = a
			break
	if target == null:
		player.cash += BuyStation.price("redeploy")  # refund
		hud.add_killfeed("TAG INVALID — no matching fallen teammate")
		return
	var drop: Vector3 = player.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	target.respawn_at(drop)
	hud.add_killfeed("%s REDEPLOYED — welcome back" % tag_name)


func call_airstrike() -> void:
	# Cluster strike: 5 explosions around the player's aim point over 3s.
	if player == null or not is_instance_valid(player):
		return
	var from: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	var dir: Vector3 = -player.global_transform.basis.z
	var target := from + dir * 60.0
	target.y = ground_height_at(target.x, target.z)
	for i in range(5):
		var off := Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
		var at := target + off
		var tw := create_tween()
		tw.tween_interval(0.5 + i * 0.55)
		tw.tween_callback(_strike_blast.bind(at))


func _strike_blast(at: Vector3, dmg := 120.0, radius := 9.0) -> void:
	play_boom_at(at)
	for e in enemies:
		if e != null and is_instance_valid(e) and e.is_alive():
			if e.global_position.distance_to(at) < radius:
				e.take_damage(dmg, "strike")


func _update_veh_minimap() -> void:
	hud.minimap_shops.clear()
	for st in buy_stations:
		if st != null and is_instance_valid(st):
			hud.minimap_shops.append(st.global_position)
	hud.minimap_vehicles.clear()
	for v in vehicles:
		if v != null and is_instance_valid(v):
			hud.minimap_vehicles.append(v)
	hud.minimap_drops.clear()
	for ad in _airdrops:
		var n: Node3D = ad["node"]
		if n != null and is_instance_valid(n):
			hud.minimap_drops.append(n.global_position)
	hud.minimap_fuel.clear()
	for fs in fuel_stations:
		if fs != null and is_instance_valid(fs):
			hud.minimap_fuel.append(fs.global_position)


# ---------------- airdrop EVENTS ----------------

func _plan_drops() -> void:
	_pending_drops.clear()
	var count := 1
	if _phase >= 2:
		count += 1
	if _phase >= 4:
		count += 1
	var used: Array = []
	for i in range(count):
		if map.poi_list.is_empty():
			break
		var p: Dictionary = map.poi_list[randi() % map.poi_list.size()]
		if str(p["name"]) in used:
			continue
		used.append(str(p["name"]))
		var pp: Vector3 = p["pos"]
		_pending_drops.append(Vector3(pp.x + randf_range(-12.0, 12.0), 130.0, pp.z + randf_range(-12.0, 12.0)))
		hud.add_killfeed("⚠ AIRDROP INCOMING — " + str(p["name"]))


func _launch_drop(drop_pos: Vector3, payload := "loot") -> void:
	# Flyover plane: crosses the sky, releases the crate mid-pass.
	var plane := Node3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(2.0, 2.0, 9.0)
	var fus := MeshInstance3D.new()
	fus.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.25, 0.26, 0.28)
	fus.set_surface_override_material(0, fmat)
	plane.add_child(fus)
	var wm := BoxMesh.new()
	wm.size = Vector3(14.0, 0.4, 2.2)
	var wings := MeshInstance3D.new()
	wings.mesh = wm
	wings.set_surface_override_material(0, fmat)
	plane.add_child(wings)
	var start := drop_pos + Vector3(-260.0, 0.0, 60.0)
	var end := drop_pos + Vector3(260.0, 0.0, -60.0)
	plane.position = start
	add_child(plane)
	var tw := create_tween()
	tw.tween_property(plane, "position", end, 13.0)
	tw.tween_callback(plane.queue_free)
	var tw2 := create_tween()
	tw2.tween_interval(5.2)
	tw2.tween_callback(_release_crate.bind(drop_pos, payload))


func _release_crate(drop_pos: Vector3, payload := "loot") -> void:
	var crate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 1.6, 1.6)
	crate.mesh = bm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.85, 0.45, 0.1)
	cmat.emission_enabled = true
	cmat.emission = Color(0.85, 0.45, 0.1)
	cmat.emission_energy_multiplier = 0.4
	crate.set_surface_override_material(0, cmat)
	crate.position = drop_pos
	add_child(crate)
	# Parachute canopy above the crate.
	var chute := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(4.5, 0.25, 4.5)
	chute.mesh = cm
	var chmat := StandardMaterial3D.new()
	chmat.albedo_color = Color(0.9, 0.88, 0.82)
	chute.set_surface_override_material(0, chmat)
	chute.position = Vector3(0, 3.2, 0)
	crate.add_child(chute)
	# Tall smoke column marks the drop (visible across the world).
	var smoke := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 1.2
	sm.bottom_radius = 2.2
	sm.height = 70.0
	smoke.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(1.0, 0.45, 0.1, 0.45)
	smoke.set_surface_override_material(0, smat)
	smoke.position = Vector3(drop_pos.x, 35.0, drop_pos.z)
	add_child(smoke)
	_airdrops.append({"node": crate, "smoke": smoke, "landed": false, "chute": chute, "payload": payload})
	hud.add_killfeed("AIRDROP released")


# ================= buy-station effect systems =================

func call_precision() -> void:
	# One massive blast at the player's aim point.
	if player == null or not is_instance_valid(player):
		return
	var from: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	var dir: Vector3 = -player.global_transform.basis.z
	var target := from + dir * 60.0
	target.y = ground_height_at(target.x, target.z)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(_strike_blast.bind(target, 220.0, 13.0))


func call_bomber_run() -> void:
	# NOVA-original: a B2 flies along the player's aim line, carpet-bombing it.
	if player == null or not is_instance_valid(player):
		return
	var from: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	var dir: Vector3 = -player.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var mid := from + dir * 70.0
	mid.y = ground_height_at(mid.x, mid.z)
	var side := dir.cross(Vector3.UP).normalized()
	for i in range(3):
		var at: Vector3 = mid + dir * (float(i) - 1.0) * 14.0
		var tw := create_tween()
		tw.tween_interval(1.0 + i * 0.45)
		tw.tween_callback(_strike_blast.bind(at, 170.0, 11.0))
	# Flyover visual.
	var jet := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(21.0, 1.2, 5.0)
	jet.mesh = bm
	var jm := StandardMaterial3D.new()
	jm.albedo_color = Color(0.05, 0.05, 0.06)
	jet.set_surface_override_material(0, jm)
	var p0 := mid - dir * 220.0 + Vector3(0, 90.0, 0)
	jet.position = p0
	add_child(jet)
	var tw2 := create_tween()
	tw2.tween_property(jet, "position", mid + dir * 220.0 + Vector3(0, 90.0, 0), 4.0)
	tw2.tween_callback(jet.queue_free)
	hud.add_killfeed("B2 on station...")


func deploy_shield() -> void:
	# Shield turret: armored cover wall in front of the player, 90s.
	if player == null or not is_instance_valid(player):
		return
	var dir: Vector3 = -player.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 1.7, 0.25)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.35, 0.55)
	m.metallic = 0.7
	m.roughness = 0.35
	mi.set_surface_override_material(0, m)
	wall.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 1.7, 0.25)
	cs.shape = bs
	wall.add_child(cs)
	var at: Vector3 = player.global_position + dir * 2.2
	at.y = ground_height_at(at.x, at.z) + 0.85
	wall.position = at
	wall.rotation.y = atan2(-dir.x, -dir.z) + PI * 0.5
	add_child(wall)
	var tw := create_tween()
	tw.tween_interval(90.0)
	tw.tween_callback(wall.queue_free)


class SentryGun:
	extends Node3D
	var life := 60.0
	var cd := 0.0
	var scene: Node = null

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		cd -= delta
		if cd > 0.0:
			return
		if scene == null:
			return
		var best = null
		var best_d := 42.0
		for e in scene.enemies:
			if e != null and is_instance_valid(e) and e.is_alive():
				var d := global_position.distance_to(e.global_position)
				if d < best_d:
					best_d = d
					best = e
		if best != null:
			cd = 0.45
			look_at(Vector3(best.global_position.x, global_position.y, best.global_position.z))
			best.take_damage(16.0, "sentry")
			scene.spawn_tracer(global_position + Vector3(0, 1.1, 0),
				best.global_position + Vector3(0, 1.2, 0))


func deploy_sentry() -> void:
	if player == null or not is_instance_valid(player):
		return
	var s := SentryGun.new()
	s.scene = self
	# Tripod + gun body.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.16, 0.18)
	var legm := BoxMesh.new()
	legm.size = Vector3(0.12, 1.0, 0.12)
	for a in [0.0, 2.1, 4.2]:
		var leg := MeshInstance3D.new()
		leg.mesh = legm
		leg.set_surface_override_material(0, dark)
		leg.position = Vector3(cos(a) * 0.4, 0.5, sin(a) * 0.4)
		s.add_child(leg)
	var bodym := BoxMesh.new()
	bodym.size = Vector3(0.5, 0.4, 1.1)
	var body := MeshInstance3D.new()
	body.mesh = bodym
	body.set_surface_override_material(0, dark)
	body.position = Vector3(0, 1.1, 0)
	s.add_child(body)
	var at: Vector3 = player.global_position + Vector3(1.5, 0, 0)
	at.y = ground_height_at(at.x, at.z)
	s.position = at
	add_child(s)


func _plan_tank_drop() -> void:
	# Tank drop marker: a tank crate falls 25m ahead of the player.
	if player == null or not is_instance_valid(player):
		return
	var dir: Vector3 = -player.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var at: Vector3 = player.global_position + dir * 25.0
	_launch_drop(Vector3(at.x, 130.0, at.z), "tank")


func _spawn_dropped_tank(pos: Vector3) -> void:
	var v := NovaVehicle.new()
	v.vid = "tank"
	add_child(v)
	v.position = Vector3(pos.x, ground_height_at(pos.x, pos.z) + 0.5, pos.z)
	v.rotation.y = randf() * TAU
	v.cannon_fired.connect(_on_vehicle_cannon.bind(v))
	v.exploded.connect(_on_vehicle_exploded.bind(v))
	vehicles.append(v)
	hud.add_killfeed("TANK DELIVERED — get in!")


func spawn_tracer(a: Vector3, b: Vector3) -> void:
	# Short-lived glowing beam between two points (sentry gun, etc.).
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var length := a.distance_to(b)
	bm.size = Vector3(0.05, 0.05, length)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.3)
	mi.set_surface_override_material(0, m)
	mi.position = (a + b) * 0.5
	add_child(mi)
	mi.look_at(b, Vector3.UP)
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(mi.queue_free)


# ================= fuel system + filling stations =================

func _spawn_fuel_stations() -> void:
	if map == null or map.poi_list.is_empty():
		return
	var count := 9 if _world_mode else 2
	var step := maxi(map.poi_list.size() / count, 1)
	var placed := 0
	var i := 0
	while placed < count and i < map.poi_list.size():
		var p: Dictionary = map.poi_list[i]
		var pp: Vector3 = p["pos"]
		var st := FuelStation.new()
		add_child(st)
		# Offset from the POI so the forecourt sits clear of buildings.
		var gx := pp.x + 14.0
		var gz := pp.z + 6.0
		st.position = Vector3(gx, ground_height_at(gx, gz), gz)
		st.rotation.y = randf() * TAU
		st.station_destroyed.connect(_on_station_destroyed)
		fuel_stations.append(st)
		# Loot inside the convenience store.
		for spot in st.store_loot_spots():
			var wp: Vector3 = st.to_global(spot)
			_spawn_store_loot(wp)
		placed += 1
		i += step


func _spawn_store_loot(wp: Vector3) -> void:
	var kinds := ["ammo", "health", "armor", "cash"]
	var l := LootScene.instantiate() as NovaLoot
	l.kind = kinds[randi() % kinds.size()]
	l.amount = 40 if l.kind != "cash" else 150
	l.tier = 1
	add_child(l)
	l.position = Vector3(wp.x, ground_height_at(wp.x, wp.z) + 0.55, wp.z)
	loots.append(l)


func _spawn_fuel_cans() -> void:
	if map == null:
		return
	var spots: Array = map.loot_spots
	if spots.is_empty():
		return
	for i in range(12):
		var sp: Vector3 = spots[randi() % spots.size()][2]
		var l := LootScene.instantiate() as NovaLoot
		l.kind = "fuelcan"
		l.tier = 2
		add_child(l)
		l.position = Vector3(sp.x, ground_height_at(sp.x, sp.z) + 0.55, sp.z)
		loots.append(l)


func _on_station_destroyed(st: FuelStation) -> void:
	hud.add_killfeed("FILLING STATION DESTROYED")


func _update_refuel(delta: float) -> void:
	_refuel_pump = null
	if player == null or not is_instance_valid(player) or game_over:
		return
	var v: NovaVehicle = player.in_vehicle
	if v == null or not v.needs_fuel():
		return
	# Nearest live pump within reach.
	for st in fuel_stations:
		if st == null or not is_instance_valid(st):
			continue
		var p = st.nearest_pump(v.global_position, 5.0)
		if p != null:
			_refuel_pump = p
			break
	# Tap F (or FUEL button) with no pump nearby = pour a carried can.
	var f_down := Input.is_key_pressed(KEY_F) or player.touch_fuel_held
	if f_down and not _f_held and _refuel_pump == null:
		pour_fuel_can()
	_f_held = f_down
	if _refuel_pump == null:
		return
	# Parked at a pump: hold F to refuel (~10s for a full tank). Driving off cancels.
	var throttle_in := absf(player.drive_move_input().y) > 0.15 or player.drive_gas or player.drive_brake
	if throttle_in:
		hud.show_prompt("STOP TO REFUEL")
		return
	hud.show_prompt("HOLD [F] TO REFUEL  —  %d%%" % int(v.fuel_frac() * 100.0))
	if f_down:
		v.refuel(v.max_fuel / 10.0 * delta)
		if not v.needs_fuel():
			hud.add_killfeed("TANK FULL")


func try_fuel_action() -> void:
	# FUEL button press: pour a can, unless parked at a pump (hold refuels there).
	if _refuel_pump != null:
		return
	pour_fuel_can()


func pour_fuel_can() -> void:
	if player == null or not is_instance_valid(player):
		return
	var v: NovaVehicle = player.in_vehicle
	if v == null or player.fuel_cans <= 0 or not v.needs_fuel():
		return
	player.fuel_cans -= 1
	v.refuel(35.0)
	hud.add_killfeed("Poured fuel can (+35)")


## Fuel explosion: big AoE + chain-detonates nearby pumps/stations.
func fuel_explosion(pos: Vector3, radius: float, dmg: float, source) -> void:
	play_boom_at(pos)
	_fireball(pos, radius)
	for e in enemies:
		if e != null and is_instance_valid(e) and e.is_alive():
			if e.global_position.distance_to(pos) < radius:
				e.take_damage(dmg, "explosion")
	if player != null and is_instance_valid(player) and player.is_alive():
		if player.global_position.distance_to(pos) < radius:
			player.take_damage(int(dmg), pos, "explosion")
	for v in vehicles:
		if v != null and is_instance_valid(v) and v != source:
			if v.global_position.distance_to(pos) < radius:
				v.take_damage(dmg, "explosion")
	# Chain: nearby live pumps cook off a moment later (staggered).
	for st in fuel_stations:
		if st == null or not is_instance_valid(st):
			continue
		for p in st.pumps:
			if p == source or p.destroyed:
				continue
			if p.global_position.distance_to(pos) < radius + 2.0:
				var tw := create_tween()
				tw.tween_interval(0.35)
				tw.tween_callback(p.take_damage.bind(dmg * 2.0))
		if not st.destroyed and st.global_position.distance_to(pos) < radius:
			var tw2 := create_tween()
			tw2.tween_interval(0.6)
			tw2.tween_callback(st.take_damage.bind(dmg))


func _fireball(pos: Vector3, radius: float) -> void:
	# Expanding fire flash + lingering smoke column.
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.set_surface_override_material(0, m)
	ball.position = pos + Vector3(0, 1.0, 0)
	add_child(ball)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 0.8, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(ball.queue_free)
	var smoke := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.5
	cm.bottom_radius = 2.5
	cm.height = 25.0
	smoke.mesh = cm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.15, 0.14, 0.13, 0.6)
	smoke.set_surface_override_material(0, smat)
	smoke.position = pos + Vector3(0, 12.0, 0)
	add_child(smoke)
	var tw2 := create_tween()
	tw2.tween_interval(20.0)
	tw2.tween_callback(smoke.queue_free)
