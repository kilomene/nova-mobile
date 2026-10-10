extends Node
class_name SoldierAnim
## Procedural keyframe animation for SoldierRig.
## Clips: {bone idx: [times PackedFloat32Array, pos PackedVector3Array, rot PackedVector3Array(euler)]}
## sampled with smoothstep easing; crossfade 0.15-0.25s between base states;
## action layer (one-shots) over base; aim layer (upper body) procedural blend.
## Hot path avoids per-frame allocations: packed arrays precomputed at build.

const UPPER_BONES := ["Spine1", "Neck", "Head", "ClavicleL", "ClavicleR",
	"ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR", "ForearmL", "ForearmR",
	"HandL", "HandR", "FingerL", "FingerR", "VestPlate", "Backpack", "Weapon"]

var rig: SoldierRig
var skel: Skeleton3D
var _clips := {}
var _rest: Array = []
var _upper := {}  # bone idx -> true

var _base := ["idle", 0.0, 1.0]  # clip, t, rate
var _prev := ["", 0.0, 1.0, 0.0, 0.2]  # clip, t, rate, fade_left, fade_dur
var _action := ["", 0.0]  # one-shot overlay
var _aim_w := 0.0
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _aim_ads := false
var _strafe_yaw := 0.0
var _jolt := 0.0
var _enabled := true
var _lod := false
var _ragdoll := false


func setup(r: SoldierRig) -> void:
	rig = r


func _ready() -> void:
	skel = rig.skel
	_rest = rig.rest_pose
	for b in UPPER_BONES:
		var i := rig.bone_index(b)
		if i >= 0:
			_upper[i] = true
	_build_all()


func has_clip(cname: String) -> bool:
	return _clips.has(cname)


func clip_duration(cname: String) -> float:
	return float((_clips.get(cname, {}) as Dictionary).get("dur", 0.0))


func clip_names() -> Array:
	return _clips.keys()


func play(cname: String, fade := 0.2, rate := 1.0) -> void:
	if not _clips.has(cname):
		return
	if str(_base[0]) == cname:
		_base[2] = rate  # same clip: just refresh the playback rate
		return
	_prev = [_base[0], _base[1], _base[2], fade, fade]
	_base = [cname, 0.0, rate]


func play_action(cname: String) -> void:
	if not _clips.has(cname):
		return
	_action = [cname, 0.0]


func action_playing() -> bool:
	return str(_action[0]) != ""


func base_name() -> String:
	return str(_base[0])


func set_aim(weight: float, yaw: float, pitch: float, ads := false) -> void:
	_aim_w = clampf(weight, 0.0, 1.0)
	_aim_yaw = yaw
	_aim_pitch = pitch
	_aim_ads = ads


func set_strafe_offset(yaw: float) -> void:
	_strafe_yaw = yaw


func add_jolt(a: float) -> void:
	_jolt = minf(_jolt + a, 2.5)


func set_enabled(b: bool) -> void:
	_enabled = b


func set_lod(far: bool) -> void:
	_lod = far


func notify_ragdoll() -> void:
	_ragdoll = true


func set_ragdoll_done() -> void:
	_ragdoll = false


# ---------------------------------------------------------------- sampling
func _process(delta: float) -> void:
	if not _enabled or _lod or _ragdoll or skel == null:
		return
	# Advance clocks.
	var bc: Dictionary = _clips[_base[0]]
	_base[1] = _adv(float(_base[1]), float(_base[2]) * delta, bc)
	if str(_prev[0]) != "":
		var pc: Dictionary = _clips[_prev[0]]
		_prev[1] = _adv(float(_prev[1]), float(_prev[2]) * delta, pc)
		_prev[3] = float(_prev[3]) - delta
		if float(_prev[3]) <= 0.0:
			_prev[0] = ""
	if str(_action[0]) != "":
		var ac: Dictionary = _clips[_action[0]]
		_action[1] = float(_action[1]) + delta
		if float(_action[1]) >= float(ac["dur"]):
			_action[0] = ""
	_jolt = move_toward(_jolt, 0.0, delta * 7.0)
	# Reset to rest pose.
	for i in range(_rest.size()):
		skel.set_bone_pose(i, _rest[i] as Transform3D)
	# Base layer.
	_apply(str(_base[0]), float(_base[1]), 1.0, false)
	# Crossfade from previous.
	if str(_prev[0]) != "":
		_apply(str(_prev[0]), float(_prev[1]), clampf(float(_prev[3]) / float(_prev[4]), 0.0, 1.0), false)
	# Action overlay (weight envelope: fast in, smooth out).
	if str(_action[0]) != "":
		var ac2: Dictionary = _clips[_action[0]]
		var at := float(_action[1])
		var dur := float(ac2["dur"])
		var w := minf(at / 0.08, 1.0) * clampf((dur - at) / 0.12, 0.0, 1.0)
		_apply(str(_action[0]), at, w, bool(ac2.get("upper_only", false)))
	# Aim layer: upper body pose + procedural yaw/pitch.
	if _aim_w > 0.01:
		var aname := "ads_pose" if _aim_ads else "hipfire_pose"
		_apply(aname, fmod(float(_base[1]), 1.0), _aim_w, true)
		_apply_aim_procedural()
	# Strafe torso offset.
	if absf(_strafe_yaw) > 0.01:
		_add_bone_yaw(rig.bone_index("Spine1"), _strafe_yaw * 0.5)
	# Per-shot jolt on shoulders.
	if _jolt > 0.01:
		_add_bone_pitch(rig.bone_index("ShoulderL"), _jolt * 0.10)
		_add_bone_pitch(rig.bone_index("ShoulderR"), _jolt * 0.10)
		_add_bone_pitch(rig.bone_index("Spine1"), _jolt * 0.05)


func _adv(t: float, dt: float, c: Dictionary) -> float:
	t += dt
	var dur := float(c["dur"])
	if bool(c["loop"]):
		return fmod(t, dur) if dur > 0.0 else 0.0
	return minf(t, dur - 0.001)


func _apply(cname: String, t: float, weight: float, upper_only: bool) -> void:
	if weight <= 0.001:
		return
	var c: Dictionary = _clips[cname]
	var bones: PackedInt32Array = c["bones"]
	var times: Array = c["times"]
	var poss: Array = c["pos"]
	var rots: Array = c["rot"]
	var full := weight >= 0.999
	for bi in range(bones.size()):
		var idx := bones[bi]
		if upper_only and not _upper.has(idx):
			continue
		var ts: PackedFloat32Array = times[bi]
		var n := ts.size()
		var i0 := 0
		var i1 := 0
		if n == 1:
			i0 = 0
			i1 = 0
		else:
			var tt := t
			if tt <= ts[0]:
				i0 = 0
				i1 = 0
			elif tt >= ts[n - 1]:
				i0 = n - 1
				i1 = n - 1
			else:
				for k in range(n - 1):
					if tt >= ts[k] and tt <= ts[k + 1]:
						i0 = k
						i1 = k + 1
						break
		var f := 0.0
		if i1 != i0:
			var span := ts[i1] - ts[i0]
			if span > 0.0001:
				f = (t - ts[i0]) / span
			f = f * f * (3.0 - 2.0 * f)  # smoothstep easing
		var ps: PackedVector3Array = poss[bi]
		var rs: PackedVector3Array = rots[bi]
		var p: Vector3 = ps[i0].lerp(ps[i1], f)
		var r: Vector3 = rs[i0].lerp(rs[i1], f)
		if full:
			skel.set_bone_pose_position(idx, p)
			skel.set_bone_pose_rotation(idx, Quaternion.from_euler(r))
		else:
			var cp := skel.get_bone_pose_position(idx)
			var cq := skel.get_bone_pose_rotation(idx)
			skel.set_bone_pose_position(idx, cp.lerp(p, weight))
			skel.set_bone_pose_rotation(idx, cq.slerp(Quaternion.from_euler(r), weight))


