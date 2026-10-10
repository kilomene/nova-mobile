extends CharacterBody3D
class_name NovaPlayer

signal health_changed(hp: int, max_hp: int, armor: int)
signal died
signal ammo_changed(mag: int, reserve: int)
signal hit_confirmed(kill: bool)
signal weapon_changed(wname: String)

const SPEED := 5.2
const ADS_SLOW := 0.6
const JUMP_VELOCITY := 4.6
const MOUSE_SENS := 0.0026
const TOUCH_SENS := 0.0045
const ADS_SENS_MULT := 0.6
const REGEN_DELAY := 5.0
const REGEN_RATE := 25.0
const HIP_FOV := 75.0
const ADS_FOV := 63.0
# --- CODM movement spec (see movement-research.md) ---
const SLIDE_TIME := 0.85
const SLIDE_COOLDOWN := 0.5
const SLIDE_MIN_SPEED := 5.0
const CROUCH_HOLD_PRONE := 0.45

const SLOT_ORDER := ["primary", "secondary", "melee"]
const START_LOADOUT := {"primary": "m5", "secondary": "p9", "melee": "knife"}

var max_hp := 100
var hp := 100
var armor := 0
const MAX_ARMOR := 150
var armor_cap := 150  # raised to 200 by the Juggernaut Carrier
## CODM-style armor plates: picked up as plates, applied via the ARMOR
## touch button with a 2s apply animation (+50 per plate).
var armor_plates := 0
const MAX_PLATES := 6
const PLATE_VALUE := 50
const PLATE_APPLY_TIME := 2.0
var _armor_timer := 0.0
## SoldierRig variant index for the player's character (set by main.gd from
## the character-select screen before add_child; default = hooded operator).
var char_variant := 4

# --- arsenal state ---
var slots := {"primary": null, "secondary": null, "melee": null}  # slot -> {id, mag, attach[]}
var cur_slot := "primary"
var ammo := {"light": 240, "medium": 150, "heavy": 40, "shell": 24, "rocket": 4, "grenade": 6, "smoke": 0, "none": 0}

# --- cash economy + vehicles ---
var cash := 0
var revive_kits := 0  # self-revive kits bought at buy stations
var gas_mask_t := 0.0  # collapse immunity from the buy-station gas mask
var fuel_cans := 0  # portable fuel canisters (max 2)
var touch_fuel_held := false  # touch FUEL button held (pump refuel)
# --- squad / BR identity ---
var downed := false  # incapacitated: crawl + bleed out, teammate can revive
var _bleed_t := 0.0
var carried_tags: Array = []  # dog tags of fallen teammates (redeploy at buy stations)
var squad_id := 0
var human_slot := 0  # 0 = local player; 1..30 RESERVED_FOR_ONLINE (Phase 2)
var reserved_online := false
var bot_name := "YOU"
var in_vehicle: NovaVehicle = null
var revive_token := false
var touch_up_held := false    # jump button held (heli ascend)
var touch_down_held := false  # crouch button held (heli descend)
var drive_gas := false        # touch GAS pedal held
var drive_brake := false      # touch BRK pedal held
var drive_hbrake := false     # touch handbrake held
var drive_nitro := false      # touch N2O held
var veh_cam_mode := 0        # 0 = driver POV, 1 = chase cam

var yaw := 0.0
var pitch := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_mobile := false
var ads := false

var _recoil := Vector2.ZERO
var _fire_cooldown := 0.0
var _reloading := false
var _reload_timer := 0.0
var _reload_dur := 1.0
var _touch_firing := false
var _was_firing := false
var _semi_armed := true
var _burst_left := 0
var _cycle_timer := 0.0
var _shot_index := 0
var _joy := Vector2.ZERO
var _dead := false
var _flash_timer := 0.0
var _since_damage := 99.0
# --- battle royale class system ---
var class_id := ""
var class_sys = null  # ClassSystem (attached by main.gd)
var class_speed_mult := 1.0
var invisible_t := 0.0  # wraith active camo
var dropping := false
var _chute: MeshInstance3D
var _rng := RandomNumberGenerator.new()

# viewmodel / fx
var _vm := {}  # build_viewmodel() result for current gun
var _audio_fire: AudioStreamPlayer
var _audio_one: AudioStreamPlayer
var _audio_boom: AudioStreamPlayer
var _tracers: Array = []
var _tracer_life: Array = []
var _shells: Array = []
var _shell_vel: Array = []
var _shell_life: Array = []
var _swap_timer := 0.0
var _melee_timer := 0.0
var _melee_did_hit := false
# --- executions / inspect / emotes ---
var _executing := false
var _exec_t := 0.0
var _exec_variant := 0
var _exec_victim: NovaEnemy = null
var _exec_slowmo := false
var _inspecting := false
var _inspect_t := 0.0
var _emote_wheel_open := false
var _sway := Vector2.ZERO
var _bob_t := 0.0

# --- character rig / FPP arms / stances ---
var _arms: SoldierArms
var _body_rig: SoldierRig
var _body_anim: SoldierAnim
var sprinting := false
var crouching := false
var proning := false
var sliding := false
var _slide_timer := 0.0
var _slide_cd := 0.0
var _slide_dir := Vector3.ZERO
var _crouch_hold_t := 0.0
var _crouch_holding := false
var _slide_dust: CPUParticles3D  # [FRAME] dust kick on slide
var _sprint_toggle := false
var _mobile_sprint := false
var _w_tap_t := -1.0
var _cooking := false
var _cook_t := 0.0
var _throw_anim_t := -1.0
var _pending_nade := {}
var _jump_ph := 0  # 0 grounded, 1 takeoff, 2 air, 3 land
var _jump_t := 0.0
var _last_input := Vector2.ZERO
var _shape_stand: CapsuleShape3D
var _shape_crouch: CapsuleShape3D
var _shape_prone: CapsuleShape3D

@onready var colshape: CollisionShape3D = $CollisionShape3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var gun: Node3D = $Head/Camera3D/Gun
@onready var muzzle: Node3D = $Head/Camera3D/Gun/Muzzle
@onready var muzzle_flash: MeshInstance3D = $Head/Camera3D/Gun/Muzzle/MuzzleFlash
@onready var muzzle_light: OmniLight3D = $Head/Camera3D/Gun/Muzzle/MuzzleLight

const GUN_HIP_POS := Vector3(0.34, -0.3, -0.55)


func _ready() -> void:
	is_mobile = DisplayServer.is_touchscreen_available()
	_rng.seed = 1234
	if not is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Remove the placeholder gun mesh; the arsenal builds real viewmodels.
	var old := gun.get_node_or_null("GunMesh")
	if old != null:
		old.queue_free()
	# Audio players.
	_audio_fire = AudioStreamPlayer.new()
	_audio_fire.bus = "Master"
	add_child(_audio_fire)
	_audio_one = AudioStreamPlayer.new()
	add_child(_audio_one)
	_audio_boom = AudioStreamPlayer.new()
	add_child(_audio_boom)
	# Tracer pool.
	for i in range(10):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.5)
		mi.set_surface_override_material(0, m)
		mi.visible = false
		get_tree().root.add_child.call_deferred(mi)
		_tracers.append(mi)
		_tracer_life.append(0.0)
	# Shell pool.
	for i in range(8):
		var sm := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.02, 0.02, 0.035)
		sm.mesh = sb
		sm.set_surface_override_material(0, GunModels._mat("brass"))
		sm.visible = false
		get_tree().root.add_child.call_deferred(sm)
		_shells.append(sm)
		_shell_vel.append(Vector3.ZERO)
		_shell_life.append(0.0)
	# Parachute canopy (hidden until a BR drop-in).
	_chute = MeshInstance3D.new()
	var canopy := BoxMesh.new()
	canopy.size = Vector3(3.4, 0.25, 3.4)
	_chute.mesh = canopy
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.45, 0.1)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.45, 0.1)
	cmat.emission_energy_multiplier = 0.35
	_chute.set_surface_override_material(0, cmat)
	_chute.position = Vector3(0, 2.8, 0)
	_chute.visible = false
	add_child(_chute)
	# Stance collision shapes.
	_shape_stand = CapsuleShape3D.new()
	_shape_stand.radius = 0.4
	_shape_stand.height = 1.7
	_shape_crouch = CapsuleShape3D.new()
	_shape_crouch.radius = 0.4
	_shape_crouch.height = 1.2
	_shape_prone = CapsuleShape3D.new()
	_shape_prone.radius = 0.4
	_shape_prone.height = 0.8
	# Third-person body (shadow + third-person moments; head hidden from own camera).
	_body_rig = SoldierRig.new()
	_body_rig.name = "BodyRig"
	add_child(_body_rig)
	_body_rig.set_variant(char_variant)  # set by main.gd from character select (default: hooded)
	_body_rig.hide_head_from_camera()
	_build_slide_dust()
	_body_anim = SoldierAnim.new()
	_body_anim.setup(_body_rig)
	_body_anim.name = "BodyAnim"
	add_child(_body_anim)
	# FPP arms viewmodel on the camera.
	_arms = SoldierArms.new()
	_arms.name = "FPPArms"
	camera.add_child(_arms)
	_reset_loadout()
	_equip_slot("primary", true)


