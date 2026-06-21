# Project: Red Descent — Open-Source Art & Asset Sourcing Guide

**Companion to:** `Red_Descent_Game_Design_Document.pdf`
**Purpose:** A curated, license-cleared shortlist of open-source artwork and audio for building the prototype. Everything here is usable in a commercial project. Each entry notes its license and whether attribution is required, so the rig never gets blocked on placeholder art.

> **TL;DR for the prototype:** Lean on **Kenney** (CC0, zero attribution, consistent style) for almost everything in Phases 1–4, and fill the mining/cave-specific gaps from **OpenGameArt's Open Pixel Project** sets. Keep one `CREDITS.txt` from day one.

---

## 1. Licensing Primer (read once)

| License | Attribution required? | Commercial use | Notes |
|---|---|---|---|
| **CC0 1.0** | No (appreciated, not required) | Yes | Public domain. Safest possible choice. Most Kenney assets. |
| **CC-BY 3.0/4.0** | **Yes** — credit the author | Yes | Must name author + link license. |
| **CC-BY-SA** | Yes + **share-alike** | Yes | Derivatives must use the same license. Use with care. |
| **OGA-BY 3.0** | Yes | Yes | OpenGameArt's attribution license; like CC-BY. |
| **GPL 2.0/3.0** | Yes | Yes | Copyleft; fine for art assets but adds obligations — prefer CC0 when available. |

**Rule of thumb for Red Descent:** Default to CC0. Only reach for CC-BY assets when there's no CC0 equivalent, and log them in `CREDITS.txt` immediately.

---

## 2. Recommended Asset Sources (the four pillars)

1. **Kenney** — https://kenney.nl/assets — Thousands of CC0 assets (2D, UI, audio, fonts). Consistent chunky style that matches the GDD's "chunky, high-contrast pixel art" direction. **No attribution required.**
2. **OpenGameArt.org** — https://opengameart.org — Huge community library. Mixed licenses — **always check the per-asset license box.**
3. **itch.io (asset packs)** — https://itch.io/game-assets/free/tag-cc0 — Filterable by CC0 / Godot / Pixel Art tags. Per-pack licensing.
4. **Freesound.org** — https://freesound.org — Sound effects, filterable by CC0. Per-sound licensing.

---

## 3. Visual Assets — Mapped to GDD Sections

### 3.1 Terrain Tilesets (GDD §5 — ProcGen / Biomes)

The game needs destructible block tiles for Dirt, Rock, and Ore (Phase 3), then biome variants for The Crust, The Mantle, and The Ruins.

