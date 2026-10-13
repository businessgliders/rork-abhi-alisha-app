"""Search results asset, 3840x2560 (3:2, Apple's template size): cream paper, one
Playfair italic line, three Dynamic Island iPhones — Schedule (left), Home (centre,
larger, in front), Chat (right). The line and all three phones sit inside Apple's
template Art Safe Area (x 836-3004, y 765-1795). Captures are only ever downscaled."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 3840, 2560
SAFE = (836, 765, 3004, 1795)
CAP = "screenshots/captures/iphone"
OUT = "screenshots/experiments/product-page"
INK = (43, 38, 34)        # brand ink #2B2622
GOLD = (194, 162, 76)     # brand gold #C2A24C
LINE = "Your guide to our wedding week"


def paper():
    bg = Image.open("screenshots/backgrounds/schedule.png").convert("RGB")
    s = max(W / bg.width, H / bg.height)
    bg = bg.resize((round(bg.width * s), round(bg.height * s)), Image.LANCZOS)
    x0 = (bg.width - W) // 2
    bg = bg.crop((x0, 0, x0 + W, H))
    return Image.blend(bg, Image.new("RGB", (W, H), (246, 239, 226)), 0.35)


def phone(capture, scale):
    scr = Image.open(f"{CAP}/{capture}.png").convert("RGB")
    assert scale <= 1.0, "never upscale a capture"
    sw, sh = round(402 * scale), round(874 * scale)
    scr = scr.resize((sw, sh), Image.LANCZOS)
    rim, bezel = max(2, round(4 * scale)), round(13 * scale)
    bw, bh = sw + 2 * (rim + bezel), sh + 2 * (rim + bezel)
    sr = round(55 * scale)
    br = sr + rim + bezel
    pad = round(8 * scale)
    im = Image.new("RGBA", (bw + 2 * pad, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    btn = (178, 179, 184, 255)
    for y, h in [(150, 32), (205, 62), (278, 62)]:
        d.rounded_rectangle([pad - 4 * scale, y * scale, pad + 3, (y + h) * scale], radius=2, fill=btn)
    for y, h in [(240, 92), (565, 50)]:
        d.rounded_rectangle([pad + bw - 3, y * scale, pad + bw + 4 * scale, (y + h) * scale], radius=2, fill=btn)
    d.rounded_rectangle([pad, 0, pad + bw - 1, bh - 1], radius=br, fill=(198, 199, 203, 255))
    d.rounded_rectangle([pad + 1, 1, pad + bw - 2, bh - 2], radius=br - 1, fill=(222, 223, 226, 255))
    d.rounded_rectangle([pad + rim - 1, rim - 1, pad + bw - rim, bh - rim], radius=br - rim + 1, fill=(120, 121, 124, 255))
    d.rounded_rectangle([pad + rim, rim, pad + bw - rim - 1, bh - rim - 1], radius=br - rim, fill=(19, 19, 19, 255))
    m = Image.new("L", (sw * 4, sh * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, sw * 4 - 1, sh * 4 - 1], radius=sr * 4, fill=255)
    im.paste(scr, (pad + rim + bezel, rim + bezel), m.resize((sw, sh), Image.LANCZOS))
    return im, pad


def drop(canvas, x, y, w, h, r, alpha, blur, dy):
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([x + 6, y + dy, x + w - 6, y + h + dy], radius=r, fill=(60, 42, 22, alpha))
    return Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(blur)))


canvas = paper().convert("RGBA")
d = ImageDraw.Draw(canvas)
f = ImageFont.truetype("ios-abhi-alisha/Shared/Resources/PlayfairDisplay-Italic.ttf", 104)
f.set_variation_by_axes([500])
BASE = SAFE[1] + 98
d.text((W / 2, BASE), LINE, font=f, fill=INK, anchor="ms")
tb = d.textbbox((W / 2, BASE), LINE, font=f, anchor="ms")
d.line([(W / 2 - 64, BASE + 30), (W / 2 + 64, BASE + 30)], fill=GOLD, width=3)

MID_S, SIDE_S = 0.95, 0.83
TOP = BASE + 64
left, lp = phone("02_schedule", SIDE_S)
mid, mp = phone("01_home", MID_S)
right, rp = phone("03_chat", SIDE_S)
mw, mh = mid.width - 2 * mp, mid.height
sw_, sh_ = left.width - 2 * lp, left.height
GAP = round((mw + sw_) / 2 - 14)            # centre phone in front, overlapping bezels only
side_top = TOP + (mh - sh_) // 2 + 14
cx = W // 2
boxes = [tb]
for im, pad, xc in [(left, lp, cx - GAP), (right, rp, cx + GAP)]:
    x = xc - (im.width - 2 * pad) // 2
    canvas = drop(canvas, x, side_top, im.width - 2 * pad, im.height, 44, 80, 22, 18)
    canvas.alpha_composite(im, (x - pad, side_top))
    boxes.append((x - pad, side_top, x - pad + im.width, side_top + im.height))
x = cx - mw // 2
canvas = drop(canvas, x, TOP, mw, mh, 52, 120, 28, 24)
canvas.alpha_composite(mid, (x - mp, TOP))
boxes.append((x - mp, TOP, x - mp + mid.width, TOP + mh))

bx = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
ok = bx[0] >= SAFE[0] and bx[1] >= SAFE[1] and bx[2] <= SAFE[2] and bx[3] <= SAFE[3]
print("content", bx, "inside Apple safe area:", ok, "| centre screen", round(402 * MID_S), "x", round(874 * MID_S),
      "side screen", round(402 * SIDE_S), "x", round(874 * SIDE_S))
assert ok
canvas.convert("RGB").save(f"{OUT}/search_3840x2560.png", "PNG")
