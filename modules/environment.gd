@tool
class_name UniEnvironment
extends RefCounted

var _core: Node
var _env: Dictionary = {
	"app": {}, "browser": {}, "i18n": {}, "payload": "", "referrer": null
}

func _init(core: Node) -> void:
	_core = core

func _update_env(env: Dictionary) -> void:
	_env = env

func get_app_id() -> String: return str(_env.get("app", {}).get("id", ""))
func get_browser_lang() -> String: return str(_env.get("browser", {}).get("lang", "ru"))
func get_lang() -> String: return str(_env.get("i18n", {}).get("lang", "ru"))
func get_tld() -> String: return str(_env.get("i18n", {}).get("tld", "ru"))
func get_payload() -> String: return str(_env.get("payload", ""))

func get_referrer() -> Dictionary:
	var ref: Variant = _env.get("referrer")
	return ref if ref is Dictionary else {}

func has_promo() -> bool: return get_referrer().get("type", "") == "promo"
func get_promo_id() -> String: return str(get_referrer().get("promoId", ""))
func get_promo_intent() -> String: return str(get_referrer().get("intent", ""))
func get_promo_inapp_id() -> String: return str(get_referrer().get("inappId", ""))

func get_all() -> Dictionary:
	return _env.duplicate(true)
