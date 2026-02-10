#!/usr/bin/env python3
"""Generate 10 procedural artwork images for seed data and upload to MinIO."""

import struct
import zlib
import math
import os
import subprocess

ARTWORKS = [
    ("b0000001-0000-0000-0000-000000000001", "sunset",   [(255,120,50), (255,80,120), (40,20,80)]),
    ("b0000001-0000-0000-0000-000000000002", "genesis",  [(0,200,255), (100,0,200), (0,50,100)]),
    ("b0000001-0000-0000-0000-000000000003", "moscow",   [(20,20,60), (255,200,50), (100,100,200)]),
    ("b0000001-0000-0000-0000-000000000004", "chaos",    [(200,0,50), (50,0,200), (255,255,0)]),
    ("b0000001-0000-0000-0000-000000000005", "retro",    [(0,200,0), (200,0,200), (50,50,50)]),
    ("b0000001-0000-0000-0000-000000000006", "cube",     [(0,100,255), (255,0,100), (0,255,200)]),
    ("b0000001-0000-0000-0000-000000000007", "neural",   [(150,0,255), (0,255,150), (255,150,0)]),
    ("b0000001-0000-0000-0000-000000000008", "algorithm",[(255,200,0), (0,100,200), (200,50,100)]),
    ("b0000001-0000-0000-0000-000000000009", "baikal",   [(200,230,255), (100,150,200), (180,220,240)]),
    ("b0000001-0000-0000-0000-000000000010", "cosmic",   [(80,0,120), (200,100,255), (0,50,100)]),
]

SIZE = 512

def make_png(pixels, w, h):
    """Create a PNG file from raw pixel data."""
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))

    raw = b''
    for y in range(h):
        raw += b'\x00'  # filter none
        for x in range(w):
            idx = (y * w + x) * 3
            raw += bytes(pixels[idx:idx+3])

    idat = chunk(b'IDAT', zlib.compress(raw, 9))
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend

def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))

