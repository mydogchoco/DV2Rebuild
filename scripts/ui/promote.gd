extends Control
## 육성 — 원작 `PromoteScene` 이식. render 층(CLAUDE.md §8.1).
##
## BGM = **`music/bg_promote.mp3`** (PromoteScene.c:961~969 playBackground 바이트디코드).
##
## 원작 구조(docs/ref/orig_code/decomp/PromoteScene.c :: initWidget / onClickTab, docs/ref/audit/PromoteScene.md):
##   · 배경 `scene/promote/bg.jpg`
##   · 우상단 `scene/promote/cash_box` (앵커 1,1 @ right, top-15) + coin/diamond + `common/charge`
##   · TitleLayer(`scene/promote/title_bar.png`, 제목, X=`common/close_btn`)
##   · 탭 3개 — `tab_train_%s`(훈련) · `tab_latea_%s`(라티아=교배) · `tab_history_%s`(하늘둥지)
##     onClickTab: 0=showTraining · 1=showMate · 2=showHistory  (getEnabledBreed()==1 분기)
##   · NpcManager(`npc/dilis`) + BottomTextBox
##
## 탭 내용은 원작이 각각 별도 레이어다:
##   · TrainingLayer     — 캠프 3개(setCamp 1·2·3), x = cx-150-w / cx / cx+150+w, 잠금은 `common/lock`
##   · MateLayer         — 부모 2슬롯(`slot_bg`) + `heart` + 카운트다운 + 다이아 즉시완료
##   · DragonHistoryLayer— 떠나보낸 드래곤 목록 + 부활(callRevive)
##
## ⚠️ 원작의 훈련/교배/부활은 전부 `Request*`/`Response*` = **서버 구동**이라 수치가 유실됐다.
##    소요시간·경험치·비용은 `data/promote.json` 자작(§6 미확인 → 튜닝 노브 한 곳).

const TAB_TRAIN := 0
const TAB_MATE := 1
const TAB_NEST := 2

## 원작 initCamp: 캠프 3개를 화면 가운데 기준 -150-w / 0 / +150+w 에 놓는다.
const CAMP_GAP := 150.0

var _params: Dictionary = {}
var _tab := TAB_TRAIN
var _npc: NpcPortrait
var _box: BottomTextBox
var _tick: Timer

func enter(params: Dictionary = {}) -> void:
	Bgm.play("bg_promote")
	_params = params
	var want := String(params.get("tab", ""))
	match want:
		"mate": _tab = TAB_MATE
		"nest": _tab = TAB_NEST
		"train": _tab = TAB_TRAIN
	if is_inside_tree():
		_rebuild()

func _ready() -> void:
	# 캠프/교배 카운트다운 갱신(1초). 남은 시간은 실시간(Unix)으로 계산하므로 표시만 새로 그린다.
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.autostart = true
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	_rebuild()

func _cfg() -> Dictionary:
	return Data.promote

# ── 화면 ─────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in get_children():
		if c != _tick:
			c.queue_free()
	_npc = null
	_box = null
	_countdowns.clear()
	var vis := _vis()
	_build_bg()
	match _tab:
		TAB_TRAIN: _build_training(vis)
		TAB_MATE: _build_mate(vis)
		_: _build_nest(vis)
	_build_npc(vis)
	_build_wallet(vis)
	_build_title(vis)

func _build_bg() -> void:
	var p := "res://assets/converted/promote_bg/bg.jpg"
	var tr := TextureRect.new()
	if ResourceLoader.exists(p):
		tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.13, 0.16, 0.12)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

## 원작 TitleLayer("scene/promote/title_bar.png", 제목, X) + 탭 3개.
func _build_title(vis: Vector2) -> void:
	var bar := AtlasUI.spr("promote_ui", "scene_promote_title_bar", Design.ASSET_SCALE)
	if bar != null:
		var sz := AtlasUI.size_pt("promote_ui", "scene_promote_title_bar")
		bar.scale.x = vis.x / maxf(1.0, sz.x / Design.ASSET_SCALE)   # 가로만 화면 폭에 맞춘다
		bar.position = Vector2(vis.x * 0.5, sz.y * 0.5)
		bar.z_index = 9
		add_child(bar)
	var t := Label.new()
	t.text = "육성"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.35, 0.2, 0.06))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = Vector2(vis.x, 60)
	t.z_index = 10
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)

	var x := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE)
	if x != null:
		x.position = Vector2(vis.x - 42, 34)
		x.z_index = 11
		add_child(x)
	var xb := Button.new()
	xb.flat = true
	xb.size = Vector2(56, 56)
	xb.position = Vector2(vis.x - 70, 6)
	xb.z_index = 11
	xb.pressed.connect(_close)
	add_child(xb)

	# 탭 — 원작 TabMenu 규칙(앵커(0,1) @ (tabW+5)*i + 70, 아이콘은 탭 로컬 (tabW/2, 50)).
	var tabs := [
		["scene_promote_tab_train_kr", TAB_TRAIN],
		["scene_promote_tab_latea_kr", TAB_MATE],
		["scene_promote_tab_history_kr", TAB_NEST],
	]
	var tw := AtlasUI.size_pt("common_ui", "common_tab_bg").x
	var th := AtlasUI.size_pt("common_ui", "common_tab_bg").y
	for i in tabs.size():
		var key: String = tabs[i][0]
		var idx: int = tabs[i][1]
		var tx := 70.0 + (tw + 5.0) * i
		var bg := AtlasUI.spr("common_ui", "common_tab_bg" if idx != _tab else "common_tab_bg4",
			Design.ASSET_SCALE)
		if bg != null:
			bg.position = Vector2(tx + tw * 0.5, th * 0.5 - (0.0 if idx == _tab else 10.0))
			bg.z_index = 6
			add_child(bg)
		var lbl := AtlasUI.spr("promote_ui", key, Design.ASSET_SCALE)
		if lbl != null:
			lbl.position = Vector2(tx + tw * 0.5, th - 50.0 - (0.0 if idx == _tab else 10.0))
			lbl.z_index = 7
			add_child(lbl)
		var b := Button.new()
		b.flat = true
		b.size = Vector2(tw, th - 40.0)
		b.position = Vector2(tx, 20)
		b.z_index = 8
		b.pressed.connect(func(): _on_tab(idx))
		add_child(b)

func _on_tab(idx: int) -> void:
	if idx == _tab:
		return
	_tab = idx
	_rebuild()

