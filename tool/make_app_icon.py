"""Renders the Sotto app icon for every desktop target.

The glyph is CueMark (lib/core/design/icons.dart): an electric cue dot beside
three script bars, on a graphite tile from the Stage palette.

    python tool/make_app_icon.py

Writes:
  assets/branding/sotto_icon.svg                    vector master
  assets/branding/sotto_icon_1024.png               full-bleed tile (stores, docs)
  assets/branding/sotto_icon_256.png                full-bleed tile (Linux)
  macos/Runner/Assets.xcassets/AppIcon.appiconset/  macOS sizes (Apple grid, with shadow)
  windows/runner/resources/app_icon.ico             16-256 px
Requires Pillow.
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent

# Stage palette (lib/core/design/tokens.dart).
GRAPHITE_850 = (0x17, 0x1A, 0x1F)
GRAPHITE_950 = (0x0B, 0x0C, 0x0F)
INK = (0xEE, 0xF1, 0xF6)
ELECTRIC_300 = (0x6E, 0xA8, 0xFF)
ELECTRIC_500 = (0x2F, 0x6B, 0xFF)

SS = 4  # supersampling factor


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _vertical_gradient(size, top, bottom):
    col = Image.new("RGB", (1, size))
    for y in range(size):
        col.putpixel((0, y), _lerp(top, bottom, y / (size - 1)))
    return col.resize((size, size))


def _radial(size, center, radius, color, alpha):
    """Soft radial wash, `alpha` at the center fading to 0 at `radius`."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    steps = 48
    for i in range(steps):
        t = i / steps
        r = radius * (1 - t)
        a = round(alpha * 255 * (t**1.6))
        d.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r], fill=a)
    mask = mask.filter(ImageFilter.GaussianBlur(radius / 10))
    layer = Image.new("RGBA", (size, size), color + (0,))
    layer.putalpha(mask)
    return layer


def _tile(px, radius_frac=0.2237, small=False):
    """A rounded graphite tile with the cue mark, `px` square, RGBA."""
    s = px * SS
    radius = round(s * radius_frac)

    shape = Image.new("L", (s, s), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, s - 1, s - 1], radius, fill=255)

    img = _vertical_gradient(s, GRAPHITE_850, GRAPHITE_950).convert("RGBA")

    # Glyph geometry: CueMark's 32-unit viewBox, glyph spans x 3..29, y 6..26.
    unit = s * (0.66 if small else 0.58) / 26
    ox = s / 2 - 16 * unit
    oy = s / 2 - 16 * unit

    def box(x, y, w, h):
        return [ox + x * unit, oy + y * unit, ox + (x + w) * unit, oy + (y + h) * unit]

    dot_c = (ox + 6 * unit, oy + 16 * unit)

    if not small:
        # A low stage light from the cue, so the tile isn't flat graphite.
        img.alpha_composite(_radial(s, dot_c, s * 0.62, ELECTRIC_500, 0.20))

    glyph = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    g = ImageDraw.Draw(glyph)
    bar_r = 2 * unit
    g.rounded_rectangle(box(12, 6, 10, 4), bar_r, fill=INK + (round(255 * 0.34),))
    g.rounded_rectangle(box(12, 14, 17, 4), bar_r, fill=INK + (255,))
    g.rounded_rectangle(box(12, 22, 13, 4), bar_r, fill=INK + (round(255 * 0.6),))

    if not small:
        glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        r = 3 * unit * 2.1
        ImageDraw.Draw(glow).ellipse(
            [dot_c[0] - r, dot_c[1] - r, dot_c[0] + r, dot_c[1] + r], fill=ELECTRIC_500 + (150,)
        )
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(3 * unit * 1.4)))

    r = 3 * unit
    dot = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(dot).ellipse([dot_c[0] - r, dot_c[1] - r, dot_c[0] + r, dot_c[1] + r], fill=ELECTRIC_500 + (255,))
    if not small:
        # A touch of highlight on the upper half of the dot.
        hl = Image.new("L", (s, s), 0)
        hr = r * 0.62
        hc = (dot_c[0] - r * 0.22, dot_c[1] - r * 0.28)
        ImageDraw.Draw(hl).ellipse([hc[0] - hr, hc[1] - hr, hc[0] + hr, hc[1] + hr], fill=110)
        hl = ImageChops.multiply(hl.filter(ImageFilter.GaussianBlur(r * 0.35)), dot.getchannel("A"))
        top = Image.new("RGBA", (s, s), ELECTRIC_300 + (0,))
        top.putalpha(hl)
        dot.alpha_composite(top)
    glyph.alpha_composite(dot)
    img.alpha_composite(glyph)

    # Hairline rim: light at the top edge, fading out toward the bottom.
    rim = Image.new("L", (s, s), 0)
    w = max(SS, round(s * 0.004))
    ImageDraw.Draw(rim).rounded_rectangle([0, 0, s - 1, s - 1], radius, outline=255, width=w)
    fade = _vertical_gradient(s, (70, 70, 70), (12, 12, 12)).convert("L")
    rim = ImageChops.multiply(rim, fade)
    edge = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    edge.putalpha(rim)
    img.alpha_composite(edge)

    img.putalpha(ImageChops.multiply(img.getchannel("A"), shape))
    # Box filtering avoids Lanczos ringing (dark halos) at small sizes.
    return img.resize((px, px), Image.BOX if px <= 48 else Image.LANCZOS)


