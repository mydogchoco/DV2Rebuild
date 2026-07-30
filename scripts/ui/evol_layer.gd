class_name EvolLayer
extends RefCounted
## 원작 `EvolLayer` 이식 — **각성(원작 메뉴명 "진화") 결과 연출**.
##
## ── 정체 확인(중요) ────────────────────────────────────────────────────────────
## 이 클래스는 성장단계(해치→성장기→완전체) 연출이 **아니다.** 확인한 근거:
##   · `EvolLayer::create` 호출자는 `DragonAwaken.c:2859` **하나뿐**이다
##     (`grep -rn "EvolLayer::create" docs/ref/orig_code/decomp/*.c`).
##   · `EvolLayer::setEvolDragon`(EvolLayer.c:2857-2858)이 `Dragon::setAwaken(true)` +
##     `Dragon::setAwakenSkill(...)` 을 호출한다 — 각성 플래그를 세우는 그 화면이다.
##   · 성장단계 변화에는 원작에 연출이 없다. `Dragon::getImagePathSpineJson`(Dragon.c:9285/9298)이
##     레벨(<10 / <25)로 스파인 경로만 갈아끼운다.
## ⇒ 예전 `cave.gd _evolution_ceremony` 가 이 스파인들을 레벨업 성장단계에 쓰던 것은 오귀속이었다.
##
## ── 진입 데이터(원작) ──────────────────────────────────────────────────────────
##   `EvolLayer::init(Dragon*, CCPoint const& start, GenericDocument* json, function<void()> cb)`
##   · start = 호출 씬에서 드래곤이 서 있던 좌표(DragonAwaken.c:2856 이 드래곤 노드
##     boundingBox 중앙 +(20, y) 로 계산해 넘긴다) → 연출이 **그 자리에서 시작**한다.
##   · json = 서버가 내려준 각성 후 스탯(hp/att/def/potential …) — **유실**. 우리는 UserDB 를 읽는다.
##   · cb = 닫힘 콜백.
##   우리 대응: `EvolLayer.open(host, uid, start, on_close)`
##
## ── 연출 순서(원작 액션 시퀀스 그대로) ─────────────────────────────────────────
## actEvol(start) — EvolLayer.c:218
##   1. 드래곤 스파인 @ start, anim "wait"(loop), setScale(0.9), anchor(0.5,0)=발밑, z=1000
##   2. `evolution_effect.spine_json`(awake_spine) @ 드래곤 bbox 중앙, anim "animation" 1회,
##      **timeScale 2.0**, setScale(1.0), anchor(0.5,0.5), z=99999
##   3. 그 이펙트에 Sequence: Delay(0.1) → [A] → Delay(dur*0.5) → [B] → [C] → Delay(0.3) → [D] → RemoveSelf
## actevolWing — EvolLayer.c:578
##   날개 @ (w*0.5, -160)=화면 아래, anim "evolution"(loop), setScale(0.5), anchor(0.5,0.5)
##   Sequence: Spawn(MoveBy(0.5,(0,h/3+200)), ScaleTo(0.5,0.45))
##           → ScaleTo(0.5,0.4)
##           → Spawn(MoveBy(0.5,(0,h/3)), ScaleTo(0.5,0.85))
##           → ScaleTo(0.25,0.7) → Delay(0.25)
##           → Spawn(ScaleTo(0.5,0.27), JumpTo(0.5,(각성체X, h-90), 100, 1))
##           → **actEvolEffect** → Spawn(ScaleTo(1/6,0.25), MoveBy(1/6,(0,-10)))
##           → Spawn(ScaleTo(1/6,0.27), MoveBy(1/6,(0,+10)))
## actEvolEffect — EvolLayer.c:402
##   `evolution_effect2.spine_json`(effectevol_spine) anim "evolution_effect" 1회,
##   setScale(0.5), anchor(0.5,0.0)
## setEvolDragon — EvolLayer.c:2818
##   각성체 스파인 @ (w*0.23, h*0.5), anim "love"(loop), setScale(1.1), tag 0x3f1, z=2
##   + `common/check_btn.png` @ (w*0.9, h*0.95), scale 1.5, opacity 0 → FadeTo(0.5, 255)
##
## ⚠️ [D] 가 actevolWing 이라는 것은 추측이 아니라 **코드가 강제하는 순서**다 —
##    actevolWing 첫 줄이 `getChildByTag(container, 0x3f1)` 로 각성체 위치를 읽는데(EvolLayer.c:640),
##    그 태그를 붙이는 곳은 setEvolDragon 뿐이다. 즉 setEvolDragon 이 먼저다.
##    A/B/C 각각이 어느 메서드인지는 std::function 람다라 디컴프로 확정되지 않는다
##    (`PTR_FUN_02898ac8/b48/bc8`) → 아래 `# ASSUMPTION:` 참조.
##
## ── 판본 불일치(CLAUDE.md §10) ─────────────────────────────────────────────────
## `drawBase`(EvolLayer.c:831)의 결과 패널은 `new9patch/po_box_1` · `newCommon/grade` ·
## `newCommon/potential` 을 쓰는데 셋 다 추출 에셋에 없다(`asset_index.py --grep` 각 0건).
## 보유 프레임(`9patch/train_box4` · `common/bar_bg2`+`bar_exp`+`bar_cover` ·
## `scene/adventure/icon_exp` · `common/backlight3` · `common/shadow`)으로 재구성한다.