| Asset | Source | License | Fits |
|---|---|---|---|
| **OPP2017 — Cave and Mine Cart** | [opengameart.org](https://opengameart.org/content/opp2017-cave-and-mine-cart) | CC0 / CC-BY / OGA-BY (multi) | **Primary mining set.** 400+ 32×32 tiles: rocks, crystals (→ ores), slopes, mine-cart tracks. DawnBringer-32 palette. Great for The Crust & The Mantle. |
| **Cave Tileset by xvideosman** | [opengameart.org](https://opengameart.org/content/cave-tileset-by-xvideosman) | Check per-asset | Dirt / Stone / **Gold Ore** tiles + crates, rails, crystals-in-stone. Directly maps to the Dirt/Rock/Ore triad in Phase 3. |
| **Kenney — Pixel Platformer Blocks** | [kenney.nl](https://kenney.nl/assets/pixel-platformer-blocks) | CC0 | 80 clean block tiles. Ideal placeholder block set for Phase 1–2 before biome art is finalized. |
| **Kenney — Platformer Art Extended Tileset** | [kenney.nl](https://kenney.nl/assets/platformer-art-extended-tileset) | CC0 | 360 assets; broad terrain variety for prototyping biome transitions. |
| **MoonRoar: Cave'n'Field** | [soulares.itch.io](https://soulares.itch.io/moonroar-cave-field) | Check pack page | Atmospheric cave + field tileset for cavern (cellular-automata) areas. |

**Mars-red palette note:** No purpose-built "Mars" CC0 tileset surfaced. Cheapest path: take a CC0 cave/dirt set above and **recolor toward Martian reds/oranges** (the GDD's stated palette) — trivial with a hue shift in Aseprite/GIMP, and CC0 permits modification freely. The Ruins biome (cold blues/silvers, 90° architecture) pairs well with a **sci-fi metal/dungeon** tileset — see §3.4.

### 3.2 The Rig / Player Vehicle (GDD §3 — Player Mechanics)

| Asset | Source | License | Fits |
|---|---|---|---|
| **OpenGameArt "Mining Unit" / robot sprites** | [Sci-fi/space theme](https://opengameart.org/content/theme-sci-fi-space) | Check per-asset | Search the sci-fi/space collection for "Mining Unit" and mech/robot rigs to stand in for the digging rig. |
| **200+ CC0 Spaceship Sprites** | [opengameart.org](https://opengameart.org/content/200-cc0-spaceship-sprites) | CC0 | Hull/part kit for the crashed ship in the hub and the escape capsule (GDD §7). |
| **2D Spaceships collection** ("Astrominer Sprites", "CC0 Ships") | [opengameart.org](https://opengameart.org/content/2d-spaceships) | Mixed — check | "Astrominer" is thematically on-the-nose for the protagonist's rig. |

> The rig is the game's signature sprite and a likely candidate for **custom art** later. For the prototype, a recolored robot/mech sprite + thruster flame is enough to validate movement and drilling.

### 3.3 Effects & Particles (GDD §3–4 — heat, bombs, cave-ins, thrusters)

| Asset | Source | License | Fits |
|---|---|---|---|
| **Kenney — Particle Pack** | [kenney.nl](https://kenney.nl/assets/particle-pack) | CC0 | Dust, smoke, fire, sparks → drill heat, thruster exhaust, dust accumulation, explosions. |
| **Kenney — Smoke / explosion particle textures** | [kenney.nl/assets](https://kenney.nl/assets) | CC0 | Feed into Godot's `GPUParticles2D` for kinetic-impactor (bomb) chain collapses. |

### 3.4 The Ruins / Endgame Architecture (GDD §7)

| Asset | Source | License | Fits |
|---|---|---|---|
| **Kenney — sci-fi / metal tilesets** (interface tag & space sets) | [kenney.nl/assets](https://kenney.nl/assets) | CC0 | Rusted bulkheads, vault doors, rigid 90° architecture for the terraforming silo. |
| **QnD001 Assets** | [opengameart.org](https://opengameart.org/content/qnd001-assets) | Check per-asset | Quick-and-dirty sci-fi prop set for set dressing the silo interior. |

---

## 4. UI / HUD (GDD §3–4 — Heat, Energy, Hull gauges; radiation UI scramble)

| Asset | Source | License | Fits |
|---|---|---|---|
| **Kenney — UI Pack: Sci-Fi** | [kenney.nl](https://kenney.nl/assets/ui-pack-sci-fi) | CC0 | **Top pick.** 130 assets: buttons, panels, cursors, **progress bars** (5 colors) + 2 bonus fonts. Progress bars = Heat/Energy/Hull gauges out of the box. |
| **Kenney — UI Pack** | [kenney.nl](https://kenney.nl/assets/ui-pack) | CC0 | General UI fallback for hub/menus. |
| **Kenney — Fonts** | [kenney.nl/assets](https://kenney.nl/assets) | CC0 | Pixel/console fonts for telemetry readouts. |

---

## 5. Audio (GDD §3–4, §7)

### 5.1 Sound Effects

| Asset | Source | License | Fits |
|---|---|---|---|
| **Kenney — Impact Sounds** | [kenney.nl/assets](https://kenney.nl/assets/category:Audio) | CC0 | Block breaks, cave-in debris, hull damage. |
| **Kenney — Sci-fi Sounds** | [kenney.nl/assets](https://kenney.nl/assets/category:Audio) | CC0 | Drill whir, thrusters, bombs, UI/telemetry beeps. |
| **Kenney — Interface Sounds** | [kenney.nl/assets](https://kenney.nl/assets/category:Audio) | CC0 | Menu/hub UI clicks, upgrade confirms. |
| **Kenney — Digital / UI Audio** | [kenney.nl/assets](https://kenney.nl/assets/category:Audio) | CC0 | Scanner pings, radiation/telemetry glitch cues. |
| **Freesound — CC0 filtered** | [freesound.org](https://freesound.org) | CC0 (filter!) | Gap-fill specific one-offs (drill loop, gas hiss). **Filter to CC0** or you inherit attribution duties. |
| **LittleRobotSoundFactory — Sci-Fi SFX Library** | [freesound.org](https://freesound.org/people/LittleRobotSoundFactory/packs/16689/) | Check pack license | Cohesive sci-fi library if a single source is preferred. |

### 5.2 Music & Ambience

| Asset | Source | License | Fits |
|---|---|---|---|
| **Loopable Dungeon Ambience** | [opengameart.org](https://opengameart.org/content/loopable-dungeon-ambience) | Check per-asset | Low wind + water drips → deep-dig tension bed. |
| **Ambience Pack 1 — Sci-Fi Horror** | [opengameart.org](https://opengameart.org/content/ambience-pack-1-sci-fi-horror) | Check per-asset | 5 loopable dark sci-fi tracks → The Mantle / The Ruins dread. |
| **OpenGameArt — CC0 Music collection** | [opengameart.org](https://opengameart.org/content/cc0-music-0) | CC0 | Browse for menu/hub theme + biome loops. |
| **OpenGameArt — Space music theme** | [opengameart.org](https://opengameart.org/content/audiomusicspace) | Mixed — check | Escape/launch sequence (GDD §7 climax). |

---

## 6. Suggested Asset Loadout by Build Phase

Mirrors the GDD's prototype phasing so art never blocks code.

- **Phase 1 (Grid & Movement):** Kenney *Pixel Platformer Blocks* (placeholder terrain) + a robot/mech sprite for the rig + Kenney *Particle Pack* (thruster flame).
- **Phase 2 (Digging / Heat):** Kenney *UI Pack: Sci-Fi* (Heat/Energy/Hull bars) + Kenney *Impact* & *Sci-fi Sounds* (drill, breaks).
- **Phase 3 (ProcGen — Dirt/Rock/Ore):** *Cave Tileset by xvideosman* (Dirt/Stone/Gold Ore) and/or *OPP2017 Cave* set, recolored Martian red.
- **Phase 4 (Game Loop / Hub):** Kenney *UI Pack* (hub menus) + *200+ CC0 Spaceship Sprites* (crashed ship) + Kenney *Interface Sounds*.
- **Phase 5 (Physics Hazards / Cave-ins):** Kenney *Particle Pack* (dust/debris) + *Impact Sounds* (collapse).
- **Endgame (The Ruins):** Kenney sci-fi/metal tilesets + *Ambience Pack 1* for the silo and launch.

---

## 7. Attribution Workflow

1. Keep a `CREDITS.txt` (or `ATTRIBUTION.md`) in the project root from day one.
2. **CC0 assets:** no obligation, but list them anyway — it documents provenance and protects against future license disputes.
3. **CC-BY / OGA-BY / GPL assets:** record **author name, asset title, source URL, and license** for each. OpenGameArt can auto-generate a credits file for collections (e.g. its `CREDITS.TXT` export).
4. When you modify a CC0/CC-BY asset (e.g. Mars recolor), note it as "modified from <source>."
5. Re-verify each per-asset license at download time — OpenGameArt licenses are set per upload and occasionally differ from what a listing page implies.

---

## 8. Open Gaps / Decisions Needed

- ~~**No off-the-shelf Mars tileset** in CC0 — plan to recolor a cave/dirt set or commission custom biome tiles.~~ **Resolved:** Martian block tiles are now baked procedurally from hand-tuned palettes via `_tools/make_mars_tiles.py` → `assets/generated/mars_*.png` (rusty Crust regolith deepening to volcanic Mantle basalt + dusty permafrost ice; ore keeps the CC0 cyan gem for vein readability). Re-run the tool to retune the palette. *(Custom hand-painted tiles still an option later.)*
- **The rig sprite** is the brand of the game — placeholder now, but budget for a bespoke sprite + animation set.
- **The Ruins** rigid-architecture look may need a dedicated sci-fi dungeon tileset beyond Kenney's space sets; evaluate during Phase planning.
- **Cohesion risk:** mixing Kenney + OpenGameArt + itch sources can clash visually. Mitigate by standardizing on one palette (e.g. DawnBringer-32, which OPP2017 already uses) and recoloring everything to it.

---

*Sources consulted: kenney.nl, opengameart.org, itch.io, freesound.org. Licenses verified per-page where noted; re-confirm at download time.*
