--[[
    World Map Generator for Luanti (Minetest)
    Generates a full-scale Earth map directly in Luanti from preprocessed world_map.json.

    World coordinates:
    - X: -30912 to +30927 (Span: 61840 blocks) -> -180° to +180° Longitude
    - Z: -30912 to +30927 (Span: 61840 blocks) -> Quadratic Luanti world:
        * Z > 15460 (North): Filled with Arctic Ocean water
        * Z < -15460 (South): Filled with Antarctic snow and ice sheet
        * -15460 <= Z <= 15460: 2:1 equirectangular Earth map (+90° to -90° Latitude)
    - Y: -30912 to +30927 -> Altitude / Depth:
        * Sea level at Y = 0
        * Sea floor at Y = -30
        * Land terrain smoothly elevated from coast (Y=1) to plains and mountains (Y=40+)
--]]

-- Set v7 mapgen settings so biomes and decorations are properly registered
minetest.set_mapgen_setting("mg_name", "v7", true)
minetest.set_mapgen_setting("mg_flags", "nocaves, nodungeons, nodecorations, nolight", true)
minetest.set_mapgen_setting("water_level", "0", true)

local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

-- Luanti world bounds
local LUANTI_X_MIN = -30912
local LUANTI_X_MAX = 30927
local LUANTI_Z_MIN = -30912
local LUANTI_Z_MAX = 30927

local MAP_Z_MIN = -15460
local MAP_Z_MAX = 15460

local SEA_LEVEL = 0
local SEA_FLOOR = -30
local SOUTH_ICE_HEIGHT = 8

-- Biome climate presets (heat and humidity points used by biomegen / minetest_game)
local biome_presets = {
    ["icesheet"]          = {heat = 0,  humid = 73},
    ["tundra"]            = {heat = 0,  humid = 40},
    ["taiga"]             = {heat = 25, humid = 70},
    ["coniferous_forest"] = {heat = 45, humid = 70},
    ["deciduous_forest"]  = {heat = 60, humid = 68},
    ["grassland"]         = {heat = 50, humid = 35},
    ["savanna"]           = {heat = 89, humid = 42},
    ["rainforest"]        = {heat = 86, humid = 65},
    ["desert"]            = {heat = 92, humid = 16},
    ["cold_desert"]       = {heat = 40, humid = 0},
    ["sandstone_desert"]  = {heat = 60, humid = 0},
    ["ocean"]             = {heat = 50, humid = 50},
}

-- Load the preprocessed world_map.json
minetest.log("action", "[" .. modname .. "] Loading world_map.json...")
local json_path = modpath .. "/world_map.json"
local json_file = io.open(json_path, "r")
if not json_file then
    error("[" .. modname .. "] CRITICAL: Could not find '" .. json_path .. "'. Run 'python3 build_world_json.py' first!")
end

local json_content = json_file:read("*a")
json_file:close()

local map_data = minetest.parse_json(json_content)
if not map_data then
    error("[" .. modname .. "] CRITICAL: Failed to parse '" .. json_path .. "'!")
end

local MAP_W = map_data.width or 2048
local MAP_H = map_data.height or 1024
local MAP_W_M1 = MAP_W - 1
local MAP_H_M1 = MAP_H - 1

local elevations = map_data.elevations
local biomes = map_data.biomes
local biome_palette = map_data.biome_palette

local MAP_SCALE_X = MAP_W_M1 / (LUANTI_X_MAX - LUANTI_X_MIN)
local MAP_SCALE_Z = MAP_H_M1 / (MAP_Z_MAX - MAP_Z_MIN)

