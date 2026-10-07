@tool
class_name PlatformAdapter
extends RefCounted

signal sdk_initialized(data: Dictionary)
signal game_paused
signal game_resumed
signal history_back_requested
signal account_selection_opened
signal account_selection_closed

var _core: Node = null

func _init(core: Node) -> void:
	_core = core

# --- Lifecycle ---
func init(options: Dictionary = {}) -> bool:
	push_error("PlatformAdapter.init() not implemented")
	return false

func game_ready() -> void: pass
func gameplay_start() -> void: pass
func gameplay_stop() -> void: pass

func get_server_time() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func is_available_method(method_name: String) -> bool:
	return false

func dispatch_event(event_name: String, detail: Dictionary = {}) -> bool:
	return false

func dispatch_exit() -> void: pass

# --- Ads ---
func show_interstitial() -> Dictionary:
	push_error("PlatformAdapter.show_interstitial() not implemented")
	return { "success": false, "was_shown": false, "error": "Not implemented" }

func show_rewarded() -> Dictionary:
	push_error("PlatformAdapter.show_rewarded() not implemented")
	return { "success": false, "rewarded": false, "was_shown": false, "error": "Not implemented" }

func show_banner() -> Dictionary:
	push_error("PlatformAdapter.show_banner() not implemented")
	return { "success": false, "error": "Not implemented" }

func hide_banner() -> Dictionary:
	push_error("PlatformAdapter.hide_banner() not implemented")
	return { "success": false, "error": "Not implemented" }

func get_banner_status() -> Dictionary:
	return { "is_showing": false, "reason": "Not implemented" }

## Спрашивает у платформы, поддерживает ли она нативную рекламу вообще.
## Только для диагностики: показ рекламы НЕ должен зависеть от этого ответа,
## потому что список методов у VK Bridge не совпадает с реальной выдачей.
func supports_native_ads() -> Dictionary:
	return { "supported": true, "platform": "unknown", "methods": {} }

## Быстрая проверка «есть ли реклама в наличии прямо сейчас».
## Платформы без такой проверки отвечают available = true.
func check_ad_available(_format: String) -> Dictionary:
	return { "success": true, "available": true }

# --- Player ---
func init_player(options: Dictionary = {}) -> Dictionary:
	push_error("PlatformAdapter.init_player() not implemented")
	return { "success": false, "error": "Not implemented" }

func is_authorized() -> bool: return false
func get_player_id() -> String: return ""
func get_player_name() -> String: return ""
func get_player_photo(_size: String = "medium") -> String: return ""
func get_player_data(_keys: Variant = null) -> Dictionary: return {}

## Чтение сохранения со статусом. ok=false означает «облако/платформа
## недоступны», а НЕ «сохранения нет». Без этого различия сбой сети
## принимается за отсутствие прогресса и затирает облако (п. 2.3.8).
func get_player_data_ex(keys: Variant = null) -> Dictionary:
	return { "ok": false, "data": await get_player_data(keys), "from_cache": false }

func set_player_data(_data: Dictionary, _flush: bool = false) -> bool: return false

## Запись сохранения со статусом. ok=false означает, что данные остались
## только в локальном зеркале и запись в облако нужно повторить.
## success — «сырой» успех записи в мост (обратная совместимость с set_player_data).
func set_player_data_ex(data: Dictionary, flush: bool = false) -> Dictionary:
	var ok: bool = await set_player_data(data, flush)
	return { "ok": ok, "success": ok, "cloud_ok": false }

## Синхронный (без await) сброс в JS-мост. Нужен в момент сворачивания
## приложения, когда таймеры Godot вот-вот остановятся.
func set_player_data_now(_data: Dictionary) -> void: pass
func get_player_stats(_keys: Variant = null) -> Dictionary: return {}
func set_player_stats(_stats: Dictionary) -> bool: return false
func increment_player_stats(_increments: Dictionary) -> Dictionary: return {}
func open_auth_dialog() -> Dictionary:
	return { "success": false, "error": "Not implemented" }

# --- Leaderboards ---
func get_leaderboard_description(_name: String) -> Dictionary: return {}
func set_leaderboard_score(_name: String, _score: int, _extra_data: String = "") -> bool: return false
func get_leaderboard_player_entry(_name: String) -> Dictionary: return {}
func get_leaderboard_entries(_name: String, _options: Dictionary = {}) -> Dictionary: return {}

# --- Payments ---
func init_payments(_options: Dictionary = {}) -> bool: return false
func purchase(_product_id: String, _developer_payload: String = "") -> Dictionary: return {}
func get_purchases() -> Array: return []
func get_catalog() -> Array: return []
func consume_purchase(_purchase_token: String) -> bool: return false

# --- Storage ---
func storage_get(_key: String, default_value: String = "") -> String: return default_value
func storage_set(_key: String, _value: String) -> bool: return false

# --- Feedback ---
func can_review() -> Dictionary:
	return { "value": false, "reason": "Not implemented" }

func request_review() -> Dictionary:
	return { "value": false, "feedback_sent": false }

# --- Shortcut ---
func can_show_shortcut_prompt() -> bool: return false
func show_shortcut_prompt() -> Dictionary:
	return { "outcome": "rejected" }

# --- Device ---
func get_device_info() -> Dictionary:
	return { "type": "desktop", "isMobile": false, "isTablet": false, "isDesktop": true, "isTV": false }
func is_fullscreen() -> bool: return false
func request_fullscreen() -> bool: return false
func exit_fullscreen() -> bool: return false
func get_orientation() -> String: return "landscape"
func set_orientation(_value: String) -> bool: return false

# --- Environment ---
func get_environment() -> Dictionary:
	return { "app": {}, "browser": {}, "i18n": {}, "payload": "" }

# --- Internal ---
func is_web() -> bool:
	return OS.has_feature("web")

func get_bridge_name() -> String:
	return "GodotYandexBridge"

func call_js_async(method_name: String, args: Array = [], timeout_sec: float = 60.0) -> Dictionary:
	if not is_web():
		return { "success": false, "error": "Not running in Web export" }
	return await _core.call_js_async(method_name, args, timeout_sec)
