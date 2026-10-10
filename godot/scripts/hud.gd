extends CanvasLayer
## CODM Advanced-Mode HUD: minimap, health/armor, ammo, fire/ADS/jump cluster,
## hitmarkers, directional damage vignette, kill feed, zone timer.
##
## Controller build: exact CODM Advanced-Mode layout (screen-fraction based,
## works at 720p/1080p/tablet), custom HUD mode (drag/pinch/save), tap-to-expand
## minimap, armor-plate + scorestreak + settings buttons, haptics on hits.

class Paint extends Control:
	var fn: Callable = Callable()
	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)

# --- CODM Advanced-Mode default layout ---
# id -> {icon, label, pos: Vector2 center as screen fractions,
#        d: diameter as fraction of viewport height, kind: "hold"|"tap"}
const LAYOUT := {
	"fire":   {"icon": "fire",    "label": "FIRE",   "pos": Vector2(0.925, 0.780), "d": 0.175, "kind": "hold"},
	"ads":    {"icon": "ads",     "label": "ADS",    "pos": Vector2(0.815, 0.655), "d": 0.115, "kind": "tap"},
	"jump":   {"icon": "jump",    "label": "JUMP",   "pos": Vector2(0.925, 0.575), "d": 0.115, "kind": "hold"},
	"crouch": {"icon": "crouch",  "label": "CRCH",   "pos": Vector2(0.805, 0.795), "d": 0.110, "kind": "hold"},
	"prone":  {"icon": "prone",   "label": "PRN",    "pos": Vector2(0.715, 0.685), "d": 0.095, "kind": "tap"},
	"grenade":{"icon": "grenade", "label": "GRN",    "pos": Vector2(0.925, 0.400), "d": 0.105, "kind": "hold"},
	"sprint": {"icon": "sprint",  "label": "SPRINT", "pos": Vector2(0.695, 0.830), "d": 0.085, "kind": "tap"},
	"reload": {"icon": "reload",  "label": "RLD",    "pos": Vector2(0.615, 0.900), "d": 0.080, "kind": "tap"},
	"swap":   {"icon": "swap",    "label": "SWAP",   "pos": Vector2(0.615, 0.790), "d": 0.080, "kind": "tap"},
	"armor":  {"icon": "armor",   "label": "ARMOR",  "pos": Vector2(0.545, 0.900), "d": 0.080, "kind": "tap"},
	"streak": {"icon": "streak",  "label": "STREAK", "pos": Vector2(0.545, 0.790), "d": 0.080, "kind": "tap"},
	"inspect":{"icon": "inspect", "label": "INSP",   "pos": Vector2(0.495, 0.900), "d": 0.070, "kind": "hold"},
	"emote":  {"icon": "emote",   "label": "EMOTE",  "pos": Vector2(0.495, 0.790), "d": 0.070, "kind": "tap"},
	"gfx":    {"icon": "gfx",     "label": "GFX",    "pos": Vector2(0.845, 0.300), "d": 0.060, "kind": "tap"},
	"gear":   {"icon": "gear",    "label": "SET",    "pos": Vector2(0.845, 0.375), "d": 0.060, "kind": "tap"},
	"ping":   {"icon": "ping",    "label": "PING",   "pos": Vector2(0.845, 0.450), "d": 0.060, "kind": "tap"},
	"smoke":  {"icon": "smoke",   "label": "SMK",    "pos": Vector2(0.845, 0.525), "d": 0.060, "kind": "tap"},
}
const MMAP_POS := Vector2(0.900, 0.150)  # center, fractions
const MMAP_D := 0.260                    # diameter, fraction of height
const MMAP_D_BIG := 0.440

var player: NovaPlayer
var enemies: Array = []
var allies: Array = []  # squad teammates (NovaAlly) — plates + minimap dots
var is_mobile := false

# Touch tracking.
var _joy_idx := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
const JOY_RADIUS := 110.0
var _touch_start := {}  # index -> Vector2 (for look filtering)

# HUD state.
var _spread := 0.0
var _hitmark_timer := 0.0
var _hitmark_kill := false
var _reload_label_visible := false
var _mm_timer := 0.0
var _killfeed_count := 0
var _mmap_big := false
var _mmap_tap := {}  # touch index -> {"pos": Vector2, "t": float}

# Custom HUD mode.
var _customize := false
var _cz_touch := {}   # touch index -> button id (move drag)
var _cz_grab := {}    # touch index -> grab offset (px, touch - button center)
var _cz_pinch := {}   # button id -> last pinch distance (px)
var _cz_hint: Label
var _cz_done_btn: HudIconButton
var _cz_reset_btn: HudIconButton

# Minimap / zone data (set by main).
var zone_center := Vector2.ZERO
var zone_radius := 60.0
var next_center := Vector2.ZERO
var next_radius := 60.0
var zone_label_text := ""
# World (battle royale) mode: whole-world minimap + region labels.
var world_mode := false
var world_extent := 70.0
var map_labels: Array = []  # {"name", "pos"}

# Nodes.
var _cross: Paint
var _hitm: Paint
var _mmap: Paint
var _bars: Paint
var _joy: Paint
var _ammo_label: Label
var _wname_label: Label
var _stk_label: Label
var _armor_break_t := 0.0
var _exec_banner_t := 0.0
var _inspect_label: Label
var _emote_panel: Control
var _emote_buttons: Array = []
var _score_label: Label
var _zone_label: Label
var _match_label: Label
var _end_banner: Label
var _hint_label: Label
# --- squad UI ---
var _squad_panel: VBoxContainer
var _squad_rows: Array = []
var _squad_hint: Label
var _squad_t := 0.0
var _downed_overlay: ColorRect
var _downed_label: Label
var _downed_timer: Label
var _toast_label: Label
var _reload_hint: Label
var _killfeed: VBoxContainer
var _vig_top: ColorRect
var _vig_bottom: ColorRect
var _vig_left: ColorRect
var _vig_right: ColorRect
var _vig_timer := 0.0
var _vig_which: ColorRect = null
var _touch_buttons := {}  # id -> Button
var _sprint_on := false


func _ready() -> void:
	is_mobile = DisplayServer.is_touchscreen_available()
	layer = 10
	_build()
	get_viewport().size_changed.connect(_on_vp_resized)


func _on_vp_resized() -> void:
	_apply_layout()
	_layout_static()
	if _squad_panel != null:
		_layout_squad_ui(get_viewport().get_visible_rect().size)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	s.set_corner_radius_all(10)
	return s


func _make_button(icon: String, caption: String) -> HudIconButton:
	var b := HudIconButton.new(icon, caption)
	add_child(b)
	return b


# ---------------- layout ----------------

## Pure layout computation (testable): button id -> Rect2 in pixels.
func compute_layout(vp: Vector2) -> Dictionary:
	var out := {}
	for id in LAYOUT:
		var e: Dictionary = LAYOUT[id]
		var pos: Vector2 = e["pos"]
		var d: float = e["d"]
		var ov := ControlSettings.get_layout(id)
		if not ov.is_empty():
			pos = ov["p"]
			d = float(ov["d"])
		var dpx := d * vp.y
		out[id] = Rect2(vp.x * pos.x - dpx * 0.5, vp.y * pos.y - dpx * 0.5,
			dpx, dpx)
	return out


func _mmap_rect(vp: Vector2) -> Rect2:
	var d := (MMAP_D_BIG if _mmap_big else MMAP_D) * vp.y
	return Rect2(vp.x * MMAP_POS.x - d * 0.5, vp.y * MMAP_POS.y - d * 0.5, d, d)


