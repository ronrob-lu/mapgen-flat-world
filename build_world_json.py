#!/usr/bin/env python3
"""
build_world_json.py
Generates a preprocessed world_map.json from Large_World_Map_bright.jpg
for the Luanti / Minetest world mapgen mod.
"""

import sys
import os
import time
import json
import math
import colorsys
from PIL import Image

# Allow processing large images
Image.MAX_IMAGE_PIXELS = None

INPUT_IMAGE = "Large_World_Map_bright.jpg"
OUTPUT_JSON = "world_map.json"

GRID_W = 2048
GRID_H = 1024

# Luanti world coordinate limits
LUANTI_X_MIN = -30912
LUANTI_X_MAX = 30927
LUANTI_Z_MIN = -30912
LUANTI_Z_MAX = 30927

# Map Z coverage (centered on Equator Z=0, maintaining 2:1 aspect ratio)
# Width = 61840, Height = 30920
MAP_Z_MIN = -15460
MAP_Z_MAX = 15460

BIOME_PALETTE = [
    "ocean",               # 0
    "icesheet",            # 1
    "tundra",              # 2
    "taiga",               # 3
    "coniferous_forest",   # 4
    "deciduous_forest",    # 5
    "grassland",           # 6
    "savanna",             # 7
    "rainforest",          # 8
    "desert",              # 9
    "cold_desert",         # 10
    "sandstone_desert"     # 11
]

BIOME_INDEX = {name: i for i, name in enumerate(BIOME_PALETTE)}

def is_water_pixel(r, g, b, lat):
    """Determine if a pixel is ocean or water body."""
    # Near extreme south (Antarctica), bright surfaces are ice land, not water
    if lat < -62:
        if r > 120 and g > 120 and b > 110:
            return False

    # Standard ocean blue: blue is dominant
    if b > r + 25 and b > 75 and r < 125 and (b > g * 0.82):
        return True
    # Deep dark ocean or bright shelf
    if b > 135 and (b > r * 1.45) and (b > g * 0.88):
        return True
    if b > 180 and r < 80 and g < 160:
        return True

    return False

def classify_biome(r, g, b, lat, dist_coast):
    """Classify land pixel into Luanti biome based on color, latitude, and coastal distance."""
    abs_lat = abs(lat)
    r_n, g_n, b_n = r / 255.0, g / 255.0, b / 255.0
    h_val, s_val, v_val = colorsys.rgb_to_hsv(r_n, g_n, b_n)
    deg = h_val * 360.0

    # 1. Polar ice sheet & glaciers (Antarctica, Greenland, polar ice cap)
    if abs_lat > 75:
        if v_val > 0.45 or (r > 130 and g > 130 and b > 120):
            return "icesheet"
    if abs_lat > 60 and r > 180 and g > 170 and b > 150 and s_val < 0.20:
        return "icesheet"

    # 2. Tundra (high latitude cold barrens)
    if abs_lat > 65:
        if v_val > 0.65 and s_val < 0.20:
            return "icesheet"
        return "tundra"

    # 3. Hot deserts (Sahara, Arabian Peninsula, Kalahari, Australian Outback)
    if (deg >= 25 and deg <= 65) and (r > 180 and g > 160) and b < r:
        if abs_lat > 36 or v_val < 0.70:
            return "cold_desert"
        if r > 220 and g > 190 and b < 160:
            return "desert"
        return "desert"
    if r > 210 and g > 185 and b < 170 and abs_lat < 36:
        return "desert"

    # 4. Cold desert & high plateaus (Tibet, Gobi, Altiplano)
    if (deg >= 20 and deg <= 55) and abs_lat > 25:
        if s_val < 0.35 and v_val > 0.45:
            return "cold_desert"

    # 5. Taiga / Boreal Forest (Siberia, Canada, Scandinavia)
    if lat >= 52:
        return "taiga"

    # 6. Rainforest (tropical, deep lush green)
    if abs_lat <= 15:
        if (deg >= 65 and deg <= 165) and s_val > 0.22:
            return "rainforest"
        if g > r and g > b:
            return "rainforest"
        return "savanna"

    # 7. Savanna (warm, sub-tropical, olive/yellow-green)
    if abs_lat <= 32:
        if (deg >= 35 and deg <= 75):
            return "savanna"
        if s_val < 0.35 and v_val > 0.4:
            return "savanna"
        if (deg >= 75 and deg <= 150) and s_val > 0.3:
            return "rainforest"
        return "savanna"

    # 8. Temperate forests & grasslands (lat 30 to 52)
    if deg >= 70 and deg <= 150:
        if s_val > 0.38 and v_val > 0.45:
            return "deciduous_forest"
        elif s_val > 0.28 and v_val < 0.42:
            return "coniferous_forest"
        else:
            return "grassland"

    if (deg >= 45 and deg <= 70) and s_val < 0.4:
        return "grassland"

    if s_val < 0.25:
        return "cold_desert"

    return "deciduous_forest"

