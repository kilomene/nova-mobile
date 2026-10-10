class_name ControlSettings
## NOVA Mobile — controller settings store (CODM-style).
## Static access so player.gd / hud.gd / settings_menu.gd all share one copy.
## Persisted to user://nova_controls.cfg via ConfigFile.
##
## Sensitivity model: multipliers applied on top of the base look speeds.
##   cam_sens   — hipfire camera sensitivity (CODM "Camera Sensitivity")
##   ads_sens   — iron/red-dot ADS multiplier
##   zoom4_sens — 4x optic multiplier, zoom8_sens — 8x optic multiplier

const PATH := "user://nova_controls.cfg"

static var cam_sens := 1.0
static var ads_sens := 0.6
static var zoom4_sens := 0.45
static var zoom8_sens := 0.35
static var invert_y := false
static var gyro_enabled := false
static var gyro_sens := 1.0
static var aim_assist := true
static var assist_strength := 0.5
static var fire_mode := "advanced"  # "advanced" (manual) | "simple" (auto-fire)
static var haptics := true
static var hud_opacity := 1.0
static var tilt_steering := false  # driving: tilt phone to steer
# Custom HUD layout: button_id -> {"p": Vector2 (center, screen fractions),
#                                  "d": float (diameter, fraction of height)}
static var layout := {}


static func reset_defaults() -> void:
	cam_sens = 1.0
	ads_sens = 0.6
	zoom4_sens = 0.45
	zoom8_sens = 0.35
	invert_y = false
	gyro_enabled = false
	gyro_sens = 1.0
	aim_assist = true
	assist_strength = 0.5
	fire_mode = "advanced"
	haptics = true
	hud_opacity = 1.0
	tilt_steering = false
	# NOTE: layout intentionally NOT cleared here; use clear_layout().


static func clear_layout() -> void:
	layout = {}


static func set_layout(id: String, pos_frac: Vector2, d_frac: float) -> void:
	layout[id] = {"p": pos_frac, "d": d_frac}


static func get_layout(id: String) -> Dictionary:
	if layout.has(id):
		return layout[id]
	return {}


static func setv(key: String, val) -> void:
	match key:
		"cam_sens": cam_sens = clampf(float(val), 0.2, 3.0)
		"ads_sens": ads_sens = clampf(float(val), 0.1, 2.0)
		"zoom4_sens": zoom4_sens = clampf(float(val), 0.1, 1.5)
		"zoom8_sens": zoom8_sens = clampf(float(val), 0.1, 1.5)
		"invert_y": invert_y = bool(val)
		"gyro_enabled": gyro_enabled = bool(val)
		"gyro_sens": gyro_sens = clampf(float(val), 0.2, 3.0)
		"aim_assist": aim_assist = bool(val)
		"assist_strength": assist_strength = clampf(float(val), 0.0, 1.0)
		"fire_mode": fire_mode = "simple" if str(val) == "simple" else "advanced"
		"haptics": haptics = bool(val)
		"hud_opacity": hud_opacity = clampf(float(val), 0.3, 1.0)


static func getv(key: String):
	match key:
		"cam_sens": return cam_sens
		"ads_sens": return ads_sens
		"zoom4_sens": return zoom4_sens
		"zoom8_sens": return zoom8_sens
		"invert_y": return invert_y
		"gyro_enabled": return gyro_enabled
		"gyro_sens": return gyro_sens
		"aim_assist": return aim_assist
		"assist_strength": return assist_strength
		"fire_mode": return fire_mode
		"haptics": return haptics
		"hud_opacity": return hud_opacity
	return null


static func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sens", "cam", cam_sens)
	cfg.set_value("sens", "ads", ads_sens)
	cfg.set_value("sens", "zoom4", zoom4_sens)
	cfg.set_value("sens", "zoom8", zoom8_sens)
	cfg.set_value("sens", "invert_y", invert_y)
	cfg.set_value("gyro", "enabled", gyro_enabled)
	cfg.set_value("gyro", "sens", gyro_sens)
	cfg.set_value("assist", "enabled", aim_assist)
	cfg.set_value("assist", "strength", assist_strength)
	cfg.set_value("fire", "mode", fire_mode)
	cfg.set_value("hud", "haptics", haptics)
	cfg.set_value("hud", "opacity", hud_opacity)
	cfg.set_value("drive", "tilt_steering", tilt_steering)
	for id in layout:
		var e: Dictionary = layout[id]
		var p: Vector2 = e["p"]
		cfg.set_value("layout", id, [p.x, p.y, float(e["d"])])
	cfg.save(PATH)


static func load_all() -> void:
	reset_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	cam_sens = clampf(float(cfg.get_value("sens", "cam", 1.0)), 0.2, 3.0)
	ads_sens = clampf(float(cfg.get_value("sens", "ads", 0.6)), 0.1, 2.0)
	zoom4_sens = clampf(float(cfg.get_value("sens", "zoom4", 0.45)), 0.1, 1.5)
	zoom8_sens = clampf(float(cfg.get_value("sens", "zoom8", 0.35)), 0.1, 1.5)
	invert_y = bool(cfg.get_value("sens", "invert_y", false))
	gyro_enabled = bool(cfg.get_value("gyro", "enabled", false))
	gyro_sens = clampf(float(cfg.get_value("gyro", "sens", 1.0)), 0.2, 3.0)
	aim_assist = bool(cfg.get_value("assist", "enabled", true))
	assist_strength = clampf(float(cfg.get_value("assist", "strength", 0.5)), 0.0, 1.0)
	var fm := str(cfg.get_value("fire", "mode", "advanced"))
	fire_mode = "simple" if fm == "simple" else "advanced"
	haptics = bool(cfg.get_value("hud", "haptics", true))
	hud_opacity = clampf(float(cfg.get_value("hud", "opacity", 1.0)), 0.3, 1.0)
	tilt_steering = bool(cfg.get_value("drive", "tilt_steering", false))
	layout = {}
	for id in cfg.get_section_keys("layout"):
		var v: Array = cfg.get_value("layout", id, [])
		if v.size() == 3:
			layout[id] = {"p": Vector2(float(v[0]), float(v[1])), "d": float(v[2])}