## 각성 조건(우리 규칙). 원작 재료표 `AccountManager::getAwakenMtrData`(아이템 3종×수량)는
## 서버 유실이고 위키에도 효과("등급 +0.6", docs/ref/wiki/etc.pdf §1.3.3)만 있다 →
## Lv.45 + 각성의 마석 1개로 둔다(레벨 상한은 Growth.level_cap 45→50).
## 진입점은 우노 마모루딕 연구소 하나뿐이며 **우노 지역 구현 전까지 연결하지 않는다**
## (scripts/ui/mamorudiclab.gd `_open_evolution`). 동굴은 이 상수를 상태 표시에만 쓴다.
const AWAKEN_LEVEL := 45
const AWAKEN_JEWELS := ["evol_jewel_6", "evol_jewel_5", "evol_jewel_4", "evol_jewel_3"]

const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const FX_AWAKE := "res://scenes/fx/evolution_effect.tscn"    # actEvol 의 각성 버스트(awake_spine)
const FX_WING := "res://scenes/fx/evolution_wing.tscn"       # actevolWing
const FX_EFFECT2 := "res://scenes/fx/evolution_effect2.tscn"  # actEvolEffect

## 원작 좌표·크기 리터럴은 이미 포인트 단위다(§9-2) → ASSET_SCALE 을 다시 곱하지 않는다.
## 반대로 `setScale(x)` 는 프레임 픽셀에 걸리는 배율이라 §9-3 대로 ASSET_SCALE 을 곱한다.
## z순서 — 원작 cocos zOrder(1000 / 99999 / 999999)는 Godot z_index 한계(±4096)를 넘는다.
## **상대 순서만 보존**해 옮긴다: 패널 < 각성체 < 각성전 드래곤 < 마무리이펙트 < 버스트 < 날개.
const Z_BASE := 1        # drawBase 패널
const Z_EVOL := 2        # setEvolDragon 각성체 (원작 z=2 그대로)
const Z_PRE := 1000      # actEvol 각성 전 드래곤 (원작 z=1000 그대로)
const Z_EFFECT2 := 3000  # actEvolEffect (원작 99999)
const Z_BURST := 4000    # actEvol 각성 버스트 (원작 99999)
const Z_WING := 4090     # actevolWing (원작 999999)

const WING_SCALE := 0.5      # actevolWing setScale(0.5)
const EFFECT2_SCALE := 0.5   # actEvolEffect setScale(0.5)
const AWAKE_SCALE := 1.0     # actEvol 버스트 setScale(1.0)
const AWAKE_TIMESCALE := 2.0 # actEvol 버스트 (this_01+0x150 = 2.0f)
const DRAGON_START_SCALE := 0.9   # actEvol 드래곤 setScale(0.9)
const EVOL_DRAGON_SCALE := 1.1    # setEvolDragon setScale(1.1)

