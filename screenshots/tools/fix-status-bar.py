import sys
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont

def retouch(path, thr):
    im = Image.open(path).convert("RGB")
    a = np.array(im)
    ty0, ty1, tx0, tx1 = 28, 146, 50, 404
    region = a[ty0:ty1, tx0:tx1]
    bg = np.median(a[ty0:ty1, 795:850].reshape(-1, 3), axis=0)
    dist = np.linalg.norm(region.astype(int) - bg.astype(int), axis=2)
    mask = (dist > thr).astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=2)
    inpainted = cv2.inpaint(region, mask, 5, cv2.INPAINT_TELEA)
    a[ty0:ty1, tx0:tx1] = inpainted
    out = Image.fromarray(a)
    bright = bg.mean()
    ink = (28, 28, 30) if bright > 127 else (245, 245, 245)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 46)
    ImageDraw.Draw(out).text((92, 52), "9:41", font=font, fill=ink)
    out.save(path)
    print("done", path)

args = sys.argv[1:]
thrs = {"01-abhi-and-alisha.png": 60, "09-where-is-the-ceremony.png": 45}
for p in args:
    import os
    retouch(p, thrs.get(os.path.basename(p), 30))
