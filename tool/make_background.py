from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "bg"
W, H = 1280, 800
BLOB_SRC = 256
BLOB_SPAN = 1.0

THEMES = {
    "night": dict(bg=(8, 9, 11), lift=(22, 22, 27), pool=(4, 4, 6),
                  blob=(40, 40, 44), hi=(43, 43, 47), lo=14.0, hi_cap=18.0),
    "light": dict(bg=(228, 228, 234), lift=(244, 244, 247), pool=(222, 222, 228),
                  blob=(214, 214, 219), hi=(218, 218, 223), lo=85.0, hi_cap=89.0),
}


def lstar(arr):
    c = arr[..., :3] / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    y = lin @ np.array([0.2126, 0.7152, 0.0722])
    fy = np.where(y > 0.008856, np.cbrt(y), 7.787 * y + 16 / 116)
    return 116 * fy - 16


def gauss(xx, yy, cx, cy, sx, sy, ang_deg):
    a = np.radians(ang_deg)
    x, y = xx - cx, yy - cy
    xr = x * np.cos(a) + y * np.sin(a)
    yr = -x * np.sin(a) + y * np.cos(a)
    return np.exp(-0.5 * ((xr / sx) ** 2 + (yr / sy) ** 2))


def grain(arr, seed):
    rng = np.random.default_rng(seed)
    n = rng.integers(-1, 2, size=arr.shape[:2])[..., None]
    return np.clip(arr + n, 0, 255)


def smoke(t):
    sw, sh = 256, 160
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    xx, yy = xx / sw, yy / sh
    img = np.zeros((sh, sw, 3), np.float32) + np.array(t["bg"], np.float32)
    lift = gauss(xx, yy, 0.22, 0.18, 0.34, 0.30, -25)[..., None]
    pool = gauss(xx, yy, 0.86, 0.92, 0.22, 0.20, 20)[..., None]
    img = img + lift * 0.55 * (np.array(t["lift"]) - img)
    img = img + pool * 0.5 * (np.array(t["pool"]) - img)
    low = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(8))
    arr = np.asarray(low.resize((W, H), Image.Resampling.LANCZOS)).astype(np.float32)
    return grain(arr, 11).astype(np.uint8)


def blob(t):
    n = BLOB_SRC
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    xx = (xx / (n - 1) - 0.5) * BLOB_SPAN
    yy = (yy / (n - 1) - 0.5) * BLOB_SPAN
    a1 = gauss(xx, yy, 0.0, 0.0, 0.190, 0.150, -22)
    a2 = 0.55 * gauss(xx, yy, -0.045, -0.040, 0.090, 0.075, -18)
    r = np.maximum(np.abs(xx), np.abs(yy)) / (BLOB_SPAN / 2)
    fade = np.clip((1.0 - r) / 0.18, 0, 1)
    fade = fade * fade * (3 - 2 * fade)
    a1, a2 = a1 * fade, a2 * fade
    alpha = 1 - (1 - a1) * (1 - a2)
    w_hi = (a2 / np.maximum(alpha, 1e-6))[..., None]
    col = np.array(t["blob"], np.float32) * (1 - w_hi) + np.array(t["hi"], np.float32) * w_hi
    col = grain(col, 7)
    img = Image.fromarray(np.dstack([np.clip(col, 0, 255), alpha * 255]).astype(np.uint8), "RGBA")
    return img.filter(ImageFilter.GaussianBlur(1.2))


def composite(base, blob_img, cx, cy, s):
    side = int(round(BLOB_SPAN * W * s))
    b = blob_img.resize((side, side), Image.Resampling.BILINEAR)
    out = Image.fromarray(base).convert("RGBA")
    layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
    layer.paste(b, (int(round(cx * W - side / 2)), int(round(cy * H - side / 2))))
    return np.asarray(Image.alpha_composite(out, layer).convert("RGB")).astype(np.float32)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, t in THEMES.items():
        base = smoke(t)
        b = blob(t)
        Image.fromarray(base).save(OUT / f"smoke_{name}.png", optimize=True)
        b.save(OUT / f"blob_{name}.png", optimize=True)
        Lb = lstar(base.astype(np.float32))
        comp = composite(base, b, 0.60, 0.70, 1.0)
        Lc = lstar(comp)
        centre = Lc[int(0.70 * H) - 5:int(0.70 * H) + 5, int(0.60 * W) - 5:int(0.60 * W) + 5].mean()
        print(f"{name}: base L* {Lb.min():.1f}-{Lb.max():.1f}  "
              f"with blob L* {Lc.min():.1f}-{Lc.max():.1f}  blob centre {centre:.1f}")