func _apply_aim_procedural() -> void:
	var si := rig.bone_index("Spine1")
	var ni := rig.bone_index("Neck")
	var q := skel.get_bone_pose_rotation(si)
	q = q * Quaternion(Vector3.UP, _aim_yaw * 0.45 * _aim_w) * Quaternion(Vector3.RIGHT, _aim_pitch * 0.30 * _aim_w)
	skel.set_bone_pose_rotation(si, q)
	var qn := skel.get_bone_pose_rotation(ni)
	skel.set_bone_pose_rotation(ni, qn * Quaternion(Vector3.UP, _aim_yaw * 0.30 * _aim_w))


func _add_bone_yaw(idx: int, yaw: float) -> void:
	if idx < 0:
		return
	var q := skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, q * Quaternion(Vector3.UP, yaw))


func _add_bone_pitch(idx: int, pitch: float) -> void:
	if idx < 0:
		return
	var q := skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, q * Quaternion(Vector3.RIGHT, pitch))


## Test helper: sample a clip at mid-duration; returns false on any error.
func sample_test(cname: String) -> bool:
	if not _clips.has(cname):
		return false
	var c: Dictionary = _clips[cname]
	_apply(cname, float(c["dur"]) * 0.5, 1.0, false)
	_apply(cname, float(c["dur"]) * 0.99, 0.5, true)
	return true


# ------------------------------------------------------------ clip building
func _new_trk() -> Dictionary:
	return {}


func _k(trk: Dictionary, bone: String, t: float, p: Vector3, r: Vector3) -> void:
	if not trk.has(bone):
		trk[bone] = []
	(trk[bone] as Array).append([t, p, r])


func _done(cname: String, trk: Dictionary, dur: float, loop: bool, upper_only := false) -> void:
	var bones := PackedInt32Array()
	var times: Array = []
	var poss: Array = []
	var rots: Array = []
	for bname in trk.keys():
		var idx := rig.bone_index(str(bname))
		if idx < 0:
			continue
		var keys: Array = trk[bname]
		keys.sort_custom(func(a, b): return a[0] < b[0])
		var ts := PackedFloat32Array()
		var ps := PackedVector3Array()
		var rs := PackedVector3Array()
		for k in keys:
			ts.append(float(k[0]))
			# Position: rest + offset (clips author offsets; rest added at sample time).
			var rp: Vector3 = (rig.rest_pose[idx] as Transform3D).origin
			ps.append(rp + (k[1] as Vector3))
			# Rotation: rest euler + offset.
			var rr: Vector3 = (rig.rest_pose[idx] as Transform3D).basis.get_euler()
			rs.append(rr + (k[2] as Vector3))
		bones.append(idx)
		times.append(ts)
		poss.append(ps)
		rots.append(rs)
	_clips[cname] = {"dur": dur, "loop": loop, "bones": bones,
		"times": times, "pos": poss, "rot": rots, "upper_only": upper_only}


func _build_all() -> void:
	_build_idle()
	_build_locomotion()
	_build_jump()
	_build_aim_poses()
	_build_reloads()
	_build_grenade()
	_build_slide_crouch_prone()
	_build_vault_melee()
	_build_air()
	_build_hits()
	_build_death_victory()
	_build_kill_variety()
	_build_executions()
	_build_inspect_emotes()


func _build_idle() -> void:
	var trk := _new_trk()
	var d := 2.4
	for i in range(5):
		var t := d * i / 4.0
		var br := sin(t / d * TAU)  # breath cycle
		_k(trk, "Spine1", t, Vector3(0, 0.004 * br, 0), Vector3(0.02 * br, 0, 0))
		_k(trk, "Head", t, Vector3.ZERO, Vector3(0.03 * br, 0.05 * sin(t * 0.7), 0))
		_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.45 + 0.02 * br, 0, 0.10))
		_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.45 + 0.02 * br, 0, -0.10))
		_k(trk, "ForearmL", t, Vector3.ZERO, Vector3(1.00, 0, 0))
		_k(trk, "ForearmR", t, Vector3.ZERO, Vector3(1.00, 0, 0))
		_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-1.80, 0, 0))
		_k(trk, "Hips", t, Vector3(0, 0.006 * sin(t / d * TAU * 2.0), 0), Vector3.ZERO)
		_k(trk, "Backpack", t, Vector3(0, 0.004 * br, 0), Vector3.ZERO)
	_done("idle", trk, d, true)


func _build_locomotion() -> void:
	# params: name, dur, leg_swing, knee_amp, lean, bob, arm_mode, pack
	_loco("walk", 0.615, 0.44, 0.75, 0.06, 0.030, "lowready", 0.012)
	# [FRAME] run carries the gun ONE-HANDED at the side (not two-handed) —
	# same as sprint, differing only in lean/pump intensity.
	_loco("run", 0.476, 0.62, 1.05, 0.14, 0.055, "run_onehand", 0.022)
	_loco("sprint", 0.329, 0.78, 1.25, 0.30, 0.075, "sprint", 0.035)
	# sprint_stop: 2-3 step decel, torso pitches back then settles
	var trk := _new_trk()
	var d := 0.55
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.30, 0, 0))
	_k(trk, "Spine1", d * 0.45, Vector3.ZERO, Vector3(-0.18, 0, 0))
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.02, 0, 0))
	for i in range(3):
		var t := d * i / 2.0
		var ph := t / d * PI * 2.0
		_k(trk, "ThighL", t, Vector3.ZERO, Vector3(0.5 * sin(ph), 0, 0))
		_k(trk, "ThighR", t, Vector3.ZERO, Vector3(0.5 * sin(ph + PI), 0, 0))
		_k(trk, "ShinL", t, Vector3.ZERO, Vector3(-0.8 * maxf(0.0, sin(ph + 0.9)), 0, 0))
		_k(trk, "ShinR", t, Vector3.ZERO, Vector3(-0.8 * maxf(0.0, sin(ph + PI + 0.9)), 0, 0))
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.15, 0, 0.1))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(0.45, 0, 0.1))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.15, 0, -0.1))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.1))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(0.35, 0, 0))
	_k(trk, "ForearmL", d, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(0.35, 0, 0))
	_k(trk, "ForearmR", d, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "Weapon", 0.0, Vector3.ZERO, Vector3(-0.2, 0, 0))
	_k(trk, "Weapon", d, Vector3.ZERO, Vector3(-1.8, 0, 0))
	_k(trk, "Hips", 0.0, Vector3(0, -0.02, 0), Vector3.ZERO)
	_k(trk, "Hips", d, Vector3.ZERO, Vector3.ZERO)
	_done("sprint_stop", trk, d, false)