## 원작 initWalletMoney/setMoney — `scene/promote/cash_box` + coin/diamond + `common/charge`(⊞).
func _build_wallet(vis: Vector2) -> void:
	var sz := AtlasUI.size_pt("promote_ui", "scene_promote_cash_box")
	var root := Control.new()
	root.size = sz
	# 원작은 앵커(1,1) @ (right, top-15) 인데, 우리 제목바(`title_bar` 81px→108pt)가 그 자리를
	# 덮어 숫자가 가려진다 → 제목바 아래로 내린다.
	root.position = Vector2(vis.x - sz.x - 8.0, 96.0)
	root.z_index = 8
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := AtlasUI.spr("promote_ui", "scene_promote_cash_box", Design.ASSET_SCALE)
	if bg != null:
		bg.position = sz * 0.5
		root.add_child(bg)
	var rows := [["common_coin_small1", AtlasUI.comma(UserDB.gold())],
		["common_diamond_small1", AtlasUI.comma(UserDB.diamond())]]
	for i in rows.size():
		var ic := AtlasUI.spr("common_ui", String(rows[i][0]), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(46.0, sz.y * 0.5 + (i - 0.5) * 48.0)
			root.add_child(ic)
		var l := Label.new()
		l.text = String(rows[i][1])
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.04))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(74.0, sz.y * 0.5 + (i - 0.5) * 48.0 - 14.0)
		l.size = Vector2(sz.x - 84.0, 28.0)
		root.add_child(l)

## 원작 setTalker — NPC 는 `npc/dilis`(딜리스). 배치는 오른쪽.
func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("dilis", _pick_emotion("dilis"))
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		_npc.position = Vector2(vis.x - 150.0, vis.y)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - 300.0
	_box.z_index = 12
	add_child(_box)
	_box.clicked.connect(func(): _say(_promote_talk()))
	_say(_promote_talk())

## 그 NPC가 가진 표정 세트 중 무작위(`data/npc_face.json`).
func _pick_emotion(npc: String) -> int:
	# 아틀라스가 가진 표정 세트에서 고른다(좌표표 기준으로 고르면 종류가 줄어든다).
	var nums := AtlasUI.npc_emotions(npc)
	return int(nums[randi() % nums.size()]) if not nums.is_empty() else 1

## 원작 대사 — `<NurtureTalk1~8>`(육성) / `<NurtureBreedTalk1~3>`(교배 탭).
## `data/npc_talk.json`(build_npc_talk.py) 에서 읽는다 — 하드코딩하지 않는다.
func _promote_talk() -> String:
	var screen: Dictionary = Data.npc_talk.get("screen", {})
	var pool: Array = (screen.get("promote.breed_talk", {}) as Dictionary).get("lines", []) if _tab == TAB_MATE 		else (screen.get("promote.talk", {}) as Dictionary).get("lines", [])
	if pool.is_empty():
		pool = Data.npc_talk.get("idle", {}).get("dilis", [])
	if pool.is_empty():
		return ""
	return String(pool[randi() % pool.size()])

func _npc_name() -> String:
	var per = Data.npc_lines_doc.get("dilis", null)
	if per is Dictionary and per.has("name"):
		return String(per["name"])
	return "딜리스"

## 대사 출력. 원작 `setTalker` 는 **대사와 표정이 한 묶음**이라 줄마다 얼굴이 바뀐다.
## `emo` > 0 이면 그 표정으로, 0 이면 현재 표정을 유지하되 반응 표정이면 기본(1)으로 되돌린다
## (원작 `setTextAgain` 의 `if (getEmotion() == 4) setTalker(..., 1, ...)` 분기).
##
## 반응 표정 = 원작 `MateLayer` 가 결과에 쓰는 **7**(딜리스는 아틀라스에 1·2·4·7 이 있다).
const REACTION_EMOTIONS := [4, 7]

func _say(line: String, emo := 0) -> void:
	if not is_instance_valid(_box):
		return
	if is_instance_valid(_npc):
		if emo > 0:
			_npc.set_emotion(emo)
		elif REACTION_EMOTIONS.has(_npc.emotion):
			_npc.set_emotion(1)
	_box.show_text(_npc_name(), line)
	if is_instance_valid(_npc):
		_npc.set_talking(true)
		if not _box.finished.is_connected(_stop_talk):
			_box.finished.connect(_stop_talk)

func _stop_talk() -> void:
	if is_instance_valid(_npc):
		_npc.set_talking(false)

func _toast(msg: String, emo := 0) -> void:
	_say(msg, emo)

# ══════════════════════════ 훈련(TrainingLayer) ══════════════════════════
## 캠프 상태는 UserDB pmeta `training` 에 둔다:
##   { "<camp>": {"uid": int, "prog": int, "end": unix_sec} }
func _camps() -> Dictionary:
	var d = UserDB.get_pmeta("training", {})
	return d if d is Dictionary else {}

func _set_camps(d: Dictionary) -> void:
	UserDB.set_pmeta("training", d)

func _programs() -> Array:
	return _cfg().get("training", {}).get("programs", [])

func _unlock_cost(camp: int) -> int:
	var arr: Array = _cfg().get("training", {}).get("unlock_cost_dia", [0, 30, 80])
	return int(arr[camp]) if camp < arr.size() else 0

func _camp_unlocked(camp: int) -> bool:
	if _unlock_cost(camp) <= 0:
		return true
	var u = UserDB.get_pmeta("training_unlocked", [])
	return (u is Array) and (camp in u)

func _build_training(vis: Vector2) -> void:
	var n := int(_cfg().get("training", {}).get("camps", 3))
	var nest := AtlasUI.size_pt("promote_ui", "scene_promote_nest1")
	var cx := vis.x * 0.5
	var cy := vis.y * 0.5 - 20.0
	var st := _camps()
	for i in n:
		# 원작 initCamp 배치: cx-150-w / cx / cx+150+w  (w = 캠프 스프라이트 폭)
		var x := cx + float(i - 1) * (CAMP_GAP + nest.x)
		_build_camp(i, Vector2(x, cy), st.get(str(i), {}))

