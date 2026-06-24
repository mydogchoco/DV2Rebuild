extends Node
## Autoload "UserDB": 유저 데이터베이스 — 가변 플레이어 상태의 단일 진실 공급원.
##
## 설계 원칙 (CLAUDE.md §5):
##   - 게임 기능(UI/시스템)은 이 API만 호출한다. raw dict(_data)를 직접 만지지 않는다.
##   - 영구 보존 대상 = 보유 드래곤별 육성 상태 + 아이템 인벤토리 + 재화 + 외형/진행도.
##   - 저장은 SaveSystem(순수 파일IO)에 위임. 마스터 데이터(불변)는 Data가 담당.
##   - 드래곤은 배열 인덱스가 아니라 안정적 고유 uid로 식별한다(방생/정렬에도 안전).

const SCHEMA_VERSION := 2   # v1=인덱스기반(레거시) → v2=uid기반

var _data: Dictionary = {}
var _autosave := true       # false면 변경이 메모리에만 반영(일괄 작업 후 save())

func _ready() -> void:
	var loaded = SaveSystem.load_or_backup()
	if loaded == null:
		_data = _default()
		SaveSystem.save(_data)
	else:
		_data = _migrate(loaded)
	print("[UserDB] v%d 로드 — 드래곤 %d마리, 골드 %d" % [
		int(_data.get("version", 0)), dragon_count(), gold()])

# ============================================================ 스키마
func _default() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"next_uid": 1,                                # 다음에 발급할 드래곤 고유 uid
		"currency": {"gold": 0, "diamond": 0},        # §I
		"dragons": [],                                # 보유 드래곤 인스턴스 목록
		"active_uid": 0,                              # 현재 활성 드래곤 uid (0=없음)
		"inventory": {},                             # {아이템명: 수량}
		"cosmetics": {"cave_skin": 0, "stand_skin": 0, "wall_skin": 0},
		"progress": {},                              # 스테이지/퀘스트 진행도
		"rng_seed": null,
	}

## 보유 드래곤 1마리의 영구 저장 스키마. 미사용 필드도 예약(향후 세이브 포맷 안정성).
## grade/crest/engravings = §K-5 보정용(등급/문장/각인). HP 등 전투 임시값은 저장 안 함.
func _new_dragon(id: int, level: int, grade: float) -> Dictionary:
	var uid := int(_data["next_uid"])
	_data["next_uid"] = uid + 1
	return {
		"uid": uid,
		"id": id,                # 도감 ID (마스터 데이터 Data.get_dragon용)
		"level": level,
		"exp": 0,
		"grade": grade,          # 개체 등급
		"crest": "",             # 문장
		"engravings": [],        # 각인 목록
		"nickname": "",
		"locked": false,         # 방생 잠금
		"acquired_at": int(Time.get_unix_time_from_system()),
	}

# ============================================================ 드래곤
func dragons() -> Array:
	return _data["dragons"]

func dragon_count() -> int:
	return _data["dragons"].size()

func get_dragon(uid: int) -> Dictionary:
	for d in _data["dragons"]:
		if int(d["uid"]) == uid:
			return d
	return {}

func add_dragon(id: int, level: int = 1, grade: float = 8.0) -> Dictionary:
	var inst := _new_dragon(id, level, grade)
	_data["dragons"].append(inst)
	if active_uid() == 0:
		_data["active_uid"] = inst["uid"]
	_commit()
	return inst

func release_dragon(uid: int) -> bool:
	var arr: Array = _data["dragons"]
	for i in arr.size():
		if int(arr[i]["uid"]) == uid:
			if bool(arr[i].get("locked", false)):
				return false
			arr.remove_at(i)
			if active_uid() == uid:
				_data["active_uid"] = int(arr[0]["uid"]) if not arr.is_empty() else 0
			_commit()
			return true
	return false

func active_uid() -> int:
	return int(_data.get("active_uid", 0))

func active_dragon() -> Dictionary:
	return get_dragon(active_uid())

func set_active(uid: int) -> void:
	if not get_dragon(uid).is_empty():
		_data["active_uid"] = uid
		_commit()

func set_level(uid: int, level: int) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d["level"] = level
		_commit()

func add_exp(uid: int, n: int) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d["exp"] = int(d.get("exp", 0)) + n
		_commit()

func set_dragon_field(uid: int, key: String, value) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d[key] = value
		_commit()

# ============================================================ 인벤토리
func inventory() -> Dictionary:
	return _data["inventory"]

func item_count(key: String) -> int:
	return int(_data["inventory"].get(key, 0))

func add_item(key: String, n: int = 1) -> void:
	var inv: Dictionary = _data["inventory"]
	inv[key] = int(inv.get(key, 0)) + n
	if inv[key] <= 0:
		inv.erase(key)
	_commit()

