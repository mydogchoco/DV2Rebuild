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
## 대사를 소비하는 op — 원작 대사 함수 네 갈래(§ScenarioWiring.md §11).
const TALK_OPS := ["setNpcTalk", "setUserTalk", "setTalker", "setTalk"]

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
var _arrow_tween: Tween
## 원작은 Character_Pos 1/2/3마다 NpcManager를 하나씩 유지한다. 한 노드로 갈아 끼우면
## 좌우 대화가 전부 중앙에 뜨고, 상대 화자가 말할 때마다 이전 초상이 사라진다.
var _npc_slots: Dictionary = {}       # {1:left, 2:right, 3:center} -> NpcPortrait
var _active_npc: Node2D

## 연출용 — 텍스트박스(암전/섬광이 아래로 밀어낸다) · 화면 전체 색막 · 제목 카드 레이어.
var _box: NinePatchRect
var _box_home := Vector2.ZERO
var _fx_layer: CanvasLayer
var _sc_item: Sprite2D            # showScenarioItem 이 띄우는 소품
var _monster: Sprite2D            # showMonster 가 세우는 컷신 몬스터
var _skip_btn: Button             # setHidePassButton 이 감추는 건너뛰기 버튼

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
	# 목록/UI 우회 진입도 막는다. 제목만 있고 본문이 없는 회차는 씬 진입점에서도 차단한다.
	if not StoryProgress.implemented(_no):
		_build_unavailable()
		return
	var sc: Dictionary = Data.scenario_def(str(_no))
	var parts: Array = sc.get("parts", [])
	_flow = Data.scenario_flow_of(_no)
	_flow_i = 0
	_npc_slots.clear()
	_active_npc = null
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
	# 전투에서 돌아온 경우 — 그 스텝 **다음부터** 잇는다. 이미 지나간 대사는 다시 세어
	# 화자·줄이 어긋나지 않게 `_idx` 도 같이 맞춘다.
	var resume := int(_params.get("resume_flow", 0))
	if resume > 0 and resume <= _flow.size():
		_flow_i = resume
		_idx = 0
		for i in resume:
			if String((_flow[i] as Dictionary).get("op", "")) in TALK_OPS:
				_idx += 1
		_idx = mini(_idx, _lines.size())
	# 원작 `ScenarioLayer::initWidget` 의 `if (sn == 0x14)` — **20화만** 컷 5장을
	# 레이어 초기화 때 깐다(스텝이 아니다). 94·99·100화는 스텝(`drawillust_N`)이라 여기 해당 없음.
	# ⚠️ 원작 좌표는 루프에서 누적돼 리터럴이 없다 → 우리 컷 표시(순차 겹침 + 암전 번뜩임)를 쓴다.
	if _no == 20 and not Data.scenario_def(str(_no)).get("cuts", []).is_empty():
		_show_cutin()
	if not _flow.is_empty():
		_play_flow()
	elif _lines.is_empty():
		_show_line_text("(이 시나리오의 대사가 없습니다 — data/scenario.json 확인)")
	else:
		_show_line(0)


## 미구현 회차가 저장 데이터/개발자 호출로 직접 들어왔을 때의 안전 화면.
## 정상 UI에서는 재생 버튼 자체가 비활성화되므로 이 경로는 방어선이다.
func _build_unavailable() -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.03, 0.06)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var msg := Label.new()
	msg.text = "%d화는 현재 구현되지 않아 열람할 수 없습니다." % _no
	msg.add_theme_font_size_override("font_size", 26)
	msg.add_theme_color_override("font_color", Color.WHITE)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(msg)
	var leave := Button.new()
	leave.text = "돌아가기"
	leave.size = Vector2(180.0, 56.0)
	leave.position = Vector2((_vis().x - leave.size.x) * 0.5, _vis().y * 0.65)
	leave.pressed.connect(_leave)
	back.add_child(leave)

