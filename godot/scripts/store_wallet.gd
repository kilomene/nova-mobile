class_name StoreWallet
extends RefCounted
## NOVA Points wallet: persisted NP balance, mythic skin ownership, and a
## full transaction ledger (every earn/spend with receipts).
##
## Saved to user://nova_wallet.json so balances survive app restarts.
## Skins are the premium goods: key format "gun_id:skin_idx" (skin_idx >= 1).
## The STANDARD (unskinned) look is always free.

const SAVE_PATH := "user://nova_wallet.json"
const VERSION := 1

static var _np := 0
static var _owned_skins := {}   # "gun:idx" -> true
static var _owned_flair := {}   # flair label -> true (draw filler items)
static var _owned_bundles := {} # bundle id -> true
static var _draws := {}         # draw_id -> {"spins": int, "won": [idx]}
static var _ledger: Array = []
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	if int(parsed.get("version", 0)) != VERSION:
		return  # old schema: start fresh rather than misread
	_np = maxi(0, int(parsed.get("np", 0)))
	for k in parsed.get("owned_skins", []):
		_owned_skins[str(k)] = true
	for k in parsed.get("owned_flair", []):
		_owned_flair[str(k)] = true
	for k in parsed.get("owned_bundles", []):
		_owned_bundles[str(k)] = true
	if parsed.get("draws") is Dictionary:
		_draws = parsed["draws"]
	if parsed.get("ledger") is Array:
		_ledger = parsed["ledger"]


static func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var d := {
		"version": VERSION, "np": _np,
		"owned_skins": _owned_skins.keys(),
		"owned_flair": _owned_flair.keys(),
		"owned_bundles": _owned_bundles.keys(),
		"draws": _draws,
		"ledger": _ledger.slice(maxi(0, _ledger.size() - 200)),
	}
	f.store_string(JSON.stringify(d, "\t"))
	f.close()


static func _log(kind: String, np_delta: int, detail: String) -> void:
	_ledger.append({
		"t": Time.get_unix_time_from_system(), "kind": kind,
		"np_delta": np_delta, "balance": _np, "detail": detail,
	})
	_save()


## For tests only: wipe in-memory + disk state.
static func _reset_for_test() -> void:
	_np = 0
	_owned_skins.clear()
	_owned_flair.clear()
	_owned_bundles.clear()
	_ledger.clear()
	_loaded = true
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func balance() -> int:
	_ensure_loaded()
	return _np


## Grant NP (purchase, promo, compensation). Returns the new balance.
static func add_np(amount: int, reason: String) -> int:
	_ensure_loaded()
	if amount <= 0:
		return _np
	_np += amount
	_log("earn", amount, reason)
	return _np


## Spend NP. Returns true on success, false when funds are insufficient
## (no partial spend, no negative balances).
static func spend_np(amount: int, reason: String) -> bool:
	_ensure_loaded()
	if amount <= 0:
		return true
	if _np < amount:
		return false
	_np -= amount
	_log("spend", -amount, reason)
	return _np >= 0


static func _skin_key(gun_id: String, skin_idx: int) -> String:
	return "%s:%d" % [gun_id, skin_idx]


static func owns_skin(gun_id: String, skin_idx: int) -> bool:
	_ensure_loaded()
	if skin_idx <= 0:
		return true  # standard look is free
	return _owned_skins.has(_skin_key(gun_id, skin_idx))


static func grant_skin(gun_id: String, skin_idx: int, reason: String) -> void:
	_ensure_loaded()
	var k := _skin_key(gun_id, skin_idx)
	if _owned_skins.has(k):
		return
	_owned_skins[k] = true
	_log("skin", 0, "%s | %s" % [reason, k])


static func owns_flair(label: String) -> bool:
	_ensure_loaded()
	return _owned_flair.has(label)


static func grant_flair(label: String, reason: String) -> void:
	_ensure_loaded()
	if _owned_flair.has(label):
		return
	_owned_flair[label] = true
	_log("flair", 0, "%s | %s" % [reason, label])


static func owns_bundle(bid: String) -> bool:
	_ensure_loaded()
	return _owned_bundles.has(bid)


static func grant_bundle(bid: String, reason: String) -> void:
	_ensure_loaded()
	if _owned_bundles.has(bid):
		return
	_owned_bundles[bid] = true
	_log("bundle", 0, "%s | %s" % [reason, bid])


## Buy a mythic skin directly (950 NP). False = already owned or broke.
static func buy_skin(gun_id: String, skin_idx: int) -> bool:
	_ensure_loaded()
	if owns_skin(gun_id, skin_idx):
		return false
	if not spend_np(StoreDefs.MYTHIC_PRICE, "skin:" + _skin_key(gun_id, skin_idx)):
		return false
	grant_skin(gun_id, skin_idx, "store purchase")
	return true


## Buy a bundle (skin + cards + frame). False = already owned or broke.
static func buy_bundle(bid: String) -> bool:
	_ensure_loaded()
	var b := StoreDefs.bundle_by_id(bid)
	if b.is_empty() or owns_bundle(bid):
		return false
	if not spend_np(int(b["price"]), "bundle:" + bid):
		return false
	grant_bundle(bid, "store purchase")
	grant_skin(str(b["gun"]), int(b["skin_idx"]), "bundle:" + bid)
	grant_flair(str(b["name"]) + " Operator Card", "bundle:" + bid)
	grant_flair(str(b["name"]) + " Calling Card", "bundle:" + bid)
	grant_flair(str(b["name"]) + " Avatar Frame", "bundle:" + bid)
	return true


static func ledger() -> Array:
	_ensure_loaded()
	return _ledger.duplicate()


## Lucky draw progress: spins used + item indices won (persisted).
static func draw_state(did: String) -> Dictionary:
	_ensure_loaded()
	if not _draws.has(did):
		_draws[did] = {"spins": 0, "won": []}
	return _draws[did]


static func record_draw_win(did: String, won_idx: int) -> void:
	_ensure_loaded()
	var st := draw_state(did)
	st["spins"] = int(st["spins"]) + 1
	(st["won"] as Array).append(won_idx)
	_save()
