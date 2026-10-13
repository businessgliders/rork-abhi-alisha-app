"""iPhone 6.9" (1320x2868) App Store slides laid out like the iPad set:
headline on top, whole device centred with even side margins, background below."""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
INK = (30, 26, 20)
CAP = "screenshots/captures/iphone"
OUT = "screenshots/iphone/en"

# Device geometry (iPhone 17 Pro Max proportions, thin black bezel like the iPad frame)
SIDE = 170
RIM, BEZEL = 7, 26
BODY_W = W - 2 * SIDE
SCR_W = BODY_W - 2 * (RIM + BEZEL)
SCALE = SCR_W / 402
SCR_H = round(874 * SCALE)
BODY_H = SCR_H + 2 * (RIM + BEZEL)
SCR_R = round(55 * SCALE)
BODY_R = SCR_R + RIM + BEZEL
DEV_X = SIDE
DEV_Y = 600

HEAD_SIZE = 112
LINE_H = round(HEAD_SIZE * 1.2)


def headline_font():
    f = ImageFont.truetype("/tmp/PlayfairItalic-VF.ttf", HEAD_SIZE)
    try:
        f.set_variation_by_axes([600])
    except Exception:
        pass
    return f


def background(name):
    bg = Image.open(f"screenshots/backgrounds/{name}.png").convert("RGB")
    s = H / bg.height
    bg = bg.resize((round(bg.width * s), H), Image.LANCZOS)
    x0 = (bg.width - W) // 2
    return bg.crop((x0, 0, x0 + W, H))


def screen(name):
    src = Image.open(f"{CAP}/{name}.png").convert("RGB")
    if name == "05_my_experience":
        # Scrolled content sits under the status bar here; give it the same clean
        # status bar band as the other captures so 9:41 / signal / battery read clearly.
        band = Image.open(f"{CAP}/03_chat.png").convert("RGB").crop((0, 0, 402, 58))
        fade = Image.new("L", (402, 70), 255)
        fd = ImageDraw.Draw(fade)
        for y in range(58, 70):
            fd.line([(0, y), (402, y)], fill=int(255 * (70 - y) / 12))
        base = Image.open(f"{CAP}/03_chat.png").convert("RGB").crop((0, 0, 402, 70))
        src.paste(base, (0, 0), fade)
        src.paste(band, (0, 0))
    scr = src.resize((SCR_W, SCR_H), Image.LANCZOS)
    # Crisp Dynamic Island over the upscaled one (capture island: x139-262, y14-49 pt)
    d = ImageDraw.Draw(scr)
    ix0, ix1 = 139 * SCALE - 2, 262 * SCALE + 2
    iy0, iy1 = 14 * SCALE - 2, 49 * SCALE + 2
    d.rounded_rectangle([ix0, iy0, ix1, iy1], radius=(iy1 - iy0) / 2, fill=(0, 0, 0))
    lens = (ix1 - 0.17 * (ix1 - ix0), (iy0 + iy1) / 2)
    r = (iy1 - iy0) * 0.17
    d.ellipse([lens[0] - r, lens[1] - r, lens[0] + r, lens[1] + r], fill=(18, 20, 30))
    return scr


def device(canvas):
    # soft drop shadow
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [DEV_X + 10, DEV_Y + 34, DEV_X + BODY_W - 10, DEV_Y + BODY_H + 34],
        radius=BODY_R, fill=(50, 38, 24, 70))
    sh = sh.filter(ImageFilter.GaussianBlur(40))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), sh).convert("RGB")
    d = ImageDraw.Draw(canvas)

    # side buttons: action + volume (left), side button + camera control (right)
    btn = (178, 179, 184)
    for y, h in [(330, 70), (450, 135), (610, 135)]:
        d.rounded_rectangle([DEV_X - 6, DEV_Y + y, DEV_X + 4, DEV_Y + y + h], radius=4, fill=btn)
    for y, h in [(520, 200), (1240, 110)]:
        d.rounded_rectangle([DEV_X + BODY_W - 4, DEV_Y + y, DEV_X + BODY_W + 6, DEV_Y + y + h], radius=4, fill=btn)

    # silver rim, then black bezel
    d.rounded_rectangle([DEV_X, DEV_Y, DEV_X + BODY_W, DEV_Y + BODY_H], radius=BODY_R, fill=(198, 199, 203))
    d.rounded_rectangle([DEV_X + 2, DEV_Y + 2, DEV_X + BODY_W - 2, DEV_Y + BODY_H - 2],
                        radius=BODY_R - 2, fill=(222, 223, 226))
    d.rounded_rectangle([DEV_X + RIM - 2, DEV_Y + RIM - 2, DEV_X + BODY_W - RIM + 2, DEV_Y + BODY_H - RIM + 2],
                        radius=BODY_R - RIM + 2, fill=(120, 121, 124))
    d.rounded_rectangle([DEV_X + RIM, DEV_Y + RIM, DEV_X + BODY_W - RIM, DEV_Y + BODY_H - RIM],
                        radius=BODY_R - RIM, fill=(19, 19, 19))
    return canvas


def compose(name, bg_name, headline):
    canvas = background(bg_name)
    canvas = device(canvas)

    sx, sy = DEV_X + RIM + BEZEL, DEV_Y + RIM + BEZEL
    mask = Image.new("L", (SCR_W * 4, SCR_H * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SCR_W * 4 - 1, SCR_H * 4 - 1], radius=SCR_R * 4, fill=255)
    mask = mask.resize((SCR_W, SCR_H), Image.LANCZOS)
    canvas.paste(screen(name), (sx, sy), mask)

    d = ImageDraw.Draw(canvas)
    f = headline_font()
    lines = headline.split("\n")
    block = LINE_H * len(lines)
    y = (DEV_Y - block) // 2 - 10
    for ln in lines:
        bb = d.textbbox((0, 0), ln, font=f)
        d.text(((W - (bb[2] - bb[0])) // 2 - bb[0], y + (LINE_H - HEAD_SIZE) // 2), ln, font=f, fill=INK)
        y += LINE_H

    os.makedirs(OUT, exist_ok=True)
    out = f"{OUT}/{name}.png"
    canvas.save(out, "PNG")
    print("saved", out, canvas.size, "device", (DEV_X, DEV_Y, BODY_W, BODY_H), "bottom margin", H - DEV_Y - BODY_H)


SLIDES = [
    ("01_home", "home", "The Celebration\nHas Begun"),
    ("02_schedule", "schedule", "Every Moment\nIn Order"),
    ("03_chat", "chat", "Stay Close"),
    ("04_wedding_week", "wedding_week", "Live From\nCancún"),
    ("05_my_experience", "my_experience", "Find Your Way"),
    ("06_my_outfits", "my_outfits", "Dress\nThe Part"),
]

only = sys.argv[1] if len(sys.argv) > 1 else None
for n, bg, hl in SLIDES:
    if only and not n.startswith(only):
        continue
    compose(n, bg, hl)
