"""Product page header, as briefed: full-bleed Brooklyn Bridge couple photo (IMG_9555,
full-res 2048x3072 hero copy), warm slightly soft grade, cream gradient rising from the
bottom ~35%, "Abhi & Alisha" (Playfair italic, ivory, gold ampersand) + gold tracked
date line, centred lower-middle inside the central 60% width. Faces centred, above text.
Also reports where everything sits against Apple's template Art Safe Area."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance

SRC = "screenshots/experiments/product-page/brooklyn_2048x3072.jpg"
OUT = "screenshots/experiments/product-page"
FONTS = "ios-abhi-alisha/Shared/Resources"
IVORY = (252, 248, 240)
GOLD = (194, 162, 76)          # brand gold #C2A24C
GOLD_DEEP = (169, 135, 60)     # brand goldDeep #A9873C (date sits on the cream)
CREAM = (246, 239, 226)
DATE = "CANCÚN · JAN 30 – FEB 3, 2027"
HAIR_TOP, CHIN, PAIR_CX = 1300, 1790, 1110      # source landmarks
APPLE_SAFE = {(5244, 2950): (1921, 660, 3323, 1622), (3840, 1646): (1097, 493, 2743, 1154)}


def font(name, size, weight):
    f = ImageFont.truetype(f"{FONTS}/{name}", size)
    f.set_variation_by_axes([weight])
    return f


def photo(W, H, scale, hair_top_y):
    src = Image.open(SRC).convert("RGB")
    sw, sh = round(src.width * scale), round(src.height * scale)
    assert sw >= W
    img = src.resize((sw, sh), Image.LANCZOS)
    x0 = max(0, min(round(PAIR_CX * scale - W / 2), sw - W))
    y0 = max(0, min(round(HAIR_TOP * scale - hair_top_y), sh - H))
    img = img.crop((x0, y0, x0 + W, y0 + H))
    faces = (round(800 * scale - x0), round(HAIR_TOP * scale - y0),
             round(1420 * scale - x0), round(CHIN * scale - y0))
    r, g, b = img.split()
    r = r.point(lambda v: min(255, int(v * 1.05 + 6)))
    g = g.point(lambda v: min(255, int(v * 1.01 + 3)))
    b = b.point(lambda v: int(v * 0.90 + 4))
    img = Image.merge("RGB", (r, g, b))
    img = ImageEnhance.Color(img).enhance(0.92)
    img = img.point(lambda v: int(12 + v * (243 / 255)))
    glow = img.filter(ImageFilter.GaussianBlur(W / 300)).point(lambda v: min(255, int(v * 1.07)))
    return Image.blend(img, glow, 0.25), faces


def ramp(W, H, start, full, alpha):
    col = Image.new("L", (1, H), 0)
    for y in range(H):
        t = max(0.0, min(1.0, (y / H - start) / (full - start)))
        col.putpixel((0, y), int(alpha * t * t * (3 - 2 * t)))
    return col.resize((W, H))


def tracked(d, cx, base, text, f, fill, tracking):
    ws = [d.textlength(c, font=f, features=["lnum"]) for c in text]
    total = sum(ws) + tracking * (len(text) - 1)
    x = cx - total / 2
    for c, w in zip(text, ws):
        d.text((x, base), c, font=f, fill=fill, anchor="ls", features=["lnum"])
        x += w + tracking
    return total


def inside(box, area):
    return box[0] >= area[0] and box[1] >= area[1] and box[2] <= area[2] and box[3] <= area[3]


def compose(W, H, scale, hair_top, names_size, names_base, date_base, grad, name):
    img, faces = photo(W, H, scale, hair_top)
    img = Image.composite(Image.new("RGB", (W, H), CREAM), img, ramp(W, H, *grad))
    fn = font("PlayfairDisplay-Italic.ttf", names_size, 500)
    fs = font("CormorantGaramond.ttf", round(names_size * 0.25), 650)
    tracking = fs.size * 0.40
    parts = [("Abhi ", IVORY), ("&", GOLD), (" Alisha", IVORY)]
    d = ImageDraw.Draw(img)
    ws = [d.textlength(t, font=fn) for t, _ in parts]
    total = sum(ws)
    nb, db = round(names_base * H), round(date_base * H)

    sh = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(sh)
    x = W / 2 - total / 2
    for (t, _), w in zip(parts, ws):
        sd.text((x, nb), t, font=fn, fill=255, anchor="ls")
        x += w
    sh = sh.filter(ImageFilter.GaussianBlur(names_size * 0.09))
    img = Image.composite(Image.new("RGB", (W, H), (52, 36, 22)), img, sh.point(lambda v: int(v * 0.62)))

    d = ImageDraw.Draw(img)
    x = W / 2 - total / 2
    for (t, c), w in zip(parts, ws):
        d.text((x, nb), t, font=fn, fill=c, anchor="ls")
        x += w
    dw = tracked(d, W / 2, db, DATE, fs, GOLD_DEEP, tracking)
    nbox = d.textbbox((W / 2 - total / 2, nb), "Abhi & Alisha", font=fn, anchor="ls")
    dbox = d.textbbox((W / 2 - dw / 2, db), DATE, font=fs, anchor="ls", features=["lnum"])
    text = (min(nbox[0], dbox[0]), nbox[1], max(nbox[2], dbox[2]), dbox[3])

    c60 = (0.2 * W, 0, 0.8 * W, H)
    safe = APPLE_SAFE[(W, H)]
    assert inside(text, c60) and text[1] > faces[3]
    print(f"{name}: faces {faces}  text {tuple(round(v) for v in text)}  "
          f"text width {(text[2] - text[0]) / W:.0%}  in central 60%: {inside(text, c60)}  "
          f"faces in Apple safe: {inside(faces, safe)}  text in Apple safe: {inside(text, safe)}")
    img.save(f"{OUT}/{name}.png", "PNG")


compose(5244, 2950, scale=2.58, hair_top=300, names_size=330,
        names_base=0.735, date_base=0.815, grad=(0.60, 0.86, 242), name="header_5244x2950")
compose(3840, 1646, scale=1.90, hair_top=70, names_size=200,
        names_base=0.765, date_base=0.865, grad=(0.60, 0.90, 240), name="header_3840x1646")
