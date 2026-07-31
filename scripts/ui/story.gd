extends Control
## 스토리(시나리오) 재생 화면 — 원작 `ScenarioLayer` + `ScenarioTextBox` 이식. render 층(§8).
##
## ── 원작에 뭐가 남아 있나 (2026-07-27 조사 결론) ───────────────────────────────
## **대사 텍스트는 전부 남아 있다. 흐름(연출) 데이터만 유실이다.**
##
## · `ScenarioManager::ResponseScriptJson`(ScenarioManager.c:1946)이 서버 응답의 `"script"`
##   배열을 읽어 `ScenarioScript` 객체 목록을 만든다. 그 객체의 필드는 libgame.so `.dynsym`
##   심볼로 확정된다(디컴파일 불필요):
##       scenarioNo · scenarioMNo · scriptNo · stateNo · npcNo · emotionNo · posNo ·
##       bgNo · bgmNo · cutNo · questItemNo · moveData · eventData · sceneAction
##   ⇒ **누가 · 어떤 표정 · 어디 서서 · 어떤 배경/BGM/컷인으로** 말하는지는 전부 서버 JSON = 유실.
##
## · 대사 본문은 `StringManager` 가 문자열 리소스에서 찾는다. 포맷 상수 3종(libgame.so):
##       `ScenarioTalk%d_%d` · `ScenarioTalk%d_%d_%d` · `ScenarioTalk%d_F_%d`
##   ⇒ **키가 순서를 인코딩**해서 대사 순서까지 복원된다.
##   `scripts/tools/build_scenario.py` 가 `data/scenario.json` 으로 뽑는다
##   (시나리오 142편 · 파트 187 · 대사 **5,029줄** · NPC 이름 62 · 삽화 54장).
##
## · 그래픽도 대부분 실재: `npc/` 아틀라스 42종(변환 완료) · `scenario/main_story/sn_*` 삽화 54장.
##   단 `scenario/main_story/bg/` 는 6장뿐이라(디컴프가 부르는 `bidel.jpg` 조차 없음)
##   장면 배경 세트는 우리 덤프에 일부만 있다(CLAUDE.md §10 판본 불일치 표 참조).
##
## 🔴 **2026-07-31 정정 — 위 "흐름 전량 유실"은 오진이었다.**
##   `ScenarioManager::makeScenarioLayer(sn)`(ScenarioManager.c @014ddce4)이 회차를 클래스로 가른다:
##       sn<10 `Scenario1` · <20 `2` · <30 `3` · <40 `4` · <50 `5` · <59 `6` · <79 `7` · 79~81 `8`
##       · 82~86 `Scenario_zimon` · 87~91 `_mamorudic` · 92~101 `_Kadeath` · **102+ `ScenarioCommon`**
##   이 중 `ScenarioCommon` **하나만** `ScenarioManager::getScriptArr`(=서버 script)를 읽는다.
##   나머지는 `initScenarioData` 가 `vector<std::function<void()>>` 로 연출을 **하드코딩**하고,
##   각 스텝이 `ScenarioSupport::setNpcTalk(NPC_NAME, Character_State, Character_Pos, TalkEmoticon, …)`
##   · `changeBackGround(BackGruundName)` · `drawIllust` 를 리터럴 인자로 부른다.
##   ⇒ **1~101화의 화자·표정·위치·배경·삽화·BGM 은 살아 있다.** 진짜 유실은 102화 이상뿐.
##   추출 = `scripts/tools/extract_scenario_flow.py` → `parse_scenario_flow.py` → `data/scenario_flow.json`.
##
## ⇒ 그래서 이 화면은 흐름이 있는 회차면 **원작 스텝을 그대로 재생**하고(`_play_flow`),
##   없는 회차(102+)만 종전처럼 텍스트 + 삽화로 넘긴다. 지어내지 않는다(HARD RULE 6).
##
## ── 원작 레이아웃 (ScenarioTextBox.c:258-352, ScenarioLayer.c) ─────────────────
##   · `9patch/dialogue_box.png` Scale9, 앵커(0.5, 0.0) 하단, contentSize(**visW-20, 150**)
##   · 본문 `CCLabelTTF("", "Thonburi", **24**)` 앵커(0.0,0.5) @ (20, h*0.5-10),
##     `setDimensions(w-75, 0)` 워드랩
##   · 화자 이름 슬롯 앵커(0.0,0.5) @ (20, **130**)
##   · 다음 화살표 `common/btn_arrow2.png` @ (w-35, h*0.5)
##   · 스킵 `common/btn_skip.png` (ScenarioLayer::setPassButton)
##   · 탭 = 타이핑 중이면 전체표시, 완료면 다음 줄 (`showString`/`showStringAll`)
##
## 진입 데이터: `Scenes.goto("story", {"no": <시나리오번호>, "part": <파트 인덱스, 기본 0>,
##                                     "back": "<끝나고 갈 씬>", "back_params": {...}})`

