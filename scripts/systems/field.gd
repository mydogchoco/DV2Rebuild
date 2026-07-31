# Field — 던전(필드) 정의의 **변형 해석** (순수 로직 계층 §8: render/에셋 의존 없음)
#
# ## 원작 구조
# 원작 `Field`(docs/ref/orig_code/decomp/Field.c)는 서버/DB 가 채워 준 필드 레코드다 —
# `{no, attribute, name, desc, levelMin, levelMax, dragonArr, soundPath, openScenarioNum}`
# (`setInfo` 가 파싱, `getAttribute`/`getName`/`getDragonArr`/… 로 읽는다).
# **변형 필드는 별도 레코드였다** — 유타칸 밤은 `no = 500 + 기본필드`, 카데스의 공간은
# `no = 600 + 기본필드` 로 서버가 다른 행을 내려줬다(우리 `DungeonBG.variant_of` 가 그 규칙).
#
# 우리는 서버가 없으니 `data/stages.json` 한 레코드 안에 `night` / `kades` **블록**으로 담고,
# 이 파일이 진입 난이도에 맞춰 **덮어쓴 사본**을 만들어 준다. 원작에서 "다른 필드 레코드"였던
# 것을 오프라인에서 재현하는 자리다.
#
# ## 이것이 고치는 버그 (🔴 2026-07-31)
# `night` 블록(전용 적·등장 드래곤·레벨 50·설명문)이 **12지역 모두 채워져 있는데 런이 읽지
# 않았다.** 밤으로 입장해도 낮 몬스터가 나오고 낮 드래곤 알이 떨어졌다. 변형 데이터를 만든
# `build_yutakan_variants.py` 는 있었지만 소비하는 쪽이 없었다.
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드 참조 금지(§8.2 단방향 의존).
class_name Field
extends RefCounted

## 변형 블록이 덮을 수 있는 키.
## 현재 `stages.json` 의 night 블록에 실제로 들어 있는 것 = enemies/dragons/level/desc/random_boss,
## kades 블록 = enemies. 나중에 블록이 늘어도 여기 목록에만 추가하면 된다.
## (`_` 로 시작하는 키는 근거 주석이라 항상 제외한다.)
const VARIANT_KEYS := [
	"enemies", "dragons", "level", "desc", "random_boss",
	"boss", "bgm", "bg", "element", "name", "party3", "once_per_day",
]

## 그 난이도가 별도 필드 레코드를 갖는가(= 변형 블록이 실재하는가).
## normal/hero 는 기본 레코드를 그대로 쓴다 — 영웅은 **스탯 배율**이지 다른 필드가 아니다
## (`stages.json` `_variant_rules.hero_stat_mult`).
static func has_variant(stage: Dictionary, mode: String) -> bool:
	if mode != "night" and mode != "kades":
		return false
	var b = stage.get(mode, {})
	return typeof(b) == TYPE_DICTIONARY and not (b as Dictionary).is_empty()

## 진입 난이도에 맞춘 필드 레코드. 변형이 없으면 **원본을 그대로** 돌려준다(복사 안 함).
##   mode = Drops.MODE_* ("normal" | "hero" | "night" | "kades")
##
## 변형이면 얕은 복사본에 블록의 키를 덮고 `variant` 를 찍는다 — 기존 `_is_kades()` 처럼
## `stage.variant` 를 보는 코드가 그대로 동작한다.
static func apply_variant(stage: Dictionary, mode: String) -> Dictionary:
	if stage.is_empty() or not has_variant(stage, mode):
		return stage
	var blk: Dictionary = stage[mode]
	var out := stage.duplicate(true)
	for k in VARIANT_KEYS:
		if blk.has(k):
			out[k] = blk[k]
	out["variant"] = mode
	# 변형 레코드 안에 또 변형 블록이 남아 있으면 혼동을 부른다 → 떼어 낸다.
	out.erase("night")
	out.erase("kades")
	return out

## 그 지역이 가진 변형 목록(디버그·검증용). 예: ["night", "kades"]
static func variants_of(stage: Dictionary) -> Array:
	var out: Array = []
	for m in ["night", "kades"]:
		if has_variant(stage, m):
			out.append(m)
	return out
