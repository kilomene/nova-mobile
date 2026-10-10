class_name GunsmithMenu
extends CanvasLayer
## NOVA gunsmith: pick primary gun, mythic skin, attachments — with a live 3D
## preview, full stats, and STK ("4 SHOTS · 2 HEAD") front and center.
## Pre-match step: map -> character -> class -> GUNSMITH -> drop-in.

signal deployed(gun_id: String, skin_idx: int, attach: Array)

const ATTACH_SLOTS := ["muzzle", "optic", "magazine", "underbarrel"]

var _sel_class := "ar"
var _sel_gun := "m5"
var _sel_skin := 0
var _sel_attach := {}

var _gun_list: VBoxContainer
var _preview_vp: SubViewport
var _preview_root: Node3D = null
var _preview_name: Label
var _stats_label: Label
var _stk_label: Label
var _skin_box: VBoxContainer
var _attach_box: VBoxContainer
var _t := 0.0


func _ready() -> void:
	layer = 20
	_build()


func _process(d: float) -> void:
	_t += d
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.rotation.y = _t * 0.7


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "GUNSMITH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "SELECT PRIMARY WEAPON · MYTHIC SKIN · ATTACHMENTS"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vb.add_child(sub)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(hb)
	_build_left(hb)
	_build_center(hb)
	_build_right(hb)


func _build_left(hb: HBoxContainer) -> void:
	var lv := VBoxContainer.new()
	lv.custom_minimum_size = Vector2(300, 0)
	lv.add_theme_constant_override("separation", 6)
	hb.add_child(lv)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	lv.add_child(grid)
	for cls in GunDefs.CLASS_NAMES.keys():
		var b := Button.new()
		b.text = str(GunDefs.CLASS_NAMES[cls]).to_upper()
		b.custom_minimum_size = Vector2(92, 40)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_class_tab.bind(str(cls)))
		grid.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)
	_gun_list = VBoxContainer.new()
	_gun_list.add_theme_constant_override("separation", 4)
	_gun_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gun_list)
	_refresh_gun_list()


func _refresh_gun_list() -> void:
	for c in _gun_list.get_children():
		c.queue_free()
	for g in GunDefs.all():
		if str(g["cls"]) != _sel_class:
			continue
		var b := Button.new()
		var stk := GunDefs.stk_label(g)
		b.text = "%s \"%s\"\n%s" % [str(g["name"]), str(g["alias"]), stk]
		b.custom_minimum_size = Vector2(280, 56)
		b.add_theme_font_size_override("font_size", 15)
		if str(g["id"]) == _sel_gun:
			b.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		b.pressed.connect(_on_gun_pick.bind(str(g["id"])))
		_gun_list.add_child(b)


func _build_center(hb: HBoxContainer) -> void:
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 8)
	hb.add_child(cv)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(420, 380)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(svc)
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = true
	svc.add_child(_preview_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0.55, 0.32, 1.05)
	cam.look_at(Vector3(0, 0.05, -0.15))
	_preview_vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0)
	sun.light_energy = 1.2
	_preview_vp.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.6, 0.4, 0.8)
	fill.light_energy = 0.5
	_preview_vp.add_child(fill)
	_preview_name = Label.new()
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name.add_theme_font_size_override("font_size", 24)
	_preview_name.add_theme_color_override("font_color", Color(1, 1, 1))
	cv.add_child(_preview_name)
	_rebuild_preview()


func _rebuild_preview() -> void:
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
		_preview_root = null
	var g := GunDefs.by_id(_sel_gun)
	if g.is_empty():
		return
	var built: Dictionary = GunModels.build_viewmodel(_sel_gun)
	_preview_root = built["root"] as Node3D
	MythicSkins.apply_to_model(_preview_root, _sel_gun, _sel_skin, 0)
	_preview_root.position = Vector3(0, -0.05, 0.1)
	_preview_vp.add_child(_preview_root)
	var skn := MythicSkins.skin_display_name(_sel_gun, _sel_skin)
	_preview_name.text = GunDefs.full_name(g) + ("" if skn == "" else "\n" + skn)
	if skn != "":
		_preview_name.add_theme_color_override("font_color", Color(1.0, 0.6, 1.0))
	else:
		_preview_name.add_theme_color_override("font_color", Color(1, 1, 1))
	_refresh_stats()
	_refresh_skins()


func _build_right(hb: HBoxContainer) -> void:
	var rv := VBoxContainer.new()
	rv.custom_minimum_size = Vector2(360, 0)
	rv.add_theme_constant_override("separation", 8)
	hb.add_child(rv)
	_stk_label = Label.new()
	_stk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stk_label.add_theme_font_size_override("font_size", 30)
	_stk_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.15))
	rv.add_child(_stk_label)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 16)
	_stats_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	rv.add_child(_stats_label)
	var skh := Label.new()
	skh.text = "MYTHIC SKINS"
	skh.add_theme_font_size_override("font_size", 18)
	skh.add_theme_color_override("font_color", Color(0.85, 0.5, 1.0))
	rv.add_child(skh)
	_skin_box = VBoxContainer.new()
	_skin_box.add_theme_constant_override("separation", 4)
	rv.add_child(_skin_box)
	var evo := Label.new()
	evo.text = "Mythic skins evolve at 5 / 10 / 20 match kills."
	evo.add_theme_font_size_override("font_size", 13)
	evo.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	evo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(evo)
	var ah := Label.new()
	ah.text = "ATTACHMENTS"
	ah.add_theme_font_size_override("font_size", 18)
	ah.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	rv.add_child(ah)
	_attach_box = VBoxContainer.new()
	_attach_box.add_theme_constant_override("separation", 4)
	rv.add_child(_attach_box)
	_refresh_stats()
	_refresh_skins()
	_refresh_attachments()
	var dep := Button.new()
	dep.text = "DEPLOY →"
	dep.custom_minimum_size = Vector2(360, 64)
	dep.add_theme_font_size_override("font_size", 26)
	dep.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	dep.pressed.connect(_on_deploy)
	rv.add_child(dep)