func _loco(cname: String, dur: float, swing: float, knee: float, lean: float,
		bob: float, arm_mode: String, pack: float) -> void:
	var trk := _new_trk()
	var n := 8
	for i in range(n + 1):
		var t := dur * i / n
		var ph := t / dur * TAU
		var s := sin(ph)
		# legs
		_k(trk, "ThighL", t, Vector3.ZERO, Vector3(swing * s, 0, 0))
		_k(trk, "ThighR", t, Vector3.ZERO, Vector3(swing * sin(ph + PI), 0, 0))
		_k(trk, "ShinL", t, Vector3.ZERO, Vector3(-knee * maxf(0.0, sin(ph + 0.9)), 0, 0))
		_k(trk, "ShinR", t, Vector3.ZERO, Vector3(-knee * maxf(0.0, sin(ph + PI + 0.9)), 0, 0))
		_k(trk, "FootL", t, Vector3.ZERO, Vector3(-0.35 * s - 0.25 * maxf(0.0, sin(ph - 0.6)), 0, 0))
		_k(trk, "FootR", t, Vector3.ZERO, Vector3(-0.35 * sin(ph + PI) - 0.25 * maxf(0.0, sin(ph + PI - 0.6)), 0, 0))
		# root bob (twice per cycle) + lean
		_k(trk, "Hips", t, Vector3(0, -bob * (0.5 - 0.5 * cos(2.0 * ph)), 0), Vector3(0.03 * s, 0, 0.02 * s))
		_k(trk, "Spine", t, Vector3.ZERO, Vector3(lean * 0.5, 0, 0))
		_k(trk, "Spine1", t, Vector3.ZERO, Vector3(lean * 0.5 + 0.02 * sin(2.0 * ph), 0, 0))
		_k(trk, "Head", t, Vector3.ZERO, Vector3(-lean * 0.55, 0, 0))
		# gear secondary motion (delayed bounce)
		_k(trk, "Backpack", t, Vector3(0, pack * sin(2.0 * ph + 1.1), 0.004 * sin(2.0 * ph + 1.1)),
			Vector3(0.06 * sin(2.0 * ph + 1.1), 0, 0))
		_k(trk, "VestPlate", t, Vector3(0, 0.5 * pack * sin(2.0 * ph + 0.9), 0), Vector3.ZERO)
		# arms by mode
		if arm_mode == "lowready" or arm_mode == "lowready_bounce":
			var bc := 0.10 if arm_mode == "lowready_bounce" else 0.03
			_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.45 + 0.05 * sin(ph + PI), 0, 0.12))
			_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.45 + 0.05 * s, 0, -0.12))
			_k(trk, "ForearmL", t, Vector3.ZERO, Vector3(1.00 + bc * sin(2.0 * ph), 0, 0))
			_k(trk, "ForearmR", t, Vector3.ZERO, Vector3(1.00 + bc * sin(2.0 * ph + 0.5), 0, 0))
			_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-1.80 - bc * sin(2.0 * ph), 0, 0))
		elif arm_mode == "run_onehand":
			# [FRAME] run: gun in the RIGHT hand only, down at the side;
			# smaller arm swing and muzzle oscillation than full sprint.
			_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.18 + 0.10 * s, 0, -0.06))
			_k(trk, "ForearmR", t, Vector3.ZERO, Vector3(0.35, 0, 0))
			_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-0.90 + 1.00 * sin(ph - 0.4), 0, 0))
			# left arm: moderate pump in opposition
			_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.60 * sin(ph + 0.4), 0, 0.14))
			_k(trk, "ForearmL", t, Vector3.ZERO, Vector3(0.55 + 0.40 * maxf(0.0, sin(ph + 1.6)), 0, 0))
		elif arm_mode == "sprint":
			# right arm: weapon lowered, held one-handed at side
			_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.16 + 0.06 * s, 0, -0.06))
			_k(trk, "ForearmR", t, Vector3.ZERO, Vector3(0.30, 0, 0))
			# [FRAME] the muzzle is NOT fixed: it swings with the arm pump
			# between ~45° down-back and ~60° up through the stride cycle.
			_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-1.24 + 1.70 * sin(ph - 0.4), 0, 0))
			# left arm: full pump
			_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.85 * sin(ph + 0.4), 0, 0.14))
			_k(trk, "ForearmL", t, Vector3.ZERO, Vector3(0.55 + 0.45 * maxf(0.0, sin(ph + 1.6)), 0, 0))
	_done(cname, trk, dur, true)


func _build_jump() -> void:
	# takeoff: knees bend, arms swing up
	var trk := _new_trk()
	var d := 0.16
	_k(trk, "Hips", 0.0, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Hips", d, Vector3(0, -0.16, 0), Vector3.ZERO)
	_k(trk, "ThighL", 0.0, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "ThighR", 0.0, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "ThighL", d, Vector3.ZERO, Vector3(0.55, 0, 0))
	_k(trk, "ThighR", d, Vector3.ZERO, Vector3(0.55, 0, 0))
	_k(trk, "ShinL", d, Vector3.ZERO, Vector3(-0.85, 0, 0))
	_k(trk, "ShinR", d, Vector3.ZERO, Vector3(-0.85, 0, 0))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(-0.5, 0, 0.2))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(-0.5, 0, -0.2))
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.18, 0, 0))
	_done("jump_takeoff", trk, d, false)
	# air: [FRAME] EXTREME tuck — knees up nearly to chest, body pitched
	# ~30° forward, gun in both hands across the chest (sprinter's leap).
	trk = _new_trk()
	d = 0.6
	_k(trk, "Hips", 0.0, Vector3(0, -0.10, 0), Vector3.ZERO)
	_k(trk, "ThighL", 0.0, Vector3.ZERO, Vector3(1.78, 0, 0))
	_k(trk, "ThighR", 0.0, Vector3.ZERO, Vector3(1.88, 0, 0))
	_k(trk, "ShinL", 0.0, Vector3.ZERO, Vector3(-2.25, 0, 0))
	_k(trk, "ShinR", 0.0, Vector3.ZERO, Vector3(-2.35, 0, 0))
	_k(trk, "FootL", 0.0, Vector3.ZERO, Vector3(0.5, 0, 0))
	_k(trk, "FootR", 0.0, Vector3.ZERO, Vector3(0.5, 0, 0))
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.55, 0, 0.15))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.55, 0, -0.15))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(1.15, 0, 0))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(1.15, 0, 0))
	_k(trk, "Weapon", 0.0, Vector3.ZERO, Vector3(-1.70, 0, 0))
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.50, 0, 0))
	_done("jump_air", trk, d, true)
	# land: [FRAME] VERY deep absorption — near-kneel: front leg deeply
	# bent, back knee drops to almost touch the ground, torso stays upright.
	trk = _new_trk()
	d = 0.28
	_k(trk, "Hips", 0.0, Vector3(0, -0.52, 0), Vector3.ZERO)
	_k(trk, "Hips", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "ThighL", 0.0, Vector3.ZERO, Vector3(1.85, 0, 0))
	_k(trk, "ThighR", 0.0, Vector3.ZERO, Vector3(0.55, 0, 0))
	_k(trk, "ThighL", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "ThighR", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "ShinL", 0.0, Vector3.ZERO, Vector3(-2.35, 0, 0))
	_k(trk, "ShinR", 0.0, Vector3.ZERO, Vector3(-2.10, 0, 0))
	_k(trk, "ShinL", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "ShinR", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.18, 0, 0))
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.02, 0, 0))
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "Weapon", 0.0, Vector3.ZERO, Vector3(-1.8, 0, 0))
	_done("jump_land", trk, d, false)


