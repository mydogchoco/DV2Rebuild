# AdventureRun — 탐험 이벤트 큐 (순수 로직 계층 §8: render/에셋 의존 없음, 헤드리스 검증 가능)
#
# ## 원작 구조 (docs/ref/porting/AdventureEventFlow.md)
#
# 원작 탐험은 씬이 아니라 **이벤트 큐**다. `AdventureScene::initEvent()` 가 `m_nEventType`
# (this+0x21c) 으로 switch 하는 디스패처이고, `setNextEventChange()` 가
# `[0x21c] ← [0x220]; [0x220] ← 0xd(유휴)` 로 다음 이벤트를 현재로 당긴다.
# 스텝 사이에는 `setNextEventExe()` 의 `CCDelayTime(0.3)` + 텍스트박스 대기가 있다.
#
# **큐의 내용은 서버가 통째로 내려줬다** — `ResponseAdventureSequance` 가 파싱하던 `exe_event`
# 배열이 그것이고, 클라에는 "무엇이 언제 나오는가"를 정하는 코드가 없다. 그래서 이 파일이
# 그 서버 역할을 대신한다. 확률표는 `data/adventure_events.json`(자작 튜닝 노브) 한 곳에 모았다.
#
# ## 이것이 고치는 버그 (🟠 2026-07-30)
#
# 종전 `adventure.gd::_rebuild` 는 회복샘·보물·갈림길·상점·카드게임을 **씬을 짓는 그 자리에서
# 각자 독립 확률로** 굴렸다. 그래서
#   · 한 조우에 여러 이벤트가 **동시에** 터져 CanvasLayer 가 겹쳐 쌓였고,
#   · 이벤트와 몬스터 조우가 **같은 순간에** 진행됐다(원작은 순차 스텝이다).
# 여기서는 한 스텝에 이벤트를 **최대 1개**만 고르고, 마지막 원소는 **항상 몬스터**다.
# render 는 이 배열을 앞에서부터 하나씩 재생하고, 각 이벤트가 끝나야 다음으로 간다.
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드 참조 금지(§8.2 단방향 의존).
class_name AdventureRun
extends RefCounted

# --- 이벤트 종류 — 원작 initEvent 스위치 값과 1:1 -----------------------------
const NOTHING := "nothing"          # 1     setEventNothing
const MONSTER := "monster"          # 2,4   setEventMonster
const HEAL_HOLY := "heal_holy"      # 0x13  setEventHealArea(true)   effect_holy_well_2.mp3
const HEAL_PLAIN := "heal_plain"    # 0x14  setEventHealArea(false)  effect_water_in.mp3
const TREASURE := "treasure"        # 0x15  setEventTreasure(true)
const QUEST := "quest"              # 0x16  setEventQuest
const SHOP := "shop"                # 0x1a  setEventDungeonShop
const CHOICE := "choice"            # 0x1b  setEventDungeonChoice  (해골요새 전용)
const CARDGAME := "cardgame"        # 0x18/0x19  setEventDungeonCardGame1/2

## 원작 이벤트 타입 번호(참조용 — 우리 코드는 문자열 키를 쓴다).
const ORIG_EVENT_ID := {
	NOTHING: 0x01, MONSTER: 0x02, HEAL_HOLY: 0x13, HEAL_PLAIN: 0x14,
	TREASURE: 0x15, QUEST: 0x16, CARDGAME: 0x18, SHOP: 0x1a, CHOICE: 0x1b,
}

# --- 큐 생성 ------------------------------------------------------------------

## 이번 조우 구간(enc)에서 재생할 이벤트 열. **마지막 원소는 항상 `{type: MONSTER}`** 다.
##   stage  = data/stages.json 의 그 스테이지
##   cfg    = data/adventure_events.json
##   enc    = 이번 조우 인덱스(0부터)
##   opts   = {hurt: bool(파티가 다쳤나) , fortress: bool(해골요새인가) , random_boss: bool}
##   rng    = 시드 고정 가능(§4 — 같은 시드면 같은 큐)
##
## 규칙
##   · **보스 조우**(enc+1 >= 적 수)와 **랜덤보스 스테이지**에는 사전 이벤트가 붙지 않는다.
##     (원작도 보스 앞에는 `setAlertMonster` 컷인만 온다.)
##   · 그 밖에는 사전 이벤트를 **최대 `max_events_per_step` 개**(기본 1) 고른다.
##   · 각 이벤트의 게이트(`needs_hurt` / `min_enc` / `fortress_only`)를 통과한 것만 후보.
static func build_steps(stage: Dictionary, cfg: Dictionary, enc: int,
		opts: Dictionary, rng: RandomNumberGenerator) -> Array:
	# 유타칸 **밤**은 구조가 다르다 — 아래 `night_steps` 참조.
	if bool(opts.get("night", false)):
		return night_steps(stage, cfg, rng)
	# 소환형(혼돈의 틈새) — 밤과 같은 **단일 조우**다(사용자 확정 2026-07-31).
	#   "탐험 페이즈가 3개로 구성되어 있고 아무것도 찾지 못하는 이벤트도 있는데,
	#    (밤)처럼 보스전 단일 페이즈로 구성하고 100% 보스 조우로 바꿔."
	# 보스를 소환해 놓고 들어가는 곳이라 '아무것도 못 찾음'이 성립하지 않는다.
	# `final` 을 실어 전투 뒤 '계속하기'가 뜨지 않게 한다(밤과 같은 통로).
	if bool(opts.get("single_boss", false)):
		return [{"type": MONSTER, "boss": true, "final": true}]
	var out: Array = []
	var total := int((stage.get("enemies", []) as Array).size())
	var is_boss := (total > 0 and enc + 1 >= total) or bool(opts.get("random_boss", false))
	if not is_boss:
		var steps: Dictionary = cfg.get("steps", {})
		var n := int(steps.get("max_events_per_step", 1))
		var picked: Dictionary = {}
		for _i in maxi(0, n):
			var ev := _pick_event(steps, enc, opts, picked, rng)
			if ev == "":
				break
			picked[ev] = true
			out.append({"type": ev})
	out.append({"type": MONSTER, "boss": is_boss})
	return out

