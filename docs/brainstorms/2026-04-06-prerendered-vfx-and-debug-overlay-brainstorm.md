# VFX Performance Overhaul & Debug Stats Overlay

**Date:** 2026-04-06
**Status:** Draft

## What We're Building

### Feature 1a: GPU Particle Preloading (Quick Fix)

Warm GPU shader caches at startup by spawning invisible one-shot GPUParticles3D instances before gameplay begins. This eliminates the first-spawn shader compilation stall, which is especially severe on web/WebGL (see [godotengine/godot#87843](https://github.com/godotengine/godot/issues/87843)).

**Approach:** At `_ready()` in main.gd (or a dedicated preloader node), instantiate the `explosion_model.tscn` SubViewport off-screen, run particles once with transparent modulate, wait for completion, then free. This forces the explosion dissolve shader + particle process materials through the GPU compiler before the player fires.

**Limitations:** Preloading helps with first-spawn compilation stalls but does NOT reduce the ongoing per-broadside cost of 4+ concurrent SubViewport 3D renders. Desktop lag on subsequent broadsides would persist.

### Feature 1b: Pre-rendered Explosion Sprites (Full Fix)

Replace the real-time 3D SubViewport explosion system with pre-rendered 2D sprite animations. The existing `explosion_renderer.gd` tool captures frames from the same `explosion_model.tscn` used in-game, but the captured sprites are not wired into gameplay yet.

**Problem:** Every `ExplosionEffect.create()` call spawns a SubViewport + 3D rendering pipeline with GPUParticles3D and glow. A broadside fires 4 cannonballs = 4 SubViewports in one frame, causing visible lag spikes.

**Solution:** Use the renderer tool to pre-capture 5 explosion variants into a single combined atlas. Replace `ExplosionEffect` with a lightweight `Sprite2D`-based player that reads frames from the atlas via `region_rect` stepping (matching the existing ship spritesheet pattern).

### Feature 2: Debug Stats Overlay

A toggle-able performance overlay (F3) showing FPS, frame time, memory, and draw calls. Top-left corner, CanvasLayer at layer 90.

## Why This Approach

- **Two-pronged fix:** Preloader is low-effort and helps web/first-spawn. Sprites are the full fix for ongoing per-broadside cost. Runtime toggle lets users compare and choose.
- **Sprite-based VFX eliminates the entire 3D rendering cost** -- no SubViewport, no GPUParticles3D, no glow, no material duplication. A `Sprite2D` with `region_rect` animation is essentially free.
- **The renderer tool already exists** and uses the same 3D model (`explosion_model.tscn`), so visual fidelity is preserved.
- **One combined atlas** is more GPU-efficient than separate textures (single draw call, single texture bind).
- **`region_rect` stepping** follows the established `ShipConfig` spritesheet pattern -- no new animation system needed.
- **3 randomized variations per type + runtime rotation** provides enough visual variety without massive texture sizes.
- **Runtime toggle** keeps the real-time 3D explosions available for visual comparison and future development.

## Key Decisions

1. **4 distinct explosion types** (water impact and enemy hit merged):
   - Muzzle flash (tight cone, scale 0.25, high velocity)
   - Impact (45-degree spread, scale 1.0, low velocity) -- shared by water/enemy hits
   - Ship destruction (360 spread, scale 1.0, medium velocity)
   - Mine detonation (360 spread, scale 1.5, high velocity)

2. **3 variations per type** with different random seeds for visual diversity. Runtime picks one at random + applies rotation/flip.

3. **Combined atlas output** -- all variants in one PNG. 4 types x 3 variations x 16 frames @ 32x32 = 512x384 pixels.

4. **Renderer tool gets automated presets** -- a dropdown with the 4 named presets that auto-set parameters matching the in-game `ExplosionEffect.create()` calls. Batch capture with 3 seeds per preset outputs to one atlas.

4. **Align renderer to match game exactly** before capture:
   - Glow intensity: 1.5 -> 5.0, bloom: 0.3 -> 1.0
   - Turbulence: enable by default (matching game's `turbulence_enabled = true`)

5. **Runtime rotation** -- sprites are captured in one direction, rotated at spawn time to match `cone_dir`. For 360-degree spread (ship/mine), no rotation needed.

6. **Drift velocity preserved** -- the muzzle flash drift (`ship.velocity * 0.75`) is applied to the sprite's position each frame, same as today.

7. **GPU particle preloader** -- at startup, instantiate the explosion SubViewport off-screen, run particles once with transparent modulate, wait for completion, then free. Forces shader compilation before gameplay. Particularly important for web export.

8. **Runtime toggle** -- a setting (and/or debug key) to switch between real-time 3D explosions (with preloader) and pre-rendered sprites. The `ExplosionEffect.create()` API stays the same but dispatches to either implementation based on the toggle. Default: sprites.

9. **Debug overlay** -- F3 toggle, top-left, CanvasLayer layer 90, `mouse_filter = MOUSE_FILTER_IGNORE`. Shows FPS, frame time, physics time, draw calls, 2D/3D objects, memory, VRAM. Uses `_draw()` or Labels with the project font.

## Explosion Context Parameters

| Context | cone_spread | effect_scale | vert_velocity | drift | cone_dir |
|---------|------------|-------------|--------------|-------|----------|
| Muzzle flash | 0 | 0.25 | 100 | ship vel * 0.75 | fire direction |
| Water impact | 45 | 1.0 | 15 | none | ball direction |
| Enemy hit | 45 | 1.0 | 15 | none | ball direction |
| Ship destruction | 360 | 1.0 | 55 | enemy velocity | Vector2.UP |
| Mine detonation | 360 | 1.5 | 80 | none | Vector2.UP |

## Resolved Questions

1. **3 variations per type** -- capture 3 different random seeds per variant for visual variety. Runtime picks one at random + applies rotation.

2. **4 types, not 5** -- water impact and enemy hit share one animation (identical parameters). Types: muzzle flash, impact (water/enemy), ship destruction, mine detonation.

3. **Show all available stats** -- FPS, frame time, physics time, draw calls, 2D/3D objects, memory, VRAM. F3 toggles the full panel.

## Atlas Layout

4 types x 3 variations x 16 frames @ 32x32 = 12 rows x 16 cols = **512x384 pixels**

| Row | Type | Variation |
|-----|------|-----------|
| 0-2 | Muzzle flash | seeds 1-3 |
| 3-5 | Impact | seeds 1-3 |
| 6-8 | Ship destruction | seeds 1-3 |
| 9-11 | Mine detonation | seeds 1-3 |
