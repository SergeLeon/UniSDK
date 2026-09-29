@tool
class_name PlatformDetector
extends RefCounted

enum Platform {
	YANDEX,
	VK,
	MOCK
}

static func detect() -> Platform:
	if not OS.has_feature("web") or not ClassDB.class_exists("JavaScriptBridge"):
		return Platform.MOCK

	if _js_has("GodotVKBridge") or _js_has("vkBridge"):
		return Platform.VK

	if _js_has("GodotYandexBridge") or _js_has("YaGames"):
		return Platform.YANDEX

	return Platform.MOCK

## Безопасная проверка: не используем eval с интерполяцией строк.
static func _js_has(name: String) -> bool:
	if not _is_safe_identifier(name):
		return false
	var obj: JavaScriptObject = JavaScriptBridge.get_interface(name)
	return obj != null

static func _is_safe_identifier(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		var c := s[i]
		if not (c.is_valid_identifier() or c.is_valid_int()):
			return false
	return true

static func platform_to_string(p: Platform) -> String:
	match p:
		Platform.YANDEX: return "yandex"
		Platform.VK: return "vk"
		Platform.MOCK: return "mock"
	return "unknown"
