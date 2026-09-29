@tool
class_name VKAdapter
extends PlatformAdapter

const AD_TIMEOUT_MS: int = 75000
const INTERSTITIAL_HARD_TIMEOUT_MS: int = 15000
const TAG := "vk"

var _cached_environment: Dictionary = {}
var _cached_device: Dictionary = {}
var _cached_player: Dictionary = {}
var _player_initialized: bool = false

func _init(core: Node) -> void:
	super._init(core)

func get_bridge_name() -> String:
	return "GodotVKBridge"

func is_ok() -> bool:
	return bool(_cached_environment.get("is_ok", false))

# --- Lifecycle ---
func init(options: Dictionary = {}) -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("init", [JSON.stringify(options)], 20.0)
	else:
		res = _core.mock_bridge.init(options)

	if not res.get("success", false):
		return false

	var data: Dictionary = res.get("data", {})
	_cached_environment = data.get("environment", {})
	_cached_device = data.get("device", {})
	sdk_initialized.emit(data)
	return true

func game_ready() -> void: pass
func gameplay_start() -> void: pass
func gameplay_stop() -> void: pass

func get_server_time() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func is_available_method(method_name: String) -> bool:
	if is_web():
		var res: Dictionary = await call_js_async("isAvailableMethod", [method_name])
		return res.get("available", false)
	return true

func dispatch_event(_event_name: String, _detail: Dictionary = {}) -> bool:
	return false

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
	var cb_data: Dictionary = await call_js_async("showNativeAds", ["interstitial"], 30.0)
	var event: String = str(cb_data.get("event", "")).to_lower()

	if event in ["error", "onerror"]:
		result.error = str(cb_data.get("error", "Ad error"))
		_core._clear_ad_event_queue()
		return result
	if event in ["close", "onclose"]:
		result.was_shown = cb_data.get("wasShown", false)
		result.success = true
		_core._clear_ad_event_queue()
		return result

	var close_received: bool = false
	var error_received: bool = false
	var timed_out: bool = false
	var start: int = Time.get_ticks_msec()

	while not close_received and not error_received:
		var next: Dictionary = await _core._wait_for_next_ad_event(5.0)
		var ev: String = str(next.get("event", "")).to_lower()
		match ev:
			"close", "onclose":
				result.was_shown = next.get("wasShown", false)
				close_received = true
			"error", "onerror":
				result.error = str(next.get("error", "Ad error"))
				error_received = true
			"timeout":
				break
		if (Time.get_ticks_msec() - start) > INTERSTITIAL_HARD_TIMEOUT_MS:
			result.error = "Hard timeout waiting for interstitial"
			timed_out = true
			break

	result.success = close_received and not error_received and not timed_out
	_core._clear_ad_event_queue()
	return result

func _mock_show_interstitial() -> Dictionary:
	var result: Dictionary = { "success": false, "was_shown": false, "error": "" }
	var mock_cb: Callable = func(payload: Dictionary) -> void:
		var ev: String = str(payload.get("event", "")).to_lower()
		match ev:
			"close", "onclose": result.success = true; result.was_shown = payload.get("wasShown", false)
			"error", "onerror": result.error = str(payload.get("error", "Ad error"))
	await _core.mock_bridge.show_fullscreen_adv(mock_cb)
	return result

func show_rewarded() -> Dictionary:
	if not is_web():
		return await _mock_show_rewarded()
	return await _web_show_rewarded()

