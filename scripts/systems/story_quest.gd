class_name StoryQuest
extends RefCounted

## 스토리 서브퀘스트 규칙 — 원작 `ScenarioSubQuestData` + `QuestData` 의 판정만 담은 logic 층
## (CLAUDE.md §8.1). 화면·에셋·노드를 일절 모른다.
##
## ## 원작이 클라에서 했다 (2026-07-30 확인)
##
## "스토리 아이템을 탐험으로 찾기 / 탐험 n회 / 스토리 몬스터 퇴치"는 **전부 클라 로직**이었다.
##
## 1. 조건 종류 = `QuestData` 의 `type` 문자열과 `stringsData_KR.xml` 포맷:
##      `QuestTitle_ADVENTURE` = `-%1$s(%2$s)  %3$d회 탐험-`
##      `QuestTitle_GATHER`    = `-%1$s(%2$s)  %3$s %4$d개 획득-`
##      `QuestTitle_KILL`      = `-%1$s(%2$s)  %3$s %4$d마리 퇴치-`
##      (+ `TALK` `RAID` `PVP1~3`. PVP 는 §2-1 컷)
##    대상 분류 = `QuestSubTitle_Item1~5`(음식/젬/장착 아이템/정기/알) · `Monster1~2`(몬스터/보스)
##    난이도 = `Adventure_Mode_N`(일반) / `_H`(영웅)
##
## 2. 카운트를 클라가 직접 올렸다 — `QuestData::setCount(getCount() + 1)` 호출부 3곳:
##      `AdventureScene.c:45749` 탐험 1회 (같은 함수가 `memcmp "KILL"/"ADVENTURE"/"GATHER"` 분기)
##      `FightManager.c:20654`   전투 종료(퇴치)
##      `MakeInterface.c:13667`  채집 성공(획득)
##    화면의 `n/m` 라벨 = `QuestAndBattleLabel::setCountNumberIncrease`
##
## 3. 회차별 조건 수치는 `ScenarioSubQuestData` 에 **하드코딩**돼 있다 →
##    `data/story_subquest.json`(scripts/tools/extract_story_subquest.py 추출).
##
## 4. 서버가 가진 것은 **보상 지급과 진행도 영속화뿐**이다
##    (`QuestManager::RequestQuestReward`, `game_data/set_scenario_quest.hb`,
##     로그인 시 `AccountManager.c:10886` 이 저장값을 `setCount` 로 복원).
##    ⇒ 오프라인에서는 카운터를 로컬 세이브에 두면 그대로 재현된다.
##
## ## 유실분과 우리 처리
##
## | 원작 소유 | 상태 |
## |---|---|
## | 회차 던전 · 탐험 클릭 수 · 배틀 후 클릭 수 · 월드맵 마크 필드 · 이벤트 전투 3종 | ✅ 추출 완료(회차 79~146) |
## | 회차 79 미만의 서브퀘스트 정의(`info_quest_v2` 로컬 SQLite) | ⚪ .db 부재 → 위키 **이름만**(story.json `submission` 16건) |
## | GATHER 대상 아이템 · KILL 대상 몬스터(회차별) | ⚪ 같은 .db 소유 → 미복원 |
## | `isSubQuestExtant` 등 6개 판정의 회차 목록(.bss `std::vector<int>`) | ⚪ 정적 초기화자 미특정 |
##
## ⇒ **탐험 n회(ADVENTURE)만 원작 수치로 완전 재현**하고, GATHER/KILL 은 엔진만 갖춘 뒤
##    표가 비어 있다(`data/story_subquest.json` 에 회차별 항목이 생기면 즉시 동작한다).
##    없는 수치를 지어내지 않는다(CLAUDE.md §2-6).

## 진행 카운터 세이브 키.
const PROGRESS_KEY := "story_sq_%d"

## 원작 `Adventure_Mode_N` / `_H`.
const MODE_NAME := {"N": "일반", "H": "영웅"}


