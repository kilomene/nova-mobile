class_name MythicSkins
extends RefCounted
## NOVA mythic skin system — extraordinarily advanced beyond CODM's mythics.
## 137 guns x 3 skins each (411+), all data-driven from 14 themes.
##
## Per theme:
##   - Procedural ANIMATED SHADER texture (molten cracks / frost crystals /
##     void nebula / circuitry / energy flow) via shaders/mythic_skin.gdshader
##   - Theme-specific 3D geometry accents (crystals, fins, muzzle rings, plates)
##   - Themed tracer, muzzle flash, impact tint, reload/draw flourishes
##   - KILL EVOLUTION: the skin visually evolves at 5/10/20 match kills
##     (dormant -> AWAKENED -> ASCENDANT -> MYTHIC), shown on the gun via the
##     shader's `evolve` uniform, with milestone banners + sound stings.
## Perf: shared cached ShaderMaterials per theme; per-instance `evolve`
## uniform; one-shot FX nodes that self-free. Zero per-frame cost otherwise.

# pattern: 0 cracks, 1 frost, 2 nebula, 3 circuit, 4 flow (see shader).
const THEMES := [
	{"id": "dragonfire", "name": "Dragonfire", "pattern": 0,
		"primary": Color(1.0, 0.32, 0.05), "secondary": Color(1.0, 0.72, 0.15),
		"tracer": Color(1.0, 0.5, 0.1), "flash": Color(1.0, 0.45, 0.1),
		"pulse": 4.2, "acc": {"crystals": 0, "fins": 3, "ring": 1, "plates": 0}},
	{"id": "glacier", "name": "Glacier", "pattern": 1,
		"primary": Color(0.45, 0.8, 1.0), "secondary": Color(0.9, 0.97, 1.0),
		"tracer": Color(0.6, 0.85, 1.0), "flash": Color(0.7, 0.9, 1.0),
		"pulse": 2.2, "acc": {"crystals": 5, "fins": 0, "ring": 1, "plates": 0}},
	{"id": "necrovoid", "name": "Necrovoid", "pattern": 2,
		"primary": Color(0.6, 0.15, 0.9), "secondary": Color(0.85, 0.4, 1.0),
		"tracer": Color(0.7, 0.3, 1.0), "flash": Color(0.65, 0.25, 0.95),
		"pulse": 3.0, "acc": {"crystals": 3, "fins": 0, "ring": 0, "plates": 0}},
	{"id": "solarflare", "name": "Solarflare", "pattern": 4,
		"primary": Color(1.0, 0.85, 0.2), "secondary": Color(1.0, 1.0, 0.85),
		"tracer": Color(1.0, 0.9, 0.4), "flash": Color(1.0, 0.9, 0.5),
		"pulse": 5.0, "acc": {"crystals": 0, "fins": 2, "ring": 1, "plates": 0}},
	{"id": "venom", "name": "Venom", "pattern": 4,
		"primary": Color(0.35, 1.0, 0.25), "secondary": Color(0.75, 1.0, 0.4),
		"tracer": Color(0.5, 1.0, 0.3), "flash": Color(0.5, 1.0, 0.35),
		"pulse": 3.6, "acc": {"crystals": 2, "fins": 2, "ring": 0, "plates": 0}},
	{"id": "bloodmoon", "name": "Bloodmoon", "pattern": 0,
		"primary": Color(0.9, 0.08, 0.12), "secondary": Color(1.0, 0.35, 0.3),
		"tracer": Color(1.0, 0.2, 0.2), "flash": Color(1.0, 0.25, 0.25),
		"pulse": 2.6, "acc": {"crystals": 0, "fins": 3, "ring": 1, "plates": 0}},
	{"id": "mecha", "name": "Mecha", "pattern": 3,
		"primary": Color(0.2, 0.9, 1.0), "secondary": Color(0.85, 0.95, 1.0),
		"tracer": Color(0.3, 0.9, 1.0), "flash": Color(0.4, 0.9, 1.0),
		"pulse": 6.0, "acc": {"crystals": 0, "fins": 0, "ring": 1, "plates": 3}},
	{"id": "aurora", "name": "Aurora", "pattern": 4,
		"primary": Color(0.25, 1.0, 0.75), "secondary": Color(1.0, 0.4, 0.85),
		"tracer": Color(0.4, 1.0, 0.8), "flash": Color(0.5, 1.0, 0.85),
		"pulse": 2.0, "acc": {"crystals": 3, "fins": 0, "ring": 1, "plates": 0}},
	{"id": "sandstorm", "name": "Sandstorm", "pattern": 4,
		"primary": Color(1.0, 0.7, 0.25), "secondary": Color(0.9, 0.8, 0.55),
		"tracer": Color(1.0, 0.8, 0.4), "flash": Color(1.0, 0.75, 0.35),
		"pulse": 3.2, "acc": {"crystals": 0, "fins": 2, "ring": 0, "plates": 2}},
	{"id": "abyssal", "name": "Abyssal", "pattern": 4,
		"primary": Color(0.1, 0.4, 1.0), "secondary": Color(0.35, 0.85, 1.0),
		"tracer": Color(0.25, 0.55, 1.0), "flash": Color(0.3, 0.6, 1.0),
		"pulse": 2.8, "acc": {"crystals": 4, "fins": 0, "ring": 1, "plates": 0}},
	{"id": "phoenix", "name": "Phoenix", "pattern": 0,
		"primary": Color(1.0, 0.55, 0.1), "secondary": Color(1.0, 0.9, 0.6),
		"tracer": Color(1.0, 0.65, 0.2), "flash": Color(1.0, 0.6, 0.25),
		"pulse": 4.6, "acc": {"crystals": 0, "fins": 4, "ring": 1, "plates": 0}},
	{"id": "stormcaller", "name": "Stormcaller", "pattern": 4,
		"primary": Color(0.5, 0.7, 1.0), "secondary": Color(0.95, 0.95, 1.0),
		"tracer": Color(0.6, 0.75, 1.0), "flash": Color(0.65, 0.8, 1.0),
		"pulse": 7.0, "acc": {"crystals": 2, "fins": 0, "ring": 1, "plates": 2}},
	{"id": "crimson", "name": "Crimson Oath", "pattern": 0,
		"primary": Color(0.75, 0.05, 0.2), "secondary": Color(1.0, 0.5, 0.55),
		"tracer": Color(0.9, 0.15, 0.3), "flash": Color(0.95, 0.2, 0.3),
		"pulse": 3.8, "acc": {"crystals": 0, "fins": 3, "ring": 0, "plates": 0}},
	{"id": "onyx", "name": "Onyx Reign", "pattern": 2,
		"primary": Color(0.5, 0.25, 0.9), "secondary": Color(0.75, 0.6, 1.0),
		"tracer": Color(0.6, 0.4, 1.0), "flash": Color(0.55, 0.35, 0.95),
		"pulse": 2.4, "acc": {"crystals": 3, "fins": 0, "ring": 1, "plates": 0}},
]

