"""Generates the SpendWise app icon set (run: python3 tool/make_icon.py).
Needs Pillow. Outputs assets/icon/*.png and platform_icons/{android,ios}."""
import json, os
from PIL import Image, ImageDraw, ImageFilter

BRAND = (20, 80, 60)       # deep green (C.brand)
BRAND_LIGHT = (30, 108, 82)
CREAM = (245, 241, 234)
CLAY = (201, 111, 74)
S = 4096                   # supersample canvas, downscaled for anti-aliasing
OUT = os.path.join(os.path.dirname(__file__), '..')


def rr(d, box, r, fill):
    d.rounded_rectangle([int(v) for v in box], radius=int(r), fill=fill)


SERIF = '/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf'


def glyph(scale=1.0, mono=False):
    """Coin-with-S mark on a transparent S x S canvas, centred, scaled around the centre."""
    from PIL import ImageFont
    k = S / 1024 * scale
    ox = S / 2 - 512 * k
    oy = S / 2 - 512 * k
    P = lambda x, y: (ox + x * k, oy + y * k)

    def disc(d, c, r, fill=None, outline=None, width=0):
        x, y = P(*c)
        d.ellipse([x - r * k, y - r * k, x + r * k, y + r * k], fill=fill, outline=outline, width=int(width * k))

    lay = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    white = (255, 255, 255, 255)
    front, back = (460, 462), (596, 572)
    # clay coin peeking out behind
    disc(d, back, 262, fill=white if mono else CLAY + (255,))
    # gap around the front coin so the two read as separate objects
    gap = Image.new('L', (S, S), 0)
    disc(ImageDraw.Draw(gap), front, 318, fill=255)
    a = lay.getchannel('A'); a.paste(0, mask=gap); lay.putalpha(a)
    d = ImageDraw.Draw(lay)
    # front coin
    disc(d, front, 290, fill=white if mono else CREAM + (255,))
    if not mono:
        disc(d, front, 246, outline=BRAND + (70,), width=9)
    # the "S"
    font = ImageFont.truetype(SERIF, int(500 * k))
    l, t, r, b = font.getbbox('S')
    fx, fy = P(*front)
    pos = (fx - (l + r) / 2, fy - (t + b) / 2)
    if mono:
        m = Image.new('L', (S, S), 0)
        ImageDraw.Draw(m).text(pos, 'S', font=font, fill=255)
        a = lay.getchannel('A'); a.paste(0, mask=m); lay.putalpha(a)
    else:
        d.text(pos, 'S', font=font, fill=BRAND + (255,))
    return lay


def background():
    bg = Image.new('RGBA', (S, S), BRAND + (255,))
    # smooth radial light from the upper-left corner
    g = Image.radial_gradient('L').resize((S, S), Image.BICUBIC)   # 0 centre -> 255 edge
    g = g.point(lambda v: max(0, 255 - int(v * 1.25)))             # bright centre, fades out
    g = g.transform((S, S), Image.AFFINE, (0.6, 0, S * 0.18, 0, 0.6, S * 0.12), Image.BICUBIC)
    light = Image.new('RGBA', (S, S), BRAND_LIGHT + (255,))
    light.putalpha(g)
    bg.alpha_composite(light)
    # concentric rings echo the home hero card
    rings = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    cx, cy = S * 0.94, S * 0.04
    for i in range(1, 5):
        r = S * 0.17 * i
        rd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 30), width=int(S * 0.004))
    bg.alpha_composite(rings)
    return bg


def with_shadow(g):
    sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 110), mask=g.getchannel('A'))
    sh = sh.filter(ImageFilter.GaussianBlur(S * .018))
    sh = Image.merge('RGBA', (*sh.split()[:3], sh.getchannel('A')))
    shifted = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    shifted.alpha_composite(sh, (0, int(S * .014)))
    shifted.alpha_composite(g)
    return shifted


def down(img, n):
    return img.resize((n, n), Image.LANCZOS)