# --- mythic skins: per-slot skin index (0 = standard), match kill counter ---
var mythic_kills := 0
var start_primary_id := ""
var start_skin := 0
var start_attach: Array = []


func set_starting_primary(gid: String, skin: int, attach: Array) -> void:
	start_primary_id = gid
	start_skin = skin
	start_attach = attach.duplicate()


func cur_skin() -> int:
	return int((_gun() as Dictionary).get("skin", 0))


func cur_gun_id() -> String:
	return str((_gun() as Dictionary)["id"])


func set_skin_for(slot: String, idx: int) -> void:
	if slots.get(slot) == null:
		return
	(slots[slot] as Dictionary)["skin"] = idx
	if slot == cur_slot:
		_equip_viewmodel_only()


## Register a player kill for mythic evolution. Returns milestone text ("")
## when the skin just evolved a stage, else "".
func register_mythic_kill() -> Dictionary:
	var before := MythicSkins.evolution_stage(mythic_kills)
	mythic_kills += 1
	var after := MythicSkins.evolution_stage(mythic_kills)
	var milestone := ""
	if after > before:
		milestone = MythicSkins.STAGE_NAMES[after]
		var r: Node = _vm.get("root", null)
		MythicSkins.set_evolution(r, after)
		_audio_one.stream = MythicSkins.evolution_sting()
		_audio_one.play()
	return {"kills": mythic_kills, "milestone": milestone}


func _reset_loadout() -> void:
	ammo = {"light": 240, "medium": 150, "heavy": 40, "shell": 24, "rocket": 4, "grenade": 6, "smoke": 0, "none": 0}
	for slot in SLOT_ORDER:
		var gid: String = START_LOADOUT[slot]
		var sk := 0
		var at: Array = []
		if slot == "primary" and start_primary_id != "":
			gid = start_primary_id
			sk = start_skin
			at = start_attach.duplicate()
		var g := GunDefs.by_id(gid)
		slots[slot] = {"id": gid, "mag": int(g["mag"]), "attach": at, "skin": sk}
		ammo[str(g["ammo"])] = int(ammo[str(g["ammo"])]) + int(g["reserve0"])


# ------------------------------------------------------------------ inventory
func _gun() -> Dictionary:
	return slots[cur_slot]


func _def() -> Dictionary:
	return GunDefs.by_id(str(_gun()["id"]))


func _eff() -> Dictionary:
	var st := _gun()
	return GunDefs.effective(_def(), st["attach"])


func cur_mag() -> int:
	return int(_gun()["mag"])


func cur_weapon_name() -> String:
	return GunDefs.full_name(_def())


func refresh_weapon_hud() -> void:
	_emit_weapon()
	_emit_ammo()
	var hud := _get_hud()
	if hud != null and hud.has_method("set_grenade_count"):
		hud.set_grenade_count(int(ammo["grenade"]))


func cur_reserve() -> int:
	return int(ammo[str(_def()["ammo"])])


func _emit_ammo() -> void:
	ammo_changed.emit(cur_mag(), cur_reserve())


func _emit_weapon() -> void:
	var g := _def()
	var wname := GunDefs.full_name(g)
	var skn := MythicSkins.skin_display_name(str(g["id"]), cur_skin())
	if skn != "":
		wname += " · " + skn
	weapon_changed.emit(wname)
	var hud := _get_hud()
	if hud != null and hud.has_method("update_weapon_stk"):
		hud.update_weapon_stk(GunDefs.stk_label(g))


## Give the player a gun (from a pickup). Returns the replaced gun id, or "".
func give_gun(gid: String, tier: int) -> String:
	var g := GunDefs.by_id(gid)
	if g.is_empty():
		return ""
	var slot: String = GunDefs.slot_of(str(g["cls"]))
	var old_id := ""
	if slots[slot] != null:
		old_id = str(slots[slot]["id"])
	slots[slot] = {"id": gid, "mag": int(g["mag"]),
		"attach": GunDefs.tier_attachments(tier, _rng), "skin": 0}
	ammo[str(g["ammo"])] = mini(int(ammo[str(g["ammo"])]) + int(g["reserve0"]), 999)
	_equip_slot(slot, true)
	return old_id


## Attach a loot attachment to the current gun. Returns success.
func attach_to_current(aid: String) -> bool:
	var a := GunDefs.find_attach(aid)
	if a.is_empty():
		return false
	var st := _gun()
	var atts: Array = st["attach"]
	var want_slot: String = str(a["slot"])
	# Replace any existing attachment in the same slot.
	var kept: Array = []
	for x in atts:
		if GunDefs.attach_slot(str(x)) != want_slot:
			kept.append(x)
	kept.append(aid)
	st["attach"] = kept
	slots[cur_slot] = st
	_equip_viewmodel_only()
	_emit_ammo()
	_audio_one.stream = GunAudio.reload_stream()
	_audio_one.play()
	return true


func swap_slot(i: int) -> void:
	if i < 0 or i >= SLOT_ORDER.size():
		return
	_equip_slot(SLOT_ORDER[i], false)


func cycle_weapon() -> void:
	var idx := SLOT_ORDER.find(cur_slot)
	for k in range(1, 4):
		var ns: String = SLOT_ORDER[(idx + k) % 3]
		if slots[ns] != null:
			_equip_slot(ns, false)
			return


func _equip_slot(slot: String, instant: bool) -> void:
	if slots[slot] == null or _dead:
		return
	if cur_slot == slot and not instant:
		return
	cur_slot = slot
	_semi_armed = true
	_burst_left = 0
	_cycle_timer = 0.0
	_reloading = false
	_equip_viewmodel_only()
	_emit_ammo()
	_emit_weapon()
	if not instant:
		_swap_timer = 0.35
		_audio_one.stream = GunAudio.reload_stream()
		_audio_one.pitch_scale = 1.4
		_audio_one.play()
		var _dtid := MythicSkins.skin_theme(cur_gun_id(), cur_skin())
		if _dtid != "":
			MythicSkins.play_draw_flourish(gun, _dtid)


func _equip_viewmodel_only() -> void:
	for c in gun.get_children():
		if c != muzzle:
			c.queue_free()
	_vm = GunModels.build_viewmodel(str(_gun()["id"]))
	gun.add_child(_vm["root"])
	muzzle.position = (_vm["muzzle"] as Node3D).position
	# Mythic skin: animated shader materials + geometry accents + evolution.
	var _gid := str(_gun()["id"])
	var _sk := cur_skin()
	MythicSkins.apply_to_model(_vm["root"], _gid, _sk, MythicSkins.evolution_stage(mythic_kills))
	muzzle_light.light_color = MythicSkins.flash_color(_gid, _sk)
	# Flash scale by class.
	var cls: String = str(_def()["cls"])
	var fs := 1.0
	if cls == "shotgun" or cls == "sniper":
		fs = 1.6
	elif cls == "launcher":
		fs = 2.2
	elif cls == "pistol":
		fs = 0.8
	muzzle_flash.scale = Vector3.ONE * fs
	if _arms != null:
		_arms.set_grip(_grip_for(str(_def()["cls"])))


func _grip_for(cls: String) -> String:
	match cls:
		"pistol":
			return "pistol"
		"launcher":
			return "launcher"
		"melee":
			return "melee"
		_:
			return "rifle"


func show_chute(b: bool) -> void:
	if _chute != null:
		_chute.visible = b


func is_alive() -> bool:
	return not _dead


# ---------------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if is_mobile:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := _mouse_look_sens()
		rotate_look(-event.relative.x * s, -event.relative.y * s)
		_sway.x = clampf(_sway.x - event.relative.x * 0.0004, -0.06, 0.06)
		_sway.y = clampf(_sway.y - event.relative.y * 0.0004, -0.04, 0.04)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		set_ads(event.pressed)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			start_reload()
		elif event.keycode == KEY_1:
			swap_slot(0)
		elif event.keycode == KEY_2:
			swap_slot(1)
		elif event.keycode == KEY_3:
			swap_slot(2)
		elif event.keycode == KEY_Q:
			cycle_weapon()
		elif event.keycode == KEY_G:
			start_grenade_cook()
		elif event.keycode == KEY_C:
			crouch_hold_down()
		elif event.keycode == KEY_Z:
			toggle_prone()
		elif event.keycode == KEY_T:
			start_inspect()
		elif event.keycode == KEY_X:
			toggle_emote_wheel()
	elif event is InputEventKey and not event.pressed and not event.echo:
		if event.keycode == KEY_G:
			release_grenade()
		elif event.keycode == KEY_C:
			crouch_hold_up()
		elif event.keycode == KEY_T:
			stop_inspect()


