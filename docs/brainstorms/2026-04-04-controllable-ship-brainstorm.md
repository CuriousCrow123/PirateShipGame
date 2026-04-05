# Brainstorm: Controllable Player Ship

**Date:** 2026-04-04  
**Status:** Ready for planning

---

## What We're Building

A player-controlled pirate ship that moves through an effectively infinite ocean with floaty, momentum-based physics. The ship sprite comes from `textures/ships_spritesheet.png`. The water world uses dynamic tile chunk loading so the ocean extends wherever the ship sails. The existing water trail/wake system is rewired to follow the ship.

---

## Decisions Made

| Decision | Choice | Rationale |
|---|---|---|
| Controls | WASD / Arrow keys | W = thrust, A/D = rotate, S = brake/reverse |
| Movement feel | Floaty / momentum-based | Velocity accumulates; slow drag so ship coasts |
| Camera | Follows ship | World scrolls as ship explores |
| Trail | Rewired to ship | Wake appears behind ship instead of cursor |

---

## Approach

**CharacterBody2D with manual velocity integration** (recommended over RigidBody2D)

Implement a `Ship` scene as `CharacterBody2D`:
- Maintain `velocity: Vector2` and integrate thrust each `_physics_process` tick
- Rotation driven by A/D input, applied to `rotation` (not physics engine)
- Drag applied as `velocity *= linear_damping` each frame
- `move_and_slide()` handles future collision automatically

This gives precise control over the floaty feel (tune `thrust`, `drag`, `turn_speed` as exports) without fighting Godot's physics solver. RigidBody2D is harder to tune and less predictable for arcade-style games.

---

## Key Design Details

### Ship Sprite
- Source: `textures/ships_spritesheet.png` (546×1033px, 97 sprites packed)
- Generated from `ShipAssets/Ships/` and `ShipAssets/Ship parts/` PNG files
- Manifest with exact positions: `textures/ships_spritesheet.json`
- For the player ship: pick one of `ship (1–24).png` (all 66×113px, in top 4 rows of sheet)
- Use `region_rect` on Sprite2D to select the specific ship by index
- Swapping ships = changing one `Rect2(col*66, row*113, 66, 113)` value

#### Spritesheet layout summary
| Section | y offset | Cell size | Count | Notes |
|---|---|---|---|---|
| ships | 0 | 66×113 | 24 | Complete ships, 6 cols × 4 rows |
| dinghy_large | 454 | 20×38 | 3 | Damage states 1→3 |
| dinghy_small | 494 | 16×26 | 3 | Damage states 1→3 |
| hull_large | 522 | 50×108 | 4 | Damage states 1→4 |
| hull_small | 632 | 40×108 | 4 | Damage states 1→4 |
| sail_large | 742 | 66×47 | 24 | 6 cols × 4 rows |
| sail_small | 932 | 42×9 | 13 | Single row |
| cannon | 943 | 29×20 | 4 | cannon, ball, loose, mobile |
| crew | 965 | 22×22 | 6 | 6 crew variants |
| flags | 989 | 6×22 | 6 | 6 flag variants |
| misc | 1013 | 26×18 | 6 | nest, pole, wood 1–4 |

### Movement Parameters (tunable via @export)
```
thrust: float = 80.0       # acceleration force
turn_speed: float = 2.5    # radians/sec
linear_drag: float = 0.97  # applied each frame (0.9=heavy drag, 0.99=coasting)
```

### Camera
- Reparent the existing Camera2D to the Ship node (or add a new Camera2D as ship child)
- Use `position_smoothing_enabled` for smooth follow

### Water — Dynamic Chunk Loading
The current TileMap covers ~352×208 px (fixed). With a following camera the ship immediately sails off the edge. Solution:

- **Single TileMap node** for the whole world (no multiple nodes, no chunk objects)
- A `water_chunks.gd` script tracks which **chunk coordinates** are currently loaded
- Each chunk is `CHUNK_SIZE × CHUNK_SIZE` tiles (e.g. 16×16 = 256×256 px per chunk)
- Every `_process` frame: compute which chunks should be visible given the ship's position (a ring of `LOAD_RADIUS` chunks around the ship's current chunk), call `set_cell()` for new ones and `erase_cell()` for distant ones
- Water tile type: interior = open ocean tile; edge tiles remain valid within chunks (border detail can be added later for islands)
- Islands slot in naturally: a chunk's tile layout can be authored data or procedurally generated rather than all-water

**Shader fix required:** the current water shader almost certainly uses UV coordinates local to the TileMap node. With infinite tiles, UVs must be derived from **world-space position** so the water pattern is seamless across all chunks. This is a targeted uniform/varying change in `water_surface.gdshader` — sample position using `VERTEX` or a world-space `SCREEN_UV` equivalent rather than the default UV.

### Trail Rewire
- `trails.gd` already has `follow_target: Node2D` export — point it at the Ship
- The `follow_cursor.gd` script on WaterTrail is removed; WaterTrail follows the ship instead
- Two feature-flag exports added to `trails.gd`:
  - `origin_override: Node2D` — if set, samples trail position from this node instead of `follow_target` (e.g. a `Marker2D` at the stern); if null, uses ship center. No code branching needed at call sites.
  - `min_move_px: float = 0.0` — skip recording a new point if the ship moved less than this distance since the last frame. 0 = always record (current behavior).

---

## Scene Structure

```
Ship (CharacterBody2D)  ← new scene: scenes/ship.tscn
  ShipSprite (Sprite2D)
  SternMarker (Marker2D)   ← optional trail origin (feature flag)
  Camera2D
  CollisionShape2D

Main (Node2D)           ← existing main.tscn
  TileMap (water)       ← gets water_chunks.gd; follow_target → Ship
  Ship (instance)       ← add this
  WaterTrail (Node2D)   ← follows Ship position; follow_target → Ship
    TrailSprite
    SubViewport
      Line2D (trails.gd) ← origin_override → SternMarker (optional)
```

---

## Open Questions

None — all key decisions resolved.

---

### Ship-on-water feel (no bobbing)
Top-down at 320×180 — the ship sprite should NOT visually bob (Y offset = sliding, scale pulse = pixel shimmer at this resolution). The floating feel comes entirely from:
- The **water shader** animating waves under/around the ship
- The **existing Circle node** in the SubViewport creating displacement around the ship position (tune scale/opacity)
- The **wake trail** behind the ship when moving

No new ship animation needed. If the water shader interaction with the ship's position needs enhancement, that's a shader tweak, not a ship script feature.

---

## Out of Scope (Post-MVP)

- Enemy ships (can use other `ship (N).png` entries from the same spritesheet)
- Islands (chunk loader already supports non-water tile layouts per chunk)
- Collision with world geometry
- Ship health / damage states (hull_large/hull_small damage variants already in sheet)
