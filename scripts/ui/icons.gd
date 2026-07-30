# Icons — 논리키 → 원본 아이콘 텍스처 로더 (render 층 전용, §8.4 에셋 카탈로그 계층)
#
# data/logic 은 파일 경로를 모르고 **논리키**만 쓴다. 실제 프레임 파일을 아는 건 여기뿐이다.
# 매핑표 = `data/icon_map.json` (scripts/tools/build_item_icons.py 가 원본 아틀라스
# `_manifest.json` 의 실제 프레임명을 스캔해 생성).
#
# 원본 근거(프레임명은 추측이 아니라 변환 산출물에서 확인):
#   장비   item/accessory/{feather,claw,talisman}1..7 · {catseye,obsidian,platinum}1..6
#   아티팩트 item/accessory/{ignis_,maris_,ventus_,lumen_,obscurum_,terra_}1..6
#   젬     item/gem/{gem_hp,gem_att,gem_def,gem_hp_att,…,gem_white}0..18  (10종 × 19티어)
#          gem_white = 샌즈의 젬(위키 §2.2.7 "하얀색 외형")
#   ⚠️ 소울젬 아이콘은 원작 후기 추가분이라 이 덤프에 없다 → 같은 축 일반젬 최고티어로 폴백.
class_name Icons
extends RefCounted

## 속성 아이콘('정기' 아이템과 **같은 프레임**) — 원작이 `item/item_small/ele_*.png` 를 쓰는 자리들의
## 단일 출처. 아틀라스 폴더는 `assets/converted/item_small_ui/`.
##   · 둥지 상단바      `CaveScene.c:15651~` 의 문자열 테이블
##   · 전투 네임플레이트 `InterFace.c:575-640`(몬스터) · `:335-400`(드래곤)
## ⚠️ `battle/element_*_mark`/`_outline` 은 **속성 조합(시너지) 연출** 자산이다 —
##    전 디컴프에서 그 프레임을 쓰는 클래스는 `CombineElementsLayer` 뿐이니 여기 섞지 말 것.
## ⚠️ 프레임명은 완성형 키로 적는다(접두사+포맷 조립 금지 — asset_index 가 같은 아틀라스의
##    아이템 아이콘 수백 개를 '사용 중'으로 오집계한다).
const ELEMENT_SMALL := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire",
	"aqua": "item_item_small_ele_water", "water": "item_item_small_ele_water",
	"earth": "item_item_small_ele_ground", "ground": "item_item_small_ele_ground",
	"wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy",
	"chaos": "item_item_small_ele_chaos", "shadow": "item_item_small_ele_shadow"}

## 속성 코드 → 프레임 키. **무속성("" / "none" / 모르는 값)은 빈 문자열** — 원작 switch 의
## default 가 스프라이트를 아예 만들지 않는 것과 같다(레퍼런스: 데스웜 플레이트에 아이콘 없음).
static func element_small_frame(element: String) -> String:
	return String(ELEMENT_SMALL.get(element, ""))

## 논리키 조회. section = "equipment_basic" | "artifact" | "event" | "gem".
## 반환: {dir, frame, fallback?} 또는 {}
static func entry(section: String, key: String) -> Dictionary:
	var m: Dictionary = Data.icon_map
	return (m.get(section, {}) as Dictionary).get(key, {})

## 논리키 → AtlasTexture. 없으면 null.
static func texture(section: String, key: String) -> Texture2D:
	var e := entry(section, key)
	if e.is_empty():
		return null
	var p := "res://assets/converted/%s/%s.tres" % [String(e["dir"]), String(e["frame"])]
	if not ResourceLoader.exists(p):
		return null
	return load(p)

## 젬 아이콘(코드+티어). gems.json 의 code 와 슬롯 티어를 그대로 넘긴다.
static func gem_texture(code: String, tier: int) -> Texture2D:
	return texture("gem", "%s:%d" % [code, tier])

## 드래곤 알 아이콘 — 가상 인벤 키 `egg:<id>`(뽑기 알 개봉 결과) 용.
## 도감·둥지와 같은 규약인 초상 아틀라스의 `dragon_dragon_<id>_egg` 프레임을 쓴다
## (cave.gd `_dex_stage_frame(id,"egg")` 과 같은 프레임 — 알 그림은 종마다 따로 있다).
static func dragon_egg_texture(dragon_id: int) -> Texture2D:
	var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_egg.tres" % [dragon_id, dragon_id]
	return load(p) if ResourceLoader.exists(p) else null

## ── 커스텀 종(600·700)의 그림·속성 해석 ─────────────────────────────────────
##
## 자작 드래곤은 보통 **빌드 때** 아트 별칭으로 해결한다 — `dragons.json` 의 `art_id` 를 보고
## `build_dragon_art_alias.py` 가 `portrait_<자기id>` · `dragon_<자기id>_*.tscn` 을 만들어 두므로
## 경로를 조립하는 40여 곳을 하나도 안 건드려도 된다.
##
## 그런데 점술집 '드래곤 소환'으로 생기는 **600·700 은 그림이 런타임에 정해진다**(재료로 넣은
## 드래곤을 따른다 — `Summon.plan` 의 inherit). 빌드 시점에 알 수 없으니 별칭 방식을 못 쓴다.
## ⇒ 개체 레코드가 들고 있는 `art_id` / `element` 를 여기서 풀어 준다. **개체를 아는 호출부만**
##    이 헬퍼를 거치면 되고(둥지·도감·상태창·파티선택·전투), 나머지 경로는 종전 그대로다.
##
## 개체(inst)를 넘기면 개체의 상속값이 우선하고, 없으면 마스터 데이터로 떨어진다.
static func art_id_of(inst: Dictionary) -> int:
	var id := int(inst.get("id", 0))
	var own := int(inst.get("art_id", 0))
	if own > 0:
		return own
	return Data.art_id(id)


