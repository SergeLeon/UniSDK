@tool
class_name UniAds
extends RefCounted

signal interstitial_opened
signal interstitial_closed(was_shown: bool)
signal interstitial_failed(error: String)
signal interstitial_cooldown_finished
signal rewarded_opened
signal rewarded_rewarded
signal rewarded_closed(was_shown: bool)
signal rewarded_failed(error: String)
signal banner_shown
signal banner_hidden
signal banner_status_changed(is_showing: bool, reason: String)
## Формат перестал отдаваться платформой (VK вернул "not supported" N раз подряд).
signal format_disabled(format: String, reason: String)

# ------------------------------------------------------------------
#  Стратегия по платформам
#
#  VK Bridge на веб-платформе отправляет любой метод в родительский фрейм
#  (vk.com / m.vk.com) и НЕ умеет сам решать, доступна ли реклама: решение
#  принимает бэкенд VK. Поэтому единственный надёжный способ узнать,
#  отдаёт ли VK interstitial/rewarded на десктопе — попробовать и посмотреть
#  на ответ. Никаких предположений "на десктопе не работает" тут быть не должно.
#
#  - mobile (android / iphone / ipad / mobile_web): все форматы.
#  - desktop_web: баннер всегда; interstitial/rewarded — пробуем, при ошибке
#    "not supported" тихо отключаем формат на сессию (см. NOT_SUPPORTED_PATTERNS).
# ------------------------------------------------------------------

const SUPPORTED = "supported"
const UNKNOWN = "unknown"
const DISABLED = "disabled"

## Сколько подряд отказов платформы переводит формат в состояние "disabled".
const DISABLE_AFTER_ATTEMPTS: int = 3

## Подстроки ответа VK, означающие "формат тут не поддерживается"
## (в отличие от временного отсутствия рекламы/таймаута).
const NOT_SUPPORTED_PATTERNS: PackedStringArray = [
	"not supported",
	"unsupported",
	"not available on this platform",
	"ads not supported",
	"method not found",
	"unknown method",
	"not implemented",
]

## Подстроки ответа, означающие "показ не состоялся за отведённое время".
const TIMEOUT_PATTERNS: PackedStringArray = [
	"timeout",
	"timed out",
]

## Жёсткий лимит ожидания показа, в секундах. Показ рекламы НИКОГДА не должен
## держать игру дольше этого времени: если VK не ответил — возвращаем управление
## игре и считаем попытку неудачной. Значения переопределяются в ProjectSettings:
##   uni_sdk/ads/interstitial_timeout
##   uni_sdk/ads/rewarded_timeout
##   uni_sdk/ads/check_timeout
const DEFAULT_INTERSTITIAL_TIMEOUT: float = 12.0
const DEFAULT_REWARDED_TIMEOUT: float = 25.0
## Сколько ждём ответ на быструю проверку «есть ли реклама». VKWebAppCheckNativeAds
## отвечает быстро именно тогда, когда рекламы нет, — поэтому по этой проверке
## можно отсечь пустой показ, не заставляя игрока ждать весь лимит.
const DEFAULT_CHECK_TIMEOUT: float = 2.5

var _core: Node
var cooldown_duration: float = 60.0
var _last_interstitial_time: float = -999999.0
var is_banner_showing: bool = false
var banner_height_pixels: int = 70

## Жёсткие лимиты ожидания показа (см. константы выше).
var interstitial_timeout: float = DEFAULT_INTERSTITIAL_TIMEOUT
var rewarded_timeout: float = DEFAULT_REWARDED_TIMEOUT
var check_timeout: float = DEFAULT_CHECK_TIMEOUT

var _cooldown_token: int = 0

# --- Телеметрия ---
var _attempts: int = 0
var _shown: int = 0
var _events: Array[Dictionary] = []
var _format_state: Dictionary = {}
## Сколько событий хранить в памяти (для отчёта и выгрузки в файл).
var max_telemetry_events: int = 100
var _telemetry_path_saved: String = ""

func _init(core: Node) -> void:
	_core = core
	cooldown_duration = float(ProjectSettings.get_setting("uni_sdk/ads/interstitial_cooldown", 60.0))
	interstitial_timeout = maxf(1.0, float(ProjectSettings.get_setting(
		"uni_sdk/ads/interstitial_timeout", DEFAULT_INTERSTITIAL_TIMEOUT)))
	rewarded_timeout = maxf(1.0, float(ProjectSettings.get_setting(
		"uni_sdk/ads/rewarded_timeout", DEFAULT_REWARDED_TIMEOUT)))
	check_timeout = maxf(0.5, float(ProjectSettings.get_setting(
		"uni_sdk/ads/check_timeout", DEFAULT_CHECK_TIMEOUT)))
	max_telemetry_events = maxi(1, int(ProjectSettings.get_setting("uni_sdk/ads/telemetry_events", 100)))
	_reset_format_state()


