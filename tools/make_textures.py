"""Generates the FpvCigarette textures (32-bit TGA, power-of-two sizes, straight alpha) and Geometry.lua.

    python tools/make_textures.py            (from the repo root; needs numpy + Pillow)

Outputs
  Textures/cigarette.tga  1024x512  flipbook 4x2 cells of 256: frame 1 = unlit, frames 2..8 = burning down
  Textures/smoke.tga      512x512   flipbook 4x4 cells of 128: one smoke puff from birth to gone
  Textures/ember.tga      64x64     radial glow (drawn with ADD blend)
  Geometry.lua            per cigarette frame: the tip (ember) position inside its cell, 0..1, y down
  tools/preview.png       every frame on a checkerboard plus a mock first-person scene (not shipped)
"""
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXTURES = os.path.join(ROOT, "Textures")
RNG = np.random.default_rng(1337)

# ------------------------------------------------------------------ helpers


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def downsample(rgba, factor):
    """Box filter with alpha weighting (no dark fringes on straight-alpha edges)."""
    h, w, _ = rgba.shape
    r = rgba.reshape(h // factor, factor, w // factor, factor, 4)
    alpha = r[..., 3]
    weight = alpha.sum(axis=(1, 3))
    color = (r[..., :3] * alpha[..., None]).sum(axis=(1, 3)) / np.maximum(weight, 1e-6)[..., None]
    return np.dstack([color, alpha.mean(axis=(1, 3))])


def save_tga(rgba, path):
    data = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(data, "RGBA").save(path)   # Pillow writes uncompressed 32-bit TGA by default


def noise(size, cells, seed_offset=0):
    """Smooth value noise in [0,1]: random grid upscaled bicubically."""
    rng = np.random.default_rng(1000 + seed_offset)
    grid = (rng.random((cells, cells)) * 255).astype(np.uint8)
    return np.asarray(Image.fromarray(grid).resize((size, size), Image.BICUBIC), dtype=np.float64) / 255.0


def fbm(size, base_cells, octaves, seed_offset=0):
    total, amplitude, norm = np.zeros((size, size)), 1.0, 0.0
    for octave in range(octaves):
        total += amplitude * noise(size, base_cells * 2 ** octave, seed_offset + octave * 17)
        norm += amplitude
        amplitude *= 0.5
    return total / norm


def sample(field, x, y):
    """Bilinear lookup of `field` at pixel coordinates x, y (clamped)."""
    h, w = field.shape
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    top = field[y0, x0] * (1 - fx) + field[y0, x0 + 1] * fx
    bottom = field[y0 + 1, x0] * (1 - fx) + field[y0 + 1, x0 + 1] * fx
    return top * (1 - fy) + bottom * fy


# ------------------------------------------------------------------ cigarette

CELL = 256
SUPER = 4
NEAR = np.array([0.30, 1.14])      # filter end, below the cell (cut off by the screen edge)
FAR = np.array([0.66, 0.26])       # tip of an unburned cigarette
HALF_NEAR, HALF_FAR = 0.115, 0.034  # half-width at both ends (perspective taper)
FILTER_END = 0.34                  # fraction of the length that is filter
ASH = 0.03                         # ash length (fraction of the length) on a lit cigarette
CHAR = 0.035                       # charred paper behind the ash
CAP = 0.014                        # depth of the visible end face
STAGES = 8                         # frame 1 unlit, 2..8 burning


def tip_fraction(frame):
    """Where the tip is along the cigarette for 1-based frame `frame`."""
    if frame == 1:
        return 1.0
    return 1.0 - 0.075 * (frame - 2)   # 1.0 .. 0.55


def render_cigarette_cell(frame):
    size = CELL * SUPER
    ys, xs = np.mgrid[0:size, 0:size]
    px, py = (xs + 0.5) / size, (ys + 0.5) / size
    axis = FAR - NEAR
    length = np.hypot(*axis)
    direction = axis / length
    normal = np.array([-direction[1], direction[0]])
    rel_x, rel_y = px - NEAR[0], py - NEAR[1]
    u = (rel_x * direction[0] + rel_y * direction[1]) / length            # 0 at the filter end, 1 at the full tip
    across = rel_x * normal[0] + rel_y * normal[1]
    half = HALF_NEAR + (HALF_FAR - HALF_NEAR) * np.clip(u, 0, 1)
    v = across / half                                                     # -1..1 across the cylinder
    tip = tip_fraction(frame)
    lit = frame > 1

    roundness = np.sqrt(np.clip(1 - v * v, 0, 1))
    body = (np.abs(v) <= 1) & (u >= -0.2) & (u <= tip)
    cap = (np.abs(v) <= 1) & (u > tip) & (u <= tip + CAP * roundness)
    inside = body | cap

    shade = 0.5 + 0.5 * roundness - 0.12 * v
    highlight = 0.22 * np.exp(-((v + 0.38) / 0.16) ** 2)

    paper = np.dstack([np.full_like(u, 0.96), np.full_like(u, 0.95), np.full_like(u, 0.91)])
    grain = noise(size, 48, 3)[..., None] * 0.05
    paper = paper - grain
    cork_spots = (noise(size, 90, 5) > 0.62)[..., None] * 0.12
    cork = np.dstack([np.full_like(u, 0.86), np.full_like(u, 0.56), np.full_like(u, 0.26)]) - cork_spots
    color = np.where((u < FILTER_END)[..., None], cork, paper)
    band = np.abs(u - FILTER_END) < 0.008
    color = np.where(band[..., None], np.array([0.88, 0.74, 0.34]), color)

    if lit:
        ash_start = tip - ASH
        char = smoothstep(ash_start - CHAR, ash_start, u)[..., None]
        charred = np.array([0.22, 0.15, 0.10])
        color = color * (1 - char) + charred * char
        ash_noise = fbm(size, 40, 3, 9)[..., None]
        ash = np.array([0.58, 0.57, 0.55]) * (0.75 + 0.5 * ash_noise)
        is_ash = (u >= ash_start)[..., None]
        color = np.where(is_ash, ash, color)
        cap_color = np.array([0.30, 0.22, 0.18])                          # glowing part comes from the ember texture
    else:
        cap_color = np.array([0.55, 0.36, 0.18]) * (0.8 + 0.4 * noise(size, 70, 11)[..., None])   # tobacco
    color = np.where(cap[..., None], cap_color * np.ones_like(color), color)

    lighting = np.where(cap, 0.9, shade + highlight)[..., None]
    color = np.clip(color * lighting, 0, 1)
    alpha = inside.astype(np.float64)
    cell = downsample(np.dstack([color, alpha]), SUPER)
    tip_point = NEAR + axis * tip
    return cell, (float(tip_point[0]), float(tip_point[1]))


def make_cigarette():
    sheet = np.zeros((CELL * 2, CELL * 4, 4))
    tips = []
    for frame in range(1, STAGES + 1):
        cell, tip = render_cigarette_cell(frame)
        column, row = (frame - 1) % 4, (frame - 1) // 4
        sheet[row * CELL:(row + 1) * CELL, column * CELL:(column + 1) * CELL] = cell
        tips.append(tip)
    save_tga(sheet, os.path.join(TEXTURES, "cigarette.tga"))
    return sheet, tips


# ------------------------------------------------------------------ smoke

SMOKE_CELL = 128
SMOKE_FRAMES = 16


def make_smoke():
    """One puff: a cluster of soft blobs that spread, swirl and thin out, eroded by drifting noise."""
    size = SMOKE_CELL * 2
    ys, xs = np.mgrid[0:size, 0:size]
    x = (xs + 0.5) / size * 2 - 1
    y = (ys + 0.5) / size * 2 - 1
    erosion = fbm(size, 6, 4, 23)
    filaments = fbm(size, 3, 4, 31)
    rng = np.random.default_rng(77)
    blob_count = 16
    angles = rng.random(blob_count) * 2 * math.pi
    distances = np.sqrt(rng.random(blob_count))
    sizes = 0.6 + 0.6 * rng.random(blob_count)
    sheet = np.zeros((SMOKE_CELL * 4, SMOKE_CELL * 4, 4))
    for frame in range(SMOKE_FRAMES):
        age = frame / (SMOKE_FRAMES - 1)
        spread = 0.10 + 0.42 * age
        swirl = 1.4 * age
        density = np.zeros_like(x)
        for index in range(blob_count):
            angle = angles[index] + swirl * (1 if index % 2 else -1)
            bx = math.cos(angle) * distances[index] * spread
            by = math.sin(angle) * distances[index] * spread * 0.8 - 0.12 * age   # drifts up a little
            radius = (0.16 + 0.22 * age) * sizes[index]
            density += np.exp(-((x - bx) ** 2 + (y - by) ** 2) / (radius * radius))
        detail = sample(erosion, xs + age * 50, ys - age * 80)
        # ridged noise gives thin filaments; they take over as the puff ages
        ridged = 1 - np.abs(2 * sample(filaments, xs - age * 30 + 20 * np.sin(y * 3), ys + age * 40) - 1)
        strands = ridged ** 3 * 2.2
        density = density * (0.3 + 1.2 * detail) * ((1 - age * 0.85) + age * 0.85 * strands)
        density = np.clip(density - (0.18 + 0.35 * age), 0, None)
        edge = 1 - smoothstep(0.80, 0.97, np.hypot(x, y))
        fade = smoothstep(0.0, 0.12, age + 0.04) * (1 - age ** 1.8)
        alpha = (1 - np.exp(-density * 1.3)) * edge * fade * 0.6
        light = 0.80 + 0.16 * np.clip(density / 2, 0, 1)
        color = np.dstack([light * 0.97, light * 0.98, light * 1.0])
        cell = downsample(np.dstack([np.clip(color, 0, 1), alpha]), 2)
        column, row = frame % 4, frame // 4
        sheet[row * SMOKE_CELL:(row + 1) * SMOKE_CELL, column * SMOKE_CELL:(column + 1) * SMOKE_CELL] = cell
    save_tga(sheet, os.path.join(TEXTURES, "smoke.tga"))
    return sheet


# ------------------------------------------------------------------ ember


def make_ember():
    size = 64
    ys, xs = np.mgrid[0:size, 0:size]
    r = np.hypot((xs + 0.5) / size * 2 - 1, (ys + 0.5) / size * 2 - 1)
    glow = np.exp(-(r ** 2) * 7)
    core = np.exp(-(r ** 2) * 40)
    color = np.dstack([np.ones_like(r), 0.35 + 0.6 * core, 0.08 + 0.7 * core * core])
    alpha = np.clip(glow * (1 - smoothstep(0.85, 1.0, r)), 0, 1)
    rgba = np.dstack([np.clip(color, 0, 1), alpha])
    save_tga(rgba, os.path.join(TEXTURES, "ember.tga"))
    return rgba


# ------------------------------------------------------------------ outputs


def write_geometry(tips):
    lines = [
        "local _, addon = ...",
        "",
        "-- GENERATED by tools/make_textures.py: do not edit. Re-run the script after changing the texture geometry.",
        "addon.Geometry = {",
        "    cigarette = { columns = 4, rows = 2, frames = %d, width = 1024, height = 512 }," % STAGES,
        "    smoke = { columns = 4, rows = 4, frames = %d }," % SMOKE_FRAMES,
        "    -- tip (ember) of each cigarette frame inside its cell, 0..1 from the top-left",
        "    tips = {",
    ]
    for frame, (tx, ty) in enumerate(tips, start=1):
        lines.append("        { x = %.4f, y = %.4f },   -- frame %d" % (tx, ty, frame))
    lines += ["    },", "}", ""]
    with open(os.path.join(ROOT, "Geometry.lua"), "w", newline="\n") as handle:
        handle.write("\n".join(lines))


def over(background, rgba, x, y, scale=1.0, additive=False):
    """Composite rgba onto background at x, y (top-left) for the preview."""
    if scale != 1.0:
        h, w = rgba.shape[:2]
        image = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA")
        rgba = np.asarray(image.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.BILINEAR)) / 255.0
    h, w = rgba.shape[:2]
    region = background[y:y + h, x:x + w]
    rgba = rgba[:region.shape[0], :region.shape[1]]
    a = rgba[..., 3:4]
    if additive:
        region[:] = np.clip(region + rgba[..., :3] * a, 0, 1)
    else:
        region[:] = region * (1 - a) + rgba[..., :3] * a


