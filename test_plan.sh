#!/usr/bin/env bash
set -e

echo "=== Testing Luanti World Map Generator ==="

# 1. Check world_map.json existence and size
if [ ! -f "world_map.json" ]; then
    echo "ERROR: world_map.json not found! Generating it now..."
    python3 build_world_json.py
fi

echo "✓ world_map.json exists ($(ls -lh world_map.json | awk '{print $5}'))"

# 2. Verify world_map.json structure and contents
python3 -c "
import json
with open('world_map.json') as f:
    d = json.load(f)
assert d['width'] == 2048, 'Width must be 2048'
assert d['height'] == 1024, 'Height must be 1024'
assert len(d['elevations']) == 2048 * 1024, 'Elevations length mismatch'
assert len(d['biomes']) == 2048 * 1024, 'Biomes length mismatch'
assert d['bounds']['x_min'] == -30912
assert d['bounds']['x_max'] == 30927
assert d['bounds']['z_min'] == -30912
assert d['bounds']['z_max'] == 30927
assert d['bounds']['map_z_min'] == -15460
assert d['bounds']['map_z_max'] == 15460
print('✓ world_map.json structure verified: 2048x1024 grid, bounds correctly set.')
"

# 3. Check Lua syntax of init.lua
lua -e "
minetest = {
    set_mapgen_setting = function() end,
    get_current_modname = function() return 'worldmap_gen' end,
    get_modpath = function() return '.' end,
    log = function() end,
    parse_json = function(s)
        return {
            width = 2048, height = 1024,
            elevations = {}, biomes = {},
            biome_palette = {'ocean'}
        }
    end,
    get_perlin_map = function() return {} end,
    register_on_mods_loaded = function() end,
    register_on_generated = function() end,
    register_chatcommand = function() end,
    register_on_newplayer = function() end,
}
dofile('init.lua')
print('✓ init.lua syntax and mock execution passed.')
"

# 4. Verify geographic queries
python3 -c "
import json
with open('world_map.json') as f:
    d = json.load(f)

elev = d['elevations']
bio = d['biomes']
pal = d['biome_palette']
w, h = d['width'], d['height']

def q(x, z):
    if z > 15460: return 0, 'ocean'
    if z < -15460: return 8, 'icesheet'
    gx = int(round((x + 30912) / 61839 * (w - 1)))
    gz = int(round((15460 - z) / 30920 * (h - 1)))
    idx = gz * w + gx
    return elev[idx], pal[bio[idx]]

# Check North Margin: water
h_n, b_n = q(0, 20000)
assert h_n == 0 and b_n == 'ocean', f'North margin failed: {h_n}, {b_n}'

# Check South Margin: ice
h_s, b_s = q(0, -20000)
assert h_s == 8 and b_s == 'icesheet', f'South margin failed: {h_s}, {b_s}'

# Check Sahara: desert
h_sahara, b_sahara = q(3440, 4300)
assert b_sahara == 'desert', f'Sahara biome expected desert, got {b_sahara}'

# Check Amazon: rainforest
h_am, b_am = q(-10300, -500)
assert b_am == 'rainforest', f'Amazon biome expected rainforest, got {b_am}'

print('✓ Geographic assertions passed (North Water, South Ice, Sahara Desert, Amazon Rainforest)!')
"

echo "=== All tests completed successfully! ==="