func _build_camp(camp: int, pos: Vector2, slot: Dictionary) -> void:
	var unlocked := _camp_unlocked(camp)
	var busy := not slot.is_empty()
	# nest1=빈 둥지 · nest2=사용 중 · nest3=잠김(회색). 근거: 프레임 실물(회색/금색 대비).
	var frame := "scene_promote_nest3" if not unlocked else ("scene_promote_nest2" if busy else "scene_promote_nest1")
	var s := AtlasUI.spr("promote_ui", frame, Design.ASSET_SCALE)
	if s != null:
		s.position = pos
		s.z_index = 2
		add_child(s)
		_camp_entry_anim(s, pos, camp)

	if not unlocked:
		var lock := AtlasUI.spr("common_ui", "common_lock", Design.ASSET_SCALE)
		if lock != null:
			lock.position = pos
			lock.z_index = 3
			add_child(lock)
		_camp_label(pos, "%d 💎 해금" % _unlock_cost(camp))
		_camp_button(pos, func(): _unlock_camp(camp))
		return

	if busy:
		var remain := int(slot.get("end", 0)) - int(Time.get_unix_time_from_system())
		var d: Dictionary = UserDB.get_dragon(int(slot.get("uid", 0)))
		var nm := _dragon_label(d)
		# 훈련 중인 드래곤을 둥지 위에 세운다(스파인 대기 모션).
		_camp_dragon(pos, int(slot.get("uid", 0)))
		if remain > 0:
			var lb := _camp_label(pos, "%s\n%s 남음" % [nm, _hms(remain)])
			_register_countdown(lb, int(slot.get("end", 0)), nm + "\n%s 남음")
			_camp_button(pos, func(): _toast("%s 는 아직 훈련 중이에요." % nm))
		else:
			_camp_label(pos, "%s\n훈련 완료!" % nm)
			_camp_button(pos, func(): _collect_camp(camp))
	else:
		_camp_label(pos, "비어 있음")
		_camp_button(pos, func(): _open_send(camp))

## 원작 initCamp 의 캠프 등장 연출 — **반복이 아니라 1회성**이다.
##   CCSequence( Delay(0.3×i), MoveBy(0, +10), MoveBy(0.2, (0,-10)),
##               ScaleBy(0.2, 1.05,0.95), ScaleBy(0.2, 0.95,1.05), ScaleBy(0.2, 1,1) ) + FadeIn(0.2)
## = 위에서 10 떨어지며 착지 스쿼시. (2026-07-28 검수: 둥지가 계속 떠다니던 건 우리 버그였다)
func _camp_entry_anim(node: Sprite2D, pos: Vector2, camp: int) -> void:
	var S := Design.ASSET_SCALE
	node.position = pos - Vector2(0, 10.0)     # Cocos +10 = 위쪽
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_interval(0.3 * float(camp))
	tw.set_parallel(true)
	tw.tween_property(node, "position:y", pos.y, 0.2)
	tw.tween_property(node, "modulate:a", 1.0, 0.2)
	tw.set_parallel(false)
	tw.tween_property(node, "scale", Vector2(S * 1.05, S * 0.95), 0.2)   # 착지 스쿼시
	tw.tween_property(node, "scale", Vector2(S * 0.95, S * 1.05), 0.2)   # 되튐
	tw.tween_property(node, "scale", Vector2(S, S), 0.2)

func _camp_label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(1, 0.97, 0.86))
	l.add_theme_color_override("font_outline_color", Color(0.2, 0.14, 0.05))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(220, 60)
	l.position = pos + Vector2(-110, 34)
	l.z_index = 4
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

## 드래곤 스파인 대기 모션 노드. 우리 변환 산출물 = `scenes/dragons/dragon_<id>_<stage>.tscn`
## (cave.gd `DRAGON_SCENE` 과 같은 규약). 없으면 null.
func _dragon_spine(uid: int, scale := 1.0) -> Node2D:
	var d: Dictionary = UserDB.get_dragon(uid)
	# 🔴 2026-08-07 — 개체의 상속 art_id(커스텀 종 600·700 은 자기 스파인이 없다).
	var id := Icons.art_id_of(d)
	for stage in [_growth_stage(d), "adult", "child", "baby"]:
		var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, stage]
		if ResourceLoader.exists(path):
			var n := (load(path) as PackedScene).instantiate() as Node2D
			if n != null:
				n.scale = Vector2(scale, scale)
			return n
	return null

## 훈련 중인 캠프 위에 드래곤을 세운다.
## ⚠️ 원작 `TrainingLayer::setCamp` 의 디컴프에는 둥지(`nest1/3`) + 라벨판(`train_box1/2`) +
##    잠금(`common/lock`) 뿐이고 드래곤을 그리는 코드가 없다. 사용자 실측 기억(2026-07-28)에
##    따라 올려 둔다 — 원작 근거가 나오면 이 함수부터 확인할 것.
func _camp_dragon(pos: Vector2, uid: int) -> void:
	var n := _dragon_spine(uid, 0.45)
	if n == null:
		return
	n.position = pos - Vector2(0, 10.0)
	n.z_index = 3
	add_child(n)

