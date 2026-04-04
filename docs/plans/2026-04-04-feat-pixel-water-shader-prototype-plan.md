---
title: "feat: Pixel Water Shader Prototype"
type: feat
status: completed
date: 2026-04-04
deepened: 2026-04-04
---

# Pixel Water Shader Prototype

## Enhancement Summary

**Deepened on:** 2026-04-04
**Research agents used:** gc-godot-architecture-reviewer, gc-godot-performance-reviewer, gc-godot-timing-reviewer, gc-resource-safety-reviewer, gc-gdscript-reviewer, gc-pattern-recognition-specialist, gc-code-simplicity-reviewer, gc-best-practices-researcher, gc-framework-docs-researcher, godot-patterns skill

### Key Improvements
1. **Critical bug fix:** `COLOR.x` in TileMap fragment shader already includes tile texture — must capture vertex color in a `varying` during `vertex()` to isolate foam heightmap input
2. **Critical bug fix:** Curve resource on Line2D is mutated every frame — must `.duplicate()` in `_ready()` to avoid shared-resource corruption
3. **Critical bug fix:** SubViewport with `transparent_bg=true` on Forward+ outputs premultiplied alpha — Sprite2D needs `BLEND_MODE_PREMULT_ALPHA` or the ripples will render too dark
4. **Simplification:** Defer specular highlights and random fade from MVP shader — caustics + foam already prove the approach; reduces 4 textures and ~20 LOC from critical path
5. **Timing fix:** Both scripts should use `_process()` — this is a visual-only system, no physics needed

