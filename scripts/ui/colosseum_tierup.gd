class_name ColosseumTierupView
extends RefCounted

const CM := "common_ui"

static func open(host: Node, res: Dictionary) -> FramedWindow:
	var after: Dictionary = res.get("tier_after", {})
	var before: Dictionary = res.get("tier_before", {})
	var up := bool(res.get("tier_up", false))
	var p := FramedWindow.open(host, "티어 승급" if up else "티어 강등", Vector2(560.0, 420.0))
	var w := p.win_size.x

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
