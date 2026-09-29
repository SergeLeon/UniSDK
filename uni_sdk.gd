@tool
class_name UniSDKNode
extends Node

signal sdk_initialized(data: Dictionary)
signal platform_detected(platform: String)
signal game_paused
signal game_resumed
signal history_back_requested
signal account_selection_opened
signal account_selection_closed

@export var auto_init: bool = true
@export var auto_mute_audio: bool = true
@export var auto_call_game_ready: bool = true
@export var auto_apply_locale: bool = true
@export var auto_pause_tree: bool = false

var is_platform_paused: bool = false
var is_initialized: bool = false

const DEBUG_TAG := "core"

# --- Подмодули ---
var ads: UniAds
var player: UniPlayer
var leaderboards: UniLeaderboards
var payments: UniPayments
var feedback: UniFeedback
var shortcut: UniShortcut
var device: UniDevice
var environment: UniEnvironment
var storage: UniStorage

# --- Адаптер ---
var _adapter: PlatformAdapter = null
var _platform: PlatformDetector.Platform = PlatformDetector.Platform.MOCK
var mock_bridge: YandexMockBridge = null

# --- Внутреннее состояние ---
var _js_pause_resume_cb: JavaScriptObject = null
var _ad_event_queue: Array[Dictionary] = []
var _is_initializing: bool = false
var _ad_playing: bool = false
var _platform_paused: bool = false
var _audio_muted_by_platform: bool = false
var _user_was_muted_before: bool = false
var _active_js_callbacks: Array[JavaScriptObject] = []
var _ad_release_generation: int = 0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_project_settings()

	_platform = PlatformDetector.detect()
	var platform_str: String = PlatformDetector.platform_to_string(_platform)
	UniLogger.info(DEBUG_TAG, "Detected platform: " + platform_str)

	# Откладываем эмит, чтобы слушатели в сцене успели подключиться.
	platform_detected.emit.call_deferred(platform_str)

	match _platform:
		PlatformDetector.Platform.YANDEX:
			_adapter = YandexAdapter.new(self)
		PlatformDetector.Platform.VK:
			_adapter = VKAdapter.new(self)
		_:
			_adapter = YandexAdapter.new(self)

	if _platform == PlatformDetector.Platform.MOCK:
		mock_bridge = YandexMockBridge.new()

	ads = UniAds.new(self)
	player = UniPlayer.new(self)
	leaderboards = UniLeaderboards.new(self)
	payments = UniPayments.new(self)
	feedback = UniFeedback.new(self)
	shortcut = UniShortcut.new(self)
	device = UniDevice.new(self)
	environment = UniEnvironment.new(self)
	storage = UniStorage.new(self)

	_connect_adapter_signals()

	if is_web():
		_setup_web_callbacks()

	if auto_init:
		init()

func _load_project_settings() -> void:
	auto_init = bool(ProjectSettings.get_setting("uni_sdk/general/auto_init", auto_init))
	auto_call_game_ready = bool(ProjectSettings.get_setting("uni_sdk/general/auto_call_game_ready", auto_call_game_ready))
	auto_apply_locale = bool(ProjectSettings.get_setting("uni_sdk/general/auto_apply_locale", auto_apply_locale))
	auto_pause_tree = bool(ProjectSettings.get_setting("uni_sdk/general/auto_pause_tree", auto_pause_tree))
	auto_mute_audio = bool(ProjectSettings.get_setting("uni_sdk/ads/auto_mute_audio", auto_mute_audio))

func _connect_adapter_signals() -> void:
	if _adapter == null:
		return
	_adapter.sdk_initialized.connect(func(data): sdk_initialized.emit(data))
	_adapter.game_paused.connect(func(): _on_platform_pause())
	_adapter.game_resumed.connect(func(): _on_platform_resume())
	_adapter.history_back_requested.connect(func(): history_back_requested.emit())
	_adapter.account_selection_opened.connect(func(): account_selection_opened.emit())
	_adapter.account_selection_closed.connect(func(): account_selection_closed.emit())

# --- Публичный API ---

func get_platform() -> String:
	return PlatformDetector.platform_to_string(_platform)

func get_platform_enum() -> PlatformDetector.Platform:
	return _platform