func _apply_layout() -> void:
	if not is_mobile:
		return
	var vp := get_viewport().get_visible_rect().size
	var lr := compute_layout(vp)
	for id in _touch_buttons:
		var b: HudIconButton = _touch_buttons[id]
		var r: Rect2 = lr[id]
		b.position = r.position
		b.size = r.size
		b.queue_redraw()
	var mr := _mmap_rect(vp)
	_mmap.position = mr.position
	_mmap.size = mr.size
	_apply_opacity()


func _apply_opacity() -> void:
	var a := ControlSettings.hud_opacity
	for id in _touch_buttons:
		(_touch_buttons[id] as HudIconButton).modulate.a = a


func apply_opacity() -> void:
	_apply_opacity()


func _layout_static() -> void:
	# Static (non-button) HUD elements, repositioned on resize.
	var vp := get_viewport().get_visible_rect().size
	_cross.position = vp * 0.5 - Vector2(30, 30)
	_hitm.position = vp * 0.5 - Vector2(30, 30)
	_bars.position = Vector2(vp.x * 0.5 - 130, vp.y - 64)
	_wname_label.position = Vector2(vp.x * 0.5 + 150, vp.y - 66)
	_ammo_label.position = Vector2(vp.x * 0.5 + 150, vp.y - 40)
	_stk_label.position = Vector2(vp.x * 0.5 + 150, vp.y - 16)
	_reload_hint.position = Vector2(vp.x * 0.5 + 150, vp.y - 92)
	_score_label.position = Vector2(16, 14)
	_zone_label.position = Vector2(vp.x * 0.5 - 90, 14)
	_match_label.position = Vector2(vp.x * 0.5 - 40, 42)
	_end_banner.position = Vector2(vp.x * 0.5 - 400, vp.y * 0.35)
	_killfeed.position = Vector2(16, 48)
	_toast_label.position = Vector2(vp.x * 0.5 - 200, vp.y * 0.62)
	_vig_top.position = Vector2(vp.x * 0.5 - 160, 0)
	_vig_bottom.position = Vector2(vp.x * 0.5 - 160, vp.y - 26)
	_vig_left.position = Vector2(0, vp.y * 0.5 - 160)
	_vig_right.position = Vector2(vp.x - 26, vp.y * 0.5 - 160)
	if _inspect_label != null:
		_inspect_label.position = Vector2(vp.x * 0.5 - 70, vp.y * 0.30)
	if _emote_panel != null:
		_emote_panel.position = Vector2(vp.x * 0.5 - 345, vp.y * 0.55)
		for i in range(_emote_buttons.size()):
			(_emote_buttons[i] as Button).position = Vector2(i * 116, 0)
	_hint_label.position = Vector2(16, vp.y - 34)
	if _cz_hint:
		_cz_hint.position = Vector2(vp.x * 0.5 - 260, 90)
	if _cz_done_btn:
		_cz_done_btn.position = Vector2(vp.x * 0.5 - 220, vp.y - 110)
	if _cz_reset_btn:
		_cz_reset_btn.position = Vector2(vp.x * 0.5 + 20, vp.y - 110)
	_veh_layout()


func _joy_zone(vp: Vector2) -> Rect2:
	# Left-bottom region: dynamic-origin joystick area (CODM style).
	return Rect2(0, vp.y * 0.38, vp.x * 0.45, vp.y * 0.62)


func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	# --- Crosshair (center). ---
	_cross = Paint.new()
	_cross.fn = _draw_crosshair
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)
	# --- Hitmarker. ---
	_hitm = Paint.new()
	_hitm.fn = _draw_hitmarker
	_hitm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hitm)
	# --- Minimap (top-right, circular, tap to expand). ---
	_mmap = Paint.new()
	_mmap.fn = _draw_minimap
	_mmap.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_mmap)
	# --- Health/armor bars (bottom-center). ---
	_bars = Paint.new()
	_bars.fn = _draw_bars
	_bars.size = Vector2(260, 52)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars)
	# --- Ammo / weapon panel (bottom-center-right). ---
	_wname_label = Label.new()
	_wname_label.text = "RIFLE"
	_wname_label.add_theme_font_size_override("font_size", 20)
	_wname_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wname_label)
	_stk_label = Label.new()
	_stk_label.text = ""
	_stk_label.add_theme_font_size_override("font_size", 14)
	_stk_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_stk_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stk_label)
	_ammo_label = Label.new()
	_ammo_label.text = "30 | 120"
	_ammo_label.add_theme_font_size_override("font_size", 26)
	_ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ammo_label)
	_reload_hint = Label.new()
	_reload_hint.text = "RELOADING..."
	_reload_hint.add_theme_font_size_override("font_size", 16)
	_reload_hint.add_theme_color_override("font_color", Color(1, 0.6, 0.15))
	_reload_hint.visible = false
	_reload_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reload_hint)
	# --- Score (top-left). ---
	_score_label = Label.new()
	_score_label.text = "SCORE 0"
	_score_label.add_theme_font_size_override("font_size", 22)
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score_label)
	# --- Zone timer (top-center). ---
	_zone_label = Label.new()
	_zone_label.text = ""
	_zone_label.add_theme_font_size_override("font_size", 22)
	_zone_label.add_theme_color_override("font_color", Color(1, 0.75, 0.3))
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_zone_label)
	# --- Match timer (below zone timer). ---
	_match_label = Label.new()
	_match_label.text = ""
	_match_label.add_theme_font_size_override("font_size", 18)
	_match_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.9))
	_match_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_match_label)
	# --- End-of-match banner (center, hidden). ---
	_end_banner = Label.new()
	_end_banner.text = ""
	_end_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_banner.size = Vector2(800, 90)
	_end_banner.add_theme_font_size_override("font_size", 54)
	_end_banner.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
	_end_banner.visible = false
	_end_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_end_banner)
	# --- Toast (small center message). ---
	_toast_label = Label.new()
	_toast_label.text = ""
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.size = Vector2(400, 40)
	_toast_label.add_theme_font_size_override("font_size", 22)
	_toast_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_toast_label.modulate.a = 0.0
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_label)
	# --- Kill feed (below score). ---
	_killfeed = VBoxContainer.new()
	_killfeed.add_theme_constant_override("separation", 2)
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_killfeed)
	# --- Damage vignette edges. ---
	_vig_top = _make_vig(Vector2(320, 26))
	_vig_bottom = _make_vig(Vector2(320, 26))
	_vig_left = _make_vig(Vector2(26, 320))
	_vig_right = _make_vig(Vector2(26, 320))
	# --- Joystick paint (dynamic origin). ---
	_joy = Paint.new()
	_joy.fn = _draw_joystick
	_joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy.visible = is_mobile
	add_child(_joy)
	# --- Touch buttons (mobile only). ---
	if is_mobile:
		_build_touch_buttons()
		_apply_layout()
	# --- Squad UI: teammate plates, contextual hint, downed overlay. ---
	_build_squad_ui()

