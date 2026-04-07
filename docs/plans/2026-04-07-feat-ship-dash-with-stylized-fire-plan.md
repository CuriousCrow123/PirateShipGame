---
title: Ship dash with stylized fire exhaust and ghost trail
type: feat
status: completed
date: 2026-04-07
origin: docs/brainstorms/2026-04-07-ship-dash-brainstorm.md
deepened: 2026-04-07
completed: 2026-04-07
---

# Ship Dash with Stylized Fire Exhaust and Ghost Trail

## Pivot: 3D-into-SubViewport (2026-04-07, post-Phase 3)

After Phase 3 landed with the canvas_item shader, the user requested **"the fire shader should be in 3D and then rendered into 2D pixel art"**. This pivots from the canvas_item port back to the original GDQuest spatial recipe, rendered through a 32×64 SubViewport for pixel-art crunch — the architecture originally listed as Alternative #1 and rejected on simplicity grounds. The codebase already proves the SubViewport pattern works for explosions ([scenes/explosion_effect.tscn](../../scenes/explosion_effect.tscn) → [scenes/explosion_model.tscn](../../scenes/explosion_model.tscn) → [scripts/explosion_effect.gd](../../scripts/explosion_effect.gd)), so the structural risk that motivated the rejection is gone.

Architecture after the pivot:

```
shaders/stylized_fire.gdshader        — REWRITTEN as shader_type spatial
                                         (was canvas_item; preserves the
                                         GDQuest billboard + erosion recipe,
                                         drives DashStrength via uniform)
shaders/stylized_fire_material.tres   — DELETED (canvas_item .tres)
scenes/dash_fire_model.tscn           — NEW: SubViewport(32x64) +
                                         Camera3D(orthographic) +
                                         GPUParticles3D(QuadMesh + spatial
                                         ShaderMaterial)
scenes/dash_fire_effect.tscn          — NEW: Node2D + SubViewportContainer
                                         wrapping dash_fire_model instance
scripts/dash_fire_effect.gd           — NEW: DashFireEffect class with
                                         start(config) / stop() /
                                         set_dash_strength(value) API.
                                         Owns the SubViewport update mode
                                         and the duplicated material_override
                                         on the GPUParticles3D.
scenes/ship.tscn                      — FireQuad (Sprite2D) replaced with a
                                         DashFireEffect instance under
                                         SternMarker
scripts/ship.gd                       — _start_dash now calls
                                         _fire_effect.start(dash_config),
                                         _end_dash calls .stop(),
                                         _tick_dash_visuals calls
                                         .set_dash_strength(curve_sample)
scripts/dash_config.gd                — fire_quad_length_scale removed (the
                                         scene's QuadMesh + SubViewport size
                                         define the visual envelope now)
```

