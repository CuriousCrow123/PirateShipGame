---
title: "feat: Cannon shooting with muzzle flash and explosion VFX"
type: feat
status: active
date: 2026-04-05
---

# feat: Cannon Shooting with Muzzle Flash and Explosion VFX

## Overview

Merge the cannon system (`feat/composable-ship-cannons`) with the 3D explosion effect (`feat/explosion-spritesheet-tool`) so that firing cannons produces visible muzzle flash at the cannon and an impact explosion where the cannonball lands. Cannonballs should travel a fixed max range with randomized distance (not infinite flight).

## Problem Statement / Motivation

Currently cannonballs fly in a straight line forever until their lifetime expires, with no visual feedback at either end. The ship fires silently and cannonballs vanish without impact. This makes combat feel lifeless.

## Proposed Solution

### 1. Merge branches

Merge `feat/composable-ship-cannons` → `main`, then merge `feat/explosion-spritesheet-tool` → `main`. Resolve any conflicts (likely minimal — different files).

### 2. Cannonball range behavior

Replace the fixed `lifetime` despawn with a **max range + random distance** system:

```gdscript
# scripts/cannonball.gd
@export var max_range: float = 150.0
@export var range_randomness: float = 0.3  # 0.0-1.0, proportion of randomness

var _target_distance: float
var _distance_traveled: float = 0.0

func setup(pos: Vector2, dir: Vector2) -> void:
    global_position = pos
    _direction = dir.normalized()
    rotation = _direction.angle()
    # Random distance: max_range * (1.0 - randomness) to max_range
    var min_dist: float = max_range * (1.0 - range_randomness)
    _target_distance = randf_range(min_dist, max_range)

func _physics_process(delta: float) -> void:
    var step: float = speed * delta
    global_position += _direction * step
    _distance_traveled += step
    if _distance_traveled >= _target_distance:
        _on_impact()
```

### 3. Muzzle flash at cannon

Spawn a small `ExplosionEffect` at the cannon's muzzle position when fired. The effect is already self-contained and auto-frees.

In `main.gd._on_cannon_fired()`:
```gdscript
func _on_cannon_fired(pos: Vector2, dir: Vector2) -> void:
    var ball: Cannonball = CannonballScene.instantiate()
    add_child(ball)
    ball.setup(pos, dir)
    ExplosionEffect.create(self, pos)  # Muzzle flash
```

### 4. Impact explosion at cannonball landing

When the cannonball reaches its target distance, spawn an `ExplosionEffect` at the impact point before freeing itself.

In `cannonball.gd`:
```gdscript
func _on_impact() -> void:
    ExplosionEffect.create(get_parent(), global_position)
    queue_free()
```

### 5. Scale differentiation

The muzzle flash and impact explosion should look different:
- **Muzzle flash**: Small, quick — reduce the SubViewportContainer size and particle count
- **Impact explosion**: Full size as currently configured

Add a `scale_factor` parameter to `ExplosionEffect.create()`:

```gdscript
static func create(parent: Node, pos: Vector2, scale_factor: float = 1.0) -> ExplosionEffect:
    var effect: ExplosionEffect = ExplosionScene.instantiate() as ExplosionEffect
    parent.add_child(effect)
    effect.global_position = pos
    effect.scale = Vector2.ONE * scale_factor
    return effect
```

Usage:
```gdscript
ExplosionEffect.create(self, pos, 0.4)  # Small muzzle flash
ExplosionEffect.create(get_parent(), global_position, 1.0)  # Full impact
```

## Technical Considerations

### Signal chain

```
Ship._unhandled_input (Q/E key)
  → Ship._fire_broadside(side)
    → Cannon.fire() returns {position, direction}
    → Ship.cannon_fired.emit(pos, dir)
      → Main._on_cannon_fired(pos, dir)
        → Cannonball spawned + setup(pos, dir)
        → ExplosionEffect.create(self, pos, 0.4)  [muzzle flash]
          → (auto queue_free after 1.5s)

Cannonball._physics_process
  → distance check → _on_impact()
    → ExplosionEffect.create(parent, pos, 1.0)  [impact]
    → queue_free()
```

### Performance

Each ExplosionEffect creates a SubViewport with 3D rendering. With 4 cannons per broadside firing simultaneously, that's 4 muzzle flashes + eventually 4 impact explosions = up to 8 concurrent SubViewports. At 64x64 each with ~60 sphere meshes, this should be fine on any modern GPU but worth monitoring.

### Resource safety

- ExplosionEffect already duplicates its ShaderMaterial and ParticleProcessMaterials in `_ready()`
- Cannonball `queue_free()` after spawning the impact effect is safe — the effect is added to `get_parent()`, not the cannonball itself

### Files to modify

| File | Change |
|------|--------|
| `scripts/cannonball.gd` | Replace lifetime with range-based despawn + impact callback |
| `scripts/main.gd` | Add muzzle flash spawn in `_on_cannon_fired()` |
| `scripts/explosion_effect.gd` | Add `scale_factor` parameter to `create()` |

### Files already complete (from existing branches)

| File | Branch |
|------|--------|
| `scripts/ship.gd` | `feat/composable-ship-cannons` |
| `scripts/cannon.gd` | `feat/composable-ship-cannons` |
| `scenes/ship.tscn` | `feat/composable-ship-cannons` |
| `scenes/cannon.tscn` | `feat/composable-ship-cannons` |
| `scenes/cannonball.tscn` | `feat/composable-ship-cannons` |
| `scripts/explosion_effect.gd` | `feat/explosion-spritesheet-tool` |
| `scenes/explosion_effect.tscn` | `feat/explosion-spritesheet-tool` |
| `shaders/explosion_dissolve.gdshader` | `feat/explosion-spritesheet-tool` |
| `shaders/explosion_dissolve_material.tres` | `feat/explosion-spritesheet-tool` |

## Acceptance Criteria

- [ ] Both branches merged to main without conflicts
- [ ] Ship fires cannonballs with Q (port) and E (starboard) broadside
- [ ] Cannonballs travel a random distance between 70-100% of max_range, then impact
- [ ] Muzzle flash (small explosion) appears at cannon position on fire
- [ ] Impact explosion (full size) appears where cannonball lands
- [ ] Effects auto-free after playing — no memory leaks
- [ ] No errors in debug output during rapid firing
- [ ] Multiple simultaneous explosions render correctly (4+ concurrent)

## Dependencies & Risks

**Dependencies:**
- `feat/composable-ship-cannons` branch must merge cleanly to main
- `feat/explosion-spritesheet-tool` branch must merge cleanly after

**Risks:**
- **Merge conflicts**: Unlikely — branches touch different files. Only `main.gd` overlaps.
- **Performance with many concurrent SubViewports**: 8 simultaneous 64x64 3D viewports should be fine, but test with rapid firing.
- **Cannonball `get_parent()` assumption**: Impact effect is added to the cannonball's parent (Main). If cannonball is ever reparented, this breaks. Using `get_tree().current_scene` would be safer but couples to scene tree structure.

## Sources & References

- Cannon system: `feat/composable-ship-cannons` branch (ship.gd, cannon.gd, cannonball.gd)
- Explosion effect: `feat/explosion-spritesheet-tool` branch (explosion_effect.gd, explosion_dissolve.gdshader)
- Composable ship brainstorm: [docs/brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md](docs/brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md)
- Explosion brainstorm: [docs/brainstorms/2026-04-05-stylized-explosion-spritesheet-brainstorm.md](docs/brainstorms/2026-04-05-stylized-explosion-spritesheet-brainstorm.md)
