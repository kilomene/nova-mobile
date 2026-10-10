extends SceneTree
## Headless verification for the CONTROLLER build (CODM-exact touch controls):
## ControlSettings store, fraction-based HUD layout, custom layout mode,
## sensitivity / gyro / aim-assist / simple-mode, armor plates, icon buttons.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_controller.gd

const HudScript := preload("res://scripts/hud.gd")

class MockEnemy extends Node3D:
	var alive := true
	func is_alive() -> bool:
		return alive

var _checks: Array = []
var _frame := 0
var _phase := 0
var _hud = null
var _player: NovaPlayer = null
var _mock: MockEnemy = null


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, ((" | " + detail) if detail != "" else ""))


func _initialize() -> void:
	ControlSettings.reset_defaults()
	ControlSettings.clear_layout()


func _process(delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _frame >= 2:
				_run_settings_checks()
				_phase = 1
		1:
			_build_hud()
			_run_button_checks()
			_phase = 2
		2:
			_run_layout_checks()
			_phase = 3
		3:
			_build_player()
			_run_sens_checks()
			_phase = 4
		4:
			_run_assist_checks()
			_phase = 5
		5:
			_run_simple_and_armor_checks()
			_phase = 6
		6:
			_run_touch_path_checks()
			_phase = 7
		7:
			_run_menu_checks()
			_summarize()
			return true
	return false


# ---------------- phase 0: settings store ----------------

func _run_settings_checks() -> void:
	_log_check("default cam_sens 1.0", ControlSettings.cam_sens == 1.0)
	_log_check("default ads_sens 0.6", ControlSettings.ads_sens == 0.6)
	_log_check("default zoom4 0.45", ControlSettings.zoom4_sens == 0.45)
	_log_check("default zoom8 0.35", ControlSettings.zoom8_sens == 0.35)
	_log_check("default invert off", not ControlSettings.invert_y)
	_log_check("default gyro off", not ControlSettings.gyro_enabled)
	_log_check("default assist on 0.5",
		ControlSettings.aim_assist and ControlSettings.assist_strength == 0.5)
	_log_check("default fire_mode advanced", ControlSettings.fire_mode == "advanced")
	_log_check("default haptics on", ControlSettings.haptics)
	_log_check("default opacity 1.0", ControlSettings.hud_opacity == 1.0)
	# Clamping.
	ControlSettings.setv("cam_sens", 99.0)
	_log_check("cam_sens clamps to 3.0", ControlSettings.cam_sens == 3.0)
	ControlSettings.setv("assist_strength", -1.0)
	_log_check("assist_strength clamps to 0.0", ControlSettings.assist_strength == 0.0)
	ControlSettings.setv("fire_mode", "simple")
	_log_check("fire_mode simple", ControlSettings.fire_mode == "simple")
	ControlSettings.setv("fire_mode", "bogus")
	_log_check("fire_mode rejects bogus", ControlSettings.fire_mode == "advanced")
	# Layout set/get/clear.
	ControlSettings.set_layout("fire", Vector2(0.5, 0.5), 0.12)
	var ov := ControlSettings.get_layout("fire")
	_log_check("layout set/get", not ov.is_empty()
		and (ov["p"] as Vector2).distance_to(Vector2(0.5, 0.5)) < 0.001
		and absf(float(ov["d"]) - 0.12) < 0.001)
	_log_check("layout missing -> empty", ControlSettings.get_layout("nope").is_empty())
	# Save / load round-trip.
	ControlSettings.setv("cam_sens", 2.5)
	ControlSettings.setv("invert_y", true)
	ControlSettings.save_all()
	ControlSettings.reset_defaults()
	ControlSettings.clear_layout()
	_log_check("reset restores cam 1.0", ControlSettings.cam_sens == 1.0)
	ControlSettings.load_all()
	_log_check("load restores cam 2.5", ControlSettings.cam_sens == 2.5)
	_log_check("load restores invert", ControlSettings.invert_y)
	var ov2 := ControlSettings.get_layout("fire")
	_log_check("load restores layout", not ov2.is_empty()
		and (ov2["p"] as Vector2).distance_to(Vector2(0.5, 0.5)) < 0.001)
	# Clean slate for the rest of the suite.
	ControlSettings.reset_defaults()
	ControlSettings.clear_layout()
	ControlSettings.save_all()


# ---------------- phase 1: HUD buttons ----------------

func _build_hud() -> void:
	_hud = HudScript.new()
	root.add_child(_hud)  # _ready runs here (headless: is_mobile=false)
	_hud.is_mobile = true  # force AFTER _ready: headless has no touchscreen
	_hud._build_touch_buttons()
	_hud._apply_layout()


func _run_button_checks() -> void:
	var n_ids := HudScript.LAYOUT.size()
	_log_check("17 touch buttons", _hud._touch_buttons.size() == 17 and n_ids == 17,
		"n=" + str(_hud._touch_buttons.size()) + " layout=" + str(n_ids))
	var icons_ok := true
	for id in HudScript.LAYOUT:
		if not _hud._touch_buttons.has(id):
			icons_ok = false
			break
		var b: HudIconButton = _hud._touch_buttons[id]
		if b.icon != str(HudScript.LAYOUT[id]["icon"]):
			icons_ok = false
			break
	_log_check("button icons match layout", icons_ok)
	# Cooldown sweep API.
	_hud.start_cooldown("fire", 1.0)
	var fb: HudIconButton = _hud._touch_buttons["fire"]
	_log_check("cooldown starts", fb.cooldown_left() > 0.0)
	fb._process(1.1)
	_log_check("cooldown expires", fb.cooldown_left() == 0.0)


# ---------------- phase 2: layout geometry ----------------

func _run_layout_checks() -> void:
	for vp in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2048, 1536)]:
		_check_layout_at(vp)
	# Custom override is honored by compute_layout.
	ControlSettings.set_layout("fire", Vector2(0.5, 0.5), 0.10)
	var lr: Dictionary = _hud.compute_layout(Vector2(1280, 720))
	var rc: Vector2 = (lr["fire"] as Rect2).get_center()
	_log_check("custom layout overrides pos",
		rc.distance_to(Vector2(640, 360)) < 2.0, str(rc))
	ControlSettings.clear_layout()