const SKINS_PER_GUN := 3
const STAGE_NAMES := ["", "AWAKENED", "ASCENDANT", "MYTHIC"]
const STAGE_KILLS := [0, 5, 10, 20]

static var _theme_mats := {}
static var _shader: Shader = null
static var _sting: AudioStreamWAV = null


static func theme_by_id(tid: String) -> Dictionary:
	for t in THEMES:
		if str(t["id"]) == tid:
			return t
	return {}


## Deterministic 3 distinct themes per gun. Returns [{theme, name}].
static func skins_for(gun_id: String) -> Array:
	var g := GunDefs.by_id(gun_id)
	if g.is_empty():
		return []
	var n := THEMES.size()
	var h := absi(gun_id.hash())
	var picks: Array = []
	var i := h % n
	var guard := 0
	while picks.size() < SKINS_PER_GUN and guard < 64:
		guard += 1
		if not picks.has(i):
			picks.append(i)
		i = (i + 5) % n  # 5 is coprime with 14: visits all themes
	var out: Array = []
	for pi in picks:
		var t: Dictionary = THEMES[pi]
		out.append({"theme": str(t["id"]), "name": "%s \"%s\"" % [str(g["name"]), str(t["name"])]})
	return out


static func skin_count(gun_id: String) -> int:
	return skins_for(gun_id).size()


static func skin_display_name(gun_id: String, skin_idx: int) -> String:
	if skin_idx <= 0:
		return ""
	var sk := skins_for(gun_id)
	if skin_idx - 1 < sk.size():
		return str(sk[skin_idx - 1]["name"])
	return ""


static func skin_theme(gun_id: String, skin_idx: int) -> String:
	if skin_idx <= 0:
		return ""
	var sk := skins_for(gun_id)
	if skin_idx - 1 < sk.size():
		return str(sk[skin_idx - 1]["theme"])
	return ""


static func tracer_color(gun_id: String, skin_idx: int) -> Color:
	var t := theme_by_id(skin_theme(gun_id, skin_idx))
	if t.is_empty():
		return Color(1.0, 0.85, 0.5)
	return t["tracer"]


static func flash_color(gun_id: String, skin_idx: int) -> Color:
	var t := theme_by_id(skin_theme(gun_id, skin_idx))
	if t.is_empty():
		return Color(1.0, 0.75, 0.4)
	return t["flash"]


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/mythic_skin.gdshader") as Shader
	return _shader


