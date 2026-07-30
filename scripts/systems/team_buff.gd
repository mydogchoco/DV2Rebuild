# TeamBuff(종족 조합 버프) — 순수 로직 계층 (§10: render/data 의존 없음, 헤드리스 검증 가능)
#
# 원작 근거: docs/ref/design/team_buff_analysis.md, docs/ref/orig_code/decomp/TeamBuff.c.
# 활성화 의미(TeamBuff::isActivate, TeamBuff.c:2106-2197):
#   파티가 버프의 combine(필요 종족×개수)을 전부 충족하면 발동. 초과 무방, 부족 시 미발동.
# 데이터: data/team_buffs.json (유실 테이블 외부화, 빈 시작). 비면 no-op.
#
# ⚠️ 이 파일은 로직만 담당: 노드/씬/스프라이트/사운드 참조 금지(§10.2 단방향 의존).
class_name TeamBuff
extends RefCounted

# combine 멀티셋 충족 검사 — 원작 isActivate 의미의 순수 재현.
# required: {race_key: count}, party_races: [race_key,...] (드래곤별 종족, 중복 허용)
static func _is_activated(required: Dictionary, party_races: Array) -> bool:
	if required.is_empty():
		return false  # 조합 없는 버프는 발동 안 함(원작: required 초기부터 비면 partyRaces 소거 무의미 → 방어적으로 미발동)
	# 필요 멀티셋을 파티 종족으로 하나씩 소거(원작 :2177-2194 erase-one)
	var need: Dictionary = required.duplicate(true)
	for race in party_races:
		if need.has(race) and int(need[race]) > 0:
			need[race] = int(need[race]) - 1
	# 남은 필요 수가 모두 0 이하면 발동(원작 :2160 required 빔 → active)
	for race in need:
		if int(need[race]) > 0:
			return false
	return true

# 파티 종족 목록으로 활성 버프 반환. table = team_buffs.json 파싱 dict.
static func active_buffs(party_races: Array, table: Dictionary) -> Array:
	var out: Array = []
	var buffs: Array = table.get("buffs", [])
	for b in buffs:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var combine: Dictionary = _as_int_dict(b.get("combine", {}))
		if _is_activated(combine, party_races):
			out.append(b)
	return out

# 활성 버프들의 스탯 델타 집계 → {stat: total}. 구형(숫자) effect 전용 — 하위호환.
static func aggregate_stats(active: Array) -> Dictionary:
	var total: Dictionary = {}
	for b in active:
		var eff: Dictionary = b.get("effect", {})
		for stat in eff:
			if typeof(eff[stat]) == TYPE_DICTIONARY:
				continue          # 신형(typed)은 aggregate_typed 로
			total[stat] = float(total.get(stat, 0.0)) + float(eff[stat])
	return total

# 신형 집계 → {stat: {"pct": x, "point": y, "flat": z}}.
# 위키 §2.3.3.1 의 효과는 스탯마다 의미가 다르다:
#   pct   = 배수(체력 30% 상승 → ×1.30)
#   point = 퍼센트 포인트(크리티컬 확률 10% 상승 → 크리 10 → 20)
#   flat  = 정수 가산(방어관통데미지 10 상승)
# 구형(숫자)은 flat 으로 취급한다.
static func aggregate_typed(active: Array) -> Dictionary:
	var total: Dictionary = {}
	for b in active:
		var eff: Dictionary = b.get("effect", {})
		for stat in eff:
			var mode := "flat"
			var value := 0.0
			if typeof(eff[stat]) == TYPE_DICTIONARY:
				mode = String((eff[stat] as Dictionary).get("mode", "flat"))
				value = float((eff[stat] as Dictionary).get("value", 0))
			else:
				value = float(eff[stat])
			var slot: Dictionary = total.get(str(stat), {"pct": 0.0, "point": 0.0, "flat": 0.0})
			slot[mode] = float(slot.get(mode, 0.0)) + value
			total[str(stat)] = slot
	return total

# 편의: 파티 종족으로 곧장 스탯 델타 집계(테이블 비면 {}).
static func stats_for_party(party_races: Array, table: Dictionary) -> Dictionary:
	return aggregate_stats(active_buffs(party_races, table))

static func typed_for_party(party_races: Array, table: Dictionary) -> Dictionary:
	return aggregate_typed(active_buffs(party_races, table))

# 집계 결과를 실스탯에 적용한 새 dict. flat/point 가산 후 pct 배수.
# stat 별칭: atk → att (원작 표기 흡수).
static func apply(stats: Dictionary, typed: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate()
	for raw in typed:
		var stat := "att" if String(raw) == "atk" else String(raw)
		var t: Dictionary = typed[raw]
		var v := float(int(out.get(stat, 0)))
		v += float(t.get("flat", 0.0)) + float(t.get("point", 0.0))
		v *= 1.0 + float(t.get("pct", 0.0)) / 100.0
		out[stat] = int(round(v))
	return out

# JSON 경유로 count가 float("2":2.0)일 수 있어 int 정규화(전투 스킬 id 버그 교훈).
static func _as_int_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[str(k)] = int(d[k])
	return out