## 배경. 원작은 두 곳에서 정한다:
##   ① 회차가 열릴 때 `ScenarioLayer::initWidget` 의 sn switch 가 한 장 깐다 → `initial_bg`
##   ② 그 뒤 `changeBackGround` 스텝이 갈아 끼운다 — **79~101화에만** 있다
## 🔴 2026-08-01: ①을 안 읽어서 1~78화가 전부 검은 화면이었다(사용자 신고 "1화 배경 검정").
##    ②만 배선돼 있었는데 그 구간엔 배경 스텝이 하나도 없다.
func _build_backdrop(sc: Dictionary) -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.03, 0.06)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	# 회차 초기 배경 — 표에 없는 회차는 원작도 배경을 만들지 않는다(스트림이 비어 있다).
	var ib := Data.scenario_initial_bg(_no)
	if ib != "":
		var res := _bg_res(ib)
		if res != "":
			_put_bg(res, _field_of(ib))
		else:
			push_warning("[story] 초기 배경 변환본 없음: %s" % ib)
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
	_skip_btn = b          # setHidePassButton 이 감춘다
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
					_show_npc(folder, 1, int(o.get("state", 0)), int(o.get("pos", 3)))
				_next_line()
				return
			"setTalker":
				# 1~78화 경로 — 원작 `ScenarioLayer::setTalker` 는 NPC 를 **이름 문자열**로 받는다
				# (번호를 받는 `setNpcTalk` 과 다르다).
				var f2 := _str(o, "npc_name")
				_name_label.text = Data.npc_name(f2) if f2 != "" else ""
				if f2 != "":
					_show_npc(f2, maxi(int(o.get("body", 1)), 1),
						maxi(int(o.get("state", 1)), 1), int(o.get("pos", 3)))
				_next_line()
				return
			"setTalk":
				# 1~78화 경로. 원작은 대사 함수를 부르기 전에 **멤버 두 개에 문자열을 써 둔다**:
				#   this+0x1d8 = 화자(`NPC_nuri`) · this+0x1f0 = 대사 키(`ScenarioTalk1_1`)
				# ⇒ 줄 번호가 확정이라 순서 추정이 필요 없고, **화자도 유실이 아니었다.**
				var f3 := _str(o, "npc_name")
				if f3 != "":
					_name_label.text = Data.npc_name(f3)
					# `body`/`state` 는 **`setTalker` 로 합류한 스텝에만** 있다(`via` 참조).
					# 나머지 다섯 함수는 그 인자를 받지 않으므로 원작도 초상을 바꾸지 않는다
					# — 그 NPC 가 이미 서 있으면 **그대로 둔다**(자세·표정 유지).
					if o.get("body") != null or o.get("state") != null:
						_show_npc(f3, maxi(int(o.get("body", 1)), 1),
							maxi(int(o.get("state", 1)), 1), int(o.get("pos", 3)))
					else:
						_keep_or_show_npc(f3)
				_line_by_key(_str(o, "key"))
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
				_hide_npc(int(o.get("talker", 0)), int(o.get("n", 0)))
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
			"scenarioBattle":
				# 원작 `ScenarioSupport::scenarioBattle(field, battleNo)` @0165c7d4 —
				# `AdventureScene::scene(…)` 을 **푸시**하고, 전투가 끝나면 그 스텝 다음부터 잇는다.
				# 우리는 씬 스택이 없으므로 battle 씬에 복귀 지점(`story_return`)을 들려 보낸다.
				if _start_battle(int(o.get("battle", 0))):
					return          # 씬이 바뀐다 — 나머지 스텝은 복귀 후에 잇는다
			"walkAction":
				# 원작 @0165bd24 — 텍스트박스를 치우고 `mScenarioManager+0x188` 에 필드 번호를
				# 박은 뒤 이동 연출(`InfoEventData`)을 돌린다. 우리는 **필드 이동 = 배경 전환**
				# 까지만 이식한다(원작의 이동 애니는 탐험 필드 시스템에 묶여 있다).
				var fld := int(o.get("field", 0))
				_push_box_away()
				if fld > 0:
					_apply_field_bg(fld)
				_restore_box()
			"delayWalkAction":
				# 원작 @0165b628 `delayWalkAction(float delay, int n)` — 지연 뒤 **n번의
				# 걷기 비트**(각 사이 0.5초). 걷는 스프라이트가 없으므로 **박자만** 남긴다.
				# ASSUMPTION: 첫 인자(지연)는 float 라 스택에 안 남아 미복원 → 0으로 둔다.
				_walk_beats(int(o.get("n", 1)))
			"drawillust_3", "drawillust_8", "drawillust_9":
				# 컷 시퀀스. 원작 렌더러는 회차 클래스의 `drawillust_N` 이고
				# `sn_<회차>/back.jpg` + `s1~sN`(20화는 `1~5`)을 깐다 — 목록은 scenario.json `cuts`.
				_show_cutin()
			"showMonster":
				# 원작 `ScenarioSupport::showMonster(vector<int>, float, bool)` @0165dba4 —
				# `scenario/monster_npc/*.png` 정지 스프라이트를 배경 위에 세운다(전투 아님).
				_show_monster(int(o.get("monsters", 0)))
			"deleteMonster":
				if is_instance_valid(_monster):
					_monster.queue_free()
			"setHidePassButton":
				# 원작 `ScenarioLayer::setHidePassButton` — 건너뛰기 버튼을 감춘다
				# (건너뛰면 안 되는 구간: 미니게임·전투 직전).
				if is_instance_valid(_skip_btn):
					_skip_btn.visible = false
			"miniGameText":
				# 원작 @0165c2a8 `miniGameText(bool, int)` — 미니게임 안내 문구.
				# 대사 키를 멤버에 박고(`ScenarioTalk86_M` 등) 보여 준다.
				_line_by_key("ScenarioTalk%d_M" % _no)
				return
			"passMiniGame":
				# 원작 @0165d3f8 — 미니게임을 **건너뛴다**(스텝 번호를 통과 지점으로 옮긴다).
				# 우리는 미니게임 자체가 없으므로 아무것도 하지 않고 다음 스텝으로 간다.
				pass
			"showScenarioItem":
				_show_sc_item(int(o.get("item", -1)))
			"removeScenarioItem":
				if is_instance_valid(_sc_item):
					_sc_item.queue_free()
			_:
				pass          # 아직 이식 안 한 연출(전투·미니게임·NPC 워크)은 건너뛴다
	_finish()

