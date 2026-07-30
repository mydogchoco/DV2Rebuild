class_name NpcEmoticon
extends Node2D
## 원작 `NpcManager::setEmoticon(int no, bool)` 포팅 — NPC 머리 위 말풍선 이모티콘.
## render 층(CLAUDE.md §8.1). 상점·점술집·연구소·육성이 공유한다.
##
## 원작 구조(docs/ref/orig_code/decomp/NpcManager.c :: setEmoticon):
##   · 배경  = `npc/emoticon/balloon.png`
##   · 아이콘 = `npc/emoticon/<N>.png` — 여러 컷짜리는 `<N>_1.png` `<N>_2.png` … (2·6·8번)
##   · 위치  = 몸통 로컬 (bodyW*0.5, bodyH*0.5 + 30)  = 머리 위
##   · 연출  = Delay(0.3) → ScaleTo(0.6, 1.5) → Delay(0.4) → ScaleTo(1.2, 1.2) + MoveBy(0,-60)
##            → Delay(0.4) → 제거
##
## ⚠️ `NpcPortrait` 를 건드리지 않고 **바깥에서 붙이는** 별도 노드로 만들었다 —
##    그 파일은 다른 작업(파츠 앵커 정정)이 동시에 진행 중이라 충돌을 피한다.
##    쓰는 쪽: `NpcEmoticon.show_on(npc_portrait, 8)`.

const DIR := "npc_emoticon"
## 원작 마지막 동작은 `MoveBy(0.8, (0,-60))` — Cocos y-up 이라 **아래로** 60 (풍선 속으로 잠긴다).
const SINK := 60.0
const FRAME_SEC := 0.4         # 여러 컷 아이콘의 컷 간격(원작 CCDelayTime 0.4)

## 몸통 기준 위치에서 추가로 밀어 주는 보정(디자인 포인트, 좌상단 방향이 음수).
## 사용자 검수 2026-07-28: 연구소 애니 옆 말풍선이 얼굴·손에 겹쳐 "왼쪽 위로 200~300px"
## 옮겨 달라는 요청. 창(768px 높이)↔디자인(692) 배율 1.11 을 감안해 디자인 225pt 로 잡았다.
## ⚠️ 이 노드는 상점·점술집·연구소·육성이 공유한다 — 값을 바꾸면 네 화면 모두 움직인다.
const NUDGE := Vector2(-90.0, -90.0)

## NPC별 "웃는 표정" 세트 번호. 이모티콘은 이 표정일 때만 뜬다(사용자 실측 2026-07-28).
## 확인 방법 = 아틀라스의 eye/mouth 세트를 몸통에 합성해 눈으로 대조
##   (애니: 1=안경/찡그림 · **2=웃음** · 3=놀람 · 6=졸림).
const SMILE_EMOTION := {"annie": 2}

var _icon: Sprite2D
var _frames: Array[Texture2D] = []
var _t := 0.0

## portrait 위에 이모티콘 하나를 띄운다. 이전 것이 남아 있으면 지운다.
## `no` = 원작 setEmoticon 의 번호(1~9).
static func show_on(portrait: NpcPortrait, no: int) -> NpcEmoticon:
	if portrait == null or no <= 0:
		return null
	# 원작에서 말풍선은 **웃는 표정일 때만** 뜬다. 표를 가진 NPC는 그 표정이 아니면 건너뛴다.
	if SMILE_EMOTION.has(portrait.npc_name) and portrait.emotion != int(SMILE_EMOTION[portrait.npc_name]):
		return null
	for c in portrait.get_children():
		if c is NpcEmoticon:
			c.queue_free()
	var e := NpcEmoticon.new()
	e._build(no, portrait.body_height(), portrait.body_width())
	if e._icon == null:
		e.queue_free()
		return null
	portrait.add_child(e)
	e._play()
	return e

func _build(no: int, body_h: float, body_w: float) -> void:
	var S := Design.ASSET_SCALE
	# 원작은 풍선을 **몸통 스프라이트의 자식**으로 (0,0) 에 붙인다 — 즉 몸통 박스의 좌하단 기준.
	# 실제 화면에서는 캐릭터 **왼쪽 어깨 옆**에 뜬다(사용자 실측 2026-07-28) → 몸통 왼쪽 가장자리,
	# 상체 높이에 맞춘다. NpcPortrait 원점은 발밑(Godot y-down)이다.
	position = Vector2(-body_w * 0.42, -body_h * 0.74) + NUDGE
	var balloon := AtlasUI.spr(DIR, "npc_emoticon_balloon", S)
	if balloon != null:
		add_child(balloon)
	_frames = _load_frames(no)
	if _frames.is_empty():
		return
	_icon = Sprite2D.new()
	_icon.texture = _frames[0]
	_icon.material = AtlasUI.pma()
	_icon.scale = Vector2(S, S)
	add_child(_icon)

## `<N>.png` 단일 컷 또는 `<N>_1..k.png` 다중 컷.
func _load_frames(no: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var single := AtlasUI.tex(DIR, "npc_emoticon_%d" % no)
	if single != null:
		out.append(single)
		return out
	for k in range(1, 6):
		var t := AtlasUI.tex(DIR, "npc_emoticon_%d_%d" % [no, k])
		if t == null:
			break
		out.append(t)
	return out

## 원작 시퀀스: 0.3 대기 → 0.6초에 걸쳐 1.5배 → 0.4 유지 → 1.2초에 걸쳐 1.2배로 줄며 위로 60 →
## 0.4 대기 → 사라짐.
func _play() -> void:
	scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(self, "scale", Vector2(1.5, 1.5), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.4)
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 1.2)
	tw.tween_property(self, "position:y", position.y + SINK, 0.8)
	tw.tween_property(self, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.set_parallel(false)
	tw.tween_interval(0.4)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	if _frames.size() < 2 or _icon == null:
		return
	_t += delta
	_icon.texture = _frames[int(_t / FRAME_SEC) % _frames.size()]
