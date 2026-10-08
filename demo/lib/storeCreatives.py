# Renders App Store creative stills: 21:9 header and 3:2 search.
# Visual system:
# - Header: Pure atmospheric room glow (amber + 4 style inks) for seamless iOS navigation blending
# - Search: Minimalist login identity ("Reframe your mind.", 4 dots, 4 style chips)
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
STORE = ROOT / "store"
MARK = STORE / ".tools" / "angles-mark.png"

PAPER = (10, 9, 8)

# Dark-mode inks from CardStyleAppearance (HomePalette.swift).
STYLES = [
    ("Stoic", (115, 166, 255)),
    ("Optimistic", (255, 158, 56)),
    ("Humorous", (89, 209, 115)),
    ("Tough Love", (255, 107, 97)),
]

FONT_REGULAR = "/Library/Fonts/SF-Pro.ttf"
FONT_SEMIBOLD = "/Library/Fonts/SF-Pro-Rounded-Semibold.otf"


def font_reg(size):
    try:
        return ImageFont.truetype(FONT_REGULAR, size)
    except Exception:
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)


def font_semi(size):
    try:
        return ImageFont.truetype(FONT_SEMIBOLD, size)
    except Exception:
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)


def ui_font(size):
    try:
        return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size)
    except Exception:
        return font_reg(size)


def radial_bloom(canvas, cx, cy, radius, color, strength=0.55):
    mask = Image.new("L", canvas.size, 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(max(8, int(radius * 0.48))))
    tint = Image.new("RGB", canvas.size, color)
    faded = mask.point(lambda p: int(p * strength))
    canvas.paste(Image.composite(tint, canvas, faded), (0, 0))
    return canvas


def login_atmosphere(canvas):
    """Four corner style blooms — matches LoginAtmosphere in LoginView.swift."""
    w, h = canvas.size
    span = min(w, h)
    specs = [
        (STYLES[0][1], 0.92, 0.08, 0.12, 0.20),
        (STYLES[1][1], 0.86, 0.92, 0.16, 0.18),
        (STYLES[2][1], 0.78, 0.12, 0.78, 0.16),
        (STYLES[3][1], 0.88, 0.90, 0.82, 0.18),
    ]
    for color, size_mul, fx, fy, strength in specs:
        canvas = radial_bloom(
            canvas,
            int(w * fx),
            int(h * fy),
            int(span * size_mul * 0.5),
            color,
            strength,
        )
    return canvas


