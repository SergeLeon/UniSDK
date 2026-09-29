@tool
class_name UniLeaderboards
extends RefCounted

signal score_set(leaderboard_name: String, score: int)
signal score_failed(leaderboard_name: String, error: String)

const TAG := "leaderboards"

var _core: Node
var _pending_scores: Dictionary = {}
var _debounce_seq: int = 0
var _last_write_ms_by_board: Dictionary = {}

func _init(core: Node) -> void:
	_core = core

func get_description(name: String) -> Dictionary:
	return await _core.get_adapter().get_leaderboard_description(name)

func set_score(name: String, score: int, extra_data: String = "") -> bool:
	if not _core.player.is_authorized() and _core.get_platform() == "yandex":
		UniLogger.warn(TAG, "set_score skipped: player not authorized")
		score_failed.emit(name, "Not authorized")
		return false

	# Троттлинг 1 запрос/сек
	var now: int = Time.get_ticks_msec()
	var last: int = int(_last_write_ms_by_board.get(name, 0))
	if now - last < 1000:
		UniLogger.warn(TAG, "set_score throttled (1/sec) for '%s'" % name)
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

func get_player_entry(name: String) -> Dictionary:
	return await _core.get_adapter().get_leaderboard_player_entry(name)

func get_entries(name: String, options: Dictionary = {}) -> Dictionary:
	var opts := options.duplicate()
	if opts.has("quantityTop"):
		opts["quantityTop"] = clampi(int(opts["quantityTop"]), 1, 20)
	if opts.has("quantityAround"):
		opts["quantityAround"] = clampi(int(opts["quantityAround"]), 1, 10)
	return await _core.get_adapter().get_leaderboard_entries(name, opts)

func load_avatar_texture(avatar_url: String, fallback_name: String = "Player") -> Texture2D:
	if _core and _core.player:
		return await _core.player.load_texture_from_url(avatar_url, fallback_name)
	return null
