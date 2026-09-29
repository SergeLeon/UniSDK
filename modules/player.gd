@tool
class_name UniPlayer
extends RefCounted

signal authorized(player_info: Dictionary)
signal auth_failed(error: String)
signal data_loaded(data: Dictionary)
signal data_saved

const BACKUP_PATH := "user://unisdk_player_backup.json"
const TAG := "player"

var _core: Node
var _info: Dictionary = {
	"isAuthorized": false,
	"uniqueId": "",
	"name": "",
	"photoSmall": "",
	"photoMedium": "",
	"photoLarge": "",
	"payingStatus": ""
}

var _backup: Dictionary = {}
var _backup_loaded: bool = false
var _backup_platform: String = ""

var _avatar_cache: Dictionary = {}

# Инициализация
var _init_done: bool = false
var _init_in_progress: bool = false

# Троттлинг get_data
var _last_get_data_ms: int = 0
var _get_data_min_interval_ms: int = 15000
var _cached_data: Dictionary = {}
var _cached_data_valid: bool = false

func _init(core: Node) -> void:
	_core = core
	_get_data_min_interval_ms = int(float(ProjectSettings.get_setting(
		"uni_sdk/player/get_data_min_interval_sec", 15.0)) * 1000.0)

# ------------------------------------------------------------------
#  Инициализация
# ------------------------------------------------------------------

func _ensure_initialized() -> void:
	if _init_done:
		return
	if _init_in_progress:
		while _init_in_progress and not _init_done:
			await _core.get_tree().process_frame
		return
	await init()

func init(options: Dictionary = {}) -> Dictionary:
	if _init_done:
		return _info
	if _init_in_progress:
		while _init_in_progress and not _init_done:
			await _core.get_tree().process_frame
		return _info

	_init_in_progress = true
	_info = await _core.get_adapter().init_player(options)
	_init_done = true
	_init_in_progress = false

	if is_authorized():
		authorized.emit(_info)
	return _info

func open_auth_dialog() -> Dictionary:
	_info = await _core.get_adapter().open_auth_dialog()
	if is_authorized():
		authorized.emit(_info)
	return _info

func is_authorized() -> bool:
	return bool(_info.get("isAuthorized", false))

func get_id() -> String: return str(_info.get("uniqueId", ""))
func get_name() -> String: return str(_info.get("name", ""))

func get_photo(size: String = "medium") -> String:
	match size.to_lower():
		"small": return str(_info.get("photoSmall", ""))
		"large": return str(_info.get("photoLarge", ""))
		_: return str(_info.get("photoMedium", ""))

func get_avatar_texture(size: String = "medium") -> Texture2D:
	return await load_texture_from_url(get_photo(size), get_name())

func get_paying_status() -> String: return str(_info.get("payingStatus", ""))
func get_signature() -> String: return str(_info.get("signature", ""))

# ------------------------------------------------------------------
#  Player data
# ------------------------------------------------------------------

func get_data(keys: Variant = null) -> Dictionary:
	var now: int = Time.get_ticks_msec()
	# Троттлинг: если недавно уже читали, и запрошен полный набор — отдаём кэш.
	if keys == null and _cached_data_valid and (now - _last_get_data_ms) < _get_data_min_interval_ms:
		data_loaded.emit(_cached_data)
		return _cached_data.duplicate(true)

	var cloud: Dictionary = await _core.get_adapter().get_player_data(keys)
	_last_get_data_ms = now

	if not _core.is_web():
		if cloud is Dictionary:
			if keys == null:
				_cached_data = cloud.duplicate(true)
				_cached_data_valid = true
			data_loaded.emit(cloud)
		return cloud if cloud is Dictionary else {}

	_load_backup()

	if cloud is Dictionary and not cloud.is_empty():
		_merge_into_backup(cloud)
		_save_backup()
		if keys == null:
			_cached_data = cloud.duplicate(true)
			_cached_data_valid = true
		data_loaded.emit(cloud)
		return cloud

	var from_backup: Dictionary = _filter_backup(keys)
	data_loaded.emit(from_backup)
	return from_backup

func set_data(data: Dictionary, flush: bool = false) -> bool:
	if data.is_empty():
		return true

	if not _core.is_web():
		var ok_mock: bool = await _core.get_adapter().set_player_data(data, flush)
		if ok_mock:
			_cached_data_valid = false
			data_saved.emit()
		return ok_mock

	_load_backup()
	_merge_into_backup(data)
	_save_backup()

	var ok: bool = await _core.get_adapter().set_player_data(data, flush)
	if ok:
		_cached_data_valid = false
		data_saved.emit()
	else:
		UniLogger.warn(TAG, "cloud save failed, data preserved in local backup")
	return ok

# ------------------------------------------------------------------
#  Stats
# ------------------------------------------------------------------