func _build_squad_ui() -> void:
	_squad_panel = VBoxContainer.new()
	_squad_panel.position = Vector2(16, 176)
	_squad_panel.add_theme_constant_override("separation", 4)
	_squad_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_squad_panel)
	for i in range(3):
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", _panel_style())
		plate.custom_minimum_size = Vector2(196, 34)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		plate.add_child(hb)
		var nm := Label.new()
		nm.add_theme_font_size_override("font_size", 15)
		nm.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		nm.custom_minimum_size = Vector2(86, 0)
		hb.add_child(nm)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = 100
		bar.custom_minimum_size = Vector2(56, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		hb.add_child(bar)
		var st := Label.new()
		st.add_theme_font_size_override("font_size", 14)
		st.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		hb.add_child(st)
		_squad_panel.add_child(plate)
		_squad_rows.append({"plate": plate, "name": nm, "bar": bar, "status": st})
	_squad_hint = Label.new()
	_squad_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_squad_hint.size = Vector2(560, 36)
	_squad_hint.add_theme_font_size_override("font_size", 20)
	_squad_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_squad_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_squad_hint)
	_downed_overlay = ColorRect.new()
	_downed_overlay.color = Color(0.45, 0.02, 0.02, 0.35)
	_downed_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_downed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_overlay.visible = false
	add_child(_downed_overlay)
	_downed_label = Label.new()
	_downed_label.text = "YOU ARE DOWN"
	_downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_label.size = Vector2(560, 44)
	_downed_label.add_theme_font_size_override("font_size", 34)
	_downed_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_downed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_overlay.add_child(_downed_label)
	_downed_timer = Label.new()
	_downed_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_timer.size = Vector2(560, 30)
	_downed_timer.add_theme_font_size_override("font_size", 22)
	_downed_timer.add_theme_color_override("font_color", Color(1, 1, 1))
	_downed_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_overlay.add_child(_downed_timer)
	_layout_squad_ui(get_viewport().get_visible_rect().size)
	_cz_hint = Label.new()
	_cz_hint.text = "DRAG buttons to move  ·  PINCH to resize"
	_cz_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cz_hint.size = Vector2(520, 40)
	_cz_hint.add_theme_font_size_override("font_size", 22)
	_cz_hint.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	_cz_hint.visible = false
	_cz_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cz_hint)
	_cz_done_btn = _make_button("", "DONE")
	_cz_done_btn.size = Vector2(200, 72)
	_cz_done_btn.visible = false
	_cz_done_btn.pressed.connect(_on_cz_done)
	_cz_reset_btn = _make_button("", "RESET")
	_cz_reset_btn.size = Vector2(200, 72)
	_cz_reset_btn.visible = false
	_cz_reset_btn.pressed.connect(_on_cz_reset)
	_layout_static()
	# --- Desktop hint. ---
	_hint_label = Label.new()
	_hint_label.text = "WASD move · Mouse aim · LMB fire · RMB ADS · R reload · 1/2/3/Q swap · Space jump · Shift sprint · C crouch/slide · Z prone · G grenade (hold to cook)"
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_hint_label.visible = not is_mobile
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)


func _build_touch_buttons() -> void:
	# Builds (or rebuilds) the CODM touch cluster. Called from _build on
	# mobile, and directly by tests after forcing is_mobile.
	for id in _touch_buttons:
		(_touch_buttons[id] as HudIconButton).queue_free()
	_touch_buttons.clear()
	_add_touch_button("fire", _on_fire_down, _on_fire_up)
	_add_touch_button("ads", _on_ads_pressed)
	_add_touch_button("jump", _on_jump_down, _on_jump_up)
	_add_touch_button("crouch", _on_crch_down, _on_crch_up)
	_add_touch_button("prone", _on_prn_pressed)
	_add_touch_button("grenade", _on_grn_down, _on_grn_up)
	_add_touch_button("inspect", _on_inspect_down, _on_inspect_up)
	_add_touch_button("emote", _on_emote_pressed)
	_add_touch_button("sprint", _on_sprint_pressed)
	_add_touch_button("reload", _on_reload_pressed)
	_add_touch_button("swap", _on_swap_pressed)
	_add_touch_button("armor", _on_armor_pressed)
	_add_touch_button("streak", _on_streak_pressed)
	_add_touch_button("gfx", _on_gfx_pressed)
	_add_touch_button("gear", _on_gear_pressed)
	_add_touch_button("ping", _on_ping_pressed)
	_add_touch_button("smoke", _on_smoke_pressed)
	_joy.visible = true


func _add_touch_button(id: String, on_press: Callable, on_release: Callable = Callable()) -> void:
	var e: Dictionary = LAYOUT[id]
	var b := _make_button(str(e["icon"]), str(e["label"]))
	var kind := str(e["kind"])
	if kind == "hold":
		b.button_down.connect(on_press)
		if on_release.is_valid():
			b.button_up.connect(on_release)
	else:
		b.pressed.connect(on_press)
	_touch_buttons[id] = b


func _make_vig(size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.9, 0.05, 0.05, 0.0)
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


# ---------------- customize mode ----------------

func set_customize(b: bool) -> void:
	_customize = b
	_cz_touch.clear()
	_cz_grab.clear()
	_cz_pinch.clear()
	_cz_hint.visible = b
	_cz_done_btn.visible = b
	_cz_reset_btn.visible = b
	if not b:
		ControlSettings.save_all()


func is_customizing() -> bool:
	return _customize


func _on_cz_done() -> void:
	set_customize(false)


func _on_cz_reset() -> void:
	ControlSettings.clear_layout()
	ControlSettings.save_all()
	_apply_layout()


func _cz_button_at(p: Vector2) -> String:
	# Topmost button whose rect contains p (reverse insertion order).
	var ids := _touch_buttons.keys()
	for i in range(ids.size() - 1, -1, -1):
		var b: HudIconButton = _touch_buttons[ids[i]]
		if b.get_global_rect().has_point(p):
			return str(ids[i])
	return ""


func _cz_handle_press(idx: int, p: Vector2) -> void:
	var id := _cz_button_at(p)
	if id == "":
		return
	# Pinch: a second finger landing on the same button starts resize.
	for other in _cz_touch:
		if int(other) != idx and str(_cz_touch[other]) == id:
			var b: HudIconButton = _touch_buttons[id]
			var c := b.get_global_rect().get_center()
			_cz_pinch[id] = (p - c).length() * 2.0
			_cz_touch[idx] = id
			_cz_grab[idx] = p - c
			return
	_cz_touch[idx] = id
	var b2: HudIconButton = _touch_buttons[id]
	_cz_grab[idx] = p - b2.get_global_rect().get_center()


func _cz_handle_drag(idx: int, p: Vector2) -> void:
	if not _cz_touch.has(idx):
		return
	var id := str(_cz_touch[idx])
	var b: HudIconButton = _touch_buttons[id]
	if _cz_pinch.has(id):
		# Pinch resize.
		var c := b.get_global_rect().get_center()
		var dist := (p - c).length() * 2.0
		var last := float(_cz_pinch[id])
		if last > 1.0 and dist > 1.0:
			var vp := get_viewport().get_visible_rect().size
			var d := clampf((b.size.x / vp.y) * (dist / last), 0.04, 0.28)
			var r := b.get_global_rect()
			var nc := r.get_center()
			var nd := d * vp.y
			b.position = nc - Vector2(nd, nd) * 0.5
			b.size = Vector2(nd, nd)
			b.add_theme_font_size_override("font_size", int(nd * 0.20))
		_cz_pinch[id] = dist
	else:
		# Move: keep the finger's grab offset so the button tracks 1:1.
		var grab: Vector2 = _cz_grab[idx]
		var vp2 := get_viewport().get_visible_rect().size
		var half := b.size * 0.5
		var nc2 := p - grab
		nc2.x = clampf(nc2.x, half.x, vp2.x - half.x)
		nc2.y = clampf(nc2.y, half.y, vp2.y - half.y)
		b.position = nc2 - half