const BOX_H := 150.0
const ARROW := "res://assets/converted/common_ui/common_btn_arrow2.tres"
const SKIP := "res://assets/converted/common_ui/common_btn_skip.tres"
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const ART_DIR := "res://assets/converted/scenario"
## 제목 카드 폰트 — 원작 `GameManager::getFontName_subtitle`(§10 의 unicode=0 보정본).
const TITLE_FONT := "res://assets/converted/font_ui/font_subtitle.fnt"
## 타자기 속도(문자/초). 원작 `ScenarioTextBox::setTextSpeed` 값은 코스메틱 클라 설정이라
## 정확값 미확정 → ASSUMPTION 40cps (BattleTextBox 이식과 같은 값).
const CPS := 40.0

var _params: Dictionary = {}
var _lines: Array = []            # [{k, text}]
var _idx := 0
var _no := 0
var _part := 0
var _pma: CanvasItemMaterial

## 원작 연출 스텝(`data/scenario_flow.json`). 비어 있으면 102화 이상이거나 미추출 회차다.
var _flow: Array = []
var _flow_i := 0
var _bg_layer: TextureRect       # changeBackGround 가 갈아 끼우는 장면 배경
var _illust: TextureRect         # drawIllust 가 띄우는 삽화(원작은 배경 위 별도 레이어)

var _label: Label
var _name_label: Label
var _arrow: Sprite2D
var _typing := false
var _timer: Timer
var _npc_node: Node2D

## 연출용 — 텍스트박스(암전/섬광이 아래로 밀어낸다) · 화면 전체 색막 · 제목 카드 레이어.
var _box: NinePatchRect
var _box_home := Vector2.ZERO
var _fx_layer: CanvasLayer

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_no = int(_params.get("no", 1))
	_part = int(_params.get("part", 0))
	_idx = 0
	var sc: Dictionary = Data.scenario_def(str(_no))
	var parts: Array = sc.get("parts", [])
	_flow = Data.scenario_flow_of(_no)
	_flow_i = 0
	_lines = []
	if _flow.is_empty():
		if _part >= 0 and _part < parts.size():
			_lines = (parts[_part] as Dictionary).get("lines", [])
	else:
		# 원작 스텝은 회차의 파트를 순서대로 관통한다(검증: 82화 = 파트0 2줄 → setSubQuest → 파트1 30줄).
		for p in parts:
			_lines.append_array((p as Dictionary).get("lines", []))
	_build_backdrop(sc)
	_build_textbox()
	_build_skip()
	if not _flow.is_empty():
		_play_flow()
	elif _lines.is_empty():
		_show_line_text("(이 시나리오의 대사가 없습니다 — data/scenario.json 확인)")
	else:
		_show_line(0)

## 배경 = 이 시나리오의 삽화(sn_<no>_<m>_illust.jpg). 없으면 검은 막.
## 원작은 `bgNo` 로 `scenario/main_story/bg/*.jpg` 를 골랐지만 그 값도, 배경 세트 대부분도
## 우리 덤프에 없다(§10) → 삽화가 있으면 삽화, 없으면 단색.
func _build_backdrop(sc: Dictionary) -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.03, 0.06)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	# 흐름이 있는 회차는 배경·삽화를 **원작 스텝이** 통제한다(changeBackGround/drawIllust).
	# 여기서 삽화를 배경으로 깔면 그 위를 덮어 버린다.
	if not _flow.is_empty():
		return
	var illust: Array = sc.get("illust", [])
	if illust.is_empty():
		return
	var pick := String(illust[mini(_part, illust.size() - 1)])
	var p := "%s/%s" % [ART_DIR, pick]
	if not ResourceLoader.exists(p):
		return
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

