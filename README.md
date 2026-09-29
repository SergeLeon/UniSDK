# UniSDK — Универсальный SDK для Яндекс.Игр и VK Игр в Godot 4

<p align="center">
  <b>Единый API для Яндекс.Игр и VK Игр с модульной системой платформ</b><br>
  Godot 4.3+ · GDScript 2.0 · Web-экспорт · Editor Mock Mode
</p>

---

## Содержание

1. [Обзор](#1-обзор)
2. [Архитектура](#2-архитектура)
3. [Структура проекта](#3-структура-проекта)
4. [Установка](#4-установка)
5. [Настройки проекта](#5-настройки-проекта)
6. [Конфигурация платформ](#6-конфигурация-платформ)
7. [Экспорт сборок](#7-экспорт-сборок)
8. [VK Hosting Deploy](#8-vk-hosting-deploy)
9. [Быстрый старт](#9-быстрый-старт)
10. [Определение платформы](#10-определение-платформы)
11. [Инициализация](#11-инициализация)
12. [Установка локали](#12-установка-локали)
13. [API Reference](#13-api-reference)
14. [Различия платформ](#14-различия-платформ)
15. [Лимиты платформ](#15-лимиты-платформ)
16. [Внутреннее устройство JS-мостов](#16-внутреннее-устройство-js-мостов)
17. [Editor Mock Mode](#17-editor-mock-mode)
18. [Миграция с Yandex-only SDK](#18-миграция-с-yandex-only-sdk)
19. [Известные ограничения](#19-известные-ограничения)
20. [Changelog](#20-changelog)

---

## 1. Обзор

**UniSDK** — универсальный плагин для Godot 4.3+, который абстрагирует работу с двумя игровыми платформами:

- **Яндекс.Игры** (`yandex.ru/games`) — через YaGames SDK
- **VK Игры** (`vk.ru/games`) — через VK Bridge

Один и тот же игровой код работает на обеих платформах. Адаптер определяется автоматически в момент запуска.

### Ключевые особенности

- **Единый API**: `UniSDK.ads.show_rewarded()` работает и в Яндексе, и в VK.
- **Автодетект платформы**: одна Web-сборка запускается везде.
- **Модульная система платформ**: добавление новой платформы сводится к регистрации профиля — без правок логики экспорта.
- **Настраиваемый экспорт**: через диалог конфигурации выбирается, какие платформы собирать, делать ли ZIP, создавать ли hosting-конфиг.
- **VK Storage с localStorage-кэшем**: мгновенный доступ к сохранениям даже при медленном VK Bridge.
- **Diff-логика записи**: в облако отправляются только изменившиеся ключи — экономия лимита 1000 вызовов/час.
- **Устойчивость к таймаутам VK**: все вызовы `vkBridge.send()` обёрнуты в `_safeSend()` с fallback.
- **Защита от параллельных вызовов VK Bridge**: сериализация `VKWebAppStorageSet` и `VKWebAppStorageGet`.
- **Rate-limit protection**: троттлинг лидербордов (1/сек) и player data чтения.
- **Защита звука и паузы**: автопауза и мьют `AudioServer` во время рекламы и потери фокуса.
- **Устойчивость к смене пользователя VK**: при смене `user_id` автоматически чистится локальный кэш сохранений.
- **Атомарная запись JSON**: mock/backup данные не повреждаются при падении.
- **Единый логгер**: уровни DEBUG/INFO/WARN/ERROR, отключение в релизе через ProjectSettings.

### Поддерживаемые версии

| Компонент | Версия |
|---|---|
| Godot | 4.3+ |
| GDScript | 2.0 |
| Yandex Games SDK | последний стабильный |
| VK Bridge | 2.15.0 (CDN) |

---

## 2. Архитектура

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
|  - UniLogger (уровни DEBUG/INFO/WARN/ERROR)                       |
|  - UniAtomicIO (атомарная запись JSON)                            |
+-------------------------------------------------------------------+
           |                       |                       |
           v                       v                       v
+---------------------+ +---------------------+ +---------------------+
|  YandexAdapter      | |  VKAdapter          | |  YandexMockBridge   |
|  (инлайн в HTML)    | |  (инлайн в HTML)    | |  (редактор)         |
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

## 3. Структура проекта

```
addons/uni_sdk/
├── plugin.cfg
├── uni_sdk_plugin.gd                # EditorPlugin
├── uni_sdk_export_plugin.gd         # EditorExportPlugin
├── uni_sdk.gd                       # Autoload (фасад)
├── platform_detector.gd
├── core/
│   ├── logger.gd                    # UniLogger (уровни)
│   ├── atomic_io.gd                 # Атомарная запись JSON
│   ├── platform_profile.gd          # Описание одной платформы
│   └── platform_registry.gd         # Реестр платформ в ProjectSettings
├── adapters/
│   ├── platform_adapter.gd          # Абстрактный базовый класс
│   ├── yandex_adapter.gd
│   └── vk_adapter.gd
├── modules/
│   ├── ads.gd
│   ├── player.gd
│   ├── payments.gd
│   ├── leaderboards.gd
│   ├── storage.gd
│   ├── feedback.gd
│   ├── shortcut.gd
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
    ├── yandex_template.html         # HTML shell + inline Yandex bridge
    └── vk_template.html             # HTML shell + inline VK bridge
```

---

## 4. Установка

1. Скопируй папку `addons/uni_sdk` в свой проект.
2. **Project → Project Settings → Plugins** → включи **UniSDK**.
3. Autoload `UniSDK` зарегистрируется автоматически.
4. При первом запуске плагин создаст дефолтные профили платформ (Yandex + VK).

---

## 5. Настройки проекта

**Project → Project Settings → UniSDK:**

| Настройка | Тип | По умолчанию | Описание |
|---|---|---|---|
| `uni_sdk/general/auto_init` | `bool` | `true` | Автоинициализация SDK при старте |
| `uni_sdk/general/auto_call_game_ready` | `bool` | `true` | Автоматический вызов `game_ready()` |
| `uni_sdk/general/auto_apply_locale` | `bool` | `true` | Автоматическая установка локали |
| `uni_sdk/general/auto_pause_tree` | `bool` | `false` | Автоматический `get_tree().paused = true` |
| `uni_sdk/general/debug_log` | `bool` | `false` | Включить подробный лог UniSDK в релизе |
| `uni_sdk/ads/auto_mute_audio` | `bool` | `true` | Глушить master-шину при рекламе |
| `uni_sdk/ads/interstitial_cooldown` | `float` | `60.0` | Кулдаун между межстраничными (сек) |
| `uni_sdk/player/get_data_min_interval_sec` | `float` | `15.0` | Минимальный интервал между чтениями player data (сек) |
| `uni_sdk/payments/auto_check_unconsumed` | `bool` | `true` | Проверять невосстановленные покупки |
| `uni_sdk/mock/player_name` | `string` | `"Test Player (Editor)"` | Ник игрока в mock |
| `uni_sdk/mock/player_unique_id` | `string` | `"mock_player_12345"` | Уникальный ID в mock |
| `uni_sdk/mock/is_authorized` | `bool` | `true` | Авторизация в mock |

### Реестр платформ

Платформы хранятся в `ProjectSettings`:

```
uni_sdk/platform_list       = PackedStringArray["yandex", "vk", ...]
uni_sdk/platforms/yandex    = { display_name, enabled, preset_name, ... }
uni_sdk/platforms/vk        = { ... }
```

Управление — через диалог конфигурации (см. ниже).

---

## 6. Конфигурация платформ

**Project → Tools → UniSDK: Configure Platforms...**

Открывается диалог, в котором можно для каждой платформы настроить:

| Поле | Описание |
|---|---|
| **Enabled** | Участвует ли платформа в создании пресетов и экспорте |
| **Preset name** | Имя пресета в `export_presets.cfg` |
| **Output directory** | Папка для сборки (`res://build/yandex`, `res://build/vk`, ...) |
| **HTML template** | Путь к Custom HTML Shell |
| **Create ZIP** | Создавать ли ZIP после экспорта |
| **ZIP name** | Имя ZIP-файла |
| **Hosting config** | Создавать ли конфиг хостинга (актуально для VK) |
| **Hosting config name** | Имя файла конфига |
| **Hosting config content (JSON)** | Содержимое конфига — редактируется в многострочном редакторе |

### Кнопки диалога

- **Reset to Defaults** — сбрасывает реестр и создаёт дефолтные платформы.
- **Validate JSON** — проверяет синтаксис JSON в редакторе hosting config.
- **Save** — валидирует все поля, сохраняет в ProjectSettings и закрывает диалог. **При ошибке JSON диалог не закрывается.**

### Формат hosting config для VK

По умолчанию:

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

- `app_id` — числовой ID приложения из VK Dev Console.
- `access_token` — сервисный ключ (Manage → Service token).
- `endpoints` — **обязательное поле** для `vk-miniapps-deploy`, без него будет `TypeError`.

---

## 7. Экспорт сборок

### Пункты меню

| Пункт | Действие |
|---|---|
| **UniSDK: Create Selected Presets** | Создаёт/обновляет пресеты для всех включённых платформ |
| **UniSDK: Export Selected Builds** | Экспортирует все включённые платформы + создаёт hosting-конфиги + пакует в ZIP |

### Что происходит при экспорте

1. Сохраняются все сцены (`EditorInterface.save_all_scenes()`).
2. Создаются пресеты с правильными `html/custom_html_shell` и `export_path`.
3. Для каждой платформы:
   - Чистится папка сборки.
   - Сохраняется существующий hosting config (содержит токены).
   - Запускается Godot CLI (`--export-release "preset name" output/index.html`).
   - Восстанавливается hosting config.
   - Если нужно — создаётся новый hosting config.
   - Если нужно — папка упаковывается в ZIP.

### Результат

```
res://build/
├── yandex/
│   ├── index.html
│   ├── index.js
│   ├── index.wasm
│   ├── index.pck
│   └── yandex_build.zip         ← для Яндекс.Консоли
└── vk/
    ├── index.html
    ├── index.js
    ├── index.wasm
    ├── index.pck
    ├── vk-hosting-config.json   ← для vk-miniapps-deploy (не в ZIP!)
    └── vk_build.zip              ← для VK Dev Console
```

> ⚠️ `vk-hosting-config.json` **исключается** из ZIP, потому что содержит секретный `access_token`. Добавь его в `.gitignore`:
> ```
> build/vk/vk-hosting-config.json
> ```

---

## 8. VK Hosting Deploy

VK Игры используют CDN VK для хостинга. Деплой через официальную утилиту `@vkontakte/vk-miniapps-deploy`.

### Шаги

1. **Заполни `build/vk/vk-hosting-config.json`**:
   - `app_id` — ID приложения из VK Dev Console.
   - `access_token` — сервисный ключ (Manage → Service token).

2. **Запусти деплой из папки `build/vk`**:
   ```bash
   cd build/vk
   npx @vkontakte/vk-miniapps-deploy
   ```

3. **Ответь на вопросы**:
   ```
   √ Would you like to deploy to VK Mini Apps hosting using these commands? ... yes
   √ Would you like to update prod urls? ... yes (для prod-режима)
   √ Would you like to update dev urls? ... no
   √ Would you like to update test group url? ... yes/no
   ```

4. После деплоя получишь URL вида `https://prod-app54788505-*.pages.vk-apps.ru`. Он станет доступен в VK Dev Console.

### Dev vs Prod режим VK

| Режим | URL | Storage | Платежи | Отзывы | Реклама |
|---|---|---|---|---|---|
| **dev** | `stage-app*.pages.vk-apps.ru` | ❌ | ❌ | ❌ | ❌ |
| **prod** | `prod-app*.pages.vk-apps.ru` | ✅ | ✅ (mobile only) | ❌ | ✅ (mobile only) |

**В dev-режиме VK сохранения не работают** — это ограничение stage-окружения VK, не SDK.

---

## 9. Быстрый старт

```gdscript
extends Node

func _ready() -> void:
    # 1. Дождаться инициализации SDK
    await UniSDK.ensure_initialized()

    # 2. Установить локаль (если auto_apply_locale выключен)
    var lang: String = UniSDK.environment.get_lang()
    if not lang.is_empty():
        TranslationServer.set_locale(lang)

    # 3. Сообщить платформе о готовности
    UniSDK.game_ready()

    # 4. Отметить старт геймплея
    UniSDK.gameplay_start()

    # 5. Загрузить сохранение
    var save_data = await UniSDK.player.get_data()
    print("Coins: ", save_data.get("coins", 0))
```

> ⚠️ Всегда жди `ensure_initialized()` перед первым обращением к `UniSDK.player.*`.

---

## 10. Определение платформы

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

Для VK возвращает `"vk"` или `"ok"` (Одноклассники). Для остальных — то же, что `get_platform()`.

### `UniSDK.is_web() -> bool`

`true`, если игра запущена в браузере.

---

## 11. Инициализация

### `init(options: Dictionary = {}) -> bool`

Инициализирует SDK через адаптер. Асинхронный. Идемпотентный.

### `ensure_initialized() -> bool`

Дожидается завершения инициализации. **Гарантирует**, что после `await` доступны `player.get_data()`, `player.is_authorized()` и т.д.

### Порядок инициализации

1. `_adapter.init()` — JS init или mock.
2. Извлекаются `environment` и `device`.
3. Если `auto_apply_locale` — устанавливается локаль.
4. **`await player._ensure_initialized()`** — профиль игрока готов.
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

## 12. Установка локали

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

## 13. API Reference

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
# Межстраничная
var res: Dictionary = await UniSDK.show_interstitial()
# { success: bool, was_shown: bool, error: String }

# Rewarded
var res: Dictionary = await UniSDK.show_rewarded()
# { success, rewarded, was_shown, error }
if res.rewarded: give_reward()

# Кулдаун
if UniSDK.ads.can_show_interstitial():
    await UniSDK.show_interstitial()

# Баннеры
await UniSDK.ads.show_banner()
await UniSDK.ads.hide_banner()
var status = await UniSDK.ads.get_banner_status()
```

### Профиль игрока

```gdscript
var info = await UniSDK.player.open_auth_dialog()
var is_auth: bool = UniSDK.player.is_authorized()
var user_id: String = UniSDK.player.get_id()
var name: String = UniSDK.player.get_name()
var photo: String = UniSDK.player.get_photo("medium")
var tex: Texture2D = await UniSDK.player.get_avatar_texture("medium")
```

### Сохранения (player data)

```gdscript
await UniSDK.player.set_data({ "coins": 500, "level": 3 }, true)
var data: Dictionary = await UniSDK.player.get_data(["coins", "level"])
await UniSDK.player.set_stats({ "high_score": 12000 })
var updated = await UniSDK.player.increment_stats({ "kills": 10 })
```

**Под капотом:**

- **Yandex**: `player.setData()` / `player.getData()` + localStorage-кэш с diff.
- **VK**: `VKWebAppStorageSet/Get` + localStorage cache + diff.

**Троттлинг `get_data()`**: если полный набор читали меньше 15 секунд назад (настраивается), вернётся кэш.

> ⚠️ **Никогда не проверяй `is_authorized()` при выборе хранилища** — player data API работает для всех.
>
> ⚠️ `setData()` в Яндексе **не мержит** данные. Всегда передавай полный набор ключей.

### Лидерборды

```gdscript
await UniSDK.leaderboards.set_score("highscores", 2500, "mage")
UniSDK.leaderboards.set_score_debounced("highscores", 5000, "", 1.0)
var entry = await UniSDK.leaderboards.get_player_entry("highscores")
var top = await UniSDK.leaderboards.get_entries("highscores", {
    "quantityTop": 10, "includeUser": true
})
```

**Ограничения платформы:**
- Yandex: 1 запрос/сек (автоматический троттлинг).
- Yandex: только авторизованные пользователи.
- `quantityTop` — 1..20, `quantityAround` — 1..10 (валидируется автоматически).

### Платежи

```gdscript
await UniSDK.payments.init_payments(true)  # signed
var catalog = await UniSDK.payments.get_catalog()
var purchase = await UniSDK.payments.purchase("coins_100")
if not purchase.is_empty():
    give_item()
    await UniSDK.payments.consume_purchase(purchase.purchaseToken)

UniSDK.payments.unconsumed_purchases_found.connect(func(list):
    for p in list: grant(p.productID)
    await UniSDK.payments.consume_all_purchases()
)
```

> ⚠️ VK: покупки работают только в мобильном приложении. На десктопе `purchase()` вернёт пустой словарь.

### Хранилище (key-value)

```gdscript
await UniSDK.storage.set_item("user_settings", '{ "sound": true }')
var val: String = await UniSDK.storage.get_item("user_settings")
```

### Отзывы и ярлыки

```gdscript
var can = await UniSDK.feedback.can_review()
if can.get("value", false): await UniSDK.feedback.request_review()

if await UniSDK.shortcut.can_show_prompt():
    var res = await UniSDK.shortcut.show_prompt()
```

### Устройство и окружение

```gdscript
var device_type: String = UniSDK.device.get_type()
var is_mob: bool = UniSDK.device.is_mobile()
var orientation: String = UniSDK.device.get_orientation()

var lang: String = UniSDK.environment.get_lang()
var browser_lang: String = UniSDK.environment.get_browser_lang()
var tld: String = UniSDK.environment.get_tld()
var app_id: String = UniSDK.environment.get_app_id()
var payload: String = UniSDK.environment.get_payload()
```

---

## 14. Различия платформ

| Возможность | Яндекс | VK |
|---|---|---|
| **Инициализация** | `YaGames.init()` | `VKWebAppInit` |
| **Готовность** | `LoadingAPI.ready()` | No-op |
| **Gameplay-метки** | `GameplayAPI` | No-op |
| **Авторизация** | Опциональная | Всегда |
| **Профиль** | `player.getPlayer()` | `VKWebAppGetUserInfo` |
| **Сохранения** | `player.setData/getData` + LS-кэш + diff | `VKWebAppStorageSet/Get` + LS-кэш + diff |
| **Лидерборды** | Native API (только authorized) | Storage-фолбэк |
| **Interstitial** | `adv.showFullscreenAdv()` | `VKWebAppShowNativeAds({ads_format:'interstitial'})` |
| **Rewarded** | `adv.showRewardedVideo()` | `VKWebAppShowNativeAds({ads_format:'reward', use_waterfall:true})` |
| **Banner** | `adv.showBannerAdv()` | `VKWebAppShowBannerAd` |
| **Покупки** | `payments.purchase()` | `VKWebAppShowOrderBox` (mobile only) |
| **Каталог** | `payments.getCatalog()` | ❌ |
| **Отзывы** | `feedback.requestReview()` | ❌ |
| **Ярлыки** | `shortcut.showPrompt()` | `VKWebAppAddToHomeScreenInfo` (mobile only) |
| **Back-кнопка** | `EVENTS.HISTORY_BACK` | `VKWebAppChangeFragment` |
| **Серверное время** | `ysdk.serverTime()` | `Date.now()` |
| **Язык** | `environment.i18n.lang` | `vk_language` |

### Рекомендации по UX

1. **Отзывы**: скрывай `YandexReviewButton` на VK (автоматически через `can_review() == false`).
2. **Лидерборды**: на VK не показывай полный топ — только свою позицию.
3. **Покупки**: в VK-web кнопку делай неактивной.
4. **Каталог**: на VK используй локальный конфиг.
5. **Реклама**: на VK-десктопе рекламы нет — предусмотри альтернативу.

---

## 15. Лимиты платформ

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
| Длина значения ключа | 4096 символов (сериализованная строка — 2236) |
| `VKWebAppShowNativeAds` | Только Android / iOS |
| `VKWebAppShowOrderBox` | Только Android / iOS |
| `VKWebAppAddToHomeScreenInfo` | Только Android |

### Что SDK делает автоматически

- **Троттлинг лидербордов** — 1 запрос/сек.
- **Троттлинг `get_data`** — 15 сек (настраивается через `uni_sdk/player/get_data_min_interval_sec`).
- **Diff записи** — в облако уходят только изменившиеся ключи.
- **Проверка размера** `set_player_data` — предупреждение при превышении 200 КБ.
- **Rate limit VK storage** — отключение облачной синхронизации после 5 фейлов подряд или при приближении к 990/час.
- **Проверка платформы** для рекламы/платежей/ярлыков — на неподдерживаемой платформе возвращается ошибка без вызова VK.

---

## 16. Внутреннее устройство JS-мостов

### Общий контракт

Оба моста (`yandex_template.html`, `vk_template.html`) приводят события к единому формату:

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
4. **Поколения**: `_release_ad_callbacks_deferred` использует счётчик поколений — не сносит callbacks, если запущена новая реклама.

### Diff-логика записи (общая для Yandex и VK)

При `setPlayerData(storageSet)`:

1. **Локально сохраняем ВСЕГДА** — мгновенно, без сети.
2. **Собираем только изменившиеся ключи** — сравнение с `_sentValues`.
3. **Если изменений нет** — облако вообще не дёргается.
4. **Отправляем** в облако **только изменившиеся ключи**.
5. **После успеха** — обновляем `_sentValues`.

Единый формат значений — функция `normalizeValue()`:

```javascript
function normalizeValue(v) {
    if (v === null || v === undefined) return null;
    if (typeof v === 'string') return v;
    try { return JSON.stringify(v); } catch (e) { return String(v); }
}
```

Для чтения из localStorage используется `normalizeFromStorage()`, который парсит JSON обратно и нормализует — иначе строковые значения всегда считались бы «изменёнными».

### `vk_template.html` — особенности

#### 1. `_safeSend(method, params, timeoutMs, fallbackValue, silentTimeout)`

Универсальная обёртка с таймаутом. Если VK молчит дольше `timeoutMs`, возвращается `fallbackValue`. `silentTimeout = true` — не логировать как warning.

#### 2. localStorage cache для storage

`storageGet` работает в 3 уровня:

```
1. Синхронное чтение localStorage      → 0 мс (если есть кэш)
2. Быстрый fallback через 800 мс        → если VK молчит
3. Полный ответ VK (до 10 сек)          → обновляет кэш
```

`storageSet`:
```
1. Мгновенно пишет в localStorage       → 0 мс
2. Мгновенно отвечает GDScript          → success: true
3. Последовательная отправка в VK       → по одному ключу за раз
```

**Последовательная отправка** — критично: VK Bridge ломает промисы при параллельных `VKWebAppStorageSet`.

#### 3. Проверка размера значений

Перед отправкой значения обрезаются до 4096 символов с предупреждением в консоль.

#### 4. Rate limit 1000/час

Каждая попытка записи (успех или ошибка) увеличивает счётчик. При приближении к 990 — записи прекращаются.

#### 5. Профиль игрока кэшируется

`getUserInfo` кэширует результат в localStorage под ключом `unisdk_vk___userinfo`. При смене `user.id` локальный кэш игрока (`unisdk_vk_player_*`) очищается.

#### 6. Проверка платформы

- Реклама: `IS_DESKTOP` → ошибка без вызова VK.
- Покупки: `IS_DESKTOP` → ошибка без вызова VK.
- Ярлыки: платформа должна быть `mobile_web` / `mobile_ipad`.

### `yandex_template.html` — особенности

- Diff-логика идентична VK-мосту.
- `getPlayer()` вызывается с `{scopes: true}`.
- `_withTimeout` — вспомогательный метод (для внутренних запросов).
- Все колбэки обёрнуты в `safeCallback` с try/catch.
- Обрабатывает `game_api_pause`, `game_api_resume`, `history_back`, `account_selection_*`.

---

## 17. Editor Mock Mode

В редакторе Godot (F5) SDK работает offline:

- **Платформа**: `PlatformDetector` вернёт `MOCK`.
- **Адаптер**: `YandexMockBridge`.
- **Хранение**: `user://unisdk_mock_data.json` (атомарная запись).
- **Задержки**: эмуляция рекламы (0.5–0.8 сек).

### Сброс данных

- **Project → Tools → UniSDK: Reset Mock Data** — очищает `unisdk_mock_data.json`.
- **Project → Tools → UniSDK: Reset Player Backup** — очищает `unisdk_player_backup.json`.

---

## 18. Миграция с Yandex-only SDK

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

## 19. Известные ограничения

1. **VK не имеет каталога товаров** — `payments.get_catalog()` пуст.
2. **VK не имеет API отзывов** — `feedback.can_review()` возвращает `false`.
3. **VK лидерборды** — только запись игрока, полный топ недоступен.
4. **VK покупки только в мобильном приложении** — в вебе `VKWebAppShowOrderBox` вернёт ошибку.
5. **VK реклама только в мобильном приложении** — на десктопе не показывается.
6. **VK dev-режим не сохраняет** — используй prod URL.
7. **VK Bridge может тормозить** на `desktop_web` — обёрнут в `_safeSend` с fallback.
8. **VK Storage лимит**: 1000 ключей × 4096 байт (сериализованные — 2236).
9. **Yandex `setData` не мержит** — всегда передавай полный набор.
10. **Yandex лидерборды только для авторизованных**.
11. **Локаль до первого рендера UI** — иначе первый кадр на неправильном языке.
12. **Не проверять `is_authorized()`** при выборе хранилища.
13. **ZIP-архив** содержит `index.html` в корне — требование обеих платформ.
14. **JS-мосты инлайнятся** в HTML — отдельные .js-файлы не работают в Web-экспорте.
15. **`platform_detected` эмитится deferred** — не используй его в `_init()`.

---

## 20. Changelog

### v1.1.0

**Исправленные баги:**

- Устранена утечка диалога конфигурации платформ (не закрывался после Save).
- Исправлена diff-логика записи для строковых значений (всегда считались изменёнными).
- `VKWebAppShowNativeAds` больше не вызывается на десктопе.
- `VKWebAppShowOrderBox` различает успех и ошибку по `error_type`.
- Зависший `VKWebAppCheckNativeAds` больше не приводит к показу рекламы.
- Callback `dispatch_exit` сохраняется от GC.
- При смене пользователя VK локальный кэш очищается.
- `_ensure_initialized` в player.gd не переинициализирует каждый раз.
- Удалён дублирующий `vk_bridge.js` / `yandex_bridge.js`.
- `platform_detected` эмитится через `call_deferred`.
- Устранён фalsy-баг в `storageGetItem`.
- `VKWebAppStorageGet` с пустым массивом не вызывает VK.
- Параллельные `VKWebAppStorageSet` сериализованы.
- Счётчик rate limit увеличивается на каждой попытке.
- Hard timeout интерстишела не возвращает `success: true`.
- Устранён busy-wait в late-reward window (заменён на ожидание события).
- Таймаут HTTPRequest для аватарок (10 сек).

**Новые возможности:**

- `UniLogger` с уровнями DEBUG/INFO/WARN/ERROR.
- `UniAtomicIO` для атомарной записи JSON.
- Троттлинг `get_data()` (настраивается через `uni_sdk/player/get_data_min_interval_sec`).
- Троттлинг лидербордов (1 запрос/сек).
- Валидация `quantityTop` / `quantityAround`.
- Проверка размера payload (200 КБ) перед `set_player_data`.
- Проверка типов в `increment_player_stats`.
- Проверка платформы для `VKWebAppAddToHomeScreenInfo`.
- `use_waterfall: true` для rewarded-рекламы VK.
- Проверка длины значений VK storage (4096).
- Атомарная запись mock/backup файлов.
- Поколения для `_release_ad_callbacks_deferred`.
- `get_platform_enum()` для типобезопасной работы.

**Улучшения:**

- Убран `print_rich` из продового кода.
- Убраны мёртвые поля (`_player_initialized` теперь используется).
- Унифицирован формат `normalizeValue` / `normalizeFromStorage`.
- Единый стиль отступов.
- Убран `push_error` там, где он не нужен.

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

# Реклама
var r = await UniSDK.show_rewarded()
if r.rewarded: give_reward()

# Сохранение
await UniSDK.player.set_data({ "coins": 100 }, true)
var d = await UniSDK.player.get_data()

# Лидерборд
await UniSDK.leaderboards.set_score("highscores", 5000)

# Покупка
await UniSDK.payments.init_payments()
var p = await UniSDK.payments.purchase("coins_pack")
if not p.is_empty():
    await UniSDK.payments.consume_purchase(p.purchaseToken)

# Хранилище
await UniSDK.storage.set_item("settings", JSON.stringify({}))
```

### Ключевые правила

1. **Всегда** устанавливай локаль после инициализации.
2. **Всегда** вызывай `game_ready()` после загрузки ассетов.
3. **Всегда** `gameplay_start()` / `gameplay_stop()` вокруг геймплея.
4. **Всегда** проверяй `result.rewarded` для rewarded-рекламы.
5. **Всегда** потребляй consumable-покупки.
6. **Всегда** передавай полный набор ключей в `set_data` (Yandex не мержит).
7. **Никогда** не вызывай `set_score()` чаще 1 раза в секунду (SDK троттлит).
8. **Никогда** не проверяй `is_authorized()` при выборе хранилища.
9. **Никогда** не полагайся на порядок событий рекламы.
10. **Проверяй `UniSDK.get_platform()`**, если поведение платформ отличается.
11. **Скрывай UI**, если платформа не поддерживает фичу.
12. **Помни про rate limits** — SDK защищает автоматически, но лишние вызовы не нужны.
