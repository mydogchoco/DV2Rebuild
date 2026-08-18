class_name EggItem
extends RefCounted

const GRADE_SEP := "#"

static func key(base: String, grade: int) -> String:
	return base if grade <= 0 else base + GRADE_SEP + str(grade)

static func base_of(k: String) -> String:
	var i := k.rfind(GRADE_SEP)
	if i < 0:
		return k
	return k.substr(0, i) if k.substr(i + 1).is_valid_int() else k

static func grade_of(k: String) -> int:
	var i := k.rfind(GRADE_SEP)
	if i < 0:
		return 0
	var s := k.substr(i + 1)
	return maxi(0, int(s)) if s.is_valid_int() else 0

static func is_upgraded(k: String) -> bool:
	return grade_of(k) > 0

static func is_variant_of(k: String, base: String) -> bool:
	return base_of(k) == base
