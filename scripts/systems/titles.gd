# Titles(칭호) — 순수 로직 계층 (§8: render/에셋 의존 없음, 헤드리스 검증 가능)
#
# 원작 근거:
#   · 화면 = `AchieveTitleLayer` (docs/ref/audit/AchieveTitleLayer.md) — CCTableView 목록,
#     획득 표시 `common/checked.png`, 상세 `PopupTypeLayer`, 아틀라스 `title.img_plist`.
#   · DB = `select title_no, name, comment, hidden from info_title_v` (디컴프 실재).
#   · 칭호 아트 = `title/<no>_kr.png` — 추출 아틀라스에 149종 실재.
#     **칭호 텍스트가 곧 이미지**라서 info_title_v.name 유실이 화면에 영향을 주지 않는다.
#
# ⚠️ 획득 조건은 원작에서 서버 소유(RequestTitle/ResponseTitle = NetworkManager)라 유실.
#    오프라인용으로 자작했다(사용자 승인 2026-07-27) — data/titles.json 의 unlock,
#    튜닝 노브 = scripts/tools/build_titles.py UNLOCK_RULES.
#
# 이 파일은 로직만: 노드/씬/스프라이트 참조 금지(§8.2).
class_name Titles
extends RefCounted

## 진행 지표 → 값. render/저장 계층이 UserDB 에서 모아 넘긴다(logic 은 UserDB 를 모른다).
## 키: dragons / hatches / battles / max_level / gold
static func unlocked_nos(progress: Dictionary, table: Dictionary) -> Array:
	var out: Array = []
	for t in (table.get("titles", []) as Array):
		var td := t as Dictionary
		if is_unlocked(td, progress):
			out.append(int(td.get("title_no", 0)))
	return out

static func is_unlocked(title: Dictionary, progress: Dictionary) -> bool:
	var u: Dictionary = title.get("unlock", {})
	if u.is_empty():
		return false
	var have := int(progress.get(String(u.get("stat", "")), 0))
	return have >= int(u.get("need", 0))

## 그 칭호까지 얼마나 남았나 → 0.0~1.0.
static func progress_ratio(title: Dictionary, progress: Dictionary) -> float:
	var u: Dictionary = title.get("unlock", {})
	var need := float(u.get("need", 0))
	if need <= 0.0:
		return 1.0
	var have := float(progress.get(String(u.get("stat", "")), 0))
	return clampf(have / need, 0.0, 1.0)

## title_no 로 정의 조회. 없으면 {}.
static func by_no(no: int, table: Dictionary) -> Dictionary:
	for t in (table.get("titles", []) as Array):
		if int((t as Dictionary).get("title_no", -1)) == no:
			return t
	return {}

## 목록을 (획득 → 미획득) 순으로, 각각 title_no 오름차순 정렬해 돌려준다.
## 원작 AchieveTitleLayer 의 CCTableView 가 획득분을 위에 보여 준다(common/checked.png 체크 표시).
static func sorted_for_view(progress: Dictionary, table: Dictionary) -> Array:
	var got: Array = []
	var yet: Array = []
	for t in (table.get("titles", []) as Array):
		var td := t as Dictionary
		if bool(td.get("hidden", false)) and not is_unlocked(td, progress):
			continue                      # hidden = 획득 전에는 목록에서 숨김(원작 컬럼)
		if is_unlocked(td, progress):
			got.append(td)
		else:
			yet.append(td)
	got.sort_custom(func(a, b): return int(a["title_no"]) < int(b["title_no"]))
	yet.sort_custom(func(a, b): return int(a["title_no"]) < int(b["title_no"]))
	return got + yet
