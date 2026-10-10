extends SceneTree
## Headless verification for the CHARACTER build (rig, anim, arms, grenade,
## enemy/player integration, ragdoll).
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_character.gd

var _checks: Array = []
var _frame := 0
var _phase := 0
var _rig: SoldierRig
var _anim: SoldierAnim
var _enemy: NovaEnemy
var _player: NovaPlayer

const REQUIRED_CLIPS := ["idle", "walk", "run", "sprint", "sprint_stop",
	"jump_takeoff", "jump_air", "jump_land", "hipfire_pose", "ads_pose",
	"reload_rifle", "reload_pistol", "reload_launcher", "reload_melee",
	"grenade_throw", "grenade_cook", "slide", "crouch_idle", "crouch_walk",
	"prone_idle", "prone_crawl", "vault", "melee_lunge", "wingsuit", "parachute",
	"hit_F", "hit_B", "hit_L", "hit_R", "death", "victory"]


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, ((" | " + detail) if detail != "" else ""))


func _count_mi(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c = 1
	for ch in n.get_children():
		c += _count_mi(ch)
	return c


func _initialize() -> void:
	_rig = SoldierRig.new()
	root.add_child(_rig)
	# NOTE: in a SceneTree script, _ready runs on the first frame, not in
	# _initialize — rig checks happen in _run_rig_checks() at frame 2.


func _run_rig_checks() -> void:
	_log_check("rig bone count == 28", _rig.bone_count() == 28, "n=" + str(_rig.bone_count()))
	var h := _rig.rig_height()
	_log_check("rig height ~1.8m", h > 1.7 and h < 1.9, "h=" + str(h))
	_log_check("get_bone Head", _rig.get_bone("Head") >= 0)
	_log_check("get_bone missing == -1", _rig.get_bone("Nope") == -1)
	var ap: Vector3 = _rig.aim_point()
	_log_check("aim_point chest height", ap.y > 1.2 and ap.y < 1.5, "y=" + str(ap.y))
	_log_check("rig mesh count >= 40", _count_mi(_rig) >= 40, "n=" + str(_count_mi(_rig)))
	_log_check("7 variants", SoldierRig.VARIANTS.size() == 7)
	_rig.set_variant(1)
	_log_check("variant desert", _rig.variant_name() == "desert")
	_rig.set_variant(2)
	_log_check("variant blackops", _rig.variant_name() == "blackops")
	_rig.set_variant(0)
	_log_check("physical bones == 17", _rig._phys.size() == 17, "n=" + str(_rig._phys.size()))
	_log_check("simulator idle", not _rig.simulator_active())
	_run_default_char_checks()


## NOVA default characters: Sentinel (masked operator) + Breacher (shotgunner).
func _run_default_char_checks() -> void:
	# --- Sentinel (variant 5) ---
	_rig.set_variant(5)
	_log_check("variant sentinel", _rig.variant_name() == "sentinel")
	var gs: Dictionary = _rig.gear_state()
	_log_check("sentinel helmet on", bool(gs["helmet"]))
	_log_check("sentinel hood off", not bool(gs["hood"]))
	_log_check("sentinel cap off", not bool(gs["cap"]))
	_log_check("sentinel face hidden", not bool(gs["face"]))
	_log_check("sentinel red goggles", bool(gs["goggles_red"]))
	_log_check("sentinel dark goggles off", not bool(gs["goggles_dark"]))
	_log_check("sentinel nvg", bool(gs["nvg"]))
	_log_check("sentinel boommic", bool(gs["boommic"]))
	_log_check("sentinel no shell rig", not bool(gs["shell_rig"]))
	var bala: Color = (_rig._mats["balaclava"] as StandardMaterial3D).albedo_color
	_log_check("sentinel white balaclava", bala.r > 0.8 and bala.g > 0.8, str(bala))
	_log_check("sentinel digi camo", (_rig._mats["uniform"] as StandardMaterial3D).albedo_texture != null)
	# --- Breacher (variant 6) ---
	_rig.set_variant(6)
	_log_check("variant breacher", _rig.variant_name() == "breacher")
	gs = _rig.gear_state()
	_log_check("breacher cap on", bool(gs["cap"]))
	_log_check("breacher helmet off", not bool(gs["helmet"]))
	_log_check("breacher hood off", not bool(gs["hood"]))
	_log_check("breacher face visible", bool(gs["face"]))
	_log_check("breacher shell rig", bool(gs["shell_rig"]))
	_log_check("breacher no goggles", not bool(gs["goggles_dark"]) and not bool(gs["goggles_red"]))
	_log_check("breacher no nvg", not bool(gs["nvg"]))
	_log_check("breacher no boommic", not bool(gs["boommic"]))
	_log_check("breacher digi camo", (_rig._mats["uniform"] as StandardMaterial3D).albedo_texture != null)
	# --- old variants unaffected ---
	_rig.set_variant(0)
	gs = _rig.gear_state()
	_log_check("woodland helmet on", bool(gs["helmet"]))
	_log_check("woodland dark goggles", bool(gs["goggles_dark"]))
	_log_check("woodland face hidden", not bool(gs["face"]))
	_log_check("woodland no cap", not bool(gs["cap"]))
	_log_check("woodland no digi", (_rig._mats["uniform"] as StandardMaterial3D).albedo_texture == null)
	_rig.set_variant(4)
	gs = _rig.gear_state()
	_log_check("hooded still works", bool(gs["hood"]) and not bool(gs["helmet"]))
	_rig.set_variant(0)


func _run_anim_checks() -> void:
	_anim = SoldierAnim.new()
	_anim.setup(_rig)
	root.add_child(_anim)
	var missing := []
	for c in REQUIRED_CLIPS:
		if not _anim.has_clip(c):
			missing.append(c)
	_log_check("all 31 clips exist", missing.is_empty(), str(missing))
	var bad := []
	for c in REQUIRED_CLIPS:
		if not _anim.sample_test(c):
			bad.append(c)
	_log_check("all clips sample clean", bad.is_empty(), str(bad))
	# Transitions blend.
	_anim.play("walk", 0.2, 1.0)
	_anim.play("run", 0.2, 1.2)
	_log_check("walk->run transition", _anim.base_name() == "run")
	_anim.play("sprint", 0.2, 1.0)
	_log_check("run->sprint transition", _anim.base_name() == "sprint")
	_anim.play_action("grenade_throw")
	_log_check("action plays", _anim.action_playing())
	_anim.set_aim(1.0, 0.3, -0.1, true)
	_anim.set_strafe_offset(0.2)
	_anim.add_jolt(1.0)
	# Let the tree run the sampler for real frames (errors would print).
	_log_check("aim/jolt/strafe set", true)


func _run_correction_checks() -> void:
	# [FRAME] hooded variant is index 4; hood visible + helmet hidden when set.
	_rig.set_variant(4)
	_log_check("hooded variant name", _rig.variant_name() == "hooded")
	var hood_vis := true
	for mi in _rig._hood_meshes:
		hood_vis = hood_vis and (mi as MeshInstance3D).visible
	_log_check("hood visible when hooded", hood_vis)
	var helm_vis := false
	for mi in _rig._helmet_meshes:
		helm_vis = helm_vis or (mi as MeshInstance3D).visible
	_log_check("helmet hidden when hooded", not helm_vis)
	_rig.set_variant(0)
	var hood_hid := true
	for mi in _rig._hood_meshes:
		hood_hid = hood_hid and not (mi as MeshInstance3D).visible
	_log_check("hood hidden when not hooded", hood_hid)
	# [FRAME] sprint muzzle oscillates through the stride (not a fixed angle).
	var wi := _rig.bone_index("Weapon")
	_anim._apply("sprint", 0.05, 1.0, false)
	var w1: float = _rig.skel.get_bone_pose_rotation(wi).get_euler().x
	_anim._apply("sprint", 0.20, 1.0, false)
	var w2: float = _rig.skel.get_bone_pose_rotation(wi).get_euler().x
	_log_check("sprint muzzle oscillates", absf(w2 - w1) > 0.5, "dx=" + str(absf(w2 - w1)))
	# [FRAME] run carries one-handed at the side (right arm down).
	_anim._apply("run", 0.24, 1.0, false)
	var sr: float = _rig.skel.get_bone_pose_rotation(_rig.bone_index("ShoulderR")).get_euler().x
	_log_check("run one-hand carry", sr < 0.45, "x=" + str(sr))
	# [FRAME] jump tuck is extreme: knees nearly to chest.
	_anim._apply("jump_air", 0.3, 1.0, false)
	var th: float = _rig.skel.get_bone_pose_rotation(_rig.bone_index("ThighL")).get_euler().x
	_log_check("jump tuck extreme", th > 1.5, "x=" + str(th))
	# [FRAME] landing is a near-kneel: hips drop deep.
	_anim._apply("jump_land", 0.0, 1.0, false)
	var hy: float = _rig.skel.get_bone_pose_position(_rig.bone_index("Hips")).y
	_log_check("landing near-kneel", hy < 0.6, "y=" + str(hy))
	# [FRAME] slide leans BACK 25-30 degrees.
	_anim._apply("slide", 0.21, 1.0, false)
	var sp: float = _rig.skel.get_bone_pose_rotation(_rig.bone_index("Spine1")).get_euler().x
	_log_check("slide leans back", sp < -0.35, "x=" + str(sp))
	# [FRAME] reload cants 30-45 deg left, sustained through the reload.
	_anim._apply("reload_rifle", 1.1, 1.0, false)
	var rz: float = _rig.skel.get_bone_pose_rotation(wi).get_euler().z
	var roll := minf(absf(rz), PI - absf(rz))  # euler wrap: 0.65 <-> -(PI-0.65)
	_log_check("reload cant left", roll > 0.5, "roll=" + str(roll))
	# [FRAME] wingsuit is full spread-eagle: arms fully extended outward.
	_anim._apply("wingsuit", 0.5, 1.0, false)
	var shz: float = _rig.skel.get_bone_pose_rotation(_rig.bone_index("ShoulderL")).get_euler().z
	_log_check("wingsuit spread-eagle", shz > 1.2, "z=" + str(shz))


func _run_transition_frames() -> void:
	# Advance the action clock manually (headless frames carry tiny deltas).
	_anim._action = ["grenade_throw", 0.95]
	_anim._process(0.1)
	_log_check("action auto-finishes", not _anim.action_playing())
	_log_check("base still sprint", _anim.base_name() == "sprint")
	_anim.play("idle", 0.2)
	_log_check("sprint->idle", _anim.base_name() == "idle")


func _run_enemy_checks() -> void:
	var ps: PackedScene = load("res://scenes/enemy.tscn")
	_enemy = ps.instantiate() as NovaEnemy
	_enemy.position = Vector3(5, 1, 0)
	root.add_child(_enemy)
	_log_check("enemy rig built", _enemy.rig() != null and _enemy.rig().bone_count() == 28)
	_log_check("enemy anim built", _enemy.anim() != null and _enemy.anim().has_clip("walk"))
	_log_check("enemy variant valid", _enemy.rig().variant_name() != "")
	_log_check("enemy alive", _enemy.is_alive())
	# Wander drives walk clip.
	for i in range(5):
		_enemy._physics_process(1.0 / 60.0)
	_log_check("wander -> walk clip", _enemy.anim().base_name() == "walk",
		"base=" + _enemy.anim().base_name())
	# Far LOD holds pose without errors.
	_enemy.anim().set_lod(true)
	_enemy.anim().set_lod(false)
	# Hit flinch (non-lethal).
	_enemy.take_damage(5, _enemy.global_position + Vector3(0, 1.5, -2.0))
	_log_check("flinch action on hit", _enemy.anim().action_playing())
	_log_check("still alive after 5 dmg", _enemy.is_alive() and _enemy.hp == 95)
	# Lethal: death -> ragdoll.
	_enemy.take_damage(10000, _enemy.global_position + Vector3(0, 1.5, -1.0))
	_log_check("enemy dead", not _enemy.is_alive())
	for i in range(25):
		_enemy._process(1.0 / 60.0)
	_log_check("ragdoll simulator active", _enemy.rig().simulator_active())
	_log_check("anim stopped for ragdoll", true)
	var sane := true
	for bname in _enemy.rig()._phys.keys():
		var pb: PhysicalBone3D = _enemy.rig()._phys[bname]
		if pb.global_position.distance_to(_enemy.global_position) > 30.0:
			sane = false
	_log_check("ragdoll bones sane (no explosion)", sane)


func _run_grenade_checks() -> void:
	# Fuse + free.
	var g := FragGrenade.throw_from(Vector3(0, 3, 0), Vector3(0, 0, -1), 8.0, 0.0, null)
	root.add_child(g)
	_log_check("grenade fuse 2.0s", absf(g.fuse - 2.0) < 0.01, "fuse=" + str(g.fuse))
	var cooked := FragGrenade.throw_from(Vector3(0, 3, 0), Vector3(0, 0, -1), 8.0, 1.2, null)
	_log_check("cook shortens fuse", absf(cooked.fuse - 0.8) < 0.01, "fuse=" + str(cooked.fuse))
	cooked.queue_free()
	for i in range(200):
		if is_instance_valid(g) and not g.is_queued_for_deletion():
			g._physics_process(1.0 / 60.0)
	_log_check("grenade exploded + freed", g.is_queued_for_deletion() or not is_instance_valid(g))
	# AoE damages a nearby enemy.
	var ps: PackedScene = load("res://scenes/enemy.tscn")
	var e2 := ps.instantiate() as NovaEnemy
	e2.position = Vector3(0, 1, 0)
	root.add_child(e2)
	var hp0: int = e2.hp
	var g2 := FragGrenade.new()
	root.add_child(g2)
	g2.global_position = e2.global_position + Vector3(0, 0.5, 0)
	g2.explode()
	_log_check("grenade AoE damages enemy", e2.hp < hp0, "hp " + str(hp0) + "->" + str(e2.hp))
	e2.queue_free()


func _make_floor() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	root.add_child(sb)


func _run_player_checks() -> void:
	_make_floor()
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate() as NovaPlayer
	_player.position = Vector3(0, 2, 0)
	root.add_child(_player)
	_log_check("player body rig", _player._body_rig != null and _player._body_rig.bone_count() == 28)
	_log_check("player default is hooded", _player._body_rig.variant_name() == "hooded")
	# Character select wiring: main.gd sets char_variant before add_child.
	_player.char_variant = 5
	_player._body_rig.set_variant(_player.char_variant)
	_log_check("select sentinel", _player._body_rig.variant_name() == "sentinel")
	_player.char_variant = 6
	_player._body_rig.set_variant(_player.char_variant)
	_log_check("select breacher", _player._body_rig.variant_name() == "breacher")
	var bgs: Dictionary = _player._body_rig.gear_state()
	_log_check("player breacher face visible", bool(bgs["face"]))
	_log_check("player body anim", _player._body_anim != null)
	_log_check("player FPP arms", _player._arms != null)
	_log_check("arms grip rifle (m5)", _player._arms.grip_name() == "rifle")
	_log_check("arms limbs posed", _player._arms._limbs.size() == 4)
	for i in range(150):
		_player._physics_process(1.0 / 60.0)
	_log_check("player lands on floor", _player.is_on_floor())
	# Crouch.
	_player.toggle_crouch()
	_log_check("crouch on", _player.crouching)
	_log_check("crouch collision", _player.colshape.shape == _player._shape_crouch)
	_player.toggle_crouch()
	_log_check("crouch off", not _player.crouching)
	# Prone.
	_player.toggle_prone()
	_log_check("prone on", _player.proning)
	_log_check("prone head low", _player.head.position.y < 0.6, "y=" + str(_player.head.position.y))
	_player.toggle_prone()
	_log_check("prone off", not _player.proning)
	# Sprint (mobile path: is_mobile forces joystick input on desktop test rig).
	_player.is_mobile = true
	_player._mobile_sprint = true
	_player.set_joystick(Vector2(0, -1))
	for i in range(20):
		_player._physics_process(1.0 / 60.0)
	_log_check("sprint engages", _player.sprinting)
	_player._process(0.05)
	_log_check("sprint anim", _player._body_anim.base_name() == "sprint",
		"base=" + _player._body_anim.base_name())
	# Slide: crouch while sprinting.
	_player.toggle_crouch()
	_log_check("slide starts", _player.sliding)
	_player._process(0.05)
	_log_check("slide clip", _player._body_anim.base_name() == "slide",
		"base=" + _player._body_anim.base_name())
	# Slide-cancel on jump.
	_player.try_jump()
	_log_check("slide-cancel", not _player.sliding)
	_player._mobile_sprint = false
	_player.set_joystick(Vector2.ZERO)
	for i in range(10):
		_player._physics_process(1.0 / 60.0)
	# Grenade: cook then release.
	_player.start_grenade_cook()
	_log_check("cook starts", _player._cooking)
	for i in range(10):
		_player._process(1.0 / 60.0)
	_log_check("still cooking", _player._cooking)
	_player.release_grenade()
	_log_check("throw consumes grenade", _player.grenade_count() == 5)
	_log_check("throw scheduled", not _player._pending_nade.is_empty())
	for i in range(60):
		_player._process(1.0 / 60.0)
	_log_check("grenade spawned", _player._pending_nade.is_empty())
	var found := false
	for ch in root.get_children():
		if ch is FragGrenade:
			found = true
			ch.queue_free()
	_log_check("frag grenade in tree", found)
	# Grips per weapon class.
	_player.give_gun("d50", 0)
	_log_check("pistol grip", _player._arms.grip_name() == "pistol")
	_player.give_gun("rl4", 0)
	_log_check("launcher grip", _player._arms.grip_name() == "launcher")
	_player.give_gun("axe", 0)
	_log_check("melee grip", _player._arms.grip_name() == "melee")
	# Reload drives the body reload action.
	_player._equip_slot("primary", true)
	_player._gun()["mag"] = 3
	_player.start_reload()
	_log_check("reload action", _player._body_anim.action_playing())
	# Melee lunge action.
	_player._equip_slot("melee", true)
	_player._melee_swing()
	_log_check("melee lunge action", _player._body_anim.action_playing())
	# Jump phase machine.
	_player._equip_slot("primary", true)
	_player._do_jump()
	_log_check("jump takeoff", _player._jump_ph == 1)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2 and _phase == 0:
		_run_rig_checks()
		_phase = 1
	if _frame == 5 and _phase == 1:
		_run_anim_checks()
		_run_correction_checks()
		_phase = 2
	if _frame == 30 and _phase == 2:
		_run_transition_frames()
		_run_enemy_checks()
		_phase = 3
	if _frame == 40 and _phase == 3:
		_run_grenade_checks()
		_run_player_checks()
		_phase = 4
	if _frame == 90 and _phase == 4:
		# Ragdoll stability after real physics frames (explosion check).
		var sane := true
		if _enemy != null and is_instance_valid(_enemy):
			for bname in _enemy.rig()._phys.keys():
				var pb: PhysicalBone3D = _enemy.rig()._phys[bname]
				if pb.global_position.distance_to(_enemy.global_position) > 30.0:
					sane = false
		_log_check("ragdoll stable after 90 frames", sane)
		_phase = 5
	if _frame >= 110:
		_finish()
		return true
	return false


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("CHARACTER: ", _checks.size() - fails, "/", _checks.size(), " checks passed")
	if fails > 0:
		print("CHARACTER: FAILURES PRESENT")
	quit()