## 스토리 전투로 넘어간다. 편성을 못 찾으면 **건너뛴다**(지어내지 않는다) — false 반환.
##
## 복귀: `battle` 씬이 `story_return` 을 그대로 들고 있다가 끝나면
##       `Scenes.goto("story", {... , "resume_flow": <다음 스텝>})` 로 되돌린다.
func _start_battle(battle_no: int) -> bool:
	var spec: Dictionary = Data.story_battle(battle_no)
	if spec.is_empty():
		push_warning("[story] 전투번호 %d 의 편성을 못 찾았다 — 건너뛴다" % battle_no)
		return false
	var p := {
		"enemy": spec["enemy"],
		"story_return": {
			"no": _no, "part": _part, "resume_flow": _flow_i,
			"back": _params.get("back", "worldmap"),
			"back_params": _params.get("back_params", {}),
		},
	}
	var fld := int(spec.get("field", 0))
	if fld > 0:
		# 배경 전용 — 적 편성은 `enemy` 가 정한다(stage 를 넘기면 그 던전 적이 이긴다).
		# 이벤트 전투는 원작이 필드를 지정하고(602·24·601), 1~78화는 그 몹의 던전이다.
		p["bg_stage"] = fld
	Scenes.goto("battle", p)
	return true

# ── 연출 헬퍼(원작 ScenarioSupport / ScenarioLayer) ────────────────────────────
## 탐험 필드 번호 → 그 필드 배경. `changeBackGround` 가 쓰는 것과 같은 변환본을 쓴다.
func _apply_field_bg(field: int) -> void:
	var p := "res://assets/converted/adventure_bg/bg_%d.jpg" % field
	if not ResourceLoader.exists(p):
		return
	_put_bg(p, field)

