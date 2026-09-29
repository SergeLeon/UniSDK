@tool
class_name UniAds
extends RefCounted

signal interstitial_opened
signal interstitial_closed(was_shown: bool)
signal interstitial_failed(error: String)
signal interstitial_cooldown_finished
signal rewarded_opened
signal rewarded_rewarded
signal rewarded_closed(was_shown: bool)
signal rewarded_failed(error: String)
signal banner_shown
signal banner_hidden
signal banner_status_changed(is_showing: bool, reason: String)

var _core: Node
var cooldown_duration: float = 60.0
var _last_interstitial_time: float = -999999.0
var is_banner_showing: bool = false
var banner_height_pixels: int = 70

var _cooldown_token: int = 0

func _init(core: Node) -> void:
	_core = core
	cooldown_duration = float(ProjectSettings.get_setting("uni_sdk/ads/interstitial_cooldown", 60.0))

func can_show_interstitial() -> bool:
	return get_time_until_next_interstitial() <= 0.0

func get_time_until_next_interstitial() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - _last_interstitial_time
	return max(0.0, cooldown_duration - elapsed)

func show_interstitial_if_available(ignore_cooldown: bool = false) -> Dictionary:
	if not ignore_cooldown and not can_show_interstitial():
		return { "success": false, "was_shown": false, "error": "Cooldown active" }
	return await show_interstitial()

func show_interstitial() -> Dictionary:
	_core._prepare_ad_call()
	interstitial_opened.emit()

	var result: Dictionary = await _core.get_adapter().show_interstitial()

	_core._finish_ad_call()

	if result.get("success", false):
		interstitial_closed.emit(result.get("was_shown", false))
		if result.get("was_shown", false):
			_last_interstitial_time = Time.get_ticks_msec() / 1000.0
			_schedule_cooldown_timer()
	else:
		interstitial_failed.emit(str(result.get("error", "Unknown error")))

	return result

func _schedule_cooldown_timer() -> void:
	var tree: SceneTree = _core.get_tree()
	if tree == null:
		return
	_cooldown_token += 1
	var my_token: int = _cooldown_token
	await tree.create_timer(cooldown_duration).timeout
	if my_token == _cooldown_token:
		interstitial_cooldown_finished.emit()

func show_rewarded() -> Dictionary:
	_core._prepare_ad_call()
	rewarded_opened.emit()

	var result: Dictionary = await _core.get_adapter().show_rewarded()

	_core._finish_ad_call()

	if result.get("rewarded", false):
		rewarded_rewarded.emit()

	if result.get("success", false):
		rewarded_closed.emit(result.get("was_shown", false))
	else:
		rewarded_failed.emit(str(result.get("error", "Unknown error")))

	return result

func show_banner() -> Dictionary:
	var result: Dictionary = await _core.get_adapter().show_banner()
	if result.get("stickyAdvIsShowing", false):
		is_banner_showing = true
		banner_shown.emit()
	banner_status_changed.emit(is_banner_showing, str(result.get("reason", "")))
	return result

func hide_banner() -> Dictionary:
	var result: Dictionary = await _core.get_adapter().hide_banner()
	is_banner_showing = false
	banner_hidden.emit()
	banner_status_changed.emit(false, "")
	return result

func get_banner_status() -> Dictionary:
	var result: Dictionary = await _core.get_adapter().get_banner_status()
	is_banner_showing = result.get("stickyAdvIsShowing", result.get("is_showing", false))
	banner_status_changed.emit(is_banner_showing, str(result.get("reason", "")))
	return { "is_showing": is_banner_showing, "reason": str(result.get("reason", "")) }
