extends Control

const BG_DIR := "res://assets/converted/colosseum_bg"
const CO := "colosseum_ui"
const NP := "ninepatch_ui"
const CM := "common_ui"

const BTN_MENU_W := 196.0 * Design.ASSET_SCALE
const BTN_MENU_H := 104.0 * Design.ASSET_SCALE
const RIGHT_COL := BTN_MENU_W + 67.0
const PANEL_LEFT := 20.0
const PANEL_TOP_GAP := 97.0
const DECO_LIFT := 26.0
const POPUP5_CAP := Rect2(25, 25, 4, 4)

const BTN_RIGHT_PAD := 25.0
const BTN_BOTTOM := 16.0
const BTN_GAP := 2.0
const BTN_VS_BG_Y := 30.0
const BTN_LABEL_Y := 80.0

const CELL_FRAME := "9patch_replay_bg"
const CELL_CAP := Rect2(24, 24, 8, 8)
const POINT_FRAME := "scene_colosseum_pvp_point_bg"

var _pma: CanvasItemMaterial
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _weekly := false
var _board_mode := Colosseum.last_mode()

var _eta_label: Label = null
var _eta_energy := -1
var _eta_timer: Timer = null
var _mode_eta: Dictionary = {}
var _mode_energy: Dictionary = {}

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	Bgm.play(Colosseum.lobby_bgm())
	var claimed: Array = Colosseum.claim_rewards()
	_rebuild()
	var daily: Array = claimed.filter(func(r: Dictionary) -> bool:
		return String(r.get("kind", "")) == "daily")
	if not daily.is_empty():
		var parts: PackedStringArray = []
		for r: Dictionary in daily:
			parts.append("%s %s 다이아 %d, 주화 %d" % [
				String(Colosseum.mode_cfg(String(r.get("mode", ""))).get("label", "")),
				String((r.get("tier", {}) as Dictionary).get("name", "")),
				int(r.get("dia", 0)), int(r.get("coin", 0))])
		_notice("일일 보상을 지급했습니다.\n" + " / ".join(parts))
	var season: Array = claimed.filter(func(r: Dictionary) -> bool:
		return String(r.get("kind", "")) == "season")
	if not season.is_empty():
		var sparts: PackedStringArray = []
		var reset_done := false
		for r: Dictionary in season:
			sparts.append("%s %s 다이아 %d, 주화 %d" % [
				String(Colosseum.mode_cfg(String(r.get("mode", ""))).get("label", "")),
				String((r.get("tier", {}) as Dictionary).get("name", "")),
				int(r.get("dia", 0)), int(r.get("coin", 0))])
			if not (r.get("reset", []) as Array).is_empty():
				reset_done = true
		var head := "시즌이 종료되었습니다."
		if reset_done:
			head += " %s 연승은 초기화되었습니다." % _reset_phrase()
		_notice(head + "\n" + " / ".join(sparts))

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_eta_label = null
	_eta_timer = null
	_mode_eta.clear()
	_mode_energy.clear()
	var vis := _vis()
	_build_bg(vis)
	var panel := _build_panel(vis)
	_build_tabs(panel)
	_build_rank_list(panel)
	_build_panel_footer(panel)
	_build_right_column(vis)
	_build_start_buttons(vis)

func _build_bg(vis: Vector2) -> void:
	var p := "%s/stage_3.jpg" % BG_DIR
	if not ResourceLoader.exists(p):
		return
	var t: Texture2D = load(p)
	var tr := TextureRect.new()
	tr.texture = t
	tr.size = vis
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(tr)

func _build_panel(vis: Vector2) -> Control:
	var sz := Vector2(vis.x - RIGHT_COL, vis.y - PANEL_TOP_GAP)
	var np := _nine("9patch_popup5", sz, POPUP5_CAP)
	var host := Control.new()
	host.position = Vector2(PANEL_LEFT, vis.y - sz.y)
	host.size = sz
	add_child(host)
	if np != null:
		host.add_child(np)
	var dh := 86.0 * Design.ASSET_SCALE
	var deco := _nine9("scene_colosseum_window_deco", Vector2(sz.x + 20.0, dh),
		Rect2(60, 20, 4, 4), CO)
	if deco != null:
		deco.position = Vector2(-10.0, -dh + DECO_LIFT)
		host.add_child(deco)
	var title := _spr(CO, "scene_colosseum_colosseum_title", Design.ASSET_SCALE)
	if title != null:
		title.position = Vector2(sz.x * 0.5, -dh + DECO_LIFT + dh * 0.5)
		host.add_child(title)
	return host