func _web_show_rewarded() -> Dictionary:
	var result: Dictionary = { "success": false, "rewarded": false, "was_shown": false, "error": "" }
	var cb_data: Dictionary = await call_js_async("showNativeAds", ["reward"], 60.0)
	var event: String = str(cb_data.get("event", "")).to_lower()
	var got_reward: bool = false
	var close_received: bool = false
	var error_received: bool = false
	var timed_out: bool = false

	match event:
		"rewarded", "reward", "onrewarded": got_reward = true
		"close", "onclose": result.was_shown = cb_data.get("wasShown", true); close_received = true
		"error", "onerror": result.error = str(cb_data.get("error", "Ad error")); error_received = true

	var start: int = Time.get_ticks_msec()
	while not close_received and not error_received:
		var next: Dictionary = await _core._wait_for_next_ad_event(60.0)
		var ev: String = str(next.get("event", "")).to_lower()
		match ev:
			"rewarded", "reward", "onrewarded": got_reward = true
			"close", "onclose": result.was_shown = next.get("wasShown", true); close_received = true
			"error", "onerror": result.error = str(next.get("error", "Ad error")); error_received = true
			"timeout": break
		if (Time.get_ticks_msec() - start) > AD_TIMEOUT_MS:
			result.error = "Timeout"
			timed_out = true
			break

	result.success = close_received and not timed_out
	result.rewarded = got_reward
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
		return await call_js_async("showBannerAd")
	return _core.mock_bridge.show_banner_adv()

func hide_banner() -> Dictionary:
	if is_web():
		return await call_js_async("hideBannerAd")
	return _core.mock_bridge.hide_banner_adv()

func get_banner_status() -> Dictionary:
	if is_web():
		return await call_js_async("getBannerAdStatus")
	return _core.mock_bridge.get_banner_adv_status()

# --- Player ---
func init_player(options: Dictionary = {}) -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("getUserInfo", [], 15.0)
	else:
		res = _core.mock_bridge.init_player(options)
	_cached_player = res.get("data", {}) if res.get("success", false) else {}
	_player_initialized = res.get("success", false)
	return _cached_player

func is_authorized() -> bool: return not get_player_id().is_empty()
func get_player_id() -> String: return str(_cached_player.get("uniqueId", ""))
func get_player_name() -> String: return str(_cached_player.get("name", ""))

func get_player_photo(size: String = "medium") -> String:
	match size.to_lower():
		"small": return str(_cached_player.get("photoSmall", ""))
		"large": return str(_cached_player.get("photoLarge", ""))
		_: return str(_cached_player.get("photoMedium", ""))

func get_player_data(keys: Variant = null) -> Dictionary:
	var res: Dictionary
	if is_web():
		var keys_json: String = JSON.stringify(keys) if keys != null else ""
		res = await call_js_async("storageGet", [keys_json], 15.0)
	else:
		res = _core.mock_bridge.get_player_data(keys)
	return res.get("data", {}) if res.get("success", false) else {}

func set_player_data(data: Dictionary, flush: bool = false) -> bool:
	if is_web():
		var res: Dictionary = await call_js_async("storageSet", [JSON.stringify(data)], 10.0)
		return res.get("success", false)
	return _core.mock_bridge.set_player_data(data, flush).get("success", false)

func get_changed_keys() -> Array:
	if not is_web():
		return []
	var res: Dictionary = await call_js_async("getChanged", [], 5.0)
	if not res.get("success", false):
		return []
	return res.get("changed", [])

func get_player_stats(keys: Variant = null) -> Dictionary: return await get_player_data(keys)
func set_player_stats(stats: Dictionary) -> bool: return await set_player_data(stats, false)

func increment_player_stats(increments: Dictionary) -> Dictionary:
	var current: Dictionary = await get_player_data()
	for k in increments:
		current[k] = int(current.get(k, 0)) + int(increments[k])
	await set_player_data(current, false)
	return current

func open_auth_dialog() -> Dictionary: return await init_player()

# --- Leaderboards ---
func get_leaderboard_description(name: String) -> Dictionary:
	return { "name": name, "title": name.capitalize(), "type": "numeric" }

func set_leaderboard_score(name: String, score: int, extra_data: String = "") -> bool:
	var key: String = "lb_%s" % name
	var data: Dictionary = await get_player_data([key])
	var current: int = int(data.get(key, 0))
	if score > current:
		return await set_player_data({ key: str(score) }, true)
	return true

