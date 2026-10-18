"""按矩形区域裁剪图片。

用法:
    python crop_image.py <源图> <输出图> <x> <y> <宽> <高>
"""

import sys

from PIL import Image


def main() -> None:
    if len(sys.argv) < 7:
        print(__doc__)
        raise SystemExit(1)

    src, dst = sys.argv[1], sys.argv[2]
    x, y, w, h = (int(v) for v in sys.argv[3:7])

    image = Image.open(src).convert("RGBA")
    cropped = image.crop((x, y, x + w, y + h))
    cropped.save(dst)
    print(f"saved {dst} {cropped.size}")


if __name__ == "__main__":
    main()