## 배경 한 장을 깐다. 탐험 필드 배경은 **2겹**이라(원경 `bg.jpg` + 전경 `bg_item.png`)
## 원작 `changeBackGround` 도 전경 스프라이트를 따로 만든다 — `DungeonBG.add_overlay` 재사용.
## fid <= 0 이면 마을·상점처럼 전경이 없는 배경이다.
func _put_bg(res: String, fid: int) -> void:
	_ensure_bg_layer()
	for c in _bg_layer.get_children():
		c.queue_free()                     # 이전 전경 오버레이 제거
	_bg_layer.texture = load(res)
	_bg_layer.visible = true
	if fid > 0:
		DungeonBG.add_overlay(_bg_layer, {"bg": fid})

## 걷기 비트 n회 — 원작은 매 비트마다 CCCallFunc(이동) + CCDelayTime(0.5).
## 우리는 이동 스프라이트가 없어 **박자만** 남긴다(텍스트박스를 치우고 n*0.5초 뒤 되돌림).
func _walk_beats(n: int) -> void:
	_push_box_away()
	var t := create_tween()
	t.tween_interval(0.5 * float(maxi(n, 1)))
	t.tween_callback(_restore_box)

## 컷 시퀀스 — 원작 `Scenario_*::drawillust_N`(예: `Scenario_Kadeath::drawillust_3` @01665ec0).
## 배경 `back.jpg` 위에 컷을 순서대로 겹치고, 원작처럼 검은 막을 짧게 번뜩인다
## (`Cutin::show` @014febe0: Delay → FadeTo(dur*0.1, 150) → Delay(dur*0.4) → FadeTo(dur*0.1, 0)).
## ⚠️ 타이밍 인자(delay·dur)는 float 라 스택에 안 남아 미복원 — dur=1.0 으로 둔다(ASSUMPTION).
func _show_cutin() -> void:
	var cuts: Array = Data.scenario_def(str(_no)).get("cuts", [])
	if cuts.is_empty():
		return
	# ⚠️ 컷은 **대사창 아래**(layer 5 < 텍스트박스 8)에 둔다 — 위에 두면 대사를 가린다.
	var lay := CanvasLayer.new()
	lay.layer = 5
	add_child(lay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(root)
	var back: TextureRect = null
	var panels: Array[TextureRect] = []
	for c in cuts:
		var name := String(c)
		var tex: Texture2D = null
		var is_back := name.ends_with(".jpg")
		if is_back:                                     # back.jpg — 낱장 복사본
			var p1 := "%s/%s" % [ART_DIR, name]
			if ResourceLoader.exists(p1):
				tex = load(p1)
		else:                                           # 아틀라스 프레임(scenario_cut)
			var p2 := "res://assets/converted/scenario_cut/%s.tres" % name
			if ResourceLoader.exists(p2):
				tex = load(p2)
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if is_back 			else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
		if is_back:
			back = tr                                   # 배경은 깔아 두고 안 지운다
		else:
			tr.modulate.a = 0.0
			panels.append(tr)
	if panels.is_empty():
		return
	# 🔴 컷은 **한 장씩 교체**한다. 원작 20화는 5장이 각각 다른 장면이라 겹쳐 쌓으면
	#    화면이 뭉갠다(실측: 난파선 컷이 서로 포개졌다). 94·99·100화도 back.jpg 위의
	#    연속 컷이라 교체가 맞다.
	var t := create_tween()
	for i in panels.size():
		var cur: TextureRect = panels[i]
		t.tween_property(cur, "modulate:a", 1.0, 0.25)
		t.tween_interval(0.9)
		if i < panels.size() - 1:
			t.tween_property(cur, "modulate:a", 0.0, 0.2)
	# 원작의 검은 번뜩임(`Cutin::show` @014febe0) — 마지막 컷 뒤 한 번.
	var flash := ColorRect.new()
	flash.color = Color(0, 0, 0, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	t.tween_property(flash, "color:a", 150.0 / 255.0, 0.1)
	t.tween_interval(0.4)
	t.tween_property(flash, "color:a", 0.0, 0.1)

## 컷신 몬스터 — 원작 `showMonster`. 전투 몬스터가 아니라 `scenario/monster_npc/` 정지 스프라이트다.
## ⚠️ 좌표·크기 인자(float)는 스택에 안 남아 미복원 — 화면 중앙에 세운다(ASSUMPTION).
func _show_monster(no: int) -> void:
	var orig := Data.scenario_monster_path(no)
	if orig == "":
		return
	var key := orig.trim_suffix(".png").replace("/", "_")
	var p := "res://assets/converted/scenario_monster/%s.tres" % key
	if not ResourceLoader.exists(p):
		return
	if is_instance_valid(_monster):
		_monster.queue_free()
	var vis := _vis()
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	s.position = Vector2(vis.x * 0.5, vis.y * 0.5)
	_monster = s
	_fx().add_child(s)
	s.modulate.a = 0.0
	s.create_tween().tween_property(s, "modulate:a", 1.0, 0.3)

## 시나리오 소품 — 원작 `ScenarioSupport::showScenarioItem(ScenarioItem*, x, y, …)` @0165cb68.
## 번호→프레임 표(0~11)는 디컴프에서 그대로 뽑아 `scenario_flow.json` `sc_items` 에 있다.
## ⚠️ 좌표 인자는 `fmov` 로 넘어가 스택에 안 남는 경우가 많아 대부분 미복원이다
##    (ASSUMPTION: 화면 중앙 상단). 값이 복원된 스텝은 그 값을 쓴다.
func _show_sc_item(no: int) -> void:
	var orig := Data.scenario_item_path(no)
	if orig == "":
		return
	var key := orig.trim_suffix(".png").replace("/", "_")
	# 12종 중 5·6(`item/item_small/stone2.png`)만 전용 아틀라스가 아니라 아이템 아틀라스에 있다.
	var cands := ["res://assets/converted/scenario_item/%s.tres" % key,
		"res://assets/converted/item_small_ui/%s.tres" % key]
	var tex: Texture2D = null
	for c in cands:
		if ResourceLoader.exists(c):
			tex = load(c)
			break
	if tex == null:
		return
	if is_instance_valid(_sc_item):
		_sc_item.queue_free()
	var vis := _vis()
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	s.position = Vector2(vis.x * 0.5, vis.y * 0.38)
	_sc_item = s
	_fx().add_child(s)
	s.modulate.a = 0.0
	var t := s.create_tween()
	t.tween_property(s, "modulate:a", 1.0, 0.3)


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

## 흐름 스텝의 문자열 필드. ⚠️ 미해석 인자는 JSON **null** 로 들어오는데 `String(null)` 은
## 4.7 런타임 에러다(`Invalid call 'String' constructor`) — 실제로 28화 재생에서 터졌다.
func _str(o: Dictionary, key: String) -> String:
	var v = o.get(key, null)
	return String(v) if typeof(v) == TYPE_STRING else ""

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
		# 원작 case 0·9 = 경로 없이 배경 노드에 setVisible(false) — **숨기라는 뜻**이다.
		# 종전엔 그냥 return 이라 이전 배경이 그대로 남았다.
		if is_instance_valid(_bg_layer):
			_bg_layer.visible = false
		return
	var res := _bg_res(String(paths[0]))
	if res == "":
		return
	_put_bg(res, _field_of(String(paths[0])))

## 장면 배경 레이어(없으면 만든다). `changeBackGround` 와 `walkAction` 이 공유한다.
func _ensure_bg_layer() -> void:
	if is_instance_valid(_bg_layer):
		return
	_bg_layer = TextureRect.new()
	_bg_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_layer)
	move_child(_bg_layer, 1)              # 검은 막 바로 위

## 원작 경로 → 우리 변환본. 시나리오 전용 배경 6장만 `scenario/bg/` 에 있고
## 나머지는 **탐험 배경 재사용**이라 `adventure_bg/bg_<필드>.jpg` 로 간다(§10 정정).
## 원작 경로에서 탐험 필드 번호를 뽑는다(전경 오버레이용). 필드 배경이 아니면 0.
func _field_of(orig: String) -> int:
	var r := RegEx.create_from_string(r"scene/adventure/bg/(\d+)/").search(orig)
	return int(r.get_string(1)) if r else 0

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
	elif orig.begins_with("scene/shop/"):
		cands.append("res://assets/converted/shop_bg/%s" % orig.get_file())
	elif orig.begins_with("scene/laboratory/"):
		cands.append("res://assets/converted/laboratory_bg/%s" % orig.get_file())
	elif orig.begins_with("scenario/prologue/"):
		cands.append("res://assets/converted/prologue_ui/%s" % orig.get_file())
	elif orig.begins_with("scenario/main_story/"):
		# 20화 초기 배경 `sn_20_1_illust.jpg` 처럼 삽화가 배경으로 오는 경우
		cands.append("%s/%s" % [ART_DIR, orig.get_file()])
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

func _hide_npc(pos := 0, mode := 0) -> void:
	var which: Array = _npc_slots.keys() if pos <= 0 else [clampi(pos, 1, 3)]
	for k in which:
		var p: Node2D = _npc_slots.get(int(k))
		_npc_slots.erase(int(k))
		if is_instance_valid(p):
			_exit_npc(p, int(k), mode)
	if not is_instance_valid(_active_npc) or pos <= 0 or int(_active_npc.get_meta("story_pos", 0)) == pos:
		_active_npc = null

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
	_stop_arrow_tween()
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
		_stop_arrow_tween()
		_arrow_tween = _arrow.create_tween().set_loops()
		_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5 + 6.0, 0.4)
		_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5, 0.4)