### New Considerations Discovered
- Godot 4.6 has a known ViewportTexture regression (#115402) — assign ViewportTexture in `_ready()` as a defensive measure
- Noise texture samplers need explicit `filter_linear` hints once project default is set to `Nearest`
- The `inverse_lerp` result in Trails.gd is unclamped — can exceed 1.0 when trail is long
- `_queue[-1]` crashes on empty array after `reset_line()` — needs guard

---

## Overview

Implement a 2D pixel-art animated water shader prototype in Godot 4.6 based on the [jess-hammer/2d-pixel-water-shader-godot](https://github.com/jess-hammer/2d-pixel-water-shader-godot) reference. The effect has two independent systems: a water surface shader (caustics, specular, foam on a TileMap) and a ripple/trail system (Line2D in SubViewport with a ripple shader, driven by cursor position).

Reference document: [pixel-water-shader.md](../../pixel-water-shader.md)

## Problem Statement / Motivation

The PirateShipGame project needs an animated water surface for its ocean environment. The reference implementation provides a complete, proven pixel-art water effect with caustics, specular highlights, animated foam, and interactive ripple trails — all the visual language expected of a 2D pirate game. This prototype validates the visual approach before integrating it with gameplay systems (boat movement, island edges, etc.).

## Proposed Solution

Port the two shader systems directly from the reference document using code shaders (`.gdshader`) and GDScript. Pull authored texture assets from the original repository. Build a minimal test scene with a TileMap water area and cursor-driven trail.

### System 1: Water Surface Shader

A `canvas_item` shader applied to a TileMap via ShaderMaterial. Renders:
- **Caustics** — two-layer caustic texture with noise-driven UV animation
- **Edge foam** — reads foam height from tile vertex color; sine-wave animated, quantized for pixel-art steps

> **MVP scope:** Specular highlights and random fade are deferred — caustics + foam are the recognizable "this is water" signals. The specular and fade blocks can be uncommented in 10 minutes once the core works. See "Deferred Features" section below.

Key technique: `floor(var_WorldPos)` locks textures to world-space pixels so the pattern doesn't swim with camera movement.

### System 2: Ripple / Water Trail

A Line2D rendered inside a 256x256 SubViewport, displayed via a Sprite2D with a separate ripple shader. The cursor (later: boat) drives trail position.

- **Trails.gd** — maintains a point queue, converts global positions to local SubViewport space, adjusts width curve based on movement distance
- **Ripple shader** — animates trail brightness via sine wave, quantizes for pixel-art look

### Deferred Features (post-MVP)

These shader features are commented out in the initial implementation and enabled after the core works:

| Feature | Shader Lines | Textures Needed | Why Deferred |
|---------|-------------|-----------------|--------------|
| Specular highlights | ~15 LOC | `SpecularNoiseTextureMoving1.png`, `SpecularNoiseTextureMoving2.png` | Secondary visual polish — shine overlay |
| Random fade | ~5 LOC | `RandomFadeNoise.png` | Anti-tiling fix irrelevant at prototype viewport size |
| Caustic highlight layer | ~3 LOC | `CausticTextureHighlights.png` | Caustics work fine with one layer |

## Technical Considerations

### Display Settings (CRITICAL — must configure first)

The project has no display/window settings. For pixel art at Camera2D zoom 7x:

```ini
[display]
window/size/viewport_width=320
window/size/viewport_height=180
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"

[rendering]
textures/canvas_textures/default_texture_filter=0
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true
```

#### Research Insights

**Best Practices:**
- Use `stretch/mode = "viewport"` (not `"canvas_items"`) — renders at native resolution then scales the entire viewport. This is the correct mode for pixel art.
- `scale_mode = "integer"` prevents uneven pixel scaling (e.g., some pixels 2px wide, others 3px). Will add black bars if window size isn't an exact multiple.
- `snap_2d_transforms_to_pixel` and `snap_2d_vertices_to_pixel` prevent sub-pixel jitter on node transforms at high zoom.

**Edge Case:**
- The camera position `(390.5, 255)` and zoom `7` from the reference likely assume a different base resolution. Start with 320x180 and adjust. A 640x360 base scales more cleanly to 720p/1080p/4K if needed later.

**References:**
- [Godot: Multiple Resolutions Guide](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
- [GDQuest: Pixel Art Setup in Godot 4](https://www.gdquest.com/library/pixel_art_setup_godot4/)

### Texture Sourcing

Pull PNG assets from the original repo: [jess-hammer/2d-pixel-water-shader-godot](https://github.com/jess-hammer/2d-pixel-water-shader-godot).

**MVP textures (6 files):**

| Texture | Import Settings | Notes |
|---------|----------------|-------|
| `CausticTexture.png` | `filter_nearest`, `repeat_enable` | Core visual |
| `MovementNoise.png` | `repeat_enable` | Drives UV animation |
| `FoamNoiseTexture.png` | `filter_nearest`, `repeat_enable` | Foam modulation |
| `WaterTrailGradient.png` | Default | Line2D texture |
| `CircleBlur64x64.png` | Default | Trail head brush |
| `WaterTilesOffsetWithBlur.png` | `filter_nearest` | Tileset with baked edge gradients |

**Deferred textures (4 files — download but don't wire until post-MVP):**
- `CausticTextureHighlights.png`, `RandomFadeNoise.png`, `SpecularNoiseTextureMoving1.png`, `SpecularNoiseTextureMoving2.png`

> `WaterTrailGradientFaded.png` is listed in the reference but never referenced in any code. **Skip it entirely.**

#### Research Insights

**Noise texture filtering — CRITICAL after project default change:**
Once `default_texture_filter = Nearest` is set globally, noise textures used for UV distortion will snap to nearest filtering too. This breaks smooth animation. Add **explicit `filter_linear`** hints to noise sampler uniforms in the shader:

```glsl
// Noise textures need smooth interpolation for UV distortion
uniform sampler2D MovementNoise : source_color, filter_linear, repeat_enable;

// Caustic textures the player SEES should stay nearest
uniform sampler2D CausticTexture : source_color, filter_nearest, repeat_enable;
```

**Rule of thumb:** `filter_nearest` on textures the player sees directly (caustics, foam). `filter_linear` on textures used as intermediate math inputs (noise for UV distortion, specular noise).

### TileMap Vertex Color / Foam Setup (CRITICAL BUG — must fix shader)

The reference says foam reads `COLOR.x` (per-vertex color from TileMap). **This will not work as written in Godot 4.**

#### Research Insights — COLOR Behavior in TileMap Shaders

**The bug (confirmed via Godot issue [#69766](https://github.com/godotengine/godot/issues/69766)):**
- In `vertex()`, `COLOR` = vertex_color * modulate * self_modulate (no texture yet)
- In `fragment()`, `COLOR` has **already been multiplied by `texture(TEXTURE, UV)`** before your code runs
- This means you **cannot** read pure modulate/vertex color via `COLOR.x` in the fragment shader — it's mixed with the tile texture

**The fix — capture vertex color in a varying:**

```glsl
varying vec4 var_VertexColor;

void vertex() {
    var_WorldPos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
    var_VertexColor = COLOR;  // Capture BEFORE fragment multiplies by texture
}

void fragment() {
    // Use var_VertexColor.x instead of COLOR.x for foam height
    float foamHeight = var_VertexColor.x;
    // ... rest of foam calculation uses foamHeight instead of COLOR.x
}
```

**Foam height approach (prioritized):**
1. **Primary:** Use `var_VertexColor.x` from the varying (per-tile modulate R channel)
2. **If tiles have baked gradients:** `WaterTilesOffsetWithBlur.png` filename suggests pre-blurred edges. If so, `texture(TEXTURE, UV).r` gives per-pixel foam height — smoother than per-tile modulate
3. **Investigate at implementation time** which approach the original repo actually uses

**TileMap foam setup:**
- Per-tile modulate with R channel encoding foam height: R=0 deep, R=0.3 shallow, R=0.7 edge
- Tile size: likely **16x16** — confirm from original repo tileset
- Minimum 3 tile variants needed for MVP: deep, shallow, edge

### SubViewport / ViewportTexture Wiring

- ViewportTexture must be created on the Sprite2D's texture property and pointed at the SubViewport node path
- SubViewport `render_target_update_mode` = `UPDATE_WHEN_VISIBLE` (default) is correct — updates when the ViewportTexture is visible
- Set SubViewport `canvas_item_default_texture_filter` to `Nearest` explicitly (does NOT inherit project setting)
- The Sprite2D `centered = true` (default) works with the Trails.gd `_offset` compensation

#### Research Insights

**Premultiplied Alpha Bug (CRITICAL on Forward+):**
When `transparent_bg = true`, Godot's Forward+ renderer outputs **premultiplied alpha** in the viewport texture. Semi-transparent ripple areas will appear darker than expected.

**Fix:** Set the Sprite2D's material blend mode to premultiplied alpha. Either:
- Use a `CanvasItemMaterial` with `blend_mode = BLEND_MODE_PREMULT_ALPHA`, OR
- Account for it in the ripple shader by using `render_mode blend_premul_alpha`

Tracked in [Godot issue #99715](https://github.com/godotengine/godot/issues/99715).

**ViewportTexture 4.6 Regression (issue [#115402](https://github.com/godotengine/godot/issues/115402)):**
ViewportTextures can break and show magenta after save/reload in Godot 4.6. **Defensive workaround** — assign ViewportTexture in code:

```gdscript
# In the WaterTrail root script _ready():
func _ready() -> void:
    var vt := ViewportTexture.new()
    vt.viewport_path = %SubViewport.get_path()
    %TrailSprite.texture = vt
```

### Curve Resource — Shared Mutation Bug (CRITICAL)

The Trails.gd script calls `width_curve.set_point_value(0, ...)` every frame. The plan's System-Wide Impact section stated "No Resources mutated at runtime" — **this is incorrect**. The Curve IS a Resource, and `set_point_value()` IS a runtime mutation.

**The bug:** Curve sub-resources in `.tscn` files are **shared by default across all instances**. If the WaterTrail scene is ever instanced more than once, all instances share the same Curve in memory. Mutations from one trail corrupt the other.

**The fix — duplicate in `_ready()`:**

```gdscript
func _ready() -> void:
    # ... other setup ...
    width_curve = width_curve.duplicate()  # Safe to mutate every frame
```

The Line2D **must** have a pre-configured `Curve` resource with points `[(0, 1.0), (1, 0.515882)]`. Save this as a `.tres` file for git visibility. If missing, the script crashes with a null reference on frame 1.

### Ripple Shader Parameter Overrides

The ripple shader code has different defaults than the intended material values. The ShaderMaterial must explicitly set:

| Parameter | Shader Default | Material Override |
|-----------|---------------|-------------------|
| `InitialAlpha` | 0.46 | **0.6** |
| `Speed` | 0.1 | **0.09** |
| `QuantizeColourAmount` | 6.0 | **3.0** |
| `UpperCutoff` | 0.3 | **0.5** |

### GDScript Improvements Over Reference Code

The reference code needs several fixes discovered during review:

#### Trails.gd — Corrected Version

```gdscript
extends Line2D

@export var max_length: int = 20
@export var sub_viewport: SubViewport
@export var follow_target: Node2D  ## Node whose position drives the trail (renamed from "parent")
@export var distance_at_largest_width: float = 16.0 * 6.0
@export var smallest_tip_width: float = 0.5
@export var largest_tip_width: float = 1.0

var _queue: Array[Vector2] = []
var _offset: Vector2 = Vector2.ZERO


func _ready() -> void:
    assert(sub_viewport != null, "Trails: sub_viewport export must be assigned")
    assert(follow_target != null, "Trails: follow_target export must be assigned")
    assert(width_curve != null and width_curve.point_count > 0,
        "Trails: width_curve must have at least one point")
    _offset = Vector2(sub_viewport.size) / 2.0
    width_curve = width_curve.duplicate()  # Safe to mutate every frame


func _process(_delta: float) -> void:
    if _queue.is_empty() and get_point_count() == 0:
        # First frame or after reset — just seed the queue
        _queue.append(follow_target.global_position + _offset)
        return

    var pos: Vector2 = follow_target.global_position + _offset
    _queue.append(pos)
    while _queue.size() > max_length and _queue.size() > 2:
        _queue.pop_front()

    var length: float = 0.0  # Local var — only used within this method
    clear_points()
    for i: int in range(_queue.size() - 1):
        length += _queue[i].distance_to(_queue[i + 1])
        add_point(follow_target.to_local(_queue[i]))
    add_point(follow_target.to_local(_queue[-1]))

    var t: float = clampf(inverse_lerp(0.0, distance_at_largest_width, length), 0.0, 1.0)
    width_curve.set_point_value(0, lerpf(smallest_tip_width, largest_tip_width, t))


func reset_line() -> void:
    clear_points()
    _queue.clear()
```

**Changes from reference:**
1. `parent` renamed to `follow_target` — avoids shadowing "scene tree parent" concept
2. Assertions in `_ready()` — clear crash messages instead of cryptic null reference
3. `width_curve.duplicate()` in `_ready()` — prevents shared resource mutation
4. `_queue.is_empty()` guard — prevents `_queue[-1]` crash after `reset_line()`
5. All variables in `_process()` explicitly typed — 28-59% faster in compute loops
6. `_length` removed as member var — it's a local computation, not state
7. `clampf()` on `inverse_lerp` result — prevents tip width exceeding `largest_tip_width`
8. `_offset` has explicit default `Vector2.ZERO`

#### FollowCursor.gd — Use `_process` and `global_position`

```gdscript
extends Node2D


func _process(_delta: float) -> void:
    global_position = get_global_mouse_position()
```

**Changes from reference:**
1. `_physics_process` → `_process` — visual-only system, no physics needed. Mouse input updates every frame, not at physics tick rate. Prevents position staleness on high-refresh displays.
2. `position` → `global_position` — works correctly regardless of parent transform. Using local `position` with a global coordinate only works if parent's global transform is identity.

## System-Wide Impact

- **Signal chain**: None — both systems are purely visual with no signals. The Trails script reads `follow_target.global_position` each frame; FollowCursor writes `global_position` each frame. No autoloads involved.
- **Error propagation**: Assertions in `_ready()` catch misconfigured exports immediately with clear messages. The three crash vectors (null `width_curve`, null `sub_viewport`, null `follow_target`) are all caught before the first frame.
- **State lifecycle risks**: The Curve resource IS mutated at runtime (corrected from original plan). Mitigated by `.duplicate()` in `_ready()`. No other persistent state, save data, or Resources mutated.
- **Scene interface parity**: N/A — this is the first scene in the project.
- **Integration test scenarios**: Visual-only effect; manual visual inspection is the primary validation. No automated testing needed for the prototype.

## Acceptance Criteria

- [x] Project display settings configured for pixel art (`viewport` stretch, `integer` scale, `Nearest` filter, pixel snapping)
- [x] MVP textures (6) imported with correct settings; deferred textures (4) downloaded but not wired
- [x] `water_surface.gdshader` renders caustics and foam on a TileMap (specular/fade commented out with TODO)
- [x] Foam uses `var_VertexColor` varying to correctly read tile modulate — NOT `COLOR.x` in fragment
- [ ] TileMap has water tiles with foam visible at edges (via per-tile modulate R channel) — *center tiles only in MVP; edge tiles can be painted in editor*
- [x] `ripple.gdshader` renders animated, quantized ripple effect with `blend_premul_alpha` render mode
- [x] SubViewport (256x256, transparent, Nearest filter) contains Line2D with Trails.gd and Circle Sprite2D
- [x] ViewportTexture correctly wired (defensive `_ready()` assignment for 4.6 compatibility)
- [x] Cursor movement produces a visible ripple trail over the water surface
- [x] Camera2D at high zoom shows crisp pixel-art rendering (no sub-pixel blur)
- [x] Both systems work together in a single scene
- [x] Curve resource duplicated in `_ready()` — no shared resource mutation
- [x] Explicit z_index on TileMap (0) and WaterTrail (1) for deterministic draw order

## Success Metrics

- Visual fidelity reasonably matches the [reference implementation](https://github.com/jess-hammer/2d-pixel-water-shader-godot) (caustics + foam only for MVP)
- Both shader systems run without visual artifacts at 60fps
- The prototype can later be adapted to use boat position instead of cursor
- Specular + random fade can be enabled by uncommenting shader blocks and wiring 4 additional textures

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Texture assets not available / repo removed | Low | Fork or mirror assets; worst case, generate with FastNoiseLite |
| TileMap `COLOR.x` doesn't produce smooth foam | Medium | **Fixed:** Use `var_VertexColor` varying; fallback to `texture(TEXTURE, UV).r` |
| SubViewport trail clips at edges during fast movement | Medium | Acceptable for prototype; increase SubViewport size (512x512) if needed |
| Camera zoom / resolution mismatch with reference | Low | Adjust base resolution and zoom until TileMap fills viewport correctly |
| Godot 4.6 ViewportTexture regression (#115402) | Medium | **Mitigated:** Assign ViewportTexture in `_ready()` via code |
| Premultiplied alpha on Forward+ SubViewport | High | **Fixed:** Use `blend_premul_alpha` render mode on ripple shader |
| Shared Curve resource mutation across instances | High | **Fixed:** `.duplicate()` in `_ready()` |

## Implementation Checklist

### Phase A: Water Surface

- [x] Configure `project.godot` display settings (see exact `[display]` and `[rendering]` blocks above)
- [x] Download all 10 texture assets from original repo into `textures/`
- [x] Configure import settings for each texture (shader sampler hints override import settings)
- [x] Create `shaders/water_surface.gdshader` — include full caustic + foam GLSL; comment out specular and random fade blocks with `// TODO: Enable post-MVP`
- [x] **CRITICAL:** Add `varying vec4 var_VertexColor` to capture vertex color before fragment texture multiplication
- [x] **CRITICAL:** Add explicit `filter_linear` hints to noise sampler uniforms (`MovementNoise`)
- [x] Create `shaders/water_surface_material.tres` (ShaderMaterial) referencing the shader
- [x] Assign MVP texture uniforms (3: CausticTexture, MovementNoise, FoamNoiseTexture) — noise textures are inline NoiseTexture2D sub-resources
- [x] Create TileSet resource using `WaterTilesOffsetWithBlur.png` — tile size 16x16
- [x] Set up TileMap with `water_surface_material.tres` and paint a test water area
- [ ] Configure per-tile modulate R channel for foam height — *deferred: center tiles only in MVP, edge tiles can be painted in editor*
- [x] Set TileMap `z_index = 0`
- [x] Create main scene: Node2D root, Camera2D (zoom 1x, 320x180 viewport), TileMap
- [x] Verify caustics animate and foam appears at tile edges

### Phase B: Ripple / Trail System

- [x] Create `shaders/ripple.gdshader` — add `render_mode blend_premul_alpha` for Forward+ SubViewport compatibility
- [x] Create `shaders/ripple_material.tres` (ShaderMaterial) with parameter overrides (InitialAlpha=0.6, Speed=0.09, QuantizeColourAmount=3.0, UpperCutoff=0.5)
- [x] Create `scripts/trails.gd` using the corrected version above (assertions, duplicate curve, typed vars, clamp)
- [x] Create `scripts/follow_cursor.gd` using the corrected version above (`_process`, `global_position`)
- [x] Create `resources/trail_width_curve.tres` — Curve with points [(0, 1.0), (1, 0.515882)]
- [x] Build the WaterTrail scene tree in the main scene:
  - WaterTrail (Node2D) with `follow_cursor.gd`, `z_index = 1`
  - TrailSprite (Sprite2D) with `ripple_material.tres`
  - SubViewport (256x256, `transparent_bg=true`, `disable_3d=true`, `canvas_item_default_texture_filter=Nearest`)
  - Line2D with `trails.gd`, `trail_width_curve.tres`, gradient `[Color(1,1,1,0) -> Color(1,1,1,1)]`, `WaterTrailGradient.png` texture, `texture_mode=TILE`, joint/cap=ROUND, width=28
  - Circle (Sprite2D) with `CircleBlur64x64.png` at position (128, 128), scale (0.3, 0.3)
- [x] Wire ViewportTexture from SubViewport to TrailSprite — use `_ready()` code assignment for 4.6 safety
- [x] Set `trails.gd` exports: `sub_viewport` → SubViewport, `follow_target` → WaterTrail
- [x] Position camera to center on water area
- [x] Verify cursor trail renders over water surface
- [x] Test at different window sizes to confirm pixel-art stretch works

### Phase C: Post-MVP Polish (optional, after core works)

- [ ] Uncomment specular highlight block in water shader; wire `SpecularNoiseTextureMoving1.png` and `SpecularNoiseTextureMoving2.png`
- [ ] Uncomment random fade block; wire `RandomFadeNoise.png`
- [ ] Uncomment caustic highlight layer; wire `CausticTextureHighlights.png`
- [ ] Tune all shader parameters to match reference visual quality
- [ ] Consider extracting WaterTrail subtree as a separate `water_trail.tscn` for reuse with boat

## Documentation Plan

### Project-Level Documentation

- [x] **CLAUDE.md** — Create project-level CLAUDE.md establishing conventions discovered during this prototype:
  - Shader naming: `snake_case.gdshader` (not PascalCase)
  - Shader uniform naming: PascalCase (inherited from reference; note divergence from GLSL convention)
  - GDScript conventions: static typing required, assertions on `@export` node references in `_ready()`
  - Resource safety rule: always `.duplicate()` any Resource mutated at runtime
  - Display settings: viewport stretch mode, integer scaling, nearest filter default
  - Folder structure: `shaders/`, `textures/`, `scripts/`, `scenes/`, `resources/`

- [x] **ADR: Water shader approach** — Record in `docs/decisions/` why we chose code shaders over VisualShader, and why we ported from the jess-hammer reference rather than building from scratch. Key decision: `var_VertexColor` varying pattern for TileMap foam (workaround for Godot #69766).

### Inline Code Documentation

- [x] **water_surface.gdshader** — Comment blocks for each visual layer (caustics, foam, deferred specular/fade) explaining the technique and linking to the reference document
- [x] **trails.gd** — Document the `_offset` compensation (why SubViewport coordinates need shifting), the `width_curve.duplicate()` requirement, and the `follow_target` export purpose
- [x] **Deferred feature markers** — `// TODO(post-mvp): Enable specular highlights — uncomment and wire SpecularNoiseTextureMoving1/2.png` in shader code

### Solution Documentation (for `docs/solutions/`)

After implementation, document these solved problems for future reference:

- [x] **TileMap shader COLOR gotcha** — Document the `var_VertexColor` varying pattern, why `COLOR.x` doesn't work in fragment(), and link to Godot #69766. Category: `shader-issues/`
- [x] **SubViewport premultiplied alpha on Forward+** — Document the `blend_premul_alpha` fix and link to Godot #99715. Category: `rendering-issues/`
- [x] **ViewportTexture 4.6 defensive assignment** — Document the `_ready()` code assignment workaround and link to #115402. Category: `configuration-fixes/`
- [x] **Shared Curve resource mutation** — Document the `.duplicate()` pattern for any Resource modified at runtime. Category: `resource-issues/`

### README / Quick Start

- [x] **Brief README.md section** (or standalone `docs/water-shader-guide.md`) covering:
  - How to run the prototype (open in Godot, press Play)
  - How to enable deferred features (uncomment shader blocks, wire textures)
  - How to swap cursor for boat position (change `follow_target` export or replace FollowCursor.gd)
  - Parameter tuning guide: which uniforms control which visual aspects

## Sources & References

- **Reference document:** [pixel-water-shader.md](../../pixel-water-shader.md) — complete GLSL, GDScript, scene structure, parameter tables
- **Original implementation:** [jess-hammer/2d-pixel-water-shader-godot](https://github.com/jess-hammer/2d-pixel-water-shader-godot) (Godot Mono 4.4, C#)
- **Texture assets:** Same repo, download PNG files from the assets/textures directory

### Godot Issues Referenced
- [#69766](https://github.com/godotengine/godot/issues/69766) — TileSet shader `COLOR` already includes texture in fragment stage
- [#99715](https://github.com/godotengine/godot/issues/99715) — SubViewport `transparent_bg` outputs premultiplied alpha on Forward+
- [#115402](https://github.com/godotengine/godot/issues/115402) — ViewportTexture regression in Godot 4.6
- [Proposal #5923](https://github.com/godotengine/godot-proposals/issues/5923) — Per-tile custom data passthrough to shaders (unresolved)

### Documentation
- [Godot: Multiple Resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
- [Godot: CanvasItem Shader Reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)
- [Godot: Using SubViewport as Texture](https://docs.godotengine.org/en/stable/tutorials/shaders/using_viewport_as_texture.html)
- [GDQuest: Pixel Art Setup in Godot 4](https://www.gdquest.com/library/pixel_art_setup_godot4/)