func _build_aim_poses() -> void:
	# hipfire: weapon at waist, both hands on it, elbows slightly out
	var trk := _new_trk()
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.38, 0, 0.28))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.38, 0, -0.28))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(0.72, 0, 0))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(0.72, 0, 0))
	_k(trk, "Weapon", 0.0, Vector3.ZERO, Vector3(-1.30, 0, 0))
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.06, 0, 0))
	_k(trk, "Head", 0.0, Vector3.ZERO, Vector3(-0.04, 0, 0))
	_done("hipfire_pose", trk, 1.0, true)
	# ADS: shouldered, cheek weld, support arm extended, torso squares
	trk = _new_trk()
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.95, 0, 0.10))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.88, 0, -0.16))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(0.28, 0, 0))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(0.42, 0, 0))
	_k(trk, "Weapon", 0.0, Vector3(0.0, 0.10, 0.02), Vector3(-1.12, -0.06, 0))
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.10, -0.10, 0))
	_k(trk, "Head", 0.0, Vector3.ZERO, Vector3(0.16, 0.06, -0.08))  # cheek down to stock
	_k(trk, "Neck", 0.0, Vector3.ZERO, Vector3(0.08, 0, 0))
	_done("ads_pose", trk, 1.0, true)


func _build_reloads() -> void:
	# rifle: [FRAME] gun raised to CHEST height and canted 30-45° LEFT
	# for the whole reload; head stays UP looking forward (never at the gun).
	var trk := _new_trk()
	var d := 2.2
	_k(trk, "Weapon", 0.0, Vector3(0, 0.08, 0), Vector3(-1.80, 0, 0.65))
	_k(trk, "Weapon", d * 0.3, Vector3(-0.05, 0.02, 0), Vector3(-1.80, 0, 0.68))
	_k(trk, "Weapon", d * 0.7, Vector3(-0.05, 0.02, 0), Vector3(-1.80, 0, 0.62))
	_k(trk, "Weapon", d, Vector3(0, 0.08, 0), Vector3(-1.80, 0, 0.65))
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.55, 0, 0.12))
	_k(trk, "ShoulderL", d * 0.3, Vector3.ZERO, Vector3(0.38, 0, 0.25))
	_k(trk, "ShoulderL", d * 0.55, Vector3.ZERO, Vector3(0.62, 0, 0.10))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(0.55, 0, 0.12))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "ForearmL", d * 0.3, Vector3.ZERO, Vector3(1.25, 0, 0))
	_k(trk, "ForearmL", d * 0.55, Vector3.ZERO, Vector3(0.85, 0, 0))
	_k(trk, "ForearmL", d, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "Head", 0.0, Vector3.ZERO, Vector3.ZERO)  # head up, eyes on threat
	_k(trk, "Head", d * 0.5, Vector3.ZERO, Vector3(-0.03, 0.12, 0))
	_k(trk, "Head", d, Vector3.ZERO, Vector3.ZERO)
	_done("reload_rifle", trk, d, false, true)
	# pistol: one hand, slide rack
	trk = _new_trk()
	d = 1.6
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.45, 0, -0.10))
	_k(trk, "ShoulderR", d * 0.5, Vector3.ZERO, Vector3(0.35, 0, -0.10))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.10))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(0.9, 0, 0))
	_k(trk, "ForearmR", d * 0.4, Vector3.ZERO, Vector3(1.15, 0, 0))
	_k(trk, "ForearmR", d, Vector3.ZERO, Vector3(0.9, 0, 0))
	_k(trk, "ShoulderL", d * 0.55, Vector3.ZERO, Vector3(0.75, 0, 0.15))
	_k(trk, "ShoulderL", d * 0.8, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "Weapon", d * 0.5, Vector3.ZERO, Vector3(-1.5, 0, 0.35))
	_k(trk, "Weapon", d, Vector3.ZERO, Vector3(-1.8, 0, 0))
	_done("reload_pistol", trk, d, false, true)
	# launcher: front-load warhead, muzzle tips up
	trk = _new_trk()
	d = 3.0
	_k(trk, "Weapon", 0.0, Vector3.ZERO, Vector3(-0.4, 0, 0))
	_k(trk, "Weapon", d * 0.35, Vector3(0, 0.05, 0), Vector3(-1.15, 0.3, 0))
	_k(trk, "Weapon", d * 0.7, Vector3(0, 0.05, 0), Vector3(-1.15, -0.2, 0))
	_k(trk, "Weapon", d, Vector3.ZERO, Vector3(-0.4, 0, 0))
	_k(trk, "ShoulderR", d * 0.35, Vector3.ZERO, Vector3(0.9, 0, -0.2))
	_k(trk, "ShoulderL", d * 0.35, Vector3.ZERO, Vector3(0.7, 0, 0.3))
	_k(trk, "Spine1", d * 0.35, Vector3.ZERO, Vector3(-0.12, 0.2, 0))
	_done("reload_launcher", trk, d, false, true)
	# melee: quick weapon check / knife flip
	trk = _new_trk()
	d = 0.8
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.45, 0, -0.1))
	_k(trk, "ShoulderR", d * 0.5, Vector3.ZERO, Vector3(0.15, 0, -0.35))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.1))
	_k(trk, "ForearmR", d * 0.5, Vector3.ZERO, Vector3(1.6, 0, 0))
	_k(trk, "Weapon", d * 0.5, Vector3.ZERO, Vector3(-1.2, 0, 0.5))
	_done("reload_melee", trk, d, false, true)


func _build_grenade() -> void:
	# Overhand throw, off hand (left). ~1.0s: windup -> release -> recover.
	var trk := _new_trk()
	var d := 1.0
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ShoulderL", 0.22, Vector3.ZERO, Vector3(-0.85, 0, 0.35))  # arm up beside ear
	_k(trk, "ShoulderL", 0.42, Vector3.ZERO, Vector3(1.05, 0, 0.05))  # swing forward
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "ForearmL", 0.22, Vector3.ZERO, Vector3(2.05, 0, 0))  # cocked back
	_k(trk, "ForearmL", 0.42, Vector3.ZERO, Vector3(0.35, 0, 0))  # snap forward
	_k(trk, "ForearmL", d, Vector3.ZERO, Vector3(1.0, 0, 0))
	_k(trk, "Spine1", 0.22, Vector3.ZERO, Vector3(-0.10, 0.25, 0))
	_k(trk, "Spine1", 0.42, Vector3.ZERO, Vector3(0.22, -0.18, 0))
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.02, 0, 0))
	# weapon dips in right hand while left throws
	_k(trk, "ShoulderR", 0.22, Vector3.ZERO, Vector3(0.25, 0, -0.08))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.10))
	_k(trk, "Weapon", 0.22, Vector3.ZERO, Vector3(-1.45, 0, 0))
	_k(trk, "Weapon", d, Vector3.ZERO, Vector3(-1.80, 0, 0))
	_done("grenade_throw", trk, d, false)
	# cook hold: frozen windup pose (loop)
	trk = _new_trk()
	d = 0.6
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(-0.85, 0, 0.35))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(-0.82, 0, 0.35))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(2.05, 0, 0))
	_k(trk, "ForearmL", d, Vector3.ZERO, Vector3(2.02, 0, 0))
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(-0.10, 0.25, 0))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.25, 0, -0.08))
	_k(trk, "Weapon", 0.0, Vector3.ZERO, Vector3(-1.45, 0, 0))
	_done("grenade_cook", trk, d, true)


