"""암호화 CCZ(.pvr.ccz, CCZp) → PNG 디코더.

원작 APK의 공용 아틀라스(common/9patch 등)는 Cocos2d-x의 **암호화된 CCZp**(zlib 전에 XXTEA XOR)
+ PVR 텍스처로 패킹돼 DV2 추출본에 PNG가 없다. libgame.so에서 복원한 암호화 키로 복호→PVR디코드→PNG.

키: `ZipUtils::ccSetPvrEncryptionKey(0x17bf0e94,0x48e4d95a,0x93ffa8d2,0x0dc9a342)` (libgame.so, .ccz 로드 시).
복호: `ccInflateCCZFile`대로 offset 0xc(12)부터 XOR복호(len필드 포함) → offset 0x10(16)부터 zlib inflate → PVR.
PVR: PVRv2(RGBA4444/8888 등).

사용:  python scripts/tools/ccz_to_png.py <in.pvr.ccz> <out.png>
"""
from __future__ import annotations
import zlib, struct, sys
from pathlib import Path
import numpy as np
from PIL import Image

KEY = [0x17bf0e94, 0x48e4d95a, 0x93ffa8d2, 0x0dc9a342]
M = 0xffffffff
DELTA = 0x9e3779b9


def _mx(y, z, s, kp):
    left = ((((y << 2) & M) ^ (z >> 5)) + ((y >> 3) ^ ((z << 4) & M))) & M
    right = ((kp ^ z) + ((y ^ s) & M)) & M
    return (left ^ right) & M


def gen_key():
    enclen = 1024
    k = [0] * enclen
    rounds = 6; s = 0
    while rounds != 0:
        s = (s + DELTA) & M
        e = (s >> 2) & 3
        z = k[enclen - 1]
        for p in range(enclen - 1):
            z = (_mx(k[p + 1], z, s, KEY[(p & 3) ^ e]) + k[p]) & M
            k[p] = z
        z = (_mx(k[0], z, s, KEY[3 ^ e]) + k[enclen - 1]) & M
        k[enclen - 1] = z
        rounds -= 1
    return k


def _xor(words, key):
    enclen = 1024; securelen = 512; distance = 64
    n = len(words); b = 0; i = 0
    while i < n and i < securelen:
        words[i] ^= key[b]; b = 0 if b + 1 >= enclen else b + 1; i += 1
    while i < n:
        words[i] ^= key[b]; b = 0 if b + 1 >= enclen else b + 1; i += distance
    return words


def decrypt_ccz(path) -> bytes:
    data = Path(path).read_bytes()
    assert data[:4] in (b'CCZ!', b'CCZp'), data[:4]
    payload = data[12:]                      # 복호는 offset 12부터
    nw = len(payload) // 4
    words = list(struct.unpack('<%dI' % nw, payload[:nw * 4]))
    _xor(words, gen_key())
    decb = struct.pack('<%dI' % nw, *words) + payload[nw * 4:]
    return zlib.decompress(decb[4:])         # offset 16부터 zlib


def pvr_to_image(raw: bytes) -> Image.Image:
    hlen, h, w, mip, flags = struct.unpack('<IIIII', raw[:20])
    pfmt = flags & 0xff
    px = raw[hlen:]
    n = w * h
    if pfmt in (0x12, 0x11) and len(px) >= n * 4:   # RGBA8888/ARGB
        return Image.frombytes('RGBA', (w, h), px[:n * 4])
    # RGBA4444 (0x10)
    a = np.frombuffer(px[:n * 2], dtype='<u2').astype(np.uint32)
    r = ((a >> 12) & 0xF) * 17; g = ((a >> 8) & 0xF) * 17
    b = ((a >> 4) & 0xF) * 17; al = (a & 0xF) * 17
    arr = np.stack([r, g, b, al], axis=1).astype('u1').reshape(h, w, 4)
    return Image.fromarray(arr, 'RGBA')


def main():
    inp, out = sys.argv[1], sys.argv[2]
    raw = decrypt_ccz(inp)
    img = pvr_to_image(raw)
    img.save(out)
    print("%s -> %s (%dx%d)" % (inp, out, img.width, img.height))


if __name__ == '__main__':
    main()
