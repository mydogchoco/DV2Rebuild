class_name Field
extends RefCounted

const VARIANT_KEYS := [
	"enemies", "dragons", "level", "desc", "random_boss",
	"boss", "bgm", "bg", "element", "name", "party3", "once_per_day",
]

static func has_variant(stage: Dictionary, mode: String) -> bool:
	if mode != "night" and mode != "kades":
		return false
	var b = stage.get(mode, {})
	return typeof(b) == TYPE_DICTIONARY and not (b as Dictionary).is_empty()

static func apply_variant(stage: Dictionary, mode: String) -> Dictionary:
	if stage.is_empty() or not has_variant(stage, mode):
		return stage
	var blk: Dictionary = stage[mode]
	var out := stage.duplicate(true)
	for k in VARIANT_KEYS:
		if blk.has(k):
			out[k] = blk[k]
	out["variant"] = mode
	out.erase("night")
	out.erase("kades")
	return out

static func variants_of(stage: Dictionary) -> Array:
	var out: Array = []
	for m in ["night", "kades"]:
		if has_variant(stage, m):
			out.append(m)
	return out
