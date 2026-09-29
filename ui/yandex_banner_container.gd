@tool
class_name YandexBannerContainer
extends MarginContainer

enum BannerPosition { BOTTOM, TOP }

@export var banner_position: BannerPosition = BannerPosition.BOTTOM:
	set(val):
		banner_position = val
		_update_margins(false)

@export var banner_height_pixels: int = 70:
	set(val):
		banner_height_pixels = val
		_update_margins(false)

@export var animate: bool = true
@export var animation_duration: float = 0.25

@export var editor_preview_banner: bool = false:
	set(val):
		editor_preview_banner = val
		_update_margins(false)

var _tween: Tween = null
var _is_banner_active: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_margins(false)
		return

	var yg: Node = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		yg = tree.root.get_node_or_null("UniSDK")
	if yg and yg.get("ads"):
		var ads = yg.get("ads")
		ads.banner_shown.connect(_on_banner_shown)
		ads.banner_hidden.connect(_on_banner_hidden)
		ads.banner_status_changed.connect(_on_banner_status_changed)
		_is_banner_active = bool(ads.get("is_banner_showing"))

	_update_margins(false)

func _on_banner_shown() -> void:
	_is_banner_active = true
	_update_margins(animate)

func _on_banner_hidden() -> void:
	_is_banner_active = false
	_update_margins(animate)

func _on_banner_status_changed(is_showing: bool, _reason: String) -> void:
	_is_banner_active = is_showing
	_update_margins(animate)

func _update_margins(use_animation: bool) -> void:
	var should_offset: bool = editor_preview_banner or _is_banner_active
	var target_margin: int = banner_height_pixels if should_offset else 0
	var margin_name: String = "margin_bottom" if banner_position == BannerPosition.BOTTOM else "margin_top"

	if _tween and _tween.is_running():
		_tween.kill()

	if use_animation and not Engine.is_editor_hint() and is_inside_tree():
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var current_val: int = get_theme_constant(margin_name)
		_tween.tween_method(
			func(val: int) -> void: add_theme_constant_override(margin_name, val),
			current_val,
			target_margin,
			animation_duration
		)
	else:
		add_theme_constant_override(margin_name, target_margin)