func _build_textbox() -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 8; add_child(lay)
	var box := NinePatchRect.new()
	box.texture = load(DIALOG_BOX)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 20.0, BOX_H)          # 원작 contentSize(visW-20, 150)
	box.position = Vector2(10.0, vis.y - BOX_H)      # 앵커(0.5,0.0) 하단
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(box)
	_box = box
	_box_home = box.position
	# 화자 이름(원작 @ (20, 130) — Cocos y-up 이라 박스 위쪽). 유실이라 대개 빈 칸이다.
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_name_label.position = Vector2(20.0, 8.0)
	_name_label.size = Vector2(box.size.x - 90.0, 28.0)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)
	# 본문 — 원작 Thonburi 24, 앵커(0.0,0.5) @ (20, h*0.5-10), dimensions(w-75)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(20.0, 38.0)
	_label.size = Vector2(box.size.x - 75.0, BOX_H - 46.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)
	# 다음 화살표(원작 common/btn_arrow2 @ (w-35, h*0.5))
	if ResourceLoader.exists(ARROW):
		_arrow = Sprite2D.new()
		_arrow.texture = load(ARROW)
		_arrow.material = _pma
		_arrow.position = Vector2(box.size.x - 35.0, BOX_H * 0.5)
		_arrow.visible = false
		box.add_child(_arrow)
	# 탭 진행(원작 ScenarioTextBox::ccTouchBegan)
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_advance())
	lay.add_child(catcher)
	lay.move_child(catcher, 0)

## 스킵(원작 ScenarioLayer::setPassButton, `common/btn_skip.png` 117x39).
## 라벨 문구는 원작 문자열 `<ScenarioPass>건너뛰기</>` — 프레임 자체엔 글자가 없다.
func _build_skip() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var lay := CanvasLayer.new(); lay.layer = 9; add_child(lay)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(117.0 * S, 39.0 * S)
	b.position = Vector2(vis.x - b.size.x - 18.0, 16.0)
	if ResourceLoader.exists(SKIP):
		var s := Sprite2D.new()
		s.texture = load(SKIP)
		s.material = _pma
		s.scale = Vector2(S, S)
		s.position = b.size * 0.5
		b.add_child(s)
	var l := Label.new()
	l.text = "건너뛰기"
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88))
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = b.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(_confirm_skip)
	lay.add_child(b)

## 건너뛰기 확인 — 원작 문자열 `<ScenarioSkipTitle>`("시나리오 Skip") ·
## `<ScenarioSkip>`("해당 시나리오를 패스 하시겠습니끼?" — 원작 오타 그대로).
## 종전에는 확인 없이 바로 종료해서 오조작으로 회차를 날릴 수 있었다.
func _confirm_skip() -> void:
	var p := OrigPopup.open(self, "시나리오 Skip", Vector2(620.0, 330.0))
	var l := Label.new()
	l.text = "해당 시나리오를 패스 하시겠습니끼?"
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.16, 0.09, 0.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = Vector2(20.0, 62.0)
	l.size = Vector2(p.win_size.x - 40.0, 70.0)
	p.content.add_child(l)
	p.add_action_button("확인", func() -> void:
		p.close()
		_finish(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 - 110.0, p.win_size.y - 60.0))
	p.add_action_button("취소", func() -> void: p.close(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 + 110.0, p.win_size.y - 60.0))