## 개체의 표시 속성. 커스텀 종은 마스터가 `element: null` 이라 개체 상속값을 본다.
## 못 찾으면 "" — 호출측은 속성 아이콘을 생략한다(없는 프레임을 만들지 않는다).
static func element_of(inst: Dictionary) -> String:
	var own = inst.get("element")
	if typeof(own) == TYPE_STRING and String(own) != "":
		return String(own)
	var m = Data.get_dragon(int(inst.get("id", 0))).get("element")
	return String(m) if typeof(m) == TYPE_STRING else ""


## 장비 카탈로그 항목 → 아이콘. Equipment.catalog() 가 만든 항목을 그대로 받는다.
##
## ⚠️ 종류는 **카탈로그 키**에서 뽑는다(표시명 파싱 금지). 키 형식은 Equipment.catalog() 소유:
##     "basic:깃털:6" · "artifact:루멘:5" · "event:눈사람 인형" · "special:balrog:…"
## 예전엔 표시명의 마지막 낱말을 종류로 썼는데, 최고등급 이름이 종류와 다른 경우
## ("아만타의 금우"=깃털, "아만타의 조갑"=발톱 — 위키 §2.1) 아이콘을 못 찾았다.
static func equip_texture(item: Dictionary) -> Texture2D:
	var grp := String(item.get("group", ""))
	var parts := String(item.get("key", "")).split(":")
	if grp == "basic" and parts.size() >= 3:
		return texture("equipment_basic", "%s:%s" % [parts[1], parts[2]])
	if grp == "artifact" and parts.size() >= 3:
		return texture("artifact", "%s:%s" % [parts[1], parts[2]])
	if grp == "event":
		return texture("event", String(item.get("name", "")))
	# special(해골요새·발록·피오드) 계열은 개별 아이콘이 이 덤프에 없다(후기 추가분) → null.
	return null

## 장비 아이콘 **뒤**에 까는 희귀도 실루엣. 원작 `Equip::getGradeImageSmallSprite` 대응 —
## `<이름>_bg.png` 흰 실루엣을 만들고 희귀도 색을 입힌다(일반=안 그림).
## 논리키는 equip_texture 와 같다(build_item_icons.py `equipment_bg`).
static func equip_bg_texture(item: Dictionary) -> Texture2D:
	var grp := String(item.get("group", ""))
	var parts := String(item.get("key", "")).split(":")
	if grp == "basic" and parts.size() >= 3:
		return texture("equipment_bg", "%s:%s" % [parts[1], parts[2]])
	if grp == "artifact" and parts.size() >= 3:
		return texture("equipment_bg", "%s:%s" % [parts[1], parts[2]])
	if grp == "event":
		return texture("equipment_bg", String(item.get("name", "")))
	return null

## 희귀도(등급 인덱스 0=일반…5=초월) → 실루엣 색. 일반이거나 표에 없으면 투명(=안 그림).
## 값은 원작 setColor 그대로 — data/equipment.json option.rarity_colors.
static func rarity_color(grade: int) -> Color:
	var tbl: Array = Data.equipment.get("option", {}).get("rarity_colors", [])
	if grade < 0 or grade >= tbl.size() or tbl[grade] == null:
		return Color(0, 0, 0, 0)
	return Color(String(tbl[grade]))

## 귀속 뱃지 프레임. 원작 `BagTableViewCell` — 내 것 `owned`, 남의 것 `owned2`, 뒷판 `owned_bg`.
static func owned_texture(kind: String) -> Texture2D:
	var p := "res://assets/converted/cave_ui/scene_cave_%s.tres" % kind
	return load(p) if ResourceLoader.exists(p) else null

## 장비 한 칸을 원작 순서대로 겹쳐 그린 Control.
##   ① 희귀도 실루엣(색 입힘) → ② 아이콘 → ③ 귀속 뱃지(owned_bg + owned/owned2)
## 원작 `BagTableViewCell` case 1 의 addChild 순서 그대로다.
##   grade      = 희귀도 인덱스(0=일반…5=초월). 음수면 실루엣 생략.
##   belong     = 귀속 대상 uid(0=미귀속)
##   viewer_uid = 지금 보고 있는 드래곤 uid — belong 과 같으면 `owned`, 다르면 `owned2`
static func equip_rect(item: Dictionary, box: float = 40.0, grade: int = -1,
		belong: int = 0, viewer_uid: int = 0) -> Control:
	var tex := equip_texture(item)
	if tex == null and belong <= 0:
		return null
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)
	holder.size = Vector2(box, box)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if grade >= 0:
		var col := rarity_color(grade)
		var bg := equip_bg_texture(item)
		if bg != null and col.a > 0.0:
			var br := rect(bg, box)
			if br:
				br.modulate = col
				holder.add_child(br)
	var ir := rect(tex, box)
	if ir:
		holder.add_child(ir)
	if belong > 0:
		var bgb := owned_texture("owned_bg")
		if bgb:
			var r := rect(bgb, box * 0.45)
			if r:
				r.position = Vector2(box * 0.55, box * 0.55)
				holder.add_child(r)
		var mark := owned_texture("owned" if belong == viewer_uid else "owned2")
		if mark:
			var r2 := rect(mark, box * 0.45)
			if r2:
				r2.position = Vector2(box * 0.55, box * 0.55)
				holder.add_child(r2)
	return holder

## 텍스처를 지정 높이에 맞춰 그리는 TextureRect(목록 행용). 없으면 null.
static func rect(tex: Texture2D, box: float = 34.0) -> TextureRect:
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(box, box)
	tr.size = Vector2(box, box)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
