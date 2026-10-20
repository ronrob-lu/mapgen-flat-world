#!/usr/bin/env python3
"""
build_world_json.py
Generates an anti-aliased, continuous world_map.json from Large_World_Map_bright.jpg
for the Luanti / Minetest world mapgen mod.
"""

import sys
import os
import time
import json
import math
import colorsys
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

INPUT_IMAGE = "Large_World_Map_bright.jpg"
OUTPUT_JSON = "world_map.json"

GRID_W = 2048
GRID_H = 1024

LUANTI_X_MIN = -30912
LUANTI_X_MAX = 30927
LUANTI_Z_MIN = -30912
LUANTI_Z_MAX = 30927

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
    """Accurately distinguish water from land."""
    if lat < -62:
        if r > 120 and g > 120 and b > 110:
            return False

    if b > r + 25 and b > 75 and r < 125 and (b > g * 0.82):
        return True
    if b > 135 and (b > r * 1.45) and (b > g * 0.88):
        return True
    if b > 180 and r < 80 and g < 160:
        return True

    return False

def smooth_falloff(dist):
    """Smooth cosine falloff from 1.0 at dist=0 to 0.0 at dist=1."""
    if dist >= 1.0:
        return 0.0
    return 0.5 * (1.0 + math.cos(math.pi * dist))

def classify_biome(r, g, b, lat, lon, dist_coast, mtn=0.0):
    """Classify land pixel into Luanti biome based on true image color and organic climate."""
    abs_lat = abs(lat)
    r_n, g_n, b_n = r / 255.0, g / 255.0, b / 255.0
    h_val, s_val, v_val = colorsys.rgb_to_hsv(r_n, g_n, b_n)
    deg = h_val * 360.0

    # Organic continuous temperature with gentle harmonic turbulence (eliminates dead-straight lines)
    temp = 1.0 - (abs_lat / 90.0) ** 1.35
    temp += 0.04 * math.sin(lat * 0.12 + lon * 0.08) + 0.03 * math.cos(lat * 0.07 - lon * 0.15)
    if mtn > 10.0:
        temp = max(0.0, temp - min(0.30, mtn / 90.0))

    # 1. Polar ice sheet & Glaciers (Antarctica, Greenland, polar ice cap, snow peaks)
    if lat < -65.0:
        return "icesheet"
    if lat > 68.0 and -60.0 <= lon <= -20.0 and v_val > 0.60:
        return "icesheet"
    if v_val > 0.85 and s_val < 0.12 and (temp < 0.50 or mtn > 20.0):
        return "icesheet"
    if temp < 0.22 and v_val > 0.60 and s_val < 0.25:
        return "icesheet"

    # 2. Arid / Deserts (warm hues: red, orange, yellow, tan)
    if (deg >= 15.0 and deg <= 65.0) and (r > 150 and g > 120 and r >= g):
        # Red sandstone deserts (Australian Outback, American Southwest)
        if (deg < 28.0 or r > g + 40) and s_val > 0.25:
            return "sandstone_desert" if temp > 0.45 else "cold_desert"
        # Sand deserts (Sahara, Arabia, Kalahari)
        if v_val > 0.55 and s_val > 0.15:
            return "desert" if temp > 0.50 else "cold_desert"
        # Rocky / dry barrens
        return "desert" if temp > 0.52 else "cold_desert"

    # High altitude cold arid plateaus (Tibet, Altiplano, high mountain barrens)
    if mtn > 22.0 and s_val < 0.35 and temp < 0.48:
        return "cold_desert"

    # 3. Dense forests & vegetated land (green / olive hues)
    if (deg >= 58.0 and deg <= 165.0) or (g > r * 0.95 and g > b * 1.1):
        # Rainforest: dense saturated tropical green in warm humid climates
        if temp > 0.62 and (deg >= 58.0 or g > r) and (s_val > 0.70 or v_val <= 0.44):
            return "rainforest"

        # Taiga: dark evergreen needleleaf in cold northern zones
        if deg >= 80.0 and v_val < 0.38 and temp < 0.45 and lat > 0:
            return "taiga"

        # Coniferous forest: cool darker forest / mountain forest
        if v_val < 0.44 and (temp < 0.55 or mtn > 10.0):
            return "coniferous_forest"

        # Deciduous forest: bright broadleaf green
        if v_val >= 0.40 and s_val > 0.35:
            return "deciduous_forest"

        # Open scrub / savanna / plains
        return "savanna" if temp > 0.60 else "grassland"

    # 4. Dry grass / Savanna / Steppe / Plains (yellowish-green or muted tan)
    if deg >= 40.0 and deg <= 80.0:
        if temp > 0.62:
            return "savanna"
        elif temp >= 0.30:
            return "grassland"
        else:
            return "tundra"

    # 5. Cold subpolar barrens & tundra
    if temp < 0.28:
        return "tundra"
    if temp < 0.45 and lat > 0:
        return "taiga"
    return "savanna" if temp > 0.62 else "grassland"

