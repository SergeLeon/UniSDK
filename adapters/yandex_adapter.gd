@tool
class_name YandexAdapter
extends PlatformAdapter

const AD_TIMEOUT_MS: int = 75000
const LATE_REWARD_WINDOW_MS: int = 2000
const TAG := "yandex"
const MAX_SET_DATA_BYTES: int = 200_000

var _cached_environment: Dictionary = {}
var _cached_device: Dictionary = {}
var _cached_player: Dictionary = {}
var _player_initialized: bool = false
var _last_leaderboard_write_ms: int = 0
const LEADERBOARD_MIN_INTERVAL_MS: int = 1000

func _init(core: Node) -> void:
	super._init(core)

func get_bridge_name() -> String:
	return "GodotYandexBridge"

# --- Lifecycle ---
func init(options: Dictionary = {}) -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("init", [JSON.stringify(options)])
	else:
		res = _core.mock_bridge.init(options)

	if not res.get("success", false):
		return false

	var data: Dictionary = res.get("data", {})
	_cached_environment = data.get("environment", {})
	_cached_device = data.get("device", {})
	sdk_initialized.emit(data)
	return true

func game_ready() -> void:
	if is_web():
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface(get_bridge_name())
		if bridge:
			bridge.loadingReady()
	else:
		_core.mock_bridge.loading_ready()

func gameplay_start() -> void:
	if is_web():
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface(get_bridge_name())
		if bridge:
			bridge.gameplayStart()
	else:
		_core.mock_bridge.gameplay_start()

func gameplay_stop() -> void:
	if is_web():
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface(get_bridge_name())
		if bridge:
			bridge.gameplayStop()
	else:
		_core.mock_bridge.gameplay_stop()

func get_server_time() -> int:
	if is_web():
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface(get_bridge_name())
		if bridge:
			return int(bridge.serverTime())
		return int(Time.get_unix_time_from_system() * 1000.0)
	return _core.mock_bridge.server_time()

func is_available_method(method_name: String) -> bool:
	if is_web():
		var res: Dictionary = await call_js_async("isAvailableMethod", [method_name])
		return res.get("available", false)
	return _core.mock_bridge.is_available_method(method_name)

func dispatch_event(event_name: String, detail: Dictionary = {}) -> bool:
	if is_web():
		var detail_json: String = JSON.stringify(detail) if not detail.is_empty() else ""
		var res: Dictionary = await call_js_async("dispatchEvent", [event_name, detail_json])
		return res.get("success", false)
	return _core.mock_bridge.dispatch_event(event_name, detail).get("success", false)

func dispatch_exit() -> void:
	if is_web():
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface(get_bridge_name())
		if bridge:
			var cb: JavaScriptObject = JavaScriptBridge.create_callback(func(_args): pass)
			_core._active_js_callbacks.append(cb)
			bridge.dispatchExit(cb)
	else:
		_core.mock_bridge.exit()

# --- Ads ---
func show_interstitial() -> Dictionary:
	if not is_web():
		return await _mock_show_interstitial()
	return await _web_show_interstitial()

func _web_show_interstitial() -> Dictionary:
	var result: Dictionary = { "success": false, "was_shown": false, "error": "" }
	var cb_data: Dictionary = await call_js_async("showFullscreenAdv")
	var event: String = str(cb_data.get("event", "")).to_lower()
	var close_received: bool = false
	var error_received: bool = false
	var timed_out: bool = false
	var was_shown: bool = false

	match event:
		"open", "onopen": pass
		"close", "onclose":
			was_shown = cb_data.get("wasShown", false)
			close_received = true
		"offline":
			result.error = "Offline"
			error_received = true
		"error", "onerror":
			result.error = str(cb_data.get("error", "Ad error"))
			error_received = true

	var start: int = Time.get_ticks_msec()
	while not close_received and not error_received:
		var next: Dictionary = await _core._wait_for_next_ad_event(75.0)
		var ev: String = str(next.get("event", "")).to_lower()
		match ev:
			"close", "onclose":
				was_shown = next.get("wasShown", false)
				close_received = true
			"offline":
				result.error = "Offline"
				error_received = true
			"error", "onerror":
				result.error = str(next.get("error", "Ad error"))
				error_received = true
		if (Time.get_ticks_msec() - start) > AD_TIMEOUT_MS:
			result.error = "Timeout waiting for close"
			timed_out = true
			break

	result.success = close_received and not timed_out
	result.was_shown = was_shown
	_core._clear_ad_event_queue()
	return result

