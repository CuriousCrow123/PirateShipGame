---
title: "feat: Add minimap radar display"
type: feat
status: completed
date: 2026-04-05
deepened: 2026-04-05
---

# feat: Add minimap radar display

## Enhancement Summary

**Deepened on:** 2026-04-05
**Agents used:** gc-godot-architecture-reviewer, gc-godot-performance-reviewer, gc-godot-timing-reviewer, gc-pattern-recognition-specialist, gc-gdscript-reviewer, gc-code-simplicity-reviewer, gc-best-practices-researcher, gc-framework-docs-researcher

### Key Improvements
1. Changed entity access from all-groups to `setup()` method — player ref passed directly, groups for dynamic collections only
2. Added freed-node safety filtering — enemies stay in group 0.4s after destruction during fade tween
3. Added accessible color palette (coral/amber) and full implementation skeleton with proper member ordering
4. Simplified MVP scope — deferred edge-clamping, trimmed Phase 2

---

## Overview

Add a beautiful radar-style minimap to the HUD showing the player ship, enemy ships, and sea mines. The minimap uses a draw-based approach (no SubViewport) with ship-relative rotation, rendering entity positions as colored dots/arrows on a semi-transparent circular background.

## Problem Statement / Motivation

The game takes place on an infinite, featureless ocean. Beyond the immediate camera view (~533x300 world pixels at 1.2x zoom), the player has zero spatial awareness. Enemies spawn at 550px and circle at 120px — players need advance warning of approaching threats and situational awareness of mine placements.

## Proposed Solution

A `Control`-based minimap node using `_draw()` on a `CanvasLayer`, rendering a circular radar with:

- **Player**: White arrow indicating heading (always centered)
- **Enemies**: Coral dots (2px), hidden when beyond radar range
- **Mines**: Amber dots (2px)
- **Background**: Dark nautical semi-transparent circle with faint border ring
- **Rotation**: Ship-relative (up = ship's forward direction)

### Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Rendering approach | `_draw()` on Control | Chunk system only loads near player; SubViewport camera would see nothing. Simpler, more performant, pixel-art friendly |
| Rotation mode | Ship-relative | Standard for vehicle radar; "up = forward" is intuitive for navigation. 53% of games use this per ISPRS research. No landmarks in infinite ocean makes world-fixed useless |
| Entity access | `setup()` for player + groups for dynamic entities | Player is singleton — direct ref avoids per-frame lookup. Enemies/mines are dynamic collections — groups match existing `sea_mines` pattern. Follows `enemy_ship.setup()` pattern already in codebase |
| Out-of-range entities | Skip drawing (MVP) | Most enemies within 700px range. Edge-clamping deferred to polish phase — adds conditional logic for marginal MVP value |
| Screen position | Top-right corner | Conventional minimap placement, away from ship sprite at center |
| CanvasLayer | Layer 10 | Above gameplay (0), well below controls overlay (100) |
| Minimap size | 60px diameter | ~1/6 viewport width at 640x360. Readable without obscuring gameplay |
| Anti-aliasing | Off (false) | Pixel-art game with nearest-neighbor filtering — AA creates blurry sub-pixel artifacts when scaled up |
| Mouse filter | IGNORE | Minimap must not block clicks on game world |

### Radar Parameters

| Parameter | Value | Notes |
|---|---|---|
| World radius | 700px | Shows enemies shortly after spawn (550px), covers full engagement range |
| Screen radius | 28px (56px diameter + 2px border = 60px total) | Fits top-right corner with 4px margin |
| Background color | `Color(0.02, 0.06, 0.12, 0.75)` | Dark nautical blue, semi-transparent |
| Border color | `Color(0.4, 0.47, 0.53, 0.8)` | Muted blue-gray, structural |
| Player color | `Color.WHITE` | Highest contrast, always findable |
| Enemy color | `Color(1.0, 0.4, 0.4, 1.0)` | Coral — better than pure red for small dots and colorblind accessibility |
| Mine color | `Color(1.0, 0.8, 0.27, 1.0)` | Amber — high luminance, distinct from coral even for deuteranopia |
| Range ring color | `Color(0.27, 0.33, 0.4, 0.3)` | Subtle, non-competing |
| Update rate | Every `_process` frame | Entities move constantly; `queue_redraw()` each frame. Multiple calls coalesce into one `_draw()` |

## Technical Considerations

### Architecture

```
scenes/minimap.tscn
  CanvasLayer (layer=10)          ← scene root, matches controls_overlay.tscn pattern
    MinimapDisplay (Control)      ← scripts/minimap_display.gd, anchored PRESET_TOP_RIGHT
      mouse_filter = IGNORE

scenes/main.tscn
  ... (existing nodes)
  Minimap (instance of minimap.tscn)  ← added after Ship node for _ready() ordering
```

The minimap is a standalone scene instanced in main.tscn. `main.gd` calls `setup()` to pass the player reference. CanvasLayer is the scene root (consistent with `controls_overlay.tscn`).

### Entity Access Pattern

- **Player ship**: Passed via `setup(ship)` from `main.gd` in `_ready()`. Direct reference — no per-frame lookup needed. Follows existing `enemy_ship.setup(_ship)` pattern at `scripts/enemy_ship.gd:39-40`.
- **Enemy ships**: Add `add_to_group("enemy_ships")` in `enemy_ship.gd` `_ready()` after assertions (mirrors `sea_mine.gd:43`). Discovered via `get_tree().get_nodes_in_group("enemy_ships")`.
- **Sea mines**: Already in `"sea_mines"` group.

**API surface dependency**: Minimap reads only `global_position` and `rotation` from the player, `global_position` from enemies/mines. All stable `Node2D` properties.

### Coordinate Transform (ship-relative)

```gdscript
# For each entity, compute minimap position:
var offset: Vector2 = entity.global_position - _player.global_position
var local: Vector2 = offset.rotated(-_player.rotation)  # align to ship heading
var radar_pos: Vector2 = local * _radar_scale

# Skip entities beyond radar range (use length_squared to avoid sqrt)
if radar_pos.length_squared() > SCREEN_RADIUS * SCREEN_RADIUS:
    return  # out of range — skip for MVP
```

### Freed-Node Safety

**Critical timing issue**: Enemies stay in the `"enemy_ships"` group for 0.4s after destruction (during the fade tween in `enemy_ship.gd:65-78`). Mines stay in `"sea_mines"` until end-of-frame after `queue_free()`. The minimap must filter these:

```gdscript
func _draw_group_entities(group_name: StringName, color: Color) -> void:
    for node: Node in get_tree().get_nodes_in_group(group_name):
        if not is_instance_valid(node) or node.is_queued_for_deletion():
            continue
        var entity := node as Node2D
        if entity == null:
            continue
        # For enemies specifically, skip destroyed ones in fade-out
        if entity is EnemyShip and entity._is_destroyed:
            continue
        _draw_entity_dot(entity, color)
```

**Note on `_is_destroyed` access**: This accesses a private member, which is an existing pattern in `main.gd:152`. Acceptable for now; a future refactor could add a public `is_destroyed()` method.

### Performance

Trivial overhead: 4 enemies + N mines = ~10 distance calculations + ~10 `_draw()` primitives per frame. `_draw()` commands are batched into a single CanvasItem command buffer draw call. No SubViewport, no shader, no texture sampling.

## Implementation Skeleton

Full `minimap_display.gd` with proper member ordering per project conventions:

```gdscript
extends Control
## Circular radar HUD showing nearby entities relative to the player ship.

# --- Constants ---
const SCREEN_RADIUS: float = 28.0
const WORLD_RADIUS: float = 700.0
const DOT_RADIUS: float = 2.0
const PLAYER_ARROW_LENGTH: float = 5.0

const BG_COLOR := Color(0.02, 0.06, 0.12, 0.75)
const BORDER_COLOR := Color(0.4, 0.47, 0.53, 0.8)
const RING_COLOR := Color(0.27, 0.33, 0.4, 0.3)
const PLAYER_COLOR := Color.WHITE
const ENEMY_COLOR := Color(1.0, 0.4, 0.4, 1.0)
const MINE_COLOR := Color(1.0, 0.8, 0.27, 1.0)

# --- Vars ---
var _player: CharacterBody2D = null
var _radar_scale: float = 0.0
var _center: Vector2 = Vector2.ZERO


# --- Virtual methods ---
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _radar_scale = SCREEN_RADIUS / WORLD_RADIUS
    _center = Vector2(SCREEN_RADIUS + 2.0, SCREEN_RADIUS + 2.0)
    custom_minimum_size = Vector2(_center.x * 2.0, _center.y * 2.0)


func _process(_delta: float) -> void:
    if _player == null:
        return
    queue_redraw()


func _draw() -> void:
    if _player == null:
        return
    # 1. Background (bottommost)
    draw_circle(_center, SCREEN_RADIUS, BG_COLOR)
    # 2. Range ring
    draw_arc(_center, SCREEN_RADIUS * 0.5, 0.0, TAU, 32, RING_COLOR, 1.0, false)
    # 3. Entity dots (mines under enemies)
    _draw_group_entities(&"sea_mines", MINE_COLOR)
    _draw_group_entities(&"enemy_ships", ENEMY_COLOR)
    # 4. Player arrow (topmost entity)
    draw_circle(_center, DOT_RADIUS, PLAYER_COLOR)
    var arrow_end: Vector2 = _center + Vector2.UP * PLAYER_ARROW_LENGTH
    draw_line(_center, arrow_end, PLAYER_COLOR, 1.0, false)
    # 5. Border (topmost)
    draw_arc(_center, SCREEN_RADIUS, 0.0, TAU, 64, BORDER_COLOR, 1.0, false)


# --- Public methods ---
func setup(player: CharacterBody2D) -> void:
    assert(player != null, "MinimapDisplay: player reference is null")
    _player = player


# --- Private methods ---
func _draw_group_entities(group_name: StringName, color: Color) -> void:
    for node: Node in get_tree().get_nodes_in_group(group_name):
        if not is_instance_valid(node) or node.is_queued_for_deletion():
            continue
        var entity := node as Node2D
        if entity == null:
            continue
        if entity is EnemyShip and entity._is_destroyed:
            continue
        _draw_entity_dot(entity, color)


func _draw_entity_dot(entity: Node2D, color: Color) -> void:
    var offset: Vector2 = entity.global_position - _player.global_position
    var local: Vector2 = offset.rotated(-_player.rotation)
    var radar_pos: Vector2 = local * _radar_scale
    # Skip if beyond radar range (length_squared avoids sqrt)
    if radar_pos.length_squared() > SCREEN_RADIUS * SCREEN_RADIUS:
        return
    draw_circle(_center + radar_pos, DOT_RADIUS, color)
```

## Acceptance Criteria

### Functional Requirements

- [x] Minimap renders as a circular radar in the top-right corner of the screen
- [x] Player ship shown as white directional arrow at center
- [x] Enemy ships shown as coral dots at correct relative positions
- [x] Sea mines shown as amber dots at correct relative positions
- [x] Minimap rotates with ship heading (up = forward)
- [x] Entities beyond radar range are simply not shown
- [x] Minimap is visible and readable at native 640x360 resolution

### Non-Functional Requirements

- [x] No frame rate impact (draw-based, no SubViewport)
- [x] `mouse_filter = IGNORE` — does not block game input
- [x] Does not interfere with controls overlay (layer 10 vs layer 100)
- [x] Static typing throughout, follows GDScript member ordering conventions
- [x] Assertion on player reference in `setup()`

### Edge Cases

- [x] Empty minimap (game start, 0 enemies, 0 mines) �� shows player arrow + background only
- [x] Enemy spawn pop-in at 550px is within radar range (700px) — dot appears naturally
- [x] Destroyed enemies filtered out — `_is_destroyed` check prevents ghost dots during 0.4s fade tween
- [x] Detonated mines filtered out — `is_queued_for_deletion()` prevents flash of dead mine dot
- [x] Minimap pauses with game (default `PROCESS_MODE_INHERIT`) — correct, no special handling needed

## Implementation Plan

### Files to create:
- `scripts/minimap_display.gd` — Control node with `_draw()` logic (see skeleton above)
- `scenes/minimap.tscn` — CanvasLayer (root, layer=10) > MinimapDisplay (Control, anchored top-right)

### Files to modify:
- `scripts/enemy_ship.gd` — Add `add_to_group("enemy_ships")` in `_ready()` after assertions
- `scripts/main.gd` — Wire minimap: call `setup(_ship)` on the minimap's MinimapDisplay node in `_ready()`
- `scenes/main.tscn` — Instance minimap scene (after Ship node for correct `_ready()` ordering)

### Implementation order:
1. Add `add_to_group("enemy_ships")` to `enemy_ship.gd` `_ready()` after assertion block
2. Create `scripts/minimap_display.gd` per the skeleton above
3. Create `scenes/minimap.tscn` (CanvasLayer root layer=10, child Control with script, anchored top-right with 4px margin)
4. Instance minimap in `scenes/main.tscn`
5. Wire `setup(_ship)` call in `scripts/main.gd` `_ready()`
6. Test visually via MCP `run_project`

### Future polish (not in MVP):
Radar sweep animation, edge-clamping for out-of-range entities, enemy heading indicators, mine state differentiation, toggle key.

## Success Metrics

- Player can identify approaching enemies before they enter camera view
- Minimap is readable at 640x360 without obscuring gameplay
- Zero errors in debug output during play

## Dependencies & Risks

- **No blockers** — all required infrastructure exists (groups, entity tracking, CanvasLayer pattern)
- **Risk: Visual tuning** — Colors/sizes may need adjustment during playtesting at native resolution. Mitigated by using named constants that are easy to tweak.

## Sources & References

- Existing group pattern: `scripts/sea_mine.gd:43` (`add_to_group("sea_mines")`)
- Setup method pattern: `scripts/enemy_ship.gd:39-40` (`setup()`)
- CanvasLayer pattern: `scenes/controls_overlay.tscn` (layer 100, CanvasLayer as root)
- Entity tracking: `scripts/main.gd:15-16` (`_enemies[]`, `_mines[]`)
- Freed-node timing: `scripts/enemy_ship.gd:65-78` (0.4s fade tween before `queue_free`)
- Godot docs: [Custom drawing in 2D](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)
- Godot docs: [CanvasLayer](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html)
- Color accessibility: [Xbox Accessibility Guideline 102](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/102)
- Minimap UX research: [ISPRS IJGI 12(2):58](https://www.mdpi.com/2220-9964/12/2/58) — 53% of games use player-relative rotation
- SubViewport gotcha (not applicable but noted): `docs/solutions/viewporttexture-46-regression.md`