func _check_layout_at(vp: Vector2) -> void:
	var tag := "%dx%d" % [int(vp.x), int(vp.y)]
	var lr: Dictionary = _hud.compute_layout(vp)
	var ids := lr.keys()
	# All rects inside the viewport.
	var inside := true
	for id in ids:
		var r: Rect2 = lr[id]
		if r.position.x < -2 or r.position.y < -2 or r.end.x > vp.x + 2 or r.end.y > vp.y + 2:
			inside = false
	_log_check("layout in bounds " + tag, inside)
	# Fire button bottom-right, ADS above-left of it (CODM cluster).
	var fc: Vector2 = (lr["fire"] as Rect2).get_center()
	var ac: Vector2 = (lr["ads"] as Rect2).get_center()
	_log_check("fire bottom-right " + tag, fc.x > vp.x * 0.85 and fc.y > vp.y * 0.65, str(fc))
	_log_check("ads above-left of fire " + tag, ac.x < fc.x and ac.y < fc.y, str(ac))
	# No heavy pairwise overlap.
	var overlap_ok := true
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a: Rect2 = lr[ids[i]]
			var b: Rect2 = lr[ids[j]]
			var inter := a.intersection(b)
			if inter.get_area() > 0.01:
				var ratio: float = inter.get_area() / minf(a.get_area(), b.get_area())
				if ratio > 0.25:
					overlap_ok = false
	_log_check("buttons don't overlap " + tag, overlap_ok)
	# Joystick zone (left-bottom) must not cover any button.
	var jz: Rect2 = _hud._joy_zone(vp)
	var jz_ok := true
	for id in ids:
		if jz.intersects(lr[id] as Rect2):
			jz_ok = false
	_log_check("joystick zone clear " + tag, jz_ok)


# ---------------- phase 3: player + sensitivity ----------------

func _build_player() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate() as NovaPlayer
	_player.position = Vector3.ZERO
	_player.rotation.y = 0.0
	_player.yaw = 0.0
	_player.pitch = 0.0
	root.add_child(_player)
	# No floor in the test scene: stop gravity from dragging the camera down
	# (simple-mode/aim-assist geometry assumes a standing player).
	_player.set_physics_process(false)
	_player._hud_override = _hud
	_mock = MockEnemy.new()
	_mock.position = Vector3(0, 0, -10)
	root.add_child(_mock)
	_hud.enemies = [_mock]