func _camp_button(pos: Vector2, cb: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.size = Vector2(180, 120)
	b.position = pos - Vector2(90, 70)
	b.z_index = 5
	b.pressed.connect(cb)
	add_child(b)

func _unlock_camp(camp: int) -> void:
	var cost := _unlock_cost(camp)
	if not UserDB.spend("diamond", cost):
		_toast("다이아가 부족해요.")
		return
	var u = UserDB.get_pmeta("training_unlocked", [])
	var arr: Array = (u as Array).duplicate() if u is Array else []
	arr.append(camp)
	UserDB.set_pmeta("training_unlocked", arr)
	_rebuild()

## 훈련 보내기 — 원작 `callSelectDragon` → `callSelectTraining` 2단계.
## 둘 다 같은 `TrainingSelectLayer`(320×461 카드 가로목록)를 쓴다.
func _open_send(camp: int) -> void:
	var picks: Array = []
	for d in UserDB.dragons():
		if UserDB.is_egg(d) or _uid_in_camp(int(d.get("uid", 0))):
			continue
		var uid := int(d.get("uid", 0))
		var lv := int(d.get("level", 1))
		picks.append({
			"kind": "dragon",
			"title": _dragon_label(d),
			"big": "%d" % lv,
			"desc": Icons.species_name(int(d.get("id", 0))),
			"spine_uid": uid,
			"value": uid,
		})
	if picks.is_empty():
		_toast("보낼 수 있는 드래곤이 없어요.")
		return
	_open_select("훈련 보낼 드래곤", picks, func(uid):
		var d0: Dictionary = UserDB.get_dragon(int(uid))
		var lv0 := int(d0.get("level", 1))
		var progs: Array = []
		for i in _programs().size():
			var pg: Dictionary = _programs()[i]
			var mins := int(pg.get("minutes", 0))
			progs.append({
				"kind": "training",
				"title": String(pg.get("name", "")),
				"big": "EXP %s" % AtlasUI.comma(int(pg.get("exp", 0))),
				# 원작 표기 그대로 `(hh : mm : ss)` (TrainingSelectLayer::tableCellAtIndex)
				"desc": "(%02d : %02d : %02d)" % [mins / 60, mins % 60, 0],
				"icon_dir": "promote_ui",
				"icon_key": "scene_promote_%s" % String(pg.get("icon", "")),
				"lv_from": lv0,
				"lv_to": _level_after(int(uid), int(pg.get("exp", 0))),
				"cost": AtlasUI.comma(int(pg.get("cost_gold", 0))),
				"cost_cur": "gold",
				"value": i,
			})
		_open_select("훈련 종류", progs, func(pi): _send_camp(camp, int(uid), int(pi))))

## 훈련을 마쳤을 때 도달할 레벨(원작 셀의 `LV a ▶ LV b` 미리보기).
## 원작은 `select level from info_exp where exp <= %d ...` 로 구한다 —
## 우리 대응 데이터는 `data/level_curve.json`(LevelSystem).
func _level_after(uid: int, gain: int) -> int:
	var d: Dictionary = UserDB.get_dragon(uid)
	var lv := int(d.get("level", 1))
	var cap := LevelSystem.cap_for(Data.level_curve, bool(d.get("awakened", false)))
	var cur := int(d.get("exp", 0)) + gain
	while lv < cap:
		var need := LevelSystem.exp_to_next(Data.level_curve, lv)
		if need <= 0 or cur < need:
			break
		cur -= need
		lv += 1
	return lv

func _uid_in_camp(uid: int) -> bool:
	for v in _camps().values():
		if int((v as Dictionary).get("uid", 0)) == uid:
			return true
	return false

func _send_camp(camp: int, uid: int, prog: int) -> void:
	var p: Dictionary = _programs()[prog]
	# 원작 TrainingSelectCell 이 셀 하단에 비용을 표시한다 → 실제로 차감한다.
	var cost := int(p.get("cost_gold", 0))
	if cost > 0 and not UserDB.spend("gold", cost):
		_toast("골드가 부족해요.")
		return
	var st := _camps().duplicate(true)
	st[str(camp)] = {"uid": uid, "prog": prog,
		"end": int(Time.get_unix_time_from_system()) + int(p.get("minutes", 0)) * 60}
	_set_camps(st)
	_rebuild()
	_toast("%s 훈련을 시작했어요." % String(p.get("name", "")))

func _collect_camp(camp: int) -> void:
	var st := _camps().duplicate(true)
	var slot: Dictionary = st.get(str(camp), {})
	if slot.is_empty():
		return
	st.erase(str(camp))
	_set_camps(st)
	var uid := int(slot.get("uid", 0))
	var p: Dictionary = _programs()[clampi(int(slot.get("prog", 0)), 0, _programs().size() - 1)]
	var exp_gain := int(p.get("exp", 0))
	# logic 층에 결과만 맡긴다 — 레벨 판정은 LevelSystem, 표시는 여기서.
	UserDB.add_exp(uid, exp_gain)
	var d: Dictionary = UserDB.get_dragon(uid)
	_rebuild()
	_toast("%s 가 훈련을 마쳤어요! EXP +%s" % [String(d.get("name", "드래곤")), AtlasUI.comma(exp_gain)])

# ══════════════════════════ 교배(MateLayer) ══════════════════════════════
## 상태는 pmeta `mate` = {"a": uid, "b": uid, "end": unix, "egg": itemkey}
func _mate() -> Dictionary:
	var d = UserDB.get_pmeta("mate", {})
	return d if d is Dictionary else {}

func _build_mate(vis: Vector2) -> void:
	var cfg: Dictionary = _cfg().get("mate", {})
	var st := _mate()
	var cx := vis.x * 0.5
	var cy := vis.y * 0.5 - 30.0
	# 부모 2슬롯 — 원작 `scene/promote/slot_bg`, 가운데 `heart`.
	for i in 2:
		var sx := cx + (-1.0 if i == 0 else 1.0) * 130.0
		var sl := AtlasUI.spr("promote_ui", "scene_promote_slot_bg", Design.ASSET_SCALE)
		if sl != null:
			sl.position = Vector2(sx, cy)
			sl.z_index = 2
			add_child(sl)
		var uid := int(st.get("a" if i == 0 else "b", 0))
		var nm := "빈 슬롯"
		if uid > 0:
			nm = String(UserDB.get_dragon(uid).get("name", "드래곤"))
			var por := _portrait(uid)
			if por != null:
				por.position = Vector2(sx, cy)
				por.z_index = 3
				add_child(por)
		_camp_label(Vector2(sx, cy), nm)
		if st.is_empty():
			var slot_i := i
			_camp_button(Vector2(sx, cy), func(): _pick_parent(slot_i))
	var heart := AtlasUI.spr("promote_ui", "scene_promote_heart", Design.ASSET_SCALE)
	if heart != null:
		heart.position = Vector2(cx, cy - 10.0)
		heart.z_index = 4
		add_child(heart)

	var act := Button.new()
	act.size = Vector2(240, 50)
	act.position = Vector2(cx - 120, cy + 120)
	act.z_index = 6
	if st.is_empty():
		act.text = "교배 시작 (%s G)" % AtlasUI.comma(int(cfg.get("cost_gold", 0)))
		act.pressed.connect(_start_mate)
	else:
		var remain := int(st.get("end", 0)) - int(Time.get_unix_time_from_system())
		if remain > 0:
			act.text = "즉시 완료 (%d 💎) — %s 남음" % [int(cfg.get("instant_dia", 0)), _hms(remain)]
			act.pressed.connect(_instant_mate)
		else:
			act.text = "알 받기"
			act.pressed.connect(_take_egg)
	add_child(act)

var _pending_parents := {}
func _pick_parent(slot: int) -> void:
	var cfg: Dictionary = _cfg().get("mate", {})
	var minlv := int(cfg.get("min_level", 1))
	var picks: Array = []
	for d in UserDB.dragons():
		if UserDB.is_egg(d) or int(d.get("level", 1)) < minlv:
			continue
		var uid := int(d.get("uid", 0))
		if _pending_parents.values().has(uid):
			continue
		picks.append({
			"kind": "dragon",
			"title": _dragon_label(d),
			"big": "%d" % int(d.get("level", 1)),
			"desc": Icons.species_name(int(d.get("id", 0))),
			"spine_uid": uid,
			"value": uid,
		})
	if picks.is_empty():
		_toast("Lv %d 이상인 드래곤이 필요해요." % minlv)
		return
	_open_select("부모 드래곤", picks, func(uid):
		_pending_parents[slot] = int(uid)
		_rebuild_mate_preview())

func _rebuild_mate_preview() -> void:
	# 아직 시작 전이므로 pmeta 는 건드리지 않고 화면만 다시 그린다.
	_rebuild()

func _start_mate() -> void:
	if _pending_parents.size() < 2:
		_toast("부모 드래곤 두 마리를 골라 주세요.")
		return
	var cfg: Dictionary = _cfg().get("mate", {})
	if not UserDB.spend("gold", int(cfg.get("cost_gold", 0))):
		_toast("골드가 부족해요.")
		return
	var a := int(_pending_parents[0])
	var b := int(_pending_parents[1])
	UserDB.set_pmeta("mate", {"a": a, "b": b,
		"end": int(Time.get_unix_time_from_system()) + int(cfg.get("minutes", 60)) * 60,
		"egg": _mate_result(a, b)})
	_pending_parents.clear()
	_rebuild()

## 결과 알 — data/combine_egg.json 레시피 우선, 없으면 부모 한쪽 속성의 기본 속성알.
func _mate_result(a: int, b: int) -> String:
	var ea := _element_egg(a)
	var eb := _element_egg(b)
	for r in Data.combine_egg.get("recipes", []):
		var mats: Array = r.get("materials", [])
		if mats.size() == 2 and ((mats[0] == ea and mats[1] == eb) or (mats[0] == eb and mats[1] == ea)):
			return String(r.get("target", ea))
	return ea if randi() % 2 == 0 else eb

func _element_egg(uid: int) -> String:
	var d: Dictionary = UserDB.get_dragon(uid)
	var def: Dictionary = Data.get_dragon(int(d.get("id", 0)))
	var el := String(def.get("element", "fire"))
	# dragons.json 은 `ground` 를 쓰고 알 아이템 키도 `mall_ground_egg` 로 맞다.
	var key := "mall_%s_egg" % el
	return key if Data.items.has(key) else "mall_fire_egg"

func _instant_mate() -> void:
	var cfg: Dictionary = _cfg().get("mate", {})
	if not UserDB.spend("diamond", int(cfg.get("instant_dia", 0))):
		_toast("다이아가 부족해요.")
		return
	var st := _mate().duplicate()
	st["end"] = int(Time.get_unix_time_from_system())
	UserDB.set_pmeta("mate", st)
	_rebuild()

func _take_egg() -> void:
	var st := _mate()
	var key := String(st.get("egg", ""))
	if key != "":
		UserDB.add_item(key, 1)
	UserDB.set_pmeta("mate", {})
	_rebuild()
	# 원작 `MateLayer` 는 결과 대사에 표정 7 을 쓴다 — 다음 대사에서 1 로 돌아온다.
	_toast("%s 을(를) 얻었어요!" % Data.item_name(key), 7)

# ══════════════════════ 하늘둥지(DragonHistoryLayer) ══════════════════════
## 원작 [육성]-[하늘둥지] 의 **본래 기능은 '드래곤의 고삐'로 맡긴 드래곤 회수**다:
##   `TutorialAnswer1_6` — "드래곤의 고삐를 사용하여 동굴에 있는 드래곤을 하늘둥지로 보낼 수 있다.
##    … [육성]-[하늘둥지]탭에서 다시 동굴로 소환 할 수 있다."
##   `NurtureHistoryMsg2` — "하늘둥지에서 맡겨 놓은 드래곤을 찾아올 수 있습니다! … 소량의 보석이 소모"
##   `AchieveMsg5` — "해당 드래곤을 하늘둥지에서 불러오시겠습니까?" · `AchieveError3` — "보관 중인 드래곤이 없습니다."
##   ⇒ 보관은 동굴(고삐 아이템, `CaveToastMsg14`), 회수는 여기. 2026-07-30 배선.
## 🟡 아래 "떠나보낸 드래곤 부활" 목록은 원작 기준 **라테아 탭** 기능이다
##   (`TutorialAnswer1_6`: "라테아는 승천으로 사라진 드래곤들이 모여 있으며 … 다이아를 소비하여 소환").
##   우리 탭 배치(라티아=교배)를 바꾸는 건 별건이라 일단 여기 남겨 둔다.
func _build_nest(vis: Vector2) -> void:
	var recs = UserDB.get_pmeta("sky_nest", [])
	var list: Array = recs if recs is Array else []
	var stored: Array = UserDB.storage_dragons()
	var panel := AtlasUI.nine("ninepatch_ui", "9patch_popup4",
		Vector2(vis.x - 380.0, vis.y - 300.0), Rect2())
	if panel != null:
		panel.position = Vector2(60, 110)
		add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(90, 150)
	scroll.size = Vector2(vis.x - 440.0, vis.y - 400.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.z_index = 3
	add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(scroll.size.x - 20, 0)
	scroll.add_child(col)
	if list.is_empty() and stored.is_empty():
		var l := Label.new()
		l.text = "맡겨 둔 드래곤이 없어요."          # 원작 AchieveError3 "보관 중인 드래곤이 없습니다."
		l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
		col.add_child(l)
		return
	# ① 보관 중인 드래곤(동굴에서 '드래곤의 고삐'로 맡긴 것) → 다시 동굴로
	if not stored.is_empty():
		col.add_child(_nest_header("보관 중인 드래곤"))
		var take := int(_cfg().get("sky_nest", {}).get("retrieve_cost_dia", 5))
		for d in stored:
			col.add_child(_stored_row(d, take))
	# ② 떠나보낸(승천) 드래곤 부활 — 🟡 원작 기준 라테아 탭 기능(위 주석)
	if not list.is_empty():
		if not stored.is_empty():
			col.add_child(_nest_header("떠나보낸 드래곤"))
		var cost := int(_cfg().get("sky_nest", {}).get("revive_cost_gold", 50000))
		for i in list.size():
			var r: Dictionary = list[i]
			col.add_child(_nest_row(i, r, cost))

## 목록 구분 머리글.
func _nest_header(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	l.custom_minimum_size = Vector2(0, 26)
	return l

## 보관 드래곤 한 줄 — 원작 `AchieveMsg5`("하늘둥지에서 불러오시겠습니까?") 흐름.
## 비용은 "소량의 보석"(NurtureHistoryMsg2)만 확인되고 액수는 서버 유실 → data/promote.json 노브.
func _stored_row(d: Dictionary, cost: int) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(560, 56)
	var bar := AtlasUI.nine("promote_ui", "scene_promote_history_box", Vector2(560, 56), Rect2())
	if bar != null:
		row.add_child(bar)
	var uid := int(d.get("uid", -1))
	var nm := Icons.species_name(int(d.get("id", 1)))
	var l := Label.new()
	l.text = "%s  ·  Lv %d" % [nm, int(d.get("level", 1))]
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.28, 0.18, 0.06))
	l.position = Vector2(16, 16); l.size = Vector2(360, 26)
	row.add_child(l)
	var b := Button.new()
	b.text = "소환 💎%d" % cost
	b.size = Vector2(160, 40); b.position = Vector2(388, 8)
	b.pressed.connect(func(): _summon_stored(uid, nm, cost))
	row.add_child(b)
	return row

## 보관 → 동굴. 실패 사유는 둘 — 다이아 부족 / 동굴 슬롯 부족.
func _summon_stored(uid: int, nm: String, cost: int) -> void:
	if cost > 0 and not UserDB.spend("diamond", cost):
		_toast("다이아가 부족해요.")
		return
	if not UserDB.unstore_dragon(uid):
		if cost > 0:
			UserDB.add_currency("diamond", cost)     # 실패했으니 되돌린다
		_toast("동굴에 자리가 없어요.")
		return
	_rebuild()
	_toast("%s 이(가) 동굴로 돌아왔어요!" % nm)

func _nest_row(idx: int, r: Dictionary, cost: int) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(560, 56)
	var bar := AtlasUI.nine("promote_ui", "scene_promote_history_box", Vector2(560, 56), Rect2())
	if bar != null:
		row.add_child(bar)
	var l := Label.new()
	l.text = "%s  ·  Lv %d  ·  %s" % [String(r.get("name", "드래곤")), int(r.get("level", 1)),
		String(r.get("date", ""))]
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.28, 0.18, 0.06))
	l.position = Vector2(16, 16)
	l.size = Vector2(360, 26)
	row.add_child(l)
	var b := Button.new()
	b.text = "부활 %s G" % AtlasUI.comma(cost)
	b.size = Vector2(160, 40)
	b.position = Vector2(388, 8)
	b.pressed.connect(func(): _revive(idx, cost))
	row.add_child(b)
	return row

