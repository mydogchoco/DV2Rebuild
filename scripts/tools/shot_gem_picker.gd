extends SceneTree
## 젬 분해 화면 + 젬 고르기 팝업(원작 `MagicSelectLayer`) 시각 검수용 드라이버.
##
## 실행(헤드리스 아님 — 뷰포트를 실제로 그려야 한다):
##   godot --path . --script res://scripts/tools/shot_gem_picker.gd -- <out_dir>
##
## 가방에 젬이 없으면 아무것도 안 보이므로 **메모리 상에서만** 몇 개 넣는다(세이브 안 함).

var _out := "user://"
var _step := 0
var _shop: Node


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	process_frame.connect(_tick)


func _tick() -> void:
	_step += 1
	if _step == 2:
		# `--script` 로 띄운 SceneTree 에선 오토로드가 전역 식별자로 안 잡힌다 → 노드로 집는다.
		var udb := get_root().get_node_or_null("UserDB")
		var gem := load("res://scripts/systems/gem.gd")
		# 검수용 젬 — 참조 영상(젬분해3)과 같은 구도가 되도록 수량을 크게 준다.
		for row in [["공격의 젬", 16, 12], ["공격의 젬", 12, 1207], ["체력의 젬", 8, 642],
				["방어의 젬", 3, 597], ["공방젬", 18, 4]]:
			udb.add_item(gem.item_key(String((row as Array)[0]), int((row as Array)[1])),
				int((row as Array)[2]))
		var ps: PackedScene = load("res://scenes/magicshop.tscn")
		_shop = ps.instantiate()
		get_root().add_child(_shop)
		if _shop.has_method("enter"):
			_shop.enter({})
	elif _step == 8:
		_shop._set_floor(1)                       # 지하(연금술)
	elif _step == 14:
		_shop._open_feature(2)                    # 지하 3번째 카드 = 젬 분해
	elif _step == 20:
		_save("disassemble.png")
	elif _step == 24:
		_shop._dis_click_slot(0)                  # 빈 칸 → 젬 고르기 팝업
	elif _step == 30:
		_save("picker_grid.png")
		# 첫 셀을 눌러 우측 상세(수량 ▲▼)를 띄운다.
		var b := _first_cell_button(_shop)
		if b != null:
			b.emit_signal("pressed")
	elif _step == 36:
		_save("picker_detail.png")
		quit(0)
	elif _step > 60:
		printerr("timeout")
		quit(1)


## 팝업 격자의 첫 셀 버튼을 찾는다(GridContainer > Panel > Button).
func _first_cell_button(n: Node) -> Button:
	if n is GridContainer:
		for cell in n.get_children():
			for c in cell.get_children():
				if c is Button:
					return c
	for ch in n.get_children():
		var r := _first_cell_button(ch)
		if r != null:
			return r
	return null


func _save(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var p := "%s/%s" % [_out.rstrip("/"), name]
	img.save_png(p)
	print("saved: ", p)
