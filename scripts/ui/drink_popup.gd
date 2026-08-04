class_name DrinkPopup
extends CanvasLayer
## 드링크(버프 물약) 먹이기 창 — 원작 `DrinkPopup` @01182074 이식. render 층(§8).
##
## ## 왜 만들었나
## 상태창(`CharacterInfoPopup`)의 드링크 칸이 "미구현"으로 막혀 있었다(사용자 지적 2026-08-05).
## 정작 **드링크 시스템은 이미 다 있었다** — 규칙·수치 `data/item_effects.json`
## (위키 item.pdf §2.3 + 사용자 확정 2026-07-26), 판정 `ItemEffect.drink_of/apply_drink`,
## 저장 `UserDB` 드래곤의 `drink_buffs`, 전투 반영 `PartyStats.summary`(배율),
## 턴 차감 `battle.gd`. **배선만 없었다.**
##
## ## 원작
##   진입: `CharacterInfoPopup::setClickInfo` — 드링크 칸(태그 4) → `DrinkPopup::create(dragon)`
##   창  : `PopupLayer::setContentSprite(..., "9patch/popup4.png", CCRect(130,190,40,58))`
##         + `common/close_btn.png` · 목록 `9patch/scroll_box.png` · 칸 `9patch/text_box.png`
##   확정: `onClickConfirm` → `RequestDrink`(서버) ⚫ 컷 → 우리는 로컬에서 바로 적용
##   갱신: `CharacterInfoPopup::setReloadPopupForDrink` = **패널을 통째로 다시 그린다**
##         ⇒ 우리도 콜백으로 호출자가 다시 그리게 한다.
##
## ⚠️ 원작 `Dragon::getBuf()` 는 **먹고 있는 드링크 아이템 하나**를 들고 있고 칸에 그 아이콘을
##    그린다. 우리 `drink_buffs` 는 **능력치 축별 누적**({att:{pct,turns}, …})이라 아이템이
##    아니라 축이 남는다 — 칸 그림은 그 축의 대표 아이템 아이콘으로 낸다(`status_layer`).

const NP := "ninepatch_ui"
const CM := "common_ui"
const PANEL := Vector2(560.0, 460.0)
const POPUP4_CAP := Rect2(130, 190, 40, 58)     # 원작 setContentSprite 의 CCRect
const ROW_H := 64.0
const ROW_GAP := 6.0

var _uid := -1
var _on_used := Callable()


## `host` 위에 띄운다. `on_used` 는 드링크를 실제로 먹였을 때만 불린다(패널 재작성용).
static func open(host: Node, uid: int, on_used := Callable()) -> DrinkPopup:
	var p := DrinkPopup.new()
	p.layer = 40
	p._uid = uid
	p._on_used = on_used
	host.add_child(p)
	return p