static func open(host: Node, uid: int, start: Vector2, on_close := Callable()) -> void:
	var d: Dictionary = UserDB.get_dragon(uid)
	if d.is_empty() or not is_instance_valid(host):
		if on_close.is_valid(): on_close.call()
		return
	var ctx := {
		"host": host, "uid": uid, "on_close": on_close,
		"vis": host.get_viewport_rect().size,
	}
	_build(ctx, start)

## 원작 init: 투명 CCLayerColor(this) + 검은 CCLayerColor(this+0x2a0) + 컨테이너(this+0x210) @ (0,-50).
static func _build(ctx: Dictionary, start: Vector2) -> void:
	var host: Node = ctx["host"]
	var vis: Vector2 = ctx["vis"]
	var layer := CanvasLayer.new()
	layer.layer = 95                     # 레벨업 화면(30/31)·팝업(72)보다 위
	host.add_child(layer)
	ctx["layer"] = layer
	# 검은 배경. 원작은 `CCLayerColor::create({0,0,0,255})` 뒤 vtable+1000 에 100 을 넘긴다.
	# ASSUMPTION: 그 슬롯을 setOpacity 로 본다(100/255 ≈ 0.39). 값이 틀려도 딤 농도만 달라진다.
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 100.0 / 255.0)
	# 크기는 뷰포트(디자인 1230×692)에 직접 맞춘다 — CanvasLayer 안에서도 앵커 프리셋이 동작하지만,
	# 이 레이어는 좌표 계산(`_cy`)에 같은 vis 를 쓰므로 한 곳에서 온 값으로 맞춰 둔다.
	back.position = Vector2.ZERO
	back.size = vis
	back.mouse_filter = Control.MOUSE_FILTER_STOP    # 뒤 입력 차단(원작 setTouchEnabled(true))
	layer.add_child(back)
	# 컨테이너 — 원작이 (0,-50) 으로 내려 잡는다(cocos y-up 이므로 Godot 에선 +50 = 아래로).
	var cont := Node2D.new()
	cont.position = Vector2(0, 50)
	layer.add_child(cont)
	ctx["cont"] = cont
	Bgm.sfx("effect_upgrade")            # 원작 playEffect(EvolLayer.c:117)
	_act_evol(ctx, start)

## cocos y-up 좌표 → Godot y-down (컨테이너 로컬).
static func _cy(ctx: Dictionary, y: float) -> float:
	return float(ctx["vis"].y) - y

static func _dragon_scene(did: int, stage: String) -> String:
	return DRAGON_SCENE % [did, stage]

## 스파인 씬 1개를 세운다. 못 찾으면 null(미빌드 종은 조용히 건너뛴다).
static func _spine(path: String, anim: String, loop: bool, scale: float, pos: Vector2,
		z: int, parent: Node) -> Node2D:
	if not ResourceLoader.exists(path):
		push_warning("[EvolLayer] 스파인 미빌드: %s" % path)
		return null
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = z
	holder.scale = Vector2(scale, scale)
	parent.add_child(holder)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation(anim):
		ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		ap.play(anim)
	holder.set_meta("ap", ap)
	return holder

static func _dur(holder: Node2D, anim: String, fallback := 1.0) -> float:
	if not is_instance_valid(holder): return fallback
	var ap = holder.get_meta("ap")
	if ap is AnimationPlayer and (ap as AnimationPlayer).has_animation(anim):
		return (ap as AnimationPlayer).get_animation(anim).length
	return fallback

