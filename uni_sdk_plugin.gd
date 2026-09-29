@tool
extends EditorPlugin

const AUTOLOAD_NAME: String = "UniSDK"
const AUTOLOAD_PATH: String = "res://addons/uni_sdk/uni_sdk.gd"

var _export_plugin: UniSDKExportPlugin = null
var _config_dialog: UniPlatformConfigDialog = null

func _enter_tree() -> void:
	_setup_project_settings()
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	UniPlatformRegistry.ensure_defaults()

	_export_plugin = UniSDKExportPlugin.new()
	add_export_plugin(_export_plugin)

	add_tool_menu_item("UniSDK: Configure Platforms...", _on_configure_platforms)
	add_tool_menu_item("UniSDK: Create Selected Presets", _on_create_selected_presets)
	add_tool_menu_item("UniSDK: Export Selected Builds", _on_export_selected_builds)
	add_tool_menu_item("UniSDK: Reset Mock Data", _on_reset_mock)
	add_tool_menu_item("UniSDK: Reset Player Backup", _on_reset_player_backup)
	add_tool_menu_item("UniSDK: Open Documentation", _on_open_docs)

func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	remove_tool_menu_item("UniSDK: Configure Platforms...")
	remove_tool_menu_item("UniSDK: Create Selected Presets")
	remove_tool_menu_item("UniSDK: Export Selected Builds")
	remove_tool_menu_item("UniSDK: Reset Mock Data")
	remove_tool_menu_item("UniSDK: Reset Player Backup")
	remove_tool_menu_item("UniSDK: Open Documentation")

	if _config_dialog and is_instance_valid(_config_dialog):
		_config_dialog.queue_free()
		_config_dialog = null

	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null

func _setup_project_settings() -> void:
	_add_setting("uni_sdk/general/auto_init", true, TYPE_BOOL)
	_add_setting("uni_sdk/general/auto_call_game_ready", true, TYPE_BOOL)
	_add_setting("uni_sdk/general/auto_apply_locale", true, TYPE_BOOL)
	_add_setting("uni_sdk/general/auto_pause_tree", false, TYPE_BOOL)
	_add_setting("uni_sdk/general/debug_log", false, TYPE_BOOL)
	_add_setting("uni_sdk/ads/auto_mute_audio", true, TYPE_BOOL)
	_add_setting("uni_sdk/ads/interstitial_cooldown", 60.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,300,1")
	_add_setting("uni_sdk/player/get_data_min_interval_sec", 15.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,120,1")
	_add_setting("uni_sdk/payments/auto_check_unconsumed", true, TYPE_BOOL)
	_add_setting("uni_sdk/mock/player_name", "Test Player (Editor)", TYPE_STRING)
	_add_setting("uni_sdk/mock/player_unique_id", "mock_player_12345", TYPE_STRING)
	_add_setting("uni_sdk/mock/is_authorized", true, TYPE_BOOL)

func _add_setting(p_name: String, p_default, p_type: int, p_hint: int = PROPERTY_HINT_NONE, p_hint_string: String = "") -> void:
	if not ProjectSettings.has_setting(p_name):
		ProjectSettings.set_setting(p_name, p_default)
	ProjectSettings.set_initial_value(p_name, p_default)
	ProjectSettings.add_property_info({
		"name": p_name, "type": p_type, "hint": p_hint, "hint_string": p_hint_string
	})

# --- Меню ---

func _on_configure_platforms() -> void:
	var base: Node = EditorInterface.get_base_control()
	if base == null:
		printerr("[UniSDK] Cannot access editor base control")
		return
	if _config_dialog and is_instance_valid(_config_dialog):
		_config_dialog.queue_free()
	_config_dialog = UniPlatformConfigDialog.new()
	base.add_child(_config_dialog)
	_config_dialog.tree_exited.connect(func():
		if _config_dialog and not is_instance_valid(_config_dialog):
			_config_dialog = null
	)
	_config_dialog.popup_centered()

func _on_create_selected_presets() -> void:
	print("[UniSDK] Creating presets for enabled platforms...")
	var res := UniSDKExportPlugin.create_presets_from_registry()
	if res.get("success", false):
		print("[UniSDK] %s" % res.get("message", ""))
		_dump_web_presets()
	else:
		printerr("[UniSDK] %s" % res.get("message", "unknown error"))

func _on_export_selected_builds() -> void:
	print("[UniSDK] Exporting enabled platforms... (may take a minute)")
	var ei: EditorInterface = get_editor_interface()
	if ei:
		ei.save_all_scenes()

	var res := UniSDKExportPlugin.export_enabled_platforms()
	if res.get("success", false):
		print("[UniSDK] Export complete.")
		var results: Dictionary = res.get("results", {})
		for id in results:
			var r: Dictionary = results[id]
			var p := UniPlatformRegistry.get_profile(id)
			print("  %s -> %s" % [p.display_name, r.get("output_dir", "")])
			if not str(r.get("zip_path", "")).is_empty():
				print("    ZIP: %s" % r.get("zip_path", ""))
		_print_deploy_hints()
	else:
		printerr("[UniSDK] Export failed: %s" % res.get("error", "unknown error"))

func _print_deploy_hints() -> void:
	for p in UniPlatformRegistry.get_enabled_profiles():
		if p.create_hosting_config and not p.hosting_config_name.is_empty():
			var rel_dir: String = p.output_dir.replace("res://", "")
			print("[UniSDK] %s deploy:" % p.display_name)
			print("  1. Fill credentials in %s/%s" % [rel_dir, p.hosting_config_name])
			print("  2. Run: cd %s && npx %s" % [rel_dir, UniSDKExportPlugin.VK_DEPLOY_NPM_PACKAGE])

func _dump_web_presets() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return
	print("[UniSDK] Web presets in export_presets.cfg:")
	for section in cfg.get_sections():
		if not section.begins_with("preset."):
			continue
		if str(cfg.get_value(section, "platform", "")) != "Web":
			continue
		var pname: String = str(cfg.get_value(section, "name", "<unnamed>"))
		var opt := section + ".options"
		var shell: String = str(cfg.get_value(opt, "html/custom_html_shell", "<empty>"))
		print("    [%s] %s shell=%s" % [section, pname, shell])

func _on_reset_mock() -> void:
	var path: String = "user://unisdk_mock_data.json"
	if FileAccess.file_exists(path):
		var dir := DirAccess.open("user://")
		if dir and dir.remove("unisdk_mock_data.json") == OK:
			print("[UniSDK] Mock storage reset: %s" % path)
		else:
			printerr("[UniSDK] Failed to remove %s" % path)
	else:
		print("[UniSDK] No mock storage file found.")

func _on_reset_player_backup() -> void:
	var path: String = "user://unisdk_player_backup.json"
	if FileAccess.file_exists(path):
		var dir := DirAccess.open("user://")
		if dir and dir.remove("unisdk_player_backup.json") == OK:
			print("[UniSDK] Player backup reset: %s" % path)
		else:
			printerr("[UniSDK] Failed to remove %s" % path)
	else:
		print("[UniSDK] No player backup file found.")

func _on_open_docs() -> void:
	OS.shell_open("https://github.com/")