func _stop_arrow_tween() -> void:
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = null
	if is_instance_valid(_arrow):
		_arrow.position.y = BOX_H * 0.5

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
## 자세·표정 인자가 없는 대사 스텝(`setReorderTalker`·`setTalk`·`setTalkFor*`).
## 원작은 이미 서 있는 화자를 앞으로 세울 뿐 초상을 새로 만들지 않는다 —
## 같은 NPC 면 그대로 두고, 아직 없으면 기본 자세로 세운다.
func _keep_or_show_npc(npc: String) -> void:
	for p in _npc_slots.values():
		if is_instance_valid(p) and String(p.get_meta("npc", "")).begins_with(npc + "|"):
			_active_npc = p
			p.z_index = 5
			for other in _npc_slots.values():
				if is_instance_valid(other) and other != p:
					other.z_index = 4
			return
	# setReorderTalker 등 위치 인자가 없는 호출은 앞선 원작 스텝에서 그 NPC의 슬롯을 찾는다.
	# 전투 복귀처럼 노드를 재구성해야 할 때만 조용히 복원한다.
	_show_npc(npc, 1, 1, _flow_pos_for_npc(npc), false)

func _show_npc(npc: String, body := 1, state := 1, pos := 3, animate := true) -> void:
	pos = clampi(pos, 1, 3)
	var want := "%s|%d|%d" % [npc, body, state]
	var old: Node2D = _npc_slots.get(pos)
	if is_instance_valid(old) and old.get_meta("npc", "") == want:
		_active_npc = old
		return
	# 원본 화자 ID 100은 폴더명이 `who`, 표시명은 `???`지만 대응 초상 에셋이 없다.
	# 빈 NpcPortrait를 만들면 매니페스트 경고와 투명 화자 노드만 남으므로 이름/대사만 표시한다.
	var manifest := "res://assets/converted/npc_%s/_manifest.json" % npc
	if not FileAccess.file_exists(manifest):
		if is_instance_valid(old):
			_exit_npc(old, pos, 2)
		_npc_slots.erase(pos)
		if _active_npc == old:
			_active_npc = null
		return
	if is_instance_valid(old):
		_exit_npc(old, pos, 2)
	var p := NpcPortrait.create(npc, maxi(state, 1), body)
	if p == null:
		_npc_slots.erase(pos)
		return
	_npc_slots[pos] = p
	_active_npc = p
	p.set_meta("npc", want)
	p.set_meta("story_pos", pos)
	# 원작 NpcManager::getDefaultNpcPos — 발밑은 화면 하단, 대화상자가 위 레이어에서 덮는다.
	var home := _npc_home(p, pos)
	p.position = home
	for other in _npc_slots.values():
		if is_instance_valid(other) and other != p:
			other.z_index = 4
	p.z_index = 5
	add_child(p)
	if animate:
		_enter_npc(p, pos, home)

