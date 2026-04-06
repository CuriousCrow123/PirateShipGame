---
title: "feat: Water ripple UV distortion via displacement map"
type: feat
status: completed
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-water-ripple-distortion-brainstorm.md
---

# feat: Water ripple UV distortion via displacement map

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 6
**Research agents used:** best-practices-researcher, framework-docs-researcher, godot-architecture-reviewer, godot-performance-reviewer, godot-timing-reviewer, resource-safety-reviewer, pattern-recognition-specialist

### Key Improvements
1. Stamp blending strategy clarified — `blend_mix` for simplicity, additive superposition deferred
2. Material duplication requirement made explicit — each stamp must `.duplicate()` its ShaderMaterial
3. Mine communication architecture locked down — `main.gd` as mediator via signals (call-down-signal-up)
4. Scene cleanup steps made explicit — `sea_mine.tscn`, `main.tscn`, `.uid` sidecars
5. Timing guards added — `_is_detonated` check in `sea_mine._process()`
6. Coordinate mapping simplified — camera-following content root + optional `SCREEN_UV` approach

### New Considerations Discovered
- Stamp material must be duplicated per instance (CLAUDE.md convention + per-stamp uniforms)
- `sea_mine.tscn` must be edited to remove `RippleSprite` node (was missing from plan)
- `.uid` sidecar files must be deleted alongside removed source files
- Mine idle bob wiring needs explicit strategy (main.gd mediator, not direct reference)

---

## Overview

Replace expanding-circular-line ripple effects with actual UV distortion of the water surface. A SubViewport renders displacement stamps (radial gradients encoding direction) at interaction points. The water surface shader reads this as a displacement map, warping caustic and specular patterns when ripples pass — creating a convincing refraction effect from top-down.

(see brainstorm: `docs/brainstorms/2026-04-05-water-ripple-distortion-brainstorm.md`)

## Problem Statement / Motivation

Current ripple effects (ship wake brightness overlay, mine concentric ring lines) are purely cosmetic overlays that don't interact with the water surface. They look like lines drawn on top of water rather than actual water disturbance. Real top-down water ripples should displace the visible surface features (caustics, specular highlights) via UV warping — the standard technique used in shipped indie games.

## Proposed Solution

**Displacement map SubViewport** — the industry-standard "stamp and fade" approach:

1. A SubViewport renders colored displacement stamps at ripple source positions
2. Stamp color encodes displacement direction: R = X offset, G = Y offset, neutral = (0.5, 0.5)
3. The water surface shader samples this SubViewport texture and offsets `worldFloor` before sampling caustics/specular
4. Stamps fade over time via alpha decay or tween, naturally dissipating ripples
5. The existing wake trail SubViewport is repurposed for this — one system replaces all current ripple visuals

### Key Architecture Decision: Opaque SubViewport

Use `transparent_bg = false` with a `ColorRect` background fill of `Color(0.5, 0.5, 0.0, 1.0)` (neutral displacement). This **avoids all premultiplied alpha complications** from Forward+ transparent SubViewports (see `docs/solutions/subviewport-premultiplied-alpha.md`). Stamps draw their displacement colors on top of the neutral background. The water shader reads RG, subtracts 0.5, done.

### Research Insights

**SubViewport clear color:** Godot SubViewport has no per-viewport clear color property. The `ColorRect` workaround is confirmed as the standard approach for 2D SubViewports needing a custom clear color. Set `render_target_clear_mode = CLEAR_MODE_ALWAYS` and ensure the `ColorRect` covers the full viewport as the first child.

**SubViewport update mode:** Use `UPDATE_ALWAYS` since stamps animate (fade over time). Optimization: track active stamp count and switch to `UPDATE_DISABLED` when zero stamps are active, back to `UPDATE_ALWAYS` when a stamp spawns.

## Technical Considerations

### Coordinate Mapping (SubViewport ↔ Water Shader)

The SubViewport is 1024×1024 world pixels, centered on the ship. To sample displacement in the water shader:

```glsl
uniform sampler2D DisplacementMap : filter_linear;
uniform vec2 DisplacementOrigin;        // ship world position (set per frame)
uniform float DisplacementViewportSize; // 1024.0
uniform float DisplacementStrength : hint_range(0.0, 20.0) = 5.0;

// In fragment(), after worldFloor:
vec2 disp_uv = (worldFloor - DisplacementOrigin + DisplacementViewportSize * 0.5) / DisplacementViewportSize;

// Mask: zero displacement outside SubViewport coverage
float in_bounds = step(0.0, disp_uv.x) * step(disp_uv.x, 1.0) * step(0.0, disp_uv.y) * step(disp_uv.y, 1.0);
vec2 raw_disp = (texture(DisplacementMap, disp_uv).rg - 0.5) * 2.0;
vec2 displacement = raw_disp * DisplacementStrength * in_bounds;

// Pixel-snap the offset
displacement = floor(displacement + 0.5);

vec2 distortedWorldFloor = worldFloor + displacement;
```

`DisplacementOrigin` is updated each frame in `main.gd` to match the ship's `global_position`.

#### Research Insights

**Coordinate approach:** A camera-following content root inside the SubViewport keeps stamp positioning simple. Stamps are placed at world coordinates as children of the content root, which offsets itself to track the camera/ship:

```gdscript
# In displacement_stamps.gd _process():
position = -_follow_target.global_position + Vector2(_sub_viewport.size) / 2.0
```

When spawning stamps, just set `stamp.position = world_pos` — the content root offset handles the viewport mapping.

**Edge artifacts:** When stamps cross the SubViewport boundary, they get clipped. At 1024×1024 covering ±512px from the ship, and a visible area of ~533×300px at 1.2× camera zoom, most stamps are well within bounds. If edge artifacts are visible, add a shader edge fade:

```glsl
float edge_fade = smoothstep(0.0, 0.05, min(
    min(disp_uv.x, 1.0 - disp_uv.x),
    min(disp_uv.y, 1.0 - disp_uv.y)
));
displacement *= edge_fade;
```

**SubViewport size:** 1024×1024 provides comfortable coverage margin beyond the visible area. A 640×360 viewport-matched size would work but leaves no buffer for stamps at screen edges. Keep 1024×1024 — the performance cost is negligible for a 2D-only SubViewport with simple sprites.

### What Gets Displaced (and What Doesn't)

**Displaced** (use `distortedWorldFloor`):
- Animated UV offset / MovementNoise (line 65-66)
- Caustic texture sampling (line 69-70)
- Caustic highlight sampling (line 73)
- Random fade noise (line 77-78)
- Specular highlight noise (line 83-86)

**NOT displaced** (keep using `worldFloor` or raw `var_WorldPos`):
- Foam height from tile texture — `texture(TEXTURE, UV)` (line 109)
- Foam noise — `var_WorldPos * FoamNoiseScale` (line 110)

This matches the brainstorm decision: foam is a surface feature that rides on waves.

### Displacement Stamp Shader

Each stamp is a `Sprite2D` with a shader that encodes radial displacement:

```glsl
// shaders/displacement_stamp.gdshader
shader_type canvas_item;

uniform float RingRadius : hint_range(0.0, 0.5) = 0.3;
uniform float RingWidth : hint_range(0.01, 0.2) = 0.05;
uniform float Amplitude : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec2 centered = UV * 2.0 - 1.0;
    float dist = length(centered);
    vec2 dir = (dist > 0.001) ? normalize(centered) : vec2(0.0);

    // Ring shape with smooth falloff
    float ring = smoothstep(RingRadius - RingWidth, RingRadius, dist)
               * smoothstep(RingRadius + RingWidth, RingRadius, dist);

    // Encode direction: 0.5 = neutral, direction * amplitude shifts from neutral
    vec2 encoded = dir * Amplitude * 0.5 + 0.5;
    COLOR = vec4(encoded.x, encoded.y, 0.0, ring);
}
```

Stamps use `blend_mix` — alpha blending over the neutral gray background. Where alpha = 0, the neutral background shows through. Where alpha > 0, the directional displacement color is written.

#### Research Insights

**Stamp blending and wave superposition:** Physically correct wave superposition requires additive blending of signed displacement deltas. However, `blend_add` in Godot clamps negative output values to zero, making it unsuitable for bidirectional displacement encoding without workarounds.

**Recommendation:** Start with `blend_mix` (alpha blending). For this pixel art game, the visual difference between averaged and superposed overlapping ripples is negligible — ripples from different sources rarely overlap in practice (impacts are sparse, wakes trail behind the ship). If superposition becomes visually important later, consider a two-pass approach or compute shader.

**Stamp material duplication:** Each stamp MUST call `.duplicate()` on its ShaderMaterial, since per-stamp uniforms (`RingRadius`, `Amplitude`) vary between stamps. This follows the documented convention at `docs/solutions/shared-resource-mutation.md`:

