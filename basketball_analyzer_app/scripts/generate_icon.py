"""Generate BASANS app icon as ICO and PNG."""
from PIL import Image, ImageDraw, ImageFont
import math
import os

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'windows', 'runner', 'resources')
ASSETS_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets')

def draw_icon(size=1024):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = int(size * 0.03)
    r = int(size * 0.19)

    # Rounded square background — orange gradient approximation
    draw.rounded_rectangle(
        [pad, pad, size - pad, size - pad],
        radius=int(size * 0.18),
        fill=(232, 67, 10, 255),
    )
    # Inner highlight
    draw.rounded_rectangle(
        [pad + 4, pad + 4, size - pad - 4, size - pad - 4],
        radius=int(size * 0.17),
        fill=(255, 107, 53, 255),
    )

    # Basketball
    cx, cy = int(size * 0.5), int(size * 0.41)
    br = int(size * 0.235)
    # Ball body
    draw.ellipse([cx - br, cy - br, cx + br, cy + br], fill=(255, 140, 66, 255))
    # Ball outline
    draw.ellipse([cx - br, cy - br, cx + br, cy + br], outline=(196, 48, 0, 200), width=max(2, size // 256))

    # Seam lines
    lw = max(2, size // 300)
    # Vertical
    draw.line([(cx, cy - br + 4), (cx, cy + br - 4)], fill=(196, 48, 0, 150), width=lw)
    # Horizontal
    draw.line([(cx - br + 4, cy), (cx + br - 4, cy)], fill=(196, 48, 0, 150), width=lw)

    # Trajectory arc (white dashed)
    arc_pts = []
    for i in range(30):
        t = i / 29
        x = int(cx - br * 0.8 + t * br * 1.6)
        y = int(cy + br * 0.4 - br * 0.9 * math.sin(math.pi * t))
        arc_pts.append((x, y))
    if len(arc_pts) > 1:
        draw.line(arc_pts, fill=(255, 255, 255, 200), width=max(2, size // 200))

    # Small hoop on right side
    hx = int(cx + br * 0.6)
    hy = int(cy + br * 0.5)
    hr = int(size * 0.06)
    draw.arc([hx - hr, hy - hr // 2, hx + hr, hy + hr // 2], 0, 360, fill=(255, 255, 255, 180), width=max(2, size // 256))

    # "BASANS" text
    text_y = int(size * 0.75)
    try:
        font = ImageFont.truetype("arialbd.ttf", int(size * 0.14))
    except:
        try:
            font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", int(size * 0.14))
        except:
            font = ImageFont.load_default()

    text = "BASANS"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    tx = (size - tw) // 2
    draw.text((tx, text_y), text, fill=(255, 255, 255, 255), font=font)

    # Subtitle
    try:
        sfont = ImageFont.truetype("arial.ttf", int(size * 0.035))
    except:
        try:
            sfont = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", int(size * 0.035))
        except:
            sfont = ImageFont.load_default()

    sub = "SHOT ANALYZER"
    bbox2 = draw.textbbox((0, 0), sub, font=sfont)
    sw = bbox2[2] - bbox2[0]
    draw.text(((size - sw) // 2, int(size * 0.88)), sub, fill=(255, 255, 255, 200), font=sfont)

    return img


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(ASSETS_DIR, exist_ok=True)

    img = draw_icon(1024)

    # Save PNG for assets
    png_path = os.path.join(ASSETS_DIR, 'app_icon.png')
    img.save(png_path, 'PNG')
    print(f"Saved: {png_path}")

    # Generate ICO with multiple sizes
    ico_path = os.path.join(OUTPUT_DIR, 'app_icon.ico')
    sizes = [256, 128, 64, 48, 32, 16]
    icons = [img.resize((s, s), Image.LANCZOS) for s in sizes]
    icons[0].save(ico_path, format='ICO', sizes=[(s, s) for s in sizes])
    print(f"Saved: {ico_path}")

    # Also save a 512px PNG for Flutter
    flutter_icon = os.path.join(ASSETS_DIR, 'icon.png')
    img.resize((512, 512), Image.LANCZOS).save(flutter_icon, 'PNG')
    print(f"Saved: {flutter_icon}")


if __name__ == '__main__':
    main()