## 아이템을 n개 소비. 부족하면 아무것도 안 하고 false.
func use_item(key: String, n: int = 1) -> bool:
	var inv: Dictionary = _data["inventory"]
	var have := int(inv.get(key, 0))
	if have < n:
		return false
	inv[key] = have - n
	if inv[key] <= 0:
		inv.erase(key)
	_commit()
	return true

# ============================================================ 재화
func currency(kind: String) -> int:
	return int(_data["currency"].get(kind, 0))

func gold() -> int:
	return currency("gold")

func diamond() -> int:
	return currency("diamond")

func add_currency(kind: String, amount: int) -> void:
	_data["currency"][kind] = currency(kind) + amount
	_commit()

## kind 재화를 amount만큼 소비. 부족하면 false.
func spend(kind: String, amount: int) -> bool:
	if currency(kind) < amount:
		return false
	_data["currency"][kind] = currency(kind) - amount
	_commit()
	return true

# ============================================================ 외형/진행도
func get_skin(slot: String) -> int:
	return int(_data["cosmetics"].get(slot, 0))

func set_skin(slot: String, idx: int) -> void:
	_data["cosmetics"][slot] = idx
	_commit()

func get_progress(key: String, default = null):
	return _data["progress"].get(key, default)

func set_progress(key: String, value) -> void:
	_data["progress"][key] = value
	_commit()

# ============================================================ 저장 제어
func _commit() -> void:
	if _autosave:
		SaveSystem.save(_data)

## 일괄 변경 시: begin_batch() → ...여러 변경... → save() 로 디스크 쓰기 1회.
func begin_batch() -> void:
	_autosave = false

func save() -> void:
	_autosave = true
	SaveSystem.save(_data)

func reset() -> void:
	_data = _default()
	SaveSystem.save(_data)

## 디스크에서 다시 읽어 메모리 상태를 교체(저장 슬롯 로드/재시작용).
func reload() -> void:
	var loaded = SaveSystem.load_or_backup()
	_data = _default() if loaded == null else _migrate(loaded)

## 디버그/검증 전용. UI/시스템 코드에서는 쓰지 말 것(스키마 우회 금지).
func raw() -> Dictionary:
	return _data

# ============================================================ 마이그레이션
func _migrate(d: Dictionary) -> Dictionary:
	var ver := int(d.get("version", 1))
	if ver >= SCHEMA_VERSION:
		return _ensure_schema(d)
	# --- v1(인덱스 기반) → v2(uid 기반) ---
	var base := _default()
	base["currency"] = d.get("currency", base["currency"])
	base["inventory"] = d.get("inventory", base["inventory"])
	base["progress"] = d.get("progress", base["progress"])
	base["rng_seed"] = d.get("rng_seed", null)
	base["cosmetics"] = {
		"cave_skin": int(d.get("cave_skin", 0)),
		"stand_skin": int(d.get("stand_skin", 0)),
		"wall_skin": int(d.get("wall_skin", 0)),
	}
	var old_list: Array = d.get("owned_dragons", [])
	var active_idx := int(d.get("active_dragon", 0))
	var uid := 1
	for i in old_list.size():
		var od: Dictionary = old_list[i]
		var nd := {
			"uid": uid, "id": int(od.get("id", 0)), "level": int(od.get("level", 1)),
			"exp": int(od.get("exp", 0)), "grade": float(od.get("grade", 8.0)),
			"crest": "", "engravings": [], "nickname": "", "locked": false, "acquired_at": 0,
		}
		if i == active_idx:
			base["active_uid"] = uid
		base["dragons"].append(nd)
		uid += 1
	base["next_uid"] = uid
	if active_uid_of(base) == 0 and not base["dragons"].is_empty():
		base["active_uid"] = int(base["dragons"][0]["uid"])
	print("[UserDB] 세이브 마이그레이션 v%d → v%d (%d마리)" % [ver, SCHEMA_VERSION, base["dragons"].size()])
	SaveSystem.save(base)
	return base

func active_uid_of(d: Dictionary) -> int:
	return int(d.get("active_uid", 0))

## 같은 버전이라도 누락된 키/드래곤 필드를 기본값으로 보강(향후 필드 추가 대비).
func _ensure_schema(d: Dictionary) -> Dictionary:
	var base := _default()
	for k in base.keys():
		if not d.has(k):
			d[k] = base[k]
	for k in base["cosmetics"].keys():
		if not d["cosmetics"].has(k):
			d["cosmetics"][k] = base["cosmetics"][k]
	var defaults := {"exp": 0, "grade": 8.0, "crest": "", "engravings": [],
		"nickname": "", "locked": false, "acquired_at": 0}
	for dr in d.get("dragons", []):
		for k in defaults.keys():
			if not dr.has(k):
				dr[k] = defaults[k]
	return d