def write_preview(cigarette, smoke, ember, tips):
    width, height = 1024, 512 + 512 + 520
    tile = ((np.indices((height, width)) // 16).sum(axis=0) % 2)[..., None]
    canvas = np.where(tile, 0.30, 0.20) * np.ones((height, width, 3))
    over(canvas, cigarette, 0, 0)
    over(canvas, smoke, 0, 512)
    # mock scene: a dusky "world" with the overlay at the bottom
    scene_top = 1024
    gradient = np.linspace(0.0, 1.0, 520)[:, None, None]
    canvas[scene_top:] = np.array([0.18, 0.22, 0.30]) * (1 - gradient) + np.array([0.10, 0.12, 0.10]) * gradient
    cell = cigarette[0:CELL, CELL * 3:CELL * 4]                          # frame 4
    scale = 2.0
    cx, cy = 560, scene_top + 520 - int(CELL * scale)
    over(canvas, cell, cx, cy, scale)
    tx, ty = tips[3]
    ember_x, ember_y = cx + int(tx * CELL * scale), cy + int(ty * CELL * scale)
    over(canvas, ember, ember_x - 24, ember_y - 24, 0.75, additive=True)
    for index, frame in enumerate([2, 5, 8, 11]):
        column, row = frame % 4, frame // 4
        puff = smoke[row * 128:(row + 1) * 128, column * 128:(column + 1) * 128]
        over(canvas, puff, ember_x - 64 + index * 18, ember_y - 120 - index * 70, 1.0 + 0.3 * index)
    Image.fromarray((canvas * 255).astype(np.uint8), "RGB").save(os.path.join(ROOT, "tools", "preview.png"))


def main():
    os.makedirs(TEXTURES, exist_ok=True)
    cigarette, tips = make_cigarette()
    smoke = make_smoke()
    ember = make_ember()
    write_geometry(tips)
    write_preview(cigarette, smoke, ember, tips)
    print("wrote", TEXTURES, "and Geometry.lua")


if __name__ == "__main__":
    main()
