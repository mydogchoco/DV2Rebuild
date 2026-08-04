# Drops(젬·장비 획득) — 순수 로직 계층 (§8: render/에셋 의존 없음, 헤드리스 검증 가능)
#
# 사용자 확정 규칙(2026-07-27):
#   · 젬·장비는 기본적으로 **탐험 드롭**
#   · **고레벨 지역**일수록 · **일반몹 < 보물상자 < 보스** 일수록 더 좋은 것
#   · 상점 = 낮은 성능을 **골드**로 · **다이아 가챠** = 좋은 것
#   · **이벤트 장비는 가챠 전용**
#   · **아티팩트는 '유타칸 – 카데스의 공간' 탐험 드롭 전용**
#
# 위키 근거(수치가 확정된 것):
#   · 아티팩트 획득처 = etc.pdf §2.2 "유타칸 카데스와 베르나에서 얻을 수 있는" (베르나=에셋부재 CUT)
#   · 카데스의 공간 = dungeon_1.pdf §2 — 새 지역이 아니라 **유타칸 전 지역 전설 난이도 모드**
#   · 젬 가챠 = item.pdf §9.3 "바루스에게 개당 15다이아, 10연속 125다이아 … 높은 등급의 일반 젬"
#   · 이벤트 장비 = equipment_0.pdf §2.1.1 "이벤트 장신구 선택권으로만 얻을 수 있다"
#
# 확률·티어폭·가격은 서버 유실 → `data/drops.json` 에 외부화한 자작값(튜닝 노브).
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드 참조 금지(§8.2 단방향 의존).
#    반환값은 **인벤 키 문자열**이다 — 아이콘·연출은 render 가 한다.
class_name Drops
extends RefCounted

const SOURCE_NORMAL := "normal"
const SOURCE_CHEST := "chest"
const SOURCE_BOSS := "boss"

# --- 속성 표기 정규화 -------------------------------------------------------
#
# 원작은 같은 속성을 **두 이름**으로 부른다 — 아이콘 경로는 `item/item_small/ele_ground.png` ·
# `ele_water.png` 인데(`AdventureScene::setRewardItemDesc` 리터럴 9종), 개체 데이터의 속성 값은
# `earth`/`aqua` 다(`Dragon::getRace()` 가 돌려주는 글자도 "E"/"A").
# 우리 데이터도 그대로 갈렸다 — `stages.json` 의 지역 속성은 `ground`/`water`,
# `dragons.json`·`items.json` 의 속성은 `earth`/`aqua`.
# 드롭 판정은 둘을 같은 것으로 봐야 하므로 여기서 한 이름으로 눕힌다.
# (render 쪽 같은 표는 `scripts/ui/icons.gd` — 그쪽은 키→아이콘이라 이 표와 방향이 다르다.)
const ELEMENT_ALIAS := {"ground": "earth", "water": "aqua"}

## 속성 표기를 정준형(earth/aqua/fire/wind/light/dark/holy/chaos/shadow)으로.
## ⚠️ Variant 를 받는다 — 데이터의 `element` 는 **null 일 수 있다**(드링크·회복물약은
##   category=food 인데 element 가 null, 우노 스테이지도 element 가 null).
##   Godot 4.7 에서 `String(null)` 은 런타임 에러(`Invalid call 'String' constructor`)라
##   호출부에서 감싸지 말고 여기서 한 번에 처리한다.
static func normalize_element(element) -> String:
	if typeof(element) != TYPE_STRING:
		return ""
	return String(ELEMENT_ALIAS.get(element, element))

# --- 탐험 먹이 드롭 ---------------------------------------------------------
#
# 사용자 확정(2026-07-30): **각 탐험 지역 속성에 맞는 먹이만** 드롭한다.
# 기준은 `stages.json` 의 지역 `element` **하나**(엄격) — 등장 드래곤 속성으로 넓히지 않는다.
#
# ⚠️ 파생 결과(의도된 것): 지역 속성은 6종(ground/water/fire/wind/light/dark)뿐이라
#   **chaos·holy·shadow 먹이는 탐험에서 나오지 않는다.** 그 3속성은 상점의 작은 변형
#   (`food_chaos_tadpole` · `food_holy_small_ginseng` · `food_shadow_chocolate_piece`)으로만
#   구할 수 있고, 큰 변형은 현재 입수 경로가 없다. 지역이 추가되거나 사용자가 배정을 주면
#   이 함수는 그대로 두고 `stages.json` 의 element 만 채우면 따라온다.
# ⚠️ 지역 속성이 비어 있으면(우노의 검은 섬·미지의 터 = element null) 먹이를 **주지 않는다**.
#   아무 속성이나 주는 종전 동작이 이 규칙이 고치려는 바로 그 버그다.

## 그 지역에서 나올 수 있는 먹이 키 목록. item_defs = data/items.json 의 items 사전.
## 정렬해 돌려준다 — 같은 시드가 같은 결과를 내야 한다(§드롭 RNG 규약).
## ⚠️ `stage_element` 는 Variant 다 — `stages.json` 의 element 는 **null 일 수 있고**
##   (우노의 검은 섬·미지의 터), `String(null)` 은 `"<null>"` 이 되어 문자열 비교를 조용히
##   통과시킨다. 여기서 한 번에 막는다.
static func food_pool(item_defs: Dictionary, stage_element) -> Array:
	var want := normalize_element(stage_element)
	if want == "" or want == "none":
		return []
	var out: Array = []
	for k in item_defs:
		# ⚠️ 원본 `items.json` 의 `items` 에는 `_` 로 시작하는 **문자열 메타**가 섞여 있다
		#   (`Data.items` 는 걸러 주지만 JSON 을 직접 읽는 도구/테스트는 그대로 받는다).
		if typeof(item_defs[k]) != TYPE_DICTIONARY:
			continue
		var v: Dictionary = item_defs[k]
		if String(v.get("category", "")) != "food":
			continue
		# 드링크·회복물약은 category=food 지만 element 가 **null** 이다 →
		# normalize_element 가 "" 를 돌려주므로 여기서 자연히 떨어진다.
		if normalize_element(v.get("element", "")) == want:
			out.append(String(k))
	out.sort()
	return out

## 그 지역 속성에 맞는 먹이 1종 → 아이템 키. 후보가 없으면 "".
static func roll_food(item_defs: Dictionary, stage_element,
		rng: RandomNumberGenerator) -> String:
	var pool := food_pool(item_defs, stage_element)
	if pool.is_empty():
		return ""
	return String(pool[rng.randi() % pool.size()])

# --- 탐험 속성 정기 드롭 ----------------------------------------------------
#
# 사용자 확정(2026-07-31): **각 탐험지역에 맞는 속성 정기**가 나온다.
# 정기 = `items.json` 의 `currency/essence` 9종(`ele_fire` "불의 정기" 등)이고, 먹이와 같은
# `element` 필드를 갖는다 → 같은 정규화(ground≡earth · water≡aqua)로 지역과 맞춘다.
# 확률은 서버 유실 → `data/drops.json` `essence`(자작 노브).

