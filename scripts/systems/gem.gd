# Gem(젬) — 순수 로직 계층 (§8: render/에셋 의존 없음, 헤드리스 검증 가능)
#
# 원작 근거(구조):
#   - 젬 슬롯은 3칸. Dragon 오브젝트의 this+0x158 / 0x160 / 0x168 을
#     getHpAdd·getAttAdd·getDefAdd 가 순서대로 훑는다(docs/ref/orig_code/decomp/Dragon.c:1940~2050).
#   - 젬 종류 식별자 = `Item::getTypeDetail()` 문자열. Dragon.c 에 실재하는 코드:
#       일반 HP/ATT/DEF · 혼성 ATTHP/ATTDEF/HPATT/HPDEF/DEFATT/DEFHP
#       소울 SOULHP/SOULATT/SOULDEF/SOULALL
#   - 소울젬은 flat 과 % 를 한 정수에 패킹하고 `getTypeParam() % 1000` 으로 % 를 꺼낸다
#     (Dragon.c:1974). 우리는 패킹하지 않고 data/gems.json 에서 필드를 나눠 둔다.
#
# 데이터: data/gems.json (scripts/tools/build_gems.py 가 docs/ref/wiki/gems.pdf 에서 생성).
#
# 저장 형식(UserDB dragon["gems"]):
#   {"types": ["ATT", "HP", "ALL"],                     ← 칸별 슬롯 타입(길이 SLOTS)
#    "slots": [null, {"name": "체력의 소울젬", "tier": 3}, null]}   ← 길이 SLOTS 고정, 빈 칸은 null
#   구형 A: {"slots": [{…}, {…}]}      (조밀 배열, 타입 없음) → entries() 가 뒤를 null 로 채운다
#   구형 B: 플랫 누적 {hp:…, _tier_hp:…}                      → migrate() 참조
#   슬롯 타입이 없는 구형 세이브에는 UserDB._ensure_schema 가 랜덤 부여한다.
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드 참조 금지(§8.2 단방향 의존).
class_name Gem
extends RefCounted

## 가방 설명 CSV의 공유 설명 키. 샌즈 2종은 각각 혼성/소울 계열에서 분리한다.
static func description_category(name: String, table: Dictionary) -> String:
	if name == "샌즈의 젬":
		return "sands"
	if name == "샌즈의 소울젬":
		return "sands_soul"
	return String(gem_def(name, table).get("category", ""))

const SLOTS := 3           # 원작 젬 슬롯 수(Dragon.c 3칸)
const FLAT_KEYS := ["hp", "att", "def"]
const PCT_KEYS := ["hp_pct", "att_pct", "def_pct"]
const SUB_KEYS := ["cri", "evd", "blk"]

# --- 조회 -------------------------------------------------------------------

## 젬 정의(코드/분류/티어배열). 없으면 {}.
static func gem_def(gem_name: String, table: Dictionary) -> Dictionary:
	return (table.get("gems", {}) as Dictionary).get(gem_name, {})

## 그 젬의 최대 티어 인덱스(0-base). 정의가 없으면 -1.
static func max_tier(gem_name: String, table: Dictionary) -> int:
	var tiers: Array = gem_def(gem_name, table).get("tiers", [])
	return tiers.size() - 1

## 특정 티어의 스탯 dict({hp/att/def/hp_pct/…}). 범위를 벗어나면 끝값으로 클램프.
static func tier_stats(gem_name: String, tier: int, table: Dictionary) -> Dictionary:
	var tiers: Array = gem_def(gem_name, table).get("tiers", [])
	if tiers.is_empty():
		return {}
	return tiers[clampi(tier, 0, tiers.size() - 1)]

## 장착 슬롯 목록(구형 저장분도 신형으로 정규화해서 반환).
static func slots(gems_field: Dictionary) -> Array:
	if gems_field.has("slots"):
		var out: Array = []
		for e in entries(gems_field):
			if e != null:
				out.append(e)
		return out
	return migrate(gems_field)

## 슬롯 index 그대로인 길이 SLOTS 배열. 빈 칸은 null.
## 조밀 배열로 저장된 구형은 앞에서부터 채워진 것으로 본다.
## ⚠️ `points`/`potions`(연금술) · `broken`(파손) 같은 부가 필드를 **보존**한다 —
##    여기서 {name,tier} 로만 재구성하면 강화 진행 상태가 조용히 날아간다.
static func entries(gems_field: Dictionary) -> Array:
	var out: Array = [null, null, null]
	var raw: Array = gems_field.get("slots", []) if gems_field.has("slots") else migrate(gems_field)
	for i in mini(raw.size(), SLOTS):
		var s = raw[i]
		if typeof(s) == TYPE_DICTIONARY and String((s as Dictionary).get("name", "")) != "":
			var e: Dictionary = (s as Dictionary).duplicate()
			e["name"] = String(s["name"])
			e["tier"] = int(s.get("tier", 0))
			if e.has("points"): e["points"] = int(e["points"])
			if e.has("potions"): e["potions"] = int(e["potions"])
			out[i] = e
	return out

