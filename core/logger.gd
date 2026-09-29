@tool
class_name UniLogger
extends RefCounted

enum Level { DEBUG, INFO, WARN, ERROR }

static var min_level: Level = Level.DEBUG if OS.is_debug_build() else Level.WARN

static func debug(tag: String, msg: String) -> void:
	if min_level <= Level.DEBUG:
		print("[UniSDK][%s] %s" % [tag, msg])

static func info(tag: String, msg: String) -> void:
	if min_level <= Level.INFO:
		print("[UniSDK][%s] %s" % [tag, msg])

static func warn(tag: String, msg: String) -> void:
	if min_level <= Level.WARN:
		push_warning("[UniSDK][%s] %s" % [tag, msg])

static func error(tag: String, msg: String) -> void:
	if min_level <= Level.ERROR:
		push_error("[UniSDK][%s] %s" % [tag, msg])
