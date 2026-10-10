extends SceneTree
## NOVA store + NOVA Points verification.
## Usage: Godot_v4.3-stable_linux.x86_64 --headless --path <project> --script res://tests/test_store.gd
## Checks: NP pack catalog, wallet math + persistence, draw odds/pool/guarantee,
## bundle pricing, Payments TEST mode (mocked — NO real charges ever),
## mythic ownership wiring into the gunsmith, store UI builds.

var _checks: Array = []
var _frame := 0
var _phase := 0
var _pay_ok := false
var _pay_np := 0
var _pay_tx := ""
var _pay_fail_reason := ""


func _log_check(cname: String, ok: bool, detail := "") -> void:
	_checks.append([cname, ok])
	print(("PASS" if ok else "FAIL"), " | ", cname, (" | " + detail) if detail != "" else "")


func _initialize() -> void:
	StoreWallet._reset_for_test()
	_run_static_checks()
	_run_wallet_checks()
	_run_draw_checks()
	_run_bundle_checks()
	_run_payment_checks()
	print("TEST: store checks starting (UI phase)")


func _run_static_checks() -> void:
	_log_check("7 store tabs", StoreDefs.TABS.size() == 7, "n=" + str(StoreDefs.TABS.size()))
	var ids := {}
	for t in StoreDefs.TABS:
		ids[str(t["id"])] = true
	for need in ["featured", "draws", "skins", "bundles", "characters", "pass", "np"]:
		_log_check("tab " + need, ids.has(need))
	_log_check("characters tab locked", StoreDefs.TABS[4]["locked"] == true)
	_log_check("battle pass tab locked", StoreDefs.TABS[5]["locked"] == true)
	_log_check("5 NP packs", StoreDefs.NP_PACKS.size() == 5)
	var pids := {}
	var ok := true
	for p in StoreDefs.NP_PACKS:
		if pids.has(str(p["id"])) or int(p["np"]) <= 0 or int(p["ngn"]) <= 0 or float(p["usd"]) <= 0.0:
			ok = false
		pids[str(p["id"])] = true
	_log_check("NP packs valid (unique ids, +NGN, +USD)", ok)
	var odds_sum := 0.0
	for k in StoreDefs.DRAW_ODDS.keys():
		odds_sum += float(StoreDefs.DRAW_ODDS[k])
	_log_check("draw odds sum ~1.0", abs(odds_sum - 1.0) < 0.001, "sum=%.3f" % odds_sum)
	for d in StoreDefs.DRAWS:
		_log_check("draw 10 items: " + str(d["id"]), (d["items"] as Array).size() == 10)
		var top := StoreDefs.draw_top_prize(str(d["id"]))
		_log_check("draw top prize mythic: " + str(d["id"]), str(top.get("kind", "")) == "mythic")
		var lbl := StoreDefs.item_label(top)
		_log_check("mythic label from catalog: " + str(d["id"]), lbl.begins_with("MYTHIC: ") and lbl.length() > 10, lbl)
	_log_check("full draw cost 4050", StoreDefs.draw_full_cost() == 4050)
	_log_check("3 bundles priced", StoreDefs.BUNDLES.size() == 3)
	for b in StoreDefs.BUNDLES:
		_log_check("bundle skin real: " + str(b["id"]),
			MythicSkins.skin_display_name(str(b["gun"]), int(b["skin_idx"])) != "")
	_log_check("24 skin offers", StoreDefs.SKIN_OFFERS.size() == 24)
	var sok := true
	for o in StoreDefs.SKIN_OFFERS:
		if MythicSkins.skin_display_name(str(o["gun"]), int(o["skin_idx"])) == "":
			sok = false
	_log_check("all skin offers map to real catalog skins", sok)