func _ready() -> void:
	var vis := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = vis
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)

	var root := Control.new()
	root.size = PANEL
	root.position = (vis - PANEL) * 0.5
	add_child(root)

	var bg := AtlasUI.nine(NP, "9patch_popup4", PANEL, POPUP4_CAP)
	if bg != null:
		root.add_child(bg)

	var title := AtlasUI.nine(NP, "9patch_pop_title_bg", Vector2(300.0, 44.0), Rect2())
	if title != null:
		title.position = Vector2((PANEL.x - 300.0) * 0.5, 2.0)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(title)
	var tl := Label.new()
	tl.text = "드링크"
	tl.size = Vector2(300.0, 44.0)
	tl.position = Vector2((PANEL.x - 300.0) * 0.5, 2.0)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)

	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		var xb := TextureButton.new()
		xb.texture_normal = load(xt)
		xb.position = Vector2(PANEL.x - 58.0, 8.0)
		xb.pressed.connect(func(): queue_free())
		root.add_child(xb)

	# 목록 — 원작 `9patch/scroll_box`.
	var list_size := Vector2(PANEL.x - 60.0, PANEL.y - 110.0)
	var box := AtlasUI.nine(NP, "9patch_scroll_box", list_size, Rect2())
	if box != null:
		box.position = Vector2(30.0, 66.0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
	var sc := ScrollContainer.new()
	sc.position = Vector2(38.0, 74.0)
	sc.size = list_size - Vector2(16.0, 16.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(ROW_GAP))
	col.custom_minimum_size.x = sc.size.x
	sc.add_child(col)

	var rows := _owned()
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "가진 드링크가 없습니다.\n(상점 · 전투 보상에서 얻습니다)"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(sc.size.x, 120.0)
		empty.add_theme_font_size_override("font_size", 20)
		col.add_child(empty)
		return
	for row: Dictionary in rows:
		col.add_child(_row(String(row["key"]), row["def"], int(row["count"]),
			row["eff"], sc.size.x))


## 보유 중인 드링크 목록(키 정렬 — 같은 세이브면 항상 같은 순서).
func _owned() -> Array:
	var out: Array = []
	var defs: Dictionary = Data.item_effects
	var keys: Array = Data.items.keys() if Data.items is Dictionary else []
	keys.sort()
	for k in keys:
		var key := String(k)
		var eff := ItemEffect.drink_of(defs, key)
		if eff.is_empty():
			continue
		var n := UserDB.item_count(key)
		if n <= 0:
			continue
		out.append({"key": key, "def": Data.items[key], "count": n, "eff": eff})
	return out


const STAT_KR := {"att": "공격력", "def": "방어력", "hp": "생명력",
	"crit": "크리티컬", "dodge": "회피", "block": "방어확률"}

func _row(key: String, idef: Dictionary, count: int, eff: Dictionary, w: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(w, ROW_H)
	# 원작 칸 배경 `9patch/text_box`.
	var rb := AtlasUI.nine(NP, "9patch_text_box", Vector2(w, ROW_H), Rect2())
	if rb != null:
		rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(rb)

	var ip := Data.item_icon_path(key)
	if ip != "" and ResourceLoader.exists(ip):
		var ic := TextureRect.new()
		ic.texture = load(ip)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(52.0, 52.0)
		ic.position = Vector2(8.0, 6.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)

	var nm := Label.new()
	nm.text = "%s  ×%d" % [String(idef.get("name", key)), count]
	nm.position = Vector2(70.0, 6.0)
	nm.size = Vector2(w - 190.0, 26.0)
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", Color(0.24, 0.2, 0.14))   # 양피지 판 위 글씨
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	var ds := Label.new()
	ds.text = "%s +%d%%  ·  %d턴" % [
		String(STAT_KR.get(String(eff["stat"]), String(eff["stat"]))),
		int(eff["pct"]), int(eff["turns"])]
	ds.position = Vector2(70.0, 32.0)
	ds.size = Vector2(w - 190.0, 24.0)
	ds.add_theme_font_size_override("font_size", 17)
	ds.add_theme_color_override("font_color", Color(0.45, 0.33, 0.18))
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ds)

	AtlasUI.frame_button(row, "먹이기", Vector2(w - 112.0, 12.0), Vector2(100.0, 40.0),
		func() -> void: _use(key, eff), 0, false, 18)
	return row


## 원작 `onClickConfirm` → `RequestDrink`(⚫ 서버) 의 자리. 우리는 로컬에서 바로 적용한다.
## 판정·수치는 `cave.gd::_use_food` 의 드링크 분기와 **같은 통로**다(§8 logic 재사용).
func _use(key: String, eff: Dictionary) -> void:
	if UserDB.item_count(key) <= 0 or _uid < 0:
		return
	var cur: Dictionary = UserDB.get_dragon(_uid).get("drink_buffs", {})
	UserDB.set_dragon_field(_uid, "drink_buffs", ItemEffect.apply_drink(cur, eff))
	UserDB.add_item(key, -1)
	Bgm.sfx("effect_button")
	Toast.show(get_tree().root, "%s +%d%%  (%d턴)" % [
		String(STAT_KR.get(String(eff["stat"]), String(eff["stat"]))),
		int(eff["pct"]), int(eff["turns"])])
	var cb := _on_used
	queue_free()
	if cb.is_valid():
		cb.call()
