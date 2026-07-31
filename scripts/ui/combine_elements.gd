class_name CombineElements
extends CanvasLayer
## 속성 조합 팀버프 **연출** — 원작 `CombineElementsLayer` 1:1 이식 (render 층, CLAUDE.md §8).
##
## 포팅 카드 = `docs/ref/porting/CombineElementsLayer.md` (원작 타임라인·좌표·문자열 전수).
## 원작 소스 = `docs/ref/orig_code/decomp/CombineElementsLayer.c` (14메서드 전량 디컴파일, [skip>8000] 0건).
## 레퍼런스 = `docs/ref/TeamBuff/2.png ~ 25.png` (버프 15 `물빛 섬광` = aqualight, 25프레임 캡처).
##
## 진입 데이터(원작 `create(Dragon*,Dragon*,Dragon*)` = 파티 3마리):
##   `CombineElements.play(host, ["aqua","aqua","light"], buff_dict)`
## 호출자(원작 `AdventureScene::setCheckTeamBuff`, AdventureScene.c:55692):
##   전투 개시 이벤트에서 **탐험 1회당 한 번**, **3마리 전원 출전일 때만** 재생하고
##   `getDuration()`(=7.0초) 뒤에 `setEventFightStart` 를 부른다 → 우리는 `battle.gd` 가 7초 뒤 재생 시작.
##
## ⚠️ 로직·데이터는 건드리지 않는다 — 어떤 버프가 걸리는지는 `TeamBuff`(systems), 수치는
##    `TeamBuff.apply` 가 이미 계산한다. 이 파일은 그 결과를 **그리기만** 한다.

# 원작 getDuration(): 버프 있으면 7.0f(0x40e00000), 없으면 0.0f. (CombineElementsLayer.c:1601)
const DURATION := 7.0
# 연출 자체의 총 길이(배경 FadeIn 0.25 + Delay 7.25 + FadeOut 0.5). 전투는 7.0 에 시작하므로
# 마지막 페이드아웃 0.5초는 전투 화면 위에 겹쳐 흐른다 — 원작도 그렇다.
const TOTAL := 8.0
# 원작 ccTouchesBegan: 최초 1회만 scheduler timeScale = 15.0f(0x41700000). end() 가 1.0 으로 복구.
const SKIP_TIME_SCALE := 15.0

# 원작 궤도 — combine_outline 중심 기준 반지름 250pt, 90°/210°/330°.
# (CombineElementsLayer.c:1450 (0,250) · :1560 (-215,-125) · :1730 (215,-125) — cocos y-up)
const ORBIT: Array[Vector2] = [Vector2(0, -250), Vector2(-215, 125), Vector2(215, 125)]
# 원소가 튀어나오는 시작 지연 / 중앙으로 빨려들기 전 유지시간. 셋 다 t=3.05 에 수렴한다.
const POP_DELAY: Array[float] = [0.80, 1.05, 1.30]
const POP_HOLD: Array[float] = [1.70, 1.45, 1.20]
# 상시 회전 = RepeatForever(RotateBy(30s, 360°)) = 12°/s (원작이 outline 계열 전부에 건다).
const SPIN_DPS := 12.0

# 원작 프레임 크기(px). 궤도 중심이 화면중앙에서 (+28,+28)pt 밀리는 근거 — 포팅 카드 §4.
#   combine_outline 의 cocos contentSize 는 트림 전 원본 479(plist sourceSize),
#   combine_outline_white 는 트림 없는 437. (479-437)/2 × ASSET_SCALE = 28pt.
const CO_SRC := 479.0
const COW_SRC := 437.0

const BATTLE_DIR := "battle_ui"
const FONT_PATH := "res://assets/converted/font_ui/font_combine.fnt"

## 원작 `AdventureScene` 의 `this[0x39a]` — **탐험 1회당 한 번만** 재생.
## 우리 전투 씬은 조우마다 새로 생기므로 탐험 키(run_seed 등)로 판별한다.
static var _shown_run := ""
static var _font_cache: FontFile = null

var _pma: CanvasItemMaterial
var _res := ""
var _center := Vector2.ZERO
var _rate := 1.0                      # 터치 스킵 배속
var _tweens: Array[Tween] = []
var _spinners: Array[Node2D] = []     # 상시 회전 대상
var _buff: Dictionary = {}
var _table: Dictionary = {}           # data/team_buffs.json (stat_order · stat_labels)
var _skipped := false