func _run_wallet_checks() -> void:
	_log_check("starts at 0", StoreWallet.balance() == 0)
	_log_check("add 500", StoreWallet.add_np(500, "test") == 500)
	_log_check("spend 200 ok", StoreWallet.spend_np(200, "test") == true)
	_log_check("balance 300", StoreWallet.balance() == 300)
	_log_check("overspend refused", StoreWallet.spend_np(99999, "test") == false)
	_log_check("balance unchanged after refused spend", StoreWallet.balance() == 300)
	_log_check("negative add ignored", StoreWallet.add_np(-50, "test") == 300)
	# persistence: grant + save, then reload from disk
	StoreWallet.add_np(700, "test persist")
	StoreWallet.grant_skin("m5", 1, "test persist")
	StoreWallet._loaded = false  # force reload from disk
	_log_check("balance persists", StoreWallet.balance() == 1000, "bal=" + str(StoreWallet.balance()))
	_log_check("skin ownership persists", StoreWallet.owns_skin("m5", 1))
	_log_check("standard look free", StoreWallet.owns_skin("m5", 0))
	_log_check("ledger has entries", StoreWallet.ledger().size() >= 3, "n=" + str(StoreWallet.ledger().size()))
	var last: Dictionary = StoreWallet.ledger().back()
	_log_check("ledger receipt fields", last.has("t") and last.has("kind") and last.has("balance"))


func _run_draw_checks() -> void:
	_log_check("spin costs escalate", LuckyDraw.spin_cost(0) == 30 and LuckyDraw.spin_cost(9) == 1020)
	_log_check("spin cost out of range", LuckyDraw.spin_cost(10) == -1)
	var draw := StoreDefs.draw_by_id("draw_dragonfire")
	_log_check("pool 10 fresh", LuckyDraw.pool(draw, []).size() == 10)
	_log_check("pool shrinks with wins", LuckyDraw.pool(draw, [0, 3]).size() == 8)
	# insufficient NP spin
	StoreWallet._reset_for_test()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var r := LuckyDraw.spin("draw_dragonfire", [], rng)
	_log_check("broke spin refused", not bool(r.get("ok", true)) and str(r.get("reason", "")) == "insufficient NP")
	# full draws always win the mythic (guarantee), exact full cost spent
	var allok := true
	for seed in [1, 7, 42, 1234, 99999]:
		StoreWallet._reset_for_test()
		StoreWallet.add_np(10000, "test draw")
		var sim := LuckyDraw.simulate_full_draw("draw_dragonfire", seed)
		var myth: Dictionary = sim.get("mythic", {})
		var bal: int = StoreWallet.balance()
		if sim.has("error") or myth.is_empty() or str(myth.get("kind", "")) != "mythic" or bal != 10000 - 4050:
			allok = false
	_log_check("10 spins always win mythic, cost exactly 4050", allok)
	# owned items removed from pool: mythic pre-owned -> still winnable set, no dupes
	StoreWallet._reset_for_test()
	StoreWallet.add_np(10000, "test draw")
	StoreWallet.grant_skin("kv47", 1, "test pre-owned")
	var draw2 := StoreDefs.draw_by_id("draw_dragonfire")
	var won: Array = [0]  # treat the mythic slot as already claimed
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var r2 := LuckyDraw.spin("draw_dragonfire", won, rng2)
	_log_check("owned slot skipped in pool", bool(r2.get("ok", false)) and int(r2.get("won_idx", -1)) != 0)


func _run_bundle_checks() -> void:
	StoreWallet._reset_for_test()
	_log_check("broke bundle refused", StoreWallet.buy_bundle("bundle_dragonfire") == false)
	StoreWallet.add_np(2000, "test bundle")
	_log_check("bundle buys", StoreWallet.buy_bundle("bundle_dragonfire") == true)
	_log_check("bundle price 1500 deducted", StoreWallet.balance() == 500)
	_log_check("bundle skin granted", StoreWallet.owns_skin("kv47", 1))
	_log_check("bundle flair granted", StoreWallet.owns_flair("DRAGONFIRE ARSENAL Operator Card"))
	_log_check("bundle ownership flagged", StoreWallet.owns_bundle("bundle_dragonfire"))
	_log_check("duplicate bundle refused", StoreWallet.buy_bundle("bundle_dragonfire") == false)
	# direct skin buy
	StoreWallet.add_np(1000, "test skin")
	_log_check("skin buys at 950", StoreWallet.buy_skin("lw9", 1) == true)
	_log_check("skin price deducted", StoreWallet.balance() == 550)
	_log_check("duplicate skin refused", StoreWallet.buy_skin("lw9", 1) == false)