# ------------------------------------------------- stances / sprint / slide
func _apply_stance_shape() -> void:
	if sliding or proning:
		colshape.shape = _shape_prone if proning else _shape_crouch
		colshape.position.y = 0.4 if proning else 0.6
		head.position.y = 0.55 if proning else 1.0
	elif crouching:
		colshape.shape = _shape_crouch
		colshape.position.y = 0.6
		head.position.y = 1.05
	else:
		colshape.shape = _shape_stand
		colshape.position.y = 0.85
		head.position.y = 1.6


func _set_sprint(b: bool) -> void:
	if sprinting == b:
		return
	sprinting = b
	if b:
		_sprint_toggle = true
		if ads:
			set_ads(false)
	else:
		_sprint_toggle = false
		_mobile_sprint = false


func toggle_mobile_sprint() -> void:
	_mobile_sprint = not _mobile_sprint
	if not _mobile_sprint:
		_set_sprint(false)


func toggle_crouch() -> void:
	if _dead or downed:
		return
	if sliding:
		return
	if sprinting and is_on_floor():
		_start_slide()  # sprint + crouch = power slide
		return
	crouching = not crouching
	if crouching:
		proning = false
		_set_sprint(false)
	_apply_stance_shape()
	_body_anim.play("crouch_idle" if crouching else "idle", 0.18)


## Crouch-button hold (tap vs hold, CODM-style): quick tap = toggle crouch
## (or slide if sprinting); hold > 0.45 s = drop to prone on release.
func crouch_hold_down() -> void:
	if _dead or downed:
		return
	_crouch_hold_t = 0.0
	_crouch_holding = true
	if sliding:
		return
	if sprinting and is_on_floor():
		_start_slide()
		_crouch_holding = false  # slide consumed the press


func crouch_hold_up() -> void:
	if not _crouch_holding:
		return
	_crouch_holding = false
	if _dead or downed:
		return
	if _crouch_hold_t >= CROUCH_HOLD_PRONE and not sliding:
		if not proning:
			toggle_prone()  # held crouch -> prone (CODM)
	else:
		toggle_crouch()  # quick tap -> crouch / slide


func toggle_prone() -> void:
	if _dead or not is_on_floor() or sliding:
		return
	proning = not proning
	if proning:
		crouching = false
		_set_sprint(false)
	_apply_stance_shape()
	_body_anim.play("prone_idle" if proning else "idle", 0.22)


func _start_slide() -> void:
	if _slide_cd > 0.0:
		return  # slide cooldown (CODM chaining)
	sliding = true
	_slide_timer = SLIDE_TIME  # 0.85 s CODM-spec slide
	_slide_cd = SLIDE_TIME + SLIDE_COOLDOWN
	crouching = false
	_set_sprint(false)
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.5:
		_slide_dir = Vector3(hv.x, 0.0, hv.y).normalized()
	else:
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		_slide_dir = fwd.normalized()
	_apply_stance_shape()
	_body_anim.play("slide", 0.12)
	# [FRAME] visible dust kick behind the slide.
	if _slide_dust != null:
		_slide_dust.position = Vector3(0, 0.15, 0.45)
		_slide_dust.restart()


func _build_slide_dust() -> void:
	# One-shot billboard dust puff, kicked up behind the player on slide.
	_slide_dust = CPUParticles3D.new()
	_slide_dust.amount = 16
	_slide_dust.one_shot = true
	_slide_dust.explosiveness = 0.9
	_slide_dust.lifetime = 0.6
	_slide_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_slide_dust.emission_sphere_radius = 0.25
	_slide_dust.direction = Vector3(0, 0.7, 1.0)  # up and back (local +Z = behind)
	_slide_dust.spread = 30.0
	_slide_dust.initial_velocity_min = 1.5
	_slide_dust.initial_velocity_max = 3.5
	_slide_dust.gravity = Vector3(0, -4.0, 0)
	_slide_dust.scale_amount_min = 0.10
	_slide_dust.scale_amount_max = 0.25
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.62, 0.55, 0.45, 0.65)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = dmat
	_slide_dust.mesh = quad
	_slide_dust.emitting = false
	add_child(_slide_dust)


func _do_jump() -> void:
	velocity.y = JUMP_VELOCITY
	_jump_ph = 1
	_jump_t = 0.0
	_body_anim.play("jump_takeoff", 0.08)


func try_jump() -> void:
	if _dead or ads:
		return
	if sliding:
		sliding = false  # slide-cancel: pop upright, gun ready
		_apply_stance_shape()
		_body_anim.play("idle", 0.1)
	if is_on_floor():
		_do_jump()
	elif global_position.y < -0.2:
		velocity.y = 3.0


# ------------------------------------------------------------- grenades
func start_grenade_cook() -> void:
	if _dead or _cooking:
		return
	if int(ammo["grenade"]) <= 0:
		_audio_one.stream = GunAudio.dry_stream()
		_audio_one.play()
		return
	_cooking = true
	_cook_t = 0.0
	_set_sprint(false)
	_body_anim.play("grenade_cook", 0.12)
	_arms.set_throw_phase(0.0)


func release_grenade() -> void:
	if not _cooking:
		return
	_cooking = false
	ammo["grenade"] = int(ammo["grenade"]) - 1
	_body_anim.play_action("grenade_throw")
	_throw_anim_t = 0.0
	_pending_nade = {"cook": _cook_t, "delay": 0.42}  # spawn at the release frame
	_arms.set_throw_phase(0.35)
	var hud := _get_hud()
	if hud != null and hud.has_method("set_grenade_count"):
		hud.set_grenade_count(int(ammo["grenade"]))
	if hud != null and hud.has_method("start_cooldown"):
		hud.start_cooldown("grenade", 1.2)


func grenade_count() -> int:
	return int(ammo["grenade"])


# ------------------------------------------------- weapon inspect / emotes
## CODM-style weapon inspect: hold T (or INSPECT touch button). Character
## lifts and looks over the gun (~3 s). Cancelled by firing/moving.
func start_inspect() -> void:
	if _dead or _inspecting or _reloading or _executing:
		return
	_inspecting = true
	_inspect_t = 0.0
	_body_anim.play_action("inspect")
	var hud := _get_hud()
	if hud != null and hud.has_method("show_inspecting"):
		hud.show_inspecting(true)


func stop_inspect() -> void:
	if not _inspecting:
		return
	_inspecting = false
	var hud := _get_hud()
	if hud != null and hud.has_method("show_inspecting"):
		hud.show_inspecting(false)


func _update_inspect(delta: float) -> void:
	if not _inspecting:
		return
	if _was_firing or sprinting or sliding or _executing:
		stop_inspect()  # firing/moving cancels the inspect
		return
	_inspect_t += delta
	# Gun viewmodel lift + slow rotation while inspecting.
	var k := clampf(_inspect_t / 0.5, 0.0, 1.0)
	gun.position = gun.position.lerp(Vector3(0, -0.18, -0.35), 8.0 * delta)
	gun.rotation.y = lerpf(gun.rotation.y, sin(_inspect_t * 1.4) * 0.45, 6.0 * delta)
	gun.rotation.x = lerpf(gun.rotation.x, -0.12 * k, 6.0 * delta)
	if _inspect_t >= 3.0:
		stop_inspect()


func is_inspecting() -> bool:
	return _inspecting


const EMOTES := ["emote_wave", "emote_point", "emote_taunt", "emote_nod", "emote_shrug", "emote_salute"]


func toggle_emote_wheel() -> void:
	if _dead or downed:
		return
	_emote_wheel_open = not _emote_wheel_open
	var hud := _get_hud()
	if hud != null and hud.has_method("show_emote_wheel"):
		hud.show_emote_wheel(_emote_wheel_open)


func play_emote(idx: int) -> void:
	if _dead or _executing:
		return
	var i := clampi(idx, 0, EMOTES.size() - 1)
	_body_anim.play_action(EMOTES[i])
	_emote_wheel_open = false
	var hud := _get_hud()
	if hud != null and hud.has_method("show_emote_wheel"):
		hud.show_emote_wheel(false)


func is_executing() -> bool:
	return _executing


## Match-end victory pose (called by main.gd on last-one-standing win).
func play_victory() -> void:
	if _dead or downed:
		return
	_body_anim.play_action("victory" if randi() % 2 == 0 else "victory_casual")


func _spawn_grenade(cook: float) -> void:
	var basis_t := camera.global_transform.basis
	var from: Vector3 = camera.global_transform.origin - basis_t.z * 0.6 + Vector3(0, -0.05, 0)
	var dir := -basis_t.z
	var g := FragGrenade.throw_from(from, dir, 15.0, cook, self)
	var scene := get_tree().current_scene
	(scene if scene != null else get_tree().root).add_child(g)


func _input(event: InputEvent) -> void:
	if is_mobile and event is InputEventScreenDrag:
		var hud := _get_hud()
		if hud != null and hud.consume_look_drag(event):
			var s := _touch_look_sens()
			var d := _assist_delta(-event.relative.x * s, -event.relative.y * s)
			rotate_look(d.x, d.y)


# ---------------- controller settings (CODM-style) ----------------