func _mock_show_interstitial() -> Dictionary:
	var result: Dictionary = { "success": false, "was_shown": false, "error": "" }
	var mock_cb: Callable = func(payload: Dictionary) -> void:
		var ev: String = str(payload.get("event", "")).to_lower()
		match ev:
			"close", "onclose":
				result.success = true
				result.was_shown = payload.get("wasShown", false)
			"error", "onerror":
				result.error = str(payload.get("error", "Ad error"))
	await _core.mock_bridge.show_fullscreen_adv(mock_cb)
	return result

func show_rewarded() -> Dictionary:
	if not is_web():
		return await _mock_show_rewarded()
	return await _web_show_rewarded()

func _web_show_rewarded() -> Dictionary:
	var result: Dictionary = { "success": false, "rewarded": false, "was_shown": false, "error": "" }
	var got_reward: bool = false
	var was_shown: bool = false
	var close_received: bool = false
	var error_received: bool = false
	var timed_out: bool = false

	var cb_data: Dictionary = await call_js_async("showRewardedVideo")
	var event: String = str(cb_data.get("event", "")).to_lower()

	match event:
		"open", "onopen": pass
		"rewarded", "reward", "onrewarded": got_reward = true
		"close", "onclose":
			was_shown = cb_data.get("wasShown", true)
			close_received = true
		"error", "onerror":
			result.error = str(cb_data.get("error", "Ad error"))
			error_received = true

	var start: int = Time.get_ticks_msec()
	while not close_received and not error_received:
		var next: Dictionary = await _core._wait_for_next_ad_event(75.0)
		var ev: String = str(next.get("event", "")).to_lower()
		match ev:
			"rewarded", "reward", "onrewarded": got_reward = true
			"close", "onclose":
				was_shown = next.get("wasShown", true)
				close_received = true
			"error", "onerror":
				result.error = str(next.get("error", "Ad error"))
				error_received = true
		if (Time.get_ticks_msec() - start) > AD_TIMEOUT_MS:
			result.error = "Timeout waiting for close"
			timed_out = true
			break

	if close_received and not got_reward and not timed_out:
		var extra_start: int = Time.get_ticks_msec()
		while not got_reward and (Time.get_ticks_msec() - extra_start) < LATE_REWARD_WINDOW_MS:
			if not _core._ad_event_queue.is_empty():
				var late: Dictionary = _core._ad_event_queue.pop_front()
				var late_ev: String = str(late.get("event", "")).to_lower()
				if late_ev in ["rewarded", "reward", "onrewarded"]:
					got_reward = true
					break
			await _core.get_tree().process_frame

	result.success = close_received and not timed_out
	result.rewarded = got_reward
	result.was_shown = was_shown
	_core._clear_ad_event_queue()
	return result

func _mock_show_rewarded() -> Dictionary:
	var result: Dictionary = { "success": false, "rewarded": false, "was_shown": false, "error": "" }
	var state: Dictionary = { "got_reward": false, "was_shown": false }
	var mock_cb: Callable = func(payload: Dictionary) -> void:
		var ev: String = str(payload.get("event", "")).to_lower()
		match ev:
			"rewarded", "reward", "onrewarded": state.got_reward = true
			"close", "onclose": state.was_shown = payload.get("wasShown", true)
	await _core.mock_bridge.show_rewarded_video(mock_cb)
	result.success = true
	result.rewarded = state.got_reward
	result.was_shown = state.was_shown
	return result

func show_banner() -> Dictionary:
	if is_web():
		return await call_js_async("showBannerAdv")
	return _core.mock_bridge.show_banner_adv()

func hide_banner() -> Dictionary:
	if is_web():
		return await call_js_async("hideBannerAdv")
	return _core.mock_bridge.hide_banner_adv()

func get_banner_status() -> Dictionary:
	if is_web():
		return await call_js_async("getBannerAdvStatus")
	return _core.mock_bridge.get_banner_adv_status()

# --- Player ---
func init_player(options: Dictionary = {}) -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("initPlayer", [JSON.stringify(options)])
		_cached_player = res.get("data", {}) if res.get("success", false) else {}
	else:
		res = _core.mock_bridge.init_player(options)
		_cached_player = res.get("data", {}) if res.get("success", false) else {}
	_player_initialized = res.get("success", false)
	return _cached_player

func is_authorized() -> bool:
	return bool(_cached_player.get("isAuthorized", false))

func get_player_id() -> String:
	return str(_cached_player.get("uniqueId", ""))

func get_player_name() -> String:
	return str(_cached_player.get("name", ""))

func get_player_photo(size: String = "medium") -> String:
	match size.to_lower():
		"small": return str(_cached_player.get("photoSmall", ""))
		"large": return str(_cached_player.get("photoLarge", ""))
		_: return str(_cached_player.get("photoMedium", ""))

