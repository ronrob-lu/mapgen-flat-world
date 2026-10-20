#!/usr/bin/env python3
"""
preview_world.py
Renders a top-down visual map preview of the entire Luanti world (61840x61840)
directly to 'world_preview.png' for instant worldwide inspection.
"""

import sys
import json
import math
from PIL import Image

PREVIEW_SIZE = 1024  # Preview image resolution (1024x1024 square world)

# Color mapping for each biome
BIOME_COLORS = {
    "ocean":             (28, 120, 200),
    "icesheet":          (230, 240, 255),
    "tundra":            (150, 165, 140),
    "taiga":             (45, 95, 45),
    "coniferous_forest": (35, 110, 60),
    "deciduous_forest":  (75, 155, 45),
    "grassland":         (110, 180, 60),
    "savanna":           (195, 175, 75),
    "rainforest":        (20, 110, 30),
    "desert":            (225, 195, 115),
    "cold_desert":       (175, 160, 130),
    "sandstone_desert":  (210, 160, 95),
}

def smoothstep(t):
    return t * t * (3.0 - 2.0 * t)

def main():
    print("Loading world_map.json...")
    with open("world_map.json") as f:
        map_data = json.load(f)

    w = map_data["width"]
    h = map_data["height"]
    elevations = map_data["elevations"]
    biomes = map_data["biomes"]
    palette = map_data["biome_palette"]

    print(f"Generating {PREVIEW_SIZE}x{PREVIEW_SIZE} full world preview (Luanti coordinates -30912 to +30927)...")
    img = Image.new("RGB", (PREVIEW_SIZE, PREVIEW_SIZE))
    pixels = img.load()

    LUANTI_X_MIN = -30912
    LUANTI_X_MAX = 30927
    MAP_Z_MIN = -15460
    MAP_Z_MAX = 15460

    for py in range(PREVIEW_SIZE):
        # In Luanti, Z goes from +30927 (top) to -30912 (bottom)
        z = LUANTI_X_MAX - (py / PREVIEW_SIZE) * (LUANTI_X_MAX - LUANTI_X_MIN)

        # North Margin (Arctic Ocean)
        if z > MAP_Z_MAX:
            for px in range(PREVIEW_SIZE):
                pixels[px, py] = (25, 110, 190)
            continue

        # South Margin (Antarctica Ice Sheet)
        if z < MAP_Z_MIN:
            for px in range(PREVIEW_SIZE):
                pixels[px, py] = (235, 245, 255)
            continue

        # Map Area
        gz = (MAP_Z_MAX - z) / (MAP_Z_MAX - MAP_Z_MIN) * (h - 1)
        gz0 = int(math.floor(gz))
        gz1 = min(h - 1, gz0 + 1)
        tz = gz - gz0
        sz = smoothstep(tz)

        for px in range(PREVIEW_SIZE):
            x = LUANTI_X_MIN + (px / PREVIEW_SIZE) * (LUANTI_X_MAX - LUANTI_X_MIN)
            gx = (x - LUANTI_X_MIN) / (LUANTI_X_MAX - LUANTI_X_MIN) * (w - 1)
            gx0 = int(math.floor(gx))
            gx1 = min(w - 1, gx0 + 1)
            tx = gx - gx0
            sx = smoothstep(tx)

            idx00 = gz0 * w + gx0
            idx10 = gz0 * w + gx1
            idx01 = gz1 * w + gx0
            idx11 = gz1 * w + gx1

            h00 = elevations[idx00]
            h10 = elevations[idx10]
            h01 = elevations[idx01]
            h11 = elevations[idx11]

            # Hermite continuous elevation
            elev = (1.0 - sx) * (1.0 - sz) * h00 \
                 + sx * (1.0 - sz) * h10 \
                 + (1.0 - sx) * sz * h01 \
                 + sx * sz * h11

            b00 = palette[biomes[idx00]]
            b10 = palette[biomes[idx10]]
            b01 = palette[biomes[idx01]]
            b11 = palette[biomes[idx11]]

            c00 = BIOME_COLORS.get(b00, (100, 100, 100))
            c10 = BIOME_COLORS.get(b10, (100, 100, 100))
            c01 = BIOME_COLORS.get(b01, (100, 100, 100))
            c11 = BIOME_COLORS.get(b11, (100, 100, 100))

            # Continuous color interpolation
            r = (1.0 - sx) * (1.0 - sz) * c00[0] + sx * (1.0 - sz) * c10[0] + (1.0 - sx) * sz * c01[0] + sx * sz * c11[0]
            g = (1.0 - sx) * (1.0 - sz) * c00[1] + sx * (1.0 - sz) * c10[1] + (1.0 - sx) * sz * c01[1] + sx * sz * c11[1]
            b = (1.0 - sx) * (1.0 - sz) * c00[2] + sx * (1.0 - sz) * c10[2] + (1.0 - sx) * sz * c01[2] + sx * sz * c11[2]

            if elev <= 0.0:
                # Water: natural ocean color shaded by depth
                depth_factor = max(0.45, min(1.0, 1.0 + elev / 45.0))
                oc = BIOME_COLORS["ocean"]
                pixels[px, py] = (int(oc[0] * depth_factor), int(oc[1] * depth_factor), int(oc[2] * depth_factor))
            else:
                # Land: lighten by elevation (mountains)
                height_factor = min(1.4, 1.0 + (elev / 50.0) * 0.35)
                pixels[px, py] = (min(255, int(r * height_factor)), min(255, int(g * height_factor)), min(255, int(b * height_factor)))

    out_file = "world_preview.png"
    img.save(out_file)
    print(f"✓ Saved full world map visual preview to '{out_file}'!")

if __name__ == "__main__":
    main()