## ── actEvol(EvolLayer.c:218) — 시작 지점의 드래곤 + 각성 버스트 ────────────────
static func _act_evol(ctx: Dictionary, start: Vector2) -> void:
	var cont: Node2D = ctx["cont"]
	var d: Dictionary = UserDB.get_dragon(int(ctx["uid"]))
	var did := int(d.get("id", 0))
	var stage := Growth.stage_for_level(int(d.get("level", 1)))
	var S := Design.ASSET_SCALE
	# 1) 각성 전 드래곤 — 호출 씬에서 서 있던 그 자리에서 "wait" 로 시작한다.
	var pre := _spine(_dragon_scene(did, stage), "wait", true, DRAGON_START_SCALE * S,
		start - cont.position, Z_PRE, cont)
	ctx["pre"] = pre
	# 2) 각성 버스트 — 드래곤 중앙. 원작은 timeScale 2.0 으로 **2배속** 재생한다.
	var burst := _spine(FX_AWAKE, "animation", false, AWAKE_SCALE * S,
		(start - cont.position) + Vector2(0, -60), Z_BURST, cont)
	if burst:
		var bap = burst.get_meta("ap")
		if bap is AnimationPlayer: (bap as AnimationPlayer).speed_scale = AWAKE_TIMESCALE
	var dur := _dur(burst, "animation", 1.2) / AWAKE_TIMESCALE
	# 3) 원작 Sequence: Delay(0.1) → [A] → Delay(dur*0.5) → [B] → [C] → Delay(0.3) → [D] → RemoveSelf
	#    ASSUMPTION: A=drawBase(결과 패널) · B=버스트 노드 자체 연출 · C=setEvolDragon · D=actevolWing.
	#    D가 C보다 뒤라는 것만은 확정이다(actevolWing 이 setEvolDragon 의 tag 0x3f1 위치를 읽는다).
	var host: Node = ctx["host"]
	var t := cont.create_tween()
	t.tween_interval(0.1)
	t.tween_callback(func(): _draw_base(ctx))                       # [A]
	t.tween_interval(maxf(0.1, dur * 0.5))
	t.tween_callback(func(): _set_evol_dragon(ctx))                 # [C]
	t.tween_interval(0.3)
	t.tween_callback(func():                                        # [D]
		if is_instance_valid(burst): burst.queue_free()
		if is_instance_valid(pre): pre.queue_free()
		_act_evol_wing(ctx))