func get_stats(keys: Variant = null) -> Dictionary:
	return await _core.get_adapter().get_player_stats(keys)

func set_stats(stats: Dictionary) -> bool:
	return await _core.get_adapter().set_player_stats(stats)

func increment_stats(increments: Dictionary) -> Dictionary:
	return await _core.get_adapter().increment_player_stats(increments)

func get_ids_per_game() -> Array[Dictionary]:
	if _core.is_web():
		var res: Dictionary = await _core.call_js_async("getPlayerIDsPerGame")
		var list: Array[Dictionary] = []
		if res.get("success", false):
			for item: Dictionary in res.get("data", []):
				list.append(item)
		return list
	return _core.mock_bridge.get_player_ids_per_game()

# ------------------------------------------------------------------
#  Локальный бэкап
# ------------------------------------------------------------------

func _current_platform() -> String:
	return _core.get_platform()

func _load_backup() -> void:
	if _backup_loaded:
		return
	_backup_loaded = true
	_backup_platform = _current_platform()
	_backup = {}

	if not FileAccess.file_exists(BACKUP_PATH):
		return

	var file: FileAccess = FileAccess.open(BACKUP_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		UniLogger.warn(TAG, "Backup parse error: %s" % json.get_error_message())
		return

	var all: Variant = json.data
	if not (all is Dictionary):
		return

	var section: Variant = (all as Dictionary).get(_backup_platform, {})
	if section is Dictionary:
		_backup = (section as Dictionary).duplicate(true)

func _save_backup() -> void:
	var all: Dictionary = {}
	if FileAccess.file_exists(BACKUP_PATH):
		var rf: FileAccess = FileAccess.open(BACKUP_PATH, FileAccess.READ)
		if rf:
			var text: String = rf.get_as_text()
			rf.close()
			var json: JSON = JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				all = (json.data as Dictionary).duplicate(true)

	all[_backup_platform] = _backup
	UniAtomicIO.write_string(
		ProjectSettings.globalize_path(BACKUP_PATH),
		JSON.stringify(all)
	)

func _merge_into_backup(data: Dictionary) -> void:
	for k in data:
		_backup[str(k)] = data[k]

func _filter_backup(keys: Variant) -> Dictionary:
	if keys == null:
		return _backup.duplicate(true)
	var result: Dictionary = {}
	if keys is Array:
		for k: Variant in keys:
			var k_str: String = str(k)
			if _backup.has(k_str):
				result[k_str] = _backup[k_str]
	elif keys is String:
		if _backup.has(keys):
			result[keys] = _backup[keys]
	return result

func clear_backup() -> void:
	_backup.clear()
	_save_backup()

# ------------------------------------------------------------------
#  Аватарки
# ------------------------------------------------------------------

func load_texture_from_url(url: String, fallback_text: String = "P") -> Texture2D:
	if url.is_empty():
		return _generate_procedural_avatar(fallback_text)
	if _avatar_cache.has(url):
		return _avatar_cache[url]
	if not _core.is_web() and (url.begins_with("mock://") or not url.begins_with("http")):
		var tex := _generate_procedural_avatar(fallback_text)
		_avatar_cache[url] = tex
		return tex

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return _generate_procedural_avatar(fallback_text)

	var http := HTTPRequest.new()
	http.timeout = 10.0
	tree.root.add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return _generate_procedural_avatar(fallback_text)

	var result: Array = await http.request_completed
	http.queue_free()

	if int(result[1]) == 200 and not (result[3] as PackedByteArray).is_empty():
		var image := Image.new()
		var img_err := image.load_png_from_buffer(result[3])
		if img_err != OK: img_err = image.load_jpg_from_buffer(result[3])
		if img_err != OK: img_err = image.load_webp_from_buffer(result[3])
		if img_err == OK:
			var tex := ImageTexture.create_from_image(image)
			_avatar_cache[url] = tex
			return tex

	var fallback := _generate_procedural_avatar(fallback_text)
	_avatar_cache[url] = fallback
	return fallback

func _generate_procedural_avatar(label: String) -> Texture2D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var hash_val := absi(label.hash())
	var hue := fmod(float(hash_val % 360) / 360.0, 1.0)
	var bg_color := Color.from_hsv(hue, 0.65, 0.75, 1.0)
	var center := Vector2(64, 64)
	var head := Vector2(64, 52)
	var body := Vector2(64, 108)
	for y in range(128):
		for x in range(128):
			if Vector2(x, y).distance_to(center) <= 62.0:
				if Vector2(x, y).distance_to(head) <= 24.0 or Vector2(x, y).distance_to(body) <= 40.0:
					img.set_pixel(x, y, Color.WHITE)
				else:
					img.set_pixel(x, y, bg_color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