func _reset_format_state() -> void:
	_format_state = {
		"interstitial": _new_format_state(),
		"rewarded": _new_format_state(),
	}


func _new_format_state() -> Dictionary:
	return {
		"state": UNKNOWN,       # unknown | supported | disabled
		"attempts": 0,          # сколько раз пытались показать
		"shown": 0,             # сколько раз реально показали
		"failed": 0,            # неудачные попытки
		"fail_streak": 0,       # отказы подряд
		"last_error": "",
		"last_result": "",      # показан / not_filled / unsupported / timeout / error
		"disabled_reason": "",
	}


# ------------------------------------------------------------------
#  Platform capabilities
#
#  Эти методы — «мягкие» подсказки для UI. Они отвечают только на вопрос
#  "может ли платформа в принципе показать формат", а не "отдаст ли VK
#  рекламу прямо сейчас". Поэтому на десктопе они возвращают true до тех
#  пор, пока платформа не отказала явно.
# ------------------------------------------------------------------

## Rewarded-реклама может быть показана на этой платформе?
func is_rewarded_supported() -> bool:
	return _is_ad_platform_supported()


## Interstitial-реклама может быть показана на этой платформе?
func is_interstitial_supported() -> bool:
	return _is_ad_platform_supported()


## Баннерная реклама доступна? Работает на всех платформах, кроме OK.
func is_banner_supported() -> bool:
	if not _core.is_initialized:
		return true
	var platform: String = _core.get_platform()
	if platform == "vk":
		# На OK (подплатформа VK) баннеры не поддерживаются.
		var sub: String = _core.get_sub_platform()
		return sub != "ok"
	return true


func _is_ad_platform_supported() -> bool:
	if not _core.is_initialized:
		# Инициализация ещё идёт: не мешаем UI показать кнопку,
		# окончательное решение всё равно за платформой.
		return true
	var platform: String = _core.get_platform()
	if platform == "mock":
		return true
	if platform == "vk":
		# Десктоп больше НЕ отсекается заранее: пробуем и слушаем ответ VK.
		# Единственное исключение — OK, где нативной рекламы нет вовсе.
		if _core.get_sub_platform() == "ok":
			return false
		if _is_format_disabled("interstitial") and _is_format_disabled("rewarded"):
			return false
		return true
	return true


## Точное состояние формата: SUPPORTED / UNKNOWN / DISABLED.
## В отличие от can_show_*, отражает то, что реально ответил VK.
func get_format_state(format: String) -> String:
	return str(_get_format(format).get("state", UNKNOWN))


func _is_format_disabled(format: String) -> bool:
	return get_format_state(format) == DISABLED


func _get_format(format: String) -> Dictionary:
	if not _format_state.has(format):
		_format_state[format] = _new_format_state()
	return _format_state[format]


## Похоже ли сообщение платформы на «формат здесь не поддерживается».
static func is_not_supported_error(error: String) -> bool:
	var lower: String = error.to_lower()
	for pattern in NOT_SUPPORTED_PATTERNS:
		if lower.contains(pattern):
			return true
	return false


## Истёк ли лимит ожидания показа.
static func is_timeout_error(error: String) -> bool:
	var lower: String = error.to_lower()
	for pattern in TIMEOUT_PATTERNS:
		if lower.contains(pattern):
			return true
	return false


## Ждёт результат асинхронного вызова не дольше timeout_sec.
## Нужен как гарантия: адаптер может ждать ответа VK десятки секунд
## (у VK собственные таймауты на 15–75 с), и всё это время игра стоит.
## Если время вышло, возвращаем управление игре и помечаем попытку неудачной.
## Поздний ответ VK уже никого не ждёт и на игру не влияет.
## Вызов оборачивается в лямбду, чтобы получить объект состояния корутины,
## а не запускать её до конца: await на таком объекте даёт её результат.
func _await_with_timeout(adapter_call: Callable, timeout_sec: float) -> Dictionary:
	var pending: Array = [null]
	var completed: Array = [false]
	var runner: Callable = func() -> void:
		var value: Variant = await adapter_call.call()
		if completed[0]:
			return
		completed[0] = true
		pending[0] = value
	runner.call()
	if await _wait_until(completed, timeout_sec):
		var result: Variant = pending[0]
		if result is Dictionary:
			return result
		return { "success": false, "was_shown": false, "rewarded": false,
			"error": "Empty ad response" }
	return { "success": false, "was_shown": false, "rewarded": false,
		"error": "Timeout waiting for ad display (%ds)" % int(timeout_sec) }