# ── 원작 연출 스텝 재생 ────────────────────────────────────────────────────────
## `data/scenario_flow.json` 의 스텝을 **대사 하나가 나올 때까지** 소비한다.
## 원작도 같은 구조다 — `std::function` 벡터를 앞에서부터 실행하고 대사 스텝에서 입력을 기다린다.
func _play_flow() -> void:
	while _flow_i < _flow.size():
		var o: Dictionary = _flow[_flow_i]
		_flow_i += 1
		match String(o.get("op", "")):
			"setNpcTalk":
				var folder := Data.scenario_npc_folder(int(o.get("npc", 0)))
				_name_label.text = Data.npc_name(folder) if folder != "" else ""
				if folder != "":
					# state = 표정(= 파츠 번호). 원작 setTalker 가 eye/mouth/양팔에 같은 값을 넘긴다.
					_show_npc(folder, 1, int(o.get("state", 0)))
				_next_line()
				return
			"setTalker":
				# 1~78화 경로 — 원작 `ScenarioLayer::setTalker` 는 NPC 를 **이름 문자열**로 받는다
				# (번호를 받는 `setNpcTalk` 과 다르다).
				var f2 := String(o.get("npc_name", ""))
				_name_label.text = Data.npc_name(f2) if f2 != "" else ""
				if f2 != "":
					_show_npc(f2)
				_next_line()
				return
			"setTalk":
				# 원작 `ScenarioLayer::setTalk(bool)` — 이름을 인자로 받지 않고
				# **대사 문자열 키**(`ScenarioTalk<회차>_<줄>`)를 멤버에 써 두고 부른다.
				# ⇒ 이 경로는 줄 번호가 확정이라 순서 추정 없이 그 줄을 바로 집는다.
				#   화자는 이 호출이 알려 주지 않는다(앞선 setTalker 가 정한 이름을 유지).
				_line_by_key(String(o.get("key", "")))
				return
			"setUserTalk":
				# 주인공(=플레이어) 대사·지문. 원작도 이때 NPC 초상을 띄우지 않는다.
				_name_label.text = ""
				_next_line()
				return
			"changeBackGround", "changeBackGroundPass":
				_apply_bg(int(o.get("bg", 0)))
			"drawIllust":
				_apply_illust(int(o.get("illust", _no)), int(o.get("kind", 1)))
			"removeIllust":
				if is_instance_valid(_illust):
					_illust.visible = false
			"setOutTalker":
				_hide_npc()
			"playBackGroundFieldMusic":
				# 원작 `ScenarioSupport::playBackGroundFieldMusic(int)` — 번호→트랙 표는
				# 디컴프에서 그대로 뽑아 `scenario_flow.json` `bgm` 에 있다.
				Bgm.play(Data.scenario_bgm(int(o.get("field", 0))))
			"setTitleScenario":
				_show_title_card(int(o.get("title", _no)))
			"scenarioBlackLayer":
				# 원작 @0165b028 — 검은 막을 FadeTo(0.5,255) → 대기1.0 → FadeTo(0.5,50) → 대기1.0.
				_color_flash(Color(0, 0, 0, 0), [[0.5, 1.0], [1.0, 0.0], [0.5, 50.0 / 255.0], [1.0, 0.0]])
			"shineAction":
				# 원작 @0165b830 — 흰 막(ccColor4B 0xffffffff)을 FadeTo(0.25,255) → FadeTo(0.25,0).
				_color_flash(Color(1, 1, 1, 0), [[0.25, 1.0], [0.25, 0.0]])
			"showColorLayer":
				# 원작 @0165e208 — FadeTo(0.2, opacity) → 대기 0.2. 인자(색·불투명도)는
				# 스텝이 구조체로 넘겨 리터럴 복원이 안 됐다 → 기본값 검정 불투명.
				# ASSUMPTION: 색·최종 불투명도(원작 param_1/param_5) 미복원.
				_color_flash(Color(0, 0, 0, 0), [[0.2, 1.0], [0.2, 1.0]], 300)
			"deleteColorLayer":
				# 원작 @0165e44c — tag 0x12d(=301) 막을 걷어낸다.
				_clear_color_layer(300)
			"actionSmoke":
				# 원작 @0165c594 — 막을 FadeTo(0.2,125) → 대기 0.5 → RemoveSelf.
				_color_flash(Color(0.5, 0.5, 0.5, 0), [[0.2, 125.0 / 255.0], [0.5, 125.0 / 255.0], [0.2, 0.0]])
			"shakeAction":
				# 원작 @0165b7fc — `Shake::actionWithDuration(0.3, 5.0)`.
				_shake(0.3, 5.0)
			"sound_CryMonster":
				# 원작 @0165df7c — 몬스터 울음. 두 분기(param 1·2) 모두 `music/voice1.mp3`.
				Bgm.sfx("voice1")
			_:
				pass          # 아직 이식 안 한 연출(전투·미니게임·NPC 워크)은 건너뛴다
	_finish()

# ── 연출 헬퍼(원작 ScenarioSupport / ScenarioLayer) ────────────────────────────
## 연출 전용 오버레이 레이어. 원작은 색막을 z=0x62(98) 로 깔아 **텍스트박스 위**에 둔다.
func _fx() -> CanvasLayer:
	if not is_instance_valid(_fx_layer):
		_fx_layer = CanvasLayer.new()
		_fx_layer.layer = 10
		add_child(_fx_layer)
	return _fx_layer

## 텍스트박스를 아래로 250 밀어 치운다(원작 암전/섬광 공통 앞동작:
## `CCMoveBy::create(0.5, (0,-250))` + `CCEaseExponentialOut`). Cocos y-up 이라 우리는 +y.
func _push_box_away() -> void:
	if not is_instance_valid(_box):
		return
	var t := _box.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(_box, "position", _box_home + Vector2(0.0, 250.0), 0.5)

