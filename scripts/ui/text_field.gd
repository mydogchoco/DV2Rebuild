class_name TextField
## 텍스트 입력 헬퍼 — **한글 IME 조합 함정** 전용. render 층(CLAUDE.md §8.1).
##
## ## 증상 (사용자 보고 2026-07-31)
## 닉네임을 "계란" 이라고 치고 확인을 누르면 **"계"** 만 저장된다. 마지막 글자가 사라진다.
##
## ## 원인
## IME(한글 입력기)로 **조합 중인 글자**는 `LineEdit.text` 에 아직 없다 — 미리보기(preedit)로
## 따로 들고 있다가 조합이 끝날 때(스페이스·엔터·다른 글자 입력·포커스 이동) 비로소 들어간다.
## 그런데 확인 버튼을 누르는 순간 **포커스가 버튼으로 옮겨가면서 조합이 취소**되고, 그 뒤에
## 실행되는 `pressed` 핸들러는 마지막 글자가 빠진 `text` 를 읽는다.
## 로마자는 조합이 없어(한 글자=한 입력) 이 버그가 안 보인다 — 그래서 한글에서만 터진다.
##
## ## 처방 (두 개를 같이 해야 한다)
## 1. `no_steal(팝업루트)` — 그 안의 버튼이 **포커스를 뺏지 않게** 한다(`FOCUS_NONE`).
##    이걸 안 하면 핸들러가 돌기도 전에 조합이 날아가 2번이 손쓸 게 없다.
## 2. `value(edit)` — 읽기 직전에 `LineEdit.apply_ime()` 로 조합을 **확정**한 뒤 읽는다.
##    (Godot 4 의 공식 API. `has_ime_text()`/`cancel_ime()` 와 한 짝이다.)
static func value(edit: LineEdit) -> String:
	if edit == null:
		return ""
	if edit.has_method("apply_ime"):
		edit.apply_ime()          # 조합 중인 글자를 text 로 확정
	return edit.text.strip_edges()


## 서브트리의 모든 버튼이 클릭으로 포커스를 가져가지 않게 한다(텍스트 입력이 있는 창 전용).
static func no_steal(root: Node) -> void:
	if root is BaseButton:
		(root as BaseButton).focus_mode = Control.FOCUS_NONE
	for c in root.get_children():
		no_steal(c)