# --- 유타칸 밤 — **1회 조우로 끝난다** ----------------------------------------
#
# 사용자 확정(2026-07-31):
#   "밤을 '한번밖에 탐험할 수 없다' 라는 뜻은 '하루 한번'이 아니라, 한번 진입하면
#    이벤트 1번만 조우하고(아무것도 찾지 못했다 / 랜덤 인카운터 몬스터 / 지역 보스 셋 중
#    하나 이벤트) 탐험이 끝난다는 의미야."
#
# ⇒ 밤 큐 = **스텝 하나**. 보물·상점·회복샘 같은 사전 이벤트가 붙지 않고, 끝나면 런이 끝난다.
#   세 갈래는
#     ① 아무것도 찾지 못했다  = 원작 `setEventNothing`(이벤트 1)
#        문구도 원작 그대로 — `stringsData_KR <AdventureNothing>`
#        "해가 질 때까지 돌아다녔지만 아무것도 찾지 못했다."
#     ② 랜덤 인카운터 몬스터  = 밤 12지역 공용 4종(#160 골드 임프·#161 실버 임프·
#        #162 검은 로브의 사도·#175 블랙 윗치)
#     ③ 지역 보스            = 그 지역 전용 밤 보스
#   ②③ 의 비율은 `stages.json` 밤 편성의 `weight`(보스 7 : 공용 각 1)가 정하고,
#   ① 의 비율만 `data/adventure_events.json` `night.nothing_weight`(자작 노브)다.
#
# 반환 원소에는 `final: true` 가 붙는다 — render 가 "이 조우로 런이 끝난다"를 알아야
# 전투 뒤 '계속하기'를 띄우지 않는다.