func _cz_handle_release(idx: int) -> void:
	if _cz_touch.has(idx):
		var id := str(_cz_touch[idx])
		var b: HudIconButton = _touch_buttons[id]
		var vp := get_viewport().get_visible_rect().size
		var c := b.get_global_rect().get_center()
		ControlSettings.set_layout(id, Vector2(c.x / vp.x, c.y / vp.y), b.size.x / vp.y)
		_cz_touch.erase(idx)
		_cz_grab.erase(idx)
		# If no more touches on this button, end pinch tracking.
		var still := false
		for other in _cz_touch:
			if str(_cz_touch[other]) == id:
				still = true
		if not still and _cz_pinch.has(id):
			_cz_pinch.erase(id)
			ControlSettings.save_all()


# ---------------- button actions ----------------

func _guard() -> bool:
	return _customize  # in customize mode, buttons don't fire actions


func _on_gfx_pressed() -> void:
	if _guard():
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("cycle_quality"):
		scene.cycle_quality()


func _on_gear_pressed() -> void:
	if _guard():
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("open_settings"):
		scene.open_settings()


func _on_fire_down() -> void:
	if _guard():
		return
	if player:
		player.set_touch_firing(true)


func _on_fire_up() -> void:
	if player:
		player.set_touch_firing(false)


func _on_ads_pressed() -> void:
	if _guard():
		return
	if player:
		player.set_ads(not player.ads)


func _on_jump_down() -> void:
	if _guard():
		return
	if player:
		player.touch_up_held = true
		player.try_jump()


func _on_jump_up() -> void:
	if player:
		player.touch_up_held = false


func _on_jump_pressed() -> void:
	# Kept for API compatibility (tests / external callers).
	_on_jump_down()
	_on_jump_up()


func _on_reload_pressed() -> void:
	if _guard():
		return
	if player:
		player.start_reload()


func _on_swap_pressed() -> void:
	if _guard():
		return
	if player:
		player.cycle_weapon()


func _on_grn_down() -> void:
	if _guard():
		return
	if player:
		player.start_grenade_cook()


func _on_grn_up() -> void:
	if player:
		player.release_grenade()


func _on_ping_pressed() -> void:
	if _guard():
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("try_ping"):
		scene.try_ping()


func _on_smoke_pressed() -> void:
	if _guard():
		return
	if player:
		player.throw_smoke()


func set_smoke_count(n: int) -> void:
	if _touch_buttons.has("smoke"):
		(_touch_buttons["smoke"] as HudIconButton).set_caption("SMK %d" % n)


func _on_crch_down() -> void:
	if _guard():
		return
	if player:
		player.touch_down_held = true
		player.crouch_hold_down()


func _on_crch_up() -> void:
	if _guard():
		return
	if player:
		player.touch_down_held = false
		player.crouch_hold_up()


func _on_inspect_down() -> void:
	if _guard():
		return
	if player:
		player.start_inspect()


func _on_inspect_up() -> void:
	if player:
		player.stop_inspect()


func _on_emote_pressed() -> void:
	if _guard():
		return
	if player:
		player.toggle_emote_wheel()


func _on_prn_pressed() -> void:
	if _guard():
		return
	if player:
		player.toggle_prone()


func _on_armor_pressed() -> void:
	if _guard():
		return
	if player and player.has_method("apply_armor_plate"):
		player.apply_armor_plate()


func _on_streak_pressed() -> void:
	if _guard():
		return
	_toast("NO SCORESTREAK EQUIPPED")


func _on_sprint_pressed() -> void:
	if _guard():
		return
	if player:
		player.toggle_mobile_sprint()
		_sprint_on = player._mobile_sprint
		(_touch_buttons["sprint"] as HudIconButton).modulate = Color(1.0, 0.65, 0.2, ControlSettings.hud_opacity) if _sprint_on else Color(1, 1, 1, ControlSettings.hud_opacity)


func _toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	var tw := _toast_label.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


func set_grenade_count(n: int) -> void:
	if _touch_buttons.has("grenade"):
		(_touch_buttons["grenade"] as HudIconButton).set_caption("GRN %d" % n)


func set_armor_plates(n: int) -> void:
	if _touch_buttons.has("armor"):
		(_touch_buttons["armor"] as HudIconButton).set_caption("ARMOR %d" % n)


func set_gfx_label(t: String) -> void:
	if _touch_buttons.has("gfx"):
		(_touch_buttons["gfx"] as HudIconButton).set_caption(t)


## Radial cooldown sweep on a touch button (grenade throw, armor apply, ...).
func start_cooldown(id: String, sec: float) -> void:
	if _touch_buttons.has(id):
		(_touch_buttons[id] as HudIconButton).set_cooldown(sec)


# ---------------- input ----------------

func _input(event: InputEvent) -> void:
	if not is_mobile:
		return
	var vp := get_viewport().get_visible_rect().size
	if _customize:
		if event is InputEventScreenTouch:
			if event.pressed:
				_cz_handle_press(event.index, event.position)
			else:
				_cz_handle_release(event.index)
		elif event is InputEventScreenDrag:
			_cz_handle_drag(event.index, event.position)
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			_touch_start[event.index] = p
			if _joy_idx == -1 and _joy_zone(vp).has_point(p):
				_joy_idx = event.index
				_joy_origin = p
				_joy_vec = Vector2.ZERO
				_joy.queue_redraw()
			# Minimap tap tracking.
			if _mmap_rect(vp).has_point(p):
				_mmap_tap[event.index] = {"pos": p, "t": Time.get_ticks_msec() / 1000.0}
		else:
			_touch_start.erase(event.index)
			if event.index == _joy_idx:
				_joy_idx = -1
				_joy_vec = Vector2.ZERO
				if player:
					player.set_joystick(Vector2.ZERO)
				_joy.queue_redraw()
			# Minimap tap: quick tap toggles expanded view.
			if _mmap_tap.has(event.index):
				var rec: Dictionary = _mmap_tap[event.index]
				var dt: float = Time.get_ticks_msec() / 1000.0 - float(rec["t"])
				var dp: Vector2 = p - (rec["pos"] as Vector2)
				_mmap_tap.erase(event.index)
				if dt < 0.35 and dp.length() < 24.0:
					_mmap_big = not _mmap_big
					_apply_layout()
	elif event is InputEventScreenDrag:
		if event.index == _joy_idx:
			var d: Vector2 = event.position - _joy_origin
			_joy_vec = d.limit_length(JOY_RADIUS) / JOY_RADIUS
			if player:
				player.set_joystick(_joy_vec)
			_joy.queue_redraw()


func consume_look_drag(event: InputEventScreenDrag) -> bool:
	# Called by the player for right-side look drags. Reject drags that
	# started on a HUD button, the joystick, or the minimap.
	if _customize:
		return false
	var start: Vector2 = _touch_start.get(event.index, event.position)
	var vp := get_viewport().get_visible_rect().size
	if _mmap_rect(vp).grow(4).has_point(start):
		return false
	for id in _touch_buttons:
		var b: HudIconButton = _touch_buttons[id]
		if b.get_global_rect().grow(8).has_point(start):
			return false
	if event.index == _joy_idx:
		return false
	return true


func is_on_fire_button(p: Vector2) -> bool:
	for id in _touch_buttons:
		var b: HudIconButton = _touch_buttons[id]
		if b.get_global_rect().grow(8).has_point(p):
			return true
	var vp := get_viewport().get_visible_rect().size
	return _mmap_rect(vp).has_point(p)


# ---------------- per-frame ----------------

