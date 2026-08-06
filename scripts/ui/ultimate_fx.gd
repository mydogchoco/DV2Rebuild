class_name UltimateFx
extends RefCounted
## render 층 공용 — 각성기(궁극기) 연출. 원작 `UltimateLayer`(138메서드) 이식분.
##
## 전수 분석·근거 = **`docs/ref/porting/UltimateLayer.md`**. 좌표·지연·z 는 전부 그 문서의
## 실측값이며, 여기서 **지어낸 수치는 `# ASSUMPTION:` 으로 표시**한다.
##
## ## 원작 구조 (한 번 더 요약)
##     setElement(el)  → init<El>()      전체판 자산·좌표
##     setColosseum()  → init<El>_C()    콜로세움 **추가분**(바닥 링) ← 대체가 아니라 덧붙임
##     runUltimate(t)  → initPosition() + run<El>() + action<El>_C()
##     damage<El>_C()  → 피해 표시(§2 표의 시각)
##     finishUltimate()
##
## ## 이 파일의 이식 상태
##   ✅ 바닥 링 4장 구성 + 링 안무 3계열(공통 / fire / shadow)  ← `init<El>_C` + `run<El>_C`
##   ✅ `_C` 속성별 추가분(dark shade · shadow twist · holy 날개 스파인 · shadow 본체 스파인)
##   ✅ **9속성 전부** `run<El>` 안무 이식 — 각 함수 머리에 근거를 적었다
##   ⚪ `damage<El>_C` 의 피격 반응(화면 흔들림·색 변화)은 호출측(fight.gd)이 낸다
##
## ⚠️ 연출을 고칠 때는 여기만 고친다. 확인 창(`scenes/dev_ultimate_fx.tscn`)이 같은 코드를 튼다.

const DIR_PREFIX := "ultimate_"

# ── §2 공통 상수 (전부 실측) ────────────────────────────────────────────────
## `getDuration()` @01001200 이 읽는 `.rodata` 표. libgame.so 직접 디코드(베이스 −0x100000).
##   콜로세움 = `DAT_021af294` · 탐험 = `DAT_021af2b8`
const DURATION := {
	"aqua": 11.0, "chaos": 10.65, "dark": 11.0, "earth": 9.0, "fire": 12.0,
	"holy": 11.25, "light": 11.25, "wind": 11.0, "shadow": 9.25,
}
const DURATION_ADV := {
	"aqua": 9.75, "chaos": 9.65, "dark": 9.75, "earth": 7.85, "fire": 9.25,
	"holy": 10.0, "light": 10.25, "wind": 9.4, "shadow": 9.25,
}
## `getDamageTextTime()` @01020e4c — 각성기 피해 수치가 뜨는 시각.
## fire 는 원작이 `mem[0x390] + 4.5` 로 계산하는데 그 멤버가 폭발 지연표의 7번째(3.3)다 ⇒ 7.8.
const DMG_TIME := {
	"aqua": 8.05, "chaos": 8.2, "dark": 8.65, "earth": 5.5, "fire": 7.8,
	"holy": 8.5, "light": 7.75, "wind": 8.0, "shadow": 8.0,
}

# ── 마스터 타임라인 — `runUltimate` @00fe6e98 실측 (2026-08-05 재작성) ────────
#
# 원작 콜로세움 호출 = `showCutIn(actor, 0.5)` 직후 `runUltimate(1.0)`:
#   장막(0x238): Delay(1.0) → FadeTo(1.0, 200)                       ← 화면 암전
#   레이어:     Delay(1.0) → Delay(0.5=initPosition 반환) → Delay(0.75)
#               → action<El>_C() → Delay(0.5) → run<El>()
#   ⇒ 시전 0초 기준: 시전자 점프 1.0 · **action_C 2.25 · run<El> 2.75**.
#   run<El> 은 첫 줄에서 run<El>_C(링 안무)를 부른다 — 링도 2.75 에 시작한다.
# 레퍼런스 영상 교차검증(배속 x1 = timeScale 1.35): 불 시전 로그 +1.0s 점프 착지,
#   +2.2s 링, +2.4s 첫 불기둥, +5.8s 화이트아웃 — 전부 이 표와 일치.
const LEAD := 1.0                  # runUltimate(delay) — FightScene 이 1.0 을 넘긴다
const POS_RET := 0.5               # initPosition 반환값(0x3f000000 실측)
const ACT_AT := LEAD + POS_RET + 0.75      # = 2.25, action<El>_C 시각
const RUN_AT := ACT_AT + 0.5               # = 2.75, run<El>(+run<El>_C) 시각

# ── 속성 공통 지연 `this + 0x228` — `setElement` @00fdf48c 이 박는다 ──────────
#
# 🔴 2026-08-06 신규 발견. 각 `run<El>` 의 액션은 전부 `Delay(this[0x228] + <표값>)` 으로
#   걸린다(불: 폭발 20단 `0x228 + 0x378[i]` · 백색 레이어 `0x228 + 4.25` · 장막 `0x228 + 6.5`).
#   생성자(@00fdee78 :58)가 0 으로 두지만 **`setElement` 의 스위치가 속성마다 덮어쓴다**:
#     fire 0x3f800000=1.0 · holy 0x3f400000=0.75 · aqua/earth/shadow 0x3fa00000=1.25 ·
#     chaos/dark/light/wind 0x3fb33333=1.4
#   우리는 이 항을 0 으로 두고 있었다 ⇒ 안무 본체가 통째로 그만큼 일렀다.
# ⚠️ **`run<El>_C`(바닥 링·먼지)에는 안 붙는다.** 그래서 원작은 링이 먼저 깔리고 뜸을 들인 뒤
#   폭발이 시작된다 — 우리가 "링과 첫 폭발이 붙어 있다"고 본 차이의 정체가 이것이다.
# 실측 교차검증(레퍼런스 영상, 배속 1.35 · run<El> = 영상 2.22s):
#   링·먼지 run+0 → 2.22s(실측 2.20) · 첫 폭발 run+1.0+0.25 → 3.15s(실측 3.15) ·
#   백색 섬광 run+1.0+4.25 → 6.11s(실측 6.05) · 장막 걷힘 run+1.0+6.5 → 7.78s(실측 7.9).
const ELEMENT_DELAY := {
	"aqua": 1.25, "chaos": 1.4, "dark": 1.4, "earth": 1.25, "fire": 1.0,
	"holy": 0.75, "light": 1.4, "wind": 1.4, "shadow": 1.25,
}
## 위 표를 실제로 적용한 속성. 나머지 8속성의 `run<El>` 은 이 항을 모르는 채 **영상에 맞춰**
## 시간을 조정해 둔 곳이 섞여 있어(예: wind 장막 "영상 실측 run+5.5") 일괄로 더하면 맞아 있던
## 정합이 깨진다. 속성별로 영상 재대조를 마칠 때마다 여기 이름을 추가한다.
## 2026-08-06 빛 추가 — 영상 실측이 이 항을 세 곳에서 **오차 없이** 확인했다(앵커 = 링 폭발
## `run+0.65` v39.537 · 백색 섬광① `run+1.4+0.5` v40.467 ⇒ 두 간격 실측 1.2555 = 예측 1.25):
##   백색 섬광① 4.15 · 별 무리 B 5.90 · 백색 섬광② 9.25 — 셋 다 종전 우리보다 **정확히 1.40** 일렀다.
const ELEMENT_DELAY_ON := ["fire", "aqua", "light", "wind"]

## `run<El>` 액션에 붙는 공통 지연(초). `run<El>_C` 계열에는 쓰지 않는다.
static func elem_delay(el: String) -> float:
	return float(ELEMENT_DELAY.get(el, 0.0)) if ELEMENT_DELAY_ON.has(el) else 0.0


# ── 화면 장막 — `setElement` 가 만드는 검은 `CCLayerColor`(tag 0x60044) ───────
#
# 🔵 2026-08-05 실측 재작성 — 종전의 "속성별 색 레이어 + ASSUMPTION 알파 0.62"는
#   반쪽이었다. 원작은 **화면보다 50pt 큰 검은 CCLayerColor 한 장**(this+0x238)을 만들어
#   `runUltimate` 가 `Delay(1.0) → FadeTo(1.0, 200)` 으로 깔고, 각 `run<El>` 이 **같은 장막**에
#   TintTo/FadeTo 시퀀스를 건다. 알파는 추측이 아니라 **200/255** 다.
# 아래 표 = 각 `run<El>` 이 장막에 거는 시퀀스(디컴프 리터럴 전수, run 시작 기준):
#   aqua   TintTo(1, 194,255,255) → Delay(3) → TintTo(1, 25,60,125) → Delay(.75) → FadeTo(.5, 0)
#   chaos  TintTo(3, 200,50,25) → Delay(2) → …(콜백)
#   dark   Delay(1) → TintTo(3.3, 23,36,74) → Delay(2) → FadeTo(1, 0)
#   earth  Delay(5.75) → FadeTo(.25, 0)
#   fire   Delay(6.5) → FadeTo(.25, 0)
#   holy   Delay(6.75) → FadeTo(.25, 0)
#   shadow TintTo(.2, 0,185,205) → Delay(.2) → TintTo(1, 0,70,80) → Delay(2)
#          → TintTo(.2, 255,255,255) → Delay(.2) → FadeTo(.5, 0)
#   light/wind — 장막 액션이 디컴프 범위에서 특정 안 됨(빛은 별도 백색 레이어가 주역).
#          ASSUMPTION: holy 와 같은 시각(run+6.75)에 걷는다.
const VEIL_A := 200.0 / 255.0
## steps = run<El> 시작 기준 [지연, [동작…]] 목록. 동작 = ["tint", 초, Color] | ["fade", 초, 알파]
const VEIL := {
	"aqua":   [["tint", 1.0, Color8(194, 255, 255)], ["wait", 3.0], ["tint", 1.0, Color8(25, 60, 125)],
		["wait", 0.75], ["fade", 0.5, 0.0]],
	"chaos":  [["tint", 3.0, Color8(200, 50, 25)], ["wait", 2.0], ["fade", 1.0, 0.0]],
	"dark":   [["wait", 1.0], ["tint", 3.3, Color8(23, 36, 74)], ["wait", 2.0], ["fade", 1.0, 0.0]],
	"earth":  [["wait", 5.75], ["fade", 0.25, 0.0]],
	"fire":   [["wait", 6.5], ["fade", 0.25, 0.0]],
	"holy":   [["wait", 6.75], ["fade", 0.25, 0.0]],
	"light":  [["wait", 6.75], ["fade", 0.25, 0.0]],   # ASSUMPTION(위 주석)
	# 🔴 2026-08-06 재실측 — 종전 `run+5.5` 는 정렬 기준이 0.4초 어긋난 값이었다. 바람 구간
	#   (영상 28.30~37.63초, 장면 컷 실측)에서 배경이 돌아오는 구간은 seg +6.90~+7.10 이고,
	#   `run+0 ↔ seg +2.12`(바닥 링 실측 앵커) · 배속 1.35 로 환산하면 **run+6.45 부터 0.27초**다.
	#   회오리 본체가 끝나는 시각(`runWind` 1.4+5.15+0.1 = 6.65)과 맞물린다.
	#   ⚠️ 이 표는 `elem_delay` 가 앞에 붙으므로(위 `_master_veil`) 여기 값은 **1.4 를 뺀 것**이다.
	"wind":   [["wait", 5.05], ["fade", 0.27, 0.0]],   # +1.4 = run+6.45 (영상 실측)
	"shadow": [["tint", 0.2, Color8(0, 185, 205)], ["wait", 0.2], ["tint", 1.0, Color8(0, 70, 80)],
		["wait", 2.0], ["tint", 0.2, Color8(255, 255, 255)], ["wait", 0.2], ["fade", 0.5, 0.0]],
}

## z 규약(2026-08-05 실측 교정) — 원작은 장막(z0) < UltimateLayer(z7) 라 **연출 전체가 장막
## 위**에서 밝게 탄다. 종전엔 장막 z84 가 불기둥(z 5~102)을 덮어 캐스케이드가 어둡게 깔렸다.
##   장막 0 < 드래곤 10 < 합체 문양 85 < 링 89~96 < 속성 안무 90~ < 백색 섬광 250
##
## 🔴 2026-08-06 장막 z 정정(물 프레임 대조) — `setElement` @00fdf48c 은 장막을
##   **`this->getParent()->addChild(veil, 0, 0x60044)`** 로 붙인다. z **0** = 드래곤보다 **뒤**다.
##   그래서 원작 암전 프레임(영상 12.55s)은 배경만 캄캄하고 두 드래곤은 원색 그대로다.
##   우리는 80 이라 드래곤까지 같이 어두워지고 있었다(9속성 공통 증상).
const Z_ACTOR := 10                        # `fight.gd` 드래곤 holder z(원작 addChild(spine, 10))
const Z_VEIL := 0
const Z_FLASH := 250
## wind 전용 — 🔴 2026-08-06 프레임 대조로 순서를 뒤집었다. 종전 회오리 z=99 는 **링·잎·소를
##   전부 덮는** 자리였는데, 원작 화면에서는 룬 링·잎·소가 회오리 줄기 **위**에 그려진다.
const Z_WIND_WHIRL := 81                   # 합체 문양(85)·링(89~)보다 뒤
const Z_WIND_DEBRIS := 96
const Z_WIND_ZMOON := 99

static func _master_veil(host: CanvasItem, el: String, at: Vector2, sp: float) -> void:
	var r := _screen_veil(host, at, Color(0, 0, 0), Z_VEIL)
	var t := r.create_tween()
	t.tween_interval(LEAD / sp)
	t.tween_property(r, "color:a", VEIL_A, 1.0 / sp)
	t.tween_interval((RUN_AT - LEAD - 1.0) / sp)
	# 아래 표는 `run<El>` 이 장막에 거는 액션이라 속성 공통 지연(`this+0x228`)이 앞에 붙는다.
	t.tween_interval(elem_delay(el) / sp)
	for step in VEIL.get(el, []):
		match String(step[0]):
			"wait":
				t.tween_interval(float(step[1]) / sp)
			"tint":
				var c: Color = step[2]
				t.tween_property(r, "color", Color(c.r, c.g, c.b, VEIL_A), float(step[1]) / sp)
			"fade":
				t.tween_property(r, "color:a", float(step[2]), float(step[1]) / sp)
	t.tween_callback(r.queue_free)


# ── 속성별 효과음 — libgame.so 문자열 실측 (2026-08-05) ─────────────────────
#
# 원작은 각성기마다 전용 효과음 세트를 쓴다. **이름은 전부 libgame.so 리터럴**이고
# (`effect_aqua1/2` `effect_fire1/2` `effect_fire_fillar` `effect_earth1/2` `effect_wind`
#  `effect_light` `effect_dark(_clap/_explosion)` `effect_holy_*` `effect_chaos_*`
#  `effect_blackhall_1/2`), `SoundManager::playEffect` 는 안무 람다(PTR_FUN_*) 안에서 불려
# **재생 시각은 디컴프 범위 밖**이다 — 시각은 안무 정렬로 둔다(ASSUMPTION).
# ⚠️ aqua1/2 · earth1/2 · fire1/2 · light · dark 는 **덤프에 mp3 가 없다**(판본 갭) —
#   `Bgm.sfx` 가 없는 파일을 조용히 건너뛰므로 원작 이름 그대로 예약해 둔다(확보 시 자동).
## [시각(초, 시전 기준), 트랙] 목록.
const SFX := {
	# fire 의 `effect_fire_fillar` 는 여기(고정 시각)가 아니라 **기둥마다** 낸다(`_fire_burst`).
	# `effect_fire2` 는 백색 섬광과 같은 박자다 = `0x228(1.0) + 4.25`(위 ELEMENT_DELAY).
	"fire":   [[RUN_AT, "effect_fire1"], [RUN_AT + 5.25, "effect_fire2"]],
	# aqua 도 `0x228`(=1.25) 을 앞에 얹는다 — 1 = 물 차오름, 2 = 상어 돌진(`0x228 + 5.0`).
	"aqua":   [[RUN_AT + 1.25, "effect_aqua1"], [RUN_AT + 6.25, "effect_aqua2"]],
	"earth":  [[RUN_AT, "effect_earth1"], [RUN_AT + 2.0, "effect_earth2"]],
	"wind":   [[RUN_AT, "effect_wind"]],
	"light":  [[RUN_AT, "effect_light"]],
	"dark":   [[RUN_AT, "effect_dark"], [RUN_AT + 1.35, "effect_dark_clap"],
		[RUN_AT + 5.9, "effect_dark_explosion"]],
	"holy":   [[ACT_AT, "effect_holy_wing"], [RUN_AT + 0.75, "effect_holy_well_1"],
		[RUN_AT + 1.25, "effect_holy_spear"], [RUN_AT + 3.0, "effect_holy_well_2"],
		[RUN_AT + 3.775, "effect_holy_fade"]],
	"chaos":  [[RUN_AT, "effect_chaos_dust"], [RUN_AT + 1.5, "effect_chaos_drop_1"],
		[RUN_AT + 2.5, "effect_chaos_drop_2"], [RUN_AT + 4.0, "effect_chaos_explosion"]],
	"shadow": [[RUN_AT, "effect_blackhall_1"], [RUN_AT + 3.0, "effect_blackhall_2"]],
}

static func _schedule_sfx(host: CanvasItem, el: String, sp: float) -> void:
	for e in SFX.get(el, []):
		var tm := Timer.new()              # host 자식 — 씬과 함께 정리(§_fire_burst 주석)
		tm.one_shot = true
		tm.wait_time = maxf(0.01, float(e[0]) / sp)
		tm.autostart = true
		var track := String(e[1])
		tm.timeout.connect(func() -> void: Bgm.sfx(track))
		host.add_child(tm)


