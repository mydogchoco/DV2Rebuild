class_name SellPrice
extends RefCounted

static func unit_price(key: String, tables: Dictionary) -> int:
	var cfg := config(tables)
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		return _gem_price(g, cfg, tables.get("gems", {}))
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		return _equip_price(key, ck, cfg)
	return _item_price(key, cfg, tables)

static func is_sellable(key: String, tables: Dictionary) -> bool:
	return unit_price(key, tables) > 0

static func stacks(key: String) -> bool:
	return Equipment.parse_item_key(key) == ""

static func talk_index(unit: int, tables: Dictionary) -> int:
	var th := int(config(tables).get("talk_price_threshold", 1000))
	return 2 if unit >= th else 1

static func config(tables: Dictionary) -> Dictionary:
	return (tables.get("shop", {}) as Dictionary).get("sell", {})

static func _gem_price(inst: Dictionary, cfg: Dictionary, gem_table: Dictionary) -> int:
	var name := String(inst.get("name", ""))
	var gd := Gem.gem_def(name, gem_table)
	if gd.is_empty():
		return 0
	var gc: Dictionary = cfg.get("gem", {})
	var cost := float(gc.get("base_cost", 3000))
	var tier := maxi(0, int(inst.get("tier", 0)))
	for t in tier:
		cost += float(Gem.upgrade_cost(t, gem_table))
	var mult: Dictionary = gc.get("category_mult", {})
	cost *= float(mult.get(String(gd.get("category", "normal")), 1.0))
	if bool(inst.get("broken", false)):
		cost *= float(gc.get("broken_mult", 0.5))
	return _apply_ratio(cost, cfg, "gem")

static func _equip_price(inv_key: String, catalog_key: String, cfg: Dictionary) -> int:
	var ec: Dictionary = cfg.get("equip", {})
	var parts := catalog_key.split(":")
	var group := String(parts[0]) if parts.size() > 0 else ""
	var cost := 0.0
	match group:
		"basic":
			var grade := int(parts[2]) if parts.size() > 2 else 0
			cost = float(ec.get("basic_base", 4000)) \
				+ float(ec.get("basic_per_grade", 4000)) * grade
		"artifact":
			var ag := int(parts[2]) if parts.size() > 2 else 0
			cost = float(ec.get("artifact_base", 4000)) \
				* pow(float(ec.get("artifact_grade_mult", 4.0)), ag)
		_:
			cost = float((ec.get("group_cost", {}) as Dictionary).get(group, 0))
	if cost <= 0.0:
		return 0
	var meta := Equipment.item_key_meta(inv_key)
	var rm: Array = ec.get("rarity_mult", [])
	var rar := clampi(int(meta.get("rarity", 0)), 0, maxi(0, rm.size() - 1))
	if not rm.is_empty():
		cost *= float(rm[rar])
	cost *= 1.0 + float(ec.get("enhance_mult_pct", 5)) * 0.01 * int(meta.get("enhance", 0))
	if int(meta.get("belong", 0)) > 0:
		cost *= float(ec.get("bound_mult", 0.5))
	return _apply_ratio(cost, cfg, "equip")

static func _item_price(key: String, cfg: Dictionary, tables: Dictionary) -> int:
	var it: Dictionary = (tables.get("items", {}) as Dictionary).get(key, {})
	if it.is_empty():
		return 0
	if String(it.get("category", "")) == "currency":
		return 0
	var base := int((tables.get("buy", {}) as Dictionary).get(key, 0))
	if base <= 0 and String(it.get("category", "")) == "food":
		base = _food_base(it, cfg, key)
	if base <= 0:
		return 0
	return _apply_ratio(float(base), cfg, "item")

static func _food_base(it: Dictionary, cfg: Dictionary, key: String) -> int:
	var rules: Dictionary = cfg.get("food_base", {})
	var by_item: Dictionary = rules.get("by_item", {})
	if by_item.has(key):
		return int(by_item[key])
	var r: Dictionary = rules.get(String(it.get("subcategory", "")), {})
	if r.is_empty():
		return 0
	if r.has("flat"):
		return int(r["flat"])
	if r.has("by_size"):
		return int((r["by_size"] as Dictionary).get(String(it.get("size", "")), 0))
	if r.has("by_tier"):
		var arr: Array = r["by_tier"]
		var i := int(it.get("tier", 0)) - 1
		return int(arr[i]) if i >= 0 and i < arr.size() else 0
	return 0

static func _apply_ratio(cost: float, cfg: Dictionary, kind: String) -> int:
	var ratio := float((cfg.get("ratio", {}) as Dictionary).get(kind,
		float(cfg.get("_default_ratio", 0.1))))
	return maxi(1, int(round(cost * ratio))) if cost > 0.0 else 0