## `NpcManager::getDefaultNpcPos(1/2/3)`의 화면 기준 배치.
func _npc_home(p: Node2D, pos: int) -> Vector2:
	var vis := _vis()
	# p 가 Node2D 로 타입 지정돼 있어 동적 메서드 반환형을 추론할 수 없다.
	# 명시 변환이 없으면 스크립트 전체가 파싱 실패해 스토리 진입 시 이전 회색 딤만 남는다.
	var w: float = float(p.call("body_width")) if p.has_method("body_width") else 0.0
	match pos:
		1: return Vector2(w * 0.5, vis.y)
		2: return Vector2(vis.x - w * 0.5, vis.y)
		_: return Vector2(vis.x * 0.5, vis.y)

## 원작 `ScenarioLayer::setTalker`: 좌우 BackOut 0.5초, 중앙 ExpoInOut 1.25초.
func _enter_npc(p: Node2D, pos: int, home: Vector2) -> void:
	var vis := _vis()
	var t := p.create_tween()
	if pos == 1:
		p.position = home - Vector2(vis.x * 0.5, 0.0)
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "position", home, 0.5)
	elif pos == 2:
		p.position = home + Vector2(vis.x * 0.5, 0.0)
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "position", home, 0.5)
	else:
		p.position = home + Vector2(0.0, vis.y)
		t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(p, "position", home, 1.25)

