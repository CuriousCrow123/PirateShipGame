---
title: "feat: Composable Ship Parts & Cannon System"
type: feat
status: completed
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md
---

# feat: Composable Ship Parts & Cannon System

## Overview

Replace the single pre-composed ship sprite with a layered ship assembled from individual spritesheet parts (hull, sails, cannons) and add a broadside cannon firing system. Cannonballs spawn from the cannon muzzle point, travel in a straight line, and despawn after a lifetime.

## Problem Statement / Motivation

The current ship is a single 66x113 region from the spritesheet — no way to swap parts, show damage states, or attach weapons. The spritesheet already contains individual hull, sail, cannon, and cannonball assets that are unused. Building the ship from parts enables:

- Visual ship customization (hull type, sail style)
- Cannon placement and firing gameplay
- Future damage state progression (hull has 4 damage variants)
- Runtime part swapping via code for upgrade/shop systems

## Proposed Solution

**Scene-Layered Composition** (see brainstorm: [docs/brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md](../brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md))

Rebuild `ship.tscn` with layered Sprite2D children and Marker2D cannon slots. Each cannon is a reusable sub-scene with a Muzzle Marker2D for pixel-precise projectile spawning. A `ShipConfig` Resource drives part selection at runtime.

### Scene Hierarchy (Target)

```
Ship (CharacterBody2D)                    scripts/ship.gd
  HullSprite (Sprite2D)                   z_index=0 (relative)
  CannonSlots (Node2D)                    organizational parent
    PortCannon1 (Marker2D)               z_index=1 (relative)
      Cannon (cannon.tscn instance)
    PortCannon2 (Marker2D)
      Cannon (cannon.tscn instance)
    StarboardCannon1 (Marker2D)
      Cannon (cannon.tscn instance)
    StarboardCannon2 (Marker2D)
      Cannon (cannon.tscn instance)
  SailSprite (Sprite2D)                   z_index=2 (relative), on top of cannons
  Camera2D

cannon.tscn:
  Cannon (Node2D)                         scripts/cannon.gd
    CannonSprite (Sprite2D)               region from spritesheet
    Muzzle (Marker2D)                     at barrel tip, projectile spawn point

cannonball.tscn:
  Cannonball (Area2D)                     scripts/cannonball.gd
    Sprite2D                              cannonball region or simple circle
    CollisionShape2D                      CircleShape2D, radius ~3px
```

## Technical Considerations

### Cannonball Parenting (Critical)

Cannonballs must NOT be children of the ship — they would rotate and move with it. The ship emits a `cannon_fired` signal with spawn position and direction. `main.gd` (or a dedicated projectile container) connects to this signal and adds the cannonball to the scene tree at the world level.

```
signal cannon_fired(position: Vector2, direction: Vector2)
```

### Cannon Orientation

Cannon sprites are 29x20px, barrel pointing along positive X in the spritesheet. For perpendicular broadside firing:
- **Port cannons (left):** `rotation = -PI/2` (barrel points left, ship-relative)
- **Starboard cannons (right):** `rotation = PI/2` (barrel points right, ship-relative)

The Muzzle Marker2D is placed at the barrel tip in cannon.tscn. After rotation, `muzzle.global_position` gives the correct world-space spawn point, and the cannon's global X-basis gives the fire direction.

### Cannonball Sprite

The `cannonBall.png` region `Rect2(29, 943, 29, 20)` may show a cannon-with-ball rather than an isolated ball. **Verify visually during implementation.** If unsuitable, use a small filled circle (e.g., 4x4 or 6x6 solid sprite) as the projectile — fits the pixel art scale better at 0.25 zoom anyway.

### Scale & Pixel Snapping

All parts use `scale = Vector2(0.25, 0.25)` matching the current ship. With pixel snapping enabled, fractional positions round to integers. Marker2D positions should use coordinates that produce integer results after scaling (multiples of 4 in native sprite space).

### Collision Layers

