@tool
class_name UniDevice
extends RefCounted

signal fullscreen_changed(is_fullscreen: bool)

var _core: Node
var _info: Dictionary = {
	"type": "desktop", "isMobile": false, "isTablet": false, "isDesktop": true, "isTV": false
}

func _init(core: Node) -> void:
	_core = core

func _update_info(info: Dictionary) -> void:
	_info = info

func get_type() -> String: return str(_info.get("type", "desktop"))
func is_mobile() -> bool: return bool(_info.get("isMobile", false))
func is_tablet() -> bool: return bool(_info.get("isTablet", false))
func is_desktop() -> bool: return bool(_info.get("isDesktop", true))
func is_tv() -> bool: return bool(_info.get("isTV", false))

func is_fullscreen() -> bool:
	return await _core.get_adapter().is_fullscreen()

func request_fullscreen() -> bool:
	var ok: bool = await _core.get_adapter().request_fullscreen()
	if ok: fullscreen_changed.emit(true)
	return ok

func exit_fullscreen() -> bool:
	var ok: bool = await _core.get_adapter().exit_fullscreen()
	if ok: fullscreen_changed.emit(false)
	return ok

func get_orientation() -> String:
	return await _core.get_adapter().get_orientation()

func set_orientation(value: String) -> bool:
	return await _core.get_adapter().set_orientation(value)
