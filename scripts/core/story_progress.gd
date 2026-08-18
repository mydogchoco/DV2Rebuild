class_name StoryProgress
extends RefCounted

const SQ := preload("res://scripts/systems/story_quest.gd")

const PROGRESS_KEY := "story_sq_%d"
const REWARD_KEY := "story_reward_%d"
const REWARD_GEM_COLOR := {"R": "ATT", "B": "DEF", "Y": "HP", "W": "ALL"}

static func count(no: int) -> int:
	return int(UserDB.get_progress(PROGRESS_KEY % no, 0))

static func spec(no: int) -> Dictionary:
	return SQ.spec_of(Data.story_episode(no))

static func gate_cleared(no: int) -> bool:
	return SQ.cleared_with(Data.story_episode(no), count(no))

const MISSION_KEY := "story_mission_at_%d"

static func mission_resume(no: int) -> int:
	return int(UserDB.get_progress(MISSION_KEY % no, 0))

static func issue_mission(no: int, flow_step: int) -> void:
	UserDB.set_progress(MISSION_KEY % no, maxi(mission_resume(no), maxi(1, flow_step)))

static func pending_episode() -> int:
	var no := next_episode()
	if no <= 0 or mission_resume(no) <= 0:
		return 0
	return 0 if gate_cleared(no) else no

static func seen(no: int) -> bool:
	return bool(UserDB.get_progress("scenario_%d_0" % no, false))

static func max_dragon_level() -> int:
	var best := 0
	for d in UserDB.dragons():
		best = maxi(best, int(d.get("level", 1)))
	return best

static func implemented(no: int) -> bool:
	return SQ.implemented_with(Data.story_episode(no), Data.scenario_def(str(no)))

static func previous_episode(no: int) -> int:
	var prev := 0
	for candidate in Data.story_episodes():
		var n := int(candidate)
		if n >= no:
			break
		if implemented(n):
			prev = n
	return prev

static func unlocked(no: int) -> bool:
	var ep := Data.story_episode(no)
	if not implemented(no):
		return false
	var prev := previous_episode(no)
	if prev > 0 and not seen(prev):
		return false
	var need := int(ep.get("unlock_level", 0))
	if need > 0 and max_dragon_level() < need:
		return false
	return true

static func next_episode() -> int:
	var eps := Data.story_episodes()
	var last_implemented := 0
	for no in eps:
		var n := int(no)
		if not implemented(n):
			continue
		last_implemented = n
		if not seen(n):
			return n
	return last_implemented

static func active_episode() -> int:
	return next_episode()

static func banner_line(no: int) -> String:
	var sp := spec(no)
	if sp.is_empty():
		return ""
	return SQ.line_with(Data.story_episode(no), count(no), place_name(sp), target_name(sp))

static func place_name(sp: Dictionary) -> String:
	if sp.has("field"):
		var nm := String(Data.stage(str(int(sp["field"]))).get("name", "필드 %d" % int(sp["field"])))
		var v := ""
		if bool(sp.get("night", false)):
			v = "밤"
		elif int(sp.get("kades", 0)) != 0:
			v = "카데스의 공간"
		return nm if v == "" else "%s(%s)" % [nm, v]
	if sp.has("region"):
		return REGION_KR.get(String(sp["region"]), String(sp["region"]))
	return ""

static func target_name(sp: Dictionary) -> String:
	if sp.has("item"):
		return String(Data.get_item(String(sp["item"])).get("name", ""))
	if sp.has("monster") and sp.has("field"):
		for e in _phase_enemies(Data.stage(str(int(sp["field"]))), sp):
			if int((e as Dictionary).get("id", -1)) == int(sp["monster"]):
				return String((e as Dictionary).get("name", ""))
	return ""

static func _phase_enemies(st: Dictionary, sp: Dictionary) -> Array:
	if bool(sp.get("night", false)):
		return ((st.get("night", {}) as Dictionary).get("enemies", []) as Array)
	if int(sp.get("kades", 0)) != 0:
		return ((st.get("kades", {}) as Dictionary).get("enemies", []) as Array)
	return (st.get("enemies", []) as Array)

const REGION_KR := {
	"yutakan": "유타칸 전지역", "elf": "엘프 전지역",
	"dwarf": "드워프 전지역", "uno": "우노 전지역",
}

static func note_event(ev: Dictionary) -> int:
	var no := pending_episode()
	if no <= 0:
		return 0
	var sp := spec(no)
	if not SQ.counts_for(sp, ev):
		return 0
	var need := int(sp.get("count", 0))
	var cur := count(no)
	if cur >= need:
		return 0
	cur += 1
	UserDB.set_progress(PROGRESS_KEY % no, cur)
	if cur < need:
		return 0
	if String(sp.get("type", "")) == "GATHER":
		var key := String(sp.get("item", ""))
		var take := mini(need, UserDB.item_count(key))
		if key != "" and take > 0:
			UserDB.add_item(key, -take)
	return no