func _refresh_stats() -> void:
	if _stk_label == null or _stats_label == null:
		return
	var g := GunDefs.by_id(_sel_gun)
	if g.is_empty():
		return
	_stk_label.text = GunDefs.stk_label(g)
	_stats_label.text = "Damage %d · RPM %d · Mag %d\nRange %dm–%dm · %s\n%s" % [
		int(g["damage"]), int(g["rpm"]), int(g["mag"]),
		int(g["range_near"]), int(g["range_far"]),
		GunDefs.class_name_of(str(g["cls"])), str(g["role"])]


func _refresh_skins() -> void:
	if _skin_box == null:
		return
	for c in _skin_box.get_children():
		c.queue_free()
	var b0 := Button.new()
	b0.text = "STANDARD"
	b0.custom_minimum_size = Vector2(340, 44)
	b0.add_theme_font_size_override("font_size", 16)
	if _sel_skin == 0:
		b0.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	b0.pressed.connect(_on_skin_pick.bind(0))
	_skin_box.add_child(b0)
	var sk := MythicSkins.skins_for(_sel_gun)
	for i in range(sk.size()):
		var s: Dictionary = sk[i]
		var t := MythicSkins.theme_by_id(str(s["theme"]))
		var owned := StoreWallet.owns_skin(_sel_gun, i + 1)
		var b := Button.new()
		b.text = ("✦ " if owned else "🔒 ") + str(s["name"]) + ("" if owned else " — %d NP" % StoreDefs.MYTHIC_PRICE)
		b.custom_minimum_size = Vector2(340, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", t["secondary"] if owned else Color(0.55, 0.57, 0.6))
		if _sel_skin == i + 1:
			b.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		b.tooltip_text = "Animated %s texture · themed tracer/flash · kill evolution" % str(t["name"]) if owned else "Buy in the NOVA STORE for %d NP" % StoreDefs.MYTHIC_PRICE
		b.pressed.connect(_on_skin_pick.bind(i + 1))
		_skin_box.add_child(b)


func _refresh_attachments() -> void:
	for c in _attach_box.get_children():
		c.queue_free()
	for slot in ATTACH_SLOTS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		_attach_box.add_child(hb)
		var lab := Label.new()
		lab.text = str(slot).capitalize()
		lab.custom_minimum_size = Vector2(96, 36)
		lab.add_theme_font_size_override("font_size", 13)
		hb.add_child(lab)
		var none_b := Button.new()
		none_b.text = "—"
		none_b.custom_minimum_size = Vector2(44, 36)
		if not _sel_attach.has(slot):
			none_b.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		none_b.pressed.connect(_on_attach_pick.bind(slot, ""))
		hb.add_child(none_b)
		var opts: Dictionary = GunDefs.ATTACHMENTS[slot]
		for aid in opts.keys():
			var a: Dictionary = opts[aid]
			var b := Button.new()
			b.text = str(a["name"])
			b.custom_minimum_size = Vector2(0, 36)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 12)
			if str(_sel_attach.get(slot, "")) == str(aid):
				b.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
			b.tooltip_text = _attach_desc(a)
			b.pressed.connect(_on_attach_pick.bind(slot, str(aid)))
			hb.add_child(b)


func _attach_desc(a: Dictionary) -> String:
	var parts: Array = []
	for k in ["dmg", "rpm", "rec", "ads", "magadd", "spread", "range", "move", "reload"]:
		if a.has(k):
			parts.append("%s %+.0f%%" % [k, (float(a[k]) - 1.0) * 100.0])
	if bool(a.get("silent", false)):
		parts.append("suppressed")
	return ", ".join(parts)


func _on_class_tab(cls: String) -> void:
	_sel_class = cls
	_sel_skin = 0
	_sel_attach.clear()
	for g in GunDefs.all():
		if str(g["cls"]) == cls:
			_sel_gun = str(g["id"])
			break
	_refresh_gun_list()
	_rebuild_preview()
	_refresh_attachments()


func _on_gun_pick(gid: String) -> void:
	_sel_gun = gid
	_sel_skin = 0
	_refresh_gun_list()
	_rebuild_preview()


func _on_skin_pick(idx: int) -> void:
	if idx > 0 and not StoreWallet.owns_skin(_sel_gun, idx):
		return  # locked mythic — buy it in the NOVA STORE
	_sel_skin = idx
	_rebuild_preview()


func _on_attach_pick(slot: String, aid: String) -> void:
	if aid == "":
		_sel_attach.erase(slot)
	else:
		_sel_attach[slot] = aid
	_refresh_attachments()
	_refresh_stats()


func _on_deploy() -> void:
	var at: Array = []
	for slot in ATTACH_SLOTS:
		if _sel_attach.has(slot):
			at.append(str(_sel_attach[slot]))
	deployed.emit(_sel_gun, _sel_skin, at)