```gdscript
var stamp := Sprite2D.new()
stamp.material = _base_material.duplicate()
(stamp.material as ShaderMaterial).set_shader_parameter("RingRadius", initial_radius)
```

**Tween pattern for stamp uniforms:** Use the `"shader_parameter/Name"` property path for direct tweening, matching the existing pattern in `sea_mine.gd`:

```gdscript
var tween: Tween = stamp.create_tween()
tween.tween_property(stamp.material, "shader_parameter/RingRadius", 0.45, 2.0) \
    .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
tween.tween_callback(stamp.queue_free)  # Cleanup after fade
```

### Stamp Types

| Source | Stamp Behavior | Spawning |
|--------|---------------|----------|
| **Ship wake** | Small radial stamp at ship position, low amplitude, fades quickly | Every N frames while moving, spawned by wake manager script |
| **Cannonball impact** | Ring stamp, RingRadius tweened from 0 → 0.45, amplitude fades out | Spawned from `_on_cannonball_water_impacted` |
| **Mine explosion** | Large ring stamp, RingRadius tweened from 0 → 0.45, high amplitude | Spawned from mine `destroyed` signal |
| **Mine idle bob** | Small pulsing radial stamp, amplitude modulated by bob phase | Continuous, driven by `main.gd` mediator |

### Existing Infrastructure Reuse

| Current | Becomes |
|---------|---------|
| `WaterTrail` SubViewport (1024×1024) | Displacement map SubViewport |
| `TrailSprite` + `ripple.gdshader` | Removed — SubViewport texture goes directly to water shader uniform |
| `trails.gd` (Line2D point queue) | Replaced by displacement stamp manager script |
| `Circle` sprite in SubViewport | Replaced by ship wake stamps |
| `sea_mine_ripple.gdshader` | Replaced by mine displacement stamps in SubViewport |
| Mine explosion ripple spawning | Replaced by explosion displacement stamps |

### Communication Architecture

**main.gd as mediator — call down, signal up:**

```
Ship movement      → main.gd._process() calls _displacement_stamps.spawn_wake()
Cannonball impact  → water_impacted signal → main.gd calls _displacement_stamps.spawn_impact()
Mine explosion     → destroyed signal → main.gd calls _displacement_stamps.spawn_impact()
Mine idle bob      → main.gd._process() iterates _mines, calls _displacement_stamps.spawn_pulse()
```

`DisplacementStamps` is a **scene-local node** inside the SubViewport. Not an autoload, not a class_name singleton. Only `main.gd` calls into it (via direct reference from `@onready`).

Mines do NOT hold a reference to the stamp manager. All stamp spawning is routed through `main.gd`, which already acts as the scene coordinator for mines (`_mines` array, `destroyed` signal, `tree_exiting` signal).

#### Research Insights

**Mine idle bob wiring:** Rather than having each mine signal every frame for bob updates, `main.gd._process()` iterates `_mines` and calls `_displacement_stamps.spawn_pulse(mine.global_position, mine.get_bob_phase())`. This keeps mines decoupled from the displacement system and avoids per-frame signal overhead.

**Shared water material uniform safety:** Setting `DisplacementOrigin` per-frame on the shared `water_material` is safe and intentional. All chunks must use the same origin. Add an inline comment:
```gdscript
# Intentionally shared: all water chunks use the same DisplacementOrigin.
# NOT duplicated — per-frame uniform updates propagate to every chunk simultaneously.
```

## Acceptance Criteria

- [x] Water caustics and specular visibly warp when ripples pass through
- [x] Ship movement produces trailing UV distortion behind the ship
- [x] Cannonball water impacts create expanding ring distortion
- [x] Mine explosions create large expanding ring distortion
- [x] Mine idle bobbing creates subtle pulsing distortion
- [x] Foam is NOT affected by displacement (rides on top of waves)
- [x] Displacement is pixel-snapped (no sub-pixel smearing)
- [x] No visual artifacts at displacement SubViewport boundaries
- [x] Multiple simultaneous ripples blend naturally (overlapping stamps)
- [x] Zero errors in debug output when running
- [x] `gdformat --check .` and `gdlint .` pass

## Implementation Phases

### Phase 1: Displacement SubViewport + Water Shader Integration

Set up the core infrastructure and verify displacement works with a static test.

