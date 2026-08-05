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

## 아직 `run<El>` 을 이식하지 않은 속성의 임시 골격 — 최장 프레임 계열 1개.
const FALLBACK_FRAME_SEC := 0.08


# ── 진입점 ──────────────────────────────────────────────────────────────────
## 각성기 재생. host 아래에 스프라이트를 붙인다(좌표는 host 로컬).
##   ctx = {element, at(**화면 중앙**), ring_at(시전자 발밑), scale(S), dir(+1/-1),
##          speed, alive(Callable), mat}
##
## 🔴 2026-08-05 기준점 정정 — 연출 본체는 **시전자가 아니라 화면 중앙 기준**이다.
##   근거: `initAqua` 가 자기 `getPosition()` 을 `this+0x270` 에 저장해 **`dir`(±1) 을 고르는
##   데에만** 쓰고, 실제 배치는 전부 `this->getContentSize()`(= 화면 크기)의 `W*0.5, H*0.5`
##   에서 잰다. 다른 속성도 같다(`initFire` 앵커표 = `중심 + dir*W*0.25 …`).
##   ⇒ 시전자는 **좌우 반전 방향만** 정하고, 불기둥·물·태양·구슬은 화면 한가운데 난다.
##   사용자 제공 원작 영상(콜로세움)이 이를 뒷받침한다 — 불은 화면 바닥을 가로지르고,
##   물은 화면을 채우고, 어둠 구슬은 화면 가운데다.
##   단 **콜로세움 바닥 링**(`init<El>_C`)만은 `CCPoint::ZERO − (0, S*87.5)` = 시전자 발밑이다.
## 반환 = 총 길이(초). 원작 `getDuration()` 콜로세움 표.
static func play(host: CanvasItem, ctx: Dictionary) -> float:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return 0.0
	var el := String(ctx.get("element", ""))
	var man := manifest(el)
	if man.is_empty():
		return 0.0
	var at: Vector2 = ctx.get("at", Vector2.ZERO)
	var ring_at: Vector2 = ctx.get("ring_at", at)
	var s := float(ctx.get("scale", 1.0))
	var dir := float(ctx.get("dir", 1.0))
	var sp := maxf(0.05, float(ctx.get("speed", 1.0)))
	var alive: Callable = ctx.get("alive", Callable())
	var mat: CanvasItemMaterial = ctx.get("mat", null)
	if mat == null:
		mat = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

	_combine_outline(host, el, at, sp)   # dark·shadow·wind·chaos 만 갖는 회전 문양
	_build_ring(host, el, ring_at, s, sp, mat)   # 바닥 링만 시전자 발밑
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	match el:
		"fire":   _run_fire(host, at, s, dir, sp, mat, alive)
		"earth":  _run_earth(host, at, dir, sp, rng)
		"aqua":   _run_aqua(host, at, dir, sp, rng)
		"wind":   _run_wind(host, at, dir, sp, rng)
		"dark":   _run_dark(host, at, dir, sp, rng)
		"light":  _run_light(host, at, dir, sp, rng)
		"holy":   _run_holy(host, at, dir, sp, rng)
		"chaos":  _run_chaos(host, at, dir, sp, rng)
		"shadow": _run_shadow(host, at, dir, sp, rng)
		_:        _run_fallback(host, el, at, sp, mat, alive)
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
		host.add_child(base)
		# nest = base 의 **자식**. 원작은 base 의 contentSize 중심에 놓는다 = 로컬 (0,0).
		if String(cfg.get("nest", "")) != "":
			var nest := _spr(el, pfx + String(cfg["nest"]))
			if nest != null:
				nest.z_index = -1
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

	# `_C` 추가 프레임(dark shade · shadow twist) — 원작 z=5, tag 0x1883f
	var ex := String(RING_EXTRA.get(el, ""))
	if ex != "":
		var e := _spr(el, pfx + ex)
		if e != null:
			e.position = pos
			e.z_index = 95
			host.add_child(e)

	# `_C` 스파인(holy 날개 · shadow 본체)
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
			t.tween_interval(RING_LEAD / sp)
			t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
			t.tween_interval(RING_HOLD / sp)
			t.tween_property(n, "scale", n.scale * (s + 0.25) * RING_BURST_MUL, RING_BURST / sp)
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
## 원작 `initFire` + `runFire`: 20지점에 (폭발 + 지진 + 화염기둥 + 돌)을 지연표대로 터뜨리고,
## base+4.25초에 화면을 하얗게 태운다.
static func _run_fire(host: CanvasItem, at: Vector2, s: float, dir: float,
		sp: float, mat: CanvasItemMaterial, alive: Callable) -> void:
	var pfx := prefix("fire")
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in FIRE_POINTS.size():
		var p: Array = FIRE_POINTS[i]
		# 원작 앵커표(`this + i*8 + 0x2d8`) = 레이어 중심 + `dir*(W*wf + dx)` + dy.
		# cocos y-up 이라 dy 부호를 뒤집어 Godot 으로 옮긴다.
		var pos := at + Vector2(dir * (vis.x * float(p[0]) + float(p[1])), -float(p[2]))
		_fire_burst(host, pfx, pos, int(FIRE_Z[i]) * 5, float(FIRE_DELAYS[i]) / sp,
			rng.randi() % 6 + FIRE_STONE_MIN, s, sp, mat, alive, rng)

	# 화면 백색 암전
	var flash := _screen_veil(host, at, Color(1, 1, 1), 120)
	var ft := flash.create_tween()
	ft.tween_interval(FIRE_FLASH_AT / sp)
	ft.tween_property(flash, "color:a", 1.0, FIRE_FLASH_IN / sp)
	ft.tween_interval(FIRE_FLASH_HOLD / sp)
	ft.tween_property(flash, "color:a", 0.0, FIRE_FLASH_OUT / sp)
	ft.tween_callback(flash.queue_free)


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
			var lt := pillar.create_tween()
			lt.tween_interval(FIRE_LAG / sp)
			lt.tween_property(pillar, "scale", Vector2.ONE * 1.25, 0.1 / sp)
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