## Current optic zoom (0 = iron/red-dot/holo, 4 / 8 = magnified optics).
func _ads_zoom() -> float:
	if not ads:
		return 0.0
	return float(_eff().get("zoom", 0.0))


func _ads_sens_mult() -> float:
	var z := _ads_zoom()
	if z >= 8.0:
		return ControlSettings.zoom8_sens
	if z >= 4.0:
		return ControlSettings.zoom4_sens
	if ads:
		return ControlSettings.ads_sens
	return 1.0


func _touch_look_sens() -> float:
	return TOUCH_SENS * ControlSettings.cam_sens * _ads_sens_mult()


func _mouse_look_sens() -> float:
	return MOUSE_SENS * ControlSettings.cam_sens * _ads_sens_mult()


## Aim assist: crosshair magnetism (slowdown near targets) + gentle
## rotational pull while ADS. Subtle by design — never a hard lock.
func _assist_delta(dx: float, dy: float) -> Vector2:
	if not ControlSettings.aim_assist or ControlSettings.assist_strength <= 0.01:
		return Vector2(dx, dy)
	var hud := _get_hud()
	if hud == null or not ("enemies" in hud):
		return Vector2(dx, dy)
	var strength := ControlSettings.assist_strength
	var fwd := -camera.global_transform.basis.z
	var best: Node3D = null
	var best_ang := 0.16  # ~9 degree assist cone
	for e in hud.enemies:
		if e == null or not is_instance_valid(e):
			continue
		if not e.is_alive():
			continue
		var chest: Vector3 = e.global_position + Vector3(0, 1.2, 0)
		var to: Vector3 = chest - camera.global_position
		var dist := to.length()
		if dist < 0.5 or dist > 90.0:
			continue
		var ang := fwd.angle_to(to / dist)
		if ang < best_ang:
			best_ang = ang
			best = e
	if best == null:
		return Vector2(dx, dy)
	# Magnetism: slow the look as the crosshair nears the target.
	var slow := 1.0 - strength * 0.55 * (1.0 - best_ang / 0.16)
	var nd := Vector2(dx, dy) * slow
	if ads:
		var chest2: Vector3 = best.global_position + Vector3(0, 1.2, 0)
		var to2: Vector3 = chest2 - camera.global_position
		var want_yaw := atan2(-to2.x, -to2.z)
		var dyaw := wrapf(want_yaw - yaw, -PI, PI)
		var flat := Vector2(to2.x, to2.z).length()
		var want_pitch := atan2(to2.y, maxf(flat, 0.01))
		var dpitch := clampf(wrapf(want_pitch - pitch, -PI, PI), -0.2, 0.2)
		var cap := 0.012 * strength
		nd.x += clampf(dyaw * 0.16 * strength, -cap, cap)
		nd.y += clampf(dpitch * 0.16 * strength, -cap, cap)
	return nd


## Simple fire mode (CODM "Simple mode"): auto-fire when an enemy is under
## the crosshair.
func _simple_mode_has_target() -> bool:
	var hud := _get_hud()
	if hud == null or not ("enemies" in hud):
		return false
	var ctr := get_viewport().get_visible_rect().size * 0.5
	for e in hud.enemies:
		if e == null or not is_instance_valid(e):
			continue
		if not e.is_alive():
			continue
		var chest: Vector3 = e.global_position + Vector3(0, 1.2, 0)
		if camera.is_position_behind(chest):
			continue
		if (chest - camera.global_position).length() > 70.0:
			continue
		var sp := camera.unproject_position(chest)
		if (sp - ctr).length() < 48.0:
			return true
	return false


var _hud_override = null  # test hook: bypass scene lookup


# ---------------- controller update (gyro + armor plates) ----------------

## Per-frame controller update: gyroscope aim and armor-plate apply timer.
## Extracted from _process so tests can drive it directly.
func _update_controller(delta: float) -> void:
	# Gyroscope aim (mobile, optional; no-ops without a gyro sensor).
	if is_mobile and ControlSettings.gyro_enabled and not _dead:
		var g := Input.get_gyroscope()
		if g.length() > 0.02:
			var gs := ControlSettings.gyro_sens
			rotate_look(g.y * gs * delta, -g.x * gs * delta)
	# Armor plate apply timer (CODM 2s apply, +50 on finish).
	if _armor_timer > 0.0:
		_armor_timer -= delta
		if _armor_timer <= 0.0:
			armor = mini(armor + PLATE_VALUE, armor_cap)
			health_changed.emit(hp, max_hp, armor)


## Haptic tick guarded to real mobile OS builds (no-op elsewhere).
func _vibrate(ms: int) -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		Input.vibrate_handheld(ms)


func _get_hud() -> Node:
	if _hud_override != null:
		return _hud_override
	var scene := get_tree().current_scene
	if scene != null and "hud" in scene:
		return scene.hud
	return null


func rotate_look(dx: float, dy: float) -> void:
	yaw += dx
	var iy := -1.0 if ControlSettings.invert_y else 1.0
	pitch = clampf(pitch + dy * iy, -1.35, 1.35)
	rotation.y = yaw
	head.rotation.x = pitch


func set_joystick(v: Vector2) -> void:
	_joy = v


func set_touch_firing(b: bool) -> void:
	_touch_firing = b


func set_ads(b: bool) -> void:
	if _dead or _reloading or sprinting:
		b = false
	var mode: String = str(_def()["mode"])
	if mode == "melee":
		b = false
	if ads == b:
		return
	ads = b
	var hud := _get_hud()
	if hud != null and hud.has_method("set_ads_state"):
		hud.set_ads_state(ads)


func start_reload() -> void:
	if _dead or _reloading:
		return
	var st := _gun()
	var e := _eff()
	var mode: String = str(_def()["mode"])
	if mode == "melee":
		return
	if int(st["mag"]) >= int(e["mag"]) or cur_reserve() <= 0:
		return
	_reloading = true
	_reload_dur = float(e["reload"])
	_reload_timer = _reload_dur
	if ads:
		set_ads(false)
	# Body reload animation per weapon class.
	var rcls := str(_def()["cls"])
	var ract := "reload_rifle"
	if rcls == "pistol":
		ract = "reload_pistol"
	elif rcls == "launcher":
		ract = "reload_launcher"
	elif rcls == "melee":
		ract = "reload_melee"
	_body_anim.play_action(ract)
	_audio_one.stream = GunAudio.reload_stream()
	_audio_one.pitch_scale = 1.0
	_audio_one.play()
	# Mythic reload flourish: theme energy puff at the gun.
	var _rtid := MythicSkins.skin_theme(cur_gun_id(), cur_skin())
	if _rtid != "":
		MythicSkins.play_reload_flourish(gun, _rtid)
	var hud := _get_hud()
	if hud != null and hud.has_method("show_reloading"):
		hud.show_reloading(true)


func _finish_reload() -> void:
	var st := _gun()
	var e := _eff()
	var atype: String = str(_def()["ammo"])
	var need: int = int(e["mag"]) - int(st["mag"])
	var take: int = mini(need, int(ammo[atype]))
	st["mag"] = int(st["mag"]) + take
	ammo[atype] = int(ammo[atype]) - take
	slots[cur_slot] = st
	_reloading = false
	_emit_ammo()
	var hud := _get_hud()
	if hud != null and hud.has_method("show_reloading"):
		hud.show_reloading(false)


func add_ammo(n: int) -> void:
	var atype: String = str(_def()["ammo"])
	ammo[atype] = mini(int(ammo[atype]) + n, 999)
	_emit_ammo()


## Caliber-specific ammo (from loot boxes / death boxes).
func add_ammo_caliber(caliber: String, n: int) -> void:
	if not ammo.has(caliber):
		return
	ammo[caliber] = mini(int(ammo[caliber]) + n, 999)
	_emit_ammo()


func add_grenades(n: int) -> void:
	ammo["grenade"] = mini(int(ammo["grenade"]) + n, 12)
	var hud := _get_hud()
	if hud != null and hud.has_method("set_grenade_count"):
		hud.set_grenade_count(int(ammo["grenade"]))


func add_smoke(n: int) -> void:
	ammo["smoke"] = mini(int(ammo["smoke"]) + n, 6)
	_refresh_smoke_btn()


func smoke_count() -> int:
	return int(ammo["smoke"])


func _refresh_smoke_btn() -> void:
	var hud := _get_hud()
	if hud != null and hud.has_method("set_smoke_count"):
		hud.set_smoke_count(int(ammo["smoke"]))


## Instant smoke throw (no cooking): lobs a canister that blooms into a
## vision-blocking cloud on landing.
func throw_smoke() -> void:
	if _dead or _cooking:
		return
	if int(ammo["smoke"]) <= 0:
		return
	ammo["smoke"] = int(ammo["smoke"]) - 1
	_body_anim.play_action("grenade_throw")
	_arms.set_throw_phase(0.35)
	var basis_t := camera.global_transform.basis
	var from: Vector3 = camera.global_transform.origin - basis_t.z * 0.6 + Vector3(0, -0.05, 0)
	var dir := -basis_t.z
	var g := SmokeGrenade.throw_from(from, dir, 14.0, self)
	var scene := get_tree().current_scene
	(scene if scene != null else get_tree().root).add_child(g)
	_refresh_smoke_btn()
	var hud := _get_hud()
	if hud != null and hud.has_method("start_cooldown"):
		hud.start_cooldown("smoke", 1.0)


