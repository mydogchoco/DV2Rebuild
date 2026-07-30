class_name CardCode
extends RefCounted
## 카드 코드 판정 — logic 층(CLAUDE.md §8). 화면·에셋을 모르고, 표는 **인자로 받는다**
## (`CardGame` · `Drops` · `EggGacha` 와 같은 관례 — 화면 없이 테스트 가능).
##
## 원작 `CodeLayer` 의 판정은 **서버 몫이라 유실**됐다. 우리는 사용자가 채운 이스터에그 표를
## 쓴다(사용자 확정 2026-07-28). 표는 `docs/input/sheets/card_codes.csv`(평문, gitignore)가
## 정본이고, 게임에 실리는 것은 `scripts/tools/build_card_codes.py` 가 구운 암호문이다.
##
## 왜 암호화하나 — 빌드를 뜯어서 코드 목록·보상을 미리 보는 것을 막는다(사용자 요청 2026-07-30).
## 키를 빌드에 넣으면 난독화일 뿐이라(데이터를 찾는 사람은 키도 찾는다) **코드 자체를 키로 쓴다**:
##
##     조회 키 = iter_sha256(SALT_ID  + 정규화코드)   ← 단방향. 역산 불가
##     암호 키 = iter_sha256(SALT_KEY + 정규화코드)   ← 이 파일에도, 빌드 어디에도 없다
##     보상    = XOR(보상JSON, SHA256 키스트림(암호키, nonce))
##
## ⇒ 빌드에서 얻을 수 있는 것은 "코드가 몇 개인가" 뿐이다. 무차별 대입은 16자리 영숫자
##    36^16 ≈ 8e24 라 불가능하다.
##
## ⚠️ 아래 상수·절차는 `scripts/tools/build_card_codes.py` 와 **바이트 단위로 같아야 한다.**
##    한쪽만 고치면 모든 코드가 조용히 인식 불가가 된다.

const SALT_ID := "dv2.cc.id.v1"
const SALT_KEY := "dv2.cc.key.v1"
const DEFAULT_ITER := 10000

## 입력 정규화 — 영숫자만 남기고 대문자로. 하이픈·공백 표기 차이를 흡수한다.
static func normalize(code: String) -> String:
	var out := ""
	for c in code.to_upper():
		if (c >= "0" and c <= "9") or (c >= "A" and c <= "Z"):
			out += c
	return out


static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


## 반복 해시 — h = sha256(salt+code), 이후 sha256(h) 를 (iterations-1)번.
## 반복 자체가 무차별 대입 비용을 올린다(정상 조회는 1회뿐이라 체감되지 않는다).
static func _iter_sha256(salt: String, code: String, iterations: int) -> PackedByteArray:
	var h := _sha256((salt + code).to_utf8_buffer())
	for i in maxi(0, iterations - 1):
		h = _sha256(h)
	return h


## SHA-256 CTR 키스트림. 블록 i = sha256(key ‖ nonce ‖ i(4바이트 빅엔디안)).
static func _keystream(key: PackedByteArray, nonce: PackedByteArray, length: int) -> PackedByteArray:
	var out := PackedByteArray()
	var counter := 0
	while out.size() < length:
		var seed := key.duplicate()
		seed.append_array(nonce)
		seed.append((counter >> 24) & 0xFF)
		seed.append((counter >> 16) & 0xFF)
		seed.append((counter >> 8) & 0xFF)
		seed.append(counter & 0xFF)
		out.append_array(_sha256(seed))
		counter += 1
	out.resize(length)
	return out


static func _xor(data: PackedByteArray, stream: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(data.size())
	for i in data.size():
		out[i] = data[i] ^ stream[i]
	return out


## 무결성 태그 — 맞는 코드로 푼 것인지 확인한다(보안 경계가 아니라 정합성 검사).
static func _tag(key: PackedByteArray, nonce: PackedByteArray, cipher: PackedByteArray) -> String:
	var seed := key.duplicate()
	seed.append_array(nonce)
	seed.append_array(cipher)
	return _sha256(seed).hex_encode().substr(0, 32)


## 코드를 표에서 찾아 **복호한 보상 페이로드**를 돌려준다. 못 쓰는 코드면 빈 사전.
##   반환 = {"rewards": [{t,k,n}…], "msg": String, "once": bool}
##   보상 종류(t) = item(k=아이템키) · gold · dia · egg(k=드래곤id) · dragon(k=드래곤id) ·
##                  flag(k=해시된 플래그 키)
## 지급은 하지 않는다 — **결과만 산출**하고 인벤/재화 반영은 호출측(render)이 한다(§8.3).
static func lookup(code: String, table: Dictionary) -> Dictionary:
	var c := normalize(code)
	if c.is_empty():
		return {}
	var iterations := int(table.get("iter", DEFAULT_ITER))
	var want := _iter_sha256(SALT_ID, c, iterations).hex_encode()
	for e in table.get("entries", []):
		var ent: Dictionary = e
		if String(ent.get("id", "")) != want:
			continue
		var key := _iter_sha256(SALT_KEY, c, iterations)
		var nonce := _hex(String(ent.get("n", "")))
		var cipher := _hex(String(ent.get("d", "")))
		if _tag(key, nonce, cipher) != String(ent.get("t", "")):
			return {}                     # 표가 손상됐거나 빌드가 어긋났다
		var plain := _xor(cipher, _keystream(key, nonce, cipher.size()))
		var parsed = JSON.parse_string(plain.get_string_from_utf8())
		return parsed if parsed is Dictionary else {}
	return {}


## 사용 이력에 남길 키 = 조회 해시. 세이브에도 **평문 코드를 남기지 않는다**
## (세이브를 열어 봐도 쓴 코드가 무엇이었는지 알 수 없다).
static func used_key(code: String, table: Dictionary) -> String:
	var c := normalize(code)
	if c.is_empty():
		return ""
	return _iter_sha256(SALT_ID, c, int(table.get("iter", DEFAULT_ITER))).hex_encode()


static func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for i in range(0, s.length() - 1, 2):
		out.append(("0x" + s.substr(i, 2)).hex_to_int())
	return out
