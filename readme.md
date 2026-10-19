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
- 🏖️ **Bilinear Elevation Smoothing**: Smooth beaches sloping gently into the sea, with gentle Perlin micro-relief to avoid artificial stepped cliffs.

### 🌴 **Powered by `biomegen`**
Real geographic biomes come alive with authentic native foliage, trees, and surfaces:
- 🌿 **Rainforests**: Dense jungle canopies in the Amazon and Congo basins.
- 🏜️ **Deserts**: Shifting desert sands and cacti across the Sahara, Arabia, and the Australian Outback.
- 🌲 **Taiga & Boreal Forests**: Endless pine forests and snowy trails throughout Siberia and Canada.
- 🍎 **Deciduous Woodlands**: Lush green fields and apple trees across Europe and East Asia.
- 🌾 **Savannas & Grasslands**: Sun-drenched acacia plains in Africa and sweeping steppes in Eurasia.
- 🏔️ **Alpine Peaks**: Towering mountain ranges including the Himalayas / Mount Everest ($Y = 44$), the Andes, the Alps, and the Rockies.

### ✈️ **In-Game Fast Travel (`/worldmap`)**
Start exploring in seconds with built-in landmark navigation:
- `/worldmap` — View your current real-world latitude, longitude, elevation, and biome.
- `/worldmap list` — Browse all major destinations.
- `/worldmap <city>` — Instantly teleport to `london`, `newyork`, `tokyo`, `cairo`, `sydney`, `amazon`, `himalayas`, `sahara`, or `southpole`!
- 🛡️ **Anti-Drown Spawn Protection**: Automatically places new players safely onto coastal land instead of dropping them in the open Atlantic Ocean.

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

Run automated validation tests:
```bash
./test_plan.sh
```

---

## 🤝 Community & Feedback

> 💡 **Reminder**: This project is **experimental and untested**. If you encounter missing chunks, unexpected elevations, weird biome blends, or edge cases, please [open an Issue on GitHub](../../issues) or submit a Pull Request. Let's build the ultimate voxel Earth together! 🌐