def generate_artwork(style, colors, w, h):
    pixels = [0] * (w * h * 3)
    c1, c2, c3 = colors

    for y in range(h):
        for x in range(w):
            fx, fy = x / w, y / h
            idx = (y * w + x) * 3

            if style == "sunset":
                # Gradient sky with sun
                base = lerp_color(c3, c1, fy)
                sun_dist = math.sqrt((fx - 0.5)**2 + (fy - 0.4)**2)
                if sun_dist < 0.15:
                    t = 1.0 - sun_dist / 0.15
                    base = lerp_color(base, (255, 220, 100), t**0.5)
                # Water reflection
                if fy > 0.65:
                    wave = math.sin(fx * 30 + fy * 10) * 0.03
                    ref_y = 1.0 - (fy - 0.65 + wave) / 0.35
                    ref_color = lerp_color(c3, c2, ref_y)
                    base = lerp_color(base, ref_color, 0.6)
                r, g, b = base

            elif style == "genesis":
                # Geometric shapes
                r, g, b = lerp_color(c3, c1, fy * 0.5 + fx * 0.5)
                for cx, cy, rad in [(0.3, 0.3, 0.2), (0.7, 0.5, 0.15), (0.5, 0.7, 0.18)]:
                    d = math.sqrt((fx - cx)**2 + (fy - cy)**2)
                    if d < rad:
                        t = 1.0 - d / rad
                        shape_c = lerp_color(c2, c1, t)
                        r, g, b = lerp_color((r, g, b), shape_c, t * 0.8)
                # Grid lines
                if (x % 64 < 2) or (y % 64 < 2):
                    r, g, b = [min(255, v + 40) for v in (r, g, b)]

            elif style == "moscow":
                # Night cityscape
                r, g, b = c1
                # Buildings
                bx = (x // 40) * 40
                building_h = 100 + (hash(bx) % 250)
                if y > (h - building_h) and x % 40 > 2 and x % 40 < 38:
                    r, g, b = 30, 30, 50
                    # Windows
                    if (x % 40) % 8 > 2 and (x % 40) % 8 < 6 and y % 12 > 2 and y % 12 < 8:
                        brightness = (hash((bx, y // 12)) % 3)
                        if brightness > 0:
                            r, g, b = lerp_color((30, 30, 50), c2, 0.5 + brightness * 0.25)
                # Stars
                if y < h - 100:
                    star_hash = hash((x // 3, y // 3))
                    if star_hash % 200 == 0:
                        r, g, b = 220, 220, 255

            elif style == "chaos":
                # Abstract swirls
                angle = math.atan2(fy - 0.5, fx - 0.5)
                dist = math.sqrt((fx - 0.5)**2 + (fy - 0.5)**2)
                swirl = math.sin(angle * 3 + dist * 15) * 0.5 + 0.5
                if swirl > 0.5:
                    r, g, b = lerp_color(c1, c2, (swirl - 0.5) * 2)
                else:
                    r, g, b = lerp_color(c3, c1, swirl * 2)
                # Add noise texture
                noise = (hash((x * 7, y * 13)) % 30) - 15
                r, g, b = clamp(r + noise), clamp(g + noise), clamp(b + noise)

            elif style == "retro":
                # Pixel art character
                px, py = x // 16, y // 16
                grid = SIZE // 16
                cx, cy = grid // 2, grid // 2
                # Background checkerboard
                r, g, b = (40, 40, 40) if (px + py) % 2 == 0 else (50, 50, 50)
                # Character body (center area)
                dx, dy = abs(px - cx), abs(py - cy)
                if dx < 4 and dy < 6:
                    if dy < 2 and dx < 3:  # Head
                        r, g, b = c1
                    elif dy >= 2 and dy < 5 and dx < 3:  # Body
                        r, g, b = c2
                    elif dy >= 5 and dx < 2:  # Legs
                        r, g, b = (100, 100, 200)
                    # Eyes
                    if dy == 1 and (dx == 1):
                        r, g, b = (255, 255, 255)

            elif style == "cube":
                # 3D cube illusion
                r, g, b = lerp_color(c3, (20, 20, 40), fy)
                # Cube faces
                cx, cy = 0.5, 0.5
                dx, dy = fx - cx, fy - cy
                # Top face (parallelogram)
                if abs(dx + dy * 0.5) < 0.2 and -0.3 < dy < -0.05:
                    t = (dy + 0.3) / 0.25
                    r, g, b = lerp_color(c1, (200, 200, 255), t)
                # Left face
                if -0.2 < dx < 0.0 and -0.05 < dy < 0.25:
                    t = dy / 0.3
                    r, g, b = lerp_color(c2, (50, 0, 30), t)
                # Right face
                if 0.0 < dx < 0.2 and -0.05 < dy < 0.25:
                    t = dy / 0.3
                    r, g, b = lerp_color(c1, c2, t)

            elif style == "neural":
                # Neural network visualization - nodes and connections
                r, g, b = 10, 10, 20  # Dark background
                # Nodes in layers
                for layer in range(5):
                    lx = 0.1 + layer * 0.2
                    nodes = 3 + (layer % 3)
                    for n in range(nodes):
                        ny = (n + 1) / (nodes + 1)
                        d = math.sqrt((fx - lx)**2 + (fy - ny)**2)
                        if d < 0.04:
                            t = 1.0 - d / 0.04
                            node_c = lerp_color(c1, c2, layer / 4)
                            r, g, b = lerp_color((r, g, b), node_c, t ** 0.5)
                        # Connection glow
                        if d < 0.08:
                            t = 1.0 - d / 0.08
                            r = clamp(r + int(t * 30))
                            g = clamp(g + int(t * 20))
                            b = clamp(b + int(t * 40))

            elif style == "algorithm":
                # Mathematical spirals
                dist = math.sqrt((fx - 0.5)**2 + (fy - 0.5)**2)
                angle = math.atan2(fy - 0.5, fx - 0.5)
                spiral = math.sin(dist * 40 - angle * 5) * 0.5 + 0.5
                golden = math.sin(dist * 25 + angle * 8) * 0.5 + 0.5
                if spiral > 0.5:
                    r, g, b = lerp_color(c1, c2, golden)
                else:
                    r, g, b = lerp_color(c3, c1, golden)

            elif style == "baikal":
                # Frozen lake - ice blue tones
                base = lerp_color(c2, c1, fy)
                # Ice cracks
                crack = math.sin(fx * 50 + math.sin(fy * 30) * 3) * math.cos(fy * 40 + math.sin(fx * 20) * 2)
                if abs(crack) < 0.05:
                    base = lerp_color(base, (255, 255, 255), 0.7)
                # Snow spots
                spot = (hash((x // 20, y // 20)) % 100)
                if spot < 10 and fy < 0.4:
                    base = lerp_color(base, (240, 245, 255), 0.3)
                r, g, b = base

            elif style == "cosmic":
                # Nebula / cosmic dust
                r, g, b = c1
                # Multiple nebula clouds
                for ncx, ncy, nr, nc in [(0.3, 0.4, 0.3, c2), (0.7, 0.6, 0.25, c3), (0.5, 0.3, 0.2, (255, 100, 50))]:
                    d = math.sqrt((fx - ncx)**2 + (fy - ncy)**2)
                    if d < nr:
                        t = 1.0 - d / nr
                        # Noise for organic look
                        noise = math.sin(fx * 30 + fy * 20) * math.cos(fx * 15 - fy * 25) * 0.3
                        t = max(0, min(1, t + noise))
                        r, g, b = lerp_color((r, g, b), nc, t * 0.7)
                # Stars
                star_hash = hash((x * 3, y * 7))
                if star_hash % 300 == 0:
                    brightness = 150 + (star_hash % 105)
                    r, g, b = clamp(r + brightness), clamp(g + brightness), clamp(b + brightness)

            pixels[idx] = clamp(r)
            pixels[idx + 1] = clamp(g)
            pixels[idx + 2] = clamp(b)

    return pixels

def main():
    out_dir = os.path.dirname(os.path.abspath(__file__))

    for uuid, style, colors in ARTWORKS:
        print(f"Generating {style} ({uuid})...")
        pixels = generate_artwork(style, colors, SIZE, SIZE)
        png_data = make_png(pixels, SIZE, SIZE)

        filepath = os.path.join(out_dir, f"{uuid}.png")
        with open(filepath, 'wb') as f:
            f.write(png_data)
        print(f"  Saved {filepath} ({len(png_data)} bytes)")

    # Upload all to MinIO
    print("\nUploading to MinIO...")
    for uuid, style, _ in ARTWORKS:
        filepath = os.path.join(out_dir, f"{uuid}.png")
        url = f"http://192.168.1.54:9000/artworks/{uuid}.png"
        result = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
             "-X", "PUT", url,
             "-H", "Content-Type: image/png",
             "--data-binary", f"@{filepath}"],
            capture_output=True, text=True
        )
        status = result.stdout.strip()
        print(f"  {style}: HTTP {status}")

    print("\nDone!")

if __name__ == "__main__":
    main()
