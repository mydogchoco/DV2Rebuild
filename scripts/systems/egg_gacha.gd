class_name EggGacha
extends RefCounted
## 뽑기 알 개봉 규칙 — logic 층(CLAUDE.md §8). 화면·에셋을 모르고, 데이터도 **인자로 받는다**
## (`Drops.roll_gem_gacha(table, gem_table, rng)` 와 같은 관례 — 화면 없이 테스트 가능).
##
## 원작에서 '의문의 알' · '빛나는 의문의 알' · '속성 드래곤알' 은 **부화 대상이 아니라
## 가방에서 개봉하는 아이템**이고, 개봉하면 정해진 풀에서 드래곤 알이 하나 무작위로 나온다
## (위키 `docs/ref/wiki/item.pdf` §5 — 인용은 `data/gacha_eggs.json` `_orig_behavior`).
##
## 🔴 2026-07-28 이전 버그: `cave.gd _egg_item_to_dragon()` 이 dragon_id 없는 알에 대해
##    `RandomNumberGenerator.seed = hash(item_key)` 로 굴려서 **같은 알은 항상 같은 드래곤**이
##    나왔다. 뽑기가 아니라 확정 부화였다.
##
## 결과 풀·성급 가중치는 `data/gacha_eggs.json`(튜닝 노브). 여기엔 규칙만 둔다.

## 이 아이템이 '개봉(사용)' 대상인가 — 부화 대상이 아니다.
static func is_gacha_egg(item: Dictionary) -> bool:
	var sub := String(item.get("subcategory", ""))
	return sub == "gacha_egg" or sub == "element_egg"

# ── 뽑은 알의 가상 인벤 키 ────────────────────────────────────────────────────
# 개봉 결과는 **가방에 들어가는 알 아이템**이다(사용자 확정 2026-07-28) — 바로 부화하지 않는다.
# 그런데 `data/items.json` 의 알 아이템은 369마리 중 18종에만 `dragon_id` 가 있어서
# 임의 드래곤의 알을 담을 아이템 키가 없다. ⇒ 젬(`gem:`)·장비(`equip:`)와 같은 방식으로
# **가상 키 `egg:<드래곤id>`** 를 쓴다. 정의는 items.json 에 복제하지 않고 여기서 합성한다(§8.1).
const KEY_PREFIX := "egg:"

static func key_for(dragon_id: int) -> String:
	return KEY_PREFIX + str(dragon_id)

## `egg:123` → 123. 가상 알 키가 아니면 0.
## 강화 등급 접미사(`egg:123#2`)는 여기서 떼어낸다 — 등급이 달라도 **같은 드래곤의 알**이다(EggItem).
static func dragon_of(key: String) -> int:
	var base := EggItem.base_of(key)
	if not base.begins_with(KEY_PREFIX):
		return 0
	var s := base.substr(KEY_PREFIX.length())
	return int(s) if s.is_valid_int() else 0

## 가상 알 키 → 아이템 정의(가방이 쓰는 형식). 키가 아니거나 모르는 드래곤이면 {}.
static func item_def(key: String, dragons: Dictionary) -> Dictionary:
	var id := dragon_of(key)
	if id <= 0 or not dragons.has(id):
		return {}
	var d: Dictionary = dragons[id]
	return {
		"name": "%s의 알" % String(d.get("name", "드래곤 %d" % id)),
		"category": "egg",
		"subcategory": "dragon_egg",
		"element": d.get("element", null),
		"dragon_id": id,
		"tier": int(d.get("star", 0)),
		"stack": true,
		"offline": "impl",
		"egg_grade": EggItem.grade_of(key),   # 강화 등급은 키에 실린다(EggItem)
	}

## 개봉 결과 드래곤 id. 뽑을 수 없으면 0.
##   item_key : 인벤 키(`mall_question_egg2` 등)
##   item     : `data/items.json` 의 그 아이템 정의(subcategory/element 를 본다)
##   cfg      : `data/gacha_eggs.json`
##   dragons  : id(int) → 드래곤 정의(star/element). `Data.dragons` 형식
##   rng      : 시드 고정 재현용(§4)
static func roll(item_key: String, item: Dictionary, cfg: Dictionary,
		dragons: Dictionary, rng: RandomNumberGenerator) -> int:
	if cfg.is_empty() or dragons.is_empty():
		return 0
	var spec: Dictionary = {}
	var element := ""
	if String(item.get("subcategory", "")) == "element_egg":
		spec = cfg.get("element_pool", {})
		element = String(item.get("element", ""))
		if element == "":
			return 0
	else:
		spec = (cfg.get("pools", {}) as Dictionary).get(item_key, {})
	if spec.is_empty():
		return 0

	var weights: Dictionary = spec.get("star_weights", {})
	if weights.is_empty():
		return 0
	# ⚠️ JSON 숫자는 Godot 에서 float 로 들어온다 — `Array.has(int)` 가 조용히 실패한다
	#    (제외 목록이 통째로 무시되는 버그). 정수로 정규화한 뒤 쓴다.
	var exclude := as_ints(spec.get("exclude", []))
	var overrides: Dictionary = spec.get("star_pool_override", {})

	# 성급을 먼저 뽑고, 그 성급의 후보 중에서 균등하게 한 마리.
	# 후보가 비면(예: 그 속성에 그 성급이 없다) 다음 성급으로 물러난다.
	for s in _weighted_order(weights.keys(), weights, rng):
		var pool := candidates(dragons, int(s), element, overrides, exclude)
		if pool.is_empty():
			continue
		return int(pool[_randi(rng, pool.size())])
	return 0