## ── setEvolDragon(EvolLayer.c:2818) — 각성체로 교체 + 확인 버튼 ────────────────
static func _set_evol_dragon(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var vis: Vector2 = ctx["vis"]
	var uid := int(ctx["uid"])
	var d: Dictionary = UserDB.get_dragon(uid)
	var did := int(d.get("id", 0))
	var S := Design.ASSET_SCALE
	# 원작은 각성 전용 스파인(`dragon_<id>_e_spine`)을 쓴다(Dragon::getImagePathSpineJson 의 e 분기).
	# 원본에 135종 실재하나 아직 씬으로 빌드되지 않았다 → 있으면 그걸, 없으면 성체로 대체한다.
	var path := _dragon_scene(did, "e")
	if not ResourceLoader.exists(path):
		path = _dragon_scene(did, Growth.stage_for_level(int(d.get("level", 1))))
	# 원작 위치 (w*0.23, h*0.5) + **anchor(0.5,0.5)** = 스프라이트 **중심**이 그 점에 온다.
	# 우리 스파인 씬의 원점은 스켈레톤 루트(=발밑)라 그대로 두면 몸이 위로만 뻗어 화면을 넘는다
	# (실측: 각성체 날개가 상단 밖으로 잘렸다). 발밑을 아래로 내려 중심을 원작 지점에 맞춘다.
	# ASSUMPTION: 오프셋 0.14h — 동굴 받침대 기준(발밑 0.49h ⇒ 몸 중심 ≈ 0.36h)에서 역산한 값.
	var pos := Vector2(vis.x * 0.23, _cy(ctx, vis.y * 0.5) + vis.y * 0.14)
	var evol := _spine(path, "love", true, EVOL_DRAGON_SCALE * S, pos, Z_EVOL, cont)
	ctx["evol"] = evol
	ctx["evol_pos"] = pos
	# 원작 앵커 지점(= 스프라이트 중심). actEvolEffect 는 대상 bbox **중앙**에 서므로 이 값을 쓴다
	# (발밑 pos 를 쓰면 워드아트가 드래곤 발치에 깔린다 — 실측으로 확인).
	ctx["evol_center"] = Vector2(vis.x * 0.23, _cy(ctx, vis.y * 0.5))
	# 확인 버튼 — 원작 `common/check_btn.png` @ (w*0.9, h*0.95), scale 1.5, 투명 → 0.5초 페이드인.
	var btn := TextureButton.new()
	var bp := "res://assets/converted/common_ui/common_check_btn.tres"
	if ResourceLoader.exists(bp):
		btn.texture_normal = load(bp)
	btn.scale = Vector2(1.5 * S, 1.5 * S)
	btn.modulate.a = 0.0
	btn.pressed.connect(func(): _close(ctx))
	var bl: CanvasLayer = ctx["layer"]
	bl.add_child(btn)
	# anchor 중앙 기준 좌표라 버튼 크기의 절반을 뺀다(TextureButton 은 좌상단 기준).
	var bsz := (btn.texture_normal.get_size() if btn.texture_normal else Vector2(44, 44)) * btn.scale
	btn.position = Vector2(vis.x * 0.9, _cy(ctx, vis.y * 0.95)) - bsz * 0.5
	btn.create_tween().tween_property(btn, "modulate:a", 1.0, 0.5)
	ctx["btn"] = btn

## ── actevolWing(EvolLayer.c:578) — 화면 아래에서 솟아오르는 날개 ───────────────
static func _act_evol_wing(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var vis: Vector2 = ctx["vis"]
	var S := Design.ASSET_SCALE
	var h := vis.y
	# 원작 시작점 (w*0.5, -160) — cocos y=-160 은 화면 **아래**다.
	var wing := _spine(FX_WING, "evolution", true, WING_SCALE * S,
		Vector2(vis.x * 0.5, _cy(ctx, -160.0)), Z_WING, cont)
	if wing == null:
		return
	# 착지 지점 x = 각성체의 x(원작이 tag 0x3f1 의 position 을 읽는다), y = h-90.
	# 원작 착지 y = `컨테이너높이 - 90`(EvolLayer.c:702). cocos 는 y-up 이라 그 값은 화면 **위쪽**이다
	# → Godot 로는 y=90. (예전엔 `_cy(90)`=602 로 잘못 옮겨 날개가 화면 아래로 내려앉았다.)
	var land := Vector2(float((ctx.get("evol_center", Vector2(vis.x * 0.23, 0)) as Vector2).x),
		_cy(ctx, vis.y - 90.0))
	# MoveBy 는 상대이동이라 각 단계의 도착 y 를 미리 계산해 둔다(cocos +y = Godot -y).
	var y0 := wing.position.y                       # 시작 = 화면 아래
	var y1 := y0 - (h / 3.0 + 200.0)                # 1)
	var y3 := y1 - h / 3.0                          # 3)
	var t := wing.create_tween()
	# 1) Spawn(MoveBy(0.5,(0, h/3+200)), ScaleTo(0.5,0.45))
	t.tween_property(wing, "position:y", y1, 0.5)
	t.parallel().tween_property(wing, "scale", Vector2.ONE * (0.45 * S), 0.5)
	# 2) ScaleTo(0.5, 0.4)
	t.tween_property(wing, "scale", Vector2.ONE * (0.4 * S), 0.5)
	# 3) Spawn(MoveBy(0.5,(0, h/3)), ScaleTo(0.5,0.85))
	t.tween_property(wing, "position:y", y3, 0.5)
	t.parallel().tween_property(wing, "scale", Vector2.ONE * (0.85 * S), 0.5)
	# 4) ScaleTo(0.25, 0.7) → 5) Delay(0.25)
	t.tween_property(wing, "scale", Vector2.ONE * (0.7 * S), 0.25)
	t.tween_interval(0.25)
	# 6) Spawn(ScaleTo(0.5,0.27), JumpTo(0.5, land, 높이 100, 1회))
	#    JumpTo = 직선 보간 + sin 포물선 1회(원작 CCJumpTo 의 jumps=1 궤적).
	var jump_from := Vector2(wing.position.x, y3)
	t.tween_property(wing, "scale", Vector2.ONE * (0.27 * S), 0.5)
	t.parallel().tween_method(
		func(p: float):
			if not is_instance_valid(wing): return
			wing.position = jump_from.lerp(land, p) + Vector2(0.0, -100.0 * sin(PI * p)),
		0.0, 1.0, 0.5)
	# 7) actEvolEffect
	t.tween_callback(func(): _act_evol_effect(ctx))
	# 8) Spawn(ScaleTo(1/6,0.25), MoveBy(1/6,(0,-10)))  ← cocos -10 = Godot +10
	t.tween_property(wing, "scale", Vector2.ONE * (0.25 * S), 1.0 / 6.0)
	t.parallel().tween_property(wing, "position:y", land.y + 10.0, 1.0 / 6.0)
	# 9) Spawn(ScaleTo(1/6,0.27), MoveBy(1/6,(0,+10)))
	t.tween_property(wing, "scale", Vector2.ONE * (0.27 * S), 1.0 / 6.0)
	t.parallel().tween_property(wing, "position:y", land.y, 1.0 / 6.0)

## ── actEvolEffect(EvolLayer.c:402) — 각성체 위의 마무리 이펙트 ─────────────────
static func _act_evol_effect(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var S := Design.ASSET_SCALE
	var at: Vector2 = ctx.get("evol_center", Vector2(float(ctx["vis"].x) * 0.23, 0))
	var fx := _spine(FX_EFFECT2, "evolution_effect", false, EFFECT2_SCALE * S, at, Z_EFFECT2, cont)
	Bgm.sfx("effect_level_updown")   # 원작 EvolLayer.c:132
	if fx:
		var d := _dur(fx, "evolution_effect", 1.5)
		fx.create_tween().tween_interval(d).finished.connect(func():
			if is_instance_valid(fx): fx.queue_free())

## ── drawBase(EvolLayer.c:831) — 결과 패널 ─────────────────────────────────────
## 원작 구성 중 **보유한 것만** 그대로 쓴다(§10): backlight3(6초 확대/축소 RepeatForever) ·
## shadow · 이름 TTF 24 · EXP 3종 게이지 + icon_exp. 없는 것(po_box_1 / grade / potential)은
## 보유 9patch·라벨로 대체한다.
static func _draw_base(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var vis: Vector2 = ctx["vis"]
	var S := Design.ASSET_SCALE
	var d: Dictionary = UserDB.get_dragon(int(ctx["uid"]))
	var ddef: Dictionary = Data.get_dragon(int(d.get("id", 0)))
	var base := Node2D.new()
	base.z_index = Z_BASE
	cont.add_child(base)
	ctx["base"] = base
	var dx := vis.x * 0.23
	var dy := _cy(ctx, vis.y * 0.5)
	# backlight3 @ (0,40) + ScaleTo(6.0, s+0.2)/(6.0, s) 무한 반복 — 원작 그대로.
	var bl := _frame("common_ui", "common_backlight3", S)
	if bl:
		bl.position = Vector2(dx, dy - 40.0)
		base.add_child(bl)
		var s0 := bl.scale
		var bt := bl.create_tween().set_loops()
		bt.tween_property(bl, "scale", s0 + Vector2(0.2, 0.2), 6.0)
		bt.tween_property(bl, "scale", s0, 6.0)
	# shadow @ (0,30) — 발밑 그림자
	var sh := _frame("common_ui", "common_shadow", S)
	if sh:
		sh.position = Vector2(dx, dy + 30.0)
		base.add_child(sh)
	# 이름(원작 CCLabelTTF 24, anchor(0,1) @ (x+30, y-15))
	var nm := Label.new()
	var nick := String(d.get("nick", ""))
	nm.text = nick if nick != "" else String(ddef.get("name", "드래곤"))
	nm.add_theme_font_size_override("font_size", 24)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	nm.add_theme_constant_override("outline_size", 5)
	nm.position = Vector2(dx + 30.0, dy - 15.0)
	base.add_child(nm)
	# 등급 — 원작은 `newCommon/grade` + `font/font_rating.fnt`. 프레임 부재 → 라벨로.
	var gr := Label.new()
	gr.text = "등급  %.1f" % _grade(d, ddef)
	gr.add_theme_font_size_override("font_size", 22)
	gr.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12))
	gr.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	gr.add_theme_constant_override("outline_size", 5)
	gr.position = Vector2(vis.x * 0.55, _cy(ctx, vis.y * 0.72))
	base.add_child(gr)
	# EXP 게이지 3종(원작 bar_bg2 + bar_exp + bar_cover) + icon_exp.
	var bar_pos := Vector2(vis.x * 0.55, _cy(ctx, vis.y * 0.62))
	var bar_size := Vector2(300.0, 18.0)
	var need := LevelSystem.exp_to_next(Data.level_curve, int(d.get("level", 1)))
	var cur := int(d.get("exp", 0))
	var pct := clampf(float(cur) / maxf(1.0, float(need)), 0.0, 1.0)
	_gauge(base, bar_pos, bar_size, pct)
	var ic := _frame("adventure_ui", "scene_adventure_icon_exp", S * 0.8)
	if ic:
		ic.position = bar_pos + Vector2(-24, 9)
		base.add_child(ic)
	# 스탯 4행 — 원작 색(ccColor3B) 그대로: 0x00e4ff · 0x7dedfa · 0x5f5ff1 · 0xff9967.
	var sb: Dictionary = d.get("stat_bonus", {})
	var st := Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []), sb.get("base", {}))
	var rows := [
		["레벨", Color8(0x00, 0xe4, 0xff), str(int(d.get("level", 1)))],
		["생명력", Color8(0x7d, 0xed, 0xfa), str(int(st.get("hp", 0)))],
		["공격력", Color8(0x5f, 0x5f, 0xf1), str(int(st.get("att", 0)))],
		["방어력", Color8(0xff, 0x99, 0x67), str(int(st.get("def", 0)))],
	]
	for i in rows.size():
		var y := _cy(ctx, vis.y * 0.52) + i * 34.0
		var l := Label.new(); l.text = String(rows[i][0])
		l.add_theme_font_size_override("font_size", 21)
		l.add_theme_color_override("font_color", rows[i][1])
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(vis.x * 0.55, y); base.add_child(l)
		var v := Label.new(); v.text = String(rows[i][2])
		v.add_theme_font_size_override("font_size", 21)
		v.add_theme_color_override("font_color", Color.WHITE)
		v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		v.add_theme_constant_override("outline_size", 5)
		v.position = Vector2(vis.x * 0.55 + 120.0, y); base.add_child(v)
	# 각성 완료 문구(원작 문자열 테이블에 대응 항목을 못 찾아 우리 문구다).
	var tt := Label.new(); tt.text = "각성 완료 — 레벨 상한 %d" % Growth.level_cap(true)
	tt.add_theme_font_size_override("font_size", 18)
	tt.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	tt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tt.add_theme_constant_override("outline_size", 5)
	tt.position = Vector2(vis.x * 0.55, _cy(ctx, vis.y * 0.78)); base.add_child(tt)

