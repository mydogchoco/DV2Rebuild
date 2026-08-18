class_name ImpShop
extends RefCounted

static func stock(table: Dictionary) -> Array:
	return (table.get("stock", []) as Array)

static func stock_of(table: Dictionary, kind: String) -> Array:
	if kind == "":
		return stock(table)
	var out: Array = []
	for r in stock(table):
		if String((r as Dictionary).get("kind", "")) == kind:
			out.append(r)
	return out

static func kinds(table: Dictionary) -> Array:
	var out: Array = []
	for r in stock(table):
		var k := String((r as Dictionary).get("kind", ""))
		if k != "" and not out.has(k):
			out.append(k)
	return out

static func can_buy(row: Dictionary, owned: Dictionary) -> bool:
	return int(owned.get(String(row.get("currency", "")), 0)) >= int(row.get("price", 0))

static func shortfall(row: Dictionary, owned: Dictionary) -> int:
	return maxi(0, int(row.get("price", 0)) - int(owned.get(String(row.get("currency", "")), 0)))

const RARITY_SOURCE := "imp_shop"

static func buy(row: Dictionary, owned: Dictionary, rng: RandomNumberGenerator,
		equip_table: Dictionary = {}) -> Dictionary:
	var cur := String(row.get("currency", ""))
	var price := int(row.get("price", 0))
	if cur == "" or price <= 0:
		return {"ok": false, "reason": "가격 정보가 없습니다"}
	if int(owned.get(cur, 0)) < price:
		return {"ok": false, "reason": "보석이 부족합니다"}
	var inst := Equipment.roll_instance(
		String(row.get("rarity_source", RARITY_SOURCE)), rng, equip_table)
	return {"ok": true, "spend_key": cur, "spend_count": price,
		"rarity": int(inst.get("rarity", 0)),
		"give_key": Equipment.item_key(String(row.get("key", "")), inst)}

static func currencies(table: Dictionary) -> Array:
	var out: Array = []
	for r in stock(table):
		var c := String((r as Dictionary).get("currency", ""))
		if c != "" and not out.has(c):
			out.append(c)
	return out

static func welcome_key(rng: RandomNumberGenerator) -> String:
	return "ShopWelcomeImp%d" % (rng.randi_range(1, 9))

static func buy_line_key(rng: RandomNumberGenerator) -> String:
	return "ShopBuyImpPong_%d" % (rng.randi_range(1, 4))
