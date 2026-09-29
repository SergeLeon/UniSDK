@tool
class_name YandexMockBridge
extends RefCounted

const MOCK_SAVE_PATH: String = "user://unisdk_mock_data.json"

var is_initialized: bool = false
var is_player_authorized: bool = true
var player_unique_id: String = "mock_player_12345"
var player_name: String = "Test Player (Editor)"
var player_photo_url: String = "mock://avatar/islands-200"

var _mock_data: Dictionary = {}
var _mock_stats: Dictionary = {}
var _mock_leaderboards: Dictionary = {}
var _mock_purchases: Array[Dictionary] = []
var _mock_catalog: Array[Dictionary] = [
	{
		"id": "coins_100",
		"title": "100 Coins",
		"description": "Bag of 100 gold coins",
		"imageURI": "",
		"price": "50 YAN",
		"priceValue": "50",
		"priceCurrencyCode": "YAN",
		"currencyImageSmall": "https://yastatic.net/s3/doc-binary/src/dev/games/ru/index/yan.svg",
		"currencyImageMedium": "https://yastatic.net/s3/doc-binary/src/dev/games/ru/index/yan.svg",
		"currencyImageSvg": "https://yastatic.net/s3/doc-binary/src/dev/games/ru/index/yan.svg"
	},
	{
		"id": "no_ads",
		"title": "Disable Ads",
		"description": "Permanent ad removal",
		"imageURI": "",
		"price": "100 YAN",
		"priceValue": "100",
		"priceCurrencyCode": "YAN",
		"currencyImageSmall": "https://yastatic.net/s3/doc-binary/src/dev/games/ru/index/yan.svg",
		"currencyImageMedium": "https://yastatic.net/s3/doc-binary/src/dev/games/ru/index/yan.svg",
		"currencyImageSvg": "https://yastatic.net/s3/doc-binary/src/dev/games/ru/index/yan.svg"
	}
]
var _banner_showing: bool = false
var _reviewed: bool = false
var _shortcut_installed: bool = false
var is_signed: bool = false

func _init() -> void:
	player_name = str(ProjectSettings.get_setting("uni_sdk/mock/player_name", player_name))
	player_unique_id = str(ProjectSettings.get_setting("uni_sdk/mock/player_unique_id", player_unique_id))
	is_player_authorized = bool(ProjectSettings.get_setting("uni_sdk/mock/is_authorized", is_player_authorized))
	_load_mock_file()

func reset_mock_storage() -> void:
	_mock_data.clear()
	_mock_stats.clear()
	_mock_leaderboards.clear()
	_mock_purchases.clear()
	_reviewed = false
	_shortcut_installed = false
	if FileAccess.file_exists(MOCK_SAVE_PATH):
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove("unisdk_mock_data.json")

