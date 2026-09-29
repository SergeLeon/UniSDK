@tool
class_name UniFeedback
extends RefCounted

signal review_requested(feedback_sent: bool)

var _core: Node

func _init(core: Node) -> void:
	_core = core

func can_review() -> Dictionary:
	return await _core.get_adapter().can_review()

func request_review() -> Dictionary:
	var res: Dictionary = await _core.get_adapter().request_review()
	review_requested.emit(res.get("feedback_sent", false))
	return res