func _build_slide_crouch_prone() -> void:
	# slide: [FRAME] body drops low, legs extended forward TOGETHER,
	# torso leaned BACK 25-30° (not forward), gun forward and shootable.
	var trk := _new_trk()
	var d := 0.7
	_k(trk, "Hips", 0.0, Vector3(0, -0.18, 0), Vector3.ZERO)
	_k(trk, "Hips", d * 0.3, Vector3(0, -0.52, 0), Vector3.ZERO)
	_k(trk, "Hips", d, Vector3(0, -0.48, 0), Vector3.ZERO)
	_k(trk, "ThighL", d * 0.3, Vector3.ZERO, Vector3(1.30, 0, 0))  # legs forward together
	_k(trk, "ThighR", d * 0.3, Vector3.ZERO, Vector3(1.22, 0, 0))
	_k(trk, "ShinL", d * 0.3, Vector3.ZERO, Vector3(-0.15, 0, 0))
	_k(trk, "ShinR", d * 0.3, Vector3.ZERO, Vector3(-0.18, 0, 0))
	_k(trk, "Spine1", d * 0.3, Vector3.ZERO, Vector3(-0.48, 0, 0))  # lean back ~27.5°
	_k(trk, "ShoulderL", d * 0.3, Vector3.ZERO, Vector3(0.75, 0, 0.15))
	_k(trk, "ShoulderR", d * 0.3, Vector3.ZERO, Vector3(0.75, 0, -0.15))
	_k(trk, "ForearmL", d * 0.3, Vector3.ZERO, Vector3(0.55, 0, 0))
	_k(trk, "ForearmR", d * 0.3, Vector3.ZERO, Vector3(0.55, 0, 0))
	_k(trk, "Weapon", d * 0.3, Vector3.ZERO, Vector3(-1.45, 0, 0))  # CAN SHOOT mid-slide
	_k(trk, "Head", d * 0.3, Vector3.ZERO, Vector3(0.28, 0, 0))
	_done("slide", trk, d, false)
	# crouch idle
	trk = _new_trk()
	d = 2.0
	for i in range(5):
		var t := d * i / 4.0
		var br := sin(t / d * TAU)
		_k(trk, "Hips", t, Vector3(0, -0.42 + 0.008 * br, 0), Vector3.ZERO)
		_k(trk, "ThighL", t, Vector3.ZERO, Vector3(1.30, 0, 0))
		_k(trk, "ThighR", t, Vector3.ZERO, Vector3(1.30, 0, 0))
		_k(trk, "ShinL", t, Vector3.ZERO, Vector3(-1.95, 0, 0))
		_k(trk, "ShinR", t, Vector3.ZERO, Vector3(-1.95, 0, 0))
		_k(trk, "FootL", t, Vector3.ZERO, Vector3(0.65, 0, 0))
		_k(trk, "FootR", t, Vector3.ZERO, Vector3(0.65, 0, 0))
		_k(trk, "Spine1", t, Vector3.ZERO, Vector3(0.28 + 0.02 * br, 0, 0))
		_k(trk, "Head", t, Vector3.ZERO, Vector3(-0.22, 0, 0))
		_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.55, 0, 0.14))
		_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.55, 0, -0.14))
		_k(trk, "ForearmL", t, Vector3.ZERO, Vector3(0.95, 0, 0))
		_k(trk, "ForearmR", t, Vector3.ZERO, Vector3(0.95, 0, 0))
		_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-1.70, 0, 0))
	_done("crouch_idle", trk, d, true)
	# crouch walk: quiet lateral-ish steps
	_loco_crouch("crouch_walk", 0.72)
	# prone idle
	trk = _new_trk()
	d = 2.4
	for i in range(5):
		var t := d * i / 4.0
		var br := sin(t / d * TAU)
		_k(trk, "Hips", t, Vector3(0, -0.82, 0), Vector3.ZERO)
		_k(trk, "Spine", t, Vector3.ZERO, Vector3(0.55, 0, 0))
		_k(trk, "Spine1", t, Vector3(0, 0.01 * br, -0.02), Vector3(0.75 + 0.02 * br, 0, 0))
		_k(trk, "Head", t, Vector3.ZERO, Vector3(-1.05, 0, 0))  # head up, eyes forward
		_k(trk, "ThighL", t, Vector3.ZERO, Vector3(-0.45, 0, -0.06))
		_k(trk, "ThighR", t, Vector3.ZERO, Vector3(-0.45, 0, 0.06))
		_k(trk, "ShinL", t, Vector3.ZERO, Vector3(-0.12, 0, 0))
		_k(trk, "ShinR", t, Vector3.ZERO, Vector3(-0.12, 0, 0))
		_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.85, 0, 0.35))
		_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.85, 0, -0.35))
		_k(trk, "ForearmL", t, Vector3.ZERO, Vector3(0.55, 0, 0))
		_k(trk, "ForearmR", t, Vector3.ZERO, Vector3(0.55, 0, 0))
		_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-1.35, 0, 0))
	_done("prone_idle", trk, d, true)
	# prone crawl
	trk = _new_trk()
	d = 0.95
	var n := 6
	for i in range(n + 1):
		var t := d * i / n
		var ph := t / d * TAU
		_k(trk, "Hips", t, Vector3(0, -0.82, 0), Vector3(0, 0.06 * sin(ph), 0))
		_k(trk, "Spine1", t, Vector3.ZERO, Vector3(0.75, 0, 0.05 * sin(ph)))
		_k(trk, "Head", t, Vector3.ZERO, Vector3(-1.05, 0, 0))
		_k(trk, "ThighL", t, Vector3.ZERO, Vector3(-0.45 + 0.35 * sin(ph), 0, -0.06))
		_k(trk, "ThighR", t, Vector3.ZERO, Vector3(-0.45 + 0.35 * sin(ph + PI), 0, 0.06))
		_k(trk, "ShinL", t, Vector3.ZERO, Vector3(-0.12 - 0.35 * maxf(0.0, sin(ph + 1.2)), 0, 0))
		_k(trk, "ShinR", t, Vector3.ZERO, Vector3(-0.12 - 0.35 * maxf(0.0, sin(ph + PI + 1.2)), 0, 0))
		_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.85 + 0.25 * sin(ph + PI), 0, 0.35))
		_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.85 + 0.25 * sin(ph), 0, -0.35))
		_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-1.35, 0, 0))
	_done("prone_crawl", trk, d, true)