## 구형 저장 형식 → 신형 슬롯 배열. 구형은 stat별로 `_name_<stat>` / `_tier_<stat>` 을 남겼다.
static func migrate(old: Dictionary) -> Array:
	var out: Array = []
	for stat: String in FLAT_KEYS:
		var nk: String = "_name_" + stat
		if old.has(nk):
			out.append({"name": String(old[nk]), "tier": int(old.get("_tier_" + stat, 0))})
	return out

# --- 집계 -------------------------------------------------------------------

## 장착 젬 전체의 보너스를 합산 → {"flat":{hp,att,def}, "pct":{hp,att,def}, "sub":{cri,evd,blk}}.
## pct/sub 는 퍼센트 포인트(예: 18 = +18%).
static func aggregate(gems_field: Dictionary, table: Dictionary) -> Dictionary:
	var flat := {"hp": 0, "att": 0, "def": 0}
	var pct := {"hp": 0.0, "att": 0.0, "def": 0.0}
	var sub := {"cri": 0.0, "evd": 0.0, "blk": 0.0}
	for s in slots(gems_field):
		if is_broken(s):
			continue          # 파손된 젬은 효과가 없다(복구해야 다시 붙는다)
		var t := tier_stats(String(s["name"]), int(s["tier"]), table)
		for k: String in FLAT_KEYS:
			flat[k] = int(flat[k]) + int(t.get(k, 0))
			pct[k] = float(pct[k]) + float(t.get(k + "_pct", 0))
		for k: String in SUB_KEYS:
			sub[k] = float(sub[k]) + float(t.get(k, 0))
	return {"flat": flat, "pct": pct, "sub": sub}

