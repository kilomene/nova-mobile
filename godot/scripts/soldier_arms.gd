extends Node3D
class_name SoldierArms
## FPP arms viewmodel parented to the camera: detailed forearms with sleeves
## + gloves, procedural grip poses per weapon class. No per-frame allocations:
## precreated unit-box limb meshes are re-posed via transform only.

const GRIPS := ["rifle", "pistol", "launcher", "melee"]

# Hand targets per grip, camera-local: [R hand, L hand]
const GRIP_POSE := {
	"rifle": [Vector3(0.30, -0.30, -0.52), Vector3(0.14, -0.33, -0.74)],
	"pistol": [Vector3(0.28, -0.30, -0.50), Vector3(0.34, -0.62, -0.18)],
	"launcher": [Vector3(0.32, -0.16, -0.42), Vector3(0.10, -0.20, -0.60)],
	"melee": [Vector3(0.30, -0.32, -0.55), Vector3(0.33, -0.60, -0.20)],
}
const GRIP_ADS := {
	"rifle": [Vector3(0.015, -0.238, -0.44), Vector3(-0.01, -0.27, -0.62)],
	"pistol": [Vector3(0.0, -0.245, -0.44), Vector3(0.02, -0.30, -0.42)],
	"launcher": [Vector3(0.05, -0.16, -0.42), Vector3(0.0, -0.20, -0.60)],
	"melee": [Vector3(0.30, -0.32, -0.55), Vector3(0.33, -0.60, -0.20)],
}

var _grip := "rifle"
var _ads_t := 0.0
var _ads_target := 0.0
var _kick := Vector3.ZERO
var _kick_rot := 0.0
var _reload_ph := -1.0  # -1 idle, else 0..1
var _throw_ph := -1.0  # -1 idle, else 0..1 (left-hand throw)
var _sprint_t := 0.0
var _sprint_target := 0.0
var _bob_t := 0.0
var _bob_amp := 0.0
var _visible_hands := true

var _limbs: Array = []  # 4 MeshInstance3D: R upper, R fore, L upper, L fore
var _gloves: Array = []  # 2 MeshInstance3D
var _nade: MeshInstance3D  # grenade in left hand while cooking/throwing


func _ready() -> void:
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.26, 0.28, 0.18)
	sleeve.roughness = 0.92
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.12, 0.11, 0.09)
	glove.roughness = 0.7
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for i in range(4):
		var mi := MeshInstance3D.new()
		mi.mesh = unit
		mi.set_surface_override_material(0, sleeve)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_limbs.append(mi)
	for i in range(2):
		var g := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.075, 0.10, 0.09)
		g.mesh = bm
		g.set_surface_override_material(0, glove)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_gloves.append(g)
	_nade = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	_nade.mesh = sm
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.2, 0.28, 0.16)
	nm.roughness = 0.6
	nm.metallic = 0.3
	_nade.set_surface_override_material(0, nm)
	_nade.visible = false
	add_child(_nade)
	visible = _visible_hands


func set_grip(g: String) -> void:
	if GRIPS.has(g):
		_grip = g


func grip_name() -> String:
	return _grip


func set_ads(b: bool) -> void:
	_ads_target = 1.0 if b else 0.0


func set_sprint(b: bool) -> void:
	_sprint_target = 1.0 if b else 0.0


func add_kick(v: float) -> void:
	_kick += Vector3(0, v * 0.35, v)
	_kick_rot += v * 1.4


func set_reload_phase(ph: float) -> void:
	_reload_ph = ph


func set_throw_phase(ph: float) -> void:
	_throw_ph = ph
	_nade.visible = ph >= 0.0 and ph < 0.55


func set_bob(t: float, amp: float) -> void:
	_bob_t = t
	_bob_amp = amp


func set_hands_visible(b: bool) -> void:
	_visible_hands = b
	visible = b


func _limb(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		mi.visible = false
		return
	mi.visible = _visible_hands
	mi.position = (a + b) * 0.5
	# orient +Z along the limb
	var fwd := d / len
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.95:
		up = Vector3.RIGHT
	mi.basis = Basis.looking_at(fwd, up)
	mi.scale = Vector3(r * 2.0, r * 2.0, len)


func _process(delta: float) -> void:
	_ads_t = move_toward(_ads_t, _ads_target, delta * 7.0)
	_sprint_t = move_toward(_sprint_t, _sprint_target, delta * 6.0)
	_kick = _kick.move_toward(Vector3.ZERO, delta * 1.6)
	_kick_rot = move_toward(_kick_rot, 0.0, delta * 9.0)
	var hip: Array = GRIP_POSE[_grip]
	var adsp: Array = GRIP_ADS[_grip]
	var rh: Vector3 = (hip[0] as Vector3).lerp(adsp[0] as Vector3, _ads_t)
	var lh: Vector3 = (hip[1] as Vector3).lerp(adsp[1] as Vector3, _ads_t)
	# Sprint: weapon lowered, right hand drops, left hand pumps at side.
	var rh_sprint := Vector3(0.34, -0.52, -0.35)
	var lh_sprint := Vector3(0.30, -0.48, -0.30) + Vector3(0, 0.10 * sin(_bob_t * 6.0), 0)
	rh = rh.lerp(rh_sprint, _sprint_t)
	lh = lh.lerp(lh_sprint, _sprint_t)
	# Walk bob.
	var bob := Vector3(sin(_bob_t * 2.0) * 0.006, cos(_bob_t * 4.0) * 0.008, 0) * _bob_amp
	rh += bob
	lh += bob
	# Per-shot kick.
	rh += _kick
	lh += _kick * 0.7
	# Reload: left hand dips to the mag well, gun tilts (gun handled by player).
	if _reload_ph >= 0.0:
		var dip := sin(_reload_ph * PI)
		lh = lh.lerp(Vector3(0.20, -0.42, -0.45), dip * 0.8)
	# Grenade throw: left hand leaves the gun, overhand arc.
	if _throw_ph >= 0.0:
		var ph := _throw_ph
		var windup := Vector3(0.05, 0.05, -0.35)  # up beside the ear
		var release := Vector3(0.10, -0.10, -0.75)  # snapped forward
		if ph < 0.35:
			lh = lh.lerp(windup, ph / 0.35)
		elif ph < 0.55:
			lh = windup.lerp(release, (ph - 0.35) / 0.20)
		else:
			lh = release.lerp(hip[1] as Vector3, (ph - 0.55) / 0.45)
	# Elbows: out, down, back from the hands.
	var re := rh + Vector3(0.16, -0.26, 0.16)
	var le := lh + Vector3(-0.16, -0.26, 0.16)
	var ra := rh + Vector3(0.10, -0.62, 0.30)
	var la := lh + Vector3(-0.10, -0.62, 0.30)
	_limb(_limbs[0] as MeshInstance3D, ra, re, 0.055)
	_limb(_limbs[1] as MeshInstance3D, re, rh, 0.048)
	_limb(_limbs[2] as MeshInstance3D, la, le, 0.055)
	_limb(_limbs[3] as MeshInstance3D, le, lh, 0.048)
	var gr: MeshInstance3D = _gloves[0]
	var gl: MeshInstance3D = _gloves[1]
	gr.visible = _visible_hands
	gl.visible = _visible_hands
	gr.position = rh + Vector3(0, -0.02, -0.03)
	gl.position = lh + Vector3(0, -0.02, -0.03)
	gr.rotation = Vector3(_kick_rot * 0.4, 0, -0.15)
	gl.rotation = Vector3(_kick_rot * 0.3, 0, 0.15)
	if _nade.visible:
		_nade.position = lh + Vector3(0, 0.03, -0.02)
