import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1284, 2778
INK = (33, 28, 22)
GOLD = (176, 138, 74)
GRAY = (110, 102, 92)
FONT_DIR = "ios-abhi-alisha/WatchShared/Resources"

def font(name, size, weight=None):
    f = ImageFont.truetype(name, size)
    if weight:
        try: f.set_variation_by_axes([weight])
        except Exception: pass
    return f

PLAYFAIR_I = f"{FONT_DIR}/PlayfairDisplay-Italic.ttf"
PLAYFAIR_R = f"{FONT_DIR}/PlayfairDisplay.ttf"
CORMORANT = f"{FONT_DIR}/CormorantGaramond.ttf"

def cream_at(im, x, y):
    r, g, b = im.getpixel((x, y))[:3]
    return (r, g, b)

def tracked_text(d, xy, text, f, fill, tracking):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        w = d.textbbox((0, 0), ch, font=f)[2]
        x += w + tracking

# ---------- screen patches (source 1284x2778 coords) ----------
def patch_flat(im, box, color=None):
    x0, y0, x1, y1 = box
    c = color or cream_at(im, x0 - 40, (y0 + y1) // 2)
    ImageDraw.Draw(im).rectangle(box, fill=c)

def sample_gold(im, box):
    """Average the gold letter pixels in a strip so redraws match the app."""
    px = []
    for y in range(box[1], box[3], 2):
        for x in range(box[0], box[2], 2):
            r, g, b = im.getpixel((x, y))[:3]
            if r > 130 and r - b > 35:
                px.append((r, g, b))
    if not px:
        return GOLD
    n = len(px)
    return (sum(p[0] for p in px) // n, sum(p[1] for p in px) // n, sum(p[2] for p in px) // n)

def redraw_eyebrow(im, x, y, text, size=32, tracking=15, color=None):
    d = ImageDraw.Draw(im)
    tracked_text(d, (x, y), text, font(CORMORANT, size), color or GOLD, tracking)

def draw_title(im, xy, text, target_w, color=INK):
    """Redraw an app section title in Playfair italic, sized to the original ink width."""
    d = ImageDraw.Draw(im)
    size = 150
    f = font("/tmp/PlayfairItalic-VF.ttf", size, weight=500)
    w = d.textbbox((0, 0), text, font=f)[2]
    size = max(20, int(size * target_w / w))
    f = font("/tmp/PlayfairItalic-VF.ttf", size, weight=500)
    bb = d.textbbox((0, 0), text, font=f)
    d.text((xy[0] - bb[0], xy[1] - bb[1]), text, font=f, fill=color)

def patch_screen(name, im):
    """Remove the baked deck headline from the app screen. Returns nothing."""
    if name == "01_home":
        return  # "Welcome to Cancún" over the hero photo reads as app content
    c = cream_at(im, 640, 620)
    if name == "02_schedule":
        patch_flat(im, (330, 235, 1000, 415), c)          # "Never Miss"
        gold = sample_gold(im, (37, 312, 340, 378))       # surviving letters
        patch_flat(im, (25, 310, 660, 392), c)            # eyebrow strip
        patch_flat(im, (25, 384, 650, 578), c)            # title + "a Mo" remnant
        patch_flat(im, (585, 398, 1000, 492), c)          # "a Moment" tail
        redraw_eyebrow(im, 37, 318, "THE CELEBRATIONS", color=gold)
        draw_title(im, (34, 424), "Schedule", 536)
    elif name == "03_chat":
        patch_flat(im, (340, 235, 990, 415), c)           # "Stay Close"
        gold = sample_gold(im, (37, 312, 340, 378))
        patch_flat(im, (25, 310, 660, 392), c)            # eyebrow strip
        patch_flat(im, (25, 378, 380, 578), c)            # title + "t." remnant
        patch_flat(im, (345, 380, 1045, 492), c)          # "to the Couple"
        redraw_eyebrow(im, 37, 318, "THE WEDDING TAB", color=gold)
        draw_title(im, (34, 424), "Chat", 294)
    elif name == "04_wedding_week":
        patch_flat(im, (330, 210, 915, 580), c)           # whole baked-headline zone
        draw_title(im, (34, 424), "Gallery", 444)
    elif name == "06_my_outfits":
        patch_flat(im, (432, 235, 905, 492), c)           # "Dress the Part"
    elif name == "05_my_experience":
        cream = cream_at(im, 1150, 935)                   # true app cream, not card white
        patch_flat(im, (0, 0, 1284, 898), cream)          # whole top zone (cards redrawn later)
        strip = Image.open("screenshots/iphone/en/03_chat.png").convert("RGB").crop((0, 0, 1284, 92))
        im.paste(strip, (0, 0))                           # clean status bar from the Chat capture

# ---------- 05 card redraw (screen coords, 950 x 2056) ----------
def rounded_card(d, box, r, fill, outline):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=2)

def gold_circle(d, cx, cy, r):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=GOLD, width=3)