func _run_sens_checks() -> void:
	ControlSettings.setv("cam_sens", 2.0)
	_player.ads = false
	var s := _player._touch_look_sens()
	_log_check("touch sens scales with cam_sens", absf(s - 0.0045 * 2.0) < 0.00001, str(s))
	_player.ads = true  # m5 default: no magnified optic -> ads_sens
	var sa := _player._touch_look_sens()
	_log_check("ads sens applies", absf(sa - 0.0045 * 2.0 * 0.6) < 0.00001, str(sa))
	_player.ads = false
	var sm := _player._mouse_look_sens()
	_log_check("mouse sens scales", absf(sm - 0.0026 * 2.0) < 0.00001, str(sm))
	ControlSettings.setv("cam_sens", 1.0)
	# Invert Y.
	ControlSettings.setv("invert_y", true)
	_player.pitch = 0.0
	_player.rotate_look(0.0, 0.1)
	_log_check("invert_y flips pitch", _player.pitch < -0.09, str(_player.pitch))
	ControlSettings.setv("invert_y", false)
	_player.pitch = 0.0
	_player.rotate_look(0.0, 0.1)
	_log_check("normal pitch up", _player.pitch > 0.09, str(_player.pitch))
	_player.pitch = 0.0
	# Gyro path: no sensor headless -> no-op, must not crash or drift.
	ControlSettings.setv("gyro_enabled", true)
	_player._update_controller(0.016)
	_log_check("gyro no-op headless", absf(_player.yaw) < 0.00001 and absf(_player.pitch) < 0.00001)
	ControlSettings.setv("gyro_enabled", false)


# ---------------- phase 4: aim assist ----------------

func _run_assist_checks() -> void:
	ControlSettings.setv("aim_assist", false)
	var d0 := _player._assist_delta(0.1, 0.05)
	_log_check("assist off -> identity", d0 == Vector2(0.1, 0.05), str(d0))
	ControlSettings.setv("aim_assist", true)
	ControlSettings.setv("assist_strength", 0.5)
	_player.ads = false
	_player.yaw = 0.0
	_player.pitch = 0.0
	# Enemy ~2.3 deg off crosshair: magnetism slows the look, no reversal.
	var d1 := _player._assist_delta(0.1, 0.0)
	_log_check("magnetism slows near target", d1.x < 0.1 and d1.x > 0.05, str(d1))
	# Enemy far outside the cone: unchanged.
	_mock.position = Vector3(10, 0, -10)
	var d2 := _player._assist_delta(0.1, 0.0)
	_log_check("out-of-cone -> identity", d2 == Vector2(0.1, 0.0), str(d2))
	_mock.position = Vector3(0, 0, -10)
	# ADS rotational assist: gentle pull toward the (slightly low) target.
	_player.ads = true
	var d3 := _player._assist_delta(0.0, 0.0)
	_log_check("ads pull is gentle", absf(d3.x) < 0.012 and absf(d3.y) < 0.012, str(d3))
	_log_check("ads pull aims down at low chest", d3.y < 0.0, str(d3.y))
	_player.ads = false
	# Dead enemy: no assist.
	_mock.alive = false
	var d4 := _player._assist_delta(0.1, 0.0)
	_log_check("dead enemy -> identity", d4 == Vector2(0.1, 0.0), str(d4))
	_mock.alive = true


# ---------------- phase 5: simple mode + armor plates ----------------

func _run_simple_and_armor_checks() -> void:
	_player.ads = false
	# Undo the ADS fov lerp from the assist phase: simple-mode's 48px
	# threshold is fov-sensitive, so pin hip fov for a deterministic check.
	var cam: Camera3D = _player.get_node("Head/Camera3D")
	cam.fov = 75.0
	# "Centered" means on the crosshair: the Head carries a ~5.7 deg up-pitch,
	# so drop the chest exactly onto the camera's forward ray at 10 m.
	var fwd := -cam.global_transform.basis.z
	_mock.global_position = cam.global_position + fwd * 10.0 - Vector3(0, 1.2, 0)
	_mock.alive = true
	_log_check("simple mode sees centered enemy", _player._simple_mode_has_target())
	_mock.global_position = Vector3(0, 1.6, 10)  # behind the player
	_log_check("simple mode ignores behind", not _player._simple_mode_has_target())
	_mock.alive = false
	_mock.global_position = cam.global_position + fwd * 10.0 - Vector3(0, 1.2, 0)
	_log_check("simple mode ignores dead", not _player._simple_mode_has_target())
	_mock.alive = true
	# Armor plates: CODM flow — pickup plates, apply via button, 2s, +50.
	_player.armor = 0
	_player.armor_plates = 0
	_player.add_armor_plate()
	_player.add_armor_plate()
	_log_check("plates picked up", _player.armor_plates == 2)
	_log_check("armor btn shows count",
		(_hud._touch_buttons["armor"] as HudIconButton).caption == "ARMOR 2")
	_player.apply_armor_plate()
	_log_check("apply starts 2s timer", absf(_player._armor_timer - 2.0) < 0.01
		and _player.armor_plates == 1)
	_player._update_controller(2.1)
	_log_check("apply grants +50 armor", _player.armor == 50, str(_player.armor))
	# Full armor: apply is refused, plate kept.
	_player.armor = 150
	_player.apply_armor_plate()
	_log_check("apply refused at max armor", _player.armor_plates == 1
		and _player._armor_timer <= 0.0)
	_player.armor = 0


