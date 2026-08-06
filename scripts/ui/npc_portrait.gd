class_name NpcPortrait
extends Node2D
## 원작 `NpcManager` 포팅 — 대화용 NPC 반신 초상(몸통 + 눈 + 입).
## render 층(CLAUDE.md §8.1). 상점·점술집·연구소·육성이 공유한다.
##
## 원작 구조(docs/ref/orig_code/decomp/NpcManager.c):
##   · 몸통  = `npc/<name>/body_<b>.png`, **앵커 (0.5, 0)** — 발밑이 기준점.
##   · 눈    = `npc/<name>/eye_<e>_<f>.png`   — setNpcEye  가 몸통 로컬 +0x150 위치에 붙인다.
##   · 입    = `npc/<name>/mouth_<e>_<f>.png` — setNpcMouse 가 몸통 로컬 +0x15c 위치에 붙인다.
##   · `<e>` = 표정(emotion) index, `<f>` = 애니 프레임(1=감음/다뭄 … 3=뜸/벌림).
##   · 화면 배치는 `getDefaultNpcPos(int)` — 1=왼쪽, 2=오른쪽, 3=가운데.
##
## ⚠️ 눈·입 스프라이트의 **앵커는 (0, 1) = 좌상단**이다.
##   근거: `setNpcEye` @014d6480 :2142 / `setNpcMouse` @014d6c40 — 프레임을 만든 직후
##   `CCPoint::CCPoint(anchor, 0.0, 1.0)` + vtable 0xf0(setAnchorPoint) 를 호출한다.
##   즉 +0x150/+0x15c 좌표는 파츠의 **중심이 아니라 좌상단 모서리**다. (중심으로 오해하면
##   파츠가 원본 크기의 절반만큼 왼쪽·위로 밀려 머리 밖으로 튀어나간다 — 실제로 났던 버그.)
##
## 좌표: 원작 값은 **포인트**(몸통 contentSize 기준, y-up, 원점 좌하단)다.
##   `data/npc_face.json` 은 이를 "몸통 위에서 아래로 내려간 거리"로 저장한다
##   (추출기 `scripts/tools/extract_npc_face.py`). 여기서 `Design.ASSET_SCALE` 로 나눠
##   텍스처 픽셀 좌표로 되돌린 뒤 몸통 스프라이트의 자식으로 붙인다(스케일은 상속).
##
## ⚠️ 표정별 좌표 차이는 최대 3pt 수준이라, 디컴프 제어흐름이 접혀 표정을 특정하지 못한
##   NPC(`"?"` 키)는 그 한 벌을 모든 표정에 쓴다.
##
## ⚠️ 표정 세트는 **좌표(`npc_face.json`)와 프레임(아틀라스)이 서로 다르게 빠져 있다.**
##   예: baruseu 는 좌표가 `"?"` 한 벌뿐이고 눈 프레임은 `eye_{1,3,4}_1` 만 있다
##   (프레임 2·3 없음 = 그 표정은 눈을 안 깜빡인다). raon 은 좌표가 6번뿐인데 프레임은
##   1·2·3·4·6 이 있다. 그래서 **좌표용 표정**(`_face_pos`)과 **그림용 표정**(`_art_emo`)을
##   따로 고른다. 눈·입은 반드시 같은 `_art_emo` 를 써야 표정이 섞이지 않는다.

## 애니 타이밍 — 원작 `setNextEye`/`setNextMouse`(NpcManager.c:1459 / :1722).
## 프레임은 **1→2→3→1 순환**이고, **1번이 쉬는 자세(눈 뜸/입 다뭄)** 라 혼자 길게 머문다.
##   · 프레임 1: delay = rand[0, HOLD) — 0.3 미만이면 +0.2 ⇒ 실질 0.2~3.0초
##   · 그 외   : delay = rand[0, FAST) ⇒ 0~0.1초 (깜빡임은 순식간에 지나간다)
## 인자값 근거: `ShopScene::setSeller` 가 넘기는 리터럴
##   `setSellerShow(0x3dcccccd, 0x40400000, 0x3cf5c28f, 0x3cf5c28f, …)` @ShopScene.c:4767
##   = (0.1, 3.0) 눈 · (0.03, 0.03) 입. `DragonAwaken.c:1212` 도 눈 (0.1, 3.0) 로 같다.
const EYE_FAST := 0.1
const EYE_HOLD := 3.0
const MOUTH_STEP := 0.03
const FIRST_DELAY := 0.15   # 원작 setNpcEye/setNpcMouse 의 최초 CCDelayTime(0.15)

