class_name StoreMenu
extends CanvasLayer
## NOVA in-game store — CODM-style: Featured, Lucky Draws, Weapon Skins,
## Bundles, Characters (locked hook), Battle Pass (locked teaser), Buy NP.
## Dark military visual language with orange accents and card-based items.
## Mythic skins bought here unlock in the gunsmith (StoreWallet ownership).

signal closed

const ORANGE := Color(1.0, 0.75, 0.2)
const BG := Color(0.03, 0.04, 0.06, 0.97)
const CARD := Color(0.07, 0.09, 0.12, 1.0)
const MUTED := Color(0.65, 0.68, 0.72)

var _rng := RandomNumberGenerator.new()
var _payments: Payments
var _np_label: Label
var _tab_row: HBoxContainer
var _content: ScrollContainer
var _content_box: VBoxContainer
var _sel_tab := "featured"
var _sel_draw := "draw_dragonfire"
var _draw_expiry := {}   # draw_id -> unix timestamp (countdown timers)
var _msg: Label
var _t := 0.0


func _ready() -> void:
	layer = 20
	_rng.randomize()
	_payments = Payments.new()
	_payments.attach_http(self)
	_payments.purchase_completed.connect(_on_purchase_completed)
	_payments.purchase_failed.connect(_on_purchase_failed)
	var now := int(Time.get_unix_time_from_system())
	for d in StoreDefs.DRAWS:
		_draw_expiry[str(d["id"])] = now + int(d["ends_in_days"]) * 86400
	_build()


func _process(d: float) -> void:
	_t += d
	if _t >= 1.0 and _sel_tab == "featured":
		_t = 0.0
		_refresh_tab()  # keep countdown timers live


# ---------------------------------------------------------------- build ---
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	_build_topbar(vb)
	_build_tabs(vb)
	_msg = Label.new()
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 16)
	_msg.add_theme_color_override("font_color", ORANGE)
	vb.add_child(_msg)
	_content = ScrollContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_content)
	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 10)
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_content_box)
	_refresh_tab()


func _build_topbar(vb: VBoxContainer) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var title := Label.new()
	title.text = "NOVA STORE"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", ORANGE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(title)
	_np_label = Label.new()
	_np_label.add_theme_font_size_override("font_size", 24)
	_np_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	hb.add_child(_np_label)
	var npb := Button.new()
	npb.text = "+ NP"
	npb.custom_minimum_size = Vector2(110, 48)
	npb.add_theme_font_size_override("font_size", 18)
	npb.add_theme_color_override("font_color", ORANGE)
	npb.pressed.connect(func() -> void: _select_tab("np"))
	hb.add_child(npb)
	var cb := Button.new()
	cb.text = "✕ CLOSE"
	cb.custom_minimum_size = Vector2(140, 48)
	cb.add_theme_font_size_override("font_size", 18)
	cb.pressed.connect(func() -> void: closed.emit())
	hb.add_child(cb)
	_refresh_balance()


func _refresh_balance() -> void:
	_np_label.text = "◈ %d NP" % StoreWallet.balance()


func _build_tabs(vb: VBoxContainer) -> void:
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	vb.add_child(_tab_row)
	for t in StoreDefs.TABS:
		var b := Button.new()
		var locked := bool(t.get("locked", false))
		b.text = str(t["name"]) + (" 🔒" if locked else "")
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = locked
		if locked:
			b.tooltip_text = str(t.get("lock_note", "COMING SOON"))
		var tid := str(t["id"])
		b.pressed.connect(_select_tab.bind(tid))
		_tab_row.add_child(b)


func _select_tab(tid: String) -> void:
	_sel_tab = tid
	_msg.text = ""
	_refresh_tab()


func _refresh_tab() -> void:
	if _content_box == null:
		return
	for c in _content_box.get_children():
		_content_box.remove_child(c)  # detach now; free at frame end (safe mid-signal)
		c.queue_free()
	_refresh_balance()
	match _sel_tab:
		"featured": _tab_featured()
		"draws": _tab_draws()
		"skins": _tab_skins()
		"bundles": _tab_bundles()
		"np": _tab_np()
		_: _tab_locked()


func _card(title_text: String, title_color: Color) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.16, 0.18, 0.22)
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	m.add_child(vb)
	p.add_child(m)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", title_color)
	vb.add_child(t)
	_content_box.add_child(p)
	return vb


