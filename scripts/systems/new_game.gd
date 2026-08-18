class_name NewGame

const SEEDED_KEY := "new_game_seeded"

static func ensure(udb, def: Dictionary) -> bool:
	if bool(udb.get_pmeta(SEEDED_KEY, false)) or udb.dragon_count() > 0:
		return false
	apply(udb, def)
	return true

static func apply(udb, def: Dictionary) -> void:
	udb.begin_batch()
	udb.set_pmeta(SEEDED_KEY, true)
	for d in def.get("dragons", []):
		udb.add_dragon(int(d["id"]), int(d.get("level", 1)))
	var cur: Dictionary = def.get("currency", {})
	for kind in cur:
		udb.add_currency(kind, int(cur[kind]))
	var inv: Dictionary = admin_inventory(def, udb.is_admin())
	for item_name in inv:
		udb.add_item(item_name, int(inv[item_name]))
	udb.save()

static func admin_inventory(def: Dictionary, is_admin: bool) -> Dictionary:
	var inv: Dictionary = (def.get("inventory", {}) as Dictionary).duplicate(true)
	if not is_admin:
		return inv
	var rep: Dictionary = (def.get("admin", {}) as Dictionary).get("inventory_replace", {})
	for from_key in rep:
		if not inv.has(from_key):
			continue
		inv.erase(from_key)
		var add: Dictionary = rep[from_key]
		for k in add:
			inv[k] = int(inv.get(k, 0)) + int(add[k])
	return inv
