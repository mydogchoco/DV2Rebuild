class_name Loadout
## logic 층: 드래곤 기본 스킬 배정. 순수 정적 — Node·render·에셋 비의존, 헤드리스 검증 가능. (CLAUDE.md §10)
##
## 스킬이 생기는 길은 둘뿐이다(2026-07-29 정정):
##   ① **레벨 10·25·45 자동 습득** — 무작위 1레벨 스킬 하나씩(위키, `SKILL_GRANT_LEVELS`)
##   ② **스킬 스크롤**(에자녹 계열) — `docs/ref/porting/SkillScroll.md`
## 정밀 배정은 data/dragon_skills.json overrides(도감ID→스킬목록)로 사용자가 보정 → override 우선.
## 개체(uid) 시드로 "무작위지만 재현 가능"(순수·헤드리스 검증 유지).

# ⚠️ 학습 풀(`skills`)에는 상한이 없다 — 원작 `Dragon::getSkillList()` 는 그냥 배열이고,
#   2는 **장착 칸**(`Dragon::getSkill(0/1)`) 수다. 종전엔 이 둘을 한 배열로 겸해서
#   "스킬 2개를 채우면 더 못 배움"이 됐다(2026-07-29 정정, docs/ref/porting/SkillScroll.md §3).

# ⚠️ 정정(2026-07-27): 슬롯 수를 성급별 2~4로 두고 "서버유실 → 자작"이라 적어 뒀는데,
#   **원작 근거가 남아 있었다.**
#   · `DV2/string/stringsData_KR.xml` `<ToolTipDragonSkillExplain>`
#       "드래곤빌리지2의 모든 드래곤들은 전투에서 최대 2개의 스킬을 사용하고 있습니다."
#   · `CaveScene::setDragonInfo` 의 스킬칸 루프가 `while (i < 2)` 이고,
#     Lv10 미달이면 0번칸 · Lv35 미달이면 1번칸에 `common/lock.png` 를 얹는다.
#   ⇒ 슬롯은 **2칸 고정 + 레벨 해금**이다. 성급은 슬롯 수와 무관하다.
#   기존 세이브에서 3~4개를 들고 있는 개체의 배열은 **자르지 않는다**(진행도 보존).
const SKILL_SLOTS := 2
const SLOT_UNLOCK_LEVEL := [10, 35]   # 칸별 해금 레벨(원작 setDragonInfo)

## 슬롯 타입(원작 `Dragon::getSkillType(slot)` 0..3). skills.json 의 `slot` 값과 같은 어휘.
## `star` 는 특수칸 — `<ToolTipDragonSkillExplain>` "별 타입의 특수 슬롯이 존재하는데
## 모든 스킬의 추가 효과를 발생 시킵니다."
const SLOT_TYPES := ["tri", "sq", "cir", "star"]

## 드래곤 슬롯 수 — 원작 2 고정. (인자는 호출부 호환용으로 남긴다.)
static func slot_count(_dragon_def: Dictionary = {}) -> int:
	return SKILL_SLOTS

## 그 칸이 열렸는지(레벨 해금).
static func slot_unlocked(slot: int, level: int) -> bool:
	if slot < 0 or slot >= SKILL_SLOTS:
		return false
	return level >= int(SLOT_UNLOCK_LEVEL[slot])

## 칸별 슬롯 타입 — 드래곤 레코드 `skill_slots`. 없거나 짧으면 "star"(전부 허용)로 폴백.
static func slot_types(dr: Dictionary) -> Array:
	var raw: Array = dr.get("skill_slots", [])
	var out: Array = []
	for i in SKILL_SLOTS:
		var t := String(raw[i]) if i < raw.size() else ""
		out.append(t if t != "" else "star")
	return out