## 그 지역 속성의 정기 키. 없으면 "".
static func essence_of(item_defs: Dictionary, stage_element) -> String:
	var want := normalize_element(stage_element)
	if want == "" or want == "none":
		return ""
	for k in item_defs:
		if typeof(item_defs[k]) != TYPE_DICTIONARY:
			continue
		var v: Dictionary = item_defs[k]
		if String(v.get("subcategory", "")) != "essence":
			continue
		if normalize_element(v.get("element", "")) == want:
			return String(k)
	return ""

## 정기 판정 → {key, count} 또는 {} (드롭 없음).
static func roll_essence(table: Dictionary, item_defs: Dictionary, stage_element,
		source: String, rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = table.get("essence", {})
	if cfg.is_empty():
		return {}
	if rng.randf() >= float((cfg.get("chance", {}) as Dictionary).get(source, 0.0)):
		return {}
	var key := essence_of(item_defs, stage_element)
	if key == "":
		return {}
	var c: Dictionary = cfg.get("count", {})
	var lo := int(c.get("min", 1))
	return {"key": key, "count": rng.randi_range(lo, maxi(lo, int(c.get("max", 1))))}

# --- 희귀 속성 드랍(신성·혼돈·그림자) ----------------------------------------
#
# 🟦 사용자 확정 2026-08-04. 지역 속성은 6종뿐이라 위의 `roll_essence`/`roll_food` 로는
# 신성·혼돈·그림자가 **영원히 나오지 않는다**(수급처 전수 대조 2026-08-04). 그래서 지역
# 속성이 아니라 **난이도**에 붙는 별도 드랍을 하나 둔다:
#   일반(·밤) = 보스 처치 · 영웅 = 전투 승리 · 카데스 = 전투 승리 → 25% 로 풀에서 1종.
# 표 = `data/drops.json` `rare_element`(자작 노브).

## 이 난이도·이 전투에서 희귀 속성 드랍을 굴릴 자격이 있는가.
## `modes` 값 "any" = 모든 승리, "boss" = 보스 처치만, 그 밖/부재 = 안 나온다.
static func rare_element_allowed(table: Dictionary, mode: String, boss: bool) -> bool:
	var cfg: Dictionary = table.get("rare_element", {})
	if cfg.is_empty():
		return false
	match String((cfg.get("modes", {}) as Dictionary).get(mode, "")):
		"any": return true
		"boss": return boss
	return false

## 희귀 속성 드랍 판정 → {key, count} 또는 {} (드롭 없음).
static func roll_rare_element(table: Dictionary, mode: String, boss: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	if not rare_element_allowed(table, mode, boss):
		return {}
	var cfg: Dictionary = table.get("rare_element", {})
	var pool: Array = cfg.get("pool", [])
	if pool.is_empty():
		return {}
	if rng.randf() >= float(cfg.get("chance", 0.0)):
		return {}
	var row: Dictionary = pool[rng.randi() % pool.size()]
	var lo := int(row.get("min", 1))
	return {"key": String(row.get("key", "")),
		"count": rng.randi_range(lo, maxi(lo, int(row.get("max", 1))))}

# --- 드링크(버프 물약) 드랍 --------------------------------------------------
#
# 🟦 사용자 확정 2026-08-04: 상점이 3단계만 팔아서 1·2단계가 어디서도 안 나왔다 →
# **모든 전투 승리**에서 10% 로 1·2단계 중 한 종. 표 = `data/drops.json` `drink`.
# 품목은 `items.json` 에서 파생한다(§8.1 정의 단일 출처) — tier 가 없는 자양강장제는 빠진다.

## 드랍 대상 드링크 키 목록(정렬 — 같은 시드면 같은 결과, §4).
static func drink_pool(table: Dictionary, item_defs: Dictionary) -> Array:
	var cfg: Dictionary = table.get("drink", {})
	if cfg.is_empty():
		return []
	var tiers: Array = cfg.get("tiers", [])
	var out: Array = []
	for k in item_defs:
		if typeof(item_defs[k]) != TYPE_DICTIONARY:
			continue
		var v: Dictionary = item_defs[k]
		if String(v.get("subcategory", "")) != "drink":
			continue
		if not v.has("tier"):
			continue                      # 자양강장제 — 단계가 없다
		for t in tiers:
			if int(t) == int(v.get("tier", 0)):
				out.append(String(k))
				break
	out.sort()
	return out

## 드링크 판정 → {key, count} 또는 {} (드롭 없음).
static func roll_drink(table: Dictionary, item_defs: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = table.get("drink", {})
	if cfg.is_empty():
		return {}
	if rng.randf() >= float(cfg.get("chance", 0.0)):
		return {}
	var pool := drink_pool(table, item_defs)
	if pool.is_empty():
		return {}
	var c: Dictionary = cfg.get("count", {})
	var lo := int(c.get("min", 1))
	return {"key": String(pool[rng.randi() % pool.size()]),
		"count": rng.randi_range(lo, maxi(lo, int(c.get("max", 1))))}

# --- 탐험 특수 드랍(지역 전용 표) --------------------------------------------
#
# 표 = `stages.json` 의 그 지역 `drops` 이고, 사용자가 CSV 로 채운다
# (`docs/input/sheets/adventure_drop_pool.csv` ↔ `scripts/tools/build_adventure_drops.py`).
# 원작은 이 표가 **서버 소유**였다(`initJsonReward` 에 확률이 없다 — 포팅 카드 §6).
#
# 🔴 2026-07-29 사고 기록: 이 표는 데이터에만 있고 **아무도 읽지 않고 있었다** —
#   우노의 아니마·보네르가 인게임에서 나올 길이 없어 각성 자체가 도달 불가였다.
#   그래서 지금은 판정을 여기(logic)로 모으고 테스트로 묶어 둔다.

# 난이도 축 — 드랍 풀이 이 단위로 **나뉜다**(사용자 확정 2026-07-31).
const MODE_NORMAL := "normal"
const MODE_HERO := "hero"
const MODE_NIGHT := "night"     # 유타칸 밤(+500 변형). night 블록이 있는 12지역에만.
const MODE_KADES := "kades"     # 카데스의 공간(+600 변형).

## 이번 런의 난이도 키. render 가 params 로 넘긴 플래그를 하나로 접는다.
## 우선순위: 카데스 > 밤 > 영웅 > 일반 (변형 필드가 영웅보다 상위 콘텐츠다).
static func mode_of(hero: bool, night: bool, kades: bool) -> String:
	if kades: return MODE_KADES
	if night: return MODE_NIGHT
	if hero: return MODE_HERO
	return MODE_NORMAL

## 그 지역·그 난이도의 특수 드랍 표. 없으면 빈 배열.
##
## `stages.json` 의 `drops` 는 **{난이도: [항목]}** 이다(2026-07-31 이후).
## ⚠️ 구판은 평평한 배열이었고 `hero_min/hero_max` 로 수량만 갈랐다 — 그 형태를 만나면
##   난이도 구분 없이 **모든 난이도에 적용**한다(마이그레이션 전 세이브/데이터 호환).
##   그때만 hero_min/hero_max 를 본다.
## 요청한 난이도의 표가 **아예 없으면**(키 부재) 일반 표로 떨어진다 — 빈 배열(`[]`)을
##   명시하면 "그 난이도엔 아무것도 안 나온다"는 뜻이 된다.
static func special_table(stage: Dictionary, mode: String) -> Array:
	var d = stage.get("drops", [])
	if typeof(d) == TYPE_ARRAY:
		return d as Array                       # 구판 — 모든 난이도 공통
	var dd: Dictionary = d
	# ⛔ 밤은 **지역 필드 보상이 없다**(사용자 확정 2026-07-31) — 진입당 조우 1회로 끝나므로
	#   지역 단위 드랍이 의미가 없다. 밤의 획득은 `roll_monster`(몬스터별 드랍)가 담당한다.
	#   여기서 일반 표로 폴백해 버리면 밤에 낮 필드 보상이 나온다.
	if mode == MODE_NIGHT:
		return (dd.get(MODE_NIGHT, []) as Array)
	if dd.has(mode):
		return dd[mode] as Array
	return (dd.get(MODE_NORMAL, []) as Array)   # 그 난이도 표가 없으면 일반 표

## 그 지역의 특수 드랍 판정 → [{kind, key, count}, …].
##
## 항목은 `kind` 로 갈린다(2026-07-31 사용자 표):
##   item          → 그 아이템 키(우노의 아니마/보네르)
##   skill_scroll  → `skill:<스킬id>:<레벨>`. 레벨은 `levels` 에서 `level_weights` 비례로 고른다.
##                   23개 지역이 **지역 전용 스킬**을 준다 — 일반 Lv1~3 0.1% / 영웅 Lv2~4 0.2%.
## `boss_only` 면 보스 조우에서만 나온다(사용자 표의 "보스에서만 드랍").
## `chance` 는 **소수 허용**(0.1 = 0.1%).
##
## ⚠️ 구판(평평한 배열 + `rate` 정수 + hero_min/hero_max)도 그대로 읽는다.
static func roll_special(stage: Dictionary, rng: RandomNumberGenerator,
		mode := MODE_NORMAL, is_boss := true) -> Array:
	var legacy := typeof(stage.get("drops", [])) == TYPE_ARRAY
	var out: Array = []
	for d in special_table(stage, mode):
		var dp: Dictionary = d
		if bool(dp.get("boss_only", false)) and not is_boss:
			continue
		# 확률 — 신형은 `chance`(%, 소수 허용), 구판은 `rate`(1~100 정수).
		var pct := float(dp.get("chance", dp.get("rate", 100)))
		if rng.randf() * 100.0 >= pct:
			continue
		match String(dp.get("kind", "item")):
			"skill_scroll":
				var sid := int(dp.get("skill", 0))
				if sid <= 0:
					continue
				var lv := _pick_level(dp, rng)
				if lv > 0:
					out.append({"kind": "item", "key": Loadout.item_key(sid, lv), "count": 1})
			_:
				var key := String(dp.get("item", dp.get("key", "")))
				if key == "":
					continue
				var lo := int(dp.get("min", 1))
				var hi := int(dp.get("max", 1))
				if legacy and mode == MODE_HERO and dp.has("hero_min"):
					lo = int(dp["hero_min"])
					hi = int(dp.get("hero_max", dp["hero_min"]))
				var qty := rng.randi_range(mini(lo, hi), maxi(lo, hi))
				if qty > 0:
					out.append({"kind": "item", "key": key, "count": qty})
	return out

## 스크롤 레벨 하나. `levels`(명시 목록)가 있으면 그 안에서 `level_weights` 비례로,
## 없으면 `level_weights[i]` 를 레벨 i+1 로 본다(몬스터 표의 구형 표기).
static func _pick_level(row: Dictionary, rng: RandomNumberGenerator) -> int:
	var lw: Array = row.get("level_weights", [1])
	var levels: Array = row.get("levels", [])
	var i := _weighted_index(lw, rng)
	if levels.is_empty():
		return i + 1
	return int(levels[clampi(i, 0, levels.size() - 1)])

# --- 몬스터별 고유 드랍 -------------------------------------------------------
#
# 사용자 확정(2026-07-31): 일부 몬스터는 **장소가 아니라 그 몬스터에** 드랍이 붙는다.
#   · 밤 지역 공용 조우 몬스터 — #160 골드 임프 · #161 실버 임프 · #162 검은 로브의 사도
#     (+ 실측: #175 칼리고마가도 밤 12지역 전부에 나온다)
#   · 혼돈의 틈새 랜덤 보스 — #36 다크닉스 · #138 그리파르 · #139 발레포르
#
# 지역 표(`stages.json drops`)와 **합산**된다 — 한 조우에서 둘 다 판정한다.
# 표 = `data/monster_drops.json` (사용자가 `docs/input/sheets/monster_drop_pool.csv` 로 채운다).
# 키는 `stages.json` 의 적 `id` 다 — `data/monsters.json` 은 **이름**으로 키가 잡힌 위키
# 추출본이라 런타임 조인에 못 쓴다.

## 그 몬스터의 고유 드랍 표. 없으면 빈 배열.
static func monster_table(table: Dictionary, monster_id: int) -> Array:
	if monster_id <= 0:
		return []
	return ((table.get("drops", {}) as Dictionary).get(str(monster_id), []) as Array)

## 몬스터 고유 드랍 판정 → [{kind, key?/currency?, count}, …].
##
## 표의 한 행 = 하나의 후보다. **같은 `kind` 끼리 `weight` 로 하나를 고른 뒤** 그 행의
## `chance`(%) 로 판정한다 — 사용자 표의 `3:2:1:1` 같은 비율이 그 weight 이고,
## 그때 드랍 자체는 확정(chance=100)이다. 알·다이아처럼 단일 행인 것은 맨 숫자가 확률(%)이다.
##
## kind 별 지급 키
##   item          → 그 아이템 키
##   skill_scroll  → `skill:<스킬id>:<레벨>` (Loadout.item_key). 원작 `Skill::create(no)+setLevel(lv)`
##                   와 1:1이고 **가방 '스킬' 탭**으로 들어간다(원작 `AccountManager::addSkill`).
##                   레벨은 `level_weights`(1~4 가중치)로 고른다.
##   egg           → `egg:<드래곤id>` (EggGacha.key_for)
##   currency      → 아이템이 아니다. 호출부가 `UserDB.add_currency` 로 지급한다.
static func roll_monster(table: Dictionary, monster_id: int,
		rng: RandomNumberGenerator) -> Array:
	var rows := monster_table(table, monster_id)
	if rows.is_empty():
		return []
	# kind 별로 묶어 각 묶음에서 하나씩 고른다.
	var by_kind: Dictionary = {}
	for r in rows:
		var k := String((r as Dictionary).get("kind", "item"))
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(r)
	var out: Array = []
	for k in by_kind:
		var group: Array = by_kind[k]
		var row: Dictionary = group[_pick_weighted_row(group, rng)]
		# chance 는 **소수 허용**(0.2 = 0.2%).
		if rng.randf() * 100.0 >= float(row.get("chance", 100)):
			continue
		var got := _monster_grant(row, rng)
		if not got.is_empty():
			out.append(got)
	return out

## 한 행 → 지급물 {kind, key/currency, count}. 만들 수 없으면 {}.
static func _monster_grant(row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var lo := int(row.get("min", 1))
	var hi := int(row.get("max", 1))
	var qty := rng.randi_range(mini(lo, hi), maxi(lo, hi))
	match String(row.get("kind", "item")):
		"item":
			var key := String(row.get("key", ""))
			if key == "" or qty <= 0:
				return {}
			return {"kind": "item", "key": key, "count": qty}
		"skill_scroll":
			var sid := int(row.get("skill", 0))
			if sid <= 0:
				return {}
			var lv := _pick_level(row, rng)
			return {"kind": "item", "key": Loadout.item_key(sid, lv), "count": 1}
		"egg":
			var did := int(row.get("dragon", 0))
			if did <= 0:
				return {}
			return {"kind": "item", "key": EggGacha.key_for(did), "count": maxi(1, qty)}
		"currency":
			var cur := String(row.get("currency", ""))
			if cur == "" or qty <= 0:
				return {}
			return {"kind": "currency", "currency": cur, "count": qty}
	return {}

## 그 스크롤 행이 줄 수 있는 레벨 목록.
static func _levels_of(row: Dictionary) -> Array:
	var levels: Array = row.get("levels", [])
	if not levels.is_empty():
		return levels
	var out: Array = []
	for i in (row.get("level_weights", [1]) as Array).size():
		out.append(i + 1)
	return out

## 행 묶음에서 `weight`(기본 1) 비례 추첨 → 인덱스.
static func _pick_weighted_row(rows: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in rows:
		total += maxf(0.0, float((r as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return rng.randi() % rows.size()
	var x := rng.randf() * total
	for i in rows.size():
		x -= maxf(0.0, float((rows[i] as Dictionary).get("weight", 1)))
		if x <= 0.0:
			return i
	return rows.size() - 1

## 그 몬스터가 줄 수 있는 **모든 인벤 키**(화이트리스트 검증용).
static func monster_keys(table: Dictionary, monster_id: int) -> Array:
	var out: Array = []
	for r in monster_table(table, monster_id):
		var row: Dictionary = r
		match String(row.get("kind", "item")):
			"item":
				out.append(String(row.get("key", "")))
			"skill_scroll":
				for lv in _levels_of(row):
					out.append(Loadout.item_key(int(row.get("skill", 0)), int(lv)))
			"egg":
				out.append(EggGacha.key_for(int(row.get("dragon", 0))))
	return out

# --- 화이트리스트 -------------------------------------------------------------
#
# 사용자 확정(2026-07-31): **탐험에서는 아래 다섯 가지만 나온다.**
#   1. 드래곤 알   — 그 탐험지 팝업 등재 드래곤만 (`roll_egg`)
#   2. 일반 젬     — `exploration.gem_pool` (`roll_exploration`)
#   3. 먹이        — 그 지역 속성에 맞는 것만 (`roll_food`)
#   4. 속성 정기   — 그 지역 속성의 것 (`roll_essence`)
#   5. 특수 드랍   — 그 지역 CSV 표 (`roll_special`)
#   (+ 장비·아티팩트는 **전 지역 공통**으로 유지 — 사용자 확정 2026-07-31, 젬과 같은 취급)
#
# 🟠 이 규칙이 걷어낸 것: 종전 `battle.gd`/`adventure.gd` 는 드랍표가 없는 던전에서
#   `Data.items_by("consumable") + items_by("material")`(+ 한때 `food`) 풀에서 **아무 아이템이나**
#   시드 추첨해 줬다. 불 지역에서 물 드래곤 먹이가 나오고, 지역과 무관한 재료가 쏟아지던 원인이다.

## 이 인벤 키가 그 지역의 탐험 드랍으로 **나올 수 있는가**. 테스트가 화이트리스트를 증명하는 데 쓴다.
## (런타임 게이트가 아니라 검증용 술어다 — 실제 드랍은 위 roll_* 들만 만든다.)
## monster_table_doc/monster_id 를 주면 **그 몬스터의 고유 드랍**도 허용 목록에 포함한다.
static func is_allowed(key: String, stage: Dictionary, item_defs: Dictionary,
		_table: Dictionary, hero := false, mode := "",
		monster_doc: Dictionary = {}, monster_id := 0) -> bool:
	if key == "":
		return false
	var m := mode if mode != "" else (MODE_HERO if hero else MODE_NORMAL)
	if monster_keys(monster_doc, monster_id).has(key):
		return true
	if key.begins_with(EggGacha.KEY_PREFIX):
		return egg_pool(stage, hero).has(EggGacha.dragon_of(key)) \
			or (hero and egg_pool(stage, true, true).has(EggGacha.dragon_of(key)))
	if not Gem.parse_item_key(key).is_empty():
		return true                                    # 일반 젬 · 전 지역 공통
	if Equipment.parse_item_key(key) != "":
		return true                                    # 장비/아티팩트 · 전 지역 공통
	if food_pool(item_defs, stage.get("element", "")).has(key):
		return true
	if key == essence_of(item_defs, stage.get("element", "")):
		return true
	# 특수 드랍은 **그 난이도의 표**에 있어야 한다 — 다른 난이도 표에만 있으면 불허다.
	for d in special_table(stage, m):
		var dp: Dictionary = d
		if String(dp.get("kind", "item")) == "skill_scroll":
			for lv in _levels_of(dp):
				if Loadout.item_key(int(dp.get("skill", 0)), int(lv)) == key:
					return true
		elif String(dp.get("item", dp.get("key", ""))) == key:
			return true
	return false

# --- 탐험 드래곤 알 드롭 ----------------------------------------------------
#
# 원작에 실재한다 — `stringsData_KR <AdventureResultEgg>` = "%1$s의 알" 이고
# `AdventureRewardLayer` 의 셀 타입 strcmp 분기에 **`EGG`** 가 있다(포팅 카드 §5).
# 다만 **무엇이 얼마나 나오는가는 서버 소유였다**(`initJsonReward` 가 파싱하던 키는
# `reward`/`cnt`/`rarity`/`option`/`belong` 뿐 — 확률표가 클라에 없다). 그래서 확률은
# `data/drops.json` `egg` 블록(자작 튜닝 노브)에 두고, **후보 목록만 원작 데이터로 고정**한다.
#
# 사용자 확정(2026-07-30):
#   · 후보 = **그 탐험지 팝업에 등재된 드래곤**(`stages.json` `dragons[]`) 뿐.
#     그 목록은 원작 `WorldMapPopupLayer::setDragonImage` 가 그리던 것과 같은 데이터다.
#   · `hero: true`(팝업의 **H 뱃지** = `info_hero_dragon_frame`)인 드래곤은
#     **영웅 난이도에서만**, 그것도 **희귀 드롭**.
#   · 드롭 지점 = **일반 몬스터 처치**와 **보스 처치** 둘 다.
#
# 반환은 `EggGacha` 소유 규약인 **가상 인벤 키 `egg:<드래곤id>`** 다(items.json 에 복제하지 않는다).

## 그 스테이지에서 나올 수 있는 드래곤 id 목록.
##   hero=false → `hero` 플래그가 없는 드래곤만
##   hero=true  → 전부(H 포함). H 만 따로 뽑고 싶으면 `hero_only`.
## ⚠️ 팝업이 H 뱃지를 강제 해제하는 특수 지역(6 해골요새 · 8 혼돈의 틈새 —
##   `worldmap.gd::_build_dragon_row` 의 `special`)에서는 hero 항목이 없으므로 그대로 동작한다.
static func egg_pool(stage: Dictionary, hero: bool, hero_only := false) -> Array:
	var out: Array = []
	for d in (stage.get("dragons", []) as Array):
		var did := int((d as Dictionary).get("id", 0))
		if did <= 0:
			continue
		var is_h := bool((d as Dictionary).get("hero", false))
		if is_h and not hero:
			continue                       # H 는 영웅 난이도 전용
		if hero_only != is_h:
			continue
		out.append(did)
	out.sort()                             # 결정적 순서(같은 시드 → 같은 결과)
	return out

## 알 1회 판정 → "egg:<id>" 또는 "".
##   table  = data/drops.json
##   stage  = data/stages.json 의 그 스테이지(= 월드맵 팝업이 읽는 것과 같은 레코드)
##   source = SOURCE_NORMAL | SOURCE_BOSS (보물상자는 알을 주지 않는다 — 사용자 확정)
##   hero   = 영웅 난이도인가
## H 드래곤을 먼저 굴리고(희귀), 떨어지면 일반 후보를 굴린다.
static func roll_egg(table: Dictionary, stage: Dictionary, source: String,
		rng: RandomNumberGenerator, hero := false) -> String:
	var cfg: Dictionary = table.get("egg", {})
	if cfg.is_empty():
		return ""
	# 영웅 난이도 H 드래곤 — 희귀 확률로 먼저.
	if hero:
		var hp := egg_pool(stage, true, true)
		if not hp.is_empty():
			var hc := float((cfg.get("hero_chance", {}) as Dictionary).get(source, 0.0))
			if rng.randf() < hc:
				return EggGacha.KEY_PREFIX + str(hp[rng.randi() % hp.size()])
	var pool := egg_pool(stage, hero)
	if pool.is_empty():
		return ""
	if rng.randf() >= float((cfg.get("chance", {}) as Dictionary).get(source, 0.0)):
		return ""
	return EggGacha.KEY_PREFIX + str(pool[rng.randi() % pool.size()])

# --- 탐험 드롭 --------------------------------------------------------------

## 탐험 1회 판정 → 인벤 키("gem:…" / "equip:…") 또는 "" (드롭 없음).
##   level       = 그 지역/스테이지의 레벨(고레벨일수록 좋다)
##   source      = SOURCE_NORMAL | SOURCE_CHEST | SOURCE_BOSS
##   equip_table = data/equipment.json — 종류별 등급 수가 달라서(부적·석류 6등급) 클램프에 필요
##   kades       = 카데스의 공간(유타칸 전설 모드)인가 — 아티팩트가 나올 수 있는 유일한 조건
##   field       = 기본 필드 id(1~15). 아티팩트 종류가 던전마다 다르다(위키 §2) → 배정표 조회용.
##                 0 이면 6종 균등(폴백).
##   artifact_mult = 아티팩트 확률 배수(각성스킬 17 구드라의 가호 = 1.5). 1.0 이면 영향 없음.
static func roll_exploration(table: Dictionary, level: int, source: String,
		equip_table: Dictionary, rng: RandomNumberGenerator, kades := false,
		field := 0, artifact_mult := 1.0) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var src: Dictionary = (exp_t.get("sources", {}) as Dictionary).get(source, {})
	if src.is_empty():
		return ""
	# 카데스: 아티팩트를 먼저 굴린다(이곳의 주 목적 — 위키 §2).
	if kades:
		var a := roll_artifact(table, source, rng, field, artifact_mult, equip_table)
		if a != "":
			return a
	if rng.randf() >= float(src.get("chance", 0.0)):
		return ""
	var quality := int(src.get("quality", 0))
	if kades:
		quality += int((table.get("kades", {}) as Dictionary).get("quality_bonus", 0))
	return _roll_gem_or_equip(table, level, quality, equip_table, rng)

## 젬/장비 중 하나를 뽑는다(가중치 = exploration.kind_weights).
static func _roll_gem_or_equip(table: Dictionary, level: int, quality: int,
		equip_table: Dictionary, rng: RandomNumberGenerator) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var kw: Dictionary = exp_t.get("kind_weights", {"gem": 50, "equip": 50})
	var gw := float(kw.get("gem", 50))
	var total := gw + float(kw.get("equip", 50))
	if total <= 0.0:
		return ""
	if rng.randf() * total < gw:
		return _roll_gem(table, level, quality, rng)
	return _roll_equip(table, level, quality, equip_table, rng)

static func _roll_gem(table: Dictionary, level: int, quality: int,
		rng: RandomNumberGenerator) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var pool: Array = exp_t.get("gem_pool", [])
	if pool.is_empty():
		return ""
	var cfg: Dictionary = exp_t.get("gem_tier", {})
	var tier := _band_roll(cfg, level, quality, rng)
	return Gem.item_key(String(pool[rng.randi() % pool.size()]), tier)

static func _roll_equip(table: Dictionary, level: int, quality: int,
		equip_table: Dictionary, rng: RandomNumberGenerator) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var kinds: Array = exp_t.get("equip_kinds", [])
	if kinds.is_empty():
		return ""
	var cfg: Dictionary = exp_t.get("equip_grade", {})
	var kind := String(kinds[rng.randi() % kinds.size()])
	var grade := _band_roll(cfg, level, quality / 2, rng)
	# ⚠️ 장비는 **종류마다 등급 수가 다르다** — 깃털·발톱은 7등급이지만 부적과
	#   묘안석/흑요석/백금석은 6등급이다(위키 §2.1: 아만타 부적 없음 + 석류는 '작은~전설의' 6단).
	#   상한을 넘기면 카탈로그에 없는 키(`basic:흑요석:6`)가 만들어진다 → 종류별로 클램프.
	# 희귀도(원작 서버 `rarity`)는 획득 시 정해진다 — 드롭표 = 일반70:레어20:유니크8:에픽2.
	return Equipment.item_key("basic:%s:%d" % [kind, clamp_grade(equip_table, kind, grade)],
		Equipment.roll_instance("drop", rng, equip_table))

## 그 종류가 실제로 가진 최고 등급으로 클램프. 정의가 없으면 그대로 둔다.
static func clamp_grade(equip_table: Dictionary, kind: String, grade: int) -> int:
	var gr: Array = (equip_table.get("basic", {}) as Dictionary).get(kind, {}).get("grades", [])
	if gr.is_empty():
		return maxi(0, grade)
	return clampi(grade, 0, gr.size() - 1)

## 지역 레벨 + 품질 보정 → 밴드 내 랜덤 정수. cfg = {per_level, band, min, max}.
static func _band_roll(cfg: Dictionary, level: int, quality: int,
		rng: RandomNumberGenerator) -> int:
	var center := float(level) * float(cfg.get("per_level", 0.1)) + float(quality)
	var band := int(cfg.get("band", 1))
	var lo := int(floor(center)) - band
	var hi := int(floor(center)) + band
	var vmin := int(cfg.get("min", 0))
	var vmax := int(cfg.get("max", 6))
	lo = clampi(lo, vmin, vmax)
	hi = clampi(hi, lo, vmax)
	return rng.randi_range(lo, hi)

# --- 아티팩트(카데스의 공간 전용) -------------------------------------------

## 아티팩트 1개 판정 → "equip:artifact:<종류>:<등급>" 또는 "".
## ⚠️ 카데스의 공간 밖에서는 절대 나오지 않는다(사용자 확정 + 위키 etc.pdf §2.2).
## field = 기본 필드 id. 위키 §2 "각 지역마다 나오는 아티펙트가 다르다" → 던전별 4종 배정표
##   (`kades.artifact_by_dungeon`, 자작). 배정이 없는 필드는 6종 균등.
## artifact_mult = 확률 배수. 각성스킬 17 '구드라의 가호'(전설 난이도 지역에서 아티팩트 획득
##   확률 50% 증가) → 1.5. 확률은 1.0 을 넘지 않게 자른다.
## `equip_table` = data/equipment.json — 희귀도·옵션을 굴리는 데 쓴다(2026-08-01 추가).
##   빈 dict 를 넘기면 메타 없이(= 일반, 옵션 0개) 나온다 — 옛 호출부 호환용이다.
static func roll_artifact(table: Dictionary, source: String,
		rng: RandomNumberGenerator, field := 0, artifact_mult := 1.0,
		equip_table: Dictionary = {}) -> String:
	var kd: Dictionary = table.get("kades", {})
	var ch: Dictionary = kd.get("artifact_chance", {})
	if rng.randf() >= clampf(float(ch.get(source, 0.0)) * artifact_mult, 0.0, 1.0):
		return ""
	var types := artifact_types_for(table, field)
	if types.is_empty():
		return ""
	var grade := _weighted_index(kd.get("artifact_grade", {}).get("weights", [1]), rng)
	# 🟢 2026-08-01: 아티팩트도 **희귀도·부가옵션을 달고 나온다**.
	#   종전엔 메타 없이 굴려 항상 일반(옵션 0개)이었고, 그래서 강화도 옵션 재설정도
	#   대상이 되지 못했다 — 위키 §2.4 가 "보통 아티팩트로 관통 100을 맞춘다"고 못 박는
	#   축이 통째로 죽어 있었다. 원작에서도 아티팩트는 같은 `Equip` 이라 `rarity`/`option`
	#   필드를 그대로 갖는다(`AccountManager` 파싱 키 6종에 종류 구분이 없다).
	#   표는 일반 장비와 같은 `drop`(equipment.json option.rarity_rolls).
	var kind := String(types[rng.randi() % types.size()])
	if equip_table.is_empty():
		return Equipment.item_key("artifact:%s:%d" % [kind, grade])
	return Equipment.item_key("artifact:%s:%d" % [kind, grade],
		Equipment.roll_instance("drop", rng, equip_table))

## 그 던전에서 나오는 아티팩트 종류 목록. 배정표에 없으면 전체 6종.
static func artifact_types_for(table: Dictionary, field: int) -> Array:
	var kd: Dictionary = table.get("kades", {})
	var by: Dictionary = kd.get("artifact_by_dungeon", {})
	var lst: Array = by.get(str(field), [])
	return lst if not lst.is_empty() else (kd.get("artifact_types", []) as Array)

# --- 상점(골드) -------------------------------------------------------------

## 상점 젬 재고 → [{key, price}]. 낮은 티어만(사용자 확정).
static func shop_gems(table: Dictionary) -> Array:
	var sh: Dictionary = table.get("shop", {})
	var pr: Dictionary = sh.get("gem_price", {})
	var out: Array = []
	for name in (sh.get("gem_pool", []) as Array):
		for t in (sh.get("gem_tiers", []) as Array):
			out.append({"key": Gem.item_key(String(name), int(t)),
				"price": int(pr.get("base", 0)) + int(t) * int(pr.get("per_tier", 0))})
	return out

## 상점 장비 재고 → [{key, price}]. 낮은 등급만.
static func shop_equips(table: Dictionary) -> Array:
	var sh: Dictionary = table.get("shop", {})
	var pr: Dictionary = sh.get("equip_price", {})
	var out: Array = []
	for kind in (sh.get("equip_kinds", []) as Array):
		for g in (sh.get("equip_grades", []) as Array):
			# 상점 골드 구매는 **일반 100%**(사용자 확정) → 메타 없는 맨 키 = 옵션 0개.
			out.append({"key": Equipment.item_key("basic:%s:%d" % [String(kind), int(g)]),
				"price": int(pr.get("base", 0)) + int(g) * int(pr.get("per_grade", 0))})
	return out

# --- 가챠(다이아) -----------------------------------------------------------

## 젬 가챠 1회 → 인벤 키. 위키: "높은 등급의 일반 젬"(item.pdf §9.3).
## 젬 뽑기 공용 롤러 — 분류(`categories`)로 후보를 뽑고 티어 범위에서 고른다.
## 후보를 이름 목록으로 박지 않고 **분류로** 고르는 이유: 젬 정의의 단일 출처는
## `data/gems.json` 이다(§8.1). 새 젬이 추가되면 표를 안 고쳐도 따라온다.
## `tier_max = -1` 은 "그 젬의 최대 티어"(혼성 19단계 / 소울 10단계).
static func roll_gem_from(cfg: Dictionary, gem_table: Dictionary, rng: RandomNumberGenerator) -> String:
	var cats: Array = cfg.get("categories", [])
	var names: Array = []
	for n in (gem_table.get("gems", {}) as Dictionary):
		if cats.has(String((gem_table["gems"][n] as Dictionary).get("category", ""))):
			names.append(String(n))
	if names.is_empty():
		return ""
	names.sort()                                  # 결정적 입력(같은 시드 → 같은 결과)
	var nm := String(names[rng.randi() % names.size()])
	var mx := Gem.max_tier(nm, gem_table)
	var lo := clampi(int(cfg.get("tier_min", 0)), 0, maxi(0, mx))
	var raw_hi := int(cfg.get("tier_max", -1))
	var hi := mx if raw_hi < 0 else clampi(raw_hi, lo, mx)
	return Gem.item_key(nm, rng.randi_range(lo, hi))

## 다이아 젬 가챠 1회 → 인벤 키.
## 사용자 확정(2026-07-27): **혼성젬 + 샌즈젬 + 소울젬, 모든 티어**.
static func roll_gem_gacha(table: Dictionary, gem_table: Dictionary, rng: RandomNumberGenerator) -> String:
	return roll_gem_from(table.get("gacha", {}).get("gem", {}), gem_table, rng)

# --- 점술집 골드 뽑기(원작 <MagicTitleSlot>) = 잭팟 ---------------------------
#
# 원작 `SlotLayer::ResponseSlot`(decomp :897):
#     if (r1 == r2 && r1 == r3) { 결과 = r1; addItem/addEgg(결과, cnt) }
#     else                      { 결과 = 0; }            // 꽝
# 릴 3개가 **전부 같을 때만** 그 아이템을 준다. 릴 번호(r1/r2/r3)는 서버가 정해서 보냈고
# 클라는 비교만 했다 → 우리도 **결과를 먼저 굴리고**(win_rate) 릴을 거기 맞춘다.
# 꽝일 때는 세 릴이 전부 같아지지 않게 보정한다(원작 서버가 그랬듯이).
#
# 10연속(`requestSlotTen` → `game_fortune/generate_reels_v2.hb`)도 같은 판정을 10번 돌리고
# 당첨분만 `ShowGetItemDetailLayer` 로 공개한다 → `roll_slot_many`.
#
# 릴 품목·확률·가격은 서버 유실 → `data/drops.json` `slot`(사용자 확정 2026-07-30).

## 릴에 박히는 품목표. **순서 고정**(같은 데이터 → 같은 배열) — render 는 이 배열의
## 인덱스로 릴을 그리므로 순서가 흔들리면 안 된다.
## 반환: [{kind:"gem"|"item", key, gem_name?, tier?, weight}]
static func slot_faces(table: Dictionary, gem_table: Dictionary) -> Array:
	var cfg: Dictionary = table.get("slot", {})
	var gcfg: Dictionary = cfg.get("gem", {})
	var w: Dictionary = cfg.get("weights", {})
	var tier := int(gcfg.get("tier_min", 0))
	var faces: Array = []
	# 젬은 이름을 박지 않고 **분류로** 고른다 — 젬 정의의 단일 출처는 data/gems.json(§8.1).
	for c in (gcfg.get("categories", []) as Array):
		var names: Array = []
		for n in (gem_table.get("gems", {}) as Dictionary):
			if String((gem_table["gems"][n] as Dictionary).get("category", "")) == String(c):
				names.append(String(n))
		if names.is_empty():
			continue
		names.sort()                                   # 결정적 순서
		var each := float(w.get(String(c), 0.0)) / float(names.size())
		for n in names:
			var t := clampi(tier, 0, maxi(0, Gem.max_tier(String(n), gem_table)))
			faces.append({"kind": "gem", "gem_name": String(n), "tier": t,
				"key": Gem.item_key(String(n), t), "weight": each})
	for it in (cfg.get("items", []) as Array):
		faces.append({"kind": "item", "key": String(it), "weight": float(w.get(String(it), 0.0))})
	return faces

## 가중치 추첨 → faces 인덱스. 가중치가 전부 0이면 균등.
static func _pick_face(faces: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for f in faces:
		total += maxf(0.0, float((f as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return rng.randi() % faces.size()
	var r := rng.randf() * total
	for i in faces.size():
		r -= maxf(0.0, float((faces[i] as Dictionary).get("weight", 0.0)))
		if r <= 0.0:
			return i
	return faces.size() - 1

## 당첨 얼굴 → 실제 지급 인벤 키. 젬은 티어를 범위에서 굴린다(tier_max = -1 → 그 젬의 최대).
static func _slot_prize_key(face: Dictionary, cfg: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator) -> String:
	if String(face.get("kind", "")) != "gem":
		return String(face.get("key", ""))
	var gcfg: Dictionary = cfg.get("gem", {})
	var nm := String(face.get("gem_name", ""))
	var mx := Gem.max_tier(nm, gem_table)
	var lo := clampi(int(gcfg.get("tier_min", 0)), 0, maxi(0, mx))
	var raw_hi := int(gcfg.get("tier_max", -1))
	var hi := mx if raw_hi < 0 else clampi(raw_hi, lo, mx)
	return Gem.item_key(nm, rng.randi_range(lo, hi))

## 뽑기 1회. 반환 = {win, reels:[i,j,k](faces 인덱스), key, count}.
## `win` 이면 reels 3개가 같고 `key` 를 `count` 개 지급한다. 꽝이면 key = "".
static func roll_slot(table: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = table.get("slot", {})
	var faces := slot_faces(table, gem_table)
	var out := {"win": false, "reels": [0, 0, 0], "key": "", "count": 0}
	if faces.is_empty():
		return out
	if rng.randf() < float(cfg.get("win_rate", 0.0)):
		var i := _pick_face(faces, rng)
		out["win"] = true
		out["reels"] = [i, i, i]
		out["key"] = _slot_prize_key(faces[i], cfg, gem_table, rng)
		# 원작은 서버가 보낸 `cnt` 개를 줬다(유실). 사용자 확정: **1개**.
		out["count"] = 1
		return out
	var r: Array = [_pick_face(faces, rng), _pick_face(faces, rng), _pick_face(faces, rng)]
	if faces.size() > 1 and r[0] == r[1] and r[1] == r[2]:
		# 꽝인데 세 개가 같아져 버렸다 → 마지막 릴을 다른 것으로 민다.
		r[2] = (int(r[2]) + 1 + rng.randi() % (faces.size() - 1)) % faces.size()
	out["reels"] = r
	return out

## 뽑기 n 회(원작 10연속) → 결과 배열. 각 회차는 독립 시행이다.
static func roll_slot_many(table: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in maxi(0, n):
		out.append(roll_slot(table, gem_table, rng))
	return out

## 진귀한 보석 상자(`jem_random`) 개봉 → 인벤 키.
## 위키 item.pdf §9.3 "높은 등급의 **일반 젬**" — 가챠와 표가 다르다.
static func roll_gem_box(table: Dictionary, gem_table: Dictionary, rng: RandomNumberGenerator) -> String:
	return roll_gem_from(table.get("box", {}).get("jem_random", {}), gem_table, rng)

## 같은 상자를 n 번 연속 개봉 → 인벤 키 배열(뽑힌 순서). 빈 결과 회차는 건너뛴다.
## ⚠️ 원작에 '10회 사용'은 없다 — 사용자 요청(2026-07-30)으로 우리가 더한 편의 기능이고,
##   1회 개봉을 **독립 시행으로 n 번 반복**한다(`EggGacha.roll_many` 와 같은 규약).
static func roll_gem_box_many(table: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in maxi(0, n):
		var k := roll_gem_box(table, gem_table, rng)
		if k != "":
			out.append(k)
	return out

## 구현 대상 전용 장비 목록(아이콘 보유 + 대상 드래곤 확정). `Equipment.event_pool` 과 같은 규약.
static func _exclusive_pool(equip_table: Dictionary) -> Array:
	var out: Array = []
	for x in (equip_table.get("exclusive", {}).get("list", []) as Array):
		var item := x as Dictionary
		if not bool(item.get("implemented", false)):
			continue
		if bool(item.get("gacha_excluded", false)):
			continue
		out.append(item)
	return out

## 구현 대상 특수 장비 목록. 항목은 `{family, item}` — 카탈로그 키를 정확히 복원한다.
static func _special_pool(equip_table: Dictionary) -> Array:
	var out: Array = []
	for family in (equip_table.get("special", {}) as Dictionary):
		var family_def: Dictionary = equip_table["special"][family]
		if not bool(family_def.get("implemented", false)):
			continue
		for item in (family_def.get("items", []) as Array):
			out.append({"family": String(family), "item": item})
	return out



## 장신구 뽑기 1회 → 인벤 키. **이벤트 장비가 나오는 유일한 경로**(사용자 확정).
## equip_table = data/equipment.json (이벤트 목록을 여기서 읽는다 — 정의 단일 출처 §8.1).
##
## grade = 상품 등급. 원작 상품이 3종이고(위키 item.pdf §3 · `상점_장비.webp`) 값이 다르므로
## **풀도 달라야 한다** — 종전엔 shop.json 의 `grade` 를 아무도 안 읽어 셋이 같은 결과였다(🔴).
##   "normal" 일반 장신구 뽑기(5000골드) — 하위 등급 일반 장비만, 희귀도 일반 100%
##   "high"   고급 장신구 뽑기(15다이아) — 상위 등급 일반 장비 + 이벤트 장비, 레어~에픽
##   "only" 전용 장신구 뽑기(30다이아) — 결과는 전용 장비. 🟢 2026-07-31 복구(아이콘 확보).
##   "special" 특수장비 뽑기(100다이아) — 해골요새·발록·피오드 특수 장비 12종.
## 표는 `data/drops.json` `gacha.equip.grades[grade]`. 없는 등급이면 빈 문자열(= 지급 없음).
static func roll_equip_gacha(table: Dictionary, equip_table: Dictionary,
		rng: RandomNumberGenerator, grade_id: String = "high") -> String:
	var eq: Dictionary = table.get("gacha", {}).get("equip", {})
	var g: Dictionary = (eq.get("grades", {}) as Dictionary).get(grade_id, {})
	if g.is_empty():
		return ""
	# 아이콘 미보유 장비는 뽑기 풀에서 빠진다(Equipment.event_pool — 판정은 icon_map 자동).
	var events: Array = Equipment.event_pool(equip_table)
	var ew := float(g.get("event_weight", 50)) if not events.is_empty() else 0.0
	var bw := float(g.get("basic_weight", 50))
	# 전용 장신구 뽑기(`only`) — 결과가 전용 장비다. 주 능력치가 없고 대응 드래곤 전용이라
	# 일반/이벤트 풀과 섞이지 않는다(사용자 확정 2026-07-31, data/drops.json `grades.only`).
	var excl: Array = _exclusive_pool(equip_table)
	var xw := float(g.get("exclusive_weight", 0)) if not excl.is_empty() else 0.0
	# 특수장비 뽑기(`special`) — 구현·아이콘이 확보된 특수 장비만 별도 풀에서 뽑는다.
	var special: Array = _special_pool(equip_table)
	var sw := float(g.get("special_weight", 0)) if not special.is_empty() else 0.0
	var total := ew + bw + xw + sw
	if total <= 0.0:
		return ""
	var pick := rng.randf() * total
	if sw > 0.0 and pick < sw:
		var inst_sp := Equipment.roll_instance(String(g.get("rarity_source", "shop_gacha")),
			rng, equip_table)
		var sp: Dictionary = special[rng.randi() % special.size()]
		var spi: Dictionary = sp["item"]
		return Equipment.item_key("special:%s:%s" % [String(sp["family"]),
			String(spi.get("name", ""))], inst_sp)
	pick -= sw
	if xw > 0.0 and pick < xw:
		var inst0 := Equipment.roll_instance(String(g.get("rarity_source", "shop_gacha")),
			rng, equip_table)
		var x: Dictionary = excl[rng.randi() % excl.size()]
		return Equipment.item_key("exclusive:%s" % String(x.get("name", "")), inst0)
	pick -= xw
	# 희귀도표(사용자 확정 2026-07-29) = 골드 상품 일반100 / 다이아 상품 레어60:유니크30:에픽10.
	var inst := Equipment.roll_instance(String(g.get("rarity_source", "shop_gacha")), rng, equip_table)
	if pick < ew:
		var e: Dictionary = events[rng.randi() % events.size()]
		return Equipment.item_key("event:%s" % String(e.get("name", "")), inst)
	var kinds: Array = table.get("exploration", {}).get("equip_kinds", [])
	var grades: Array = g.get("basic_grades", [0])
	# 위 grades 는 요청 등급이고, 종류마다 최고 등급이 다르다(깃털·발톱 0~6 / 나머지 0~5).
	# 아래 clamp_grade 가 그 종류의 상한으로 눌러 준다.
	if kinds.is_empty():
		return ""
	var kind := String(kinds[rng.randi() % kinds.size()])
	var grade := int(grades[rng.randi() % grades.size()])
	# 부적·석류처럼 등급 수가 적은 종류는 상한으로 클램프한다(아만타 부적은 없다).
	return Equipment.item_key("basic:%s:%d" % [kind, clamp_grade(equip_table, kind, grade)], inst)

# --- 공용 -------------------------------------------------------------------

## 젬/장비 인벤 키 → 표시 이름. render 가 토스트·전리품 문구에 쓴다.
## (logic 이 문자열을 만드는 건 §8.3 위반이 아니다 — 노드/에셋을 만지지 않는다.)
static func display_name(key: String, gem_table: Dictionary, equip_table: Dictionary) -> String:
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		return Gem.display_name(String(g["name"]), int(g["tier"]), gem_table)
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		var it: Dictionary = Equipment.catalog(equip_table).get(ck, {})
		if not it.is_empty():
			return String(it.get("name", ck))
	return key

static func _weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(0.0, float(weights[i]))
		if r < acc:
			return i
	return weights.size() - 1
