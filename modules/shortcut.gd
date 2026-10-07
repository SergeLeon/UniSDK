@tool
class_name UniShortcut
extends RefCounted

signal prompt_shown(outcome: String)

var _core: Node

func _init(core: Node) -> void:
	_core = core


# ------------------------------------------------------------------
#  Platform capabilities
# ------------------------------------------------------------------

## Платформа поддерживает ярлыки вообще?
## Yandex: да, и на десктопе, и на мобильных.
## VK / OK: только в мобильном приложении.
## Mock: да.
func is_shortcut_supported() -> bool:
	if not _core.is_initialized:
		return true
	var platform: String = _core.get_platform()
	if platform == "mock":
		return true
	if platform == "vk":
		return not _core.device.is_desktop()
	return true


func can_show_shortcut() -> bool:
	return is_shortcut_supported()


# ------------------------------------------------------------------
#  Shortcut
# ------------------------------------------------------------------

func can_show_prompt() -> bool:
	if not is_shortcut_supported():
		return false
	return await _core.get_adapter().can_show_shortcut_prompt()


func show_prompt() -> Dictionary:
	if not is_shortcut_supported():
		return { "outcome": "rejected" }
	var res: Dictionary = await _core.get_adapter().show_shortcut_prompt()
	prompt_shown.emit(res.get("outcome", "rejected"))
	return res