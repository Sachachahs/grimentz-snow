"""Génère l'icône de l'application (montagne + flocon, fond anthracite) dans assets/icon/.

Lancé automatiquement par setup_platforms.py si les images manquent. Nécessite Pillow (pip install pillow).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
S = 1024


def main():
    bg = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / S
        d.line([(0, y), (S, y)], fill=(int(24 - 10 * t), int(38 - 21 * t), int(58 - 36 * t), 255))
    d.polygon([(40, 820), (330, 430), (470, 600), (640, 400), (1000, 820)], fill=(48, 82, 128, 255))
    d.polygon([(0, 900), (420, 300), (690, 690), (790, 580), (1024, 900)], fill=(77, 155, 255, 255))
    d.polygon([(420, 300), (338, 418), (392, 398), (436, 446), (478, 392), (512, 428)], fill=(241, 243, 245, 255))
    d.polygon([(790, 580), (752, 628), (782, 620), (808, 646), (830, 614)], fill=(241, 243, 245, 255))
    d.polygon([(0, 880), (300, 820), (620, 860), (1024, 800), (1024, 1024), (0, 1024)], fill=(236, 242, 248, 255))
    d.polygon([(0, 940), (380, 900), (700, 940), (1024, 890), (1024, 1024), (0, 1024)], fill=(205, 222, 238, 255))
    cx, cy, r = 760, 240, 118
    col = (57, 197, 220, 255)
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        d.line([(cx, cy), (cx + r * math.cos(a), cy + r * math.sin(a))], fill=col, width=26)
        bx, by = cx + r * 0.56 * math.cos(a), cy + r * 0.56 * math.sin(a)
        for s in (-1, 1):
            b = a + s * math.pi / 4
            d.line([(bx, by), (bx + 46 * math.cos(b), by + 46 * math.sin(b))], fill=col, width=20)
    d.ellipse([cx - 24, cy - 24, cx + 24, cy + 24], fill=col)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=225, fill=255)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.paste(bg, (0, 0), mask)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "icon_1024.png")
    bg.convert("RGB").save(OUT / "icon_1024_square.png")
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        folder = OUT / "android" / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        img.resize((px, px), Image.LANCZOS).save(folder / "ic_launcher.png")
    print("Icônes générées dans", OUT)


if __name__ == "__main__":
    main()
