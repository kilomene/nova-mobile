class_name HudIconButton
extends BaseButton
## CODM-style touch button: rounded translucent dark panel, white vector icon,
## small-caps label, orange pressed state, radial cooldown sweep.
## All visuals are drawn procedurally (no image assets).

const ACCENT := Color(1.0, 0.60, 0.12)      # CODM orange
const PANEL := Color(0.02, 0.03, 0.05, 0.55)
const PANEL_PRESS := Color(1.0, 0.55, 0.10, 0.60)
const ICON_COL := Color(1, 1, 1, 0.92)

var icon := ""
var caption := ""
var active_tint := false  # e.g. ADS/sprint toggled on -> orange frame
var _cd := 0.0
var _cd_total := 1.0
var _sb: StyleBoxFlat
var _sb_press: StyleBoxFlat


func _init(p_icon := "", p_caption := "") -> void:
	icon = p_icon
	caption = p_caption
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sb = StyleBoxFlat.new()
	_sb.bg_color = PANEL
	_sb.set_corner_radius_all(14)
	_sb.border_color = Color(1, 1, 1, 0.22)
	_sb.set_border_width_all(2)
	_sb_press = StyleBoxFlat.new()
	_sb_press.bg_color = PANEL_PRESS
	_sb_press.set_corner_radius_all(14)
	_sb_press.border_color = Color(1, 1, 1, 0.45)
	_sb_press.set_border_width_all(2)


func set_cooldown(sec: float) -> void:
	_cd_total = maxf(sec, 0.01)
	_cd = sec
	set_process(true)
	queue_redraw()


func cooldown_left() -> float:
	return _cd


func set_caption(t: String) -> void:
	caption = t
	queue_redraw()


func _process(delta: float) -> void:
	if _cd > 0.0:
		_cd = maxf(_cd - delta, 0.0)
		queue_redraw()
	else:
		set_process(false)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_sb_press if is_pressed() else _sb, r)
	if active_tint:
		# Orange frame to show a toggled-on state (ADS / sprint).
		draw_arc(size * 0.5, minf(size.x, size.y) * 0.5 - 3.0, 0, TAU, 48,
			ACCENT, 3.0)
	if icon == "":
		# Text-only button (DONE / RESET): centered caption, CODM orange text.
		var font0 := ThemeDB.fallback_font
		var fs0 := int(minf(size.x, size.y) * 0.24)
		var tw0 := font0.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, fs0).x
		draw_string(font0, Vector2((size.x - tw0) * 0.5, size.y * 0.5 + fs0 * 0.35),
			caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, ACCENT)
	else:
		_draw_icon(size * 0.5, minf(size.x, size.y) * 0.30)
		if caption != "":
			var font := ThemeDB.fallback_font
			var fs := int(minf(size.x, size.y) * 0.16)
			var tw := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string(font, Vector2(size.x * 0.5 - tw * 0.5, size.y * 0.92),
				caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))
	if _cd > 0.0:
		# Cooldown sweep: dark veil + orange arc showing remaining fraction.
		var f := _cd / _cd_total
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, Color(0, 0, 0, 0.55))
		draw_arc(size * 0.5, minf(size.x, size.y) * 0.5 - 4.0,
			-PI * 0.5, -PI * 0.5 + TAU * f, 40, ACCENT, 5.0)


func _glyph_line(a: Vector2, b: Vector2, w: float) -> void:
	draw_line(a, b, ICON_COL, w, true)