func get_player_data(keys: Variant = null) -> Dictionary:
	var res: Dictionary
	if is_web():
		var keys_json: String = JSON.stringify(keys) if keys != null else ""
		res = await call_js_async("getPlayerData", [keys_json])
	else:
		res = _core.mock_bridge.get_player_data(keys)
	return res.get("data", {}) if res.get("success", false) else {}

func get_changed_keys() -> Array:
	if not is_web():
		return []
	var res: Dictionary = await call_js_async("getChangedKeys", [], 5.0)
	if not res.get("success", false):
		return []
	return res.get("changed", [])

func set_player_data(data: Dictionary, flush: bool = false) -> bool:
	var json_str: String = JSON.stringify(data)
	if json_str.length() > MAX_SET_DATA_BYTES:
		UniLogger.warn(TAG, "set_player_data payload exceeds 200KB limit")
	if is_web():
		var res: Dictionary = await call_js_async("setPlayerData", [json_str, flush])
		return res.get("success", false)
	return _core.mock_bridge.set_player_data(data, flush).get("success", false)

func get_player_stats(keys: Variant = null) -> Dictionary:
	var res: Dictionary
	if is_web():
		var keys_json: String = JSON.stringify(keys) if keys != null else ""
		res = await call_js_async("getPlayerStats", [keys_json])
	else:
		res = _core.mock_bridge.get_player_stats(keys)
	return res.get("data", {}) if res.get("success", false) else {}

func set_player_stats(stats: Dictionary) -> bool:
	if is_web():
		var res: Dictionary = await call_js_async("setPlayerStats", [JSON.stringify(stats)])
		return res.get("success", false)
	return _core.mock_bridge.set_player_stats(stats).get("success", false)

func increment_player_stats(increments: Dictionary) -> Dictionary:
	for k in increments:
		if not (increments[k] is int or increments[k] is float):
			UniLogger.warn(TAG, "increment_player_stats: non-numeric value for '%s'" % k)
			return {}
	var res: Dictionary
	if is_web():
		res = await call_js_async("incrementPlayerStats", [JSON.stringify(increments)])
	else:
		res = _core.mock_bridge.increment_player_stats(increments)
	return res.get("data", {}) if res.get("success", false) else {}

func open_auth_dialog() -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("openAuthDialog", [], 300.0)
		_cached_player = res.get("data", {}) if res.get("success", false) else {}
	else:
		res = await _core.mock_bridge.open_auth_dialog()
		_cached_player = res.get("data", {}) if res.get("success", false) else {}
	return _cached_player

# --- Leaderboards ---
func get_leaderboard_description(name: String) -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("getLeaderboardDescription", [name])
	else:
		res = _core.mock_bridge.get_leaderboard_description(name)
	return res.get("data", {}) if res.get("success", false) else {}

func set_leaderboard_score(name: String, score: int, extra_data: String = "") -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _last_leaderboard_write_ms < LEADERBOARD_MIN_INTERVAL_MS:
		UniLogger.warn(TAG, "set_leaderboard_score throttled (1 req/sec)")
		return false
	_last_leaderboard_write_ms = now

	if is_web():
		if not bool(await is_available_method("leaderboards.setScore")):
			UniLogger.warn(TAG, "leaderboards.setScore unavailable")
			return false
		var res: Dictionary = await call_js_async("setLeaderboardScore", [name, score, extra_data])
		return res.get("success", false)
	return _core.mock_bridge.set_leaderboard_score(name, score, extra_data).get("success", false)

func get_leaderboard_player_entry(name: String) -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("getLeaderboardPlayerEntry", [name])
	else:
		res = _core.mock_bridge.get_leaderboard_player_entry(name)
	return res.get("data", {}) if res.get("success", false) else {}

func get_leaderboard_entries(name: String, options: Dictionary = {}) -> Dictionary:
	var opts := options.duplicate()
	if opts.has("quantityTop"):
		opts["quantityTop"] = clampi(int(opts["quantityTop"]), 1, 20)
	if opts.has("quantityAround"):
		opts["quantityAround"] = clampi(int(opts["quantityAround"]), 1, 10)
	var res: Dictionary
	if is_web():
		res = await call_js_async("getLeaderboardEntries", [name, JSON.stringify(opts)])
	else:
		res = _core.mock_bridge.get_leaderboard_entries(name, opts)
	return res.get("data", {}) if res.get("success", false) else {}

# --- Payments ---
func init_payments(options: Dictionary = {}) -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("initPayments", [JSON.stringify(options)])
	else:
		if _core.mock_bridge:
			_core.mock_bridge.is_signed = bool(options.get("signed", _core.mock_bridge.is_signed))
		res = { "success": true }
	return res.get("success", false)