**Files modified:**
- `shaders/water_surface.gdshader` — add `DisplacementMap`, `DisplacementOrigin`, `DisplacementViewportSize`, `DisplacementStrength` uniforms; compute `distortedWorldFloor`; use it for caustic/specular sampling (lines 65-86), leave foam (lines 109-119) unchanged
- `shaders/water_surface_material.tres` — add default values for new uniforms
- `scripts/main.gd` — wire SubViewport texture to `water_material.DisplacementMap` in `_ready()` using `get_texture()` (per ViewportTexture 4.6 regression workaround); update `DisplacementOrigin` each frame in `_process()`
- `scenes/main.tscn` — restructure SubViewport: remove `TrailSprite`, `Line2D`, `Circle`; add `ColorRect` neutral background; rename `WaterTrail` to `DisplacementViewport`; remove `z_index = 1` (no visible children)

**Scene tree after Phase 1:**
```
Main (Node2D, script: main.gd)
  Ship
  ChunkContainer (water_chunks.gd)
  DisplacementViewport (Node2D, follows ship position)
    SubViewport (1024x1024, transparent_bg=false, clear_mode=ALWAYS)
      NeutralBackground (ColorRect, Color(0.5, 0.5, 0, 1), full_rect)
      [static test sprite for verification]
```

**Verification:** Place a static colored circle (e.g., Sprite2D with a radial gradient where R varies from 0.3 to 0.7) in the SubViewport manually. Run project — water should visibly warp around the ship's position.

#### Research Insights

