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
##   ✅ fire 20단 폭발 캐스케이드                                ← `initFire` + `runFire`
##   ⚪ 나머지 8속성의 `run<El>` 본체 — 골격(최장 프레임 계열)으로 임시 재생 중
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
const FIRE_STONE_MIN := 14     # 지점당 돌 `idx%6 + 14` 개
## 화면 백색 암전 — `runFire`: Delay(base+4.25) → FadeTo(1.0,255) → Delay(1.0) → FadeTo(0.5,0)
const FIRE_FLASH_AT := 4.25
const FIRE_FLASH_IN := 1.0
const FIRE_FLASH_HOLD := 1.0
const FIRE_FLASH_OUT := 0.5

## 아직 `run<El>` 을 이식하지 않은 속성의 임시 골격 — 최장 프레임 계열 1개.
const FALLBACK_FRAME_SEC := 0.08


# ── 진입점 ──────────────────────────────────────────────────────────────────
## 각성기 재생. host 아래에 스프라이트를 붙인다(좌표는 host 로컬).
##   ctx = {element, at(몸통 중앙), scale(S), dir(+1/-1), speed, alive(Callable), mat}
## 반환 = 총 길이(초). 원작 `getDuration()` 콜로세움 표.
static func play(host: CanvasItem, ctx: Dictionary) -> float:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return 0.0
	var el := String(ctx.get("element", ""))
	var man := manifest(el)
	if man.is_empty():
		return 0.0
	var at: Vector2 = ctx.get("at", Vector2.ZERO)
	var s := float(ctx.get("scale", 1.0))
	var dir := float(ctx.get("dir", 1.0))
	var sp := maxf(0.05, float(ctx.get("speed", 1.0)))
	var alive: Callable = ctx.get("alive", Callable())
	var mat: CanvasItemMaterial = ctx.get("mat", null)
	if mat == null:
		mat = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

	_build_ring(host, el, at, s, sp, mat)
	match el:
		"fire":
			_run_fire(host, at, s, dir, sp, mat, alive)
		_:
			_run_fallback(host, el, at, sp, mat, alive)
	return float(DURATION.get(el, 9.0)) / sp


## 피해 수치가 떠야 하는 시각(초). 호출측이 각성기 시작 시점에서 재면 된다.
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
		# 원작 `dir * (W*wf + dx)` — cocos y-up 이라 dy 부호를 뒤집어 Godot 으로 옮긴다.
		var dx := dir * (vis.x * float(p[0]) + float(p[1]))
		var pos := at + Vector2(dx, -float(p[2]))
		var zbase := int(FIRE_Z[i]) * 5
		var delay := float(FIRE_DELAYS[i]) / sp
		var n_stone := (i % 6) + FIRE_STONE_MIN
		_fire_burst(host, pfx, pos, zbase, delay, n_stone, s, sp, mat, alive, rng)

	# 화면 백색 암전
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.size = vis
	flash.z_index = 120
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(flash)
	var ft := flash.create_tween()
	ft.tween_interval(FIRE_FLASH_AT / sp)
	ft.tween_property(flash, "color:a", 1.0, FIRE_FLASH_IN / sp)
	ft.tween_interval(FIRE_FLASH_HOLD / sp)
	ft.tween_property(flash, "color:a", 0.0, FIRE_FLASH_OUT / sp)
	ft.tween_callback(flash.queue_free)


## 폭발 지점 하나 — 지진(z+2) · 폭발(z+1) · 화염기둥(z+0) · 돌 여러 개.
static func _fire_burst(host: CanvasItem, pfx: String, pos: Vector2, zbase: int,
		delay: float, n_stone: int, s: float, sp: float, mat: CanvasItemMaterial,
		alive: Callable, rng: RandomNumberGenerator) -> void:
	var quake := _spr("fire", pfx + "earthquake")
	var pillar := _spr("fire", pfx + "fillar1")
	var expl := _spr("fire", pfx + "explosion1")
	for pair in [[quake, zbase + 2], [pillar, zbase], [expl, zbase + 1]]:
		var n: Node2D = pair[0]
		if n == null:
			continue
		n.position = pos
		n.z_index = int(pair[1])
		n.visible = false
		host.add_child(n)
	# 돌 — 원작이 `rand()%3 * 100` 으로 x 를 흩는다(§5-fire).
	var stones: Array = []
	for k in n_stone:
		var st := _spr("fire", pfx + "stone")
		if st == null:
			break
		st.position = pos + Vector2(float(rng.randi() % 3) * 100.0 - 100.0, 0.0)
		st.z_index = zbase + 3
		st.visible = false
		host.add_child(st)
		stones.append(st)

	var go := func() -> void:
		if alive.is_valid() and not bool(alive.call()):
			return
		if is_instance_valid(quake):
			quake.visible = true
			var qt := quake.create_tween()
			qt.tween_property(quake, "modulate:a", 0.0, 0.6 / sp)
			qt.tween_callback(quake.queue_free)
		if is_instance_valid(pillar):
			pillar.visible = true
			_play_frames(pillar, "fire", pfx + "fillar%d", 3, 7, FIRE_PILLAR_SEC / sp, true)
		if is_instance_valid(expl):
			expl.visible = true
			_play_frames(expl, "fire", pfx + "explosion%d", 2, 6, FIRE_EXPL_SEC / sp, true)
		for st in stones:
			if not is_instance_valid(st):
				continue
			st.visible = true
			# ASSUMPTION: 돌의 비행 궤적은 원작 `runFire` 의 조립을 자동 복원하지 못해
			#   위로 튀었다 떨어지는 포물선으로 둔다(높이·시간은 우리 값).
			var up := 60.0 + float(rng.randi() % 90)
			var side := (float(rng.randi() % 120) - 60.0)
			var t2: Tween = st.create_tween()
			t2.tween_property(st, "position", st.position + Vector2(side, -up), 0.28 / sp)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t2.tween_property(st, "position", st.position + Vector2(side * 1.6, 40.0), 0.42 / sp)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t2.parallel().tween_property(st, "modulate:a", 0.0, 0.42 / sp)
			t2.tween_callback(st.queue_free)

	var host_tree := host.get_tree()
	if host_tree == null:
		return
	var timer := host_tree.create_timer(delay)
	timer.timeout.connect(go)


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
static func _spr(element: String, key: String) -> Node2D:
	return AtlasUI.spr_cocos(DIR_PREFIX + element, key)


## `_spr` 홀더의 프레임을 갈아 끼운다 — **트림 오프셋도 함께 다시 잡는다**.
static func _set_frame(holder: Node2D, element: String, key: String) -> bool:
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return false
	var dir := DIR_PREFIX + element
	var t := AtlasUI.tex(dir, key)
	if t == null:
		return false
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
