@tool
class_name UniShortcut
extends RefCounted

signal prompt_shown(outcome: String)

var _core: Node

func _init(core: Node) -> void:
	_core = core

func can_show_prompt() -> bool:
	return await _core.get_adapter().can_show_shortcut_prompt()

func show_prompt() -> Dictionary:
	var res: Dictionary = await _core.get_adapter().show_shortcut_prompt()
	prompt_shown.emit(res.get("outcome", "rejected"))
	return res
