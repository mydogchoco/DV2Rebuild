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
## ⇒ 그래서 이 화면은 **텍스트 + 삽화 + NPC 초상**까지 원작 레이아웃으로 재생하고,
##   화자/배경/표정은 `data/scenario_cast.json`(사용자 기입, 없으면 생략)에서만 읽는다.
##   지어내지 않는다(HARD RULE 6).
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
## 타자기 속도(문자/초). 원작 `ScenarioTextBox::setTextSpeed` 값은 코스메틱 클라 설정이라
## 정확값 미확정 → ASSUMPTION 40cps (BattleTextBox 이식과 같은 값).
const CPS := 40.0

var _params: Dictionary = {}
var _lines: Array = []            # [{k, text}]
var _idx := 0
var _no := 0
var _part := 0
var _pma: CanvasItemMaterial

var _label: Label
var _name_label: Label
var _arrow: Sprite2D
var _typing := false
var _timer: Timer
var _npc_node: Node2D

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
	_lines = []
	if _part >= 0 and _part < parts.size():
		_lines = (parts[_part] as Dictionary).get("lines", [])
	_build_backdrop(sc)
	_build_textbox()
	_build_skip()
	if _lines.is_empty():
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
	b.pressed.connect(_finish)
	lay.add_child(b)

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
	if _lines.is_empty() or _idx + 1 >= _lines.size():
		_finish()
		return
	_show_line(_idx + 1)

func _finish() -> void:
	# 본 시나리오를 봤다고 기록(원작 setScenarioMark 대응) — 재관람/진행도 판정용.
	UserDB.set_progress("scenario_%d_%d" % [_no, _part], true)
	# 회차별 특별보상(원작 `ScenarioManager::setSpecialReward` 3건) — 클리어 시 지급.
	# 근거 문구: `ScenarioRewardNoti1` "해당 시나리오 클리어시 지급되며 …".
	var rw := StoryProgress.grant_special_reward(_no)
	if not rw.is_empty():
		_show_special_reward(rw)
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

## NPC 초상 합성 — 원작 `npc/<plist>` 의 body + eye + mouth 파츠.
## 배치 근거는 adventure.gd `_show_npc` 와 같은 `PopSeekFinishLayer.c:191-217`
## (body 앵커 (0.5,0) 화면 하단중앙, mouth @(103,310), eye @(104,346) — body 로컬 y-up).
## 표정(emotionNo)도 유실이라 기본 파츠만 쓴다.
func _show_npc(npc: String, body := 1, eye := "4_1", mouth := "3_2") -> void:
	if is_instance_valid(_npc_node) and _npc_node.get_meta("npc", "") == npc:
		return
	if is_instance_valid(_npc_node):
		_npc_node.queue_free()
	var dir := "npc_%s" % npc
	var man := _man(dir)
	if man.is_empty(): return
	var bkey := "npc_%s_body_%d" % [npc, body]
	var bi: Dictionary = man.get(bkey, {})
	if bi.is_empty(): return
	var S := Design.ASSET_SCALE
	var bw_px := float(bi.get("w", 219))
	var bh_px := float(bi.get("h", 351))
	var vis := _vis()
	_npc_node = Node2D.new()
	_npc_node.set_meta("npc", npc)
	_npc_node.position = Vector2(vis.x * 0.5, vis.y - BOX_H)
	_npc_node.z_index = 4
	add_child(_npc_node)
	var b := _spr(dir, bkey, S)
	if b == null: return
	b.position = Vector2(0, -bh_px * S * 0.5)
	_npc_node.add_child(b)
	for part in [["mouth", mouth, Vector2(103, 310)], ["eye", eye, Vector2(104, 346)]]:
		var key := "npc_%s_%s_%s" % [npc, part[0], part[1]]
		if not man.has(key): continue
		var ps := _spr(dir, key, 1.0)   # body 의 scale 을 상속 → 여기서 또 곱하지 않는다
		if ps == null: continue
		var pos: Vector2 = part[2]
		ps.position = Vector2(pos.x / S - bw_px * 0.5, bh_px * 0.5 - pos.y / S)
		b.add_child(ps)
	_npc_node.modulate.a = 0.0
	_npc_node.create_tween().tween_property(_npc_node, "modulate:a", 1.0, 0.2)

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
