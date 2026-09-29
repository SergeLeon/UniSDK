@tool
class_name UniStorage
extends RefCounted

var _core: Node

func _init(core: Node) -> void:
	_core = core

func get_item(key: String, default_value: String = "") -> String:
	return await _core.get_adapter().storage_get(key, default_value)

func set_item(key: String, value: String) -> bool:
	return await _core.get_adapter().storage_set(key, value)