## 화면 전체 색막 한 장 + 페이드 시퀀스. `steps` = [[초, 목표알파], …].
## 원작은 `CCLayerColor` 를 z=98·tag=100 으로 깔고 `CCSequence(CCFadeTo…)` 를 돌린다.
func _color_flash(base: Color, steps: Array, tag := 100) -> void:
	_push_box_away()
	_clear_color_layer(tag)
	var r := ColorRect.new()
	r.name = "fx_%d" % tag
	r.color = base
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx().add_child(r)
	var t := r.create_tween()
	for s in steps:
		var arr: Array = s
		t.tween_property(r, "color:a", float(arr[1]), float(arr[0]))
	# 마지막 알파가 0이면 원작처럼 스스로 걷힌다(`CCRemoveSelf`). 남는 막은 다음 op 가 지운다.
	if not steps.is_empty() and is_zero_approx(float((steps[-1] as Array)[1])):
		t.tween_callback(func() -> void:
			if is_instance_valid(r):
				r.queue_free())
	# 박스를 다시 올린다 — 원작은 시퀀스 꼬리의 CCCallFunc 가 되돌린다.
	t.tween_callback(_restore_box)

func _restore_box() -> void:
	if not is_instance_valid(_box):
		return
	var t := _box.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(_box, "position", _box_home, 0.5)

func _clear_color_layer(tag := 100) -> void:
	if not is_instance_valid(_fx_layer):
		return
	var n := _fx_layer.get_node_or_null("fx_%d" % tag)
	if n != null:
		n.queue_free()

## 원작 `Shake::actionWithDuration(dur, amp)` — 매 프레임 [-amp, amp] 무작위 오프셋.
func _shake(dur: float, amp: float) -> void:
	var home := position
	var t := create_tween()
	var n := int(dur * 60.0)
	for i in n:
		t.tween_property(self, "position",
			home + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)), dur / float(n))
	t.tween_property(self, "position", home, 0.0)

## 회차 제목 카드 — 원작 `ScenarioLayer::setTitleScenario(int, bool)` @016d55f8.
##   · `music/effect_jingle.mp3` 재생
##   · 전체 색막 위에 두 줄: `<ScenarioTitleNumber>스토리 %1$d.` @ (w*0.2, h*0.8)
##                            회차 제목                        @ (w*0.5, h*0.55)
##     (원작 y 는 Cocos 상향이라 화면 위쪽 = 0.8 → 우리 좌표로 뒤집는다)
##   · 두 줄 모두 `GameManager::getFontName_subtitle` = `font/font_subtitle.fnt`
## ⚠️ 제목 텍스트는 원작이 로컬 SQLite `info_scenario_v2.title` 에서 읽는데 그 DB 가
##    덤프에 없다 → 위키에서 1~146화 전량 복원(`build_scenario.py::read_titles`).
func _show_title_card(no: int) -> void:
	Bgm.sfx("effect_jingle")
	var vis := _vis()
	var lay := _fx()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(root)
	# 원작 시퀀스(전부 `CCEaseExponentialInOut`):
	#   색막·번호 = FadeTo(0.9,255) → 대기 2.7 → FadeTo(0.36,0)
	#   제목      = 대기 1.1 → FadeTo(0.9,255) → 대기 1.6 → FadeTo(0.36,0)
	# 색막 바탕색은 `ccColor4B{0,0,0,0}`(local_268[0]=0) — 검정이 **완전 불투명까지** 찬다.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var num := _title_label("스토리 %d." % no, 30)      # 원작 <ScenarioTitleNumber> 그대로
	num.position = Vector2(vis.x * 0.2, vis.y * 0.2)
	num.modulate.a = 0.0
	root.add_child(num)
	var ttl := _title_label(Data.scenario_title(no), 42)
	ttl.position = Vector2(vis.x * 0.5 - ttl.size.x * 0.5, vis.y * 0.45)
	ttl.modulate.a = 0.0
	root.add_child(ttl)
	for pair in [[dim, "color:a"], [num, "modulate:a"]]:
		var n: CanvasItem = pair[0]
		var t0 := n.create_tween()
		t0.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_EXPO)
		t0.tween_property(n, String(pair[1]), 1.0, 0.9)
		t0.tween_interval(2.7)
		t0.tween_property(n, String(pair[1]), 0.0, 0.36)
	var t := ttl.create_tween()
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_interval(1.1)
	t.tween_property(ttl, "modulate:a", 1.0, 0.9)
	t.tween_interval(1.6)
	t.tween_property(ttl, "modulate:a", 0.0, 0.36)
	t.tween_callback(func() -> void:
		if is_instance_valid(root):
			root.queue_free())

## 원작 폰트(`font_subtitle`)로 한 줄. 비트맵이라 `fixed_size_scale_mode` 를 켜야 크기가 먹는다(§10).
func _title_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := load(TITLE_FONT) if ResourceLoader.exists(TITLE_FONT) else null
	if f != null:
		if f is FontFile:
			(f as FontFile).fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.size = l.get_minimum_size()
	return l