func _note(parent: Control, text: String, size := 14, color := MUTED) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _countdown(did: String) -> String:
	var left: int = int(_draw_expiry.get(did, 0)) - int(Time.get_unix_time_from_system())
	if left < 0:
		left = 0
	var d := left / 86400
	var h := (left % 86400) / 3600
	var m := (left % 3600) / 60
	return "Ends in %dd %02dh %02dm" % [d, h, m]


# -------------------------------------------------------------- featured ---
func _tab_featured() -> void:
	var d := StoreDefs.DRAWS[0]
	var vb := _card(str(d["name"]) + "  ·  " + _countdown(str(d["id"])), ORANGE)
	_note(vb, "Top prize: " + StoreDefs.item_label(StoreDefs.draw_top_prize(str(d["id"]))), 16, Color(1.0, 0.6, 1.0))
	_note(vb, "10 spins · escalating costs · owned items removed from pool · 10th spin GUARANTEES the mythic")
	var b := Button.new()
	b.text = "VIEW DRAW →"
	b.custom_minimum_size = Vector2(220, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", ORANGE)
	b.pressed.connect(func() -> void:
		_sel_draw = str(d["id"])
		_select_tab("draws"))
	vb.add_child(b)
	for bu in StoreDefs.BUNDLES:
		var owned := StoreWallet.owns_bundle(str(bu["id"]))
		var cb := _card(str(bu["name"]) + ("  ·  OWNED" if owned else ""), Color(0.6, 0.85, 1.0))
		_note(cb, str(bu["desc"]))
		if not owned:
			var bb := Button.new()
			bb.text = "BUY — %d NP" % int(bu["price"])
			bb.custom_minimum_size = Vector2(220, 44)
			bb.add_theme_font_size_override("font_size", 16)
			bb.add_theme_color_override("font_color", ORANGE)
			bb.pressed.connect(_on_buy_bundle.bind(str(bu["id"])))
			cb.add_child(bb)


# ----------------------------------------------------------------- draws ---
func _tab_draws() -> void:
	# draw selector
	var sel := HBoxContainer.new()
	sel.add_theme_constant_override("separation", 8)
	_content_box.add_child(sel)
	for d in StoreDefs.DRAWS:
		var b := Button.new()
		b.text = str(d["name"])
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		if str(d["id"]) == _sel_draw:
			b.add_theme_color_override("font_color", ORANGE)
		b.pressed.connect(func() -> void:
			_sel_draw = str(d["id"])
			_refresh_tab())
		sel.add_child(b)
	var draw := StoreDefs.draw_by_id(_sel_draw)
	if draw.is_empty():
		return
	var st := StoreWallet.draw_state(_sel_draw)
	var won: Array = st["won"]
	var vb := _card(str(draw["name"]) + "  ·  " + _countdown(_sel_draw), ORANGE)
	_note(vb, "Top prize: " + StoreDefs.item_label(StoreDefs.draw_top_prize(_sel_draw)), 16, Color(1.0, 0.6, 1.0))
	_note(vb, "Odds per spin — Mythic 3% · Epic 12% · Rare 30% · Common 55% (re-weighted over remaining pool)")
	# 10-slot grid
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	var items: Array = draw["items"]
	for i in range(items.size()):
		var it: Dictionary = items[i]
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(190, 56)
		lab.add_theme_font_size_override("font_size", 13)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var kind := str(it["kind"])
		var col: Color = {"mythic": Color(1.0, 0.6, 1.0), "epic": Color(0.75, 0.5, 1.0),
			"rare": Color(0.45, 0.7, 1.0), "common": Color(0.7, 0.7, 0.7)}.get(kind, Color.WHITE)
		if won.has(i):
			lab.text = "✔ " + StoreDefs.item_label(it)
			lab.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
		else:
			lab.text = StoreDefs.item_label(it)
			lab.add_theme_color_override("font_color", col)
		grid.add_child(lab)
	# spin controls
	var spins_used := won.size()
	if spins_used >= 10:
		_note(vb, "DRAW COMPLETE — all 10 items claimed.", 16, Color(0.35, 0.9, 0.45))
	else:
		var cost := LuckyDraw.spin_cost(spins_used)
		var sb := Button.new()
		sb.text = "SPIN (%d) — %d NP" % [spins_used + 1, cost]
		sb.custom_minimum_size = Vector2(280, 56)
		sb.add_theme_font_size_override("font_size", 19)
		sb.add_theme_color_override("font_color", ORANGE)
		sb.disabled = StoreWallet.balance() < cost
		sb.tooltip_text = "Insufficient NP — buy more in the BUY NOVA POINTS tab" if StoreWallet.balance() < cost else ""
		sb.pressed.connect(_on_spin)
		vb.add_child(sb)
		_note(vb, "Full draw (all 10 spins) = %d NP — 10th spin guarantees the mythic." % StoreDefs.draw_full_cost())


func _on_spin() -> void:
	var st := StoreWallet.draw_state(_sel_draw)
	var won: Array = (st["won"] as Array).duplicate()
	var r := LuckyDraw.spin(_sel_draw, won, _rng)
	if not bool(r.get("ok", false)):
		_msg.text = "Spin failed: " + str(r.get("reason", "?"))
		return
	StoreWallet.record_draw_win(_sel_draw, int(r["won_idx"]))
	var label := StoreDefs.item_label(r["item"])
	_msg.text = ("✦ GUARANTEED MYTHIC! " if bool(r.get("guaranteed", false)) else "Won: ") + label
	_refresh_tab()


# ----------------------------------------------------------------- skins ---
func _tab_skins() -> void:
	_note(_content_box, "Direct-buy mythic skins — %d NP each. Owned skins unlock in the gunsmith." % StoreDefs.MYTHIC_PRICE, 15, ORANGE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content_box.add_child(grid)
	var holder := VBoxContainer.new()  # cards need a plain parent, not the box
	for offer in StoreDefs.SKIN_OFFERS:
		var gun := str(offer["gun"])
		var idx := int(offer["skin_idx"])
		var g := GunDefs.by_id(gun)
		if g.is_empty():
			continue
		var t := MythicSkins.theme_by_id(MythicSkins.skin_theme(gun, idx))
		var col: Color = t.get("secondary", Color.WHITE)
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = CARD
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.16, 0.18, 0.22)
		p.add_theme_stylebox_override("panel", sb)
		grid.add_child(p)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		var m := MarginContainer.new()
		for mm in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			m.add_theme_constant_override(mm, 10)
		m.add_child(vb)
		p.add_child(m)
		var nm := Label.new()
		nm.text = "✦ " + MythicSkins.skin_display_name(gun, idx)
		nm.add_theme_font_size_override("font_size", 17)
		nm.add_theme_color_override("font_color", col)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(nm)
		var gl := Label.new()
		gl.text = "%s · %s · %s" % [str(g["name"]), GunDefs.class_name_of(str(g["cls"])), str(t.get("name", ""))]
		gl.add_theme_font_size_override("font_size", 13)
		gl.add_theme_color_override("font_color", MUTED)
		vb.add_child(gl)
		var owned := StoreWallet.owns_skin(gun, idx)
		if owned:
			var ol := Label.new()
			ol.text = "✔ OWNED — equip in gunsmith"
			ol.add_theme_font_size_override("font_size", 14)
			ol.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
			vb.add_child(ol)
		else:
			var b := Button.new()
			b.text = "BUY — %d NP" % StoreDefs.MYTHIC_PRICE
			b.custom_minimum_size = Vector2(200, 44)
			b.add_theme_font_size_override("font_size", 15)
			b.add_theme_color_override("font_color", ORANGE)
			b.disabled = StoreWallet.balance() < StoreDefs.MYTHIC_PRICE
			b.pressed.connect(_on_buy_skin.bind(gun, idx))
			vb.add_child(b)
	holder.queue_free()


func _on_buy_skin(gun: String, idx: int) -> void:
	if StoreWallet.buy_skin(gun, idx):
		_msg.text = "✔ Unlocked: " + MythicSkins.skin_display_name(gun, idx)
	else:
		_msg.text = "Could not buy — insufficient NP or already owned."
	_refresh_tab()


# --------------------------------------------------------------- bundles ---
func _tab_bundles() -> void:
	for bu in StoreDefs.BUNDLES:
		var owned := StoreWallet.owns_bundle(str(bu["id"]))
		var vb := _card(str(bu["name"]) + ("  ·  OWNED" if owned else ""), Color(0.6, 0.85, 1.0))
		_note(vb, "Includes mythic skin: " + MythicSkins.skin_display_name(str(bu["gun"]), int(bu["skin_idx"])), 15, Color(1.0, 0.6, 1.0))
		_note(vb, str(bu["desc"]))
		if owned:
			_note(vb, "✔ OWNED — skin equippable in gunsmith", 14, Color(0.35, 0.9, 0.45))
		else:
			var b := Button.new()
			b.text = "BUY BUNDLE — %d NP" % int(bu["price"])
			b.custom_minimum_size = Vector2(260, 48)
			b.add_theme_font_size_override("font_size", 17)
			b.add_theme_color_override("font_color", ORANGE)
			b.disabled = StoreWallet.balance() < int(bu["price"])
			b.pressed.connect(_on_buy_bundle.bind(str(bu["id"])))
			vb.add_child(b)


func _on_buy_bundle(bid: String) -> void:
	if StoreWallet.buy_bundle(bid):
		_msg.text = "✔ Bundle unlocked: " + str(StoreDefs.bundle_by_id(bid)["name"])
	else:
		_msg.text = "Could not buy bundle — insufficient NP or already owned."
	_refresh_tab()


# -------------------------------------------------------------------- np ---
func _tab_np() -> void:
	_note(_content_box, "NOVA Points are bought with REAL money via Flutterwave (secure checkout). NP buys mythic skins, draws and bundles.", 15, ORANGE)
	if _payments.mode() == Payments.TEST_MODE:
		_note(_content_box, "⚠ TEST MODE — no real money moves. Zenas must add real Flutterwave keys to go live.", 14, Color(1.0, 0.55, 0.3))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content_box.add_child(grid)
	for pack in StoreDefs.NP_PACKS:
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = CARD
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = Color(1.0, 0.65, 0.15, 0.6)
		p.add_theme_stylebox_override("panel", sb)
		grid.add_child(p)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		var m := MarginContainer.new()
		for mm in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			m.add_theme_constant_override(mm, 12)
		m.add_child(vb)
		p.add_child(m)
		var nm := Label.new()
		nm.text = "◈ %d NP" % int(pack["np"])
		nm.add_theme_font_size_override("font_size", 24)
		nm.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		vb.add_child(nm)
		var tn := Label.new()
		tn.text = str(pack["name"])
		tn.add_theme_font_size_override("font_size", 14)
		tn.add_theme_color_override("font_color", MUTED)
		vb.add_child(tn)
		if str(pack["bonus"]) != "":
			var bn := Label.new()
			bn.text = str(pack["bonus"])
			bn.add_theme_font_size_override("font_size", 14)
			bn.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
			vb.add_child(bn)
		var pr := Label.new()
		pr.text = "₦%s  ·  $%.2f" % [_fmt_naira(int(pack["ngn"])), float(pack["usd"])]
		pr.add_theme_font_size_override("font_size", 18)
		pr.add_theme_color_override("font_color", Color.WHITE)
		vb.add_child(pr)
		var b := Button.new()
		b.text = "BUY"
		b.custom_minimum_size = Vector2(180, 46)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", ORANGE)
		b.pressed.connect(_on_buy_np.bind(str(pack["id"])))
		vb.add_child(b)


func _fmt_naira(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _on_buy_np(pid: String) -> void:
	_msg.text = "Opening secure checkout…"
	_payments.purchase_np_pack(pid)


func _on_purchase_completed(pack_id: String, np: int, tx_ref: String) -> void:
	_msg.text = "✔ +%d NP added! (receipt %s)" % [np, tx_ref]
	_refresh_tab()


func _on_purchase_failed(pack_id: String, reason: String) -> void:
	_msg.text = "Purchase failed: " + reason + " — no charge made."
	_refresh_tab()


# ---------------------------------------------------------------- locked ---
func _tab_locked() -> void:
	var tab := {}
	for t in StoreDefs.TABS:
		if str(t["id"]) == _sel_tab:
			tab = t
	var vb := _card(str(tab.get("name", "")), MUTED)
	var l := Label.new()
	l.text = "🔒\n" + str(tab.get("lock_note", "COMING SOON"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", MUTED)
	vb.add_child(l)