func _loco_crouch(cname: String, dur: float) -> void:
	var trk := _new_trk()
	var n := 6
	for i in range(n + 1):
		var t := dur * i / n
		var ph := t / dur * TAU
		var s := sin(ph)
		_k(trk, "Hips", t, Vector3(0, -0.42 - 0.02 * (0.5 - 0.5 * cos(2.0 * ph)), 0), Vector3.ZERO)
		_k(trk, "ThighL", t, Vector3.ZERO, Vector3(1.30 + 0.30 * s, 0, 0))
		_k(trk, "ThighR", t, Vector3.ZERO, Vector3(1.30 + 0.30 * sin(ph + PI), 0, 0))
		_k(trk, "ShinL", t, Vector3.ZERO, Vector3(-1.95 - 0.30 * maxf(0.0, sin(ph + 0.9)), 0, 0))
		_k(trk, "ShinR", t, Vector3.ZERO, Vector3(-1.95 - 0.30 * maxf(0.0, sin(ph + PI + 0.9)), 0, 0))
		_k(trk, "FootL", t, Vector3.ZERO, Vector3(0.65 - 0.2 * s, 0, 0))
		_k(trk, "FootR", t, Vector3.ZERO, Vector3(0.65 - 0.2 * sin(ph + PI), 0, 0))
		_k(trk, "Spine1", t, Vector3.ZERO, Vector3(0.28, 0, 0))
		_k(trk, "Head", t, Vector3.ZERO, Vector3(-0.22, 0, 0))
		_k(trk, "ShoulderL", t, Vector3.ZERO, Vector3(0.55, 0, 0.14))
		_k(trk, "ShoulderR", t, Vector3.ZERO, Vector3(0.55, 0, -0.14))
		_k(trk, "ForearmL", t, Vector3.ZERO, Vector3(0.95, 0, 0))
		_k(trk, "ForearmR", t, Vector3.ZERO, Vector3(0.95, 0, 0))
		_k(trk, "Weapon", t, Vector3.ZERO, Vector3(-1.70, 0, 0))
	_done(cname, trk, dur, true)


func _build_vault_melee() -> void:
	# vault: hands on obstacle, one leg swings over, ~0.6s
	var trk := _new_trk()
	var d := 0.6
	_k(trk, "Hips", 0.0, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Hips", d * 0.5, Vector3(0, 0.55, 0), Vector3.ZERO)
	_k(trk, "Hips", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "ShoulderL", d * 0.3, Vector3.ZERO, Vector3(1.35, 0, 0.2))
	_k(trk, "ShoulderR", d * 0.3, Vector3.ZERO, Vector3(1.35, 0, -0.2))
	_k(trk, "ForearmL", d * 0.3, Vector3.ZERO, Vector3(0.4, 0, 0))
	_k(trk, "ForearmR", d * 0.3, Vector3.ZERO, Vector3(0.4, 0, 0))
	_k(trk, "ThighL", d * 0.55, Vector3.ZERO, Vector3(1.25, 0, 0))
	_k(trk, "ShinL", d * 0.55, Vector3.ZERO, Vector3(-0.9, 0, 0))
	_k(trk, "ThighR", d * 0.7, Vector3.ZERO, Vector3(0.9, 0, 0))
	_k(trk, "ShinR", d * 0.7, Vector3.ZERO, Vector3(-1.1, 0, 0))
	_k(trk, "Spine1", d * 0.5, Vector3.ZERO, Vector3(0.25, 0.15, 0))
	_done("vault", trk, d, false)
	# melee lunge: knife hand stabs forward, torso twist, ~0.45s
	trk = _new_trk()
	d = 0.45
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.05, 0, 0))
	_k(trk, "Spine1", d * 0.45, Vector3.ZERO, Vector3(0.30, -0.55, 0))
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.05, 0, 0))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.45, 0, -0.1))
	_k(trk, "ShoulderR", d * 0.45, Vector3.ZERO, Vector3(1.35, 0, -0.05))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.1))
	_k(trk, "ForearmR", d * 0.45, Vector3.ZERO, Vector3(0.15, 0, 0))
	_k(trk, "ShoulderL", d * 0.45, Vector3.ZERO, Vector3(0.2, 0, 0.4))
	_k(trk, "Hips", d * 0.45, Vector3(0, -0.08, 0), Vector3.ZERO)
	_k(trk, "Head", d * 0.45, Vector3.ZERO, Vector3(0, -0.3, 0))
	_done("melee_lunge", trk, d, false, true)


func _build_air() -> void:
	# wingsuit glide: [FRAME] full SPREAD-EAGLE — arms AND legs fully
	# extended outward, body flat and horizontal, slight back arch, head up.
	var trk := _new_trk()
	_k(trk, "Spine", 0.0, Vector3.ZERO, Vector3(1.15, 0, 0))
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.30, 0, 0))
	_k(trk, "Head", 0.0, Vector3.ZERO, Vector3(-1.05, 0, 0))
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.15, 0, 1.45))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.15, 0, -1.45))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(0.05, 0, 0))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(0.05, 0, 0))
	_k(trk, "ThighL", 0.0, Vector3.ZERO, Vector3(-0.15, 0, -0.38))
	_k(trk, "ThighR", 0.0, Vector3.ZERO, Vector3(-0.15, 0, 0.38))
	_k(trk, "ShinL", 0.0, Vector3.ZERO, Vector3(-0.05, 0, 0))
	_k(trk, "ShinR", 0.0, Vector3.ZERO, Vector3(-0.05, 0, 0))
	_done("wingsuit", trk, 1.0, true)
	# parachute: upright, hands up on risers, legs slightly bent
	trk = _new_trk()
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(2.55, 0, 0.25))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(2.55, 0, -0.25))
	_k(trk, "ForearmL", 0.0, Vector3.ZERO, Vector3(0.45, 0, 0))
	_k(trk, "ForearmR", 0.0, Vector3.ZERO, Vector3(0.45, 0, 0))
	_k(trk, "ThighL", 0.0, Vector3.ZERO, Vector3(0.28, 0, 0))
	_k(trk, "ThighR", 0.0, Vector3.ZERO, Vector3(0.28, 0, 0))
	_k(trk, "ShinL", 0.0, Vector3.ZERO, Vector3(-0.38, 0, 0))
	_k(trk, "ShinR", 0.0, Vector3.ZERO, Vector3(-0.38, 0, 0))
	_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3(0.06, 0, 0))
	_k(trk, "Head", 0.0, Vector3.ZERO, Vector3(-0.25, 0, 0))
	_done("parachute", trk, 1.2, true)


func _build_hits() -> void:
	# Directional flinch: torso jolts away from the hit, brief stagger.
	var defs := {
		"hit_F": Vector3(-0.38, 0, 0),  # hit from front -> jolt back
		"hit_B": Vector3(0.38, 0, 0),  # hit from behind -> jolt forward
		"hit_L": Vector3(0, 0, -0.32),  # hit from left -> jolt right
		"hit_R": Vector3(0, 0, 0.32),  # hit from right -> jolt left
	}
	for cname in defs.keys():
		var j: Vector3 = defs[cname]
		var trk := _new_trk()
		var d := 0.35
		_k(trk, "Spine1", 0.0, Vector3.ZERO, Vector3.ZERO)
		_k(trk, "Spine1", d * 0.3, Vector3(j.x * 0.2, 0, j.z * 0.2), j)
		_k(trk, "Spine1", d, Vector3.ZERO, Vector3.ZERO)
		_k(trk, "Head", d * 0.3, Vector3.ZERO, j * 0.7)
		_k(trk, "Head", d, Vector3.ZERO, Vector3.ZERO)
		_k(trk, "ShoulderL", d * 0.3, Vector3.ZERO, Vector3(j.x * 0.8, 0, j.z * 0.8))
		_k(trk, "ShoulderR", d * 0.3, Vector3.ZERO, Vector3(j.x * 0.8, 0, j.z * 0.8))
		_k(trk, "Hips", d * 0.3, Vector3(j.x * 0.15, -0.03, j.z * 0.15), Vector3.ZERO)
		_k(trk, "Hips", d, Vector3.ZERO, Vector3.ZERO)
		_done(cname, trk, d, false)