func _process(delta: float) -> void:
	_spread = maxf(_spread - delta * 3.0, 0.0)
	if _spread > 0.0:
		_cross.queue_redraw()
	if _hitmark_timer > 0.0:
		_hitmark_timer -= delta
		if _hitmark_timer <= 0.0:
			_hitm.queue_redraw()
	if _vig_timer > 0.0:
		_vig_timer -= delta
		var a := clampf(_vig_timer / 0.7, 0.0, 1.0) * 0.55
		_set_vig_alpha(a)
		if _vig_timer <= 0.0:
			_set_vig_alpha(0.0)
	_mm_timer -= delta
	if _mm_timer <= 0.0:
		_mm_timer = 0.2
		_mmap.queue_redraw()
	_squad_t -= delta
	if _squad_t <= 0.0:
		_squad_t = 0.25
		update_squad_plates()
	if _armor_break_t > 0.0:
		_armor_break_t -= delta
		_bars.queue_redraw()  # armor bar flashes while timer runs
	if _exec_banner_t > 0.0:
		_exec_banner_t -= delta
	# Vehicles: refresh gauges, tick UAV reveal.
	if _uav_t > 0.0:
		_uav_t -= delta
	if _veh_ref != null:
		if is_instance_valid(_veh_ref):
			_veh_paint.queue_redraw()
		else:
			_veh_ref = null
			hide_vehicle()


func notify_fired() -> void:
	_spread = minf(_spread + 0.35, 1.0)
	_cross.queue_redraw()


func _set_vig_alpha(a: float) -> void:
	for r in [_vig_top, _vig_bottom, _vig_left, _vig_right]:
		var c: Color = r.color
		c.a = a if r == _vig_which else 0.0
		r.color = c


# ---------------- painters ----------------

func _draw_crosshair(c: Control) -> void:
	var ctr := c.size * 0.5
	var gap := 7.0 + _spread * 16.0
	var ln := 9.0
	var col := Color(1, 1, 1, 0.9)
	var w := 2.0
	c.draw_line(ctr + Vector2(-gap - ln, 0), ctr + Vector2(-gap, 0), col, w)
	c.draw_line(ctr + Vector2(gap, 0), ctr + Vector2(gap + ln, 0), col, w)
	c.draw_line(ctr + Vector2(0, -gap - ln), ctr + Vector2(0, -gap), col, w)
	c.draw_line(ctr + Vector2(0, gap), ctr + Vector2(0, gap + ln), col, w)
	c.draw_circle(ctr, 1.6, col)


func _draw_hitmarker(c: Control) -> void:
	if _hitmark_timer <= 0.0:
		return
	var ctr := c.size * 0.5
	var s := 14.0
	var col := Color(1, 0.15, 0.1, 0.95) if _hitmark_kill else Color(1, 1, 1, 0.95)
	var w := 3.0
	c.draw_line(ctr + Vector2(-s, -s), ctr + Vector2(-s + 7, -s + 7), col, w)
	c.draw_line(ctr + Vector2(s, -s), ctr + Vector2(s - 7, -s + 7), col, w)
	c.draw_line(ctr + Vector2(-s, s), ctr + Vector2(-s + 7, s - 7), col, w)
	c.draw_line(ctr + Vector2(s, s), ctr + Vector2(s - 7, s - 7), col, w)


func _draw_minimap(c: Control) -> void:
	var r := c.size.x * 0.5
	var ctr := c.size * 0.5
	c.draw_circle(ctr, r, Color(0.02, 0.04, 0.06, 0.72))
	c.draw_arc(ctr, r - 2.0, 0.0, TAU, 64, Color(1, 1, 1, 0.55), 2.0)
	if player == null:
		return
	var view_range := 60.0
	if world_mode:
		view_range = world_extent * 2.7  # whole world fits in the circle
	var sc := (r - 8.0) / view_range
	# Zone rings (white): current solid, next faint.
	_draw_ring(c, ctr, sc, zone_center, zone_radius, Color(1, 1, 1, 0.9), 2.5)
	_draw_ring(c, ctr, sc, next_center, next_radius, Color(1, 1, 1, 0.4), 1.5)
	if world_mode:
		# Region labels across the world.
		var font := ThemeDB.fallback_font
		for l in map_labels:
			var lp: Vector3 = l["pos"]
			var rel := (Vector2(lp.x, lp.z) - Vector2(player.global_position.x, player.global_position.z)) * sc
			if rel.length() < r - 14.0:
				c.draw_circle(ctr + rel, 3.0, Color(1.0, 0.8, 0.3, 0.9))
				c.draw_string(font, ctr + rel + Vector2(6, -4), str(l["name"]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))
	# Enemies as red dots (nearby always; all while UAV is active).
	var uav := _uav_t > 0.0
	for e in enemies:
		if e != null and is_instance_valid(e) and e.is_alive():
			var ed := Vector2(e.global_position.x - player.global_position.x,
				e.global_position.z - player.global_position.z).length()
			if not uav and ed > 25.0:
				continue
			var rel := Vector2(e.global_position.x - player.global_position.x,
				e.global_position.z - player.global_position.z) * sc
			if rel.length() < r - 8.0:
				c.draw_circle(ctr + rel, 4.0, Color(1.0, 0.2, 0.15, 0.95))
	# Squadmates: green dots with a white ring when downed.
	for sa in allies:
		if sa != null and is_instance_valid(sa) and sa.is_alive():
			var srel := Vector2(sa.global_position.x - player.global_position.x,
				sa.global_position.z - player.global_position.z) * sc
			if srel.length() < r - 8.0:
				c.draw_circle(ctr + srel, 4.0, Color(0.3, 1.0, 0.4, 0.95))
				if sa.is_downed():
					c.draw_arc(ctr + srel, 6.5, 0.0, TAU, 24, Color(1.0, 0.3, 0.25, 0.95), 2.0)
	# Buy stations: green $ markers.
	var font2 := ThemeDB.fallback_font
	for sp in minimap_shops:
		var sv: Vector3 = sp
		var srel := (Vector2(sv.x, sv.z) - Vector2(player.global_position.x, player.global_position.z)) * sc
		if srel.length() < r - 8.0:
			c.draw_circle(ctr + srel, 6.0, Color(0.1, 0.5, 0.2, 0.9))
			c.draw_string(font2, ctr + srel + Vector2(-5, 5), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 1.0, 0.5))
	# Filling stations: orange F markers.
	for fp in minimap_fuel:
		var fv: Vector3 = fp
		var frel := (Vector2(fv.x, fv.z) - Vector2(player.global_position.x, player.global_position.z)) * sc
		if frel.length() < r - 8.0:
			c.draw_circle(ctr + frel, 6.0, Color(0.7, 0.35, 0.05, 0.9))
			c.draw_string(font2, ctr + frel + Vector2(-5, 5), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.7, 0.3))
	# Airdrops: orange crate markers.
	for dp in minimap_drops:
		var dv: Vector3 = dp
		var drel := (Vector2(dv.x, dv.z) - Vector2(player.global_position.x, player.global_position.z)) * sc
		if drel.length() < r - 8.0:
			c.draw_rect(Rect2(ctr + drel - Vector2(5, 5), Vector2(10, 10)), Color(1.0, 0.55, 0.1, 0.95))
	# Vehicles: white dots.
	for vv in minimap_vehicles:
		if vv != null and is_instance_valid(vv) and not bool(vv.get("destroyed")):
			var vrel := (Vector2(vv.global_position.x, vv.global_position.z) - Vector2(player.global_position.x, player.global_position.z)) * sc
			if vrel.length() < r - 8.0:
				c.draw_circle(ctr + vrel, 3.0, Color(1, 1, 1, 0.8))
	# Loot pings: tier-colored diamonds.
	for pg in minimap_pings:
		var pd: Dictionary = pg
		var pp: Vector3 = pd["pos"]
		var prel := (Vector2(pp.x, pp.z) - Vector2(player.global_position.x, player.global_position.z)) * sc
		if prel.length() < r - 8.0:
			var pc: Color = LootModels.tier_color(int(pd.get("tier", 0)))
			var q := ctr + prel
			c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -7), q + Vector2(5, 0), q + Vector2(0, 7), q + Vector2(-5, 0)]), pc)
	# Player arrow, north-up.
	var pts := PackedVector2Array([Vector2(0, -10), Vector2(7, 8), Vector2(-7, 8)])
	var xf := Transform2D(-player.yaw, ctr)
	c.draw_colored_polygon(xf * pts, Color(0.35, 1.0, 0.45))


