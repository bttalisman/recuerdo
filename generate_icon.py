#!/usr/bin/env python3
"""Generate app icon with lightning bolt and distributed star field."""

from PIL import Image, ImageDraw, ImageFilter
import random
import math

ICON_DIR = "flashCards/Assets.xcassets/AppIcon.appiconset"


def draw_lightning_bolt(draw, cx, cy, scale, color_outer, color_inner):
    """Draw a stylized lightning bolt centered at (cx, cy)."""
    # Lightning bolt polygon points (relative to center, scaled)
    # Upper portion - wider top zigzag
    points = [
        (-0.08, -0.42),  # top left
        (0.12, -0.42),   # top right
        (0.02, -0.10),   # first notch right
        (0.15, -0.10),   # middle right
        (-0.03, 0.42),   # bottom point
        (0.03, 0.08),    # second notch left
        (-0.10, 0.08),   # middle left
    ]

    poly = [(cx + x * scale, cy + y * scale) for x, y in points]

    # Outer glow
    for offset in range(6, 0, -1):
        alpha = int(40 * (1 - offset / 7))
        glow_color = (*color_outer[:3], alpha)
        expanded = []
        # Expand polygon outward
        center_x = sum(p[0] for p in poly) / len(poly)
        center_y = sum(p[1] for p in poly) / len(poly)
        for px, py in poly:
            dx = px - center_x
            dy = py - center_y
            dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0:
                expanded.append((px + dx / dist * offset * 2, py + dy / dist * offset * 2))
            else:
                expanded.append((px, py))
        draw.polygon(expanded, fill=glow_color)

    # Main bolt - gradient effect via two layers
    draw.polygon(poly, fill=color_outer)

    # Inner highlight (slightly offset left, lighter)
    inner_points = [
        (-0.07, -0.38),
        (0.05, -0.38),
        (-0.01, -0.10),
        (0.08, -0.10),
        (-0.02, 0.30),
        (0.02, 0.08),
        (-0.06, 0.08),
    ]
    inner_poly = [(cx + x * scale, cy + y * scale) for x, y in inner_points]
    draw.polygon(inner_poly, fill=color_inner)


