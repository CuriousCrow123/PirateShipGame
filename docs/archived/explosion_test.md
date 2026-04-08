---
title: Archived — explosion_test
type: dev-tool (active baker)
status: still-active (DO NOT DELETE until Phase 11 step 47)
archived_on: 2026-04-07
source_files:
  - scenes/explosion_test.tscn
  - scripts/explosion_test.gd
artifacts_written:
  - textures/explosions/atlas_meta.json
  - textures/explosions/cannonball_impact_atlas.png
  - textures/explosions/enemy_destruction_atlas.png
  - textures/explosions/muzzle_flash_atlas.png
  - textures/explosions/sea_mine_atlas.png
---

# explosion_test

## Purpose

**This is an active atlas baker, not a scratchpad.** Captures every
explosion variant configured in `resources/explosion_config.tres` into a
sprite-sheet PNG that the live game then samples from at runtime. The
output PNGs in `res://textures/explosions/` are checked into git and
referenced by `explosion_atlas_player.gd`.

Re-run this scene whenever any of the following change and you want the
runtime to use the new appearance:

- The shader on `ExplosionEffect`'s SubViewport mesh
- Any field in `resources/explosion_config.tres`
- The `VARIANTS` list in this script (currently muzzle_flash,
  cannonball_impact, enemy_destruction, sea_mine)

## How to launch

Open `scenes/explosion_test.tscn` and run it directly (F6). The capture
runs unattended:

1. Loads `ExplosionConfig` from `res://resources/explosion_config.tres`.
2. For each variant in `VARIANTS`, instantiates 10 `ExplosionEffect`
   instances using the per-type tuning, plus two bake-time overrides:
   - `cone_dir` is forced to a fixed direction (`+x` for ground-aligned
     types, `+y` for vertical) so the saved atlas is unrotated and the
     runtime can rotate the sprite freely.
   - `effect_scale` is forced to `1.0` so the atlas is at native pixel
     density (the runtime applies game-time scale on top).
3. Captures frames at `CAPTURE_FPS = 20` for the variant's full
   `lifetime` from the config.
4. Trims each captured Image to its alpha bounding box (`TRIM_PADDING =
   2`, `ALPHA_CUTOFF = 10` strips faint glow bleed).
5. Stacks the trimmed frames as rows in one atlas PNG per variant.
6. Writes a per-variant entry into `_atlas_meta` and finally serialises
   it to `textures/explosions/atlas_meta.json`.

The `Title` Label at the top of the scene shows live capture progress
("Capturing: muzzle_flash_3...").

## Status

**Active development tool, do NOT delete** even after the refactor
lands. The bake step is necessary for any future explosion appearance
change. After Phase 11 step 47 it should move into
`addons/pirate_dev_tools/explosion_atlas_baker.tscn` (excluded from
export builds), but the *capability* must be preserved.

## Risks

- **Iterating `Image.get_used_rect()` semantics**: Godot 4.6's used-rect
  may include sub-pixel padding; the `TRIM_PADDING = 2` constant exists
  to defend against this. If a future Godot upgrade trims atlases too
  tightly, raise this constant first before debugging the shader.
- **`OUTPUT_DIR = "res://textures/explosions"`** writes inside the
  project, so `DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)` is
  required for first-run on a fresh checkout. The folder is in git so
  this is a no-op for collaborators.
- **`config["effect_scale"] = 1.0` override** is non-obvious and is
  documented in the script's `_capture_all_variants()` comment. Don't
  remove without understanding why.

## Replaces / replaced by

- Replaces: hand-painted explosion sprite-sheets (predates this tool).
- Will be replaced by: `addons/pirate_dev_tools/explosion_atlas_baker.tscn`
  (Phase 11 step 47), which will source-of-truth the same baker logic
  but live outside the shipped game tree.
