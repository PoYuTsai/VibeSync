"""抽卡揭曉 V3 第三刀音效產生器（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md §8）。

D3 定案：N／R／SR 用同一條揭曉配樂（沿用 v4「SR／R／N 聲音一致」），稀有度差別只靠畫面與震動。
這支程式產出兩個檔：

- `practice_draw_reveal_bed_v6.m4a`：bed v5 的同一段音樂（bed v4 的 4.95–8.25 s，120 ms 淡入、
  2.9–3.3 s 淡出），把翻牌紙聲（flip snap 1）直接混進 1.35 s。紙聲照原本的播放比例
  （紙聲 0.25 ÷ bed 0.74）混入，和音樂同一個 player，不會各自延遲。
- `practice_draw_archive_v3.m4a`：收卡音，Claude Code 原創程式合成（沒有任何 sample）。
  0–450 ms 從 G4 輕輕滑到 G5，450 ms（光球落進那一格）一聲水晶鈴（G5＋C6＋E6）加一點低頻
  落點，0.8 s 內收完。只用有音高的正弦疊加、7 kHz 以上低通，沒有噪聲，不會有「西西簌簌」聲。

用法（在 repo 根目錄）：
  python3 tools/practice-draw-audio-v3/make_audio_v3.py
沒有指定來源時，從 git 取 bed v4 與紙聲（兩個檔都已不在工作目錄）。需要 numpy 與 ffmpeg。
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / 'assets/audio/practice_draw'
SR = 48000

# 來源（git 歷史）：bed v4 在 2aae192 之前都在；紙聲最後一次在 e0f534e（第二刀）。
BED_V4_REV = '2aae192:assets/audio/practice_draw/practice_draw_reveal_bed.mp3'
SNAP_REV = 'e0f534e:assets/audio/practice_draw/practice_draw_flip_snap_1.wav'

# bed：和 v5 同一段、同樣的淡入淡出。
BED_START_S = 4.95
BED_LENGTH_S = 3.3
BED_FADE_IN_S = 0.12
BED_FADE_OUT_FROM_S = 2.9

# 紙聲落在卡片側立那一刻，音量比例照原本兩個 player 的播放音量。
SNAP_AT_S = 1.35
SNAP_GAIN = 0.25 / 0.74

# 收卡音：時間點對齊 PracticeRevealTiming（landMs 450），總長 0.8 s。
ARCHIVE_LENGTH_S = 0.8
ARCHIVE_LAND_S = 0.45
ARCHIVE_PEAK_DBFS = -3.0
LOWPASS_HZ = 7000


def git_bytes(rev_path: str) -> bytes:
    return subprocess.run(
        ['git', 'show', rev_path], cwd=ROOT, check=True, capture_output=True
    ).stdout


def decode(path: Path, start: float | None = None, length: float | None = None) -> np.ndarray:
    """用 ffmpeg 解成 48 kHz 立體聲 float32，形狀 (n, 2)。"""
    cmd = ['ffmpeg', '-v', 'error']
    if start is not None:
        cmd += ['-ss', f'{start}']
    if length is not None:
        cmd += ['-t', f'{length}']
    cmd += ['-i', str(path), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-']
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def write_wav(path: Path, audio: np.ndarray) -> None:
    pcm = np.round(np.clip(audio, -1, 1) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def encode_aac(wav: Path, out: Path) -> None:
    subprocess.run(
        ['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-c:a', 'aac', '-b:a', '160k',
         '-ar', str(SR), '-ac', '2', '-movflags', '+faststart', str(out)],
        check=True,
    )


def lowpass(audio: np.ndarray, cutoff: float) -> np.ndarray:
    """FFT 低通，截止頻率附近 1 kHz 內平滑滾降，避免振鈴。"""
    spec = np.fft.rfft(audio, axis=0)
    freqs = np.fft.rfftfreq(audio.shape[0], 1 / SR)
    gain = np.clip((cutoff + 500 - freqs) / 1000, 0, 1)
    return np.fft.irfft(spec * gain[:, None], n=audio.shape[0], axis=0)


def build_bed(bed_v4: Path, snap: Path) -> np.ndarray:
    bed = decode(bed_v4, BED_START_S, BED_LENGTH_S)
    n = bed.shape[0]
    t = np.arange(n) / SR
    fade_in = np.clip(t / BED_FADE_IN_S, 0, 1)
    fade_out = np.clip((BED_LENGTH_S - t) / (BED_LENGTH_S - BED_FADE_OUT_FROM_S), 0, 1)
    bed *= (fade_in * fade_out)[:, None]

    paper = decode(snap) * SNAP_GAIN
    at = int(round(SNAP_AT_S * SR))
    end = min(n, at + paper.shape[0])
    bed[at:end] += paper[: end - at]
    peak = float(np.abs(bed).max())
    assert peak < 0.99, f'bed clips after adding the paper snap (peak {peak:.3f})'
    return bed


def _partial(t: np.ndarray, freq: float, amp: float, decay: float, start: float,
             attack: float = 0.003) -> np.ndarray:
    local = t - start
    env = np.where(local < 0, 0.0,
                   np.minimum(1.0, local / attack) * np.exp(-np.maximum(local, 0) / decay))
    return amp * env * np.sin(2 * np.pi * freq * np.maximum(local, 0))


def build_archive() -> np.ndarray:
    n = int(round(ARCHIVE_LENGTH_S * SR))
    t = np.arange(n) / SR
    channels = []
    for cents in (+2.0, -2.0):  # 左右各偏 2 cents，做出一點寬度、單聲道也相容。
        detune = 2 ** (cents / 1200)

        # 0–450 ms：G4 → G5 的輕柔上滑（正弦＋兩個泛音），落點前 50 ms 收掉。
        f0, f1 = 392.0 * detune, 784.0 * detune
        rise_len = ARCHIVE_LAND_S
        k = np.log2(f1 / f0) / rise_len
        phase = 2 * np.pi * f0 * (2 ** (k * np.minimum(t, rise_len)) - 1) / (k * np.log(2))
        phase += 2 * np.pi * f1 * np.maximum(t - rise_len, 0)
        swell = np.clip(t / rise_len, 0, 1) ** 1.5
        release = np.where(t < rise_len, 1.0, np.exp(-(t - rise_len) / 0.05))
        rise = (np.sin(phase) + 0.3 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase))
        rise *= 0.32 * swell * release

        # 450 ms：水晶鈴。C6 帶玻璃感的非整數泛音，下面墊 G5、上面點 E6（C 大調，和配樂同調）。
        land = ARCHIVE_LAND_S
        c6 = 1046.5 * detune
        chime = sum(
            _partial(t, c6 * ratio, amp, decay, land)
            for ratio, amp, decay in (
                (1.0, 1.0, 0.32),
                (2.0, 0.32, 0.20),
                (2.92, 0.20, 0.14),
                (4.16, 0.10, 0.09),
                (5.43, 0.05, 0.06),
            )
        )
        chime += _partial(t, 784.0 * detune, 0.55, 0.36, land)
        chime += _partial(t, 1318.5 * detune, 0.30, 0.24, land + 0.012)
        chime *= 0.5

        # 落點的一點重量：C3 正弦，60 ms 衰減。
        thump = _partial(t, 130.81, 0.35, 0.06, land, attack=0.002)

        channels.append(rise + chime + thump)

    audio = np.stack(channels, axis=1)
    audio = lowpass(audio, LOWPASS_HZ)
    # 最後 60 ms 收到 0，0.8 s 整收完。
    tail = np.clip((ARCHIVE_LENGTH_S - t) / 0.06, 0, 1)
    audio *= tail[:, None]
    audio *= 10 ** (ARCHIVE_PEAK_DBFS / 20) / float(np.abs(audio).max())
    return audio


def loudness(path: Path) -> str:
    out = subprocess.run(
        ['ffmpeg', '-nostats', '-i', str(path), '-af', 'ebur128=peak=true:framelog=quiet',
         '-f', 'null', '-'],
        capture_output=True, text=True,
    ).stderr
    lines = [line.strip() for line in out.splitlines() if line.strip().startswith(('I:', 'Peak:'))]
    return ', '.join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--bed-v4', type=Path, help='bed v4 mp3（預設從 git 取）')
    parser.add_argument('--snap', type=Path, help='flip snap 1 wav（預設從 git 取）')
    parser.add_argument('--out', type=Path, default=OUT_DIR)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        bed_v4 = args.bed_v4
        if bed_v4 is None:
            bed_v4 = tmp_dir / 'bed_v4.mp3'
            bed_v4.write_bytes(git_bytes(BED_V4_REV))
        snap = args.snap
        if snap is None:
            snap = tmp_dir / 'flip_snap_1.wav'
            snap.write_bytes(git_bytes(SNAP_REV))

        args.out.mkdir(parents=True, exist_ok=True)
        for name, audio in (
            ('practice_draw_reveal_bed_v6.m4a', build_bed(bed_v4, snap)),
            ('practice_draw_archive_v3.m4a', build_archive()),
        ):
            wav = tmp_dir / f'{name}.wav'
            write_wav(wav, audio)
            out = args.out / name
            encode_aac(wav, out)
            print(f'{name}: {audio.shape[0] / SR:.2f} s, {out.stat().st_size / 1024:.1f} KB; '
                  f'{loudness(out)}')


if __name__ == '__main__':
    main()