# ── 진입 ────────────────────────────────────────────────────────────────────

## 이번 조우에서 연출을 틀 조건인지. 원작 setCheckTeamBuff 의 가드를 그대로 옮긴 것:
##   ① 이 탐험에서 아직 안 틀었다  ② 3마리 전원 출전  ③ 발동 버프가 있다
## + 우리 사정 하나: ④ 그 버프의 아이콘(`img`)이 추출 에셋에 있다.
##   25~30(그림자 계열)은 `battle/<res>/` 폴더가 통째로 없어 가운데 문양을 그릴 수 없다 →
##   흉내 내지 않고 연출을 생략한다(CLAUDE.md §3 "못 찾으면 임의 대체 금지").
static func can_play(run_key: String, party_size: int, buff: Dictionary) -> bool:
	if run_key != "" and _shown_run == run_key:
		return false
	if party_size != 3:
		return false
	return String(buff.get("img", "")) != ""

static func mark_played(run_key: String) -> void:
	_shown_run = run_key

## 연출 시작. elements = 파티 3마리의 속성 키.
## 원작 `combine()` 이 `Dragon::getRace()` 를 문자열로 바꾸는 switch 와 같은 축이다
## (0=earth 1=aqua 2=fire 3=wind 4=light 5=dark 6=holy 7=chaos 8=shadow).
## 재생할 수 없으면 null — 호출측은 곧바로 전투를 시작한다.
## `table` = `data/team_buffs.json` 파싱본(효과 줄의 `stat_order`/`stat_labels` 를 여기서 읽는다).
## 오토로드를 직접 참조하지 않는다 — 호출측이 넘긴다(§8.2 단방향 의존 + 헤드리스 검증 가능).
static func play(host: Node, elements: Array, buff: Dictionary, table: Dictionary) -> CombineElements:
	if elements.size() != 3 or String(buff.get("img", "")) == "":
		return null
	var l := CombineElements.new()
	l.layer = 100                       # 원작: runningScene->addChild(layer, 1000)
	l._buff = buff
	l._table = table
	l._res = String(buff["img"])
	host.add_child(l)
	l._build(elements)
	return l


# ── active() — 원작과 같은 단위로 나눠 둔다 ──────────────────────────────────

func _build(elements: Array) -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var vis := _vp_size()
	_center = vis * 0.5
	var S := Design.ASSET_SCALE

	# ── 배경 암막 (원작 CCLayerColor(0,0,0,0) 전체화면, z=-1) ──
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.size = vis
	bg.z_index = -10
	# 원작 onEnter 가 TouchController::disableAllTouchesWithoutCurrentLayer 로 아래 화면을
	# 통째로 막는다 → 전체화면 Control 하나로 같은 일을 한다(클릭은 스킵으로).
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_blocker_input)
	add_child(bg)
	var tb := _tween(bg)
	tb.tween_property(bg, "color:a", 1.0, 0.25)
	tb.tween_interval(TOTAL - 0.25 - 0.5)
	tb.tween_property(bg, "color:a", 0.0, 0.5)
	tb.tween_callback(queue_free)                # 원작 CallFunc(end)

	# 원작은 아틀라스별 CCSpriteBatchNode 2개(z=0 `<res>`, z=1 `battle`)에 담는다.
	# Godot 엔 배치노드가 없으므로 z_index 로만 같은 순서를 만든다.
	_build_center_mark()
	_build_center_ring()
	_build_orbit(elements)

	# 원작은 `combine_outline_thick` 시퀀스 안에서 `text()` 를 부른다(t=3.85).
	var tt := _tween(self)
	tt.tween_interval(3.85)
	tt.tween_callback(_text)

