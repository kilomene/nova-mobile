class_name Payments
extends RefCounted
## Flutterwave payment module — buys NOVA Points with REAL money.
##
## Interface:  Payments.purchase_np_pack(pack_id) -> starts checkout
##             (signals / callbacks deliver purchase_completed / purchase_failed)
##
## MODES:
##  - "test":  fully simulated checkout. NO real money moves, NO network
##             calls. Used in-game until Zenas provides live keys AND chooses
##             the distribution channel. This is the default.
##  - "live":  real Flutterwave checkout. The game NEVER holds the secret key
##             (it would ship inside the APK). Instead the game asks the NOVA
##             payments backend (server/nova_payments_server.py, holds the
##             secret key as an env var) for a hosted checkout link, opens it
##             in the OS browser, then polls the backend to verify payment
##             before crediting NP. Requires in user://flutterwave_config.json:
##             {"mode": "live", "backend_url": "https://your-host:8777"}
##
## KEYS ARE NEVER HARDCODED. No secret key is stored in the game, ever.
## In test mode the file may say {"mode": "test"} or not exist at all.
##
## DISTRIBUTION FLAG (for Zenas): Google Play requires Google Play Billing
## for digital goods inside Play-distributed apps — Flutterwave fits a
## direct-download APK (own site / sideload) or a web store instead.

signal purchase_completed(pack_id: String, np: int, tx_ref: String)
signal purchase_failed(pack_id: String, reason: String)

const CONFIG_PATH := "user://flutterwave_config.json"
const TEST_MODE := "test"
const LIVE_MODE := "live"

# Placeholder-shaped defaults — NOT real keys, never usable for charges.
const PLACEHOLDER_PUBLIC := "FLWPUBK_TEST-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-X"
const PLACEHOLDER_SECRET := "FLWSECK_TEST-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

var _mode := TEST_MODE
var _backend_url := ""
var _simulate_result := "success"  # test hook: success | fail | cancel
var _pending_pack := ""
var _pending_tx_ref := ""
var _http: HTTPRequest  # created lazily; only used in live mode
var _http_host: Node = null  # set via attach_http() by the store UI


static func config_template() -> Dictionary:
	return {
		"mode": "test",
		"backend_url": "https://your-host:8777",
		"note": "Live mode needs the NOVA payments backend (server/nova_payments_server.py) hosted with FLW_SECRET_KEY set. The game never stores the secret key.",
	}


func _init() -> void:
	_load_config()


func _load_config() -> void:
	_mode = TEST_MODE
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	if str(parsed.get("mode", "test")) == LIVE_MODE:
		var backend := str(parsed.get("backend_url", ""))
		# Refuse to go live without a real backend URL — accident guard.
		if backend != "" and "your-host" not in backend and backend.begins_with("https://"):
			_mode = LIVE_MODE
			_backend_url = backend


func mode() -> String:
	return _mode


## Test hook: force the next simulated checkout to succeed/fail/cancel.
func set_simulated_result(r: String) -> void:
	_simulate_result = r


## Start buying an NP pack. In test mode this runs a simulated checkout
## (instant, no network). In live mode it would open the Flutterwave
## Standard checkout and verify the transaction server-side.
func purchase_np_pack(pack_id: String) -> void:
	var pack := StoreDefs.np_pack_by_id(pack_id)
	if pack.is_empty():
		purchase_failed.emit(pack_id, "unknown pack")
		return
	_pending_pack = pack_id
	if _mode == TEST_MODE:
		_simulate_checkout(pack)
	else:
		_live_checkout(pack)


## --- TEST checkout: no network, no money, deterministic outcomes. ---
func _simulate_checkout(pack: Dictionary) -> void:
	var tx_ref := "TEST-%s-%d" % [str(pack["id"]), int(Time.get_unix_time_from_system())]
	match _simulate_result:
		"success":
			_verify_and_credit(str(pack["id"]), tx_ref, true)
		"cancel":
			purchase_failed.emit(str(pack["id"]), "user cancelled")
		_:
			purchase_failed.emit(str(pack["id"]), "payment declined (test)")


## --- LIVE checkout: backend creates the Flutterwave hosted link, the OS
## browser opens it, then we poll the backend until it confirms payment. ---
func _live_checkout(pack: Dictionary) -> void:
	if _backend_url == "":
		purchase_failed.emit(str(pack["id"]), "live backend not configured")
		return
	_ensure_http()
	var body := JSON.stringify({
		"pack_id": str(pack["id"]),
		"currency": "NGN",
		"redirect_url": "https://example.com/nova-purchase-done",
		"email": "",
	})
	var err := _http.request(_backend_url + "/create-link",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		purchase_failed.emit(str(pack["id"]), "could not reach payment backend")
		return
	# Response handled in _on_link_response (bound per-request below).
	_http.request_completed.connect(_on_link_response, CONNECT_ONE_SHOT)


func _ensure_http() -> void:
	if _http == null:
		_http = HTTPRequest.new()
		if _http_host != null:
			_http_host.add_child(_http)


## The store UI calls this after Payments.new() so live-mode HTTP works.
## (Payments is RefCounted and cannot parent nodes itself.)
func attach_http(host: Node) -> void:
	_http_host = host
	if _http != null and _http.get_parent() == null:
		_http_host.add_child(_http)


func _on_link_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		purchase_failed.emit(_pending_pack, "payment link failed")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or parsed.get("link", "") == "":
		purchase_failed.emit(_pending_pack, str(parsed.get("error", "payment link failed")))
		return
	_pending_tx_ref = str(parsed.get("tx_ref", ""))
	# Open the hosted Flutterwave checkout in the OS browser.
	OS.shell_open(str(parsed["link"]))
	# Poll the backend for confirmation (player pays in the browser).
	_poll_verify(0)


func _poll_verify(attempt: int) -> void:
	if attempt >= 40:  # ~10 minutes of polling, then give up
		purchase_failed.emit(_pending_pack, "payment not confirmed in time")
		return
	_ensure_http()
	var url := _backend_url + "/verify?tx_ref=" + _pending_tx_ref.uri_encode()
	var err := _http.request(url)
	if err != OK:
		purchase_failed.emit(_pending_pack, "could not reach payment backend")
		return
	_http.request_completed.connect(_on_verify_response.bind(attempt), CONNECT_ONE_SHOT)


func _on_verify_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, attempt: int) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary and bool(parsed.get("paid", false)):
			_verify_and_credit(_pending_pack, _pending_tx_ref, true)
			return
	# Not paid yet — wait 15s and poll again.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(15.0).timeout
		_poll_verify(attempt + 1)
	else:
		purchase_failed.emit(_pending_pack, "payment not confirmed")


func _verify_and_credit(pack_id: String, tx_ref: String, verified: bool) -> void:
	if not verified:
		purchase_failed.emit(pack_id, "verification failed")
		return
	var pack := StoreDefs.np_pack_by_id(pack_id)
	if pack.is_empty():
		purchase_failed.emit(pack_id, "unknown pack")
		return
	var np := int(pack["np"])
	StoreWallet.add_np(np, "np pack:%s tx:%s mode:%s" % [pack_id, tx_ref, _mode])
	purchase_completed.emit(pack_id, np, tx_ref)
