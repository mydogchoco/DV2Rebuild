class_name ColosseumTierupPopup
extends RefCounted
## 콜로세움 티어 승급 팝업 — 원작 `ColosseumTierupPopup` 대응. render 층(§8).
##
## ## 원작 구조 (initWidget @00f922b4, 3,656B)
## 이 창은 **NPC 가 축하해 주는 팝업**이다:
##     CCLayer::create()
##     NpcManager::create() → setTarget(…, 2, 2, 2, 0)
##                          → setNpcEye(…) / setNpcMouse(…) / setEmoticon(4, true)
## 즉 눈·입 파츠가 움직이는 NPC 한 명 + 승급 문구 + 확인 버튼 구성이다.
##
## ## 못 쓰는 것 (§10 판본 불일치)
##   `scene/colosseum/redmedal.png`  — 승급 메달. 전 아틀라스 **0건**
##   `new9patch/colosseum_btn.png`   — 전용 버튼. `new9patch/` 폴더 자체가 없다
##   (`scene/auction/bt_arrow_right.png` 만 보유)
##
## ## 그래서 어떻게 했나
## 메달 자리는 **원작 티어 아이콘**(`common/tier_icon_<tier>.png`, 보유)으로 대신한다 —
## 승급의 주인공이 티어이므로 의미가 어긋나지 않고, 자작 도형이 아니다.
## 창은 보유 `OrigPopup`(9patch/popup4 + pop_title_bg + common/close_btn).
##
## ⚠️ **NPC 는 넣지 않았다.** `setTarget(…, 2, 2, 2, 0)` 의 `2` 가 어느 NPC 인지 특정할 근거를
##   못 찾았다(NpcManager 의 인자 규약을 확정하지 못했다). 아무나 세우면 그게 자작이 된다
##   (HARD RULE 6). NPC 를 특정하면 `_build` 에 `NpcTalkLayer` 계열을 한 줄 얹으면 된다.

const CM := "common_ui"


## 승급 팝업을 띄운다. `res` = `Colosseum.apply_result()` 반환값.
static func open(host: Node, res: Dictionary) -> OrigPopup:
	var after: Dictionary = res.get("tier_after", {})
	var before: Dictionary = res.get("tier_before", {})
	var up := bool(res.get("tier_up", false))
	var p := OrigPopup.open(host, "티어 승급" if up else "티어 강등", Vector2(560.0, 420.0))
	var w := p.win_size.x

	# 메달 자리 = 티어 아이콘(원작 redmedal 미보유 대체).
	var rating := int(res.get("rating_after", 0))
	var frame := Colosseum.tier_frame(rating, "icon")
	if frame != "":
		var key := "common_" + frame.get_slice("/", 1).replace(".png", "")
		var path := "res://assets/converted/%s/%s.tres" % [CM, key]
		if ResourceLoader.exists(path):
			var s := Sprite2D.new()
			s.texture = load(path)
			s.scale = Vector2.ONE * Design.ASSET_SCALE * 1.5
			s.position = Vector2(w * 0.5, 150.0)
			p.content.add_child(s)

	var name_lb := Label.new()
	name_lb.text = String(after.get("name", ""))
	name_lb.size = Vector2(w, 44.0)
	name_lb.position = Vector2(0.0, 200.0)
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lb.add_theme_font_size_override("font_size", 34)
	name_lb.modulate = Color(1.0, 0.9, 0.45) if up else Color(0.8, 0.8, 0.85)
	p.content.add_child(name_lb)

	var msg := Label.new()
	msg.text = ("%s 에서 %s 로 승급했습니다!" if up else "%s 에서 %s 로 강등되었습니다.") % [
		String(before.get("name", "")), String(after.get("name", ""))]
	msg.size = Vector2(w, 40.0)
	msg.position = Vector2(0.0, 256.0)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 20)
	p.content.add_child(msg)

	# 원작 `Colosseum_Word_3` = "%1$d점".
	var pt := Label.new()
	pt.text = "%d점" % rating
	pt.size = Vector2(w, 32.0)
	pt.position = Vector2(0.0, 296.0)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pt.add_theme_font_size_override("font_size", 22)
	pt.modulate = Color(0.85, 0.82, 0.7)
	p.content.add_child(pt)

	AtlasUI.frame_button(p.content, "확인", Vector2(w * 0.5 - 110.0, 340.0),
		Vector2(220.0, 52.0), func() -> void: p.queue_free())
	return p