# ---------------- phase 6: touch paths ----------------

func _touch_event(idx: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.pressed = pressed
	e.position = pos
	return e


func _run_touch_path_checks() -> void:
	var vp: Vector2 = _hud.get_viewport().get_visible_rect().size
	# Minimap tap toggles expanded view.
	var mr: Rect2 = _hud._mmap_rect(vp)
	var c := mr.get_center()
	_hud._input(_touch_event(21, true, c))
	_hud._input(_touch_event(21, false, c))
	_log_check("minimap tap expands", _hud._mmap_big)
	_hud._input(_touch_event(21, true, c))
	_hud._input(_touch_event(21, false, c))
	_log_check("minimap tap collapses", not _hud._mmap_big)
	# consume_look_drag: empty area ok, buttons/minimap rejected.
	var dg := InputEventScreenDrag.new()
	dg.index = 31
	dg.position = Vector2(vp.x * 0.5, vp.y * 0.45)
	_log_check("look drag in open area", _hud.consume_look_drag(dg))
	var lr: Dictionary = _hud.compute_layout(vp)
	dg.position = (lr["fire"] as Rect2).get_center()
	_hud._touch_start[31] = dg.position
	_log_check("look drag on fire btn rejected", not _hud.consume_look_drag(dg))
	dg.position = mr.get_center()
	_hud._touch_start[31] = dg.position
	_log_check("look drag on minimap rejected", not _hud.consume_look_drag(dg))
	# Multi-touch: two drags on different indices don't crash.
	var d1 := InputEventScreenDrag.new()
	d1.index = 32
	d1.position = Vector2(vp.x * 0.5, vp.y * 0.45)
	d1.relative = Vector2(4, -2)
	_hud._input(_touch_event(32, true, d1.position))
	_hud._input(d1)
	_hud._input(_touch_event(32, false, d1.position))
	_log_check("multi-touch path clean", true)
	# Customize mode: drag the fire button, layout persists.
	_hud.set_customize(true)
	_log_check("customize shows chrome", _hud._cz_done_btn.visible)
	var fc: Vector2 = (lr["fire"] as Rect2).get_center()
	_hud._input(_touch_event(41, true, fc))
	_log_check("customize grabs button", _hud._cz_touch.has(41))
	var target := Vector2(vp.x * 0.35, vp.y * 0.55)
	var dr := InputEventScreenDrag.new()
	dr.index = 41
	dr.position = target
	_hud._input(dr)
	_hud._input(_touch_event(41, false, target))
	var ov := ControlSettings.get_layout("fire")
	_log_check("customize drag saves pos", not ov.is_empty()
		and (ov["p"] as Vector2).distance_to(Vector2(0.35, 0.55)) < 0.05, str(ov.get("p")))
	_log_check("joystick idle in customize", _hud._joy_idx == -1)
	_hud.set_customize(false)
	_log_check("customize exits", not _hud._cz_done_btn.visible)
	ControlSettings.clear_layout()


# ---------------- phase 7: settings menu ----------------

func _run_menu_checks() -> void:
	var sm := SettingsMenu.new()
	root.add_child(sm)
	sm.open()
	_log_check("settings opens", sm._built)
	var headers := 0
	for n in _all_descendants(sm):
		if n is Label and str((n as Label).text) in ["SENSITIVITY", "GYROSCOPE",
			"AIM ASSIST", "FIRE MODE", "FEEL", "HUD LAYOUT", "GRAPHICS"]:
			headers += 1
	_log_check("settings has 7 sections", headers == 7, "n=" + str(headers))
	sm.close()
	_log_check("settings closes", sm.is_queued_for_deletion())
	# Restore clean persisted state.
	ControlSettings.reset_defaults()
	ControlSettings.clear_layout()
	ControlSettings.save_all()


func _all_descendants(n: Node) -> Array:
	var out := []
	for ch in n.get_children():
		out.append(ch)
		out.append_array(_all_descendants(ch))
	return out


func _summarize() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("CONTROLLER: %d checks, %d failures" % [_checks.size(), fails])
	if fails > 0:
		quit(1)
	else:
		quit(0)