## 원작 DragonHistoryLayer::callRevive — 떠나보낸 드래곤을 되살린다.
func _revive(idx: int, cost: int) -> void:
	var recs = UserDB.get_pmeta("sky_nest", [])
	if not (recs is Array) or idx >= (recs as Array).size():
		return
	if not UserDB.spend("gold", cost):
		_toast("골드가 부족해요.")
		return
	var arr: Array = (recs as Array).duplicate()
	var r: Dictionary = arr[idx]
	arr.remove_at(idx)
	UserDB.set_pmeta("sky_nest", arr)
	UserDB.add_dragon(int(r.get("id", 1)), int(r.get("level", 1)))
	_rebuild()
	_toast("%s 이(가) 돌아왔어요!" % String(r.get("name", "드래곤")))

# ── 공통 ─────────────────────────────────────────────────────────────────
## ⚠️ 매초 `_rebuild()` 를 부르면 대사가 다시 뽑히고 둥지 등장 연출이 반복된다
##    (2026-07-28 검수 지적). 카운트다운은 **등록된 라벨의 텍스트만** 갈아 끼운다.
##    `_countdowns` = [{node, end, fmt}] — `_rebuild` 때마다 비우고 다시 등록한다.
var _countdowns: Array = []

func _register_countdown(node: Label, end_unix: int, fmt: String) -> void:
	_countdowns.append({"node": node, "end": end_unix, "fmt": fmt})