func _build_death_victory() -> void:
	# death handoff: body crumples just before the simulator takes over
	var trk := _new_trk()
	var d := 0.45
	_k(trk, "Hips", 0.0, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Hips", d, Vector3(0, -0.35, 0), Vector3.ZERO)
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.45, 0.2, 0))
	_k(trk, "Head", d, Vector3.ZERO, Vector3(0.35, 0, 0))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(0.1, 0, 0.35))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.1, 0, -0.35))
	_k(trk, "ForearmL", d, Vector3.ZERO, Vector3(0.25, 0, 0))
	_k(trk, "ForearmR", d, Vector3.ZERO, Vector3(0.25, 0, 0))
	_k(trk, "ThighL", d, Vector3.ZERO, Vector3(0.35, 0, 0))
	_k(trk, "ThighR", d, Vector3.ZERO, Vector3(0.25, 0, 0))
	_done("death", trk, d, false)
	# victory emote: weapon raised high
	trk = _new_trk()
	d = 2.5
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ShoulderL", d * 0.3, Vector3.ZERO, Vector3(2.7, 0, 0.15))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_k(trk, "ShoulderR", d * 0.3, Vector3.ZERO, Vector3(2.7, 0, -0.15))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_k(trk, "Weapon", d * 0.3, Vector3.ZERO, Vector3(-2.6, 0, 0))
	_k(trk, "Spine1", d * 0.3, Vector3.ZERO, Vector3(-0.12, 0, 0))
	_k(trk, "Head", d * 0.3, Vector3.ZERO, Vector3(-0.2, 0, 0))
	_k(trk, "Hips", d * 0.45, Vector3(0, 0.06, 0), Vector3.ZERO)
	_k(trk, "Hips", d * 0.6, Vector3.ZERO, Vector3.ZERO)
	_done("victory", trk, d, false)
	# victory casual: weapon lowered, confident nod
	trk = _new_trk()
	d = 2.0
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_k(trk, "ShoulderR", d * 0.5, Vector3.ZERO, Vector3(0.55, 0, -0.12))
	_k(trk, "Head", d * 0.3, Vector3.ZERO, Vector3(-0.25, 0, 0))
	_k(trk, "Head", d * 0.6, Vector3.ZERO, Vector3(0.1, 0, 0))
	_k(trk, "Head", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Spine1", d * 0.5, Vector3.ZERO, Vector3(-0.08, 0, 0))
	_done("victory_casual", trk, d, false)


func _build_kill_variety() -> void:
	# Cause/direction death variants so no two kills look alike.
	# death_head: headshot snap-back — head whips back, body follows.
	var trk := _new_trk()
	var d := 0.4
	_k(trk, "Head", 0.0, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Head", d * 0.35, Vector3.ZERO, Vector3(-0.85, 0, 0))
	_k(trk, "Head", d, Vector3.ZERO, Vector3(-0.3, 0, 0))
	_k(trk, "Spine1", d * 0.35, Vector3.ZERO, Vector3(-0.4, 0, 0))
	_k(trk, "Hips", d, Vector3(0, -0.3, 0), Vector3.ZERO)
	_k(trk, "ShoulderL", d * 0.35, Vector3.ZERO, Vector3(-0.3, 0, 0.3))
	_k(trk, "ShoulderR", d * 0.35, Vector3.ZERO, Vector3(-0.3, 0, -0.3))
	_done("death_head", trk, d, false)
	# death_explosive: body hurled backward, limbs flailing.
	trk = _new_trk()
	d = 0.45
	_k(trk, "Hips", 0.0, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Hips", d, Vector3(0, 0.25, 0.6), Vector3(0, 0, 0))
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(-0.6, 0, 0.2))
	_k(trk, "Head", d, Vector3.ZERO, Vector3(-0.7, 0, 0))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(-1.2, 0, 0.9))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(-1.2, 0, -0.9))
	_k(trk, "ThighL", d, Vector3.ZERO, Vector3(0.9, 0, 0.2))
	_k(trk, "ThighR", d, Vector3.ZERO, Vector3(0.7, 0, -0.2))
	_done("death_explosive", trk, d, false)
	# death_fwd: collapse forward onto face.
	trk = _new_trk()
	d = 0.5
	_k(trk, "Hips", d, Vector3(0, -0.5, -0.15), Vector3.ZERO)
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.9, 0, 0))
	_k(trk, "Head", d, Vector3.ZERO, Vector3(0.6, 0, 0))
	_k(trk, "ThighL", d, Vector3.ZERO, Vector3(0.5, 0, 0))
	_k(trk, "ThighR", d, Vector3.ZERO, Vector3(0.4, 0, 0))
	_done("death_fwd", trk, d, false)
	# death_side: crumple sideways.
	trk = _new_trk()
	d = 0.5
	_k(trk, "Hips", d, Vector3(0.25, -0.45, 0), Vector3(0, 0, 0.5))
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0, 0, 0.8))
	_k(trk, "Head", d, Vector3.ZERO, Vector3(0, 0, 0.6))
	_k(trk, "ThighL", d, Vector3.ZERO, Vector3(0, 0, 0.4))
	_done("death_side", trk, d, false)
	# death_kneel: drop to knees, then pitch over.
	trk = _new_trk()
	d = 0.7
	_k(trk, "Hips", d * 0.45, Vector3(0, -0.55, 0), Vector3.ZERO)
	_k(trk, "ThighL", d * 0.45, Vector3.ZERO, Vector3(1.9, 0, 0))
	_k(trk, "ThighR", d * 0.45, Vector3.ZERO, Vector3(1.7, 0, 0))
	_k(trk, "ShinL", d * 0.45, Vector3.ZERO, Vector3(-1.9, 0, 0))
	_k(trk, "ShinR", d * 0.45, Vector3.ZERO, Vector3(-1.8, 0, 0))
	_k(trk, "Hips", d, Vector3(0, -0.7, -0.1), Vector3.ZERO)
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.7, 0, 0))
	_k(trk, "Head", d, Vector3.ZERO, Vector3(0.4, 0, 0))
	_done("death_kneel", trk, d, false)
	# death_stumble: two staggering steps, then fall.
	trk = _new_trk()
	d = 0.8
	_k(trk, "Hips", d * 0.3, Vector3(0, -0.1, -0.25), Vector3(0.15, 0, 0.1))
	_k(trk, "Hips", d * 0.6, Vector3(0, -0.25, -0.1), Vector3(-0.1, 0, -0.15))
	_k(trk, "Hips", d, Vector3(0, -0.55, 0.1), Vector3.ZERO)
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.5, 0, 0.2))
	_k(trk, "ShoulderL", d * 0.5, Vector3.ZERO, Vector3(0.6, 0, 0.5))
	_k(trk, "ShoulderR", d * 0.5, Vector3.ZERO, Vector3(0.6, 0, -0.5))
	_done("death_stumble", trk, d, false)


