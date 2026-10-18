"""把角色图与剪影图合成为带描边的角色图。

用法：
    python tools/compose_outline.py <char.png> <sil.png> <out.png> [padding]

剪影层必须垫在角色层**下方**：`alpha_composite` 是"前景叠到背景上"，
所以调用顺序是 sil.alpha_composite(char)，不是反过来。
"""
import sys

from PIL import Image


def main() -> None:
    if len(sys.argv) < 4:
        print("用法: compose_outline.py <char.png> <sil.png> <out.png> [padding]")
        raise SystemExit(1)

    char = Image.open(sys.argv[1]).convert("RGBA")
    sil = Image.open(sys.argv[2]).convert("RGBA")
    out_path = sys.argv[3]
    padding = int(sys.argv[4]) if len(sys.argv) > 4 else 4

    if sil.size != char.size:
        sil = sil.resize(char.size, Image.LANCZOS)

    canvas = Image.new("RGBA", char.size, (0, 0, 0, 0))
    canvas.alpha_composite(sil)    # 背景层
    canvas.alpha_composite(char)   # 前景层

    box = canvas.split()[3].getbbox()
    if box is not None:
        box = (
            max(0, box[0] - padding),
            max(0, box[1] - padding),
            min(canvas.width, box[2] + padding),
            min(canvas.height, box[3] + padding),
        )
        canvas = canvas.crop(box)

    canvas.save(out_path)
    print("COMPOSED %s %s" % (out_path, canvas.size))


if __name__ == "__main__":
    main()
