import math
from PIL import Image, ImageDraw

# Brand palette
ELECTRIC_BLUE = (0, 102, 255, 255)      # #0066FF
WHITE = (255, 255, 255, 255)
CHARCOAL = (30, 33, 38, 255)            # #1E2126
TRANSPARENT = (0, 0, 0, 0)

OUT_DIR = "/Users/johnq/Library/Application Support/Claude/scratch-workspaces/d211950b-0965-4d23-b9be-1d25769d8ade/b784e78b-fc81-4ddb-8486-98fa204312c9/scratch-2026-09-18-83368f/design"


def draw_mark(size, bg, fg, padding_frac=0.16, ring_frac=0.20, transparent_bg=False):
    """GLIDE mark: a 'G' ring (exact annulus: filled disk minus filled inner
    disk) with a straight slot cut through its right side -- the G's mouth
    -- and a crossbar spur + arrowhead filling that slot, reading as a G
    opening into a forward arrow.
    """
    S = size
    hole_color = TRANSPARENT if transparent_bg else bg
    img = Image.new("RGBA", (S, S), TRANSPARENT if transparent_bg else bg)
    draw = ImageDraw.Draw(img)

    cx, cy = S / 2, S / 2
    pad = S * padding_frac
    outer_r = S / 2 - pad
    stroke = S * ring_frac
    inner_r = outer_r - stroke

    outer_bbox = [cx - outer_r, cy - outer_r, cx + outer_r, cy + outer_r]
    inner_bbox = [cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r]

    # 1) filled disk, 2) punch the hole -> exact annulus (no stroke artifacts)
    draw.ellipse(outer_bbox, fill=fg)
    draw.ellipse(inner_bbox, fill=hole_color)

    # 3) cut a straight slot through the ring's right side (the G's mouth) --
    # sized just enough for the crossbar + a modest arrow tip, so the ring
    # still reads as a (mostly closed) G rather than a wide-open C.
    slot_half_h = stroke * 0.40
    draw.rectangle(
        [cx + inner_r - stroke * 0.05, cy - slot_half_h, cx + outer_r + 2, cy + slot_half_h],
        fill=hole_color,
    )

    # 4) spur: the G's crossbar, floating inside the hollow interior,
    # attached to the ring's inner wall at the slot. Rounded only on the
    # free (left) end; the right end is flush so the arrowhead can butt
    # against it with no gap or seam.
    spur_thickness = stroke * 0.62
    spur_x0 = cx + inner_r * 0.12
    spur_x1 = cx + inner_r + stroke * 0.05
    draw.rectangle(
        [spur_x0, cy - spur_thickness / 2, spur_x1, cy + spur_thickness / 2],
        fill=fg,
    )
    draw.ellipse(
        [spur_x0 - spur_thickness / 2, cy - spur_thickness / 2,
         spur_x0 + spur_thickness / 2, cy + spur_thickness / 2],
        fill=fg,
    )

    # 5) arrowhead: a modest tip continuing the crossbar out through the
    # mouth -- an accent, not the dominant shape -- tip at the ring's own
    # outer radius so nothing exceeds the padding. Base matches spur_x1
    # exactly so the two shapes fuse with no visible seam.
    head_half_h = stroke * 0.36
    draw.polygon(
        [
            (cx + outer_r, cy),
            (spur_x1, cy - head_half_h),
            (spur_x1, cy + head_half_h),
        ],
        fill=fg,
    )

    return img


def save_all():
    master = draw_mark(1024, ELECTRIC_BLUE, WHITE, transparent_bg=False)
    master.save(f"{OUT_DIR}/glide-icon-1024.png")

    dark_icon = draw_mark(1024, CHARCOAL, ELECTRIC_BLUE, transparent_bg=False)
    dark_icon.save(f"{OUT_DIR}/glide-icon-1024-dark.png")

    # Adaptive-icon-style foreground: kept within the ~66% safe zone.
    mark_white = draw_mark(1024, None, WHITE, padding_frac=0.30, ring_frac=0.17, transparent_bg=True)
    mark_white.save(f"{OUT_DIR}/glide-mark-white.png")

    mark_blue = draw_mark(1024, None, ELECTRIC_BLUE, padding_frac=0.04, ring_frac=0.20, transparent_bg=True)
    mark_blue.save(f"{OUT_DIR}/glide-mark-blue.png")

    mark_charcoal = draw_mark(1024, None, CHARCOAL, padding_frac=0.04, ring_frac=0.20, transparent_bg=True)
    mark_charcoal.save(f"{OUT_DIR}/glide-mark-charcoal.png")

    print("done")


if __name__ == "__main__":
    save_all()
