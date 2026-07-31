class_name EggItem
extends RefCounted
## 알 인벤 키의 **강화 등급 접미사** — logic 층(CLAUDE.md §8). 화면·에셋·UserDB 를 모른다.
##
## ## 왜 등급이 키에 들어가는가 (원작 근거, 2026-07-31)
##
## 원작의 알은 `Egg : Item` 객체이고 `Egg::getGrade()` 를 **개체마다** 들고 다닌다. 계정의 알
## 목록(`AccountManager` +0x238)에 그 개체들이 들어가는데, **서버 목록을 읽는 경로가 행마다
## 개체를 따로 만들어 그대로 넣는다**:
##
##     AccountManager::setInfoEggs(json)   // AccountManager.c:10035~10062
##       for row in rows:
##         egg = Egg::create(row[0]);  Item::setCount(egg, row[5]);
##         CCArray::addObject(this+0x238, egg);      // ← 번호로 합치지 않는다
##
## 즉 **같은 알 번호라도 등급이 다르면 목록에 따로 존재**하고, 가방 그리드는 목록을 그대로
## 셀로 펼치므로(`BagPopup::setItemList` → `tableCellAtIndex`) **0강과 2강은 다른 칸**이다.
## 셀 자체도 등급을 그린다 — `BagTableViewCell` 이 `common/ani_egg_up1_1~6` 애니를 셀에 붙이고
## grade 2/3 에 색을 입힌다(BagTableViewCell.c:760~793).
## (`AccountManager::addEgg(no, cnt)` 만 번호로 합치는데, 그건 **새로 얻은 알**(항상 0강) 경로다.)
##
## 우리 알은 인벤토리의 스택 아이템이라 개체가 없다 → **등급을 키에 넣어** 스택을 가른다.
## 종전(v13~v14)에는 `meta.egg_grades = {알키: {등급: 개수}}` 곁 테이블이었는데, 그러면
## 한 칸에 여러 등급이 섞여 원작처럼 갈리지 않았다(🟦사용자 지적 2026-07-31).
##
## ## 키 형식
##
##     <기본키>                 0강(미강화). 종전 키와 **완전히 같다** → 마이그레이션이 단순하다
##     <기본키>#<등급>          1강 이상.  예: `egg:17#2` · `mall_back_egg#1`
##
## 기본키는 두 갈래다 — 가상 키 `egg:<드래곤id>`(EggGacha) 와 items.json 알 아이템 키.
## 구분자를 `:` 가 아니라 `#` 으로 둔 이유: 가상 키가 이미 `:` 를 쓰고, 연구소 알 강화 화면이
## 진작부터 선택 id 로 `"<키>#<등급>"` 을 쓰고 있었다(`laboratory.gd::_sel_egg_up`).

const GRADE_SEP := "#"


## (기본키, 등급) → 인벤 키. 0 이하면 접미사를 붙이지 않는다(= 기존 키 그대로).
static func key(base: String, grade: int) -> String:
	return base if grade <= 0 else base + GRADE_SEP + str(grade)


## 인벤 키 → 기본키. 접미사가 없으면 그대로 돌려준다.
static func base_of(k: String) -> String:
	var i := k.rfind(GRADE_SEP)
	if i < 0:
		return k
	return k.substr(0, i) if k.substr(i + 1).is_valid_int() else k


## 인벤 키 → 강화 등급(0=미강화).
static func grade_of(k: String) -> int:
	var i := k.rfind(GRADE_SEP)
	if i < 0:
		return 0
	var s := k.substr(i + 1)
	return maxi(0, int(s)) if s.is_valid_int() else 0


## 강화된 알인가.
static func is_upgraded(k: String) -> bool:
	return grade_of(k) > 0


## 이 키가 그 기본키의 어떤 등급 변형인가(자기 자신 포함).
static func is_variant_of(k: String, base: String) -> bool:
	return base_of(k) == base
