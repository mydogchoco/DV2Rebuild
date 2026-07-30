class_name LevelUpResult
extends RefCounted
## 레벨업 결과창 — 원작 `TrainingResultLayer`(docs/ref/porting/TrainingResultLayer.md) 레이아웃을
## **탐험/전투에서도 재사용**할 수 있게 씬 밖으로 뽑아낸 공용 모달.
##
## ── 원작 대조(중요) ────────────────────────────────────────────────────────────
## 원작 **탐험 중에는 레벨업 "창"이 없었다.** 확인한 근거:
##   · `AdventureMethod::CheckLevelUp`(AdventureMethod.c:4-300)은 서버가 내려준
##     `change1/2/3` JSON을 드래곤 스탯에 **적용만** 한다 — Layer 생성·show·사운드 호출이 없다.
##   · 대신 하단 텍스트박스(BattleTextBox)에 한 줄이 흐른다:
##       `<AdventureResultExpLevelup>%1$s이(가) 경험치를 %2$d 얻고 레벨업 했습니다.`
##       `<AdventureResultExpBonusLevelup>…%2$d(+%3$d)…`   (stringsData_KR.xml)
##     이 문자열을 만드는 곳이 `AdventureScene::setEventExpText`(AdventureScene.c:42707/42731).
##   · 레벨업 결과 **창**을 띄우는 건 육성(훈련) 경로의 `TrainingResultLayer` 뿐이다
##     (`TrainingLayer`가 `setTarget`으로 대상 주입 → `getLevel()/getLevelExp()` 자체 조회).
## ⇒ 탐험 중 모달 + 일시정지는 **오프라인 재구현의 의도적 변형**(사용자 2026-07-27 지시).
##    원작 자산·레이아웃은 TrainingResultLayer 그대로 쓰고, 등장 시점만 탐험으로 넓혔다.
##    텍스트박스 한 줄(원작 동작)은 그대로 유지한다 — 창과 병행.
##
## 사용:
##   LevelUpResult.open(host, entries, func(): ...)
##   entries = [{ "uid": int, "name": String, "from_lv": int, "to_lv": int,
##                "gains": Array,           # LevelSystem.apply_exp 의 ev["gains"]
##                "max_stats": Dictionary   # 티어 최대 상승량(분모)
##             }, …]

const POPUP4 := "res://assets/converted/ninepatch_ui/9patch_popup4.tres"
const TITLE_BG := "res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres"
const LEVEL_UP_ART := "res://assets/converted/lvup_ui/level_up.png"

const BW := 440.0
const BH := 500.0

const _STAT_ROWS := [
	["hp", "생명력", Color(0.45, 0.95, 0.45)],
	["att", "공격력", Color(1.0, 0.45, 0.4)],
	["def", "방어력", Color(0.45, 0.7, 1.0)],
]

## 여러 마리가 동시에 올랐으면 한 마리씩 차례로 띄운다. 전부 닫히면 on_close 호출.
static func open(host: Node, entries: Array, on_close := Callable()) -> void:
	if entries.is_empty():
		if on_close.is_valid(): on_close.call()
		return
	_open_one(host, entries, 0, on_close)

static func _open_one(host: Node, entries: Array, idx: int, on_close: Callable) -> void:
	if idx >= entries.size() or not is_instance_valid(host) or not host.is_inside_tree():
		if on_close.is_valid(): on_close.call()
		return
	var e: Dictionary = entries[idx]
	_build(host, e, func():
		_open_one(host, entries, idx + 1, on_close))

