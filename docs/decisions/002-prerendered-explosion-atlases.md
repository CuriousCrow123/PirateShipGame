# ADR 002: Pre-rendered Explosion Atlases

**Date:** 2026-04-06
**Status:** Accepted

## Context

Explosions are rendered at runtime via `ExplosionEffect` — a Node2D that hosts a 3D `SubViewport` containing `GPUParticles3D` emitters (vertical + horizontal) drawn with a dissolve shader. Each spawn creates its own viewport, `WorldEnvironment`, duplicated materials, and a `Camera3D` that auto-zooms based on particle velocity.

This works visually but:
- Every explosion instantiates a 3D rendering pipeline inside a SubViewport
- Materials are duplicated per instance to avoid shared-resource mutation
- Particle simulation runs on the GPU even for small short-lived effects like muzzle flashes

The goal is to replace the real-time 3D rendering with pre-rendered sprite atlases for each explosion type, keeping the original look but eliminating per-spawn 3D overhead.

## Decision

Build a capture tool that runs the real `ExplosionEffect` inside a test scene, reads frames from its `SubViewport.get_texture().get_image()`, and bakes them to PNG atlases with metadata.

### Capture tool: [scripts/explosion_test.gd](../../scripts/explosion_test.gd)

For each of the 4 explosion types (`muzzle_flash`, `cannonball_impact`, `enemy_destruction`, `sea_mine`), captures 5 variations (different particle seeds) at 20 fps over the 1.2s lifetime → 25 frames per variation.

Pipeline per variation:
1. Spawn `ExplosionEffect` with the type's parameters (cone_dir, cone_spread, vert_velocity)
2. Wait 2 process frames for `_ready()` to restart particles
3. Capture `viewport.get_texture().get_image()` every `1/20 s` via `RenderingServer.frame_post_draw`
4. Threshold alpha below 10/255 to strip faint glow bleed
5. Compute union `Rect2i` of `get_used_rect()` across all frames — **skipping empty frames** (see [rect2i-merge-empty-bug.md](../solutions/rect2i-merge-empty-bug.md))
6. Crop each frame to the union rect + 2px padding
7. Record origin offset = `viewport_center - crop.position` (where the explosion spawn point lands in the cropped frame)

After all 5 variations of a type are captured, build that type's atlas immediately and clear the in-memory frames before moving to the next type. Holding all 20 variations' Image data simultaneously caused severe slowdowns.

### Atlas layout

Each explosion type gets one atlas with **one variation per row**. Rows have independent frame dimensions because each variation is trimmed to its own bounding box. Atlas width = `max(frame_w × frame_count)` across rows, height = `sum(frame_h)`.

```
muzzle_flash_atlas.png          2825×154   (5 rows, 25 frames each)
cannonball_impact_atlas.png      575× 96
enemy_destruction_atlas.png     1800×320
sea_mine_atlas.png              2900×390
```

### Metadata: `textures/explosions/atlas_meta.json`

Per type:
```json
{
  "muzzle_flash": {
    "atlas": "muzzle_flash_atlas.png",
    "atlas_size": [2825, 154],
    "cone_dir": [1.0, 0.0],
    "cone_spread": 0.0,
    "effect_scale": 0.25,
    "fps": 20,
    "variations": [
      { "row_y": 0, "frame_w": 82, "frame_h": 28, "frame_count": 25, "origin": [9, 8] },
      ...
    ]
  }
}
```

The `origin` field stores the spawn point within each cropped frame. To display a sprite in the game, set `Sprite2D.offset = -Vector2(origin.x, origin.y)` so the sprite's `position` becomes the explosion spawn point.

### Playback verification: [scripts/explosion_atlas_player.gd](../../scripts/explosion_atlas_player.gd)

Loads `atlas_meta.json` and plays all 20 variations in a 4×5 grid (types × variations) using `AtlasTexture.region` updates driven by elapsed time.

## Alternatives Considered

**Per-frame crops with per-frame origins** — Would eliminate all empty space but breaks `AnimatedSprite2D` which expects uniform frame sizes. Rejected as too complex to consume in-game.

**Single atlas for all types** — Simpler metadata, but the max frame dimensions across all types would bloat the atlas significantly. Sea mine frames are ~116×90 while cannonball impacts are ~20×20. Rejected.

**Alpha cutoff to trim outliers** — Tried values 3, 10, 25, 128, 225. The dissolve shader uses `ALPHA_SCISSOR_THRESHOLD = 0.5`, so surviving pixels have alpha in `[0.5, 1.0]` — no intermediate values to threshold away. The outliers expanding the bounding box were fully-opaque particles, not faint glow. The real fix was the empty-rect merge bug, not the cutoff.

## Consequences

**Positive:**
- Eliminates per-spawn 3D rendering, SubViewport creation, and material duplication
- Atlas pixel sizes match the 1:1 on-screen appearance (including `effect_scale` already baked in)
- 5 visual variations per type prevent repetition without increasing per-spawn cost
- Origin offsets preserved so directional explosions (muzzle flash firing right) still position correctly

**Negative:**
- Frozen seed — same 5 variations repeat; cannot dynamically tweak particle parameters at runtime
- Re-running the capture tool requires rebuilding atlases and updating metadata
- Glow/bloom is baked into the sprite; post-process effects (e.g. game-level bloom) will re-bloom the already-bloomed pixels
- The atlases replace `ExplosionEffect` for new spawns, but the runtime effect script is still in the codebase (not yet removed)

**Follow-up work:**
- Write a sprite-based explosion spawner that reads `atlas_meta.json` and replaces `ExplosionEffect.create()` calls
- Decide whether to keep `ExplosionEffect` as a fallback / re-capture tool
