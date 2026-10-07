@tool
class_name UniPayments
extends RefCounted

signal purchase_success(purchase: Dictionary)
signal purchase_failed(error: String)
signal catalog_loaded(catalog: Array)
signal purchases_loaded(purchases: Array)
signal unconsumed_purchases_found(purchases: Array)

var _core: Node
var auto_check_unconsumed: bool = true

func _init(core: Node) -> void:
	_core = core
	auto_check_unconsumed = bool(ProjectSettings.get_setting("uni_sdk/payments/auto_check_unconsumed", true))


# ------------------------------------------------------------------
#  Platform capabilities
# ------------------------------------------------------------------

## Покупки доступны?
## Yandex: всегда.
## VK / OK: только в мобильном приложении.
## Mock: всегда.
func is_purchase_supported() -> bool:
	if not _core.is_initialized:
		return true
	var platform: String = _core.get_platform()
	if platform == "mock":
		return true
	if platform == "vk":
		return not _core.device.is_desktop()
	return true


## Каталог товаров доступен?
## Yandex: да.
## VK / OK: API каталога отсутствует.
func is_catalog_supported() -> bool:
	var platform: String = _core.get_platform()
	if platform == "vk":
		return false
	return true


func can_purchase() -> bool:
	return is_purchase_supported()

func can_get_catalog() -> bool:
	return is_catalog_supported()


# ------------------------------------------------------------------
#  Lifecycle
# ------------------------------------------------------------------

func init(options: Dictionary = {}) -> bool:
	var ok: bool = await _core.get_adapter().init_payments(options)
	if ok and auto_check_unconsumed:
		_check_unconsumed.call_deferred()
	return ok

func init_payments(signed: bool = false) -> bool:
	return await init({ "signed": signed })


# ------------------------------------------------------------------
#  Purchase
# ------------------------------------------------------------------

func purchase(product_id: String, developer_payload: String = "") -> Dictionary:
	if not is_purchase_supported():
		var err := "Purchase not supported on this platform"
		purchase_failed.emit(err)
		return { "error": err }

	var purchase_data: Dictionary = await _core.get_adapter().purchase(product_id, developer_payload)
	if not purchase_data.is_empty():
		purchase_success.emit(purchase_data)
	else:
		purchase_failed.emit("Purchase failed")
	return purchase_data


# ------------------------------------------------------------------
#  Catalog
# ------------------------------------------------------------------

func get_catalog() -> Array:
	if not is_catalog_supported():
		catalog_loaded.emit([])
		return []
	var catalog: Array = await _core.get_adapter().get_catalog()
	catalog_loaded.emit(catalog)
	return catalog


# ------------------------------------------------------------------
#  Purchases list
# ------------------------------------------------------------------

func get_purchases() -> Array:
	var purchases: Array = await _core.get_adapter().get_purchases()
	purchases_loaded.emit(purchases)
	return purchases

func consume_purchase(purchase_token: String) -> bool:
	return await _core.get_adapter().consume_purchase(purchase_token)

func _check_unconsumed() -> void:
	var purchases: Array = await get_purchases()
	if not purchases.is_empty():
		unconsumed_purchases_found.emit(purchases)

func consume_all_purchases() -> Array:
	var purchases: Array = await get_purchases()
	var consumed: Array = []
	for p in purchases:
		var token: String = str(p.get("purchaseToken", ""))
		if not token.is_empty():
			if await consume_purchase(token):
				consumed.append(p)
	return consumed


# ------------------------------------------------------------------
#  Helpers
# ------------------------------------------------------------------

func get_price_formatted(product: Dictionary) -> String:
	var price_str: String = str(product.get("price", ""))
	if not price_str.is_empty():
		return price_str
	var val: String = str(product.get("priceValue", ""))
	var cur: String = str(product.get("priceCurrencyCode", ""))
	if not cur.is_empty():
		return "%s %s" % [val, cur]
	return val