var npc_name: String = ""
var emotion: int = 1
var _body: Sprite2D
var _eye: Sprite2D
var _mouth: Sprite2D
var _man: Dictionary = {}
var _dir: String = ""
var _body_key: String = ""
var _art_emo: int = 1                # 실제로 프레임을 가진 표정(그림용)
var _eye_tl := Vector2.ZERO          # 눈  원본 박스 좌상단(몸통 중앙 기준, 텍스처 px)
var _mouth_tl := Vector2.ZERO        # 입  〃
var _eye_fr: Array = []              # 이 표정이 가진 눈 프레임 번호(순환 순서)
var _mouth_fr: Array = []
var _eye_i := 0                      # 원작 NpcManager +0x88 (현재 프레임 index)
var _mouth_i := 0                    #   〃      +0x8c
var _eye_next := FIRST_DELAY
var _mouth_next := FIRST_DELAY
var _t := 0.0
var _talking := false

## npc = 원작 폴더명(pino/popo/randolph/raon/baruseu/romini …), emotion = 표정 index.
## body_index 는 원작 setTarget 의 body 번호(대개 1).
## `body_index` = 원작 `setTalker` 의 몸통 인자. 상점·점술집·연구소·육성은 전부 **1** 이다.
static func create(npc: String, emotion_idx := 1, body_index := 1) -> NpcPortrait:
	var n := NpcPortrait.new()
	n.npc_name = npc
	n.emotion = emotion_idx
	n._build(body_index)
	return n

## 정수 후보 중 want 에 가장 가까운 값(동률이면 작은 쪽).
static func _nearest(nums: Array, want: int) -> int:
	nums.sort()
	var best: int = nums[0]
	for v in nums:
		if absi(int(v) - want) < absi(best - want):
			best = int(v)
	return best

func _build(body_index: int) -> void:
	_dir = "npc_%s" % npc_name
	_man = _manifest(_dir)
	if _man.is_empty():
		push_warning("[NpcPortrait] 매니페스트 없음: %s" % _dir)
		return
	# 몸통 인자는 원작 `NpcManager::setTarget` 이 받는 값 그대로다. UI 씬(상점·점술집·연구소·
	# 육성)의 `setTalker` 호출부는 **전부 1** 을 넘긴다(`MagicShopScene.c:1373·1466·1489…`).
	# `body_3`·`body_5` 같은 다른 포즈는 스토리 컷씬 쪽에서 쓰인다(사용자 확인 2026-07-28).
	var bkey := "npc_%s_body_%d" % [npc_name, body_index]
	if not _man.has(bkey):
		bkey = "npc_%s_body_1" % npc_name
	_body_key = bkey
	_body = _sprite(bkey, Design.ASSET_SCALE)
	if _body == null:
		return
	# 원작 앵커 (0.5, 0) = 하단 중앙 → Godot 중앙 앵커 스프라이트를 위로 반만큼 올린다.
	var bh: float = float(_man[bkey].get("h", 0)) * Design.ASSET_SCALE
	_body.position = Vector2(0, -bh * 0.5)
	add_child(_body)

	_art_emo = _resolve_art_emotion()
	_eye_fr = _frames("eye", _art_emo)
	_mouth_fr = _frames("mouth", _art_emo)
	_drop_duplicate_mouth()
	var pos := _face_pos()
	_eye = _attach_part("eye", pos.get("eye", null))
	_mouth = _attach_part("mouth", pos.get("mouth", null))

## 입 프레임이 눈 프레임과 **같은 그림**이면 입을 그리지 않는다.
##
## 🔴 2026-07-31 (사용자 신고 "퐁 눈이 4개"): 임프 퐁의 아틀라스는 `mouth_1_1` 이
##   `eye_1_1`(뜬 눈)과 **완전히 같은 region**(160,324,77,23)이다 — 입 그림이 따로 없고
##   눈 프레임을 재사용한다. 둘 다 그리면 눈 한 쌍이 입 자리에 또 그려져 **눈이 네 개**가 된다.
##   프레임 자체를 비교하므로 퐁 말고 같은 사정인 NPC 가 있어도 함께 걸린다.
func _drop_duplicate_mouth() -> void:
	if _eye_fr.is_empty() or _mouth_fr.is_empty():
		return
	var er := _region_of("eye", _eye_fr[0])
	var mr := _region_of("mouth", _mouth_fr[0])
	if er != Rect2() and er == mr:
		_mouth_fr = []