## 가운데 문양(combine_mark 계열) — 회전 없음.
func _build_center_mark() -> void:
	var S := Design.ASSET_SCALE

	# combine_mark: 3.85 즉시 등장 → 3.25 유지 → 0.9 로 조였다 2배로 터지며 소멸
	var cm := _spr_res("combine_mark", 0)
	if cm:
		cm.modulate.a = 0.0
		var t := _tween(cm)
		t.tween_interval(3.85)
		t.tween_callback(_set_alpha.bind(cm, 1.0))
		t.tween_interval(3.25)
		t.tween_property(cm, "scale", Vector2.ONE * 0.9 * S, 0.35)
		t.tween_property(cm, "scale", Vector2.ONE * 2.0 * S, 0.1)
		t.parallel().tween_property(cm, "modulate:a", 0.0, 0.1)
		t.tween_callback(cm.queue_free)

	# combine_mark_white #1 — 3.75 에 scale 0→1 팝인, 0.4 유지 후 페이드아웃(흰 섬광)
	var cmw1 := _spr_res("combine_mark_white", 2)
	if cmw1:
		cmw1.scale = Vector2.ZERO
		var t1 := _tween(cmw1)
		t1.tween_interval(3.75)
		t1.tween_property(cmw1, "scale", Vector2.ONE * S, 0.1)
		t1.tween_interval(0.4)
		t1.tween_property(cmw1, "modulate:a", 0.0, 0.5)
		t1.tween_callback(cmw1.queue_free)

	# combine_mark_white #2 — 같은 타이밍에 2.5배로 퍼지는 **충격파**(레퍼런스 16.png)
	var cmw2 := _spr_res("combine_mark_white", 2)
	if cmw2:
		cmw2.scale = Vector2.ZERO
		cmw2.visible = false
		var t2 := _tween(cmw2)
		t2.tween_interval(3.75)
		t2.tween_property(cmw2, "scale", Vector2.ONE * S, 0.1)
		t2.tween_callback(_set_visible.bind(cmw2, true))
		t2.tween_property(cmw2, "scale", Vector2.ONE * 2.5 * S, 0.25)
		t2.parallel().tween_property(cmw2, "modulate:a", 0.0, 0.25)
		t2.tween_callback(cmw2.queue_free)

	# combine_mark_thick — 3.85 즉시 등장, 3.25 뒤 소멸
	var cmt := _spr_res("combine_mark_thick", 0)
	if cmt:
		cmt.modulate.a = 0.0
		var t3 := _tween(cmt)
		t3.tween_interval(3.85)
		t3.tween_callback(_set_alpha.bind(cmt, 1.0))
		t3.tween_interval(3.25)
		t3.tween_callback(cmt.queue_free)

## 가운데 원환(combine_outline 계열) — 전부 상시 회전 + 일부는 급회전이 겹친다.
## 상시 회전은 스프라이트에, 급회전은 감싼 루트 노드에 걸어 서로 덮어쓰지 않게 한다.
func _build_center_ring() -> void:
	var S := Design.ASSET_SCALE

	# combine_outline(버프 색 원환) — 3.85 등장, 7.10 에 480° 급회전하며 터진다
	var co := _spr_res("combine_outline", 0, true)
	if co:
		var spr: Sprite2D = co.get_child(0)
		spr.modulate.a = 0.0
		_spinners.append(spr)
		# 원작 7.10: Spawn( EaseIn(RotateBy(0.45,480°),1.0),
		#                   Seq( ScaleTo(0.35,0.9), Spawn(ScaleTo(0.1,2.0), FadeTo(0.1,0)) ) )
		# 회전축(루트)과 크기/알파(스프라이트)는 서로 다른 노드라 트윈을 나눠 겹쳐 돌린다.
		var t := _tween(co)
		t.tween_interval(3.85)
		t.tween_callback(_set_alpha.bind(spr, 1.0))
		t.tween_interval(3.25)
		t.tween_method(_ease_rot.bind(co, deg_to_rad(480.0), 1.0), 0.0, 1.0, 0.45)
		t.tween_callback(co.queue_free)
		var t2 := _tween(co)
		t2.tween_interval(3.85 + 3.25)
		t2.tween_property(spr, "scale", Vector2.ONE * 0.9 * S, 0.35)
		t2.tween_property(spr, "scale", Vector2.ONE * 2.0 * S, 0.1)
		t2.parallel().tween_property(spr, "modulate:a", 0.0, 0.1)

	# combine_outline_white #1 — 2.25 부터 1.5초간 **1440° 가속 회전 + 페이드인 + 0.9 축소**
	# (레퍼런스 6~14.png 의 흰 룬 원환)
	var cow1 := _spr_bat("battle_combine_outline_white", 1, true)
	if cow1:
		var spr1: Sprite2D = cow1.get_child(0)
		spr1.modulate.a = 0.0
		_spinners.append(spr1)
		var t1 := _tween(cow1)
		t1.tween_interval(2.25)
		t1.tween_property(spr1, "modulate:a", 1.0, 1.5)
		t1.parallel().tween_method(_ease_rot.bind(cow1, deg_to_rad(1440.0), 3.25), 0.0, 1.0, 1.5)
		t1.parallel().tween_method(_ease_scale.bind(spr1, 1.0, 0.9, 3.25), 0.0, 1.0, 1.5)
		t1.tween_property(spr1, "scale", Vector2.ONE * S, 0.1)
		t1.tween_interval(0.4)
		t1.tween_property(spr1, "modulate:a", 0.0, 0.5)
		t1.tween_callback(cow1.queue_free)

	# combine_outline_white #2 — 같이 돌다가 3.85 에 2.5배 충격파로 퍼진다
	var cow2 := _spr_bat("battle_combine_outline_white", 1, true)
	if cow2:
		var spr2: Sprite2D = cow2.get_child(0)
		spr2.visible = false
		_spinners.append(spr2)
		var t2 := _tween(cow2)
		t2.tween_interval(2.25)
		t2.tween_method(_ease_rot.bind(cow2, deg_to_rad(1440.0), 3.25), 0.0, 1.0, 1.5)
		t2.tween_interval(0.1)
		t2.tween_callback(_set_visible.bind(spr2, true))
		t2.tween_property(spr2, "scale", Vector2.ONE * 2.5 * S, 0.25)
		t2.parallel().tween_property(spr2, "modulate:a", 0.0, 0.25)
		t2.tween_callback(cow2.queue_free)

	# combine_outline_thick — 상시 회전만. 3.85 등장, 3.25 뒤 소멸
	var cot := _spr_res("combine_outline_thick", 0)
	if cot:
		cot.modulate.a = 0.0
		_spinners.append(cot)
		var t3 := _tween(cot)
		t3.tween_interval(3.85)
		t3.tween_callback(_set_alpha.bind(cot, 1.0))
		t3.tween_interval(3.25)
		t3.tween_callback(cot.queue_free)