func add_armor(n: int) -> void:
	armor = mini(armor + n, armor_cap)
	health_changed.emit(hp, max_hp, armor)


## Armor plate pickup (from loot): plates are applied via apply_armor_plate().
func add_armor_plate() -> void:
	if _dead or downed:
		return
	if armor_plates < MAX_PLATES:
		armor_plates += 1
	_refresh_armor_btn()


## CODM-style plate apply: 2s animation, +50 armor, cannot fire meanwhile.
func apply_armor_plate() -> void:
	if _dead or _armor_timer > 0.0 or armor_plates <= 0 or armor >= armor_cap:
		return
	if _reloading:
		return
	armor_plates -= 1
	_armor_timer = PLATE_APPLY_TIME
	_refresh_armor_btn()
	var hud := _get_hud()
	if hud != null and hud.has_method("start_cooldown"):
		hud.start_cooldown("armor", PLATE_APPLY_TIME)


func _refresh_armor_btn() -> void:
	var hud := _get_hud()
	if hud != null and hud.has_method("set_armor_plates"):
		hud.set_armor_plates(armor_plates)


func heal(n: int) -> void:
	if class_sys != null:
		n = class_sys.modify_heal(n)
	hp = mini(hp + n, max_hp)
	health_changed.emit(hp, max_hp, armor)


# ---------------- cash economy ----------------
func add_cash(n: int) -> void:
	cash = mini(cash + n, 99999)
	var hud := _get_hud()
	if hud != null and hud.has_method("update_cash"):
		hud.update_cash(cash)


func spend_cash(n: int) -> bool:
	if cash < n:
		return false
	cash -= n
	var hud := _get_hud()
	if hud != null and hud.has_method("update_cash"):
		hud.update_cash(cash)
	return true


func refill_all_ammo() -> void:
	for k in ammo.keys():
		if k != "none" and k != "grenade":
			ammo[k] = 999
	ammo["grenade"] = 6


func add_ammo_all(n: int) -> void:
	for k in ammo.keys():
		if k != "none" and k != "grenade":
			ammo[k] = mini(int(ammo[k]) + n, 999)
	_emit_ammo()


# ---------------- vehicles ----------------
func drive_move_input() -> Vector2:
	if is_mobile:
		if in_vehicle != null and ControlSettings.tilt_steering:
			var acc := Input.get_accelerometer()
			return Vector2(clampf(-acc.x * 1.4, -1.0, 1.0), _joy.y)
		return _joy
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func drive_up_held() -> bool:
	if is_mobile:
		return touch_up_held
	return Input.is_key_pressed(KEY_SPACE)


func drive_down_held() -> bool:
	if is_mobile:
		return touch_down_held
	return Input.is_key_pressed(KEY_C)


func wants_fire() -> bool:
	if is_mobile:
		return _touch_firing
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func enter_vehicle(v: NovaVehicle) -> void:
	if in_vehicle != null or v == null or v.is_destroyed():
		return
	in_vehicle = v
	v.enter(self)
	visible = false
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	velocity = Vector3.ZERO
	var hud := _get_hud()
	if hud != null and hud.has_method("show_vehicle"):
		hud.show_vehicle(v)


func _apply_veh_camera() -> void:
	# Driver POV (0) vs chase cam (1). Gun viewmodel hidden in chase.
	if camera == null:
		return
	if in_vehicle != null and veh_cam_mode == 1:
		camera.position = Vector3(0, 3.0, 7.5)
		if gun != null:
			gun.visible = false
		if _arms != null:
			_arms.visible = false
	else:
		camera.position = Vector3.ZERO
		if gun != null:
			gun.visible = true
		if _arms != null:
			_arms.visible = true


func exit_vehicle() -> void:
	if in_vehicle == null:
		return
	var v := in_vehicle
	in_vehicle = null
	var exit_pos: Vector3 = v.exit()
	visible = true
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	global_position = exit_pos
	velocity = Vector3.ZERO
	_apply_veh_camera()
	var hud := _get_hud()
	if hud != null and hud.has_method("hide_vehicle"):
		hud.hide_vehicle()


# -------------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	if _dead:
		return
	if downed:
		_downed_physics(delta)
		return
	if in_vehicle != null:
		# Driving: ride the seat, camera follows the vehicle.
		if is_instance_valid(in_vehicle):
			global_position = in_vehicle.seat_position()
			yaw = in_vehicle.rotation.y
			rotation.y = yaw
			_apply_veh_camera()
		else:
			in_vehicle = null
			_apply_veh_camera()
		return
	if _slide_cd > 0.0:
		_slide_cd -= delta
	if gas_mask_t > 0.0:
		gas_mask_t -= delta
	if _crouch_holding:
		_crouch_hold_t += delta
	_update_execution(delta)
	_update_inspect(delta)
	if dropping:
		velocity.y = move_toward(velocity.y, -14.0, 40.0 * delta)
		var dinput := Vector2.ZERO
		if is_mobile:
			dinput = _joy
		else:
			dinput = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var ddir := (transform.basis * Vector3(dinput.x, 0.0, dinput.y))
		if ddir.length() > 0.01:
			ddir = ddir.normalized()
			velocity.x = ddir.x * 11.0
			velocity.z = ddir.z * 11.0
		else:
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		move_and_slide()
		if is_on_floor() or global_position.y < 1.0:
			dropping = false
			show_chute(false)
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	var in_water := global_position.y < -0.2
	if not is_on_floor() and global_position.y < 0.1:
		var depth := -0.25 - global_position.y
		var target_vy := clampf(depth * 9.0, -2.5, 3.0)
		velocity.y = move_toward(velocity.y, target_vy, 28.0 * delta)
	if not is_mobile and Input.is_action_just_pressed("ui_accept") and is_on_floor() and not ads:
		_do_jump()
	var input_dir := Vector2.ZERO
	if is_mobile:
		input_dir = _joy
	else:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_last_input = input_dir
	# Sprint: Shift hold, double-tap W toggle, or mobile sprint toggle.
	if not is_mobile:
		if Input.is_action_just_pressed("move_forward"):
			var now := Time.get_ticks_msec() / 1000.0
			if _w_tap_t > 0.0 and now - _w_tap_t < 0.32:
				_sprint_toggle = true
			_w_tap_t = now
		if not Input.is_action_pressed("move_forward"):
			_sprint_toggle = false
	var shift_held := (not is_mobile) and Input.is_key_pressed(KEY_SHIFT)
	var fwd := input_dir.y < -0.1
	var want_sprint := (shift_held or _sprint_toggle or _mobile_sprint) and fwd \
		and is_on_floor() and not ads and not crouching and not proning \
		and not sliding and not _reloading
	_set_sprint(want_sprint)
	var e := _eff()
	var speed := SPEED * float(e["move"])
	speed *= class_speed_mult
	if ads:
		speed *= ADS_SLOW
	if sprinting:
		speed *= 1.38
	if crouching:
		speed *= 0.5
	if proning:
		speed *= 0.32
	if in_water:
		speed *= 0.55
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if sliding:
		# Power slide: keep momentum, slight decay. CAN SHOOT mid-slide.
		_slide_timer -= delta
		var sp := maxf(Vector2(velocity.x, velocity.z).length(), SLIDE_MIN_SPEED)
		velocity.x = _slide_dir.x * sp
		velocity.z = _slide_dir.z * sp
		_bob_t += delta * sp
		if _slide_timer <= 0.0:
			sliding = false
			_apply_stance_shape()
			_body_anim.play("idle", 0.2)
	elif dir.length() > 0.01:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_bob_t += delta * speed * 1.6
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
	move_and_slide()
	var pos := global_position
	var ext := 72.0
	var scene := get_tree().current_scene
	if scene != null and "map_extent" in scene:
		ext = float(scene.map_extent) + 2.0
	pos.x = clampf(pos.x, -ext, ext)
	pos.z = clampf(pos.z, -ext, ext)
	if pos.y < -8.0:
		respawn()
		return
	global_position = pos


