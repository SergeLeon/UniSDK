@tool
class_name UniFeedback
extends RefCounted

signal review_requested(feedback_sent: bool)

var _core: Node

func _init(core: Node) -> void:
	_core = core


# ------------------------------------------------------------------
#  Platform capabilities
# ------------------------------------------------------------------

## Платформа поддерживает API отзывов вообще?
## Yandex: да. VK / OK: нет. Mock: да.
func is_review_supported() -> bool:
	if not _core.is_initialized:
		return true
	var platform: String = _core.get_platform()
	if platform == "mock":
		return true
	if platform == "vk":
		return false
	return true


func can_request_review() -> bool:
	return is_review_supported()


# ------------------------------------------------------------------
#  Review
# ------------------------------------------------------------------

func can_review() -> Dictionary:
	if not is_review_supported():
		return { "value": false, "reason": "NOT_SUPPORTED" }
	return await _core.get_adapter().can_review()


func request_review() -> Dictionary:
	if not is_review_supported():
		return { "value": false, "feedback_sent": false }
	var res: Dictionary = await _core.get_adapter().request_review()
	review_requested.emit(res.get("feedback_sent", false))
	return res