## 원소 메달 3종 + 그 궤도.
## 원작: CCLayer(크기 = combine_outline_white.contentSize)를 화면 중앙에 놓고
##       그 안의 (combine_outline.contentSize*0.5 + 오프셋) 자리에 원소를 배치한다.
##       두 크기가 달라 궤도 중심이 화면중앙에서 (+28,+28)pt 밀린다 — 포팅 카드 §4.
##       회전축은 레이어 원점(=화면 중앙)이라 3종은 **중심이 어긋난 원**을 돈다. 그대로 옮긴다.
func _build_orbit(elements: Array) -> void:
	var S := Design.ASSET_SCALE
	var orbit_off := Vector2(1, -1) * ((CO_SRC - COW_SRC) * 0.5 * S)

	var orbit := Node2D.new()
	orbit.position = _center
	orbit.z_index = 2
	add_child(orbit)
	# 2.25 부터 1.5초간 1440° 가속 회전(원작 Spawn 의 EaseIn(RotateBy(1.5,1440), 3.25))
	var t7 := _tween(orbit)
	t7.tween_interval(2.25)
	t7.tween_method(_ease_rot.bind(orbit, deg_to_rad(1440.0), 3.25), 0.0, 1.0, 1.5)

	for i in 3:
		var elem := String(elements[i])
		var mark := _spr_bat("battle_element_%s_mark" % elem, 0)
		if mark == null:
			continue
		mark.reparent(orbit, false)
		mark.position = orbit_off + ORBIT[i]
		mark.scale = Vector2.ZERO                      # 원작 setScale(0)

		# 자식 ① 원소 외곽 링(z=-1) — 상시 회전 + 1.75 에 켜졌다 3.05 에 꺼진다
		var outline := _spr_bat("battle_element_%s_outline" % elem, -1)
		if outline:
			_attach(outline, mark)
			outline.modulate.a = 0.0
			_spinners.append(outline)
			var t8 := _tween(outline)
			t8.tween_interval(1.75)
			t8.tween_property(outline, "modulate:a", 1.0, 1.0)
			t8.tween_interval(0.3)
			t8.tween_property(outline, "modulate:a", 0.0, 0.5)
			t8.tween_callback(outline.queue_free)

		# 자식 ② 흰 원소 문양(z=0) — 3.05 에 켜져, 중앙으로 빨려들 때 하얗게 보이게 한다
		var mwhite := _spr_bat("battle_element_%s_mark_white" % elem, 0)
		if mwhite:
			_attach(mwhite, mark)
			mwhite.modulate.a = 0.0
			var t9 := _tween(mwhite)
			t9.tween_interval(3.05)
			t9.tween_property(mwhite, "modulate:a", 1.0, 0.5)

			# 손자 ③ 흰 외곽 링(z=-1) — 상시 회전 + 3.05 페이드인
			var owhite := _spr_bat("battle_element_outline_white", -1)
			if owhite:
				_attach(owhite, mwhite)
				owhite.modulate.a = 0.0
				_spinners.append(owhite)
				var ta := _tween(owhite)
				ta.tween_interval(3.05)
				ta.tween_property(owhite, "modulate:a", 1.0, 0.5)

		# mark 본체: 지연 → 1.25 팝 → 1.0 → 유지 → 중앙으로 이동+페이드아웃 → 0 으로 수축
		var tm := _tween(mark)
		tm.tween_interval(POP_DELAY[i] + 0.35)
		tm.tween_property(mark, "scale", Vector2.ONE * 1.25 * S, 0.1)
		tm.tween_property(mark, "scale", Vector2.ONE * S, 0.1)
		tm.tween_interval(POP_HOLD[i])
		tm.tween_property(mark, "modulate:a", 0.0, 0.5)
		tm.parallel().tween_property(mark, "position", orbit_off, 0.5)
		tm.tween_property(mark, "scale", Vector2.ZERO, 0.1)
		tm.tween_callback(mark.queue_free)