func _on_tick() -> void:
	var now := int(Time.get_unix_time_from_system())
	var done := false
	for c in _countdowns:
		var n: Label = c["node"]
		if not is_instance_valid(n):
			continue
		var remain := int(c["end"]) - now
		if remain <= 0:
			done = true                     # 완료된 순간 한 번만 다시 그린다
			continue
		n.text = String(c["fmt"]) % _hms(remain)
	if done:
		_countdowns.clear()
		_rebuild()

func _hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]

## 드래곤 박스 썸네일 — 원작 `dragon/dragon_<id>.png` 의 `box_<stage>` 프레임.
## 변환 산출물은 `assets/converted/portrait_<id>/dragon_dragon_<id>_box_<stage>.tres`
## (cave.gd `_portrait_sprite` 와 같은 규약).
func _portrait_tex(uid: int) -> Texture2D:
	var d: Dictionary = UserDB.get_dragon(uid)
	var id := int(d.get("id", 0))
	for stage in [_growth_stage(d), "adult", "child", "baby"]:
		var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_%s.tres" % [id, id, stage]
		if ResourceLoader.exists(p):
			return load(p)
	return null

## 레벨 → 성장 단계(원작 Growth 규칙). Growth 오토로드가 있으면 그쪽을 쓴다.
func _growth_stage(d: Dictionary) -> String:
	var lv := int(d.get("level", 1))
	return "adult" if lv >= 35 else ("child" if lv >= 10 else "baby")

## 드래곤 표시 이름 — 개체 이름이 비어 있으면 종족 이름(dragons.json).
func _dragon_label(d: Dictionary) -> String:
	var nm := String(d.get("name", ""))
	if nm != "" and nm != "드래곤":
		return nm
	return Icons.name_of(d)

func _portrait(uid: int) -> Sprite2D:
	var t := _portrait_tex(uid)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = AtlasUI.pma()
	s.scale = Vector2(0.8, 0.8)
	return s