def draw_star(draw, x, y, size, color):
    """Draw a small 4-pointed star."""
    # Horizontal and vertical spikes
    draw.line([(x - size, y), (x + size, y)], fill=color, width=max(1, int(size * 0.4)))
    draw.line([(x, y - size), (x, y + size)], fill=color, width=max(1, int(size * 0.4)))
    # Center bright dot
    r = max(1, size // 3)
    draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def generate_icon(size):
    """Generate a single icon at the given size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background gradient - deep blue to slightly darker blue
    for y in range(size):
        t = y / size
        r = int(10 + t * 15)
        g = int(40 + t * 20)
        b = int(140 - t * 40)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # Subtle corner vignette
    vignette = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    vdraw = ImageDraw.Draw(vignette)
    cx, cy = size // 2, size // 2
    max_dist = math.sqrt(cx * cx + cy * cy)
    for y in range(size):
        for x in range(0, size, 2):  # step by 2 for speed
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            alpha = int(60 * (dist / max_dist) ** 2)
            vdraw.rectangle([x, y, x + 1, y], fill=(0, 0, 0, alpha))
    img = Image.alpha_composite(img, vignette)
    draw = ImageDraw.Draw(img)

    # Distributed stars - random positions across the whole background
    random.seed(42)  # reproducible
    star_color_bright = (255, 255, 220, 255)
    star_color_dim = (200, 210, 255, 160)
    star_color_faint = (180, 190, 255, 90)

    # Keep stars away from the lightning bolt center
    bolt_zone_x = (size * 0.35, size * 0.65)
    bolt_zone_y = (size * 0.15, size * 0.85)

    stars = []
    for _ in range(35):
        sx = random.randint(int(size * 0.05), int(size * 0.95))
        sy = random.randint(int(size * 0.05), int(size * 0.95))

        # Skip if too close to bolt center column
        in_bolt = (bolt_zone_x[0] < sx < bolt_zone_x[1] and
                   bolt_zone_y[0] < sy < bolt_zone_y[1])
        if in_bolt:
            # Push to sides
            if random.random() < 0.5:
                sx = random.randint(int(size * 0.05), int(size * 0.30))
            else:
                sx = random.randint(int(size * 0.70), int(size * 0.95))

        stars.append((sx, sy))

    # Draw stars in 3 layers: faint background, medium, bright foreground
    for i, (sx, sy) in enumerate(stars):
        if i < 12:
            s = random.randint(max(1, size // 300), max(2, size // 180))
            draw_star(draw, sx, sy, s, star_color_faint)
        elif i < 25:
            s = random.randint(max(1, size // 250), max(2, size // 140))
            draw_star(draw, sx, sy, s, star_color_dim)
        else:
            s = random.randint(max(2, size // 200), max(3, size // 100))
            draw_star(draw, sx, sy, s, star_color_bright)

    # Light beam behind bolt
    beam = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(beam)
    beam_cx = size * 0.50
    beam_cy = size * 0.30
    for r in range(int(size * 0.35), 0, -1):
        alpha = int(25 * (1 - r / (size * 0.35)))
        bdraw.ellipse([beam_cx - r, beam_cy - r * 0.6,
                       beam_cx + r, beam_cy + r * 0.6],
                      fill=(180, 210, 255, alpha))
    img = Image.alpha_composite(img, beam)
    draw = ImageDraw.Draw(img)

    # Lightning bolt
    bolt_scale = size * 1.1
    bolt_cx = size * 0.50
    bolt_cy = size * 0.48
    draw_lightning_bolt(
        draw, bolt_cx, bolt_cy, bolt_scale,
        color_outer=(255, 200, 30, 255),   # gold
        color_inner=(255, 240, 120, 255),   # bright yellow
    )

    # Top edge highlight on bolt
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(highlight)
    h_points = [
        (-0.08, -0.42),
        (0.12, -0.42),
        (0.02, -0.10),
        (-0.04, -0.10),
    ]
    h_poly = [(bolt_cx + x * bolt_scale, bolt_cy + y * bolt_scale) for x, y in h_points]
    hdraw.polygon(h_poly, fill=(255, 255, 255, 70))
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=size // 120))
    img = Image.alpha_composite(img, highlight)

    return img


def generate_dark_icon(size):
    """Generate dark mode variant - deeper background."""
    img = generate_icon(size)
    dark_overlay = Image.new("RGBA", (size, size), (0, 0, 20, 50))
    return Image.alpha_composite(img, dark_overlay)


def generate_tinted_icon(size):
    """Generate tinted variant - monochrome silhouette for iOS tinted mode."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Solid background
    draw.rectangle([0, 0, size, size], fill=(40, 40, 40, 255))

    # White lightning bolt
    bolt_scale = size * 1.1
    bolt_cx = size * 0.50
    bolt_cy = size * 0.48
    points = [
        (-0.08, -0.42), (0.12, -0.42), (0.02, -0.10),
        (0.15, -0.10), (-0.03, 0.42), (0.03, 0.08), (-0.10, 0.08),
    ]
    poly = [(bolt_cx + x * bolt_scale, bolt_cy + y * bolt_scale) for x, y in points]
    draw.polygon(poly, fill=(255, 255, 255, 255))

    return img


# Mac icon sizes: 16, 32, 128, 256, 512 at 1x and 2x
MAC_SIZES = {
    "icon_16x16@1x.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32@1x.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128@1x.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256@1x.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512@1x.png": 512,
    "icon_512x512@2x.png": 1024,
}


def main():
    print("Generating app icons...")

    # iOS 1024x1024
    icon = generate_icon(1024)
    path = f"{ICON_DIR}/icon_1024.png"
    icon.convert("RGB").save(path)
    print(f"  {path}")

    dark = generate_dark_icon(1024)
    path = f"{ICON_DIR}/icon_dark_1024.png"
    dark.convert("RGB").save(path)
    print(f"  {path}")

    tinted = generate_tinted_icon(1024)
    path = f"{ICON_DIR}/icon_tinted_1024.png"
    tinted.convert("RGB").save(path)
    print(f"  {path}")

    # Mac sizes
    for filename, size in MAC_SIZES.items():
        img = generate_icon(size)
        path = f"{ICON_DIR}/{filename}"
        img.convert("RGBA").save(path)
        print(f"  {path}")

    print("\nDone!")


if __name__ == "__main__":
    main()