## Ждёт смены флага. true — флаг выставлен, false — истёк лимит времени.
func _wait_until(flag: Array, timeout_sec: float) -> bool:
	var deadline: float = (Time.get_ticks_msec() / 1000.0) + timeout_sec
	while not flag[0]:
		if (Time.get_ticks_msec() / 1000.0) >= deadline:
			return false
		await _core.get_tree().process_frame
	return true


## Быстрая проверка «есть ли реклама в наличии» (VKWebAppCheckNativeAds).
## Нужна, чтобы неудачный показ между уровнями не тянулся весь лимит:
## если рекламы нет, VK отвечает на проверку быстро, и мы сразу продолжаем игру.
## Нет ответа — считаем, что показывать нечего (false), и не ждём.
func is_ad_available(format: String) -> bool:
	var response: Dictionary = await _await_with_timeout(
		func(): return await _core.get_adapter().check_ad_available(format),
		check_timeout)
	if not response.get("success", false):
		UniLogger.info("ads", "check %s: нет ответа за %.1fs (%s) — пропускаем показ" % [
			format, check_timeout, str(response.get("error", ""))])
		return false
	var available: bool = bool(response.get("available", false))
	UniLogger.info("ads", "check %s: available=%s" % [format, str(available)])
	return available


# ------------------------------------------------------------------
#  Cooldown
# ------------------------------------------------------------------

func can_show_interstitial() -> bool:
	if not is_interstitial_supported():
		return false
	return get_time_until_next_interstitial() <= 0.0


func get_time_until_next_interstitial() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - _last_interstitial_time
	return max(0.0, cooldown_duration - elapsed)


func can_show_rewarded() -> bool:
	return is_rewarded_supported()


func can_show_banner() -> bool:
	return is_banner_supported()


# ------------------------------------------------------------------
#  Interstitial
# ------------------------------------------------------------------

func show_interstitial_if_available(ignore_cooldown: bool = false) -> Dictionary:
	if not is_interstitial_supported():
		return { "success": false, "was_shown": false, "error": "Not supported on this platform" }
	if not ignore_cooldown and not can_show_interstitial():
		return { "success": false, "was_shown": false, "error": "Cooldown active" }
	return await show_interstitial()


func show_interstitial() -> Dictionary:
	if not is_interstitial_supported():
		var err := "Not supported on this platform"
		_record("interstitial", "unsupported", false, err)
		interstitial_failed.emit(err)
		return { "success": false, "was_shown": false, "error": err }

	# Дешёвая проверка перед показом. Игрок не запускал эту рекламу сам, поэтому
	# пустой показ не должен стоить ему 12 секунд ожидания: узнаём заранее,
	# есть ли что показывать, и если нет — сразу отдаём управление игре.
	if not await is_ad_available("interstitial"):
		var reason := "No ads available"
		_record("interstitial", "not_filled", false, reason)
		interstitial_failed.emit(reason)
		return { "success": false, "was_shown": false, "error": reason, "reason": "not_filled" }

	_core._prepare_ad_call()
	interstitial_opened.emit()

	var result: Dictionary = await _await_with_timeout(
		func(): return await _core.get_adapter().show_interstitial(),
		interstitial_timeout)

	_core._finish_ad_call()

	var was_shown: bool = bool(result.get("was_shown", false))
	var success: bool = bool(result.get("success", false))
	var error_text: String = str(result.get("error", ""))

	if success and was_shown:
		_last_interstitial_time = Time.get_ticks_msec() / 1000.0
		_schedule_cooldown_timer()

	_classify_result("interstitial", success, was_shown, error_text)

	if success:
		interstitial_closed.emit(was_shown)
	else:
		interstitial_failed.emit(error_text if not error_text.is_empty() else "Unknown error")

	# Явно сообщаем игре причину: "not_filled" — рекламы нет, но формат рабочий;
	# "unsupported" — формат выключен на этой платформе.
	result["reason"] = _get_format("interstitial").get("last_result", "")
	return result


func _schedule_cooldown_timer() -> void:
	var tree: SceneTree = _core.get_tree()
	if tree == null:
		return
	_cooldown_token += 1
	var my_token: int = _cooldown_token
	await tree.create_timer(cooldown_duration).timeout
	if my_token == _cooldown_token:
		interstitial_cooldown_finished.emit()


# ------------------------------------------------------------------
#  Rewarded
# ------------------------------------------------------------------