## 부화용 랜덤 슬롯 타입 — 젬 슬롯과 같은 규칙(원작 `CaveBagMsg20` "현재의 스킬 슬롯이
## 랜덤으로 변경 됩니다" + '다이즈의 호신부'(items.json `skillslot_change`) 가 재부여 아이템).
## ASSUMPTION: 4종 균등. 원작 가중치(특히 star 특수칸의 희귀도)는 유실 — 사용자 보정 대상.
static func random_slot_types(rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	for _i in SKILL_SLOTS:
		var k := (rng.randi() if rng != null else randi()) % SLOT_TYPES.size()
		out.append(String(SLOT_TYPES[k]))
	return out

## 스킬 타입이 그 칸 타입과 일치하나(star 칸은 전부 일치 → 추가효과 발생).
## 추가효과의 **내용**은 `data/combat.json` `skill_slot_match` 가 갖는다(수치는 서버 유실):
##   일반 = 스킬 피해 +power_pct% · 회복 계열 = 최대 사용횟수 +heal_use_bonus
##   (사용자 확정 2026-07-29, docs/input/sheets/open_questions.csv). 판정은 Battle 이 한다.
static func slot_matches(slot_type: String, skill_def: Dictionary) -> bool:
	if slot_type == "star":
		return true
	return String(skill_def.get("slot", "")) == slot_type

## 그 스킬이 칸 일치로 받는 추가효과의 한 줄 표기(툴팁용). cfg = data/combat.json.
static func slot_match_label(skill_def: Dictionary, cfg: Dictionary) -> String:
	var m: Dictionary = cfg.get("skill_slot_match", {})
	var cats: Array = m.get("heal_categories", [])
	if String(skill_def.get("category", "")) in cats and int(m.get("heal_use_bonus", 0)) > 0:
		return "사용횟수 +%d" % int(m["heal_use_bonus"])
	var pct := int(m.get("power_pct", 0))
	return "피해 +%d%%" % pct if pct > 0 else "추가효과"

# ============================================================ 스킬 스크롤(에자녹 계열) · 스킬 아이템
## 원작 3단 구조 — 상세·근거는 `docs/ref/porting/SkillScroll.md`.
##   에자녹의 기억/권능(document) → **스킬 아이템**(계정 인벤) → 드래곤 학습 풀 → 장착 2칸
## ⚠️ 스크롤을 쓰는 시점에 **대상 드래곤을 고르지 않는다.** 드래곤이 정해지는 건 스킬 아이템을
##   가방에서 쓸 때이고, 대상은 언제나 현재 선택 중인 드래곤이다(`BagPopup.c:1505` getDragonSelected).
##   종전 구현은 여기에 드래곤 선택 단계를 넣고 스킬 아이템 계층을 통째로 빠뜨렸다(2026-07-29 정정).

## 스킬 아이템의 가상 인벤 키 — 젬 `gem:` · 장비 `equip:` 와 같은 방식(§8.4 에셋/데이터 카탈로그).
## 원작 `AccountManager::addSkill(no, level, cnt)` 이 (번호, 레벨) 쌍으로 세므로 키도 그 쌍이다.
const ITEM_PREFIX := "skill:"

static func item_key(skill_id: int, level: int) -> String:
	return "%s%d:%d" % [ITEM_PREFIX, skill_id, level]

## "skill:<id>:<level>" → {id, level}. 아니면 {}.
static func parse_item_key(key: String) -> Dictionary:
	if not key.begins_with(ITEM_PREFIX):
		return {}
	var p := key.substr(ITEM_PREFIX.length()).split(":")
	if p.size() < 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return {}
	return {"id": int(p[0]), "level": int(p[1])}

## 아이템 subcategory가 에자녹 스크롤인지.
static func is_skill_scroll(subcategory: String) -> bool:
	return subcategory == "memory_random" or subcategory == "memory_select"

## 스크롤 1개가 줄 수 있는 (스킬 id, 레벨) 후보 전부. table = data/skill_scrolls.json `scrolls`.
## 원작 선택형 목록은 `Skill::getSkillAll()` — **드래곤과 무관한 전체 스킬**이다.
static func scroll_candidates(scroll_key: String, table: Dictionary, skills_db: Dictionary) -> Array:
	var row: Dictionary = table.get(scroll_key, {})
	var out: Array = []
	for lv in row.get("levels", []):
		for sid in usable_pool(skills_db):
			var maxlv := int(skills_db.get(str(sid), {}).get("max_level", 5))
			if int(lv) <= maxlv:
				out.append({"id": int(sid), "level": int(lv)})
	return out

## 선택형 스크롤인가(에자녹의 권능). 아니면 무작위(에자녹의 기억).
static func scroll_is_select(scroll_key: String, table: Dictionary) -> bool:
	return bool((table.get(scroll_key, {}) as Dictionary).get("select", false))

## 무작위 스크롤: 후보 중 하나. 반환 {id, level} — 못 고르면 {}.
static func roll_scroll(scroll_key: String, table: Dictionary, skills_db: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cand := scroll_candidates(scroll_key, table, skills_db)
	if cand.is_empty():
		return {}
	return cand[rng.randi_range(0, cand.size() - 1)]

## 순차 학습 게이트 — 원작 `Dragon::checkSkillList(no, level)`(`Dragon.c:815`, 반환 true = **불가**)
## 의 반대. `BagPopup::onClickConfirm`(case 4, 0xdf5650)이 스킬 아이템을 쓰기 직전에 이걸 부르고,
## 막히면 `CaveSkillUseMsg1` 팝업만 띄우고 끝낸다(서버 요청도 안 간다).
##   · Lv.1   : 그 번호를 **아직 안 배웠을 때만** (`param_2 == 1` 분기 — 번호가 있으면 1 반환)
##   · Lv.N≥2 : 그 번호를 **정확히 Lv.N-1 로** 갖고 있을 때만
##              (else 분기 — `getNo()==no && getLevel()==level-1` 인 항목을 찾아야 0 반환)
## ⇒ 3레벨 스크롤을 안 배운 드래곤에게 바로 쓸 수 없고, 배운 스킬의 레벨을 되돌릴 수도 없다.
## 문구 근거: `<ToolTipDragonSkillExplain>` "스킬은 1등급 부터 순차적으로 강화하여야 하며
## 한단계 높은 같은 스킬 스크롤을 이용하여 최대 5등급까지 강화 가능합니다."
static func can_learn(pool: Array, skill_id: int, level: int) -> bool:
	var have := -1
	for s in pool:
		if int((s as Dictionary).get("id", 0)) == int(skill_id):
			have = int((s as Dictionary).get("level", 0))
	if level <= 1:
		return have < 0
	return have == level - 1

## 못 배우는 이유(원작은 사유를 구분하지 않고 한 문구만 띄운다 — `CaveSkillUseMsg1`).
const LEARN_BLOCKED_MSG := "드래곤이 이미 배웠거나 아직 배울 수 없는 스킬입니다."

## 스킬 아이템 사용 → 학습 풀에 넣는다. 반환 {skills, ok, id, level, is_new, msg}.
##
## 원작(`BagPopup.c:6046` serverResult case 4)은 같은 번호를 풀에서 먼저 지우고 새 레벨로 다시
## 넣는다 — 위 `can_learn` 게이트가 앞에 있으므로 이 교체는 **Lv.N-1 → Lv.N 강화**로만 일어난다.
## (2026-07-31 정정: 종전 주석은 "1레벨 스크롤을 쓰면 1레벨로 내려간다"고 적었으나, 원작은
##  `checkSkillList` 가 그 경우를 먼저 막는다. 게이트를 빠뜨려 다운그레이드가 가능했다.)
## 풀에는 상한이 없다(2칸은 장착칸 수이지 학습 풀 크기가 아니다).
static func learn_from_item(pool: Array, skill_id: int, level: int, skills_db: Dictionary) -> Dictionary:
	var sd: Dictionary = skills_db.get(str(skill_id), {})
	if sd.is_empty():
		return {"skills": pool, "ok": false, "msg": "알 수 없는 스킬입니다"}
	var lv := clampi(level, 1, int(sd.get("max_level", 5)))
	if not can_learn(pool, int(skill_id), lv):
		return {"skills": pool, "ok": false, "msg": LEARN_BLOCKED_MSG}
	var nm := String(sd.get("name", "스킬"))
	var ns: Array = []
	var was := 0
	for s in pool:
		if int(s.get("id", 0)) == int(skill_id):
			was = int(s.get("level", 0))
			continue                      # 같은 번호는 제거 후 재삽입(원작과 동일)
		ns.append((s as Dictionary).duplicate(true))
	ns.append({"id": int(skill_id), "level": lv, "dedicated": false})
	if was == 0:
		return {"skills": ns, "ok": true, "id": int(skill_id), "level": lv, "is_new": true,
			"msg": "%s Lv.%d 습득!" % [nm, lv]}
	return {"skills": ns, "ok": true, "id": int(skill_id), "level": lv, "is_new": false,
		"msg": "%s Lv.%d → Lv.%d" % [nm, was, lv]}

# ------------------------------------------------------------ 장착 2칸(원작 Dragon::getSkill(0/1))
## 드래곤 레코드의 `skill_equip` 정규화 — 길이 SKILL_SLOTS, 0=빈칸.
## 학습 풀에 없는 번호는 비운다(스킬을 잃었는데 칸에 남는 일 방지).
static func equipped_ids(dr: Dictionary) -> Array:
	var raw: Array = dr.get("skill_equip", [])
	var pool := {}
	for s in dr.get("skills", []):
		pool[int((s as Dictionary).get("id", 0))] = true
	var out: Array = []
	for i in SKILL_SLOTS:
		var id := int(raw[i]) if i < raw.size() else 0
		out.append(id if pool.has(id) else 0)
	return out

## 장착 칸의 스킬 레코드([{id,level,dedicated}] 중 그 번호). 빈칸/미보유면 {}.
static func equipped_entry(dr: Dictionary, slot: int) -> Dictionary:
	var ids := equipped_ids(dr)
	if slot < 0 or slot >= ids.size() or int(ids[slot]) <= 0:
		return {}
	for s in dr.get("skills", []):
		if int((s as Dictionary).get("id", 0)) == int(ids[slot]):
			return s
	return {}

## 칸에 스킬을 꽂는다(skill_id=0 이면 해제 — 원작 `disarmament` 의 ns=0).
## 같은 스킬이 다른 칸에 이미 있으면 두 칸을 교환한다(중복 장착 방지).
## 반환 = 새 skill_equip 배열.
static func equip_skill(dr: Dictionary, slot: int, skill_id: int) -> Array:
	var ids := equipped_ids(dr)
	if slot < 0 or slot >= ids.size():
		return ids
	if int(skill_id) > 0:
		var prev := ids.find(int(skill_id))
		if prev >= 0 and prev != slot:
			ids[prev] = ids[slot]
	ids[slot] = int(skill_id)
	return ids

# ============================================================ 레벨 자동 습득(10·25·45)
## 원작: "드래곤은 레벨 10·25·45 달성 시 스킬을 랜덤으로 하나씩 자동 습득한다"
##   (나무위키/스킬 — `docs/game_design.md` §스킬. 서버가 하던 일이라 클라 디컴프에는 없다.)
## ⇒ **Lv1~9 드래곤은 스킬이 하나도 없다.** 스킬 칸도 Lv10 부터 열리므로 앞뒤가 맞는다.
##   (2026-07-29 이전엔 부화 즉시 무작위 2개를 주는 자작 스타터를 썼다 — 이 규칙으로 대체.)
const SKILL_GRANT_LEVELS := [10, 25, 45]

## 아직 받지 않은 습득 마일스톤. claimed = 드래곤 레코드 `skill_grants`(이미 받은 레벨 목록).
static func due_grants(level: int, claimed: Array) -> Array:
	var out: Array = []
	for m in SKILL_GRANT_LEVELS:
		if level >= int(m) and not claimed.has(int(m)):
			out.append(int(m))
	return out

## 그 레벨에서 배울 스킬 하나 뽑기 — usable+active 중 **아직 안 배운 것**에서 무작위.
## 반환 {id, level:1} / 더 뽑을 게 없으면 {}. rng 를 주면 재현 가능(개체 uid+마일스톤 시드 권장).
static func roll_grant(pool: Array, skills_db: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var owned := {}
	for s in pool:
		owned[int((s as Dictionary).get("id", 0))] = true
	var cand: Array = []
	for sid in usable_pool(skills_db):
		if not owned.has(int(sid)):
			cand.append(int(sid))
	if cand.is_empty():
		return {}
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	return {"id": int(cand[r.randi_range(0, cand.size() - 1)]), "level": 1}

## 드래곤 최초 스킬 → [{id,level,dedicated}].
## override(`data/dragon_skills.json`, 사용자 정밀배정)가 있으면 그것, **없으면 빈 배열**이다 —
## 스킬은 위 마일스톤(10/25/45)에서 생긴다. 종전의 "무작위 2개 스타터"는 폐기(2026-07-29).
static func default_skills(dragon_def: Dictionary, _skills_db: Dictionary = {}, overrides: Dictionary = {}, _rng: RandomNumberGenerator = null) -> Array:
	var id := int(dragon_def.get("id", 0))
	if overrides.has(str(id)):
		return normalize(overrides[str(id)])
	return []

## skills_db에서 전투 사용 가능한 스킬 id 목록(active+usable). 정렬(결정적 입력).
static func usable_pool(skills_db: Dictionary) -> Array:
	var out: Array = []
	for k in skills_db:
		var sd: Dictionary = skills_db[k]
		if sd.get("active", false) and sd.get("usable", false):
			out.append(int(sd.get("id", int(str(k)) if str(k).is_valid_int() else 0)))
	out.sort()
	return out

## 다양한 입력형([id,level] 배열 / {id,level} 딕셔너리 / "id_level" 문자열)을 [{id,level,dedicated}]로 정규화.
static func normalize(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for it in raw:
			if it is Array and it.size() >= 1:
				out.append({"id": int(it[0]), "level": (int(it[1]) if it.size() > 1 else 1), "dedicated": false})
			elif it is Dictionary:
				out.append({"id": int(it.get("id", 0)), "level": int(it.get("level", 1)), "dedicated": bool(it.get("dedicated", false))})
			elif it is String and "_" in it:
				var p := (it as String).split("_")
				if p[0].is_valid_int():
					out.append({"id": int(p[0]), "level": (int(p[1]) if p.size() > 1 and p[1].is_valid_int() else 1), "dedicated": false})
	return out