def draw_lock_card(d, x, y, w, h, fill, border):
    rounded_card(d, (x, y, x + w, y + h), 24, fill, border)
    cx, cy = x + 92, y + h // 2
    gold_circle(d, cx, cy, 44)
    # phone glyph
    d.rounded_rectangle([cx - 13, cy - 24, cx + 13, cy + 24], radius=7, outline=GOLD, width=3)
    d.line([cx - 5, cy + 15, cx + 5, cy + 15], fill=GOLD, width=3)
    f_title = font(PLAYFAIR_R, 44)
    f_body = font(CORMORANT, 42)
    tx = x + 168
    d.text((tx, y + 34), "Lock Screen", font=f_title, fill=INK)
    for i, ln in enumerate(["Each celebration appears", "on your Lock Screen an hour", "before it begins."]):
        d.text((tx, y + 96 + i * 44), ln, font=f_body, fill=GRAY)
    # ON pill
    pw, ph = 118, 52
    px, py = x + w - pw - 28, y + 30
    d.rounded_rectangle([px, py, px + pw, py + ph], radius=ph // 2, fill=(240, 231, 208))
    d.line([px + 24, py + 27, px + 31, py + 34], fill=GOLD, width=4)
    d.line([px + 31, py + 34, px + 43, py + 18], fill=GOLD, width=4)
    d.text((px + 52, py + 7), "ON", font=font(CORMORANT, 36), fill=GOLD)

def draw_questions_card(d, x, y, w, h, fill, border):
    rounded_card(d, (x, y, x + w, y + h), 24, fill, border)
    cx, cy = x + 92, y + h // 2
    gold_circle(d, cx, cy, 44)
    d.text((cx, cy - 32), "?", font=font(CORMORANT, 64), fill=GOLD, anchor="ma")
    f_title = font(PLAYFAIR_R, 44)
    f_body = font(CORMORANT, 42)
    tx = x + 168
    d.text((tx, y + 44), "Questions & Answers", font=f_title, fill=INK)
    d.text((tx, y + 108), "32 answers from Abhi & Alisha,", font=f_body, fill=GRAY)
    d.text((tx, y + 152), "all searchable.", font=f_body, fill=GRAY)
    d.text((x + w - 74, y + h // 2 - 40), "›", font=font(CORMORANT, 72), fill=(190, 178, 158))

# ---------- device frame ----------
SCR_W = 950
SCR_H = round(SCR_W * H / W)  # 2055
BEZEL, RIM = 22, 8
BODY_R, SCR_R = 156, 130
BODY_W, BODY_H = SCR_W + 2 * (BEZEL + RIM), SCR_H + 2 * (BEZEL + RIM)
DEV_X, DEV_Y = (W - BODY_W) // 2, 585

def titanium(draw, box, r):
    x0, y0, x1, y1 = box
    grad = Image.new("RGB", (1, 256))
    for i in range(256):
        t = i / 255
        grad.putpixel((0, i), (int(245 - 55 * t), int(245 - 55 * t), int(247 - 52 * t)))
    grad = grad.resize((x1 - x0, y1 - y0))
    mask = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, x1 - x0 - 1, y1 - y0 - 1], radius=r, fill=255)
    draw._image.paste(grad, (x0, y0), mask)

def notch_cover(screen):
    """Cover the baked status-bar notch with one clean shape (screen coords)."""
    d = ImageDraw.Draw(screen)
    d.rounded_rectangle([322, -30, 630, 74], radius=38, fill=(12, 12, 14))

def compose(name, headline, bg_path, shot_path, out_path):
    canvas = Image.new("RGB", (W, H), (244, 236, 221))
    bg = Image.open(bg_path).convert("RGB")
    s = H / bg.height
    bg = bg.resize((round(bg.width * s), H), Image.LANCZOS)
    x0 = (bg.width - W) // 2
    canvas.paste(bg.crop((x0, 0, x0 + W, H)).filter(ImageFilter.GaussianBlur(2.2)), (0, 0))

    src = Image.open(shot_path).convert("RGB")
    patch_screen(name, src)
    screen = src.resize((SCR_W, SCR_H), Image.LANCZOS)
    notch_cover(screen)
    if name == "05_my_experience":
        d = ImageDraw.Draw(screen)
        draw_lock_card(d, 36, 128, 878, 250, (253, 250, 243), (222, 205, 170))
        draw_questions_card(d, 36, 408, 878, 234, (253, 250, 243), (222, 205, 170))

    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [DEV_X, DEV_Y + 30, DEV_X + BODY_W, DEV_Y + BODY_H + 30],
        radius=BODY_R, fill=(60, 45, 25, 85))
    sh = sh.filter(ImageFilter.GaussianBlur(55))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), sh).convert("RGB")
    d = ImageDraw.Draw(canvas)

    for bx, by, bh in [(DEV_X - 9, DEV_Y + 300, 64), (DEV_X - 9, DEV_Y + 440, 118),
                       (DEV_X - 9, DEV_Y + 596, 118), (DEV_X + BODY_W - 1, DEV_Y + 500, 178)]:
        d.rounded_rectangle([bx, by, bx + 10, by + bh], radius=5, fill=(176, 176, 184))

    titanium(d, (DEV_X, DEV_Y, DEV_X + BODY_W, DEV_Y + BODY_H), BODY_R)
    d.rounded_rectangle([DEV_X, DEV_Y, DEV_X + BODY_W, DEV_Y + BODY_H],
                        radius=BODY_R, outline=(120, 120, 128), width=2)
    d.rounded_rectangle((DEV_X + RIM, DEV_Y + RIM, DEV_X + BODY_W - RIM, DEV_Y + BODY_H - RIM),
                        radius=BODY_R - RIM - 2, fill=(12, 12, 14))

    sx, sy = DEV_X + BEZEL + RIM, DEV_Y + BEZEL + RIM
    smask = Image.new("L", (SCR_W, SCR_H), 0)
    ImageDraw.Draw(smask).rounded_rectangle([0, 0, SCR_W - 1, SCR_H - 1], radius=SCR_R, fill=255)
    canvas.paste(screen, (sx, sy), smask)

    f = font("/tmp/PlayfairItalic-VF.ttf", 116, weight=600)
    d = ImageDraw.Draw(canvas)
    lines = headline.split("\n")
    lh = 142
    y = 128 + (420 - 128 - lh * len(lines)) // 2
    for ln in lines:
        bb = d.textbbox((0, 0), ln, font=f)
        d.text(((W - (bb[2] - bb[0])) // 2 - bb[0], y), ln, font=f, fill=INK)
        y += lh

    canvas.save(out_path, "PNG")
    print("saved", out_path)

SLIDES = [
    ("01_home", "The Celebration\nHas Begun", "home"),
    ("02_schedule", "Every Moment\nIn Order", "schedule"),
    ("03_chat", "Stay Close", "chat"),
    ("04_wedding_week", "Live From\nCancún", "wedding_week"),
    ("05_my_experience", "Find Your Way", "my_experience"),
    ("06_my_outfits", "Dress\nThe Part", "my_outfits"),
]

os.makedirs("screenshots/iphone/en-framed", exist_ok=True)
import sys
only = sys.argv[1] if len(sys.argv) > 1 else None
for name, headline, bg in SLIDES:
    if only and not name.startswith(only):
        continue
    compose(name, headline, f"screenshots/backgrounds/{bg}.png",
            f"screenshots/iphone/en/{name}.png",
            f"screenshots/iphone/en-framed/{name}.png")
