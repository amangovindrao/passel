"""Draws the launcher icons and splash marks for the three Paasel apps.

Placeholder brand marks, geometric on purpose: they need to be distinguishable
on a home screen with all three installed, and they need to be regenerable
rather than three binaries nobody can edit. Replace with real artwork when there
is any — the file layout is what the platform expects, so dropping better PNGs
into the same paths is all it takes.

Needs Pillow, which is not a project dependency:

    py -m venv .icons && .icons\\Scripts\\pip install pillow
    .icons\\Scripts\\python scripts/generate_app_icons.py

Writes, per app, into android/app/src/main/res/:
  mipmap-<density>/ic_launcher.png             legacy square icon
  mipmap-<density>/ic_launcher_foreground.png  adaptive-icon foreground
  mipmap-<density>/splash_logo.png             the mark used on the splash
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent

INK = (11, 11, 13, 255)
GOLD = (212, 175, 55, 255)
PAPER = (252, 252, 251, 255)

# Android's launcher densities. The legacy icon is the full square; the adaptive
# foreground is drawn on a larger canvas because the launcher masks and animates
# it, and anything outside the middle ~66% can be cropped away.
LEGACY_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
ADAPTIVE_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

# Everything is drawn at this size and downsampled, which is what keeps the
# curves clean at mdpi.
MASTER = 1024


def _canvas(background: tuple[int, int, int, int] | None) -> Image.Image:
    return Image.new("RGBA", (MASTER, MASTER), background or (0, 0, 0, 0))


def _rounded_square(draw: ImageDraw.ImageDraw) -> None:
    draw.rounded_rectangle(
        [(0, 0), (MASTER - 1, MASTER - 1)],
        radius=int(MASTER * 0.22),
        fill=INK,
    )


# --- The three marks -------------------------------------------------------
#
# Each takes a centre and a radius so the same drawing serves the legacy icon,
# the adaptive foreground and the splash at whatever scale each needs.


def draw_customer(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float):
    """A P monogram — the brand mark, for the app that carries the brand name.

    A shopping bag was the obvious first choice and it does not survive contact
    with the shape: a rounded body with an arc above it reads as a padlock no
    matter how the proportions are tuned, because that silhouette is a padlock.
    Rather than fight it, the flagship app takes the wordmark and the other two
    keep their role pictograms — which also makes the three instantly sortable on
    a home screen.

    Drawn from primitives rather than set in a typeface so the output does not
    depend on which fonts happen to be installed.
    """
    stroke = r * 0.3
    stem_x = cx - r * 0.34
    top = cy - r * 0.92
    bottom = cy + r * 0.92

    # Stem, with rounded ends.
    draw.rounded_rectangle(
        [(stem_x - stroke / 2, top), (stem_x + stroke / 2, bottom)],
        radius=stroke / 2,
        fill=GOLD,
    )

    # Bowl: the right half of an ellipse springing from the top of the stem and
    # closing back onto it just above centre.
    bowl_height = r * 1.0
    draw.arc(
        [
            (stem_x, top + stroke / 2 - stroke / 2),
            (stem_x + r * 1.16, top + bowl_height),
        ],
        start=-90,
        end=90,
        fill=GOLD,
        width=int(stroke),
    )
    # Close the bowl flush against the stem at both ends, so the join does not
    # read as a gap at small sizes.
    for y in (top + stroke / 2, top + bowl_height - stroke / 2):
        draw.rounded_rectangle(
            [
                (stem_x - stroke / 2, y - stroke / 2),
                (stem_x + r * 0.2, y + stroke / 2),
            ],
            radius=stroke / 2,
            fill=GOLD,
        )


def draw_shop(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float):
    """A storefront with a scalloped awning."""
    width = r * 1.4
    left, right = cx - width / 2, cx + width / 2
    awning_top = cy - r * 0.62
    awning_bottom = cy - r * 0.16
    stroke = max(2, int(r * 0.13))

    # Awning, drawn as scallops so it reads as a shop rather than a house.
    scallops = 4
    span = width / scallops
    for i in range(scallops):
        x0 = left + i * span
        draw.pieslice(
            [(x0, awning_top), (x0 + span, awning_bottom + span * 0.5)],
            start=180,
            end=360,
            fill=GOLD,
        )
    draw.rectangle(
        [(left, awning_top), (right, awning_top + stroke * 0.6)], fill=GOLD
    )

    # Body.
    draw.rounded_rectangle(
        [(left + r * 0.1, awning_bottom), (right - r * 0.1, cy + r * 0.62)],
        radius=r * 0.08,
        outline=GOLD,
        width=stroke,
    )
    # Door.
    door_w = r * 0.34
    draw.rounded_rectangle(
        [(cx - door_w / 2, cy + r * 0.06), (cx + door_w / 2, cy + r * 0.62)],
        radius=r * 0.06,
        fill=GOLD,
    )


def draw_rider(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float):
    """A scooter, abstracted to two wheels and a swept body."""
    stroke = max(2, int(r * 0.13))
    wheel_r = r * 0.3
    rear = (cx - r * 0.6, cy + r * 0.42)
    front = (cx + r * 0.62, cy + r * 0.42)

    for wx, wy in (rear, front):
        draw.ellipse(
            [(wx - wheel_r, wy - wheel_r), (wx + wheel_r, wy + wheel_r)],
            outline=GOLD,
            width=stroke,
        )

    # Deck and the sweep up to the handlebar.
    draw.line(
        [
            (rear[0] + wheel_r * 0.5, rear[1] - wheel_r * 0.9),
            (cx - r * 0.05, cy + r * 0.06),
            (cx + r * 0.42, cy + r * 0.06),
        ],
        fill=GOLD,
        width=stroke,
        joint="curve",
    )
    draw.line(
        [
            (cx + r * 0.42, cy + r * 0.06),
            (cx + r * 0.5, cy - r * 0.52),
        ],
        fill=GOLD,
        width=stroke,
    )
    draw.line(
        [
            (cx + r * 0.24, cy - r * 0.6),
            (cx + r * 0.68, cy - r * 0.46),
        ],
        fill=GOLD,
        width=stroke,
    )
    # Motion marks behind, so a still icon still reads as moving.
    for i, dx in enumerate((0.95, 1.18)):
        y = cy - r * (0.05 + i * 0.26)
        draw.line(
            [(cx - r * dx, y), (cx - r * (dx - 0.28), y)],
            fill=GOLD,
            width=max(2, int(stroke * 0.7)),
        )


MARKS = {
    "customer_app": draw_customer,
    "shop_app": draw_shop,
    "delivery_app": draw_rider,
}


def _ring(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float) -> None:
    draw.ellipse(
        [(cx - r, cy - r), (cx + r, cy + r)],
        outline=(GOLD[0], GOLD[1], GOLD[2], 90),
        width=max(2, int(r * 0.045)),
    )


def build_legacy(app: str) -> Image.Image:
    image = _canvas(None)
    draw = ImageDraw.Draw(image)
    _rounded_square(draw)
    centre = MASTER / 2
    _ring(draw, centre, centre, MASTER * 0.36)
    MARKS[app](draw, centre, centre, MASTER * 0.24)
    return image


def build_adaptive_foreground(app: str) -> Image.Image:
    """Transparent, and drawn small.

    The launcher crops an adaptive foreground to the middle ~66% and animates it
    beyond that, so a mark sized like the legacy icon would lose its edges.
    """
    image = _canvas(None)
    draw = ImageDraw.Draw(image)
    centre = MASTER / 2
    MARKS[app](draw, centre, centre, MASTER * 0.18)
    return image


def build_splash(app: str) -> Image.Image:
    image = _canvas(None)
    draw = ImageDraw.Draw(image)
    centre = MASTER / 2
    _ring(draw, centre, centre, MASTER * 0.38)
    MARKS[app](draw, centre, centre, MASTER * 0.26)
    return image


def write(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path, "PNG")


def main() -> None:
    for app in MARKS:
        res = REPO / "apps" / app / "android/app/src/main/res"
        legacy = build_legacy(app)
        foreground = build_adaptive_foreground(app)
        splash = build_splash(app)

        for density, size in LEGACY_SIZES.items():
            write(legacy, res / f"mipmap-{density}/ic_launcher.png", size)
            # Splash marks are drawn at the adaptive size: they sit in the
            # middle of the window, not in a launcher mask.
            write(
                splash,
                res / f"mipmap-{density}/splash_logo.png",
                ADAPTIVE_SIZES[density],
            )
        for density, size in ADAPTIVE_SIZES.items():
            write(
                foreground,
                res / f"mipmap-{density}/ic_launcher_foreground.png",
                size,
            )
        print(f"{app}: icons written to {res}")


if __name__ == "__main__":
    main()