def rounded(img, frac=0.2237):
    n = img.size[0]
    m = Image.new('L', (n * 4, n * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, n * 4 - 1, n * 4 - 1], radius=int(n * 4 * frac), fill=255)
    m = m.resize((n, n), Image.LANCZOS)
    out = img.copy()
    out.putalpha(m)
    return out


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


full = background()
full.alpha_composite(with_shadow(glyph(1.0)))
fg = with_shadow(glyph(0.80))      # adaptive foreground: keep inside the 66% safe zone
mono = glyph(0.80, mono=True)

A = os.path.join(OUT, 'assets', 'icon')
save(down(full, 1024).convert('RGB'), f'{A}/app_icon.png')
save(down(fg, 1024), f'{A}/app_icon_foreground.png')
save(down(mono, 1024), f'{A}/app_icon_monochrome.png')

# ---- manual drop-in copies (use these if you don't want to run flutter_launcher_icons) ----
P = os.path.join(OUT, 'platform_icons')
for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(rounded(down(full, px)), f'{P}/android/res/mipmap-{name}/ic_launcher.png')
for name, px in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
    save(down(fg, px), f'{P}/android/res/mipmap-{name}/ic_launcher_foreground.png')
    save(down(mono, px), f'{P}/android/res/mipmap-{name}/ic_launcher_monochrome.png')
os.makedirs(f'{P}/android/res/mipmap-anydpi-v26', exist_ok=True)
open(f'{P}/android/res/mipmap-anydpi-v26/ic_launcher.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n</adaptive-icon>\n')
os.makedirs(f'{P}/android/res/values', exist_ok=True)
open(f'{P}/android/res/values/ic_launcher_background.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#14503C</color>\n</resources>\n')

ios = [(20, 2, 'iphone'), (20, 3, 'iphone'), (29, 2, 'iphone'), (29, 3, 'iphone'), (40, 2, 'iphone'), (40, 3, 'iphone'),
       (60, 2, 'iphone'), (60, 3, 'iphone'), (20, 1, 'ipad'), (20, 2, 'ipad'), (29, 1, 'ipad'), (29, 2, 'ipad'),
       (40, 1, 'ipad'), (40, 2, 'ipad'), (76, 1, 'ipad'), (76, 2, 'ipad'), (83.5, 2, 'ipad'), (1024, 1, 'ios-marketing')]
images, done = [], set()
for size, scale, idiom in ios:
    px = int(round(size * scale))
    fn = f'Icon-App-{size:g}x{size:g}@{scale}x.png'
    if fn not in done:
        save(down(full, px).convert('RGB'), f'{P}/ios/AppIcon.appiconset/{fn}')
        done.add(fn)
    images.append({'size': f'{size:g}x{size:g}', 'idiom': idiom, 'filename': fn, 'scale': f'{scale}x'})
json.dump({'images': images, 'info': {'version': 1, 'author': 'xcode'}}, open(f'{P}/ios/AppIcon.appiconset/Contents.json', 'w'), indent=2)

# preview sheet (not shipped in the app)
prev = Image.new('RGB', (1500, 560), (236, 232, 224))
x = 40
for label, img in [('iOS', rounded(down(full, 400))), ('Android circle', None), ('Android squircle', None)]:
    if label == 'iOS':
        prev.paste(img.convert('RGB'), (x, 80), img.getchannel('A')); x += 460; continue
    base = down(full, 400) if False else None
    canvas = Image.new('RGBA', (S, S), BRAND + (255,))
    canvas.alpha_composite(background())
    canvas.alpha_composite(fg)
    c = down(canvas, 400)
    m = Image.new('L', (1600, 1600), 0)
    dm = ImageDraw.Draw(m)
    if 'circle' in label: dm.ellipse([0, 0, 1599, 1599], fill=255)
    else: dm.rounded_rectangle([0, 0, 1599, 1599], radius=520, fill=255)
    m = m.resize((400, 400), Image.LANCZOS)
    prev.paste(c.convert('RGB'), (x, 80), m); x += 460
prev.save('/tmp/icon_preview.png')
print('ok')
