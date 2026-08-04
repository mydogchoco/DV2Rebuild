# Equipment(장비) — 순수 로직 계층 (§8: render/에셋 의존 없음, 헤드리스 검증 가능)
#
# 원작 근거(구조):
#   - 장비 슬롯 = `Dragon::getDragonEquipSlot(int)`, 편린 슬롯 = `Dragon::getDragonPieceSlot(int)`
#     (docs/ref/orig_code/decomp/Dragon.c). 슬롯 종류는 위키 §2 표: 전체 / 전투형 / 보조형 / 아티팩트 4칸.
#   - 장비 옵션 테이블 = `info_item_acc`, 컬럼 9개:
#       select hp, atk, def, blk, gold, exp, pure, depure, accuracy from info_item_acc where no=%d
#       (docs/ref/orig_code/decomp/OptionSelectLayer.c:2343)
#   - 편린 세트 옵션 = `info_item_setacc`, 컬럼 13개 (docs/ref/orig_code/decomp/RaidpieceItem.c:2128)
#   - 장비 부가 버프 = `info_item_buf` (select hp,att,def,cri,evd,blk).
#
# 데이터: data/equipment.json (scripts/tools/build_equipment.py 가 docs/ref/wiki/equipment_*.pdf 에서 생성).
#
# 저장 형식(UserDB dragon["equip"]):
#   {"slots": [{"key": "<카탈로그 키>", "options": [{"stat": "att", "value": 30}, …],
#               "grade": <희귀도 인덱스 0=일반…5=초월>, "enhance": <강화 횟수>,
#               "belong": <귀속된 드래곤 uid, 0=미귀속>}, …],
#    "pieces": ["<편린 이름>", …]}
#   카탈로그 키 = catalog() 가 만드는 문자열. 예)
#     "basic:깃털:6"          일반 장비(종류:등급인덱스)
#     "event:눈사람 인형"     이벤트 장비
#     "special:balrog:카이저 발록의 팔찌"
#     "artifact:루멘:5"       아티팩트(종류:등급인덱스)
#
# ⚠️ 미구현(데이터만 보유):
#   - 전용 장비(exclusive) — 드래곤별 고유 효과라 개별 로직 필요. equipment.json 에 implemented=false.
#   - 레이드 편린(pieces) — 🟢 2026-07-31 **아이콘 복원 완료**로 다시 켰다(위키 PDF 표에서 6장).
#     남은 것은 획득·장착 경로(원작 4세대 레이드 산출물 → 솔로 재설계 대상)로, 에셋 문제가 아니다.
#   - 특수 장비의 **부가 효과**(bonus 텍스트) — "체방형 공격 시 25% 추가 대미지" 등 조건부.
#     주 능력(main)만 전투에 반영한다. 2026-07-29 조사: 원작 클라에도 이 효과를 계산하는
#     훅이 없다(서버가 보내는 장비 레코드는 index/belong/option/rarity/grade/cnt 6개뿐).
#   - 옵션 롤 수치 범위 — 서버 유실. options 는 저장된 값을 그대로 합산만 한다.
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드 참조 금지(§8.2 단방향 의존).
class_name Equipment
extends RefCounted

const PIECE_SLOTS := 3

## 전투에 반영되는 스탯 키(원작 info_item_acc + info_item_buf 합집합).
const STATS := ["hp", "att", "def", "blk", "evd", "cri", "cri_pow",
				"pure", "depure", "accuracy", "cure", "awaken_rate", "gold", "exp"]

# --- 카탈로그 ---------------------------------------------------------------

## 구현 대상 이벤트 장비만 — `implemented: false` 는 뺀다.
##
## 사용자 확정(2026-07-30): **아이콘 프레임이 없는 장비는 구현하지 않는다.** 이벤트 25종 중
## 6종만 아이콘이 추출 에셋에 있고(나머지 19종 + 특수 12종은 원작 후기 업데이트분 —
## CLAUDE.md §10 '이벤트 장비 아이콘 19종' 행), 그동안은 목록에 텍스트만 뜨는 유령 장비였다.
##
## 플래그는 `build_equipment.py` 가 `data/icon_map.json` 을 조회해 자동으로 박는다 —
## 여기(logic)는 **데이터 플래그만** 보고 아이콘/파일 경로는 모른다(§8.2 단방향 의존).
static func event_pool(table: Dictionary) -> Array:
	var out: Array = []
	for e in (table.get("event", []) as Array):
		if bool((e as Dictionary).get("implemented", true)):
			out.append(e)
	return out