- **Layer 1:** Reserved (world/terrain, future)
- **Layer 2:** Player ship (set on Ship's CharacterBody2D when CollisionShape2D is added)
- **Layer 3:** Cannonballs — Area2D on layer 3, mask layers 1 and 4 (not 2, to avoid self-hit)
- **Layer 4:** Enemy ships (future)

For MVP with no targets, cannonballs simply despawn on lifetime. Collision detection is wired but nothing to collide with yet.

### Fire Rate

Per-broadside cooldown of **0.5 seconds** using a Timer node on the ship. Prevents projectile spam. Port and starboard have independent cooldowns.

### Input Actions

Add to `project.godot`:
- `fire_port` — Q key
- `fire_starboard` — E key

## ShipConfig Resource Schema

```gdscript
# scripts/ship_config.gd
class_name ShipConfig
extends Resource

enum HullSize { LARGE }  # SMALL deferred to post-MVP
enum CannonType { STANDARD, MOBILE, LOOSE }

@export var hull_size: HullSize = HullSize.LARGE
@export var hull_variant: int = 0          ## 0-3, damage state index
@export var sail_variant: int = 0          ## 0-23 for large sails
@export var cannon_slots: Array[bool] = [true, true, true, true]  ## port1, port2, star1, star2
@export var cannon_type: CannonType = CannonType.STANDARD
```

- **Read-only at runtime** — ship reads config to set up sprites, does not mutate it
- **Damage state tracked separately** on the ship instance, not in ShipConfig (ShipConfig defines the "ship class," damage is per-instance)
- **No size restrictions** for sail/hull pairing for now — any combination allowed

### Spritesheet Region Lookup

Helper method on ship.gd or a static utility to compute region rects from variant indices:

| Part | Base Rect | Grid | Formula |
|---|---|---|---|
| Hull large | (0, 522) | 50x108, 4 cols | `Rect2(variant * 50, 522, 50, 108)` |
| Sail large | (0, 742) | 66x47, 6 cols x 4 rows | `Rect2((variant % 6) * 66, 742 + (variant / 6) * 47, 66, 47)` |
| Cannon | (0, 943) | 29x20, 4 cols | `Rect2(type * 29, 943, 29, 20)` |

## System-Wide Impact

- **Signal chain:** `Input (Q/E)` → `ship._unhandled_input()` → `cannon.fire()` → `ship.cannon_fired.emit(pos, dir)` → `main._on_cannon_fired()` → adds Cannonball to scene tree
- **Error propagation:** If cannon slots are empty (no cannon instance), `fire_broadside()` skips them silently — no error. If ShipConfig is null, `_ready()` asserts.
- **State lifecycle risks:** Cannonballs are independent scene tree nodes — config swaps mid-flight are safe since cannonballs are already detached from the ship.
- **Scene interface parity:** `main.gd` and `water_chunks.gd` reference `$Ship` by path and `@export`. The Ship root node name and type (CharacterBody2D) must not change. Internal children are safe to restructure.
- **Existing trail system:** Unaffected — trails follow `$Ship.global_position` which remains the CharacterBody2D center.

## Acceptance Criteria

### Functional Requirements

- [x] Ship renders from layered parts (hull + sail) instead of single pre-composed sprite
- [x] 4 Marker2D cannon slots visible in editor (2 port, 2 starboard) with cannon.tscn instances
- [x] Pressing Q fires all port cannons; pressing E fires all starboard cannons
- [x] Cannonballs spawn at the Muzzle Marker2D position on each cannon
- [x] Cannonballs travel perpendicular to the ship (left for port, right for starboard) in world space
- [x] Cannonballs despawn after lifetime (2.0s default)
- [x] Broadside cooldown prevents firing faster than every 0.5s per side
- [x] `ShipConfig` Resource can be swapped at runtime via `set_config()` to change hull variant, sail variant, and cannon slot population
- [x] Movement, water trail, and water chunk systems continue working unchanged

### Non-Functional Requirements

- [x] All GDScript uses static typing
- [x] `@export` node references validated with `assert()` in `_ready()`
- [x] `gdformat --check .` and `gdlint .` pass
- [x] Zero errors in debug output when running the project

## Implementation Phases

### Phase 1: Ship Scene Refactor

**Files:** `scenes/ship.tscn`, `scripts/ship.gd`, `scripts/ship_config.gd`

1. Create `scripts/ship_config.gd` — ShipConfig Resource class
2. Create a default `resources/default_ship_config.tres` — large hull variant 0, sail variant 0, all 4 slots filled
3. Restructure `scenes/ship.tscn`:
   - Replace `ShipSprite` with `HullSprite` (Sprite2D, region = hull_large variant 0)
   - Add `SailSprite` (Sprite2D, region = sail_large variant 0, positioned on hull)
   - Add `CannonSlots` (Node2D) with 4 child Marker2Ds: `PortCannon1`, `PortCannon2`, `StarboardCannon1`, `StarboardCannon2`
   - Position Marker2Ds visually in the editor on the hull sides
   - Set relative z_index: hull=0, cannon slots=1, sail=2
4. Update `scripts/ship.gd`:
   - Add `@export var config: ShipConfig`
   - Add `_apply_config()` method that sets region rects on HullSprite and SailSprite
   - Add public `set_config(new_config: ShipConfig)` method
   - Keep all existing movement code unchanged

### Phase 2: Cannon Scene & Firing

**Files:** `scenes/cannon.tscn`, `scripts/cannon.gd`, `scenes/cannonball.tscn`, `scripts/cannonball.gd`

1. Create `scenes/cannon.tscn`:
   - Root: `Cannon` (Node2D) with `scripts/cannon.gd`
   - Child: `CannonSprite` (Sprite2D, region = cannon variant, texture_filter = Nearest)
   - Child: `Muzzle` (Marker2D, positioned at barrel tip)
2. Create `scripts/cannon.gd`:
   - `fire() -> Dictionary` — returns `{ position: Vector2, direction: Vector2 }` from Muzzle global transform
3. Create `scenes/cannonball.tscn`:
   - Root: `Cannonball` (Area2D) with `scripts/cannonball.gd`
   - Child: `Sprite2D` (cannonball visual)
   - Child: `CollisionShape2D` (CircleShape2D)
4. Create `scripts/cannonball.gd`:
   - `@export var speed: float = 200.0`
   - `@export var lifetime: float = 2.0`
   - `func setup(pos: Vector2, dir: Vector2)` — sets position, rotation, starts lifetime timer
   - `_physics_process()` — moves in direction at speed
   - `queue_free()` on lifetime timeout

### Phase 3: Firing Integration

**Files:** `scripts/ship.gd`, `scripts/main.gd`, `project.godot`

1. Add `fire_port` and `fire_starboard` input actions to `project.godot`
2. Update `scripts/ship.gd`:
   - Add `signal cannon_fired(pos: Vector2, dir: Vector2)`
   - Add `_fire_broadside(side: String)` — iterates matching cannon slots, calls `cannon.fire()`, emits signal per cannonball
   - Add `_unhandled_input()` to handle fire actions with cooldown timers
   - Add port/starboard cooldown Timer nodes (0.5s, one-shot)
3. Update `scripts/main.gd`:
   - Preload `cannonball.tscn`
   - Connect to `$Ship.cannon_fired`
   - `_on_cannon_fired(pos, dir)` — instantiates cannonball, calls `setup()`, adds to scene tree
4. Instance `cannon.tscn` into each Marker2D slot in `ship.tscn`

### Phase 4: Validation

1. Run project via MCP — verify ship renders correctly with layered parts
2. Test Q/E firing — cannonballs spawn from muzzle points, travel perpendicular
3. Test cooldown — rapid key presses don't spawn excessive projectiles
4. Test config swap — call `set_config()` with different variants, verify visual update
5. Verify trail system and water chunks still work
6. Run `gdformat --check .` and `gdlint .`

## MVP Scope

### Files to Create (6)

| File | Type | Description |
|---|---|---|
| `scripts/ship_config.gd` | Script | ShipConfig Resource class |
| `resources/default_ship_config.tres` | Resource | Default ship configuration |
| `scenes/cannon.tscn` | Scene | Reusable cannon with muzzle point |
| `scripts/cannon.gd` | Script | Cannon fire logic |
| `scenes/cannonball.tscn` | Scene | Projectile with hitbox |
| `scripts/cannonball.gd` | Script | Projectile movement and lifetime |

### Files to Modify (3)

| File | Change |
|---|---|
| `scenes/ship.tscn` | Restructure: replace ShipSprite with layered parts + cannon slots |
| `scripts/ship.gd` | Add config system, broadside firing, cannon_fired signal |
| `scripts/main.gd` | Connect cannon_fired signal, spawn cannonballs |

### Deferred (Post-MVP)

- Small hull support (hull_small, 40x108)
- Water splash effect on cannonball despawn
- Cannon recoil animation / muzzle flash
- Sound effects for firing
- Screen shake on broadside
- Damage state progression system
- Crew, flags, misc part composition
- Enemy ships (targets for cannonballs)
- Collision response (damage dealing)

## Dependencies & Risks

- **Cannonball sprite uncertainty:** The `cannonBall.png` region may show a full cannon, not an isolated ball. Verify during Phase 2; fall back to a simple circle sprite if needed.
- **Pixel alignment:** At 0.25 scale with pixel snapping, Marker2D positions must be multiples of 4 in native sprite space to avoid sub-pixel jitter. Test and adjust in editor.
- **No breaking changes:** Ship root node stays named "Ship" as CharacterBody2D. Movement code unchanged. Trail and chunk systems unaffected.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md](../brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md) — Key decisions: scene-layered composition, broadside firing (Q/E), Marker2D cannon slots with muzzle points, ShipConfig Resource for runtime swapping, large hull only for MVP.

### Internal References

- Spritesheet manifest: [textures/ships_spritesheet.json](../../textures/ships_spritesheet.json)
- Resource duplication pattern: [docs/solutions/shared-resource-mutation.md](../solutions/shared-resource-mutation.md)
- Current ship scene: [scenes/ship.tscn](../../scenes/ship.tscn)
- Current ship script: [scripts/ship.gd](../../scripts/ship.gd)