static func _combine_outline(host: CanvasItem, el: String, at: Vector2, sp: float) -> void:
	var c: Dictionary = COMBINE.get(el, {})
	if c.is_empty():
		return
	# 컨테이너 = 원작 `CCLayerColor`(tag 0x1d650). 눌린 배율만 갖고 **회전하지 않는다**.
	var holder := Node2D.new()
	holder.position = at
	holder.z_index = 83                 # 드래곤 뒤(바닥 링보다 아래)
	holder.scale = Vector2(COMBINE_SCALE, COMBINE_SCALE_Y)
	host.add_child(holder)
	# 흰 외곽선(0x18832) — 원작 `setScale(0)` 으로 시작해 `EaseIn(ScaleTo(0.25, 1.0), 0.5)` 로 편다.
	var w := AtlasUI.spr_cocos(COMBINE_WHITE_DIR, COMBINE_WHITE_KEY)
	if w != null:
		w.z_index = 1
		w.scale = Vector2.ZERO
		holder.add_child(w)
		var wt := w.create_tween()
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
		ot.tween_interval(0.25 / sp)
		ot.tween_property(o, "modulate:a", 200.0 / 255.0, 0.75 / sp)
		ot.tween_interval(3.5 / sp)
		ot.tween_property(o, "modulate:a", 0.0, 0.5 / sp)
	if holder.get_child_count() == 0:
		holder.queue_free()
		return
	# 회전은 **컨테이너가 아니라 자식마다** — 원작이 tag 0x18832·0x18831 에 각각 건다.
	# ⚠️ 원작 인자는 `CCEaseInOut(RotateBy(4.5, 720°), −0.25)` 인데 **rate 가 음수**다.
	#    Cocos 식(`0.5·t^rate`)에 넣으면 t→0 에서 발산해 첫 프레임이 720°를 몇 바퀴 넘겨 버린다
	#    ⇒ 그대로 쓸 수 없다. 회전량·시간은 실측 그대로 두고 곡선만 통상 sine in/out 으로 둔다.
	for ch in holder.get_children():
		var n2 := ch as Node2D
		var st: Tween = n2.create_tween()
		st.tween_property(n2, "rotation_degrees", COMBINE_SPIN_DEG, COMBINE_SPIN_SEC / sp)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 정리는 **holder 에 매인 트윈**으로 — SceneTreeTimer 는 holder 보다 오래 살아
	# 씬이 먼저 사라지면 "Lambda capture was freed" 경고를 낸다.
	var ht: Tween = holder.create_tween()
	ht.tween_interval((COMBINE_SPIN_SEC + 1.0) / sp)
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
		t.tween_property(mt, "scale", Vector2.ONE, 2.0 / sp)
		# 원작은 `earth_mountain1~15` 를 **낱개 스프라이트 15장**으로 base + (0, 90) 에
		# 미리 깔아 두고(z=2, tag 0x1fd5f+i, 처음 숨김) 차례로 보인다.
		_play_frames(mt, el, pfx + "mountain%d", 1, 15, 0.08 / sp)
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
		lt.tween_property(lg, "modulate:a", 1.0, 0.25 / sp)
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
	var stone_h := 60.0
	_swarm(host, el, pfx + "stone", EARTH_STONES, base, Vector2(200.0, stone_h), 95, rng,
		func(n: Node2D, i: int, r: RandomNumberGenerator) -> void:
			var dx := n.position.x - base.x
			var lag := float(r.randi() % 4) * 0.05 / sp     # 원작 `(rand%4)*0.05`
			var t3: Tween = n.create_tween()               # Spawn 한쪽 = 10바퀴 회전
			t3.tween_interval(lag)
			t3.tween_property(n, "rotation_degrees", EARTH_SPIN_DEG, EARTH_SPIN_SEC / sp)\
				.as_relative()
			var t4: Tween = n.create_tween()               # Spawn 다른쪽 = 3단 점프
			t4.tween_interval(lag)
			_jump_by(t4, n, Vector2(dx + dx, -20.0), stone_h * 2.0, 1, 0.5 / sp, 1.0)
			_jump_by(t4, n, Vector2(dx + dx, 0.0), stone_h * 0.75, 1, 0.25 / sp, 0.5)
			_jump_by(t4, n, Vector2(dx + dx, 0.0), stone_h * 0.25, 1, 0.125 / sp, 0.25)
			t4.tween_property(n, "modulate:a", 0.0, 0.75 / sp)
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


# ── aqua (11.0초) — 화면이 물빛으로 물들고 상어가 지나간다 ────────────────────
## 원작 `runAqua`: 화면 막을 **TintTo** 로 두 번 물들인다(물속에 잠기는 색조).
##     TintTo(1.0, 194,255,255) → Delay(3.0) → TintTo(1.0, 25,60,125) → Delay(0.75)
##     → FadeTo(0.5, 0) → Delay(5.0)
## 상어(tag 0x18830) = RepeatForever(애니) + JumpTo(0.25, …, 75) → MoveBy(0.5) →
##     JumpTo(0.25, …, 50) → Delay(5.25) → FadeTo(0.5, 0)
## 거품 **49개** · 물고기 5종 · 수면(0x18835)은 Delay(6.25) → FadeTo(0.5, 0).
const AQUA_TINT1 := Color(194.0 / 255.0, 1.0, 1.0)
const AQUA_TINT2 := Color(25.0 / 255.0, 60.0 / 255.0, 125.0 / 255.0)
const AQUA_BUBBLES := 49        # 원작 루프 상한 0x31
const AQUA_SHARK_S := 1.75      # 원작 setScaleX/Y(1.75)

static func _run_aqua(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "aqua"
	var pfx := prefix(el)

	var veil := _screen_veil(host, at, AQUA_TINT1, 85)
	var vt := veil.create_tween()
	vt.tween_property(veil, "color", Color(AQUA_TINT1.r, AQUA_TINT1.g, AQUA_TINT1.b, 0.45), 1.0 / sp)
	vt.tween_interval(3.0 / sp)
	vt.tween_property(veil, "color", Color(AQUA_TINT2.r, AQUA_TINT2.g, AQUA_TINT2.b, 0.45), 1.0 / sp)
	vt.tween_interval(0.75 / sp)
	vt.tween_property(veil, "color:a", 0.0, 0.5 / sp)
	vt.tween_callback(veil.queue_free)

	# 수면 — 원작 `initAqua`: **화면 폭에 맞춰 늘리고 화면 바닥**에 둔다.
	#   `setOpacity(100)` · `setScaleX(화면폭 / 수면폭)` · pos = VisibleRect::bottom() − (0, 수면높이)
	#   그 **자식**으로 물빛 `CCLayerColor`(anchor 0.5/1, 수면 폭·화면 높이)를 매달아
	#   수면 아래를 채운다 ⇒ 물이 차오르는 그림이다(종전엔 화면 전체 틴트였다).
	var vis0: Vector2 = host.get_viewport().get_visible_rect().size
	var ctr0 := _screen_center(host)
	var surf := _spr_a(el, pfx + "surface1", Vector2(0.5, 0.5))
	if surf != null:
		var sw := 1.0
		var man0 := manifest(el)
		var info: Dictionary = man0.get(pfx + "surface1", {})
		var fw := float(info.get("w", 1.0)) * Design.ASSET_SCALE
		var fh := float(info.get("h", 1.0)) * Design.ASSET_SCALE
		if fw > 1.0:
			sw = vis0.x / fw
		surf.scale = Vector2(sw, 1.0)
		surf.position = Vector2(ctr0.x, ctr0.y + vis0.y * 0.5 - fh)
		surf.z_index = 86
		surf.modulate.a = 100.0 / 255.0
		host.add_child(surf)
		var water := ColorRect.new()          # 원작 CCLayerColor(수면의 자식, anchor 0.5/1)
		water.color = Color(AQUA_TINT2.r, AQUA_TINT2.g, AQUA_TINT2.b, 0.0)
		water.size = Vector2(fw, vis0.y)
		water.position = Vector2(-fw * 0.5, 0.0)
		water.z_index = -1
		water.mouse_filter = Control.MOUSE_FILTER_IGNORE
		surf.add_child(water)
		var wt := water.create_tween()
		wt.tween_property(water, "color:a", 0.45, 1.0 / sp)
		_play_frames(surf, el, pfx + "surface%d", 2, 4, 0.1 / sp)
		var st := surf.create_tween()
		st.tween_property(surf, "position", Vector2(ctr0.x, ctr0.y - vis0.y * 0.1), 1.5 / sp)
		st.tween_interval(4.75 / sp)
		st.tween_property(surf, "modulate:a", 0.0, 0.5 / sp)
		st.tween_callback(surf.queue_free)

	# 상어 — 원작 `initAqua`: scaleY 1.75 · scaleX = dir×1.75 · rotation = dir×15° ·
	#   pos = 화면중앙 + (dir×(중앙x + 상어폭×1.5), −80) = **화면 밖 옆구리**에서 들어온다.
	var shark := _spr(el, pfx + "shark1")
	if shark != null:
		var vis: Vector2 = host.get_viewport().get_visible_rect().size
		var sk_w := float(manifest(el).get(pfx + "shark1", {}).get("w", 200.0)) * Design.ASSET_SCALE
		shark.position = ctr0 + Vector2(dir * (vis.x * 0.5 + sk_w * 1.5), 80.0)
		shark.z_index = 100
		shark.scale = Vector2(-dir * AQUA_SHARK_S, AQUA_SHARK_S)
		shark.rotation_degrees = -dir * 15.0
		host.add_child(shark)
		_play_frames(shark, el, pfx + "shark%d", 2, 8, 0.03 / sp)
		var kt := shark.create_tween()
		# 원작 `runAqua` 조립(2026-08-05 복원): 목적지는 **화면 중앙**이지 앞이 아니다.
		#   JumpTo(0.25, center, 75, 1) → MoveBy(0.5, (0,−50)) → JumpTo(0.25, center+(0,217.5), 50, 1)
		#   → Delay(5.25) → FadeTo(0.5, 0)
		var ctr := ctr0
		_arc(kt, shark, ctr, 75.0, 0.25 / sp)
		kt.tween_property(shark, "position", Vector2(0.0, 50.0), 0.5 / sp).as_relative()
		_arc(kt, shark, ctr + Vector2(0.0, -217.5), 50.0, 0.25 / sp)
		kt.tween_interval(5.25 / sp)
		kt.tween_property(shark, "modulate:a", 0.0, 0.5 / sp)
		kt.tween_callback(shark.queue_free)

	# 거품 — 원작은 **화면 바닥 전폭**에 뿌린다(pos = (rand % 화면폭, 0)), scale (rand%5)×0.25,
	#   opacity 0, z = rand%5. 시전자 주변이 아니다.
	_swarm(host, el, pfx + "bubble", AQUA_BUBBLES,
		Vector2(ctr0.x, ctr0.y + vis0.y * 0.5), Vector2(vis0.x * 0.5, 0.0), 98, rng,
		func(n: Node2D, i: int, r: RandomNumberGenerator) -> void:
			var t: Tween = n.create_tween()
			t.tween_interval(float(i % 12) * 0.12 / sp)
			t.tween_property(n, "modulate:a", 1.0, 0.0)
			t.parallel().tween_property(n, "scale", n.scale * (float(i % 5) * 0.05 + 0.9), 0.25 / sp)
			t.tween_property(n, "position", n.position + Vector2(r.randf_range(-30.0, 30.0), -160.0),
				(float(i % 7) * 0.05 + 0.5) / sp)
			t.parallel().tween_property(n, "scale", n.scale * (float(i % 5) * 0.05 + 0.9), 0.75 / sp)
			t.tween_interval(0.5 / sp)
			t.tween_property(n, "modulate:a", 0.0, 0.25 / sp)
			t.tween_callback(n.queue_free))

	# 물고기 5종.
	for i in 5:
		var f := _spr(el, pfx + "fish%d" % (i + 1))
		if f == null:
			break
		f.position = at + Vector2(-dir * 300.0, rng.randf_range(-80.0, 40.0))
		f.z_index = 97
		f.scale *= (float(i % 6) * 0.1 + 0.75)
		host.add_child(f)
		var t6 := f.create_tween()
		t6.tween_interval(float(i) * 0.35 / sp)
		t6.tween_property(f, "position", f.position + Vector2(dir * 620.0, -40.0), 1.6 / sp)
		t6.tween_property(f, "modulate:a", 0.0, 0.25 / sp)
		t6.tween_callback(f.queue_free)


# ── wind (11.0초) — 회오리 두 겹이 720° 돌고 잔해가 빨려 든다 ────────────────
## 원작 `runWind`: 회오리 본체(0x18894) `EaseOut(ScaleBy(5.15, 1.15, 1.05), 0.25)`,
##   겹 두 장(0x18895·0x18896)이 각각 **RotateBy(5.25초, 720°)**.
##   0x18896 = ScaleTo(0.25,1.0) EaseIn(0.5) → FadeTo(0.75, 0)
##   0x18895 = Delay(0.25) → FadeTo(0.75, 200) → Delay(4.15) → FadeTo(0.1, 0)
##   잔해(나무·잎)는 MoveBy(1.0) + ScaleBy(0.9, 1.25) → MoveBy(0.25) → ScaleBy(0.25, 3.0, 0.5)
##   → FadeTo(0.25, 0) — **가늘고 길게 늘어나며 사라진다**(빨려 드는 표현).
const WIND_SPIN_SEC := 5.25
const WIND_SPIN_DEG := 720.0
const WIND_LEAVES := 12         # 원작 `rand()%8 + 12` 의 하한
const WIND_WOODS := 3

static func _run_wind(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "wind"
	var pfx := prefix(el)

	var body := _spr(el, pfx + "whirl1")
	if body != null:
		body.position = at
		body.z_index = 99
		host.add_child(body)
		_play_frames(body, el, pfx + "whirl%d", 1, 4, 0.035 / sp)
		var t := body.create_tween()
		t.tween_property(body, "scale", body.scale * Vector2(1.15, 1.05), 5.15 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(body, "scale", body.scale * Vector2(1.75, 1.5), 0.1 / sp)
		t.tween_property(body, "modulate:a", 0.0, 0.75 / sp)
		t.tween_callback(body.queue_free)

	for i in 2:
		var lay := _spr(el, pfx + "whirl4")
		if lay == null:
			break
		lay.position = at
		lay.z_index = 97 + i
		host.add_child(lay)
		var t2 := lay.create_tween()
		t2.tween_property(lay, "rotation_degrees", WIND_SPIN_DEG * (1.0 if i == 0 else -1.0),
			WIND_SPIN_SEC / sp)
		var t3 := lay.create_tween()
		if i == 0:
			t3.tween_property(lay, "scale", lay.scale, 0.25 / sp)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t3.tween_interval(WIND_SPIN_SEC / sp)
			t3.tween_property(lay, "modulate:a", 0.0, 0.75 / sp)
		else:
			t3.tween_interval(0.25 / sp)
			t3.tween_property(lay, "modulate:a", 200.0 / 255.0, 0.75 / sp)
			t3.tween_interval(4.15 / sp)
			t3.tween_property(lay, "modulate:a", 0.0, 0.1 / sp)
		t3.tween_callback(lay.queue_free)

	# 잔해 — 빨려 들며 늘어난다.
	var debris := func(key: String, n: int, z: int) -> void:
		_swarm(host, el, pfx + key, n, at, Vector2(260.0, 120.0), z, rng,
			func(nd: Node2D, i: int, r: RandomNumberGenerator) -> void:
				var t4: Tween = nd.create_tween()
				t4.tween_interval(0.15 / sp + float(i) * 0.05 / sp)
				t4.tween_property(nd, "position", at + Vector2(0.0, -40.0), 1.0 / sp)
				t4.parallel().tween_property(nd, "scale", nd.scale * 1.25, 0.9 / sp)
				t4.tween_property(nd, "position", at + Vector2(0.0, -120.0), 0.25 / sp)
				t4.parallel().tween_property(nd, "scale",
					nd.scale * Vector2(3.0, 0.5), 0.25 / sp)
				t4.tween_property(nd, "modulate:a", 0.0, 0.25 / sp)
				t4.tween_callback(nd.queue_free))
	debris.call("leaf", WIND_LEAVES, 96)
	debris.call("wood", WIND_WOODS, 95)

	# zmoon — 뒤늦게 밝아진다.
	for i in 2:
		var zm := _spr(el, pfx + ("zmoon" if i == 0 else "zmoon%d" % (i + 1)))
		if zm == null:
			continue
		zm.position = at
		zm.z_index = 87 + i
		zm.modulate.a = 0.0
		host.add_child(zm)
		var t5 := zm.create_tween()
		t5.tween_interval((0.15 + 0.75) / sp)
		t5.tween_property(zm, "modulate:a", 1.0, 0.5 / sp)
		t5.tween_interval(3.5 / sp)
		t5.tween_property(zm, "modulate:a", 0.0, 0.75 / sp)
		t5.tween_callback(zm.queue_free)


# ── dark (11.0초) — 손아귀가 잡고 폭발한다 ──────────────────────────────────
## 원작 `initDark`: `dark_punch`·`dark_ball` 이 화면 좌우 `(W×∓0.5, 200)` 에서 들어오고,
##   손 애니 4벌(`dark_hand1~4`, **전부 0.025초/프레임**), 폭발 두 벌
##   (`explosion1~7` 0.04초 · `explosion8~10` 0.025초).
const DARK_PUNCH_S := 1.75      # 원작 setScale(1.75)
const DARK_HAND_SEC := 0.025
const DARK_EXPL_SEC := 0.04
const DARK_EXPL2_SEC := 0.025

static func _run_dark(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "dark"
	var pfx := prefix(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	# 원작 `initDark` — **전부 레이어 중심 한 자리**에 겹쳐 둔다(좌우에서 날아오지 않는다).
	#   `dark_punch`      setScale(**1.75**) · 숨김 · z 2 (tag 0x1883b)
	#   `dark_ball`       setScale(0)        · z 1 (tag 0x1883a)
	#   `dark_explosion1` setScale(0) · z 1 / `dark_explosion8` setScale(0) · **rotation 90** · z 1
	#   `dark_hand14` ×2 — 한 장은 **setScaleX(−1)** 로 뒤집어 반대편 손이 된다(각기 다른 배치노드)
	var punch := _spr(el, pfx + "punch")
	if punch != null:
		punch.position = at
		punch.scale = Vector2.ONE * DARK_PUNCH_S
		punch.z_index = 97
		punch.visible = false
		host.add_child(punch)
		var pt: Tween = punch.create_tween()
		pt.tween_interval(0.4 / sp)
		pt.tween_callback(func() -> void: punch.visible = true)
		pt.tween_property(punch, "scale", Vector2.ONE * DARK_PUNCH_S * 1.2, 0.2 / sp)
		pt.tween_property(punch, "modulate:a", 0.0, 0.3 / sp)
		pt.tween_callback(punch.queue_free)
	var ball := _spr(el, pfx + "ball")
	if ball != null:
		ball.position = at
		ball.scale = Vector2.ZERO
		ball.z_index = 96
		host.add_child(ball)
		var bt: Tween = ball.create_tween()
		bt.tween_interval(0.7 / sp)
		bt.tween_property(ball, "scale", Vector2.ONE, 0.35 / sp)
		bt.tween_interval(0.5 / sp)
		bt.tween_property(ball, "modulate:a", 0.0, 0.2 / sp)
		bt.tween_callback(ball.queue_free)

	# 손 — 원작은 `dark_hand14` 를 **두 장** 두고 한 장을 뒤집는다. 프레임은 그 위에서 갈아 낀다.
	for i in 2:
		var hd := _spr(el, pfx + "hand1")
		if hd == null:
			break
		hd.position = at
		hd.z_index = 99
		if i == 1:
			hd.scale = Vector2(-hd.scale.x, hd.scale.y)
		host.add_child(hd)
		_play_frames(hd, el, pfx + "hand%d", 1, 20, DARK_HAND_SEC / sp)
		var ht: Tween = hd.create_tween()
		ht.tween_interval(20.0 * DARK_HAND_SEC / sp + 3.0 / sp)
		ht.tween_property(hd, "modulate:a", 0.0, 0.5 / sp)
		ht.tween_callback(hd.queue_free)

	# 폭발 — 두 벌을 시차로.
	for i in 2:
		var e := _spr(el, pfx + ("explosion1" if i == 0 else "explosion8"))
		if e == null:
			continue
		e.position = at
		e.z_index = 101 + i
		e.visible = false
		host.add_child(e)
		var d := (1.2 + 1.4 * float(i)) / sp
		var t2: Tween = e.create_tween()
		t2.tween_interval(d)
		t2.tween_callback(func() -> void:
			if not is_instance_valid(e):
				return
			e.visible = true
			if i == 0:
				_play_frames(e, el, pfx + "explosion%d", 1, 7, DARK_EXPL_SEC / sp, true)
			else:
				_play_frames(e, el, pfx + "explosion%d", 8, 10, DARK_EXPL2_SEC / sp, true))

	# 그림자 장막.
	var shade := _spr(el, pfx + "shade")
	if shade != null:
		shade.position = at
		shade.z_index = 84
		shade.modulate.a = 0.0
		host.add_child(shade)
		var t3 := shade.create_tween()
		t3.tween_property(shade, "modulate:a", 1.0, 0.5 / sp)
		t3.tween_interval(6.0 / sp)
		t3.tween_property(shade, "modulate:a", 0.0, 0.75 / sp)
		t3.tween_callback(shade.queue_free)


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
const LIGHT_SUN_DX := 60.0        # 원작 태양 뭉치 = 레이어 중심 + (60, 60)
const LIGHT_SUN_DY := 60.0
const LIGHT_FLASHWING_SX := 10.0  # 원작 setScaleX(10) — 가로로 길게 찢어지는 섬광
const LIGHT_STARS_IN := 30
const LIGHT_STARS_OUT := 720
const LIGHT_STARS := LIGHT_STARS_IN + LIGHT_STARS_OUT   # 30 + 720 = 750 (원작 0x2ee)

static func _run_light(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "light"
	var pfx := prefix(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	var field := Node2D.new()
	field.z_index = 86
	host.add_child(field)
	var ctr := _screen_center(host)
	var half := vis * 0.5
	for i in LIGHT_STARS:
		var st := _spr(el, pfx + "star")
		if st == null:
			break
		st.position = ctr + Vector2(rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y))
		st.scale *= rng.randf_range(0.4, 1.0)
		st.visible = false
		field.add_child(st)
		var spot := ctr + Vector2(rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y))       # 원작 `rand() % VisibleRect` 임의점
		var t: Tween = st.create_tween()
		if i < LIGHT_STARS_IN:
			t.tween_interval(0.75 / sp)
			t.tween_callback(func() -> void: st.visible = true)
			t.tween_property(st, "position", spot,
				(float(rng.randi() % 11) * 0.025 + 1.75) / sp).set_ease(Tween.EASE_IN)
		else:
			t.tween_interval(1.75 / sp)
			t.tween_callback(func() -> void: st.visible = true)
			t.tween_property(st, "position",
				(spot - ctr) * (float(rng.randi() % 9) * 0.25 + 1.0),
				(float(rng.randi() % 45) * 0.025 + 0.75) / sp)\
				.as_relative().set_ease(Tween.EASE_IN)
	var ft := field.create_tween()
	ft.tween_interval(7.5 / sp)
	ft.tween_property(field, "modulate:a", 0.0, 1.0 / sp)
	ft.tween_callback(field.queue_free)

	# 태양·행성·섬광 — 원작이 쓰는 단품들을 차례로 띄운다.
	# 원작 `initLight` — 태양 뭉치는 전부 **레이어 중심 + (60, 60)**(cocos) 한 자리에 겹친다.
	#   `light_sun`/`sunlight`/`sunwing` : setScale(1) · setOpacity(0) · z 0 (tag 0x18835/33/34)
	#   `light_flash`  : setScale(0) · **anchor(0.54, 0.5)** · pos 중심+(60,60) · z 1
	#   `light_flashwing`: flash 의 **자식**, setScaleX(10) · pos = flash 중앙
	#   `light_bomb`   : setScale(0) · pos 중심+(60,60) · z 0
	#   `light_sunwing` 은 **자기 복제본을 자식**으로 갖는다(scale 0 · opacity 0 · rotation 90).
	#   `light_earth`  : anchor 중앙 · pos (중심x + w*0.5, h*0.8) · scale 0.4 · 숨김
	var sun_at := at + Vector2(LIGHT_SUN_DX, -LIGHT_SUN_DY)
	var seq := [["sun", 0.5, 101], ["sunlight", 0.6, 100], ["sunwing", 0.7, 99],
		["saturn", 1.4, 98], ["earth", 1.8, 98], ["flash", 2.4, 103],
		["flashwing", 2.5, 102], ["bomb", 3.0, 104]]
	for e in seq:
		var n := _spr(el, pfx + String(e[0]))
		if n == null:
			continue
		n.position = sun_at
		if String(e[0]) == "flashwing":
			n.scale = Vector2(LIGHT_FLASHWING_SX, 1.0)   # 원작 setScaleX(10)
		n.z_index = int(e[2])
		n.modulate.a = 0.0
		host.add_child(n)
		var t: Tween = n.create_tween()
		t.tween_interval(float(e[1]) / sp)
		t.tween_property(n, "modulate:a", 1.0, 0.3 / sp)
		t.parallel().tween_property(n, "scale", n.scale * 1.15, 1.2 / sp)
		t.tween_interval(2.5 / sp)
		t.tween_property(n, "modulate:a", 0.0, 0.6 / sp)
		t.tween_callback(n.queue_free)


# ── holy (11.25초) — 창 세례 ─────────────────────────────────────────────────
## 원작 `initHoly`: `holy_spear` **31개 × 2벌**(앞 z=idx+1 / 뒤 z=375−idx)을 **3라운드**
## 반복한다 ⇒ 창 186개. 높이는 `(0, rand()%301)` 로 흩고 기준은 `(0, 62.5)`.
const HOLY_SPEARS := 31
const HOLY_ROUNDS := 3
const HOLY_BASE_DY := 62.5
const HOLY_SPEAR_GAP := 24.166666        # 원작 `initHoly`: x = i × 24.1667 (31개 = 화면 폭)

static func _run_holy(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "holy"
	var pfx := prefix(el)
	var base := at - Vector2(0.0, HOLY_BASE_DY)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	var well := _spr(el, pfx + "well")
	if well != null:
		well.position = base
		well.z_index = 88
		well.modulate.a = 0.0
		host.add_child(well)
		var wt := well.create_tween()
		wt.tween_property(well, "modulate:a", 1.0, 0.6 / sp)
		wt.tween_interval(7.5 / sp)
		wt.tween_property(well, "modulate:a", 0.0, 0.75 / sp)
		wt.tween_callback(well.queue_free)

	# 창(spear) — 2026-08-05 `initHoly` + `runHoly` 를 함께 복원해 **연출이 통째로 바뀌었다**.
	# 종전엔 "위에서 떨어진다"였는데 원작은 **가로 한 줄로 늘어서 초점으로 모여든다**:
	#   배치(`initHoly`) : x = i × 24.1667 (31개가 화면 폭을 채운다)
	#                      y = layer.y + 62.5 + sin(i × 6°) × 56.25
	#                      rotation = 초점 `(layer.x, layer.y − 125)` 을 향하도록 atan2(...) − 90
	#                      anchor (0.5, 0.1)
	#   안무(`runHoly`)  : Delay(base) → Delay(r × 0.2) → Delay(i × 0.0125 + 1.25) → Show
	#                      → FadeTo(0.25, 200)
	#                      → EaseIn(MoveBy(1.775 − 0.1r − 0.0125i, 자기 방향 × 200), 0.3)
	#                      → Spawn(ScaleBy(0.1, 1.2), MoveTo(0.1, 중심), FadeTo(0.1, 100))
	#                      → Spawn(MoveBy(0.75, 자기 방향 × −50), FadeTo(0.5, 0)) → remove
	#   라운드는 3(`if (2 < r) return`), 한 라운드에 두 벌(앞/뒤) × 31개.
	var focus := base + Vector2(0.0, 125.0)         # cocos −125 ⇒ Godot +125(아래)
	for r in HOLY_ROUNDS:
		for i in HOLY_SPEARS:
			for layer in 2:                     # 앞/뒤 두 벌(원작 tag 0x18835 / +0x1f)
				var s := _spr(el, pfx + "spear")
				if s == null:
					return
				var x := base.x + (float(i) - float(HOLY_SPEARS - 1) * 0.5) * HOLY_SPEAR_GAP
				var y := base.y - (HOLY_BASE_DY + sin(float(i) * PI / 30.0) * 56.25)
				s.position = Vector2(x, y)
				var v := (focus - s.position).normalized()
				s.rotation = atan2(v.x, -v.y)
				s.z_index = (95 + i) if layer == 0 else (84 - i / 8)
				s.visible = false
				s.modulate.a = 0.0
				host.add_child(s)
				var fly := maxf(0.1, 1.775 - 0.1 * float(r) - 0.0125 * float(i))
				var t: Tween = s.create_tween()
				t.tween_interval((float(r) * 0.2 + float(i) * 0.0125 + 1.25) / sp)
				t.tween_callback(func() -> void: s.visible = true)
				t.tween_property(s, "modulate:a", 200.0 / 255.0, 0.25 / sp)
				t.tween_property(s, "position", v * 200.0, fly / sp)\
					.as_relative().set_ease(Tween.EASE_IN)
				t.tween_property(s, "position", base, 0.1 / sp)
				t.parallel().tween_property(s, "scale", s.scale * 1.2, 0.1 / sp)
				t.parallel().tween_property(s, "modulate:a", 100.0 / 255.0, 0.1 / sp)
				t.tween_property(s, "position", v * -50.0, 0.75 / sp).as_relative()
				t.parallel().tween_property(s, "modulate:a", 0.0, 0.5 / sp)
				t.tween_callback(s.queue_free)


# ── chaos (10.65초) — 운석과 먼지 ────────────────────────────────────────────
## 원작 `initChaos`: `chaos_meteo1/2` + `chaos_dust1~3`(애니 0.05초/프레임) +
##   `scene/colosseum/dust`·`dust_cover` 를 **18개**(0x12) · 12개(0xc) 루프로 깐다.
##   운석 앵커가 `(0.5, 0.0493)` = 꼬리 끝 기준이다.
const CHAOS_DUST_SEC := 0.05
const CHAOS_COVERS := 18
const CHAOS_METEOS := 12
const CHAOS_METEO_ANCHOR_Y := 0.0493

static func _run_chaos(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "chaos"
	var pfx := prefix(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	# 운석 — 위에서 비스듬히 떨어진다.
	for i in CHAOS_METEOS:
		var m := _spr(el, pfx + ("meteo1" if i % 2 == 0 else "meteo2"))
		if m == null:
			break
		var tx := at.x + rng.randf_range(-vis.x * 0.4, vis.x * 0.4)
		m.position = Vector2(tx - dir * 260.0, at.y - 420.0)
		m.z_index = 100
		m.rotation = atan2(420.0, dir * 260.0) - PI * 0.5
		host.add_child(m)
		var t: Tween = m.create_tween()
		t.tween_interval(float(i) * 0.28 / sp)
		t.tween_property(m, "position", Vector2(tx, at.y), 0.45 / sp)
		t.tween_property(m, "modulate:a", 0.0, 0.15 / sp)
		t.tween_callback(m.queue_free)

	# 먼지 기둥.
	var du := _spr(el, pfx + "dust1")
	if du != null:
		du.position = at
		du.z_index = 92
		host.add_child(du)
		_play_frames(du, el, pfx + "dust%d", 1, 3, CHAOS_DUST_SEC / sp)
		var t2 := du.create_tween()
		t2.tween_interval(6.0 / sp)
		t2.tween_property(du, "modulate:a", 0.0, 0.75 / sp)
		t2.tween_callback(du.queue_free)

	# 흙먼지 장막 — 원작이 `scene/colosseum` 아틀라스에서 가져온다(우리도 보유).
	for i in CHAOS_COVERS:
		var c := AtlasUI.spr_cocos("colosseum_ui",
			"scene_colosseum_dust_cover" if i % 2 == 0 else "scene_colosseum_dust")
		if c == null:
			break
		c.position = at + Vector2(rng.randf_range(-vis.x * 0.45, vis.x * 0.45),
			rng.randf_range(-40.0, 40.0))
		c.z_index = 90
		c.modulate.a = 0.0
		host.add_child(c)
		var t3 := c.create_tween()
		t3.tween_interval(float(i) * 0.08 / sp)
		t3.tween_property(c, "modulate:a", 1.0, 0.25 / sp)
		t3.tween_property(c, "position", c.position + Vector2(dir * 90.0, -50.0), 2.0 / sp)
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
	return AtlasUI.spr_cocos(DIR_PREFIX + element, key, 1.0, anchor)


static func _spr(element: String, key: String) -> Node2D:
	used_keys[element + "/" + key] = true
	return AtlasUI.spr_cocos(DIR_PREFIX + element, key)


## `_spr` 홀더의 프레임을 갈아 끼운다 — **트림 오프셋도 함께 다시 잡는다**.
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
	s.texture = t
	# `spr_cocos` 의 앵커 (0.5,0.5) 기준 식과 같다 — 앵커 항이 0 이라 오프셋만 남는다.
	s.position = Vector2(float(off[0]) * S, -float(off[1]) * S)
	return true
