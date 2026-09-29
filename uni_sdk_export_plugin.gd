@tool
class_name UniSDKExportPlugin
extends EditorExportPlugin

const VK_DEPLOY_NPM_PACKAGE: String = "@vkontakte/vk-miniapps-deploy"

func _get_name() -> String:
	return "UniSDK"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformWeb

# ------------------------------------------------------------------
#  Пресеты
# ------------------------------------------------------------------

static func create_presets_from_registry() -> Dictionary:
	var presets_path := "res://export_presets.cfg"

	if FileAccess.file_exists(presets_path):
		var src := FileAccess.open(presets_path, FileAccess.READ)
		if src:
			var dst := FileAccess.open(presets_path + ".bak", FileAccess.WRITE)
			if dst:
				dst.store_string(src.get_as_text())
				dst.close()
			src.close()

	var cfg := ConfigFile.new()
	var err := cfg.load(presets_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		return { "success": false, "message": "Cannot load %s (err %d)" % [presets_path, err], "results": {} }

	var enabled := UniPlatformRegistry.get_enabled_profiles()
	if enabled.is_empty():
		return {
			"success": false,
			"message": "No platforms enabled. Open Project -> Tools -> UniSDK: Configure Platforms",
			"results": {}
		}

	var next_idx := 0
	var existing_by_name: Dictionary = {}
	for section in cfg.get_sections():
		if not section.begins_with("preset."):
			continue
		var n := section.trim_prefix("preset.")
		if n.is_valid_int():
			next_idx = maxi(next_idx, n.to_int() + 1)
		if str(cfg.get_value(section, "platform", "")) == "Web":
			var pname := str(cfg.get_value(section, "name", ""))
			if not pname.is_empty() and not existing_by_name.has(pname):
				existing_by_name[pname] = section

	var results: Dictionary = {}
	for p in enabled:
		var section: String = str(existing_by_name.get(p.preset_name, ""))
		var created := false
		if section.is_empty():
			section = "preset.%d" % next_idx
			next_idx += 1
			created = true
		_write_preset_section(cfg, section, p)
		results[p.id] = { "section": section, "created": created }

	if cfg.save(presets_path) != OK:
		return { "success": false, "message": "Cannot save %s" % presets_path, "results": results }

	_force_reload_export_presets()

	return {
		"success": true,
		"message": "Processed %d platform(s): %s" % [enabled.size(), ", ".join(_names(enabled))],
		"results": results
	}

static func _names(profiles: Array[UniPlatformProfile]) -> Array[String]:
	var out: Array[String] = []
	for p in profiles:
		out.append(p.display_name)
	return out

static func _write_preset_section(cfg: ConfigFile, section: String, p: UniPlatformProfile) -> void:
	cfg.set_value(section, "name", p.preset_name)
	cfg.set_value(section, "platform", "Web")
	cfg.set_value(section, "runnable", true)
	cfg.set_value(section, "advanced_options", false)
	cfg.set_value(section, "dedicated_server", false)
	cfg.set_value(section, "custom_features", "")
	cfg.set_value(section, "export_filter", "all_resources")
	cfg.set_value(section, "include_filter", "")
	cfg.set_value(section, "exclude_filter", "")
	cfg.set_value(section, "export_path", p.output_dir + "/index.html")
	cfg.set_value(section, "patches", PackedStringArray())
	cfg.set_value(section, "encryption_include_filters", "")
	cfg.set_value(section, "encryption_exclude_filters", "")
	cfg.set_value(section, "seed", 0)
	cfg.set_value(section, "encrypt_pck", false)
	cfg.set_value(section, "encrypt_directory", false)
	cfg.set_value(section, "script_export_mode", 2)

	var opt := section + ".options"
	cfg.set_value(opt, "custom_template/debug", "")
	cfg.set_value(opt, "custom_template/release", "")
	cfg.set_value(opt, "variant/extensions_support", false)
	cfg.set_value(opt, "variant/thread_support", false)
	cfg.set_value(opt, "vram_texture_compression/for_desktop", true)
	cfg.set_value(opt, "vram_texture_compression/for_mobile", false)
	cfg.set_value(opt, "html/export_icon", true)
	cfg.set_value(opt, "html/custom_html_shell", p.template_path)
	cfg.set_value(opt, "html/head_include", "")
	cfg.set_value(opt, "html/canvas_resize_policy", 2)
	cfg.set_value(opt, "html/focus_canvas_on_start", true)
	cfg.set_value(opt, "html/experimental_virtual_keyboard", false)
	cfg.set_value(opt, "progressive_web_app/enabled", false)
	cfg.set_value(opt, "progressive_web_app/ensure_cross_origin_isolation_headers", true)
	cfg.set_value(opt, "progressive_web_app/offline_page", "")
	cfg.set_value(opt, "progressive_web_app/display", 1)
	cfg.set_value(opt, "progressive_web_app/orientation", 0)
	cfg.set_value(opt, "progressive_web_app/icon_144x144", "")
	cfg.set_value(opt, "progressive_web_app/icon_180x180", "")
	cfg.set_value(opt, "progressive_web_app/icon_512x512", "")
	cfg.set_value(opt, "progressive_web_app/background_color", Color(0, 0, 0, 1))

static func _force_reload_export_presets() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		efs.scan()

# ------------------------------------------------------------------
#  Экспорт
# ------------------------------------------------------------------

static func export_enabled_platforms() -> Dictionary:
	var presets_res := create_presets_from_registry()
	if not presets_res.get("success", false):
		return { "success": false, "error": "Preset creation failed: %s" % presets_res.get("message", ""), "results": {} }

	var enabled := UniPlatformRegistry.get_enabled_profiles()
	if enabled.is_empty():
		return { "success": false, "error": "No platforms enabled", "results": {} }

	var godot_path := OS.get_executable_path()
	if godot_path.is_empty() or not FileAccess.file_exists(godot_path):
		return { "success": false, "error": "Godot executable not found: %s" % godot_path, "results": {} }

	var project_path := ProjectSettings.globalize_path("res://")

	var results: Dictionary = {}
	for p in enabled:
		var r := _export_single_platform(p, godot_path, project_path)
		results[p.id] = r
		if not r.get("success", false):
			return {
				"success": false,
				"error": "%s export failed: %s" % [p.display_name, r.get("error", "")],
				"results": results
			}

	return { "success": true, "error": "", "results": results }

static func _export_single_platform(p: UniPlatformProfile, godot_path: String, project_path: String) -> Dictionary:
	var abs_dir := ProjectSettings.globalize_path(p.output_dir)

	var hosting_backup: Dictionary = {}
	var hosting_path := abs_dir.path_join(p.hosting_config_name)
	if p.create_hosting_config and not p.hosting_config_name.is_empty():
		if FileAccess.file_exists(hosting_path):
			var f := FileAccess.open(hosting_path, FileAccess.READ)
			if f:
				var j := JSON.new()
				if j.parse(f.get_as_text()) == OK and j.data is Dictionary:
					hosting_backup = j.data
				f.close()
			if not hosting_backup.is_empty():
				print("[UniSDK] Preserving %s across re-export" % p.hosting_config_name)

	_remove_dir_recursive(abs_dir)
	if not _make_dir_recursive(abs_dir):
		return { "success": false, "error": "Cannot create %s" % abs_dir }

	if not hosting_backup.is_empty():
		var f := FileAccess.open(hosting_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(hosting_backup, "  "))
			f.close()

	print("[UniSDK] Exporting %s -> %s" % [p.display_name, abs_dir])
	var index_path := abs_dir.path_join("index.html")
	var export_res := _run_export(godot_path, project_path, p.preset_name, index_path)
	if not export_res.get("success", false):
		return { "success": false, "error": export_res.get("error", "") }

	if not FileAccess.file_exists(index_path):
		return { "success": false, "error": "index.html not created at %s" % index_path }

	if p.create_hosting_config and not p.hosting_config_name.is_empty():
		var hc_res := _create_hosting_config_file(abs_dir, p)
		if not hc_res.get("success", false):
			printerr("[UniSDK] Hosting config: %s" % hc_res.get("error", ""))
		elif hc_res.get("created", false):
			print("[UniSDK] %s" % hc_res.get("message", ""))

	var zip_path := ""
	if p.make_zip:
		var zip_name: String = p.zip_name if not p.zip_name.is_empty() else "%s_build.zip" % p.id
		zip_path = abs_dir.path_join(zip_name)
		print("[UniSDK] Packaging %s -> %s" % [p.display_name, zip_path])
		var exclude: Array[String] = []
		if p.create_hosting_config and not p.hosting_config_name.is_empty():
			exclude.append(p.hosting_config_name)
		if not _zip_directory(abs_dir, zip_path, exclude):
			return { "success": false, "error": "Cannot create ZIP: %s" % zip_path }

	return {
		"success": true,
		"output_dir": abs_dir,
		"index_path": index_path,
		"zip_path": zip_path,
		"profile": p
	}

static func _create_hosting_config_file(abs_dir: String, p: UniPlatformProfile) -> Dictionary:
	var path := abs_dir.path_join(p.hosting_config_name)
	if FileAccess.file_exists(path):
		return { "success": true, "created": false, "message": "%s already exists" % path, "error": "" }

	var content: Dictionary = p.hosting_config_default.duplicate(true)
	if content.is_empty():
		content = { "app_id": 0, "access_token": "<TOKEN>" }

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return { "success": false, "created": false, "message": "", "error": "Cannot write %s" % path }
	f.store_string(JSON.stringify(content, "  "))
	f.close()

	return {
		"success": true,
		"created": true,
		"message": "Created %s - fill in credentials." % path,
		"error": ""
	}

static func _run_export(godot_path: String, project_path: String, preset_name: String, output_path: String) -> Dictionary:
	var args: PackedStringArray = PackedStringArray([
		"--headless",
		"--path", project_path,
		"--export-release", preset_name,
		output_path
	])

	var output: Array = []
	var exit_code: int = OS.execute(godot_path, args, output, true)

	var log_text := ""
	for line in output:
		log_text += str(line) + "\n"

	if exit_code != 0:
		printerr("[UniSDK] Export '%s' exited with code %d" % [preset_name, exit_code])
		var lines: PackedStringArray = log_text.split("\n")
		var start: int = maxi(0, lines.size() - 40)
		for i in range(start, lines.size()):
			printerr("[UniSDK]   ", lines[i])
		return { "success": false, "error": "Exit code %d" % exit_code, "log": log_text }

	if not FileAccess.file_exists(output_path):
		printerr("[UniSDK] Export '%s' finished with code 0, but output missing" % preset_name)
		return { "success": false, "error": "Output not created", "log": log_text }

	return { "success": true }

# ------------------------------------------------------------------
#  ZIP
# ------------------------------------------------------------------

static func package_dir_to_zip(source_dir_abs: String, output_zip_abs: String, exclude_names: Array[String] = []) -> bool:
	return _zip_directory(source_dir_abs, output_zip_abs, exclude_names)

static func _zip_directory(source_dir: String, output_zip: String, exclude_names: Array[String] = []) -> bool:
	var packer := ZIPPacker.new()
	if packer.open(output_zip) != OK:
		return false

	var add_recursive: Callable
	add_recursive = func(cur_dir: String, rel: String) -> int:
		var dir := DirAccess.open(cur_dir)
		if not dir:
			return 0
		var count := 0
		dir.list_dir_begin()
		var f := dir.get_next()
		while not f.is_empty():
			if f != "." and f != "..":
				var full := cur_dir.path_join(f)
				var entry := f if rel.is_empty() else rel.path_join(f)
				entry = entry.replace("\\", "/")
				if dir.current_is_dir():
					count += add_recursive.call(full, entry)
				else:
					if f.ends_with(".zip") or f in exclude_names:
						f = dir.get_next()
						continue
					var file := FileAccess.open(full, FileAccess.READ)
					if file:
						packer.start_file(entry)
						packer.write_file(file.get_buffer(file.get_length()))
						packer.close_file()
						count += 1
			f = dir.get_next()
		dir.list_dir_end()
		return count

	add_recursive.call(source_dir, "")
	packer.close()
	return true

# ------------------------------------------------------------------
#  Директории
# ------------------------------------------------------------------

static func _make_dir_recursive(abs_path: String) -> bool:
	if DirAccess.dir_exists_absolute(abs_path):
		return true
	var err := DirAccess.make_dir_recursive_absolute(abs_path)
	return err == OK or DirAccess.dir_exists_absolute(abs_path)

static func _remove_dir_recursive(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var dir := DirAccess.open(abs_path)
	if not dir:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while not f.is_empty():
		if f != "." and f != "..":
			var full := abs_path.path_join(f)
			if dir.current_is_dir():
				_remove_dir_recursive(full)
			else:
				dir.remove(f)
		f = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_path)