## 키(`ScenarioTalk<회차>_<줄>`)로 그 줄을 바로 집는다. 키 형식이 아니면 순서대로 폴백.
## 원작 문자열 키가 순서를 인코딩하고 있어서(§build_scenario.py) 줄 번호가 곧 `k` 다.
func _line_by_key(key: String) -> void:
	var m := RegEx.create_from_string(r"^ScenarioTalk\d+(?:_\d+)?_(\d+)$").search(key)
	if m == null:
		_next_line()
		return
	var want := int(m.get_string(1))
	for i in _lines.size():
		var d: Dictionary = _lines[i]
		if int(d.get("k", -1)) == want:
			_show_line_text(String(d.get("text", "")))
			_idx = i + 1
			return
	_next_line()

## 다음 대사 한 줄. 흐름이 대사보다 길면(분기 회차) 조용히 끝낸다 — 지어내지 않는다.
func _next_line() -> void:
	if _idx >= _lines.size():
		_show_line_text("")
		return
	_show_line_text(String((_lines[_idx] as Dictionary).get("text", "")))
	_idx += 1

## 배경 = 원작 `changeBackGround` 의 BackGruundName. 경로는 `data/scenario_flow.json`
## `backgrounds` 에 원작 그대로 들어 있고, 여기서 우리 변환본으로 옮긴다.
func _apply_bg(bg_no: int) -> void:
	var paths: Array = Data.scenario_bg_paths(bg_no)
	if paths.is_empty():
		return
	var res := _bg_res(String(paths[0]))
	if res == "":
		return
	if not is_instance_valid(_bg_layer):
		_bg_layer = TextureRect.new()
		_bg_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg_layer)
		move_child(_bg_layer, 1)          # 검은 막 바로 위
	_bg_layer.texture = load(res)
	_bg_layer.visible = true

## 원작 경로 → 우리 변환본. 시나리오 전용 배경 6장만 `scenario/bg/` 에 있고
## 나머지는 **탐험 배경 재사용**이라 `adventure_bg/bg_<필드>.jpg` 로 간다(§10 정정).
func _bg_res(orig: String) -> String:
	var cands: Array[String] = []
	var m := RegEx.create_from_string(r"scene/adventure/bg/(\d+)/")
	var r := m.search(orig)
	if r:
		cands.append("res://assets/converted/adventure_bg/bg_%s.jpg" % r.get_string(1))
	elif orig.begins_with("scenario/main_story/bg/"):
		cands.append("%s/bg/%s" % [ART_DIR, orig.get_file()])
	elif orig.begins_with("scene/magicshop/"):
		cands.append("res://assets/converted/magicshop_bg/%s" % orig.get_file())
	for c in cands:
		if ResourceLoader.exists(c):
			return c
	return ""

## 삽화 — 원작 `drawIllust(no, kind, bool)`. 파일명은 `sn_<회차>_<n>_illust.jpg`.
func _apply_illust(no: int, kind: int) -> void:
	var sc: Dictionary = Data.scenario_def(str(no))
	var arr: Array = sc.get("illust", [])
	if arr.is_empty():
		return
	var pick := String(arr[clampi(kind - 1, 0, arr.size() - 1)])
	var p := "%s/%s" % [ART_DIR, pick]
	if not ResourceLoader.exists(p):
		return
	if not is_instance_valid(_illust):
		_illust = TextureRect.new()
		_illust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_illust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_illust.set_anchors_preset(Control.PRESET_FULL_RECT)
		_illust.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_illust)
	_illust.texture = load(p)
	_illust.visible = true

func _hide_npc() -> void:
	if is_instance_valid(_npc_node):
		_npc_node.queue_free()
		_npc_node = null

func _show_line(i: int) -> void:
	_idx = i
	var e: Dictionary = _lines[i]
	# 화자는 유실 데이터다 — data/scenario_cast.json 에 기입한 것만 쓴다.
	var cast_npc := _cast_npc(_no, _part, int(e.get("k", 0)))
	_name_label.text = Data.npc_name(cast_npc) if cast_npc != "" else ""
	if cast_npc != "":
		_show_npc(cast_npc)
	_show_line_text(String(e.get("text", "")))

func _show_line_text(text: String) -> void:
	_label.text = text
	_label.visible_characters = 0
	_typing = true
	if _arrow: _arrow.visible = false
	if is_instance_valid(_timer): _timer.queue_free()
	_timer = Timer.new()
	_timer.wait_time = 1.0 / CPS
	add_child(_timer)
	var total := text.length()
	_timer.timeout.connect(func() -> void:
		_label.visible_characters += 1
		if _label.visible_characters >= total:
			_reveal_all())
	_timer.start()

