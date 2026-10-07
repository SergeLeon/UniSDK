@tool
class_name UniLeaderboards
extends RefCounted

signal score_set(leaderboard_name: String, score: int)
signal score_failed(leaderboard_name: String, error: String)

var _core: Node
var _pending_scores: Dictionary = {}
var _debounce_seq: int = 0
var _last_write_ms_by_board: Dictionary = {}


func _init(core: Node) -> void:
	_core = core


# ------------------------------------------------------------------
#  Platform capabilities
# ------------------------------------------------------------------

## Отправка счёта в лидерборд доступна?
## Yandex: только для авторизованных игроков.
## VK / OK: работает через storage-фолбэк.
## Mock: всегда.
func is_set_score_supported() -> bool:
	if not _core.is_initialized:
		return true
	var platform: String = _core.get_platform()
	if platform == "mock":
		return true
	if platform == "yandex":
		return _core.player.is_authorized()
	return true


## Чтение топа доступно?
## Yandex: только для авторизованных.
## VK / OK: возвращает только запись игрока.
func is_get_entries_supported() -> bool:
	if not _core.is_initialized:
		return true
	var platform: String = _core.get_platform()
	if platform == "mock":
		return true
	if platform == "yandex":
		return _core.player.is_authorized()
	return true


## Доступен ли полный топ на текущей платформе?
## На VK / OK всегда false.
func is_full_leaderboard_available() -> bool:
	var platform: String = _core.get_platform()
	return platform != "vk"


func can_set_score() -> bool:
	return is_set_score_supported()

func can_get_entries() -> bool:
	return is_get_entries_supported()


# ------------------------------------------------------------------
#  Description
# ------------------------------------------------------------------

func get_description(name: String) -> Dictionary:
	if not is_get_entries_supported():
		return {}
	return await _core.get_adapter().get_leaderboard_description(name)


# ------------------------------------------------------------------
#  Set score
# ------------------------------------------------------------------

func set_score(name: String, score: int, extra_data: String = "") -> bool:
	if not is_set_score_supported():
		score_failed.emit(name, "Not supported on this platform")
		return false

	var now: int = Time.get_ticks_msec()
	var last: int = int(_last_write_ms_by_board.get(name, 0))
	if now - last < 1000:
		score_failed.emit(name, "Throttled")
		return false
	_last_write_ms_by_board[name] = now

	var ok: bool = await _core.get_adapter().set_leaderboard_score(name, score, extra_data)
	if ok:
		score_set.emit(name, score)
	else:
		score_failed.emit(name, "Failed to set score")
	return ok


func set_score_debounced(name: String, score: int, extra_data: String = "", delay_sec: float = 1.0) -> void:
	if not is_set_score_supported():
		return

	_debounce_seq += 1
	var current_seq: int = _debounce_seq
	if _pending_scores.has(name):
		var prev: Dictionary = _pending_scores[name]
		prev["score"] = score
		prev["extra_data"] = extra_data
		prev["seq"] = current_seq
	else:
		_pending_scores[name] = { "score": score, "extra_data": extra_data, "seq": current_seq }

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(delay_sec).timeout

	if _pending_scores.has(name):
		var data: Dictionary = _pending_scores[name]
		if int(data.get("seq", -1)) == current_seq:
			_pending_scores.erase(name)
			await set_score(name, int(data.get("score", 0)), str(data.get("extra_data", "")))


# ------------------------------------------------------------------
#  Read entries
# ------------------------------------------------------------------

func get_player_entry(name: String) -> Dictionary:
	if not is_get_entries_supported():
		return {}
	return await _core.get_adapter().get_leaderboard_player_entry(name)


func get_entries(name: String, options: Dictionary = {}) -> Dictionary:
	if not is_get_entries_supported():
		return {}

	if not is_full_leaderboard_available():
		var entry: Dictionary = await _core.get_adapter().get_leaderboard_player_entry(name)
		return {
			"leaderboard": { "name": name, "title": name.capitalize() },
			"entries": [entry] if entry.get("score", 0) > 0 else [],
			"userRank": entry.get("rank", 0)
		}

	var opts := options.duplicate()
	if opts.has("quantityTop"):
		opts["quantityTop"] = clampi(int(opts["quantityTop"]), 1, 20)
	if opts.has("quantityAround"):
		opts["quantityAround"] = clampi(int(opts["quantityAround"]), 1, 10)

	return await _core.get_adapter().get_leaderboard_entries(name, opts)


# ------------------------------------------------------------------
#  Avatar helper
# ------------------------------------------------------------------

func load_avatar_texture(avatar_url: String, fallback_name: String = "Player") -> Texture2D:
	if _core and _core.player:
		return await _core.player.load_texture_from_url(avatar_url, fallback_name)
	return null
