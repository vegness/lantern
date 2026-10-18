"""从截图中裁剪一块区域并放大，便于逐像素检查细节。

用法:
    python crop_preview.py <源图> <输出图> <中心x> <中心y> <半宽> <放大倍数>
"""

import sys

from PIL import Image


def main() -> None:
    if len(sys.argv) < 7:
        print(__doc__)
        raise SystemExit(1)

    src, dst = sys.argv[1], sys.argv[2]
    cx, cy, half, scale = (int(v) for v in sys.argv[3:7])

    image = Image.open(src)
    box = (cx - half, cy - half, cx + half, cy + half)
    crop = image.crop(box).resize((half * 2 * scale, half * 2 * scale), Image.NEAREST)
    crop.save(dst)
    print(f"saved {dst} size={crop.size}")


if __name__ == "__main__":
    main()