## Cached per-theme ShaderMaterials: armor (full pattern), accent (softer),
## glow (bright secondary, for crystals/rings).
static func theme_mats(tid: String) -> Dictionary:
	if _theme_mats.has(tid):
		return _theme_mats[tid]
	var t := theme_by_id(tid)
	if t.is_empty():
		return {}
	var sh := _get_shader()
	var armor := ShaderMaterial.new()
	armor.shader = sh
	armor.set_shader_parameter("pattern", int(t["pattern"]))
	armor.set_shader_parameter("col_primary", t["primary"])
	armor.set_shader_parameter("col_secondary", t["secondary"])
	armor.set_shader_parameter("glow_strength", 1.4)
	armor.set_shader_parameter("anim_speed", float(t["pulse"]) * 0.4)
	var accent := ShaderMaterial.new()
	accent.shader = sh
	accent.set_shader_parameter("pattern", int(t["pattern"]))
	accent.set_shader_parameter("col_primary", t["secondary"])
	accent.set_shader_parameter("col_secondary", t["secondary"])
	accent.set_shader_parameter("glow_strength", 0.9)
	accent.set_shader_parameter("anim_speed", float(t["pulse"]) * 0.4)
	var glow := ShaderMaterial.new()
	glow.shader = sh
	glow.set_shader_parameter("pattern", 4)
	glow.set_shader_parameter("col_primary", t["secondary"])
	glow.set_shader_parameter("col_secondary", t["secondary"])
	glow.set_shader_parameter("glow_strength", 2.2)
	glow.set_shader_parameter("anim_speed", float(t["pulse"]) * 0.6)
	var d := {"armor": armor, "accent": accent, "glow": glow,
		"pulse": float(t["pulse"])}
	_theme_mats[tid] = d
	return d


const _BODY_KEYS := ["gunmetal", "black", "carbon", "graphite", "dark"]
const _ACCENT_KEYS := ["wood", "tan", "od", "steel", "brass", "bronze", "bluegrey", "grey", "white", "sand"]


static func _classify(mat: Material) -> String:
	if mat == null:
		return ""
	for k in _BODY_KEYS:
		if mat == GunModels._mat(k):
			return "armor"
	for k in _ACCENT_KEYS:
		if mat == GunModels._mat(k):
			return "accent"
	if mat == GunModels._mat("glass"):
		return "glow"
	return ""


## Apply a mythic skin to a built gun model root (viewmodel or world model).
## skin_idx 0 = default (no-op). Replaces materials with animated shader
## materials, attaches theme geometry accents, sets evolution stage.
static func apply_to_model(root: Node, gun_id: String, skin_idx: int, stage := 0) -> void:
	var tid := skin_theme(gun_id, skin_idx)
	if tid == "" or root == null:
		return
	var mats := theme_mats(tid)
	_apply_recursive(root, mats)
	_build_theme_accents(root, tid, mats)
	set_evolution(root, stage)


static func _apply_recursive(n: Node, mats: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var key := _classify(mi.material_override)
		if key != "" and mats.has(key):
			mi.material_override = mats[key]
	for c in n.get_children():
		_apply_recursive(c, mats)


## Theme-specific 3D accents: crystals, swept fins, muzzle ring, armor plates.
## Small node counts; gun points along -Z, origin at receiver.
static func _build_theme_accents(root: Node, tid: String, mats: Dictionary) -> void:
	var t := theme_by_id(tid)
	var spec: Dictionary = t["acc"]
	var holder := Node3D.new()
	holder.name = "MythicAccents"
	root.add_child(holder)
	var n_crys := int(spec["crystals"])
	for i in range(n_crys):
		var s := 0.03 + 0.012 * float(i % 2)
		var bm := BoxMesh.new()
		bm.size = Vector3(s * 0.5, s * 1.6, s * 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mats["glow"]
		var side := 1.0 if i % 2 == 0 else -1.0
		mi.position = Vector3(side * 0.055, 0.035 + 0.012 * float(i / 2), 0.02 - 0.09 * float(i / 2))
		mi.rotation = Vector3(0.3 * side, 0.0, 0.55 * side)
		holder.add_child(mi)
	var n_fins := int(spec["fins"])
	for i in range(n_fins):
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.008, 0.055, 0.11)
		var mi2 := MeshInstance3D.new()
		mi2.mesh = bm2
		mi2.material_override = mats["accent"]
		var side2 := 1.0 if i % 2 == 0 else -1.0
		mi2.position = Vector3(side2 * 0.032, 0.055, -0.28 - 0.1 * float(i / 2))
		mi2.rotation = Vector3(0.0, 0.0, -0.45 * side2)
		holder.add_child(mi2)
	if int(spec["ring"]) > 0:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.032
		tm.outer_radius = 0.048
		var mi3 := MeshInstance3D.new()
		mi3.mesh = tm
		mi3.material_override = mats["glow"]
		mi3.position = Vector3(0, 0.012, -0.62)
		mi3.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		holder.add_child(mi3)
	var n_plates := int(spec["plates"])
	for i in range(n_plates):
		var bm3 := BoxMesh.new()
		bm3.size = Vector3(0.075, 0.012, 0.09)
		var mi4 := MeshInstance3D.new()
		mi4.mesh = bm3
		mi4.material_override = mats["accent"]
		mi4.position = Vector3(0, 0.062, 0.1 - 0.12 * float(i))
		holder.add_child(mi4)


# --- kill evolution -------------------------------------------------------
## Stages: 0 dormant, 1 AWAKENED (5), 2 ASCENDANT (10), 3 MYTHIC (20).
static func evolution_stage(kills: int) -> int:
	if kills >= 20:
		return 3
	if kills >= 10:
		return 2
	if kills >= 5:
		return 1
	return 0


## Set the shader `evolve` uniform per model instance (0..1).
static func set_evolution(root: Node, stage: int) -> void:
	if root == null:
		return
	var v := clampf(float(stage) / 3.0, 0.0, 1.0)
	_set_evolve_recursive(root, v)


static func _set_evolve_recursive(n: Node, v: float) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).set_instance_shader_parameter("evolve", v)
	for c in n.get_children():
		_set_evolve_recursive(c, v)