func purchase(product_id: String, developer_payload: String = "") -> Dictionary:
	var res: Dictionary
	var options: Dictionary = { "id": product_id, "developerPayload": developer_payload }
	if is_web():
		res = await call_js_async("purchase", [JSON.stringify(options)], 300.0)
	else:
		res = _core.mock_bridge.purchase(options)
	return res.get("data", {}) if res.get("success", false) else {}

func get_purchases() -> Array:
	if is_web():
		var res: Dictionary = await call_js_async("getPurchases")
		return res.get("data", []) if res.get("success", false) else []
	return _core.mock_bridge.get_purchases()

func get_catalog() -> Array:
	if is_web():
		var res: Dictionary = await call_js_async("getCatalog")
		return res.get("data", []) if res.get("success", false) else []
	return _core.mock_bridge.get_catalog()

func consume_purchase(purchase_token: String) -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("consumePurchase", [purchase_token])
	else:
		res = _core.mock_bridge.consume_purchase(purchase_token)
	return res.get("success", false)

# --- Storage ---
func storage_get(key: String, default_value: String = "") -> String:
	if is_web():
		var res: Dictionary = await call_js_async("getStorageItem", [key])
		if res.get("success", false) and res.get("value") != null:
			return str(res.get("value"))
		return default_value
	var config: ConfigFile = ConfigFile.new()
	if config.load("user://yandex_safe_storage.cfg") == OK:
		return str(config.get_value("storage", key, default_value))
	return default_value

func storage_set(key: String, value: String) -> bool:
	if is_web():
		var res: Dictionary = await call_js_async("setStorageItem", [key, value])
		return res.get("success", false)
	var config: ConfigFile = ConfigFile.new()
	config.load("user://yandex_safe_storage.cfg")
	config.set_value("storage", key, value)
	return config.save("user://yandex_safe_storage.cfg") == OK

# --- Feedback ---
func can_review() -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("canReview")
	else:
		res = _core.mock_bridge.can_review()
	return res.get("data", { "value": false, "reason": "UNKNOWN" }) if res.get("success", false) else { "value": false, "reason": "UNKNOWN" }

func request_review() -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("requestReview")
	else:
		res = await _core.mock_bridge.request_review()
	var data: Dictionary = res.get("data", {}) if res.get("success", false) else {}
	return { "value": data.get("value", false), "feedback_sent": data.get("feedbackSent", false) }

# --- Shortcut ---
func can_show_shortcut_prompt() -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("canShowPrompt")
	else:
		res = _core.mock_bridge.can_show_prompt()
	var data: Dictionary = res.get("data", {}) if res.get("success", false) else {}
	return data.get("canShow", false)

func show_shortcut_prompt() -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("showPrompt")
	else:
		res = await _core.mock_bridge.show_prompt()
	var data: Dictionary = res.get("data", {}) if res.get("success", false) else {}
	return { "outcome": str(data.get("outcome", "rejected")) }

# --- Device ---
func get_device_info() -> Dictionary:
	if not _cached_device.is_empty():
		return _cached_device
	if _core.mock_bridge != null:
		return _core.mock_bridge.get_device_info()
	return { "type": "desktop", "isMobile": false, "isTablet": false, "isDesktop": true, "isTV": false }

func is_fullscreen() -> bool:
	if is_web():
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface(get_bridge_name())
		if bridge:
			return bridge.fullscreenStatus()
		return false
	return _core.mock_bridge.fullscreen_status()

func request_fullscreen() -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("fullscreenRequest")
	else:
		res = _core.mock_bridge.fullscreen_request()
	return res.get("success", false)

func exit_fullscreen() -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("fullscreenExit")
	else:
		res = _core.mock_bridge.fullscreen_exit()
	return res.get("success", false)

func get_orientation() -> String:
	if is_web():
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface(get_bridge_name())
		if bridge:
			return str(bridge.screenOrientationGet())
		return "landscape"
	return _core.mock_bridge.screen_orientation_get()

func set_orientation(value: String) -> bool:
	if is_web():
		var res: Dictionary = await call_js_async("screenOrientationSet", [value])
		return res.get("success", false)
	return _core.mock_bridge.screen_orientation_set(value).get("success", false)

# --- Environment ---
func get_environment() -> Dictionary:
	if not _cached_environment.is_empty():
		return _cached_environment
	if _core.mock_bridge != null:
		return _core.mock_bridge.get_environment()
	return { "app": {}, "browser": {}, "i18n": {}, "payload": "" }
