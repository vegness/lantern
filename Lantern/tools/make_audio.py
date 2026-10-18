"""程序化生成游戏的音效与背景音乐（WAV）。

不依赖任何外部素材库：全部用正弦波 + 谐波 + 指数包络合成。
音色统一偏向柔和的"音乐盒 / 木琴"质感，与游戏温暖低饱和的画面基调一致。

这样做的三个好处：
  1. 零版权风险，可以随项目分发；
  2. 参数就在代码里，想调"更脆一点 / 更闷一点"直接改数字；
  3. 不引入额外的素材依赖，项目 clone 下来就能出声。

用法:
    python tools/make_audio.py
"""

import math
import os
import struct
import wave

SR = 22050          # 采样率。音效素材不高，降到 22.05k 可以省一半体积
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
BGM_DIR = os.path.join(ROOT, "assets", "audio", "bgm")


def write_wav(path: str, samples) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples
        )
        handle.writeframes(frames)


def envelope(t: float, dur: float, attack: float = 0.008, decay: float = 4.0) -> float:
    if t < attack:
        return t / attack
    return math.exp(-decay * (t - attack) / dur)


def tone(f0: float, f1: float, dur: float, decay: float = 4.0,
         harm: float = 0.30, gain: float = 0.55) -> list:
    """一段带滑音的柔和音。f0→f1 为起止频率。"""
    count = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(count):
        t = i / SR
        freq = f0 + (f1 - f0) * (t / dur)
        phase += 2.0 * math.pi * freq / SR
        # 基频 + 少量二次谐波，比纯正弦更有"木质"感
        sample = math.sin(phase) + harm * math.sin(phase * 2.0) * 0.45
        out.append(sample * envelope(t, dur, 0.008, decay) * gain)
    return out


def mix(*tracks) -> list:
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, v in enumerate(track):
            out[i] += v
    return out


def silence(dur: float) -> list:
    return [0.0] * int(SR * dur)


def concat(*parts) -> list:
    out = []
    for part in parts:
        out.extend(part)
    return out


# ---------------------------------------------------------------------------
# 音效
# ---------------------------------------------------------------------------

def build_sfx() -> None:
    effects = {
        # 跳跃：短促的上行，收得干脆
        "jump.wav": tone(320.0, 620.0, 0.15, decay=6.5, harm=0.22, gain=0.42),
        # 落地：低频闷响，很轻
        "land.wav": tone(190.0, 120.0, 0.12, decay=7.5, harm=0.35, gain=0.40),
        # 提灯开关：清脆的双音
        "lantern.wav": concat(
            tone(880.0, 880.0, 0.08, decay=9.0, harm=0.15, gain=0.34),
            tone(1320.0, 1320.0, 0.16, decay=8.0, harm=0.12, gain=0.28),
        ),
        # 收集萤火：明亮上行的铃音
        "pickup.wav": concat(
            tone(1046.0, 1046.0, 0.10, decay=6.0, harm=0.18, gain=0.36),
            tone(1568.0, 1568.0, 0.26, decay=5.0, harm=0.14, gain=0.30),
        ),
        # 压力板触发 / 复位
        "plate_on.wav": tone(240.0, 360.0, 0.18, decay=5.5, harm=0.40, gain=0.44),
        "plate_off.wav": tone(330.0, 210.0, 0.16, decay=6.5, harm=0.35, gain=0.36),
        # 闸门：低沉拖长的运行声
        "gate.wav": tone(120.0, 88.0, 0.55, decay=2.2, harm=0.55, gain=0.40),
        # 藤蔓生长：上行琶音
        "grow.wav": concat(
            tone(523.0, 523.0, 0.14, decay=5.0, harm=0.20, gain=0.28),
            tone(659.0, 659.0, 0.14, decay=5.0, harm=0.20, gain=0.28),
            tone(784.0, 784.0, 0.30, decay=4.0, harm=0.18, gain=0.30),
        ),
        # 点亮终点灯座：一个明亮的和弦，拖得久一点
        "goal.wav": mix(
            tone(523.0, 523.0, 0.95, decay=2.6, harm=0.16, gain=0.24),
            tone(659.0, 659.0, 0.95, decay=2.6, harm=0.16, gain=0.22),
            tone(784.0, 784.0, 0.95, decay=2.6, harm=0.16, gain=0.22),
            tone(1046.0, 1046.0, 0.95, decay=3.0, harm=0.12, gain=0.18),
        ),
    }
    for name, samples in effects.items():
        path = os.path.join(SFX_DIR, name)
        write_wav(path, samples)
        print(f"sfx  {name:16s} {len(samples) / SR:.2f}s")


# ---------------------------------------------------------------------------
# 背景音乐
# ---------------------------------------------------------------------------

NOTES = {
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00,
    "A4": 440.00, "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25,
    "F5": 698.46, "G5": 783.99, "A5": 880.00,
}

# 一段温柔的四小节循环：C - Am - F - G
# 每小节左手一个长低音，右手四个分解音，像音乐盒。
PROGRESSION = [
    ("C4", ["E4", "G4", "C5", "G4"]),
    ("A4", ["C5", "E5", "A5", "E5"]),
    ("F4", ["A4", "C5", "F5", "C5"]),
    ("G4", ["B4", "D5", "G5", "D5"]),
]


def build_bgm() -> None:
    beat = 0.52
    bar_tracks = []
    for bass_name, arp in PROGRESSION:
        bass = NOTES[bass_name] / 2.0     # 低八度作为铺底
        bar = mix(
            # 低音：长音、慢衰减
            tone(bass, bass, beat * 4.0, decay=0.9, harm=0.45, gain=0.20),
            silence(beat * 0.0),
        )
        # 右手分解和弦
        arp_track = []
        for note_name in arp:
            freq = NOTES[note_name]
            arp_track = concat(
                arp_track,
                tone(freq, freq, beat * 0.95, decay=3.4, harm=0.14, gain=0.20),
            )
        # 让低音与琶音长度对齐
        length = max(len(bar), len(arp_track))
        padded = bar + [0.0] * (length - len(bar))
        for i, v in enumerate(arp_track):
            padded[i] += v
        bar_tracks.append(padded)

    loop = concat(*bar_tracks)
    # 简单软限幅，避免叠加后削顶产生刺耳失真
    loop = [math.tanh(v * 1.25) * 0.62 for v in loop]

    path = os.path.join(BGM_DIR, "theme.wav")
    write_wav(path, loop)
    print(f"bgm  theme.wav        {len(loop) / SR:.2f}s")


if __name__ == "__main__":
    build_sfx()
    build_bgm()
