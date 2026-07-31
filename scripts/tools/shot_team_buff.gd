extends SceneTree
## 조합 팀버프 연출(`CombineElements`) 시각 검증 — 레퍼런스 `docs/ref/TeamBuff/*.png` 대조용.
##
## 원작 연출을 단독으로 띄우고 지정한 시각에 스크린샷을 찍는다(전투 씬 없이 render 층만).
## 실행(헤드리스 아님):
##   Godot --path . --script res://scripts/tools/shot_team_buff.gd -- [<버프no>] [<출력폴더>]
## 기본 = 버프 15(`물빛 섬광`, aqualight) — 레퍼런스 영상과 같은 버프.
##
## 찍는 시각은 레퍼런스 25프레임과 대응시키기 좋은 지점들이다(포팅 카드 §5 타임라인):
##   1.4  첫 원소만 · 2.0 원소 3종 정렬(레퍼런스 6.png) · 3.0 궤도 회전(10.png)
##   3.8  흰 룬 원환만(14.png) · 3.95 충격파(16.png) · 4.6 문양 정착(18.png)
##   5.5  버프명+효과 2줄 · 6.2 효과 3줄(21.png) · 7.3 소멸 직전(25.png)

const SHOTS := [1.4, 2.0, 3.0, 3.8, 3.95, 4.6, 5.5, 6.2, 7.3]

var _t := 0.0
var _i := 0
var _out := "user://team_buff"
var _layer: Node = null
var _table: Dictionary = {}
var _elements: Array = []
var _buff: Dictionary = {}


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var no := int(a[0]) if a.size() > 0 else 15
	if a.size() > 1:
		_out = a[1]
	DirAccess.make_dir_recursive_absolute(_out)

	# --script 모드엔 오토로드가 없다 → 마스터 데이터를 직접 읽는다.
	_table = _json("res://data/team_buffs.json")
	var buff := _find_buff(no)
	if buff.is_empty():
		push_error("team_buffs.json 에 no=%d 가 없다" % no)
		quit(1); return
	var elements := _elements_of(buff)
	print("[shot_team_buff] no=%d %s  img=%s  elements=%s" % [
		no, buff.get("name", "?"), buff.get("img", "-"), str(elements)])
	print("[shot_team_buff] 효과 줄 = ", CombineElements.option_lines(buff, _table))

	# 어두운 배경(원작 전투 화면 자리) — 연출 자체가 검은 암막을 깔지만 그 전 0.25초를 보기 위해.
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.16)
	bg.size = get_root().get_visible_rect().size
	get_root().add_child(bg)

	_elements = elements
	_buff = buff
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	# 첫 프레임에 만든다 — `_initialize()` 시점엔 루트가 아직 SceneTree 에 물려 있지 않아
	# 자식 노드의 `get_tree()` 가 null 이다(툴 하니스 전용 사정).
	if _layer == null:
		_layer = CombineElements.play(get_root(), _elements, _buff, _table)
		if _layer == null:
			push_error("CombineElements.play 실패 — 아이콘(img) 없는 버프인가?")
			quit(1); return
		return
	_t += get_root().get_process_delta_time()
	while _i < SHOTS.size() and _t >= SHOTS[_i]:
		var p := "%s/t%03d.png" % [_out, int(round(SHOTS[_i] * 100))]
		get_root().get_texture().get_image().save_png(p)
		print("  saved %s (t=%.2f)" % [p, _t])
		_i += 1
	if _t > CombineElements.TOTAL + 0.3:
		var alive := is_instance_valid(_layer)
		print("[shot_team_buff] 종료 — 레이어 자동 정리됨: ", not alive)
		quit(0 if not alive else 1)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _find_buff(no: int) -> Dictionary:
	for b in (_table.get("buffs", []) as Array):
		if int((b as Dictionary).get("no", 0)) == no:
			return b
	return {}


## 그 버프를 발동시키는 파티 속성 3종을 combine 에서 펼친다(원작 getDragonRaces 와 같은 전개).
func _elements_of(buff: Dictionary) -> Array:
	var out: Array = []
	for race in (buff.get("combine", {}) as Dictionary):
		for _n in int((buff["combine"] as Dictionary)[race]):
			out.append(String(race))
	return out
