@tool
class_name UniPlatformRegistry
extends RefCounted

const LIST_KEY := "uni_sdk/platform_list"
const PLATFORM_KEY_PREFIX := "uni_sdk/platforms/"

static func get_all_ids() -> PackedStringArray:
	if not ProjectSettings.has_setting(LIST_KEY):
		return PackedStringArray()
	var v: Variant = ProjectSettings.get_setting(LIST_KEY)
	if v is PackedStringArray:
		return v
	if v is Array:
		var out := PackedStringArray()
		for x in v:
			out.append(str(x))
		return out
	return PackedStringArray()

static func set_all_ids(ids: PackedStringArray) -> void:
	ProjectSettings.set_setting(LIST_KEY, ids)

static func has(id: String) -> bool:
	return id in get_all_ids()

static func get_profile(id: String) -> UniPlatformProfile:
	var d: Dictionary = {}
	var key := PLATFORM_KEY_PREFIX + id
	if ProjectSettings.has_setting(key):
		var v: Variant = ProjectSettings.get_setting(key)
		if v is Dictionary:
			d = v
	return UniPlatformProfile.from_dict(id, d)

static func save_profile(profile: UniPlatformProfile) -> void:
	var key := PLATFORM_KEY_PREFIX + profile.id
	ProjectSettings.set_setting(key, profile.to_dict())

	var ids := get_all_ids()
	if not profile.id in ids:
		ids.append(profile.id)
		set_all_ids(ids)

static func remove_profile(id: String) -> void:
	var key := PLATFORM_KEY_PREFIX + id
	if ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, null)
	var ids := get_all_ids()
	var new_ids := PackedStringArray()
	for x in ids:
		if x != id:
			new_ids.append(x)
	set_all_ids(new_ids)

static func get_all_profiles() -> Array[UniPlatformProfile]:
	var out: Array[UniPlatformProfile] = []
	for id in get_all_ids():
		out.append(get_profile(id))
	return out

static func get_enabled_profiles() -> Array[UniPlatformProfile]:
	var out: Array[UniPlatformProfile] = []
	for id in get_all_ids():
		var p := get_profile(id)
		if p.enabled:
			out.append(p)
	return out

static func ensure_defaults() -> void:
	if ProjectSettings.has_setting(LIST_KEY) and not get_all_ids().is_empty():
		return
	_register_defaults()

static func _register_defaults() -> void:
	var y := UniPlatformProfile.new()
	y.id = "yandex"
	y.display_name = "Yandex Games"
	y.enabled = true
	y.preset_name = "Web (Yandex Games)"
	y.template_path = "res://addons/uni_sdk/templates/yandex_template.html"
	y.output_dir = "res://build/yandex"
	y.make_zip = true
	y.zip_name = "yandex_build.zip"
	y.create_hosting_config = false
	save_profile(y)

	var vk := UniPlatformProfile.new()
	vk.id = "vk"
	vk.display_name = "VK Games"
	vk.enabled = true
	vk.preset_name = "Web (VK)"
	vk.template_path = "res://addons/uni_sdk/templates/vk_template.html"
	vk.output_dir = "res://build/vk"
	vk.make_zip = true
	vk.zip_name = "vk_build.zip"
	vk.create_hosting_config = true
	vk.hosting_config_name = "vk-hosting-config.json"
	vk.hosting_config_default = {
		"static_path": ".",
		"app_id": 0,
		"access_token": "<YOUR_VK_SERVICE_TOKEN>",
		"endpoints": {
			"mobile": "index.html",
			"mvk": "index.html",
			"web": "index.html"
		}
	}
	save_profile(vk)

static func reset_to_defaults() -> void:
	for id in get_all_ids():
		var key := PLATFORM_KEY_PREFIX + id
		if ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, null)
	if ProjectSettings.has_setting(LIST_KEY):
		ProjectSettings.set_setting(LIST_KEY, null)
	_register_defaults()