## 밤 1스텝 큐. 반환 = [{type: NOTHING|MONSTER, …, final: true}]
## MONSTER 면 `enemy_index`(밤 편성 배열의 인덱스)와 `boss` 가 실린다.
##
## 세 갈래 비율 = `data/adventure_events.json` `night.weights`
## (사용자 확정 2026-07-31 **2 : 3 : 5**). 원작 확률은 클라에 없다 — §확인 결과 참조.
## 어느 **공용 몬스터**·어느 **보스**인지는 그 그룹 안에서 `stages.json` 밤 편성의
## `weight` 비례로 고른다(현재 공용 4종이 전부 1 = 균등).
static func night_steps(stage: Dictionary, cfg: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var enemies: Array = stage.get("enemies", [])
	var w: Dictionary = (cfg.get("night", {}) as Dictionary).get("weights", {})
	var commons: Array = []      # 밤 공용 조우 몬스터(비보스)
	var bosses: Array = []       # 그 지역 밤 보스
	for i in enemies.size():
		if bool((enemies[i] as Dictionary).get("boss", false)):
			bosses.append(i)
		else:
			commons.append(i)
	# 후보가 없는 갈래는 가중치를 0으로 눌러 "그 갈래로 뽑혔는데 대상이 없다"를 막는다.
	var w_nothing := maxf(0.0, float(w.get("nothing", 0)))
	var w_common := maxf(0.0, float(w.get("encounter", 0))) if not commons.is_empty() else 0.0
	var w_boss := maxf(0.0, float(w.get("boss", 0))) if not bosses.is_empty() else 0.0
	var total := w_nothing + w_common + w_boss
	if total <= 0.0:
		return [{"type": NOTHING, "final": true}]
	var x := rng.randf() * total
	if x < w_nothing:
		return [{"type": NOTHING, "final": true}]
	var pool := commons if x < w_nothing + w_common else bosses
	var idx := int(pool[_weighted_pick_of(enemies, pool, rng)])
	return [{"type": MONSTER, "final": true, "enemy_index": idx,
		"boss": bool((enemies[idx] as Dictionary).get("boss", false))}]

## `pool`(enemies 인덱스 목록) 안에서 weight 비례 추첨 → **pool 안에서의 위치**.
static func _weighted_pick_of(enemies: Array, pool: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for i in pool:
		total += maxf(0.0, float((enemies[int(i)] as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return rng.randi() % pool.size()
	var x := rng.randf() * total
	for j in pool.size():
		x -= maxf(0.0, float((enemies[int(pool[j])] as Dictionary).get("weight", 1)))
		if x <= 0.0:
			return j
	return pool.size() - 1

## `weight`(기본 1) 비례 추첨 → 인덱스. 합이 0이면 균등.
static func _weighted_pick(rows: Array, rng: RandomNumberGenerator) -> int:
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

## 이 스텝으로 런이 끝나는가(밤 1회 조우).
static func is_final(step: Dictionary) -> bool:
	return bool(step.get("final", false))

## 후보 중 가중치 추첨 1회. `nothing_weight` 가 뽑히거나 후보가 없으면 "".
## already = 이번 스텝에 이미 뽑힌 것(같은 이벤트를 두 번 넣지 않는다).
static func _pick_event(steps: Dictionary, enc: int, opts: Dictionary,
		already: Dictionary, rng: RandomNumberGenerator) -> String:
	var cands: Array = []
	var total := maxf(0.0, float(steps.get("nothing_weight", 0)))
	for e in (steps.get("events", []) as Array):
		var d: Dictionary = e
		var t := String(d.get("type", ""))
		if t == "" or already.has(t):
			continue
		if not is_available(d, enc, opts):
			continue
		var w := maxf(0.0, float(d.get("weight", 0)))
		if w <= 0.0:
			continue
		cands.append({"type": t, "weight": w})
		total += w
	if cands.is_empty() or total <= 0.0:
		return ""
	var r := rng.randf() * total
	for c in cands:
		r -= float((c as Dictionary)["weight"])
		if r <= 0.0:
			return String((c as Dictionary)["type"])
	return ""                                  # nothing_weight 구간에 떨어졌다

## 이 이벤트가 이번 스텝에 나올 수 있는가(게이트만 본다 — 확률은 보지 않는다).
static func is_available(ev: Dictionary, enc: int, opts: Dictionary) -> bool:
	if bool(ev.get("fortress_only", false)) and not bool(opts.get("fortress", false)):
		return false
	# 회복샘은 **다친 상태**에서만 의미가 있다(원작 getHealAreaRecoverHp 가 0이면 아무 일도 없다).
	if bool(ev.get("needs_hurt", false)) and not bool(opts.get("hurt", false)):
		return false
	if enc < int(ev.get("min_enc", 0)):
		return false
	return true

## 이 이벤트가 회복샘인가(둘 중 어느 쪽이든).
static func is_heal(event_type: String) -> bool:
	return event_type == HEAL_HOLY or event_type == HEAL_PLAIN

# --- 조우 전 선택지 — 원작 setBattleReady ------------------------------------

## 몬스터 조우 직전에 **도망 버튼을 줄 것인가**.
## 원작(`setBattleReady`)에서 단일 버튼(도망 불가)이 되는 조건은
##   `!isBoss && !Uno && !Raid && !Darknix && !Dungeon && !ScenarioBattle && m_nMode==2
##    && 난이도=="H" && User::getBoostHardAuto() > now`
## 즉 **영웅 난이도 + hard-auto 부스트 결제 아이템**이 켜진 자동전투 상태 하나뿐이다.
## 그 부스트는 결제 기능이라 ⚫CUT → 우리는 **항상 두 버튼**을 준다(보스 포함 — 원작도 보스는
## 단일버튼 블록에 들어가지 못하고 양버튼 경로로 떨어진다).
static func offers_escape(_is_boss: bool) -> bool:
	return true

## 두 번째 버튼의 라벨 프레임 키. 원작: `getIsDungeonMode()`(=해골요새)면 '포기한다',
## 그 밖에는 '도망간다'.
static func escape_frame(fortress: bool) -> String:
	return "scene_adventure_choice_giveup_KR" if fortress else "scene_adventure_choice_run_KR"

## 도망 성공 판정(원작 `setEventRun` = 0x9). 성공률은 서버 소유였다(클라에 판정 코드가 없다)
## → `data/adventure_events.json` `run.chance`(자작). 보스는 `run.boss_chance`.
static func run_succeeds(cfg: Dictionary, is_boss: bool, rng: RandomNumberGenerator) -> bool:
	var r: Dictionary = cfg.get("run", {})
	var p := float(r.get("boss_chance", 0.0)) if is_boss else float(r.get("chance", 1.0))
	return rng.randf() < clampf(p, 0.0, 1.0)
