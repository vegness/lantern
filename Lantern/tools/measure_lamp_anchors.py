"""实测逐帧提灯锚点，直接打印可粘贴进 player_visual.gd 的 LAMP_ANCHORS 表。

为什么必须有这个脚本：提灯挂在右手，像素位置完全由手臂姿态决定。
**手臂一改，整张锚点表就全错**，而错了不会报任何错 —— 只会表现为
"灯在画面上摆、光却不动"或"光从别处发出来"。交接文档写了"改完动作必须
重测"，但之前只有一段临时 python -c，换个会话就找不到了，于是重新发明一遍。
这里把它固化下来。

判色依据（实测）：提灯受光核心 (255,222,142)，与肤色 (254,223,189) 的
G−B 分别约 80 与 34 —— 所以用 G−B ≥ 58 且 G ≥ 195 分离，比按亮度和
色相都稳。注意兜帽/斗篷是暖红，B 通道极低，G−B 也很大，必须同时卡
R−G 上限，否则会把斗篷边缘算进来。

用法：
    D:/python/python.exe tools/measure_lamp_anchors.py
输出：stdout 的 GDScript 片段（并写入 verify/lamp_anchors.txt）
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art", "kid")

# 与 player_visual.gd 顶部常量必须一致
IMG_W, IMG_H = 400.0, 480.0
FOOT_RATIO = 0.7771
RENDERED_HEIGHT = 307.0
RENDERED_CENTER_X = 192.0
TARGET_HEIGHT = 47.0

SCALE = TARGET_HEIGHT / RENDERED_HEIGHT

CLIPS = {"idle": 9, "run": 9, "jump": 16}


def lamp_centroid(path):
    """返回提灯像素质心 (cx, cy) 与命中像素数。命中太少说明判色失效。"""
    im = Image.open(path).convert("RGB")
    px = im.load()
    w, h = im.size
    sx = sy = n = 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if g - b >= 58 and g >= 195 and r - g <= 45:
                sx += x
                sy += y
                n += 1
    if n == 0:
        return None, 0
    return (sx / n, sy / n), n


def main():
    out = []
    out.append("LAMP_ANCHORS 实测（每行：clip 帧号 质心px → 世界单位 命中像素数）")
    table = {}
    for clip, count in CLIPS.items():
        pts = []
        for i in range(1, count + 1):
            p = os.path.join(ART, clip, "%03d.png" % i)
            c, n = lamp_centroid(p)
            if c is None:
                out.append("  %-5s %2d  未命中！" % (clip, i))
                pts.append((0.0, 0.0))
                continue
            wx = (c[0] - RENDERED_CENTER_X) * SCALE
            wy = (c[1] - IMG_H * FOOT_RATIO) * SCALE
            pts.append((wx, wy))
            out.append("  %-5s %2d  px(%.1f,%.1f)  world(%+.1f,%+.1f)  n=%d"
                       % (clip, i, c[0], c[1], wx, wy, n))
        table[clip] = pts

    out.append("")
    out.append("── 粘贴到 scripts/player/player_visual.gd 的 LAMP_ANCHORS ──")
    out.append("const LAMP_ANCHORS := {")
    for clip, pts in table.items():
        out.append('\t"%s": [' % clip)
        line = "\t\t"
        for k, (wx, wy) in enumerate(pts):
            piece = "Vector2(%.1f, %.1f), " % (wx, wy)
            if len(line) + len(piece) > 96:
                out.append(line.rstrip())
                line = "\t\t"
            line += piece
        if line.strip():
            out.append(line.rstrip())
        out.append("\t],")
    out.append("}")

    text = "\n".join(out)
    print(text)
    with open(os.path.join(ROOT, "verify", "lamp_anchors.txt"), "w", encoding="utf-8") as f:
        f.write(text + "\n")


if __name__ == "__main__":
    sys.exit(main())