def get_mountain_boost(lat, lon):
    """Calculate elevation boost for mountain ranges and high plateaus."""
    boost = 0.0

    # Himalayas & Tibetan Plateau (70°E to 104°E, 26°N to 38°N)
    if 26.0 <= lat <= 38.0 and 70.0 <= lon <= 104.0:
        d = ((lat - 33.0) / 6.0)**2 + ((lon - 88.0) / 16.0)**2
        if d < 1.0:
            boost = max(boost, 26.0 * (1.0 - d))
        # Himalayan ridge
        d_ridge = ((lat - 28.5) / 2.5)**2 + ((lon - 85.0) / 10.0)**2
        if d_ridge < 1.0:
            boost = max(boost, 36.0 * (1.0 - d_ridge))

    # Andes (Venezuela down to Patagonia: 11°N to 55°S, 80°W to 64°W)
    if -55.0 <= lat <= 11.0 and -80.0 <= lon <= -64.0:
        center_lon = -70.0 - (lat * 0.12)
        d_lon = abs(lon - center_lon)
        if d_lon < 5.0:
            boost = max(boost, 25.0 * (1.0 - d_lon / 5.0))

    # Rocky Mountains & North American Cordillera (32°N to 65°N, 126°W to 105°W)
    if 32.0 <= lat <= 65.0 and -126.0 <= lon <= -105.0:
        center_lon = -118.0 + (lat - 32.0) * 0.22
        d_lon = abs(lon - center_lon)
        if d_lon < 7.0:
            boost = max(boost, 22.0 * (1.0 - d_lon / 7.0))

    # Alps (Europe: 43°N to 48°N, 5°E to 16°E)
    if 43.0 <= lat <= 48.0 and 5.0 <= lon <= 16.0:
        d = ((lat - 46.0) / 3.0)**2 + ((lon - 10.0) / 6.0)**2
        if d < 1.0:
            boost = max(boost, 20.0 * (1.0 - d))

    # Caucasus (40°N to 44°N, 39°E to 49°E)
    if 40.0 <= lat <= 44.0 and 39.0 <= lon <= 49.0:
        d = ((lat - 42.0) / 2.0)**2 + ((lon - 44.0) / 5.0)**2
        if d < 1.0:
            boost = max(boost, 18.0 * (1.0 - d))

    # Ural Mountains (50°N to 68°N, 57°E to 63°E)
    if 50.0 <= lat <= 68.0 and 57.0 <= lon <= 63.0:
        d_lon = abs(lon - 60.0)
        if d_lon < 2.5:
            boost = max(boost, 12.0 * (1.0 - d_lon / 2.5))

    # Atlas Mountains (North Africa: 30°N to 35°N, 10°W to 4°E)
    if 30.0 <= lat <= 35.0 and -10.0 <= lon <= 4.0:
        d = ((lat - 32.5) / 2.5)**2 + ((lon + 3.0) / 7.0)**2
        if d < 1.0:
            boost = max(boost, 14.0 * (1.0 - d))

    # Greenland Ice Sheet interior (65°N to 82°N, 50°W to 25°W)
    if 65.0 <= lat <= 82.0 and -50.0 <= lon <= -25.0:
        d = ((lat - 74.0) / 9.0)**2 + ((lon - (-37.5)) / 13.0)**2
        if d < 1.0:
            boost = max(boost, 12.0 * (1.0 - d))

    # Antarctica ice plateau (lat < -70°)
    if lat < -70.0:
        dist_pole = abs(lat + 90.0)
        boost = max(boost, 8.0 + (1.0 - dist_pole / 20.0) * 10.0)

    return boost