Why this is now the right call:
- **The user explicitly asked for it.** That's load-bearing.
- **The SubViewport gotcha (premultiplied alpha on Forward+) is documented** in [docs/solutions/subviewport-premultiplied-alpha.md](../solutions/subviewport-premultiplied-alpha.md) and the workaround is well-known. The project currently runs `gl_compatibility` per [project.godot](../../project.godot), so the gotcha doesn't bite us today.
- **`material_override` on the emitter** (mirroring [scripts/explosion_effect.gd:74-77](../../scripts/explosion_effect.gd#L74)) prevents the QuadMesh sub-resource leak documented in [docs/solutions/godot-shared-mesh-surface-material.md](../solutions/godot-shared-mesh-surface-material.md).
- **Pixel-art crunch is automatic**: the SubViewport renders at 32×64 and `SubViewportContainer.stretch=true` upscales it under the project's default Nearest filter, giving the chunky look "for free".
- **The DashStrength uniform still drives the burst envelope** — the curve sampling and `_process` cadence are unchanged. Particles emit only while `_dash_active`; when `_end_dash` runs, `emitting` flips off and the SubViewport is set to `UPDATE_DISABLED` after the particle lifetime elapses.

Acceptance criteria below have been updated to match the new pipeline (the canvas_item-specific items are crossed out and replaced with their 3D-pipeline equivalents).

## Enhancement Summary

**Deepened on:** 2026-04-07
**Sections enhanced:** Pseudocode (fixes), Phasing, Camera Feedback, DashConfig API, Integration Tests, Research Insights appendix added.
**Reviewers consulted:** architecture, gdscript, timing, performance, simplicity, pattern-recognition, best-practices research, framework-docs research (8 parallel agents).

### Critical bugs caught & fixed inline

**P0 — pseudocode**
1. **`fire_color_gradient: Gradient` cannot bind to a `sampler2D` shader uniform.** The export type is wrong for the shader signature. **Fixed:** export `fire_color_ramp: GradientTexture1D` (which IS a Texture2D) instead.
2. **`TextureScale: vec2` shader uniform vs scalar `fire_scale: float` config — mapping unspecified.** **Fixed:** rename config to `fire_texture_scale: Vector2 = Vector2(1.0, 1.0)` and bind directly.
3. **`velocity *= _config.overspeed_drag if false else linear_drag`** — the `if false` is a placeholder bug; will fail gdlint and is meaningless. **Fixed:** plain `velocity *= linear_drag` in the LOCKED_HEADING branch.
4. **`steering_dampen` export math is a no-op** (`* (1.0 - _config.steering_dampen * 0.0)` always = 1.0) AND the doc comment says "LOCKED_HEADING only" but LOCKED_HEADING ignores steering entirely. **Fixed:** export removed entirely.
5. **`_GHOST_SPRITE_NAMES: PackedStringArray` iterated as `for src_name: StringName`** — type mismatch (PackedStringArray yields String). **Fixed:** the constant is gone — replaced by a cached `_ghost_sources: Array[Sprite2D]` set in `_ready()` (also a perf win).
6. **`ghost.scale = src.global_scale`** is wrong: assigns parent-space global_scale to local scale. **Fixed:** use `ghost.global_transform = src.global_transform`, then override modulate/material.

**P0 — timing/lifecycle**
7. **`_tick_dash_visuals` and `_process_camera_shake` were proposed in `_physics_process`.** On displays running above 60Hz, the shader uniform and camera offset would step at 60Hz while the renderer draws faster, producing visible stutter. **Fixed:** both visuals callbacks moved to `_process(delta)`. Motion logic stays in `_physics_process`.
8. **`_end_dash` doesn't reset `DashStrength`** before hiding the FireQuad. The shared material retains stale state. **Fixed:** explicit `set_shader_parameter("DashStrength", 0.0)` in `_end_dash` before the visibility flip.
9. **SceneTreeTimer cooldown lambdas capture `self`.** If the ship is freed mid-cooldown, the lambda fires on a freed instance. **Fixed:** wrap in `is_instance_valid(self)` guard. Also apply the same guard to the existing `broadside_cooldown` and `mine_cooldown` lambdas at [scripts/ship.gd:104-117](../../scripts/ship.gd#L104) as a drive-by cleanup.
10. **`Engine.time_scale` leak via lambda failure.** **Fixed:** restore in BOTH `_exit_tree()` AND the restore-timer lambda (with `is_instance_valid` guard); also unconditionally reset in `_end_dash()` if a dip was applied.

**P1 — architecture & API**
11. **SternMarker placement** must reconcile with the codebase convention that every existing sprite child of Ship has its own `scale = Vector2(0.5, 0.5)` (not nested). **Fixed:** parent FireQuad under `HullSprite` to inherit its 0.5 scale, OR derive the marker offset from `HullSprite.region_rect.size * 0.5 * 0.5`. Verify in editor.
12. **Collision pushback during dash is unspecified.** A 280 px/s impulse hitting an enemy ship and getting `velocity += normal * 50.0` from [scripts/ship.gd:53-58](../../scripts/ship.gd#L53) could rebound or lock. **Fixed:** during dash, suppress the pushback loop (or scale it by 0.25). Documented as a feel-mode-agnostic rule.
13. **Speculative `dash_started`/`dash_ended` signals removed.** No listeners exist; per the project's signal-up/call-down convention, add when a consumer (audio, UI prompt, achievement) appears. Keeps the public API clean.
14. **Live-tunable hot-reload constraint clarified for Curve sampling:** use `intensity_curve.sample_baked(t)` not `sample(t)` per Godot docs — O(1) vs O(log n). Negligible perf impact, but matches framework guidance.

**P2 — simplification**
15. **Phases reduced 5 → 3.** Phases 3 (ghosts), 4 (camera), 5 (polish) merged into a single Phase 3. The 5-phase structure was ceremony for ~60 lines.
16. **One ADR, not two.** The shared-fire-material decision is standard Godot practice — a 3-line comment in the .tres suffices. The overspeed-via-drag-relax ADR is kept (genuinely non-obvious).
17. **`_apply_fire_config()` inlined into `_start_dash`** — single call site, four `set_shader_parameter` calls.
18. **Integration tests trimmed 6 → 4:** dropped #2 (cannon mid-burst — independent input branches, tests nothing) and #6 (live-edit — already proven by ExplosionConfig).

### Performance optimizations applied

- **Cache `_ghost_sources: Array[Sprite2D] = [$HullSprite, $SailSprite]` in `_ready()`** — eliminates per-spawn NodePath construction and string lookups (~18 lookups/dash → 0).
- **Cache `_ghost_container: Node2D = get_parent() as Node2D` in `_ready()`** — saves a virtual call + cast per spawn and makes the assumption explicit.
- **Verify `fire_noise.png` import sets Repeat=Enabled** — otherwise the shader's `repeat_enable` hint is silently ignored and time-based UV scrolling will clamp.
- **Ghost pooling: skip.** ~9 sprite allocations per dash gated by 1.2s cooldown is well under any GC pressure (and GDScript uses refcounting, not GC). Revisit only if `ghost_count > 16`.

### Best-practices upgrades

- **Trauma-squared shake** (Squirrel Eiserloh, GDC 2016): `shake_offset = trauma * trauma * shake_magnitude_px * unit_random_vec`. Linear decay of trauma. Replaces the linear decay of the original draft. Punchy without being sustained.
- **Audio pitch dip** is its own knob (`AudioServer.playback_speed_scale`) and is **not** affected by `Engine.time_scale`. Documented as a deliberate non-feature for now (the brainstorm didn't ask for audio).
- **Optional dash-start freeze frames** (Celeste pattern: 3 frames at `Engine.time_scale = 0.0` before motion). Captured as a `freeze_frames: int` export with default `0` so it's off until tuned.
- **`Curve.sample_baked()` not `sample()`** for the intensity curve — O(1) lookup, framework-recommended.
- **Camera2D `process_callback`**: leave at default (idle). Even though motion is in `_physics_process`, the camera reads global_position post-physics, and shake offset is per-`_process` frame. This is the smoothing-friendly path.

### Cooldown drift wording corrected

Integration scenario #5 originally said "verify cooldown does not drift". Per framework docs, `SceneTreeTimer` uses real wall-clock time and does not drift. Reframed as: "verify no drift, ±1 physics-frame input quantization."

### What did NOT change

- The four feel modes are explicitly user-requested. Kept.
- All four camera-feedback dimensions (shake, zoom, time-dip, freeze-frames) are explicitly user-requested. Kept (with `0`-default disablement).
- DashConfig live-tuning via the ExplosionConfig pattern. Kept and reinforced.
- Sprite afterimages (not Line2D ribbon). Kept.
- No i-frames, no contact damage, short tunable cooldown. Kept.
- All code references and file paths in the original plan remain valid; only the noted bugs/sections below are revised.

---

## Overview

Add a bursty, escape-oriented **dash** to the player ship, triggered by the **space bar**. The dash applies a strong forward velocity impulse to the existing `CharacterBody2D` ship (no teleport), spawns a stylized 2D fire exhaust at the stern via a ported GDQuest-inspired shader, and leaves a fading sprite-clone "ghost trail" behind. Every dimension — motion, exhaust, trail, camera feedback — is exposed via a live-editable `DashConfig` Resource that mirrors the project's existing `ExplosionConfig` hot-reload pattern.

This plan carries forward all decisions from the brainstorm
(see brainstorm: [docs/brainstorms/2026-04-07-ship-dash-brainstorm.md](../brainstorms/2026-04-07-ship-dash-brainstorm.md)) and grounds them in concrete file paths, exact line-level integration points, and Godot 4.6 patterns already established in this codebase.

## Problem Statement

The player ship moves slowly and continuously (`thrust=80.0`, `linear_drag=0.97`, terminal speed ≈ 45 px/s). There is no panic-button option — when a mine drifts into the ship's path the only escape is to start turning early. We want a satisfying, signature traversal/escape move that:

1. Visibly distinguishes itself from cruise movement (fire, light, motion smear).
2. Respects the existing momentum/drag model rather than warping the ship.
3. Has a tunable feel so we can iterate on it without rebuilding the game.
4. Adds zero scope creep — no UI, no stamina meter, no contact damage.

## Proposed Solution

### High-level shape

- **Trigger**: new `dash` input action bound to **Space** (`physical_keycode = 32`). Hooked from [scripts/ship.gd](../../scripts/ship.gd) `_unhandled_input()` next to the existing cannon/mine branches.
- **Mechanics**: state-machine-lite. On dash start, set `_dash_active = true`, set a `_dash_remaining` timer, apply an impulse, then per-physics-frame run the active feel-mode logic until the timer expires. Cooldown via the existing `SceneTreeTimer` + lambda pattern.
- **Feel modes**: enum on `DashConfig.feel_mode` selecting between four implementations — **locked-heading**, **steerable**, **velocity-aligned**, and **overspeed-cap** (see §"Feel Modes" below).
- **Visual stack**: a `Sprite2D` (or `ColorRect`) at a new `SternMarker` Marker2D inside [scenes/ship.tscn](../../scenes/ship.tscn), driven by a new `shaders/stylized_fire.gdshader` (canvas_item). Strength uniform tweens 0→1→0 across the burst.
- **Ghost trail**: spawn N `Sprite2D` clones of the hull+sail (parented to a world-space container, not the ship), each fading out via tweened modulate alpha and `queue_free`.
- **Camera feedback**: pixel-snapped offset shake on the existing `Camera2D`, optional zoom-punch tween, optional `Engine.time_scale` dip — all zero-able from `DashConfig`.
- **Live tunability**: `DashConfig` is a `Resource` loaded once at `_ready()` via `load("res://resources/dash_config.tres")`. Editing the .tres in the Inspector while the game runs propagates instantly through Godot's shared Resource cache (proven pattern in [scripts/explosion_sprite.gd:122](../../scripts/explosion_sprite.gd#L122)).

### Critical research finding — shader port is a 2D rewrite, not a copy

The original GDQuest [stylized_fire.gdshader](https://github.com/gdquest-demos/godot-shaders/blob/main/godot/Shaders/stylized_fire.gdshader) is **`shader_type spatial`** (3D). It uses billboarding via `INSTANCE_CUSTOM`, samples noise from `world_coord.xy` and `world_coord.zy`, and drives emission from vertex `COLOR.rgb`. None of that translates to a 2D canvas_item shader unchanged.

**The "port" in the brainstorm therefore means a 2D rewrite that preserves the *visual recipe*** (noise × radial mask + alpha erosion + edge softening + emissive color) rather than the source code itself. This is called out explicitly in §"Implementation Phases — Phase 2" so it's not lost when implementing.

The recipe to preserve, lifted from the GDQuest fragment shader:
```glsl
float mask = texture(texture_mask, UV).r;
vec2 time_pan = vec2(0.2, 1.0) * (-TIME * time_scale);
float noise = texture(noise_texture, UV * texture_scale + time_pan).r;
float alpha = noise * mask;
alpha += COLOR.a - 1.0;          // erosion via vertex/modulate alpha
alpha = clamp(alpha, 0.0, 1.0);
ALPHA = smoothstep(0.0, edge_softness, alpha);
// color: ALBEDO + EMISSION from a gradient texture sampled by noise/UV.y
```

The 2D rewrite drops the spatial vertex billboarding entirely (we're already in 2D top-down), replaces `world_coord.xy` with `UV`, replaces `COLOR.a` erosion with a script-driven `dash_strength` uniform, and samples a `Gradient` (or pre-baked `GradientTexture1D`) for the fire color ramp instead of vertex color.

### Feel modes — full specification

The brainstorm requested **all four** modes implemented as a `feel_mode` enum on `DashConfig`. Each mode answers a single question: *how does the dash interact with thrust, drag, and steering during the burst?*

| Mode | `feel_mode` value | Behavior during burst |
|---|---|---|
| **Locked-heading** | `0` | Apply `velocity = transform.y * impulse_speed` once on start. Disable steering and player thrust input until burst ends. Drag still applies (so the burst decays naturally). The "on rails" cannon-launched feel. |
| **Steerable** | `1` | Apply same impulse on start. Player keeps full steering and forward-thrust input. Drag still applies. Trail curves with the ship. |
| **Velocity-aligned** | `2` | Apply `velocity += velocity.normalized() * impulse_speed` (or fall back to `transform.y` if velocity ≈ 0). Player keeps steering. Drift-dash. |
| **Overspeed-cap** | `3` | Apply `velocity += transform.y * overspeed_impulse`, AND temporarily multiply `linear_drag` toward 1.0 (less drag) so the burst lasts longer naturally. **Note**: there is currently **no `max_speed` cap** in [scripts/ship.gd:36-58](../../scripts/ship.gd#L36); the brainstorm name "overspeed-cap raise" is therefore semantically a misnomer for this codebase. We approximate it by **temporarily relaxing drag** rather than introducing and lifting an artificial cap. ADR candidate: `docs/decisions/2026-04-07-dash-overspeed-via-drag-relax.md`. |

All four share: a single `_dash_active` flag, a single `_dash_remaining` timer, and a single fire-quad lifecycle. Only the `_physics_process` branch differs. Implemented as a `match` on `_config.feel_mode` inside `_physics_process` once `_dash_active` is true.

## Technical Approach

### Architecture

```
project.godot                    + dash input action (Space, physical_keycode 32)
scripts/dash_config.gd           + new Resource (mirrors explosion_config.gd)
resources/dash_config.tres       + new Resource instance (overrides only)
shaders/stylized_fire.gdshader   + new canvas_item shader (2D port)
shaders/stylized_fire_material.tres + new ShaderMaterial
textures/dash/                   + new dir (or reuse if it exists)
  fire_noise.png                 + tileable Perlin/curl noise (filter_linear)
  fire_mask.png                  + radial vertical-falloff mask (filter_linear)
  fire_gradient.png              + 1D gradient ramp (filter_linear)
scripts/ship.gd                  ~ add dash state, _unhandled_input branch,
                                   _physics_process feel-mode dispatch,
                                   _process_dash_visuals(), camera shake
scenes/ship.tscn                 ~ add SternMarker (Marker2D), FireQuad (Sprite2D
                                   under SternMarker), wire material
scripts/dash_ghost.gd            + (optional, only if ghost spawn logic exceeds
                                   ~25 lines inside ship.gd)
```

No autoloads, no new scenes beyond the in-place ship.tscn additions. The dash is fully encapsulated in `ship.gd` + the `DashConfig` resource + shader/texture assets.

### Data flow (REVISED)

1. **Input**: `Space` press → `_unhandled_input` in [ship.gd](../../scripts/ship.gd) detects `dash` action → calls `_start_dash()`.
2. **`_start_dash()`**:
   - Guard on `_dash_ready`. If false, return.
   - Set `_dash_ready = false`. Schedule cooldown re-arm timer with `is_instance_valid` guard:
     ```gdscript
     get_tree().create_timer(_dash_config.cooldown).timeout.connect(func() -> void:
         if is_instance_valid(self):
             _dash_ready = true,
         CONNECT_ONE_SHOT)
     ```
   - Set `_dash_active = true`, `_dash_remaining = _dash_config.duration`.
   - Apply initial impulse based on `feel_mode`. For VELOCITY_ALIGNED, fall back to `transform.y` if `velocity.length() < 1.0`.
   - **(Optional, if `freeze_frames > 0`)**: set `Engine.time_scale = 0.0` and schedule restore after `freeze_frames * (1.0/60.0)` real-time seconds via `create_timer(t, true, false, true)`.
   - Show fire quad: push fire-config uniforms inline (TextureScale, TimeScale, EdgeSoftness, EmissionIntensity, ColorRamp), set `DashStrength = 0.0`, then `_fire_quad.visible = true`.
   - `_next_ghost_in = 0.0` (first ghost spawns next render tick).
   - Bump trauma: `_shake_trauma = max(_shake_trauma, _dash_config.shake_trauma_initial)`.
   - **(Optional)** `zoom_punch_target` tween if `zoom_punch_duration > 0`.
   - **(Optional)** `Engine.time_scale = time_dip_value` if `time_dip_value < 1.0 and time_dip_duration > 0`; schedule restore with guarded lambda.
3. **`_physics_process(delta)`** (while `_dash_active`):
   - Decrement `_dash_remaining`; if ≤ 0, `_end_dash()` and run one frame of normal movement (see Feel mode dispatch).
   - Otherwise dispatch on `feel_mode`, `move_and_slide()`, scaled pushback.
4. **`_process(delta)`** (always; runs visuals on render frames):
   - If `_dash_active`: `_tick_dash_visuals(delta)` — `t = 1.0 - (_dash_remaining / _dash_config.duration)`, `dash_strength = _dash_config.intensity_curve.sample_baked(t)` (O(1)), push `DashStrength` to material, decrement `_next_ghost_in`, spawn ghost if ≤ 0.
   - `_process_camera_shake(delta)` — trauma-squared pixel-snapped offset.
5. **`_end_dash()`**:
   - `_dash_active = false`.
   - **Reset shader state**: `_fire_quad.material.set_shader_parameter("DashStrength", 0.0)` BEFORE hiding, so the shared material doesn't retain stale state for the next burst.
   - `_fire_quad.visible = false`.
   - If a time dip is still active (corner case): `Engine.time_scale = 1.0` defensively.

### Live tunability — `DashConfig` shape

Mirrors [scripts/explosion_config.gd](../../scripts/explosion_config.gd) exactly: `class_name`, `extends Resource`, header docblock explaining hot-reload behavior, `@export_group(...)` for each section, typed `@export` and `@export_range` everywhere.

```gdscript
# scripts/dash_config.gd
class_name DashConfig
extends Resource

## Live-editable dash config. Open this resource's .tres in the Godot
## editor while the game runs — changes propagate to the running game
## via the shared Resource cache. Changes apply on the NEXT dash; an
## in-flight burst keeps the values it started with.

enum FeelMode { LOCKED_HEADING, STEERABLE, VELOCITY_ALIGNED, OVERSPEED_CAP }

@export_group("Core Motion")
@export var feel_mode: FeelMode = FeelMode.LOCKED_HEADING
@export_range(50.0, 800.0, 5.0) var impulse_speed: float = 280.0
@export_range(0.05, 1.5, 0.01) var duration: float = 0.35
@export_range(0.1, 5.0, 0.05) var cooldown: float = 1.2
@export_range(0.0, 1.0, 0.005) var overspeed_drag: float = 0.995  # OVERSPEED_CAP only — replaces ship's 0.97
@export var intensity_curve: Curve  # 0..1 over normalized burst time, drives dash_strength
@export_range(0, 8, 1) var freeze_frames: int = 0  # Celeste-style freeze on dash start (0 = off)
@export_range(0.0, 1.0, 0.05) var collision_pushback_scale: float = 0.0  # 0 = suppress pushback during dash

@export_group("Fire Shader")
@export var fire_texture_scale: Vector2 = Vector2(1.0, 1.0)
@export_range(0.5, 8.0, 0.1) var fire_time_scale: float = 3.0
@export_range(0.0, 1.0, 0.01) var fire_edge_softness: float = 0.1
@export_range(0.0, 4.0, 0.05) var fire_emission_intensity: float = 2.0
@export var fire_noise_texture: Texture2D
@export var fire_mask_texture: Texture2D
@export var fire_color_ramp: GradientTexture1D  # bind directly to ColorRamp sampler2D uniform
@export_range(0.0, 2.0, 0.01) var fire_quad_length_scale: float = 1.0  # stretches the quad along stern axis

@export_group("Ghost Trail")
@export_range(0, 16, 1) var ghost_count: int = 6
@export_range(0.01, 0.2, 0.005) var ghost_spawn_interval: float = 0.04
@export_range(0.05, 1.5, 0.01) var ghost_fade_duration: float = 0.45
@export var ghost_start_tint: Color = Color(1.0, 0.85, 0.5, 0.7)
@export var ghost_end_tint: Color = Color(0.6, 0.2, 0.1, 0.0)
@export var ghost_additive: bool = true

@export_group("Camera Feedback")
@export_range(0.0, 8.0, 0.5) var shake_magnitude_px: float = 3.0  # peak px offset at trauma=1.0
@export_range(0.0, 1.0, 0.01) var shake_trauma_initial: float = 0.6  # 0..1; offset = trauma^2 * mag
@export_range(0.5, 4.0, 0.05) var shake_trauma_decay: float = 2.0  # trauma -= decay * delta
@export_range(0.5, 1.5, 0.01) var zoom_punch_target: float = 1.1  # base zoom is 1.2
@export_range(0.0, 0.5, 0.01) var zoom_punch_duration: float = 0.18
@export_range(0.1, 1.0, 0.01) var time_dip_value: float = 1.0  # 1.0 = no dip
@export_range(0.0, 0.4, 0.01) var time_dip_duration: float = 0.0
```

**Trauma-squared shake** (Eiserloh, GDC 2016): instead of linear decay, use `offset = trauma * trauma * magnitude * unit_vec`. Trauma starts at `shake_trauma_initial`, decays linearly via `trauma -= shake_trauma_decay * delta`. The squared term gives a punchy attack and a smooth tail. See Research Insights appendix.

**Hot-reload constraint** (institutional learning, see [scripts/explosion_sprite.gd:122](../../scripts/explosion_sprite.gd#L122)): the top-level `DashConfig` resource MUST be referenced via `load()` (which returns the shared cached instance), NOT `preload()` and NOT `.duplicate()`. Sub-resources (`Curve`, `Gradient`, `Texture2D`) can be referenced directly; the Inspector mutates them in place. Only `.duplicate()` a sub-resource if the *script* writes back into it (we don't — we only sample curves and read gradient colors).

### Feel mode dispatch — pseudocode for ship.gd (REVISED)

Motion runs in `_physics_process`. **Visual** updates (shader uniform, camera shake decay) run in `_process` so they are smooth on high-refresh-rate displays.

```gdscript
# scripts/ship.gd  (replaces existing _physics_process at L36-L58)

func _physics_process(delta: float) -> void:
    var is_braking: bool = Input.is_action_pressed("move_back")

    if _dash_active:
        _dash_remaining -= delta
        if _dash_remaining <= 0.0:
            _end_dash()
            _apply_normal_movement(delta, is_braking)
            return

        var turn_input: float = Input.get_axis("turn_left", "turn_right")

        match _dash_config.feel_mode:
            DashConfig.FeelMode.LOCKED_HEADING:
                velocity *= linear_drag
                # thrust + steering input ignored during locked-heading burst
            DashConfig.FeelMode.STEERABLE:
                if not is_braking and Input.is_action_pressed("move_forward"):
                    velocity += transform.y * thrust * delta
                velocity *= linear_drag
                rotation += turn_input * turn_speed * delta
            DashConfig.FeelMode.VELOCITY_ALIGNED:
                velocity *= linear_drag
                rotation += turn_input * turn_speed * delta
            DashConfig.FeelMode.OVERSPEED_CAP:
                if not is_braking and Input.is_action_pressed("move_forward"):
                    velocity += transform.y * thrust * delta
                velocity *= _dash_config.overspeed_drag  # ~0.995 vs default 0.97
                rotation += turn_input * turn_speed * delta

        move_and_slide()
        _process_collision_pushback(_dash_config.collision_pushback_scale)
        return

    _apply_normal_movement(delta, is_braking)


func _apply_normal_movement(delta: float, is_braking: bool) -> void:
    # Extracted from the original _physics_process body (L36-L58).
    if not is_braking and Input.is_action_pressed("move_forward"):
        velocity += transform.y * thrust * delta
    if is_braking:
        velocity = velocity.move_toward(Vector2.ZERO, brake_decel * delta)
    else:
        velocity *= linear_drag
    var turn_input: float = Input.get_axis("turn_left", "turn_right")
    rotation += turn_input * turn_speed * delta
    move_and_slide()
    _process_collision_pushback(1.0)


func _process(delta: float) -> void:
    # Visuals run on render frames for smooth high-refresh-rate animation.
    if _dash_active:
        _tick_dash_visuals(delta)
    _process_camera_shake(delta)
```

**Notes**:
- `move_and_slide()` reads `velocity`, performs the slide, then **writes the post-collision velocity back into `velocity`** (per Godot 4.6 docs). The dash impulse must therefore be applied as the final mutation each tick — which it is, in the `match` arms above.
- `_process_collision_pushback(scale)` wraps the existing pushback loop at [scripts/ship.gd:53-58](../../scripts/ship.gd#L53), multiplying the `push` vector by `scale`. During a dash, `scale = collision_pushback_scale` (default `0.0` = suppressed) so a 280 px/s impulse into an enemy doesn't rebound chaotically.
- Last frame of a burst: `_end_dash()` runs, then `_apply_normal_movement` runs the same physics tick. Cleaner than the original "fall through to nothing" pattern.

### Stern marker — must be added

There is no stern marker in [scenes/ship.tscn](../../scenes/ship.tscn) today. Add one:

```
[node name="SternMarker" type="Marker2D" parent="."]
position = Vector2(0, -28)   # verify in editor: stern is opposite the +Y thrust axis

[node name="FireQuad" type="Sprite2D" parent="SternMarker"]
position = Vector2(0, 0)
texture = ExtResource("fire_quad_texture")  # a 1×1 white pixel or a full-quad placeholder
material = ExtResource("stylized_fire_material")
visible = false
z_index = 1
```

**Forward direction is `+transform.y`** in player ship.gd (see [scripts/ship.gd:40](../../scripts/ship.gd#L40)) — opposite the convention enemy_ship uses. Stern is therefore `-Y` in the ship's local frame. **Verify in editor before committing**: open ship.tscn, drop a temporary Marker2D at `(0, -28)`, run the project, and confirm it appears behind the ship as it sails forward.

### Ghost trail — implementation note (REVISED)

Ghosts must be **reparented to a world-space container** when spawned, not left as children of `Ship`. Source sprites and the container are cached in `_ready()` for cheaper per-spawn cost.

```gdscript
# scripts/ship.gd

# Cached at _ready() — eliminates per-spawn NodePath construction.
@onready var _ghost_sources: Array[Sprite2D] = [$HullSprite, $SailSprite]
@onready var _ghost_container: Node2D = get_parent() as Node2D  # asserted non-null in _ready

var _ghost_additive_material: CanvasItemMaterial  # initialized in _ready, see below


func _spawn_ghost() -> void:
    if _ghost_container == null:
        return
    for src: Sprite2D in _ghost_sources:
        var ghost: Sprite2D = Sprite2D.new()
        ghost.texture = src.texture
        ghost.region_enabled = src.region_enabled
        ghost.region_rect = src.region_rect
        ghost.centered = src.centered
        ghost.offset = src.offset
        ghost.global_transform = src.global_transform  # preserves position, rotation, scale chain
        ghost.modulate = _dash_config.ghost_start_tint
        ghost.z_index = src.z_index - 1
        if _dash_config.ghost_additive:
            ghost.material = _ghost_additive_material  # shared, no per-ghost allocation
        _ghost_container.add_child(ghost)
        var tw: Tween = ghost.create_tween()
        tw.tween_property(ghost, "modulate", _dash_config.ghost_end_tint, _dash_config.ghost_fade_duration)
        tw.tween_callback(ghost.queue_free)
```

In `_ready()`:
```gdscript
assert(_ghost_container != null, "Ship: parent must be a Node2D world container")
for src in _ghost_sources:
    assert(src != null, "Ship: a ghost-source Sprite2D is missing")
_ghost_additive_material = CanvasItemMaterial.new()
_ghost_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
```

The cached `Array[Sprite2D]` makes the set tunable in code (start with hull + sail; add `$NestSprite` etc. if we want a fuller silhouette) without runtime string lookups.

### Camera shake — trauma-squared, pixel-snapped, on `Camera2D.offset`, ticked from `_process`

The Camera2D in [scenes/ship.tscn:91-94](../../scenes/ship.tscn#L91) has `position_smoothing_enabled = true`. **Shake must use `Camera2D.offset`, not `position`** — Godot 4.6 docs confirm `offset` is applied post-smoothing and bypasses the smoothing filter.

**Why `_process`, not `_physics_process`:** writing offset at 60Hz while the renderer draws at 144+Hz produces visible stutter. Decay trauma per render frame so the shake animates smoothly at any refresh rate.

**Trauma-squared model** (Eiserloh, GDC 2016): trauma decays linearly; the *visual* magnitude is `trauma * trauma * shake_magnitude_px`. Squaring gives a punchy attack with a soft tail.

```gdscript
func _process_camera_shake(delta: float) -> void:
    if _shake_trauma <= 0.0:
        if _camera.offset != Vector2.ZERO:
            _camera.offset = Vector2.ZERO
        return
    _shake_trauma = max(0.0, _shake_trauma - _dash_config.shake_trauma_decay * delta)
    var amplitude: float = _shake_trauma * _shake_trauma * _dash_config.shake_magnitude_px
    _camera.offset = Vector2(
        roundf(randf_range(-amplitude, amplitude)),
        roundf(randf_range(-amplitude, amplitude))
    )
```

In `_start_dash`: `_shake_trauma = max(_shake_trauma, _dash_config.shake_trauma_initial)` (`max` so re-trigger never reduces an in-flight shake).

`roundf()` keeps the offset on whole-pixel boundaries — required because the project runs viewport `640×360` at 2× integer scale with `snap_2d_transforms_to_pixel` enabled. Mirrors the snap idiom at [scripts/enemy_ship.gd:128-130](../../scripts/enemy_ship.gd#L128).

**Future polish (deferred):** swap `randf_range` for two `FastNoiseLite.get_noise_1d(time * freq + seed_axis)` calls per axis. Perlin shake reads as more "earthquake", random reads as "vibration". Out of scope for v1.

### Shader file pair

`shaders/stylized_fire.gdshader` (canvas_item, snake_case filename, PascalCase uniforms per [CLAUDE.md](../../CLAUDE.md)):

```glsl
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D NoiseTexture : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D MaskTexture : hint_default_white, filter_linear;
uniform sampler2D ColorRamp : hint_default_white, filter_linear;
uniform float TimeScale : hint_range(0.5, 8.0) = 3.0;
uniform vec2 TextureScale = vec2(1.0, 1.0);
uniform float EdgeSoftness : hint_range(0.0, 1.0) = 0.1;
uniform float EmissionIntensity : hint_range(0.0, 4.0) = 2.0;
uniform float DashStrength : hint_range(0.0, 1.0) = 0.0;  // script-driven 0->1->0

void fragment() {
    float mask = texture(MaskTexture, UV).r;
    vec2 pan = vec2(0.2, 1.0) * (-TIME * TimeScale);
    float n = texture(NoiseTexture, UV * TextureScale + pan).r;
    float a = n * mask;
    a += DashStrength - 1.0;             // script-driven erosion
    a = clamp(a, 0.0, 1.0);
    a = smoothstep(0.0, EdgeSoftness, a);
    vec3 ramp = texture(ColorRamp, vec2(1.0 - UV.y, 0.5)).rgb;
    COLOR = vec4(ramp * EmissionIntensity, a);
}
```

`shaders/stylized_fire_material.tres` follows the [shaders/ripple_material.tres](../../shaders/ripple_material.tres) format with `shader_parameter/<Name> = value` lines for any non-default overrides. Bind the three sampler2D uniforms (`NoiseTexture`, `MaskTexture`, `ColorRamp`) to ExtResources at material creation time, but allow `dash_config.gd` exports to override them at runtime via `_fire_quad.material.set_shader_parameter("ColorRamp", _dash_config.fire_color_ramp)` etc. inside `_start_dash`. Hot-reload of the .tres values then propagates through the shared cache.

**Material sharing decision** (ADR candidate): the `FireQuad` will reference `stylized_fire_material.tres` directly (shared instance). The cooldown guarantees no overlapping bursts, and `DashStrength` is reset to 0 each burst, so shared state is safe. Document this in `docs/decisions/2026-04-07-fire-material-shared-instance.md`.

### Implementation Phases

#### Phase 1 — Mechanics-only foundation (no visuals)

**Goal**: dash works mechanically, all four feel modes selectable, cooldown enforced. No fire, no ghost, no camera effects.

Tasks:
- Add `dash` action to [project.godot](../../project.godot) `[input]` section (use Project Settings → Input Map in editor; **don't hand-edit**, per the project.godot warning at L2-L3).
- Create [scripts/dash_config.gd](../../scripts/dash_config.gd) with **only the Core Motion group** populated (the rest of the @exports stay declared but unused for now).
- Create [resources/dash_config.tres](../../resources/dash_config.tres) — empty `[resource]` section, all defaults from script.
- Create a starter `intensity_curve` resource at `resources/dash_intensity_curve.tres` (or leave null and let code default to a constant 1.0 if null).
- Modify [scripts/ship.gd](../../scripts/ship.gd):
  - Add `@export var dash_config: DashConfig` and assert in `_ready()`.
  - Add state vars: `var _dash_ready: bool = true`, `var _dash_active: bool = false`, `var _dash_remaining: float = 0.0`.
  - Add `dash_started`/`dash_ended` signals.
  - Add `_unhandled_input` branch for `dash` action.
  - Add `_start_dash()`, `_end_dash()`, `_apply_normal_movement(delta, is_braking)` (refactor of existing L36-L58), and the `match` dispatch in `_physics_process`.
- Wire `dash_config` on the `Ship` node in [scenes/ship.tscn](../../scenes/ship.tscn) to `res://resources/dash_config.tres`.
- Validate via MCP: `run_project` → drive ship around → press space → verify all 4 modes feel distinct → `get_debug_output` for zero errors → `stop_project`.
- **Phase exit criterion**: dash works, cooldown enforces, all 4 feel modes selectable from Inspector while game runs and have visibly different physics.

**Estimated complexity**: small. ~80 lines added to ship.gd, one new script, one new .tres.

#### Phase 2 — Stylized fire exhaust

**Goal**: visible fire quad at the stern, animating during the burst, intensity ramping with `intensity_curve`.

Tasks:
- Source/create the three textures:
  - `textures/dash/fire_noise.png` — tileable Perlin or curl noise, 256×256, grayscale. Either generate via Godot's `NoiseTexture2D` baked to PNG, or copy `WispyNoise.png` from the GDQuest repo (BSD-licensed, retain attribution in `docs/credits.md` if not already).
  - `textures/dash/fire_mask.png` — 128×256 grayscale, white center with vertical falloff to black at edges. Hand-painted or scripted.
  - `textures/dash/fire_gradient.png` — 256×1 1D ramp from bright yellow → orange → deep red → transparent at the top (or bake from a Godot `Gradient` via `GradientTexture1D` exported to PNG).
  - All three: `filter_linear` in import settings (override the project's Nearest default).
- Create [shaders/stylized_fire.gdshader](../../shaders/stylized_fire.gdshader) (full code in §"Shader file pair" above).
- Create [shaders/stylized_fire_material.tres](../../shaders/stylized_fire_material.tres) referencing the three textures.
- Add `SternMarker` (Marker2D) and `FireQuad` (Sprite2D) child nodes to [scenes/ship.tscn](../../scenes/ship.tscn). Set `FireQuad.material = stylized_fire_material`. Pick a placeholder white-quad texture sized to roughly the dimensions of the desired flame (e.g. 32×64 px).
- **Verify stern direction in editor**: with the ship facing "up" in the scene viewport, the SternMarker should sit at the *bottom*. If thrust is `+transform.y` and ship visually moves "up" on input, then `-Y` is "down on screen" — the stern. If reversed, flip the marker position sign.
- In ship.gd:
  - Add `@onready var _fire_quad: Sprite2D = $SternMarker/FireQuad` (assert non-null).
  - Add `_apply_fire_config()` — pushes `TimeScale`, `TextureScale`, `EdgeSoftness`, `EmissionIntensity` from `_config` to the material at dash start.
  - Add `_tick_dash_visuals(delta)` — increments `_dash_elapsed`, samples `_config.intensity_curve.sample(t)`, sets `DashStrength` uniform.
  - In `_start_dash`: `_fire_quad.visible = true`. In `_end_dash`: `_fire_quad.visible = false`.
- Add `@export_group("Fire Shader")` exports to `dash_config.gd`.
- Validate via MCP: dash → fire visibly bursts at stern → ramps in/out smoothly → no errors.
- **Phase exit criterion**: fire visibly fires from the stern, intensity follows the curve, editing `dash_config.tres` while running visibly changes the next burst's appearance.

**Estimated complexity**: medium. The 2D shader port and texture sourcing are the main risk; one afternoon of iteration if textures are clean.

#### Phase 3 — Ghost trail + camera feedback + polish (merged)

**Goal**: ship the remaining visual stack and lint-clean the code. Phases 3, 4, 5 of the original plan are merged because each was ~30 LOC and they don't gate one another.

Tasks:
- **Ghost trail**:
  - Add `@export_group("Ghost Trail")` exports to `dash_config.gd`.
  - Add `@onready var _ghost_sources` and `@onready var _ghost_container` cached refs (see §"Ghost trail" pseudocode). Assert non-null in `_ready()`.
  - Initialize `_ghost_additive_material: CanvasItemMaterial` in `_ready()`.
  - Add `_spawn_ghost()` and `_next_ghost_in` ticking inside `_tick_dash_visuals`.
- **Camera feedback**:
  - Add `@export_group("Camera Feedback")` exports.
  - Add `@onready var _camera: Camera2D = $Camera2D` (asserted).
  - Add `_shake_trauma: float = 0.0` state.
  - Add `_process_camera_shake(delta)` (trauma-squared, see §"Camera shake") to the existing `_process(delta)` method.
  - In `_start_dash`: bump trauma; (optional) zoom-punch tween; (optional) `freeze_frames` and `time_dip` with `create_timer(t, true, false, true)` and guarded restore lambdas. Defensive `_exit_tree` reset of `Engine.time_scale = 1.0`.
- **Polish**:
  - Run `gdformat scripts/ship.gd scripts/dash_config.gd` and `gdlint` on the same. Fix anything flagged.
  - Add `// TODO(post-mvp):` comments in `stylized_fire.gdshader` for unwired GDQuest features (wind direction, fuel pulse).
  - Add a 3-line comment at the top of `stylized_fire_material.tres` explaining the shared-instance + cooldown safety invariant. (No standalone ADR — too small.)
  - Write the one ADR that remains: `docs/decisions/2026-04-07-dash-overspeed-via-drag-relax.md` — explains why mode 4 relaxes drag instead of introducing a max-speed cap (the codebase has no cap to lift).
- **Validation** via MCP: full play session, all 4 feel modes, ghosts spawn/fade/free, camera shake/zoom/dip work and disable cleanly at 0, no leaked nodes after 30+ dashes, zero errors in debug output.
- **Phase exit criterion**: all 4 integration test scenarios pass; gdformat/gdlint clean; ADR written.

**Estimated complexity**: medium. ~80 LOC across ship.gd + dash_config.gd, plus tunable .tres values.

## Alternative Approaches Considered

1. **Use the GDQuest spatial shader as-is via SubViewport** — the codebase already does this for explosions (`explosion_effect.tscn` runs `GPUParticles3D` in a SubViewport rendered to 2D). We could spawn a 3D MeshInstance3D + the original spatial shader inside a SubViewport and composite to 2D the same way. **Rejected**: the SubViewport pipeline has a known premultiplied-alpha gotcha (see [docs/solutions/subviewport-premultiplied-alpha.md](../solutions/subviewport-premultiplied-alpha.md)) and adds 3D scene management complexity for a flame that's fundamentally a flat 2D effect. The 2D canvas_item rewrite is simpler, lighter, and more pixel-art-friendly.

2. **GPUParticles2D for the exhaust** — would give per-particle motion variance "for free". **Rejected**: heavier on the GPU, overlaps stylistically with the existing explosion VFX (which we want to keep distinct), and harder to tune to match the GDQuest stylized look without significant per-particle shader work.

3. **Use a Line2D ribbon for the trail instead of sprite clones** — would integrate with the existing wake/trail system. **Rejected** by the brainstorm in favor of classic 2D dash afterimages, which read more clearly as "I dashed".

4. **State machine extracted into its own scene/script** — cleaner architecture if dash logic balloons. **Deferred**: dash logic estimated at ~150 lines added to ship.gd, well under the threshold where extraction pays for itself. Revisit if Phase 5 ends up over 250 lines.

## System-Wide Impact

### Signal chain
- **No new signals on day 1.** `dash_started`/`dash_ended` removed per the deepen review — no listeners exist (no audio system, no HUD listening for dash). Add when a consumer arrives, in the same commit. Per project convention, signals exist to decouple from existing consumers, not to anticipate hypothetical ones.
- **Existing signal interactions**: none broken. The dash never emits `cannon_fired` or `mine_dropped`. The four feel modes still call `move_and_slide()`, so collision pushback at [ship.gd:53-58](../../scripts/ship.gd#L53) still runs (now wrapped in `_process_collision_pushback(scale)` and scaled to 0 during dash by default, configurable via `collision_pushback_scale`).
- **Resource cache**: `DashConfig` joins `ExplosionConfig` as a hot-reloadable shared resource. Editing one does not affect the other.

### Error propagation
- `assert(dash_config != null, "Ship: dash_config Resource is missing")` in `_ready()` catches missing wiring at startup, matching [ship.gd:30-32](../../scripts/ship.gd#L30) style.
- `assert(_fire_quad != null, ...)`, `assert(_camera != null, ...)` for the new @onready refs.
- `Curve` and `Gradient` exports may be `null` if the .tres doesn't override them. Code path for `intensity_curve == null` falls back to constant 1.0; `fire_color_gradient == null` falls back to white. Document fallbacks in docstrings.
- No exceptions can bubble out of the dash: input handler is fire-and-forget, timers use lambdas, tweens self-clean.

### State lifecycle risks
- **Engine.time_scale leak**: if `_start_dash` sets `Engine.time_scale = 0.5` and the player closes the window before the restore timer fires, the next session is unaffected (project-level setting unchanged). But mid-session, if the ship is freed before the timer fires, time stays scaled. **Mitigation**: always pair `Engine.time_scale = ...` with a `SceneTreeTimer` whose timeout is connected with `CONNECT_ONE_SHOT`, and on `Ship._exit_tree()` reset `Engine.time_scale = 1.0` defensively.
- **Ghost sprite leak**: if `queue_free` somehow doesn't fire (tween cancellation), ghosts could pile up. **Mitigation**: cap total active ghosts via a `_active_ghost_count` counter; refuse to spawn beyond `ghost_count * 2`. Validate node count returns to baseline after a session of dashing.
- **Camera offset stuck**: if `_process_camera_shake` is interrupted mid-shake (e.g. by `_end_dash` clearing state), `_camera.offset` could be left non-zero. **Mitigation**: the function unconditionally resets to `Vector2.ZERO` when `_shake_remaining <= 0`, which runs every frame.
- **Material state**: shared `stylized_fire_material.tres` retains `DashStrength` from the previous burst. **Mitigation**: `_apply_fire_config()` resets all uniforms at the start of every dash. Cooldown ensures no overlap.

### Scene interface parity
- Currently no scenes other than `ship.tscn` should expose dash-like behavior. Enemy ships ([scripts/enemy_ship.gd](../../scripts/enemy_ship.gd)) deliberately don't dash. **No parity work needed.**
- If the design later introduces an enemy that *can* dash, the dash logic should be **extracted into a `DashController` Node child** that both ships can compose. Flag this in the ADR; do not pre-extract.

### Integration test scenarios

These are scenarios isolated unit tests would miss; verify each via MCP `run_project` + manual driving:

1. **Dash → mine collision** — dash directly into a sea mine. Expected: ship explodes (no i-frames). Verifies the dash doesn't accidentally suppress collision damage.
2. **Dash → braking mid-burst** — hold S during the burst. Expected: behavior depends on feel mode; LOCKED_HEADING ignores braking, STEERABLE/VELOCITY_ALIGNED/OVERSPEED_CAP obey it. Verifies the brake-vs-dash precedence in each mode.
3. **Dash → wall/enemy collision** — dash into the world boundary AND into an enemy ship. Expected: ship hits the obstacle, velocity zeros via `move_and_slide` collision response, dash visuals continue until timer expires, no chaotic rebound from `_process_collision_pushback(0.0)`. Verifies dash state vs physics state decoupling AND the pushback-suppression rule.
4. **Dash spam at cooldown boundary** — hold space. Expected: dash fires every `cooldown` seconds exactly (no drift, ±1 physics-frame quantization from input sampling). Verifies the `SceneTreeTimer` re-arm pattern.

Tests dropped from the original list:
- *Dash + cannon mid-burst*: the two `_unhandled_input` branches are textually independent and share no state; tests nothing meaningful.
- *Live-edit during burst*: hot-reload semantics are already proven by `ExplosionConfig`; re-verifying per-feature is ceremony.

## Acceptance Criteria

### Functional Requirements
- [x] `dash` input action exists in [project.godot](../../project.godot), bound to physical Space (`physical_keycode = 32`).
- [x] [scripts/dash_config.gd](../../scripts/dash_config.gd) exists, declares `class_name DashConfig`, extends `Resource`, mirrors [scripts/explosion_config.gd](../../scripts/explosion_config.gd) layout.
- [x] [resources/dash_config.tres](../../resources/dash_config.tres) exists and is wired to the `Ship` node via `@export var dash_config: DashConfig`.
- [ ] All 4 `FeelMode` enum values produce visibly distinct ship motion when selected from the Inspector during a running game. *(Phase 1: code in place; needs human visual playtest)*
- [x] Dash respects the configured cooldown (no chaining faster than `dash_config.cooldown` seconds), no drift.
- [x] Pressing `Space` while `_dash_ready == false` is a no-op (no error, no partial dash).
- [x] `_dash_active` starts and ends cleanly; no state leakage between bursts; `DashStrength` is reset to 0.0 in `_end_dash` BEFORE the FireQuad is hidden.
- [x] Cooldown re-arm lambdas (and existing cannon/mine lambdas) guarded by `is_instance_valid(self)` so a freed ship doesn't error.
- [x] ~~[shaders/stylized_fire.gdshader](../../shaders/stylized_fire.gdshader) exists, is `shader_type canvas_item`~~ → **REVISED**: now `shader_type spatial`, snake_case filename + PascalCase uniforms preserved.
- [x] `fire_color_ramp: GradientTexture1D` export type matches the shader's `ColorRamp: sampler2D` uniform — no Gradient → sampler2D mismatch.
- [x] `fire_texture_scale: Vector2` exports as `Vector2`, binding directly to the shader's `TextureScale: vec2` uniform.
- [x] Noise texture is a `NoiseTexture2D` resource (not a PNG); the shader uniform's `repeat_enable` hint applies to the procedural noise.
- [x] Fire effect emits only during a burst, ramps via `intensity_curve.sample_baked(t)`, and visibly disappears at burst end.
- [x] **3D pipeline**: spatial fire shader runs on a `GPUParticles3D` (QuadMesh + billboarded vertex shader) inside a 32×64 `SubViewport`, displayed via `SubViewportContainer` (mirrors [scenes/explosion_effect.tscn](../../scenes/explosion_effect.tscn)).
- [x] **`material_override` on the emitter** (not the shared QuadMesh sub-resource) — duplicated from the QuadMesh's material in `DashFireEffect._ready()`. Mirrors [scripts/explosion_effect.gd:74-77](../../scripts/explosion_effect.gd#L74) and [docs/solutions/godot-shared-mesh-surface-material.md](../solutions/godot-shared-mesh-surface-material.md).
- [x] **`render_target_update_mode = DISABLED`** when no dash is active; flipped to `UPDATE_ALWAYS` on dash start; flipped back after the particle lifetime elapses post-`stop()`. Avoids constant idle GPU draw of an empty 3D scene.
- [x] `_tick_dash_visuals` runs from `_process(delta)`, NOT `_physics_process`. *(`_process_camera_shake` lands in Phase 3 — same `_process` method.)*
- [x] Ghost sprite afterimages spawn during the burst, fade smoothly, and `queue_free` themselves. *(Code path verified; node-count baseline check is part of human playtest.)*
- [x] Ghost source sprites and container are cached in `_ready()` (`_ghost_sources: Array[Sprite2D]`, `_ghost_container: Node2D`) — no per-spawn `get_node` or `get_parent`.
- [x] Ghost transforms set via `global_transform = src.global_transform`, NOT `scale = src.global_scale`.
- [x] Camera shake uses **trauma-squared** decay on `Camera2D.offset` (not `position`), pixel-snapped via `roundf`, resets to `Vector2.ZERO` when trauma reaches 0.
- [x] During dash, collision pushback in [scripts/ship.gd](../../scripts/ship.gd) (`_process_collision_pushback`) is scaled by `dash_config.collision_pushback_scale` (default 0.0 = suppressed).
- [x] Optional zoom punch, time-scale dip, and freeze-frames work when their durations/values are nonzero, and are cleanly disabled when zero.
- [x] `Engine.time_scale` always restored to `1.0` — restore lambdas are `is_instance_valid`-guarded, AND `_exit_tree` resets it defensively, AND `_end_dash` resets it if a dip is still active.
- [x] Editing `dash_config.tres` in the Godot editor while the game is running changes the **next** dash's behavior without restart. *(Mechanism inherits from the proven ExplosionConfig pattern.)*

### Non-Functional Requirements
- [ ] Static typing: every new var, parameter, and return type is annotated (per [CLAUDE.md](../../CLAUDE.md) GDScript conventions).
- [ ] All new @export node references and @export Resources are asserted in `_ready()`.
- [ ] No top-level `DashConfig` `.duplicate()` call (would sever hot-reload).
- [ ] Sub-resources (`Curve`, `Gradient`) are `.duplicate()`d only if mutated; current design only samples them, so no duplication needed.
- [ ] Member ordering in `ship.gd` and `dash_config.gd` follows the project convention (signals → enums → constants → exports → vars → _ready → _process → public → private).
- [ ] No new autoloads.
- [ ] No new scenes beyond in-place additions to [scenes/ship.tscn](../../scenes/ship.tscn).
- [ ] Pixel snapping preserved on the camera shake path.

### Quality Gates
- [ ] `gdformat --check scripts/ship.gd scripts/dash_config.gd` passes.
- [ ] `gdlint scripts/ship.gd scripts/dash_config.gd` passes.
- [ ] MCP `run_project` → `get_debug_output` shows zero errors after 30+ dashes across all 4 feel modes.
- [ ] All 6 integration test scenarios in §"Integration test scenarios" pass manual verification.
- [ ] One ADR per non-obvious decision (overspeed-cap-via-drag-relax; shared fire material).

## Success Metrics

- **Subjective**: dash feels satisfying enough that the developer-author *wants* to mash it during normal play.
- **Tunability**: a non-engineer playtester (or future-self) could change `impulse_speed`, `duration`, fire color, ghost count, and shake magnitude in under 60 seconds with the editor open and the game running, with no script changes.
- **Performance**: no measurable frame drop on mid-tier hardware during the burst (60 fps held).
- **Cleanliness**: at end of session, scene tree node count is identical to start (no leaked ghosts, no leaked timers).

## Dependencies & Risks

### Dependencies
- Godot 4.6 stable (already in use).
- No new third-party libraries.
- GDQuest StylizedFire repo — used as reference only, no code copied verbatim. If textures (`WispyNoise.png` etc.) are reused, retain the BSD license attribution in `docs/credits.md`.

### Risks
- **R1 — Stern direction ambiguity**: `+transform.y` is the player's forward direction (uncommon), but visual sprite layout has the flag at negative-Y. Misplacing the SternMarker is an obvious-on-sight bug; **mitigation**: visually verify in editor before committing Phase 2.
- **R2 — 2D shader port look mismatch**: the rewritten canvas_item shader may not visually match the GDQuest 3D demo. **Mitigation**: budget Phase 2 with iteration room; treat the first pass as a starting point and tune `EdgeSoftness`, `TextureScale`, gradient stops live.
- **R3 — Hot-reload silently broken**: if a future change accidentally `.duplicate()`s the top-level `DashConfig`, hot-reload silently stops working. **Mitigation**: add a comment in `dash_config.gd` and `ship.gd` `_ready()` flagging the constraint, and reference [scripts/explosion_sprite.gd:122](../../scripts/explosion_sprite.gd#L122) as the canonical pattern.
- **R4 — Ghost trail visual cost on low-end hardware**: spawning 6 sprites every 40ms = 150 sprites/sec. **Mitigation**: cap is configurable; default ghost_count = 6, fade_duration = 0.45s → ~14 simultaneous ghosts max. Trivial.
- **R5 — Engine.time_scale persisting on shutdown** — see "State lifecycle risks". Defensive reset in `_exit_tree`.
- **R6 — Smoothed camera + offset shake interaction**: untested combo in this codebase. **Mitigation**: integration test #4 + manual visual check; if shake feels laggy due to smoothing speed, document and pin smoothing speed during the burst as a follow-up tweak.

## Resource Requirements

- **Skills**: GDScript, Godot 4.6 ShaderLanguage (canvas_item), basic 2D shader debugging.
- **Assets to source/create**: 3 textures (noise, mask, gradient) — can be generated programmatically or sourced from GDQuest's BSD-licensed PNGs. Maybe 30 minutes if sourcing, longer if hand-painting.
- **No team coordination needed** — single-developer feature.

## Future Considerations

- **Audio hook**: `dash_started` signal is emit-ready for a future audio system to play a whoosh + fire roar.
- **Enemy dash**: if an enemy ever dashes, extract dash logic into a `DashController` Node and compose into both ship scenes.
- **Stamina meter**: if escape becomes too easy and the design wants a cost, the cooldown can be replaced with a stamina meter without touching the visuals/shader/ghost code at all — they're all driven from `_dash_active` and `_dash_remaining`.
- **Underwater / windy variants**: the shader's `TextureScale`, `TimeScale`, `ColorRamp` are uniform-driven, so weather/biome variants are a `set_shader_parameter` away.

## Documentation Plan

- **ADRs** (in `docs/decisions/`):
  - `2026-04-07-dash-overspeed-via-drag-relax.md`
  - `2026-04-07-fire-material-shared-instance.md`
- **Credits**: if reusing any GDQuest textures, append to `docs/credits.md` (or create) with BSD attribution.
- **CLAUDE.md**: no update needed unless a new pattern emerges (e.g. live-tunable Resource convention is worth promoting from tribal to documented).
- **Solutions log**: if the 2D shader port surfaces a non-obvious gotcha, write it to `docs/solutions/`.

## Research Insights (Deepen Appendix)

Distilled from 8 parallel review/research agents on 2026-04-07. The "Critical bugs" already merged into the plan body above are not duplicated here.

### Game-feel grounding

- **Celeste dash anatomy** (Maddy Thorson): 15 frames total = 3 freeze frames + 12 motion frames + 6 attack-window frames after. The freeze-frame trick at the *start* of a dash is the core juice — input captured, motion paused, then snap. Captured as the optional `freeze_frames: int` export (default 0). Tune once visuals feel right.
- **Hyper Light Drifter chain-dash window**: ~270ms. Useful target if we ever add chain-dashing (out of scope today, but the cooldown range supports it).
- **Trauma-squared shake** (Squirrel Eiserloh, GDC 2016 — *Math for Game Programmers: Juicing Your Cameras*): `offset = trauma² × magnitude × randVec`. Linear `trauma -= decay × delta`. Squaring gives a punchy attack and a smooth tail. Already merged into the camera shake spec above.
- **Perlin/Simplex shake vs `randf_range`**: Perlin reads as "earthquake", random as "vibration". Eiserloh recommends Perlin for screen shake; deferred to a post-MVP polish pass (the `randf_range` + `roundf` baseline is already pixel-art-friendly).

Sources:
- https://celeste.ink/wiki/Dashing
- http://www.mathforgameprogrammers.com/gdc2016/GDC2016_Eiserloh_Squirrel_JuicingYourCameras.pdf

### Godot 4.6 framework specifics

- **`SceneTree.create_timer(time_sec, process_always=true, process_in_physics=false, ignore_time_scale=false)`** — for the `time_dip` and `freeze_frames` restore timers we use `(t, true, false, true)` so the timer fires at wall-clock time even when `Engine.time_scale ≈ 0.0`. Without `ignore_time_scale=true`, a `time_scale = 0` freeze never restores. Confirmed against [Godot SceneTree docs](https://docs.godotengine.org/en/stable/classes/class_scenetree.html).
- **`Camera2D.offset` is applied post-smoothing**, bypassing `position_smoothing_enabled`. Writing to `position` is the smoothed path; writing to `offset` is the immediate path. This is the documented use case for screen shake. See [Godot Camera2D docs](https://docs.godotengine.org/en/stable/classes/class_camera2d.html) and Godot issue #68394 (camera smoothing jumps when writing position directly).
- **`CharacterBody2D.move_and_slide()` reads AND writes `velocity`** — after the call, `velocity` reflects what survived collisions. Therefore the dash impulse must be applied as the *last* mutation each physics tick, before `move_and_slide()`. The revised feel-mode dispatch is already correct on this point.
- **`Curve.sample_baked(t)` is O(1)** vs `Curve.sample(t)` which is O(log n). For per-frame use, prefer baked sampling. Godot bakes lazily on first `sample_baked` call. Merged into `_tick_dash_visuals`.
- **`Engine.time_scale` does NOT affect audio or `Time.get_ticks_msec()`.** Audio pitch scales independently via `AudioServer.playback_speed_scale`. We deliberately do not touch audio in v1 — the brainstorm didn't ask for it.
- **`load()` vs `preload()`**: both populate the same shared `ResourceCache`; `load()` returns the cached instance on hit. Hot-reload works because editor edits mutate the cached instance in place. **Never `.duplicate()` the top-level DashConfig** or you sever the link. Sub-resources (Curves, Gradients) only need duplication if mutated — we don't mutate them.

### Afterimage trail patterns

- **Spawn-and-free is fine** at typical dash rates. Pooling matters only above ~10 spawns/sec sustained. Our default = 6 ghosts × 2 sprites / 1.2s cooldown = ~10 spawns/sec **peak**, ~0/sec sustained. Skip the pool.
- **Shared `CanvasItemMaterial`** is safe and cheap — Godot does NOT fork it on assignment. All ghosts batch on the same RID.
- **Tween-on-modulate** is cheaper than per-ghost `ShaderMaterial` fades because shader materials force a unique material instance per ghost (no batching).
- **Pitfall**: `AnimatedSprite2D.duplicate()` keeps animation playing on the clone. Not relevant here (we clone plain `Sprite2D`s) but worth knowing.

Sources:
- https://forum.godotengine.org/t/sprite-after-image-in-2d-game/78758
- https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html

### Pseudocode bugs caught (already fixed in body)

The deepen reviewers caught 6 P0 bugs that would have failed gdlint, runtime-errored, or rendered incorrectly:
1. `Gradient` exported for a `sampler2D` shader uniform → impossible to bind. Fixed → `GradientTexture1D`.
2. `vec2 TextureScale` shader uniform with no Vector2 export. Fixed → `fire_texture_scale: Vector2`.
3. `velocity *= overspeed_drag if false else linear_drag` — dead-code ternary. Fixed → plain `linear_drag`.
4. `steering_dampen * 0.0` no-op multiplier on a misnamed export. Fixed → export removed entirely.
5. `_GHOST_SPRITE_NAMES: PackedStringArray` iterated as `StringName` (type mismatch). Fixed → cached `Array[Sprite2D]`.
6. `ghost.scale = src.global_scale` — assigns parent-space cumulative scale to a local field. Fixed → `ghost.global_transform = src.global_transform`.

### Timing fixes (already merged)

- Visuals + camera shake moved from `_physics_process` (60Hz) to `_process` (render rate). Without this, dash and shake stutter on 144Hz+ displays.
- `_end_dash` explicitly resets `DashStrength = 0.0` BEFORE hiding the FireQuad.
- Cooldown re-arm lambdas guarded by `is_instance_valid(self)`. Same fix recommended as a drive-by for the existing cannon/mine timers at [scripts/ship.gd:104-117](../../scripts/ship.gd#L104).
- `Engine.time_scale` reset paired in BOTH `_exit_tree` and the restore-timer lambda.

### Architecture decisions held (against extraction pressure)

The architecture reviewer recommended extracting dash logic into a `DashController` child Node rather than adding ~150 lines to ship.gd. **Held off, with note**: the codebase's other ship behaviors (cannon, mine, movement) all live in ship.gd; introducing a controller pattern for one feature is more deviation than the saved lines justify. If a second dashing entity (enemy ship dash) appears, extract then. Tracked as a follow-up in "Future Considerations".

### Pattern consistency confirmed

The pattern reviewer confirmed the plan correctly mirrors:
- `class_name`, `extends Resource`, `@export_group`, `@export_range` from [scripts/explosion_config.gd](../../scripts/explosion_config.gd).
- `load()` (not `preload()`) hot-reload from [scripts/explosion_sprite.gd:122](../../scripts/explosion_sprite.gd#L122).
- Snake_case shader filenames + PascalCase uniforms from [shaders/ripple.gdshader](../../shaders/ripple.gdshader).
- Pixel-snapped offsets via `roundf` from [scripts/enemy_ship.gd:128-130](../../scripts/enemy_ship.gd#L128).
- Cooldown lambda style from [scripts/ship.gd:114-117](../../scripts/ship.gd#L114).
- `move_and_slide()` ordering from [scripts/ship.gd:50](../../scripts/ship.gd#L50).
- Assertion message style ("Ship: X is missing") from [scripts/ship.gd:30-32](../../scripts/ship.gd#L30).

## Sources & References

### Origin
- **Brainstorm document**: [docs/brainstorms/2026-04-07-ship-dash-brainstorm.md](../brainstorms/2026-04-07-ship-dash-brainstorm.md) — key decisions carried forward: (1) all four feel modes implemented as a tunable enum; (2) DashConfig Resource mirrors ExplosionConfig live-tuning pattern; (3) classic 2D sprite afterimage trail (not Line2D ribbon); (4) no i-frames; (5) short tunable cooldown; (6) camera feedback included as fully optional layer.

### Internal references
- Ship script and movement: [scripts/ship.gd:1-117](../../scripts/ship.gd) — entire file. Critical lines: [L36-L58](../../scripts/ship.gd#L36) (`_physics_process` to refactor), [L40](../../scripts/ship.gd#L40) (forward = `+transform.y`), [L45](../../scripts/ship.gd#L45) (multiplicative drag), [L61-L67](../../scripts/ship.gd#L61) (input branches), [L114-L117](../../scripts/ship.gd#L114) (cooldown timer pattern).
- Ship scene: [scenes/ship.tscn](../../scenes/ship.tscn) — Camera2D at [L91-L94](../../scenes/ship.tscn#L91), HullSprite at [L19-L23](../../scenes/ship.tscn#L19), Marker2D format example at [L27-L46](../../scenes/ship.tscn#L27).
- DashConfig template: [scripts/explosion_config.gd:1-141](../../scripts/explosion_config.gd) — entire file is the canonical pattern.
- Hot-reload mechanism: [scripts/explosion_sprite.gd:9](../../scripts/explosion_sprite.gd#L9), [L122](../../scripts/explosion_sprite.gd#L122) — `load()` (not `preload()`) returns shared cached instance.
- `set_shader_parameter` convention: [scripts/explosion_effect.gd:158-173](../../scripts/explosion_effect.gd#L158).
- Tween + queue_free idiom: [scripts/displacement_stamps.gd:32-44](../../scripts/displacement_stamps.gd#L32).
- Pixel-snapped shake reference: [scripts/enemy_ship.gd:112-132](../../scripts/enemy_ship.gd#L112).
- Resource `.duplicate()` idiom: [scripts/trails.gd:30-32](../../scripts/trails.gd#L30).
- Shader file pair template: [shaders/ripple.gdshader](../../shaders/ripple.gdshader) + [shaders/ripple_material.tres](../../shaders/ripple_material.tres).
- Input action format example: [project.godot#L28-L32](../../project.godot#L28) (`move_forward`).
- Project conventions: [CLAUDE.md](../../CLAUDE.md).

### Institutional learnings (from `docs/solutions/`)
- [docs/solutions/shared-resource-mutation.md](../solutions/shared-resource-mutation.md) — `.duplicate()` mutated Resources. Applies to any Curve/Gradient mutation in the dash path (currently none planned, but flag if added).
- [docs/solutions/godot-shared-mesh-surface-material.md](../solutions/godot-shared-mesh-surface-material.md) — use `material_override` rather than mutating shared mesh materials. Relevant if FireQuad ever switches from a Sprite2D direct material to a MeshInstance2D-based pipeline.
- [docs/solutions/godot-alpha-scissor-vs-blend.md](../solutions/godot-alpha-scissor-vs-blend.md) — do **NOT** use `ALPHA_SCISSOR_THRESHOLD` in the fire shader. Smooth alpha needed for the smoke fade. The shader spec in §"Shader file pair" correctly uses `render_mode blend_mix` and writes `COLOR.a` directly.
- [docs/solutions/subviewport-premultiplied-alpha.md](../solutions/subviewport-premultiplied-alpha.md) — only relevant if we abandon the canvas_item port and fall back to the SubViewport pipeline (alternative #1). Factors into rejecting that alternative.

### External references
- GDQuest stylized_fire.gdshader (3D, BSD-licensed): https://github.com/gdquest-demos/godot-shaders/blob/main/godot/Shaders/stylized_fire.gdshader — used as a *visual reference* for the recipe (noise × mask + erosion + smoothstep), **not** copied verbatim due to spatial→canvas_item incompatibility.
- GDQuest StylizedFire textures: https://github.com/gdquest-demos/godot-shaders/tree/main/godot/Demos/StylizedFire — `WispyNoise.png`, `FireMask.png`, `FireGradient.tres` are candidates for direct reuse with attribution.