func get_leaderboard_player_entry(name: String) -> Dictionary:
	var key: String = "lb_%s" % name
	var data: Dictionary = await get_player_data([key])
	return {
		"score": int(data.get(key, 0)),
		"rank": 0,
		"player": {
			"uniqueID": get_player_id(),
			"publicName": get_player_name(),
			"avatarUrlSmall": get_player_photo("small")
		}
	}

func get_leaderboard_entries(name: String, _options: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = await get_leaderboard_player_entry(name)
	return {
		"leaderboard": { "name": name, "title": name.capitalize() },
		"entries": [entry] if entry.get("score", 0) > 0 else [],
		"userRank": entry.get("rank", 0)
	}

# --- Payments ---
func init_payments(options: Dictionary = {}) -> bool:
	if not is_web() and _core.mock_bridge:
		_core.mock_bridge.is_signed = bool(options.get("signed", _core.mock_bridge.is_signed))
	return true

func purchase(product_id: String, developer_payload: String = "") -> Dictionary:
	if not is_web():
		return _core.mock_bridge.purchase({ "id": product_id, "developerPayload": developer_payload })
	if _cached_device.get("isDesktop", true):
		UniLogger.warn(TAG, "purchase not supported on desktop web")
		return {}
	var res: Dictionary = await call_js_async("openPayForm", [product_id, developer_payload], 130.0)
	return res.get("data", {}) if res.get("success", false) else {}

func get_purchases() -> Array: return []
func get_catalog() -> Array: return []
func consume_purchase(_purchase_token: String) -> bool: return true

# --- Storage ---
func storage_get(key: String, default_value: String = "") -> String:
	if is_web():
		var res: Dictionary = await call_js_async("storageGetItem", [key], 15.0)
		if res.get("success", false) and res.get("value") != null:
			return str(res.get("value"))
		return default_value
	var config: ConfigFile = ConfigFile.new()
	if config.load("user://vk_safe_storage.cfg") == OK:
		return str(config.get_value("storage", key, default_value))
	return default_value

func storage_set(key: String, value: String) -> bool:
	if is_web():
		var res: Dictionary = await call_js_async("storageSetItem", [key, value], 10.0)
		return res.get("success", false)
	var config: ConfigFile = ConfigFile.new()
	config.load("user://vk_safe_storage.cfg")
	config.set_value("storage", key, value)
	return config.save("user://vk_safe_storage.cfg") == OK

# --- Feedback ---
func can_review() -> Dictionary: return { "value": false, "reason": "NOT_SUPPORTED" }
func request_review() -> Dictionary: return { "value": false, "feedback_sent": false }

# --- Shortcut ---
func can_show_shortcut_prompt() -> bool:
	var res: Dictionary
	if is_web():
		res = await call_js_async("canShowShortcutPrompt")
	else:
		res = _core.mock_bridge.can_show_prompt()
	var data: Dictionary = res.get("data", {}) if res.get("success", false) else {}
	return data.get("canShow", false)

func show_shortcut_prompt() -> Dictionary:
	var res: Dictionary
	if is_web():
		res = await call_js_async("showShortcutPrompt")
	else:
		res = await _core.mock_bridge.show_prompt()
	var data: Dictionary = res.get("data", {}) if res.get("success", false) else {}
	return { "outcome": str(data.get("outcome", "rejected")) }

# --- Device ---
func get_device_info() -> Dictionary:
	if not _cached_device.is_empty(): return _cached_device
	if _core.mock_bridge != null: return _core.mock_bridge.get_device_info()
	return { "type": "desktop", "isMobile": false, "isTablet": false, "isDesktop": true, "isTV": false }

func is_fullscreen() -> bool: return false
func request_fullscreen() -> bool: return false
func exit_fullscreen() -> bool: return false
func get_orientation() -> String: return "landscape"
func set_orientation(_value: String) -> bool: return false

# --- Environment ---
func get_environment() -> Dictionary:
	if not _cached_environment.is_empty(): return _cached_environment
	if _core.mock_bridge != null: return _core.mock_bridge.get_environment()
	return { "app": {}, "browser": {}, "i18n": {}, "payload": "" }