**ViewportTexture assignment:** `sub_viewport.get_texture()` returns a live-linked ViewportTexture handle that updates every frame. Assign once in `_ready()` — it does not go stale. First frame will show no displacement (SubViewport hasn't rendered yet), which is fine.

**Uniform case sensitivity:** The shader parameter name in `set_shader_parameter("DisplacementMap", ...)` must match the uniform name exactly (PascalCase, matching project convention).

### Phase 2: Displacement Stamp Shader + Stamp Manager

Create the stamp shader and a manager script that spawns/fades stamps in the SubViewport.

**Files created:**
- `shaders/displacement_stamp.gdshader` — radial ring shader encoding direction as RG color
- `shaders/displacement_stamp_material.tres` — base ShaderMaterial for stamps (duplicated per instance)
- `scripts/displacement_stamps.gd` — stamp manager: spawns `Sprite2D` stamps in the SubViewport, manages lifetime/fading, provides public API for game systems to request stamps

**Stamp manager design:**

```gdscript
# scripts/displacement_stamps.gd
extends Node2D

## Manages displacement stamp sprites inside a SubViewport.
## Lives as a child of the SubViewport. Stamps are Sprite2D children.

@export var sub_viewport: SubViewport
@export var follow_target: Node2D  ## Node whose position centers the viewport

var _base_material: ShaderMaterial
var _stamp_texture: Texture2D

func _ready() -> void:
    assert(sub_viewport != null, "DisplacementStamps: sub_viewport must be assigned")
    assert(follow_target != null, "DisplacementStamps: follow_target must be assigned")
    _base_material = preload("res://shaders/displacement_stamp_material.tres")
    # Simple white texture for stamp sprites — shader does all the work
    _stamp_texture = preload("res://textures/white_square.png")  # or PlaceholderTexture2D

func _process(_delta: float) -> void:
    # Track follow_target so stamps appear at correct world positions
    position = -follow_target.global_position + Vector2(sub_viewport.size) / 2.0

func spawn_impact(world_pos: Vector2, radius: float, duration: float) -> void:
    ## Expanding ring stamp for point impacts (cannonballs, explosions).
    var stamp := Sprite2D.new()
    stamp.texture = _stamp_texture
    stamp.material = _base_material.duplicate()
    stamp.position = world_pos
    stamp.scale = Vector2(radius, radius) * 2.0
    add_child(stamp)
    var mat: ShaderMaterial = stamp.material as ShaderMaterial
    var tween: Tween = stamp.create_tween()
    tween.tween_property(mat, "shader_parameter/RingRadius", 0.45, duration) \
        .from(0.02).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
    tween.parallel().tween_property(mat, "shader_parameter/Amplitude", 0.0, duration * 0.6) \
        .set_ease(Tween.EASE_IN)
    tween.tween_callback(stamp.queue_free)

func spawn_wake(world_pos: Vector2, amplitude: float) -> void:
    ## Small radial stamp for ship wake trail.
    var stamp := Sprite2D.new()
    stamp.texture = _stamp_texture
    stamp.material = _base_material.duplicate()
    stamp.position = world_pos
    stamp.scale = Vector2(32, 32)  # Small wake disturbance
    add_child(stamp)
    var mat: ShaderMaterial = stamp.material as ShaderMaterial
    mat.set_shader_parameter("Amplitude", amplitude)
    mat.set_shader_parameter("RingRadius", 0.0)  # Filled disc, not ring
    mat.set_shader_parameter("RingWidth", 0.5)
    var tween: Tween = stamp.create_tween()
    tween.tween_property(stamp, "modulate:a", 0.0, 0.5)
    tween.tween_callback(stamp.queue_free)

func spawn_pulse(world_pos: Vector2, amplitude: float, phase: float) -> void:
    ## Pulsing stamp for continuous sources (mine bob).
    ## Phase modulates amplitude — stronger at bob extremes.
    pass  # Implementation in Phase 4
```

#### Research Insights

**No object pooling:** The codebase uses instantiate/queue_free for all dynamic objects (mines, enemies, cannonballs, explosions). Keep stamps consistent with this pattern. At ~1-3 instantiations per second, pooling is premature optimization.

**`@export` references with assertions:** Follow the pattern from `trails.gd` lines 11-12 and 21-27 — `@export` for SubViewport and follow_target, validated in `_ready()`.

**Stamp base texture:** A simple white square texture (or `PlaceholderTexture2D`) works since the stamp shader computes everything from UVs. The texture just provides a quad for the shader to run on.

### Phase 3: Ship Wake Stamps

Replace the Line2D trail with continuous displacement stamps at the ship position.

**Files modified:**
- `scripts/main.gd` — call `_displacement_stamps.spawn_wake()` in `_process()` while ship is moving (throttle to every N frames or by distance traveled)

**Files removed:**
- `scripts/trails.gd` — no longer needed (Line2D trail replaced)
- `scripts/trails.gd.uid` — sidecar UID file
- `shaders/ripple.gdshader` — no longer needed (brightness overlay replaced)
- `shaders/ripple.gdshader.uid` — sidecar UID file
- `shaders/ripple_material.tres` — no longer needed

**Scene cleanup in `main.tscn`:**
- Remove unused `ext_resource` declarations: `WaterTrailGradient.png`, `CircleBlur64x64.png`, `trail_width_curve.tres`, `ripple_material.tres`, `trails.gd`
- Remove unused `sub_resource` declarations: `Gradient_trail`

### Phase 4: Impact + Explosion Stamps

Wire cannonball and mine events to spawn displacement stamps.

**Files modified:**
- `scripts/main.gd`:
  - `_on_cannonball_water_impacted()` — add `_displacement_stamps.spawn_impact(impact_pos, ...)`
  - `_process()` — iterate `_mines` for idle bob: `_displacement_stamps.spawn_pulse(mine.global_position, ...)`
  - Connect mine `destroyed` signal to spawn explosion displacement stamp
- `scripts/sea_mine.gd`:
  - Add `_is_detonated` guard at top of `_process()`: `if _is_detonated: return`
  - Add `func get_bob_phase() -> float` public accessor for bob phase value
  - Remove `_spawn_explosion_ripple()` method and all ripple-related code
  - Remove `_ripple_sprite` references and material duplication for ripple

**Files removed:**
- `shaders/sea_mine_ripple.gdshader` — replaced by displacement stamps
- `shaders/sea_mine_ripple.gdshader.uid` — sidecar UID file

**Scene cleanup in `sea_mine.tscn`:**
- Remove `RippleSprite` node
- Remove `ShaderMaterial_ripple` sub-resource
- Remove `ext_resource` for `sea_mine_ripple.gdshader`

#### Research Insights

**Timing safety for mine explosions:** `queue_free()` only marks for end-of-frame deletion. The `destroyed` signal (emitted before `queue_free()` at `sea_mine.gd` line 176) is synchronous — `main.gd`'s handler runs immediately and can spawn the displacement stamp before the mine is freed. This follows the existing pattern exactly.

**Timing safety for cannonball impacts:** `water_impacted.emit(global_position)` at `cannonball.gd` line 56 is synchronous. The signal handler in `main.gd` runs before `queue_free()` on line 58. Safe — `global_position` is passed by value.

**`_is_detonated` guard:** Without this, `_process()` could run one extra frame after detonation, spawning a spurious bob pulse. Low risk but logically wrong — add the guard.

### Phase 5: Tuning + Cleanup

- Tune displacement strength, stamp sizes, fade durations
- Verify pixel-snapping looks good (may relax to sub-pixel if needed)
- Remove any orphaned textures (`WaterTrailGradient.png`, `CircleBlur64x64.png` if unused elsewhere)
- Run `update_project_uids` via MCP to verify no stale UID references
- Run `gdformat` and `gdlint`
- Visual test via MCP: `run_project` → `get_debug_output` → `stop_project`

## Dependencies & Risks

**Risk: Tile UV bleeding** — When displacement offsets are large, the water shader may sample UVs that land in neighboring tile space. Mitigation: keep `DisplacementStrength` moderate (5-10 world pixels max). The tile texture is uniform (same water tile everywhere), so bleeding between identical tiles is invisible.

**Risk: SubViewport coverage** — The 1024×1024 SubViewport covers ±512 world pixels from the ship. Ripples beyond this range won't appear. At the current camera zoom (1.2×, viewport 640×360), the visible area is ~533×300 pixels — well within coverage. Mines/cannonballs far from the ship won't get visible distortion, which is acceptable.

**Risk: Stamp sprite count** — Many simultaneous stamps could affect performance. Mitigation: cap maximum active stamps (~32), aggressive fade-out durations. At this viewport resolution the GPU cost of drawing ~32 small sprites into a SubViewport is negligible. No object pooling needed — matches existing codebase pattern of instantiate/queue_free.

### Research Insights

**Performance profile:** The water surface shader already performs 8 texture samples per fragment. Adding a 9th (displacement map) is ~12% increase — negligible at 640×360. The SubViewport with ~32 sprites is trivially cheap for a 2D-only render target.

**Material batching:** Each stamp gets a duplicated ShaderMaterial (required for per-stamp uniforms). This means one draw call per stamp, which is fine at ≤32 stamps. If stamp count becomes a concern, redesign stamps to use `Sprite2D.modulate` and `Sprite2D.scale` for per-instance variation with a shared material.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-04-05-water-ripple-distortion-brainstorm.md](../brainstorms/2026-04-05-water-ripple-distortion-brainstorm.md) — Key decisions carried forward: displacement map SubViewport (industry standard), replace existing trail SubViewport, distort caustics/specular but not foam, pixel-snapped offsets.