# ── text() / setTextPercentage() ────────────────────────────────────────────

## 원작 `CombineElementsLayer::text()` (CombineElementsLayer.c:2045). t=3.85 에 호출된다.
func _text() -> void:
	var S := Design.ASSET_SCALE
	var vis := _vp_size()

	# 글자용 추가 암막(alpha 100/255) — 원작 CCLayerColor z=3
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = vis
	dim.z_index = 3
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var td := _tween(dim)
	td.tween_interval(0.5)
	td.tween_property(dim, "color:a", 100.0 / 255.0, 0.25)
	td.tween_interval(2.5)
	td.tween_property(dim, "color:a", 0.0, 0.5)
	td.tween_callback(dim.queue_free)

	# text_bend — 가로로 늘어난 흰 선이 좌우에서 조여들었다 다시 퍼진다(레퍼런스 18.png 의 가로선)
	var bend := _spr_bat("battle_text_bend", 3)
	if bend:
		bend.position = _center + Vector2(0, -150)
		bend.scale = Vector2(10.0, 0.0) * S
		var tb := _tween(bend)
		tb.tween_interval(0.5)
		tb.tween_property(bend, "scale", Vector2(10.0, 0.025) * S, 0.1)
		tb.tween_property(bend, "scale", Vector2(0.025, 0.125) * S, 0.25)
		tb.tween_callback(_set_visible.bind(bend, false))
		tb.tween_interval(2.2)
		tb.tween_callback(_show_at_scale.bind(bend, Vector2.ONE * 0.125 * S))
		tb.tween_property(bend, "scale", Vector2(10.0, 0.025) * S, 0.25)
		tb.tween_property(bend, "scale", Vector2(10.0, 0.0) * S, 0.1)
		tb.tween_callback(bend.queue_free)

	# 버프명 — 원작 CCLabelBMFont(buff.name, font/font_combine.fnt, -1)
	var nm := _bm_label(String(_buff.get("name", "")), 4)
	if nm:
		nm.position = _center + Vector2(0, -150)
		nm.scale = Vector2.ZERO
		var tn := _tween(nm)
		tn.tween_interval(0.85)
		tn.tween_property(nm, "scale", Vector2(2.0, 3.0) * S, 0.05)
		tn.tween_property(nm, "scale", Vector2(2.0, 2.0) * S, 0.05)
		tn.tween_interval(2.0)
		tn.tween_property(nm, "scale", Vector2(2.0, 3.0) * S, 0.05)
		tn.tween_property(nm, "scale", Vector2(1.0, 0.0) * S, 0.05)
		tn.tween_callback(nm.queue_free)

	_text_percentage()