# -------------------------------------------------------------------- process
func _process(delta: float) -> void:
	invisible_t = maxf(0.0, invisible_t - delta)
	_update_fx(delta)
	_update_character(delta)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			muzzle_flash.visible = false
			muzzle_light.visible = false
	if _recoil.length() > 0.001:
		_recoil = _recoil.move_toward(Vector2.ZERO, 2.2 * delta)
		rotation.y = yaw + _recoil.x
		head.rotation.x = pitch + _recoil.y
	# Gyroscope aim + armor plate timer (extracted for testability).
	_update_controller(delta)
	# ADS blend: per-gun speed, position, FOV.
	var e := _eff()
	var ads_spd := 6.0 / maxf(float(e["ads"]) * 4.0, 0.4)
	var sight_h := GunModels.sight_height(str(_gun()["id"]))
	var target_pos := Vector3(0, -sight_h, -0.42) if ads else GUN_HIP_POS
	gun.position = gun.position.lerp(target_pos, minf(ads_spd, 30.0) * delta)
	var zoom: float = float(e["zoom"])
	var hip_fov := HIP_FOV + (8.0 if sprinting and not ads else 0.0)  # sprint FOV kick
	var target_fov := hip_fov / (1.0 + zoom * 0.25) if (ads and zoom > 0.0) else (ADS_FOV if ads else hip_fov)
	camera.fov = lerpf(camera.fov, target_fov, minf(ads_spd, 30.0) * delta)
	# Reload anim: dip + tilt in phases.
	if _reloading:
		var t := 1.0 - _reload_timer / maxf(_reload_dur, 0.01)
		var rstyle := str((GunDefs.by_id(str(_gun()["id"]))["model"] as Dictionary).get("style", ""))
		if rstyle == "rpg7":
			# Front-load warhead: muzzle tips up toward the loader, twist, settle.
			var ph := sin(t * PI)
			gun.rotation.x = -ph * 0.75
			gun.rotation.y = ph * 0.4 * sin(t * PI * 2.0)
			gun.position.y -= ph * 0.10
			gun.position.z += ph * 0.10
		else:
			var dip := sin(t * PI)
			gun.rotation.x = dip * 0.55
			gun.rotation.z = dip * 0.35 * sin(t * PI * 2.0)
			gun.position.y -= dip * 0.12
	elif _swap_timer > 0.0:
		_swap_timer -= delta
		gun.position.y -= sin((_swap_timer / 0.35) * PI) * 0.18
		gun.rotation.x = sin((_swap_timer / 0.35) * PI) * 0.5
	elif _melee_timer > 0.0:
		_melee_timer -= delta
		var mt := 1.0 - _melee_timer / 0.45
		gun.rotation.z = -sin(mt * PI) * 1.2
		gun.position.x += sin(mt * PI) * 0.15
		if not _melee_did_hit and mt > 0.35:
			_melee_did_hit = true
			_melee_hit()
	else:
		# Sway recovery + walk bob.
		_sway = _sway.move_toward(Vector2.ZERO, 3.0 * delta)
		gun.rotation.x = lerpf(gun.rotation.x, _sway.y, 10.0 * delta)
		gun.rotation.y = lerpf(gun.rotation.y, _sway.x, 10.0 * delta)
		gun.rotation.z = lerpf(gun.rotation.z, 0.0, 10.0 * delta)
		var hv := Vector2(velocity.x, velocity.z).length()
		if hv > 0.5 and is_on_floor():
			gun.position.y += sin(_bob_t * 2.0) * 0.008
			gun.position.x += cos(_bob_t) * 0.006
	if _dead or downed:
		return
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
		return
	_since_damage += delta
	if _since_damage >= REGEN_DELAY and hp < max_hp:
		hp = mini(int(hp + REGEN_RATE * delta), max_hp)
		health_changed.emit(hp, max_hp, armor)
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta
	if _cycle_timer > 0.0:
		_cycle_timer -= delta
	# Trigger edge tracking (for semi / melee).
	var want_fire := _touch_firing
	if not is_mobile and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		want_fire = want_fire or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# Simple fire mode: auto-fire when an enemy is under the crosshair.
	if ControlSettings.fire_mode == "simple" and is_mobile and not _touch_firing and not _dead:
		if _simple_mode_has_target():
			want_fire = true
	# Cannot fire while applying an armor plate (CODM behavior).
	if _armor_timer > 0.0:
		want_fire = false
	var pressed_edge := want_fire and not _was_firing
	_was_firing = want_fire
	if pressed_edge and is_mobile and ControlSettings.haptics:
		_vibrate(12)
	var mode: String = str(_def()["mode"])
	if _fire_cooldown > 0.0 or _cycle_timer > 0.0 or _melee_timer > 0.0:
		return
	if mode == "melee":
		if pressed_edge:
			_melee_swing()
	elif mode == "burst":
		if pressed_edge and _burst_left <= 0:
			_burst_left = int(_def().get("burst_n", 3))
		if want_fire and _burst_left > 0:
			_fire_bullet()
			_burst_left -= 1
	elif mode == "semi":
		if pressed_edge and _semi_armed:
			_semi_armed = false
			_fire_bullet()
		if not want_fire:
			_semi_armed = true
	elif mode == "rocket" or mode == "grenade":
		if pressed_edge:
			_fire_projectile()
	else:  # auto / pump / bolt
		if want_fire:
			_fire_bullet()


func _fire_bullet() -> void:
	var st := _gun()
	if int(st["mag"]) <= 0:
		_fire_cooldown = 0.3
		_audio_one.stream = GunAudio.dry_stream()
		_audio_one.play()
		start_reload()
		return
	st["mag"] = int(st["mag"]) - 1
	slots[cur_slot] = st
	var e := _eff()
	var def := _def()
	var mode: String = str(def["mode"])
	_fire_cooldown = 60.0 / maxf(float(e["rpm"]), 1.0)
	_shot_index += 1
	_play_fire_sound()
	# Bot hearing: unsuppressed shots attract nearby squads — they investigate
	# the sound position (hearing, not wallhack targeting).
	if not bool(e["silent"]):
		var scene_h := get_tree().current_scene
		if scene_h != null and scene_h.has_method("on_player_fired"):
			scene_h.on_player_fired(global_position)
	# Muzzle flash.
	muzzle_flash.visible = true
	_flash_timer = 0.06
	if not bool(e["silent"]):
		muzzle_light.visible = true
	# Per-gun recoil with slight pattern alternation.
	var alt := 1.0 if _shot_index % 2 == 0 else -1.0
	var kick := (0.010 if ads else 0.018) * float(e["recv"]) / 0.015
	_recoil.y += kick + randf() * 0.006
	_recoil.x += alt * float(e["rech"]) * 0.7 + randf_range(-0.006, 0.006)
	_eject_shell()
	_emit_ammo()
	# Character feedback: body jolt + FPP arm kick; firing breaks sprint.
	_body_anim.add_jolt(0.7)
	_arms.add_kick(kick * 0.6)
	if sprinting:
		_set_sprint(false)
	var scene := get_tree().current_scene
	if mode == "shotgun" or str(def["cls"]) == "shotgun":
		_fire_pellets(e, def, scene)
	else:
		_fire_hitscan(e, def, scene, _class_dmg_mult())
	# Pump / bolt cycle delay.
	if mode == "pump":
		_cycle_timer = 0.75
	elif mode == "bolt":
		_cycle_timer = 0.95
		gun.position.z += 0.06  # bolt pull nudge


func _fire_hitscan(e: Dictionary, def: Dictionary, scene: Node, dmg_mult: float) -> void:
	var from := camera.global_transform.origin
	var spread: float = 0.0 if ads else float(e["spread"])
	var fwd := -camera.global_transform.basis.z
	var dir := (fwd + camera.global_transform.basis.x * randf_range(-spread, spread)
		+ camera.global_transform.basis.y * randf_range(-spread, spread)).normalized()
	var rng: float = float(def["range_far"]) * 1.6
	var to := from + dir * rng
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_spawn_tracer(dir, rng if hit.is_empty() else from.distance_to(hit["position"]), e)
	if hit.is_empty():
		return
	var point: Vector3 = hit["position"]
	var collider: Object = hit["collider"]
	if collider != null and is_instance_valid(collider) and collider.is_in_group("enemies") \
			and collider.has_method("take_damage"):
		var dist: float = from.distance_to(point)
		var hs: bool = collider.has_method("is_headshot") and collider.is_headshot(point)
		var hm := GunDefs.headshot_mult(str(def["cls"])) if hs else 1.0
		var dmg := int(GunDefs.damage_at_range(def, dist) * dmg_mult * hm)
		var was_alive: bool = collider.is_alive() if collider.has_method("is_alive") else true
		collider.take_damage(dmg, point, "bullet", hs)
		if class_sys != null:
			class_sys.on_damaged_enemy(collider)
		hit_confirmed.emit(false)
		if scene != null and scene.has_method("on_enemy_damaged"):
			scene.on_enemy_damaged(collider, was_alive)
	elif scene != null and scene.has_method("spawn_impact"):
		var n: Vector3 = hit.get("normal", Vector3.UP)
		scene.spawn_impact(point, n)


