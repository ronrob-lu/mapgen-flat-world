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
        * Sea floor down to Y = -30
        * Smooth, organic anti-aliased coastlines (zero square edges) via domain warping
          and continuous signed distance field interpolation.
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

-- Biome climate baseline palette
local biome_climate_palette = {
    [0]  = {heat = 50, humid = 50, name = "ocean"},
    [1]  = {heat = 0,  humid = 73, name = "icesheet"},
    [2]  = {heat = 0,  humid = 40, name = "tundra"},
    [3]  = {heat = 25, humid = 70, name = "taiga"},
    [4]  = {heat = 45, humid = 70, name = "coniferous_forest"},
    [5]  = {heat = 60, humid = 68, name = "deciduous_forest"},
    [6]  = {heat = 50, humid = 35, name = "grassland"},
    [7]  = {heat = 89, humid = 42, name = "savanna"},
    [8]  = {heat = 86, humid = 65, name = "rainforest"},
    [9]  = {heat = 92, humid = 16, name = "desert"},
    [10] = {heat = 40, humid = 0,  name = "cold_desert"},
    [11] = {heat = 60, humid = 0,  name = "sandstone_desert"},
}

-- Load preprocessed world_map.json
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

-- Noise 1 & 2: Domain Warping to bend pixel grid lines into organic, fractal natural curves
local np_warp_x = {
    offset = 0,
    scale = 45.0,
    spread = {x = 180, y = 180, z = 180},
    seed = 52719,
    octaves = 3,
    persist = 0.5,
    lacunarity = 2.0,
}
local np_warp_z = {
    offset = 0,
    scale = 45.0,
    spread = {x = 180, y = 180, z = 180},
    seed = 98124,
    octaves = 3,
    persist = 0.5,
    lacunarity = 2.0,
}

-- Noise 3: Fine micro-relief noise for natural coastal variation and hills
local np_fine_relief = {
    offset = 0,
    scale = 2.2,
    spread = {x = 32, y = 32, z = 32},
    seed = 44210,
    octaves = 3,
    persist = 0.55,
    lacunarity = 2.0,
}

local nobj_warp_x, nobj_warp_z, nobj_fine_relief = nil, nil, nil
local pnoise_warp_x, pnoise_warp_z = nil, nil
local nvals_warp_x = {}
local nvals_warp_z = {}
local nvals_fine_relief = {}

-- Smoothstep curve for cubic Hermite interpolation (zero derivative at grid boundaries)
local function smoothstep(t)
    return t * t * (3.0 - 2.0 * t)
end