def draw_angles_motif(canvas, cx, cy, arm, stroke=3):
    """Four arms from center — same thought, four viewing angles."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i, (_, ink) in enumerate(STYLES):
        angle = math.radians(45 + i * 90)
        ex = cx + arm * math.cos(angle)
        ey = cy + arm * math.sin(angle)
        d.line([(cx, cy), (ex, ey)], fill=(*ink, 72), width=stroke)
        dot = 28
        d.ellipse([ex - dot, ey - dot, ex + dot, ey + dot], fill=(*ink, 220))
    d.ellipse([cx - 18, cy - 18, cx + 18, cy + 18], fill=(255, 255, 255, 36))
    return Image.alpha_composite(canvas.convert("RGBA"), layer).convert("RGB")


def cover_crop(img, tw, th, vertical_bias=0.38):
    """Crop at full resolution, then downscale once (keeps architectural detail sharp)."""
    w, h = img.size
    target_ar = tw / th
    src_ar = w / h
    if src_ar > target_ar:
        crop_h = h
        crop_w = int(h * target_ar)
    else:
        crop_w = w
        crop_h = int(w / target_ar)
    left = (w - crop_w) // 2
    top = int((h - crop_h) * vertical_bias)
    top = max(0, min(top, h - crop_h))
    cropped = img.crop((left, top, left + crop_w, top + crop_h))
    out = cropped.resize((tw, th), Image.Resampling.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=1.1, percent=115, threshold=3))


def render_header():
    """Renders 21:9 header as a center crop of search-3x2.png (same creative)."""
    w, h = 3840, 1646
    search_path = STORE / "search-3x2.png"
    if not search_path.exists():
        render_search()
    search = Image.open(search_path).convert("RGB")
    top = int((search.height - h) * 0.34)
    top = max(0, min(top, search.height - h))
    img = search.crop((0, top, w, top + h))
    path = STORE / "header-21x9.png"
    img.save(path, "PNG", optimize=True, compress_level=1)
    img.resize((960, 411), Image.Resampling.LANCZOS).save(STORE / "header-21x9-preview.png")
    print(f"header {path} {img.size} {path.stat().st_size}")


def render_preview_poster(width=886, height=1920):
    """App Preview poster still: mark, warm glow, four style dots (886×1920)."""
    if not MARK.exists():
        raise FileNotFoundError(f"missing app mark at {MARK}")

    img = Image.new("RGB", (width, height), PAPER)
    img = login_atmosphere(img)

    cx, cy = width // 2, int(height * 0.42)
    span = min(width, height)
    img = radial_bloom(img, cx, cy, int(span * 0.42), (255, 140, 48), 0.42)

    icon_px = int(width * 0.34)
    icon = Image.open(MARK).convert("RGBA").resize((icon_px, icon_px), Image.Resampling.LANCZOS)
    radius = max(28, int(icon_px * 0.22))
    ix = cx - icon_px // 2
    iy = cy - icon_px // 2 - int(height * 0.04)
    paste_rounded(img, icon, (ix, iy), radius)

    d = ImageDraw.Draw(img)
    dot_r = max(5, int(width * 0.012))
    gap = max(10, int(width * 0.022))
    total_w = 4 * (2 * dot_r) + 3 * gap
    start_x = (width - total_w) // 2
    dot_y = iy + icon_px + int(height * 0.045)

    for i, (_, c) in enumerate(STYLES):
        x = start_x + i * (2 * dot_r + gap)
        d.ellipse([x, dot_y, x + 2 * dot_r, dot_y + 2 * dot_r], fill=c)

    path = STORE / "preview-poster.png"
    img.save(path, "PNG", optimize=True)
    img.save(STORE / "preview-thumbnail.png", "PNG", optimize=True)
    print(f"preview-poster {path} {img.size} {path.stat().st_size}")
    return path


def render_search():
    """Renders 3:2 search still — same identity as LoginView (no icon, no wordmark)."""
    w, h = 3840, 2560
    img = Image.new("RGB", (w, h), PAPER)
    img = login_atmosphere(img)

    cy = int(h * 0.46)
    d = ImageDraw.Draw(img)

    dot_r = 34
    gap = 72
    total_w = 4 * (2 * dot_r) + 3 * gap
    start_x = (w - total_w) // 2
    dot_y = cy - 80

    for i, (_, c) in enumerate(STYLES):
        x = start_x + i * (2 * dot_r + gap)
        d.ellipse([x, dot_y, x + 2 * dot_r, dot_y + 2 * dot_r], fill=c)

    f_head = font_semi(252)
    f_sub = font_reg(118)

    h1 = "Reframe your mind."
    w1 = d.textlength(h1, font=f_head)
    d.text(((w - w1) / 2, dot_y + 130), h1, font=f_head, fill=(255, 255, 255))

    sub = "Four angles on the same situation."
    w_sub = d.textlength(sub, font=f_sub)
    d.text(((w - w_sub) / 2, dot_y + 420), sub, font=f_sub, fill=(168, 168, 176))

    path = STORE / "search-3x2.png"
    img.save(path, "PNG", optimize=True)
    img.resize((768, 512), Image.Resampling.LANCZOS).save(STORE / "search-3x2-preview.png")
    print(f"search {path} {img.size} {path.stat().st_size}")


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255
    )
    return mask


def paste_rounded(canvas, img, xy, radius):
    canvas.paste(img, xy, rounded_mask(img.size, radius))


def draw_get_pill(d, right_x, y, pw=210, ph=78, fill=(56, 56, 58, 235)):
    x0 = right_x - pw
    d.rounded_rectangle([x0, y, x0 + pw, y + ph], radius=ph // 2, fill=fill)
    fnt = ui_font(44)
    tw = d.textlength("GET", font=fnt)
    d.text((x0 + (pw - tw) / 2, y + 15), "GET", font=fnt, fill=(10, 132, 255))


def draw_result_row(canvas, y, dimmed=False):
    d = ImageDraw.Draw(canvas, "RGBA")
    alpha = 140 if dimmed else 255
    icon = Image.open(MARK).convert("RGBA").resize((168, 168), Image.Resampling.LANCZOS)
    if dimmed:
        ghost = Image.new("RGBA", (168, 168), (36, 36, 38, 255))
        icon = ghost
    paste_rounded(canvas, icon, (48, y), 38)
    if dimmed:
        d.rounded_rectangle([252, y + 24, 872, y + 62], radius=19, fill=(44, 44, 46, alpha))
        d.rounded_rectangle([252, y + 92, 682, y + 124], radius=16, fill=(40, 40, 42, alpha))
        d.rounded_rectangle(
            [canvas.size[0] - 258, y + 44, canvas.size[0] - 48, y + 122],
            radius=39,
            fill=(44, 44, 46, alpha),
        )
        return
    d.text((252, y + 18), "Angles: Reframe Thoughts", font=ui_font(46), fill=(255, 255, 255))
    d.text(
        (252, y + 84),
        "See a hard thought differently",
        font=ui_font(40),
        fill=(160, 160, 165),
    )
    draw_get_pill(d, canvas.size[0] - 48, y + 44)


def render_search_mock():
    W, H = 1290, 2796
    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(canvas, "RGBA")

    d.text((60, 42), "9:41", font=ui_font(42), fill=(255, 255, 255))
    fx, fy, fh = 48, 150, 96
    d.rounded_rectangle([fx, fy, W - 48, fy + fh], radius=48, fill=(32, 32, 34))
    d.text((fx + 44, fy + 24), "Angles", font=ui_font(44), fill=(150, 150, 155))

    draw_result_row(canvas, 300)

    ax, ay = 48, 560
    aw = W - 96
    asset = Image.open(STORE / "search-3x2.png").convert("RGBA")
    ah = int(aw * asset.size[1] / asset.size[0])
    asset = asset.resize((aw, ah), Image.Resampling.LANCZOS)
    paste_rounded(canvas, asset, (ax, ay), 28)

    draw_result_row(canvas, ay + ah + 90, dimmed=True)

    canvas.save(STORE / "search-3x2-mock.png", "PNG", optimize=True)
    canvas.resize((430, 932), Image.Resampling.LANCZOS).save(
        STORE / "search-3x2-mock-phone.png"
    )
    print(f"mock {STORE / 'search-3x2-mock.png'}")


def render_header_mock():
    W, H = 1290, 1900
    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    asset = Image.open(STORE / "header-21x9.png").convert("RGBA")
    ah = int(W * asset.size[1] / asset.size[0])
    asset = asset.resize((W, ah), Image.Resampling.LANCZOS)
    canvas.paste(asset, (0, 0), asset)

    d = ImageDraw.Draw(canvas, "RGBA")
    d.text((60, 42), "9:41", font=ui_font(42), fill=(255, 255, 255))

    # App row overlapping the header bottom; Get chip at the right edge
    iy = ah - 96
    icon = Image.open(MARK).convert("RGBA").resize((168, 168), Image.Resampling.LANCZOS)
    paste_rounded(canvas, icon, (48, iy), 38)
    d.text((252, iy + 18), "Angles: Reframe Thoughts", font=ui_font(46), fill=(255, 255, 255))
    d.text(
        (252, iy + 84),
        "See a hard thought differently",
        font=ui_font(40),
        fill=(190, 190, 195),
    )
    draw_get_pill(d, W - 48, iy + 44)

    sy = ah + 260
    for i in range(3):
        sx = 48 + i * (360 + 24)
        d.rounded_rectangle([sx, sy, sx + 360, sy + 780], radius=24, fill=(20, 20, 22))

    canvas.save(STORE / "header-21x9-mock.png", "PNG", optimize=True)
    canvas.resize((430, 633), Image.Resampling.LANCZOS).save(
        STORE / "header-21x9-mock-phone.png"
    )
    print(f"mock {STORE / 'header-21x9-mock.png'}")


if __name__ == "__main__":
    STORE.mkdir(parents=True, exist_ok=True)
    if "--preview-poster" in sys.argv:
        render_preview_poster()
        raise SystemExit(0)
    render_search()
    render_header()
    if MARK.exists():
        render_search_mock()
        render_header_mock()
