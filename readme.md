# 🌍 Luanti WorldMap Gen 🚀

> ### ⚠️ **Work In Progress & Untested**
> **Notice for GitHub Visitors**: This mod is currently **under active development and completely untested** in production / long-term gameplay. Expect experimental mechanics, terrain quirks, and evolving features. We strongly recommend testing in a dedicated new world. Feedback, issue reports, and pull requests are warmly welcome! 🧪🛠️

---

Ever wanted to walk across the Sahara, scale the Himalayas, or voyage down the Amazon river inside **Luanti** (formerly Minetest)? 

**Luanti WorldMap Gen** transforms the entire Luanti universe into a breathtaking, full-scale replica of Planet Earth! Spanning across all **61,840 blocks** of Luanti's world boundaries, this mod translates high-resolution Earth satellite & relief imagery into playable terrain with authentic biomes, realistic mountain peaks, and seamless polar ice caps.

---

## 🌟 Why You'll Love It

### 🗺️ **True Full-Scale Earth Simulation**
No cramped mini-maps! Earth stretches across the maximum allowable coordinates of Luanti from **`-30912` to `+30927`** along the $X$ and $Z$ axes:
- **East-to-West Longitude**: Spans $-180^\circ$ to $+180^\circ$ across the full 61,840-block $X$ axis.
- **Equator & Prime Meridian**: Centered precisely at `(0, 0)`.
- **The Central Earth Band**: Preserves Earth's natural $2:1$ equirectangular projection between $Z = -15460$ and $Z = +15460$.

### 🌊 **Endless Oceans & Polar Ice Caps**
Because Luanti's world boundary is quadratic (square) while Earth maps are $2:1$, we solved the polar puzzle naturally:
- 🧊 **North Margin ($Z > 15460$)**: All filled with the **Arctic Ocean** ($Y \le 0$ water down to the ocean floor at $Y = -30$).
- ❄️ **South Margin ($Z < -15460$)**: All filled with **Antarctica's Ice Sheet** — a massive, frozen expanse of solid snow and ice blocks stretching to the southern border!

### ⚡ **Blazing Performance with Zero Lag**
Instead of forcing your Luanti engine to parse an enormous 78.6 MB JPEG on every chunk generation, this mod ships with a preprocessed, compact **`world_map.json`** ($2048 \times 1024$ grid):
- 🏎️ **Loads in under 0.1 seconds** via Luanti's native C++ JSON parser!
- 💾 Instant $O(1)$ lookups during terrain generation.
### ⚡ **Organic Anti-Aliased Landscapes (No Squares!)**
In real life, nature never builds straight square boxes! We completely eliminated grid pixel steps and square edges through a two-stage organic smoothing engine:
- 🌀 **Coordinate Domain Warping**: A multi-octave 2D Perlin turbulence field continuously deforms sample coordinates before querying the map. Rigid square grid lines are bent into winding, realistic, fractal coastlines, bays, and peninsulas!
- 🌊 **Continuous Signed Distance Fields (SDF)**: Ocean water carries continuous negative depths ($-1$ to $-30$) while land carries positive elevations ($+1$ to $+45$). Waterlines cross grid cells smoothly at arbitrary angles instead of dropping off in 30-block square cliffs.
- 🎨 **Cubic Hermite Climate Blending**: Heat and humidity are continuously interpolated between climate zones. Biomes feather and merge organically without boxy pixel boundaries!

### 🌴 **Powered by `biomegen`**
Real geographic biomes come alive with authentic native foliage, trees, and surfaces:
- 🌿 **Rainforests**: Dense jungle canopies in the Amazon and Congo basins.
- 🏜️ **Deserts**: Shifting desert sands and cacti across the Sahara, Arabia, and the Australian Outback.
- 🌲 **Taiga & Boreal Forests**: Endless pine forests and snowy trails throughout Siberia and Canada.
- 🍎 **Deciduous Woodlands**: Lush green fields and apple trees across Europe and East Asia.
- 🌾 **Savannas & Grasslands**: Sun-drenched acacia plains in Africa and sweeping steppes in Eurasia.
- 🏔️ **Alpine Peaks**: Towering mountain ranges including the Himalayas / Mount Everest ($Y = 44$), the Andes, the Alps, and the Rockies.