func _draw_ring(c: Control, ctr: Vector2, sc: float, center: Vector2, radius: float, col: Color, w: float) -> void:
	if player == null:
		return
	var rel := (center - Vector2(player.global_position.x, player.global_position.z)) * sc
	var rr := radius * sc
	var r := c.size.x * 0.5
	if rr < r * 2.5:
		c.draw_arc(ctr + rel, rr, 0.0, TAU, 64, col, w)


func _draw_bars(c: Control) -> void:
	var w := c.size.x
	# Armor pips above (3 x 50); flash red while armor-break timer runs.
	var pip_w := (w - 16.0) / 3.0
	var breaking := _armor_break_t > 0.0 and int(_armor_break_t * 10.0) % 2 == 0
	for i in range(3):
		var filled: bool = player != null and player.armor > i * 50
		var col := Color(0.25, 0.55, 1.0, 0.95) if filled else Color(0.1, 0.12, 0.16, 0.7)
		if breaking:
			col = Color(1.0, 0.2, 0.15, 0.95)
		c.draw_rect(Rect2(8 + i * pip_w, 0, pip_w - 4, 10), col)
	# Health bar (white).
	c.draw_rect(Rect2(0, 16, w, 20), Color(0.05, 0.06, 0.08, 0.75))
	if player != null:
		var f := float(player.hp) / float(player.max_hp)
		var hcol := Color(1, 1, 1, 0.95) if f > 0.3 else Color(1, 0.25, 0.2, 0.95)
		c.draw_rect(Rect2(2, 18, (w - 4) * f, 16), hcol)


func _draw_joystick(c: Control) -> void:
	if _joy_idx != -1:
		c.draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		c.draw_arc(_joy_origin, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		c.draw_circle(_joy_origin + _joy_vec * 62.0, 34.0, Color(1, 1, 1, 0.4))
	else:
		var vp := get_viewport().get_visible_rect().size
		var dflt := Vector2(vp.x * 0.14, vp.y * 0.72)
		c.draw_arc(dflt, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.22), 3.0)


# ---------------- public API (called by player/main) ----------------

func set_ads_state(b: bool) -> void:
	if _touch_buttons.has("ads"):
		(_touch_buttons["ads"] as HudIconButton).modulate = Color(1.0, 0.65, 0.2, ControlSettings.hud_opacity) if b else Color(1, 1, 1, ControlSettings.hud_opacity)


func show_reloading(b: bool) -> void:
	_reload_hint.visible = b


func update_ammo(mag: int, reserve: int) -> void:
	_ammo_label.text = "%d | %d" % [mag, reserve]


func update_weapon(wname: String) -> void:
	_wname_label.text = wname.to_upper()


func update_weapon_stk(text: String) -> void:
	_stk_label.text = text


## Armor plates shattered: flash the armor bar + toast.
func show_armor_break() -> void:
	_armor_break_t = 1.2
	add_killfeed("ARMOR BROKEN")


## Stealth execution banner.
func show_execution() -> void:
	_exec_banner_t = 1.6
	_toast("EXECUTION")


## Weapon inspect indicator.
func show_inspecting(b: bool) -> void:
	if _inspect_label == null:
		_inspect_label = Label.new()
		_inspect_label.text = "INSPECTING…"
		_inspect_label.add_theme_font_size_override("font_size", 18)
		_inspect_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_inspect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_inspect_label)
		_layout_static()
	_inspect_label.visible = b


## Emote wheel: 6 buttons in a row above the touch cluster.
func show_emote_wheel(open: bool) -> void:
	if _emote_panel == null:
		_emote_panel = Control.new()
		_emote_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_emote_panel)
		var names := ["WAVE", "POINT", "TAUNT", "NOD", "SHRUG", "SALUTE"]
		for i in range(names.size()):
			var b := Button.new()
			b.text = str(names[i])
			b.custom_minimum_size = Vector2(110, 44)
			b.pressed.connect(_on_emote_chosen.bind(i))
			_emote_panel.add_child(b)
			_emote_buttons.append(b)
		_layout_static()
	_emote_panel.visible = open


func _on_emote_chosen(i: int) -> void:
	if player:
		player.play_emote(i)


func update_health(hp: int, max_hp: int, armor: int) -> void:
	_bars.queue_redraw()


func update_score(s: int, alive: int) -> void:
	_score_label.text = "SCORE %d   ·   HOSTILES %d" % [s, alive]


func update_zone_text(t: String) -> void:
	_zone_label.text = t


func update_match_time(t: float) -> void:
	if _match_label:
		_match_label.text = "%02d:%02d" % [int(t) / 60, int(t) % 60]


func show_end_banner(text: String) -> void:
	if _end_banner:
		_end_banner.text = text
		_end_banner.visible = true


func show_hitmarker(kill: bool) -> void:
	_hitmark_kill = kill
	_hitmark_timer = 0.3
	_hitm.queue_redraw()
	if is_mobile and ControlSettings.haptics:
		_vibrate_handheld_hud(40 if kill else 22)


func _vibrate_handheld_hud(ms: int) -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		Input.vibrate_handheld(ms)


func show_damage_from(from_pos: Vector3) -> void:
	if player == null:
		return
	var to: Vector3 = (from_pos - player.global_position)
	var ang := atan2(-to.x, -to.z)  # world bearing of attacker
	var rel := wrapf(ang - player.yaw, -PI, PI)
	# rel 0 = ahead, +PI/2 = left? Determine: yaw=0 faces -Z. Attacker ahead => to=(0,0,-d) => ang=atan2(0, d)=0, rel=0 => top.
	var rects := [_vig_top, _vig_right, _vig_bottom, _vig_left]
	# Map rel in [-PI, PI] to 4 sectors: top(-PI/4..PI/4), right, bottom, left.
	var idx := int(floor((rel + PI / 4.0) / (PI / 2.0))) % 4
	_vig_which = rects[idx]
	_vig_timer = 0.7
	_set_vig_alpha(0.55)


# ---------------- squad UI (teammate plates, hints, downed overlay) ----------------

func _layout_squad_ui(vp: Vector2) -> void:
	if _squad_hint != null:
		_squad_hint.position = Vector2(vp.x * 0.5 - 280, vp.y - 220)
	if _downed_label != null:
		_downed_label.position = Vector2(vp.x * 0.5 - 280, vp.y * 0.38)
	if _downed_timer != null:
		_downed_timer.position = Vector2(vp.x * 0.5 - 280, vp.y * 0.38 + 46)


## Contextual squad hint (revive progress, dog-tag prompts). Empty = hide.
func show_hint(text: String) -> void:
	if _squad_hint == null:
		return
	_squad_hint.text = text
	_squad_hint.visible = text != ""