-- Interpolates terrain elevation, heat, and humidity with zero square artifacts
local function get_smooth_terrain_info(raw_x, raw_z)
    -- Northern polar margin: all water
    if raw_z > MAP_Z_MAX then
        return SEA_LEVEL, 0, 73, "icesheet"
    end

    -- Southern polar margin: all snow and ice
    if raw_z < MAP_Z_MIN then
        return SOUTH_ICE_HEIGHT, 0, 73, "icesheet"
    end

    -- Map area: fractional grid coordinates
    local gx = (raw_x - LUANTI_X_MIN) * MAP_SCALE_X
    local gz = (MAP_Z_MAX - raw_z) * MAP_SCALE_Z

    if gx < 0 then gx = 0 elseif gx > MAP_W_M1 then gx = MAP_W_M1 end
    if gz < 0 then gz = 0 elseif gz > MAP_H_M1 then gz = MAP_H_M1 end

    local gx0 = math.floor(gx)
    local gz0 = math.floor(gz)
    local gx1 = (gx0 < MAP_W_M1) and (gx0 + 1) or gx0
    local gz1 = (gz0 < MAP_H_M1) and (gz0 + 1) or gz0

    local tx = gx - gx0
    local tz = gz - gz0

    -- Cubic Hermite smoothing weights: eliminates square steps and sharp seams
    local sx = smoothstep(tx)
    local sz = smoothstep(tz)

    local idx00 = gz0 * MAP_W + gx0 + 1
    local idx10 = gz0 * MAP_W + gx1 + 1
    local idx01 = gz1 * MAP_W + gx0 + 1
    local idx11 = gz1 * MAP_W + gx1 + 1

    local h00 = elevations[idx00] or 0
    local h10 = elevations[idx10] or 0
    local h01 = elevations[idx01] or 0
    local h11 = elevations[idx11] or 0

    -- Continuous signed elevation: smoothly crosses sea level (0)
    local h = (1.0 - sx) * (1.0 - sz) * h00
            + sx * (1.0 - sz) * h10
            + (1.0 - sx) * sz * h01
            + sx * sz * h11

    -- Continuous climate interpolation: blends heat & humidity across biome borders
    local b00 = biomes[idx00] or 0
    local b10 = biomes[idx10] or 0
    local b01 = biomes[idx01] or 0
    local b11 = biomes[idx11] or 0

    local c00 = biome_climate_palette[b00] or biome_climate_palette[0]
    local c10 = biome_climate_palette[b10] or biome_climate_palette[0]
    local c01 = biome_climate_palette[b01] or biome_climate_palette[0]
    local c11 = biome_climate_palette[b11] or biome_climate_palette[0]

    local heat = (1.0 - sx) * (1.0 - sz) * c00.heat
               + sx * (1.0 - sz) * c10.heat
               + (1.0 - sx) * sz * c01.heat
               + sx * sz * c11.heat

    local humid = (1.0 - sx) * (1.0 - sz) * c00.humid
                + sx * (1.0 - sz) * c10.humid
                + (1.0 - sx) * sz * c01.humid
                + sx * sz * c11.humid

    local dom_idx = (tx < 0.5) and ((tz < 0.5) and idx00 or idx01)
                               or ((tz < 0.5) and idx10 or idx11)
    local b_id = biomes[dom_idx] or 0
    local b_name = biome_palette[b_id + 1] or "ocean"

    return h, heat, humid, b_name
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

    -- Initialize standalone Perlin noise objects for point-based coordinate warping
    if PerlinNoise then
        pnoise_warp_x = PerlinNoise(np_warp_x)
        pnoise_warp_z = PerlinNoise(np_warp_z)
    end

    -- Hook into biomegen for living vegetation & biomes with matching warped coordinates
    if biomegen then
        local orig_calc = biomegen.calc_biome_from_noise
        biomegen.calc_biome_from_noise = function(heat, humid, pos)
            local wx, wz = 0, 0
            if pnoise_warp_x and pnoise_warp_z then
                wx = pnoise_warp_x:get_2d({x = pos.x, y = pos.z})
                wz = pnoise_warp_z:get_2d({x = pos.x, y = pos.z})
            end
            local _, c_heat, c_humid, _ = get_smooth_terrain_info(pos.x + wx, pos.z + wz)
            return orig_calc(c_heat, c_humid, pos)
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
        minetest.log("action", "[" .. modname .. "] Successfully hooked into biomegen with continuous climate blending!")
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
    local minp2d = {x = minp.x, y = minp.z}

    -- Get domain warping and fine relief noise maps
    nobj_warp_x = nobj_warp_x or minetest.get_perlin_map(np_warp_x, permapdims2d)
    nobj_warp_z = nobj_warp_z or minetest.get_perlin_map(np_warp_z, permapdims2d)
    nobj_fine_relief = nobj_fine_relief or minetest.get_perlin_map(np_fine_relief, permapdims2d)

    nobj_warp_x:get_2d_map_flat(minp2d, nvals_warp_x)
    nobj_warp_z:get_2d_map_flat(minp2d, nvals_warp_z)
    nobj_fine_relief:get_2d_map_flat(minp2d, nvals_fine_relief)

    local noise_idx = 1
    local ystride = area.ystride

    for z = minp.z, maxp.z do
        for x = minp.x, maxp.x do
            -- Apply coordinate domain warping: turns square grid cells into curving fractal shorelines!
            local wx = nvals_warp_x[noise_idx] or 0
            local wz = nvals_warp_z[noise_idx] or 0
            local warped_x = x + wx
            local warped_z = z + wz

            local is_south_ice = (warped_z < MAP_Z_MIN)
            local is_north_water = (warped_z > MAP_Z_MAX)

            local base_h, _, _, _ = get_smooth_terrain_info(warped_x, warped_z)
            local relief = nvals_fine_relief[noise_idx] or 0

            local final_h
            if is_north_water then
                final_h = SEA_LEVEL
            elseif is_south_ice then
                final_h = SOUTH_ICE_HEIGHT + relief
            else
                final_h = base_h + relief
            end

            local vi = area:index(x, minp.y, z)

            if is_north_water or final_h <= 0 then
                -- Water body: natural seabed sloping down from beach
                local seabed = math.max(SEA_FLOOR, math.floor(final_h))
                for y = minp.y, maxp.y do
                    if y <= seabed then
                        data[vi] = c_stone
                    elseif y <= SEA_LEVEL then
                        data[vi] = c_water
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end
            elseif is_south_ice then
                -- South margin: polar ice cap
                local surface_y = math.floor(final_h + 0.5)
                for y = minp.y, maxp.y do
                    if y <= SEA_FLOOR then
                        data[vi] = c_stone
                    elseif y <= surface_y - 2 then
                        data[vi] = c_ice
                    elseif y <= surface_y then
                        data[vi] = c_snowblock
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end
            else
                -- Land column: solid stone up to smoothly curved surface (biomegen sets grass/sand/trees)
                local surface_y = math.max(1, math.floor(final_h + 0.5))
                for y = minp.y, maxp.y do
                    if y <= surface_y then
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

    -- Call biomegen to populate surfaces with flora, trees, and ores
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