func _draw_icon(c: Vector2, s: float) -> void:
	# s = icon radius-ish scale. All icons white vector glyphs.
	var w := maxf(2.0, s * 0.14)
	match icon:
		"fire":
			# Bullet: body + tip.
			var bw := s * 0.42
			draw_rect(Rect2(c.x - bw * 0.5, c.y - s * 0.35, bw, s * 0.9), ICON_COL)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-bw * 0.5, -s * 0.35), c + Vector2(bw * 0.5, -s * 0.35),
				c + Vector2(0, -s * 0.85)]), ICON_COL)
			draw_rect(Rect2(c.x - bw * 0.5, c.y + s * 0.55, bw, s * 0.18),
				Color(1, 1, 1, 0.45))
		"ads":
			# Scope: circle + cross.
			draw_arc(c, s * 0.62, 0, TAU, 32, ICON_COL, w)
			_glyph_line(c + Vector2(-s * 0.62, 0), c + Vector2(s * 0.62, 0), w * 0.7)
			_glyph_line(c + Vector2(0, -s * 0.62), c + Vector2(0, s * 0.62), w * 0.7)
			draw_circle(c, w * 0.8, ACCENT)
		"jump":
			# Double chevron up.
			for k in range(2):
				var y := c.y + s * 0.35 - k * s * 0.42
				_glyph_line(Vector2(c.x - s * 0.55, y), Vector2(c.x, y - s * 0.38), w)
				_glyph_line(Vector2(c.x + s * 0.55, y), Vector2(c.x, y - s * 0.38), w)
		"crouch":
			# Double chevron down.
			for k in range(2):
				var y := c.y - s * 0.35 + k * s * 0.42
				_glyph_line(Vector2(c.x - s * 0.55, y), Vector2(c.x, y + s * 0.38), w)
				_glyph_line(Vector2(c.x + s * 0.55, y), Vector2(c.x, y + s * 0.38), w)
		"prone":
			# Lying figure: head + body bar.
			draw_circle(c + Vector2(-s * 0.55, -s * 0.15), s * 0.22, ICON_COL)
			draw_rect(Rect2(c.x - s * 0.30, c.y - s * 0.02, s * 1.05, s * 0.30), ICON_COL)
			_glyph_line(Vector2(c.x - s * 0.75, c.y + s * 0.42),
				Vector2(c.x + s * 0.75, c.y + s * 0.42), w * 0.7)
		"grenade":
			# Round body + lever + pin ring.
			draw_circle(c + Vector2(0, s * 0.18), s * 0.52, ICON_COL)
			draw_circle(c + Vector2(0, s * 0.18), s * 0.52, Color(0, 0, 0, 0.25))
			_glyph_line(c + Vector2(-s * 0.30, -s * 0.30), c + Vector2(s * 0.45, -s * 0.45), w)
			draw_arc(c + Vector2(s * 0.62, -s * 0.52), s * 0.20, 0, TAU, 20, ICON_COL, w * 0.8)
		"sprint":
			# Double chevron right.
			for k in range(2):
				var x := c.x - s * 0.35 + k * s * 0.42
				_glyph_line(Vector2(x, c.y - s * 0.55), Vector2(x + s * 0.38, c.y), w)
				_glyph_line(Vector2(x + s * 0.38, c.y), Vector2(x, c.y + s * 0.55), w)
		"reload":
			# Circular arrow.
			draw_arc(c, s * 0.55, 0.6, TAU - 0.4, 32, ICON_COL, w)
			var tip := c + Vector2(cos(0.6), sin(0.6)) * s * 0.55
			var d1 := tip + Vector2(-s * 0.28, s * 0.05)
			var d2 := tip + Vector2(-s * 0.05, -s * 0.28)
			_glyph_line(tip, d1, w)
			_glyph_line(tip, d2, w)
		"swap":
			# Opposing up/down arrows.
			_glyph_line(Vector2(c.x - s * 0.30, c.y + s * 0.45), Vector2(c.x - s * 0.30, c.y - s * 0.45), w)
			_glyph_line(Vector2(c.x - s * 0.30, c.y - s * 0.45), Vector2(c.x - s * 0.48, c.y - s * 0.18), w)
			_glyph_line(Vector2(c.x - s * 0.30, c.y - s * 0.45), Vector2(c.x - s * 0.12, c.y - s * 0.18), w)
			_glyph_line(Vector2(c.x + s * 0.30, c.y - s * 0.45), Vector2(c.x + s * 0.30, c.y + s * 0.45), w)
			_glyph_line(Vector2(c.x + s * 0.30, c.y + s * 0.45), Vector2(c.x + s * 0.48, c.y + s * 0.18), w)
			_glyph_line(Vector2(c.x + s * 0.30, c.y + s * 0.45), Vector2(c.x + s * 0.12, c.y + s * 0.18), w)
		"armor":
			# Shield outline + plate line.
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.62), c + Vector2(s * 0.52, -s * 0.35),
				c + Vector2(s * 0.52, s * 0.15), c + Vector2(0, s * 0.62),
				c + Vector2(-s * 0.52, s * 0.15), c + Vector2(-s * 0.52, -s * 0.35)]),
				Color(0, 0, 0, 0.0))
			var pts := PackedVector2Array([
				c + Vector2(0, -s * 0.62), c + Vector2(s * 0.52, -s * 0.35),
				c + Vector2(s * 0.52, s * 0.15), c + Vector2(0, s * 0.62),
				c + Vector2(-s * 0.52, s * 0.15), c + Vector2(-s * 0.52, -s * 0.35),
				c + Vector2(0, -s * 0.62)])
			draw_polyline(pts, ICON_COL, w)
			_glyph_line(c + Vector2(-s * 0.28, 0), c + Vector2(s * 0.28, 0), w * 0.8)
		"streak":
			# Star.
			var pts := PackedVector2Array()
			for k in range(10):
				var rr := s * 0.62 if k % 2 == 0 else s * 0.28
				var a := -PI * 0.5 + k * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, ICON_COL)
		"gfx":
			# Three sliders.
			for k in range(3):
				var y := c.y - s * 0.40 + k * s * 0.40
				_glyph_line(Vector2(c.x - s * 0.60, y), Vector2(c.x + s * 0.60, y), w * 0.7)
				var kx := c.x + (float(k) - 1.0) * s * 0.30
				draw_circle(Vector2(kx, y), w * 0.9, ACCENT)
		"gear":
			# Gear: 8 teeth + ring + hub.
			for k in range(8):
				var a := k * TAU / 8.0
				var d := Vector2(cos(a), sin(a))
				_glyph_line(c + d * s * 0.42, c + d * s * 0.62, w * 1.1)
			draw_arc(c, s * 0.40, 0, TAU, 28, ICON_COL, w)
			draw_circle(c, s * 0.14, ICON_COL)
		"ping":
			# Diamond marker + dot.
			var p0 := c + Vector2(0, -s * 0.55)
			var p1 := c + Vector2(s * 0.45, 0)
			var p2 := c + Vector2(0, s * 0.55)
			var p3 := c + Vector2(-s * 0.45, 0)
			_glyph_line(p0, p1, w)
			_glyph_line(p1, p2, w)
			_glyph_line(p2, p3, w)
			_glyph_line(p3, p0, w)
			draw_circle(c, s * 0.16, ICON_COL)
		"smoke":
			# Canister + wavy smoke lines.
			draw_rect(Rect2(c.x - s * 0.28, c.y - s * 0.10, s * 0.56, s * 0.65), ICON_COL)
			for k in range(3):
				var x := c.x - s * 0.30 + k * s * 0.30
				_glyph_line(Vector2(x, c.y - s * 0.25), Vector2(x + s * 0.12, c.y - s * 0.45), w * 0.7)
				_glyph_line(Vector2(x + s * 0.12, c.y - s * 0.45), Vector2(x - s * 0.05, c.y - s * 0.62), w * 0.7)
		_:
			draw_circle(c, s * 0.30, ICON_COL)