# ══════════════════════════════════════════════════════════ 순수 규칙 (테이블을 받는다)
## 회차의 서브퀘스트 정의. 없으면 {}.
## `sq` = `data/story_subquest.json` 전체.
##
## 반환 {type, field, need, night, requires, battle_need}
##   type        "ADVENTURE" — 원작 `scenairoClickCountCheck` 가 주는 것은 탐험 클릭 수다.
##   field       원작 `getScenarioSubQuestFiled` 가 주는 던전 번호.
##   need        클릭 수(=탐험 횟수).
##   night       밤에만 유효(원작이 `getDBYutakanNight()` 를 넘겨 판정했다).
##   requires    {"kades": 1} / {"selectmap": 1|2} — 유타칸 변형 조건.
##   battle_need 원작 `isBattleCountClick` — 배틀 완료 후 추가로 필요한 클릭 수(0이면 없음).
static func spec_of(sq: Dictionary, no: int) -> Dictionary:
	var need := int((sq.get("click_count", {}) as Dictionary).get(str(no), 0))
	var fld: Dictionary = (sq.get("subquest_field", {}) as Dictionary).get(str(no), {})
	if need <= 0 or fld.is_empty():
		return {}
	var out := {
		"type": "ADVENTURE",
		"field": int(fld.get("field", 0)),
		"need": need,
		"night": bool(fld.get("night", false)),
		"requires": fld.get("requires", {}),
		"battle_need": int((sq.get("battle_click_count", {}) as Dictionary).get(str(no), 0)),
	}
	return out


## 서브퀘스트 조건 충족? 정의가 없으면 **통과**(그 회차엔 서브퀘스트가 없다).
static func cleared_with(sq: Dictionary, no: int, count: int) -> bool:
	var sp := spec_of(sq, no)
	if sp.is_empty():
		return true
	return count >= int(sp["need"])


## 이번 탐험 1회를 이 회차의 서브퀘스트로 셀 수 있는가.
## 원작 `WorldMapLayer::setScenarioNotification` 이 마크를 찍는 조건과 같은 판정 —
## 필드가 맞고, 밤 조건이 맞고, 카데스 조건이 맞아야 한다.
##
## `requires.selectmap` 은 **일부러 보지 않는다**: 원작 `getDBSelectmap()` 은
## `select param_int from user_setting where value_name='worldmap'` = 지금 보고 있는 **지역 맵**이고,
## 그 조건이 걸린 회차 96·97 의 필드(22·17)는 애초에 그 지역에만 있다 ⇒ 필드 일치가
## 같은 조건을 더 강하게 검사한다. 값 1·2 가 어느 지역인지는 근거가 없어 매핑하지 않는다.
## (카데스는 다르다 — 같은 기본 필드가 일반/카데스 두 모드로 존재하므로 반드시 본다.)
static func counts_for(sp: Dictionary, field_no: int, is_night: bool, variant: Dictionary) -> bool:
	if sp.is_empty():
		return false
	if int(sp.get("field", 0)) != field_no:
		return false
	if bool(sp.get("night", false)) and not is_night:
		return false
	var req: Dictionary = sp.get("requires", {})
	if req.has("kades") and int(variant.get("kades", 0)) != int(req["kades"]):
		return false
	return true


## 배너 한 줄 — 원작 `QuestTitleSub`("서브미션 : %s") + `QuestTitle_ADVENTURE`.
## 🟡 원작 포맷의 `(%2$s)`(난이도)는 `info_quest_v2` 유실로 알 수 없어 **뺐다**.
##    지어내지 않는다(CLAUDE.md §2-6).
static func line_with(sq: Dictionary, ep: Dictionary, no: int, count: int, field_name: String) -> String:
	var parts: Array[String] = []
	if ep.has("submission"):
		parts.append("서브미션 : %s" % String(ep["submission"]))
	var sp := spec_of(sq, no)
	if not sp.is_empty():
		var fname := field_name if field_name != "" else "필드 %d" % int(sp["field"])
		var tail := ""
		if bool(sp["night"]):
			tail = " (밤)"
		var req: Dictionary = sp.get("requires", {})
		if req.has("kades"):
			tail += " (카데스)"
		parts.append("-%s  %d회 탐험-  %d/%d%s" % [fname, int(sp["need"]), count, int(sp["need"]), tail])
	return "    ".join(parts)