## 원작 `setOutTalker`: mode1=FadeOut(0.5), mode2=위치별 바깥 이동(0.5).
func _exit_npc(p: Node2D, pos: int, mode: int) -> void:
	if mode <= 0:
		p.queue_free()
		return
	var vis := _vis()
	var t := p.create_tween()
	if mode == 1:
		t.tween_property(p, "modulate:a", 0.0, 0.5)
	else:
		var dst := p.position
		if pos == 1: dst -= Vector2(vis.x * 0.5, 0.0)
		elif pos == 2: dst += Vector2(vis.x * 0.5, 0.0)
		else: dst += Vector2(0.0, vis.y)
		t.set_trans(Tween.TRANS_EXPO if pos == 3 else Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(p, "position", dst, 0.5)
	t.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

## 위치 없는 setReorderTalker/복귀 재구성용. 앞선 원작 스텝에서 같은 NPC의 마지막 pos를 찾는다.
func _flow_pos_for_npc(npc: String) -> int:
	for i in range(mini(_flow_i, _flow.size()) - 1, -1, -1):
		var o: Dictionary = _flow[i]
		if not o.has("pos"):
			continue
		if String(o.get("npc_name", "")) == npc:
			return clampi(int(o.get("pos", 3)), 1, 3)
		if String(o.get("op", "")) == "setNpcTalk" \
				and Data.scenario_npc_folder(int(o.get("npc", 0))) == npc:
			return clampi(int(o.get("pos", 3)), 1, 3)
	return 3 # 102화 이상 서버 유실 폴백만 중앙(기존 동작)

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