def main():
    start_time = time.time()
    print(f"Loading '{INPUT_IMAGE}'...")

    if not os.path.exists(INPUT_IMAGE):
        print(f"Error: {INPUT_IMAGE} not found!", file=sys.stderr)
        sys.exit(1)

    im_orig = Image.open(INPUT_IMAGE)
    orig_w, orig_h = im_orig.size
    print(f"Original size: {orig_w}x{orig_h}")

    print(f"Resampling to {GRID_W}x{GRID_H}...")
    t_resample = time.time()
    im = im_orig.resize((GRID_W, GRID_H), Image.Resampling.LANCZOS)
    print(f"Resampled in {time.time() - t_resample:.2f}s")

    pixels = im.load()

    # Step 1: Detect water vs land
    print("Classifying water vs land...")
    is_land = [[False] * GRID_W for _ in range(GRID_H)]
    for y in range(GRID_H):
        lat = 90.0 - (y / GRID_H) * 180.0
        for x in range(GRID_W):
            r, g, b = pixels[x, y]
            is_land[y][x] = not is_water_pixel(r, g, b, lat)

    # Step 2: Distance transform for smooth coastal slopes
    print("Computing distance-to-coast transform...")
    INF = 9999
    dist = [[INF if is_land[y][x] else 0 for x in range(GRID_W)] for y in range(GRID_H)]

    # Forward pass
    for y in range(GRID_H):
        for x in range(GRID_W):
            if dist[y][x] != 0:
                d = dist[y][x]
                if x > 0:
                    d = min(d, dist[y][x - 1] + 1)
                else:
                    # Wrap around longitude at left edge!
                    d = min(d, dist[y][GRID_W - 1] + 1)
                if y > 0:
                    d = min(d, dist[y - 1][x] + 1)
                dist[y][x] = d

    # Backward pass
    for y in range(GRID_H - 1, -1, -1):
        for x in range(GRID_W - 1, -1, -1):
            if dist[y][x] != 0:
                d = dist[y][x]
                if x < GRID_W - 1:
                    d = min(d, dist[y][x + 1] + 1)
                else:
                    # Wrap around longitude at right edge!
                    d = min(d, dist[y][0] + 1)
                if y < GRID_H - 1:
                    d = min(d, dist[y + 1][x] + 1)
                dist[y][x] = d

    # Step 3: Compute heights and biomes
    print("Classifying biomes and elevations...")
    elevations = [0] * (GRID_W * GRID_H)
    biomes = [0] * (GRID_W * GRID_H)

    for y in range(GRID_H):
        lat = 90.0 - ((y + 0.5) / GRID_H) * 180.0
        row_offset = y * GRID_W

        for x in range(GRID_W):
            lon = ((x + 0.5) / GRID_W) * 360.0 - 180.0
            idx = row_offset + x

            if not is_land[y][x]:
                # Water
                elevations[idx] = 0
                # Choose ocean biome based on latitude
                if abs(lat) > 65:
                    biomes[idx] = BIOME_INDEX["icesheet"]
                elif abs(lat) > 50:
                    biomes[idx] = BIOME_INDEX["taiga"]
                else:
                    biomes[idx] = BIOME_INDEX["ocean"]
            else:
                # Land
                d_c = dist[y][x]
                r, g, b = pixels[x, y]

                # Base height rises smoothly from beach (1-2) to inland plain (4-8)
                base_h = min(8.0, 1.0 + d_c * 0.45)

                # Mountain boost
                mtn = get_mountain_boost(lat, lon)
                total_h = base_h + mtn

                # If polar ice sheet (Antarctica)
                if lat < -65:
                    total_h = max(total_h, 6.0)

                final_h = int(round(total_h))
                elevations[idx] = max(1, min(final_h, 60))

                # Biome
                b_name = classify_biome(r, g, b, lat, d_c)
                biomes[idx] = BIOME_INDEX[b_name]

    # Step 4: Write JSON
    print(f"Generating JSON output: '{OUTPUT_JSON}'...")
    data_dict = {
        "width": GRID_W,
        "height": GRID_H,
        "bounds": {
            "x_min": LUANTI_X_MIN,
            "x_max": LUANTI_X_MAX,
            "z_min": LUANTI_Z_MIN,
            "z_max": LUANTI_Z_MAX,
            "map_z_min": MAP_Z_MIN,
            "map_z_max": MAP_Z_MAX
        },
        "water_level": 0,
        "sea_floor": -30,
        "biome_palette": BIOME_PALETTE,
        "elevations": elevations,
        "biomes": biomes
    }

    t_write = time.time()
    with open(OUTPUT_JSON, "w") as f:
        # Use compact formatting
        json.dump(data_dict, f, separators=(",", ":"))

    file_size_mb = os.path.getsize(OUTPUT_JSON) / (1024 * 1024)
    print(f"Successfully generated '{OUTPUT_JSON}' ({file_size_mb:.2f} MB) in {time.time() - start_time:.2f}s total.")

if __name__ == "__main__":
    main()
