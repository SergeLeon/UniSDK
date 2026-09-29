@tool
class_name YandexShortcutButton
extends Button

signal shortcut_prompt_completed(outcome: String)
signal shortcut_check_completed(can_show: bool)

@export var auto_check_on_ready: bool = true
@export var hide_when_unsupported: bool = true
@export var hide_after_installed: bool = true

var is_eligible: bool = true

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	pressed.connect(_on_pressed)
	if auto_check_on_ready:
		check_eligibility()

func _get_sdk() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("UniSDK")
	return null

func check_eligibility() -> bool:
	var yg := _get_sdk()
	if not yg or not yg.get("shortcut"):
		return false
	is_eligible = await yg.shortcut.can_show_prompt()
	shortcut_check_completed.emit(is_eligible)
	if hide_when_unsupported:
		visible = is_eligible
	return is_eligible

func _on_pressed() -> void:
	var yg := _get_sdk()
	if not yg or not yg.get("shortcut"):
		return
	disabled = true
	var res: Dictionary = await yg.shortcut.show_prompt()
	disabled = false
	var outcome: String = str(res.get("outcome", "rejected"))
	shortcut_prompt_completed.emit(outcome)
	if outcome == "accepted" and hide_after_installed:
		visible = false
