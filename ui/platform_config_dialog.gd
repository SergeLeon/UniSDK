@tool
class_name UniPlatformConfigDialog
extends AcceptDialog

signal config_saved()

var _scroll: ScrollContainer
var _list_vbox: VBoxContainer
var _widgets: Dictionary = {}
var _save_requested: bool = false

func _init() -> void:
	title = "UniSDK: Platform Configuration"
	ok_button_text = "Save"
	min_size = Vector2i(820, 680)
	close_requested.connect(_on_close_requested)
	_build_ui()

	# Валидация ДО закрытия — вешаемся на кнопку.
	get_ok_button().pressed.connect(_try_save)

func _build_ui() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 12)
	_scroll.add_child(_list_vbox)

	_rebuild_list()

func _rebuild_list() -> void:
	for c in _list_vbox.get_children():
		c.queue_free()
	_widgets.clear()

	var hint := Label.new()
	hint.text = "Configure which platforms UniSDK creates presets for and how they export.\n" \
		+ "Только включённые платформы участвуют в создании пресетов и экспорте.\n" \
		+ "Hosting config — JSON, который будет создан в папке сборки."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_vbox.add_child(hint)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.pressed.connect(_on_reset_defaults)
	_list_vbox.add_child(reset_btn)

	_list_vbox.add_child(HSeparator.new())

	for p in UniPlatformRegistry.get_all_profiles():
		_build_platform_section(p)

func _build_platform_section(p: UniPlatformProfile) -> void:
	var panel := PanelContainer.new()
	_list_vbox.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(pad)

	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	pad.add_child(section)

	var header := HBoxContainer.new()
	section.add_child(header)

	var en := CheckBox.new()
	en.text = p.display_name
	en.button_pressed = p.enabled
	en.add_theme_font_size_override("font_size", 16)
	header.add_child(en)

	var id_lbl := Label.new()
	id_lbl.text = "(id: %s)" % p.id
	id_lbl.modulate = Color(0.7, 0.7, 0.7)
	header.add_child(id_lbl)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	section.add_child(grid)

	var preset_edit := _make_line_edit(grid, "Preset name:", p.preset_name)
	var outdir_edit := _make_line_edit(grid, "Output directory:", p.output_dir)
	var tmpl_edit := _make_line_edit(grid, "HTML template:", p.template_path)

	grid.add_child(_make_label("Create ZIP:"))
	var zip_row := HBoxContainer.new()
	zip_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(zip_row)
	var zip_cb := CheckBox.new()
	zip_cb.button_pressed = p.make_zip
	zip_row.add_child(zip_cb)
	var zip_name_edit := LineEdit.new()
	zip_name_edit.text = p.zip_name
	zip_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zip_row.add_child(zip_name_edit)

	grid.add_child(_make_label("Hosting config:"))
	var host_row := HBoxContainer.new()
	host_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(host_row)
	var host_cb := CheckBox.new()
	host_cb.button_pressed = p.create_hosting_config
	host_row.add_child(host_cb)
	var host_name_edit := LineEdit.new()
	host_name_edit.text = p.hosting_config_name
	host_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(host_name_edit)

	var json_container := VBoxContainer.new()
	json_container.visible = p.create_hosting_config
	section.add_child(json_container)

	var json_label := Label.new()
	json_label.text = "Hosting config content (JSON):"
	json_container.add_child(json_label)

	var json_hint := Label.new()
	json_hint.text = "Секретные поля сохраняются при повторном экспорте, но не попадают в ZIP."
	json_hint.modulate = Color(0.7, 0.7, 0.7)
	json_hint.add_theme_font_size_override("font_size", 11)
	json_container.add_child(json_hint)

	var json_edit := TextEdit.new()
	json_edit.custom_minimum_size = Vector2(0, 180)
	json_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	json_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	json_edit.text = JSON.stringify(p.hosting_config_default, "  ")
	json_container.add_child(json_edit)

	var validate_btn := Button.new()
	validate_btn.text = "Validate JSON"
	validate_btn.pressed.connect(func(): _validate_json_for(json_edit))
	json_container.add_child(validate_btn)

	var error_lbl := Label.new()
	error_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	error_lbl.visible = false
	json_container.add_child(error_lbl)

	host_cb.toggled.connect(func(pressed: bool) -> void:
		json_container.visible = pressed
	)

	_widgets[p.id] = {
		"enabled": en,
		"preset_name": preset_edit,
		"output_dir": outdir_edit,
		"template_path": tmpl_edit,
		"make_zip": zip_cb,
		"zip_name": zip_name_edit,
		"create_hosting_config": host_cb,
		"hosting_config_name": host_name_edit,
		"hosting_config_default_json": json_edit,
		"hosting_config_error_label": error_lbl,
	}

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

func _make_line_edit(parent: GridContainer, label: String, value: String) -> LineEdit:
	parent.add_child(_make_label(label))
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit

# --- Валидация ---

func _validate_json_for(json_edit: TextEdit) -> bool:
	var parsed: Variant = _try_parse_json(json_edit.text)
	var err_label: Label = null
	for id in _widgets.keys():
		if _widgets[id].get("hosting_config_default_json") == json_edit:
			err_label = _widgets[id].get("hosting_config_error_label")
			break

	if parsed == null:
		if err_label:
			err_label.text = "Invalid JSON. Check syntax."
			err_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
			err_label.visible = true
		return false

	if err_label:
		err_label.text = "JSON is valid."
		err_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		err_label.visible = true
	return true

func _try_parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	if not (json.data is Dictionary):
		return null
	return json.data

# --- Сохранение ---

func _try_save() -> void:
	var any_error := false

	for id in _widgets.keys():
		var w: Dictionary = _widgets[id]
		var p := UniPlatformRegistry.get_profile(id)
		p.enabled = (w["enabled"] as CheckBox).button_pressed
		p.preset_name = (w["preset_name"] as LineEdit).text.strip_edges()
		p.output_dir = (w["output_dir"] as LineEdit).text.strip_edges()
		p.template_path = (w["template_path"] as LineEdit).text.strip_edges()
		p.make_zip = (w["make_zip"] as CheckBox).button_pressed
		p.zip_name = (w["zip_name"] as LineEdit).text.strip_edges()
		p.create_hosting_config = (w["create_hosting_config"] as CheckBox).button_pressed
		p.hosting_config_name = (w["hosting_config_name"] as LineEdit).text.strip_edges()

		if p.create_hosting_config:
			var json_edit: TextEdit = w["hosting_config_default_json"]
			var err_lbl: Label = w["hosting_config_error_label"]
			var parsed: Variant = _try_parse_json(json_edit.text)
			if parsed == null:
				err_lbl.text = "Invalid JSON. Fix before saving."
				err_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
				err_lbl.visible = true
				any_error = true
				continue
			p.hosting_config_default = parsed

		UniPlatformRegistry.save_profile(p)

	if any_error:
		printerr("[UniSDK] Fix JSON errors before saving.")
		return

	ProjectSettings.save()
	print("[UniSDK] Platform configuration saved.")
	config_saved.emit()
	queue_free()

func _on_reset_defaults() -> void:
	UniPlatformRegistry.reset_to_defaults()
	ProjectSettings.save()
	_rebuild_list()

func _on_close_requested() -> void:
	queue_free()
