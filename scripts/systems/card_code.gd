class_name CardCode
extends RefCounted

const SALT_ID := "dv2.cc.id.v1"
const SALT_KEY := "dv2.cc.key.v1"
const DEFAULT_ITER := 10000

const PUNCT_EXTRA := "·—–―…“”‘’、。，．！？：；（）［］｛｝「」『』〈〉《》〜～"
const SPACE_CP := [0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
	0x2007, 0x2008, 0x2009, 0x200A, 0x200B, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]

static func normalize(code: String) -> String:
	var out := ""
	for c in code:
		if (c >= "0" and c <= "9") or (c >= "A" and c <= "Z"):
			out += c
		elif c >= "a" and c <= "z":
			out += c.to_upper()
		elif c.unicode_at(0) >= 0x80 and not PUNCT_EXTRA.contains(c) and not SPACE_CP.has(c.unicode_at(0)):
			out += c
	return out

static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()

static func _iter_sha256(salt: String, code: String, iterations: int) -> PackedByteArray:
	var h := _sha256((salt + code).to_utf8_buffer())
	for i in maxi(0, iterations - 1):
		h = _sha256(h)
	return h

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

static func _tag(key: PackedByteArray, nonce: PackedByteArray, cipher: PackedByteArray) -> String:
	var seed := key.duplicate()
	seed.append_array(nonce)
	seed.append_array(cipher)
	return _sha256(seed).hex_encode().substr(0, 32)

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
			return {}
		var plain := _xor(cipher, _keystream(key, nonce, cipher.size()))
		var parsed = JSON.parse_string(plain.get_string_from_utf8())
		return parsed if parsed is Dictionary else {}
	return {}

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
