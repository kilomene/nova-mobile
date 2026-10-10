class_name SettingsMenu
extends CanvasLayer
## CODM-style settings screen: dark military theme, orange/white accents,
## clean sectioned typography. Opened pre-match (map menu) or in-match
## (HUD gear button). All changes persist via ControlSettings.

const ACCENT := Color(1.0, 0.60, 0.12)
const BG := Color(0.03, 0.04, 0.06, 0.96)
const PANEL := Color(0.08, 0.10, 0.13, 1.0)
const TEXT_DIM := Color(0.75, 0.78, 0.82)

var hud = null  # HUD ref for customize-mode + opacity (null pre-match)
var _built := false


func open() -> void:
	if _built:
		queue_free()
		_built = false
	layer = 30
	_build()
	_built = true


func close() -> void:
	queue_free()
	_built = false


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.set_corner_radius_all(12)
	s.border_color = Color(1, 1, 1, 0.14)
	s.set_border_width_all(2)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 20
	s.content_margin_bottom = 20
	return s


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", ACCENT)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1.0, 0.60, 0.12, 0.35)
	r.custom_minimum_size = Vector2(0, 2)
	return r


func _slider_row(parent: VBoxContainer, label: String, key: String,
		minv: float, maxv: float, step: float, fmt: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", TEXT_DIM)
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = minv
	sl.max_value = maxv
	sl.step = step
	sl.value = float(ControlSettings.getv(key))
	sl.custom_minimum_size = Vector2(320, 36)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(4)
	sl.add_theme_stylebox_override("slider", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.16, 0.18, 0.22)
	track.set_corner_radius_all(4)
	sl.add_theme_stylebox_override("grabber_area", track)
	hb.add_child(sl)
	var v := Label.new()
	v.custom_minimum_size = Vector2(90, 0)
	v.add_theme_font_size_override("font_size", 19)
	v.add_theme_color_override("font_color", Color.WHITE)
	hb.add_child(v)
	var upd := func(val: float) -> void:
		ControlSettings.setv(key, val)
		ControlSettings.save_all()
		v.text = fmt % val
		if key == "hud_opacity" and hud != null and hud.has_method("apply_opacity"):
			hud.apply_opacity()
	sl.value_changed.connect(upd)
	upd.call(float(ControlSettings.getv(key)))


func _toggle_row(parent: VBoxContainer, label: String, key: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(110, 44)
	b.add_theme_font_size_override("font_size", 19)
	b.focus_mode = Control.FOCUS_NONE
	hb.add_child(b)
	var paint := func() -> void:
		var on := bool(ControlSettings.getv(key))
		b.text = "ON" if on else "OFF"
		b.add_theme_color_override("font_color", ACCENT if on else TEXT_DIM)
	b.pressed.connect(func() -> void:
		ControlSettings.setv(key, not bool(ControlSettings.getv(key)))
		ControlSettings.save_all()
		paint.call())
	paint.call()


func _action_row(parent: VBoxContainer, label: String, btn_text: String,
		cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var b := Button.new()
	b.text = btn_text
	b.custom_minimum_size = Vector2(260, 48)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", ACCENT)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	hb.add_child(b)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(760, 0)
	cc.add_child(panel)
	var margin := VBoxContainer.new()
	margin.add_theme_constant_override("separation", 8)
	panel.add_child(margin)
	# Title bar.
	var tb := HBoxContainer.new()
	margin.add_child(tb)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.custom_minimum_size = Vector2(56, 48)
	x.add_theme_font_size_override("font_size", 24)
	x.add_theme_color_override("font_color", ACCENT)
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(close)
	tb.add_child(x)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 560)
	margin.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	# --- Sensitivity ---
	vb.add_child(_header("SENSITIVITY"))
	vb.add_child(_rule())
	_slider_row(vb, "Camera", "cam_sens", 0.2, 3.0, 0.05, "%.2f")
	_slider_row(vb, "ADS", "ads_sens", 0.1, 2.0, 0.05, "%.2f")
	_slider_row(vb, "4x Scope", "zoom4_sens", 0.1, 1.5, 0.05, "%.2f")
	_slider_row(vb, "8x Scope", "zoom8_sens", 0.1, 1.5, 0.05, "%.2f")
	_toggle_row(vb, "Invert Y", "invert_y")
	# --- Gyroscope ---
	vb.add_child(_header("GYROSCOPE"))
	vb.add_child(_rule())
	_toggle_row(vb, "Gyro Aim", "gyro_enabled")
	_slider_row(vb, "Gyro Sensitivity", "gyro_sens", 0.2, 3.0, 0.05, "%.2f")
	# --- Aim assist ---
	vb.add_child(_header("AIM ASSIST"))
	vb.add_child(_rule())
	_toggle_row(vb, "Aim Assist", "aim_assist")
	_slider_row(vb, "Assist Strength", "assist_strength", 0.0, 1.0, 0.05, "%.2f")
	# --- Fire mode ---
	vb.add_child(_header("FIRE MODE"))
	vb.add_child(_rule())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var mode_btns: Array = []
	for m in ["advanced", "simple"]:
		var b := Button.new()
		b.text = m.to_upper()
		b.set_meta("mode", m)
		b.custom_minimum_size = Vector2(220, 52)
		b.add_theme_font_size_override("font_size", 20)
		b.focus_mode = Control.FOCUS_NONE
		hb.add_child(b)
		mode_btns.append(b)
		b.pressed.connect(_on_fire_mode.bind(m, mode_btns))
	_paint_fire_modes(mode_btns)
	# --- Feel ---
	vb.add_child(_header("FEEL"))
	vb.add_child(_rule())
	_toggle_row(vb, "Haptics", "haptics")
	_slider_row(vb, "HUD Opacity", "hud_opacity", 0.3, 1.0, 0.05, "%.2f")
	# --- HUD layout ---
	vb.add_child(_header("HUD LAYOUT"))
	vb.add_child(_rule())
	_action_row(vb, "Move / resize buttons", "CUSTOMIZE LAYOUT", _on_customize)
	_action_row(vb, "Restore CODM default", "RESET LAYOUT", func() -> void:
		ControlSettings.clear_layout()
		ControlSettings.save_all())
	# --- Graphics ---
	vb.add_child(_header("GRAPHICS"))
	vb.add_child(_rule())
	_action_row(vb, "Quality preset", "CYCLE QUALITY", _on_cycle_quality)


func _on_fire_mode(m: String, mode_btns: Array) -> void:
	ControlSettings.setv("fire_mode", m)
	ControlSettings.save_all()
	_paint_fire_modes(mode_btns)


func _paint_fire_modes(mode_btns: Array) -> void:
	for mb in mode_btns:
		var sel: bool = str((mb as Button).get_meta("mode")) == str(ControlSettings.getv("fire_mode"))
		(mb as Button).add_theme_color_override("font_color",
			ACCENT if sel else TEXT_DIM)


func _on_customize() -> void:
	if hud != null and hud.has_method("set_customize"):
		hud.set_customize(true)
		close()
	else:
		# Pre-match: no live HUD to customize.
		pass


func _on_cycle_quality() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("cycle_quality"):
		scene.cycle_quality()