### ✈️ **In-Game Fast Travel & Spawn in Lisbon (`/worldmap`, `/goto`, `/fly`)**
Start exploring in seconds with built-in landmark navigation and inspection tools:
- 🇵🇹 **Default Spawn in Lisbon (Portugal)**: All players spawn safely on land in Lisbon (`X=-1480, Z=6670`). If an existing player was trapped in the Atlantic Ocean at `(0, 0)`, they are automatically rescued and relocated to Lisbon on join!
- ⚡ **Direct Shortcut Commands**:
  - `/spawn` or `/lisbon` — Teleport to Lisbon (Portugal).
  - `/dover` — Teleport to Dover (GB) on the White Cliffs of Kent (`X=150, Z=8780`).
  - `/calais` — Teleport to Calais (France) across the English Channel (`X=380, Z=8690`).
  - `/newyork` — Teleport to New York (USA) (`X=-12630, Z=7030`).
- 🌐 **Global Coordinate Teleport (`/goto <lat> <lon>`)**:
  - Teleport to *any* real-world coordinates on Earth! (e.g. `/goto 51.13 1.31` for Dover, `/goto -33.86 151.2` for Sydney, `/goto 48.85 2.35` for Paris).
- 🚀 **High-Speed World Inspection**:
  - `/fly` — Instantly grants fly, fast, and noclip privileges. (Press `K` to fly, `J` for fast).
  - `/flyspeed <multiplier>` — Set flying speed multiplier (e.g. `/flyspeed 10` or `/flyspeed 20`) to zoom across continents in seconds.
- 🧭 `/worldmap` — View current real-world latitude, longitude, elevation, and biome.
- 📋 `/worldmap list` — Browse all major destinations (`lisbon`, `dover`, `calais`, `newyork`, `london`, `paris`, `tokyo`, `cairo`, `sydney`, `amazon`, `himalayas`, `sahara`, `southpole`, `north`).

---

## 🔍 How to Test & Inspect the Entire World

Testing a 61,840-block Earth can feel daunting! Here are two easy ways to inspect the whole world:

### Method 1: Instant Top-Down Visual Preview (External)
Run the built-in world renderer to generate a complete visual map preview image:
```bash
python3 preview_world.py
```
This produces **`world_preview.png`** (a full $1024 \times 1024$ rendering of the entire Luanti quadratic coordinate space). Open it in your image viewer to inspect coastlines, mountain ranges, Dover/Calais separation, biomes, and polar caps at a glance!

### Method 2: High-Speed Flight & Global Teleport (In-Game)
1. In-game, run `/fly` to enable fly and noclip privileges.
2. Run `/flyspeed 10` (or `/flyspeed 20`) to fly across entire continents at super-speed.
3. Use `/goto <lat> <lon>` or `/worldmap <city>` to jump anywhere on the globe.

---

## 🚀 Quick Start Guide

1. **Install Dependencies**:
   - Make sure you have `minetest_game` (provides `default`) and `biomegen` (included in `source_mods/biomegen`).
2. **Drop the Mod**:
   - Clone or copy this repository into your Luanti `mods/` folder.
3. **Enable in World**:
   - In the Luanti main menu, select your world, click **Configure Mods**, and enable **`worldmap_gen`** (or ensure `load_mod_worldmap_gen = true` in `world.mt`).
4. **Enter the World & Explore**:
   - Type `/worldmap list` to start your globe-trotting journey!

---

## 🛠️ Developer & Customization Tools

Want to regenerate or modify the terrain dataset with custom resolutions or mountain curves?
A Python build tool is included right in the repository:

```bash
# Regenerates world_map.json directly from Large_World_Map_bright.jpg
python3 build_world_json.py
```

> 📌 **Note on `Large_World_Map_bright.jpg`**: The 78.6 MB image is **not needed by Luanti** at runtime and is ignored in `.gitignore`. Only `world_map.json` is required to run the mod, keeping git repositories small and fast!

Run automated validation tests:
```bash
./test_plan.sh
```

---

## 🤝 Community & Feedback

> 💡 **Reminder**: This project is **experimental and untested**. If you encounter missing chunks, unexpected elevations, weird biome blends, or edge cases, please [open an Issue on GitHub](../../issues) or submit a Pull Request. Let's build the ultimate voxel Earth together! 🌐
