class_name BattleMission
## 전투 미션(원작 AdventureScene::initJsonBattleMission + QuestAndBattleLabel) 판정 — **순수 로직**.
##
## 계층(CLAUDE.md §8): logic. 노드·씬·에셋을 모르고, 이벤트 배열만 보고 진행도를 센다.
## 정의는 data/battle_missions.json(유실 서버데이터 복원, `_re_basis` 참조).
##
## 입력 이벤트는 scripts/systems/battle.gd 가 만든 것 그대로:
##   {type: normal|double|skill|awaken|dot|timed, attacker, defender, miss, block, crit, damage, dead}
## "우리 편"은 party_names(표시 이름 집합)로 구분한다.

## data/battle_missions.json 에서 pick_count 개를 뽑는다.
## # ASSUMPTION: 원작의 선택 규칙(스테이지별 고정? 가중치?)은 유실 → 균등 랜덤.
static func pick(defs: Dictionary, rng: RandomNumberGenerator) -> Array:
	var all: Array = (defs.get("missions", []) as Array).duplicate()
	var n := mini(int(defs.get("pick_count", 2)), all.size())
	var out: Array = []
	for i in n:
		if all.is_empty():
			break
		out.append(all.pop_at(rng.randi() % all.size()))
	return out

## 이벤트 배열 전체에 대한 미션별 진행도. 반환 = [{mission, count, done}] (mission=정의 Dictionary).
static func evaluate(missions: Array, events: Array, party_names: Array) -> Array:
	var out: Array = []
	for m in missions:
		var c := _count(String(m.get("rule", "")), int(m.get("rule_arg", 0)), events, party_names)
		out.append({"mission": m, "count": mini(c, int(m.get("goal", 1))),
			"done": c >= int(m.get("goal", 1))})
	return out

## 달성한 미션의 exp_bonus 합(0.0~). 원작 EXP 패널의 "+40%/+20%" 가산.
static func exp_bonus(progress: Array) -> float:
	var b := 0.0
	for p in progress:
		if bool(p.get("done", false)):
			b += float((p["mission"] as Dictionary).get("exp_bonus", 0.0))
	return b

static func _is_ours(name: Variant, party_names: Array) -> bool:
	# 이벤트 종류에 따라 attacker/defender 키가 없을 수 있다(status_skip 등).
	# Godot 4에서 String(null)은 런타임 에러 → 문자열일 때만 비교한다.
	if typeof(name) != TYPE_STRING:
		return false
	return party_names.has(name)

static func _count(rule: String, arg: int, events: Array, party: Array) -> int:
	match rule:
		"hits_taken":      # 우리 편이 실제로 피격당한 횟수(빗나감·방어 제외)
			var n := 0
			for e in events:
				if _is_ours(e.get("defender"), party) and not bool(e.get("miss", false)) \
						and not bool(e.get("block", false)) and int(e.get("damage", 0)) > 0:
					n += 1
			return n
		"blocks":          # 우리 편이 방어에 성공한 횟수
			var n2 := 0
			for e in events:
				if _is_ours(e.get("defender"), party) and bool(e.get("block", false)):
					n2 += 1
			return n2
		"dodges":          # 우리 편이 회피한 횟수
			var n3 := 0
			for e in events:
				if _is_ours(e.get("defender"), party) and bool(e.get("miss", false)):
					n3 += 1
			return n3
		"combo_hits":      # 우리 편이 한 턴에 arg타 이상 연속 명중시킨 횟수
			var best := 0
			var run := 0
			var last := ""
			for e in events:
				var atk := String(e.get("attacker", ""))
				if not _is_ours(atk, party) or bool(e.get("miss", false)) or bool(e.get("block", false)):
					run = 0; last = ""
					continue
				if atk == last:
					run += 1
				else:
					run = 1; last = atk
				if run >= arg:
					best += 1
					run = 0; last = ""
			return best
	return 0
