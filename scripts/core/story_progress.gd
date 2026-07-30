class_name StoryProgress
extends RefCounted

## 스토리 진행도 — `Data`(마스터) 와 `UserDB`(세이브) 를 물어다 규칙층
## `scripts/systems/story_quest.gd`(순수)에 넘기는 **얇은 조정 층**.
##
## ## 왜 규칙과 나눴나 (CLAUDE.md §8)
##
## `StoryQuest` 는 오토로드를 참조하지 않아 `--script` 헤드리스로 단독 테스트된다
## (`scripts/tools/test_story_quest.gd`). 오토로드 식별자가 하나라도 섞이면 그 모드에서
## **컴파일 자체가 실패**해 순수 함수까지 못 부른다 — 실제로 그렇게 막혀서 갈랐다.
## ⇒ 규칙 = `StoryQuest`(systems) · 데이터·세이브 배선 = 여기(core) · 연출 = `scripts/ui`.
##
## ## 원작 대응
##
## 원작은 `ScenarioManager`(현재 회차 sn/sn_s) + `QuestManager`(진행 카운터) + `AccountManager`
## (서버 저장분 복원)가 나눠 갖던 상태다. 오프라인에서는 전부 로컬 세이브 한 곳이다.

const SQ := preload("res://scripts/systems/story_quest.gd")

## 진행 카운터 세이브 키(회차별 서브퀘스트 달성 수).
const PROGRESS_KEY := "story_sq_%d"
## 특별보상 수령 여부 키.
const REWARD_KEY := "story_reward_%d"
## 원작 젬 칸 색 → 우리 슬롯 타입. `data/gems.json` `slot_types._source` 그대로:
##   `Dragon::getGemType` 0=ATT 1=DEF 2=HP 3=ALL ↔ `gem_red/blue/yellow/white_bg`.
const REWARD_GEM_COLOR := {"R": "ATT", "B": "DEF", "Y": "HP", "W": "ALL"}


# ══════════════════════════════════════════════════════════════════ 진행도 조회
static func count(no: int) -> int:
	return int(UserDB.get_progress(PROGRESS_KEY % no, 0))


static func spec(no: int) -> Dictionary:
	return SQ.spec_of(Data.story_subquest, no)


static func gate_cleared(no: int) -> bool:
	return SQ.cleared_with(Data.story_subquest, no, count(no))


static func seen(no: int) -> bool:
	return bool(UserDB.get_progress("scenario_%d_0" % no, false))


static func max_dragon_level() -> int:
	var best := 0
	for d in UserDB.dragons():
		best = maxi(best, int(d.get("level", 1)))
	return best


## 해금 판정 = 레벨 게이트(또는 직전 회차 관람) **AND** 서브퀘스트 완료.
## 레벨 게이트는 `data/story.json` `_unlock`(ASSUMPTION — 원작 `info_scenario_v2.min_lv` 유실),
## 서브퀘스트는 원작 하드코딩 수치(`data/story_subquest.json`).
static func unlocked(no: int) -> bool:
	var ep := Data.story_episode(no)
	if ep.is_empty():
		return false
	var need := int(ep.get("unlock_level", 0))
	if need > 0:
		if max_dragon_level() < need:
			return false
	elif not (no <= 1 or seen(no - 1)):
		return false
	return gate_cleared(no)


## "다음에 볼 회차" = 아직 안 본 것 중 가장 앞. 전부 봤으면 마지막.
static func next_episode() -> int:
	var eps := Data.story_episodes()
	for no in eps:
		if not seen(int(no)):
			return int(no)
	return int(eps[-1]) if not eps.is_empty() else 1


## 지금 진행 중인 회차 = 다음에 볼 회차. 원작 `ScenarioManager+0x168`(sn) 자리.
static func active_episode() -> int:
	return next_episode()


## 배너 한 줄(서브미션 이름 + "-<필드> N회 탐험- cur/need").
static func banner_line(no: int) -> String:
	var sp := SQ.spec_of(Data.story_subquest, no)
	var fname := ""
	if not sp.is_empty():
		fname = String(Data.stage(str(int(sp["field"]))).get("name", ""))
	return SQ.line_with(Data.story_subquest, Data.story_episode(no), no, count(no), fname)