# ── §4 바닥 링 — `init<El>_C` 실측 구성 ─────────────────────────────────────
## 원작은 스프라이트 3~4장을 만들어 **하나를 다른 하나의 자식으로 겹친다**(형제가 아니다).
##     layer.addChild(base,  z=el-1, tag 9000)      base 안에 nest 가 z=-1 로 들어간다
##     layer.addChild(sib[0], z=el-1, tag 0x2329)
##     layer.addChild(sib[1], z=el-1, tag 0x232a)   (shadow 만 sib 3장, 0x232b 까지)
## 위치 = 몸통 중앙 − (0, S×87.5) = **발밑**. S = 시전자 스케일(원작 `this+0x22c`).
##
## ⚠️ 속성마다 프레임 구성이 다르다 — fire 는 아틀라스에 circle3 이 아예 없고 circle2 를 두 번
##    쓴다. shadow 는 base 가 링이 아니라 `marsh1`(늪)이다. 지어낸 게 아니라 원작 그대로다.
const RING := {
	"aqua":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"chaos":  {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"dark":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"earth":  {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"fire":   {"base": "circle1", "nest": "",        "sib": ["circle2", "circle2"]},
	"holy":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"light":  {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"wind":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"shadow": {"base": "marsh1",  "nest": "",        "sib": ["circle1", "circle2", "circle2"]},
}
## `_C` 가 링 말고 더 까는 것 — 배치노드에 z=5, tag 0x1883f 로 붙는다.
const RING_EXTRA := {"dark": "shade", "shadow": "twist"}
## `_C` 가 세우는 스파인(변환본 씬). 원작 `initHoly_C` / `initShadow` 참조.
const RING_SPINE := {
	"holy": {"scene": "res://scenes/fx/ultimate_holy_wing.tscn", "anim": "animation"},
	"shadow": {"scene": "res://scenes/fx/ultimate_shadow.tscn", "anim": "s1"},
}
const RING_DY := 87.5          # 원작 `CCPoint(S*0.0, S*87.5)` 를 base 에서 뺀다

# 링 안무 — `run<El>_C` 실측. 8속성이 **같은 계열**이고 fire·shadow 만 따로다.
const RING_FADE_IN := 0.25     # FadeTo(0.25, 255)
const RING_LEAD := 0.15        # Delay(0.15)
const RING_HOLD := 0.25        # Delay(0.25)
const RING_BURST := 0.25       # ScaleTo(0.25, (S+0.25)*10)
const RING_BURST_MUL := 10.0
const RING_DIM := 0.1          # FadeTo(0.1, 25)
const RING_OUT := 0.15         # FadeTo(0.15, 0)
const SIB_LEAD := 0.4          # Delay(0.4) → FadeTo(0.25,255) → FadeTo(0,125) → FadeTo(0.15,0)
const SIB_MID := 125.0 / 255.0
# fire 전용(runFire_C): 상하 진동 + EaseIn 축소 + 긴 감광
const FIRE_BOB := 2.5
const FIRE_BOB_SEC := 0.25
const FIRE_SHRINK_SEC := 4.1
const FIRE_SHRINK := 0.85
const FIRE_DIM_SEC := 3.85
const FIRE_DIM := 100.0 / 255.0
# shadow 전용(runShadow_C)
const SHADOW_LEAD := 0.5
const SHADOW_HOLD := 0.5

## 바닥 링이 깔리는 시각(시전 0초 기준). 기본은 `run<El>` 과 같은 `RUN_AT`.
## 🔴 2026-08-06 — **혼돈만 `LEAD`(1.0)** 다. 영상 실측(T0 = 66.53s · timeScale 1.35):
##   흰 원 67.27 = 명목 **1.00** → 붉은 원 67.47 = 1.27 → 1.8 에 퍼지며 소멸.
##   불은 종전대로 `RUN_AT` 이 맞다(포팅 카드 실측 "링 영상 2.20s" = 명목 2.72).
##   나머지 7속성은 아직 이 축으로 재대조하지 않았다 — 확인할 때마다 여기 한 줄로 적는다.
const RING_AT := {"chaos": LEAD}
## 링 버스트 배율 상한 — 기본은 원작 리터럴 `RING_BURST_MUL`(×10).
## 혼돈만 영상(67.73s)에서 발밑 타원이 두 배 남짓만 퍼진다 ⇒ ×10 이면 화면이 통째로 붉어진다.
const RING_BURST_CAP := {"chaos": 2.5}

static func ring_at_sec(el: String) -> float:
	return float(RING_AT.get(el, RUN_AT))

# ── §5-fire 20단 폭발 캐스케이드 — `initFire` + `runFire` 실측 ──────────────
## 폭발 지점 20곳. 원작은 `this+0x2d8`~`0x370` 에 박아 둔다.
## 각 항 = (dx, dy) — **cocos 좌표(y-up)**, 몸통 중앙 기준. `W` = 레이어 폭.
##   원작 표기 `dir * X, Y` 에서 dir 은 시전 방향(±1). dy 는 원작의 `(…,-N) + (0,50)` 합.
## ⚠️ 17번만 `+(0,50)` 보정이 없다 — **원작 그대로**다(오타처럼 보이지만 재현한다).
const FIRE_POINTS := [
	[0.25, 0.0, -110.0], [-0.25, 0.0, -80.0], [0.0, 0.0, -130.0],
	[0.25, -50.0, -70.0], [-0.25, 25.0, -90.0], [0.25, 30.0, -145.0],
	[0.0, -30.0, -150.0], [0.0, -60.0, -140.0], [0.25, -75.0, -77.5],
	[-0.25, -25.0, -120.0], [0.25, 5.0, -160.0], [-0.25, 10.0, -70.0],
	[0.0, 10.0, -160.0], [0.25, -45.0, -70.0], [-0.25, 30.0, -60.0],
	[0.25, 0.0, -170.0], [0.0, -17.5, -110.0], [-0.25, 0.0, -175.0],
	[0.25, -55.0, -80.0], [0.0, 90.0, -200.0],
]
## 터지는 시각 `mem[0x378]`~`0x3c4` (float×20).
const FIRE_DELAYS := [
	0.25, 1.0, 1.65, 2.15, 2.6, 3.0, 3.3, 3.55, 3.7, 3.85,
	4.0, 4.125, 4.25, 4.375, 4.5, 4.625, 4.75, 4.875, 5.0, 5.1,
]
## z 층 `mem[0x3c8]`~ (int×20). 실제 z = 층×5 (+1 폭발 / +2 지진 / +0 화염기둥).
const FIRE_Z := [5, 2, 7, 1, 4, 9, 10, 8, 3, 6, 11, 2, 13, 3, 1, 16, 1, 18, 4, 20]
const FIRE_EXPL_SEC := 0.06    # 애니 explosion2~6
const FIRE_PILLAR_SEC := 0.03  # 애니 fillar3~7
const FIRE_STONE_MIN := 14     # 지점당 돌 `rand()%6 + 14` 개 (원작 루프 상한)
const FIRE_START_SX := 0.5     # 원작 setScaleX(0.5) — 세로는 0 에서 솟는다
const FIRE_LAG := 0.225        # 기둥·지진·돌은 폭발보다 0.225초 늦다
## 화면 백색 암전 — `runFire`: Delay(base+4.25) → FadeTo(1.0,255) → Delay(1.0) → FadeTo(0.5,0)
const FIRE_FLASH_AT := 4.25
const FIRE_FLASH_IN := 1.0
const FIRE_FLASH_HOLD := 1.0
const FIRE_FLASH_OUT := 0.5

# ── §5-fire 불덩이 20발 — `initFire_C` @0100c928 + `runFire_C` @01003df8 꼬리 ──
#
# 🔴 2026-08-06 신규 이식. 종전엔 불기둥만 솟았다 — 원작은 **시전자 머리 위에 불덩이가
#   생겨 표적 지점으로 대각선으로 떨어지고, 닿는 순간 그 자리에서 폭발+기둥이 솟는다.**
#   자산(`fire_fireball1~4`)은 변환본에 있었는데 아무 데서도 안 부르는 **미배선** 상태였다.
#
# `initFire_C` 배치(루프 20회, 태그 0x22470+i · z = FIRE_Z[i]*5 · setScale(0)):
#     pos = 시전자쪽 base + ( k*(−0.5*W + rand%301), rand%75 + 100 )      k = 시전자 바라보는 방향
#   ⇒ W = 시전자 dragonLayer 의 contentSize.x, y 는 cocos y-up 이라 **위쪽** 100~175.
# `initFire_C` 애니: fireball1→4, 0x3d75c28f = **0.06초/프레임**, 무한(loops=0) — `this+0x418`.
# `runFire_C` 안무(A = FIRE_POINTS[i] 의 절대 좌표 = 그 지점의 폭발 자리):
#     Delay(0x228 + FIRE_DELAYS[i] − 0.5)
#     → Spawn( Repeat(Animate(fireball1~4, 0.06), 20),
#              Seq( ScaleTo(0.1, k*S*1.25, S*1.25) → CallFunc → ScaleTo(0.1, k*S, S)
#                   → MoveBy(0.2, (start+A)*0.01)
#                   → Spawn( MoveTo(0.1, A), Seq(Delay(0.05), FadeTo(0.05, 0)) ) → 제거 ) )
#   ⇒ 비행 총 0.5초라 **도착 = 폭발 시각**과 정확히 맞물린다.
const FB_LEAD := 0.5           # 폭발보다 0.5초 먼저 뜬다(= 비행 시간)
const FB_FRAME_SEC := 0.06     # fireball1~4
const FB_POP_SEC := 0.1        # ScaleTo ×1.25 / 되돌림
const FB_POP_MUL := 1.25
const FB_DRIFT_SEC := 0.2      # MoveBy((start+A)*0.01)
const FB_DRIFT_K := 0.01
const FB_DASH_SEC := 0.1       # MoveTo(A)
const FB_FADE_AT := 0.05       # 낙하 도중 0.05초 뒤부터 0.05초에 걸쳐 소멸
const FB_FADE_SEC := 0.05
const FB_SPREAD := 301         # rand % 301 (시전자 앞쪽으로 퍼지는 폭)
const FB_UP_MIN := 100.0       # rand % 75 + 100 (시전자 머리 위)
const FB_UP_RAND := 75
const FB_CASTER_W := 170.0     # W 기본값 — 호출자가 `caster_w` 를 안 주면 이 값(= DRAGON_H)

# ── 도약·착지 먼지 — `MakeInterface::setDust` @0108a2b0 ─────────────────────
#
# 🔴 2026-08-06 신규 이식. `runFire_C` 가 **링 위치 +(0,80)** 에 세 번 부른다(지연 0 / 4.3 / 5.3).
#   ⚠️ 공통 지연(`this+0x228`)이 안 붙는 `_C` 계열이다.
# 자산은 `skill/ultimate/earth/earth_dust1·2`(땅 각성기와 같은 프레임 — 원작도 공용).
#   dust1: pos+(0, −80*S)      setScale(0.2) · 숨김
#     → Delay(d) → Show → Spawn( Seq(Delay(0.75), FadeTo(1.0, 0)),
#                                Seq(ScaleTo(0.25, 0.5), ScaleTo(1.5, 0.75, 0.5)) ) → 제거
#   dust2: dust1 + (rand%200 − 100, 75)   setScale(0.5) · 숨김 · z=+10
#     → Delay(d) → Show → Spawn( MoveBy(1.85, (rand%150 − 75, 50)), ScaleTo(1.85, 0.75),
#                                Seq(Delay(0.75), FadeTo(1.1, 0)) ) → 제거
const DUST_EL := "earth"                      # 프레임이 사는 아틀라스(원작도 earth 것을 쓴다)
const FIRE_DUST_AT := [0.0, 4.3, 5.3]         # runFire_C 의 setDust 3회
const DUST_UP := 80.0                         # 호출자가 얹는 +80, setDust 안의 −80*S

## 아직 `run<El>` 을 이식하지 않은 속성의 임시 골격 — 최장 프레임 계열 1개.
const FALLBACK_FRAME_SEC := 0.08


# ── 기준점 — `initWithDragon` @00fdef1c 의 race 스위치 (2026-08-05 재확정) ────
#
# 🔴 종전의 "화면 중앙" 가정은 **틀렸다.** 원작은 레이어 위치를 **속성별로** 잡고,
#   `init<El>` 의 모든 좌표(`contentSize*0.5` 기준)는 그 위치에 얹힌다(앵커 0.5/0.5).
#   레퍼런스 영상 교차검증: 불 = 시전자 왼쪽 → 불기둥이 오른쪽(≈0.66W)에서 솟고,
#   땅 = 시전자 오른쪽 → 산이 왼쪽(≈0.2W)에서 솟는다. 둘 다 아래 표와 일치.
#
#   race 스위치(초안 좌표는 cocos y-up, H=692 · `mine` = 시전자가 왼쪽 진영):
#     earth·fire·shadow : left|right ± (225, −50)      ← **시전자 반대편**(피격 진영)
#     aqua              : leftBottom|rightBottom ± (335, 262.5)   ← 반대편
#     wind·dark·chaos   : (W*0.5, 262.5 − 95 = 167.5)
#     light             : center
#     holy              : (W*0.5, 262.5)
#   반대편 판정 = `getDragonLayer()->getTag() ∈ {0xb,0xd,0xf}`(내 진영 태그)면 right.
#
# dir 은 `initFire` 실측 — `getPosition().x <= center.x ? +1 : −1` = **레이어 → 화면 중앙 방향**.
# W(좌표 수식의 `contentSize.x`) = `VisibleRect::top().x` = **화면 폭의 절반**(1024 기준 512).
const BASE_EDGE := {"earth": 225.0, "fire": 225.0, "shadow": 225.0, "aqua": 335.0}

## 연출 기준점(host 로컬, y-down). mine = 시전자가 왼쪽(내) 진영인가.
static func base_at(host: CanvasItem, el: String, mine: bool) -> Vector2:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var p: Vector2
	match el:
		"earth", "fire", "shadow":
			p = Vector2((vis.x - BASE_EDGE[el]) if mine else BASE_EDGE[el],
				vis.y * 0.5 + 50.0)                      # cocos −50 ⇒ 아래로 +50
		"aqua":
			p = Vector2((vis.x - BASE_EDGE[el]) if mine else BASE_EDGE[el],
				vis.y - 262.5)
		"wind", "dark", "chaos":
			p = Vector2(vis.x * 0.5, vis.y - 167.5)
		"holy":
			p = Vector2(vis.x * 0.5, vis.y - 262.5)
		_:                                               # light = 화면 중앙
			p = vis * 0.5
	return host.get_global_transform_with_canvas().affine_inverse() * p


# ── 진입점 ──────────────────────────────────────────────────────────────────
## 각성기 재생. host 아래에 스프라이트를 붙인다(좌표는 host 로컬).
##   ctx = {element, mine(시전자가 왼쪽 진영?), ring_at(시전자 무대 자리), caster_w(시전자 폭),
##          scale(S), speed, alive(Callable), mat}
##
## 기준점 `at` 과 방향 `dir` 은 **여기서 계산**한다(위 `base_at` — 원작 `initWithDragon`).
## 바닥 링(`init<El>_C`)만은 `CCPoint::ZERO − (0, S*87.5)` = 시전자 발밑(`ring_at`)이다.
## 반환 = 총 길이(초). 원작 `getDuration()` 콜로세움 표.
static func play(host: CanvasItem, ctx: Dictionary) -> float:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return 0.0
	var el := String(ctx.get("element", ""))
	var man := manifest(el)
	if man.is_empty():
		return 0.0
	var mine := bool(ctx.get("mine", true))
	var at := base_at(host, el, mine)
	var ring_at: Vector2 = ctx.get("ring_at", at)
	# 원작 `initFire_C` 의 W = 시전자 dragonLayer 의 contentSize.x — 불덩이가 퍼지는 폭의 기준.
	var caster_w := float(ctx.get("caster_w", 0.0))
	var s := float(ctx.get("scale", 1.0))
	# 원작 dir = 레이어가 왼쪽 절반이면 +1(중앙 쪽으로 편다), 오른쪽이면 −1.
	var ctr := _screen_center(host)
	var dir := 1.0 if at.x <= ctr.x else -1.0
	var sp := maxf(0.05, float(ctx.get("speed", 1.0)))
	var alive: Callable = ctx.get("alive", Callable())
	var mat: CanvasItemMaterial = ctx.get("mat", null)
	if mat == null:
		mat = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

	_master_veil(host, el, at, sp)       # 화면 장막(원작 0x238) — Delay(1.0) 부터 암전
	_schedule_sfx(host, el, sp)          # 속성별 효과음(libgame 리터럴 이름)
	# run<El>(+run<El>_C 링, 합체 문양 회전)은 **시전 후 2.75초**에 시작한다(마스터 타임라인).
	# 합체 문양 = 원작이 `contentSize*0.5`(= 기준점 `at`)에 놓는다(`initDark` 등).
	# wind·dark·chaos 의 기준점 y(167.5)가 이미 바닥 높이라 별도 보정이 필요 없다.
	var run_body := func() -> void:
		if alive.is_valid() and not bool(alive.call()):
			return
		if not is_instance_valid(host) or not host.is_inside_tree():
			return
		_combine_outline(host, el, at, sp)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		match el:
			"fire":   _run_fire(host, at, ring_at, s, dir, sp, mat, alive, caster_w)
			"earth":  _run_earth(host, at, dir, sp, rng)
			"aqua":   _run_aqua(host, at, ring_at, dir, sp, rng)
			"wind":   _run_wind(host, at, dir, sp, rng)
			"dark":   _run_dark(host, at, dir, sp, rng)
			"light":  _run_light(host, at, dir, sp, rng)
			"holy":   _run_holy(host, at, dir, sp, rng)
			"chaos":  _run_chaos(host, at, dir, sp, rng)
			"shadow": _run_shadow(host, at, dir, sp, rng)
			_:        _run_fallback(host, el, at, sp, mat, alive)
	var start := Timer.new()               # host 자식 Timer — 씬과 함께 정리된다(§_fire_burst 주석)
	start.one_shot = true
	start.wait_time = RUN_AT / sp
	start.autostart = true
	start.timeout.connect(run_body)
	host.add_child(start)

	# 바닥 링(`run<El>_C`)만 따로 건다 — 속성마다 시각이 다르다(§RING_AT).
	var ring_body := func() -> void:
		if alive.is_valid() and not bool(alive.call()):
			return
		if not is_instance_valid(host) or not host.is_inside_tree():
			return
		_build_ring(host, el, ring_at, s, sp, mat)   # 바닥 링만 시전자 발밑
	var rt := Timer.new()
	rt.one_shot = true
	rt.wait_time = maxf(0.01, ring_at_sec(el) / sp)
	rt.autostart = true
	rt.timeout.connect(ring_body)
	host.add_child(rt)
	return float(DURATION.get(el, 9.0)) / sp


## 피해 수치가 떠야 하는 시각(초) — 원작 `getDamageTextTime`.
## ⚠️ 2026-08-05: 실제로 숫자를 예약하는 쪽은 `UltimateLayer::calculateDamage` 였고 값이 다르다
##   (fire 는 여기 7.8, 저기 4.8). 전투 배선은 `fight.gd::_ult_dmg_plan` 을 따른다.
##   이 함수는 확인 창의 표시용으로만 남는다.
static func damage_at(element: String, speed := 1.0) -> float:
	return float(DMG_TIME.get(element, 8.0)) / maxf(0.05, speed)


# ── §4 바닥 링 ──────────────────────────────────────────────────────────────
static func _build_ring(host: CanvasItem, el: String, at: Vector2, s: float,
		sp: float, mat: CanvasItemMaterial) -> void:
	var cfg: Dictionary = RING.get(el, {})
	if cfg.is_empty():
		return
	var pfx := prefix(el)
	# cocos `base − (0, S*87.5)` = 발밑. Godot 은 y 가 아래로 자라므로 **더한다**.
	var pos := at + Vector2(0.0, s * RING_DY)

	var base := _spr(el, pfx + String(cfg["base"]))
	if base != null:
		base.position = pos
		base.z_index = 90
		base.modulate.a = 0.0          # 원작도 FadeTo 로 들어온다(시작 투명)
		base.scale *= (s + 0.25)       # 원작 `setScale(S + 0.25)` — 시작 배율부터 크다
		host.add_child(base)
		# nest = base 의 **자식**. 원작은 base 의 contentSize 중심에 놓는다 = 로컬 (0,0).
		# ⚠️ 원작 circle2 는 `setOpacity(0)` 시작이고 cocos 는 부모 알파가 전파되지 않는다 —
		#   Godot 은 전파되므로 self_modulate 로 따로 꺼 둔다(안 끄면 base 의 ×10 버스트 때
		#   문양이 화면을 다 덮는다 — 2026-08-05 땅 캡처 실측).
		if String(cfg.get("nest", "")) != "":
			var nest := _spr(el, pfx + String(cfg["nest"]))
			if nest != null:
				nest.z_index = -1
				nest.modulate.a = 0.0
				base.add_child(nest)
		_anim_ring_base(base, el, s, sp)

	var sibs: Array = cfg.get("sib", [])
	for i in sibs.size():
		var sib := _spr(el, pfx + String(sibs[i]))
		if sib == null:
			continue
		sib.position = pos
		sib.z_index = 89
		sib.modulate.a = 0.0
		host.add_child(sib)
		_anim_ring_sib(sib, el, sp, i)

	# `_C` 추가 프레임(dark shade · shadow twist) — 원작 z=5, tag 0x1883f · setScale(0)·setOpacity(0)
	# ⚠️ 종전엔 애니도 정리도 없이 영원히 남았다(2026-08-05 캡처 실측 — 대전에선 전투 내내 잔상).
	var ex := String(RING_EXTRA.get(el, ""))
	if ex != "":
		var e := _spr(el, pfx + ex)
		if e != null:
			e.position = pos
			e.z_index = 95
			e.modulate.a = 0.0
			host.add_child(e)
			var et := e.create_tween()
			et.tween_property(e, "modulate:a", 1.0, 0.5 / sp)
			et.tween_interval(4.0 / sp)
			et.tween_property(e, "modulate:a", 0.0, 0.75 / sp)
			et.tween_callback(e.queue_free)

	# 땅 전용 — `initEarth_C` 는 링 자리에 **지진 조각 5장(S×1.25) + 먼지 + 돌**을 더 깐다.
	# 레퍼런스 영상: 시전자 발밑이 통째로 먼지구름에 싸인다(+25s 오른쪽 구름).
	# 오프셋 5벌 = 레이아웃 추출값. ASSUMPTION: 등장/소멸 타이밍(runEarth_C 세부 미해독) —
	# 영상 실측(등장 run+0.3 · 유지 ~5초)으로 맞춘다.
	if el == "earth":
		var qoff := [Vector2(-100, -100), Vector2(-50, -70), Vector2(-10, -120),
			Vector2(-10, -95), Vector2(0, -100)]
		for i in qoff.size():
			var q := _spr(el, pfx + "earthquake1")
			if q == null:
				break
			q.position = pos + (qoff[i] as Vector2) * s
			q.scale *= s * 1.25
			q.z_index = 94
			q.modulate.a = 0.0
			host.add_child(q)
			var qt := q.create_tween()
			# 시전자 착지와 싱크 — 착지 i 번째에 이쪽(시전자 발밑) 바위도 솟는다.
			qt.tween_interval(EARTH_WAVES[i % EARTH_WAVES.size()] / sp)
			qt.tween_property(q, "modulate:a", 1.0, 0.2 / sp)
			qt.tween_interval(2.2 / sp)
			qt.tween_property(q, "modulate:a", 0.0, 0.75 / sp)
			qt.tween_callback(q.queue_free)
		for k in 2:
			var du := _spr(el, pfx + ("dust1" if k == 0 else "dust2"))
			if du == null:
				break
			du.position = pos + Vector2(-40.0 + 80.0 * float(k), -30.0)
			du.z_index = 96
			du.modulate.a = 0.0
			host.add_child(du)
			var dt := du.create_tween()
			dt.tween_interval(0.4 / sp)
			dt.tween_property(du, "modulate:a", 1.0, 0.3 / sp)
			dt.parallel().tween_property(du, "scale", du.scale * 1.35, 4.0 / sp)
			dt.tween_interval(3.2 / sp)
			dt.tween_property(du, "modulate:a", 0.0, 0.75 / sp)
			dt.tween_callback(du.queue_free)
		var rng2 := RandomNumberGenerator.new()
		rng2.randomize()
		for k in 8:
			var st := _spr(el, pfx + "stone")
			if st == null:
				break
			st.position = pos + Vector2(rng2.randf_range(-90.0, 90.0),
				rng2.randf_range(-70.0, 10.0))
			st.scale *= s * (float(rng2.randi() % 0x4c + 0x19) / 100.0)   # 원작 (rand%76+25)/100
			st.z_index = 95
			st.modulate.a = 0.0
			host.add_child(st)
			var stt := st.create_tween()
			stt.tween_interval((EARTH_WAVES[k % EARTH_WAVES.size()]
				+ float(rng2.randi() % 3) * 0.05) / sp)     # 착지 파도와 싱크
			stt.tween_property(st, "modulate:a", 1.0, 0.2 / sp)
			stt.tween_interval(2.2 / sp)
			stt.tween_property(st, "modulate:a", 0.0, 0.6 / sp)
			stt.tween_callback(st.queue_free)

	# `_C` 스파인(holy 날개 · shadow 본체) — 연출 길이만큼 살고 정리된다.
	var spn: Dictionary = RING_SPINE.get(el, {})
	if not spn.is_empty() and ResourceLoader.exists(String(spn["scene"])):
		var holder := Node2D.new()
		holder.position = pos
		holder.z_index = 96
		host.add_child(holder)
		var inst = (load(String(spn["scene"])) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := _find_anim_player(inst)
		if ap != null and ap.has_animation(String(spn["anim"])):
			ap.play(String(spn["anim"]))
		var life := holder.create_tween()
		life.tween_interval(maxf(1.0, (float(DURATION.get(el, 9.0)) - RUN_AT - 0.75)) / sp)
		life.tween_property(holder, "modulate:a", 0.0, 0.75 / sp)
		life.tween_callback(holder.queue_free)


## 링 본체 안무. 8속성이 같은 계열이고 fire·shadow 만 다르다(`run<El>_C` 실측).
static func _anim_ring_base(n: Node2D, el: String, s: float, sp: float) -> void:
	var t := n.create_tween()
	match el:
		"fire":
			# 상하 진동은 별도 트윈으로 무한 반복(원작 CCRepeatForever).
			var bob := n.create_tween().set_loops()
			bob.tween_property(n, "position:y", n.position.y - FIRE_BOB, FIRE_BOB_SEC / sp)
			bob.tween_property(n, "position:y", n.position.y, FIRE_BOB_SEC / sp)
			t.tween_interval(RING_LEAD / sp)
			t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
			t.parallel().tween_property(n, "scale", n.scale * FIRE_SHRINK, FIRE_SHRINK_SEC / sp)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(n, "modulate:a", FIRE_DIM, FIRE_DIM_SEC / sp)
		"shadow":
			t.tween_interval(SHADOW_LEAD / sp)
			t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
			t.parallel().tween_property(n, "scale", n.scale * (s + 0.25), RING_BURST / sp)
			t.tween_interval(SHADOW_HOLD / sp)
			t.tween_property(n, "modulate:a", 0.0, RING_FADE_IN / sp)
		_:
			# 공통: 떠올랐다가 **10배로 퍼지며** 사라지는 충격파.
			# (시작 배율이 이미 S+0.25 라 여기서는 ×10 만 곱한다 = 원작 ScaleTo((S+0.25)*10))
			# ⚠️ 혼돈만 ×10 이 화면을 통째로 붉게 덮는다 — 영상(67.73s)에서는 발밑 타원이
			#   두 배 남짓 퍼지고 흐려질 뿐이다. 속성별 상한을 둔다(§RING_BURST_CAP).
			t.tween_interval(RING_LEAD / sp)
			t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
			t.tween_interval(RING_HOLD / sp)
			t.tween_property(n, "scale",
				n.scale * float(RING_BURST_CAP.get(el, RING_BURST_MUL)), RING_BURST / sp)
			t.parallel().tween_property(n, "modulate:a", 25.0 / 255.0, RING_DIM / sp)
			t.tween_property(n, "modulate:a", 0.0, RING_OUT / sp)
	t.tween_callback(n.queue_free)


## 링 형제(0x2329·0x232a) 안무. earth 만 지연·길이가 다르다(runEarth_C).
static func _anim_ring_sib(n: Node2D, el: String, sp: float, idx: int) -> void:
	var t := n.create_tween()
	if el == "earth":
		t.tween_interval(1.05 / sp)
		t.tween_property(n, "modulate:a", 1.0, 4.25 / sp)
		t.tween_property(n, "modulate:a", 0.0, 0.25 / sp)
	elif el == "chaos":
		# 🔴 2026-08-06 — 혼돈은 **흰 원(circle3)이 먼저** 터지고 그 다음에 붉은 원(base)이
		#   앉는다(영상 67.27 흰 → 67.33 확장 → 67.40 소멸 → 67.47 붉은). 종전의 공통
		#   `SIB_LEAD 0.4` 는 순서를 거꾸로 만들고 있었다. 링 자체도 `LEAD` 로 당겼다(§RING_AT).
		t.tween_interval(0.05 * float(idx) / sp)
		t.tween_property(n, "modulate:a", 1.0, 0.1 / sp)
		t.tween_property(n, "scale", n.scale * 6.0, 0.15 / sp)
		t.parallel().tween_property(n, "modulate:a", 0.0, 0.15 / sp)
	elif el == "shadow":
		t.tween_interval((1.5 + 0.25 * float(idx)) / sp)
		t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
		t.tween_property(n, "modulate:a", SIB_MID, 0.01 / sp)
		t.tween_property(n, "modulate:a", 0.0, RING_OUT / sp)
	else:
		t.tween_interval((SIB_LEAD + 0.1 * float(idx)) / sp)
		t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
		t.tween_property(n, "modulate:a", SIB_MID, 0.01 / sp)
		t.tween_property(n, "modulate:a", 0.0, RING_OUT / sp)
	t.tween_callback(n.queue_free)


# ── §5-fire 안무 ────────────────────────────────────────────────────────────
## 원작 `initFire`/`runFire`(20지점 폭발+지진+기둥+돌, base+4.25 백색 암전)
## + `initFire_C`/`runFire_C`(시전자 머리 위 **불덩이 20발**이 각 지점으로 낙하, 링 먼지 3방).
##
## 🔴 2026-08-06 — 두 가지를 바로잡았다.
##   ① 폭발·섬광·장막에 속성 공통 지연 `this+0x228`(불 = 1.0초)을 붙였다(§ELEMENT_DELAY).
##   ② 불덩이 낙하를 이식했다 — 종전엔 기둥만 솟아 "예고 없이 터지는" 그림이었다.
static func _run_fire(host: CanvasItem, at: Vector2, ring_at: Vector2, s: float, dir: float,
		sp: float, mat: CanvasItemMaterial, alive: Callable, caster_w: float) -> void:
	var pfx := prefix("fire")
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var w_half := vis.x * 0.5           # 원작 W = contentSize.x = VisibleRect::top().x = 화면 폭 절반
	# 🔴 2026-08-05 영상 프레임 실측 — 불의 dir 은 **바깥 방향**이다: 첫 기둥(+0.25W)이
	#   화면 바깥 가장자리(0.93W)에서 서고 캐스케이드가 중앙 쪽으로 쓸려 온다.
	#   (물 상어의 진입 방향 실측과 반대 부호 — initFire/initAqua 가 각자 dir 을 계산하며
	#    디컴프의 비교 방향이 흐려 두 실측을 각자 따른다.)
	dir = -dir
	var ed := elem_delay("fire")        # `this+0x228` — 폭발 계열에만 붙는다
	# 원작 k = 시전자 몸통(tag 1)의 scaleX 부호. 우리 쪽에서는 시전자(ring_at)에서 폭발
	# 진영(at)으로 향하는 부호로 잡는다 — 불덩이가 시전자 **앞쪽**에 뜬다(영상 실측).
	var k := 1.0 if at.x >= ring_at.x else -1.0
	# 🔵 2026-08-06 — 스프라이트 좌우 반전은 **k 의 반대**다. `fire_fireball1~4` 는 머리(밝은
	#   덩어리)가 왼쪽 아래, 꼬리가 오른쪽 위로 그려져 있어 **왼쪽 아래로 날아가는 그림**이다
	#   (프레임 4장 전수 확인). 원작도 진영 스프라이트를 뒤집어 쓰므로(우리 `_build_side` 의
	#   `mine → scale.x < 0` 과 같은 규약) 왼쪽 진영 시전자에게는 반전이 걸린다.
	#   ⚠️ 뿌리는 방향(k)과 반전(flip)이 반대 부호인 건 `dir = -dir`(위)과 같은 계열의
	#     변환본 규약 차이다 — 한쪽 부호만 바꾸면 다른 쪽이 틀어지니 둘을 따로 둔다.
	var flip := -k
	var cw := caster_w if caster_w > 1.0 else FB_CASTER_W
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in FIRE_POINTS.size():
		var p: Array = FIRE_POINTS[i]
		# 원작 앵커표(`this + i*8 + 0x2d8`) = 기준점 + `dir*(W*wf + dx)` + dy.
		# cocos y-up 이라 dy 부호를 뒤집어 Godot 으로 옮긴다.
		var pos := at + Vector2(dir * (w_half * float(p[0]) + float(p[1])), -float(p[2]))
		# z = 장막 위 밑단(90) + 원작 층×5.
		var z := 90 + int(FIRE_Z[i]) * 5
		_fire_burst(host, pfx, pos, z, (ed + float(FIRE_DELAYS[i])) / sp,
			rng.randi() % 6 + FIRE_STONE_MIN, s, sp, mat, alive, rng)
		# 그 지점으로 떨어지는 불덩이 — 폭발 0.5초 전에 시전자 머리 위에서 출발한다.
		var from := ring_at + Vector2(k * (-0.5 * cw + float(rng.randi() % FB_SPREAD)),
			-(FB_UP_MIN + float(rng.randi() % FB_UP_RAND)))
		_fire_ball(host, pfx, from, pos, z, (ed + float(FIRE_DELAYS[i]) - FB_LEAD) / sp,
			flip, s, sp, alive)

	# 링 자리 먼지 3방 — `runFire_C` 의 `MakeInterface::setDust`(공통 지연 없음).
	# 원작이 넘기는 좌표 = **링 노드(tag 9000)의 위치 + (0,80)**. 링은 base − (0,S*87.5)(cocos)
	# 이므로 우리 y-down 으로는 `ring_at + s*RING_DY`. setDust 안에서 다시 −80*S 되므로
	# S=1 이면 결국 링 자리에 정확히 얹힌다(발밑) — 종전엔 base 를 넘겨 가슴께에 떴다.
	var dust_at := ring_at + Vector2(0.0, s * RING_DY - DUST_UP)
	for d in FIRE_DUST_AT:
		_ring_dust(host, dust_at, float(d) / sp, s, sp, rng, alive)

	# 화면 백색 암전 — 원작 `runFire` 의 `CCLayerColor(0xffffff)`
	var flash := _screen_veil(host, at, Color(1, 1, 1), Z_FLASH)
	var ft := flash.create_tween()
	ft.tween_interval((ed + FIRE_FLASH_AT) / sp)
	ft.tween_property(flash, "color:a", 1.0, FIRE_FLASH_IN / sp)
	ft.tween_interval(FIRE_FLASH_HOLD / sp)
	ft.tween_property(flash, "color:a", 0.0, FIRE_FLASH_OUT / sp)
	ft.tween_callback(flash.queue_free)


## 불덩이 한 발 — 원작 `initFire_C` 배치 + `runFire_C` 안무(§FB_* 상수의 주석이 원문).
##
## 시전자 머리 위에서 `scale 0` 으로 대기하다가, 폭발 0.5초 전에 팝업(×1.25 → ×1)하고
## 살짝 밀린 뒤 **0.1초 만에 폭발 지점으로 내리꽂히며** 사라진다 = 도착 = 폭발.
## `flip` = 스프라이트 좌우 부호(±1). 프레임이 왼쪽 아래로 날아가게 그려져 있어
## 오른쪽으로 날 때 −1 이다 — 호출부(`_run_fire`)의 주석 참조.
static func _fire_ball(host: CanvasItem, pfx: String, from: Vector2, to: Vector2,
		z: int, delay: float, flip: float, s: float, sp: float, alive: Callable) -> void:
	var n := _spr("fire", pfx + "fireball1")
	if n == null:
		return
	n.position = from
	n.z_index = z
	n.scale = Vector2.ZERO                 # 원작 setScale(0)
	host.add_child(n)
	# 원작 MoveBy 는 `(출발점 + 도착점) * 0.01` — 레이어 원점 기준 좌표의 1% 만큼 밀린다.
	var drift: Vector2 = (from + to) * FB_DRIFT_K
	var t := n.create_tween()
	t.tween_interval(maxf(0.01, delay))
	t.tween_callback(func() -> void:
		if not is_instance_valid(n):
			return
		if alive.is_valid() and not bool(alive.call()):
			n.queue_free()
			return
		_loop_frames(n, "fire", pfx + "fireball%d", 1, 4, FB_FRAME_SEC / sp))
	t.tween_property(n, "scale", Vector2(flip * s * FB_POP_MUL, s * FB_POP_MUL), FB_POP_SEC / sp)
	t.tween_property(n, "scale", Vector2(flip * s, s), FB_POP_SEC / sp)
	t.tween_property(n, "position", drift, FB_DRIFT_SEC / sp).as_relative()
	# 낙하와 소멸은 원작이 `CCSpawn` 으로 겹친다 — 소멸만 0.05초 늦게 시작한다.
	t.tween_callback(func() -> void:
		if not is_instance_valid(n):
			return
		var f := n.create_tween()
		f.tween_interval(FB_FADE_AT / sp)
		f.tween_property(n, "modulate:a", 0.0, FB_FADE_SEC / sp))
	t.tween_property(n, "position", to, FB_DASH_SEC / sp)
	t.tween_callback(n.queue_free)


## 도약·착지 먼지 한 방 — 원작 `MakeInterface::setDust`(§DUST_* 상수의 주석이 원문).
## 프레임은 땅 각성기와 공용(`earth_dust1/2`)이라 아틀라스만 바꿔 부른다.
static func _ring_dust(host: CanvasItem, at: Vector2, delay: float, s: float,
		sp: float, rng: RandomNumberGenerator, alive: Callable) -> void:
	var dpfx := prefix(DUST_EL)
	var d1 := _spr(DUST_EL, dpfx + "dust1")
	if d1 == null:
		return
	var b1: Vector2 = d1.scale                 # 홀더 기본 배율 — 원작 setScale 은 **절대값**이다
	# cocos `pos + (0, −80*S)` = 아래로. Godot 은 y 가 아래로 자라므로 부호를 뒤집는다.
	d1.position = at + Vector2(0.0, DUST_UP * s)
	d1.z_index = 92                            # 링(89~96) 사이 — 장막 z 와 무관한 절대값
	d1.scale = b1 * 0.2
	d1.visible = false
	host.add_child(d1)

	var show := func(n: Node2D) -> void:
		if not is_instance_valid(n):
			return
		if alive.is_valid() and not bool(alive.call()):
			n.queue_free()
			return
		n.visible = true

	# dust1 — Spawn( Seq(Delay .75, FadeTo 1.0→0), Seq(ScaleTo .25→0.5, ScaleTo 1.5→(0.75,0.5)) )
	var t1 := d1.create_tween()
	t1.tween_interval(maxf(0.01, delay))
	t1.tween_callback(show.bind(d1))
	t1.tween_property(d1, "scale", b1 * 0.5, 0.25 / sp)
	t1.tween_property(d1, "scale", Vector2(b1.x * 0.75, b1.y * 0.5), 1.5 / sp)
	t1.tween_callback(d1.queue_free)
	var f1 := d1.create_tween()                # Spawn 의 다른 갈래 = 별도 트윈
	f1.tween_interval(maxf(0.01, delay) + 0.75 / sp)
	f1.tween_property(d1, "modulate:a", 0.0, 1.0 / sp)

	var d2 := _spr(DUST_EL, dpfx + "dust2")
	if d2 == null:
		return
	var b2: Vector2 = d2.scale
	d2.position = d1.position + Vector2(float(rng.randi() % 200) - 100.0, -75.0)
	d2.z_index = d1.z_index + 10
	d2.scale = b2 * 0.5
	d2.visible = false
	host.add_child(d2)

	# dust2 — Spawn( MoveBy 1.85, ScaleTo 1.85→0.75, Seq(Delay .75, FadeTo 1.1→0) )
	var t2 := d2.create_tween()
	t2.tween_interval(maxf(0.01, delay))
	t2.tween_callback(show.bind(d2))
	t2.tween_property(d2, "position",
		Vector2(float(rng.randi() % 150) - 75.0, -50.0), 1.85 / sp).as_relative()
	t2.parallel().tween_property(d2, "scale", b2 * 0.75, 1.85 / sp)
	t2.tween_callback(d2.queue_free)
	var f2 := d2.create_tween()
	f2.tween_interval(maxf(0.01, delay) + 0.75 / sp)
	f2.tween_property(d2, "modulate:a", 0.0, 1.1 / sp)


## 폭발 지점 하나 — 원작 `initFire` 배치 + `runFire` 안무를 그대로.
##
## 배치(`initFire`, 앵커 i 마다):
##   `fire_fillar1`     anchor(0.5, 0) · pos=A[i]        · scale(0.5, 0) · z = Z[i]*5
##   `fire_explosion1`  anchor(0.5, 0) · pos=A[i]        · scale(0.5, 0) · z = Z[i]*5 + 1
##   `fire_earthquake`  anchor(0.5, 0) · pos=A[i]+(0,−5) · scale(0.5, 0) · z = Z[i]*5 + 2
##   `fire_stone` ×(rand%6 + 14) — **지진의 자식**, z=−1, 처음엔 숨김
##       A: local(−100 + (rand%3)*100, 0)   scale (rand%8)*0.1+0.25  rot rand%361
##       B: local(−75 + (rand%31)*5, +25)   scale (rand%4)*0.25+0.5  rot rand%360  (조건부)
##       ⚠️ 원작 local 은 지진의 **왼쪽 아래** 기준이라 x 에 폭/2 가 붙는다 —
##          우리 홀더 원점은 앵커(0.5,0)=아래 **가운데**라 그 항이 상쇄돼 위 값이 된다.
##
## 안무(`runFire`, d = FIRE_DELAYS[i]):
##   폭발    Delay(d)         → ScaleTo(0.1, 1.0)  → 애니 explosion2~6
##                            → Spawn(FadeTo(0.1,0), ScaleTo(0.1,1.25)) → 제거
##   화염기둥 Delay(0.225 + d) → ScaleTo(0.1, 1.25) → 애니 fillar3~7 → 제거
##   지진    Delay(0.225 + d) → ScaleTo(0.1, 1.1) → ScaleTo(0.05, 1.0)
##                            → Delay(0.75) → FadeTo(1.0, 0) → 제거
##   ⇒ 셋 다 **세로 0 에서 솟는다**(scaleY 0 시작). 종전엔 통짜로 떠 있다가 페이드만 했다.
static func _fire_burst(host: CanvasItem, pfx: String, pos: Vector2, zbase: int,
		delay: float, n_stone: int, s: float, sp: float, mat: CanvasItemMaterial,
		alive: Callable, rng: RandomNumberGenerator) -> void:
	var pillar := _spr_a("fire", pfx + "fillar1", BOTTOM)
	var expl := _spr_a("fire", pfx + "explosion1", BOTTOM)
	var quake := _spr_a("fire", pfx + "earthquake", BOTTOM)
	for pair in [[pillar, zbase], [expl, zbase + 1], [quake, zbase + 2]]:
		var n: Node2D = pair[0]
		if n == null:
			continue
		n.position = pos + (Vector2(0.0, 5.0) if n == quake else Vector2.ZERO)
		n.z_index = int(pair[1])
		n.scale = Vector2(FIRE_START_SX, 0.0)      # 원작 setScaleX(0.5) · setScaleY(0)
		host.add_child(n)

	# 돌 — 지진의 **자식**이라 지진과 함께 솟았다가 튄다.
	var stones: Array = []
	if quake != null:
		for k in n_stone:
			var st := _spr("fire", pfx + "stone")
			if st == null:
				break
			st.position = Vector2(-100.0 + float(rng.randi() % 3) * 100.0, 0.0)
			st.scale *= float(rng.randi() % 8) * 0.1 + 0.25
			st.rotation_degrees = float(rng.randi() % 361)
			st.z_index = -1
			st.visible = false
			quake.add_child(st)
			stones.append(st)
			if k > rng.randi() % 3:
				continue
			var st2 := _spr("fire", pfx + "stone")
			if st2 == null:
				continue
			st2.position = Vector2(-75.0 + float(rng.randi() % 31) * 5.0, -25.0)
			st2.scale *= float(rng.randi() % 4) * 0.25 + 0.5
			st2.rotation_degrees = float(rng.randi() % 360)
			st2.z_index = -1
			st2.visible = false
			quake.add_child(st2)
			stones.append(st2)

	var go := func() -> void:
		if alive.is_valid() and not bool(alive.call()):
			return
		# 기둥 하나 = 타격 하나 — 원작은 타격마다 효과음이 배선된다(사용자 확정 2026-08-05).
		Bgm.sfx("effect_fire_fillar", 0.5)
		if is_instance_valid(expl):
			var et := expl.create_tween()
			et.tween_property(expl, "scale", Vector2.ONE, 0.1 / sp)
			et.tween_callback(func() -> void:
				_play_frames(expl, "fire", pfx + "explosion%d", 2, 6, FIRE_EXPL_SEC / sp))
			et.tween_interval(FIRE_EXPL_SEC * 5.0 / sp)
			et.tween_property(expl, "modulate:a", 0.0, 0.1 / sp)
			et.parallel().tween_property(expl, "scale", Vector2.ONE * 1.25, 0.1 / sp)
			et.tween_callback(expl.queue_free)
		if is_instance_valid(pillar):
			# 세로는 **기둥 꼭대기가 화면 밖으로 나가도록** 늘린다 — 원작 영상에서 기둥
			# 윗단(프레임의 평평한 캔버스 끝)이 화면 안에 보이는 프레임이 없다.
			# ASSUMPTION: 원작 리터럴은 ScaleTo(0.1, 1.25) 균일이지만 fillar 프레임(323px)
			# ×1.25 로는 위쪽 앵커점이 화면 안에 남는 지점이 있어, 세로만 필요한 만큼 더 편다.
			var fh := 323.0 * Design.ASSET_SCALE
			var sy := maxf(1.25, (pos.y + 40.0) / fh)
			var lt := pillar.create_tween()
			lt.tween_interval(FIRE_LAG / sp)
			lt.tween_property(pillar, "scale", Vector2(1.25, sy), 0.1 / sp)
			lt.tween_callback(func() -> void:
				_play_frames(pillar, "fire", pfx + "fillar%d", 3, 7, FIRE_PILLAR_SEC / sp))
			lt.tween_interval(FIRE_PILLAR_SEC * 5.0 / sp)
			lt.tween_property(pillar, "modulate:a", 0.0, 0.25 / sp)
			lt.tween_callback(pillar.queue_free)
		if is_instance_valid(quake):
			var qt := quake.create_tween()
			qt.tween_interval(FIRE_LAG / sp)
			qt.tween_property(quake, "scale", Vector2(1.1, 1.1), 0.1 / sp)
			qt.tween_property(quake, "scale", Vector2.ONE, 0.05 / sp)
			qt.tween_interval(0.75 / sp)
			qt.tween_property(quake, "modulate:a", 0.0, 1.0 / sp)
			qt.tween_callback(quake.queue_free)
		for st in stones:
			if not is_instance_valid(st):
				continue
			st.visible = true
			# 원작 `runFire` 의 돌 시퀀스(`resolve_actions.py` 로 조립 순서 복원):
			#   d  = (dx*(rand%3+1) + rand%90, (rand%8)*10 − 25),  dx = 돌.x − 폭발 중심.x
			#   t  = (rand%4)*0.125 + 0.125,  sign = d.x ≥ 0 ? +1 : −1
			#   Spawn(EaseInOut(JumpBy(t,     d,    (rand%400)+150, 1), 2t), RotateBy(t,     sign*((rand%1080)+1080)))
			#   Spawn(EaseInOut(JumpBy(0.75t, d/5,  (rand%50)+100,  1), 2t), RotateBy(0.75t, sign*((rand%720)+720)))
			#   Spawn(EaseInOut(JumpBy(0.5t,  d/10, (rand%75)+25,   1), 2t), RotateBy(0.5t,  sign*((rand%360)+360)))
			#   Spawn(MoveBy(t, (d.x*0.1, 0)), RotateBy(t, d.x*0.1*7.5))
			#   → Delay(0.25) → FadeTo(0.75, 0) → 제거
			var dx: float = st.position.x
			var d := Vector2(dx * float(rng.randi() % 3 + 1) + float(rng.randi() % 90),
				float(rng.randi() % 8) * 10.0 - 25.0)
			var jt := float(rng.randi() % 4) * 0.125 + 0.125
			var sgn := 1.0 if d.x >= 0.0 else -1.0
			var t2: Tween = st.create_tween()
			t2.tween_interval(FIRE_LAG / sp)
			_jump_by(t2, st, d, float(rng.randi() % 400) + 150.0, 1, jt / sp, jt + jt)
			t2.parallel().tween_property(st, "rotation_degrees",
				sgn * (float(rng.randi() % 1080) + 1080.0), jt / sp).as_relative()
			_jump_by(t2, st, d / 5.0, float(rng.randi() % 50) + 100.0, 1, jt * 0.75 / sp, jt + jt)
			t2.parallel().tween_property(st, "rotation_degrees",
				sgn * (float(rng.randi() % 720) + 720.0), jt * 0.75 / sp).as_relative()
			_jump_by(t2, st, d / 10.0, float(rng.randi() % 75) + 25.0, 1, jt * 0.5 / sp, jt + jt)
			t2.parallel().tween_property(st, "rotation_degrees",
				sgn * (float(rng.randi() % 360) + 360.0), jt * 0.5 / sp).as_relative()
			t2.tween_property(st, "position", Vector2(d.x * 0.1, 0.0), jt / sp).as_relative()
			t2.parallel().tween_property(st, "rotation_degrees", d.x * 0.1 * 7.5, jt / sp)				.as_relative()
			t2.tween_interval(0.25 / sp)
			t2.tween_property(st, "modulate:a", 0.0, 0.75 / sp)
			t2.tween_callback(st.queue_free)

	# ⚠️ `SceneTree.create_timer` 는 host 보다 오래 산다 — 씬이 먼저 사라지면 `go` 가 붙든
	#    노드들이 이미 free 돼 "Lambda capture was freed" 가 무더기로 뜬다(스크린샷 도구에서 실측).
	#    host 의 자식 Timer 로 만들면 host 와 함께 정리된다.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(0.01, delay)
	timer.autostart = true
	timer.timeout.connect(go)
	host.add_child(timer)


# ── 합체 외곽선(회전 문양) — `init<El>` + `run<El>` ─────────────────────────
#
# 네 속성만 갖는다. 원작 `initDark` 실측:
#   `CCLayerColor`(흰색, 외곽선 프레임 크기, 앵커 0.5/0.5)를 레이어 위치에 놓고
#   **setScale(2.25)** · setRotation(0.375) 로 세운 뒤 tag 0x1d650 으로 붙이고,
#   그 안에 `battle/combine_outline_white`(0x18832) 와 `battle/<n>/combine_outline`(0x18831) 을
#   가운데 겹친다. `runDark` 가 **`EaseInOut(RotateBy(4.5초, 720°), −0.25)`** 로 두 바퀴 돌린다.
#
# 원본 프레임은 전부 보유·변환돼 있다(`battle_combine_*` · `battle_ui`).
const COMBINE := {
	"dark":   {"dir": "battle_combine_dark",      "key": "battle_dark_combine_outline"},
	"shadow": {"dir": "battle_combine_blackwind", "key": "battle_blackwind_combine_outline"},
	"wind":   {"dir": "battle_combine_hurricane", "key": "battle_hurricane_combine_outline"},
	"chaos":  {"dir": "battle_combine_amagethon", "key": "battle_amagethon_combine_outline"},
}
const COMBINE_WHITE_DIR := "battle_ui"
const COMBINE_WHITE_KEY := "battle_combine_outline_white"
## 🔵 2026-08-05 슬롯 확정 — `vtable+0x58 = setScaleX` · `+0x68 = setScaleY`.
##   근거 ①: `AlchemyTutorialLayer.c:534` 가 `(*+0x68)(692.0 / contentSize.height)` 를 부른다
##           — 디자인 높이를 **세로만** 맞추는 호출이라 setScaleY 말고는 될 수 없다.
##   근거 ②: 이미 확정된 슬롯들과 cocos2d-x 2.x `CCNode` 선언 순서가 정확히 맞물린다
##           (0x30 setZOrder · 0x40 getZOrder · **0x58 setScaleX · 0x60 getScaleX ·
##            0x68 setScaleY · 0x70 getScaleY** · 0x78 setScale · 0x90 setPosition ·
##            0xb0~0xc8 position X/Y · 0xd0~0xe8 skew · 0xf0 setAnchorPoint ·
##            0x110 getContentSize · 0x128/0x130 setRotation/getRotation).
##   근거 ③: `runFire` 가 `(*+0x70)()` 반환값으로 좌표를 나눈다 = getScaleY.
##
##   ⇒ 컨테이너는 **(2.25, 0.375) 로 납작**하다. 종전에 "띠로 보여 앞뒤가 안 맞는다"고 판단한 건
##      **회전을 컨테이너에 걸었기 때문**이었다. 원작은 회전을 **자식 두 장**(흰 외곽선 0x18832 ·
##      속성 외곽선 0x18831)에 각각 걸고 컨테이너는 가만히 둔다 ⇒ **바닥에 누운 원근 링이 도는**
##      그림이 된다. 이제 앞뒤가 맞는다.
const COMBINE_SCALE := 2.25        # setScaleX(0x40100000)
const COMBINE_SCALE_Y := 0.375     # setScaleY(0x3ec00000)
const COMBINE_SPIN_SEC := 4.5
const COMBINE_SPIN_DEG := 720.0
## 속성 외곽선(0x18831)의 `Delay(0.25) → FadeTo(0.75,200) → Delay(<hold>) → FadeTo(<out>, 0)`.
## 🔴 2026-08-06 — 종전 3.5/0.5 는 `initDark` 를 읽고 4속성에 공통으로 쓴 값이었다.
##   `runWind` 실측은 **4.15 / 0.1** 이라 링이 원작보다 1.15초 일찍 걷혔다. 속성별로 가른다.
##   (dark·chaos·shadow 는 재대조 전까지 종전 값 유지 — 근거를 확인하면 여기 추가한다.)
const COMBINE_HOLD := {"wind": 4.15}
const COMBINE_OUT := {"wind": 0.1}
const COMBINE_HOLD_DEF := 3.5
const COMBINE_OUT_DEF := 0.5
## `RotateBy(<초>, 720°)` — dark 는 4.5(`initDark`), wind 는 **5.25**(`runWind` 실측).
const COMBINE_SPIN := {"wind": 5.25}

static func _combine_outline(host: CanvasItem, el: String, at: Vector2, sp: float) -> void:
	var c: Dictionary = COMBINE.get(el, {})
	if c.is_empty():
		return
	# `run<El>` 액션이라 속성 공통 지연(`this+0x228`)이 앞에 붙는다 — 바닥 링(`run<El>_C`)과 달리.
	var ed := elem_delay(el)
	var hold := float(COMBINE_HOLD.get(el, COMBINE_HOLD_DEF))
	var out := float(COMBINE_OUT.get(el, COMBINE_OUT_DEF))
	# 컨테이너 = 원작 `CCLayerColor`(tag 0x1d650). 눌린 배율만 갖고 **회전하지 않는다**.
	var holder := Node2D.new()
	holder.position = at
	holder.z_index = 85                 # 장막(Z_VEIL) 위 · 바닥 링(89~) 아래
	holder.scale = Vector2(COMBINE_SCALE, COMBINE_SCALE_Y)
	host.add_child(holder)
	# 흰 외곽선(0x18832) — 원작 `setScale(0)` 으로 시작해 `EaseIn(ScaleTo(0.25, 1.0), 0.5)` 로 편다.
	var w := AtlasUI.spr_cocos(COMBINE_WHITE_DIR, COMBINE_WHITE_KEY)
	if w != null:
		w.z_index = 1
		w.scale = Vector2.ZERO
		holder.add_child(w)
		var wt := w.create_tween()
		wt.tween_interval(maxf(0.01, ed) / sp)
		wt.tween_property(w, "scale", Vector2.ONE, 0.25 / sp).set_ease(Tween.EASE_IN)
		wt.tween_property(w, "modulate:a", 0.0, 0.75 / sp)
		wt.tween_callback(w.queue_free)
	# 속성 외곽선(0x18831) — 원작 `setOpacity(0)` 으로 시작해 `Delay(0.25) → FadeTo(0.75, 200)`.
	var o := AtlasUI.spr_cocos(String(c["dir"]), String(c["key"]))
	if o != null:
		o.z_index = 2
		o.modulate.a = 0.0
		holder.add_child(o)
		var ot := o.create_tween()
		ot.tween_interval((ed + 0.25) / sp)
		ot.tween_property(o, "modulate:a", 200.0 / 255.0, 0.75 / sp)
		ot.tween_interval(hold / sp)
		ot.tween_property(o, "modulate:a", 0.0, out / sp)
	if holder.get_child_count() == 0:
		holder.queue_free()
		return
	# 회전은 **컨테이너가 아니라 자식마다** — 원작이 tag 0x18832·0x18831 에 각각 건다.
	# ⚠️ 원작 인자는 `CCEaseInOut(RotateBy(4.5, 720°), −0.25)` 인데 **rate 가 음수**다.
	#    Cocos 식(`0.5·t^rate`)에 넣으면 t→0 에서 발산해 첫 프레임이 720°를 몇 바퀴 넘겨 버린다
	#    ⇒ 그대로 쓸 수 없다. 회전량·시간은 실측 그대로 두고 곡선만 통상 sine in/out 으로 둔다.
	var spin := float(COMBINE_SPIN.get(el, COMBINE_SPIN_SEC))
	for ch in holder.get_children():
		var n2 := ch as Node2D
		var st: Tween = n2.create_tween()
		st.tween_interval(maxf(0.01, ed) / sp)
		st.tween_property(n2, "rotation_degrees", COMBINE_SPIN_DEG, spin / sp)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 정리는 **holder 에 매인 트윈**으로 — SceneTreeTimer 는 holder 보다 오래 살아
	# 씬이 먼저 사라지면 "Lambda capture was freed" 경고를 낸다.
	# 수명 = 회전이 끝나는 시각과 알파 시퀀스가 끝나는 시각 중 **늦은 쪽**(원작은 둘이 한 Spawn).
	var ht: Tween = holder.create_tween()
	ht.tween_interval((ed + maxf(spin, 0.25 + 0.75 + hold + out) + 0.1) / sp)
	ht.tween_callback(holder.queue_free)


# ── 각성기 이름 배너 — ⚫ 컷 (2026-08-05) ───────────────────────────────────
#
# 원작 `showUltimateName` @01005e1c (19,776B) 은 클래스 최대 함수인데 **프레임 리터럴이 0개**로
# `StringManager::getString` + `CCLabelBMFont::create` 19회만 부른다. 우리는 그 안무까지
# 이식했었으나 **원작 실제 화면에는 텍스트가 없다**(사용자 확정 2026-08-05).
#
# 근거가 맞아떨어진다 — `grep -rn showUltimateName docs/ref/orig_code/decomp/*.c` 결과가
# **정의 한 곳뿐이고 호출자가 없다.** 만들다 만 채 남은 죽은 코드다.
# 되살릴 근거(호출 경로)가 나오면 git 이력 `449e795` 이전 판에 안무·문구가 통째로 있다.


# ── 속성별 안무 ─────────────────────────────────────────────────────────────
#
# 아래 8개는 각 `run<El>` 의 **박자(CCDelayTime)·변형(Scale/Rotate/Move)·프레임 수**를 실측해
# 옮긴 것이다. ⚠️ 원작의 `CCSequence` **조립 순서**는 Ghidra 가 지역변수로 흩어 놔 자동 복원이
# 안 된다(§8 도구 한계) — 그래서 **어느 노드에 어떤 액션이 몇 초로 걸리는지**는 실측이고,
# 그것들을 잇는 순서 일부는 우리가 읽어 재구성했다. 재구성한 곳만 `# ASSUMPTION:` 을 단다.

## 흩뿌리는 스프라이트 무리 — 여러 속성이 같은 꼴을 쓴다(거품 49 · 별 750 · 낙석 …).
##   n      = 개수(원작 루프 상한)
##   spread = 뿌리는 반경(x, y)
##   each   = func(node, i, rng) — 개별 안무
static func _swarm(host: CanvasItem, el: String, key: String, n: int, at: Vector2,
		spread: Vector2, z: int, rng: RandomNumberGenerator, each: Callable) -> void:
	for i in n:
		var s := _spr(el, key)
		if s == null:
			return                                # 프레임이 없으면 무리 자체를 만들지 않는다
		s.position = at + Vector2(
			rng.randf_range(-spread.x, spread.x), rng.randf_range(-spread.y, spread.y))
		s.z_index = z
		host.add_child(s)
		each.call(s, i, rng)


## 화면 전체를 덮는 색 막(물속 색조 · 백색 암전 등).
##
## ⚠️ host 는 화면 원점이 아닐 수 있다 — 대전에서는 씬 Control(원점=화면)이지만 확인 창에서는
##    무대 노드다(원점이 화면 한가운데). 그래서 **시전 지점 기준으로 사방 한 화면씩** 덮는다.
##    (2026-08-05 실측: 종전엔 확인 창에서 막이 우하단 1/4 에만 깔렸다.)
static func _screen_veil(host: CanvasItem, at: Vector2, col: Color, z: int) -> ColorRect:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var r := ColorRect.new()
	r.color = Color(col.r, col.g, col.b, 0.0)
	r.position = at - vis
	r.size = vis * 2.0
	r.z_index = z
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(r)
	return r


# ── earth (9.0초) — 산이 솟고 파편이 회전하며 낙석이 쏟아진다 ────────────────
## 원작 `initEarth` + `runEarth`: 기준점 = 레이어 중심 + (0, 37.5).
##   · `earth_mountain`(앵커 (0.5,0), (0,−210), z=2) — ScaleTo(0, 0.2) → ScaleTo(2.0, 0.5)
##   · `earth_earthquake1` ×4 — (−130,−50)·(120,−20)·(−30,−140)·(60,−120), z=1,1,4,3
##     **RotateBy(0.875초, 3600°)** = 10바퀴 회전
##   · 낙석 `earth_stone` — JumpBy(0.5 / 0.25 / 0.125, 높이 h×0.75 / h×0.25) → FadeTo(0.75, 0)
##   · `earth_earthquake2`(0,−100) — Delay(2.5) … Delay(3.15) → FadeTo(0.75, 0)
##   · 먼지 `earth_dust1/2` — ScaleTo(4.0, 1.5)
const EARTH_BASE_DY := 37.5
const EARTH_QUAKE_POS := [Vector2(-130.0, -50.0), Vector2(120.0, -20.0),
	Vector2(-30.0, -140.0), Vector2(60.0, -120.0)]
const EARTH_QUAKE_Z := [1, 1, 4, 3]
const EARTH_SPIN_SEC := 0.875
const EARTH_SPIN_DEG := 3600.0
## 시전자 착지 시각(run 기준) — `actionEarth_C` 통통 점프 6회의 착지와 1:1(사용자 실측:
## "착지할 때마다 양측 바위가 나타난다"). caster_fx.earth 의 홉 체인에서 유도.
const EARTH_WAVES := [1.45, 1.95, 2.45, 2.95, 3.65, 4.15]
const EARTH_LIGHT_SCALE := 1.5   # 원작 setScale(1.5) — 빛기둥 4개(0/90/180/270°)
const EARTH_STONES := 49        # 원작 `rand()%26 + 49` 의 하한

static func _run_earth(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "earth"
	var pfx := prefix(el)
	var base := at - Vector2(0.0, EARTH_BASE_DY)     # cocos +37.5(위) ⇒ Godot 은 −

	# 산 — 원작 `initEarth`: `earth_mountain` 을 base + (0, −210) 에 **anchor(0.5, 0)** 로 두고
	#   `setScaleY(0)` 으로 눌러 둔다 ⇒ 바닥에서 **솟아오른다**. (종전엔 통짜로 0.2 → 0.5 였다.)
	var mt := _spr_a(el, pfx + "mountain", BOTTOM)
	if mt != null:
		mt.position = base + Vector2(0.0, 210.0)      # cocos −210 ⇒ Godot +210
		mt.z_index = 92
		mt.scale = Vector2(1.0, 0.0)
		host.add_child(mt)
		var t := mt.create_tween()
		# 영상 실측(2026-08-05) — 산은 즉시가 아니라 **run+1.4쯤부터** 솟아 +2.5에 완성된다
		# (첫 파도들이 먼저, 산은 그 위에 늦게 선다).
		t.tween_interval(1.3 / sp)
		t.tween_callback(func() -> void:
			_play_frames(mt, el, pfx + "mountain%d", 1, 15, 0.08 / sp))
		t.tween_property(mt, "scale", Vector2.ONE, 1.3 / sp)
		t.tween_interval(1.5 / sp)
		t.tween_property(mt, "modulate:a", 0.0, 0.5 / sp)
		t.tween_callback(mt.queue_free)

	# 빛기둥 4개 — 원작 `initEarth` 끝: `earth_light` 를 base 에 **anchor(0.5,0)** · scale 1.5 ·
	#   opacity 0 · rotation i×90° 로 넷 깐다(z=2, tag 0x18893+i).
	for i in 4:
		var lg := _spr_a(el, pfx + "light", BOTTOM)
		if lg == null:
			break
		lg.position = base
		lg.scale = Vector2.ONE * EARTH_LIGHT_SCALE
		lg.rotation_degrees = float(i) * 90.0
		lg.z_index = 92
		lg.modulate.a = 0.0
		host.add_child(lg)
		var lt := lg.create_tween()
		lt.tween_interval((0.6 + float(i) * 0.1) / sp)
		# ASSUMPTION: 최대 알파 — 레퍼런스에서 광선이 화면을 지배하지 않는다(은은한 배광).
		lt.tween_property(lg, "modulate:a", 0.55, 0.25 / sp)
		lt.tween_interval(1.5 / sp)
		lt.tween_property(lg, "modulate:a", 0.0, 0.75 / sp)
		lt.tween_callback(lg.queue_free)

	# 회전 파편 4개.
	for i in EARTH_QUAKE_POS.size():
		var q := _spr(el, pfx + "earthquake1")
		if q == null:
			break
		var p: Vector2 = EARTH_QUAKE_POS[i]
		q.position = base + Vector2(dir * p.x, -p.y)
		q.z_index = 90 + int(EARTH_QUAKE_Z[i])
		host.add_child(q)
		var t2 := q.create_tween()
		t2.tween_interval((0.05 * float(i % 4)) / sp)
		t2.tween_property(q, "rotation_degrees", EARTH_SPIN_DEG, EARTH_SPIN_SEC / sp)
		t2.tween_property(q, "modulate:a", 0.0, 0.75 / sp)
		t2.tween_callback(q.queue_free)

	# 낙석 — 원작 `runEarth` 조립 순서 그대로(2026-08-05 `resolve_actions.py` 복원):
	#   Delay(base) → Delay(f + (rand%4)*0.05)
	#   → Spawn( RotateBy(0.875, 3600°),
	#            Seq( EaseInOut(JumpBy(0.5,   (2dx,−20), 2H,     1), 1.0),
	#                 EaseInOut(JumpBy(0.25,  (2dx,  0), 0.75H,  1), 0.5),
	#                 EaseInOut(JumpBy(0.125, (2dx,  0), 0.25H,  1), 0.25) ) )
	#   → FadeTo(0.75, 0) → remove
	#   dx = 돌.x − 부모 폭/2, H = 부모 contentSize.height.
	#   ⚠️ 그 부모 노드(0x240 의 자식)를 우리 구조에 대응시킬 근거가 없어 H 는 낙석 무리의
	#      세로 퍼짐(60)을 쓴다 — 비율(2 : 0.75 : 0.25)과 시간·회전은 원작 그대로다.
	# 낙석 — 🔴 2026-08-05 사용자 실측 교정: 종전의 10바퀴 회전(3600°)은 원작 화면에 없다
	#   (그 리터럴은 지진 조각 몫으로 재해석). 돌은 지진 파열과 **싱크된 파도**로 튀어올라
	#   포물선으로 떨어질 뿐이고, 구르는 정도의 약한 텀블만 갖는다.
	var stone_h := 60.0
	_swarm(host, el, pfx + "stone", EARTH_STONES, base, Vector2(200.0, stone_h), 95, rng,
		func(n: Node2D, i: int, r: RandomNumberGenerator) -> void:
			# 원작 낙석 크기 = setScale((rand%76 + 25)/100) — 0.25~1.0 의 잔돌.
			n.scale *= float(r.randi() % 0x4c + 0x19) / 100.0
			var dx := n.position.x - base.x
			# 파도 싱크 — **시전자 착지 6회**와 1:1(EARTH_WAVES).
			var lag: float = (float(EARTH_WAVES[i % EARTH_WAVES.size()])
				+ float(r.randi() % 4) * 0.05) / sp
			var tumble := (float(r.randi() % 180) + 90.0) * (1.0 if dx >= 0.0 else -1.0)
			var t3: Tween = n.create_tween()
			t3.tween_interval(lag)
			t3.tween_property(n, "rotation_degrees", tumble, 0.9 / sp).as_relative()
			var t4: Tween = n.create_tween()
			t4.tween_interval(lag)
			_jump_by(t4, n, Vector2(dx, -20.0), stone_h * 2.0, 1, 0.5 / sp, 1.0)
			_jump_by(t4, n, Vector2(dx * 0.4, 0.0), stone_h * 0.6, 1, 0.25 / sp, 0.5)
			t4.tween_property(n, "modulate:a", 0.0, 0.5 / sp)
			t4.tween_callback(n.queue_free))

	# 두 번째 지진 + 먼지.
	var q2 := _spr(el, pfx + "earthquake2")
	if q2 != null:
		q2.position = base + Vector2(0.0, 100.0)
		q2.z_index = 92
		host.add_child(q2)
		var t4 := q2.create_tween()
		t4.tween_interval(2.5 / sp)
		t4.tween_interval(3.15 / sp)
		t4.tween_property(q2, "modulate:a", 0.0, 0.75 / sp)
		t4.tween_callback(q2.queue_free)
	for k2 in 2:
		var du := _spr(el, pfx + ("dust1" if k2 == 0 else "dust2"))
		if du == null:
			break
		du.position = base
		du.z_index = 88
		host.add_child(du)
		var t5 := du.create_tween()
		t5.tween_interval(2.0 / sp)
		t5.tween_property(du, "scale", du.scale * 1.5, 4.0 / sp)
		t5.parallel().tween_property(du, "modulate:a", 0.0, 4.0 / sp)
		t5.tween_callback(du.queue_free)


# ── aqua (11.0초) — 물이 차오르고 물고기 떼가 훑은 뒤 상어가 물고 간다 ────────
#
# 🔵 2026-08-06 영상 프레임 재대조로 전면 재작성. 원작 구성(`initAqua` @00fdf62c ·
#   `runAqua` @00fe80ec, 시퀀스 = `docs/ref/design/ultimate_layer_sequences.md` L1586~):
#
#   · 수면 `aqua_surface1`(tag 0x18830) — `parent->addChild(surf, this->getZOrder()+1)` =
#     **드래곤보다 앞**. `setOpacity(100)`. 그 **자식**으로 물몸 `CCLayerColor`(tag 0x18835,
#     색 리터럴 `3.7778792e+22` → **RGBA(194,255,255,100)**, 앵커 (0.5,1))가 매달려
#     수면 아래를 채운다. 둘 다 39% 반투명이라 바닥돌·드래곤이 비친다.
#     상승 = `Delay(0x228) → JumpTo(.25,+75) → MoveBy(.5) → JumpTo(.25,+50)` = run+1.25~+2.25
#     **두 번 튀어오르는 궤적**. 소거 = `Delay(0x228) → Delay(6.25) → FadeTo(.5, 0)` = run+7.5.
#   · 거품 `aqua_bubble` **49개**(루프 상한 0x31) — pos = (rand % 화면폭, 0), scale (rand%5)×0.25.
#   · 물고기 — `switch(rand() % 5)` 로 `aqua_fish1~5` 중 하나를 골라 **40마리**(루프가
#     `iVar4 == 0x28` 에서 종료, tag 0x1883a + i). setScale (rand%6)×0.1+0.5 = 0.5~1.0.
#     이동 = `Delay(0x228) → Delay(f+2.5) → MoveTo((i%4)*.1+.1) → MoveBy(.75) → MoveBy(.75)
#     → MoveBy(.15) → MoveTo(.05)` = run+3.75 부터 ~1.85초에 걸쳐 화면을 훑고 지나간다.
#   · 상어 `aqua_shark1`(tag 0x18893) — 배치노드 **z 0**(= 드래곤 뒤. 영상 16.83s 에서
#     피격 드래곤이 이빨 사이에 또렷하다). scale 1.75 · scaleX = dir×1.75 · rotation dir×15° ·
#     pos = 화면중앙 + (dir×(중앙x + 상어폭×1.5), **−80**).
#     `Delay(0x228) → Delay(5.0)` = run+6.25 에 출발해 1.5초 만에 물고 지나간다.
#
# ⚠️ MoveTo 목적지는 스택 소실이라 **영상에서 잰다**(아래 AQUA_BITE_* 참조).
const AQUA_BUBBLES := 49        # 원작 루프 상한 0x31
const AQUA_FISH := 40           # 원작 루프 상한 0x28
const AQUA_SHARK_S := 1.75      # 원작 setScale/setScaleX(1.75)
const AQUA_WATER := Color8(194, 255, 255, 100)   # 원작 CCLayerColor 리터럴(색·알파 모두)
const AQUA_SURF_A := 100.0 / 255.0               # 원작 수면 setOpacity(100)
## 아래 시각은 전부 **`0x228` 뒤**의 값이다(`ed` 를 따로 더한다) — 표와 코드가 어긋나지 않게
## 원작 시퀀스의 `CCDelayTime` 리터럴을 그대로 적는다.
const AQUA_FADE_AT := 6.25      # 수면·물몸 `Delay(6.25) → FadeTo(0.5, 0)`
const AQUA_FISH_AT := 2.5       # `Delay(f + 2.5)` — f 는 개체별(스택 소실) → 아래에서 균등 분산
const AQUA_SHARK_AT := 5.0      # `Delay(5.0)`
## 상어 돌진 종점 — 영상 16.83s 프레임에서 실측했다(붉은 눈 표식을 자산 좌표와 정합).
## 스프라이트 중심이 **피격 지점에서 상어 반폭만큼 뒤 · 화면 중앙보다 66pt 위**에 온다
## (= 머리 끝이 피격 지점에 닿는다). 배율 정합은 `ASSET_SCALE × 1.75` 로 프레임과 일치 확인.
const AQUA_BITE_UP := 66.0

static func _run_aqua(host: CanvasItem, at: Vector2, ring_at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "aqua"
	var pfx := prefix(el)
	var ed := elem_delay(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var ctr := _screen_center(host)
	# 피격자 무대 자리 = 시전자 자리(`ring_at`)의 화면 대칭점. `at`(= `base_at` 의 ±335)은
	# 안무 기준점이라 무대 선(±ULT_DX)보다 안쪽이다 — 상어 아가리를 여기에 물리면 짧게 멈춘다.
	var prey_x := 2.0 * ctr.x - ring_at.x

	# ── 수면 + 물몸 ─────────────────────────────────────────────────────────
	# 파도 띠(PMA 스프라이트)와 물몸(ColorRect)은 페이드 방식이 달라(§_fade_pma) **형제**로
	# 두고 컨테이너를 함께 움직인다. 종전엔 물몸을 띠의 자식으로 매달아 놓고 띠를
	# `modulate:a` 로 페이드해서 밑단이 흰색으로 타 버렸다.
	var water := Node2D.new()
	water.z_index = 85                       # 드래곤(Z_ACTOR) 위 — 원작 getZOrder()+1
	host.add_child(water)
	var band := _spr_a(el, pfx + "surface1", Vector2(0.5, 0.5))
	if band != null:
		var man0 := manifest(el)
		var info: Dictionary = man0.get(pfx + "surface1", {})
		var fw := float(info.get("w", 1.0)) * Design.ASSET_SCALE
		var fh := float(info.get("src", [480, 102])[1]) * Design.ASSET_SCALE
		band.scale = Vector2((vis.x / fw) if fw > 1.0 else 1.0, 1.0)
		band.z_index = 1
		_set_alpha(band, AQUA_SURF_A)
		water.add_child(band)
		_loop_frames(band, el, pfx + "surface%d", 1, 4, 0.1 / sp, (ed + AQUA_FADE_AT + 0.5) / sp)

		var body := ColorRect.new()          # 띠 밑단과 같은 색 — 이음새가 없다
		body.color = AQUA_WATER
		body.size = Vector2(vis.x * 1.2, vis.y * 1.5)
		body.position = Vector2(-vis.x * 0.6, fh * 0.5 - 2.0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		water.add_child(body)

		var y0 := ctr.y + vis.y * 0.42       # 바닥 근처
		var y1 := ctr.y - vis.y * 0.28       # 다 찼을 때
		water.position = Vector2(ctr.x, y0)
		# 원작 JumpTo ×2 + MoveBy — 경유점은 스택 소실이라 3등분으로 근사(ASSUMPTION).
		var t := water.create_tween()
		t.tween_interval(ed / sp)                      # 원작 `Delay(0x228) → JumpTo…`
		_arc(t, water, Vector2(ctr.x, lerpf(y0, y1, 0.4)), 75.0, 0.25 / sp)
		t.tween_property(water, "position", Vector2(ctr.x, lerpf(y0, y1, 0.75)), 0.5 / sp)
		_arc(t, water, Vector2(ctr.x, y1), 50.0, 0.25 / sp)
		# 소거 — 둘의 페이드 규약이 다르므로 각자 트윈으로.
		var tb := band.create_tween()
		tb.tween_interval((ed + AQUA_FADE_AT) / sp)
		_fade_pma(tb, band, 0.0, 0.5 / sp)
		var tw := body.create_tween()
		tw.tween_interval((ed + AQUA_FADE_AT) / sp)
		tw.tween_property(body, "color:a", 0.0, 0.5 / sp)
		tw.tween_callback(water.queue_free)

	# ── 상어 ────────────────────────────────────────────────────────────────
	var shark := _spr(el, pfx + "shark1")
	if shark != null:
		var man1 := manifest(el)
		var sk_w := float(man1.get(pfx + "shark1", {}).get("w", 200.0)) \
			* Design.ASSET_SCALE * AQUA_SHARK_S
		# 원작 리터럴: pos = 중앙 + (dir×(중앙x + 상어폭×1.5), −80). cocos y-up 이라 −80 = 아래.
		# dir 은 레이어→중앙 방향이므로 **시전자 진영 밖**에서 들어와 −dir 쪽으로 돌진한다.
		shark.position = ctr + Vector2(dir * (vis.x * 0.5 + sk_w * 1.5), 80.0)
		shark.z_index = Z_ACTOR - 1          # 원작 배치노드 z0 — 드래곤 **뒤**
		shark.scale = Vector2(dir * AQUA_SHARK_S, AQUA_SHARK_S)
		shark.rotation_degrees = dir * 15.0
		host.add_child(shark)
		_play_frames(shark, el, pfx + "shark%d", 2, 8, 0.03 / sp)
		# 머리 끝이 피격자에 닿는 자리(영상 실측, 위 AQUA_BITE_UP 주석).
		var bite := Vector2(prey_x + dir * sk_w * 0.5, ctr.y - AQUA_BITE_UP)
		var kt := shark.create_tween()
		kt.tween_interval((ed + AQUA_SHARK_AT) / sp)
		kt.tween_property(shark, "position", bite, 0.42 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		kt.parallel().tween_property(shark, "rotation_degrees", dir * 4.0, 0.42 / sp)
		# 원작 `ScaleTo(0.15, dir×1.8, 1.825)` → 물기 펄스 → 복귀
		kt.parallel().tween_property(shark, "scale",
			Vector2(dir * 1.8, 1.825), 0.15 / sp).set_delay(0.27 / sp)
		kt.tween_property(shark, "scale", Vector2(dir * AQUA_SHARK_S, 1.7), 0.05 / sp)
		kt.tween_property(shark, "scale", Vector2(dir * AQUA_SHARK_S, AQUA_SHARK_S), 0.05 / sp)
		# 물고 지나간다 — `MoveBy(0.5) + RotateBy(dir×−2.5)` → `MoveBy(0.5) + FadeTo(0.5, 0)`
		kt.tween_property(shark, "position", Vector2(-dir * 320.0, 10.0), 0.5 / sp)\
			.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		kt.parallel().tween_property(shark, "rotation_degrees", -dir * 8.0, 0.5 / sp)
		kt.tween_property(shark, "position", Vector2(-dir * 260.0, 0.0), 0.5 / sp).as_relative()
		_fade_pma(kt.parallel(), shark, 0.0, 0.5 / sp)
		kt.tween_callback(shark.queue_free)

	# ── 거품 ────────────────────────────────────────────────────────────────
	# 원작은 **화면 바닥 전폭**에 뿌리고(pos = (rand % 화면폭, 0)) 물속이니 위까지 떠오른다.
	_swarm(host, el, pfx + "bubble", AQUA_BUBBLES,
		Vector2(ctr.x, ctr.y + vis.y * 0.5), Vector2(vis.x * 0.5, 0.0), 98, rng,
		func(n: Node2D, i: int, r: RandomNumberGenerator) -> void:
			n.scale *= float(i % 5) * 0.25 + 0.25          # 원작 (rand%5)×0.25
			_set_alpha(n, 0.0)
			var rise := r.randf_range(vis.y * 0.45, vis.y * 0.95)
			var t: Tween = n.create_tween()
			t.tween_interval((ed + float(i % 12) * 0.3) / sp)
			_fade_pma(t, n, 1.0, 0.2 / sp)
			t.tween_property(n, "position",
				n.position + Vector2(r.randf_range(-40.0, 40.0), -rise),
				r.randf_range(2.0, 4.0) / sp)
			t.parallel().tween_property(n, "scale", n.scale * 1.3, 2.0 / sp)
			_fade_pma(t, n, 0.0, 0.3 / sp)
			t.tween_callback(n.queue_free))

	# ── 물고기 40마리 ────────────────────────────────────────────────────────
	# 🔴 2026-08-06 — 종전엔 5종을 한 마리씩만 냈다(원작 루프 상한 0x28 = 40 을 5로 오독).
	#   영상 14.79s 프레임의 "화면을 가득 메운 떼"가 이것이다.
	var enter := ctr.x + dir * (vis.x * 0.5 + 120.0)     # 시전자 진영 밖
	var exit_x := ctr.x - dir * (vis.x * 0.5 + 220.0)    # 반대편 밖
	for i in AQUA_FISH:
		var f := _spr(el, pfx + "fish%d" % (rng.randi() % 5 + 1))
		if f == null:
			break
		var y := ctr.y + rng.randf_range(-vis.y * 0.34, vis.y * 0.3)
		var sc := float(rng.randi() % 6) * 0.1 + 0.5     # 원작 setScale (rand%6)×0.1+0.5
		f.position = Vector2(enter + dir * float(i % 8) * 90.0, y)
		f.z_index = 97
		f.scale *= sc
		if dir > 0.0:
			f.scale.x = -f.scale.x                       # 진행 방향(−dir)을 보게
		host.add_child(f)
		# 제자리 몸짓 — 원작 initAqua 의 RepeatForever(ScaleBy 왕복).
		var wob := f.create_tween().set_loops()
		wob.tween_property(f, "scale", f.scale * 1.1, 0.1 / sp)
		wob.tween_property(f, "scale", f.scale, 0.1 / sp)
		# 이동 — 원작 구간 길이 그대로(MoveTo (i%4)*.1+.1 / MoveBy .75 / .75 / .15 / MoveTo .05).
		# 첫 구간에서 이미 화면 안으로 들어온다 — 영상 14.98s(run+3.75)에 떼가 화면 한복판이다.
		var t6 := f.create_tween()
		t6.tween_interval((ed + AQUA_FISH_AT + float(i % 10) * 0.07) / sp)
		var legs := [[0.3, float(i % 4) * 0.1 + 0.1], [0.65, 0.75], [0.9, 0.75],
			[0.98, 0.15], [1.0, 0.05]]
		for leg in legs:
			t6.tween_property(f, "position", Vector2(lerpf(enter, exit_x, float(leg[0])),
				y + rng.randf_range(-40.0, 40.0)), float(leg[1]) / sp)
		t6.tween_callback(f.queue_free)


# ── wind (11.0초) — 화면을 통째로 쓸어가는 강풍 ─────────────────────────────
#
# 🔴 2026-08-06 3차 재대조. `initWind` @00fe5860 을 다시 읽어 **태그 귀속이 틀렸던 것**을
#    바로잡았다. 종전 카드는 `wind_zmoon` 을 "4장(tag 0x299a0 / 0x18832)" 이라고 적었는데,
#    `initWind` 꼬리의 addChild 4줄을 보면 정반대다:
#      batch0(this+0x240): whirl1 z=0 tag **0x299a0** · zmoon#1 z=2 tag **0x18832**
#      batch1(this+0x248): whirl4 z=2 tag **0x299a0** · zmoon#2 z=0 tag **0x18832**
#    ⇒ 0x299a0 = **회오리**, 0x18832 = **소(zmoon)**. 각 2장씩이다.
#
# 원작 구성(전부 `initWind` 리터럴):
#   ① 회오리 2겹 — 화면을 꽉 채운다.
#      whirl1: 앵커 (0.5, 0.0) · setScaleX(VisibleRect::right().x / w) · setScaleY(top().y / h)
#              ⇒ **밑변이 화면 바닥에 붙고 화면 높이만큼 올라간다** = 화면 전면
#      whirl4: 앵커 (0.4, 1.0) · setScaleX(right().x / (w*0.8)) · setScaleY(whirl1.scaleY * −0.75)
#              ⇒ 가로로 더 넓고 **세로로 뒤집힌** 겹, 기준점 +(0,10) 에 매달린다
#      둘 다 setOpacity(0) 으로 시작한다.
#   ② 바닥 먼지 45장(`0x2d` 루프, `scene/colosseum/dust{,_cover}`) — ⚫ 배율 0 이라 안 뜬다(아래 ②)
#   ③ 나무 `rand()%3` 개 · 잎 `rand()%8 + 12` 개
#   ④ 소 2장
#
# 안무(`runWind` 액션 트리, 전부 `Delay(this+0x228)` = **1.4초** 뒤에 시작):
#   본체   EaseOut(ScaleBy(5.15, 1.15, 1.05), 0.25) → ScaleBy(0.1, 1.75, 1.5) → 제거
#          ⇒ 회오리·잎·링이 **일제히 run+6.65 에 끝난다**(영상 실측 seg +7.05 와 일치)
#   나타남 Delay(0.15) → Delay(0.75) → Show → FadeTo(0.5, 255/175)
#          ∥ EaseOut(ScaleBy(3.8375, 1.25, 1.0), 0.25)
#   잔해   Delay(0.15) → [MoveBy(1.0) ∥ ScaleBy(0.9, 1.25)]
#          → [MoveBy(0.25) ∥ ScaleBy(0.25, 3.0, 0.5) ∥ FadeTo(0.25, 0)]  ← 가늘고 길게 늘어나며
#          → Place(원위치) → 알파 200 → [MoveBy(1.5) ∥ ScaleBy(1.4, 1.25)] → FadeTo(1.5, 0)
#          ⇒ 조각 하나가 **두 번** 지나간다. 초기 회전 RotateBy(0, rand%181 − 90)
#
# 프레임 애니(`initWind` 의 CCAnimation delay 리터럴):
#   whirl1→4 = 0.035초(0x3d0f5c29) · whirl4→1 = 0.025초(0x3ccccccd) · zmoon 2프레임 0.05초
#   (zmoon 은 **같은 프레임 두 장**이라 사실상 정지 그림이다)
const WIND_FADE_IN_AT := 0.9        # Delay(0.15) + Delay(0.75)
const WIND_BODY_LIFE := 5.25        # ScaleBy(5.15) + ScaleBy(0.1)
const WIND_GROW_SEC := 3.8375       # 0x40766666
const WIND_WHIRL_SEC := [0.035, 0.025]
const WIND_DEBRIS_LEAD := 0.15

static func _run_wind(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "wind"
	var pfx := prefix(el)
	var ed := elem_delay(el)                     # `this+0x228` = 1.4 — 아래 전부에 붙는다
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	# 화면 암전은 마스터 장막(`_master_veil`)이 낸다 — 종전의 개별 gloom 은 중복이라 제거.

	_wind_whirl(host, el, pfx, at, ed, sp, vis)
	_wind_debris(host, el, pfx, at, dir, ed, sp, vis, rng)
	_wind_zmoon(host, el, pfx, sp, vis, rng)


## ① 회오리 2겹 — `initWind` 의 scaleX/scaleY 식을 그대로 푼다.
##   🔴 종전엔 `scale = (vis.x/w * 1.4, vis.y/h)` 에 **중앙 앵커**로 기준점(cocos y=167.5)에
##      놓아서 화면 위 26% 가 통째로 비어 있었다(행별 표준편차 실측: 상단 20 vs 원작 50).
##      1.4 배 가로 확대도 자작이었다 — 원작은 whirl4 만 `/0.8` 로 넓다.
static func _wind_whirl(host: CanvasItem, el: String, pfx: String, at: Vector2,
		ed: float, sp: float, vis: Vector2) -> void:
	var mn: Dictionary = manifest(el).get(pfx + "whirl1", {})
	var bw := float(mn.get("w", 1.0)) * Design.ASSET_SCALE
	var bh := float(mn.get("h", 1.0)) * Design.ASSET_SCALE
	if bw <= 1.0 or bh <= 1.0:
		return
	var sy := vis.y / bh                         # setScaleY(VisibleRect::top().y / h)
	for k in 2:
		# whirl1 = 앵커 아래 가운데(밑변을 화면 바닥에), whirl4 = 앵커 (0.4, 1.0) 을 기준점에.
		var anchor := BOTTOM if k == 0 else Vector2(0.4, 1.0)
		var body := _spr_a(el, pfx + ("whirl1" if k == 0 else "whirl4"), anchor)
		if body == null:
			break
		if k == 0:
			body.scale = Vector2(vis.x / bw, sy)
			body.position = Vector2(vis.x * 0.5, vis.y)      # 밑변 = 화면 바닥
		else:
			# setScaleX(right / (w*0.8)) · setScaleY(whirl1.scaleY × −0.75) = 세로 반전 겹
			body.scale = Vector2(vis.x / (bw * 0.8), -sy * 0.75)
			body.position = at + Vector2(0.0, -10.0)         # 원작 pos + (0,10) (cocos y-up)
		body.z_index = Z_WIND_WHIRL + k          # 잎·소·링보다 **뒤** (원작 화면 실측)
		body.modulate.a = 0.0
		host.add_child(body)
		# 프레임 왕복 — whirl1 은 1→4(0.035초), whirl4 는 4→1(0.025초).
		if k == 0:
			_loop_frames(body, el, pfx + "whirl%d", 1, 4, WIND_WHIRL_SEC[0] / sp,
				(ed + WIND_BODY_LIFE) / sp)
		else:
			_loop_frames_rev(body, el, pfx + "whirl%d", 4, 1, WIND_WHIRL_SEC[1] / sp,
				(ed + WIND_BODY_LIFE) / sp)
		var s0 := body.scale
		# 배율 — 원작은 `ScaleBy(3.8375, 1.25, 1.0)`(나타남)과 `ScaleBy(5.15, 1.15, 1.05)`(본체)를
		#   **동시에** 건다(cocos 는 곱해진다). Godot 은 같은 속성에 트윈 둘을 겹치면 뒤엣것이
		#   매 프레임 덮어써 버리므로 **한 트윈으로 이어** 곱을 낸다.
		var grow := body.create_tween()
		grow.tween_interval(ed / sp)
		grow.tween_property(body, "scale", Vector2(s0.x * 1.25, s0.y), WIND_GROW_SEC / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		grow.tween_property(body, "scale", Vector2(s0.x * 1.25 * 1.15, s0.y * 1.05),
			(WIND_BODY_LIFE - WIND_GROW_SEC) / sp)
		# 알파 — Delay(0.15+0.75) → FadeTo(0.5, 255/175) … 본체가 끝나는 run+6.65 에 걷힌다.
		var t := body.create_tween()
		t.tween_interval((ed + WIND_FADE_IN_AT) / sp)
		t.tween_property(body, "modulate:a", 1.0 if k == 0 else 175.0 / 255.0, 0.5 / sp)
		t.tween_interval((WIND_BODY_LIFE - WIND_FADE_IN_AT - 0.5 - 0.25) / sp)
		t.tween_property(body, "modulate:a", 0.0, 0.25 / sp)
		t.tween_callback(body.queue_free)


## ② 바닥 먼지 45장 — ⚫ **넣지 않는다.** (2026-08-06 시도 후 철회)
##   `initWind` 의 `0x2d` 루프는 잎·나무가 아니라 `scene/colosseum/dust{,_cover}` 45장이다
##   (종전 카드의 "45조각 = 회오리 기둥" 도, 우리 코드의 "45조각 = 잔해 스트림" 도 오독이었다).
##   좌표식까지 다 읽었지만 **원작 화면에는 뜨지 않는다**:
##     init 이 `setScale(0)` 으로 두고(`plVar5 + 0x78`(setScale) 인자 0),
##     `runWind` 가 거는 건 `ScaleBy(d*0.5, 1.75)` = **곱셈**이다 ⇒ 0 × 1.75 = 0.
##     `Place` 앞뒤 어디에도 `ScaleTo` 가 없다(액션 트리 전수) ⇒ 45장 전부 배율 0 으로 남는다.
##   실제로 넣어 봤더니 원작에 없는 **흰 구름 벽**이 화면 하단을 덮었다(캡처 대조).
##   ⚠️ 남은 숙제: 영상 seg +3.3~3.6 의 바닥 흰 연기는 이것도, 회오리(그때 알파 0)도 아니다.
##      `runWind_C` / `MakeInterface::setDust`(시전자 착지 먼지) 쪽을 다음에 확인한다.

## ③ 잔해 — 원작 개수는 **나무 `rand%3`(0~2) · 잎 `rand%8+12`(12~19)** 뿐이다.
##   조각마다 두 번 지나간다(1차 MoveBy 1.0+0.25, Place 로 되돌린 뒤 2차 MoveBy 1.5).
##   소멸은 `ScaleBy(0.25, 3.0, 0.5)` = **가로로 3배 늘어나며 납작해진다**(빨려 드는 표현) —
##   종전엔 그냥 화면 밖으로 내보내기만 했다.
##   ASSUMPTION: 조각별 y·출발 x·통과 시차는 원작 rand 인자가 추출에서 소실돼 영상(항상
##   여러 장이 동시에 흐른다)에 맞춰 흩는다. 개수·안무·소멸 방식은 원작 리터럴 그대로.
static func _wind_debris(host: CanvasItem, el: String, pfx: String, at: Vector2, dir: float,
		ed: float, sp: float, vis: Vector2, rng: RandomNumberGenerator) -> void:
	var n_wood := int(rng.randi() % 3)                  # 원작 rand()%3
	var n_leaf := int(rng.randi() % 8 + 12)             # 원작 rand()%8 + 12
	for i in n_wood + n_leaf:
		var is_wood := i < n_wood
		var seg := _spr(el, pfx + ("wood" if is_wood else "leaf"))
		if seg == null:
			return
		# 원작 나무 배율 = 0.75 + (rand%6)*0.1*(±1)
		var s0 := 0.75 + float(rng.randi() % 6) * 0.1 * (1.0 if rng.randi() % 2 == 1 else -1.0)
		var home := Vector2(at.x + dir * (vis.x * 0.55 + rng.randf_range(0.0, 220.0)),
			at.y - vis.y * (0.10 + 0.60 * rng.randf()))
		seg.position = home
		seg.scale *= s0 if is_wood else rng.randf_range(0.7, 1.1)
		seg.z_index = Z_WIND_DEBRIS + (i % 3)
		seg.rotation_degrees = float(rng.randi() % 181) - 90.0   # RotateBy(0, rand%0xb5 − 90)
		var base_scale := seg.scale
		var cross := Vector2(-dir * (vis.x + 320.0), rng.randf_range(-70.0, 70.0))
		host.add_child(seg)
		# 두 통과를 한 트윈에 잇는다 — 시차만 조각별로 흩는다.
		# 원작은 두 통과 사이에 `Delay(3.8375)` 를 두는데, 그대로 넣으면 1차가 끝난 뒤 화면이
		# 텅 빈다. 영상은 run+1.6~6.6 내내 잎이 흐르므로 **출발 시차를 넓게 흩어** 메운다.
		var lead := ed + WIND_DEBRIS_LEAD + rng.randf() * 1.6
		t.tween_interval(lead / sp)
		for pass_i in 2:
			var move_sec := 1.0 if pass_i == 0 else 1.5
			if pass_i == 1:                              # Place — 원위치로 되돌리고 다시 켠다
				t.tween_callback(func() -> void:
					if is_instance_valid(seg):
						seg.position = home
						seg.scale = base_scale
						seg.modulate.a = 200.0 / 255.0)
				t.tween_interval(rng.randf_range(0.3, 1.1) / sp)
			t.tween_property(seg, "position", cross, move_sec / sp).as_relative()
			t.parallel().tween_property(seg, "scale", base_scale * 1.25,
				(0.9 if pass_i == 0 else 1.4) / sp)
			t.parallel().tween_property(seg, "rotation_degrees",
				(float(rng.randi() % 181) - 90.0) * 3.0, move_sec / sp).as_relative()
			# 소멸 — 가로 3배·세로 0.5배로 늘어나며 사라진다(원작 ScaleBy = 직전 배율에 곱한다).
			t.tween_property(seg, "scale",
				Vector2(base_scale.x * 1.25 * 3.0, base_scale.y * 1.25 * 0.5), 0.25 / sp)
			t.parallel().tween_property(seg, "modulate:a", 0.0, 0.25 / sp)
		t.tween_callback(seg.queue_free)


## ④ 소(zmoon) 2장 — 🔴 2026-08-06 복원. 종전엔 "영상 전 구간 미출현"이라 적고 껐는데
##   **틀린 관찰이었다.** 바람 구간(영상 28.30~37.63초)에서 큼직한 소가 오른쪽→왼쪽으로
##   화면을 가로지르는 것이 3회 잡힌다(분홍-남색 덩어리 추적, 구간 시작 기준):
##     +4.13 → +4.37  x 0.56W → 0.08W, y 0.47H → 0.33H
##     +4.97 → +5.30  x 0.72W → 0.06W, y 0.46H → 0.19H   (화면 높이의 ≈0.3 크기)
##     +6.20 → +6.43  x 0.84W → 0.10W, y 0.35H → 0.32H
##   원작 초기 위치도 이와 맞는다 — #1 = `VisibleRect::rightBottom() + (100, 0)`(오른쪽 바깥),
##   #2 = `(−100, layer.y)` + `setScale(0.75)`. 2장이 각각 두 번 지나가면 관측 3회를 덮는다.
##   ASSUMPTION: 통과 시각·궤적은 위 영상 실측값. `run + [시각]` 으로 환산하면 2.7 / 3.85 / 5.5
##   (`run+0 ↔ seg +2.12` 앵커 · 배속 1.35). 소 #0 이 두 번(2.7·5.5), #1 이 한 번(3.85) 지나간다.
const WIND_ZMOON_PASS := [[0, 2.7], [1, 3.85], [0, 5.5]]   # [소 번호, run 기준 초]
const WIND_ZMOON_SEC := 0.75                               # 화면 횡단 시간(영상 실측 환산)

## ⚠️ 위 통과 시각은 **run 기준 절대값**(영상에서 잰 것)이라 `elem_delay` 를 또 더하지 않는다.
static func _wind_zmoon(host: CanvasItem, el: String, pfx: String,
		sp: float, vis: Vector2, rng: RandomNumberGenerator) -> void:
	for k in 2:
		var cow := _spr(el, pfx + "zmoon")
		if cow == null:
			return
		if k == 1:
			cow.scale *= 0.75                     # 원작 #2 setScale(0.75)
		cow.z_index = Z_WIND_ZMOON
		cow.modulate.a = 0.0
		host.add_child(cow)
		var t := cow.create_tween()
		var prev := 0.0
		var used := false
		for row in WIND_ZMOON_PASS:
			if int(row[0]) != k:
				continue
			used = true
			var when := float(row[1])
			t.tween_interval(maxf(0.01, when - prev) / sp)
			prev = when + WIND_ZMOON_SEC
			var y := vis.y * rng.randf_range(0.18, 0.48)
			t.tween_callback(func() -> void:
				if is_instance_valid(cow):
					cow.position = Vector2(vis.x + 140.0, y)
					cow.rotation_degrees = float(rng.randi() % 61) - 30.0
					cow.modulate.a = 1.0)
			# 오른쪽 바깥 → 왼쪽 바깥. 살짝 떠오르며 구른다(영상: y 가 조금씩 올라간다).
			t.tween_property(cow, "position",
				Vector2(-240.0, y - vis.y * 0.12), WIND_ZMOON_SEC / sp)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.parallel().tween_property(cow, "rotation_degrees", -180.0,
				WIND_ZMOON_SEC / sp).as_relative()
			t.tween_callback(func() -> void:
				if is_instance_valid(cow):
					cow.modulate.a = 0.0)
		if not used:
			cow.queue_free()
			continue
		t.tween_callback(cow.queue_free)


# ── dark (11.0초) — 소용돌이가 화면을 삼키고 손아귀가 잡는다 ─────────────────
## 원작 `runDark` 실측(sequences.md, 2026-08-05 재이식 — 시각은 run 기준):
##   구슬(0x1883a)  Delay(1.5) → [ScaleTo(0.25,1)+RotateBy(0.25,−30)]
##                  → [EaseOut(RotateBy(3.0,−3600°)) ∥ ScaleTo(3.0, **2.5**)] → ScaleTo(0.075,0)
##                  = 10바퀴 돌며 화면을 채우는 소용돌이 → 순간 붕괴
##   손(0x18833/4)  Delay(1.0) → Show → [MoveBy+RotateBy(−45/−25)+**ScaleBy(0.35, 2.0)**]
##                  → 스쿼시 펄스 → 3초 배회 → [ScaleBy(0.25,1.5)+FadeTo(0.1,0)]  (좌우 두 벌)
##   펀치(0x1883b)  Delay(4.8) → Show → 스쿼시 → [ScaleBy(1.0,0.8)+RotateBy(−45)] → Hide
##   폭발(0x1883c)  Delay(5.9) → [ScaleTo(0.04, **3.75**)+…] → [RotateBy(360)+ScaleTo(0)+Fade](0.05)
##                  ← 절대시각 8.65 = getDamageTextTime(dark) 와 일치(피해가 여기 뜬다)
const DARK_PUNCH_S := 1.75      # 원작 setScale(1.75)
const DARK_HAND_SEC := 0.025

static func _run_dark(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "dark"
	var pfx := prefix(el)
	# 원기옥 클러스터(구슬·손·펀치·폭발)는 **화면 세로 중앙**에 뜬다 — 영상 실측(+50.5s:
	# 소용돌이 중심 ≈ 0.47H). 원작 initDark 의 `contentCenter + aCStack_a0` 오프셋이 이것.
	# 바닥 기준점(at)은 링·장막 몫이다.
	var dk := Vector2(at.x, _screen_center(host).y)

	# 구슬 — 화면을 삼키는 소용돌이.
	var ball := _spr(el, pfx + "ball")
	if ball != null:
		ball.position = dk
		ball.scale = Vector2.ZERO
		ball.z_index = 96
		host.add_child(ball)
		var bt: Tween = ball.create_tween()
		bt.tween_interval(1.5 / sp)
		bt.tween_property(ball, "scale", Vector2.ONE, 0.25 / sp)
		bt.parallel().tween_property(ball, "rotation_degrees", -30.0, 0.25 / sp)\
			.as_relative().set_ease(Tween.EASE_IN)
		bt.tween_property(ball, "scale", Vector2.ONE * 2.5, 3.0 / sp)
		bt.parallel().tween_property(ball, "rotation_degrees", -3600.0, 3.0 / sp)\
			.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bt.tween_property(ball, "scale", Vector2.ZERO, 0.075 / sp)
		bt.tween_callback(ball.queue_free)

	# 손 — 🔴 2026-08-05 배치 교정(사용자 실측): **원기옥을 양옆에서 감싸 쥐는** 두 손이다.
	#   구슬(중심, 최대 ×2.5)의 좌우 바깥에서 손바닥이 안쪽을 보며 나타나 함께 커지다가,
	#   구슬이 붕괴하는 순간(run+4.75) 안쪽으로 움켜쥔다. 종전엔 아래쪽에 몰려 있었다.
	for i in 2:
		var hd := _spr(el, pfx + "hand1")
		if hd == null:
			break
		var sgn := -1.0 if i == 0 else 1.0
		hd.position = dk + Vector2(sgn * 300.0, -40.0)   # 구슬(×2.5) 좌우 바깥
		hd.z_index = 99
		if i == 1:
			hd.scale = Vector2(-hd.scale.x, hd.scale.y)  # 원작 setScaleX(−1) — 반대편 손
		hd.visible = false
		host.add_child(hd)
		# 손 프레임은 원작이 **RepeatForever**(4벌, 0.025초/프레임) — 잡았다 놓는 반복.
		_loop_frames(hd, el, pfx + "hand%d", 1, 20, DARK_HAND_SEC / sp, 6.0 / sp)
		var ht: Tween = hd.create_tween()
		ht.tween_interval(1.0 / sp)
		ht.tween_callback(func() -> void:
			if is_instance_valid(hd):
				hd.visible = true)
		# 구슬과 함께 커진다(1.75→4.75 사이) — 손끝은 항상 구슬 가장자리.
		ht.tween_property(hd, "scale", hd.scale * 2.0, 0.35 / sp)
		ht.parallel().tween_property(hd, "position", Vector2(sgn * 60.0, 0.0), 0.35 / sp)\
			.as_relative()
		ht.tween_property(hd, "scale", hd.scale * 2.0 * 1.05, 0.025 / sp)
		ht.tween_property(hd, "scale", hd.scale * 2.0, 0.025 / sp)
		ht.tween_interval(2.4 / sp)
		# 움켜쥔다 — 구슬 붕괴(run+4.75~4.83)에 맞춰 중심으로.
		ht.tween_property(hd, "position", dk + Vector2(sgn * 90.0, -40.0), 0.15 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ht.tween_interval(0.9 / sp)
		ht.tween_property(hd, "scale", hd.scale * 3.0, 0.25 / sp)
		ht.parallel().tween_property(hd, "modulate:a", 0.0, 0.25 / sp)
		ht.tween_callback(hd.queue_free)

	# 펀치 — 충돌 순간의 주먹 플래시.
	var punch := _spr(el, pfx + "punch")
	if punch != null:
		punch.position = dk
		punch.scale = Vector2.ONE * DARK_PUNCH_S
		punch.z_index = 100
		punch.visible = false
		host.add_child(punch)
		var pt: Tween = punch.create_tween()
		pt.tween_interval(4.8 / sp)
		pt.tween_callback(func() -> void:
			if is_instance_valid(punch):
				punch.visible = true)
		pt.tween_property(punch, "position", Vector2(dir * 40.0, 0.0), 0.1 / sp).as_relative()
		pt.parallel().tween_property(punch, "scale",
			Vector2(DARK_PUNCH_S, DARK_PUNCH_S * 1.1), 0.05 / sp)
		pt.tween_property(punch, "scale", Vector2.ONE * DARK_PUNCH_S, 0.05 / sp)
		pt.tween_property(punch, "scale", Vector2.ONE * DARK_PUNCH_S * 0.8, 1.0 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.parallel().tween_property(punch, "rotation_degrees", -45.0, 1.0 / sp).as_relative()
		pt.tween_callback(punch.queue_free)

	# 폭발 — 피해 시각(run+5.9)의 대폭발. explosion8 은 rotation 90 짝(초기 배치 그대로).
	# 프레임 애니(1~7 @0.04 · 8~10 @0.025)를 돌리며 커진다 — 종전엔 1프레임 정지화상이었다.
	for i in 2:
		var e := _spr(el, pfx + ("explosion1" if i == 0 else "explosion8"))
		if e == null:
			continue
		e.position = dk
		e.z_index = 101 + i
		e.scale = Vector2.ZERO
		if i == 1:
			e.rotation_degrees = 90.0
		host.add_child(e)
		var lo := 1 if i == 0 else 8
		var hi := 7 if i == 0 else 10
		var fsec := 0.04 if i == 0 else 0.025
		var t2: Tween = e.create_tween()
		t2.tween_interval((5.9 + 0.05 * float(i)) / sp)
		t2.tween_callback(func() -> void:
			_play_frames(e, el, pfx + "explosion%d", lo, hi, fsec / sp))
		t2.tween_property(e, "scale", Vector2.ONE * 3.75, 0.04 / sp)
		t2.tween_interval((0.2 + fsec * float(hi - lo)) / sp)
		t2.tween_property(e, "scale", Vector2.ZERO, 0.05 / sp)
		t2.parallel().tween_property(e, "rotation_degrees", 360.0, 0.05 / sp).as_relative()
		t2.parallel().tween_property(e, "modulate:a", 0.0, 0.05 / sp)
		t2.tween_callback(e.queue_free)

	# 그림자 장막(shade)은 `init<El>_C` 몫이라 `_build_ring` 의 RING_EXTRA 가 낸다 — 여기서
	# 또 만들면 두 장이 겹친다(2026-08-05 중복 제거).


# ── light (11.25초) — 별 750개를 깔고 태양이 뜬다 ────────────────────────────
## 원작 `initLight` 이 `light_star` 를 **750개**(0x2ee) 만든다.
## 2026-08-05 `resolve_actions.py` 로 **별 안무가 두 무리로 갈린다**는 것을 복원했다:
##   · 무리 A **30개**(tag 0x1883a~, 루프 상한 0x1e)
##       Delay(base) → Delay(0.75) → Show → EaseIn(MoveTo((rand%11)*0.025+1.75, 화면 임의점), 0.1)
##     = 화면 아무 데로나 **모여든다**.
##   · 무리 B **720개**(tag 0x18858~, 루프 상한 0x2d0)
##       Delay(base) → Delay(1.75) → Show → EaseIn(MoveBy((rand%45)*0.025+0.75, Δ), 0.1)
##       Δ = (화면 임의점 − 중앙) × ((rand%9)*0.25 + 1.0)
##     = 중앙에서 **바깥으로 뻗어 나간다**(별이 흐르는 그 연출).
##
## 🔴 2026-08-06 프레임 실측 재이식 — 종전 안무는 **영상에 눈대중으로 맞춘 것**이라 큐마다
##   −2.15 ~ +2.30초씩 흩어져 있었다. 이제 `runLight`(13액션) 시퀀스 표를 그대로 옮긴다.
##   시각은 전부 `run + this[0x228](=1.4) + d`. 대조 = 원작 영상 빛 구간(v37.63~46.67, 배속 1.35,
##   기준점 v37.020) ↔ `--write-movie --fixed-fps 30` 결정론 녹화.
##   ⚠️ `dev_ultimate_fx --series` 벽시계 캡처는 별 750개 구간에서 게임시간과 어긋나 시각
##      측정에 못 쓴다(같은 코드가 `--series=0.25` 면 11.25s, `1.0` 이면 9.0s 로 나온다).
##
## | 큐 | 원작(run 기준 절대 로직 초) | 종전 우리 |
## |---|---|---|
## | flash+flashwing | 4.15 | 3.30 |
## | 백색 레이어 ① | 4.65 | 3.25 |
## | 별 A(30) | 4.90 | 3.50 |
## | 행성1(지구) 비행 | 5.60 | 5.05(정지) |
## | bomb · sun · sunlight | 5.75 | 8.05 / 3.60 / 3.60 |
## | 별 B(720) | 5.90 | 4.50 |
## | sunwing (쌍둥이 8.15) | 5.90 | 7.35 |
## | 행성2(토성) 비행 | 6.60 | 6.15(정지) |
## | 백색 레이어 ② | 9.25 → 10.85 | 7.85 → 9.45 |
const LIGHT_FLASHWING_SX := 10.0  # 원작 setScaleX(10) — 가로로 길게 찢어지는 섬광
const LIGHT_STARS_IN := 30
const LIGHT_STARS_OUT := 720
const LIGHT_STARS := LIGHT_STARS_IN + LIGHT_STARS_OUT   # 30 + 720 = 750 (원작 0x2ee)
## 별 하나하나의 초기값 — `initLight` 루프 실측. 종전 `randf(0.4, 1.0)` 은 **3배 컸다**
## (실측 블롭 넓이 우리 25~75px² vs 원작 12~16px²).
const LIGHT_STAR_SCALE_MIN := 0.125     # rand()%0x15 * 0.0125 + 0.125 ⇒ 0.125~0.375
const LIGHT_STAR_SCALE_STEP := 0.0125
const LIGHT_STAR_SCALE_N := 21
const LIGHT_STAR_A_MIN := 155.0 / 255.0 # rand()%0xb * 10 + 155 ⇒ 155~255
## `initLight`: `light_saturn` 의 자리 = `light_earth` 자리 + (60, 60)(cocos y-up).
## ⚠️ 종전에 이 (60,60)을 **태양 뭉치의 오프셋**으로 읽어 태양이 우상단으로 밀려 있었다.
##   실측: 원작 태양 중심 = 캔버스 정규화 (0.499, 0.499) = **화면 정중앙**(5프레임 평균),
##   우리는 (0.557, 0.410) 이었다.
const LIGHT_SATURN_OFF := Vector2(60.0, -60.0)
## 행성 비행 곡선(2차 베지어, 화면 폭·높이 비율 · 중심 기준). 원작 `CCBezierTo` 제어점은
## 디컴프에서 소실 — **영상 실측 6점 최소자승**으로 복원했다. 표본 = 지구 1차 통과
## (L6.0/6.2/6.4/6.6, BezierTo 2.0초) + **2차 통과**(L8.8/9.0, BezierTo 1.0초).
## 두 통과가 **같은 곡선**에 잔차 ≤0.03(≈40pt)로 얹힌다 — 곡선이 하나라는 증거다.
## 끝점은 태양(중앙) — 행성이 태양 쪽으로 날아들며 부풀어 사라진다.
## P0 이 화면 밖(우상단 +0.72W)이라 원작도 뜬 직후 0.5초쯤은 안 보인다(토성 L7.2 첫 등장).
const LIGHT_PLANET_P0 := Vector2(0.724, -0.432)
const LIGHT_PLANET_P1 := Vector2(0.088, 0.117)
## z 규약 — 원작 배치 순서(행성 < 별 < bomb < sunwing < sun < sunlight < flash).
## 행성은 별과 **같은 배치노드**(`this+0x240`)의 자식이라 z 가 상대값이다(원작 행성 z=0 < 별 z=1).
const Z_LIGHT_PLANET := -1
const Z_LIGHT_STARS := 98
const Z_LIGHT_BOMB := 99
const Z_LIGHT_SUNWING := 100
const Z_LIGHT_SUN := 101
const Z_LIGHT_HALO := 102
const Z_LIGHT_FLASH := 103

static func _run_light(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "light"
	var pfx := prefix(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	var d := elem_delay(el)          # this[0x228] = 1.4 — `runLight` 액션 전부에 붙는다

	# 백색 섬광 두 번 — `runLight` 의 별도 CCLayerColor(L521) 실측:
	#   Delay(0x228) → Delay(0.5) → FadeTo(0.1, 255) → Delay(0.75) → FadeTo(0.1, 0)
	#   → Delay(3.65) → FadeTo(0.1, 255) → Delay(0.75) → FadeTo(0.75, 0)
	var flash_v := _screen_veil(host, at, Color(1, 1, 1), Z_FLASH)
	var fl := flash_v.create_tween()
	fl.tween_interval((d + 0.5) / sp)
	fl.tween_property(flash_v, "color:a", 1.0, 0.1 / sp)
	fl.tween_interval(0.75 / sp)
	fl.tween_property(flash_v, "color:a", 0.0, 0.1 / sp)
	fl.tween_interval(3.65 / sp)
	fl.tween_property(flash_v, "color:a", 1.0, 0.1 / sp)
	fl.tween_interval(0.75 / sp)
	fl.tween_property(flash_v, "color:a", 0.0, 0.75 / sp)
	fl.tween_callback(flash_v.queue_free)

	# ── 별 750개 ────────────────────────────────────────────────────────────
	# 🔴 원작은 750개를 **레이어 자리 한 점**(`setPosition(this->getPosition())`)에 겹쳐 두고
	#   거기서 바깥으로 뿜는다. 종전엔 화면 전체에 흩뿌려 두고 시작해 "이미 깔린 별밭"이었다.
	#   실측 뒷받침: 원작 우하단 ROI 별 개수가 66 → 42 → 38 → 34 로 **줄다가** 안정된다
	#   (1~3배 오버슛으로 상당수가 화면 밖으로 빠져나간다).
	# 이징 주의 — 원작 `CCEaseIn(rate)` 은 `t^rate` 다. rate 0.1 이면 **초반이 폭발적**이라
	#   Godot 기준으로는 EASE_OUT 이다(종전 EASE_IN 은 정확히 반대였다).
	var field := Node2D.new()
	field.z_index = Z_LIGHT_STARS
	field.position = at                      # 컨테이너 확대(ScaleTo 1.1)의 피벗 = 레이어 자리
	_set_alpha(field, 0.0)                   # PMA — §_fade_pma
	host.add_child(field)
	var ctr := _screen_center(host)
	var half := vis * 0.5
	for i in LIGHT_STARS:
		var st := _spr(el, pfx + "star")
		if st == null:
			break
		st.position = Vector2.ZERO           # = field.position = 레이어 자리
		st.scale = Vector2.ONE * (float(rng.randi() % LIGHT_STAR_SCALE_N)
			* LIGHT_STAR_SCALE_STEP + LIGHT_STAR_SCALE_MIN)
		_set_alpha(st, float(rng.randi() % 11) * (10.0 / 255.0) + LIGHT_STAR_A_MIN)
		st.visible = false
		field.add_child(st)
		var spot := ctr + Vector2(rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y))       # 원작 `rand() % VisibleRect` 임의점
		var t: Tween = st.create_tween()
		if i < LIGHT_STARS_IN:
			# 무리 A(30) — Delay(0x228+0.75) → Show → EaseIn(MoveTo(1.75~2.0초, 임의점), 0.1)
			t.tween_interval((d + 0.75) / sp)
			t.tween_callback(func() -> void: st.visible = true)
			t.tween_property(st, "position", spot - at,
				(float(rng.randi() % 11) * 0.025 + 1.75) / sp)\
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		else:
			# 무리 B(720) — Delay(0x228+1.75) → Show → EaseIn(MoveBy(0.75~1.85초, Δ), 0.1)
			t.tween_interval((d + 1.75) / sp)
			t.tween_callback(func() -> void: st.visible = true)
			t.tween_property(st, "position",
				(spot - ctr) * (float(rng.randi() % 9) * 0.25 + 1.0),
				(float(rng.randi() % 45) * 0.025 + 0.75) / sp)\
				.as_relative().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# 별밭 컨테이너(L369) — Delay(0x228+0.6) → FadeTo(0,255) → ScaleTo(4.75, 1.1)
	#   → Delay(0.5) → Hide. 사라지는 시각 10.0초 = **2차 섬광(9.25~10.85) 한가운데**라
	#   원작은 뒷정리가 흰 화면에 가려진다. 종전(7.5초 뒤 1초 페이드)은 그 밖이었다.
	# ⚠️ 이 Hide 는 배치노드(`this+0x240`) 것이라 **별과 행성이 함께** 사라진다 — 행성을
	#   여기 자식으로 붙이는 이유다(안 그러면 섬광이 걷힌 뒤 거대 지구가 화면에 남는다).
	var ft := field.create_tween()
	ft.tween_interval((d + 0.6) / sp)
	ft.tween_callback(func() -> void: _set_alpha(field, 1.0))     # FadeTo(0.0, 255) = 즉시
	ft.tween_property(field, "scale", Vector2(1.1, 1.1), 4.75 / sp)
	ft.tween_interval(0.5 / sp)
	ft.tween_callback(field.queue_free)

	# ── 행성 2개(L287 tag 0x19a66 = earth · L309 tag 0x19a67 = saturn) ──────
	# 🔴 원작 행성은 장식이 아니라 **카메라 앞을 스쳐 지나간다** — 베지어를 타고 날아오며
	#   `CCEaseExponentialIn(ScaleTo(…, 8.0))` 으로 부풀고 3초에 걸쳐 사라진다.
	#   지구는 이 비행을 **두 번**(Place 로 되감아 재사용) 한다. 종전엔 둘 다 정지 스프라이트였다.
	# 좌표는 `field` 로컬(= 절대 좌표 − field.position). 행성은 별과 같은 배치노드에 산다.
	var p0 := ctr - at + Vector2(vis.x * LIGHT_PLANET_P0.x, vis.y * LIGHT_PLANET_P0.y)
	var p1 := ctr - at + Vector2(vis.x * LIGHT_PLANET_P1.x, vis.y * LIGHT_PLANET_P1.y)
	var p2 := ctr - at
	_light_planet(field, el, pfx + "earth", [p0, p1, p2], 0.4, d + 1.45, sp,
		[[2.0, 3.0], [1.0, 2.0]])                       # 2패스: Bezier 2.0/1.0 · ScaleTo 3.0/2.0
	_light_planet(field, el, pfx + "saturn",
		[p0 + LIGHT_SATURN_OFF, p1 + LIGHT_SATURN_OFF, p2], 1.0, d + 2.45, sp,
		[[2.5, 5.0]])                                   # 1패스: Bezier 2.5 · ScaleTo 5.0

	# ── 태양 무리 — `initLight` 은 전부 **한 자리**(레이어 중심)에 겹쳐 놓는다 ─────
	#   `light_sun`(0x18835) / `sunlight`(0x18833) / `sunwing`(0x18834) : setScale(1)·setOpacity(0)
	#   `light_flash`(0x27290) : setScale(0) · **anchor(0.54, 0.5)** · z 1
	#   `light_flashwing`(0x18831) : flash 의 자식, setScaleX(10) · pos = flash 중앙
	#   `light_bomb`(0x18832) : setScale(0)
	#   `sunwing` 은 **자기 복제본**을 자식으로 갖는다(scale 0 · opacity 0 · rotation 90).
	var sun_at := at
	# cocos `CCEaseOut(rate)` = t^(1/rate) → Godot EASE_IN, `CCEaseIn(rate)` = t^rate → EASE_OUT.

	# flash — 씨앗(0.15)에서 5.0 배로 터졌다가 7.5 → 2.0 → 1.75 로 잦아들며 사라진다.
	#   섬광이 걷힌 뒤 화면에 남는 **청백 구체 + 회색 후광 링**의 정체가 이 단계다(종전 누락).
	var flash := _spr_a(el, pfx + "flash", Vector2(0.54, 0.5))
	if flash != null:
		flash.position = sun_at
		flash.scale = Vector2.ZERO
		flash.z_index = Z_LIGHT_FLASH
		host.add_child(flash)
		var wing := _spr(el, pfx + "flashwing")
		if wing != null:
			# 원작은 flash 의 contentSize*0.5(= 도형 중심)에 붙인다. 앵커가 0.54 라 그만큼 밀린다.
			wing.position = Vector2((0.5 - 0.54)
				* AtlasUI.size_pt(DIR_PREFIX + el, pfx + "flash").x, 0.0)
			wing.scale = Vector2(LIGHT_FLASHWING_SX, 1.0)   # setScaleX(10)
			wing.z_index = -1
			flash.add_child(wing)
			var wt := wing.create_tween()
			wt.tween_interval(d / sp)
			wt.tween_property(wing, "scale", Vector2.ONE, 0.5 / sp)\
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)   # CCEaseOut(0.25)
			wt.tween_interval(1.0 / sp)
			_fade_pma(wt, wing, 0.0, 0.25 / sp)
			wt.tween_callback(wing.queue_free)
		var t := flash.create_tween()
		t.tween_interval(d / sp)
		t.tween_property(flash, "scale", Vector2(0.15, 0.15), 0.5 / sp)
		t.tween_property(flash, "scale", Vector2(5.0, 5.0), 0.1 / sp)
		t.tween_interval(0.75 / sp)
		t.tween_callback(func() -> void: flash.scale = Vector2(7.5, 7.5))  # ScaleTo(0.0, 7.5)
		t.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.25 / sp)
		t.tween_property(flash, "scale", Vector2(1.75, 1.75), 0.5 / sp)
		_fade_pma(t.parallel(), flash, 0.0, 0.5 / sp)
		t.tween_callback(flash.queue_free)

	# bomb — 태양이 태어나는 순간의 착화(+1.6). 종전엔 2차 섬광 착화(+5.3)로 잘못 배정돼 있었다.
	var bomb := _spr(el, pfx + "bomb")
	if bomb != null:
		bomb.position = sun_at
		bomb.scale = Vector2.ZERO
		bomb.z_index = Z_LIGHT_BOMB
		host.add_child(bomb)
		var bt := bomb.create_tween()
		bt.tween_interval((d + 1.6) / sp)
		bt.tween_property(bomb, "scale", Vector2(7.5, 7.5), 0.5 / sp)
		bt.tween_callback(bomb.queue_free)

	# sun — 회전하며 0.75 → 2.0 으로 자라다 2차 섬광 안에서 접혀 사라진다.
	var sun := _spr(el, pfx + "sun")
	if sun != null:
		sun.position = sun_at
		_set_alpha(sun, 0.0)
		sun.z_index = Z_LIGHT_SUN
		host.add_child(sun)
		var t := sun.create_tween()
		t.tween_interval((d + 1.6) / sp)
		t.tween_property(sun, "rotation_degrees", -1260.0, 3.5 / sp).as_relative()\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)   # CCEaseInOut(0.25)
		_fade_pma(t.parallel(), sun, 1.0, 0.25 / sp)
		t.parallel().tween_property(sun, "scale", Vector2(0.75, 0.75), 1.0 / sp)
		t.parallel().tween_property(sun, "scale", Vector2(2.0, 2.0), 2.5 / sp)\
			.set_delay(1.0 / sp)
		t.tween_interval(0.75 / sp)
		t.tween_property(sun, "scale", Vector2.ZERO, 0.75 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(sun, "rotation_degrees", -360.0, 0.75 / sp).as_relative()
		t.tween_callback(sun.queue_free)

	# sunlight — **태양과 같이 태어나 같이 자라는 후광**(0.75 → 2.0, 3.5초).
	#   🔴 종전엔 scale 2.6 으로 0.9초만 떴다 져서, ① 그동안 화면 전체가 주황빛으로 날아가고
	#      ② 그 뒤로는 맨 태양만 남아 **차갑게(무채색)** 보였다. 실측 반경 120pt 색:
	#      원작 (177,136,103) vs 종전 우리 (123,119,113) — 원작의 따뜻한 코로나가 곧 이 후광이다.
	var halo := _spr(el, pfx + "sunlight")
	if halo != null:
		halo.position = sun_at
		_set_alpha(halo, 0.0)
		halo.z_index = Z_LIGHT_HALO
		host.add_child(halo)
		var t := halo.create_tween()
		t.tween_interval((d + 1.6) / sp)
		t.tween_property(halo, "scale", Vector2(0.75, 0.75), 1.0 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)     # CCEaseIn(0.25)
		_fade_pma(t.parallel(), halo, 1.0, 0.25 / sp)
		t.tween_property(halo, "scale", Vector2(2.0, 2.0), 2.5 / sp)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)       # CCEaseOut(0.1)
		t.tween_interval(0.75 / sp)                                    # Delay .25 + 콜백 + Delay .5
		t.tween_property(halo, "scale", Vector2.ZERO, 0.75 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.tween_callback(halo.queue_free)

	# sunwing — 788×44 **가로 막대**다. 태양을 관통하는 수평 플레어로 상주하다가 +4.0 에
	#   90° 쌍둥이가 떠 **+자**가 되고, +1.75 에서야 0.75초 동안 720° 한 바퀴 돈다.
	#   🔴 종전엔 3.5초에 걸쳐 200° 를 계속 돌려 **화면을 가로지르는 거대한 X자**였다.
	var swing := _spr(el, pfx + "sunwing")
	if swing != null:
		swing.position = sun_at
		_set_alpha(swing, 0.0)
		swing.z_index = Z_LIGHT_SUNWING
		host.add_child(swing)
		var twin := _spr(el, pfx + "sunwing")
		if twin != null:
			twin.rotation_degrees = 90.0
			twin.scale = Vector2.ZERO
			_set_alpha(twin, 0.0)
			twin.z_index = -1
			swing.add_child(twin)
			var tt := twin.create_tween()
			tt.tween_interval((d + 4.0) / sp)
			tt.tween_property(twin, "scale", Vector2.ONE, 1.0 / sp)
			_fade_pma(tt.parallel(), twin, 1.0, 1.0 / sp)
		var t := swing.create_tween()
		t.tween_interval((d + 1.75) / sp)
		t.tween_property(swing, "scale", Vector2(0.75, 0.75), 1.0 / sp)
		_fade_pma(t.parallel(), swing, 1.0, 0.1 / sp)
		t.tween_property(swing, "scale", Vector2(2.0, 2.0), 2.5 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(swing, "rotation_degrees", 720.0, 0.75 / sp)\
			.as_relative().set_delay(1.75 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.tween_callback(swing.queue_free)


## 행성 한 개 — `runLight` L287/L309. `pts` = 2차 베지어 [시작, 제어, 끝],
## `passes` = 통과마다 [베지어 초, ScaleTo 초]. 매 통과: 8.0 배까지 지수적으로 부풀며 3초 페이드.
static func _light_planet(host: CanvasItem, el: String, key: String, pts: Array,
		scale0: float, at_sec: float, sp: float, passes: Array) -> void:
	var n := _spr(el, key)
	if n == null:
		return
	n.position = pts[0]
	n.scale = Vector2.ONE * scale0
	n.visible = false
	n.z_index = Z_LIGHT_PLANET
	host.add_child(n)
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	var p2: Vector2 = pts[2]
	var t := n.create_tween()
	t.tween_interval(at_sec / sp)
	t.tween_callback(func() -> void: n.visible = true)
	for i in passes.size():
		if i > 0:                                    # 원작 Place → ScaleTo(0, s0) → FadeTo(0, 255)
			t.tween_callback(func() -> void:
				n.position = p0
				n.scale = Vector2.ONE * scale0
				_set_alpha(n, 1.0))
		var bez := float(passes[i][0])
		var sec := float(passes[i][1])
		t.tween_method(func(x: float) -> void:
			if is_instance_valid(n):
				var q := 1.0 - x
				n.position = p0 * (q * q) + p1 * (2.0 * q * x) + p2 * (x * x),
			0.0, 1.0, bez / sp)
		t.parallel().tween_property(n, "scale", Vector2(8.0, 8.0), sec / sp)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)   # CCEaseExponentialIn
		_fade_pma(t.parallel(), n, 0.0, 3.0 / sp)
	t.tween_callback(n.queue_free)


# ── holy (11.25초) — 창 세례 ─────────────────────────────────────────────────
## 원작 `initHoly`: `holy_spear` **31개 × 2벌**(앞 z=idx+1 / 뒤 z=375−idx)을 **3라운드**
## 반복한다 ⇒ 창 186개. 높이는 `(0, rand()%301)` 로 흩고 기준은 `(0, 62.5)`.
const HOLY_SPEARS := 31
const HOLY_ROUNDS := 3
const HOLY_BASE_DY := 62.5
const HOLY_WELL_AT := 0.75      # ASSUMPTION: 영상 — 우물 광구는 창 세례 동안 바닥에서 빛난다
const HOLY_WELL_OUT := 3.9      # 백색 섬광(run+3.775)과 함께 소멸(영상 +62.5s)
const HOLY_SPEAR_GAP := 24.166666        # 원작 `initHoly`: x = i × 24.1667 (31개 = 화면 폭)

static func _run_holy(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "holy"
	var pfx := prefix(el)
	var base := at - Vector2(0.0, HOLY_BASE_DY)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	# 백색 섬광 — `runHoly` 의 별도 CCLayerColor 실측(2026-08-05):
	#   Delay(3.775) → FadeTo(0.75, 255) → Delay(0.1) → FadeTo(0.25, 0)
	var flash := _screen_veil(host, at, Color(1, 1, 1), Z_FLASH)
	var fl := flash.create_tween()
	fl.tween_interval(3.775 / sp)
	fl.tween_property(flash, "color:a", 1.0, 0.75 / sp)
	fl.tween_interval(0.1 / sp)
	fl.tween_property(flash, "color:a", 0.0, 0.25 / sp)
	fl.tween_callback(flash.queue_free)

	# 우물 — 🔴 2026-08-05 영상 프레임 실측: 작은 광구가 먼저 맺혀 있다가(58.6~59.3s)
	#   **run 직후 웅덩이로 터지고**(59.5s), 거기서 창 분수가 솟는다. 섬광과 함께 소멸.
	var pool := base + Vector2(0.0, HOLY_BASE_DY * 2.0)
	var well := _spr(el, pfx + "well")
	if well != null:
		well.position = pool
		well.z_index = 88
		well.scale = Vector2.ONE * 0.35            # 맺힌 광구
		host.add_child(well)
		var wt := well.create_tween()
		wt.tween_interval(0.2 / sp)
		wt.tween_property(well, "scale", Vector2.ONE, 0.3 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # 웅덩이로 폭발
		wt.tween_property(well, "scale", Vector2.ONE * 1.35,
			maxf(0.1, HOLY_WELL_OUT - 0.5) / sp)
		wt.tween_property(well, "modulate:a", 0.0, 0.25 / sp)
		wt.tween_callback(well.queue_free)

	# 창(spear) — 🔴 2026-08-05 영상 프레임 실측 재구성: 하늘에서 떨어지는 게 아니라
	#   **웅덩이에서 분수처럼 위로 분출**했다가(59.7~61.3s 부채꼴 fountain) 되돌아 떨어진다.
	#   해독된 `runHoly` 와도 부합한다 — `MoveBy(자기 방향 × 200)`(분출) → `MoveTo(중심)`(낙하).
	#   배치만 종전 해석(가로 한 줄)이 틀렸다: 시작점 = 웅덩이, 방향 = 위쪽 부채꼴.
	for r in HOLY_ROUNDS:
		for i in HOLY_SPEARS:
			for layer in 2:                     # 앞/뒤 두 벌(원작 tag 0x18835 / +0x1f)
				var s := _spr_a(el, pfx + "spear", Vector2(0.5, 0.1))
				if s == null:
					return
				s.position = pool + Vector2(rng.randf_range(-50.0, 50.0),
					rng.randf_range(-14.0, 6.0))
				# 위쪽 부채꼴(−160°~−20°) — 라운드마다 살짝 어긋난다.
				var ang := deg_to_rad(lerpf(-160.0, -20.0, float(i) / float(HOLY_SPEARS - 1))
					+ float(r) * 7.0 + rng.randf_range(-4.0, 4.0))
				var v := Vector2(cos(ang), sin(ang))
				s.rotation = atan2(v.x, -v.y)      # 창끝이 분출 방향을 향한다(앵커 0.5/0.1)
				s.z_index = (95 + i) if layer == 0 else (84 - i / 8)
				s.visible = false
				s.modulate.a = 0.0
				host.add_child(s)
				var fly := maxf(0.1, 1.775 - 0.1 * float(r) - 0.0125 * float(i))
				var reach := rng.randf_range(210.0, 380.0)   # 원작 `자기 방향 × 200` + 산포
				var land := Vector2(base.x + v.x * rng.randf_range(160.0, 420.0),
					base.y + HOLY_BASE_DY + rng.randf_range(40.0, 110.0))
				var t: Tween = s.create_tween()
				t.tween_interval((float(r) * 0.2 + float(i) * 0.0125 + 0.4) / sp)
				t.tween_callback(func() -> void: s.visible = true)
				t.tween_property(s, "modulate:a", 200.0 / 255.0, 0.15 / sp)
				t.parallel().tween_property(s, "position", v * reach, fly * 0.55 / sp)\
					.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)  # 분출
				t.tween_property(s, "position", land, fly * 0.45 / sp)\
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)                 # 낙하
				t.parallel().tween_property(s, "modulate:a", 100.0 / 255.0, fly * 0.45 / sp)
				t.tween_property(s, "modulate:a", 0.0, 0.3 / sp)
				t.tween_callback(s.queue_free)

	# 깃털 — 영상 64.0~65.0s: 섬광이 걷히며 **흰 깃털이 화면 가득** 흩날린다.
	#   프레임 = `common/feather1~6`(레벨업 연출과 공유하는 실물 보유분).
	for i in 24:
		var fe := AtlasUI.spr_cocos("common_ui", "common_feather%d" % (1 + i % 6))
		if fe == null:
			break
		var ctr_h := _screen_center(host)
		fe.position = ctr_h + Vector2(rng.randf_range(-vis.x * 0.5, vis.x * 0.5),
			rng.randf_range(-vis.y * 0.55, -vis.y * 0.1))
		fe.scale = Vector2.ONE * rng.randf_range(0.7, 1.2)
		fe.z_index = Z_FLASH + 1                   # 섬광이 걷힐 때 그 위에서 떨어진다
		fe.modulate.a = 0.0
		fe.rotation_degrees = rng.randf_range(-40.0, 40.0)
		host.add_child(fe)
		var ft2 := fe.create_tween()
		ft2.tween_interval((3.9 + float(i % 8) * 0.08) / sp)
		ft2.tween_property(fe, "modulate:a", 1.0, 0.2 / sp)
		ft2.tween_property(fe, "position",
			Vector2(rng.randf_range(-70.0, 70.0), vis.y * rng.randf_range(0.35, 0.6)),
			rng.randf_range(1.2, 2.0) / sp).as_relative()\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ft2.parallel().tween_property(fe, "rotation_degrees",
			rng.randf_range(-90.0, 90.0), 1.6 / sp).as_relative()
		ft2.tween_property(fe, "modulate:a", 0.0, 0.4 / sp)
		ft2.tween_callback(fe.queue_free)


# ── chaos (10.65초) — 운석과 먼지 ────────────────────────────────────────────
## 원작 `initChaos`: `chaos_meteo1/2` + `chaos_dust1~3`(애니 0.05초/프레임) +
##   `scene/colosseum/dust`·`dust_cover` 를 **18개**(0x12) · 12개(0xc) 루프로 깐다.
##   운석 앵커가 `(0.5, 0.0493)` = 꼬리 끝 기준이다.
##
## 🔴 2026-08-06 영상 프레임 재대조로 **먼지 두 종류의 시각이 통째로 뒤바뀐 것**을 잡았다.
##   정합: 혼돈 구간 컷 65.80~74.53s · timeScale **1.35** · 시전 0초 T0 = **66.53s**
##   (근거 3중 — 붉은 강하 빔 68.20 = `ACT_AT` 2.25 / 먼지 등장 68.57 = `RUN_AT` 2.75 /
##    클립 끝 74.53 = 명목 10.80 ≈ `DURATION.chaos` 10.65).
##   실측 타임라인(명목 초):
##     2.6~5.5  `chaos_dust1~3`(검붉은 톱니 바위)가 **지면 좌·우**에서 밀려든다
##     2.75→5.75 장막 `TintTo(3.0, 200/50/25)` — 상단 밝은 띠 폭 762→1114px 로 측정
##     6.3→7.2  **운석이 화면을 덮으며 백열**(71.4~71.6s 프레임의 회색 연기 날개·백열
##              테두리가 `chaos_meteo1` 에셋과 일치)
##     8.7~9.5  백색이 걷히며 지면에 **흰 흙먼지 뭉치**(`colosseum/dust`·`dust_cover`)
##   종전 코드는 이 둘을 서로 바꿔 깔고 있었다(톱니 7.75~9.5 · 흰 구름 2.75~5.5).
const CHAOS_DUST_AT := 0.0      # `chaos_dust1~3` = run+0 (영상 68.57 = 명목 2.75)
const CHAOS_DUST_LIVE := 2.75   # 붉은 물들임이 다 차오르는 5.5 까지 남아 삼켜진다
const CHAOS_COVER_AT := 5.75    # 흰 흙먼지 = 착탄 뒤(명목 8.5) — run 기준
const CHAOS_DUST_SEC := 0.05
const CHAOS_COVERS := 18
const CHAOS_METEO_ANCHOR_Y := 0.049295776   # 원작 앵커 — 운석 **꼬리 끝**이 축이다
## 운석 — 영상 실측 스케줄(run 기준). 앵커(백열 테두리)가 화면 위에서 내려와 상단 22% 에
##   걸리고, 몸통은 화면 밖 위쪽에 있다 ⇒ **하늘을 채운 백열 테두리**로 보인다.
##   근거: 상단 밝은 띠 폭이 명목 2.25→5.3 에 762→1114px 로 자란다(원 현의 길이가 자라는 꼴).
##   4.45(명목 7.2)에 백색 섬광이 받아 간다.
const CHAOS_METEO_IN := 0.75
const CHAOS_METEO_FALL := 2.95
const CHAOS_METEO_REST := 0.22    # 최종 테두리 높이 = 화면 위에서 22%

static func _run_chaos(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "chaos"
	var pfx := prefix(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var s_ring := RING_DY

	# 운석 — 원작 `initChaos` 의 운석 노드는 **둘뿐**이다(meteo1 = `setScale(W/운석폭)` 화면 폭,
	#   meteo2 짝). 앵커 `(0.5, 0.0493)` = **꼬리 끝**(= 백열하는 아랫테두리)이 축.
	# 🔴 2026-08-06 재작성 — 종전 코드는 운석을 `Z_VEIL - 2`(장막 뒤)에 두어 **한 프레임도
	#   보이지 않았다**(우리 캡처를 콘트라스트로 늘려야만 t≈6.5에 아랫테두리 한 조각이 나온다).
	#   영상에서 붉은 화면 자체는 장막의 `TintTo(3.0, 200/50/25)` 로 설명된다(화면 평균 R
	#   39→145 ≈ 200×200/255) — 운석은 그 뒤에 숨는 것이 아니라 **백색 섬광 직전 1초 남짓
	#   화면을 덮으며 등장**한다(71.4~71.6s 프레임의 회색 연기 날개·백열 테두리가 에셋과 일치).
	#   같은 날 확정된 `Z_VEIL = 0`(장막이 드래곤보다 뒤) 덕에 **장막 위·드래곤 아래**(z 1~9)에
	#   놓으면 원작 그대로 "드래곤 뒤를 채우는 거대 운석"이 된다.
	var mw := float(manifest(el).get(pfx + "meteo1", {}).get("w", 1.0)) * Design.ASSET_SCALE
	var mh := float(manifest(el).get(pfx + "meteo1", {}).get("h", 1.0)) * Design.ASSET_SCALE
	var ctrx := _screen_center(host).x
	var m := _spr_a(el, pfx + "meteo1", Vector2(0.5, CHAOS_METEO_ANCHOR_Y))
	if m != null:
		# 화면 폭에 맞춘다 ⇒ 백열 테두리 호가 화면 폭을 가로지른다(실측 띠 폭 1114/1142px).
		var sc := (vis.x / mw) if mw > 1.0 else 1.0
		m.scale = Vector2.ONE * sc
		var top := _screen_center(host).y - vis.y * 0.5
		m.position = Vector2(ctrx, top - 30.0)     # 테두리가 화면 위쪽 밖 — 몸통은 더 위
		m.z_index = Z_VEIL + 1                     # 장막 위 · 드래곤(Z_ACTOR 10) 뒤
		m.modulate.a = 0.0
		host.add_child(m)
		var t: Tween = m.create_tween()
		t.tween_interval(CHAOS_METEO_IN / sp)
		t.tween_property(m, "position:y", top + vis.y * CHAOS_METEO_REST,
			CHAOS_METEO_FALL / sp).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(m, "modulate:a", 1.0, 0.75 / sp)
		t.tween_property(m, "modulate:a", 0.0, 0.75 / sp)   # 백색 섬광에 삼켜진다
		t.tween_callback(m.queue_free)
		# meteo2 는 meteo1 의 교체 프레임 — 낙하 중 0.1초로 갈아 끼워 불길이 일렁이게 한다.
		_loop_frames(m, el, pfx + "meteo%d", 1, 2, 0.1 / sp,
			(CHAOS_METEO_IN + CHAOS_METEO_FALL + 0.75) / sp)

	# 착탄 섬광 — `runChaos` 의 별도 CCLayerColor 실측(2026-08-05):
	#   Delay(3.0) → FadeTo(1.0, 175) → [TintTo(1.0, white) ∥ FadeTo(1.0, 255)] → Delay(0.5) → …
	#   🔴 2026-08-06 지연 교정: 영상은 명목 6.3 에 하얘지기 시작해 **7.2 에 완전 백색**이다
	#   (run 기준 3.55~4.45). 종전 3.0 시작은 우리 화면을 0.5초 늦게 태웠다.
	var bang := _screen_veil(host, at, Color8(200, 50, 25), Z_FLASH)
	var bt := bang.create_tween()
	bt.tween_interval(2.5 / sp)
	bt.tween_property(bang, "color:a", 175.0 / 255.0, 1.0 / sp)
	bt.tween_property(bang, "color", Color(1, 1, 1, 1), 1.0 / sp)
	bt.tween_interval(0.5 / sp)
	bt.tween_property(bang, "color:a", 0.0, 1.0 / sp)   # ASSUMPTION: 걷는 시간(콜백 뒤 미상)
	bt.tween_callback(bang.queue_free)

	# 톱니 바위 먼지 — 원작 앵커 `(0.5, 0)` · `setScaleY(0)` ⇒ **바닥에서 솟는다**.
	# 🔴 2026-08-06 시각 교정: run+0(영상 68.57)에 지면 좌·우로 밀려들어와 붉은 물들임이
	#   다 차오르는 명목 5.5 까지 남는다. 종전 `CHAOS_FLASH_AT(5.0)` 은 **백색 섬광 도중**에
	#   띄우고 있어서, 하얀 화면 위에 검붉은 판이 사각형째 얹혔다.
	var du := _spr_a(el, pfx + "dust1", BOTTOM)
	if du != null:
		# 🔴 폭 교정 — 프레임 563pt(×4/3 = 751)는 화면(1024)보다 좁아 **네모난 경계**가 보였다.
		#   영상에서 이 바위 무리는 화면 폭을 꽉 채운다(경계가 화면 밖) ⇒ 폭을 화면에 맞춘다.
		var dw := float(manifest(el).get(pfx + "dust1", {}).get("w", 1.0)) * Design.ASSET_SCALE
		var kx := maxf(1.0, vis.x / dw) if dw > 1.0 else 1.0
		du.position = Vector2(ctrx, at.y + s_ring)   # 화면 중앙 지면 — 좌·우 한 쌍이 한 프레임이다
		du.z_index = Z_VEIL + 2                      # 운석 앞 · 드래곤 뒤
		du.scale = Vector2(kx, 0.0)
		host.add_child(du)
		var dg := du.create_tween()
		dg.tween_interval(CHAOS_DUST_AT / sp)
		dg.tween_property(du, "scale", Vector2(kx, 1.0), 0.4 / sp)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_loop_frames(du, el, pfx + "dust%d", 1, 3, CHAOS_DUST_SEC / sp,
			(CHAOS_DUST_AT + CHAOS_DUST_LIVE + 1.0) / sp)
		var t2 := du.create_tween()
		t2.tween_interval((CHAOS_DUST_AT + CHAOS_DUST_LIVE) / sp)
		t2.tween_property(du, "modulate:a", 0.0, 1.0 / sp)   # 붉은 장막에 녹아 없어진다
		t2.tween_callback(du.queue_free)

	# 흙먼지 장막 — 원작이 `scene/colosseum` 아틀라스에서 가져온다(우리도 보유).
	# 🔴 2026-08-06 시각 교정: 이건 **착탄 잔해**다(영상 72.9~73.6 = 명목 8.7~9.5, 백색이
	#   걷히며 지면에 남는 흰 연기). 종전엔 run+0 에 깔아 붉은 국면 내내 화면 아래가
	#   흰 구름밭이었다.
	var ground_y := _screen_center(host).y + vis.y * 0.5
	for i in CHAOS_COVERS:
		var c := AtlasUI.spr_cocos("colosseum_ui",
			"scene_colosseum_dust_cover" if i % 2 == 0 else "scene_colosseum_dust")
		if c == null:
			break
		c.position = Vector2(ctrx + rng.randf_range(-vis.x * 0.45, vis.x * 0.45),
			ground_y - rng.randf_range(15.0, 70.0))
		c.z_index = 90
		c.modulate.a = 0.0
		host.add_child(c)
		var t3 := c.create_tween()
		t3.tween_interval((CHAOS_COVER_AT + float(i) * 0.05) / sp)
		t3.tween_property(c, "modulate:a", 1.0, 0.25 / sp)
		t3.tween_property(c, "position", c.position + Vector2(dir * 110.0, -20.0), 2.0 / sp)
		t3.parallel().tween_property(c, "modulate:a", 0.0, 2.0 / sp)
		t3.tween_callback(c.queue_free)


# ── shadow (9.25초) — 연출 본체가 스파인이다 ─────────────────────────────────
## 원작 `initShadow` 은 프레임 대신 `shadow_spine.spine_json` 을 세운다(애니 `s1`·`s2`).
## 링(`_build_ring`)이 이미 `s1` 을 틀었으므로 여기서는 **두 번째 애니 `s2`** 와 늪을 얹는다.
const SHADOW_MARSH_Z := 100

static func _run_shadow(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "shadow"
	var pfx := prefix(el)
	# 원작이 (0,150) 에 z=100 짜리 3장을 둔다(tag 0x1883a~c).
	for i in 3:
		var m := _spr(el, pfx + "marsh%d" % (i + 1))
		if m == null:
			break
		m.position = at + Vector2(0.0, -150.0)
		m.z_index = SHADOW_MARSH_Z + i
		m.modulate.a = 0.0
		host.add_child(m)
		var t: Tween = m.create_tween()
		t.tween_interval(float(i) * 0.3 / sp)
		t.tween_property(m, "modulate:a", 1.0, 0.4 / sp)
		t.tween_interval(5.0 / sp)
		t.tween_property(m, "modulate:a", 0.0, 0.6 / sp)
		t.tween_callback(m.queue_free)

	var spn: Dictionary = RING_SPINE.get(el, {})
	if spn.is_empty() or not ResourceLoader.exists(String(spn["scene"])):
		return
	var holder := Node2D.new()
	holder.position = at
	holder.z_index = 103
	host.add_child(holder)
	var inst = (load(String(spn["scene"])) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null and ap.has_animation("s2"):
		ap.play("s2")
	var t2 := holder.create_tween()
	t2.tween_interval(float(DURATION.get(el, 9.25)) / sp)
	t2.tween_callback(holder.queue_free)


# ── 피격자 포즈 — 원작 `damage<El>_C` 스파인 문자열 전수 채굴 (2026-08-05) ────
#
# 모든 속성이 3단계다: **`damaged`(타격마다 재생) → `down`(엎어짐) → `wait`(복귀)**.
#   runSpine 호출 수 실측: fire 13 · dark 13 · shadow 15 · earth 12(= 연타마다 damaged) ·
#   aqua/wind/light/chaos/holy 3(한 번씩).
# 물만 **`love`** 가 있다 — 물고기 떼가 에워싸는 구간(영상 14.75~16.3s)의 포즈다.
# 아래 표 = 저글링 앞에 따로 트는 **선행 포즈**(시전 0초 기준). damaged/down/wait 는
# 저글링 쪽(fight `_ultimate_knockback` · dev 창)이 타격/마무리에 맞춰 튼다.
const TGT_PRE_POSE := {
	"aqua": [[3.25, "down"], [4.05, "love"]],   # 침수에 엎어졌다가 물고기 떼에 love
}

# ── 시전자 무대 안무 — 원작 `action<El>_C` 실측 (2026-08-05 전수 채굴) ────────
#
# 각 속성의 시전자 레이어(this_00)·몸통(tag 1)·그림자(-50×el) 시퀀스를 옮긴 것.
# 스파인 모션은 **3단계**다: `ultimate1`(도약·부양) → `ultimate2`(부양 중 격양) → `wait`(복귀).
#   (actionFire_C 의 SSO 문자열 실측 — "ultimate1"·"ultimate2"·"wait")
# 시각은 시전 0초 기준. MoveBy 의 Δ 는 스택 소실이라 영상 정합으로 근사한 곳에 ASSUMPTION.
#
#   fire : ACT+0.25 홉(+75,h50) → EaseIn(MoveBy 4.35,(0,50)) 상승 → 3.0 대기 → 0.15 복귀
#   aqua : ACT+2.75 유영 드리프트(0.5→2.0→2.5) → 1.0 대기 → JumpTo(집, S×150)
#   earth: ACT+1.45 **연쇄 통통 점프** h150→200→250→300→400→350(간격 0.2) → JumpTo(집, S×200)
#   wind : ACT+2.0 상승 4연 이동(토네이도에 휩쓸림, 그림자 0 으로) → 4.15 부유 → 복귀
#   light: ACT+1.8 자리이동 → +2.5 **소멸**(섬광 속으로) → +7.15 재등장 → JumpTo(집)
#   chaos: ACT+1.15 → **화면 중앙으로 이동** → 적색 변신 → 3.05초 축소 → 소멸 → +8.65 복귀
#   holy : 몸통 FadeTo(1.0, 0) — 창 세례 동안 사라졌다가 +4 뒤 FadeTo(1.0, 255) 복귀
#   dark·shadow: ASSUMPTION — action 캐스터 항 미채굴, fire 꼴로 근사
#
## a = {node(레이어 Node2D), anim(AnimationPlayer|null), shadow(Node2D|null),
##      home(Vector2), stage(Vector2), scale(float), host(CanvasItem)}
## 반환 = 시전자가 제자리로 돌아오는 시각(초).
static func caster_fx(a: Dictionary, el: String, sp := 1.0) -> float:
	var node = a.get("node")
	if not (node is Node2D) or not is_instance_valid(node):
		return 0.0
	var n := node as Node2D
	var ap = a.get("anim")
	var shadow = a.get("shadow")
	var home: Vector2 = a.get("home", n.position)
	var stage: Vector2 = a.get("stage", n.position)
	var s := float(a.get("scale", 1.0))
	var host = a.get("host")
	var ctr := _screen_center(host) if host is CanvasItem else stage
	var dirc := 1.0 if stage.x <= ctr.x else -1.0      # 시전자 → 화면 중앙 방향
	var play := func(anim_name: String) -> void:
		if ap is AnimationPlayer and is_instance_valid(ap) \
				and (ap as AnimationPlayer).has_animation(anim_name):
			(ap as AnimationPlayer).play(anim_name)
	var anim_at := func(t: float, anim_name: String) -> void:
		var tw: Tween = n.create_tween()
		tw.tween_interval(maxf(0.01, t) / sp)
		tw.tween_callback(func() -> void: play.call(anim_name))
	var back := 0.0

	match el:
		"fire":
			# fire 실측: 홉 → 상승 → 대기 → 복귀
			var t := n.create_tween()
			t.tween_interval((ACT_AT + 0.25) / sp)
			_jump_by(t, n, Vector2(0.0, s * 75.0), 50.0, 1, 0.15 / sp)
			t.tween_property(n, "position", Vector2(0.0, -50.0), 4.35 / sp).as_relative()\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_interval(3.0 / sp)
			t.tween_property(n, "position", home, 0.15 / sp)
			anim_at.call(ACT_AT + 0.4, "ultimate1")
			# 격양(입 벌림)은 화이트아웃 직전 — 영상 정합(사용자 확정 2026-08-05).
			anim_at.call(ACT_AT + 4.2, "ultimate2")
			back = ACT_AT + 0.25 + 0.15 + 4.35 + 3.0 + 0.15
		"shadow":
			# 영상 실측(76.75~82.75s): 시전자가 **발밑 늪 소용돌이로 가라앉아 소멸**
			# (링의 marsh1 이 그 소용돌이다), run+5.4쯤 같은 자리에서 다시 솟는다.
			var t := n.create_tween()
			t.tween_interval((LEAD + 0.3) / sp)
			t.tween_property(n, "scale", Vector2(1.1, 0.75), 0.2 / sp)   # 빨려드는 스쿼시
			t.tween_property(n, "scale", Vector2(0.55, 0.15), 0.25 / sp)
			t.parallel().tween_property(n, "modulate:a", 0.0, 0.25 / sp)
			t.tween_interval((RUN_AT + 5.4 - LEAD - 1.1) / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home)
			t.tween_property(n, "scale", Vector2.ONE, 0.3 / sp)
			t.parallel().tween_property(n, "modulate:a", 1.0, 0.3 / sp)  # 늪에서 솟는다
			anim_at.call(LEAD + 0.1, "ultimate1")
			back = RUN_AT + 5.4 + 0.3
		"dark":
			# 영상 실측(+48.25~48.75s): 시전 직후 **흑자색으로 물들며 소멸** — 소용돌이가
			# 대신 싸우고, 폭발 뒤(run+7.6쯤) 제자리에 재등장한다.
			var t := n.create_tween()
			t.tween_interval((LEAD + 0.2) / sp)
			t.tween_property(n, "modulate", Color(0.25, 0.1, 0.35), 0.25 / sp)
			t.tween_property(n, "modulate:a", 0.0, 0.3 / sp)
			t.tween_interval(7.3 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.modulate = Color(1, 1, 1, 0)
					n.position = home)
			t.tween_property(n, "modulate:a", 1.0, 0.4 / sp)
			anim_at.call(LEAD + 0.1, "ultimate1")
			back = LEAD + 0.2 + 0.25 + 0.3 + 7.3 + 0.4
		"aqua":
			var t := n.create_tween()
			t.tween_interval((ACT_AT + 2.75) / sp)
			t.tween_property(n, "position", Vector2(dirc * 40.0, -30.0), 0.5 / sp)\
				.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(n, "position", Vector2(dirc * 90.0, -25.0), 2.0 / sp)\
				.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(n, "position", Vector2(dirc * -30.0, 25.0), 2.5 / sp)\
				.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_interval(1.0 / sp)
			_jump_by(t, n, Vector2(home.x - n.position.x, 0.0), s * 150.0, 1, 0.25 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home)
			anim_at.call(ACT_AT + 2.0, "ultimate1")
			back = ACT_AT + 2.75 + 5.0 + 1.0 + 0.25
			# 그림자 — 유영 동안 사라진다(FadeTo 0.5→0, +7.0 뒤 복귀).
			if shadow is CanvasItem and is_instance_valid(shadow):
				var st: Tween = (shadow as CanvasItem).create_tween()
				st.tween_interval((ACT_AT + 1.25) / sp)
				st.tween_property(shadow, "modulate:a", 0.0, 0.5 / sp)
				st.tween_interval(7.0 / sp)
				st.tween_property(shadow, "modulate:a", 1.0, 0.25 / sp)
		"earth":
			# 연쇄 통통 점프 — JumpBy 6연(높이 150→400×S). Δx 는 소실 → 중앙 쪽으로
			# 조금씩 튀다 돌아온다(ASSUMPTION).
			var hops := [[0.3, 150.0, 50.0], [0.3, 200.0, 40.0], [0.3, 250.0, 30.0],
				[0.3, 300.0, -30.0], [0.5, 400.0, -40.0], [0.3, 350.0, -50.0]]
			var t := n.create_tween()
			t.tween_interval((ACT_AT + 1.45) / sp)
			for h_e in hops:
				t.tween_interval(0.2 / sp)
				_jump_by(t, n, Vector2(dirc * float(h_e[2]), 0.0), s * float(h_e[1]), 1,
					float(h_e[0]) / sp)
			t.tween_interval(0.2 / sp)
			t.tween_property(n, "position", stage, 0.1 / sp)
			t.tween_interval(1.65 / sp)
			_jump_by(t, n, Vector2(home.x - stage.x, home.y - stage.y), s * 200.0, 1,
				0.25 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home)
			anim_at.call(ACT_AT + 0.2, "ultimate1")
			anim_at.call(ACT_AT + 3.5, "ultimate2")     # ASSUMPTION
			back = ACT_AT + 1.45 + (0.2 + 0.3) * 5.0 + 0.2 + 0.5 + 0.2 + 0.1 + 1.65 + 0.25
		"wind":
			var t := n.create_tween()
			t.tween_interval((ACT_AT + 2.0) / sp)
			t.tween_property(n, "position", Vector2(0.0, -140.0), 0.15 / sp).as_relative()
			t.tween_property(n, "position", Vector2(dirc * 60.0, -60.0), 0.5 / sp).as_relative()
			t.tween_property(n, "position", Vector2(dirc * -80.0, -35.0), 0.25 / sp).as_relative()
			t.tween_property(n, "position", Vector2(dirc * 20.0, -15.0), 0.1 / sp).as_relative()
			t.tween_interval(4.15 / sp)
			t.tween_property(n, "position", home, 0.15 / sp)
			anim_at.call(ACT_AT + 1.8, "ultimate1")
			back = ACT_AT + 2.0 + 1.0 + 4.15 + 0.15
			# 그림자 — 공중이라 0 으로 줄었다가 착지에 돌아온다(실측 S+0.75 → 0.9 → 0).
			if shadow is Node2D and is_instance_valid(shadow):
				var sn := shadow as Node2D
				var bs := sn.scale
				var st: Tween = sn.create_tween()
				st.tween_interval((ACT_AT + 2.0) / sp)
				st.tween_property(sn, "scale", bs * (s + 0.75), 0.15 / sp)
				st.tween_interval(0.5 / sp)
				st.tween_property(sn, "scale", bs * (s + 0.9), 0.25 / sp)
				st.tween_property(sn, "scale", Vector2.ZERO, 0.1 / sp)
				st.tween_interval(4.15 / sp)
				st.tween_property(sn, "scale", bs, 0.15 / sp)
		"light":
			# 실측(액션 + 영상 40.0~45.0s): **화면 중앙으로 이동**(Place) → 1차 대섬광에
			# 소멸(Hide) → 2차 섬광 걷힐 때 중앙에 재등장(Show) → 제자리로 점프.
			var t := n.create_tween()
			t.tween_interval((ACT_AT + 1.55) / sp)
			t.tween_property(n, "position", Vector2(ctr.x, stage.y), 0.2 / sp)
			t.tween_interval(0.75 / sp)
			t.tween_property(n, "modulate:a", 0.0, 0.15 / sp)   # 섬광 속으로
			t.tween_interval(5.0 / sp)
			t.tween_property(n, "modulate:a", 1.0, 0.25 / sp)   # 중앙 재등장
			t.tween_interval(1.0 / sp)
			_jump_by(t, n, Vector2(home.x - ctr.x, 0.0), s * 150.0, 1, 0.25 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home)
			anim_at.call(ACT_AT + 0.25, "ultimate1")
			back = ACT_AT + 1.55 + 0.2 + 0.75 + 0.15 + 5.0 + 0.25 + 1.0 + 0.25
		"chaos":
			# 🔴 2026-08-06 영상 프레임 실측 재작성(T0 = 66.53s · timeScale 1.35).
			#   종전엔 시전자가 제자리에서 그냥 걸어 중앙으로 갔는데, 원작은 **순간이동**이다:
			#     1.6  (67.73) 제자리에서 사라진다 — 0.6초 동안 화면에 아무것도 없다
			#     2.25 (68.20) 화면 중앙에 **가는 붉은 세로 빔**이 내려꽂힌다
			#     2.43 (68.33) 빔이 펴지며 **핏빛 실루엣**으로 재림, 합체 문양이 함께 터진다
			#     ~6.5         백열에 삼켜진다 (그때까지 계속 핏빛 — 종전엔 0.9초만 붉었다)
			#     ~8.6 (73.2)  제자리로 복귀
			# ASSUMPTION: 강하 빔 전용 프레임을 못 찾았다(`--grep chaos_` 는 circle/dust/meteo
			#   7종뿐). 시전자 자신을 가로로 눌러(scale.x 0.04) 그 그림을 낸다 — 프레임을
			#   확보하면 이 callback 한 곳만 갈아 끼우면 된다.
			var CHAOS_GONE := 1.6             # 소멸 시각(시전 기준)
			var CHAOS_BEAM := 0.18            # 빔이 꽂혀 있는 시간
			var CHAOS_BURN := 6.5             # 백열에 삼켜지는 시각
			var CHAOS_HOME := 8.6             # 복귀 시각
			var bs := n.scale
			var t := n.create_tween()
			t.tween_interval(CHAOS_GONE / sp)
			t.tween_property(n, "scale", Vector2(bs.x * 1.15, bs.y * 0.7), 0.1 / sp)  # 빨려드는 스쿼시
			t.tween_property(n, "scale", Vector2(bs.x * 0.15, bs.y * 1.35), 0.12 / sp)
			t.parallel().tween_property(n, "modulate:a", 0.0, 0.12 / sp)
			# 강하 빔 — 중앙에 눌린 채로 붉게 나타난다.
			t.tween_interval((ACT_AT - CHAOS_GONE - 0.22) / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = Vector2(ctr.x, stage.y)
					n.scale = Vector2(bs.x * 0.04, bs.y * 1.3)
					n.modulate = Color(0.85, 0.05, 0.05, 1.0))
			t.tween_interval(CHAOS_BEAM / sp)
			t.tween_property(n, "scale", bs, 0.12 / sp)                    # 펴지며 재림
			# 영상 68.33~70.9 의 시전자는 **거의 검붉은 실루엣**이다(밝은 적색이 아니다).
			t.parallel().tween_property(n, "modulate", Color(0.32, 0.05, 0.06, 1.0), 0.12 / sp)
			# 핏빛 유지 → 백열에 삼켜짐 → 복귀
			t.tween_interval((CHAOS_BURN - ACT_AT - CHAOS_BEAM - 0.12) / sp)
			t.tween_property(n, "modulate:a", 0.0, 0.3 / sp)
			t.tween_interval((CHAOS_HOME - CHAOS_BURN - 0.3) / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.modulate = Color(1, 1, 1, 0)   # 적색 변신을 되돌리고 제자리에서 다시 켠다
					n.scale = bs
					n.position = home)
			t.tween_property(n, "modulate:a", 1.0, 0.3 / sp)
			anim_at.call(ACT_AT + 0.4, "ultimate1")
			back = CHAOS_HOME + 0.3
		"holy":
			# 몸통 페이드 아웃 → 창 세례 뒤 복귀(실측 FadeTo(1.0,0) … FadeTo(1.0,255)).
			var t := n.create_tween()
			t.tween_interval((ACT_AT + 2.25) / sp)
			t.tween_property(n, "modulate:a", 0.0, 1.0 / sp)
			t.tween_interval(2.0 / sp)
			t.tween_property(n, "modulate:a", 1.0, 1.0 / sp)
			anim_at.call(ACT_AT + 0.4, "ultimate1")
			back = ACT_AT + 2.25 + 1.0 + 2.0 + 1.0
		_:
			back = ACT_AT + 7.0
	anim_at.call(back + 0.1, "wait")                    # 실측: 마지막은 "wait" 복귀
	return back / sp


## Cocos `CCEaseInOut(action, rate)` 의 시간 곡선.
##   t*=2; t<1 ? 0.5*t^rate : 1 − 0.5*(2−t)^rate
static func _ease_io(x: float, rate: float) -> float:
	var t := x * 2.0
	if t < 1.0:
		return 0.5 * pow(t, rate)
	return 1.0 - 0.5 * pow(2.0 - t, rate)


## Cocos `CCJumpBy(sec, delta, height, jumps)` — 선형 이동 위에 포물선 hop 을 얹는다.
##   frac = fmod(t*jumps, 1); y += height*4*frac*(1−frac); 그 위에 delta*t.
##   ⚠️ delta·height 는 **cocos 좌표(y 위쪽 +)** 로 준다 — 여기서 뒤집는다.
static func _jump_by(t: Tween, n: Node2D, delta: Vector2, h: float, jumps: int,
		sec: float, rate := 0.0) -> void:
	# ⚠️ 시작점은 **그 단계가 실제로 시작될 때** 읽어야 한다 — 트윈은 지금 조립되지만
	#    앞 단계가 이미 노드를 옮겨 놓기 때문이다(연속 3단 점프에서 어긋났다).
	var from := [Vector2.ZERO, false]
	var j := maxi(1, jumps)
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(n):
			return
		if not bool(from[1]):
			from[0] = n.position
			from[1] = true
		var u := x if rate <= 0.0 else _ease_io(x, rate)
		var frac := fmod(u * float(j), 1.0)
		var hop := h * 4.0 * frac * (1.0 - frac)
		n.position = (from[0] as Vector2) + Vector2(delta.x * u, -(delta.y * u + hop)),
		0.0, 1.0, maxf(0.01, sec))


## 원작 `VisibleRect::center()` 를 **host 로컬 좌표**로. host 원점이 화면 원점이 아닐 수 있다
## (대전=씬 Control 이라 같지만, 확인 창에서는 무대 노드다 — `_screen_veil` 과 같은 사정).
static func _screen_center(host: CanvasItem) -> Vector2:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	return host.get_global_transform_with_canvas().affine_inverse() * (vis * 0.5)


## 포물선 이동 한 구간(원작 `CCJumpTo` 한 번에 대응).
static func _arc(t: Tween, n: Node2D, to: Vector2, h: float, sec: float) -> void:
	var from := [Vector2.ZERO, false]              # 시작점은 그 단계 시작 시점에 읽는다
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(n):
			return
		if not bool(from[1]):
			from[0] = n.position
			from[1] = true
		var p := (from[0] as Vector2).lerp(to, x)
		p.y -= h * 4.0 * x * (1.0 - x)
		n.position = p,
		0.0, 1.0, sec)


# ── 임시 골격(미이식 8속성) ─────────────────────────────────────────────────
## `run<El>` 을 아직 안 옮긴 속성에 쓰는 자리표시자 — 최장 프레임 계열 1개를 돌린다.
## **원작이 아니다.** 속성을 이식할 때마다 이 분기에서 빠진다.
static func _run_fallback(host: CanvasItem, el: String, at: Vector2,
		sp: float, mat: CanvasItemMaterial, alive: Callable) -> void:
	var man := manifest(el)
	var fam := longest_family(man, prefix(el))
	if fam.is_empty():
		return
	var spr := _spr(el, fam[0])
	if spr == null:
		return
	spr.position = at
	spr.z_index = 101
	host.add_child(spr)
	var i := 0
	var t := Timer.new()
	t.wait_time = FALLBACK_FRAME_SEC / sp
	t.autostart = true
	spr.add_child(t)
	t.timeout.connect(func() -> void:
		i += 1
		var ok := true if not alive.is_valid() else bool(alive.call())
		if not ok or i >= fam.size():
			if is_instance_valid(spr):
				spr.queue_free()
			return
		_set_frame(spr, el, String(fam[i])))


# ── 공용 헬퍼 ───────────────────────────────────────────────────────────────
## `<fmt>` 의 번호를 lo..hi 로 갈아 끼우며 프레임을 돌린다. 끝나면 free(옵션).
static func _play_frames(spr: Node2D, el: String, fmt: String, lo: int, hi: int,
		sec: float, free_at_end := false) -> void:
	var n := lo
	var t := Timer.new()
	t.wait_time = maxf(0.01, sec)
	t.autostart = true
	spr.add_child(t)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		if n > hi:
			if free_at_end:
				spr.queue_free()
			else:
				t.stop()
			return
		_set_frame(spr, el, fmt % n)
		n += 1)


## `<fmt>` 의 lo..hi 프레임을 **반복** 재생한다(원작 CCRepeatForever). `total` 초 뒤 멈춘다(0=무한).
static func _loop_frames(spr: Node2D, el: String, fmt: String, lo: int, hi: int,
		sec: float, total := 0.0) -> void:
	var n := lo
	var t := Timer.new()
	t.wait_time = maxf(0.01, sec)
	t.autostart = true
	spr.add_child(t)
	var elapsed := [0.0]
	t.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		elapsed[0] += t.wait_time
		if total > 0.0 and elapsed[0] >= total:
			t.stop()
			return
		_set_frame(spr, el, fmt % n)
		n = lo if n >= hi else n + 1)


## `_loop_frames` 의 역방향판(hi → lo). 원작 `initWind` 의 두 번째 CCAnimation 이
## `whirl4 → whirl3 → whirl2 → whirl1`(0.025초)로 **거꾸로** 도는 겹을 만든다.
static func _loop_frames_rev(spr: Node2D, el: String, fmt: String, hi: int, lo: int,
		sec: float, total := 0.0) -> void:
	var n := hi
	var t := Timer.new()
	t.wait_time = maxf(0.01, sec)
	t.autostart = true
	spr.add_child(t)
	var elapsed := [0.0]
	t.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		elapsed[0] += t.wait_time
		if total > 0.0 and elapsed[0] >= total:
			t.stop()
			return
		_set_frame(spr, el, fmt % n)
		n = hi if n <= lo else n - 1)


static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


## `<prefix><name><N>` 꼴 중 원소가 가장 많은 계열을 프레임 순서대로 반환.
static func longest_family(man: Dictionary, pfx: String) -> Array:
	for b in families(man, pfx):
		return b["frames"]
	return []


## 그 속성의 번호 계열 전부 — [{name, frames:[키…]}], **긴 것부터**.
static func families(man: Dictionary, pfx: String) -> Array:
	var groups := {}
	for k in man:
		var s := String(k)
		if not s.begins_with(pfx) or s.begins_with(pfx + "circle"):
			continue
		var tail := s.substr(pfx.length())
		var base := tail.rstrip("0123456789")
		if base == tail:
			continue                    # 번호 없는 단품은 시퀀스가 아니다
		if not groups.has(base):
			groups[base] = []
		(groups[base] as Array).append(s)
	var out: Array = []
	for b in groups:
		var arr: Array = groups[b]
		# ⚠️ 문자열 정렬이라 10 이 2 보다 앞선다 — **번호로** 정렬해야 프레임 순서가 맞는다.
		arr.sort_custom(func(x, y): return _frame_no(String(x)) < _frame_no(String(y)))
		out.append({"name": String(b), "frames": arr})
	out.sort_custom(func(x, y): return x["frames"].size() > y["frames"].size())
	return out


static func _frame_no(key: String) -> int:
	var digits := ""
	for i in range(key.length() - 1, -1, -1):
		var c := key[i]
		if c < "0" or c > "9":
			break
		digits = c + digits
	return int(digits) if digits != "" else 0


static func manifest(element: String) -> Dictionary:
	return _man(DIR_PREFIX + element)


static func prefix(element: String) -> String:
	return "skill_ultimate_%s_%s_" % [element, element]


static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func _tex(element: String, key: String) -> Texture2D:
	return AtlasUI.tex(DIR_PREFIX + element, key)


## 프레임 스프라이트 — **트림 보정 포함**. `AtlasUI.spr_cocos` 를 그대로 쓴다(§3 헬퍼 재사용).
##
## ⚠️ 여기서 직접 `Sprite2D` 를 만들면 안 된다. 각성기 프레임은 트림 오프셋이 프레임마다
##    크게 다르다 — 불기둥이 `fillar1 off=(-6,-51)` → `fillar2~7 off=(-6,0)` 이라 애니 첫
##    프레임에서 51pt 튄다. 폭발도 `explosion1 off=(3,-39)` → `explosion6 off=(0,24)` 로
##    63pt 를 오간다. 원작은 **원본 캔버스 기준**으로 놓으므로 그 차이가 곧 연출이다.
##
## 반환 = 홀더 `Node2D`(원점 = 원작 앵커점). 프레임 교체는 `_set_frame` 을 쓴다.
## ⚠️ `Design.ASSET_SCALE` 은 **안쪽 Sprite2D 가 이미 흡수**한다 — 여기 또 곱하지 말 것(§9-2).
## 확인 창(`dev_ultimate_fx`)이 "우리가 실제로 쓰는 프레임"을 알 수 있게 **실제 요청을 기록**한다.
## 종전엔 창이 "가장 긴 계열 + circle1" 이라는 추측으로 표시해서, 이식을 마친 뒤에도
## `spear`·`well`·`stone` 을 "안 쓰는 단품" 으로 잘못 적었다(2026-08-05).
static var used_keys := {}

## 앵커를 지정해 만든다. 원작은 대부분 **아래 가운데**(0.5, 0)로 세워 바닥에 붙인다 —
## 기본값(가운데)으로 두면 스프라이트가 제 높이의 절반만큼 떠 보인다.
const BOTTOM := Vector2(0.5, 0.0)

static func _spr_a(element: String, key: String, anchor: Vector2) -> Node2D:
	used_keys[element + "/" + key] = true
	var n := AtlasUI.spr_cocos(DIR_PREFIX + element, key, 1.0, anchor)
	if n != null:
		n.set_meta("anchor", anchor)   # `_set_frame` 이 프레임 교체 때 같은 앵커를 다시 쓴다
	return n


static func _spr(element: String, key: String) -> Node2D:
	used_keys[element + "/" + key] = true
	return AtlasUI.spr_cocos(DIR_PREFIX + element, key)


## PMA 프레임의 불투명도 — **`modulate:a` 만 건드리면 안 된다**.
##
## 🔴 2026-08-06 실측(물 수면). `AtlasUI.spr_cocos` 는 모든 스프라이트에
##   `BLEND_MODE_PREMULT_ALPHA` 를 걸고 아틀라스도 PMA 로 구워져 있다. 그 블렌드는
##   `out = src.rgb + dst*(1 − src.a)` 라서 alpha 만 낮추면 **rgb 가 그대로 더해져 가산 합성**이
##   된다 — 반투명이 아니라 흰색으로 탄다(수면 밑단 (204,255,255) → 실측 (255,255,255)).
##   PMA 에서 배율 a 의 정답은 rgb·alpha 를 **같이** 곱하는 것이다.
static func _set_alpha(n: CanvasItem, a: float) -> void:
	n.modulate = Color(a, a, a, a)


## 위와 같은 이유로 페이드도 `modulate` 전체를 민다. 반환값으로 `.parallel()` 을 이어 쓸 수 있다.
static func _fade_pma(t: Tween, n: CanvasItem, a: float, sec: float) -> PropertyTweener:
	return t.tween_property(n, "modulate", Color(a, a, a, a), sec)


## `_spr` 홀더의 프레임을 갈아 끼운다 — **트림 오프셋·앵커를 함께 다시 잡는다**.
##
## 🔴 2026-08-05 앵커 정정 — 종전엔 앵커 항을 빼먹어(가운데 앵커 가정) BOTTOM 앵커였던
##   불기둥이 첫 프레임 교체 순간 **절반 높이만큼 아래로 떨어졌다**(밑변이 화면 바닥에 붙고
##   평평한 꼭대기가 화면 중간에 걸렸다 — 사용자 실측 지적의 진범). 앵커는 `_spr_a` 가
##   홀더 meta 에 남긴 것을 그대로 쓴다.
static func _set_frame(holder: Node2D, element: String, key: String) -> bool:
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return false
	var dir := DIR_PREFIX + element
	var t := AtlasUI.tex(dir, key)
	if t == null:
		return false
	used_keys[element + "/" + key] = true
	var s := holder.get_child(0) as Sprite2D
	if s == null:
		return false
	var S := Design.ASSET_SCALE
	var info: Dictionary = AtlasUI.manifest(dir).get(key, {})
	var src: Array = info.get("src", [float(info.get("w", t.get_width())),
		float(info.get("h", t.get_height()))])
	var off: Array = info.get("off", [0, 0])
	var anchor: Vector2 = holder.get_meta("anchor", Vector2(0.5, 0.5))
	s.texture = t
	# `spr_cocos` 와 같은 식(앵커 기준 원본 캔버스 중심 + 트림 오프셋).
	s.position = Vector2(
		(0.5 - anchor.x) * float(src[0]) * S + float(off[0]) * S,
		(anchor.y - 0.5) * float(src[1]) * S - float(off[1]) * S)
	return true