## 그 파츠 프레임의 아틀라스 region. 없으면 Rect2().
func _region_of(slot: String, frame: int) -> Rect2:
	var key := "npc_%s_%s_%d_%d" % [npc_name, slot, _art_emo, frame]
	var path := "res://assets/converted/%s/%s.tres" % [_dir, key]
	if not ResourceLoader.exists(path):
		return Rect2()
	var t := load(path)
	return (t as AtlasTexture).region if t is AtlasTexture else Rect2()

## 표정만 갈아끼운다(몸통은 그대로). 원작 `setTalker` 는 **대사를 낼 때마다** 표정을 바꾼다 —
## `NpcManager::setTarget` → `setNpcEye` / `setNpcMouse` 가 매 호출 새 표정으로 파츠를 다시 붙인다.
## 각 기능 레이어가 자기 상황의 표정을 지정해 부른다(예: `GemCraftLayer`·`SlotLayer` 는 실패 반응에
## 4, `MateLayer` 는 7). 그래서 진입 표정보다 실제로 보이는 표정이 더 다양하다.
##
## ⚠️ 전용 몸통이 있는 표정(`body_<n>`, n≠1 — 유리아 5 등)은 이 씬의 몸통 1과 짝이 아니라
##    받아도 무시한다(`AtlasUI.npc_emotions` 와 같은 기준).
func set_emotion(e: int) -> void:
	if e <= 0 or e == emotion or _body == null:
		return
	if _man.has("npc_%s_body_%d" % [npc_name, e]) and _body_key != "npc_%s_body_%d" % [npc_name, e]:
		return                          # 컷씬 전용 포즈 표정 — UI 몸통에 얹지 않는다
	if _frames("eye", e).is_empty() and _frames("mouth", e).is_empty():
		return                          # 그림이 없는 표정
	emotion = e
	for part in [_eye, _mouth]:
		if part != null:
			_body.remove_child(part)
			part.queue_free()
	_eye = null
	_mouth = null
	_art_emo = _resolve_art_emotion()
	_eye_fr = _frames("eye", _art_emo)
	_mouth_fr = _frames("mouth", _art_emo)
	_drop_duplicate_mouth()
	_eye_i = 0
	_mouth_i = 0
	_eye_next = _t + FIRST_DELAY
	_mouth_next = _t + FIRST_DELAY
	var pos := _face_pos()
	_eye = _attach_part("eye", pos.get("eye", null))
	_mouth = _attach_part("mouth", pos.get("mouth", null))

## data/npc_face.json 에서 이 NPC/표정의 눈·입 좌표를 꺼낸다.
## 요청 표정 → "?"(표정 미상 한 벌) → 가장 가까운 번호 순.
func _face_pos() -> Dictionary:
	var all: Dictionary = Data.npc_face.get("npc", {})
	var per: Dictionary = all.get(npc_name, {})
	if per.is_empty():
		return {}
	for key in [str(emotion), "?"]:
		if per.has(key):
			return per[key]
	var nums: Array = []
	for k in per.keys():
		if String(k).is_valid_int():
			nums.append(int(k))
	if nums.is_empty():
		return per.values()[0]
	return per[str(_nearest(nums, emotion))]

## 눈·입 프레임을 실제로 가진 표정. 요청 표정에 프레임이 없으면 가장 가까운 보유 표정으로.
## ⚠️ 눈과 입이 서로 다른 표정에서 오면 얼굴이 섞인다 → 반드시 한 번만 정해 공유한다.
func _resolve_art_emotion() -> int:
	var have: Array = []
	for e in range(1, 10):
		if not _frames("eye", e).is_empty() or not _frames("mouth", e).is_empty():
			have.append(e)
	if have.is_empty() or emotion in have:
		return emotion
	return _nearest(have, emotion)

## 그 슬롯/표정이 가진 애니 프레임 번호(오름차순). 원작 InfoNpc +0x158(눈)/+0x164(입) 개수에 해당.
func _frames(slot: String, emo: int) -> Array:
	var out: Array = []
	for f in range(1, 4):
		if _man.has("npc_%s_%s_%d_%d" % [npc_name, slot, emo, f]):
			out.append(f)
	return out