-- Default spawn location: Lisbon (Portugal)
local SPAWN_POS = {x = -1480, y = 5, z = 6670, name = "Lisbon (Portugal) [Spawn]"}
minetest.set_mapgen_setting("static_spawnpoint", string.format("%d,%d,%d", SPAWN_POS.x, SPAWN_POS.y, SPAWN_POS.z), true)

-- Geographic landmarks and teleport destinations
local major_locations = {
    ["lisbon"]    = {x = -1480,  z = 6670,  name = "Lisbon (Portugal) [Spawn]"},
    ["dover"]     = {x = 150,    z = 8780,  name = "Dover (GB)"},
    ["calais"]    = {x = 380,    z = 8690,  name = "Calais (France)"},
    ["newyork"]   = {x = -12630, z = 7030,  name = "New York (USA)"},
    ["london"]    = {x = 0,      z = 8847,  name = "London (UK)"},
    ["paris"]     = {x = 395,    z = 8383,  name = "Paris (France)"},
    ["cairo"]     = {x = 5360,   z = 5170,  name = "Cairo (Egypt)"},
    ["tokyo"]     = {x = 24000,  z = 6130,  name = "Tokyo (Japan)"},
    ["sydney"]    = {x = 25950,  z = -5820, name = "Sydney (Australia)"},
    ["amazon"]    = {x = -10300, z = -500,  name = "Amazon Rainforest (Brazil)"},
    ["sahara"]    = {x = 3440,   z = 4300,  name = "Sahara Desert"},
    ["himalayas"] = {x = 14900,  z = 4850,  name = "Himalayas / Mount Everest"},
    ["southpole"] = {x = 0,      z = -15400,name = "South Pole (Antarctica)"},
    ["north"]     = {x = 0,      z = 20000, name = "Arctic Ocean (North Margin)"},
}

local function teleport_player_to(player, loc)
    local h, _, _, _ = get_smooth_terrain_info(loc.x, loc.z)
    local y_target = math.max(2, math.floor(h + 2))
    player:set_pos({x = loc.x, y = y_target, z = loc.z})
end

-- Direct teleport commands
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
            local h, _, _, b_name = get_smooth_terrain_info(p.x, p.z)
            return true, string.format(
                "Current World Map Position:\n" ..
                "• Coordinates: X=%.0f, Y=%.0f, Z=%.0f\n" ..
                "• Geographical: %.2f° %s, %.2f° %s\n" ..
                "• Biome: %s (Base Elevation: %.1f)\n" ..
                "Type '/worldmap list' or '/goto <lat> <lon>' to explore.",
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
            return true, list .. "Usage: /worldmap <location> (or shortcuts: /dover, /calais, /lisbon, /newyork, /spawn)"
        elseif major_locations[param] then
            local loc = major_locations[param]
            teleport_player_to(player, loc)
            return true, "Teleported to " .. loc.name .. "!"
        else
            return false, "Unknown location '" .. param .. "'. Type '/worldmap list' for available locations."
        end
    end,
})