func _reveal_all() -> void:
	_label.visible_characters = -1
	_typing = false
	if is_instance_valid(_timer): _timer.stop()
	if _arrow:
		_arrow.visible = true
		var t := _arrow.create_tween().set_loops()
		t.tween_property(_arrow, "position:y", BOX_H * 0.5 + 6.0, 0.4)
		t.tween_property(_arrow, "position:y", BOX_H * 0.5, 0.4)

## 탭: 타이핑 중이면 전체표시, 완료면 다음 줄. 마지막이면 종료.
func _advance() -> void:
	if _typing:
		_reveal_all()
		return
	if not _flow.is_empty():
		_play_flow()
		return
	if _lines.is_empty() or _idx + 1 >= _lines.size():
		_finish()
		return
	_show_line(_idx + 1)

## 시나리오 완료 알림 — 원작 문자열 `<ScenarioComplete>`/`<ScenarioCompleteTitle>`.
##   ScenarioComplete      = "스토리 보기 완료~!"          ← 창 제목
##   ScenarioCompleteTitle = "{제목}\n스토리를 완료하였습니다."  ← 본문(%1$s = 회차 제목)
## 이미 본 회차를 다시 볼 때는 띄우지 않는다(원작 setIsReview 분기와 같은 취지).
func _show_complete_notice() -> void:
	var ep := Data.story_episode(_no)
	var title := String(ep.get("title", "%d화" % _no))
	var p := OrigPopup.open(self, "스토리 보기 완료~!", Vector2(620.0, 330.0))
	var l := Label.new()
	l.text = "%s\n스토리를 완료하였습니다." % title
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.16, 0.09, 0.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = Vector2(20.0, 60.0)
	l.size = Vector2(p.win_size.x - 40.0, 90.0)
	p.content.add_child(l)
	p.add_action_button("확인", func() -> void:
		p.close()
		_leave())

func _finish() -> void:
	var first: bool = not bool(UserDB.get_progress("scenario_%d_%d" % [_no, _part], false))
	# 본 시나리오를 봤다고 기록(원작 setScenarioMark 대응) — 재관람/진행도 판정용.
	UserDB.set_progress("scenario_%d_%d" % [_no, _part], true)
	# 회차별 특별보상(원작 `ScenarioManager::setSpecialReward` 3건) — 클리어 시 지급.
	# 근거 문구: `ScenarioRewardNoti1` "해당 시나리오 클리어시 지급되며 …".
	var rw := StoryProgress.grant_special_reward(_no)
	if not rw.is_empty():
		_show_special_reward(rw)
		return
	if first:
		_show_complete_notice()
		return
	_leave()


func _leave() -> void:
	var back := String(_params.get("back", ""))
	if back == "":
		back = "worldmap"
	Scenes.goto(back, _params.get("back_params", {}))


## 특별보상 안내 — 원작 `ScenarioSpecialRewardPopup`.
## ⚠️ 원작 팝업의 프레임은 `new9patch/ma_*` · `newCommon/ncb_*`(후기판 UI 세트)라 우리 덤프에
##    통째로 없다(CLAUDE.md §10 의 `new*` 63% 군). 그래서 **보유 프레임**으로 재구성한다 —
##    창은 `OrigPopup`(9patch/popup4 + pop_title_bg + common/close_btn), 문구는 원작
##    문자열 키(`ScenarioRewardTitle`·`ScenarioRewardTitle2`·`ScenarioRewardGem`·
##    `ScenarioRewardSkill`·`ScenarioRewardNoti1`) 그대로.
func _show_special_reward(rw: Dictionary) -> void:
	var p := OrigPopup.open(self, "시나리오 보상", Vector2(700.0, 470.0))   # ScenarioRewardTitle
	p.closed.connect(_leave)
	var y := 110.0
	var name_l := Label.new()
	name_l.text = "Lv.%d %s" % [int(rw.get("level", 1)), String(rw.get("name", ""))]  # ScenarioRewardTitle2
	name_l.add_theme_font_size_override("font_size", 30)
	name_l.add_theme_color_override("font_color", Color(0.24, 0.15, 0.05))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.position = Vector2(0, y); name_l.size = Vector2(p.win_size.x, 40)
	p.content.add_child(name_l)
	y += 56.0
	# 드래곤 썸네일 = 원작 `dragon/dragon_<id>_box_<단계>.png`([[dv2-dragon-portraits-and-card-offlimits]]).
	var dno := int(rw.get("dragon_no", 0))
	var tp := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_adult.tres" % [dno, dno]
	if ResourceLoader.exists(tp):
		var tr := TextureRect.new()
		tr.texture = load(tp)
		# ⚠️ 원작 아틀라스는 **PMA(프리멀티플라이드 알파)** 다 — 이 재질을 안 걸면 투명부가
		#    검은 판으로 보인다(cocos_export.py 헤더 · 이 파일의 `_pma` 와 같은 이유).
		tr.material = _pma
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(150, 150)
		tr.position = Vector2(p.win_size.x * 0.5 - 75.0, y)
		p.content.add_child(tr)
		y += 162.0
	var det := Label.new()
	var miss: Array = rw.get("skills_missing", [])
	det.text = "보유 스킬 %d개 습득" % int(rw.get("skills_granted", 0))   # ScenarioRewardSkill
	if not miss.is_empty():
		det.text += "  (미구현 스킬 %s 제외)" % str(miss)
	det.add_theme_font_size_override("font_size", 17)
	det.add_theme_color_override("font_color", Color(0.36, 0.26, 0.1))
	det.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.position = Vector2(20, y); det.size = Vector2(p.win_size.x - 40, 44)
	p.content.add_child(det)
	var noti := Label.new()
	noti.text = "해당 시나리오 클리어시 지급되며, 해당 드래곤은\n둥지의 드래곤 목록에서 확인할 수 있습니다."
	noti.add_theme_font_size_override("font_size", 15)
	noti.add_theme_color_override("font_color", Color(0.5, 0.36, 0.14))
	noti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	noti.position = Vector2(20, y + 48.0); noti.size = Vector2(p.win_size.x - 40, 50)
	p.content.add_child(noti)

