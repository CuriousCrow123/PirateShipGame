---
title: "feat: Edge Tiles and Phase C Water Shader Polish"
type: feat
status: completed
date: 2026-04-04
deepened: 2026-04-04
---

# Edge Tiles and Phase C Water Shader Polish

## Enhancement Summary

**Deepened on:** 2026-04-04
**Research agents used:** gc-godot-architecture-reviewer, gc-godot-performance-reviewer, gc-resource-safety-reviewer, gc-godot-timing-reviewer, gc-code-simplicity-reviewer, gc-pattern-recognition-specialist, gc-best-practices-researcher, godot-patterns skill

### Key Improvements
1. **Dropped C5 (scene extraction)** — YAGNI. Only one consumer exists (`main.tscn`). Extract when a boat or second water body needs it.
2. **Merged C1–C4 into a single step** — all deferred shader blocks can be uncommented, moved, and wired in one pass with one test cycle.
3. **Added `generate_mipmaps = false`** to all new NoiseTexture2D sub-resources for consistency with existing noise textures.
4. **Fixed load_steps** — current material has incorrect count (8 vs correct 7); after Phase C it should be 14.

### New Considerations Discovered
- NoiseTexture2D generates asynchronously — first 1–3 frames may show static caustics (cosmetic, acceptable)
- Sub-resource ordering in `.tres` is critical: each FastNoiseLite must be declared before its NoiseTexture2D
- TileSet `x:y/0 = 0` syntax has an editor tooltip bug (#83877) showing wrong coordinate order — the serialized format is correct
- 7 texture samples per fragment is safe (16 minimum guaranteed by OpenGL ES 3.0 / Vulkan)

---

## Overview

Complete the water shader prototype by adding edge/corner tiles for visible foam at water borders, then enable the three deferred shader features (specular highlights, random fade, caustic highlights). This finishes all remaining items from the [original plan](2026-04-04-feat-pixel-water-shader-prototype-plan.md).

## Problem Statement / Motivation

The foam shader code is complete and working, but the TileMap only contains center tiles (atlas 1,20 — solid black). Since `foamHeight = texture(TEXTURE, UV).r * var_VertexColor.x`, and center tiles have R=0 everywhere, foam is invisible. Adding edge tiles with baked gradients makes foam appear at water-land borders — the key visual that says "this is a shoreline."

The deferred shader features (specular, fade, caustic highlights) add visual depth that makes the water feel alive rather than flat.

## Proposed Solution

### Phase A: Edge Tiles (MVP completion)

Register 8 edge/corner tile types from the atlas and paint them around the water border. The tile atlas (`WaterTilesOffsetWithBlur.png`) has baked grayscale gradients — bright pixels near edges fade to dark toward centers. These gradients drive the foam shader.

#### Atlas Coordinate Map

From the original repo's TileSet (terrain peering bits indicate which corners have water):

| Position | Water corners | Atlas coord | Tile_data encoding (int1, int2) |
|----------|--------------|-------------|--------------------------------|
| Center | all 4 | (1, 20) | 65536, 20 |
| Top edge | BR + BL | (1, 5) | 65536, 5 |
| Bottom edge | TL + TR | (1, 6) | 65536, 6 |
| Left edge | BR + TR | (0, 3) | 0, 3 |
| Right edge | BL + TL | (1, 3) | 65536, 3 |
| Top-left corner | BR only | (0, 0) | 0, 0 |
| Top-right corner | BL only | (1, 0) | 65536, 0 |
| Bottom-left corner | TR only | (0, 1) | 0, 1 |
| Bottom-right corner | TL only | (1, 1) | 65536, 1 |

> **Note:** These atlas coordinates are at rows 0, 1, 3, 5, 6 in the texture — all of which have proper baked gradients (NOT the hard binary edges at row 20). Row 20 is only for the solid center tile.

> **No animation for now.** The atlas interleaves animation frames at even/odd columns (10 frames per tile, separation=1). We register only the first frame at the base coordinate.

#### Research Insights

**TileSet atlas registration format:**
- The `x:y/0 = 0` syntax means: atlas column `x`, row `y`, alternative tile `0`, tile data flags `0` (all defaults)
- Coordinates must be within texture bounds (23 columns × 22 rows for a 368×352 atlas at 16×16)
- Known editor tooltip bug [#83877](https://github.com/godotengine/godot/issues/83877) shows coordinates in wrong order — the serialized format is correct

**References:**
- [TileSetAtlasSource docs](https://docs.godotengine.org/en/stable/classes/class_tilesetatlassource.html)
- [Using TileSets guide](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html)

#### TileSet Registration

Add 8 entries to the `TileSetAtlasSource` in `scenes/main.tscn`:

```ini
[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_water"]
texture = ExtResource("2_tiles_tex")
0:0/0 = 0
0:1/0 = 0
0:3/0 = 0
1:0/0 = 0
1:1/0 = 0
1:3/0 = 0
1:5/0 = 0
1:6/0 = 0
1:20/0 = 0
```

#### TileMap Painting

For the 22x14 grid (cells 0,0 to 21,13), replace border tiles:

- **Row 0:** top-left corner at (0,0), top edge at (1,0)–(20,0), top-right corner at (21,0)
- **Row 13:** bottom-left corner at (0,13), bottom edge at (1,13)–(20,13), bottom-right corner at (21,13)
- **Column 0, rows 1–12:** left edge
- **Column 21, rows 1–12:** right edge
- **Interior (1,1)–(20,12):** center tiles (unchanged)

Generate tile_data inline (one-time operation for a fixed grid), encoding each cell as 3 int32 values:
- `int0 = cell_x | (cell_y << 16)`
- `int1 = source_id | (atlas_x << 16)` — source_id=0 for all
- `int2 = atlas_y | (alt << 16)` — alt=0 for all

### Phase C: Enable All Deferred Shader Features

Enable caustic highlights, random fade, and specular highlights in a single pass. The actual work is: uncomment 3 blocks of uniforms, uncomment 3 blocks of fragment code, move the specular block above the water mix line, fix one variable reference, and wire resources in the material `.tres`.

#### Shader Edits (`water_surface.gdshader`)

1. **Uncomment** the `CausticHighlight*` uniforms (lines 26–28) and fragment code (lines 75–77)
2. **Uncomment** the `RandomFade*` uniforms (lines 31–34) and fragment code (lines 79–82)
3. **Uncomment** the `Specular*` uniforms (lines 38–44) and fragment code (lines 87–103)
4. **Move** the specular block (currently after `withWater` mix) to just before `withWater` — so the order matches the reference: caustic → highlight → fade → specular → water mix → foam
5. **Fix** the specular masking: change `ceil(causticResult.a)` to `ceil(fadedAlpha)` so specular is correctly masked by the faded caustic alpha

> **Why reorder?** The reference shader applies specular BEFORE mixing with water color, and masks specular by `ceil(fadedAlpha)` (from the random fade step). The current code has specular AFTER water mix using `ceil(causticResult.a)`. Moving one block up and renaming one variable is the fix — not a major restructure.

#### Research Insights — Shader Compositing

**Correct layer order (confirmed by best-practices research):**
1. Caustic base → 2. Caustic highlights → 3. Random fade → 4. Specular → 5. Water mix → 6. Foam

This follows standard Porter-Duff compositing: caustics are floor-projected light, specular is surface reflections (above caustics), foam is a physical surface feature (above everything).

**Performance at 7 texture samples:**
- OpenGL ES 3.0 guarantees 16 fragment samplers minimum. Vulkan is typically 16+.
- 7 independent reads at 320×180 (57,600 fragments) is trivially fast even on integrated GPUs.
- The only dependent read chain is MovementNoise → CausticTexture (noise UV feeds caustic UV). This already exists and is not made worse.
- No performance cliff at 7 or 8 samples.

**References:**
- [Khronos OpenGL Wiki — Sampler limits](https://www.khronos.org/opengl/wiki/Sampler_(GLSL))
- [CanvasItem shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)

#### Material Edits (`water_surface_material.tres`)

Add 1 ext_resource and 6 sub_resources (3 FastNoiseLite + 3 NoiseTexture2D). Update `load_steps` from 8 to **14**.

**CRITICAL: Sub-resource ordering** — each FastNoiseLite must be declared BEFORE the NoiseTexture2D that references it. If the NoiseTexture2D block appears first, Godot fails to parse the file.

```ini
[gd_resource type="ShaderMaterial" load_steps=14 format=3]

[ext_resource type="Shader" path="res://shaders/water_surface.gdshader" id="1_shader"]
[ext_resource type="Texture2D" path="res://textures/CausticTexture.png" id="2_caustic"]
[ext_resource type="Texture2D" path="res://textures/CausticTextureHighlights.png" id="3_highlight"]

# --- Existing noise sub-resources (movement, foam) ---
# ... (unchanged) ...

# --- Random fade noise ---
[sub_resource type="FastNoiseLite" id="FastNoiseLite_fade"]
frequency = 0.001
fractal_octaves = 4
fractal_lacunarity = 4.0
fractal_gain = 1.0

[sub_resource type="NoiseTexture2D" id="NoiseTexture2D_fade"]
generate_mipmaps = false
seamless = true
noise = SubResource("FastNoiseLite_fade")

# --- Specular noise 1 ---
[sub_resource type="FastNoiseLite" id="FastNoiseLite_spec1"]
frequency = 0.001
fractal_octaves = 4
fractal_lacunarity = 4.0
fractal_gain = 1.0

[sub_resource type="NoiseTexture2D" id="NoiseTexture2D_spec1"]
generate_mipmaps = false
seamless = true
noise = SubResource("FastNoiseLite_spec1")

# --- Specular noise 2 ---
[sub_resource type="FastNoiseLite" id="FastNoiseLite_spec2"]
seed = 1
frequency = 0.0012
fractal_octaves = 4
fractal_lacunarity = 4.0
fractal_gain = 1.0

[sub_resource type="NoiseTexture2D" id="NoiseTexture2D_spec2"]
generate_mipmaps = false
seamless = true
noise = SubResource("FastNoiseLite_spec2")

[resource]
# ... existing params ...
shader_parameter/CausticHighlightTexture = ExtResource("3_highlight")
shader_parameter/CausticHighlightColour = Color(1, 1, 1, 0.792157)
shader_parameter/RandomFadeNoise = SubResource("NoiseTexture2D_fade")
shader_parameter/SpecularNoiseTextureMoving1 = SubResource("NoiseTexture2D_spec1")
shader_parameter/SpecularNoiseTextureMoving2 = SubResource("NoiseTexture2D_spec2")
```

> **Parameter values:** The shader defaults (SpecularScaleMoving=0.007, SpecularSpeed=0.03, SpecularThreshold=0.15) come from the original repo's actual material, NOT the reference document (which lists 0.07, 0.5, 0.5). The repo values are the correct tuned values.

#### Research Insights — NoiseTexture2D

**Async generation:** NoiseTexture2D generates its image on a background thread ([#90661](https://github.com/godotengine/godot/issues/90661), [#105261](https://github.com/godotengine/godot/issues/105261)). On the first 1–3 frames, noise textures may sample as blank:
- `MovementNoise` blank → caustics appear static briefly
- `FoamNoiseTexture` blank → foam calculation degenerates briefly

**Verdict:** Cosmetic-only artifact, invisible if the game has any loading transition. Not worth adding `await` guards for a prototype.

**Best practice:** Set `generate_mipmaps = false` and keep dimensions at default 512×512 or smaller. This matches the existing `NoiseTexture2D_movement` pattern and speeds up generation.

## Technical Considerations

### Tile_data encoding

Each tile in `PackedInt32Array` is 3 consecutive int32 values:
- `int0`: cell position — `cell_x | (cell_y << 16)`, signed 16-bit
- `int1`: source + atlas_x — `source_id | (atlas_x << 16)`
- `int2`: atlas_y + alt — `atlas_y | (alt_id << 16)`

Example: cell (0, 0) with atlas (0, 0) → `0, 0, 0`
Example: cell (1, 0) with atlas (1, 5) → `1, 65536, 5`

### Noise texture filter hints

All 3 new NoiseTexture2D resources are used for UV distortion/math — they need `filter_linear` hints in the shader (already set in the deferred uniform declarations). Player-visible textures like `CausticHighlightTexture` use `filter_nearest`.

## System-Wide Impact

- **Signal chain**: None — purely visual changes. No signals, no autoloads.
- **Error propagation**: No new failure points. Tile registration is declarative.
- **State lifecycle risks**: None — no runtime mutation (NoiseTexture2D sub-resources are read-only).
- **Scene interface parity**: N/A — still the only scene.
- **Integration test scenarios**: Visual-only; manual inspection via MCP run/debug cycle.

## Acceptance Criteria

### Phase A: Edge Tiles
- [x] 8 edge/corner tile types registered in TileSetAtlasSource (atlas coords from mapping table above)
- [x] TileMap border cells use correct edge/corner tiles (4 corners, 4×20 top/bottom edges, 4×12 left/right edges)
- [x] Foam renders as an animated gradient band at water-to-land borders
- [x] No foam visible on interior center tiles
- [x] Foam wave animation is smooth (quantized pixel-art steps, not binary on/off)

### Phase C: Shader Polish
- [x] Caustic highlight layer blends brighter caustic overlay — wire `CausticTextureHighlights.png`
- [x] Random fade breaks up caustic tiling repetition — wire NoiseTexture2D (frequency=0.001, octaves=4)
- [x] Specular highlights render as moving bright spots over water — wire 2 NoiseTexture2D resources
- [x] Fragment shader order matches reference: caustic → highlight → fade → specular → water → foam
- [x] All 3 NoiseTexture2D resources use FastNoiseLite configs from original repo, with `generate_mipmaps = false`
- [x] `load_steps` in material .tres is correct (14)
- [x] Zero errors in Godot debug output
- [x] `gdformat --check . && gdlint .` passes

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Atlas coordinates produce wrong gradient direction | Medium | Verify visually after painting — run project and inspect foam edges |
| Shader restructuring breaks existing caustic rendering | Low | Commit edge tiles first, then shader changes in a separate commit |
| Specular/fade interaction produces unexpected alpha | Low | All code is from the reference; test after enabling |
| NoiseTexture2D first-frame blank | Low | Cosmetic only, 1–3 frames; acceptable for prototype |
| Sub-resource ordering in .tres | High if wrong | FastNoiseLite MUST precede its NoiseTexture2D — follow existing pattern |

## Implementation Checklist

### Phase A: Edge Tiles

- [x] Register 8 edge/corner tiles in TileSetAtlasSource in `scenes/main.tscn`
- [x] Generate new tile_data with edge/corner tiles on border, center tiles on interior
- [x] Update TileMap in `scenes/main.tscn` with new tile_data
- [x] Run project and verify foam at edges
- [x] Commit: `feat(water): add edge tiles for foam visibility`

### Phase C: Enable Deferred Shader Features

- [x] Uncomment all deferred uniform blocks in `water_surface.gdshader` (highlights, fade, specular)
- [x] Uncomment all deferred fragment code blocks
- [x] Move specular block before water mix; fix masking to use `ceil(fadedAlpha)`
- [x] Rewrite `water_surface_material.tres` — add `CausticTextureHighlights.png` ext_resource, 3 NoiseTexture2D + 3 FastNoiseLite sub-resources (all with `generate_mipmaps = false`), set `load_steps=14`
- [x] Run project and verify all visual layers work together
- [x] Run `gdformat --check . && gdlint .`
- [x] Commit: `feat(water): enable specular, fade, and caustic highlight layers`

### Final

- [x] Update plan status to completed
- [x] Update [water-shader-guide.md](../water-shader-guide.md) to remove "deferred features" section (they're now enabled)

## Sources & References

- **Original plan:** [2026-04-04-feat-pixel-water-shader-prototype-plan.md](2026-04-04-feat-pixel-water-shader-prototype-plan.md)
- **Original repo TileSet:** `jess-hammer/2d-pixel-water-shader-godot/Assets/Water/WaterTileSet.tres` — terrain peering bits define tile types
- **Original repo WaterMaterial:** `jess-hammer/2d-pixel-water-shader-godot/Assets/Water/WaterMaterial.tres` — FastNoiseLite configs for all noise textures
- **Solution docs:** [tilemap-shader-color-gotcha.md](../solutions/tilemap-shader-color-gotcha.md), [shared-resource-mutation.md](../solutions/shared-resource-mutation.md)

### Godot Documentation
- [TileSetAtlasSource](https://docs.godotengine.org/en/stable/classes/class_tilesetatlassource.html)
- [Using TileSets](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html)
- [CanvasItem Shader Reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)

### Godot Issues
- [#83877](https://github.com/godotengine/godot/issues/83877) — TileSet editor tooltip shows wrong coordinate order
- [#90661](https://github.com/godotengine/godot/issues/90661) — NoiseTexture2D async generation
- [#105261](https://github.com/godotengine/godot/issues/105261) — NoiseTexture2D.get_image() returns null in _ready()
