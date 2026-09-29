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

func init(options: Dictionary = {}) -> bool:
	var ok: bool = await _core.get_adapter().init_payments(options)
	if ok and auto_check_unconsumed:
		_check_unconsumed.call_deferred()
	return ok

func init_payments(signed: bool = false) -> bool:
	return await init({ "signed": signed })

func purchase(product_id: String, developer_payload: String = "") -> Dictionary:
	if _core.get_platform() == "vk" and _core.device.is_desktop():
		UniLogger.warn("payments", "purchase not supported on VK desktop")
		purchase_failed.emit("Not supported on desktop")
		return {}
	var purchase_data: Dictionary = await _core.get_adapter().purchase(product_id, developer_payload)
	if not purchase_data.is_empty():
		purchase_success.emit(purchase_data)
	else:
		purchase_failed.emit("Purchase failed")
	return purchase_data

func get_catalog() -> Array:
	var catalog: Array = await _core.get_adapter().get_catalog()
	catalog_loaded.emit(catalog)
	return catalog

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

func get_price_formatted(product: Dictionary) -> String:
	var price_str: String = str(product.get("price", ""))
	if not price_str.is_empty():
		return price_str
	var val: String = str(product.get("priceValue", ""))
	var cur: String = str(product.get("priceCurrencyCode", ""))
	if not cur.is_empty():
		return "%s %s" % [val, cur]
	return val