## 화자 배정 — `data/scenario_cast.json` { "<no>": { "<part>": { "<scriptNo>": "<npc폴더>" } } }.
## 원작 `ScenarioScript::npcNo` + `InfoNpc::getNpcPlistName()` 조합이 하던 일인데 둘 다 서버
## 데이터라 유실이다. 파일이 없거나 키가 없으면 "" → 이름칸을 비우고 초상도 띄우지 않는다.
var _cast: Dictionary = {}
var _cast_loaded := false
func _cast_npc(no: int, part: int, k: int) -> String:
	if not _cast_loaded:
		_cast_loaded = true
		var f := FileAccess.open("res://data/scenario_cast.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _cast = d
	var byno: Dictionary = _cast.get(str(no), {})
	var bypart: Dictionary = byno.get(str(part), {})
	return String(bypart.get(str(k), ""))

## NPC 초상 — **공용 컴포넌트 `NpcPortrait` 를 쓴다**(상점·연구소·육성과 같은 것).
##
## 🔴 2026-07-31: 여기 자체 합성 코드를 두고 있었는데, 파츠 좌표를 다른 화면
##   (`PopSeekFinishLayer`)의 상수로 박아 둬서 **눈이 이마 위로 튀어나갔다**(사용자 지적).
##   원작은 `NpcManager::setTarget` 이 **NPC·포즈마다** 눈/입 위치를 잡고, 그 값은 이미
##   `data/npc_face.json` 으로 추출돼 `NpcPortrait` 가 앵커(0,1)까지 맞춰 그리고 있었다.
##   ⇒ 자체 구현을 버리고 공용 컴포넌트로 교체(CLAUDE.md §3 "우리 코드에 같은 헬퍼가 있는지 먼저 grep").
##
## 표정 = `Character_State`. `ScenarioLayer::setTalker(bool, name, int body, int state, …)` 이
##   같은 값을 `setNpcEye`/`setNpcMouse`/양팔에 그대로 넘긴다(전부 `param_9`) —
##   조합표 같은 건 없고 **표정 번호 = 파츠 번호**다.
func _show_npc(npc: String, body := 1, state := 1) -> void:
	var want := "%s|%d|%d" % [npc, body, state]
	if is_instance_valid(_npc_node) and _npc_node.get_meta("npc", "") == want:
		return
	if is_instance_valid(_npc_node):
		_npc_node.queue_free()
	var p := NpcPortrait.create(npc, maxi(state, 1), body)
	if p == null:
		_npc_node = null
		return
	_npc_node = p
	p.set_meta("npc", want)
	# 원작 대화 초상은 하단 대화상자 위에 발밑을 붙인다(몸통 앵커 (0.5,0)).
	p.position = Vector2(_vis().x * 0.5, _vis().y - BOX_H)
	p.z_index = 4
	add_child(p)
	p.modulate.a = 0.0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.2)

# ---------- 헬퍼 ----------
func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _spr(dir: String, name: String, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s