## 파츠 1개를 몸통의 자식으로 붙인다. `slot_pos` = [x, 위에서부터의 y] (포인트, 파츠 **좌상단**).
## 시작 프레임은 원작과 같이 배열 0번(= 프레임 1 = 눈 뜸 / 입 다뭄)이다.
func _attach_part(slot: String, slot_pos) -> Sprite2D:
	if _body == null or slot_pos == null or not (slot_pos is Array):
		return null
	var frames: Array = _eye_fr if slot == "eye" else _mouth_fr
	if frames.is_empty():
		return null
	# 추출 실패 기본값. (0,0) = 몸통 좌상단 모서리라 얼굴 파츠 좌표일 수 없다.
	# (2026-08-01 현재 해당 없음 — 종전 6종은 원작이 파츠를 **화면 밖으로 치우는** 자리였고
	#  추출기가 그 형태를 `fVar` 변수형까지 읽게 되면서 전부 null(미표시)로 바뀌었다.)
	if is_zero_approx(float(slot_pos[0])) and is_zero_approx(float(slot_pos[1])):
		push_warning("[NpcPortrait] %s/%s 좌표 미추출(0,0) — 미표시" % [npc_name, slot])
		return null
	var key := "npc_%s_%s_%d_%d" % [npc_name, slot, _art_emo, frames[0]]
	var s := _sprite(key, 1.0)          # 몸통의 scale 을 상속하므로 여기선 1.0
	if s == null:
		return null
	var bi: Dictionary = _man.get(_body_key, {})
	var S := Design.ASSET_SCALE
	# 포인트 → 픽셀, 그리고 몸통 중앙 앵커 기준 상대좌표로. 여기까지가 파츠의 **좌상단**.
	var tl := Vector2(
		float(slot_pos[0]) / S - float(bi.get("w", 0)) * 0.5,
		float(slot_pos[1]) / S - float(bi.get("h", 0)) * 0.5)
	# 눈맞춤 보정 — `data/npc_face.json` `nudge`(디자인 px). 원작 좌표는 그대로 두고
	# 우리 몸통 프레임 기준이 달라 어긋나는 NPC 만 밀어 준다(extract_npc_face.py NUDGE).
	# 예: pong 은 몸통 그림에 이미 눈이 그려져 있어 어긋나면 **눈이 네 개**로 보인다.
	tl += _nudge(slot) / S
	if slot == "eye":
		_eye_tl = tl
	else:
		_mouth_tl = tl
	_body.add_child(s)
	_place(s, key, tl)
	return s

## 눈맞춤 보정(`data/npc_face.json` `nudge`, **디자인 px**) — 원작 좌표는 그대로 두고
## 우리 몸통 프레임 기준이 달라 어긋나는 것만 밀어 준다(`extract_npc_face.py` NUDGE).
##
## 두 형식을 받는다:
##   `[dx, dy]`                                   그 NPC 전체
##   `{"body_5": {"mouth": [dx, dy]}}`            포즈·슬롯별(`"*"` = 전부)
## 뒤 형식이 필요한 이유: 같은 NPC라도 **포즈마다 얼굴 각도가 달라** 한 벌로는 못 맞춘다
## (유리아 정면 포즈 body_5 의 입 — 사용자 실측 2026-08-04).
func _nudge(slot: String) -> Vector2:
	var nd = (Data.npc_face.get("nudge", {}) as Dictionary).get(npc_name, null)
	if nd is Array:
		return Vector2(float(nd[0]), float(nd[1])) if (nd as Array).size() >= 2 else Vector2.ZERO
	if not (nd is Dictionary):
		return Vector2.ZERO
	# `_body_key` = `npc_<이름>_body_<n>` → 뒤의 `body_<n>` 만 쓴다.
	var bkey := _body_key.trim_prefix("npc_%s_" % npc_name)
	var total := Vector2.ZERO
	for bk in [bkey, "*"]:
		var per = (nd as Dictionary).get(bk, null)
		if not (per is Dictionary):
			continue
		for sk in [slot, "*"]:
			var v = (per as Dictionary).get(sk, null)
			if v is Array and (v as Array).size() >= 2:
				total += Vector2(float(v[0]), float(v[1]))
	return total

