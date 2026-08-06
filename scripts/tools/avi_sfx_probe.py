"""`--write-movie` 로 구운 AVI 에서 **오디오만** 뜯어 소리가 난 시각을 잰다.

각성기 효과음 배선을 눈이 아니라 **파형으로** 검증하려고 만들었다(2026-08-06).
Godot 의 movie writer 는 AVI 에 PCM 오디오를 함께 굽는다 — RIFF 의 `01wb` 청크가 그것이다.
프레임 캡처와 같은 고정 델타라 시각이 어긋나지 않는다([[dv2-wallclock-capture-desync]]).

    python scripts/tools/avi_sfx_probe.py out.avi [--win 0.05] [--thr 0.02]
"""
from __future__ import annotations
import argparse, struct, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def read_wav_chunks(blob: bytes) -> tuple[bytes, int, int]:
    """RIFF 를 훑어 `01wb`(PCM) 를 잇고 `strf`(WAVEFORMATEX)에서 채널·샘플레이트를 읽는다."""
    pcm, rate, ch = bytearray(), 48000, 2
    i, n = 12, len(blob)
    stack = [n]
    while i + 8 <= n:
        cid = blob[i:i + 4]
        sz, = struct.unpack_from("<I", blob, i + 4)
        if cid in (b"LIST", b"RIFF"):
            i += 12                                   # 리스트는 안으로 들어간다
            continue
        if cid == b"strf" and sz >= 16:
            tag, c, r = struct.unpack_from("<HHI", blob, i + 8)
            if tag == 1:                              # WAVE_FORMAT_PCM
                ch, rate = c, r
        elif cid == b"01wb":
            pcm += blob[i + 8:i + 8 + sz]
        i += 8 + sz + (sz & 1)
    del stack
    return bytes(pcm), rate, ch


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("avi")
    ap.add_argument("--win", type=float, default=0.05, help="RMS 창(초)")
    ap.add_argument("--thr", type=float, default=0.02, help="소리로 칠 RMS 문턱(0~1)")
    a = ap.parse_args()

    pcm, rate, ch = read_wav_chunks(Path(a.avi).read_bytes())
    if not pcm:
        print("오디오 청크(01wb)가 없다 — --write-movie 로 구운 파일인지 확인할 것."); return
    step = max(1, int(rate * a.win)) * ch
    total = len(pcm) // 2
    print("PCM %.2f초 · %dHz · %dch" % (total / ch / rate, rate, ch))

    prev_loud = False
    for off in range(0, total - step, step):
        s = struct.unpack_from("<%dh" % step, pcm, off * 2)
        rms = (sum(v * v for v in s) / len(s)) ** 0.5 / 32768.0
        loud = rms >= a.thr
        t = off / ch / rate
        if loud and not prev_loud:                    # 상승 에지 = 새 효과음
            print("  ▲ %6.2fs  RMS %.3f" % (t, rms))
        prev_loud = loud


if __name__ == "__main__":
    main()
