---
title: "feat: Controllable Player Ship with Infinite Ocean"
type: feat
status: completed
date: 2026-04-04
deepened: 2026-04-04
origin: docs/brainstorms/2026-04-04-controllable-ship-brainstorm.md
---

# feat: Controllable Player Ship with Infinite Ocean

## Enhancement Summary

**Deepened on:** 2026-04-04
**Agents used:** architecture, performance, timing, simplicity, resource-safety, best-practices (x2), framework-docs

### Key Improvements
1. **TileMap → TileMapLayer** — TileMap deprecated since Godot 4.3; use one TileMapLayer node per chunk for clean memory via `queue_free()`
2. **Thrust direction fix** — `-transform.y` (not `transform.y`) because sprite faces up and Godot Y points down
3. **YAGNI cuts** — removed 7 over-engineered items (follow_target.gd, origin_override, min_move_px, SternMarker, CollisionShape2D, hash-based tile selection, hysteresis buffer)
4. **motion_mode = MOTION_MODE_FLOATING** — required for top-down CharacterBody2D (skips floor/wall/ceiling detection)

### New Considerations Discovered
- Camera smoothing + pixel snapping can cause 1px jitter at 320×180 — test early
- `move_and_slide()` internally multiplies velocity by delta — do NOT pre-multiply
- Brake should use `velocity.move_toward(Vector2.ZERO, brake_decel * delta)` for guaranteed stop
- ShaderMaterial on water tiles must not be mutated at runtime without `.duplicate()`

---

## Overview

Add a player-controlled pirate ship that sails through an effectively infinite ocean. The ship uses floaty, momentum-based physics (CharacterBody2D). The ocean extends dynamically via chunk-loaded TileMapLayer nodes. The existing water trail/wake system is rewired from the mouse cursor to the ship. The camera follows the ship with smoothing.

## Problem Statement / Motivation

The project currently has a complete water rendering system (shader, trails, ripples) but no gameplay — just a mouse cursor moving over a fixed tile grid. This feature adds the core player entity and makes the world explorable.

## Proposed Solution

Three subsystems, implemented in order:

1. **Ship scene** — `CharacterBody2D` with sprite, movement script, camera
2. **Dynamic ocean chunks** — `water_chunks.gd` manages TileMapLayer nodes per chunk around the ship
3. **Trail rewire** — Point existing trail system at the ship, remove cursor-following

(See brainstorm: `docs/brainstorms/2026-04-04-controllable-ship-brainstorm.md`)

## Technical Considerations

### Ship Movement

**Controls:** WASD / Arrow keys. W = thrust forward, A/D = rotate, S = brake (no reverse).

**Thrust direction:** The ship sprite faces up. Godot's Y axis points down. Therefore the ship's forward direction is `-transform.y`:
```gdscript
velocity += -transform.y * thrust * delta
```

**`move_and_slide()` handles delta internally** — the velocity property should be in px/s. Do NOT multiply velocity by delta before calling `move_and_slide()`. The thrust line above adds acceleration (px/s/s * delta = px/s), which is correct.

**Drag:** `velocity *= linear_drag` per physics tick (e.g. 0.97). This models viscous water drag (exponential decay). At 60hz with `thrust=80, drag=0.97`:
- Terminal velocity ≈ `(80 / 60) / (1 - 0.97)` ≈ 44 px/s
- ~7 seconds to cross the 320px viewport — intentionally slow and floaty
- Coupled to physics tick rate (Godot default 60hz) — acceptable for MVP
- Future-proof option: `velocity *= pow(linear_drag, delta * 60.0)`

**Brake (S key):** Uses `velocity.move_toward(Vector2.ZERO, brake_decel * delta)` for guaranteed deceleration to zero. More satisfying than just increasing drag. S takes priority over W (no simultaneous thrust + brake).

**Rotation:** `rotation += Input.get_axis("turn_left", "turn_right") * turn_speed * delta`. Allowed while stationary (arcade feel).

**CharacterBody2D settings:**
- `motion_mode = MOTION_MODE_FLOATING` — required for top-down (skips floor/wall/ceiling)
- No CollisionShape2D for MVP — `move_and_slide()` still integrates velocity correctly with no collision shapes. Add shapes when collision is needed.

**Movement parameters (tunable via @export):**
```
thrust: float = 80.0         # acceleration (px/s/s)
turn_speed: float = 2.5      # radians/sec
linear_drag: float = 0.97    # per physics tick (0.9=heavy, 0.99=coasting)
brake_decel: float = 120.0   # deceleration when braking (px/s/s)
```

### Chunk Loading — Architecture

**TileMap is deprecated since Godot 4.3.** Use `TileMapLayer` instead. The recommended pattern is **one TileMapLayer node per chunk**:

```
Main (Node2D)
  ChunkContainer (Node2D)    ← water_chunks.gd
    Chunk_0_0 (TileMapLayer) ← created/freed at runtime
    Chunk_1_0 (TileMapLayer)
    ...
```