func _build_executions() -> void:
	# Stealth finishing takedowns: attacker + matching victim clips (~1.4 s).
	var trk := _new_trk()
	var d := 1.4
	# exec_necksnap: grab head, sharp twist.
	_k(trk, "ShoulderR", 0.0, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_k(trk, "ShoulderR", d * 0.35, Vector3(0, 0.1, -0.25), Vector3(1.4, 0, -0.5))
	_k(trk, "ForearmR", d * 0.35, Vector3.ZERO, Vector3(1.1, 0, 0))
	_k(trk, "ShoulderR", d * 0.55, Vector3(0, 0.1, -0.25), Vector3(1.4, -0.9, -0.5))
	_k(trk, "Head", d * 0.55, Vector3.ZERO, Vector3(0, -0.5, 0))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_k(trk, "Spine1", d * 0.45, Vector3.ZERO, Vector3(0.25, 0, 0))
	_done("exec_necksnap", trk, d, false)
	# exec_throat: arm across throat, drag back.
	trk = _new_trk()
	_k(trk, "ShoulderR", d * 0.3, Vector3(0, 0.15, -0.3), Vector3(1.1, 0, -1.2))
	_k(trk, "ForearmR", d * 0.3, Vector3.ZERO, Vector3(1.6, 0, 0))
	_k(trk, "ShoulderR", d * 0.6, Vector3(0, 0.1, -0.1), Vector3(0.9, 0, -1.4))
	_k(trk, "Spine1", d * 0.6, Vector3.ZERO, Vector3(-0.2, 0, 0))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_done("exec_throat", trk, d, false)
	# exec_silent: hand over mouth, strike, lower the body.
	trk = _new_trk()
	_k(trk, "ShoulderL", d * 0.3, Vector3(0, 0.15, -0.28), Vector3(1.2, 0, 0.6))
	_k(trk, "ShoulderR", d * 0.45, Vector3(0, 0.05, -0.2), Vector3(1.8, 0, -0.3))
	_k(trk, "Spine1", d * 0.7, Vector3.ZERO, Vector3(0.35, 0, 0))
	_k(trk, "Hips", d * 0.7, Vector3(0, -0.25, 0), Vector3.ZERO)
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_done("exec_silent", trk, d, false)
	# Victim variants (played on the enemy being executed).
	trk = _new_trk()
	_k(trk, "Head", d * 0.5, Vector3.ZERO, Vector3(0, 1.4, 0.3))
	_k(trk, "Spine1", d * 0.55, Vector3.ZERO, Vector3(-0.3, 0.4, 0))
	_k(trk, "Hips", d * 0.8, Vector3(0, -0.6, 0), Vector3.ZERO)
	_k(trk, "ShoulderL", d * 0.5, Vector3.ZERO, Vector3(0.8, 0, 0.6))
	_k(trk, "ShoulderR", d * 0.5, Vector3.ZERO, Vector3(0.8, 0, -0.6))
	_done("exec_victim_neck", trk, d, false)
	trk = _new_trk()
	_k(trk, "Head", d * 0.5, Vector3.ZERO, Vector3(-0.5, 0, 0))
	_k(trk, "ShoulderL", d * 0.4, Vector3.ZERO, Vector3(1.0, 0, 0.8))
	_k(trk, "Hips", d * 0.8, Vector3(0, -0.65, 0.1), Vector3.ZERO)
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(-0.5, 0, 0))
	_done("exec_victim_throat", trk, d, false)
	trk = _new_trk()
	_k(trk, "Head", d * 0.4, Vector3.ZERO, Vector3(0.3, 0, 0))
	_k(trk, "Hips", d, Vector3(0, -0.75, 0), Vector3.ZERO)
	_k(trk, "Spine1", d, Vector3.ZERO, Vector3(0.4, 0, 0))
	_k(trk, "ThighL", d, Vector3.ZERO, Vector3(1.4, 0, 0))
	_k(trk, "ThighR", d, Vector3.ZERO, Vector3(1.4, 0, 0))
	_done("exec_victim_silent", trk, d, false)


func _build_inspect_emotes() -> void:
	# Weapon inspect: lift and look over the gun (~3 s, upper body).
	var trk := _new_trk()
	var d := 3.0
	_k(trk, "ShoulderL", 0.0, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ShoulderL", d * 0.25, Vector3(0, 0.12, -0.1), Vector3(0.9, 0, 0.3))
	_k(trk, "ShoulderR", d * 0.25, Vector3(0, 0.12, -0.1), Vector3(0.9, 0, -0.3))
	_k(trk, "Head", d * 0.25, Vector3.ZERO, Vector3(0.35, 0, 0))
	_k(trk, "Weapon", d * 0.4, Vector3.ZERO, Vector3(0, 0.9, 0.2))
	_k(trk, "Weapon", d * 0.6, Vector3.ZERO, Vector3(0, -0.9, -0.2))
	_k(trk, "Head", d * 0.8, Vector3.ZERO, Vector3(-0.1, 0.3, 0))
	_k(trk, "ShoulderL", d, Vector3.ZERO, Vector3(0.45, 0, 0.12))
	_k(trk, "ShoulderR", d, Vector3.ZERO, Vector3(0.45, 0, -0.12))
	_k(trk, "Head", d, Vector3.ZERO, Vector3.ZERO)
	_k(trk, "Weapon", d, Vector3.ZERO, Vector3.ZERO)
	_done("inspect", trk, d, false)
	# Emotes: upper-body only, modest 2 s.
	var emotes := {
		"emote_wave": [["ShoulderR", 0.5, Vector3(2.4, 0, -0.3)], ["ForearmR", 0.5, Vector3(0.3, 0, 0)]],
		"emote_point": [["ShoulderR", 0.4, Vector3(1.5, 0, -0.1)], ["Head", 0.4, Vector3(0, -0.4, 0)]],
		"emote_taunt": [["ShoulderL", 0.4, Vector3(1.2, 0, 0.9)], ["ShoulderR", 0.4, Vector3(1.2, 0, -0.9)], ["Head", 0.4, Vector3(-0.2, 0, 0)]],
		"emote_nod": [["Head", 0.5, Vector3(0.4, 0, 0)]],
		"emote_shrug": [["ShoulderL", 0.5, Vector3(0.9, 0, 0.7)], ["ShoulderR", 0.5, Vector3(0.9, 0, -0.7)], ["Head", 0.5, Vector3(0.15, 0, 0.2)]],
		"emote_salute": [["ShoulderR", 0.4, Vector3(1.1, 0, -1.5)], ["ForearmR", 0.4, Vector3(1.9, 0, 0)], ["Head", 0.4, Vector3(-0.1, 0, 0)]],
	}
	for ename in emotes.keys():
		trk = _new_trk()
		d = 2.0
		for spec in (emotes[ename] as Array):
			var bone := str(spec[0])
			var peak: float = float(spec[1])
			var rot := spec[2] as Vector3
			_k(trk, bone, 0.0, Vector3.ZERO, Vector3.ZERO)
			_k(trk, bone, d * peak, Vector3.ZERO, rot)
			_k(trk, bone, d, Vector3.ZERO, Vector3.ZERO)
		_done(ename, trk, d, false, true)