## 원작 `CombineElementsLayer::setTextPercentage()` (CombineElementsLayer.c:1773).
## 효과 줄을 스탯 순서대로 계단식으로 슬라이드-인 시켰다가 오른쪽으로 날려 보낸다.
## 위치와 알파를 **별도 트윈**으로 돌린다 — 원작이 Spawn(FadeTo 0.2, Seq(MoveBy .1, MoveBy .1))
## 처럼 길이가 다른 두 축을 겹쳐 돌리기 때문(한 체인으로 엮으면 두 번째 이동이 밀린다).
func _text_percentage() -> void:
	var S := Design.ASSET_SCALE
	var lines := option_lines(_buff, _table)
	for i in lines.size():
		var lab := _bm_label(String(lines[i]), 4)
		if lab == null:
			continue
		# 원작 center + (-50, -25 - 50i) (cocos y-up) → 정착점은 +75-25 = +50 이동한 자리.
		var home := _center + Vector2(0, 25.0 + 50.0 * i)
		lab.position = home + Vector2(-50, 0)
		lab.scale = Vector2.ONE * S
		lab.modulate.a = 0.0
		var lead := i * 0.125
		var gap := i * 0.025

		var tp := _tween(lab)                       # 위치 체인
		tp.tween_interval(lead + 1.25)
		tp.tween_property(lab, "position", home + Vector2(25, 0), 0.1)   # MoveBy(+75)
		tp.tween_property(lab, "position", home, 0.1)                    # MoveBy(-25)
		tp.tween_interval(gap + 1.0)
		tp.tween_property(lab, "position", home + Vector2(-10, 0), 0.1)
		tp.tween_property(lab, "position", home + Vector2(65, 0), 0.1)   # MoveBy(+75)
		tp.tween_callback(lab.queue_free)

		var tf := _tween(lab)                       # 알파 체인
		tf.tween_interval(lead + 1.25)
		tf.tween_property(lab, "modulate:a", 1.0, 0.2)
		tf.tween_interval(gap + 1.0 + 0.1)
		tf.tween_property(lab, "modulate:a", 0.0, 0.1)

## 효과 줄 문자열 — 원작 `TeamBuff::getOptions()`(TeamBuff.c:918-1490) 재현.
## 11개 스탯을 `stat_order` 순으로 훑어 값이 0 이 아닌 것만 `"<이름> +%2d%%"` 로 만든다.
## 원작 포맷 리터럴은 `{#rrggbb:+%2d%%}` 색 태그지만 **생성 직후 setColor(WHITE)** 로 덮이므로
## 화면에는 흰 글씨만 나온다(레퍼런스 21.png) → 색은 옮기지 않는다.
## flat 스탯(pure/depure)만 원작이 `%` 없이 찍는다.
static func option_lines(buff: Dictionary, table: Dictionary) -> Array:
	var order: Array = table.get("stat_order", [])
	var labels: Dictionary = table.get("stat_labels", {})
	var eff: Dictionary = buff.get("effect", {})
	var out: Array = []
	for key in order:
		if not eff.has(key):
			continue
		var e = eff[key]
		var mode := "flat"
		var val := 0
		if typeof(e) == TYPE_DICTIONARY:
			mode = String((e as Dictionary).get("mode", "flat"))
			val = int(round(float((e as Dictionary).get("value", 0))))
		else:
			val = int(round(float(e)))
		if val == 0:
			continue
		var suffix := "" if mode == "flat" else "%"
		out.append("%s +%s%s" % [String(labels.get(key, key)), str(val).lpad(2, " "), suffix])
	return out


# ── 스킵 / 상시 회전 ────────────────────────────────────────────────────────

func _on_blocker_input(ev: InputEvent) -> void:
	# 원작 ccTouchesBegan: 최초 1회만 scheduler timeScale = 15.0 (end() 가 1.0 복구).
	if _skipped:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_skipped = true
		_rate = SKIP_TIME_SCALE
		for t in _tweens:
			if is_instance_valid(t):
				t.set_speed_scale(_rate)

func _process(delta: float) -> void:
	# RepeatForever(RotateBy(30s, 360°)) 상시 회전. 트윈으로 걸면 같은 노드의 급회전과
	# `rotation` 을 서로 덮어쓰므로, 느린 회전은 여기서 누적하고 급회전은 감싼 부모에 건다.
	var d := deg_to_rad(SPIN_DPS) * delta * _rate
	for n in _spinners:
		if is_instance_valid(n):
			n.rotation += d


# ── 헬퍼 ────────────────────────────────────────────────────────────────────

