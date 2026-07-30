# ItemSmelt(재료 제련) — 순수 로직 계층 (§8: render/에셋 의존 없음, 헤드리스 검증 가능)
#
# 원작 근거(구조):
#   · 화면 = `ItemSmeltPopup`. **가방에서 열린다** — `BagPopup::onClickConfirm` 의 `case 6` 이
#     `ItemSmeltPopup::create(item)` + `setConfirmListener` 를 부른다(BagPopup.c:15703).
#     즉 제련 대상 아이템에서는 가방의 확인 버튼이 곧 '제련'이다.
#   · 대상 조건도 그 case 에 있다 — 아이템 번호 `0xbb9`(3001) 부터 7개 중 `+3`(3004) 제외
#     = 정령석/스톤하트의 **하위 3티어씩 6종**(최상위 티어는 제련 불가). BagPopup.c:15702.
#   · 결과 = `CombineItem::create(itemNo + 1)` → **다음 아이템 번호**, 즉 한 티어 위(:267).
#   · 재료·비용 = `CombineItem` (`getItemNo1/getItemCnt1/getItemNo2/getItemCnt2/getCost`),
#     비용 표기는 `common/coin_small1` + `개수 × cost`(:620).
#   · 개수 스테퍼 = `onClickCount`(+/-), 기본 1(:30). 확정 시 `addItem(target, count)`(:1533).
#   · 문구(DV2/string/stringsData_KR.xml): `SmeltTitle`="재료 제련" · `SmeltMsg`="%1$s을 제련하시겠습니까?"
#     · `SmeltBtn`="%1$d 제련" · `SystemMsg5`="아이템 %1$s를 %2$d개 얻었습니다."
#
# 데이터: data/combine_item.json (원작 info_combine_item 스키마. 행 값은 서버 유실 →
#   정령석·스톤하트 환산 6행만 위키 확정치로 채웠다 — labwiki.pdf §2.1 각주 [3]~[8]).
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드/UserDB 참조 금지(§8.2 단방향 의존).
class_name ItemSmelt
extends RefCounted


## 이 아이템을 제련하면 나오는 레시피. 원작은 번호+1 로 찾지만 우리 키는 문자열이라
## "재료1이 이 아이템인 행"으로 찾는다(결과가 곧 다음 티어). 없으면 {}.
static func for_source(source_key: String, ci_data: Dictionary) -> Dictionary:
	if source_key == "":
		return {}
	for r in (ci_data.get("recipes", []) as Array):
		var d: Dictionary = r
		if String(d.get("item1", "")) == source_key:
			return d
	return {}


## 이 아이템이 제련 대상인가(원작 BagPopup case 6 판정에 대응).
static func can_smelt(source_key: String, ci_data: Dictionary) -> bool:
	return not for_source(source_key, ci_data).is_empty()


## 레시피의 재료 목록 [{item, count}] — 재료2가 비어 있으면 1종만.
static func materials(recipe: Dictionary) -> Array:
	var out: Array = []
	var i1 := String(recipe.get("item1", ""))
	if i1 != "":
		out.append({"item": i1, "count": maxi(1, int(recipe.get("item1_cnt", 1)))})
	var i2 := String(recipe.get("item2", ""))
	if i2 != "":
		out.append({"item": i2, "count": maxi(1, int(recipe.get("item2_cnt", 1)))})
	return out


## count 번 제련하는 총 비용(원작 `개수 × combine_cost`).
static func total_cost(recipe: Dictionary, count: int) -> int:
	return maxi(0, int(recipe.get("cost", 0))) * maxi(0, count)


## 지금 가능한 최대 제련 횟수. have = {아이템키: 보유수}, gold = 보유 골드.
## 원작 onClickCount 의 상한에 대응(재료·비용이 모자라면 못 올린다).
static func max_count(recipe: Dictionary, have: Dictionary, gold: int) -> int:
	if recipe.is_empty():
		return 0
	var n := -1
	for m in materials(recipe):
		var md: Dictionary = m
		var per := int(md.get("count", 1))
		var owned := int(have.get(String(md.get("item", "")), 0))
		var fit := owned / per
		n = fit if n < 0 else mini(n, fit)
	if n < 0:
		return 0
	var cost := int(recipe.get("cost", 0))
	if cost > 0:
		n = mini(n, gold / cost)
	return maxi(0, n)


## count 번 제련이 가능한지(재료·골드 충족).
static func affordable(recipe: Dictionary, count: int, have: Dictionary, gold: int) -> bool:
	return count > 0 and count <= max_count(recipe, have, gold)
