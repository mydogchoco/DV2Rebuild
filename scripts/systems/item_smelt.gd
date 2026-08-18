class_name ItemSmelt
extends RefCounted

static func for_source(source_key: String, ci_data: Dictionary) -> Dictionary:
	if source_key == "":
		return {}
	for r in (ci_data.get("recipes", []) as Array):
		var d: Dictionary = r
		if String(d.get("item1", "")) == source_key:
			return d
	return {}

static func can_smelt(source_key: String, ci_data: Dictionary) -> bool:
	return not for_source(source_key, ci_data).is_empty()

static func materials(recipe: Dictionary) -> Array:
	var out: Array = []
	var i1 := String(recipe.get("item1", ""))
	if i1 != "":
		out.append({"item": i1, "count": maxi(1, int(recipe.get("item1_cnt", 1)))})
	var i2 := String(recipe.get("item2", ""))
	if i2 != "":
		out.append({"item": i2, "count": maxi(1, int(recipe.get("item2_cnt", 1)))})
	return out

static func total_cost(recipe: Dictionary, count: int) -> int:
	return maxi(0, int(recipe.get("cost", 0))) * maxi(0, count)

static func max_count(recipe: Dictionary, have: Dictionary, gold: int) -> int:
	if recipe.is_empty():
		return 0
	var n := -1
	for m in materials(recipe):
		var md: Dictionary = m
		var per := int(md.get("count", 1))
		var owned := int(have.get(String(md.get("item", "")), 0))
		var fit := owned / per
		n = fit if n < 0 else mini(n, fit)
	if n < 0:
		return 0
	var cost := int(recipe.get("cost", 0))
	if cost > 0:
		n = mini(n, gold / cost)
	return maxi(0, n)

static func affordable(recipe: Dictionary, count: int, have: Dictionary, gold: int) -> bool:
	return count > 0 and count <= max_count(recipe, have, gold)