func show_rewarded() -> Dictionary:
	if not is_rewarded_supported():
		var err := "Not supported on this platform"
		_record("rewarded", "unsupported", false, err)
		rewarded_failed.emit(err)
		return { "success": false, "rewarded": false, "was_shown": false, "error": err, "reason": "unsupported" }

	_core._prepare_ad_call()
	rewarded_opened.emit()

	var result: Dictionary = await _await_with_timeout(
		func(): return await _core.get_adapter().show_rewarded(),
		rewarded_timeout)

	_core._finish_ad_call()

	var success: bool = bool(result.get("success", false))
	var was_shown: bool = bool(result.get("was_shown", false))
	var rewarded: bool = bool(result.get("rewarded", false))
	var error_text: String = str(result.get("error", ""))

	if rewarded:
		rewarded_rewarded.emit()

	if success:
		rewarded_closed.emit(was_shown)
	else:
		rewarded_failed.emit(error_text if not error_text.is_empty() else "Unknown error")

	_classify_result("rewarded", success, was_shown, error_text)

	result["reason"] = _get_format("rewarded").get("last_result", "")
	return result


# ------------------------------------------------------------------
#  Banner
# ------------------------------------------------------------------

func show_banner() -> Dictionary:
	if not is_banner_supported():
		return { "success": false, "is_showing": false, "reason": "Not supported on this platform" }
	var result: Dictionary = await _core.get_adapter().show_banner()
	if result.get("stickyAdvIsShowing", false):
		is_banner_showing = true
		banner_shown.emit()
	banner_status_changed.emit(is_banner_showing, str(result.get("reason", "")))
	return result


func hide_banner() -> Dictionary:
	var result: Dictionary = await _core.get_adapter().hide_banner()
	is_banner_showing = false
	banner_hidden.emit()
	banner_status_changed.emit(false, "")
	return result


func get_banner_status() -> Dictionary:
	var result: Dictionary = await _core.get_adapter().get_banner_status()
	is_banner_showing = result.get("stickyAdvIsShowing", result.get("is_showing", false))
	banner_status_changed.emit(is_banner_showing, str(result.get("reason", "")))
	return { "is_showing": is_banner_showing, "reason": str(result.get("reason", "")) }


# ------------------------------------------------------------------
#  Классификация ответов и телеметрия
#
#  Нужна, чтобы отличить «VK не отдаёт этот формат здесь» от «рекламы
#  временно нет». Первое — повод выключить формат, второе — повод
#  повторить позже. Без этого десктопный interstitial либо блокируется
#  навсегда, либо долбит VK на каждой попытке.
# ------------------------------------------------------------------

func _record(format: String, result_kind: String, was_shown: bool, error: String) -> void:
	_attempts += 1
	if was_shown:
		_shown += 1
	var event: Dictionary = {
		"time": int(Time.get_ticks_msec() / 1000.0),
		"format": format,
		"result": result_kind,
		"was_shown": was_shown,
		"error": error,
	}
	_events.append(event)
	if _events.size() > max_telemetry_events:
		_events.pop_front()

	var state: Dictionary = _get_format(format)
	state["attempts"] = int(state["attempts"]) + 1
	state["last_result"] = result_kind
	state["last_error"] = error
	if was_shown:
		state["shown"] = int(state["shown"]) + 1
	else:
		state["failed"] = int(state["failed"]) + 1

	UniLogger.info("ads", "VK %s -> %s%s%s" % [
		format, result_kind,
		"" if was_shown else " (не показан)",
		"" if error.is_empty() else " | %s" % error,
	])


func _classify_result(format: String, success: bool, was_shown: bool, error: String) -> void:
	var state: Dictionary = _get_format(format)
	if success and was_shown:
		state["state"] = SUPPORTED
		state["fail_streak"] = 0
		_record(format, "shown", true, "")
		return
	if success and not was_shown:
		# Платформа ответила корректно, но рекламы не было (нет фила).
		state["fail_streak"] = 0
		_record(format, "not_filled", false, error)
		return
	if is_not_supported_error(error):
		state["fail_streak"] = int(state["fail_streak"]) + 1
		if int(state["fail_streak"]) >= DISABLE_AFTER_ATTEMPTS and state["state"] != DISABLED:
			state["state"] = DISABLED
			state["disabled_reason"] = error
			UniLogger.info("ads", "%s отключён платформой после %d отказов: %s" % [
				format, int(state["fail_streak"]), error])
			format_disabled.emit(format, error)
		_record(format, "unsupported", false, error)
		return
	if is_timeout_error(error):
		# Попытка не дождалась ответа. Формат остаётся рабочим: следующий
		# показ может ответить нормально.
		UniLogger.warn("ads", "%s: превышен лимит ожидания (%.0f с), управление возвращено игре: %s" % [
			format, interstitial_timeout if format == "interstitial" else rewarded_timeout, error])
		_record(format, "timeout", false, error)
		return
	# Прочая ошибка / закрыли раньше — формат остаётся рабочим.
	_record(format, "error" if not error.is_empty() else "not_filled", false, error)


