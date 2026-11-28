# Draws the white taskbar thumbnail-toolbar icons from the AgGlyph shapes
# (lib/ui/widgets/icons.dart) and writes multi-size .ico files.
# Usage: python tool/make_taskbar_icons.py
from pathlib import Path

from PIL import Image, ImageDraw

SIZES = [16, 20, 24, 32]
SS = 16  # supersampling factor
OUT = Path(__file__).resolve().parent.parent / 'assets' / 'taskbar'
WHITE = (255, 255, 255, 255)


def glyph(name, d, s):
    p = lambda x, y: (x * s, y * s)
    if name == 'play':
        d.polygon([p(.36, .24), p(.36, .76), p(.76, .50)], fill=WHITE)
    elif name == 'pause':
        w = .14
        for x in (.28, .58):
            d.rounded_rectangle([p(x, .24), p(x + w, .76)], radius=s * .04, fill=WHITE)
    elif name == 'previous':
        d.polygon([p(.66, .26), p(.66, .74), p(.32, .50)], fill=WHITE)
        d.rectangle([p(.24, .26), p(.32, .74)], fill=WHITE)
    elif name == 'next':
        d.polygon([p(.34, .26), p(.34, .74), p(.68, .50)], fill=WHITE)
        d.rectangle([p(.68, .26), p(.76, .74)], fill=WHITE)


def render(name, size):
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    glyph(name, ImageDraw.Draw(img), big)
    return img.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ('previous', 'play', 'pause', 'next'):
        imgs = [render(name, n) for n in SIZES]
        imgs[-1].save(
            OUT / f'{name}.ico',
            format='ICO',
            sizes=[(n, n) for n in SIZES],
            append_images=imgs[:-1],
        )
        print(OUT / f'{name}.ico')


if __name__ == '__main__':
    main()