def full_bleed(px):
    """Windows / Linux: the tile nearly fills the canvas."""
    small = px <= 32
    pad = 0 if px <= 32 else round(px * 0.03)
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    inner = px - 2 * pad
    canvas.alpha_composite(_tile(inner, radius_frac=0.2 if not small else 0.18, small=small), (pad, pad))
    return canvas


def macos(px):
    """Apple's grid: an 824/1024 body centred on the canvas, with a soft drop shadow."""
    small = px <= 32
    body = round(px * 824 / 1024)
    off = (px - body) // 2
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    if px >= 64:
        sh = Image.new("L", (px, px), 0)
        dy = round(px * 10 / 1024)
        ImageDraw.Draw(sh).rounded_rectangle(
            [off, off + dy, off + body, off + body + dy], round(body * 0.2237), fill=90
        )
        sh = sh.filter(ImageFilter.GaussianBlur(px * 12 / 1024))
        shadow = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        shadow.putalpha(sh)
        canvas.alpha_composite(shadow)
    canvas.alpha_composite(_tile(body, small=small), (off, off))
    return canvas


SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#171A1F"/>
      <stop offset="1" stop-color="#0B0C0F"/>
    </linearGradient>
    <radialGradient id="light" cx="{dx}" cy="512" r="635" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2F6BFF" stop-opacity="0.2"/>
      <stop offset="1" stop-color="#2F6BFF" stop-opacity="0"/>
    </radialGradient>
    <filter id="glow" x="-1" y="-1" width="3" height="3">
      <feGaussianBlur stdDeviation="{blur}"/>
    </filter>
    <clipPath id="tile"><rect width="1024" height="1024" rx="205"/></clipPath>
  </defs>
  <g clip-path="url(#tile)">
    <rect width="1024" height="1024" fill="url(#ground)"/>
    <rect width="1024" height="1024" fill="url(#light)"/>
    <circle cx="{dx}" cy="512" r="{glow_r}" fill="#2F6BFF" fill-opacity="0.6" filter="url(#glow)"/>
    <g transform="translate({ox} {ox}) scale({u})">
      <rect x="12" y="6" width="10" height="4" rx="2" fill="#EEF1F6" fill-opacity="0.34"/>
      <rect x="12" y="14" width="17" height="4" rx="2" fill="#EEF1F6"/>
      <rect x="12" y="22" width="13" height="4" rx="2" fill="#EEF1F6" fill-opacity="0.6"/>
      <circle cx="6" cy="16" r="3" fill="#2F6BFF"/>
    </g>
  </g>
  <rect x="2" y="2" width="1020" height="1020" rx="203" fill="none" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="4"/>
</svg>
"""


def write_svg(path):
    u = 1024 * 0.58 / 26
    ox = 512 - 16 * u
    path.write_text(
        SVG.format(u=f"{u:.3f}", ox=f"{ox:.1f}", dx=f"{ox + 6 * u:.1f}", glow_r=f"{3 * u * 2.1:.1f}", blur=f"{3 * u * 1.4:.1f}"),
        encoding="utf-8",
    )


def main():
    branding = ROOT / "assets" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    write_svg(branding / "sotto_icon.svg")
    full_bleed(1024).save(branding / "sotto_icon_1024.png")
    full_bleed(256).save(branding / "sotto_icon_256.png")  # Linux (tool/package_linux.sh)

    mac = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for px in (16, 32, 64, 128, 256, 512, 1024):
        macos(px).save(mac / f"app_icon_{px}.png")

    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    frames = [full_bleed(px) for px in sizes]
    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    frames[-1].save(ico, format="ICO", sizes=[(p, p) for p in sizes], append_images=frames[:-1])
    print("done")


if __name__ == "__main__":
    main()