func _run_payment_checks() -> void:
	var pay := Payments.new()
	_log_check("payments default to TEST mode", pay.mode() == Payments.TEST_MODE)
	_log_check("placeholder keys not real", "xxxx" in Payments.PLACEHOLDER_PUBLIC)
	pay.purchase_completed.connect(_on_pc)
	pay.purchase_failed.connect(_on_pf)
	# success path
	StoreWallet._reset_for_test()
	pay.set_simulated_result("success")
	pay.purchase_np_pack("np_500")
	_log_check("test purchase credits NP", _pay_ok and _pay_np == 500 and StoreWallet.balance() == 500,
		"np=%d tx=%s" % [_pay_np, _pay_tx])
	_log_check("receipt in ledger", StoreWallet.ledger().back()["detail"].begins_with("np pack:np_500 tx:TEST-"))
	# cancel path: no credit
	_pay_ok = false
	pay.set_simulated_result("cancel")
	pay.purchase_np_pack("np_100")
	_log_check("cancel credits nothing", not _pay_ok and StoreWallet.balance() == 500)
	_log_check("cancel reason surfaced", _pay_fail_reason == "user cancelled")
	# declined path: no credit
	pay.set_simulated_result("fail")
	pay.purchase_np_pack("np_100")
	_log_check("decline credits nothing", StoreWallet.balance() == 500)
	# unknown pack
	pay.set_simulated_result("success")
	pay.purchase_np_pack("np_nope")
	_log_check("unknown pack fails", _pay_fail_reason == "unknown pack" and not _pay_ok)


func _on_pc(pack_id: String, np: int, tx_ref: String) -> void:
	_pay_ok = true
	_pay_np = np
	_pay_tx = tx_ref
	_pay_fail_reason = ""


func _on_pf(_pack_id: String, reason: String) -> void:
	_pay_ok = false
	_pay_fail_reason = reason


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5 and _phase == 0:
		_run_ui_checks()
		_phase = 1
	if _frame == 12 and _phase == 1:
		_run_gunsmith_checks()
		_phase = 2
	if _frame >= 20:
		_finish()
		return true
	return false


func _run_ui_checks() -> void:
	var store := StoreMenu.new()
	root.add_child(store)
	_log_check("store menu builds", store.get_child_count() > 0)
	var tabs_ok := store._tab_row != null and store._tab_row.get_child_count() == 7
	_log_check("7 tab buttons built", tabs_ok)
	# NP tab: 5 pack cards with buy buttons
	store._select_tab("np")
	var buys := _count_buy_buttons(store._content_box)
	_log_check("5 NP pack buy buttons", buys == 5, "n=" + str(buys))
	# skins tab: 24 offers -> 24 buy buttons (fresh wallet, nothing owned)
	store._select_tab("skins")
	var sb := _count_buy_buttons(store._content_box)
	_log_check("24 skin buy buttons", sb == 24, "n=" + str(sb))
	# draws tab: 10 slot labels + spin button
	store._select_tab("draws")
	var spin_b := _count_buy_buttons(store._content_box)
	_log_check("draw spin button present", spin_b >= 1, "n=" + str(spin_b))
	# locked tabs show COMING SOON, not purchasables
	store._select_tab("characters")
	var cb := _count_buy_buttons(store._content_box)
	_log_check("characters tab locked, no buy buttons", cb == 0)
	store.queue_free()


func _count_buy_buttons(n: Node) -> int:
	var c := 0
	if n is Button and (str((n as Button).text).begins_with("BUY") or str((n as Button).text).begins_with("SPIN")):
		c += 1
	for ch in n.get_children():
		c += _count_buy_buttons(ch)
	return c


func _run_gunsmith_checks() -> void:
	StoreWallet._reset_for_test()
	var gs := GunsmithMenu.new()
	root.add_child(gs)
	# pick a gun, try to select a locked mythic skin -> refused
	gs._on_gun_pick("m5")
	gs._on_skin_pick(1)
	_log_check("locked mythic refused in gunsmith", gs._sel_skin == 0)
	# buy it in the store, then it equips
	StoreWallet.add_np(2000, "test gs")
	_log_check("store buy unlocks", StoreWallet.buy_skin("m5", 1))
	gs._on_skin_pick(1)
	_log_check("owned mythic equips in gunsmith", gs._sel_skin == 1)
	# standard look always selectable
	gs._on_skin_pick(0)
	_log_check("standard look selectable", gs._sel_skin == 0)
	gs.queue_free()
	StoreWallet._reset_for_test()


func _finish() -> void:
	var fails := 0
	for c in _checks:
		if not c[1]:
			fails += 1
	print("STORE: ", _checks.size() - fails, "/", _checks.size(), " checks passed")
	if fails > 0:
		print("STORE: FAILURES PRESENT")
	quit()