minetest.log("action", string.format("[%s] Loaded world map grid: %dx%d cells (%d total points)",
    modname, MAP_W, MAP_H, #elevations))

-- Fine 2D Perlin noise for natural, organic micro-terrain relief on land
local np_fine_terrain = {
    offset = 0,
    scale = 1.4,
    spread = {x = 32, y = 32, z = 32},
    seed = 847291,
    octaves = 3,
    persist = 0.5,
    lacunarity = 2.0,
}
local nobj_fine = nil
local nvals_fine = {}

-- Query function: converts world coordinates (x, z) to terrain height, biome id, and biome name
local function get_terrain_info(x, z)
    -- Northern margin (Arctic Ocean): all filled with water
    if z > MAP_Z_MAX then
        return SEA_LEVEL, 0, "ocean"
    end

    -- Southern margin (Antarctica Ice Sheet): all filled with snow and ice
    if z < MAP_Z_MIN then
        return SOUTH_ICE_HEIGHT, 1, "icesheet"
    end

    -- Map area: interpolate within the 2048x1024 grid
    local gx = (x - LUANTI_X_MIN) * MAP_SCALE_X
    local gz = (MAP_Z_MAX - z) * MAP_SCALE_Z

    if gx < 0 then gx = 0 elseif gx > MAP_W_M1 then gx = MAP_W_M1 end
    if gz < 0 then gz = 0 elseif gz > MAP_H_M1 then gz = MAP_H_M1 end

    local gx0 = math.floor(gx)
    local gz0 = math.floor(gz)
    local gx1 = (gx0 < MAP_W_M1) and (gx0 + 1) or gx0
    local gz1 = (gz0 < MAP_H_M1) and (gz0 + 1) or gz0

    local tx = gx - gx0
    local tz = gz - gz0

    local idx00 = gz0 * MAP_W + gx0 + 1
    local idx10 = gz0 * MAP_W + gx1 + 1
    local idx01 = gz1 * MAP_W + gx0 + 1
    local idx11 = gz1 * MAP_W + gx1 + 1

    local h00 = elevations[idx00] or 0
    local h10 = elevations[idx10] or 0
    local h01 = elevations[idx01] or 0
    local h11 = elevations[idx11] or 0

    -- Bilinear interpolation for height
    local h = (1.0 - tx) * (1.0 - tz) * h00
            + tx * (1.0 - tz) * h10
            + (1.0 - tx) * tz * h01
            + tx * tz * h11

    -- Nearest neighbor for biome to prevent blurring biome identities
    local b_idx = (tx < 0.5) and ((tz < 0.5) and idx00 or idx01)
                             or ((tz < 0.5) and idx10 or idx11)
    local b_id = biomes[b_idx] or 0
    local b_name = biome_palette[b_id + 1] or "ocean"

    return h, b_id, b_name
end

-- Content IDs
local c_stone, c_water, c_air
local c_ice, c_snowblock, c_snow

minetest.register_on_mods_loaded(function()
    c_stone = minetest.get_content_id("mapgen_stone")
    c_water = minetest.get_content_id("mapgen_water_source")
    c_air   = minetest.get_content_id("air")

    c_ice       = minetest.get_content_id("default:ice")
    c_snowblock = minetest.get_content_id("default:snowblock")
    c_snow      = minetest.get_content_id("default:snow")

    -- Hook into biomegen if available
    if biomegen then
        local orig_calc = biomegen.calc_biome_from_noise
        biomegen.calc_biome_from_noise = function(heat, humid, pos)
            local _, _, b_name = get_terrain_info(pos.x, pos.z)
            local preset = biome_presets[b_name]
            if not preset then
                if pos.z > MAP_Z_MAX then
                    preset = biome_presets["icesheet"]
                else
                    preset = biome_presets["ocean"]
                end
            end
            return orig_calc(preset.heat, preset.humid, pos)
        end

        -- Ensure biomegen's internal get_biome_at_index calls the overridden calc_biome_from_noise
        if debug and debug.getupvalue and debug.setupvalue and biomegen.get_biome_at_index then
            local i = 1
            while true do
                local n, _ = debug.getupvalue(biomegen.get_biome_at_index, i)
                if not n then break end
                if n == "calc_biome_from_noise" then
                    debug.setupvalue(biomegen.get_biome_at_index, i, function(heat, humid, pos)
                        return biomegen.calc_biome_from_noise(heat, humid, pos)
                    end)
                    break
                end
                i = i + 1
            end
        end
        minetest.log("action", "[" .. modname .. "] Successfully hooked into biomegen!")
    end
end)

-- Reusable voxel data buffer
local data = {}

-- Mapgen chunk generation
minetest.register_on_generated(function(minp, maxp, seed)
    -- Quick check: chunk completely in the sky
    if minp.y > 65 then
        return
    end

    local voxelmanip, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
    voxelmanip:get_data(data)

    -- Quick check: chunk completely deep underground
    if maxp.y < SEA_FLOOR - 2 then
        local vi_start = area:index(minp.x, minp.y, minp.z)
        local vi_end = area:index(maxp.x, maxp.y, maxp.z)
        for vi = vi_start, vi_end do
            data[vi] = c_stone
        end
        voxelmanip:set_data(data)
        voxelmanip:set_lighting({day = 0, night = 0})
        voxelmanip:write_to_map()
        return
    end

    local sidelen_x = maxp.x - minp.x + 1
    local sidelen_z = maxp.z - minp.z + 1
    local permapdims2d = {x = sidelen_x, y = sidelen_z, z = 1}

    nobj_fine = nobj_fine or minetest.get_perlin_map(np_fine_terrain, permapdims2d)
    nobj_fine:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_fine)

    local noise_idx = 1
    local ystride = area.ystride

    for z = minp.z, maxp.z do
        local is_south_ice = (z < MAP_Z_MIN)
        local is_north_water = (z > MAP_Z_MAX)

        for x = minp.x, maxp.x do
            local base_h, _, b_name = get_terrain_info(x, z)
            local target_h

            if is_north_water then
                target_h = SEA_LEVEL
            elseif is_south_ice then
                -- South margin: gentle rolling Antarctic ice sheet
                local fine = nvals_fine[noise_idx] or 0
                target_h = math.floor(SOUTH_ICE_HEIGHT + fine + 0.5)
            elseif base_h <= 0 then
                -- Ocean water
                target_h = SEA_LEVEL
            else
                -- Land: add natural micro-relief noise
                local fine = nvals_fine[noise_idx] or 0
                target_h = math.max(1, math.floor(base_h + fine + 0.5))
            end

            -- Fill column from minp.y to maxp.y
            local vi = area:index(x, minp.y, z)

            if is_north_water or base_h <= 0 then
                -- Ocean column: stone below SEA_FLOOR, water up to 0, air above 0
                for y = minp.y, maxp.y do
                    if y <= SEA_FLOOR then
                        data[vi] = c_stone
                    elseif y <= SEA_LEVEL then
                        data[vi] = c_water
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end
            elseif is_south_ice or b_name == "icesheet" then
                -- Polar ice column: stone deep below, ice block up to surface, air above
                for y = minp.y, maxp.y do
                    if y <= SEA_FLOOR then
                        data[vi] = c_stone
                    elseif y <= target_h - 2 then
                        data[vi] = c_ice
                    elseif y <= target_h then
                        data[vi] = c_snowblock
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end
            else
                -- Standard Land column: stone up to target_h, air above
                for y = minp.y, maxp.y do
                    if y <= target_h then
                        data[vi] = c_stone
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end
            end

            noise_idx = noise_idx + 1
        end
    end

    -- Call biomegen to place biome surface nodes, trees, foliage, and ores
    if biomegen then
        biomegen.generate_all(data, area, voxelmanip, minp, maxp, seed)
    else
        voxelmanip:set_data(data)
    end

    voxelmanip:set_lighting({day = 15, night = 0})
    voxelmanip:write_to_map()
    voxelmanip:update_liquids()
    voxelmanip:update_map()
end)

-- Helpful geographic teleport / navigation command for players
local major_locations = {
    ["london"]    = {x = 0,      z = 8847,  name = "London (UK)"},
    ["paris"]     = {x = 395,    z = 8383,  name = "Paris (France)"},
    ["newyork"]   = {x = -12700, z = 7000,  name = "New York (USA)"},
    ["cairo"]     = {x = 5360,   z = 5170,  name = "Cairo (Egypt)"},
    ["tokyo"]     = {x = 24000,  z = 6130,  name = "Tokyo (Japan)"},
    ["sydney"]    = {x = 25950,  z = -5820, name = "Sydney (Australia)"},
    ["amazon"]    = {x = -10300, z = -500,  name = "Amazon Rainforest (Brazil)"},
    ["sahara"]    = {x = 3440,   z = 4300,  name = "Sahara Desert"},
    ["himalayas"] = {x = 14900,  z = 4850,  name = "Himalayas / Mount Everest"},
    ["southpole"] = {x = 0,      z = -15400,name = "South Pole (Antarctica)"},
    ["north"]     = {x = 0,      z = 20000, name = "Arctic Ocean (North Margin)"},
}

minetest.register_chatcommand("worldmap", {
    params = "[location / list / info]",
    description = "Teleport to major Earth landmarks or view current real-world coordinates",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end

        param = param:trim():lower()

        if param == "" or param == "info" then
            local p = player:get_pos()
            local lon = (p.x / LUANTI_X_MAX) * 180.0
            local lat = (p.z / MAP_Z_MAX) * 90.0
            local h, _, b_name = get_terrain_info(p.x, p.z)
            return true, string.format(
                "Current World Map Position:\n" ..
                "• Coordinates: X=%.0f, Y=%.0f, Z=%.0f\n" ..
                "• Geographical: %.2f° %s, %.2f° %s\n" ..
                "• Biome: %s (Base Elevation: %.0f)\n" ..
                "Type '/worldmap list' to see landmarks you can teleport to.",
                p.x, p.y, p.z,
                math.abs(lat), (lat >= 0 and "N" or "S"),
                math.abs(lon), (lon >= 0 and "E" or "W"),
                b_name, h
            )
        elseif param == "list" then
            local list = "Available Earth locations:\n"
            for key, loc in pairs(major_locations) do
                list = list .. string.format("• %s -> %s\n", key, loc.name)
            end
            return true, list .. "Usage: /worldmap <location>"
        elseif major_locations[param] then
            local loc = major_locations[param]
            local h, _, _ = get_terrain_info(loc.x, loc.z)
            local y_target = math.max(1, math.floor(h + 2))
            player:set_pos({x = loc.x, y = y_target, z = loc.z})
            return true, "Teleported to " .. loc.name .. "!"
        else
            return false, "Unknown location '" .. param .. "'. Type '/worldmap list' for available locations."
        end
    end,
})

-- Ensure new players don't spawn trapped deep in the ocean if (0,0) is water
minetest.register_on_newplayer(function(player)
    local p = player:get_pos()
    local h, _, _ = get_terrain_info(p.x, p.z)
    if h <= 0 then
        -- Spawn near West African coast / Nigeria (land near Greenwich/Equator)
        local spawn_x = 1000
        local spawn_z = 1000
        local spawn_h, _, _ = get_terrain_info(spawn_x, spawn_z)
        player:set_pos({x = spawn_x, y = math.max(1, math.floor(spawn_h + 2)), z = spawn_z})
        minetest.chat_send_player(player:get_player_name(),
            "Welcome to the World Map in Luanti! Type '/worldmap' for coordinates or '/worldmap list' to travel.")
    end
end)
