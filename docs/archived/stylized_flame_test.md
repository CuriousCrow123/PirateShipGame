---
title: Archived — stylized_flame_test
type: dev-tool (canonical authoring tool)
status: still-active (DO NOT DELETE until Phase 11 step 47)
archived_on: 2026-04-07
source_files:
  - scenes/stylized_flame_test.tscn
  - scripts/stylized_flame_test.gd
artifacts_written:
  - resources/dash_flame_material.tres   (ResourceSaver, on SAVE press)
  - resources/dash_flame_profile.tres    (lathe profile, on SAVE press)
  - resources/stylized_flame_snapshot.json (lathe profile snapshot)
---

# stylized_flame_test

## Purpose

**This is the canonical authoring tool** for the stylized 3D dash flame.
Two things are tuned here and persisted to disk:

1. **The shared `ShaderMaterial`** at
   `res://resources/dash_flame_material.tres` — also referenced by
   `scenes/dash_fire_model.tscn` at runtime, so any tuning saved here
   propagates directly to the live game.
2. **The lathe profile** (`bulge_radius`, `tail_length`, `dome_radius`)
   for the procedural `DashFlameLathe` mesh, persisted both as a
   `DashFlameProfile.tres` Resource and as a JSON snapshot at
   `res://resources/stylized_flame_snapshot.json` so the game-side
   scene can rebuild the same shape without instantiating a `.tres`
   loader.

The lathe geometry replaced an older sphere + cone composite that had a
visible normal-discontinuity seam at the joint. **Do not revert** to the
sphere+cone composite; the seam fix is the entire reason this tool
exists.

## How to launch

Open `scenes/stylized_flame_test.tscn` and run it directly (F6).

## Layout

- **Left** — `HiResContainer/HiResViewport/FlameSphere`: 256×256 native
  SubViewport, LINEAR upscale, full-quality reference.
- **Right** — `PixelContainer/PixelViewport/FlameSphere`: 64×64 native
  SubViewport, NEAREST upscale, what the game ships.
- **Right panel** — scrollable HSliders. Sliders write into the **same**
  shared `ShaderMaterial` instance referenced from disk, so both
  viewports update simultaneously and a save round-trips back into all
  consumers.

Note: the per-primitive `FlameCone` nodes are kept in the .tscn but
hidden in `_ready()`; the lathe `ArrayMesh` built by
`DashFlameLathe.build()` replaces them. Don't delete the cone nodes —
removing them would break the .tscn structure that the side-by-side
layout depends on.

## Critical implementation note (premultiplied alpha)

`_ready()` builds a `CanvasItemMaterial` with
`BLEND_MODE_PREMULT_ALPHA` and assigns it to **both**
`SubViewportContainer`s. This is required because the SubViewport with
`transparent_bg = true` writes premultiplied colors; the default
container blends straight-alpha and would multiply RGB by alpha a
second time, darkening partially-dissolved pixels to black instead of
fading them smoothly. Mirrors the same fix in
`scripts/dash_fire_effect.gd`.

If you ever build a replacement panel in the dev-tools addon, **port
this premult-alpha block first** — the WYSIWYG illusion is the entire
point of the tool.

## SAVE behaviour

The "SAVE" button writes:

- The current `ShaderMaterial` state to `dash_flame_material.tres` via
  `ResourceSaver.save()`.
- The current `DashFlameProfile` (sliders for `bulge_radius`,
  `tail_length`, `dome_radius`) to `dash_flame_profile.tres`.
- A JSON dump of the same lathe values to
  `stylized_flame_snapshot.json`.

A `_save_status_label` reports success/failure inline.

## Slider sections (truncated)

| Section | Parameters tuned |
|---|---|
| PROFILE | `bulge_radius`, `tail_length`, `dome_radius` |
| MOTION | (TODO — re-read script if you need exact list) |
| SHADER | various uniforms on the shared ShaderMaterial |

## Status

**Active canonical authoring tool, do NOT delete** until the
`pirate_dev_tools/stylized_flame_panel.tscn` replacement lands at
Phase 11 step 47, AND the replacement preserves the SAVE round-trip,
the dual viewport layout, and the premult-alpha blit.

## Replaces / replaced by

- Replaces: the original sphere+cone composite mesh (the seam fix is
  the reason this exists).
- Will be replaced by: `addons/pirate_dev_tools/stylized_flame_panel.tscn`
  (Phase 11 step 47).