## data/equipment.json 을 "키 → 장비" 평면 카탈로그로 펼친다.
## 각 항목: {key, name, group, stat_main:{…}, slot_class, bonus(선택), grade(선택)}
## ⚠️ `implemented: false`(아이콘 미보유) 항목은 여기 들어오지 않는다 — event_pool 주석 참조.
static func catalog(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for kind in (table.get("basic", {}) as Dictionary):
		var spec: Dictionary = table["basic"][kind]
		for g in (spec.get("grades", []) as Array):
			var key := "basic:%s:%d" % [kind, int(g["grade"])]
			out[key] = {
				"key": key, "name": String(g["name"]), "group": "basic",
				"slot_class": String(spec.get("slot", "all")),
				"grade": int(g["grade"]),
				"stat_main": {String(spec["stat"]): int(g["value"])},
			}
	for e in event_pool(table):
		var key2 := "event:%s" % String(e["name"])
		out[key2] = {
			"key": key2, "name": String(e["name"]), "group": "event",
			"slot_class": _slot_of(e.get("main", {}), table),
			"stat_main": _int_dict(e.get("main", {})),
		}
	for fam in (table.get("special", {}) as Dictionary):
		var famd: Dictionary = table["special"][fam]
		if not bool(famd.get("implemented", true)):
			continue                                   # 아이콘 미보유 계열 — 아래 주석 참조
		for it in (famd.get("items", []) as Array):
			var key3 := "special:%s:%s" % [fam, String(it["name"])]
			out[key3] = {
				"key": key3, "name": String(it["name"]), "group": "special:" + String(fam),
				"slot_class": _slot_of(it.get("main", {}), table),
				"stat_main": _int_dict(it.get("main", {})),
				"bonus": String(it.get("bonus", "")),
				"acquire": String(famd.get("acquire", "")),
			}
	# 전용 장비 — 🟦 사용자 확정 2026-07-31: **주 능력치가 없는 것이 원작 사양**이다.
	# 대응하는 드래곤에게만 장착되고 조건부 효과(effect)만 갖는다.
	#   · `stat_main` 은 빈 dict → aggregate 가 더할 것이 없다(스탯 0 기여)
	#   · `dragon_id` = 그 장비를 낄 수 있는 유일한 종. can_equip 이 아니라 **belong_species_ok**
	#     로 따로 판정한다(슬롯 규칙과 종족 규칙은 다른 축이다)
	#   · 슬롯은 위키 §2 "전용장비를 포함한 말 그대로 모든 장비" → `all` 칸
	for x in (table.get("exclusive", {}).get("list", []) as Array):
		var xd := x as Dictionary
		if not bool(xd.get("implemented", false)):
			continue
		var key5 := "exclusive:%s" % String(xd.get("name", ""))
		out[key5] = {
			"key": key5, "name": String(xd.get("name", "")), "group": "exclusive",
			"slot_class": "all", "stat_main": {},
			"dragon_id": int(xd.get("dragon_id", 0)),
			"dragon": String(xd.get("dragon", "")),
			"bonus": String(xd.get("effect", "")),
			"acquire": String(xd.get("acquire", "")),
		}
	var art: Dictionary = table.get("artifacts", {})
	for a in (art.get("types", []) as Array):
		for gi in (art.get("grades", []) as Array).size():
			var key4 := "artifact:%s:%d" % [String(a["name"]), gi]
			out[key4] = {
				"key": key4, "group": "artifact", "slot_class": "artifact", "grade": gi,
				"name": "%s %s" % [String((art["grades"] as Array)[gi]), String(a["name"])],
				"stat_main": {},                       # 아티팩트는 스탯이 아니라 스킬을 건드린다
				"artifact_effect": String(a.get("effect", "")),
				"artifact_skills": a.get("skills", []),
			}
	return out


## 장비 목록 공통 정렬 규칙(가방/칸별 장비 선택창).
##   1) 장착 중인 개체
##   2) 희귀도 내림차순(에픽→유니크→레어→일반; 초월이 있으면 에픽보다 앞)
##   3) 같은 희귀도 안에서 전용→특수→일반→아티팩트
##   4) 이름/키(결정적 순서)
## row = {it: 카탈로그 항목, meta: {rarity}, worn: bool, inv/cat: String}.
static func display_sort_less(a: Dictionary, b: Dictionary) -> bool:
	var aw := bool(a.get("worn", false))
	var bw := bool(b.get("worn", false))
	if aw != bw:
		return aw
	var ar := int((a.get("meta", {}) as Dictionary).get("rarity", 0))
	var br := int((b.get("meta", {}) as Dictionary).get("rarity", 0))
	if ar != br:
		return ar > br
	var ai: Dictionary = a.get("it", {})
	var bi: Dictionary = b.get("it", {})
	var ag := display_group_rank(ai)
	var bg := display_group_rank(bi)
	if ag != bg:
		return ag < bg
	var an := String(ai.get("name", ""))
	var bn := String(bi.get("name", ""))
	if an != bn:
		return an < bn
	return String(a.get("inv", a.get("cat", ""))) < String(b.get("inv", b.get("cat", "")))


## 사용자가 보는 장비 분류 순서. event/basic 및 그 밖의 장비는 모두 "일반장비"다.
static func display_group_rank(item: Dictionary) -> int:
	var group := String(item.get("group", ""))
	if group == "exclusive":
		return 0
	if group.begins_with("special:"):
		return 1
	if group == "artifact":
		return 3
	return 2

## 주 능력 스탯으로 어느 슬롯 칸에 붙는지 판정(위키 §2 슬롯 표).
static func _slot_of(main: Dictionary, table: Dictionary) -> String:
	for s in (table.get("slots", []) as Array):
		var acc = (s as Dictionary).get("accepts", "*")
		if typeof(acc) != TYPE_ARRAY:
			continue
		for stat in main:
			if String(stat) in acc:
				return String((s as Dictionary)["id"])
	return "all"

static func _int_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[String(k)] = int(d[k])
	return out

# --- 슬롯 규칙 --------------------------------------------------------------

## 그 장비를 그 칸에 낄 수 있는가. slot_id = "all"|"battle"|"support"|"artifact".
## 위키 §2: "모든 장비"칸에는 전부, 전투형/보조형 칸에는 해당 주 능력만, 아티팩트 칸엔 아티팩트만.
static func can_equip(item: Dictionary, slot_id: String) -> bool:
	var cls := String(item.get("slot_class", "all"))
	if slot_id == "all":
		return cls != "artifact"      # 아티팩트는 전용 칸에만(위키 §2 '아티팩트 장비=모든 아티팩트')
	return cls == slot_id

## 그 **종**이 이 장비를 낄 수 있는가. 전용 장비만 제한이 있고 나머지는 전부 통과한다.
## 🟦 사용자 확정 2026-07-31: 전용 장비는 대응하는 드래곤에게만 장착된다.
## 근거는 위키 전용 장비 표의 **드래곤 열**이다 — 원작 클라에는 종족 제한 훅이 없다
## (`Equip` 메서드 전수에서 `getDragonTag` 는 개체 귀속 uid 이고 종족이 아니다). 서버 소유였다.
## ⚠️ 개체 귀속(belong, uid)과는 **다른 축**이다 — 그쪽은 belong_allows 가 본다.
static func species_allows(item: Dictionary, dragon_id: int) -> bool:
	var need := int(item.get("dragon_id", 0))
	return need <= 0 or need == dragon_id

## 칸 순서(표시·저장 공통). `all` 은 처음부터 열려 있다.
const SLOT_ORDER := ["all", "battle", "support", "artifact"]

## 드래곤이 해금한 칸 목록. 원작 '드래곤 강화'로 최대 4칸.
##
## 🔴 정정(2026-07-29, `docs/ref/Lab/드래곤강화4.png` 실측): 원작은 **순차 해금이 아니다** —
##    "어떤 슬롯을 여는지 상관없이 …"(주의문) 대로 전투형/보조형/아티팩트를 **임의 순서**로 연다.
##    그래서 저장값이 개수(int)가 아니라 **해금한 칸 id 배열**이다. 구세이브(int)도 받는다.
static func slot_ids(unlocked) -> Array:
	if unlocked is Array:
		var out: Array = []
		for s in SLOT_ORDER:                      # 표시 순서는 항상 SLOT_ORDER
			if s == "all" or (unlocked as Array).has(s):
				out.append(s)
		return out
	return SLOT_ORDER.slice(0, clampi(int(unlocked), 1, SLOT_ORDER.size()))

# --- 집계 -------------------------------------------------------------------

## 장착 장비 + 옵션 + 편린 세트효과 → {stat: value}.
##
## ## 🔴 주 능력은 합산이 아니라 **최고값 하나만** 먹는다 (2026-08-01 정정)
##
## 원작 문자열 `<MultyEquip_Slot_Warring_2>`:
##   "같은 메인 옵션의 아이템을 장착하시면 **최상위 메인 옵션이 적용**됩니다."
## 클라 코드로도 확인했다 — `Dragon::getAvoidRateAdd`(Dragon.c:2054) 가 4칸을 도는 루프에서
##
##     iVar9 = Item::getTypeParam(item);            // 그 장비의 주 능력 수치
##     if (iVar9 <= iVar16) { iVar9 = iVar16; }     // ← 누적 최댓값. 덧셈이 아니다
##     ... } while (iVar8 != 4);
##
## `getCriticalRateAdd`·`getStunRateAdd` 도 같은 관용구다. 반면 **부가 옵션**은
## `Equip::getAtk/getBlk/...` 를 칸마다 `fVar = fVar + …` 로 **더한다**(getBlkRateAdd:2372 등).
## 젬 3칸(`this+0x158/0x160/0x168`)과 편린 세트도 덧셈이다.
##
## ⇒ 최종식 = **max(주 능력) + Σ(부가 옵션) + Σ(젬) + Σ(편린 세트)**
##   (주 능력과 부가 옵션은 원작에서도 **다른 항**이라 같은 스탯이어도 서로 더해진다 —
##    해골요새 관통 40 + 옵션 관통 +5 = 45.)
##
## hp_pct/att_pct/def_pct 는 **배수** 항이다 — 편린 세트효과(체력 10% 등)와
## 부가옵션의 hp/att/def(원작에서 %)가 여기로 모인다.
static func aggregate(equip_field: Dictionary, table: Dictionary) -> Dictionary:
	var cat := catalog(table)
	var pct: Array = table.get("option", {}).get("pct_stats", [])
	var out: Dictionary = {}
	var main_max: Dictionary = {}          # 주 능력은 칸별 최댓값(위 주석)
	for s in (equip_field.get("slots", []) as Array):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = cat.get(String(s.get("key", "")), {})
		# 주 능력(stat_main)은 원작에서도 그 스탯의 고유 단위 그대로다(회피율 %, 관통 flat …).
		# 배수 전환은 **부가옵션에만** 적용한다.
		for stat in (item.get("stat_main", {}) as Dictionary):
			var v := float(item["stat_main"][stat])
			main_max[stat] = maxf(float(main_max.get(stat, 0.0)), v)
		for o in (s.get("options", []) as Array):
			var st := String((o as Dictionary).get("stat", ""))
			if st == "":
				continue
			# 원작 Dragon.c: hp/att/def 옵션만 기본값에 곱한다(§EquipBelongOption.md §2-2).
			var key := (st + "_pct") if st in pct else st
			out[key] = float(out.get(key, 0.0)) + float((o as Dictionary).get("value", 0))
	for stat in main_max:
		out[stat] = float(out.get(stat, 0.0)) + float(main_max[stat])
	_add_piece_sets(equip_field, table, out)
	# 아티팩트 히든 옵션 중 **스탯**인 것(벤투스 회피율 +5%)은 여기서 합류한다.
	# 나머지(발동확률·발동횟수)는 스탯이 아니라 전투 규칙이라 artifact_mods 로 간다.
	var hid := artifact_hidden(equip_field, table)
	if int(hid.get("evd", 0)) != 0:
		out["evd"] = float(out.get("evd", 0.0)) + float(hid["evd"])
	return out

## 편린 세트 효과(위키 §3): 같은 편린 2개/3개를 맞추면 각각 set2/set3 효과.
## set2 는 수치가 명확해 반영하고, set3 는 조건부 메커닉(회피 2회마다 …)이라 데이터로만 둔다.
##
## 편린 계열은 `pieces.implemented` 가 꺼져 있으면 통째로 무시한다 — 아이콘 미보유로 구현에서
## 뺀 계열의 세트효과가 스탯에 남는 것을 막는다(구세이브에 `pieces` 가 있어도 마찬가지).
## 2026-07-31 현재는 위키에서 아이콘을 복원해 **켜져 있다**.
## (여기는 logic 이라 아이콘을 모른다 — **데이터 플래그만** 본다, §8.2 단방향 의존)
static func _add_piece_sets(equip_field: Dictionary, table: Dictionary, out: Dictionary) -> void:
	if not bool((table.get("pieces", {}) as Dictionary).get("implemented", true)):
		return
	var worn: Array = equip_field.get("pieces", [])
	if worn.is_empty():
		return
	var count: Dictionary = {}
	for p in worn:
		count[String(p)] = int(count.get(String(p), 0)) + 1
	for pd in (table.get("pieces", {}).get("list", []) as Array):
		var nm := String((pd as Dictionary)["name"])
		var n := int(count.get(nm, 0))
		if n < 2:
			continue
		var eff := _parse_set_effect(String((pd as Dictionary).get("set2", "")))
		for stat in eff:
			out[stat] = float(out.get(stat, 0.0)) + float(eff[stat])

## "체력 10% 증가" / "공격력 20 증가" 같은 세트2 문구를 {stat: value} 로.
## % 가 붙으면 <stat>_pct, 아니면 flat.
static func _parse_set_effect(text: String) -> Dictionary:
	var map := {"체력": "hp", "공격력": "att", "방어력": "def"}
	for kr in map:
		if not text.begins_with(kr):
			continue
		var rest := text.substr(kr.length()).strip_edges()
		var num := ""
		for ch in rest:
			if ch.is_valid_int():
				num += ch
			elif num != "":
				break
		if num == "":
			return {}
		var key := String(map[kr])
		return {(key + "_pct" if rest.contains("%") else key): int(num)}
	return {}

## 실스탯에 장비 보너스를 적용한 새 dict.
## flat 은 가산, *_pct(편린 세트)는 배수로 마지막에 적용.
static func apply(stats: Dictionary, equip_field: Dictionary, table: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate()
	var agg := aggregate(equip_field, table)
	for stat: String in STATS:
		if agg.has(stat):
			out[stat] = int(out.get(stat, 0)) + int(round(float(agg[stat])))
	for base: String in ["hp", "att", "def"]:
		var pk := base + "_pct"
		if agg.has(pk):
			out[base] = int(round(float(int(out.get(base, 0))) * (1.0 + float(agg[pk]) / 100.0)))
	return out


# --- 아티팩트(원작 typeDetail BOOST/REQHP/BNR/DEDMG/INRATE/DERATE) -----------
#
# 아티팩트는 **스탯이 아니라 스킬**을 건드린다(위키 §2.4). 종류↔축 짝은 원작 문자열 테이블에서
# 확정됐다(§docs/ref/porting/EquipBelongOption.md §3):
#   이그니스 BOOST 스킬효과+ / 마리스 REQHP 발동 요구체력 완화 / 테라 BNR 효과+확률 /
#   벤투스 DEDMG 받는 스킬피해− / 루멘 INRATE 발동확률+ / 옵스큐럼 DERATE 상대 발동확률−
# 세기(등급 6단)는 서버 유실 → equipment.json artifacts.power 자작값.
#
# 각 아티팩트는 **지정된 스킬 목록에만** 걸린다(types[].skills, 위키 표 그대로).

## 장착한 아티팩트의 **히든 옵션** 합. 표에 안 적힌 상시 효과로, 등급과 무관한 고정값이고
## 대상 스킬 제한도 없다(사용자 확정 2026-07-29 — 위키 §2.4 각주).
##   마리스 = 스킬 발동 확률 +5% · 벤투스 = 회피율 +5% · 테라 = 스킬 발동 횟수 +1
## 반환 {proc_add_all, evd, skill_uses}
static func artifact_hidden(equip_field: Dictionary, table: Dictionary) -> Dictionary:
	var out := {"proc_add_all": 0, "evd": 0, "skill_uses": 0}
	var arts: Dictionary = table.get("artifacts", {})
	var axes: Dictionary = arts.get("axes", {})
	var hid: Dictionary = arts.get("hidden", {})
	if axes.is_empty() or hid.is_empty():
		return out
	for sl in (equip_field.get("slots", []) as Array):
		var parts := String((sl as Dictionary).get("key", "")).split(":")
		if parts.size() < 3 or parts[0] != "artifact":
			continue
		var spec: Dictionary = hid.get(String(axes.get(String(parts[1]), "")), {})
		for f in spec:
			out[String(f)] = int(out.get(String(f), 0)) + int(spec[f])
	return out

## 장착한 아티팩트 → 전투가 쓸 수정치. 스킬 **id** 로 키를 잡는다(전투는 id로 돈다).
## 반환 {proc_add:{id:%}, power_lv:{id:레벨}, foe_proc_sub:{id:%}, skill_dmg_taken_pct:{id:%},
##       req_hp_relax_pct:{id:%}}
static func artifact_mods(equip_field: Dictionary, table: Dictionary,
		skills_db: Dictionary) -> Dictionary:
	var out := {"proc_add": {}, "power_lv": {}, "foe_proc_sub": {},
				"skill_dmg_taken_pct": {}, "req_hp_relax_pct": {},
				"hidden": artifact_hidden(equip_field, table)}
	var arts: Dictionary = table.get("artifacts", {})
	var axes: Dictionary = arts.get("axes", {})
	var power: Dictionary = arts.get("power", {})
	if axes.is_empty() or power.is_empty():
		return out
	var by_name := _skill_ids_by_name(skills_db)
	for s in (equip_field.get("slots", []) as Array):
		var parts := String((s as Dictionary).get("key", "")).split(":")
		if parts.size() < 3 or parts[0] != "artifact":
			continue
		var kind := String(parts[1])
		var gi := int(parts[2])
		var axis := String(axes.get(kind, ""))
		var spec: Dictionary = power.get(axis, {})
		if axis == "" or spec.is_empty():
			continue
		# 그 아티팩트가 강화하는 스킬 목록(위키 표).
		var names: Array = []
		for t in (arts.get("types", []) as Array):
			if String((t as Dictionary).get("name", "")) == kind:
				names = (t as Dictionary).get("skills", [])
		for field in spec:
			var arr: Array = spec[field]
			if gi < 0 or gi >= arr.size():
				continue
			var v := int(arr[gi])
			if v == 0:
				continue
			var bucket: Dictionary = out[String(field)]
			for nm in names:
				for sid in by_name.get(_norm_skill_name(String(nm)), []):
					bucket[int(sid)] = int(bucket.get(int(sid), 0)) + v
	return out

## 스킬 이름 → id 목록. 위키 표기는 `[카데스]철갑방패` 처럼 지역 접두어가 붙어 있어 정규화한다.
static func _skill_ids_by_name(skills_db: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in skills_db:
		var sd: Dictionary = skills_db[k]
		var nm := _norm_skill_name(String(sd.get("name", "")))
		if nm == "":
			continue
		if not out.has(nm):
			out[nm] = []
		(out[nm] as Array).append(int(sd.get("id", int(str(k)) if str(k).is_valid_int() else 0)))
	return out

## `[카데스]철갑방패` → `철갑방패`, 공백 제거. 위키 표기와 skills.json 표기를 맞춘다.
static func _norm_skill_name(nm: String) -> String:
	var s := nm.strip_edges()
	var rb := s.find("]")
	if s.begins_with("[") and rb > 0:
		s = s.substr(rb + 1)
	return s.replace(" ", "")

# --- 획득 시 희귀도 (원작 서버가 실어 보내던 rarity) -------------------------
#
# 원작은 장비를 받을 때 서버가 `rarity` 를 함께 줬다(AccountManager 파싱 키). 값은 유실 →
# equipment.json option.rarity_rolls(사용자 확정 2026-07-29)로 굴린다.
#   drop 70/20/8/2 · shop_gold 일반100 · shop_gacha 60/30/10

## source = "drop" | "shop_gold" | "shop_gacha". 표가 없으면 0(일반).
static func roll_rarity(source: String, rng: RandomNumberGenerator, table: Dictionary) -> int:
	var tbl: Dictionary = table.get("option", {}).get("rarity_rolls", {}).get(source, {})
	if tbl.is_empty():
		return 0
	var total := 0.0
	for g in tbl:
		total += float(tbl[g])
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	var acc := 0.0
	var last := 0
	for g in tbl:
		acc += float(tbl[g])
		last = int(str(g))
		if r < acc:
			return last
	return last

## 획득 1건의 개체 정보(희귀도 + 그 희귀도만큼의 옵션)를 굴린다 → item_key 용 meta.
static func roll_instance(source: String, rng: RandomNumberGenerator, table: Dictionary) -> Dictionary:
	var rar := roll_rarity(source, rng, table)
	return {"rarity": rar, "options": roll_options(rar, rng, table)}

# --- 옵션(원작 info_item_acc) -----------------------------------------------
# 원작: 장비 등급(일반/매직/레어/유니크/에픽/초월)에 따라 옵션이 0~5개 붙고,
#       강화 횟수 = 옵션 수 × 5 (위키 §2.6). 옵션 스탯 9종 = info_item_acc 컬럼.
# ⚠️ 1롤당 수치 범위와 강화 증가폭은 원작 유실 → data/equipment.json option.value_ranges /
#    option.enhance_step_pct 로 외부화한 **자작값**(사용자 승인 2026-07-27, HARD RULE 6 예외).

## 등급 인덱스(0=일반 … 5=초월)의 옵션 개수. 표는 equipment.json option.grades.
static func option_count(grade: int, table: Dictionary) -> int:
	var gs: Array = table.get("option", {}).get("grades", [])
	if grade < 0 or grade >= gs.size():
		return 0
	return int((gs[grade] as Dictionary).get("options", 0))

## 그 장비 등급에서 가능한 최대 강화 횟수 = 옵션 수 × enhance_per_option(원작 5).
static func enhance_limit(grade: int, table: Dictionary) -> int:
	var per := int(table.get("option", {}).get("enhance_per_option", 5))
	return option_count(grade, table) * per

## 옵션 1개 굴리기 → {stat, value}. rng 를 받아 재현 가능하게 한다(§8: logic은 순수).
## `weights` = {스탯: 가중치}. 비어 있으면 9종 균등(기본). 표에 없는 스탯은 가중치 1.
## 마모루딕 제련이 관통을 더 잘 띄우는 데 쓴다 — 위키 §2.4 "기누의 동전에 비해 관통 옵션이
## 나올 확률이 높다. 그래서 보통 아티팩트로 관통 100을 맞춘다".
static func roll_option(rng: RandomNumberGenerator, table: Dictionary,
		weights: Dictionary = {}) -> Dictionary:
	var opt: Dictionary = table.get("option", {})
	var stats: Array = opt.get("stats", [])
	var ranges: Dictionary = opt.get("value_ranges", {})
	if stats.is_empty():
		return {}
	var stat := ""
	if weights.is_empty():
		stat = String(stats[rng.randi() % stats.size()])
	else:
		var total := 0.0
		for s in stats:
			total += maxf(0.0, float(weights.get(String(s), 1.0)))
		if total <= 0.0:
			return {}
		var r0 := rng.randf() * total
		var acc := 0.0
		for s in stats:
			acc += maxf(0.0, float(weights.get(String(s), 1.0)))
			stat = String(s)
			if r0 < acc:
				break
	var r: Array = ranges.get(stat, [1, 1])
	var lo := int(r[0])
	var hi := int(r[1]) if r.size() > 1 else lo
	return {"stat": stat, "value": rng.randi_range(lo, maxi(lo, hi))}

## 등급에 맞는 옵션 세트를 통째로 굴린다(장비 획득/재설정 시).
static func roll_options(grade: int, rng: RandomNumberGenerator, table: Dictionary,
		weights: Dictionary = {}) -> Array:
	var out: Array = []
	for _i in option_count(grade, table):
		var o := roll_option(rng, table, weights)
		if not o.is_empty():
			out.append(o)
	return out


## 마모루딕 '아티펙트 제련' 설정(`option.artifact_smelt`). 없으면 {}.
static func artifact_smelt_cfg(table: Dictionary) -> Dictionary:
	return (table.get("option", {}) as Dictionary).get("artifact_smelt", {})


## 제련이 쓰는 옵션 가중치. 표가 없으면 균등({}).
static func artifact_smelt_weights(table: Dictionary) -> Dictionary:
	return artifact_smelt_cfg(table).get("option_weights", {})

## slot_id 칸 장비의 옵션을 새로 굴린 equip 필드(원작 '기누의 동전'류 옵션 재설정).
##
## 🔴 2026-08-01 정정 — **등급은 건드리지 않는다.**
##   원작 동전은 `getRarity(equip) == 동전이 요구하는 희귀도`인 장비에만 쓸 수 있고
##   (`ItemEquipSelectPopup::init` + `initData` @00ea7338), 바꾸는 것은 옵션뿐이다.
##   종전엔 인자 `grade` 를 슬롯에 박아 **등급 상승 경로**가 생겼다(원작에 없다).
##   이제 `grade` 는 "몇 개를 굴릴지"만 정하며, 호출부가 장비의 현재 등급을 넘긴다.
##   호출부가 등급을 잘못 넘기면 조용히 틀리므로 **불일치는 여기서 거절**한다.
## owner_uid > 0 이고 등급이 레어(bind_grade) 이상이면 그 자리에서 귀속된다
## (원작 "레어 등급 이상은 장착 시 귀속" — 위키 item.pdf).
static func reroll(equip_field: Dictionary, slot_id: String, grade: int,
		rng: RandomNumberGenerator, table: Dictionary, owner_uid: int = 0) -> Dictionary:
	var out := equip_field.duplicate(true)
	for s in (out.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) != slot_id:
			continue
		if int((s as Dictionary).get("grade", 0)) != grade:
			return {}                      # 동전 등급 ≠ 장비 등급 — 원작은 목록에 띄우지도 않는다
		(s as Dictionary)["options"] = roll_options(grade, rng, table)
		(s as Dictionary)["enhance"] = 0
		if owner_uid > 0 and binds_at(grade, table):
			(s as Dictionary)["belong"] = owner_uid
		return out
	return {}

## 강화 **성공** 1회: 옵션 하나를 골라 값을 올리고 강화 횟수를 +1 한다. 막혀 있으면 {}.
## 증가폭 = enhance_step_pct % (최소 +1) — 자작값.
##
## 위키 §2.6 / item.pdf: "강화하면 **일정 확률로 옵션이 하나 더 붙는다**"(추가 옵션).
## 원작 `onClickEnchant` 가 한도를 `rarity×5` 와 `optionAmount×5` 로 **따로** 검사하는 것이
## 그 흔적이다 — 추가 옵션이 붙으면 optionAmount 가 늘어 두 한도가 갈린다.
## 확률표(`enchant.extra_option_pct`)는 유실이라 자작.
static func enhance(equip_field: Dictionary, slot_id: String, rng: RandomNumberGenerator,
		table: Dictionary) -> Dictionary:
	var out := equip_field.duplicate(true)
	for s in (out.get("slots", []) as Array):
		var sd := s as Dictionary
		if String(sd.get("slot", "")) != slot_id:
			continue
		var opts: Array = sd.get("options", [])
		if opts.is_empty():
			return {}
		if enchant_blocked(sd, table) != "":
			return {}
		var step := float(table.get("option", {}).get("enhance_step_pct", 10))
		var i := rng.randi() % opts.size()
		var od := opts[i] as Dictionary
		var inc := maxi(1, int(round(float(od.get("value", 0)) * step / 100.0)))
		od["value"] = int(od.get("value", 0)) + inc
		sd["enhance"] = int(sd.get("enhance", 0)) + 1
		var extra := int(enchant_cfg(table).get("extra_option_pct", 0))
		if extra > 0 and opts.size() < 6 and rng.randi() % 100 < extra:
			var no := roll_option(rng, table)
			if not no.is_empty():
				opts.append(no)
		return out
	return {}

# --- 장착/해제 --------------------------------------------------------------

## slot_id 칸에 장비를 끼운 새 equip 필드. 규칙 위반이면 {}.
## meta = 가방 키에서 읽은 개체 정보(`item_key_meta`) — 귀속·희귀도·옵션·강화가 그대로 옮겨온다.
##   ⚠️ 획득 시 정해진 희귀도/옵션을 장착이 덮어쓰지 않는다. 예전엔 슬롯에서 옵션을 굴렸는데,
##      그러면 **뺐다 끼우기만 해도 옵션이 새로 굴러** 기누의 동전이 무의미해진다.
## `dragon_id` = 끼우려는 드래곤의 **종 id**. 0이면 종족 검사를 건너뛴다(구 호출부 호환).
## 전용 장비는 대응 종에만 들어간다(species_allows).
static func equip(equip_field: Dictionary, slot_id: String, key: String, table: Dictionary,
		meta: Dictionary = {}, dragon_id: int = 0) -> Dictionary:
	var cat := catalog(table)
	if not cat.has(key):
		return {}
	if not can_equip(cat[key], slot_id):
		return {}
	if dragon_id > 0 and not species_allows(cat[key], dragon_id):
		return {}
	var slots: Array = []
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) != slot_id:
			slots.append(s)
	slots.append({
		"slot": slot_id, "key": key,
		"options": (meta.get("options", []) as Array).duplicate(true),
		"grade": int(meta.get("rarity", 0)),
		"enhance": int(meta.get("enhance", 0)),
		"belong": int(meta.get("belong", 0)),
	})
	var out := equip_field.duplicate(true)
	out["slots"] = slots
	return out

static func unequip(equip_field: Dictionary, slot_id: String) -> Dictionary:
	var slots: Array = []
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) != slot_id:
			slots.append(s)
	var out := equip_field.duplicate(true)
	out["slots"] = slots
	return out

## slot_id 칸에 낀 장비 항목({} 이면 빈 칸).
static func equipped(equip_field: Dictionary, slot_id: String, table: Dictionary) -> Dictionary:
	var cat := catalog(table)
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return cat.get(String((s as Dictionary).get("key", "")), {})
	return {}

# --- 인벤토리 아이템 키 -----------------------------------------------------
#
# 원작 가방에는 **EQUIP 탭**이 있고 보유 장비에서 골라 낀다
# (`BagPopup.c:9186 "EQUIP"` · MultyEquipPop/ItemEquipSelectPopup).
# 장비 정의는 data/equipment.json 소유이므로 items.json 에 111행을 복제하지 않고
# 카탈로그 키를 감싼 **가상 인벤 키**로 보유한다(§8.1 data 계층 단일 출처).
#
#     "equip:basic:깃털:6"   ← ITEM_PREFIX + catalog() 키
#
# ⚠️ 옵션(info_item_acc 롤)은 장착 슬롯에 붙어 있다 — 인벤에 있는 동안은 옵션이 없다.
#   해제해서 인벤으로 돌려보내면 옵션도 함께 사라진다(원작의 옵션 보존 여부는 서버 유실).

#
# 귀속·희귀도·옵션·강화는 **아이템 개체**의 속성인데 우리 가방은 `{키: 개수}` 라 개체가 없다.
# 그래서 개체 정보를 키에 실어 스택을 나눈다(값이 똑같은 것끼리만 겹친다):
#
#     "equip:basic:깃털:6"                    메타 없음
#     "equip:b12@basic:깃털:6"                uid 12 드래곤에게 귀속
#     "equip:r3,oA7.P5@basic:깃털:6"          유니크 + 옵션(공격력7% · 관통5)
#     "equip:b12,r3,e2,oA7.P5@basic:깃털:6"   위 전부 + 강화 2회
#
# 메타 토큰(순서 고정 b→r→e→o, `,` 로 이음):
#     b<uid>   귀속 대상        r<n>  희귀도(등급 인덱스)
#     e<n>     강화 횟수        o<코드><값>.<코드><값>…  부가옵션
#
# ⚠️ 옵션 코드 글자는 **원작 그대로**다 — `Equip::setOption`/`getSummaryOption` 이 쓰는
#    H A D B E G P U C (§docs/ref/porting/EquipBelongOption.md §2-1). 원작도 옵션을
#    문자열로 직렬화했으므로 이 표현은 흉내가 아니라 같은 규약이다.
#
# 카탈로그 키에는 `@` 가 없으므로(basic/event/special/artifact 접두어 + 한글 이름) 모호하지 않다.
# 구버전 키(`equip:<카탈로그>` · `equip:<uid>@<카탈로그>`)도 그대로 읽힌다 — 마이그레이션 불필요.

const ITEM_PREFIX := "equip:"

## 옵션 스탯 ↔ 원작 직렬화 글자(`Equip::getSummaryOption` 의 "H%0.1f" "A%0.1f" … 그대로).
## 🟢 **원작 확정(2026-08-01)** — 이 글자표는 우리가 지은 게 아니라 원작 옵션 인코딩과 같다.
## `Equip::setOption(string)` 은 옵션 문자열을 `<글자><번호>` 토큰으로 끊어서
##   ① 번호로 `select hp, atk, def, blk, gold, exp, pure, depure, accuracy from info_item_acc
##      where no=%d` 를 돌려 9개 값을 읽고
##   ② `switch(글자)` 로 **그중 어느 컬럼을 쓸지** 고른다.
## 디컴프에서 전 케이스를 뽑은 결과(글자 → 컬럼 / 내부 type / 누적 필드):
##   A→atk(1,0x14c) · B→blk(3,0x154) · C→accuracy(8,0x168) · D→def(2,0x150) · E→exp(4,0x15c)
##   G→gold(5,0x158) · H→hp(0,0x148) · P→pure(6,0x160) · U→depure(7,0x164)
## 아래 표와 **글자 하나까지 같다.** 즉 우리 인벤 키의 옵션 인코딩이 곧 원작 인코딩이다.
##
## 표시 단위도 같은 switch 에서 확정된다 — A/B/C/D/E/G/H 는 뒤에 `"%"` 를 붙이고
## **P(관통)·U(관통감소)만 flat** 이다. 그중 실제로 기본 스탯에 **곱해지는** 것은
## hp/att/def 뿐이고(`Dragon::getAttAdd` 가 `Equip::getAtk()/100.0`), blk·accuracy·gold·exp 는
## 스탯 자체가 %라 퍼센트포인트 가산이다 → `option.pct_stats` = [hp, att, def] 가 맞다.
##
## ⚠️ 옵션 **수치**는 `info_item_acc` 행(로컬 SQLite)이라 그 DB 가 없는 우리는 못 읽는다.
##    그래서 `option.value_ranges`(자작 범위 롤)로 대신한다 — 구조가 원작과 다른 유일한 지점.
const OPTION_CODE := {
	"hp": "H", "att": "A", "def": "D", "blk": "B", "exp": "E",
	"gold": "G", "pure": "P", "depure": "U", "accuracy": "C",
}

static func _code_to_stat(c: String) -> String:
	for st in OPTION_CODE:
		if String(OPTION_CODE[st]) == c:
			return String(st)
	return ""

## 카탈로그 키 + 개체 정보 → 인벤토리 키.
## meta = {belong, rarity, enhance, options:[{stat,value}]} — 없는 키는 생략된다.
static func item_key(catalog_key: String, meta: Dictionary = {}) -> String:
	var tok: PackedStringArray = []
	var belong := int(meta.get("belong", 0))
	var rarity := int(meta.get("rarity", 0))
	var enhance := int(meta.get("enhance", 0))
	var opts: Array = meta.get("options", [])
	if belong > 0:
		tok.append("b%d" % belong)
	if rarity > 0:
		tok.append("r%d" % rarity)
	if enhance > 0:
		tok.append("e%d" % enhance)
	if not opts.is_empty():
		var parts: PackedStringArray = []
		for o in opts:
			var st := String((o as Dictionary).get("stat", ""))
			if not OPTION_CODE.has(st):
				continue
			parts.append("%s%d" % [String(OPTION_CODE[st]), int((o as Dictionary).get("value", 0))])
		if not parts.is_empty():
			tok.append("o" + ".".join(parts))
	if tok.is_empty():
		return ITEM_PREFIX + catalog_key
	return "%s%s@%s" % [ITEM_PREFIX, ",".join(tok), catalog_key]

## 인벤토리 키 → 카탈로그 키. 장비 키가 아니면 "". (메타는 떼고 돌려준다)
static func parse_item_key(key: String) -> String:
	if not key.begins_with(ITEM_PREFIX):
		return ""
	var rest := key.substr(ITEM_PREFIX.length())
	var at := rest.find("@")
	return rest.substr(at + 1) if at > 0 else rest

## 인벤토리 키의 개체 정보 → {belong, rarity, enhance, options}. 메타가 없으면 전부 0/빈배열.
static func item_key_meta(key: String) -> Dictionary:
	var out := {"belong": 0, "rarity": 0, "enhance": 0, "options": []}
	if not key.begins_with(ITEM_PREFIX):
		return out
	var rest := key.substr(ITEM_PREFIX.length())
	var at := rest.find("@")
	if at <= 0:
		return out
	var meta := rest.substr(0, at)
	if meta.is_valid_int():
		out["belong"] = int(meta)      # 구버전(2026-07-29 오전) 형식: 소유자만 실려 있었다
		return out
	for t in meta.split(","):
		var body := String(t).substr(1)
		match String(t).substr(0, 1):
			"b": out["belong"] = int(body) if body.is_valid_int() else 0
			"r": out["rarity"] = int(body) if body.is_valid_int() else 0
			"e": out["enhance"] = int(body) if body.is_valid_int() else 0
			"o":
				var opts: Array = []
				for p in body.split("."):
					var s := String(p)
					if s.length() < 2:
						continue
					var st := _code_to_stat(s.substr(0, 1))
					if st != "" and s.substr(1).is_valid_int():
						opts.append({"stat": st, "value": int(s.substr(1))})
				out["options"] = opts
	return out

## 인벤토리 키의 귀속 대상 uid. 미귀속이면 0.
static func item_key_belong(key: String) -> int:
	return int(item_key_meta(key).get("belong", 0))

## 장착 슬롯 dict → 인벤토리 키(해제할 때 개체 정보를 고스란히 되돌린다).
static func slot_to_item_key(slot: Dictionary) -> String:
	return item_key(String(slot.get("key", "")), {
		"belong": int(slot.get("belong", 0)),
		"rarity": int(slot.get("grade", 0)),
		"enhance": int(slot.get("enhance", 0)),
		"options": slot.get("options", []),
	})

# --- 귀속 규칙 ---------------------------------------------------------------
#
# 원작(§docs/ref/porting/EquipBelongOption.md §1):
#   · 값은 드래곤 tag. 미귀속 = 0 또는 -1.
#   · 장착 판정 = `belong == -1 || belong == 0 || belong == 그 드래곤`(BagTableViewCell.c:671).
#   · 레어 등급 이상은 장착하면 귀속된다(위키 item.pdf) → 우리는 등급이 정해지는 시점,
#     즉 옵션 재설정(reroll)에서 건다.
#   · 해제는 '구드라의 지혜'(items.json `item_disconnect`) 1회 소모.

## 그 등급이면 귀속되는가. 표 = equipment.json option.bind_grade(기본 2=레어).
static func binds_at(grade: int, table: Dictionary) -> bool:
	return grade >= int(table.get("option", {}).get("bind_grade", 2))

## 그 드래곤이 이 귀속값의 장비를 쓸 수 있는가(원작 판정식 그대로).
static func belong_allows(belong: int, dragon_uid: int) -> bool:
	return belong <= 0 or belong == dragon_uid

## slot_id 칸의 귀속 대상 uid(0=미귀속).
static func slot_belong(equip_field: Dictionary, slot_id: String) -> int:
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return int((s as Dictionary).get("belong", 0))
	return 0

## slot_id 칸의 귀속을 푼 새 equip 필드. 귀속돼 있지 않으면 {}.
static func unbind(equip_field: Dictionary, slot_id: String) -> Dictionary:
	var out := equip_field.duplicate(true)
	for s in (out.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			if int((s as Dictionary).get("belong", 0)) <= 0:
				return {}
			(s as Dictionary)["belong"] = 0
			return out
	return {}

# --- 아티팩트 합성(원작 ArtifactMix) -----------------------------------------
## 원작 = 마모루딕 연구소 '아티펙트 합성'. 대상 아티팩트 1개 + **재료 3개** + 골드로
## 대상의 등급을 1단 올린다. 포팅 카드 = `docs/ref/porting/ArtifactMix.md`.
##
## 원작 클라가 갖고 있던 것(디컴프 실측):
##   · 재료 3칸 고정 — `onClickMix` 가 세 슬롯 중 하나라도 -1 이면 토스트
##     `<ArtifactMixErrorMsg>`("아티펙트 합성에는 3개의 재료를 필요로 합니다.")
##   · 비용 = `표[getTypeLevel(대상)-1] × 채운 재료 수` (`ArtifactMix::setGold`)
## 유실된 것: 그 표(서버 배열)와 성공 확률 → `data/equipment.json` `artifacts.mix`(자작).

## 인벤 키/카탈로그 키 → {type, grade}. 아티팩트가 아니면 {}.
static func artifact_of(key: String) -> Dictionary:
	var cat := parse_item_key(key)
	if cat == "":
		cat = key
	var p := cat.split(":")
	if p.size() != 3 or String(p[0]) != "artifact":
		return {}
	return {"type": String(p[1]), "grade": int(p[2])}

static func artifact_mix_cfg(table: Dictionary) -> Dictionary:
	return (table.get("artifacts", {}) as Dictionary).get("mix", {})

## 재료 하나당 골드(원작 setGold 의 서버 배열 자리). 대상이 최고 등급이면 0.
static func artifact_mix_unit_cost(table: Dictionary, base_key: String) -> int:
	var a := artifact_of(base_key)
	if a.is_empty():
		return 0
	var arr: Array = artifact_mix_cfg(table).get("cost_per_material", [])
	var g := int(a["grade"])
	return int(arr[g]) if g >= 0 and g < arr.size() else 0

## 원작 `setGold` 그대로 — 단가 × 채운 재료 수.
static func artifact_mix_cost(table: Dictionary, base_key: String, filled: int) -> int:
	return artifact_mix_unit_cost(table, base_key) * maxi(filled, 0)

## 그 아티팩트를 대상으로 삼을 수 있나(최고 등급은 더 올릴 데가 없다).
static func artifact_mix_upgradable(table: Dictionary, base_key: String) -> bool:
	var a := artifact_of(base_key)
	if a.is_empty():
		return false
	var grades: Array = (table.get("artifacts", {}) as Dictionary).get("grades", [])
	return int(a["grade"]) + 1 < grades.size() \
		and artifact_mix_unit_cost(table, base_key) > 0

## 재료로 쓸 수 있나. 대상과 같은 종류·아티팩트 등급이어야 한다(자작 규칙).
## 대상 그 자체(같은 인벤 키의 같은 개체)는 호출부가 수량으로 걸러야 한다.
static func artifact_mix_material_ok(table: Dictionary, base_key: String, mat_key: String) -> bool:
	var b := artifact_of(base_key)
	var m := artifact_of(mat_key)
	if b.is_empty() or m.is_empty():
		return false
	if bool(artifact_mix_cfg(table).get("same_type_required", true)):
		if String(m["type"]) != String(b["type"]):
			return false
	if bool(artifact_mix_cfg(table).get("same_grade_required", true)):
		if int(m["grade"]) != int(b["grade"]):
			return false
	return true

## 합성 결과 인벤 키(등급 +1). 대상의 개체 정보(귀속·강화·옵션)는 그대로 승계한다.
static func artifact_mix_result(table: Dictionary, base_key: String) -> String:
	var a := artifact_of(base_key)
	if a.is_empty() or not artifact_mix_upgradable(table, base_key):
		return ""
	return item_key("artifact:%s:%d" % [String(a["type"]), int(a["grade"]) + 1],
		item_key_meta(base_key))

## 성공 확률(%) — 자작. 현재 표는 전부 100 이라 실패 분기는 데이터로만 열려 있다.
static func artifact_mix_success_pct(table: Dictionary, base_key: String) -> int:
	var a := artifact_of(base_key)
	if a.is_empty():
		return 0
	var arr: Array = artifact_mix_cfg(table).get("success_pct", [])
	var g := int(a["grade"])
	return int(arr[g]) if g >= 0 and g < arr.size() else 100

# --- 아이템 강화(원작 ItemEnchantPopup) --------------------------------------
#
# 🟢 비용도 확률도 **클라가 계산**한다 — 서버가 한 건 성공/실패 주사위뿐이다.
# 공식은 디컴프 실측(추측 0), 표는 `data/equipment.json` `enchant`:
#
#     W(장비) = type_level + rarity×2 + upgrade          (Item::getTypeLevel 등)
#     기준%   = int(W(대상) × -1.5 + 50), 0 미만이면 0    (initWidget @00e8e1xx)
#     골드    = W(대상) × 500
#     가산%   = ΣW(재료) × 100 / (W(대상) × 5)            (calculate @00e98edc)
#     표시%   = 기준 + 가산, 99 초과면 100
#
# 참조 프레임 `docs/ref/equip/장비강화1.png` 의 "23% / 코인 x 9000" 이 W=18 하나로
# 동시에 맞는다(9000/500=18, 50−1.5×18=23) — 교차검증 통과.

static func enchant_cfg(table: Dictionary) -> Dictionary:
	return table.get("enchant", {}) as Dictionary

## 그 카탈로그 항목의 type_level(= 사다리 단계 번호, 1부터).
## 사다리가 있는 계열(basic·artifact)은 `grade + 1`, 없는 계열은 표(자작).
static func enchant_type_level(item: Dictionary, table: Dictionary) -> int:
	var grp := String(item.get("group", ""))
	if item.has("grade"):
		return int(item["grade"]) + 1
	var by_grp: Dictionary = enchant_cfg(table).get("type_level_group", {})
	for k in by_grp:
		if grp == String(k) or grp.begins_with(String(k) + ":"):
			return int(by_grp[k])
	return 1

## 강화 무게 W. `rarity` = 희귀도 인덱스(0=일반), `upgrade` = 현재 강화 횟수.
static func enchant_weight(item: Dictionary, rarity: int, upgrade: int,
		table: Dictionary) -> int:
	if item.is_empty():
		return 0
	return enchant_type_level(item, table) + rarity * 2 + upgrade

## 인벤토리 키(`equip:…`) 1개의 W. 카탈로그에 없는 키면 0.
static func enchant_weight_of_key(key: String, table: Dictionary) -> int:
	var item: Dictionary = catalog(table).get(parse_item_key(key), {})
	if item.is_empty():
		return 0
	var m := item_key_meta(key)
	return enchant_weight(item, int(m.get("rarity", 0)), int(m.get("enhance", 0)), table)

## 장착 슬롯 dict 1개의 W.
static func enchant_weight_of_slot(slot: Dictionary, table: Dictionary) -> int:
	var item: Dictionary = catalog(table).get(String(slot.get("key", "")), {})
	if item.is_empty():
		return 0
	return enchant_weight(item, int(slot.get("grade", 0)), int(slot.get("enhance", 0)), table)

static func enchant_gold(weight: int, table: Dictionary) -> int:
	return weight * int(enchant_cfg(table).get("gold_per_weight", 500))

## 재료 없는 기준 확률(%).
static func enchant_base_pct(weight: int, table: Dictionary) -> int:
	var c := enchant_cfg(table)
	var v := int(float(weight) * float(c.get("percent_per_weight", -1.5))
		+ float(c.get("base_percent", 50)))
	return maxi(0, v)

## 재료를 넣은 뒤의 표시 확률(%). `mat_weights` = 채운 재료들의 W(빈 칸은 넣지 않는다).
static func enchant_pct(weight: int, mat_weights: Array, table: Dictionary) -> int:
	var base := enchant_base_pct(weight, table)
	var denom := weight * int(enchant_cfg(table).get("material_denom", 5))
	var bonus := 0
	if denom != 0:
		var sum := 0
		for w in mat_weights:
			sum += int(w)
		bonus = int(sum * 100 / denom)          # 원작도 정수 나눗셈(내림)이다
	var v := base + bonus
	return 100 if v > 99 else v

## 그 칸을 더 강화할 수 있는가. 막혀 있으면 **사유 코드**, 가능하면 "".
## 원작 `onClickEnchant` 의 두 게이트 그대로 — 희귀도 한도와 옵션 수 한도를 따로 본다.
## 코드 → 문구는 render 가 붙인다(§8.3: logic 은 표시를 모른다). 원작 대응 문자열:
##   `no_equip` = <CaveItemEquipMsg11> · `grade_max` = <CaveItemEquipMsg7> ·
##   `option_max` = <CaveItemEquipMsg8>
static func enchant_blocked(slot: Dictionary, table: Dictionary) -> String:
	if slot.is_empty():
		return "no_equip"
	var per := int(table.get("option", {}).get("enhance_per_option", 5))
	var up := int(slot.get("enhance", 0))
	if up >= int(slot.get("grade", 0)) * per:
		return "grade_max"
	if up >= (slot.get("options", []) as Array).size() * per:
		return "option_max"
	return ""