func _load_mock_file() -> void:
	if not FileAccess.file_exists(MOCK_SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(MOCK_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json_str: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(json_str) != OK or not (json.data is Dictionary):
		return
	var d: Dictionary = json.data
	_mock_data = d.get("data", {}) if d.get("data") is Dictionary else {}
	_mock_stats = d.get("stats", {}) if d.get("stats") is Dictionary else {}
	_mock_leaderboards = d.get("leaderboards", {}) if d.get("leaderboards") is Dictionary else {}
	_mock_purchases.clear()
	for p in d.get("purchases", []):
		if p is Dictionary:
			_mock_purchases.append(p)
	_reviewed = bool(d.get("reviewed", false))
	_shortcut_installed = bool(d.get("shortcut_installed", false))

func _save_mock_file() -> void:
	var save_dict: Dictionary = {
		"data": _mock_data,
		"stats": _mock_stats,
		"leaderboards": _mock_leaderboards,
		"purchases": _mock_purchases,
		"reviewed": _reviewed,
		"shortcut_installed": _shortcut_installed
	}
	UniAtomicIO.write_string(
		ProjectSettings.globalize_path(MOCK_SAVE_PATH),
		JSON.stringify(save_dict, "\t")
	)

# --- Core Lifecycle ---

func init(options: Dictionary = {}) -> Dictionary:
	is_signed = bool(options.get("signed", false))
	is_initialized = true
	return {
		"success": true,
		"data": {
			"environment": get_environment(),
			"device": get_device_info()
		}
	}

func loading_ready() -> void: pass
func gameplay_start() -> void: pass
func gameplay_stop() -> void: pass
func server_time() -> int: return int(Time.get_unix_time_from_system() * 1000.0)
func is_available_method(_method_name: String) -> bool: return true

# --- Environment & Device ---

func get_environment() -> Dictionary:
	return {
		"app": { "id": "mock_app_id" },
		"browser": { "lang": "ru" },
		"i18n": { "lang": "ru", "tld": "ru" },
		"payload": "",
		"fullscreen": false,
		"referrer": {
			"type": "promo",
			"promoId": "mock_promo_2026",
			"intent": "open_shop",
			"inappId": "coins_100"
		}
	}

func get_device_info() -> Dictionary:
	var os_name: String = OS.get_name().to_lower()
	var is_mob: bool = (os_name == "android" or os_name == "ios")
	return {
		"type": "mobile" if is_mob else "desktop",
		"isMobile": is_mob,
		"isTablet": false,
		"isDesktop": not is_mob,
		"isTV": false
	}

# --- Fullscreen & Orientation ---

func fullscreen_status() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func fullscreen_request() -> Dictionary: return { "success": true, "status": "on" }
func fullscreen_exit() -> Dictionary: return { "success": true, "status": "off" }

func screen_orientation_get() -> String:
	var vp_size: Vector2 = DisplayServer.window_get_size()
	return "landscape" if vp_size.x >= vp_size.y else "portrait"

func screen_orientation_set(val: String) -> Dictionary:
	return { "success": true, "orientation": val }

# --- Ads ---

func show_fullscreen_adv(callback: Callable) -> void:
	callback.call({ "event": "open" })
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(0.5).timeout
	callback.call({ "event": "close", "wasShown": true })

func show_rewarded_video(callback: Callable) -> void:
	callback.call({ "event": "open" })
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(0.8).timeout
	callback.call({ "event": "rewarded" })
	callback.call({ "event": "close", "wasShown": true })

func get_banner_adv_status() -> Dictionary:
	return { "success": true, "stickyAdvIsShowing": _banner_showing, "reason": null }

func show_banner_adv() -> Dictionary:
	_banner_showing = true
	return { "success": true, "stickyAdvIsShowing": true, "reason": null }

func hide_banner_adv() -> Dictionary:
	_banner_showing = false
	return { "success": true, "stickyAdvIsShowing": false }

# --- Player & Auth ---

func init_player(options: Dictionary = {}) -> Dictionary:
	var signed_req: bool = is_signed or bool(options.get("signed", false))
	return {
		"success": true,
		"data": {
			"isAuthorized": is_player_authorized,
			"uniqueId": player_unique_id if is_player_authorized else "",
			"name": player_name if is_player_authorized else "",
			"photoSmall": player_photo_url if is_player_authorized else "",
			"photoMedium": player_photo_url if is_player_authorized else "",
			"photoLarge": player_photo_url if is_player_authorized else "",
			"payingStatus": "paying" if is_player_authorized else "",
			"signature": "mock_player_jwt_signature_eyJhbGciOi..." if signed_req else ""
		}
	}

func open_auth_dialog() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(0.3).timeout
	is_player_authorized = true
	return init_player()

func get_player_data(keys: Variant = null) -> Dictionary:
	if keys == null:
		return { "success": true, "data": _mock_data.duplicate(true) }
	var result: Dictionary = {}
	if keys is Array:
		for k: Variant in keys:
			var k_str: String = str(k)
			if _mock_data.has(k_str):
				result[k_str] = _mock_data[k_str]
	elif keys is String:
		if _mock_data.has(keys):
			result[keys] = _mock_data[keys]
	return { "success": true, "data": result }

func set_player_data(data: Dictionary, _flush: bool = false) -> Dictionary:
	for k: Variant in data.keys():
		_mock_data[str(k)] = data[k]
	_save_mock_file()
	return { "success": true }

func get_player_stats(keys: Variant = null) -> Dictionary:
	if keys == null:
		return { "success": true, "data": _mock_stats.duplicate(true) }
	var result: Dictionary = {}
	if keys is Array:
		for k: Variant in keys:
			var k_str: String = str(k)
			if _mock_stats.has(k_str):
				result[k_str] = _mock_stats[k_str]
	return { "success": true, "data": result }

func set_player_stats(stats: Dictionary) -> Dictionary:
	for k: Variant in stats.keys():
		_mock_stats[str(k)] = stats[k]
	_save_mock_file()
	return { "success": true }

func increment_player_stats(increments: Dictionary) -> Dictionary:
	for k: Variant in increments.keys():
		var k_str: String = str(k)
		var val: Variant = _mock_stats.get(k_str, 0)
		_mock_stats[k_str] = val + increments[k]
	_save_mock_file()
	return { "success": true, "data": _mock_stats.duplicate(true) }

func get_player_ids_per_game() -> Array[Dictionary]:
	return [
		{ "appID": "mock_app_1", "userID": "mock_user_1" },
		{ "appID": "mock_app_2", "userID": "mock_user_2" }
	]

# --- Leaderboards ---

func get_leaderboard_description(name: String) -> Dictionary:
	return {
		"success": true,
		"data": {
			"name": name,
			"title": name.capitalize(),
			"type": "numeric",
			"description": { "invert_sort_order": false, "decimal_offset": 0 }
		}
	}

func set_leaderboard_score(name: String, score: int, extra_data: String = "") -> Dictionary:
	if not _mock_leaderboards.has(name):
		_mock_leaderboards[name] = []
	var list: Array = _mock_leaderboards[name]
	var found: bool = false
	for entry: Dictionary in list:
		if entry.get("player", {}).get("uniqueID") == player_unique_id:
			entry["score"] = score
			entry["extraData"] = extra_data
			found = true
			break
	if not found:
		list.append({
			"score": score,
			"extraData": extra_data,
			"rank": 1,
			"player": {
				"uniqueID": player_unique_id,
				"publicName": player_name,
				"avatarUrlSmall": player_photo_url
			}
		})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	for i: int in range(list.size()):
		list[i]["rank"] = i + 1
	_save_mock_file()
	return { "success": true }

func get_leaderboard_player_entry(name: String) -> Dictionary:
	var list: Array = _mock_leaderboards.get(name, [])
	for entry: Dictionary in list:
		if entry.get("player", {}).get("uniqueID") == player_unique_id:
			return { "success": true, "data": entry }
	return {
		"success": true,
		"data": {
			"score": 0, "rank": 0, "extraData": "",
			"player": { "uniqueID": player_unique_id, "publicName": player_name }
		}
	}

func get_leaderboard_entries(name: String, _options: Dictionary = {}) -> Dictionary:
	var list: Array = _mock_leaderboards.get(name, [])
	if list.is_empty():
		for i: int in range(1, 6):
			list.append({
				"score": 1000 - i * 150,
				"rank": i,
				"extraData": "",
				"player": {
					"uniqueID": "mock_bot_%d" % i,
					"publicName": "Player Bot %d" % i,
					"avatarUrlSmall": player_photo_url
				}
			})
		_mock_leaderboards[name] = list
	return {
		"success": true,
		"data": {
			"leaderboard": { "name": name, "title": name.capitalize() },
			"entries": list,
			"userRank": 1
		}
	}

# --- Payments ---

func get_catalog() -> Array[Dictionary]:
	return _mock_catalog

func get_purchases() -> Array[Dictionary]:
	return _mock_purchases

func purchase(options: Dictionary) -> Dictionary:
	var product_id: String = str(options.get("id", ""))
	var token: String = "mock_token_" + str(Time.get_ticks_msec())
	var purchase_entry: Dictionary = {
		"productID": product_id,
		"purchaseToken": token,
		"developerPayload": options.get("developerPayload", "")
	}
	if is_signed:
		purchase_entry["signature"] = "mock_purchase_jwt_signature_eyJhbGciOi..."
	_mock_purchases.append(purchase_entry)
	_save_mock_file()
	return { "success": true, "data": purchase_entry }

func consume_purchase(token: String) -> Dictionary:
	for i: int in range(_mock_purchases.size()):
		if _mock_purchases[i].get("purchaseToken") == token:
			_mock_purchases.remove_at(i)
			_save_mock_file()
			return { "success": true }
	return { "success": false, "error": "Token not found" }

# --- Feedback ---

func can_review() -> Dictionary:
	return {
		"success": true,
		"data": {
			"value": not _reviewed,
			"reason": "GAME_RATED" if _reviewed else null
		}
	}

func request_review() -> Dictionary:
	_reviewed = true
	_save_mock_file()
	return { "success": true, "data": { "value": true, "feedbackSent": true } }

# --- Shortcut ---

func can_show_prompt() -> Dictionary:
	return { "success": true, "data": { "canShow": not _shortcut_installed } }

func show_prompt() -> Dictionary:
	_shortcut_installed = true
	_save_mock_file()
	return { "success": true, "data": { "outcome": "accepted" } }

# --- Remote Config ---

func get_flags(params: Dictionary = {}) -> Dictionary:
	return { "success": true, "data": params.get("defaultFlags", {}) }

# --- Cross-Promotion ---

func get_all_games() -> Dictionary:
	var list: Array[Dictionary] = [
		{ "appID": "mock_game_1", "title": "Example Game 1", "url": "https://yandex.ru/games" },
		{ "appID": "mock_game_2", "title": "Example Game 2", "url": "https://yandex.ru/games" }
	]
	return {
		"developerURL": "https://yandex.ru/games/developer?name=mock",
		"games": list
	}

func get_game_by_id(app_id: Variant) -> Dictionary:
	return {
		"success": true,
		"data": { "appID": str(app_id), "title": "Example Game", "url": "https://yandex.ru/games" }
	}

# --- Clipboard ---

func clipboard_write_text(text: String) -> Dictionary:
	DisplayServer.clipboard_set(text)
	return { "success": true }

# --- Multiplayer ---

func multiplayer_init_sessions(options: Dictionary) -> Array[Dictionary]:
	var count: int = int(options.get("count", 1))
	var sample: Array[Dictionary] = []
	for i: int in range(count):
		sample.append({
			"id": "mock_session_%d" % (i + 1),
			"meta": { "meta1": 100 * (i + 1), "meta2": i + 1, "meta3": 0 },
			"player": { "name": "Opponent Bot %d" % (i + 1), "avatar": player_photo_url },
			"timeline": [
				{ "id": "1", "time": 100, "payload": { "action": "start" } },
				{ "id": "2", "time": 500, "payload": { "action": "move", "x": 10, "y": 20 } }
			]
		})
	return sample

func multiplayer_commit(_payload: Dictionary) -> void: pass
func multiplayer_push(_meta: Dictionary) -> Dictionary: return { "success": true }

# --- SDK Events ---

func dispatch_event(_event_name: String, _detail: Dictionary = {}) -> Dictionary:
	return { "success": true }

func exit() -> Dictionary:
	return { "success": true }
