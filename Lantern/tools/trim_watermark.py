"""裁掉 AI 生成图右下角的水印。

用法:
    python trim_watermark.py <源图> <输出图> [右裁像素] [下裁像素]
"""

import sys

from PIL import Image


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        raise SystemExit(1)

    src, dst = sys.argv[1], sys.argv[2]
    trim_right = int(sys.argv[3]) if len(sys.argv) > 3 else 130
    trim_bottom = int(sys.argv[4]) if len(sys.argv) > 4 else 70

    image = Image.open(src).convert("RGBA")
    width, height = image.size
    trimmed = image.crop((0, 0, width - trim_right, height - trim_bottom))
    trimmed.save(dst)
    print(f"saved {dst} {trimmed.size}")


if __name__ == "__main__":
    main()