static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _spr(dir: String, name: String, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new()
	s.texture = load(p)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	s.material = m
	s.scale = Vector2(scale, scale)
	return s

static func _build(host: Node, e: Dictionary, done: Callable) -> void:
	var uid := int(e.get("uid", 0))
	var d: Dictionary = UserDB.get_dragon(uid)
	var did := int(d.get("id", 0))
	var from_lv := int(e.get("from_lv", 1))
	var to_lv := int(e.get("to_lv", from_lv + 1))
	var gains: Array = e.get("gains", [])
	var max_stats: Dictionary = e.get("max_stats", {})
	# 현재(=레벨업 후) 실스탯 = gain_log 누적. 이전 스탯 = 현재 − 이번에 오른 만큼.
	var ddef: Dictionary = Data.get_dragon(did)
	var sb: Dictionary = d.get("stat_bonus", {})
	var after: Dictionary = Growth.main_stats(ddef, Data.stat_table,
		d.get("gain_log", []), sb.get("base", {}))
	var delta := {"hp": 0, "att": 0, "def": 0}
	var maxn := {"hp": 0, "att": 0, "def": 0}
	var trans := {"hp": false, "att": false, "def": false}
	for g in gains:
		var gd: Dictionary = g
		var ism: Dictionary = gd.get("is_max", {})
		var tm: Dictionary = gd.get("tmax", {})
		for k in ["hp", "att", "def"]:
			delta[k] = int(delta[k]) + int(gd.get(k, 0))
			if bool(ism.get(k, false)): maxn[k] = int(maxn[k]) + 1
			if bool(tm.get(k, false)): trans[k] = true

	var vis: Vector2 = host.get_viewport_rect().size
	Bgm.sfx("effect_level_updown")            # 원작 TrainingResultLayer 레벨 사운드
	var layer := CanvasLayer.new(); layer.layer = 90
	host.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤쪽 입력 차단 = 탐험 정지 보장
	layer.add_child(dim)

	var win := NinePatchRect.new()
	win.texture = load(POPUP4)
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)

	var tbar := NinePatchRect.new()
	tbar.texture = load(TITLE_BG)
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12)
	win.add_child(tbar)
	var tl := Label.new()
	tl.text = String(e.get("name", d.get("name", "드래곤")))
	tl.add_theme_font_size_override("font_size", 26)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)

	var bl := _spr("common_ui", "common_backlight3", 0.9)
	if bl:
		bl.position = Vector2(BW * 0.5, 150)
		bl.modulate = Color(1, 1, 1, 0.4)
		win.add_child(bl)
		bl.create_tween().set_loops().tween_property(bl, "rotation", TAU, 8.0).from(0.0)
	var pdir := "portrait_%d" % did
	var por := _spr(pdir, "dragon_dragon_%d_box_%s" % [did, Growth.stage_for_level(to_lv)], 0.8)
	if por:
		por.position = Vector2(BW * 0.5, 150)
		win.add_child(por)

	var lup := TextureRect.new()
	lup.texture = load(LEVEL_UP_ART)
	lup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lup.size = Vector2(180, 96); lup.position = Vector2((BW - 180) * 0.5, 196)
	lup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(lup)

	# 행: 레벨 + 주스탯 3종. 증가분 = (+상승/티어최대), 최대치가 나오면 색 강조.
	var rows := [["레벨", Color(1.0, 0.83, 0.25), str(from_lv), str(to_lv), "", false]]
	var maxed := 0
	for spec in _STAT_ROWS:
		var k: String = spec[0]
		var dv := int(delta[k])
		var av := int(after.get(k, 0))
		var bvv := av - dv
		var mx := int(max_stats.get(k, 0))
		var levels := maxi(1, gains.size())
		var dtxt := ""
		if mx > 0:
			dtxt = ("(+%d/%d)" % [dv, mx]) if levels == 1 else ("(+%d)" % dv)
		else:
			dtxt = "(+%d)" % dv
		if int(maxn[k]) > 0: maxed += 1
		rows.append([String(spec[1]), spec[2], str(bvv), str(av), dtxt,
			int(maxn[k]) > 0 or bool(trans[k])])
	# ⚠️ 원작은 증가분에 `font/font_heal.fnt`를 쓰지만 그 BMFont 글리프가 `.0123456789` 12자뿐이라
	#    `(+13/9)` 의 괄호·+·/ 를 못 낸다(CLAUDE.md §10). 증가분 표기는 TTF로 낸다.
	var cman := _man("common_ui")
	for i in rows.size():
		var y := 300.0 + i * 34.0
		var nm2 := Label.new(); nm2.text = String(rows[i][0])
		nm2.add_theme_font_size_override("font_size", 21)
		nm2.add_theme_color_override("font_color", rows[i][1])
		nm2.position = Vector2(48, y); nm2.size = Vector2(96, 28); win.add_child(nm2)
		var bv := Label.new(); bv.text = String(rows[i][2])
		bv.add_theme_font_size_override("font_size", 21)
		bv.add_theme_color_override("font_color", Color(0.35, 0.26, 0.12))
		bv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bv.position = Vector2(140, y); bv.size = Vector2(78, 28); win.add_child(bv)
		# ▶ = 원작 `common/btn_arrow2`
		var ar := _spr("common_ui", "common_btn_arrow2", 0.6)
		if ar and not cman.is_empty():
			ar.position = Vector2(240, y + 14); win.add_child(ar)
		else:
			var art := Label.new(); art.text = "▶"
			art.add_theme_font_size_override("font_size", 20)
			art.add_theme_color_override("font_color", Color(1.0, 0.78, 0.15))
			art.position = Vector2(226, y); art.size = Vector2(28, 28); win.add_child(art)
		var av2 := Label.new(); av2.text = String(rows[i][3])
		av2.add_theme_font_size_override("font_size", 21)
		av2.add_theme_color_override("font_color", Color(0.2, 0.14, 0.05))
		av2.position = Vector2(262, y); av2.size = Vector2(78, 28); win.add_child(av2)
		if String(rows[i][4]) != "":
			var dlb := Label.new(); dlb.text = String(rows[i][4])
			dlb.add_theme_font_size_override("font_size", 17)
			dlb.add_theme_color_override("font_color",
				Color(1.0, 0.45, 0.85) if bool(rows[i][5]) else Color(0.45, 0.6, 0.35))
			dlb.position = Vector2(338, y + 3); dlb.size = Vector2(84, 24); win.add_child(dlb)
	if maxed > 0:
		var mb := Label.new(); mb.text = "%dMAX" % maxed
		mb.add_theme_font_size_override("font_size", 22)
		mb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		mb.add_theme_color_override("font_outline_color", Color(0.5, 0.15, 0.4, 0.9))
		mb.add_theme_constant_override("outline_size", 4)
		mb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mb.position = Vector2(BW - 110, 268); mb.size = Vector2(90, 28); win.add_child(mb)

	var ok := Button.new(); ok.text = "확인"
	ok.size = Vector2(160, 46); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(func():
		Bgm.sfx("effect_button")
		if is_instance_valid(layer): layer.queue_free()
		if done.is_valid(): done.call())
	win.add_child(ok)

	# 등장 팝(원작 팝업 공통 연출)
	win.pivot_offset = win.size * 0.5
	win.scale = Vector2(0.8, 0.8); win.modulate.a = 0.0
	var t := win.create_tween()
	t.tween_property(win, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(win, "scale", Vector2.ONE, 0.28)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