func show_downed(on: bool) -> void:
	if _downed_overlay != null:
		_downed_overlay.visible = on


func update_downed(secs: float) -> void:
	if _downed_timer != null:
		_downed_timer.text = "BLEEDING OUT — %.0fs" % maxf(secs, 0.0)


## Teammate plates: name, health bar, distance, status. Throttled by caller.
func update_squad_plates() -> void:
	if _squad_panel == null or player == null:
		return
	_squad_panel.visible = not allies.is_empty()
	for i in range(_squad_rows.size()):
		var row: Dictionary = _squad_rows[i]
		if i >= allies.size():
			(row["plate"] as Control).visible = false
			continue
		var a = allies[i]
		if a == null or not is_instance_valid(a):
			(row["plate"] as Control).visible = false
			continue
		(row["plate"] as Control).visible = true
		(row["name"] as Label).text = str(a.get("bot_name"))
		var bar := row["bar"] as ProgressBar
		bar.value = float(a.get("hp"))
		var st := row["status"] as Label
		if not a.is_alive():
			st.text = "OUT"
			st.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		elif a.is_downed():
			st.text = "DOWN"
			st.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
		else:
			var d: float = player.global_position.distance_to(a.global_position)
			st.text = "%dm" % int(d)
			st.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		# Low-health plate flash.
		var style := (row["plate"] as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		if float(a.get("hp")) < 35.0 and a.is_alive():
			style.bg_color = Color(0.5, 0.08, 0.08, 0.55)
		else:
			style.bg_color = Color(0.0, 0.0, 0.0, 0.45)


func add_killfeed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_killfeed.add_child(l)
	_killfeed_count += 1
	while _killfeed_count > 4:
		var oldest := _killfeed.get_child(0)
		_killfeed.remove_child(oldest)
		oldest.queue_free()
		_killfeed_count -= 1
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
	_killfeed_count -= 1


# ================= vehicles + economy (NOVA WORLD fleet) =================
var _cash_label: Label = null
var _veh_paint: Paint = null       # driving gauges (speedo / rpm / nitro / hull)
var _veh_ref = null                # NovaVehicle being driven
var _prompt_label: Label = null
var _act_btn: HudIconButton = null # contextual ACT button (touch)
var _shop_panel: PanelContainer = null
var _shop_cash: Label = null
var _shop_redeploy_btn: Button = null
var shop_callback := Callable()    # main.gd: func(shop_item_id)
var _uav_t := 0.0
var minimap_shops: Array = []      # Vector3 world positions
var minimap_drops: Array = []      # Vector3 world positions
var minimap_vehicles: Array = []   # NovaVehicle refs
var minimap_fuel: Array = []       # Vector3 world positions of filling stations
var minimap_pings: Array = []      # {pos: Vector3, tier: int} loot pings
var _drive_btns := {}

const DRIVE_LAYOUT := {
	"gas":    {"label": "GAS",  "pos": Vector2(0.885, 0.600), "d": 0.130},
	"brake":  {"label": "BRK",  "pos": Vector2(0.735, 0.700), "d": 0.130},
	"hbrake": {"label": "HBRK", "pos": Vector2(0.600, 0.790), "d": 0.100},
	"nitro":  {"label": "N2O",  "pos": Vector2(0.885, 0.425), "d": 0.100},
	"horn":   {"label": "HORN", "pos": Vector2(0.115, 0.560), "d": 0.095},
	"vexit":  {"label": "EXIT", "pos": Vector2(0.060, 0.300), "d": 0.095},
	"vcam":   {"label": "CAM",  "pos": Vector2(0.060, 0.425), "d": 0.095},
	"lights": {"label": "LAMP", "pos": Vector2(0.165, 0.425), "d": 0.095},
	"fuel":   {"label": "FUEL", "pos": Vector2(0.770, 0.520), "d": 0.100},
}


func _veh_ensure() -> void:
	if _cash_label != null:
		return
	_cash_label = Label.new()
	_cash_label.text = "$0"
	_cash_label.add_theme_font_size_override("font_size", 24)
	_cash_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
	_cash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cash_label)
	_veh_paint = Paint.new()
	_veh_paint.fn = _draw_drive
	_veh_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veh_paint.visible = false
	add_child(_veh_paint)
	_prompt_label = Label.new()
	_prompt_label.text = ""
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 24)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.visible = false
	add_child(_prompt_label)
	_act_btn = HudIconButton.new("", "ACT")
	_act_btn.visible = false
	_act_btn.pressed.connect(_on_act_pressed)
	add_child(_act_btn)
	_build_drive_buttons()
	_veh_layout()


func _build_drive_buttons() -> void:
	for id in DRIVE_LAYOUT:
		var e: Dictionary = DRIVE_LAYOUT[id]
		var b := HudIconButton.new("", str(e["label"]))
		b.visible = false
		add_child(b)
		_drive_btns[id] = b
	(_drive_btns["gas"] as HudIconButton).button_down.connect(_on_gas_down)
	(_drive_btns["gas"] as HudIconButton).button_up.connect(_on_gas_up)
	(_drive_btns["brake"] as HudIconButton).button_down.connect(_on_brake_down)
	(_drive_btns["brake"] as HudIconButton).button_up.connect(_on_brake_up)
	(_drive_btns["hbrake"] as HudIconButton).button_down.connect(_on_hbrake_down)
	(_drive_btns["hbrake"] as HudIconButton).button_up.connect(_on_hbrake_up)
	(_drive_btns["nitro"] as HudIconButton).button_down.connect(_on_nitro_down)
	(_drive_btns["nitro"] as HudIconButton).button_up.connect(_on_nitro_up)
	(_drive_btns["horn"] as HudIconButton).pressed.connect(_on_horn_pressed)
	(_drive_btns["vexit"] as HudIconButton).pressed.connect(_on_vexit_pressed)
	(_drive_btns["vcam"] as HudIconButton).pressed.connect(_on_vcam_pressed)
	(_drive_btns["lights"] as HudIconButton).pressed.connect(_on_lights_pressed)
	(_drive_btns["fuel"] as HudIconButton).button_down.connect(_on_fuel_down)
	(_drive_btns["fuel"] as HudIconButton).button_up.connect(_on_fuel_up)


func _veh_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if _cash_label != null:
		_cash_label.position = Vector2(16, 84)
	if _prompt_label != null:
		_prompt_label.position = Vector2(vp.x * 0.5 - 260, vp.y * 0.42)
		_prompt_label.size = Vector2(520, 40)
	if _veh_paint != null:
		_veh_paint.position = Vector2(vp.x - 240, vp.y - 215)
		_veh_paint.size = Vector2(224, 175)
	if _act_btn != null:
		_act_btn.position = Vector2(vp.x * 0.5 - 60, vp.y * 0.52)
		_act_btn.size = Vector2(120, 64)
	for id in _drive_btns:
		var e: Dictionary = DRIVE_LAYOUT[id]
		var p: Vector2 = e["pos"]
		var d: float = float(e["d"]) * vp.y
		var b: HudIconButton = _drive_btns[id]
		b.position = Vector2(p.x * vp.x - d * 0.5, p.y * vp.y - d * 0.5)
		b.size = Vector2(d, d)


func update_cash(c: int) -> void:
	_veh_ensure()
	_cash_label.text = "$%d" % c


func show_vehicle(v) -> void:
	_veh_ensure()
	_veh_ref = v
	_veh_paint.visible = true
	if is_mobile:
		for id in _drive_btns:
			(_drive_btns[id] as HudIconButton).visible = true
		_veh_layout()