## 좌상단 앵커(원작 0,1) → Godot 중앙 앵커 스프라이트 위치.
## 원작 앵커는 **트리밍 전 원본 박스**(`src`) 기준이므로 그 절반을 더한 뒤,
## 아틀라스가 여백을 잘라낸 만큼(`off`, Cocos y-up) 되돌린다.
func _place(spr: Sprite2D, key: String, tl: Vector2) -> void:
	var info: Dictionary = _man.get(key, {})
	var src: Array = info.get("src", [info.get("w", 0), info.get("h", 0)])
	var off: Array = info.get("off", [0, 0])
	spr.position = tl + Vector2(
		float(src[0]) * 0.5 + float(off[0]),
		float(src[1]) * 0.5 - float(off[1]))

# ── 애니메이션 ────────────────────────────────────────────────────────────
## 말하는 중에는 입이 움직인다(원작 setMouseAction/setStopMouse).
func set_talking(on: bool) -> void:
	_talking = on
	_mouth_next = _t + FIRST_DELAY
	if not on and not _mouth_fr.is_empty():
		_mouth_i = 0
		_set_frame(_mouth, "mouth", _mouth_fr[0])

func _process(delta: float) -> void:
	_t += delta
	# 프레임이 1장뿐인 표정은 원작에서도 정지다(CCArray count == 1 → 항상 같은 index).
	if _eye != null and _eye_fr.size() > 1 and _t >= _eye_next:
		_eye_i = (_eye_i + 1) % _eye_fr.size()
		_set_frame(_eye, "eye", _eye_fr[_eye_i])
		_eye_next = _t + _eye_delay()
	if _mouth != null and _talking and _mouth_fr.size() > 1 and _t >= _mouth_next:
		_mouth_i = (_mouth_i + 1) % _mouth_fr.size()
		_set_frame(_mouth, "mouth", _mouth_fr[_mouth_i])
		_mouth_next = _t + _mouth_delay()

## 원작 setNextEye 의 다음 delay. 쉬는 자세(index 0)만 길게 잡는다.
## 연출용 난수라 시드 고정 대상(`RNG` 오토로드)이 아니다 — 전역 randf() 를 쓴다.
func _eye_delay() -> float:
	if _eye_i != 0:
		return randf() * EYE_FAST
	var r := randf() * EYE_HOLD
	return r + 0.2 if r < 0.3 else r

## 원작 setNextMouse — 두 인자가 같아(0.03) 프레임마다 0.05~0.08초로 균일하다.
func _mouth_delay() -> float:
	var r := randf() * MOUTH_STEP
	return r + 0.05 if r < 0.1 else r

## 프레임 교체. 그 표정이 안 가진 번호는 그냥 무시한다(프레임이 1장뿐인 표정 = 정지).
## ⚠️ 프레임마다 트리밍(`off`/`src`)이 달라서 **위치도 같이 다시 계산**해야 한다.
func _set_frame(spr: Sprite2D, slot: String, frame: int) -> void:
	if spr == null:
		return
	var key := "npc_%s_%s_%d_%d" % [npc_name, slot, _art_emo, frame]
	if not _man.has(key):
		return
	var p := "res://assets/converted/%s/%s.tres" % [_dir, key]
	if not ResourceLoader.exists(p):
		return
	spr.texture = load(p)
	_place(spr, key, _eye_tl if slot == "eye" else _mouth_tl)

# ── 유틸 ─────────────────────────────────────────────────────────────────
## 이 NPC 의 초상 그림이 있나(원본에 없는 오리지널 캐릭터를 걸러내는 용도).
## ⚠️ 없다고 다른 NPC 얼굴로 대체하지 않는다 — 대사창만 띄운다(CLAUDE.md §3).
static func has_art(npc: String) -> bool:
	return npc != "" and not _manifest("npc_%s" % npc).is_empty()

static func _manifest(dir: String) -> Dictionary:
	var p := "res://assets/converted/%s/_manifest.json" % dir
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _sprite(key: String, scale: float) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [_dir, key]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.scale = Vector2(scale, scale)
	# 원본 아틀라스는 PMA(premultiplied alpha)로 변환된다 — 다른 화면과 동일 처리.
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	s.material = m
	return s

## 몸통 폭(디자인 포인트). 화면 좌/우 배치 계산용 — 원작 getDefaultNpcPos 가 쓰는 값.
func body_width() -> float:
	if _body == null:
		return 0.0
	return float(_body.texture.get_width()) * Design.ASSET_SCALE

func body_height() -> float:
	if _body == null:
		return 0.0
	return float(_body.texture.get_height()) * Design.ASSET_SCALE
