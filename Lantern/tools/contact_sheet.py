"""把多张截图横向拼成一张对比图。

用法:
    python contact_sheet.py <输出图> <输入图1> <输入图2> ...
"""

import sys

from PIL import Image


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        raise SystemExit(1)

    dst = sys.argv[1]
    paths = sys.argv[2:]

    images = [Image.open(p).convert("RGBA") for p in paths]
    total_w = sum(img.width for img in images)
    max_h = max(img.height for img in images)

    sheet = Image.new("RGBA", (total_w, max_h), (0, 0, 0, 0))
    x = 0
    for img in images:
        sheet.paste(img, (x, max_h - img.height))
        x += img.width

    sheet.save(dst)
    print(f"saved {dst} {sheet.size}")


if __name__ == "__main__":
    main()