func _fire_pellets(e: Dictionary, def: Dictionary, scene: Node) -> void:
	var pellets := int(def.get("pellets", 8))
	for i in range(pellets):
		var from := camera.global_transform.origin
		var spread: float = (0.02 if ads else float(e["spread"])) + 0.035
		var fwd := -camera.global_transform.basis.z
		var dir := (fwd + camera.global_transform.basis.x * randf_range(-spread, spread)
			+ camera.global_transform.basis.y * randf_range(-spread, spread)).normalized()
		var rng: float = float(def["range_far"]) * 1.4
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * rng)
		query.exclude = [self]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var point: Vector3 = hit["position"]
		var collider: Object = hit["collider"]
		if collider != null and is_instance_valid(collider) and collider.is_in_group("enemies") \
				and collider.has_method("take_damage"):
			var dist: float = from.distance_to(point)
			var hs: bool = collider.has_method("is_headshot") and collider.is_headshot(point)
			var hm := GunDefs.headshot_mult(str(def["cls"])) if hs else 1.0
			var dmg := int(GunDefs.damage_at_range(def, dist) * _class_dmg_mult() * hm)
			var was_alive: bool = collider.is_alive() if collider.has_method("is_alive") else true
			collider.take_damage(dmg, point, "bullet", hs)
			if class_sys != null:
				class_sys.on_damaged_enemy(collider)
			hit_confirmed.emit(false)
			if scene != null and scene.has_method("on_enemy_damaged"):
				scene.on_enemy_damaged(collider, was_alive)
	_spawn_tracer(-camera.global_transform.basis.z, 12.0, e)


func _fire_projectile() -> void:
	var st := _gun()
	if int(st["mag"]) <= 0:
		_audio_one.stream = GunAudio.dry_stream()
		_audio_one.play()
		start_reload()
		return
	st["mag"] = int(st["mag"]) - 1
	slots[cur_slot] = st
	var def := _def()
	var e := _eff()
	_fire_cooldown = 60.0 / maxf(float(e["rpm"]), 1.0)
	_play_fire_sound()
	# Launcher fire is loud: bots hear it too.
	var scene_h2 := get_tree().current_scene
	if scene_h2 != null and scene_h2.has_method("on_player_fired"):
		scene_h2.on_player_fired(global_position)
	muzzle_flash.visible = true
	muzzle_light.visible = true
	_flash_timer = 0.12
	_recoil.y += 0.05
	_emit_ammo()
	_body_anim.add_jolt(1.4)
	_arms.add_kick(0.05)
	if sprinting:
		_set_sprint(false)
	var dir := -camera.global_transform.basis.z
	var p := GunProjectile.launch(muzzle.global_position, dir,
		float(def.get("proj_speed", 40.0)), float(def.get("proj_grav", 0.2)),
		float(def.get("blast", 4.0)), float(e["damage"]), self)
	get_tree().current_scene.add_child(p)


func _melee_swing() -> void:
	# Stealth execution first: behind an unaware enemy within 2.2 m.
	if _try_execution():
		return
	_fire_cooldown = 60.0 / maxf(float(_eff()["rpm"]), 1.0)
	_melee_timer = 0.45
	_melee_did_hit = false
	_body_anim.play_action("melee_lunge")
	if sprinting:
		_set_sprint(false)
	_audio_one.stream = GunAudio.swing_stream()
	_audio_one.pitch_scale = float(_def()["pitch"])
	_audio_one.play()
	# Small forward lunge.
	var fwd := -global_transform.basis.z
	velocity += Vector3(fwd.x, 0, fwd.z) * 2.2


## CODM-style stealth execution: directly behind an UNAWARE enemy within
## 2.2 m. Synced takedown: attacker clip + victim clip + instant kill.
## Returns true if an execution started.
func _try_execution() -> bool:
	if _executing or _dead:
		return false
	var best: NovaEnemy = null
	var best_d := 2.2
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as NovaEnemy
		if e == null or not e.is_alive() or e.is_engaged():
			continue  # must be unaware
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		# Behind check: enemy facing away from player (vector enemy->player
		# points opposite the enemy's forward, dot < -0.35 ~ >110 deg cone).
		var efwd := -e.global_transform.basis.z
		efwd.y = 0.0
		var away: Vector3 = (global_position - e.global_position)
		away.y = 0.0
		if away.normalized().dot(efwd.normalized()) < -0.35:
			best = e
			best_d = d
	if best == null:
		return false
	# Lock both into the synced takedown.
	_executing = true
	_exec_t = 0.0
	_exec_victim = best
	var variant := randi() % 3
	_exec_variant = variant
	var atk: String = ["exec_necksnap", "exec_throat", "exec_silent"][variant]
	_body_anim.play_action(atk)
	# Face the victim and step in.
	var look: Vector3 = best.global_position - global_position
	look.y = 0.0
	yaw = atan2(-look.x, -look.z)
	rotation.y = yaw
	velocity = Vector3.ZERO
	best.play_execution_victim(variant)
	# Premium feel: brief slow-mo + sound emphasis.
	Engine.time_scale = 0.35
	_exec_slowmo = true
	_audio_one.stream = GunAudio.swing_stream()
	_audio_one.pitch_scale = 0.6
	_audio_one.play()
	var hud := _get_hud()
	if hud != null and hud.has_method("show_execution"):
		hud.show_execution()
	return true


func _update_execution(delta: float) -> void:
	if not _executing:
		return
	_exec_t += delta / maxf(Engine.time_scale, 0.01)  # real-time seconds
	if _exec_slowmo and _exec_t >= 0.45:
		Engine.time_scale = 1.0
		_exec_slowmo = false
	if _exec_t >= 1.45:
		_executing = false
		_exec_victim = null
		Engine.time_scale = 1.0
		_exec_slowmo = false



func _melee_hit() -> void:
	var def := _def()
	var reach: float = float(def["range_near"])
	var fwd := -global_transform.basis.z
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Node3D and n.has_method("take_damage") and n.has_method("is_alive") and (n as Node).is_alive():
			var to: Vector3 = (n as Node3D).global_position - global_position
			if to.length() <= reach + 0.6 and fwd.dot(to.normalized()) > 0.45:
				(n as Node).take_damage(int(float(def["damage"]) * _class_dmg_mult()), (n as Node3D).global_position, "melee")
				hit_confirmed.emit(false)
				var scene := get_tree().current_scene
				if scene != null and scene.has_method("on_enemy_damaged"):
					scene.on_enemy_damaged(n, true)


func on_projectile_hit(_e: Node) -> void:
	hit_confirmed.emit(false)


func play_explosion_sound() -> void:
	_audio_boom.stream = GunAudio.explosion_stream()
	_audio_boom.play()


func _play_fire_sound() -> void:
	var def := _def()
	_audio_fire.stream = GunAudio.fire_stream_for(str(def["id"]))
	_audio_fire.pitch_scale = float(def["pitch"]) * _rng.randf_range(0.97, 1.03)
	_audio_fire.volume_db = -6.0 if bool(_eff()["silent"]) else 0.0
	_audio_fire.play()


# ------------------------------------------------------------------------- fx
func _spawn_tracer(dir: Vector3, dist: float, e: Dictionary) -> void:
	for i in range(_tracers.size()):
		if _tracer_life[i] <= 0.0:
			var mi: MeshInstance3D = _tracers[i]
			var a := muzzle.global_position
			var b := a + dir * dist
			mi.global_position = (a + b) * 0.5
			mi.look_at(b)
			mi.scale = Vector3(1, 1, maxf(dist, 0.5))
			mi.visible = true
			mi.transparency = 0.35 if bool(e["silent"]) else 0.0
			# Mythic tracer tint.
			var _tmat := mi.get_surface_override_material(0) as StandardMaterial3D
			if _tmat != null:
				_tmat.albedo_color = MythicSkins.tracer_color(cur_gun_id(), cur_skin())
			_tracer_life[i] = 0.06
			return


func _eject_shell() -> void:
	var em: Node3D = _vm.get("eject", null)
	var from: Vector3 = em.global_position if em != null else muzzle.global_position
	var basis_t := camera.global_transform.basis
	for i in range(_shells.size()):
		if _shell_life[i] <= 0.0:
			var sm: MeshInstance3D = _shells[i]
			sm.global_position = from
			sm.visible = true
			_shell_vel[i] = basis_t.x * _rng.randf_range(1.2, 2.2) \
				+ basis_t.y * _rng.randf_range(1.0, 2.0) - basis_t.z * 0.6
			_shell_life[i] = 0.8
			return


func _update_fx(delta: float) -> void:
	for i in range(_tracers.size()):
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= delta
			if _tracer_life[i] <= 0.0:
				(_tracers[i] as MeshInstance3D).visible = false
	for i in range(_shells.size()):
		if _shell_life[i] > 0.0:
			_shell_life[i] -= delta
			var sm: MeshInstance3D = _shells[i]
			if _shell_life[i] <= 0.0:
				sm.visible = false
				continue
			_shell_vel[i] = _shell_vel[i] + Vector3(0, -9.8, 0) * delta
			sm.global_position += _shell_vel[i] * delta
			sm.rotation += Vector3(7.0, 5.0, 9.0) * delta