### Internal References

- Water surface shader: [shaders/water_surface.gdshader](../../shaders/water_surface.gdshader) (worldFloor at line 62, caustic sampling lines 65-86, foam lines 109-119)
- Existing trail system: [scripts/trails.gd](../../scripts/trails.gd), [scripts/main.gd:24](../../scripts/main.gd) (viewport texture wiring)
- Water material shared via: [scripts/water_chunks.gd:63](../../scripts/water_chunks.gd) (all chunks share one material)
- Cannonball impact handler: [scripts/main.gd:59-61](../../scripts/main.gd)
- Mine ripple system: [scripts/sea_mine.gd](../../scripts/sea_mine.gd), [shaders/sea_mine_ripple.gdshader](../../shaders/sea_mine_ripple.gdshader)
- ViewportTexture regression workaround: [docs/solutions/viewporttexture-46-regression.md](../solutions/viewporttexture-46-regression.md)
- Premultiplied alpha solution: [docs/solutions/subviewport-premultiplied-alpha.md](../solutions/subviewport-premultiplied-alpha.md)
- Shared resource mutation: [docs/solutions/shared-resource-mutation.md](../solutions/shared-resource-mutation.md)

### External References

- [Minions Art: Interactive Water via RenderTexture](https://www.patreon.com/posts/making-water-24192529) — canonical render-texture approach
- [Cyanilux: 2D Water Shader Breakdown](https://www.cyanilux.com/tutorials/2d-water-shader-breakdown/) — UV distortion with tile-aware edge handling
- [Dynamic Water Demo (John Wigg)](https://john-wigg.dev/DynamicWaterDemo/) — ping-pong upgrade path
- [Godot Docs: SubViewport as Texture](https://docs.godotengine.org/en/stable/tutorials/shaders/using_viewport_as_texture.html)
- [Godot Docs: SubViewport class reference](https://docs.godotengine.org/en/4.4/classes/class_subviewport.html)
- [Object Pooling in Godot](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/) — referenced but deferred (not needed at current scale)
