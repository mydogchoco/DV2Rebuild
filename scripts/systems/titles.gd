class_name Titles
extends RefCounted

static func unlocked_nos(progress: Dictionary, table: Dictionary) -> Array:
	var out: Array = []
	for t in (table.get("titles", []) as Array):
		var td := t as Dictionary
		if is_unlocked(td, progress):
			out.append(int(td.get("title_no", 0)))
	return out

static func is_unlocked(title: Dictionary, progress: Dictionary) -> bool:
	var u: Dictionary = title.get("unlock", {})
	if u.is_empty():
		return false
	var have := int(progress.get(String(u.get("stat", "")), 0))
	return have >= int(u.get("need", 0))

static func progress_ratio(title: Dictionary, progress: Dictionary) -> float:
	var u: Dictionary = title.get("unlock", {})
	var need := float(u.get("need", 0))
	if need <= 0.0:
		return 1.0
	var have := float(progress.get(String(u.get("stat", "")), 0))
	return clampf(have / need, 0.0, 1.0)

static func by_no(no: int, table: Dictionary) -> Dictionary:
	for t in (table.get("titles", []) as Array):
		if int((t as Dictionary).get("title_no", -1)) == no:
			return t
	return {}

static func sorted_for_view(progress: Dictionary, table: Dictionary) -> Array:
	var got: Array = []
	var yet: Array = []
	for t in (table.get("titles", []) as Array):
		var td := t as Dictionary
		if bool(td.get("hidden", false)) and not is_unlocked(td, progress):
			continue
		if is_unlocked(td, progress):
			got.append(td)
		else:
			yet.append(td)
	got.sort_custom(func(a, b): return int(a["title_no"]) < int(b["title_no"]))
	yet.sort_custom(func(a, b): return int(a["title_no"]) < int(b["title_no"]))
	return got + yet