## Drive the third-person body rig + FPP arms from player state.
func _update_character(delta: float) -> void:
	if _body_anim == null or _arms == null:
		return
	# Grenade cooking / throw timing.
	if _cooking:
		_cook_t += delta
		_arms.set_throw_phase(minf(_cook_t * 1.5, 0.34))
		if _cook_t >= 2.2:
			release_grenade()  # auto-release before the fuse runs out
	if not _pending_nade.is_empty():
		_pending_nade["delay"] = float(_pending_nade["delay"]) - delta
		if float(_pending_nade["delay"]) <= 0.0:
			_spawn_grenade(float(_pending_nade["cook"]))
			_pending_nade = {}
	if _throw_anim_t >= 0.0:
		_throw_anim_t += delta / 0.65
		if _throw_anim_t >= 1.0:
			_throw_anim_t = -1.0
			_arms.set_throw_phase(-1.0)
		else:
			_arms.set_throw_phase(0.35 + _throw_anim_t * 0.65)
	if _dead or downed:
		return
	# Jump phase machine.
	if _jump_ph == 1:
		_jump_t += delta
		if _jump_t >= 0.16:
			_jump_ph = 2
			_body_anim.play("jump_air", 0.10)
	elif _jump_ph == 2 and is_on_floor():
		_jump_ph = 3
		_jump_t = 0.0
		_body_anim.play("jump_land", 0.08)
	elif _jump_ph == 3:
		_jump_t += delta
		if _jump_t >= 0.28:
			_jump_ph = 0
	var hv := Vector2(velocity.x, velocity.z).length()
	# Aim layer: full weight when ADS, partial while firing on the move.
	var aim_w := 1.0 if ads else (0.6 if _was_firing else 0.0)
	_body_anim.set_aim(aim_w, 0.0, pitch * 0.4, ads)
	_body_anim.set_strafe_offset(-_last_input.x * 0.35)
	# Locomotion state.
	if dropping:
		_body_anim.play("parachute", 0.3)
		_body_anim.set_aim(0.0, 0.0, 0.0)
	elif _jump_ph == 1 or _jump_ph == 3:
		pass  # transition clips already playing
	elif _jump_ph == 2 or not is_on_floor():
		if _jump_ph == 0:
			_jump_ph = 2
			_body_anim.play("jump_air", 0.12)
	elif sliding:
		pass  # slide clip playing
	elif proning:
		_body_anim.play("prone_crawl" if hv > 0.4 else "prone_idle", 0.25, maxf(hv / 1.2, 0.7))
	elif crouching:
		if hv > 0.4:
			_body_anim.play("crouch_walk", 0.25, hv / 1.6)
		else:
			_body_anim.play("crouch_idle", 0.25)
	elif sprinting and hv > 1.0:
		_body_anim.play("sprint", 0.20, maxf(hv / 7.0, 0.6))
	elif hv > 3.4:
		_body_anim.play("run", 0.25, hv / 4.2)
	elif hv > 0.4:
		_body_anim.play("walk", 0.25, hv / 2.6)
	else:
		_body_anim.play("idle", 0.30)
	# FPP arms.
	_arms.set_ads(ads and not sprinting)
	_arms.set_sprint(sprinting and not ads)
	_arms.set_bob(_bob_t, clampf(hv / 5.0, 0.0, 1.0) * (0.4 if ads else 1.0))
	if _reloading:
		_arms.set_reload_phase(1.0 - _reload_timer / maxf(_reload_dur, 0.01))
	else:
		_arms.set_reload_phase(-1.0)


# --------------------------------------------------------------------- damage
## Class system: outgoing damage multiplier (volt passive, overcharge, wraith).
func _class_dmg_mult() -> float:
	if class_sys != null:
		return class_sys.outgoing_dmg_mult()
	return 1.0


func take_damage(amount: int, from_pos: Vector3 = Vector3.ZERO, kind: String = "bullet", headshot: bool = false, killer = null) -> void:
	if _dead:
		return
	if downed:
		# Finished off while downed.
		downed = false
		_dead = true
		_arms.set_hands_visible(false)
		_body_anim.play("death", 0.15)
		var hud0 := _get_hud()
		if hud0 != null and hud0.has_method("show_downed"):
			hud0.show_downed(false)
		died.emit()
		return
	# Driving: bullets/explosions hit the vehicle first.
	if in_vehicle != null and kind in ["bullet", "explosive", "ram"]:
		in_vehicle.take_damage(float(amount), kind)
		return
	_since_damage = 0.0
	if class_sys != null:
		amount = class_sys.modify_incoming_damage(amount, from_pos, kind)
	var had_armor := armor > 0
	var remaining := amount
	if armor > 0:
		var absorbed: int = mini(armor, remaining)
		armor -= absorbed
		remaining -= absorbed
	hp = maxi(hp - remaining, 0)
	health_changed.emit(hp, max_hp, armor)
	var hud := _get_hud()
	if had_armor and armor <= 0 and hud != null and hud.has_method("show_armor_break"):
		hud.show_armor_break()  # plates shattered feedback
	if hud != null and hud.has_method("show_damage_from") and from_pos != Vector3.ZERO:
		hud.show_damage_from(from_pos)
	if hp <= 0:
		if revive_token:
			revive_token = false
			hp = 50
			health_changed.emit(hp, max_hp, armor)
			var hud2 := _get_hud()
			if hud2 != null and hud2.has_method("add_killfeed"):
				hud2.add_killfeed("SELF-REVIVE USED — back in the fight")
			return
		if _go_downed():
			return
		_dead = true
		_arms.set_hands_visible(false)
		_body_anim.play("death", 0.15)
		died.emit()
	elif _body_anim != null:
		_body_anim.play_action("hit_F")


## Downed-state query for squad AI / HUD.
func is_downed() -> bool:
	return downed


## Downed state: incapacitated but revivable when a squadmate is alive.
## Returns true when the player entered the downed state (death deferred).
func _go_downed() -> bool:
	var scene := get_tree().current_scene
	var sm = scene.get("squadman") if scene != null else null
	var mate_alive := false
	if sm != null and sm.has_method("has_living_mate"):
		mate_alive = sm.has_living_mate(self)
	if not mate_alive:
		return false
	downed = true
	_bleed_t = 30.0
	var hud := _get_hud()
	if hud != null and hud.has_method("show_downed"):
		hud.show_downed(true)
	if hud != null and hud.has_method("add_killfeed"):
		hud.add_killfeed("YOU ARE DOWN — crawl to cover, a teammate can revive you")
	if scene != null and scene.has_method("bot_bark"):
		scene.bot_bark("YOU", "I'm down! Need a revive!")
	return true


## Downed physics: slow crawl with move input; bleed-out finishes the job.
func _downed_physics(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if is_mobile and _joy.length() > 0.05:
		iv = _joy
	var dir3 := (transform.basis * Vector3(iv.x, 0, iv.y))
	dir3.y = 0.0
	if dir3.length() > 0.01:
		var n := dir3.normalized()
		velocity.x = n.x * 1.2
		velocity.z = n.z * 1.2
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	_bleed_t -= delta
	var hud := _get_hud()
	if hud != null and hud.has_method("update_downed"):
		hud.update_downed(_bleed_t)
	if _bleed_t <= 0.0:
		downed = false
		_dead = true
		_arms.set_hands_visible(false)
		_body_anim.play("death", 0.15)
		if hud != null and hud.has_method("show_downed"):
			hud.show_downed(false)
		died.emit()


## Revive from the downed state (teammate channel, 5 s).
func revive() -> void:
	if _dead or not downed:
		return
	downed = false
	hp = 50
	health_changed.emit(hp, max_hp, armor)
	_body_anim.play("idle", 0.1)
	var hud := _get_hud()
	if hud != null and hud.has_method("show_downed"):
		hud.show_downed(false)
	if hud != null and hud.has_method("add_killfeed"):
		hud.add_killfeed("REVIVED — back in the fight")


## Pick up a fallen teammate's dog tag (redeploy them at a buy station).
func carry_tag(tag_name: String) -> void:
	carried_tags.append(tag_name)
	var hud := _get_hud()
	if hud != null and hud.has_method("add_killfeed"):
		hud.add_killfeed("DOG TAG secured: %s — REDEPLOY at a buy station" % tag_name)


func respawn() -> void:
	var scene := get_tree().current_scene
	var sp := Vector3(0, 1.2, 24)
	if scene != null and scene.has_method("get_player_spawn"):
		sp = scene.get_player_spawn()
	global_position = sp
	velocity = Vector3.ZERO
	hp = max_hp
	armor = 0
	_dead = false
	_reloading = false
	sprinting = false
	crouching = false
	proning = false
	sliding = false
	_cooking = false
	_pending_nade = {}
	_executing = false
	_exec_victim = null
	_exec_slowmo = false
	_inspecting = false
	_emote_wheel_open = false
	Engine.time_scale = 1.0
	_jump_ph = 0
	_apply_stance_shape()
	_arms.set_hands_visible(true)
	_body_anim.play("idle", 0.1)
	yaw = 0.0
	pitch = 0.0
	_recoil = Vector2.ZERO
	rotation.y = yaw
	head.rotation.x = pitch
	set_ads(false)
	_reset_loadout()
	_equip_slot("primary", true)
	health_changed.emit(hp, max_hp, armor)
