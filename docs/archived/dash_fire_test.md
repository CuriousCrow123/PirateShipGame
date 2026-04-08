---
title: Archived — dash_fire_test
type: dev-tool
status: still-active (DO NOT DELETE until Phase 11 step 47)
archived_on: 2026-04-07
source_files:
  - scenes/dash_fire_test.tscn
  - scripts/dash_fire_test.gd
---

# dash_fire_test

## Purpose

Side-by-side authoring environment for the GPU-particles dash flame effect
that plays at the back of the player ship during a dash. Lets a designer
tune ParticleProcessMaterial fields, the underlying ShaderMaterial uniforms,
the scale curve, and the start/end colors of the gradient ramp **live**,
with both a high-resolution and a pixel-art viewport rendered side-by-side
so the impact of each tuning change is visible at both authoring and
in-game resolutions simultaneously.

## How to launch

Open the project in the Godot editor and run `scenes/dash_fire_test.tscn`
directly (F6, or set as run scene temporarily). It is **not** wired into
`main.tscn` and never runs in shipping builds.

## Layout

- **Left column** — `HiResContainer/HiResViewport/FireEmitter`: a
  GPUParticles3D rendered at 128×256 native, no upscaling. Shows the raw
  spatial-shader output.
- **Centre column** — `PixelContainer/PixelViewport/FireEmitter`: the
  same emitter rendered into a 32×64 SubViewport that is then nearest-
  neighbour upscaled. This is the resolution and filter the live game
  uses for the dash flame.
- **Right column** — `ControlsScroll/Controls`: a scrollable VBox
  populated by `_build_controls()`. Each slider writes into BOTH
  emitters' `process_material` and `material_override` so left and
  right always reflect the same tuning.

## Important implementation note (resource safety)

`_ready()` calls `.duplicate(true)` on the `ParticleProcessMaterial`,
shader material, scale curve (via the `CurveTexture` wrapper) and
gradient (via the `GradientTexture1D` wrapper) **per emitter** before
writing any slider values. This prevents the panel's mutations from
leaking through shared sub-resources back into the on-disk `.tres` and
into other scenes. Whoever writes the panel-only equivalent in the
`pirate_dev_tools` addon (Phase 11 step 47) MUST preserve this pattern —
the same shader material is referenced by `dash_fire_effect.gd` at
runtime and a leaked mutation would corrupt the live ship's flame.

## Slider sections

| Section | Parameters tuned |
|---|---|
| EMISSION | `amount`, `lifetime`, `randomness`, `lifetime_randomness` |
| MOTION | `initial_velocity_min/max`, `linear_accel_min/max`, `spread`, `gravity_y`, `damping_min/max` |
| SCALE | `scale_min/max`, scale curve (start/peak Y/peak X/end) |
| SHADER | `EmissionIntensity`, `TimeScale`, `EdgeSoftness`, `TextureScale` x/y |
| COLOR (start) | gradient stop 0 RGBA |
| COLOR (end) | gradient stop N RGBA |

There is currently no SAVE button in this scene — tuning is meant to be
read from the slider state and then hand-written into the production
particle / shader material. (The flame **mesh profile** authoring tool
that DOES save back to disk is `stylized_flame_test.gd`, not this one.)

## Status

**Active development tool, do NOT delete** until the
`pirate_dev_tools/dash_fire_panel.tscn` replacement lands at Phase 11
step 47. After that, this scene + script may be removed (the addon
version will live outside `scenes/` and will be excluded from exports).

## Replaces / replaced by

- Replaces: nothing (was the original authoring environment).
- Will be replaced by: `addons/pirate_dev_tools/dash_fire_panel.tscn`
  (Phase 11 step 47).