const TAB_W := 101.0 * Design.ASSET_SCALE
const TAB_H := 35.0 * Design.ASSET_SCALE
const TAB_X0 := 50.0
const TAB_GAP := 6.0
const TAB_TOP := 10.0
const TAB_DROP := 8.0

func _build_tabs(host: Control) -> void:
	var tabs := [[false, "scene_colosseum_txt_overall_kr"],
				 [true, "scene_colosseum_txt_weekly_kr"]]
	for i in tabs.size():
		var weekly := bool(tabs[i][0])
		var on := weekly == _weekly
		var b := Button.new()
		b.flat = true
		b.size = Vector2(TAB_W, TAB_H)
		b.position = Vector2(TAB_X0 + float(i) * (TAB_W + TAB_GAP),
			TAB_TOP + (0.0 if on else TAB_DROP))
		var bg := _spr(CO, "scene_colosseum_tab_selected" if on else "scene_colosseum_tab_normal",
			Design.ASSET_SCALE)
		if bg != null:
			bg.position = Vector2(TAB_W * 0.5, TAB_H * 0.5)
			b.add_child(bg)
		var txt := _spr(CO, String(tabs[i][1]), Design.ASSET_SCALE)
		if txt != null:
			txt.position = Vector2(TAB_W * 0.5, TAB_H * 0.5)
			if not on:
				txt.modulate = Color(0.72, 0.68, 0.62)
			b.add_child(txt)
		var w := weekly
		b.pressed.connect(func() -> void:
			if _weekly == w:
				return
			_weekly = w
			_rebuild())
		host.add_child(b)

	var mtabs := [["single", "scene_colosseum_icon_1vs1"],
				  ["team", "scene_colosseum_icon_3vs3"]]
	for i in mtabs.size():
		var key := String(mtabs[i][0])
		var on := key == _board_mode
		var b := Button.new()
		b.flat = true
		b.size = Vector2(TAB_W * 0.62, TAB_H)
		b.position = Vector2(TAB_X0 + 2.0 * (TAB_W + TAB_GAP) + 26.0
			+ float(i) * (TAB_W * 0.62 + TAB_GAP), TAB_TOP + (0.0 if on else TAB_DROP))
		var bg := _nine9("scene_colosseum_tab_selected" if on else "scene_colosseum_tab_normal",
			Vector2(TAB_W * 0.62, TAB_H), Rect2(30, 18, 6, 6), CO)
		if bg != null:
			b.add_child(bg)
		var ic := _spr(CO, String(mtabs[i][1]), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(TAB_W * 0.31, TAB_H * 0.5)
			if not on:
				ic.modulate = Color(0.7, 0.66, 0.6)
			b.add_child(ic)
		var m := key
		b.pressed.connect(func() -> void:
			if _board_mode == m:
				return
			_board_mode = m
			Colosseum.set_last_mode(m)
			_rebuild())
		host.add_child(b)

const CELL_H := 62.0
const CELL_GAP := 4.0
const LIST_TOP := TAB_TOP + TAB_H + 12.0
const LIST_PAD := 22.0
const LIST_BOTTOM := 62.0

func _build_rank_list(host: Control) -> void:
	var w := host.size.x - LIST_PAD * 2.0
	var view_h := host.size.y - LIST_TOP - LIST_BOTTOM

	var back := _nine("9patch_list_bg2", Vector2(w, view_h), Rect2(24, 24, 8, 8))
	if back != null:
		back.position = Vector2(LIST_PAD, LIST_TOP)
		back.modulate = Color(1, 1, 1, 0.85)
		host.add_child(back)

	var sc := ScrollContainer.new()
	sc.position = Vector2(LIST_PAD + 6.0, LIST_TOP + 6.0)
	sc.size = Vector2(w - 12.0, view_h - 12.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(sc)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(sc.size.x, 0.0)
	sc.add_child(inner)

	var rows := Colosseum.ladder(_board_mode, _weekly, _rng).duplicate()
	var mine := Colosseum.rating_of(_board_mode)
	var me_nick := UserDB.user_nickname()
	if me_nick == "":
		me_nick = "나"
	rows.append({"nick": me_nick, "rating": mine, "me": true})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rating", 0)) > int(b.get("rating", 0)))

	var cw := sc.size.x
	for i in rows.size():
		var r: Dictionary = rows[i]
		var cell := Control.new()
		cell.position = Vector2(0.0, float(i) * (CELL_H + CELL_GAP))
		cell.size = Vector2(cw, CELL_H)
		inner.add_child(cell)

		var bg := _nine(CELL_FRAME, Vector2(cw, CELL_H), CELL_CAP)
		if bg != null:
			if bool(r.get("me", false)):
				bg.modulate = Color(1.35, 1.22, 0.8)
			cell.add_child(bg)

		var rk := Label.new()
		rk.text = "%d" % (i + 1)
		rk.size = Vector2(52.0, CELL_H)
		rk.position = Vector2(4.0, 0.0)
		rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rk.add_theme_font_size_override("font_size", 22)
		rk.modulate = Color(1.0, 0.88, 0.5) if i < 3 else Color.WHITE
		cell.add_child(rk)

		var rating := int(r.get("rating", 0))
		var tf := Colosseum.tier_frame(rating, "icon")
		if tf != "":
			var tk := "common_" + tf.get_slice("/", 1).replace(".png", "")
			var ts := _spr(CM, tk, Design.ASSET_SCALE * 0.55)
			if ts != null:
				ts.position = Vector2(78.0, CELL_H * 0.5)
				cell.add_child(ts)

		var nick := Label.new()
		nick.text = String(r.get("nick", ""))
		nick.size = Vector2(cw * 0.5, CELL_H)
		nick.position = Vector2(106.0, 0.0)
		nick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nick.add_theme_font_size_override("font_size", 20)
		if bool(r.get("me", false)):
			nick.modulate = Color(1.0, 0.92, 0.55)
		cell.add_child(nick)

		var pw := 230.0 * Design.ASSET_SCALE * 0.62
		var pb := _nine9(POINT_FRAME, Vector2(pw, 41.0 * Design.ASSET_SCALE * 0.72),
			Rect2(30, 18, 4, 4), CO)
		if pb != null:
			pb.position = Vector2(cw - pw - 12.0, CELL_H * 0.5 - 41.0 * Design.ASSET_SCALE * 0.36)
			cell.add_child(pb)
		var pt := Label.new()
		pt.text = "%d점" % rating
		pt.size = Vector2(pw, CELL_H)
		pt.position = Vector2(cw - pw - 12.0, 0.0)
		pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pt.add_theme_font_size_override("font_size", 19)
		cell.add_child(pt)

	inner.custom_minimum_size = Vector2(cw,
		float(rows.size()) * (CELL_H + CELL_GAP))

func _build_panel_footer(host: Control) -> void:
	var y := host.size.y - 52.0

	var wbox := _nine("9patch_list_bg2", Vector2(300.0, 40.0), Rect2(24, 24, 8, 8))
	if wbox != null:
		wbox.position = Vector2(15.0, y)
		host.add_child(wbox)
	var wt := _spr(CO, "scene_colosseum_week_time", Design.ASSET_SCALE)
	if wt != null:
		wt.position = Vector2(15.0 + 10.0 + 11.0, y + 20.0)
		host.add_child(wt)
	var wl := Label.new()
	wl.text = "이번 시즌 %s 남음" % _season_left()
	wl.position = Vector2(15.0 + 44.0, y + 8.0)
	wl.add_theme_font_size_override("font_size", 18)
	host.add_child(wl)

	var cost := Colosseum.season_reset_cost()
	if cost > 0:
		var rb := Button.new()
		rb.flat = true
		rb.size = Vector2(155.0, 40.0)
		rb.position = Vector2(15.0 + 300.0 + 10.0, y)
		var rbg := _spr(CO, "scene_colosseum_btn_refresh", 1.0)
		if rbg != null:
			rbg.position = Vector2(77.5, 20.0)
			rb.add_child(rbg)
		var ri := _spr(CO, "scene_colosseum_refresh", 1.0)
		if ri != null:
			ri.position = Vector2(28.0, 20.0)
			rb.add_child(ri)
		var rl := Label.new()
		rl.text = "시즌 종료"
		rl.size = Vector2(96.0, 40.0)
		rl.position = Vector2(52.0, 0.0)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.add_theme_font_size_override("font_size", 17)
		rb.add_child(rl)
		rb.pressed.connect(_ask_season_reset)
		host.add_child(rb)

	var eb := Button.new()
	eb.flat = true
	eb.size = Vector2(60.0, 44.0)
	eb.position = Vector2(host.size.x - 76.0, y - 2.0)
	var es := _spr(CM, "common_ether_rank", Design.ASSET_SCALE)
	if es != null:
		es.position = Vector2(30.0, 22.0)
		eb.add_child(es)
	eb.pressed.connect(func() -> void:
		var c: Dictionary = Data.colosseum.get("coin", {})
		var dparts: PackedStringArray = []
		var sparts: PackedStringArray = []
		for mode in (Data.colosseum.get("modes", {}) as Dictionary):
			var mt := Colosseum.tier_of(Colosseum.rating_of(String(mode)))
			var tk := str(int(mt.get("id", 0)))
			var label := "%s %s" % [String(Colosseum.mode_cfg(String(mode)).get("label", "")),
				String(mt.get("name", ""))]
			var d: Dictionary = (c.get("daily", {}) as Dictionary).get(tk, {})
			var sn: Dictionary = (c.get("season", {}) as Dictionary).get(tk, {})
			dparts.append("%s 다이아 %d, 주화 %d"
				% [label, int(d.get("dia", 0)), int(d.get("coin", 0))])
			sparts.append("%s 다이아 %d, 주화 %d"
				% [label, int(sn.get("dia", 0)), int(sn.get("coin", 0))])
		_notice("일일 보상 %s\n시즌 보상 %s (종료 시 %s 연승이 초기화됩니다)"
			% [" / ".join(dparts), " / ".join(sparts), _reset_phrase()]))
	host.add_child(eb)

func _season_left() -> String:
	var left := Colosseum.season_left_sec()
	return "%d일 %d시간" % [left / 86400, (left % 86400) / 3600]

func _build_start_buttons(vis: Vector2) -> void:
	var max_energy := int(Data.colosseum.get("ticket", {}).get("max", 10))
	var modes := [["team", "3 VS 3", "scene_colosseum_icon_3vs3"],
				  ["single", "1 VS 1", "scene_colosseum_icon_1vs1"]]
	for i in modes.size():
		var key := String(modes[i][0])
		var cy_cocos := BTN_MENU_H * 0.5 + BTN_BOTTOM + float(i) * (BTN_MENU_H + BTN_GAP)
		var cx := vis.x - BTN_MENU_W * 0.5 - BTN_RIGHT_PAD
		var top_left := Vector2(cx - BTN_MENU_W * 0.5, vis.y - cy_cocos - BTN_MENU_H * 0.5)

		var b := Button.new()
		b.flat = true
		b.size = Vector2(BTN_MENU_W, BTN_MENU_H)
		b.position = top_left
		add_child(b)

		var face := _spr(CO, "scene_colosseum_btn_menu", Design.ASSET_SCALE)
		if face != null:
			face.position = Vector2(BTN_MENU_W * 0.5, BTN_MENU_H * 0.5)
			b.add_child(face)

		var vw := 92.0 * Design.ASSET_SCALE
		var vh := 21.0 * Design.ASSET_SCALE
		var vy := BTN_MENU_H - BTN_VS_BG_Y - vh * 0.5
		var vbg := _spr(CO, "scene_colosseum_icon_vs_bg", Design.ASSET_SCALE)
		if vbg != null:
			vbg.position = Vector2(BTN_MENU_W * 0.5, vy)
			b.add_child(vbg)
		var mi := _spr(CO, String(modes[i][2]), Design.ASSET_SCALE)
		if mi != null:
			mi.position = Vector2(BTN_MENU_W * 0.5 - vw * 0.5, vy)
			b.add_child(mi)
		var mine := Colosseum.ticket_of(key)
		_mode_energy[key] = mine
		var en := Label.new()
		en.text = "%d/%d" % [mine, max_energy]
		en.size = Vector2(vw, vh)
		en.position = Vector2(BTN_MENU_W * 0.5 - vw * 0.5 + 8.0, vy - vh * 0.5)
		en.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		en.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_bm_style(en, 18, Color.WHITE if mine >= max_energy else Color(1.0, 0.80, 0.45))
		b.add_child(en)
		_mode_eta[key] = null
		if mine < max_energy:
			var el := Label.new()
			el.size = Vector2(BTN_MENU_W, 18.0)
			el.position = Vector2(0.0, vy + vh * 0.5 + 1.0)
			el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_bm_style(el, 15, ETA_COLOR)
			b.add_child(el)
			_mode_eta[key] = el

		var lb := Label.new()
		lb.text = String(modes[i][1])
		lb.size = Vector2(BTN_MENU_W, 40.0)
		lb.position = Vector2(0.0, BTN_MENU_H - BTN_LABEL_Y - 26.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bm_style(lb, 30, Color.WHITE)
		b.add_child(lb)

		var st := Colosseum.streak_of(key)
		if st > 0:
			var fw := 42.0 * Design.ASSET_SCALE
			var fx := fw * 0.5 + 10.0
			var fy := fw * 0.5 + 5.0
			var fi := _spr(CO, "scene_colosseum_icon_fist%d" % (1 if key == "single" else 2),
				Design.ASSET_SCALE * 0.7)
			if fi != null:
				fi.position = Vector2(fx, fy)
				b.add_child(fi)
			var sl := Label.new()
			sl.text = "%d" % st
			sl.size = Vector2(fw + 20.0, 24.0)
			sl.position = Vector2(fx - (fw + 20.0) * 0.5, fy + fw * 0.35)
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_bm_style(sl, 20, Color(1.0, 0.86, 0.5), "font_title")
			b.add_child(sl)

		var m := key
		b.pressed.connect(func() -> void: _start(m))

func _start(mode: String) -> void:
	if not Colosseum.can_enter(mode):
		_ask_refill(mode)
		return
	var n := Colosseum.party_size(mode)
	var ok := Colosseum.eligible_uids()
	if ok.size() < n:
		_notice("레벨 %d 이상 드래곤이 %d마리 필요합니다." % [Colosseum.min_level(), n])
		return
	Colosseum.set_last_mode(mode)
	var seed_party: Array = []
	for u in UserDB.party():
		if Colosseum.eligible(int(u)):
			seed_party.append(int(u))
	for u in ok:
		if seed_party.size() >= n:
			break
		if not seed_party.has(int(u)):
			seed_party.append(int(u))
	ColosseumSelect.open(self, mode, seed_party.slice(0, n), func(picked: Array) -> void:
		if picked.is_empty():
			return
		if not Colosseum.spend_ticket(mode):
			_notice(String(Data.colosseum.get("log", {}).get("no_stamina",
				Data.ui("#99976bed"))))
			return
		var foe := Colosseum.roll_match(mode, _rng)
		Colosseum.consume_guard(mode, foe)
		MatchingWait.open(self, Colosseum.matching_seconds(), func() -> void:
			Scenes.goto("fight", {"mode": mode, "opponent": foe, "party": picked.slice(0, n)})))

func _ask_refill(mode: String) -> void:
	var log: Dictionary = Data.colosseum.get("log", {})
	var cost := Colosseum.refill_cost()
	if cost <= 0:
		_notice(String(log.get("no_stamina", Data.ui("#99976bed"))))
		return
	var msg := String(log.get("no_stamina", "")) + "\n\n" \
		+ "%s " % String(Colosseum.mode_cfg(mode).get("label", "")) \
		+ String(log.get("refill_ask", "피로도를 가득 충전하시겠습니까?\n(다이아 %d개 소모)")) % cost
	MessageWindow.open(self, String(log.get("refill_title", "피로도 충전")), msg,
		func() -> void:
			var r := Colosseum.buy_refill(mode)
			_rebuild()
			if not bool(r.get("ok", false)):
				_notice(String(log.get("refill_error", Data.ui("#0a0171ae")))
					if String(r.get("reason", "")) == "money"
					else String(log.get("refill_full", "피로도가 이미 가득 차 있습니다.")))
				return
			_notice(String(log.get("refill_done", "피로도를 %d개 충전했습니다.")) % int(r.get("filled", 0)))
			_start(mode),
		"확인", "취소")

func _ask_season_reset() -> void:
	var log: Dictionary = Data.colosseum.get("log", {})
	var cost := Colosseum.season_reset_cost()
	if cost <= 0:
		return
	var msg := String(log.get("season_reset_ask",
		"이번 시즌을 지금 종료하시겠습니까?\n(다이아 %d개 소모)")) % cost
	MessageWindow.open(self, String(log.get("season_reset_title", "시즌 초기화")), msg,
		func() -> void:
			var r := Colosseum.buy_season_reset()
			_rebuild()
			if not bool(r.get("ok", false)):
				_notice(String(log.get("season_reset_error", "시즌 초기화에 필요한 다이아가 부족합니다.")))
				return
			_notice(String(log.get("season_reset_done",
				"시즌을 종료했습니다.\n다이아 %d개와 콜로세움 주화 %d개를 받았습니다."))
				% [int(r.get("dia", 0)), int(r.get("coin", 0))]),
		"확인", "취소")

func _build_right_column(vis: Vector2) -> void:
	var x := vis.x - RIGHT_COL + PANEL_LEFT
	var col := Control.new()
	col.position = Vector2(x, 0.0)
	col.size = Vector2(RIGHT_COL - PANEL_LEFT, vis.y)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var s := Colosseum.refresh_ticket(_board_mode)
	var rating := Colosseum.rating_of(_board_mode)
	var streak := Colosseum.streak_of(_board_mode)

	const PAD := 18.0
	var cw := col.size.x - PAD * 2.0
	var py := 76.0
	var modes: Array = (Data.colosseum.get("modes", {}) as Dictionary).keys()
	if modes.is_empty():
		modes = [_board_mode]
	var slots := modes.size()
	var sw := col.size.x / float(slots)
	for i in slots:
		var mode := String(modes[i])
		var mrating := Colosseum.rating_of(mode)
		var active := mode == _board_mode
		var dim := Color.WHITE if active else Color(0.6, 0.6, 0.6)
		var cx := sw * (float(i) + 0.5)
		var pbg := _spr(CO, "scene_colosseum_top_profile_bg", Design.ASSET_SCALE * 0.72)
		if pbg != null:
			pbg.position = Vector2(cx, py)
			pbg.modulate = dim
			col.add_child(pbg)
		var tf := Colosseum.tier_frame(mrating, "icon")
		if tf != "":
			var tk := "common_" + tf.get_slice("/", 1).replace(".png", "")
			var ts := _spr(CM, tk, Design.ASSET_SCALE * 0.58)
			if ts != null:
				ts.position = Vector2(cx, py)
				ts.modulate = dim
				col.add_child(ts)
		var ml := _outlined(_center_label(
			String(Colosseum.mode_cfg(mode).get("label", "")).to_upper(),
			sw, py + 30.0, 13, ETA_COLOR if active else Color(0.72, 0.72, 0.72)))
		ml.position.x = sw * float(i)
		col.add_child(ml)
		var tn := _outlined(_center_label(String(Colosseum.tier_of(mrating).get("name", "")),
			sw, py + 52.0, 17, dim))
		tn.position.x = sw * float(i)
		col.add_child(tn)

	var pb := _nine9(POINT_FRAME, Vector2(cw, 41.0 * Design.ASSET_SCALE),
		Rect2(30, 20, 4, 4), CO)
	if pb != null:
		pb.position = Vector2(PAD, py + 88.0)
		col.add_child(pb)
	var mode_name := String(Colosseum.mode_cfg(_board_mode).get("label", "")).to_upper()
	col.add_child(_center_label("%s  %d 점" % [mode_name, rating], col.size.x, py + 100.0, 21))

	col.add_child(_center_label("%d위  ·  %d연승 (최고 %d)" % [
		Colosseum.my_rank(_board_mode, _weekly), streak, int(s.get(
		"straight_single_best" if _board_mode == "single" else "straight_team_best", 0))],
		col.size.x, py + 148.0, 17, Color(1.0, 0.92, 0.7)))

	var have := int(s.get(Colosseum.energy_keys(_board_mode)[0], 0))
	var mx := int(Data.colosseum.get("ticket", {}).get("max", 10))
	var gy := py + 196.0
	var gw := 125.0 * Design.ASSET_SCALE
	var gx := col.size.x * 0.5 - gw * 0.5
	var gbg := _spr(CO, "scene_colosseum_stamina_bar_bg", Design.ASSET_SCALE)
	if gbg != null:
		gbg.position = Vector2(col.size.x * 0.5, gy)
		col.add_child(gbg)
	var gt := _tex(CO, "scene_colosseum_stamina_bar")
	if gt != null and have > 0:
		var ratio := clampf(float(have) / float(maxi(1, mx)), 0.0, 1.0)
		var fill := Sprite2D.new()
		fill.texture = gt
		fill.material = _pma
		fill.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		fill.region_enabled = true
		fill.region_rect = Rect2(0, 0, float(gt.get_width()) * ratio, gt.get_height())
		fill.position = Vector2(gx + gw * ratio * 0.5, gy)
		col.add_child(fill)
	col.add_child(_center_label("%s 피로도 %d / %d"
		% [String(Colosseum.mode_cfg(_board_mode).get("label", "")), have, mx],
		col.size.x, gy + 14.0, 17))
	_eta_label = _center_label("", col.size.x, gy + 36.0, 15, ETA_COLOR)
	col.add_child(_eta_label)
	_eta_energy = have
	_tick_eta()
	_start_eta_timer()

	var bw := cw - 40.0
	AtlasUI.frame_button(col, "나가기",
		Vector2(20.0, vis.y - BTN_MENU_H * 2.0 - BTN_BOTTOM - BTN_GAP - 54.0),
		Vector2(bw, 42.0),
		func() -> void: Scenes.goto_main({"from": "colosseum"}))

const ETA_COLOR := Color(0.86, 0.9, 1.0, 0.85)

func _start_eta_timer() -> void:
	if is_instance_valid(_eta_timer):
		return
	_eta_timer = Timer.new()
	_eta_timer.wait_time = 1.0
	_eta_timer.autostart = true
	_eta_timer.timeout.connect(_tick_eta)
	add_child(_eta_timer)

func _tick_eta() -> void:
	var log: Dictionary = Data.colosseum.get("log", {})
	var mx := Colosseum.ticket_max()
	for key in _mode_eta:
		var lb = _mode_eta[key]
		if not is_instance_valid(lb):
			continue
		var e := Colosseum.ticket_eta(String(key))
		lb.text = "%02d:%02d" % [e / 60, e % 60] if e > 0 else ""
	if not is_instance_valid(_eta_label):
		return
	if _eta_energy >= mx:
		_eta_label.text = String(log.get("ticket_full", "피로도가 가득 찼습니다."))
		return
	var eta := Colosseum.ticket_eta(_board_mode)
	if eta > 0:
		_eta_label.text = String(log.get("ticket_eta", "다음 회복까지 %s")) \
			% ("%02d:%02d" % [eta / 60, eta % 60])
		return
	var changed := false
	for key in (Data.colosseum.get("modes", {}) as Dictionary):
		var m := String(key)
		var ek: String = Colosseum.energy_keys(m)[0]
		if int(Colosseum.refresh_ticket(m).get(ek, 0)) != _mode_energy.get(m, -1):
			changed = true
	if changed:
		_rebuild()

var _bmfonts := {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f

func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _notice(msg: String) -> void:
	Toast.show(self, msg)

func _reset_phrase() -> String:
	var drop := Colosseum.season_tier_drop()
	return "레이팅, 티어," if drop <= 0 else "티어가 %d단계 내려가고," % drop

func _outlined(l: Label) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04, 0.92))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _center_label(text: String, w: float, y: float, size: int,
		col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.size = Vector2(w, float(size) + 8.0)
	l.position = Vector2(0.0, y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	return l

func _vis() -> Vector2:
	return get_viewport_rect().size

func _tex(dir: String, key: String) -> Texture2D:
	return AtlasUI.tex(dir, key)

func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	return AtlasUI.spr(dir, key, scale)

func _nine(key: String, sz_pt: Vector2, cap: Rect2) -> NinePatchRect:
	return _nine9(key, sz_pt, cap, NP)

func _nine9(key: String, sz_pt: Vector2, cap: Rect2, dir: String) -> NinePatchRect:
	var tex := _tex(dir, key)
	if tex == null:
		return null
	var inv := 1.0 / Design.ASSET_SCALE
	var l := tex.get_width() / 3.0
	var t := tex.get_height() / 3.0
	var cw := l
	var ch := t
	if cap.size != Vector2.ZERO:
		l = cap.position.x * inv; t = cap.position.y * inv
		cw = cap.size.x * inv; ch = cap.size.y * inv
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - ch)))
	np.size = sz_pt if sz_pt.y > 0.0 else Vector2(sz_pt.x, float(tex.get_height()) * Design.ASSET_SCALE)
	np.material = _pma
	return np