## 원작 `TrainingSelectLayer` 이식 — 훈련 보낼 드래곤/훈련 종류를 **카드 가로 목록**에서 고른다.
##
## 근거(docs/ref/orig_code/decomp/TrainingSelectLayer.c :: init · tableCellSizeForIndex,
##      docs/ref/orig_code/decomp/TrainingSelectCell.c :: initWithSize):
##   · 팝업 배경 = `PopupLayer::setContentSprite("9patch/popup4.png", capInsets)`
##   · 닫기 X   = (w-50, h-50) · 제목 = (w/2, h-45)
##   · 목록 틀  = `9patch/scroll_box.png` Scale9, contentSize (w-100, 481), 앵커(0,0) @ (50,40)
##   · 표      = CCTableView (w-20, h-20) @ (10,10) — **가로 스크롤**
##   · 셀      = 320×461. 배경 `common/bg/stat_box2` + `common/backlight3`(w/2, h/2+60)
##              + 이름(w/2, h-50) + 큰 숫자(font_heal, w/2, h/2-20) + 설명(w/2, h/2-60)
##              + `LV n` ▶ `LV n+1`  (`common/btn_arrow2` 가 가운데, 라벨이 ±30)
##              + 비용(w/2-20, 53)
##   ⚠️ `common/bg/stat_box2` 는 `common/bg/` 부재 계열이라(CLAUDE.md §10) `9patch/train_box4` 로 대체.
const SEL_CELL := Vector2(320.0, 461.0)

## items = [{title, big, desc, lv_from, lv_to, cost, icon_dir, icon_key, value}]
func _open_select(title: String, items: Array, on_pick: Callable) -> void:
	var vis := _vis()
	var lay := CanvasLayer.new()
	lay.layer = 40
	add_child(lay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	lay.add_child(dim)

	var BW := minf(vis.x - 60.0, 900.0)
	var BH := minf(vis.y - 40.0, 600.0)
	var origin := Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	var win := AtlasUI.nine("ninepatch_ui", "9patch_popup4", Vector2(BW, BH), Rect2())
	if win != null:
		win.position = origin
		lay.add_child(win)

	# 제목 — 원작 (w/2, h-45)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(1, 0.93, 0.7))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(BW, 34)
	t.position = origin + Vector2(0, 45.0 - 17.0)
	lay.add_child(t)

	# 목록 틀 — 원작 `9patch/scroll_box`, 앵커(0,0) @ (50,40), 높이 481(팝업보다 크면 줄인다)
	var box_w := BW - 100.0
	var box_h := minf(481.0, BH - 100.0)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(box_w, box_h), Rect2())
	if box != null:
		box.position = origin + Vector2(50.0, BH - 40.0 - box_h)
		lay.add_child(box)

	var scroll := ScrollContainer.new()
	scroll.position = origin + Vector2(60.0, BH - 30.0 - box_h)
	scroll.size = Vector2(box_w - 20.0, box_h - 20.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	lay.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	scroll.add_child(strip)

	var ch := minf(SEL_CELL.y, scroll.size.y - 8.0)
	for it in items:
		strip.add_child(_select_cell(it, Vector2(SEL_CELL.x, ch), func(v):
			lay.queue_free()
			on_pick.call(v)))

	# 닫기 X — 원작 (w-50, h-50)
	var x := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE)
	if x != null:
		x.position = origin + Vector2(BW - 50.0, 50.0)
		lay.add_child(x)
	var xb := Button.new()
	xb.flat = true
	xb.size = Vector2(56, 56)
	xb.position = origin + Vector2(BW - 78.0, 22.0)
	xb.pressed.connect(func(): lay.queue_free())
	lay.add_child(xb)

## 원작은 선택창 셀이 **두 클래스**다 — 드래곤은 `DragonSelectCell`, 훈련은 `TrainingSelectCell`.
## 둘 다 320×461 이지만 내부 배치가 다르므로 따로 그린다(사용자 확정 2026-07-28: 원작대로).
## `it.kind` 로 분기한다.
func _select_cell(it: Dictionary, sz: Vector2, on_pick: Callable) -> Control:
	var card := Control.new()
	card.custom_minimum_size = sz
	# 셀 배경 — 원작은 `common/bg/stat_box2`(드래곤)/동일 프레임(훈련)인데 `common/bg/` 계열이
	# 추출 에셋에 없다(CLAUDE.md §10) → `9patch/train_box4` 로 대체.
	var bg := AtlasUI.nine("ninepatch_ui", "9patch_train_box4", sz, Rect2())
	if bg != null:
		card.add_child(bg)
	if String(it.get("kind", "training")) == "dragon":
		_fill_dragon_cell(card, it, sz)
	else:
		_fill_training_cell(card, it, sz)
	var b := Button.new()
	b.flat = true
	b.size = sz
	var v = it.get("value", 0)
	b.pressed.connect(func(): on_pick.call(v))
	card.add_child(b)
	return card

## 원작 `DragonSelectCell::initWithSize` 이식.
##   · `common/shadow`            @ (w/2, h/2 + 30)      [Cocos y-up]
##   · `scene/promote/train_box1` @ (w/2, h/2 - 30)      = 이름판
##       ↳ 이름 라벨 anchor(0,0.5) @ (20, 판높이/2), scale 0.6  + TTF 18 라벨 @ (60, …)
##   · 수치 한 쌍 — anchor(1,0.5) @ (120,160) / anchor(0,0.5) @ (140,160), scale 0.6 / 0.8
## 드래곤 자체는 그림자 위에 선다(원작이 그림자를 까는 이유).
func _fill_dragon_cell(card: Control, it: Dictionary, sz: Vector2) -> void:
	var cy := sz.y * 0.5
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	if sh != null:
		sh.position = Vector2(sz.x * 0.5, cy - 30.0)
		sh.modulate = Color(1, 1, 1, 0.55)
		card.add_child(sh)
	var sp := _dragon_spine(int(it.get("spine_uid", 0)), 0.6)
	if sp != null:
		sp.position = Vector2(sz.x * 0.5, cy - 34.0)     # 발밑을 그림자에 맞춘다
		sp.z_index = 0
		sp.z_as_relative = false
		card.add_child(sp)

	# 이름판 — 원작 train_box1(213×38)
	var pw := AtlasUI.size_pt("promote_ui", "scene_promote_train_box1")
	var plate := AtlasUI.spr("promote_ui", "scene_promote_train_box1", Design.ASSET_SCALE)
	if plate != null:
		plate.position = Vector2(sz.x * 0.5, cy + 30.0)
		plate.z_index = 10
		card.add_child(plate)
	var nm := Label.new()
	nm.text = String(it.get("title", ""))
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color(1, 0.97, 0.86))
	nm.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.03))
	nm.add_theme_constant_override("outline_size", 5)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.size = Vector2(pw.x - 30.0, 26.0)
	nm.position = Vector2(sz.x * 0.5 - pw.x * 0.5 + 20.0, cy + 30.0 - 13.0)
	nm.z_index = 20
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(nm)

	# 수치 한 쌍 — 원작 (120,160) 우측정렬 / (140,160) 좌측정렬 [Cocos y-up]
	var ry := sz.y - 160.0
	var lk := Label.new()
	lk.text = "레벨"
	lk.add_theme_font_size_override("font_size", 15)
	lk.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
	lk.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.03))
	lk.add_theme_constant_override("outline_size", 4)
	lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lk.size = Vector2(120.0, 22.0)
	lk.position = Vector2(0.0, ry - 11.0)
	lk.z_index = 20
	lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lk)
	var lv := Label.new()
	lv.text = String(it.get("big", ""))
	lv.add_theme_font_size_override("font_size", 20)
	lv.add_theme_color_override("font_color", Color(1, 0.7, 0.15))
	lv.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.02))
	lv.add_theme_constant_override("outline_size", 5)
	lv.size = Vector2(sz.x - 140.0, 24.0)
	lv.position = Vector2(140.0, ry - 12.0)
	lv.z_index = 20
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lv)

	var sub := Label.new()
	sub.text = String(it.get("desc", ""))
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
	sub.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.03))
	sub.add_theme_constant_override("outline_size", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(sz.x, 20.0)
	sub.position = Vector2(0.0, ry + 20.0)
	sub.z_index = 20
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sub)