-- /goto <lat> <lon> allows teleporting to ANY point on Earth
minetest.register_chatcommand("goto", {
    params = "<latitude> <longitude>",
    description = "Teleport to real-world latitude and longitude (e.g. /goto 51.13 1.31 for Dover)",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end

        local parts = param:split()
        local lat = tonumber(parts[1])
        local lon = tonumber(parts[2])

        if not (lat and lon) then
            return false, "Usage: /goto <latitude> <longitude> (e.g. /goto 51.13 1.31 for Dover)"
        end

        local x = (lon / 180.0) * LUANTI_X_MAX
        local z = (lat / 90.0) * MAP_Z_MAX

        local h, _, _, b_name = get_smooth_terrain_info(x, z)
        local y_target = math.max(2, math.floor(h + 2))
        player:set_pos({x = x, y = y_target, z = z})

        return true, string.format("Teleported to %.2f°%s, %.2f°%s (X=%.0f, Z=%.0f) | Biome: %s, Elevation: %.1f",
            math.abs(lat), (lat >= 0 and "N" or "S"),
            math.abs(lon), (lon >= 0 and "E" or "W"),
            x, z, b_name, h)
    end
})

-- /fly grants fast flying and noclip privileges for testing the world
minetest.register_chatcommand("fly", {
    description = "Grant fast flying and noclip privileges to inspect the world quickly",
    func = function(name)
        local privs = minetest.get_player_privs(name)
        privs.fly = true
        privs.fast = true
        privs.noclip = true
        minetest.set_player_privs(name, privs)
        return true, "Granted fly, fast, and noclip privileges! Press 'K' to toggle fly, 'J' to toggle fast speed."
    end
})

-- /flyspeed <speed> sets flying movement speed
minetest.register_chatcommand("flyspeed", {
    params = "[speed_multiplier]",
    description = "Set movement speed multiplier (e.g. /flyspeed 5 or /flyspeed 10) to cross continents quickly",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end
        local spd = tonumber(param) or 5.0
        player:set_physics_override({speed = spd, jump = 1.5, gravity = 1.0})
        return true, string.format("Movement speed multiplier set to %.1fx! (Default is 1.0)", spd)
    end
})

-- Quick convenience chat commands
minetest.register_chatcommand("spawn", {
    description = "Teleport back to Lisbon spawn",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, SPAWN_POS)
            return true, "Teleported to Lisbon (Spawn)!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("lisbon", {
    description = "Teleport to Lisbon (Portugal)",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, SPAWN_POS)
            return true, "Teleported to Lisbon (Portugal)!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("dover", {
    description = "Teleport to Dover (GB)",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, major_locations["dover"])
            return true, "Teleported to Dover (GB)!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("calais", {
    description = "Teleport to Calais (France)",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, major_locations["calais"])
            return true, "Teleported to Calais (France)!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("newyork", {
    description = "Teleport to New York (USA)",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, major_locations["newyork"])
            return true, "Teleported to New York (USA)!"
        end
        return false, "Player not found."
    end
})

-- Handle new player spawn in Lisbon
minetest.register_on_newplayer(function(player)
    teleport_player_to(player, SPAWN_POS)
    player:get_meta():set_string("spawned_in_lisbon", "true")
    minetest.chat_send_player(player:get_player_name(),
        "Welcome to the World Map in Luanti! You have spawned in Lisbon (Portugal). Type '/worldmap list' or '/goto <lat> <lon>' to explore.")
end)

-- Handle respawn in Lisbon
minetest.register_on_respawnplayer(function(player)
    teleport_player_to(player, SPAWN_POS)
    return true
end)

-- Safety hook on join: rescues any player trapped at (0, 0) in the Atlantic Ocean
minetest.register_on_joinplayer(function(player)
    local p = player:get_pos()
    local dist_from_zero = math.sqrt(p.x * p.x + p.z * p.z)
    local meta = player:get_meta()

    if dist_from_zero < 250 or p.y <= 0 or meta:get_string("spawned_in_lisbon") ~= "true" then
        teleport_player_to(player, SPAWN_POS)
        meta:set_string("spawned_in_lisbon", "true")
        minetest.chat_send_player(player:get_player_name(),
            "Welcome to Lisbon (Portugal)! Type '/worldmap list' for fast travel (e.g. /dover, /calais, /newyork).")
    end
end)