def get_mountain_boost(lat, lon):
    """Calculate elevation boost with C1 continuous smooth falloff (zero square borders)."""
    boost = 0.0

    # Himalayas & Tibetan Plateau
    d_him = math.hypot((lat - 32.0) / 7.0, (lon - 88.0) / 16.0)
    boost = max(boost, 38.0 * smooth_falloff(d_him))

    # Andes (Venezuela down to Patagonia)
    center_lon = -70.0 - (lat * 0.12)
    d_and_lat = abs(lat - (-22.0)) / 33.0
    d_and_lon = abs(lon - center_lon) / 5.5
    d_and = math.hypot(d_and_lat, d_and_lon)
    boost = max(boost, 26.0 * smooth_falloff(d_and))

    # Rocky Mountains & North American Cordillera
    center_lon = -118.0 + (lat - 32.0) * 0.22
    d_roc_lat = abs(lat - 48.0) / 18.0
    d_roc_lon = abs(lon - center_lon) / 7.5
    d_roc = math.hypot(d_roc_lat, d_roc_lon)
    boost = max(boost, 24.0 * smooth_falloff(d_roc))

    # Alps (Europe)
    d_alps = math.hypot((lat - 46.0) / 3.0, (lon - 10.0) / 7.0)
    boost = max(boost, 20.0 * smooth_falloff(d_alps))

    # Caucasus
    d_cauc = math.hypot((lat - 42.0) / 2.5, (lon - 44.0) / 5.5)
    boost = max(boost, 18.0 * smooth_falloff(d_cauc))

    # Ural Mountains
    d_ural_lat = abs(lat - 59.0) / 10.0
    d_ural_lon = abs(lon - 60.0) / 3.0
    boost = max(boost, 12.0 * smooth_falloff(math.hypot(d_ural_lat, d_ural_lon)))

    # Atlas Mountains (North Africa)
    d_atlas = math.hypot((lat - 32.5) / 3.0, (lon + 3.0) / 7.0)
    boost = max(boost, 14.0 * smooth_falloff(d_atlas))

    # Greenland Ice Sheet interior
    d_grn = math.hypot((lat - 74.0) / 9.0, (lon - (-37.5)) / 13.0)
    boost = max(boost, 14.0 * smooth_falloff(d_grn))

    # Antarctica ice plateau
    if lat < -65.0:
        d_ant = abs(lat - (-90.0)) / 25.0
        boost = max(boost, 12.0 * smooth_falloff(d_ant))

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

    # Step 2: 8-connected Euclidean Chamfer distance transform (prevents diamond/square contours)
    print("Computing 8-connected Euclidean Chamfer distance transforms...")
    INF = 9999.0
    SQRT2 = 1.4142

    dist_land = [[INF if is_land[y][x] else 0.0 for x in range(GRID_W)] for y in range(GRID_H)]
    dist_water = [[0.0 if is_land[y][x] else INF for x in range(GRID_W)] for y in range(GRID_H)]

    # Forward pass (8-connected)
    for y in range(GRID_H):
        for x in range(GRID_W):
            # Land distance to coast
            if dist_land[y][x] != 0.0:
                d = dist_land[y][x]
                xm1 = x - 1 if x > 0 else GRID_W - 1
                xp1 = x + 1 if x < GRID_W - 1 else 0
                d = min(d, dist_land[y][xm1] + 1.0)
                if y > 0:
                    d = min(d, dist_land[y - 1][x] + 1.0)
                    d = min(d, dist_land[y - 1][xm1] + SQRT2)
                    d = min(d, dist_land[y - 1][xp1] + SQRT2)
                dist_land[y][x] = d

            # Water distance to coast
            if dist_water[y][x] != 0.0:
                d = dist_water[y][x]
                xm1 = x - 1 if x > 0 else GRID_W - 1
                xp1 = x + 1 if x < GRID_W - 1 else 0
                d = min(d, dist_water[y][xm1] + 1.0)
                if y > 0:
                    d = min(d, dist_water[y - 1][x] + 1.0)
                    d = min(d, dist_water[y - 1][xm1] + SQRT2)
                    d = min(d, dist_water[y - 1][xp1] + SQRT2)
                dist_water[y][x] = d

    # Backward pass (8-connected)
    for y in range(GRID_H - 1, -1, -1):
        for x in range(GRID_W - 1, -1, -1):
            xm1 = x - 1 if x > 0 else GRID_W - 1
            xp1 = x + 1 if x < GRID_W - 1 else 0

            if dist_land[y][x] != 0.0:
                d = dist_land[y][x]
                d = min(d, dist_land[y][xp1] + 1.0)
                if y < GRID_H - 1:
                    d = min(d, dist_land[y + 1][x] + 1.0)
                    d = min(d, dist_land[y + 1][xm1] + SQRT2)
                    d = min(d, dist_land[y + 1][xp1] + SQRT2)
                dist_land[y][x] = d

            if dist_water[y][x] != 0.0:
                d = dist_water[y][x]
                d = min(d, dist_water[y][xp1] + 1.0)
                if y < GRID_H - 1:
                    d = min(d, dist_water[y + 1][x] + 1.0)
                    d = min(d, dist_water[y + 1][xm1] + SQRT2)
                    d = min(d, dist_water[y + 1][xp1] + SQRT2)
                dist_water[y][x] = d

    # Step 3: Compute continuous signed elevations (logarithmic, no flat clamps)
    print("Classifying biomes and generating continuous floating-point elevations...")
    raw_elev = [[0.0] * GRID_W for _ in range(GRID_H)]
    biomes = [0] * (GRID_W * GRID_H)

    for y in range(GRID_H):
        lat = 90.0 - ((y + 0.5) / GRID_H) * 180.0
        row_offset = y * GRID_W

        for x in range(GRID_W):
            lon = ((x + 0.5) / GRID_W) * 360.0 - 180.0
            idx = row_offset + x

            if not is_land[y][x]:
                # Water: continuous smooth logarithmic seabed depth
                d_w = dist_water[y][x]
                depth = -(1.0 + math.log1p(d_w) * 6.5)
                raw_elev[y][x] = max(-30.0, depth)
                biomes[idx] = BIOME_INDEX["ocean"]
            else:
                # Land: smooth continuous rising elevation, no flat capped plateaus
                d_l = dist_land[y][x]
                r, g, b = pixels[x, y]

                base_h = 1.0 + math.log1p(d_l) * 2.2
                mtn = get_mountain_boost(lat, lon)
                total_h = base_h + mtn

                if lat < -65:
                    total_h = max(total_h, 6.0)

                raw_elev[y][x] = max(1.0, min(total_h, 60.0))

                b_name = classify_biome(r, g, b, lat, lon, d_l, mtn)
                biomes[idx] = BIOME_INDEX[b_name]

    # Step 4: 3x3 Gaussian smoothing filter on the continuous elevation field
    # Completely dissolves any remaining discrete grid stepping artifacts
    print("Applying 3x3 anti-aliasing spatial filter to elevation field...")
    smoothed_elev = [0.0] * (GRID_W * GRID_H)
    kernel = [
        [1.0/16.0, 2.0/16.0, 1.0/16.0],
        [2.0/16.0, 4.0/16.0, 2.0/16.0],
        [1.0/16.0, 2.0/16.0, 1.0/16.0]
    ]

    for y in range(GRID_H):
        row_offset = y * GRID_W
        ym1 = max(0, y - 1)
        yp1 = min(GRID_H - 1, y + 1)

        for x in range(GRID_W):
            xm1 = x - 1 if x > 0 else GRID_W - 1
            xp1 = x + 1 if x < GRID_W - 1 else 0

            val = (kernel[0][0] * raw_elev[ym1][xm1] + kernel[0][1] * raw_elev[ym1][x] + kernel[0][2] * raw_elev[ym1][xp1] +
                   kernel[1][0] * raw_elev[y][xm1]   + kernel[1][1] * raw_elev[y][x]   + kernel[1][2] * raw_elev[y][xp1] +
                   kernel[2][0] * raw_elev[yp1][xm1] + kernel[2][1] * raw_elev[yp1][x] + kernel[2][2] * raw_elev[yp1][xp1])

            smoothed_elev[row_offset + x] = round(val, 1)

    # Step 5: Write JSON
    print(f"Writing '{OUTPUT_JSON}'...")
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
        "elevations": smoothed_elev,
        "biomes": biomes
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(data_dict, f, separators=(",", ":"))

    file_size_mb = os.path.getsize(OUTPUT_JSON) / (1024 * 1024)
    print(f"Successfully generated '{OUTPUT_JSON}' ({file_size_mb:.2f} MB) in {time.time() - start_time:.2f}s total.")

if __name__ == "__main__":
    main()