## 원작 `TrainingSelectCell::initWithSize` + `TrainingSelectLayer::tableCellAtIndex` 이식.
##   · `common/backlight3` + 훈련 아이콘 @ (w/2, h/2 + 60)   [Cocos y-up]
##   · 이름            @ (w/2, h - 50)
##   · 큰 숫자(font_heal) @ (w/2, h/2 - 20)
##   · 설명(소요시간 `(hh : mm : ss)`) @ (w/2, h/2 - 60)
##   · `LV a` ▶`common/btn_arrow2`▶ `LV b` @ y = h/2 - 120 (라벨은 화살표 ±30)
##   · 비용 아이콘(`coin_small1`/`diamond_small1`) anchor(1,0.5) @ (w/2 - 20, 50) + 숫자
func _fill_training_cell(card: Control, it: Dictionary, sz: Vector2) -> void:
	var cy := sz.y * 0.5
	var back := AtlasUI.spr("common_ui", "common_backlight3", 0.5 * Design.ASSET_SCALE)
	if back != null:
		back.position = Vector2(sz.x * 0.5, cy - 60.0)
		back.modulate = Color(1, 1, 1, 0.8)
		card.add_child(back)
	var icon_dir := String(it.get("icon_dir", ""))
	var icon_key := String(it.get("icon_key", ""))
	if icon_dir != "" and icon_key != "":
		var ic := AtlasUI.spr(icon_dir, icon_key, Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(sz.x * 0.5, cy - 60.0)
			card.add_child(ic)

	_cell_label(card, String(it.get("title", "")), Vector2(0, 28.0), sz.x, 22,
		Color(1, 0.97, 0.86))
	_cell_label(card, String(it.get("big", "")), Vector2(0, cy + 8.0), sz.x, 30,
		Color(1, 0.7, 0.15))
	_cell_label(card, String(it.get("desc", "")), Vector2(0, cy + 52.0), sz.x, 15,
		Color(0.86, 0.82, 0.72))

	# 원작: `LV a` anchor(1,0.5) @ (w/2 - 30) · 화살표 @ (w/2) · `LV b` anchor(0,0.5) @ (w/2 + 30)
	if it.has("lv_from"):
		var y := cy + 108.0
		var half := sz.x * 0.5
		var lf := Label.new()
		lf.text = "LV %d" % int(it["lv_from"])
		lf.add_theme_font_size_override("font_size", 18)
		lf.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
		lf.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.03))
		lf.add_theme_constant_override("outline_size", 4)
		lf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lf.size = Vector2(half - 30.0, 24.0)
		lf.position = Vector2(0.0, y)
		lf.z_index = 20
		lf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lf)
		var ar := AtlasUI.spr("common_ui", "common_btn_arrow2", Design.ASSET_SCALE * 0.7)
		if ar != null:
			ar.position = Vector2(half, y + 12.0)
			card.add_child(ar)
		var lt := Label.new()
		lt.text = "LV %d" % int(it["lv_to"])
		lt.add_theme_font_size_override("font_size", 18)
		lt.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		lt.add_theme_color_override("font_outline_color", Color(0.06, 0.2, 0.08))
		lt.add_theme_constant_override("outline_size", 4)
		lt.size = Vector2(half - 30.0, 24.0)
		lt.position = Vector2(half + 30.0, y)
		lt.z_index = 20
		lt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lt)

	# 비용 — 원작 아이콘 anchor(1,0.5) @ (w/2 - 20, 50) [Cocos y-up] → Godot y = h - 50
	if it.has("cost"):
		var iy := sz.y - 50.0
		var ck := String(it.get("cost_cur", "gold"))
		var ci := AtlasUI.spr("common_ui",
			"common_diamond_small1" if ck == "diamond" else "common_coin_small1", Design.ASSET_SCALE)
		if ci != null:
			ci.position = Vector2(sz.x * 0.5 - 34.0, iy)
			card.add_child(ci)
		var cl := Label.new()
		cl.text = String(it["cost"])
		cl.add_theme_font_size_override("font_size", 18)
		cl.add_theme_color_override("font_color", Color(1, 0.97, 0.86))
		cl.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.03))
		cl.add_theme_constant_override("outline_size", 4)
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.size = Vector2(sz.x * 0.5, 24.0)
		cl.position = Vector2(sz.x * 0.5 - 16.0, iy - 12.0)
		cl.z_index = 20
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cl)

func _cell_label(parent: Control, text: String, off: Vector2, w: float, fs: int, col: Color) -> void:
	if text == "":
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.03))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(w, 46)
	l.position = Vector2(off.x, off.y)
	l.z_index = 20                      # 스파인 위에 오도록
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)

func _close() -> void:
	var from := String(_params.get("from", "worldmap"))
	if from == "cave":
		Scenes.goto("cave", {})
	elif from == "town":
		Scenes.goto("town", {"area": _params.get("area", "elpis")})
	else:
		Scenes.goto("worldmap", {"region": "yutakan"})

func _vis() -> Vector2:
	return get_viewport_rect().size