func hide_vehicle() -> void:
	_veh_ref = null
	if _veh_paint != null:
		_veh_paint.visible = false
	for id in _drive_btns:
		(_drive_btns[id] as HudIconButton).visible = false


func show_prompt(t: String) -> void:
	_veh_ensure()
	_prompt_label.text = t
	_prompt_label.visible = true
	if is_mobile:
		_act_btn.visible = true
		_act_btn.set_caption("ACT")


func hide_prompt() -> void:
	if _prompt_label != null:
		_prompt_label.visible = false
	if _act_btn != null:
		_act_btn.visible = false


func _on_act_pressed() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("interact_pressed"):
		scene.interact_pressed()


func _on_gas_down() -> void:
	if player:
		player.drive_gas = true


func _on_gas_up() -> void:
	if player:
		player.drive_gas = false


func _on_brake_down() -> void:
	if player:
		player.drive_brake = true


func _on_brake_up() -> void:
	if player:
		player.drive_brake = false


func _on_hbrake_down() -> void:
	if player:
		player.drive_hbrake = true


func _on_hbrake_up() -> void:
	if player:
		player.drive_hbrake = false


func _on_nitro_down() -> void:
	if player:
		player.drive_nitro = true


func _on_nitro_up() -> void:
	if player:
		player.drive_nitro = false


func _on_horn_pressed() -> void:
	if player and player.in_vehicle != null:
		player.in_vehicle.honk()


func _on_vexit_pressed() -> void:
	if player:
		player.exit_vehicle()


func _on_vcam_pressed() -> void:
	if player:
		player.veh_cam_mode = 1 - player.veh_cam_mode


func _on_lights_pressed() -> void:
	if player and player.in_vehicle != null:
		player.in_vehicle.toggle_lights()


func _on_fuel_down() -> void:
	# Tap = pour a carried can (unless at a pump: hold refuels there instead).
	if player:
		player.touch_fuel_held = true
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("try_fuel_action"):
			scene.try_fuel_action()


func _on_fuel_up() -> void:
	if player:
		player.touch_fuel_held = false


func reveal_uav(sec: float) -> void:
	_uav_t = sec


func _draw_drive(c: Control) -> void:
	if _veh_ref == null or not is_instance_valid(_veh_ref):
		return
	var v = _veh_ref
	var spd := int(absf(float(v.get("speed"))) * 3.6)
	var rpm01: float = clampf(absf(float(v.get("speed"))) / maxf(float(v.spec.get("top_speed", 20.0)), 1.0), 0.0, 1.0)
	var hp01: float = clampf(float(v.get("hp")) / maxf(float(v.get("max_hp")), 1.0), 0.0, 1.0)
	var n01: float = clampf(float(v.get("nitro")), 0.0, 100.0) / 100.0
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(8, 34), "%d km/h" % spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.95))
	# RPM bar (redline at the end).
	c.draw_rect(Rect2(8, 46, 208, 14), Color(0.1, 0.1, 0.12, 0.8))
	var rcol := Color(0.3, 0.9, 0.4) if rpm01 < 0.75 else Color(1.0, 0.25, 0.2)
	c.draw_rect(Rect2(10, 48, 204.0 * rpm01, 10), rcol)
	# Hull bar.
	c.draw_rect(Rect2(8, 66, 208, 14), Color(0.1, 0.1, 0.12, 0.8))
	c.draw_rect(Rect2(10, 68, 204.0 * hp01, 10), Color(0.35, 0.7, 1.0))
	# Nitro bar.
	c.draw_rect(Rect2(8, 86, 208, 14), Color(0.1, 0.1, 0.12, 0.8))
	c.draw_rect(Rect2(10, 88, 204.0 * n01, 10), Color(0.2, 0.6, 1.0))
	# Fuel bar (orange; hidden for fuel-free vehicles).
	var f01: float = float(v.call("fuel_frac"))
	if float(v.get("max_fuel")) > 0.0:
		c.draw_rect(Rect2(8, 106, 208, 14), Color(0.1, 0.1, 0.12, 0.8))
		var fcol := Color(1.0, 0.55, 0.1) if f01 > 0.25 else Color(1.0, 0.15, 0.1)
		c.draw_rect(Rect2(10, 108, 204.0 * f01, 10), fcol)
	c.draw_string(font, Vector2(8, 118), "HULL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	c.draw_string(font, Vector2(120, 118), "NITRO", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.75, 1.0, 0.8))
	if float(v.get("max_fuel")) > 0.0:
		c.draw_string(font, Vector2(8, 138), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.7, 0.3, 0.85))


# ---------------- buy-station shop UI ----------------
func open_shop() -> void:
	_veh_ensure()
	if _shop_panel != null:
		_shop_panel.visible = true
		_refresh_shop_cash()
		return
	_shop_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.96)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(0.3, 1.0, 0.45, 0.6)
	sb.set_border_width_all(2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_shop_panel.add_theme_stylebox_override("panel", sb)
	var vp := get_viewport().get_visible_rect().size
	_shop_panel.position = Vector2(vp.x * 0.5 - 230, vp.y * 0.5 - 260)
	_shop_panel.size = Vector2(460, 520)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_shop_panel.add_child(vb)
	var title := Label.new()
	title.text = "BUY STATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
	vb.add_child(title)
	_shop_cash = Label.new()
	_shop_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_cash.add_theme_font_size_override("font_size", 24)
	_shop_cash.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vb.add_child(_shop_cash)
	# Scrollable categorized catalog.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(424, 380)
	vb.add_child(scroll)
	var cat_vb := VBoxContainer.new()
	cat_vb.add_theme_constant_override("separation", 6)
	cat_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cat_vb)
	var last_cat := ""
	for it in BuyStation.items():
		var cat := str(it.get("cat", "MISC"))
		if cat != last_cat:
			last_cat = cat
			var hl := Label.new()
			hl.text = "— " + cat + " —"
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hl.add_theme_font_size_override("font_size", 16)
			hl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.55))
			cat_vb.add_child(hl)
		var b := Button.new()
		b.text = "%s — $%d\n%s" % [str(it["name"]), int(it["price"]), str(it["desc"])]
		b.custom_minimum_size = Vector2(400, 56)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_on_shop_buy.bind(str(it["id"])))
		if str(it["id"]) == "redeploy":
			_shop_redeploy_btn = b
		cat_vb.add_child(b)
	var cb := Button.new()
	cb.text = "CLOSE"
	cb.custom_minimum_size = Vector2(420, 48)
	cb.add_theme_font_size_override("font_size", 20)
	cb.pressed.connect(close_shop)
	vb.add_child(cb)
	add_child(_shop_panel)
	_refresh_shop_cash()


func _refresh_shop_cash() -> void:
	if _shop_cash != null and player != null:
		_shop_cash.text = "CASH: $%d" % player.cash
	if _shop_redeploy_btn != null and player != null:
		var tags: Array = player.get("carried_tags") if player.get("carried_tags") != null else []
		_shop_redeploy_btn.disabled = tags.is_empty()
		_shop_redeploy_btn.text = "Redeploy Teammate — $2000\n%s" % (
			"TAG: " + str(tags.back()) if not tags.is_empty() else "No dog tag carried")


func _on_shop_buy(item_id: String) -> void:
	if shop_callback.is_valid():
		shop_callback.call(item_id)
		_refresh_shop_cash()


func close_shop() -> void:
	if _shop_panel != null:
		_shop_panel.visible = false


func is_shop_open() -> bool:
	return _shop_panel != null and _shop_panel.visible
