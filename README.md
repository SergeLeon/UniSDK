# UniSDK — Универсальный SDK для Яндекс.Игр и VK Игр в Godot 4

<p align="center">
  <b>Единый API для Яндекс.Игр, VK Игр и Одноклассников с модульной системой платформ</b><br>
  Godot 4.3+ · GDScript 2.0 · Web-экспорт · Editor Mock Mode
</p>

---

## Содержание

1. [Обзор](#1-обзор)
2. [Ключевые особенности](#2-ключевые-особенности)
3. [Архитектура](#3-архитектура)
4. [Структура проекта](#4-структура-проекта)
5. [Установка](#5-установка)
6. [Настройки проекта](#6-настройки-проекта)
7. [Конфигурация платформ](#7-конфигурация-платформ)
8. [Экспорт сборок](#8-экспорт-сборок)
9. [VK Hosting Deploy](#9-vk-hosting-deploy)
10. [Быстрый старт](#10-быстрый-старт)
11. [Определение платформы](#11-определение-платформы)
12. [Инициализация](#12-инициализация)
13. [Установка локали](#13-установка-локали)
14. [Platform capabilities](#14-platform-capabilities)
15. [API Reference](#15-api-reference)
16. [Различия платформ](#16-различия-платформ)
17. [Синхронизация сохранений между устройствами](#17-синхронизация-сохранений-между-устройствами)
18. [Лимиты платформ](#18-лимиты-платформ)
19. [Внутреннее устройство JS-мостов](#19-внутреннее-устройство-js-мостов)
20. [Патч Emscripten и cache-busting](#20-патч-emscripten-и-cache-busting)
21. [Editor Mock Mode](#21-editor-mock-mode)
22. [Миграция с Yandex-only SDK](#22-миграция-с-yandex-only-sdk)
23. [Известные ограничения](#23-известные-ограничения)
24. [Troubleshooting](#24-troubleshooting)
25. [Changelog](#25-changelog)

---

## 1. Обзор

**UniSDK** — универсальный плагин для Godot 4.3+, абстрагирующий работу с несколькими игровыми платформами:

- **Яндекс.Игры** (`yandex.ru/games`) — через YaGames SDK
- **VK Игры** (`vk.ru/games`) — через VK Bridge
- **Одноклассники** (`ok.ru/games`) — через тот же VK Bridge (частичная поддержка)

Один и тот же игровой код работает на всех платформах. Адаптер определяется автоматически при запуске.

---

## 2. Ключевые особенности

- **Единый API**: `UniSDK.ads.show_rewarded()` работает и в Яндексе, и в VK.
- **Автодетект платформы**: одна Web-сборка запускается везде.
- **Модульная система платформ**: добавление новой платформы — регистрация профиля без правок логики экспорта.
- **Platform capability методы**: проверка доступности каждой фичи до её вызова (`can_show_rewarded()`, `is_purchase_supported()`, `can_request_review()` и т.д.).
- **Настраиваемый экспорт**: диалог конфигурации платформ, ZIP, hosting config.
- **Синхронизация сохранений между устройствами** через облако платформы (Yandex Player Data / VK Storage).
- **VK Storage с localStorage-кэшем и diff-записями**: только изменившиеся ключи уходят в облако.
- **Автоматическая позиция баннера**: снизу в портрете, справа в ландшафте (VK Bridge 2.15.1+).
- **Устойчивость к таймаутам VK Bridge**: все вызовы обёрнуты в `_safeSend()` с fallback.
- **Последовательная запись в VK Storage**: обход известного бага параллельных вызовов.
- **Защита от rate limit**: троттлинг лидербордов (1 запрос/сек), player data чтения (15 сек), VK Storage (1000 вызовов/час).
- **Патч Emscripten-вывода**: убирает ложную проверку Safari версии, из-за которой игра не запускалась в Android WebView (в том числе внутри VK).
- **Cache-busting для index.js**: автоматическая подстановка `?v=<timestamp>` в HTML — обход агрессивного кэша WebView.
- **Защита звука и паузы**: автопауза и мьют `AudioServer` во время рекламы.
- **Атомарная запись JSON**: mock и backup не повреждаются при падении.
- **Единый логгер** с уровнями DEBUG/INFO/WARN/ERROR.

### Поддерживаемые версии

| Компонент | Версия |
|---|---|
| Godot | 4.3+ |
| GDScript | 2.0 |
| Yandex Games SDK | последний стабильный |
| VK Bridge | **2.15.1+** (CDN) |

---

## 3. Архитектура

### Схема

```
+-------------------------------------------------------------------+
|                     Игровой код (GDScript)                        |
|                    UniSDK.ads.show_rewarded()                     |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                        UniSDK (Autoload)                          |
|  - PlatformDetector: yandex / vk / mock                           |
|  - Модули: ads, player, payments, leaderboards, storage, ...      |
|  - UniLogger, UniAtomicIO                                         |
+-------------------------------------------------------------------+
           |                       |                       |
           v                       v                       v
+---------------------+ +---------------------+ +---------------------+
|  YandexAdapter      | |  VKAdapter          | |  YandexMockBridge   |
|  (inline в HTML)    | |  (inline в HTML)    | |  (редактор)         |
+---------------------+ +---------------------+ +---------------------+
           |                       |
           v                       v
+---------------------+ +---------------------+
|  YaGames SDK        | |  VK Bridge SDK      |
+---------------------+ +---------------------+
```

### Слои

1. **Игровой код** — обращается только к `UniSDK.*`.
2. **Фасад `UniSDK`** — точка входа, содержит подмодули.
3. **Адаптеры** — `YandexAdapter`, `VKAdapter`, `YandexMockBridge`.
4. **JS-мосты** — инлайнятся прямо в HTML-шаблоны (`templates/yandex_template.html`, `templates/vk_template.html`).
5. **Mock-мост** — используется в редакторе, хранит данные в `user://unisdk_mock_data.json`.

> ⚠️ JS-мосты **не хранятся отдельными .js файлами**, а инлайнятся в шаблоны. Это требование Web-экспорта Godot (файлы из `res://` не отдаются как статика).

---

## 4. Структура проекта

```
addons/uni_sdk/
├── plugin.cfg
├── uni_sdk_plugin.gd                # EditorPlugin
├── uni_sdk_export_plugin.gd         # EditorExportPlugin (экспорт + патч + cache-busting)
├── uni_sdk.gd                       # Autoload (фасад)
├── platform_detector.gd
├── core/
│   ├── logger.gd                    # UniLogger (уровни)
│   ├── atomic_io.gd                 # Атомарная запись JSON
│   ├── platform_profile.gd
│   └── platform_registry.gd
├── adapters/
│   ├── platform_adapter.gd
│   ├── yandex_adapter.gd
│   └── vk_adapter.gd
├── modules/
│   ├── ads.gd                       # + can_show_rewarded / interstitial / banner
│   ├── player.gd                    # + can_open_auth_dialog
│   ├── payments.gd                  # + can_purchase / can_get_catalog
│   ├── leaderboards.gd              # + can_set_score / can_get_entries
│   ├── storage.gd
│   ├── feedback.gd                  # + is_review_supported
│   ├── shortcut.gd                  # + is_shortcut_supported
│   ├── device.gd
│   └── environment.gd
├── ui/
│   ├── platform_config_dialog.gd
│   ├── yandex_banner_container.gd
│   ├── yandex_review_button.gd
│   └── yandex_shortcut_button.gd
├── mock/
│   └── mock_bridge.gd
└── templates/
    ├── yandex_template.html
    └── vk_template.html             # VK Bridge 2.15.1 + banner positions
```

---

## 5. Установка

1. Скопируй папку `addons/uni_sdk` в свой проект.
2. **Project → Project Settings → Plugins** → включи **UniSDK**.
3. Autoload `UniSDK` зарегистрируется автоматически.
4. При первом запуске плагин создаст дефолтные профили платформ (Yandex + VK).

---

## 6. Настройки проекта

**Project → Project Settings → UniSDK:**

| Настройка | Тип | По умолчанию | Описание |
|---|---|---|---|
| `uni_sdk/general/auto_init` | `bool` | `true` | Автоинициализация SDK при старте |
| `uni_sdk/general/auto_call_game_ready` | `bool` | `true` | Автоматический `game_ready()` |
| `uni_sdk/general/auto_apply_locale` | `bool` | `true` | Автоматическая установка локали |
| `uni_sdk/general/auto_pause_tree` | `bool` | `false` | `get_tree().paused = true` при рекламе |
| `uni_sdk/general/debug_log` | `bool` | `false` | Зарегистрирован в настройках, но `UniLogger` его пока не читает: уровень зависит от типа сборки (DEBUG в debug, WARN в release) |
| `uni_sdk/ads/auto_mute_audio` | `bool` | `true` | Глушить master-шину при рекламе |
| `uni_sdk/ads/interstitial_cooldown` | `float` | `60.0` | Кулдаун между межстраничными (сек) |
| `uni_sdk/ads/interstitial_timeout` | `float` | `12.0` | Жёсткий лимит ожидания показа interstitial (сек) |
| `uni_sdk/ads/rewarded_timeout` | `float` | `25.0` | Жёсткий лимит ожидания показа rewarded (сек) |
| `uni_sdk/ads/check_timeout` | `float` | `2.5` | Лимит быстрой проверки «есть ли реклама» (сек) |
| `uni_sdk/ads/telemetry_events` | `int` | `100` | Сколько событий рекламы держать в памяти для отчёта |
| `uni_sdk/ads/telemetry_path` | `string` | `user://ad_telemetry.json` | Куда `dump_telemetry()` сохраняет отчёт |
| `uni_sdk/player/get_data_min_interval_sec` | `float` | `15.0` | Троттлинг чтения player data |
| `uni_sdk/payments/auto_check_unconsumed` | `bool` | `true` | Проверять невосстановленные покупки |
| `uni_sdk/mock/player_name` | `string` | `"Test Player (Editor)"` | Ник игрока в mock |
| `uni_sdk/mock/player_unique_id` | `string` | `"mock_player_12345"` | ID в mock |
| `uni_sdk/mock/is_authorized` | `bool` | `true` | Авторизация в mock |

---

## 7. Конфигурация платформ

**Project → Tools → UniSDK: Configure Platforms...**

Диалог позволяет настроить для каждой платформы:

| Поле | Описание |
|---|---|
| **Enabled** | Участвует ли в создании пресетов и экспорте |
| **Preset name** | Имя пресета в `export_presets.cfg` |
| **Output directory** | Папка сборки |
| **HTML template** | Путь к Custom HTML Shell |
| **Create ZIP** | Создавать ли ZIP после экспорта |
| **ZIP name** | Имя ZIP-файла |
| **Hosting config** | Создавать ли конфиг хостинга |
| **Hosting config name** | Имя файла конфига |
| **Hosting config content (JSON)** | Содержимое |

### Формат hosting config для VK

```json
{
  "static_path": ".",
  "app_id": 0,
  "access_token": "<YOUR_VK_SERVICE_TOKEN>",
  "endpoints": {
    "mobile": "index.html",
    "mvk": "index.html",
    "web": "index.html"
  }
}
```

- `endpoints` — **обязательное поле** для `vk-miniapps-deploy`, без него будет `TypeError`.

---

## 8. Экспорт сборок

### Пункты меню

| Пункт | Действие |
|---|---|
| **UniSDK: Create Selected Presets** | Создаёт/обновляет пресеты |
| **UniSDK: Export Selected Builds** | Экспорт + патч + hosting config + ZIP |

### Что делает плагин при экспорте

1. Сохраняет все сцены.
2. Создаёт пресеты с правильными `html/custom_html_shell` и `export_path`.
3. Для каждой платформы:
   - Чистит папку сборки.
   - Сохраняет существующий hosting config (с токенами).
   - Запускает Godot CLI (`--export-release`).
   - **Патчит `index.js`**: заменяет проверки версий браузеров (`currentSafariVersion<150200` и т.д.) на `if(false)`.
   - **Патчит `index.html`**: заменяет `<script src=index.js>` на `<script src=index.js?v=<timestamp>>`.
   - Восстанавливает hosting config.
   - Создаёт ZIP (кроме hosting config).

### Результат

```
res://build/
├── yandex/
│   ├── index.html           # со cache-busting
│   ├── index.js             # с патчем Safari
│   ├── index.wasm
│   ├── index.pck
│   └── yandex_build.zip
└── vk/
    ├── index.html
    ├── index.js
    ├── index.wasm
    ├── index.pck
    ├── vk-hosting-config.json   # НЕ в ZIP — содержит токен
    └── vk_build.zip
```

> ⚠️ Добавь `build/vk/vk-hosting-config.json` в `.gitignore` — там секретный `access_token`.

---

## 9. VK Hosting Deploy

VK Игры используют CDN VK. Деплой через `@vkontakte/vk-miniapps-deploy`.

### Шаги

1. Заполни `build/vk/vk-hosting-config.json`:
   - `app_id` — ID приложения.
   - `access_token` — сервисный ключ из VK Dev Console (Manage → Service token).
2. Запусти деплой:
   ```bash
   cd build/vk
   npx @vkontakte/vk-miniapps-deploy
   ```
3. После деплоя получишь URL вида `https://prod-app54788505-*.pages.vk-apps.ru`.

### Dev vs Prod режим VK

| Режим | URL | Storage | Платежи | Отзывы | Реклама |
|---|---|---|---|---|---|
| **dev** | `stage-app*.pages.vk-apps.ru` | ❌ | ❌ | ❌ | ❌ |
| **prod** | `prod-app*.pages.vk-apps.ru` | ✅ | ✅ (mobile) | ❌ | ✅ (mobile + banner desktop) |

**В dev-режиме VK сохранения не работают** — это ограничение stage-окружения.

---

## 10. Быстрый старт

```gdscript
extends Node

func _ready() -> void:
    await UniSDK.ensure_initialized()

    var lang: String = UniSDK.environment.get_lang()
    if not lang.is_empty():
        TranslationServer.set_locale(lang)

    UniSDK.game_ready()
    UniSDK.gameplay_start()

    var save_data = await UniSDK.player.get_data()
    print("Coins: ", save_data.get("coins", 0))
```

> ⚠️ Всегда жди `ensure_initialized()` перед первым обращением к `UniSDK.player.*`.

---

## 11. Определение платформы

### `UniSDK.get_platform() -> String`

Возвращает `"yandex"`, `"vk"` или `"mock"`.

```gdscript
match UniSDK.get_platform():
    "yandex": setup_yandex_ui()
    "vk":     setup_vk_ui()
    _:        setup_editor_ui()
```

### `UniSDK.get_platform_enum() -> PlatformDetector.Platform`

Типобезопасный вариант.

### `UniSDK.get_sub_platform() -> String`

Для VK возвращает `"vk"` или `"ok"` (Одноклассники).

### `UniSDK.is_web() -> bool`

`true`, если игра запущена в браузере.

---

## 12. Инициализация

### `init(options: Dictionary = {}) -> bool`

Инициализирует SDK через адаптер. Асинхронный. Идемпотентный.

### `ensure_initialized() -> bool`

Дожидается завершения инициализации. Гарантирует, что после `await` доступны `player.get_data()`, `player.is_authorized()` и т.д.

### Порядок инициализации

1. `_adapter.init()` — JS init или mock.
2. Извлекаются `environment` и `device`.
3. Если `auto_apply_locale` — устанавливается локаль.
4. `await player._ensure_initialized()` — профиль игрока готов.
5. `is_initialized = true`.
6. Если `auto_call_game_ready` — `game_ready()`.

### Сигналы

| Сигнал | Параметры |
|---|---|
| `sdk_initialized` | `data: Dictionary` |
| `platform_detected` | `platform: String` |
| `game_paused` / `game_resumed` | — |
| `history_back_requested` | — |
| `account_selection_opened` / `account_selection_closed` | — |

> ⚠️ `platform_detected` эмитится через `call_deferred()` — слушатели в `_ready()` сцены успеют подключиться.

---

## 13. Установка локали

Локаль нужно устанавливать **до первого рендера UI**.

### Автоматически

При `auto_apply_locale = true` (по умолчанию) SDK сам выставит `TranslationServer.set_locale()`.

### Вручную

```gdscript
await UniSDK.ensure_initialized()
var lang: String = UniSDK.environment.get_lang()
if not lang.is_empty():
    TranslationServer.set_locale(lang)
```

### Маппинг

```gdscript
const LOCALE_MAP := { "pt": "pt_BR", "zh": "zh_CN" }
var lang: String = UniSDK.environment.get_lang()
lang = LOCALE_MAP.get(lang, lang)
TranslationServer.set_locale(lang)
```

---

## 14. Platform capabilities

**Каждый модуль UniSDK имеет методы для проверки доступности своих функций.** Используйте их перед вызовом, чтобы UI корректно скрывал недоступные кнопки и не было ошибок на неподдерживаемых платформах.

| Модуль | Метод | Что проверяет |
|---|---|---|
| `UniSDK.ads` | `is_rewarded_supported()` / `can_show_rewarded()` | Платформа поддерживает rewarded |
| `UniSDK.ads` | `is_interstitial_supported()` | Платформа поддерживает interstitial |
| `UniSDK.ads` | `can_show_interstitial()` | Платформа + кулдаун |
| `UniSDK.ads` | `is_banner_supported()` / `can_show_banner()` | Платформа поддерживает баннеры |
| `UniSDK.payments` | `is_purchase_supported()` / `can_purchase()` | Платформа поддерживает покупки |
| `UniSDK.payments` | `is_catalog_supported()` / `can_get_catalog()` | Платформа поддерживает каталог |
| `UniSDK.leaderboards` | `is_set_score_supported()` / `can_set_score()` | Платформа + авторизация |
| `UniSDK.leaderboards` | `is_get_entries_supported()` / `can_get_entries()` | Платформа + авторизация |
| `UniSDK.leaderboards` | `is_full_leaderboard_available()` | Доступен ли полный топ |
| `UniSDK.feedback` | `is_review_supported()` / `can_request_review()` | Платформа поддерживает отзывы |
| `UniSDK.shortcut` | `is_shortcut_supported()` / `can_show_shortcut()` | Платформа поддерживает ярлыки |
| `UniSDK.player` | `is_auth_dialog_supported()` / `can_open_auth_dialog()` | Платформа поддерживает диалог входа |
| `UniSDK.player` | `is_player_data_supported()` | Всегда `true` (для симметрии) |

### Как использовать в UI

```gdscript
# В popup с рекламой за возрождение
btn_watch_ad.visible = (
    GameState.player_lost_reason == PlayerLostReason.OUT_OF_ENERGY
    and GameState.num_energy_boosts < MAX_ENERGY_BOOSTS
    and UniSDK.ads.can_show_rewarded()
)
```

```gdscript
# В UI магазина
btn_buy.visible = UniSDK.payments.can_purchase()
catalog_panel.visible = UniSDK.payments.can_get_catalog()
```

```gdscript
# В UI лидербордов
btn_submit_score.visible = UniSDK.leaderboards.can_set_score()
if UniSDK.leaderboards.is_full_leaderboard_available():
    _show_full_top()
else:
    _show_player_only()
```

```gdscript
# В UI кнопки "Оставить отзыв"
review_button.visible = UniSDK.feedback.is_review_supported() \
    and (await UniSDK.feedback.can_review()).get("value", false)
```

> ⚠️ Все capability-методы безопасны для вызова до инициализации SDK — они возвращают `true` оптимистично, чтобы UI не мигал. После `UniSDK.ensure_initialized()` результат становится точным.

---

## 15. API Reference

### Lifecycle & Core

```gdscript
UniSDK.game_ready()
UniSDK.gameplay_start()
UniSDK.gameplay_stop()
var t: int = UniSDK.get_server_time()
var ok: bool = await UniSDK.is_available_method("leaderboards.setScore")
var sent: bool = await UniSDK.dispatch_event("EXIT")
UniSDK.dispatch_exit()
```

### Реклама

```gdscript
# Capability check
if UniSDK.ads.can_show_rewarded():
    var res: Dictionary = await UniSDK.show_rewarded()
    # { success, rewarded, was_shown, error, reason }
    # reason: shown | not_filled | unsupported | timeout | error
    if res.rewarded:
        give_reward()

# Interstitial с проверкой кулдауна
if UniSDK.ads.can_show_interstitial():
    await UniSDK.show_interstitial()

# Точная проверка «есть ли что показывать» прямо сейчас
if await UniSDK.ads.is_ad_available("rewarded"):
    await UniSDK.show_rewarded()

# Состояние формата: supported | unknown | disabled
var state: String = UniSDK.ads.get_format_state("rewarded")

# Баннеры
if UniSDK.ads.can_show_banner():
    await UniSDK.ads.show_banner()
    await UniSDK.ads.hide_banner()
    var status = await UniSDK.ads.get_banner_status()
```

> ⏱ Показ ограничен по времени: 25 с для rewarded, 12 с для interstitial, 2.5 с на проверку `is_ad_available()` — управление всегда возвращается игре. При `res.rewarded == false` показ не состоялся (нет фила, таймаут или отказ платформы) — сообщите об этом игроку.

### Профиль игрока

```gdscript
var info = await UniSDK.player.open_auth_dialog()
var is_auth: bool = UniSDK.player.is_authorized()
var user_id: String = UniSDK.player.get_id()
var name: String = UniSDK.player.get_name()
var photo: String = UniSDK.player.get_photo("medium")
var tex: Texture2D = await UniSDK.player.get_avatar_texture("medium")

# Capability check (на VK диалог не поддерживается)
if UniSDK.player.can_open_auth_dialog():
    show_auth_button()
```

### Сохранения

```gdscript
await UniSDK.player.set_data({ "coins": 500, "level": 3 }, true)
var data: Dictionary = await UniSDK.player.get_data(["coins", "level"])
await UniSDK.player.set_stats({ "high_score": 12000 })
var updated = await UniSDK.player.increment_stats({ "kills": 10 })

# Статус облака — когда важно не потерять прогресс
var read: Dictionary = await UniSDK.player.get_data_ex(["coins", "level"])
# { ok, data, from_cache }: ok = false — облако недоступно (это не «сохранения нет»)
var write: Dictionary = await UniSDK.player.set_data_ex({ "coins": 550 }, true)
# { ok, success, cloud_ok }: cloud_ok = false — запись осталась в локальном бэкапе
UniSDK.player.set_data_now({ "coins": 550 })   # синхронно, при сворачивании приложения
```

**Под капотом:**

- **Yandex**: `player.setData()` / `player.getData()` + localStorage-кэш с diff.
- **VK / OK**: `VKWebAppStorageSet/Get` + localStorage-зеркало + diff. Облако читается первым и с повторами; локальный кэш отдаётся только как фолбэк и со статусом `cloud_ok: false`.

**Троттлинг `get_data()`**: если полный набор читали меньше 15 секунд назад, вернётся кэш.

> ⚠️ **Никогда не проверяй `is_authorized()` при выборе хранилища** — player data API работает для всех.
>
> ⚠️ `setData()` в Яндексе **не мержит** данные. Всегда передавай полный набор ключей.
>
> ⚠️ **Сбой чтения нельзя считать пустым сохранением**: не записывай в облако, пока `get_data_ex()` не вернул `ok = true`, иначе локальные нули затрут прогресс с другой платформы.

### Лидерборды

```gdscript
if UniSDK.leaderboards.can_set_score():
    await UniSDK.leaderboards.set_score("highscores", 2500, "mage")

UniSDK.leaderboards.set_score_debounced("highscores", 5000, "", 1.0)

if UniSDK.leaderboards.can_get_entries():
    var top = await UniSDK.leaderboards.get_entries("highscores", {
        "quantityTop": 10, "includeUser": true
    })
```

### Платежи

```gdscript
if UniSDK.payments.can_purchase():
    await UniSDK.payments.init_payments(true)
    var catalog = await UniSDK.payments.get_catalog() if UniSDK.payments.can_get_catalog() else []
    var purchase = await UniSDK.payments.purchase("coins_100")
    if not purchase.is_empty():
        give_item()
        await UniSDK.payments.consume_purchase(purchase.purchaseToken)
```

### Хранилище

```gdscript
await UniSDK.storage.set_item("user_settings", '{ "sound": true }')
var val: String = await UniSDK.storage.get_item("user_settings")
```

### Отзывы и ярлыки

```gdscript
if UniSDK.feedback.is_review_supported():
    var can = await UniSDK.feedback.can_review()
    if can.get("value", false):
        await UniSDK.feedback.request_review()

if UniSDK.shortcut.is_shortcut_supported():
    if await UniSDK.shortcut.can_show_prompt():
        var res = await UniSDK.shortcut.show_prompt()
```

### Устройство и окружение

```gdscript
var device_type: String = UniSDK.device.get_type()
var is_mob: bool = UniSDK.device.is_mobile()
var is_desk: bool = UniSDK.device.is_desktop()
var orientation: String = UniSDK.device.get_orientation()

var lang: String = UniSDK.environment.get_lang()
var browser_lang: String = UniSDK.environment.get_browser_lang()
var tld: String = UniSDK.environment.get_tld()
var app_id: String = UniSDK.environment.get_app_id()
```

---

## 16. Различия платформ

| Возможность | Яндекс | VK (mobile) | VK (desktop) | OK |
|---|---|---|---|---|
| **Инициализация** | `YaGames.init()` | `VKWebAppInit` | `VKWebAppInit` | `VKWebAppInit` |
| **Готовность** | `LoadingAPI.ready()` | No-op | No-op | No-op |
| **Авторизация** | Опциональная | Всегда | Всегда | Всегда |
| **Диалог входа** | ✅ | ❌ | ❌ | ❌ |
| **Сохранения** | ✅ | ✅ | ✅ | ✅ |
| **Interstitial** | ✅ | ✅ | ⚠️ по ответу VK | ❌ |
| **Rewarded** | ✅ | ✅ | ⚠️ по ответу VK | ❌ |
| **Banner** | ✅ | ✅ (bottom) | ✅ (bottom/top) | ❌ |
| **Покупки** | ✅ | ✅ | ❌ | ❌ |
| **Каталог** | ✅ | ❌ | ❌ | ❌ |
| **Лидерборды** | ✅ | Только запись | Только запись | Только запись |
| **Отзывы** | ✅ | ❌ | ❌ | ❌ |
| **Ярлыки** | ✅ | ✅ (mobile) | ❌ | ❌ |
| **Back-кнопка** | `HISTORY_BACK` | `VKWebAppChangeFragment` | ✅ | ✅ |
| **Язык** | `environment.i18n.lang` | `vk_language` | `vk_language` | `vk_language` |

### Рекомендации по UX

1. **Отзывы**: используйте `UniSDK.feedback.is_review_supported()` — скроет кнопку на VK/OK автоматически.
2. **Лидерборды**: проверяйте `is_full_leaderboard_available()` — на VK показывайте только запись игрока.
3. **Покупки**: `can_purchase()` вернёт `false` на десктопе VK/OK — кнопка автоматически скроется.
4. **Rewarded**: `can_show_rewarded()` вернёт `false` только в OK и после того, как VK трижды ответил «не поддерживается». На десктопе VK кнопку **не скрывай заранее** — попробуй показать и, если `res.rewarded == false`, сообщи игроку о неудаче (и при необходимости убери/заблокируй кнопку).
5. **Баннеры**: `can_show_banner()` вернёт `false` в OK. Позиция автоматическая.

---

## 17. Синхронизация сохранений между устройствами

**Требование пункта 2.3.8 правил VK Mini Apps**: прогресс должен синхронизироваться между версиями для разных платформ (десктоп и мобильные).

### Как UniSDK это обеспечивает

- **Yandex**: `player.setData()` / `getData()` — облако Яндекса доступно для всех игроков (включая неавторизованных через localStorage браузера).
- **VK / OK**: `VKWebAppStorageSet` / `Get` — облако VK, привязанное к `user_id`, а не к устройству и браузеру.
- Облако читается первым и с повторами; локальный кэш отдаётся только когда облако недоступно — и со статусом `cloud_ok: false` в `get_data_ex()`.
- Запись отправляет только изменившиеся ключи и отвечает после реальной отправки (`cloud_ok`).
- При сворачивании приложения приходит `UniSDK.game_paused` — сохранитесь и вызовите `set_data_now()`.

### Ключевое правило

**Всегда передавайте явный список ключей в `get_data()`**, если используете VK Storage:

```gdscript
# ❌ ПЛОХО для VK — VK Bridge не поддерживает "получить все ключи":
var data = await UniSDK.player.get_data(null)

# ✅ ХОРОШО — работает везде:
const SAVE_KEYS := ["coins", "level", "achievements"]
var data = await UniSDK.player.get_data(SAVE_KEYS)
```

Если передать `null`, на Яндекс.Играх данные подтянутся (YaGames API это умеет), но **на VK Storage вы получите пустой объект**, и игра прочитает локальный кэш с текущего устройства.

### Пример из `save_state.gd`

```gdscript
const SAVE_KEYS: = [
    "total_game_time", "beat_game", "total_bricks_destroyed",
    "bosses_cleared", "money", "diamonds", "upgrade_levels",
    # ... остальные ключи
]

func get_save_data():
    if _has_sdk() and UniSDK.player:
        await _ensure_player_ready()
        # Явный список ключей — критично для VK Storage.
        var cloud_data = await UniSDK.player.get_data(SAVE_KEYS)
        if cloud_data is Dictionary and not cloud_data.is_empty():
            return cloud_data
    # Fallback на локальный файл
    ...
```

### Удаление сохранения

VK Storage не умеет удалять ключи. Правильный способ — **перезаписать значениями по умолчанию**:

```gdscript
func delete_save():
    var defaults := _build_defaults_dict()
    await UniSDK.player.set_data(defaults, true)
```

Если записать пустой `{}`, `UniPlayer.set_data()` вернёт `true` (это no-op), и облако не изменится.

---

## 18. Лимиты платформ

### Yandex Games SDK

| Метод | Лимит |
|---|---|
| `player.getData()` | 20 раз / 5 мин |
| `player.setData()` | 100 раз / 5 мин |
| `player.getStats()` | 60 раз / 1 мин |
| `player.incrementStats()` | 60 раз / 1 мин |
| `player.getPlayer()` | 20 раз / 5 мин |
| `leaderboards.setScore()` | 1 раз / 1 сек |
| `leaderboards.getEntries()` | 1 раз / 1 сек |
| Размер `setData` payload | 200 КБ |
| Размер `setStats` payload | 10 КБ |
| `quantityTop` | 1..20 (default 5) |
| `quantityAround` | 1..10 |

### VK Bridge

| Параметр | Лимит |
|---|---|
| `VKWebAppStorageSet` вызовов | 1000 / час на пользователя |
| Всего ключей в storage | 1000 |
| Длина значения ключа | 4096 символов |
| `VKWebAppShowNativeAds` | Только Android / iOS |
| `VKWebAppShowOrderBox` | Только Android / iOS |
| `VKWebAppAddToHomeScreenInfo` | Только Android |
| `VKWebAppShowBannerAd` | Все платформы (кроме OK) |

### Что SDK делает автоматически

- **Троттлинг лидербордов** — 1 запрос/сек.
- **Троттлинг `get_data`** — 15 сек (настраивается).
- **Diff записи** — в облако уходят только изменившиеся ключи.
- **Проверка размера** `set_player_data` — предупреждение при превышении 200 КБ.
- **Rate limit VK storage** — при приближении к 990 вызовам в час или после 5 сбоев подряд запись берёт паузу на 60 секунд (а не отключается до перезапуска).
- **Проверка платформы** для рекламы/платежей/ярлыков — на неподдерживаемой платформе возвращается ошибка без вызова VK.

---

## 19. Внутреннее устройство JS-мостов

### Общий контракт событий

```javascript
{ "event": "open" }
{ "event": "rewarded" }
{ "event": "close", "wasShown": true }
{ "event": "error", "error": "..." }
```

### `call_js_async` в GDScript

```gdscript
var res: Dictionary = await UniSDK.call_js_async("methodName", [arg1, arg2], timeout_sec)
```

**Особенности:**

1. **Защита от GC**: `JavaScriptObject` сохраняется в `_active_js_callbacks`.
2. **Очередь отложенных событий**: повторные вызовы колбэка → `_ad_event_queue`.
3. **Таймаут**: по истечении — возврат `{ success: false, error: "Timeout" }`.
4. **Поколения**: `_release_ad_callbacks_deferred` использует счётчик поколений.

### Diff-логика записи

При `setPlayerData(storageSet)`:

1. **Локально сохраняем ВСЕГДА** — мгновенно, без сети.
2. **Собираем только изменившиеся ключи** — сравнение с `_sentValues`.
3. **Если изменений нет** — облако вообще не дёргается.
4. **Отправляем** в облако **только изменившиеся ключи**.
5. **После успеха** — обновляем `_sentValues`.

GDScript получает ответ после реальной отправки: `{ success, cloud_ok, changed, failed, deferred }`.

Единый формат значений — функция `normalizeValue()`.

### `vk_template.html` — особенности

#### 1. `_safeSend(method, params, timeoutMs, fallbackValue, silentTimeout)`

Универсальная обёртка с таймаутом.

#### 2. Storage: облако первым, кэш — только фолбэк

`storageGet`:
```
1. VKWebAppStorageGet                    → до 4 сек на попытку
2. Повтор при сбое                       → 2 попытки, пауза 500 мс
3. Облако не ответило                    → localStorage + cloud_ok: false
```

`storageSet`:
```
1. Мгновенно пишет в localStorage        → 0 мс
2. Считает diff с _sentValues
3. Последовательно отправляет изменившиеся ключи в VK
4. Отвечает GDScript после отправки      → cloud_ok / failed / deferred
```

**Последовательная отправка** — критично: VK Bridge ломает промисы при параллельных `VKWebAppStorageSet`.

#### 3. Позиция баннера зависит от ориентации

```javascript
_buildBannerParams: function () {
    var landscape = isLandscape();
    if (landscape) {
        return {
            layout_type: 'overlay',
            banner_align: 'right',
            orientation: 'vertical'
        };
    } else {
        return {
            banner_location: 'bottom',
            orientation: 'horizontal',
            height_type: 'regular'
        };
    }
}
```

При смене ориентации (`resize` / `orientationchange`) баннер пересоздаётся с новыми параметрами.

#### 4. Проверка размера значений

Перед отправкой значения обрезаются до 4096 символов.

#### 5. Rate limit 1000/час

Каждая попытка записи (успех или ошибка) увеличивает счётчик. При приближении к 990 вызовам в час или после 5 сбоев подряд запись приостанавливается на 60 секунд (`_storageWriteRetryAfterMs`) — облако не отключается насовсем, следующий вызов попробует снова.

---

## 20. Патч Emscripten и cache-busting

### Проблема 1: ложная проверка Safari

Emscripten в сгенерированном `index.js` парсит `userAgent`. В Android WebView (в том числе внутри VK) `userAgent` содержит `Version/4.0`, и Emscripten думает, что это Safari 4.0, ниже требуемой 15.2.0, и выбрасывает исключение:

```
Uncaught (in promise) Error: This emscripten-generated code requires Safari v15.2.0 (detected v040000)
```

Игра не запускается. **Решение:** `UniSDKExportPlugin._patch_export_artifacts()` заменяет условия на `if(false)` после каждого экспорта.

### Проблема 2: WebView кэширует старый `index.js`

При обновлении сборки браузер продолжает использовать старый `index.js`, поэтому патч не применяется. **Решение:** плагин добавляет `?v=<timestamp>` к тегу `<script src=index.js>` в `index.html`.

### Проверка после экспорта

В консоли должно быть:
```
[UniSDK] Patched Emscripten browser checks in index.js
[UniSDK] Added cache-busting to index.js in index.html
```

В `build/vk/index.html`:
```html
<script src=index.js?v=1730123456></script>
```

### Ручное исправление уже собранного билда

1. Открой `build/vk/index.js`.
2. Найди `currentSafariVersion<150200`, `currentFirefoxVersion<100`, `currentChromeVersion<95`.
3. Замени каждое на `false`.
4. Открой `build/vk/index.html`, замени `<script src=index.js>` на `<script src=index.js?v=2>`.
5. Задеплой заново.

### Очистка кэша на стороне VK

VK Dev Console → ваше приложение → **Manage → Cache** → **Clear cache**. Либо подожди TTL (5–15 минут).

---

## 21. Editor Mock Mode

В редакторе Godot (F5) SDK работает offline:

- **Платформа**: `PlatformDetector` вернёт `MOCK`.
- **Адаптер**: `YandexMockBridge`.
- **Хранение**: `user://unisdk_mock_data.json` (атомарная запись).
- **Задержки**: эмуляция рекламы (0.5–0.8 сек).
- **Все capability-методы**: возвращают `true`.

### Сброс данных

- **Project → Tools → UniSDK: Reset Mock Data** — очищает `unisdk_mock_data.json`.
- **Project → Tools → UniSDK: Reset Player Backup** — очищает `unisdk_player_backup.json`.

---

## 22. Миграция с Yandex-only SDK

### Массовая замена

```
YandexGames.        →  UniSDK.
```

### Что перенести вручную

1. **Autoload**: удалить `YandexGames`, добавить `UniSDK`.
2. **UI-компоненты**: `get_node_or_null("YandexGames")` → `get_node_or_null("UniSDK")`.
3. **Project Settings**: ключи `yandex_games/*` → `uni_sdk/*`.

### Что НЕ изменится

- Сигнатуры методов `ads.show_rewarded()`, `player.get_data()` и т.д.
- Формат возвращаемых словарей.
- Имена сигналов.

---

## 23. Известные ограничения

1. **VK не имеет каталога товаров** — `payments.get_catalog()` пуст.
2. **VK не имеет API отзывов** — `feedback.can_review()` возвращает `false`.
3. **VK лидерборды** — только запись игрока, полный топ недоступен.
4. **VK покупки только в мобильном приложении** — на десктопе `VKWebAppShowOrderBox` вернёт ошибку.
5. **VK реклама (interstitial/rewarded) в веб-версии чаще всего не отдаётся** — но SDK не отсекает её заранее по платформе: показ пробуется, а формат гасится только после 3 явных отказов VK («not supported»).
6. **VK баннеры работают и на десктопе** — это единственный рекламный формат, доступный в веб-версии.
7. **OK не поддерживает баннеры** — `can_show_banner()` вернёт `false`.
8. **OK не поддерживает interstitial/rewarded** даже на мобильных.
9. **VK dev-режим не сохраняет** — используй prod URL.
10. **VK Bridge может тормозить** на `desktop_web` — обёрнут в `_safeSend` с fallback.
11. **VK Storage не умеет удалять ключи** — удаление = перезапись значениями по умолчанию.
12. **Yandex `setData` не мержит** — всегда передавай полный набор.
13. **Yandex лидерборды только для авторизованных**.
14. **Локаль до первого рендера UI** — иначе первый кадр на неправильном языке.
15. **ZIP-архив** содержит `index.html` в корне — требование обеих платформ.
16. **JS-мосты инлайнятся** в HTML — отдельные .js-файлы не работают в Web-экспорте.
17. **`platform_detected` эмитится deferred** — не используй его в `_init()`.
18. **`get_data(null)` не работает в VK Storage** — всегда передавай явный список ключей.

---

## 24. Troubleshooting

### Игра не запускается в VK на Android

**Симптом:** белый экран, в консоли `This emscripten-generated code requires Safari v15.2.0`.

**Решение:** проверь, что в `build/vk/index.js` условия `if(currentSafariVersion<150200)` заменены на `if(false)`, и что в `build/vk/index.html` подключение `<script src=index.js?v=...>`. Если нет — пересобери через **UniSDK: Export Selected Builds**.

### Прогресс не синхронизируется между устройствами

**Симптом:** на десктопе прогресс есть, на мобильном — нет (или наоборот).

**Причины:**
1. `UniSDK.player.get_data(null)` вместо `get_data(SAVE_KEYS)` — VK Storage требует явный список.
2. VK dev-режим (stage URL) — там Storage не работает. Используй prod URL.
3. Монетизация не подключена в VK Dev Console.
4. Сбой чтения облака принят за пустое сохранение: сверяйтесь с `get_data_ex()` и не пишите в облако, пока `ok == false`.
5. Игра не сохраняется при сворачивании: обработайте `UniSDK.game_paused` и вызовите `set_data_now()`.

### Баннер не показывается

**Причины:**
1. Монетизация не подключена в VK Dev Console.
2. Платформа OK — там баннеры не поддерживаются.
3. `VKWebAppShowBannerAd` вызван до `VKWebAppInit` (проверь порядок скриптов в `index.html`).
4. VK Bridge версии младше 2.15.1 — параметры `orientation`, `height_type`, `layout_type`, `banner_align` там не поддерживаются.

### Rewarded-кнопка видна, но реклама не показывается

**Причина:** на десктопе VK `VKWebAppShowNativeAds` чаще всего возвращает ошибку, но заранее по платформе это не определить.

**Что делать:**

1. Награду не выдавайте и сообщите игроку, что показ не состоялся (`res.rewarded == false`).
2. Посмотрите причину: `res.reason` (`shown` / `not_filled` / `unsupported` / `timeout` / `error`) и `res.error`.
3. Отчёт по попыткам: `UniSDK.ads.log_telemetry()` в консоль, `dump_telemetry()` в файл, в JS — `GodotVKBridge.adReport()`.

### Игра «приближена» и обрезана в WebView

**Причина:** `viewport-fit=cover` в `<meta name="viewport">` или использование `100dvh`/`100dvw` в CSS.

**Решение:** используй обновлённые шаблоны из `addons/uni_sdk/templates/`, где `<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">` (без `viewport-fit`).

### Игра повёрнута/искажена в ландшафте

**Причина:** поворот `Camera2D` вместо корневого `Node2D` мира.

**Решение:** не крути `Camera2D`. Поворачивай `WorldRoot` (Node2D с уровнем) на `-90°` в ландшафте. Камера должна оставаться ровной.

---

## 25. Changelog

### v1.3.0

**Сохранения (п. 2.3.8 правил VK Mini Apps):**
- `storageGet` читает облако первым и повторяет запрос; локальный кэш — только фолбэк со статусом `cloud_ok: false` (убрана гонка 800 мс, из-за которой старый кэш затирал свежий облачный прогресс).
- `storageSet` отвечает после реальной отправки: `{ success, cloud_ok, changed, failed, deferred }`.
- Вместо отключения облака насовсем при сбоях — пауза 60 с и повтор.
- Новые методы `player.get_data_ex()` / `set_data_ex()` / `set_data_now()` и аналоги в адаптерах; `set_data()` сохранил прежний контракт.
- Шаблоны VK и Яндекс шлют pause/resume по `visibilitychange` / `pagehide` / `freeze` — игра успевает сохраниться при сворачивании.

**Реклама:**
- Состояния форматов (`supported` / `unknown` / `disabled`), сигнал `format_disabled`, гашение формата после 3 явных отказов платформы.
- Лимиты ожидания 12 / 25 / 2.5 с, `is_ad_available()`, поле `reason` в результате показа.
- Диагностика: `diagnose()`, `get_telemetry_report()`, `dump_telemetry()`; в VK-мосте — `checkNativeAds`, `supportsNativeAds`, `adReport`; при показе отдаются оба события (`rewarded` + `close`).
- Убран предварительный запрет нативной рекламы на десктопе VK (откат поведения v1.2.0).

### v1.2.0

**Добавлено:**
- Platform capability методы во все модули: `can_show_rewarded`, `can_show_banner`, `can_purchase`, `can_get_catalog`, `can_set_score`, `can_get_entries`, `is_full_leaderboard_available`, `is_review_supported`, `is_shortcut_supported`, `can_open_auth_dialog`.
- Алиасы `is_*_supported()` для явного именования.
- Патч Emscripten browser checks в `index.js` при экспорте (обход ложной Safari 15.2.0).
- Cache-busting `?v=<timestamp>` для `index.js` в HTML при экспорте.
- Автоматическая позиция баннера VK: снизу в портрете, справа в ландшафте (VK Bridge 2.15.1+).
- Проверка платформы для interstitial / rewarded / purchase / shortcut на десктопе VK.
- Явный список `SAVE_KEYS` в `get_data()` для синхронизации VK Storage между устройствами.
- `delete_save()` в VK Storage через перезапись значениями по умолчанию.

**Исправлено:**
- Утечка диалога конфигурации платформ.
- Diff-логика для строковых значений.
- `VKWebAppShowNativeAds` больше не вызывается на десктопе.
- `VKWebAppShowOrderBox` различает успех и ошибку.
- Зависший `VKWebAppCheckNativeAds` больше не приводит к показу рекламы.
- Callback `dispatch_exit` сохраняется от GC.
- При смене пользователя VK локальный кэш очищается.
- `_ensure_initialized` в `player.gd` не переинициализирует каждый раз.
- Удалён дублирующий `vk_bridge.js` / `yandex_bridge.js`.
- `platform_detected` эмитится через `call_deferred`.
- Фalsy-баг в `storageGetItem`.
- `VKWebAppStorageGet` с пустым массивом не вызывает VK.
- Параллельные `VKWebAppStorageSet` сериализованы.
- Счётчик rate limit увеличивается на каждой попытке.
- Hard timeout интерстишела не возвращает `success: true`.
- Таймаут HTTPRequest для аватарок.

**Улучшения:**
- Обновлён VK Bridge до 2.15.1.
- Убран `viewport-fit=cover` из шаблонов (устранил обрезку/приближение в WebView).
- Убраны `dvh`/`dvw` единицы (не поддерживаются старыми WebView).
- Убран `print_rich` из продового кода.
- Единый логгер `UniLogger`.
- Атомарная запись JSON через `UniAtomicIO`.

### v1.0.0

- Первый релиз.

---

## Быстрая шпаргалка

```gdscript
# Старт
await UniSDK.ensure_initialized()
TranslationServer.set_locale(UniSDK.environment.get_lang())
UniSDK.game_ready()
UniSDK.gameplay_start()

# Реклама (проверяй capability перед показом)
if UniSDK.ads.can_show_rewarded():
    var r = await UniSDK.show_rewarded()
    if r.rewarded: give_reward()

if UniSDK.ads.can_show_interstitial():
    await UniSDK.show_interstitial()

# Баннер (не требует capability check — просто вызови)
await UniSDK.ads.show_banner()

# Сохранение (ОБЯЗАТЕЛЬНО с явным списком ключей для VK)
await UniSDK.player.set_data({"coins": 100}, true)
var d = await UniSDK.player.get_data(["coins"])

# Лидерборд (только для авторизованных)
if UniSDK.leaderboards.can_set_score():
    await UniSDK.leaderboards.set_score("highscores", 5000)

# Покупка (только на mobile VK и Яндекс)
if UniSDK.payments.can_purchase():
    var p = await UniSDK.payments.purchase("coins_pack")
    if not p.is_empty():
        await UniSDK.payments.consume_purchase(p.purchaseToken)

# Отзыв (только на Яндексе)
if UniSDK.feedback.is_review_supported():
    var can = await UniSDK.feedback.can_review()
    if can.get("value", false):
        await UniSDK.feedback.request_review()
```

### Ключевые правила

1. **Всегда** устанавливай локаль после инициализации.
2. **Всегда** вызывай `game_ready()` после загрузки ассетов.
3. **Всегда** `gameplay_start()` / `gameplay_stop()` вокруг геймплея.
4. **Всегда** проверяй `result.rewarded` для rewarded-рекламы и сообщай игроку, если показ не состоялся.
5. **Всегда** потребляй consumable-покупки.
6. **Всегда** передавай явный список ключей в `get_data()` (VK Storage требует).
7. **Всегда** передавай полный набор ключей в `set_data()` (Yandex не мержит).
8. **Проверяй capability** перед показом UI с рекламой/покупками/отзывами.
9. **Никогда** не вызывай `set_score()` чаще 1 раза в секунду.
10. **Никогда** не проверяй `is_authorized()` при выборе хранилища.
11. **Никогда** не полагайся на порядок событий рекламы.
12. **Никогда** не крути `Camera2D` для ландшафта — крути корневой `Node2D` мира.
13. **Не скрывай** кнопку rewarded заранее на десктопе VK: `can_show_rewarded()` вернёт `false` только в OK и после явных отказов платформы.