## 같은 알을 n 번 연속 개봉한다 — 반환 = 뽑힌 순서대로의 드래곤 id 배열.
## 뽑기 1회가 실패(풀 없음)하면 그 회차는 건너뛴다(빈 배열이면 개봉 자체가 불가).
##
## ⚠️ **원작 로직이 아니다**(사용자 요청 2026-07-30). 우리 덤프의 원작 클라에는 '10회 사용'이
##   없다 — 문자열(`stringsData_KR.xml` 에 "10회/10개 사용" 없음) · 프레임(`x10`/`_ten` 0건) ·
##   심볼(`symbol_map.md` 에 use/open 계열 Ten·Multi·All 0건) 모두 부재. 후기 업데이트분으로
##   보이며, 여기서는 1회 개봉을 **독립 시행으로 n 번 반복**한다(확률은 회차마다 동일).
static func roll_many(item_key: String, item: Dictionary, cfg: Dictionary,
		dragons: Dictionary, rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in maxi(0, n):
		var did := roll(item_key, item, cfg, dragons, rng)
		if did > 0:
			out.append(did)
	return out

## 성급 목록을 가중치에 따라 **뽑힌 순서대로** 늘어놓는다.
## 첫 항목이 당첨이고, 그 성급 풀이 비었을 때 다음 항목으로 물러나기 위한 순서다.
static func _weighted_order(stars: Array, weights: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var rest: Array = stars.duplicate()
	rest.sort_custom(func(a, b): return int(a) < int(b))    # 결정적 순서(§4)
	var out: Array = []
	while not rest.is_empty():
		var total := 0.0
		for s in rest:
			total += maxf(0.0, float(weights.get(s, 0)))
		if total <= 0.0:
			out.append_array(rest)
			break
		var r := _randf(rng) * total
		var pick = rest[rest.size() - 1]
		for s in rest:
			r -= maxf(0.0, float(weights.get(s, 0)))
			if r <= 0.0:
				pick = s
				break
		out.append(pick)
		rest.erase(pick)
	return out

## 그 성급(+속성)의 후보 드래곤 id 목록. 오름차순 — 같은 시드면 같은 결과(§4).
static func candidates(dragons: Dictionary, star: int, element: String,
		overrides: Dictionary, exclude_raw: Array) -> Array:
	var exclude := as_ints(exclude_raw)
	var forced = overrides.get(str(star), null)
	if forced is Array:
		return as_ints(forced).filter(func(i): return not exclude.has(i))
	var out: Array = []
	for id in dragons:
		var d: Dictionary = dragons[id]
		# 기본 숨김 종(미구현 더미 = `dragons.csv` 이름 미정)은 **입수처에서 제외**한다.
		# 사용자 확정(2026-07-30): 600·700 은 도감에서도 특수 트리거로만 보이고,
		# 뽑기·부화 같은 입수 경로에는 아예 등장하지 않는다.
		if bool(d.get("dex_hidden", false)):
			continue
		# 커스텀 세대(600·700·666·777)는 **지정 획득처 전용**(사용자 확정 2026-07-30) —
		# 소환·카드 코드로만 얻는다. 666·777 은 도감에 보이므로 dex_hidden 이 아니고,
		# 이 플래그로만 걸린다. 데이터 = `dragons.json.acquire_locked`(build_data.py).
		if bool(d.get("acquire_locked", false)):
			continue
		if int(d.get("star", 0)) != star:
			continue
		# ⚠️ `String(null)` 은 Godot 4.7 에서 런타임 에러다 — 드래곤 4083 은 element 가 null 인데
		#    dex_hidden 도 아니라서 속성 알 뽑기에서 이 줄에 걸려 터졌다(2026-07-30 발견).
		var del = d.get("element")
		if element != "" and (del if typeof(del) == TYPE_STRING else "") != element:
			continue
		if exclude.has(int(id)):
			continue
		out.append(int(id))
	out.sort()
	return out


## 그 알에서 특정 성급이 나올 확률(%). 원작 확인창이 이 값을 보여 준다 —
## `CaveEggBronMsg4` "{#002940:* 5성 드래곤의 알이 나올 확률 : %1$s%% }".
## 후보가 하나도 없는 성급은 0 을 돌려준다(그 성급은 실제로 안 나오므로).
static func star_chance_pct(item_key: String, item: Dictionary, cfg: Dictionary,
		star: int, dragons: Dictionary = {}) -> float:
	var spec: Dictionary = {}
	if String(item.get("subcategory", "")) == "element_egg":
		spec = cfg.get("element_pool", {})
	else:
		spec = (cfg.get("pools", {}) as Dictionary).get(item_key, {})
	var w: Dictionary = spec.get("star_weights", {})
	if w.is_empty():
		return 0.0
	var total := 0.0
	for k in w:
		total += maxf(0.0, float(w[k]))
	if total <= 0.0:
		return 0.0
	# dragons 를 주면 후보가 빈 성급을 제외하고 실효 확률을 낸다(무한 폴백 반영).
	if not dragons.is_empty():
		var element := String(item.get("element", "")) if String(item.get("subcategory", "")) == "element_egg" else ""
		var eff := 0.0
		for k in w:
			if not candidates(dragons, int(k), element,
					spec.get("star_pool_override", {}), spec.get("exclude", [])).is_empty():
				eff += maxf(0.0, float(w[k]))
		total = eff if eff > 0.0 else total
	return maxf(0.0, float(w.get(str(star), 0))) / total * 100.0

## JSON 에서 온 숫자 배열 → 정수 배열. `Array.has()` 는 float 4041.0 과 int 4041 을
## 다른 값으로 본다 — 이 정규화가 없으면 제외 목록이 조용히 무시된다(2026-07-28 테스트로 검출).
static func as_ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out


static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()

static func _randi(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 1:
		return 0
	return rng.randi_range(0, n - 1) if rng != null else randi_range(0, n - 1)