## Rising shimmer sting for evolution milestones. Synthesized, cached.
static func evolution_sting() -> AudioStreamWAV:
	if _sting != null:
		return _sting
	var rate := 22050
	var dur := 0.6
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / rate
		var f := 500.0 + 1400.0 * (t / dur)
		phase += TAU * f / rate
		var env := exp(-3.0 * t)
		var s := sin(phase) * env + 0.4 * sin(phase * 2.0) * env
		data[i] = clampi(int(127 + 90 * s), 0, 255)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.data = data
	_sting = w
	return w


# --- one-shot FX ----------------------------------------------------------
class FXOneShot extends CPUParticles3D:
	var life := 1.0
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		if t > life:
			queue_free()


static func _burst(parent: Node3D, theme: Dictionary, count: int, speed: float, size: float, life: float) -> void:
	if theme.is_empty() or parent == null:
		return
	var p := FXOneShot.new()
	p.amount = count
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = life
	p.life = life + 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -4, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.color = theme["secondary"]
	parent.add_child(p)
	p.emitting = true


## Theme reload flourish: energy puff at the gun.
static func play_reload_flourish(gun_node: Node3D, theme_id: String) -> void:
	_burst(gun_node, theme_by_id(theme_id), 14, 2.5, 0.09, 0.5)


## Theme draw flourish: brighter flash when the mythic is drawn.
static func play_draw_flourish(gun_node: Node3D, theme_id: String) -> void:
	_burst(gun_node, theme_by_id(theme_id), 22, 3.5, 0.12, 0.6)


## Mythic kill FX: theme-colored burst + floating kill counter.
## milestone: "" or e.g. "AWAKENED" -> big banner instead.
static func play_killfx(parent: Node, pos: Vector3, theme_id: String, kill_num: int, milestone := "") -> bool:
	var t := theme_by_id(theme_id)
	if t.is_empty() or parent == null:
		return false
	var fx := KillFX.new()
	parent.add_child(fx)
	fx.global_position = pos
	fx.setup(t, kill_num, milestone)
	return true


class KillFX extends Node3D:
	var t := 0.0
	var life := 1.5
	var label: Label3D = null

	func setup(theme: Dictionary, kill_num: int, milestone: String) -> void:
		var p := CPUParticles3D.new()
		p.amount = 34 if milestone == "" else 60
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4
		p.direction = Vector3(0, 1, 0)
		p.spread = 60.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 8.0
		p.gravity = Vector3(0, -6, 0)
		p.scale_amount_min = 0.06
		p.scale_amount_max = 0.16
		p.color = theme["primary"]
		add_child(p)
		p.emitting = true
		label = Label3D.new()
		if milestone == "":
			label.text = "KILL #%d" % kill_num
			label.font_size = 96
			label.pixel_size = 0.008
			label.position = Vector3(0, 1.2, 0)
		else:
			label.text = "%s\n%s" % [str(theme["name"]).to_upper(), milestone]
			label.font_size = 128
			label.pixel_size = 0.012
			label.position = Vector3(0, 1.6, 0)
			life = 2.4
		label.modulate = theme["secondary"]
		label.outline_size = 12
		label.outline_modulate = Color(0, 0, 0, 0.9)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)

	func _process(d: float) -> void:
		t += d
		if label != null and is_instance_valid(label):
			label.position.y += d * 1.6
			var c: Color = label.modulate
			c.a = clampf(life - t, 0.0, 1.0)
			label.modulate = c
		if t > life:
			queue_free()
