# ImpShop — 임프상인(원작 `ImpShopScene`) 규칙 (순수 로직 계층 §8: render/에셋 의존 없음)
#
# ## 원작 구조 — 서버 랭킹 + 클라 상점이 한 씬에 섞여 있다
# `docs/ref/orig_code/decomp/ImpShopScene.c`(5,401줄, `[skip>` 없음 = 전량 디컴파일).
#
#   클라 담당(살아 있음) : `initWidget` · `setSeller`/`setSellerInto`/`setSellerShow` ·
#                          `showItem`/`showItemBuy`/`onClickItemBuy`/`CallbackItemBuy` ·
#                          `setTreasureView` · `onClickTab`/`setCurrentView` · `tableCellAtIndex`
#   서버 담당(유실)      : `requestRankCave`/`responseRankCave` · `onClickRanker` ·
#                          `requestShopInfo` · `requestProfile`/`responseProfile` ·
#                          API `game_treasure/get_treasurehunter_data.hb` · `game_social/visit_cave.hb`
#                          JSON `my_rank` `my_week_rank` `treasure_total_rank` `treasure_week_rank`
#                          `week_reward` `rank_init` `shop_list` `item_no` `count`
#
# ⚫ **주간 트레저헌터 랭킹은 통째로 CUT**(사용자 확정 2026-07-31, CLAUDE.md §2-1).
#    원작이 콜로세움 주간 타이머(`ColosseumWeekReset` + `scene/colosseum/week_time`)를
#    재사용하던 부분도 함께 뺀다. 남기는 것은 **보석 ↔ 장비 교환**뿐이다.
#
# ## 화폐 = 보석(임프 보물)
# 원작 `<ShopWelcomeImp7>` "나는 **금화 따윈 받지 않아**. 멋진 **보석**을 가져오라고 애송이!"
# 보석은 밤 지역의 골드/실버 임프가 떨군다(`<NightTutorial_talk11>`,
# `data/monster_drops.json` #160·#161). 즉 **밤 탐험 → 보석 → 임프상인**이 한 고리다.
#
# 재고·가격 = `data/imp_shop.json`. **한 아이템은 한 종류의 보석만** 받는다(사용자 확정).
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드 참조 금지(§8.2 단방향 의존).
class_name ImpShop
extends RefCounted

## 진열 목록 → [{key, name, kind, grade, currency, price}] (파일 순서 그대로).
## `key` 는 `data/equipment.json` 의 카탈로그 키다 — 스탯은 여기 없다(§8.1 정의 단일 출처).
static func stock(table: Dictionary) -> Array:
	return (table.get("stock", []) as Array)

## 탭(계열)별 목록. kind = "묘안석" | "흑요석" | "백금석". ""이면 전체.
static func stock_of(table: Dictionary, kind: String) -> Array:
	if kind == "":
		return stock(table)
	var out: Array = []
	for r in stock(table):
		if String((r as Dictionary).get("kind", "")) == kind:
			out.append(r)
	return out

## 진열된 계열 목록(탭 구성용). 파일 등장 순서를 유지한다.
static func kinds(table: Dictionary) -> Array:
	var out: Array = []
	for r in stock(table):
		var k := String((r as Dictionary).get("kind", ""))
		if k != "" and not out.has(k):
			out.append(k)
	return out

## 그 품목을 살 수 있는가. `owned` = {아이템키: 개수}(보유 보석).
static func can_buy(row: Dictionary, owned: Dictionary) -> bool:
	return int(owned.get(String(row.get("currency", "")), 0)) >= int(row.get("price", 0))

## 부족한 개수(0이면 살 수 있다). render 가 "N개 부족" 을 띄우는 데 쓴다.
static func shortfall(row: Dictionary, owned: Dictionary) -> int:
	return maxi(0, int(row.get("price", 0)) - int(owned.get(String(row.get("currency", "")), 0)))

## 구매 결과를 **계산만** 한다(인벤토리를 만지지 않는다 — 그건 render/UserDB 몫 §8.3).
## 반환 {ok, spend_key, spend_count, give_key} · 실패면 {ok:false, reason}.
##   give_key = 지급할 인벤 키. 원작 서버가 `rarity`/`option` 을 실어 줬는데 그건 유실이라
##   상점 구매는 **일반 100%**(옵션 0개)로 준다 — `data/drops.json` 골드 상점과 같은 규약.
static func buy(row: Dictionary, owned: Dictionary) -> Dictionary:
	var cur := String(row.get("currency", ""))
	var price := int(row.get("price", 0))
	if cur == "" or price <= 0:
		return {"ok": false, "reason": "가격 정보가 없습니다"}
	if int(owned.get(cur, 0)) < price:
		return {"ok": false, "reason": "보석이 부족합니다"}
	return {"ok": true, "spend_key": cur, "spend_count": price,
		"give_key": Equipment.item_key(String(row.get("key", "")))}

## 임프상인이 받는 보석 종류 전부(보유 표시줄 구성용). 진열 순서에서 유도한다.
static func currencies(table: Dictionary) -> Array:
	var out: Array = []
	for r in stock(table):
		var c := String((r as Dictionary).get("currency", ""))
		if c != "" and not out.has(c):
			out.append(c)
	return out

## 인사말 키(원작 `ShopWelcomeImp%d`, 1~9). 방문마다 하나를 고른다.
static func welcome_key(rng: RandomNumberGenerator) -> String:
	return "ShopWelcomeImp%d" % (rng.randi_range(1, 9))

## 구매 후 대사 키(원작 `ShopBuyImpPong_%d`, 1~4).
static func buy_line_key(rng: RandomNumberGenerator) -> String:
	return "ShopBuyImpPong_%d" % (rng.randi_range(1, 4))