func get_sub_platform() -> String:
	if get_platform() != "vk":
		return get_platform()
	var adapter = get_adapter()
	if adapter and adapter.has_method("is_ok") and adapter.is_ok():
		return "ok"
	return "vk"

func get_adapter() -> PlatformAdapter:
	return _adapter

func is_web() -> bool:
	return OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge")

func ensure_initialized() -> bool:
	if is_initialized:
		return true
	if _is_initializing:
		while _is_initializing and not is_initialized:
			await get_tree().process_frame
		return is_initialized
	return await init()

func init(options: Dictionary = {}) -> bool:
	if is_initialized:
		return true
	if _is_initializing:
		while _is_initializing and not is_initialized:
			await get_tree().process_frame
		return is_initialized

	_is_initializing = true

	var ok: bool = await _adapter.init(options)
	if not ok:
		UniLogger.error(DEBUG_TAG, "init FAILED")
		_is_initializing = false
		return false

	var env_data: Dictionary = await _adapter.get_environment()
	var dev_data: Dictionary = await _adapter.get_device_info()

	if _platform != PlatformDetector.Platform.MOCK:
		if not env_data.is_empty() and auto_apply_locale:
			var lang: String = str(env_data.get("i18n", {}).get("lang", ""))
			if not lang.is_empty():
				TranslationServer.set_locale(lang)
				UniLogger.info(DEBUG_TAG, "Locale set to: " + lang)
		if not dev_data.is_empty():
			device._update_info(dev_data)
		environment._update_env(env_data)

	await player._ensure_initialized()

	is_initialized = true
	_is_initializing = false

	if auto_call_game_ready:
		game_ready()
	return true

# --- Lifecycle ---

func game_ready() -> void:
	_adapter.game_ready()

func gameplay_start() -> void:
	_adapter.gameplay_start()

func gameplay_stop() -> void:
	_adapter.gameplay_stop()

func get_server_time() -> int:
	return _adapter.get_server_time()

func is_available_method(method_name: String) -> bool:
	return await _adapter.is_available_method(method_name)

func dispatch_event(event_name: String, detail: Dictionary = {}) -> bool:
	return await _adapter.dispatch_event(event_name, detail)

func dispatch_exit() -> void:
	_adapter.dispatch_exit()

# --- Convenience ---

func show_interstitial() -> Dictionary:
	return await ads.show_interstitial()

func show_rewarded() -> Dictionary:
	return await ads.show_rewarded()

func show_banner() -> Dictionary:
	return await ads.show_banner()

func hide_banner() -> Dictionary:
	return await ads.hide_banner()

# --- Внутренние хуки ---

func _on_platform_pause() -> void:
	_platform_paused = true
	_sync_pause_state()

func _on_platform_resume() -> void:
	_platform_paused = false
	_sync_pause_state()

func _on_ad_start() -> void:
	_ad_playing = true
	_sync_pause_state()

func _on_ad_end() -> void:
	_ad_playing = false
	if is_web():
		var is_hidden: bool = bool(JavaScriptBridge.eval("Boolean(document.hidden)"))
		if not is_hidden:
			_platform_paused = false
	else:
		_platform_paused = false
	_sync_pause_state()
	_ad_release_generation += 1
	_release_ad_callbacks_deferred(_ad_release_generation)

func _sync_pause_state() -> void:
	var should_pause: bool = _ad_playing or _platform_paused
	if should_pause == is_platform_paused:
		return
	is_platform_paused = should_pause
	if is_platform_paused:
		if auto_mute_audio:
			_user_was_muted_before = AudioServer.is_bus_mute(0)
			if not _user_was_muted_before:
				AudioServer.set_bus_mute(0, true)
				_audio_muted_by_platform = true
		if auto_pause_tree:
			get_tree().paused = true
		game_paused.emit()
	else:
		if auto_mute_audio and _audio_muted_by_platform:
			if not _user_was_muted_before:
				AudioServer.set_bus_mute(0, false)
			_audio_muted_by_platform = false
		if auto_pause_tree:
			get_tree().paused = false
		game_resumed.emit()

# --- JS-мост ---

func _setup_web_callbacks() -> void:
	if not is_web():
		return
	_js_pause_resume_cb = JavaScriptBridge.create_callback(_on_js_pause_resume)
	_active_js_callbacks.append(_js_pause_resume_cb)
	var bridge: JavaScriptObject = JavaScriptBridge.get_interface(_adapter.get_bridge_name())
	if bridge:
		bridge.setPauseResumeCallback(_js_pause_resume_cb)