# ------------------------------------------------------------------
#  Отладочная диагностика (для Dev Console и логов)
# ------------------------------------------------------------------

## Спрашивает у VK Bridge список поддерживаемых методов и печатает отчёт.
## На VK это bridge.supportsAsync("VKWebAppShowNativeAds") — единственный
## источник правды о возможностях текущего клиента.
## Возвращает: { platform, is_desktop, show_native_ads, show_banner_ad, ... }
func diagnose() -> Dictionary:
	var diag: Dictionary = {
		"platform": _core.get_platform(),
		"sub_platform": _core.get_sub_platform(),
		"device_type": _core.device.get_type(),
		"is_desktop": _core.device.is_desktop(),
		"methods": {},
	}
	UniLogger.info("ads", "=== Диагностика рекламы ===")
	UniLogger.info("ads", "platform=%s sub=%s device=%s is_desktop=%s" % [
		diag["platform"], diag["sub_platform"], diag["device_type"], str(diag["is_desktop"])])

	if _core.is_web():
		var res: Dictionary = await _core.get_adapter().supports_native_ads()
		diag["methods"] = res.get("methods", {})
		diag["bridge_platform"] = res.get("platform", "unknown")
		diag["bridge_supports"] = res.get("supported", true)
		UniLogger.info("ads", "vk_platform=%s, bridge.supports: %s (на показ не влияет)" % [
			str(diag["bridge_platform"]), str(diag["methods"])])
	else:
		UniLogger.info("ads", "не веб-сборка: проверка методов VK Bridge недоступна")

	for format in ["interstitial", "rewarded"]:
		var state: Dictionary = _get_format(format)
		UniLogger.info("ads", "%s: state=%s attempts=%d shown=%d fail_streak=%d last=%s%s" % [
			format, state["state"], state["attempts"], state["shown"],
			state["fail_streak"], state["last_result"],
			"" if str(state["last_error"]).is_empty() else " | %s" % state["last_error"]])
	return diag


## Сводка по рекламе за сессию.
func get_telemetry() -> Dictionary:
	return {
		"platform": _core.get_platform(),
		"device_type": _core.device.get_type(),
		"is_desktop": _core.device.is_desktop(),
		"attempts": _attempts,
		"shown": _shown,
		"fill_rate": (float(_shown) / float(_attempts)) if _attempts > 0 else 0.0,
		"formats": _format_state.duplicate(true),
		"events": _events.duplicate(true),
	}


## Человекочитаемый отчёт одной строкой на событие.
func get_telemetry_report() -> String:
	var lines: PackedStringArray = []
	lines.append("platform=%s device=%s desktop=%s attempts=%d shown=%d" % [
		_core.get_platform(), _core.device.get_type(),
		str(_core.device.is_desktop()), _attempts, _shown])
	for format in ["interstitial", "rewarded"]:
		var state: Dictionary = _get_format(format)
		lines.append("%s: state=%s attempts=%d shown=%d failed=%d last=%s %s" % [
			format, state["state"], state["attempts"], state["shown"],
			state["failed"], state["last_result"], state["last_error"]])
	for event in _events:
		lines.append("  t=%d %s -> %s%s" % [
			event["time"], event["format"], event["result"],
			"" if str(event["error"]).is_empty() else " (%s)" % event["error"]])
	return "\n".join(lines)


## Печатает отчёт в консоль (видно в DevTools на VK).
func log_telemetry() -> void:
	for line in get_telemetry_report().split("\n"):
		UniLogger.info("ads", line)


## Сохраняет отчёт в user:// — чтобы выгрузить с устройства/из браузера.
## Возвращает путь к файлу или пустую строку при ошибке.
func dump_telemetry() -> String:
	var path: String = str(ProjectSettings.get_setting("uni_sdk/ads/telemetry_path", "user://ad_telemetry.json"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		UniLogger.warn("ads", "не удалось записать телеметрию в %s" % path)
		return ""
	file.store_string(JSON.stringify(get_telemetry(), "\t"))
	file.close()
	_telemetry_path_saved = path
	UniLogger.info("ads", "телеметрия сохранена: %s" % path)
	return path


func get_saved_telemetry_path() -> String:
	return _telemetry_path_saved