**Why per-chunk nodes instead of a single shared layer:**
- `queue_free()` guarantees full memory cleanup (known physics memory leak with `erase_cell()` on shared layers — [#79553](https://github.com/godotengine/godot/issues/79553))
- Each chunk's TileMapLayer shares the same TileSet resource (read-only, no `.duplicate()` needed)
- Scoped physics quadrant rebuilds per chunk
- Natural shader material isolation per chunk

**Algorithm:**
```
CHUNK_SIZE  = 16      # tiles per chunk edge (256×256 px)
LOAD_RADIUS = 2       # chunks to keep loaded around ship (5×5 grid max)
```

**Per-frame logic in `_process()`:**
1. Compute ship's current chunk coord: `Vector2i(floori(ship.global_position.x / (CHUNK_SIZE * 16)), floori(ship.global_position.y / (CHUNK_SIZE * 16)))`
2. If chunk coord hasn't changed since last frame, early-exit
3. Compute set of chunks within LOAD_RADIUS
4. For each new chunk: create a TileMapLayer, assign TileSet, call `set_cell()` for 16×16 tiles, set position, `add_child()`
5. For each chunk now beyond LOAD_RADIUS: `queue_free()` and remove from tracking dict
6. Update `_loaded_chunks: Dictionary`

**Tile selection:** Use a single interior ocean tile (`Vector2i(1, 20)` atlas coords) for all dynamically loaded water cells. Simple `randi()` variation is optional but not needed for MVP.

**Initialization:** Generate initial chunks in `_ready()` centered on `Vector2.ZERO` (or an exported spawn position). The first `_process()` frame will re-evaluate based on actual ship position. This avoids depending on ship node initialization order and prevents a first-frame empty-tile flash.

**Chunk TileMapLayer setup:**
```gdscript
var layer := TileMapLayer.new()
layer.tile_set = tile_set          # shared TileSet resource (read-only)
layer.position = Vector2(chunk_coord * CHUNK_SIZE * 16)
layer.material = water_material    # shared ShaderMaterial (read-only)
# ... set_cell() for all 16×16 tiles ...
add_child(layer)
```

### Water Shader — No Changes Needed

The water shader already uses world-space coordinates (`var_WorldPos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` at `shaders/water_surface.gdshader:54`). Dynamically created TileMapLayer nodes with the same ShaderMaterial will render seamlessly.

**Resource safety note:** The ShaderMaterial (`water_surface_material.tres`) is an external `.tres` loaded by path — shared across all chunk layers. This is correct as long as no code calls `set_shader_parameter()` at runtime. If runtime shader param changes are ever needed (e.g. day/night cycle), each layer must `.duplicate()` the material first.

### Trail Rewire

**WaterTrail follow mechanism:** Remove `follow_cursor.gd` from WaterTrail. Instead, add one line in `main.gd`'s `_process()`:
```gdscript
$WaterTrail.global_position = $Ship.global_position
```
No separate script needed for a single assignment.

**Trail system:** `trails.gd` already accepts any `Node2D` as `follow_target`. Rewire the export in the scene to point at the Ship node. No code changes to `trails.gd` for MVP.

**Circle node:** Stays at SubViewport center (128, 128). WaterTrail follows the ship, so the Circle displacement stays centered on the ship automatically.

**Trail clipping:** SubViewport is 256×256. At terminal velocity ~44 px/s with `max_length=20`, the trail extends ~15px — well within the 128px radius.

### Deferred Features (post-MVP)
These were in the original plan but cut for simplicity. Add when needed:
- `origin_override: Node2D` on `trails.gd` — sample trail from stern marker instead of ship center
- `min_move_px: float` on `trails.gd` — skip recording when ship barely moved
- `SternMarker (Marker2D)` — attachment point for origin_override
- `CollisionShape2D` — add when collision with islands/other ships is implemented
- Deterministic tile hashing — for consistent tile variation when revisiting areas
- Chunk load/unload hysteresis — if boundary thrashing ever becomes measurable

### Camera

- Camera2D as child of Ship, no smoothing (instant follow)
- Remove existing Camera2D from Main
- `ignore_rotation = true` (default) — camera stays axis-aligned while ship rotates

**Pixel snapping resolved:** Camera smoothing + `snap_2d_transforms_to_pixel` caused visible jitter. Fix: disable smoothing entirely — camera snaps to ship position each frame. Viewport doubled to 640×360 (from 320×180) to give the ship more room.

### Z-Ordering

| Node | z_index | Reason |
|---|---|---|
| TileMapLayer chunks | 0 | Water surface (bottom) |
| WaterTrail | 1 | Wake/ripple effect over water |
| Ship | 2 | Ship renders above wake |

### ViewportTexture Workaround

The existing workaround in `main.gd` (programmatic ViewportTexture for Godot 4.6 bug #115402) must be preserved. Node paths remain unchanged since WaterTrail stays as a sibling of Ship under Main.

## System-Wide Impact

- **Signal chain**: No signals introduced. Ship movement is self-contained (`_physics_process`). Chunk loading is polled in `_process`.
- **Error propagation**: Assertions on all `@export` node references in `_ready()` (project convention).
- **State lifecycle risks**: `water_chunks.gd` tracks loaded chunks in a Dictionary — pure runtime state. Chunk TileMapLayer nodes are `queue_free()`'d cleanly.
- **Scene interface parity**: No other scenes or autoloads affected.
- **Initialization order**: Main's `_ready()` fires after all children. Ship position is available. Chunk initial generation uses a hardcoded/exported spawn position to avoid tree-order dependency on Ship node.

## Acceptance Criteria

### Core Ship
- [ ] Ship scene (`scenes/ship.tscn`) with CharacterBody2D (FLOATING mode), Sprite2D (region_rect from spritesheet), Camera2D
- [ ] `scripts/ship.gd` with momentum-based movement: W=thrust (`-transform.y`), A/D=rotate, S=brake (`move_toward`)
- [ ] Movement params exported: `thrust`, `turn_speed`, `linear_drag`, `brake_decel`
- [ ] Ship renders above water trail (z_index=2)
- [ ] Camera follows ship with `position_smoothing_enabled`

### Input
- [ ] Input actions defined in `project.godot`: `move_forward` (W/Up), `move_back` (S/Down), `turn_left` (A/Left), `turn_right` (D/Right)

### Dynamic Ocean
- [ ] `scripts/water_chunks.gd` on a ChunkContainer node creates/frees TileMapLayer nodes per chunk
- [ ] `LOAD_RADIUS=2` — 5×5 chunk grid around ship
- [ ] Ocean appears seamless — no visible chunk seams or gaps during movement
- [ ] All chunk layers share the same TileSet and ShaderMaterial (read-only, no `.duplicate()`)

### Trail
- [ ] WaterTrail follows ship position (one line in `main.gd._process()`)
- [ ] Wake trail appears behind ship when moving
- [ ] `follow_cursor.gd` removed or unused

### Integration
- [ ] Ship instanced in `main.tscn`; old Camera2D removed
- [ ] Existing ViewportTexture workaround in `main.gd` preserved
- [ ] Zero errors in debug output when running project
- [ ] `gdformat --check .` and `gdlint .` pass

## Implementation Order

### Step 1: Input Actions + Ship Scene (standalone, testable)

New files:
- `scripts/ship.gd` — CharacterBody2D movement (FLOATING mode, `-transform.y` thrust, `move_toward` brake)
- `scenes/ship.tscn` — CharacterBody2D + Sprite2D + Camera2D

Edit files:
- `project.godot` (add `[input]` section with WASD + arrow key mappings)
- `scenes/main.tscn` (instance Ship, remove old Camera2D)

Test: Ship moves on existing fixed tile grid. Camera follows.

### Step 2: Dynamic Ocean Chunks

New files:
- `scripts/water_chunks.gd` — chunk lifecycle (create TileMapLayer, set cells, queue_free)

Edit files:
- `scenes/main.tscn` (add ChunkContainer node with water_chunks.gd, remove old TileMap)

Test: Sail in any direction — water tiles appear ahead, vanish behind. No seams.

### Step 3: Trail Rewire

Edit files:
- `scripts/main.gd` (add `$WaterTrail.global_position = $Ship.global_position` in `_process()`, update ViewportTexture paths if needed)
- `scenes/main.tscn` (change trails.gd `follow_target` export to point at Ship, remove `follow_cursor.gd` from WaterTrail)

Test: Wake trail follows ship. Ripple circle stays centered on ship.

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| Camera pixel-snap jitter | Test early; tune `position_smoothing_speed` or switch to drag margins |
| Chunk loading perf (256 `set_cell()` per new TileMapLayer) | Only loads when chunk coord changes (~every 6s). TODO: stagger if frame spikes measured |
| Trail clipping at high speed | Safe at 44 px/s. Increase SubViewport size if speed tuning changes |
| ViewportTexture paths break | Paths unchanged — WaterTrail stays as sibling under Main |
| TileMapLayer shader material mutation | Document as read-only; `.duplicate()` if runtime changes needed |
| Chunk initialization before ship position known | Generate initial chunks at spawn position (export), not from ship node |

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-04-04-controllable-ship-brainstorm.md](docs/brainstorms/2026-04-04-controllable-ship-brainstorm.md)
- **Documented solutions:** ViewportTexture regression, shared resource mutation, TileMap shader COLOR gotcha, SubViewport premultiplied alpha (all in `docs/solutions/`)
- **Water shader:** `shaders/water_surface.gdshader:54` — world-space coords confirmed
- **Spritesheet manifest:** `textures/ships_spritesheet.json`
- **Godot docs:** [CharacterBody2D](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html), [TileMapLayer](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html), [Camera2D](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)
- **Known issues:** TileMap physics memory leak [#79553](https://github.com/godotengine/godot/issues/79553), tile seam collisions [#89458](https://github.com/godotengine/godot/issues/89458)
- **Patterns:** KidsCanCode top-down movement, GDQuest smooth ship steering, community infinite TileMap patterns
