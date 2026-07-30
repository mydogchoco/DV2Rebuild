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
		var a := roll_artifact(table, source, rng, field, artifact_mult)
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
static func roll_artifact(table: Dictionary, source: String,
		rng: RandomNumberGenerator, field := 0, artifact_mult := 1.0) -> String:
	var kd: Dictionary = table.get("kades", {})
	var ch: Dictionary = kd.get("artifact_chance", {})
	if rng.randf() >= clampf(float(ch.get(source, 0.0)) * artifact_mult, 0.0, 1.0):
		return ""
	var types := artifact_types_for(table, field)
	if types.is_empty():
		return ""
	var grade := _weighted_index(kd.get("artifact_grade", {}).get("weights", [1]), rng)
	return Equipment.item_key("artifact:%s:%d" % [String(types[rng.randi() % types.size()]), grade])

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

## 점술집 **골드 뽑기**(원작 <MagicTitleSlot>) 1회 → 인벤 키.
## 사용자 확정: **공격/방어/체력 젬의 최소~최대 티어**.
static func roll_gem_slot(table: Dictionary, gem_table: Dictionary, rng: RandomNumberGenerator) -> String:
	return roll_gem_from(table.get("slot", {}), gem_table, rng)

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

## 장비 가챠 1회 → 인벤 키. **이벤트 장비가 나오는 유일한 경로**(사용자 확정).
## equip_table = data/equipment.json (이벤트 목록을 여기서 읽는다 — 정의 단일 출처 §8.1).
static func roll_equip_gacha(table: Dictionary, equip_table: Dictionary,
		rng: RandomNumberGenerator) -> String:
	var g: Dictionary = table.get("gacha", {}).get("equip", {})
	var events: Array = equip_table.get("event", [])
	var ew := float(g.get("event_weight", 50)) if not events.is_empty() else 0.0
	var bw := float(g.get("basic_weight", 50))
	if ew + bw <= 0.0:
		return ""
	# 가챠 희귀도(사용자 확정) = 레어60:유니크30:에픽10 — 일반이 아예 안 나온다.
	var inst := Equipment.roll_instance("shop_gacha", rng, equip_table)
	if rng.randf() * (ew + bw) < ew:
		var e: Dictionary = events[rng.randi() % events.size()]
		return Equipment.item_key("event:%s" % String(e.get("name", "")), inst)
	var kinds: Array = table.get("exploration", {}).get("equip_kinds", [])
	var grades: Array = g.get("basic_grades", [0])
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
