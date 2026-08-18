class_name StoryQuest
extends RefCounted

const PROGRESS_KEY := "story_sq_%d"

const MODE_NAME := {"N": "일반", "H": "영웅"}

static func implemented_with(ep: Dictionary, scenario: Dictionary) -> bool:
	if ep.is_empty() or bool(ep.get("no_lines", false)) or scenario.is_empty():
		return false
	for part in (scenario.get("parts", []) as Array):
		if not ((part as Dictionary).get("lines", []) as Array).is_empty():
			return true
	return false

static func spec_of(ep: Dictionary) -> Dictionary:
	var s = ep.get("submission", null)
	return s if s is Dictionary else {}

static func cleared_with(ep: Dictionary, count: int) -> bool:
	var sp := spec_of(ep)
	if sp.is_empty():
		return true
	return count >= int(sp.get("count", 0))

static func counts_for(sp: Dictionary, ev: Dictionary) -> bool:
	if sp.is_empty():
		return false
	if String(sp.get("type", "")) != String(ev.get("kind", "")):
		return false
	if sp.has("field") and int(sp["field"]) != int(ev.get("field", -1)):
		return false
	if sp.has("region") and String(sp["region"]) != String(ev.get("region", "")):
		return false
	if sp.has("monster") and int(sp["monster"]) != int(ev.get("monster", -1)):
		return false
	if sp.has("item") and String(sp["item"]) != String(ev.get("item", "")):
		return false
	if bool(sp.get("win", false)) and not bool(ev.get("win", false)):
		return false
	if bool(sp.get("night", false)) and not bool(ev.get("night", false)):
		return false
	if sp.has("kades") and int(sp["kades"]) != int(ev.get("kades", 0)):
		return false
	return true

const TITLE_FMT := {
	"ADVENTURE": "-%s  %d회 탐험-",
	"KILL": "-%s  %s%d마리 퇴치-",
	"GATHER": "-%s  %s%d개 획득-",
	"COLOSSEUM": "-%s  %d회 전투-",
}

static func cond_line(sp: Dictionary, place: String, target: String) -> String:
	if sp.is_empty():
		return ""
	var kind := String(sp.get("type", ""))
	var n := int(sp.get("count", 0))
	var tgt := (target + " ") if target != "" else ""
	match kind:
		"KILL", "GATHER":
			return TITLE_FMT[kind] % [place, tgt, n]
		"COLOSSEUM":
			var head := "콜로세움 1vs1 승리" if bool(sp.get("win", false)) else "콜로세움"
			return TITLE_FMT[kind] % [head, n]
		_:
			return TITLE_FMT.get(kind, "-%s  %d-") % [place, n]

static func line_with(ep: Dictionary, count: int, place: String, target := "") -> String:
	var sp := spec_of(ep)
	if sp.is_empty():
		return ""
	var parts: Array[String] = [_ui("#fdc3d44b") % String(sp.get("name", ""))]
	var n := int(sp.get("count", 0))
	parts.append("%s  %d/%d" % [cond_line(sp, place, target), count, n])
	return "    ".join(parts)

static func _ui(key: String) -> String:
	return UiText.get_text(key)