## 디자인 좌표계(692 고정) 화면 크기. CanvasLayer 는 부모 Viewport 가 없는 실행 경로
## (`--script` 툴 하니스)에서 `get_viewport()` 가 null 이라 SceneTree 루트로 폴백한다.
func _vp_size() -> Vector2:
	var v := get_viewport()
	if v == null:
		v = get_tree().root
	return v.get_visible_rect().size

func _tween(bound: Node) -> Tween:
	var t := bound.create_tween()
	t.set_speed_scale(_rate)
	_tweens.append(t)
	return t

func _set_alpha(node: CanvasItem, a: float) -> void:
	if is_instance_valid(node):
		node.modulate.a = a

func _set_visible(node: CanvasItem, v: bool) -> void:
	if is_instance_valid(node):
		node.visible = v

func _show_at_scale(node: Node2D, s: Vector2) -> void:
	if is_instance_valid(node):
		node.visible = true
		node.scale = s

## CCEaseIn(action, rate) = update(pow(t, rate)). Godot 의 TRANS_* 엔 임의 지수가 없어 직접 건다.
func _ease_rot(t: float, node: Node2D, total: float, rate: float) -> void:
	if is_instance_valid(node):
		node.rotation = total * pow(t, rate)

func _ease_scale(t: float, node: Node2D, from_s: float, to_s: float, rate: float) -> void:
	if is_instance_valid(node):
		var s: float = from_s + (to_s - from_s) * pow(t, rate)
		node.scale = Vector2.ONE * s * Design.ASSET_SCALE

## 자식으로 붙인다 — 부모가 이미 ASSET_SCALE 을 갖고 있으므로 로컬 배율은 1.0.
func _attach(child: Sprite2D, parent: Node2D) -> void:
	child.reparent(parent, false)
	child.position = Vector2.ZERO
	child.scale = Vector2.ONE

func _spr_res(frame: String, z: int, wrap := false) -> Node2D:
	return _spr("battle_combine_%s" % _res, "battle_%s_%s" % [_res, frame], z, wrap)

func _spr_bat(key: String, z: int, wrap := false) -> Node2D:
	return _spr(BATTLE_DIR, key, z, wrap)

## `wrap=true` 면 스프라이트를 Node2D 로 한 겹 감싸 반환한다 — 상시 회전(스프라이트)과
## 급회전(루트)이 같은 `rotation` 을 덮어쓰지 않게 하기 위한 것. 그 경우 스프라이트는 자식 0번.
func _spr(dir: String, key: String, z: int, wrap := false) -> Node2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		push_warning("[CombineElements] 프레임 없음: %s" % p)
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2.ONE * Design.ASSET_SCALE      # §9 — 480 아틀라스는 4/3 배로 그린다
	if not wrap:
		s.position = _center
		s.z_index = z
		add_child(s)
		return s
	var root := Node2D.new()
	root.position = _center
	root.z_index = z
	root.add_child(s)
	add_child(root)
	return root

## 원작 폰트 = `font/font_combine.fnt`(GameManager::getFontName_combine, GameManager.c:1990).
## 비트맵이라 `fixed_size_scale_mode = ENABLED` 를 켜야 font_size 가 먹는다(CLAUDE.md §10).
## 네이티브 크기(.fnt 헤더 size=26)로 찍고 확대는 노드 scale 로 — 원작 CCLabelBMFont 와 같은 경로.
static func _combine_font() -> FontFile:
	if _font_cache != null:
		return _font_cache
	if not ResourceLoader.exists(FONT_PATH):
		return null
	var f: FontFile = (load(FONT_PATH) as FontFile).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	# font_combine 은 원작이 실제로 쓴 한글 136자 부분집합이다 → 안전망만 둔다.
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_font_cache = f
	return f

## 중앙 정렬 BMFont 라벨을 Node2D 로 감싸 반환(스케일 기준점을 글자 중앙으로).
func _bm_label(text: String, z: int) -> Node2D:
	if text == "":
		return null
	var holder := Node2D.new()
	holder.z_index = z
	var l := Label.new()
	var f := _combine_font()
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", 26)          # .fnt 헤더의 size=26(네이티브)
	l.add_theme_color_override("font_color", Color.WHITE)    # 원작 setColor(ccColor3B::WHITE)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	add_child(holder)
	l.reset_size()
	l.position = -l.size * 0.5
	return holder