const MARK_OVERRIDE := {
	11: 4,
	26: 9,
	48: 21,
	49: 1003,
	50: 1003,
	51: 1003,
	52: 23,
	53: 16,
	54: 1004,
	55: 1004,
	56: 1004,
	57: 19,
	96: 1004,
	74: {"field": 6, "phase": "night"},
	79: {"field": 7, "phase": "night"},
	80: {"field": 4, "phase": "night"},
	81: {"field": 4, "phase": "night"},
	82: {"field": 1, "phase": "night"},
	83: {"field": 1, "phase": "night"},
	84: {"field": 9, "phase": "night"},
	85: {"field": 1, "phase": "night"},
	86: {"field": 1, "phase": "night"},
	92: {"field": 1002, "phase": "kades"},
	93: {"field": 9, "phase": "kades"},
	94: {"field": 5, "phase": "kades"},
	95: {"field": 1, "phase": "kades"},
	98: {"field": 14, "phase": "kades"},
	99: {"field": 7, "phase": "kades"},
	100: {"field": 15, "phase": "kades"},
}

static func yutakan_phase() -> String:
	if bool(UserDB.get_pmeta("kades_space", false)):
		return "kades"
	if bool(UserDB.get_pmeta("yutakan_night", false)):
		return "night"
	return "day"

static func mark_pending_phase() -> String:
	var no := active_episode()
	if MARK_OVERRIDE.has(no):
		var ov = MARK_OVERRIDE[no]
		if ov is Dictionary:
			var want := String((ov as Dictionary).get("phase", ""))
			return want if want != "" and want != yutakan_phase() else ""
		return ""
	var sm := Data.story_scenario_mark(no)
	if sm.has("night") and bool(UserDB.get_pmeta("yutakan_night", false)) != bool(sm["night"]):
		return "night" if bool(sm["night"]) else "day"
	return ""

static func mark_field() -> int:
	if pending_episode() > 0:
		return 0
	var no := active_episode()
	if MARK_OVERRIDE.has(no):
		var ov = MARK_OVERRIDE[no]
		if ov is Dictionary:
			var want := String((ov as Dictionary).get("phase", ""))
			if want != "" and want != yutakan_phase():
				return 0
			return int((ov as Dictionary)["field"])
		return int(ov)
	var sm := Data.story_scenario_mark(no)
	if not sm.is_empty():
		if sm.has("night") and bool(UserDB.get_pmeta("yutakan_night", false)) != bool(sm["night"]):
			return 0
		var f = sm.get("field", 0)
		return _town_fallback(Data.story_mark_field(no) if f is String else int(f))
	return _town_fallback(notify_field())

const TOWN_MARK_FIELD := 1002

static func _town_fallback(field: int) -> int:
	return TOWN_MARK_FIELD if field <= 0 or field == 999 else field

static func notify_field() -> int:
	var no := active_episode()
	var sp := spec(pending_episode())
	if sp.has("field"):
		return int(sp["field"])
	var notify := Data.story_notify_field(no)
	if notify > 0:
		return notify
	var cond := Data.story_notify_conditional(no)
	if not cond.is_empty():
		return _notify_conditional_field(cond)
	return Data.story_mark_field(no)

static func _notify_conditional_field(cond: Dictionary) -> int:
	if cond.has("night"):
		var night := bool(UserDB.get_pmeta("yutakan_night", false))
		if night != bool(cond["night"]):
			return 0
	return int(cond.get("field", 0))

static func reward_claimed(no: int) -> bool:
	return bool(UserDB.get_progress(REWARD_KEY % no, false))

static func grant_special_reward(no: int) -> Dictionary:
	var rw := Data.story_special_reward(no)
	if rw.is_empty() or reward_claimed(no):
		return {}
	var dno := int(rw.get("dragon_no", 0))
	if dno <= 0:
		return {}
	var inst := UserDB.add_dragon(dno, int(rw.get("level", 1)))
	var uid := int(inst.get("uid", 0))
	var types: Array = []
	for c in (rw.get("gem_colors", []) as Array):
		types.append(String(REWARD_GEM_COLOR.get(String(c), "ATT")))
	if types.size() == Gem.SLOTS:
		var d := UserDB.get_dragon(uid)
		if not d.is_empty():
			d["gems"] = Gem.set_types(d.get("gems", {}), types)
	var learn: Array = []
	var missing: Array = []
	for s in (rw.get("skills", []) as Array):
		var sid := int((s as Dictionary).get("no", 0))
		if Data.skills.has(str(sid)):
			learn.append({"id": sid, "level": int((s as Dictionary).get("lv", 1)), "dedicated": false})
		else:
			missing.append(sid)
	if not learn.is_empty():
		UserDB.ensure_dragon_skills(uid, learn)
	UserDB.set_progress(REWARD_KEY % no, true)
	return {
		"uid": uid, "dragon_no": dno,
		"name": String(Data.get_dragon(dno).get("name", "드래곤 %d" % dno)),
		"level": int(rw.get("level", 1)),
		"skills_granted": learn.size(), "skills_missing": missing,
	}
