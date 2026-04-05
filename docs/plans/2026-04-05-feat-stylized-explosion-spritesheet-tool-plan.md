---
title: "feat: Stylized Explosion Spritesheet Tool"
type: feat
status: completed
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-stylized-explosion-spritesheet-brainstorm.md
---

# feat: Stylized Explosion Spritesheet Tool

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 7
**Review agents used:** architecture, performance, resource-safety, timing, simplicity, pattern-consistency, best-practices, godot-patterns

### Key Improvements
1. **Simplified pipeline** -- removed premul alpha conversion (no-op with alpha scissor), removed resize step (render directly at 32x32), removed quantization pass (shader already produces limited palette), dropped to one emitter for MVP
2. **Determinism** -- use `use_fixed_seed` + `seed` + `fixed_fps` properties (PR #92089, Godot 4.4+) for reproducible bursts; set `emitting = false` before `restart()` to avoid one_shot flash
3. **Safety** -- editor-only assertion for `res://` writes, state guard for capture re-entrancy, `is_instance_valid()` guard after await, explicit material duplication strategy

### New Considerations Discovered
- Alpha scissor produces binary alpha (0 or 1), making premul-to-straight conversion unnecessary
- GPUParticles3D skips one frame of update when newly created -- wait a frame before first emission
- `fixed_fps` should be set explicitly (default 0 uses 30fps fallback) for deterministic capture
- Physical lighting units break `transparent_bg` on SubViewport (issue #95805) -- use unshaded only
- WorldEnvironment is unnecessary when all materials use `render_mode unshaded`

---

## Overview

An offline tool scene that renders a stylized 3D explosion effect (fresnel + noise dissolve on sphere mesh particles) and captures it as a pixel-art spritesheet strip. Run via F6 (Run Current Scene) in the editor.

## Problem Statement / Motivation

The game needs explosion effects (cannonball impacts, ship destruction) but is a 2D pixel-art game. Rather than building 3D particle systems into the game runtime, we render 3D explosions offline and export them as 2D spritesheets -- keeping runtime simple while getting the visual quality of 3D fresnel/dissolve effects.

(see brainstorm: `docs/brainstorms/2026-04-05-stylized-explosion-spritesheet-brainstorm.md`)

## Proposed Solution

A self-contained tool scene at `scenes/tools/explosion_renderer.tscn` with:

1. **3D explosion** in a SubViewport (GPUParticles3D emitter + spatial dissolve shader)
2. **Preview UI** with tweakable parameters and live viewport display
3. **Capture system** that renders frames to a horizontal strip PNG

### Architecture

```
scenes/tools/explosion_renderer.tscn (Control root)
├── HBoxContainer
│   ├── VBoxContainer (controls panel)
│   │   ├── ColorPickerButton × 2 (dark color, fire color HDR)
│   │   ├── HSlider × 3 (smoothstep, simulation speed, bright/dark dissolve offset)
│   │   ├── Button "Play"
│   │   ├── Button "Capture"
│   │   └── Label (status)
│   └── SubViewportContainer (preview, stretch=true)
│       └── SubViewport (32×32, transparent_bg, own_world_3d)
│           ├── Camera3D
│           └── GPUParticles3D "Emitter" (sphere shape)
│               └── draw_pass_1: SphereMesh + explosion_dissolve ShaderMaterial
```

### Research Insights: Architecture

**Simplifications applied (from simplicity review):**
- **One emitter** instead of two -- `EMISSION_SHAPE_SPHERE` already emits in all directions; at 32x32 output the difference between sphere+ring and sphere-only is invisible. Add a second emitter later if needed.
- **HBoxContainer** instead of HSplitContainer -- no draggable divider needed for a fixed-layout tool.
- **No WorldEnvironment** -- `render_mode unshaded` ignores all lighting/environment settings.
- **Hardcoded frame count** -- `const FRAME_COUNT: int = 8` instead of a SpinBox. One-line edit if you need 16 later.
- **32x32 SubViewport directly** -- no 128x128 supersample + resize. The particle shader with alpha scissor produces clean hard edges at any resolution. Bump to 64x64 only if the result looks too jaggy.

**Pattern consistency (from pattern review):**
- `scenes/tools/` is a new subdirectory -- reasonable extension for offline tooling. First tool scene in the project.
- SubViewportContainer (vs. existing Sprite2D pattern) is justified -- auto-displays child viewport, handles alpha correctly, simpler for a 1:1 preview.
- Use `%` scene unique nodes for script references (recommended by godot-patterns review).

### Files to Create

| File | Purpose |
|------|---------|
| `shaders/explosion_dissolve.gdshader` | Spatial shader: fresnel + noise dissolve, two color layers, alpha scissor |
| `shaders/explosion_dissolve_material.tres` | ShaderMaterial with noise texture and default parameters |
| `scenes/tools/explosion_renderer.tscn` | Tool scene with SubViewport, particles, UI |
| `scripts/explosion_renderer.gd` | UI logic, capture pipeline, parameter binding |

## Technical Considerations

### Shader Design (`explosion_dissolve.gdshader`)

```
shader_type spatial;
render_mode unshaded, cull_disabled;
```

**Fresnel** -- calculated manually (no built-in in Godot):
```gdshader
float fresnel(float power, vec3 normal, vec3 view) {
    return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), power);
}
```

**Dissolve mechanism** -- `INSTANCE_CUSTOM` from ParticleProcessMaterial, passed to `fragment()` via a varying. The brainstorm references "UV2" but that is the Unity equivalent -- Godot uses `INSTANCE_CUSTOM` (vec4, vertex-only built-in).

```gdshader
varying float dissolve_progress;

void vertex() {
    dissolve_progress = INSTANCE_CUSTOM.y;  // normalized lifetime 0→1
}
```

**Two color layers:**
- Dark layer: `fresnel(0.5, ...) + noise`, dissolved by `dissolve_progress * DarkDissolveScale`
- Bright layer: `fresnel(1.0, ...) + noise`, dissolved by `dissolve_progress * BrightDissolveScale`
- Each layer: invert fresnel (1.0 - f), add noise, subtract dissolve value x 2.0, smoothstep for edge control
- Final: dark x DarkColour + bright x FireColour -> ALBEDO, combined alpha -> ALPHA with ALPHA_SCISSOR_THRESHOLD

**Uniforms** (PascalCase per convention):
- `NoiseTexture : sampler2D` -- hint_default_white, filter_linear (NOT source_color -- avoid sRGB conversion on noise data)
- `DarkColour : vec3` -- source_color, default gray
- `FireColour : vec3` -- source_color, default HDR orange
- `SmoothStepEdge : float` -- hint_range(0.0, 1.0), default 0.0 for hard-edge style
- `BrightDissolveScale : float` -- hint_range(0.5, 2.0), default 1.2
- `DarkDissolveScale : float` -- hint_range(0.5, 2.0), default 0.8
- `FresnelPowerBright : float` -- default 1.0
- `FresnelPowerDark : float` -- default 0.5

### Research Insights: Shader

**Alpha scissor implications (from simplicity + performance reviews):**
- `ALPHA_SCISSOR_THRESHOLD` produces **binary alpha** (0 or 1) for every pixel. This means premultiplied and straight alpha are identical -- dividing by 1.0 is a no-op, and 0-alpha pixels are black/transparent either way.
- This eliminates the need for a per-pixel `premul_to_straight()` conversion entirely.
- This also eliminates the need for a quantization pass -- the shader already produces a limited color palette (two user-chosen colors modulated by fresnel).

**Spatial shader on particles gotchas (from best-practices research):**
- `INSTANCE_CUSTOM` is only available in `vertex()` -- must pass via `varying` to `fragment()`.
- For `render_mode unshaded`, drive all color through `ALBEDO` and optionally `EMISSION` for glow.
- Use `depth_draw_never` if particles Z-fight (unlikely for an isolated SubViewport).

**Pattern note:** `hint_default_white` on NoiseTexture is new to this project (existing noise textures use `source_color`), but correct for a spatial shader where `source_color` would trigger unwanted sRGB-to-linear conversion on noise data.

### Particle Configuration

ParticleProcessMaterial settings:
- `one_shot = true`, `explosiveness = 1.0` (burst) -- set on GPUParticles3D node
- `use_fixed_seed = true`, `seed = 12345` -- determinism (preview matches capture)
- `fixed_fps = 30` -- explicit FPS for deterministic simulation (default 0 uses 30fps fallback inconsistently)
- `amount = 40` -- single emitter (was 30x2, now 40x1)
- `lifetime = 2.0` (overall emitter lifetime)
- `particle_flag_disable_z = false` (3D)
- `initial_velocity_min/max = 5.0 / 10.0`
- `damping_min/max = 50.0 / 75.0`
- `angle_min/max = 0 / 360` (random rotation)
- `scale_min/max = 0.3 / 0.5` (small spheres)
- `emission_shape = EMISSION_SHAPE_SPHERE`, `emission_sphere_radius = 0.5`
- `draw_pass_1` = SphereMesh with explosion_dissolve ShaderMaterial

### Research Insights: Particles

**Determinism (from best-practices research + timing review):**
- PR #92089 (merged Jan 2025, Godot 4.4+) added `use_fixed_seed` and `seed` properties. Set both before first emission.
- `restart()` with `use_fixed_seed = true` produces the same particle burst each time.
- **However**, GPU particles are time-stepped by actual frame deltas, so preview and capture may differ slightly. This is acceptable -- the capture result is the canonical output.
- **One-shot re-triggering bug:** Calling `restart()` while particles are still alive can flash old positions. Fix: set `emitting = false` before `restart()`:

```gdscript
func _play_explosion() -> void:
    %Emitter.emitting = false
    %Emitter.restart()
```

**Known skip-frame bug (from best-practices research):**
- GPUParticles3D skips one frame of update when newly created (issue #101758). Wait one frame after scene load before first emission:

```gdscript
func _ready() -> void:
    # ... setup ...
    await get_tree().process_frame  # wait for GPU particle init
    _play_explosion()
```

**`speed_scale` is on the GPUParticles3D node**, not on ParticleProcessMaterial. The simulation speed slider should modify `%Emitter.speed_scale`, not the material. No duplication needed for this property.

### Capture Pipeline

**No formal state machine needed** -- a single `var _capturing: bool = false` is sufficient for a two-button tool.

**Frame timing formula:**
```
const FRAME_COUNT: int = 8
capture_duration = emitter.lifetime  # 2.0s default
warmup_delay = 0.05  # skip first 50ms (GPU particle latency)
interval = (capture_duration - warmup_delay) / FRAME_COUNT
```

**Capture sequence:**
1. Guard: `if _capturing: return` (re-entrancy protection)
2. Set `_capturing = true`, disable all UI controls
3. `assert(OS.has_feature("editor"), "This tool only works in the editor")`
4. Set `emitting = false`, then `restart()` on emitter
5. Wait `warmup_delay` seconds
6. For each frame (0..7):
   a. `await RenderingServer.frame_post_draw`
   b. `if not is_instance_valid(%SubViewport): return` (safety guard)
   c. `var img: Image = %SubViewport.get_texture().get_image()` (32x32, binary alpha from scissor)
   d. `strip_image.blit_rect(img, Rect2i(0, 0, 32, 32), Vector2i(i * 32, 0))`
   e. Update status label: "Frame %d/%d..." % [i + 1, FRAME_COUNT]
   f. Wait remaining interval time before next frame
7. `strip_image.save_png("res://textures/explosion_strip.png")`
8. Show status: "Saved: textures/explosion_strip.png"
9. Set `_capturing = false`, re-enable UI controls

### Research Insights: Capture Pipeline

**Simplifications applied (from simplicity + performance reviews):**
- **No resize step** -- SubViewport renders directly at 32x32.
- **No premul-to-straight conversion** -- alpha scissor produces binary alpha; premul and straight are identical when alpha is 0 or 1.
- **No quantization pass** -- the two-color shader with fresnel modulation already produces a limited, pixel-art-friendly palette. Add quantization only if the output looks too smooth (unlikely).
- **Single per-pixel processing pass eliminated** -- the capture just blits raw viewport frames into the strip.

**Timing considerations (from timing review):**
- Keep `render_target_update_mode = UPDATE_ALWAYS` during capture. Do not switch to UPDATE_ONCE -- if the main window loses focus, `frame_post_draw` may not fire and the coroutine hangs.
- The interval wait + frame_post_draw await introduces a ~1 frame offset (~16ms at 60fps). Over 8 frames spanning 2 seconds, this is negligible.
- Real-time capture (~2 seconds total) is the only reliable approach. GPUParticles3D cannot be time-stepped manually.

**Re-entrancy (from timing review):**
- The `_capturing` bool guard is the primary defense against double-trigger.
- UI `disabled = true` prevents new mouse clicks but not programmatic calls or queued signals.
- Slider callbacks should also check `if _capturing: return` for safety.

### SubViewport Configuration

| Property | Value | Reason |
|----------|-------|--------|
| `size` | Vector2i(32, 32) | Direct output resolution, no resize needed |
| `transparent_bg` | `true` | Alpha channel for compositing |
| `own_world_3d` | `true` | Isolate from main scene |
| `render_target_update_mode` | `UPDATE_ALWAYS` | Continuous during preview and capture |
| `disable_3d` | `false` | Must render 3D particles |

Since we use a `SubViewportContainer`, the viewport texture is displayed automatically -- no manual ViewportTexture assignment needed. The container handles this internally, bypassing the Godot 4.6 ViewportTexture serialization regression.

### Research Insights: SubViewport

- **Physical lighting breaks transparent_bg** (issue #95805). Since we use `render_mode unshaded`, this is not a concern, but do NOT add lights to the SubViewport.
- **No WorldEnvironment needed** -- unshaded materials ignore environment settings. The SubViewport's `transparent_bg = true` handles the clear color.
- `get_texture().get_image()` performs a GPU-to-CPU readback stall. At 32x32 (4KB RGBA8), this is sub-millisecond. Fine for 8 captures.

### Resource Safety

- `.duplicate()` the ShaderMaterial **once** in `_ready()`, then assign the same duplicate to the emitter's draw pass mesh. Since there is now one emitter, this is straightforward:

```gdscript
func _ready() -> void:
    # Duplicate material to avoid mutating the .tres on disk
    var base_mat: ShaderMaterial = %Emitter.draw_pass_1.surface_get_material(0)
    _material = base_mat.duplicate() as ShaderMaterial
    %Emitter.draw_pass_1.surface_set_material(0, _material)
    # NoiseTexture inside the material is intentionally shared (read-only)
```

- ParticleProcessMaterial is NOT modified at runtime -- only `speed_scale` on the GPUParticles3D node. No duplication needed.
- `res://` writes only work in-editor. Add assertion: `assert(OS.has_feature("editor"))`.
- Godot's import system will auto-reimport the saved PNG when the editor regains focus after F6 -- this is intended behavior.

### GDScript Conventions

Per project CLAUDE.md and godot-patterns review:

- **Static typing** on all variables, parameters, return types
- **`%` unique node references** for all script-accessed nodes (e.g., `%Emitter`, `%SubViewport`, `%StatusLabel`)
- **`@export` assertions** in `_ready()` with clear messages (if any @export references used)
- **Member ordering:** signals, enums, constants, exports, vars, @onready, _ready, _process, signal callbacks, public methods, private methods
- **Comment at script top:** `## Run this scene with F6 (Run Current Scene) in the editor.`

## Acceptance Criteria

- [x] Tool scene runs standalone via F6 (Run Current Scene) -- no changes to project main scene
- [x] 3D explosion renders in SubViewport with visible fresnel dissolve effect on sphere particles
- [x] GPUParticles3D emitter bursts with `use_fixed_seed` for deterministic results
- [x] Spatial shader has: fresnel + noise dissolve, dark + bright color layers, alpha scissor
- [x] Preview shows live SubViewport output with correct alpha compositing
- [x] UI sliders update shader parameters in real-time (dark color, fire color, smoothstep, speed)
- [x] "Play" button restarts the explosion (sets `emitting = false` first, then `restart()`)
- [x] "Capture" button renders 8 frames to a horizontal strip PNG at `textures/explosion_strip.png`
- [x] Output is 32x32px per frame with clean binary alpha from alpha scissor
- [x] Controls disabled during capture with progress feedback in status label
- [x] Capture is guarded against re-entrancy (`_capturing` bool check)
- [x] Editor-only assertion prevents capture in exported builds
- [x] No errors in debug output when running the tool scene
- [x] Follows project conventions: static typing, PascalCase shader uniforms, snake_case filenames, `%` unique node refs

## Success Metrics

- Tool produces a usable spritesheet that looks correct when loaded as SpriteFrames in the game
- Exported PNG has clean alpha (binary from scissor, no fringing)
- Tweaking parameters visibly changes the effect in preview
- Capture produces identical results on repeated runs (deterministic via `use_fixed_seed`)

## Dependencies & Risks

**Dependencies:** None -- self-contained tool, no changes to existing game code

**Risks:**
- **GPU particle timing:** GPUParticles3D is GPU-driven; frame capture timing may vary slightly between runs even with `use_fixed_seed`. The capture result is the canonical output. Mitigated by `fixed_fps = 30` for consistent simulation stepping.
- **First-frame latency:** GPU particles may not render on the exact first frame (issue #101758). Mitigated by 50ms warmup delay + waiting one frame after `_ready()` before first emission.
- **32x32 may be too low-res:** If the explosion looks too jaggy at 32x32, bump SubViewport to 64x64 and add `img.resize(32, 32, Image.INTERPOLATE_NEAREST)` before blit. This is a one-line change.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-04-05-stylized-explosion-spritesheet-brainstorm.md](docs/brainstorms/2026-04-05-stylized-explosion-spritesheet-brainstorm.md) -- Key decisions: full 3D with GPUParticles3D, 8 frames at 32x32, quantized pixel-art, preview+tweak UI

### Internal References

- SubViewport pattern: [scenes/main.tscn](scenes/main.tscn) (wake trail SubViewport)
- Quantization pattern: [shaders/ripple.gdshader:39](shaders/ripple.gdshader#L39) (`floor(v * steps) / steps`)
- ViewportTexture regression: [docs/solutions/viewporttexture-46-regression.md](docs/solutions/viewporttexture-46-regression.md)
- Premultiplied alpha: [docs/solutions/subviewport-premultiplied-alpha.md](docs/solutions/subviewport-premultiplied-alpha.md)
- Resource mutation: [docs/solutions/shared-resource-mutation.md](docs/solutions/shared-resource-mutation.md)
- Shader material pattern: [shaders/water_surface_material.tres](shaders/water_surface_material.tres)

### External References

- Godot spatial shader INSTANCE_CUSTOM: [Particle Shader Reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/particle_shader.html)
- ParticleProcessMaterial: [Class Reference](https://docs.godotengine.org/en/stable/classes/class_particleprocessmaterial.html)
- Fresnel in spatial shaders: [GodotShaders snippet](https://godotshaders.com/snippet/fresnel/)
- 3D Explosion VFX reference: [GodotShaders](https://godotshaders.com/shader/3d-explosion-vfx/)
- Particle seed/determinism: [PR #92089](https://github.com/godotengine/godot/pull/92089) (merged Jan 2025)
- GPU particle skip-frame bug: [Issue #101758](https://github.com/godotengine/godot/issues/101758)
- SubViewport transparent_bg + physical lighting: [Issue #95805](https://github.com/godotengine/godot/issues/95805)
- SubViewport get_image timing: [Issue #106957](https://github.com/godotengine/godot/issues/106957)
- Pixel Quantization shader: [GodotShaders](https://godotshaders.com/shader/pixel-quantization/)
