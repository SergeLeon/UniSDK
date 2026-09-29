@tool
class_name YandexReviewButton
extends Button

signal review_completed(feedback_sent: bool)
signal review_check_completed(can_review: bool, reason: String)

@export var auto_check_on_ready: bool = true
@export var hide_when_unsupported: bool = true
@export var hide_after_reviewed: bool = true

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
	if not yg or not yg.get("feedback"):
		return false
	var res: Dictionary = await yg.feedback.can_review()
	is_eligible = bool(res.get("value", false))
	review_check_completed.emit(is_eligible, str(res.get("reason", "")))
	if hide_when_unsupported:
		visible = is_eligible
	return is_eligible

func _on_pressed() -> void:
	var yg := _get_sdk()
	if not yg or not yg.get("feedback"):
		return
	disabled = true
	var res: Dictionary = await yg.feedback.request_review()
	disabled = false
	var sent: bool = bool(res.get("feedback_sent", false))
	review_completed.emit(sent)
	if sent and hide_after_reviewed:
		visible = false
