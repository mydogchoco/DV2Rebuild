class_name DailyQuest
extends RefCounted

const POOL := [
	{"kind": "item", "key": "bless_of_dersa", "n": 1},
	{"kind": "currency", "key": "diamond", "n": 100},
	{"kind": "item", "key": "colosseum_coin", "n": 200},
	{"kind": "item", "key": "stone_heart2", "n": 1},
	{"kind": "item", "key": "stone_spirit2", "n": 1},
	{"kind": "crystal", "key": "", "n": 50},
]

const CRYSTALS := [
	"crystal_fire", "crystal_water", "crystal_wind", "crystal_earth",
	"crystal_light", "crystal_dark", "crystal_holy", "crystal_chaos", "crystal_shadow",
]

static func roll(rng: RandomNumberGenerator = null) -> Dictionary:
	var i := (rng.randi() % POOL.size()) if rng != null else RNG.randi_range(0, POOL.size() - 1)
	var pick: Dictionary = (POOL[i] as Dictionary).duplicate()
	if String(pick.get("kind", "")) == "crystal":
		var c := (rng.randi() % CRYSTALS.size()) if rng != null else RNG.randi_range(0, CRYSTALS.size() - 1)
		pick["kind"] = "item"
		pick["key"] = CRYSTALS[c]
	return pick

static func grant(pick: Dictionary) -> void:
	var key := String(pick.get("key", ""))
	var n := int(pick.get("n", 0))
	if key.is_empty() or n <= 0:
		return
	if String(pick.get("kind", "")) == "currency":
		UserDB.add_currency(key, n)
	else:
		UserDB.add_item(key, n)

static func roll_and_grant(rng: RandomNumberGenerator = null) -> Dictionary:
	var pick := roll(rng)
	grant(pick)
	return pick

static func display_name(pick: Dictionary) -> String:
	var key := String(pick.get("key", ""))
	if String(pick.get("kind", "")) == "currency":
		return {"diamond": "다이아", "gold": "골드"}.get(key, key)
	return String((Data.items.get(key, {}) as Dictionary).get("name", key))

static func describe(pick: Dictionary) -> String:
	var n := int(pick.get("n", 0))
	if String(pick.get("kind", "")) == "currency" and String(pick.get("key", "")) == "gold":
		return "%d G" % n
	return "%s %d개" % [display_name(pick), n]