static func _gauge(parent: Node2D, pos: Vector2, size: Vector2, pct: float) -> void:
	var bg := _stretch("common_ui", "common_bar_bg2", size)
	if bg: bg.position = pos; parent.add_child(bg)
	var clip := Control.new()
	clip.position = pos
	clip.size = Vector2(size.x * pct, size.y)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(clip)
	var fill := _stretch("common_ui", "common_bar_exp", size)
	if fill: clip.add_child(fill)
	var cov := _stretch("common_ui", "common_bar_cover", size)
	if cov: cov.position = pos; parent.add_child(cov)

static func _frame(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new()
	s.texture = load(p)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	s.material = m
	s.scale = Vector2(scale, scale)
	return s

static func _stretch(dir: String, key: String, size: Vector2) -> TextureRect:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p): return null
	var t := TextureRect.new()
	t.texture = load(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	t.material = m
	return t

## 등급 = cave.gd `_grade_of` 와 **같은 인자**로 부른다(레벨업 롤 gain_log 포함, §K-10).
static func _grade(d: Dictionary, ddef: Dictionary) -> float:
	return Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
		d.get("gain_log", []), Data.level_curve.get("grade", {}))

static func _close(ctx: Dictionary) -> void:
	var layer = ctx.get("layer")
	if is_instance_valid(layer): (layer as Node).queue_free()
	Bgm.sfx("effect_button")
	var cb = ctx.get("on_close")
	if cb is Callable and (cb as Callable).is_valid(): (cb as Callable).call()
