@tool
class_name UniPlatformProfile
extends RefCounted

var id: String = ""
var display_name: String = ""
var enabled: bool = true
var preset_name: String = ""
var template_path: String = ""
var output_dir: String = ""
var make_zip: bool = true
var zip_name: String = ""
var create_hosting_config: bool = false
var hosting_config_name: String = ""
var hosting_config_default: Dictionary = {}

static func from_dict(id: String, d: Dictionary) -> UniPlatformProfile:
	var p := UniPlatformProfile.new()
	p.id = id
	p.display_name = str(d.get("display_name", id.capitalize()))
	p.enabled = bool(d.get("enabled", true))
	p.preset_name = str(d.get("preset_name", "Web (%s)" % p.display_name))
	p.template_path = str(d.get("template_path", ""))
	p.output_dir = str(d.get("output_dir", "res://build/%s" % id))
	p.make_zip = bool(d.get("make_zip", true))
	p.zip_name = str(d.get("zip_name", "%s_build.zip" % id))
	p.create_hosting_config = bool(d.get("create_hosting_config", false))
	p.hosting_config_name = str(d.get("hosting_config_name", ""))
	var hcd: Variant = d.get("hosting_config_default", {})
	p.hosting_config_default = hcd if hcd is Dictionary else {}
	return p

func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"enabled": enabled,
		"preset_name": preset_name,
		"template_path": template_path,
		"output_dir": output_dir,
		"make_zip": make_zip,
		"zip_name": zip_name,
		"create_hosting_config": create_hosting_config,
		"hosting_config_name": hosting_config_name,
		"hosting_config_default": hosting_config_default,
	}

func duplicate_profile() -> UniPlatformProfile:
	return UniPlatformProfile.from_dict(id, to_dict())