func _on_js_pause_resume(args: Array) -> void:
	if args.is_empty():
		return
	var json_str: String = _js_to_string(args[0])
	var json: JSON = JSON.new()
	if json.parse(json_str) == OK and json.data is Dictionary:
		var ev: String = str(json.data.get("event", ""))
		match ev:
			"pause": _on_platform_pause()
			"resume": _on_platform_resume()
			"history_back": history_back_requested.emit()
			"account_selection_opened": account_selection_opened.emit()
			"account_selection_closed": account_selection_closed.emit()

func _js_to_string(js_val: Variant) -> String:
	if js_val == null:
		return ""
	if js_val is String:
		return js_val
	if ClassDB.class_exists("JavaScriptObject") and js_val is JavaScriptObject:
		var js_json: JavaScriptObject = JavaScriptBridge.get_interface("JSON")
		if js_json:
			return str(js_json.stringify(js_val))
	return str(js_val)

func call_js_async(method_name: String, args: Array = [], timeout_sec: float = 60.0) -> Dictionary:
	if not is_web():
		return { "success": false, "error": "Not running in Web export" }
	var bridge_name: String = _adapter.get_bridge_name()
	var bridge: JavaScriptObject = JavaScriptBridge.get_interface(bridge_name)
	if not bridge:
		return { "success": false, "error": "%s not found" % bridge_name }

	UniLogger.debug(DEBUG_TAG, "call_js_async [%s].%s" % [bridge_name, method_name])
	var result_holder: Dictionary = { "completed": false, "data": {}, "call_count": 0 }
	var cb_ref: Array[JavaScriptObject] = []

	var cb: JavaScriptObject = JavaScriptBridge.create_callback(func(cb_args: Array) -> void:
		result_holder.call_count += 1
		var raw: String = _js_to_string(cb_args[0]) if not cb_args.is_empty() else ""
		var json: JSON = JSON.new()
		var parsed: Dictionary = {}
		if json.parse(raw) == OK and json.data is Dictionary:
			parsed = json.data
		else:
			parsed = { "success": true, "raw": raw }

		if result_holder.completed:
			_ad_event_queue.append(parsed)
		else:
			result_holder.data = parsed
			result_holder.completed = true
	)
	cb_ref.append(cb)
	_active_js_callbacks.append(cb)

	var call_args: Array = args.duplicate()
	call_args.append(cb)
	bridge.callv(method_name, Array(call_args))

	var start_time: int = Time.get_ticks_msec()
	while not result_holder.completed:
		await get_tree().process_frame
		if timeout_sec > 0.0:
			if (Time.get_ticks_msec() - start_time) >= int(timeout_sec * 1000.0):
				UniLogger.warn(DEBUG_TAG, "TIMEOUT in call_js_async: " + method_name)
				_active_js_callbacks.erase(cb)
				return { "success": false, "error": "Timeout: %s" % method_name }

	if method_name not in ["showRewardedVideo", "showFullscreenAdv", "showNativeAds"]:
		_active_js_callbacks.erase(cb)
	return result_holder.data

func _wait_for_next_ad_event(timeout_sec: float = 75.0) -> Dictionary:
	var start_time: int = Time.get_ticks_msec()
	while _ad_event_queue.is_empty():
		await get_tree().process_frame
		if timeout_sec > 0.0:
			if (Time.get_ticks_msec() - start_time) >= int(timeout_sec * 1000.0):
				return { "event": "error", "error": "Timeout waiting for ad event" }
	return _ad_event_queue.pop_front()

func _clear_ad_event_queue() -> void:
	_ad_event_queue.clear()

func _release_ad_callbacks_deferred(generation: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(0.5).timeout

	if generation != _ad_release_generation:
		return
	if _ad_playing:
		return

	var keep: Array[JavaScriptObject] = []
	if _js_pause_resume_cb != null:
		keep.append(_js_pause_resume_cb)
	_active_js_callbacks = keep

# --- Утилиты для адаптеров ---

func _prepare_ad_call() -> void:
	_on_ad_start()
	_clear_ad_event_queue()

func _finish_ad_call() -> void:
	_on_ad_end()