# ══════════════════════════════════════════════════════════════════ 진행도 기록
## 탐험 1회 보고 — 원작 `AdventureScene::setEventScenario` 의
## `QuestData::setCount(getCount() + 1)`(AdventureScene.c:45749) 자리.
## 조건이 맞는 진행 회차의 카운터를 올리고, 이번에 조건을 채웠으면 그 회차 번호를 돌려준다
## (0 = 변화 없음). 연출은 호출한 render 층이 한다(§8.3).
static func note_adventure(field_no: int, is_night := false, variant: Dictionary = {}) -> int:
	var no := active_episode()
	var sp := SQ.spec_of(Data.story_subquest, no)
	if not SQ.counts_for(sp, field_no, is_night, variant):
		return 0
	var cur := count(no)
	if cur >= int(sp["need"]):
		return 0
	cur += 1
	UserDB.set_progress(PROGRESS_KEY % no, cur)
	return no if cur >= int(sp["need"]) else 0


## 월드맵 이벤트 마크를 찍을 필드 — 원작 `getEventMarkFieldValue(sn, isNight)`.
## 0 이면 마크 없음. 서브퀘스트를 이미 채웠으면 마크를 지운다.
static func mark_field() -> int:
	var no := active_episode()
	if gate_cleared(no):
		return 0
	var sp := SQ.spec_of(Data.story_subquest, no)
	if not sp.is_empty():
		return int(sp["field"])
	return Data.story_mark_field(no)


# ══════════════════════════════════ 회차별 특별보상 드래곤 (원작 setSpecialReward)
## 원작 `ScenarioManager::setSpecialReward` 가 3건을 하드코딩한다(26·58·78화):
##   26화 → 드래곤 9 · 58화 → 87 · 78화 → 105. 전부 Lv.50 · 등급 3 · 젬 3칸 · 스킬 3개.
## 지급 시점은 원작 문구가 못 박는다 — `ScenarioRewardNoti1`:
##   "해당 시나리오 클리어시 지급되며, 해당 드래곤은 하늘둥지에 맡겨집니다."
## 🟡 우리 '하늘둥지'(`DragonHistoryLayer` 이식분)는 **떠나보낸 드래곤 기록부**라 보관함이
##    아니다 → 보유 목록에 바로 넣는다(원작 대비 이탈: 수령 절차가 없다).
static func reward_claimed(no: int) -> bool:
	return bool(UserDB.get_progress(REWARD_KEY % no, false))


## 그 회차의 특별보상을 지급한다. 이미 받았거나 보상이 없으면 {}. 멱등.
## 반환 {uid, dragon_no, name, level, skills_granted, skills_missing} — 연출은 render 가 한다.
static func grant_special_reward(no: int) -> Dictionary:
	var rw := Data.story_special_reward(no)
	if rw.is_empty() or reward_claimed(no):
		return {}
	var dno := int(rw.get("dragon_no", 0))
	if dno <= 0:
		return {}
	var inst := UserDB.add_dragon(dno, int(rw.get("level", 1)))
	var uid := int(inst.get("uid", 0))
	# 젬 칸 타입 = 원작 색 3개. 실제로 박혀 있던 젬 번호(112/131/150 …)는 우리 gems.json 이
	# 이름 키라 매핑 근거가 없다 → **칸 타입만** 옮기고 슬롯은 비워 둔다(지어내지 않는다).
	var types: Array = []
	for c in (rw.get("gem_colors", []) as Array):
		types.append(String(REWARD_GEM_COLOR.get(String(c), "ATT")))
	if types.size() == Gem.SLOTS:
		var d := UserDB.get_dragon(uid)
		if not d.is_empty():
			d["gems"] = Gem.set_types(d.get("gems", {}), types)
	# 스킬 = 원작 {no, lv}. 우리 skills.json 에 없는 번호(후기 추가분)는 건너뛰고 보고한다.
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