## 실스탯에 젬 보너스를 적용한 새 dict 반환.
## 순서 = flat 가산 → % 배수(합산된 %를 한 번에) → 부가 확률 가산.
## ASSUMPTION: 원작이 %를 flat 포함 총합에 거는지 기본치에만 거는지는 유실.
##   소울젬 툴팁("공격력 +x, 공격력 +y%")과 인플레 서술(위키 §3)에 맞춰 **flat 포함 총합**에 건다.
static func apply(stats: Dictionary, gems_field: Dictionary, table: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate()
	var agg := aggregate(gems_field, table)
	var flat: Dictionary = agg["flat"]
	var pct: Dictionary = agg["pct"]
	var sub: Dictionary = agg["sub"]
	for k in FLAT_KEYS:
		var v := float(int(out.get(k, 0)) + int(flat[k]))
		v *= 1.0 + float(pct[k]) / 100.0
		out[k] = int(round(v))
	for k in SUB_KEYS:
		out[k] = int(out.get(k, 0)) + int(round(float(sub[k])))
	return out

# --- 슬롯 타입 (원작 Dragon::getGemType) ------------------------------------
#
# 칸마다 타입이 있고 맞는 젬만 들어간다 — 원작 문자열 `CaveGemEuqipMsg2`
#   "선택한 젬과 맞는 슬롯이 없습니다." · `CaveGemEuqipMsg3` "젬 슬롯이 모두 사용 중입니다."
# 타입 **값**은 서버 유실 → 사용자 확정(2026-07-27): 부화 시 칸마다 4종 중 랜덤 1종,
#   이후 '샌즈의 비약'(items.json `gemslot_change`)으로 랜덤 재부여(`CaveBagMsg19`
#   "현재의 잼 슬롯이 랜덤으로 변경 됩니다.").
# 허용표는 data/gems.json `slot_types.accept` (= GemsPopup::setGemsList memcmp 체인).

const FALLBACK_TYPE := "ALL"      # 타입 정보가 없는 구형 세이브: 아무 젬이나 받는 만능칸

## 슬롯 타입 코드 목록(원작 0..3 순서). 표가 없으면 하드 폴백.
static func type_order(table: Dictionary) -> Array:
	var o: Array = (table.get("slot_types", {}) as Dictionary).get("order", [])
	return o if not o.is_empty() else ["ATT", "DEF", "HP", "ALL"]

## 칸별 슬롯 타입(길이 SLOTS). 없거나 짧으면 FALLBACK_TYPE 으로 채운다.
static func types(gems_field: Dictionary) -> Array:
	var out: Array = []
	var raw: Array = gems_field.get("types", [])
	for i in SLOTS:
		var t := String(raw[i]) if i < raw.size() else ""
		out.append(t if t != "" else FALLBACK_TYPE)
	return out

## 부화용 — 칸마다 4종 중 랜덤 1종. rng 를 주면 시드 고정 재현 가능(§4).
static func random_types(table: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	var order := type_order(table)
	var out: Array = []
	for _i in SLOTS:
		var k := (rng.randi() if rng != null else randi()) % order.size()
		out.append(String(order[k]))
	return out

## 슬롯 타입 배열을 교체한 새 gems 필드('샌즈의 비약').
static func set_types(gems_field: Dictionary, new_types: Array) -> Dictionary:
	var out := gems_field.duplicate(true)
	out["types"] = types({"types": new_types})     # 길이/폴백 정규화
	out["slots"] = entries(gems_field)
	return out

## 그 타입 칸에 이 젬을 넣을 수 있나. 표가 없으면 허용(폴백).
static func accepts(slot_type: String, gem_name: String, table: Dictionary) -> bool:
	var acc: Dictionary = (table.get("slot_types", {}) as Dictionary).get("accept", {})
	if acc.is_empty():
		return true
	var allow: Array = acc.get(slot_type, acc.get(FALLBACK_TYPE, []))
	return allow.has(String(gem_def(gem_name, table).get("code", "")))

## 이 젬이 들어갈 수 있는 **빈 칸** index. 없으면 -1.
## 원작 onClickGem 은 칸을 먼저 고르지만, 가방에서 장착할 때(BagPopup)는 맞는 칸을 찾는다.
static func fit_slot(gems_field: Dictionary, gem_name: String, table: Dictionary) -> int:
	var ty := types(gems_field)
	var en := entries(gems_field)
	for i in SLOTS:
		if en[i] == null and accepts(String(ty[i]), gem_name, table):
			return i
	return -1

## 칸이 꽉 찼는지(맞는 빈 칸이 없는 이유를 구분해 토스트를 고르기 위함).
static func all_full(gems_field: Dictionary) -> bool:
	for e in entries(gems_field):
		if e == null:
			return false
	return true

# --- 장착/해제/강화 ---------------------------------------------------------
#
# ⚠️ 모든 변경 API 의 index 는 **슬롯 index(0..SLOTS-1)** 다. 예전엔 조밀 배열의
#   순번이라 칸과 어긋났다 — 슬롯 타입 도입으로 칸 고정이 필수가 됐다.

## 맞는 빈 칸을 찾아 장착. 미정의 젬·맞는 칸 없음이면 {} (실패).
static func equip(gems_field: Dictionary, gem_name: String, tier: int, table: Dictionary,
		meta: Dictionary = {}) -> Dictionary:
	var slot := fit_slot(gems_field, gem_name, table)
	if slot < 0:
		return {}
	return equip_at(gems_field, slot, gem_name, tier, table, meta)

## 지정한 칸에 장착(원작 onClickGem → GemsPopup::setSelectTag(slot) 경로).
## 미정의 젬 · 칸 범위 밖 · 이미 찬 칸 · 타입 불일치면 {} (실패).
## `meta` = 가방 키가 들고 온 연금술 진행도({points, potions, broken}) — 장착해도 안 날아간다.
static func equip_at(gems_field: Dictionary, slot: int, gem_name: String, tier: int,
		table: Dictionary, meta: Dictionary = {}) -> Dictionary:
	if slot < 0 or slot >= SLOTS or gem_def(gem_name, table).is_empty():
		return {}
	var en := entries(gems_field)
	if en[slot] != null:
		return {}
	var ty := types(gems_field)
	if not accepts(String(ty[slot]), gem_name, table):
		return {}
	var e := {"name": gem_name, "tier": clampi(tier, 0, maxi(0, max_tier(gem_name, table)))}
	if int(meta.get("points", 0)) > 0:
		e["points"] = int(meta["points"])
	if int(meta.get("potions", 0)) > 0:
		e["potions"] = int(meta["potions"])
	if bool(meta.get("broken", false)):
		e["broken"] = true
	en[slot] = e
	return {"types": ty, "slots": en}

## 가방 키 그대로 장착(진행도 포함). 맞는 빈 칸이 없으면 {}.
static func equip_key(gems_field: Dictionary, key: String, table: Dictionary) -> Dictionary:
	var g := parse_item_key(key)
	if g.is_empty():
		return {}
	return equip(gems_field, String(g["name"]), int(g["tier"]), table, g)

## 그 칸을 비운 새 gems 필드.
static func unequip_at(gems_field: Dictionary, slot: int) -> Dictionary:
	var en := entries(gems_field)
	if slot >= 0 and slot < SLOTS:
		en[slot] = null
	return {"types": types(gems_field), "slots": en}

## 그 칸 젬의 티어를 1 올린 새 gems 필드. 빈 칸·이미 최대면 {} (실패).
## ⚠️ 성공률/재화 차감은 호출부 담당 — 로직은 상태 전이만 한다(성공 판정은 roll_upgrade).
static func upgrade_at(gems_field: Dictionary, slot: int, table: Dictionary) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var name := String(en[slot]["name"])
	var tier := int(en[slot]["tier"])
	if tier >= max_tier(name, table):
		return {}
	en[slot] = {"name": name, "tier": tier + 1}
	return {"types": types(gems_field), "slots": en}

# --- 강화 실패 / 다이아 복구 / 연금술 포인트 -------------------------------
#
# 원작 근거(문자열 테이블 `DV2/string/stringsData_KR.xml` + `AlchemyLayer`/`GemCraftLayer`):
#   `MagicWelcomeGem`  "젬 강화는 젬을 더 강하게 만들 수 있죠. **실패할 수도 있으니** 신중하게…"
#   `MagicGemFail`     "아쉽게 실패했네요. 다음을 기약하죠."
#   `AlchemyMsg7`      "%s을 조합하시겠습니까? [혼성젬 강화 1~%d **연금포인트 증가**]"
#   `AlchemyMsg8~11`   "연금술 포인트" / "남은 용액 투입 수" / "성공률" /
#                      "100포인트가 넘으면 성공률이 하락합니다."
#   자산: `scene/magicshop/alchemy/alchemy_point_5` `alchemy_success` · `gem_fail` · `btn_gemrepair`
#
# 사용자 확정(2026-07-27):
#   · 100 초과 = **0 으로 초기화**(위키의 '초기화' 표기를 채택)
#   · 실패율은 기억나지 않으니 **ASSUMPTION 으로 채운다** → `upgrade.success.base_pct_*`
#
# 상태는 슬롯 엔트리에 붙는다: `points`(연금포인트) `potions`(투입 횟수) `broken`(파손).
# 파손된 젬은 **효과가 0** 이고(aggregate 제외) 다이아로 복구해야 한다(`repair_diamond`).

## 파손 여부.
static func is_broken(entry) -> bool:
	return typeof(entry) == TYPE_DICTIONARY and bool((entry as Dictionary).get("broken", false))

## 그 젬의 강화 기본 성공률(%) — **용액 미투입 기준**.
## 출처: docs/ref/orig_image/shop/점술집_젬강화.pdf 의 등급별 실측표(data/gems.json `upgrade.success.by_tier_pct`).
##   1강 60% → 18강 14% 까지 위키에 값이 있다. (종전 ASSUMPTION 공식은 폐기)
## 소울젬은 그 표에 없으므로 종전 공식(90 - 7×티어)을 유지한다.
static func base_success(gem_name: String, tier: int, table: Dictionary) -> int:
	var cfg: Dictionary = (table.get("upgrade", {}) as Dictionary).get("success", {})
	var floor_pct := int(cfg.get("floor_pct", 14))
	if String(gem_def(gem_name, table).get("category", "")) == "soul":
		return clampi(int(cfg.get("base_pct_soul_start", 90)) - int(cfg.get("step_pct_soul", 7)) * tier,
			floor_pct, 100)
	# ⚠️ `tier` 는 **0-base**(1강 = 0)다 — repair_cost/display_name 과 같은 규약.
	#    위키 표는 강 번호(1~18) 키라서 +1 해서 찾는다.
	var tbl: Dictionary = cfg.get("by_tier_pct", {})
	if tbl.has(str(tier + 1)):
		return int(tbl[str(tier + 1)])
	# 표 밖(19강 이상)은 마지막 값으로 고정 — 위키 표가 18강에서 끝난다.
	return floor_pct

## 강화 1회 비용(골드). 출처: 같은 위키 표 — 3,000 + 600×(티어-1).
static func upgrade_cost(tier: int, table: Dictionary) -> int:
	# `tier` 는 0-base(1강 = 0). 위키 표는 강 번호 키.
	var tbl: Dictionary = (table.get("upgrade", {}) as Dictionary).get("cost_gold", {}).get("by_tier", {})
	if tbl.has(str(tier + 1)):
		return int(tbl[str(tier + 1)])
	return 3000 + 600 * maxi(0, tier)

## 연금술 포인트 → 성공률 가산분(%).
##
## 원작 `AlchemyLayer` 는 서버표 `gem_rate_data` 의 `{default_rate, point_rate, gold}` 로
## `성공률 = default_rate + points × point_rate` 를 계산한다(디컴프 AlchemyLayer.c :3396/:3445).
## 표 자체는 서버 소유라 유실 — `default_rate` 는 위키 실측표(`base_success`), `point_rate` 는
## 참조 영상 실측(`docs/ref/gem/혼성젬강화3.png` 2pt→60% · `혼성젬강화5(용액사용연출).png` 6pt→62%
## ⇒ 0.5 %/point)로 채웠다. 종전 1:1 가산은 그 관측과 맞지 않았다.
static func point_bonus(points: int, table: Dictionary) -> int:
	var cfg: Dictionary = (table.get("upgrade", {}) as Dictionary).get("success", {})
	return int(floor(float(maxi(0, points)) * float(cfg.get("point_rate", 0.5))))

## 실제 성공률(%) = 기본 + 연금포인트×배율, 100 상한.
## 포인트가 `alchemy_point_overflow`(100)를 **넘으면 0으로 초기화**된다(사용자 확정) —
## 그 판정은 포인트를 넣는 `add_potion()` 에서 하므로 여기서는 그냥 더한다.
static func success_chance(gems_field: Dictionary, slot: int, table: Dictionary) -> int:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return 0
	var e: Dictionary = en[slot]
	return clampi(base_success(String(e["name"]), int(e["tier"]), table)
		+ point_bonus(int(e.get("points", 0)), table), 0, 100)

## 젬 **개체 하나**의 성공률(%). 개체 = {name, tier, points?, potions?, broken?} —
## 가방 키(`item_key_to_slot`)에서 온 것이든 장착 슬롯 엔트리든 같은 모양이다.
static func inst_success_chance(inst: Dictionary, table: Dictionary) -> int:
	if inst.is_empty():
		return 0
	return clampi(base_success(String(inst.get("name", "")), int(inst.get("tier", 0)), table)
		+ point_bonus(int(inst.get("points", 0)), table), 0, 100)

## ── 개체 단위 연금술 ────────────────────────────────────────────────────────
## 원작이 **가방의 젬**을 대상으로 하므로(§docs/ref/porting/GemAlchemy.md §3) 규칙의 본체는
## 여기(개체)에 두고, 아래 `add_potion`/`roll_upgrade`(장착 슬롯 판)는 이걸 감싸기만 한다.

## 용액 투입 — 1~max 포인트 증가. 반환 {inst, gained, points, reset, uses_left} / 실패 시 {}.
## `potion` = data/gems.json `upgrade.potions` 의 한 항목.
static func inst_add_potion(inst: Dictionary, potion: Dictionary, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if inst.is_empty() or is_broken(inst):
		return {}
	var up: Dictionary = table.get("upgrade", {})
	var max_try := int(up.get("potion_max_per_try", 5))
	var e: Dictionary = inst.duplicate()
	var used := int(e.get("potions", 0))
	if used >= max_try:
		return {}                                   # 원작 "남은 용액 투입 수" 0
	var gained := 0
	if potion.has("points"):
		var lo := int((potion["points"] as Array)[0])
		var hi := int((potion["points"] as Array)[1])
		gained = lo + ((rng.randi() if rng != null else randi()) % maxi(1, hi - lo + 1))
	else:
		gained = int(potion.get("success_pct", 0))   # 초월의 용액 = 고정치
	var pts := int(e.get("points", 0)) + gained
	var reset := false
	if pts > int(up.get("alchemy_point_overflow", 100)):
		pts = 0                                     # 사용자 확정: 100 초과 → 0 초기화
		reset = true
	e["points"] = pts
	e["potions"] = used + 1
	return {"inst": e, "gained": gained, "points": pts, "reset": reset,
			"uses_left": max_try - (used + 1)}

## 강화 판정(개체) — 성공하면 티어 +1, 실패하면 **파손**(효과 0, 복구 필요).
## 성공/실패 어느 쪽이든 연금포인트·투입 횟수는 소모된다(원작 AlchemyMsg7 "사용된 재료는 사라집니다").
## 반환 {inst, ok, broken, chance} / 대상이 없거나 최대 티어면 {}.
static func inst_roll_upgrade(inst: Dictionary, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if inst.is_empty() or is_broken(inst):
		return {}
	var e: Dictionary = inst.duplicate()
	var nm := String(e.get("name", ""))
	var tier := int(e.get("tier", 0))
	if tier >= max_tier(nm, table):
		return {}
	var chance := inst_success_chance(e, table)
	var roll := (rng.randf() if rng != null else randf()) * 100.0
	var ok := roll < float(chance)
	e["points"] = 0
	e["potions"] = 0
	if ok:
		e["tier"] = tier + 1
	else:
		e["broken"] = true
	return {"inst": e, "ok": ok, "broken": not ok, "chance": chance}

## 파손 해제(개체). 다이아 차감은 호출부.
static func inst_repair(inst: Dictionary) -> Dictionary:
	if not is_broken(inst):
		return {}
	var e: Dictionary = inst.duplicate()
	e.erase("broken")
	return e

## ── 장착 슬롯 판(위 개체 함수의 얇은 래퍼) ─────────────────────────────────
## 반환에 `field`(새 gems 필드)를 실어 준다 — 기존 호출부 규약 유지.

static func add_potion(gems_field: Dictionary, slot: int, potion: Dictionary, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var r := inst_add_potion(en[slot], potion, table, rng)
	if r.is_empty():
		return {}
	en[slot] = r["inst"]
	r.erase("inst")
	r["field"] = {"types": types(gems_field), "slots": en}
	return r

static func roll_upgrade(gems_field: Dictionary, slot: int, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var r := inst_roll_upgrade(en[slot], table, rng)
	if r.is_empty():
		return {}
	en[slot] = r["inst"]
	r.erase("inst")
	r["field"] = {"types": types(gems_field), "slots": en}
	return r

# ======================= 혼성젬 제작 (원작 UpgradeGemLayer 모드 1) =======================
## 제작으로 나올 수 있는 젬 = `category == "hybrid"` 전부. 이름순으로 고정해 **재현 가능**하게
## 둔다(같은 시드 → 같은 결과, §4). 표가 비면 빈 배열.
static func hybrid_pool(table: Dictionary) -> Array:
	var out: Array = []
	for name in (table.get("gems", {}) as Dictionary):
		if String((table["gems"][name] as Dictionary).get("category", "")) == "hybrid":
			out.append(String(name))
	out.sort()
	return out


## 이 아이템이 '샌즈의 눈물'이면 그 보너스(%), 아니면 0.
## 출처 = data/gems.json `craft.sands_tear_items[]`(위키 §2.2 — 제작 시 샌즈젬 확률 +10/+20%).
static func sands_bonus(item_key: String, table: Dictionary) -> int:
	for s in ((table.get("craft", {}) as Dictionary).get("sands_tear_items", []) as Array):
		if String((s as Dictionary).get("item", "")) == item_key:
			return int((s as Dictionary).get("sands_bonus_pct", 0))
	return 0


## 제작 결과가 **샌즈의 젬**일 확률(%). 눈물을 안 넣으면 균등(1/N), 넣으면 그만큼 더한다.
## ⚠️ 위키는 "+10%/+20%" 라고만 적는다 — 기준선(균등)에 **가산**으로 읽었다.
##   나머지 확률은 다른 혼성젬들이 균등하게 나눠 가진다.
static func sands_chance(table: Dictionary, bonus_pct: int) -> int:
	var pool := hybrid_pool(table)
	if pool.is_empty():
		return 0
	var base := int(round(100.0 / float(pool.size())))
	return clampi(base + maxi(0, bonus_pct), 0, 100)


## 혼성젬 제작 — 결과 젬 이름 1개. `bonus_pct` = 투입한 샌즈의 눈물 보너스(0이면 균등).
## **순수 로직**이다 — 재료 차감·인벤 반영은 호출부(render) 몫(§8.2).
static func craft_hybrid(table: Dictionary, bonus_pct: int = 0,
		rng: RandomNumberGenerator = null) -> String:
	var pool := hybrid_pool(table)
	if pool.is_empty():
		return ""
	var sands := String((table.get("craft", {}) as Dictionary).get("sands_gem_name", "샌즈의 젬"))
	if not pool.has(sands):
		sands = ""
	var roll := int((rng.randf() if rng != null else randf()) * 100.0)
	if sands != "" and roll < sands_chance(table, bonus_pct):
		return sands
	# 샌즈 이외에서 균등 1개. (샌즈가 풀에 없으면 전체에서 균등)
	var rest: Array = pool.duplicate()
	if sands != "":
		rest.erase(sands)
	if rest.is_empty():
		return sands
	return String(rest[(rng.randi() if rng != null else randi()) % rest.size()])


## ── 젬 분해 ────────────────────────────────────────────────────────────────
## 원작 `UpgradeGemLayer::onClickDisassembleCntMenu` 이 화면에서 직접 계산하던 값들.
## 서버로는 `"<itemNo>_<cnt>"` 목록만 보냈으므로(`requestDisassemble`), 산출량 공식은
## **클라에 남아 있었다** — 디컴프 그대로 옮긴다:
##
##     dVar11 = pow(1.55, typeLevel - 1);
##     iVar3  = (int)dVar11 / 10;
##     if (iVar3 < 2) iVar3 = 1;
##
## `tier` 는 우리 규약대로 0-base(1강 = 0)라 지수는 그대로 `tier` 다.
static func disassemble_dust(tier: int, table: Dictionary) -> int:
	var dc: Dictionary = table.get("disassemble", {})
	var base := float(dc.get("dust_pow_base", 1.55))
	var div := int(dc.get("dust_div", 10))
	return maxi(1, int(pow(base, float(maxi(0, tier)))) / maxi(1, div))

## 분해 골드 = 500 × 총 개수. 원작 `confirmBtIconTextSort(this, cnt * 500)`.
## 교차검증: `docs/ref/gem/젬분해4.png` 의 1,454,000 = 500 × 2,908(슬롯 6칸 수량 합).
static func disassemble_gold(count: int, table: Dictionary) -> int:
	var dc: Dictionary = table.get("disassemble", {})
	return maxi(0, count) * int(dc.get("gold_per_gem", 500))

## 초월의 용액 산출. 13강 미만은 0, 13강부터 1개 → 18강(원형젬 수준)에서 36개.
## ⚠️ 이 곡선만은 원작 코드에 없다 — 위키 §2.2 의 양 끝값(1↔36)을 선형 보간한 자작이다.
static func disassemble_special(tier: int, table: Dictionary) -> int:
	var dc: Dictionary = table.get("disassemble", {})
	var min_t := int(dc.get("special_min_tier", 13))
	var lvl := tier + 1                              # 강 번호(1-base)
	if lvl < min_t:
		return 0
	var lo := int(dc.get("special_min", 1))
	var hi := int(dc.get("special_max", 36))
	var span := maxi(1, 18 - min_t)
	return clampi(lo + int(round(float(hi - lo) * float(lvl - min_t) / float(span))), lo, hi)

## 젬 이름 → 마법가루 종류. 공격=붉은 / 방어=푸른 / 체력=노란(위키 gems.pdf §2.2).
static func dust_key_for(gem_name: String) -> String:
	if "방어" in gem_name:
		return "def_powder"
	if "체력" in gem_name:
		return "hp_powder"
	return "att_powder"


## 파손 복구 다이아 — 위키 §2.2 표(18단계, 값이 정확히 단계+1). 이름이 우리 `shapes` 와
## 다르므로(짱돌/삼각젬 … vs 자갈/삼각형 …) **순서(index)** 로 맞춘다.
static func repair_cost(tier: int, table: Dictionary) -> int:
	var tbl: Dictionary = (table.get("upgrade", {}) as Dictionary).get("repair_diamond", {})
	var vals: Array = tbl.values()
	if vals.is_empty():
		return tier + 1
	return int(vals[clampi(tier, 0, vals.size() - 1)])

## 파손 해제(다이아 차감은 호출부). 반환 새 gems 필드 / 대상 없으면 {}.
static func repair(gems_field: Dictionary, slot: int) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or not is_broken(en[slot]):
		return {}
	var e: Dictionary = (en[slot] as Dictionary).duplicate()
	e.erase("broken")
	en[slot] = e
	return {"types": types(gems_field), "slots": en}

## 혼성젬 → 소울젬 승급(원작 위키 §2.2: 최대 티어에서 100만골드 + 젬가루).
## 승급 대상 코드는 data/gems.json 의 promote_to. 조건 미충족이면 {}.
## 승급 후에도 **같은 칸**에 남는다 — 소울젬이 그 칸 타입에 안 맞으면 승급 불가(원작 허용표).
static func promote_at(gems_field: Dictionary, slot: int, table: Dictionary) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var name := String(en[slot]["name"])
	var gd := gem_def(name, table)
	var to_code := String(gd.get("promote_to", ""))
	if to_code == "":
		return {}
	if int(en[slot]["tier"]) < max_tier(name, table):
		return {}        # 원형(최대 티어)에서만 승급
	var to_name := name_of_code(to_code, table)
	if to_name == "":
		return {}
	if not accepts(String(types(gems_field)[slot]), to_name, table):
		return {}
	en[slot] = {"name": to_name, "tier": 0}
	return {"types": types(gems_field), "slots": en}

# --- 표시 이름 / 효과 문구 -------------------------------------------------
#
# 원작 이름 양식(사용자 확정 2026-07-27):
#   일반·혼성젬 = "<젬 종류> +<능력치 상승량>"   예) `체력의 젬 +28` · `체공젬 +36`
#   소울젬      = "<종류>의 소울젬 +<단계>"      예) `공격의 소울젬 +3`  (단계 1~10)
# ⚠️ 예전엔 모양 이름을 붙여 "공격의 젬 [삼각형]" 으로 찍고 있었다 — 모양은 위키의
#   **아이콘 인덱스**일 뿐 이름이 아니다. 모양은 강화 단계 표기(`shape_label`)로만 쓴다.

## 그 젬의 **주 능력** 스탯 키. 위키 §2.2 "능력치 상승폭 역시 앞의 이름의 능력치가 더 크다"
## → 원작 typeDetail 코드의 앞 스탯이 주 능력이다(HPATT=체공 → hp).
## ALL(샌즈의 젬)은 hp/att/def 를 함께 올리는데 티어표에서 hp 가 주 수치다.
static func primary_stat(code: String) -> String:
	var c := code.substr(4) if code.begins_with("SOUL") else code
	if c.begins_with("HP"):
		return "hp"
	if c.begins_with("ATT"):
		return "att"
	if c.begins_with("DEF"):
		return "def"
	return "hp"

## 인게임 표시 이름(위 양식). 정의가 없으면 이름만 돌려준다.
static func display_name(gem_name: String, tier: int, table: Dictionary) -> String:
	var gd := gem_def(gem_name, table)
	if gd.is_empty():
		return gem_name
	if String(gd.get("category", "")) == "soul":
		return "%s +%d" % [gem_name, tier + 1]       # 소울젬은 단계(1~10)
	var t := tier_stats(gem_name, tier, table)
	return "%s +%d" % [gem_name, int(t.get(primary_stat(String(gd.get("code", ""))), 0))]

## 강화 단계 표기. 일반·혼성은 모양 이름(자갈→…→원형), 소울젬은 "N단계".
## 근거: 위키 §2.1 "스텟을 얼마만큼 상승시키는가에 따라 모양이 전부 다르다" + 모양 19종 목록.
static func shape_label(gem_name: String, tier: int, table: Dictionary) -> String:
	var gd := gem_def(gem_name, table)
	if String(gd.get("category", "")) == "soul":
		return "%d단계" % (tier + 1)
	var shapes: Array = gd.get("shapes", [])
	return String(shapes[tier]) if tier >= 0 and tier < shapes.size() else "%d단계" % (tier + 1)

## 스탯키 → 위키 툴팁 표기 한글명.
const STAT_KR := {
	"hp": "체력", "att": "공격력", "def": "방어력",
	"hp_pct": "체력", "att_pct": "공격력", "def_pct": "방어력",
	"cri": "크리티컬 확률", "evd": "회피율", "blk": "방어율",
}

## 효과 문구 — 위키 gems.pdf 툴팁과 같은 순서/표기.
##   예) "체력 +28" · "체력 +36, 공격력 +4" · "공격력 +28, 공격력 +5%, 크리티컬 확률 +1%"
static func effect_text(gem_name: String, tier: int, table: Dictionary) -> String:
	var t := tier_stats(gem_name, tier, table)
	var parts: PackedStringArray = []
	for k: String in FLAT_KEYS:
		if int(t.get(k, 0)) != 0:
			parts.append("%s +%d" % [String(STAT_KR[k]), int(t[k])])
	for k2: String in PCT_KEYS:
		if int(t.get(k2, 0)) != 0:
			parts.append("%s +%d%%" % [String(STAT_KR[k2]), int(t[k2])])
	for k3: String in SUB_KEYS:
		if int(t.get(k3, 0)) != 0:
			parts.append("%s +%d%%" % [String(STAT_KR[k3]), int(t[k3])])
	return ", ".join(parts)

## typeDetail 코드(SOULHP 등) → 젬 이름. 없으면 "".
static func name_of_code(code: String, table: Dictionary) -> String:
	for n in (table.get("gems", {}) as Dictionary):
		if String((table["gems"][n] as Dictionary).get("code", "")) == code:
			return String(n)
	return ""

# --- 인벤토리 아이템 키 -----------------------------------------------------
#
# 원작 가방에는 **GEM 탭**이 있고 보유 젬 목록에서 골라 장착한다
# (`BagPopup.c:9192 "GEM"` · `GemsPopup::setGemsList` + CCTableView, `item/gem.img_plist`).
# 젬은 (종류 × 티어) 마다 다른 아이템이므로 items.json 에 230행을 복제하지 않고
# **가상 키**로 보유한다 — 정의는 이미 data/gems.json 에 있다(§8.1 data 계층 단일 출처).
#
#     "gem:체력의 젬:0"     ← ITEM_PREFIX + 젬 이름 + ":" + 티어(0-base)
#
# UserDB.inventory() 는 key→개수 평면 dict 이라 추가 스키마 없이 그대로 쓴다.

const ITEM_PREFIX := "gem:"

# ── 개체 상태(연금술 진행도)를 가방 키에 싣는다 ─────────────────────────────
#
# 원작 `AlchemyLayer`(혼성젬 강화)의 대상은 **가방의 젬**이고, 연금술 포인트·용액 투입
# 횟수는 서버가 **그 젬 개체에 붙여** 보관했다(`alchemy_gem_check` 의 `remain`/`cnt`).
# 종전 우리 모델은 그 상태를 드래곤 슬롯 엔트리에만 둬서 "장착한 젬만 강화 가능" 이었다.
#
# 해결은 이미 프로젝트에 있는 규약을 그대로 쓴다 — `Equipment.item_key` 의 `<meta>@<본체>`:
#
#     gem:체력의 젬:7           진행도 없음 → **기존 키와 동일**(스택 유지, 구세이브 무손실)
#     gem:p12,u2@체력의 젬:7    연금포인트 12 · 용액 2회 투입
#     gem:x@체력의 젬:7         파손(강화 실패)
#
# 진행도가 다르면 키가 달라져 자연히 다른 스택이 된다 = 개체 구분. 별도 uid 레지스트리가
# 필요 없고, 진행도 0인 젬은 예전과 완전히 같은 키라 마이그레이션도 필요 없다.
const META_POINTS := "p"      # 연금술 포인트
const META_POTIONS := "u"     # 용액 투입 횟수(used)
const META_BROKEN := "x"      # 파손

## 젬 이름+티어(+개체 상태) → 인벤토리 키.
## `meta` = {points, potions, broken} — 0/false 는 생략돼 진행도 없는 젬은 옛 형식 그대로다.
static func item_key(gem_name: String, tier: int, meta: Dictionary = {}) -> String:
	var body := "%s:%d" % [gem_name, tier]
	var tok: PackedStringArray = []
	if int(meta.get("points", 0)) > 0:
		tok.append("%s%d" % [META_POINTS, int(meta["points"])])
	if int(meta.get("potions", 0)) > 0:
		tok.append("%s%d" % [META_POTIONS, int(meta["potions"])])
	if bool(meta.get("broken", false)):
		tok.append(META_BROKEN)
	if tok.is_empty():
		return ITEM_PREFIX + body
	return "%s%s@%s" % [ITEM_PREFIX, ",".join(tok), body]

## 인벤토리 키 → {name, tier, points, potions, broken}. 젬 키가 아니면 {}.
## ⚠️ 젬 이름에 ':' 이 없다는 가정 대신 **마지막 ':' 로 쪼갠다**(이름 안전).
static func parse_item_key(key: String) -> Dictionary:
	if not key.begins_with(ITEM_PREFIX):
		return {}
	var rest := key.substr(ITEM_PREFIX.length())
	var meta := ""
	var at := rest.find("@")
	if at > 0:
		meta = rest.substr(0, at)
		rest = rest.substr(at + 1)
	var cut := rest.rfind(":")
	if cut <= 0:
		return {}
	var out := {"name": rest.substr(0, cut), "tier": int(rest.substr(cut + 1)),
		"points": 0, "potions": 0, "broken": false}
	for t in meta.split(",", false):
		var s := String(t)
		var body := s.substr(1)
		match s.substr(0, 1):
			META_POINTS: out["points"] = int(body) if body.is_valid_int() else 0
			META_POTIONS: out["potions"] = int(body) if body.is_valid_int() else 0
			META_BROKEN: out["broken"] = true
	return out

## 가방 키의 개체 상태만 → {points, potions, broken}.
static func item_key_meta(key: String) -> Dictionary:
	var g := parse_item_key(key)
	if g.is_empty():
		return {"points": 0, "potions": 0, "broken": false}
	return {"points": int(g["points"]), "potions": int(g["potions"]), "broken": bool(g["broken"])}

## 장착 슬롯 엔트리 → 가방 키(해제할 때 연금술 진행도를 고스란히 되돌린다).
## `Equipment.slot_to_item_key` 와 같은 역할이다.
static func slot_to_item_key(entry) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var e: Dictionary = entry
	return item_key(String(e.get("name", "")), int(e.get("tier", 0)), e)

## 가방 키 → 장착 슬롯 엔트리(장착할 때 진행도를 그대로 옮긴다).
## 진행도가 0이면 부가 필드를 넣지 않는다(구형 엔트리와 같은 모양 유지).
static func item_key_to_slot(key: String) -> Dictionary:
	var g := parse_item_key(key)
	if g.is_empty():
		return {}
	var e := {"name": String(g["name"]), "tier": int(g["tier"])}
	if int(g["points"]) > 0:
		e["points"] = int(g["points"])
	if int(g["potions"]) > 0:
		e["potions"] = int(g["potions"])
	if bool(g["broken"]):
		e["broken"] = true
	return e
