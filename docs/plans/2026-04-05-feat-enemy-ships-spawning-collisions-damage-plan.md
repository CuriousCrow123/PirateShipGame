---
title: "feat: Add Enemy Pirate Ships with Spawning, Collisions, and Damage"
type: feat
status: completed
date: 2026-04-05
deepened: 2026-04-05
---

# feat: Add Enemy Pirate Ships with Spawning, Collisions, and Damage

## Enhancement Summary

**Deepened on:** 2026-04-05
**Research agents used:** gc-godot-architecture-reviewer, gc-godot-timing-reviewer, gc-godot-performance-reviewer, gc-resource-safety-reviewer, gc-gdscript-reviewer, gc-pattern-recognition-specialist, gc-best-practices-researcher, gc-framework-docs-researcher

### Key Improvements from Review

1. **Double-destroy guard** — `_is_destroyed` flag prevents two cannonballs on same frame from calling `_destroy()` twice
2. **Tween conflict resolution** — Store flash tween reference, kill it before creating destroy fade-out tween
3. **Cannonball impact guard rewrite** — Clean idempotency pattern replaces contradictory guard logic
4. **Spawn ordering fix** — `add_child()` before `global_position` to match existing codebase pattern
5. **Pixel-snapped shake** — `roundf()` on shake offsets to match pixel-art pipeline
6. **`tree_exiting` safety net** — Prevents stale references in `_enemies` array regardless of removal path
7. **Named collision layers** — Add layer names in project.godot for inspector readability

### Timing Hazards Identified

- `body_entered` can fire same frame as range-based `_on_impact()` — guard flag required
- Flash tween and destroy tween both animate `modulate` — must kill flash tween first
- `queue_free()` during despawn does NOT emit `destroyed` signal — `tree_exiting` backup needed
- Explosion VFX should be parented to Main, not enemy, so they survive enemy's `queue_free()`

---

## Overview

Add dummy enemy pirate ships that randomly spawn offscreen, drift through the world, and can be damaged by the player's cannonballs. Implement ship-ship physics collisions, cannonball-ship hit detection with impact explosions, per-ship shake on hit, and hull damage visual progression using existing spritesheet damage states plus a brief hit flash.

## Problem Statement / Motivation

The game currently has a player ship that can fire cannonballs, but there are no targets. Cannonballs despawn at max range with a water splash. Adding enemy ships provides gameplay targets, validates the cannon system end-to-end, and establishes the collision/damage architecture for future combat features.

## Proposed Solution

### Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Enemy node type | `CharacterBody2D` | Consistent with player ship; gives precise control over movement and collision response |
| Enemy AI | Slow drift with random rotation | Spec says "dummy" — minimal AI, enemies are floating targets |
| Enemy script | Separate `enemy_ship.gd` | Player ship.gd is tightly coupled to input; enemy is far simpler — no need to refactor ship.gd |
| Health model | `hits_remaining: int = 4` (4 hits to destroy) | Maps directly to 4 hull damage variants (0-3); simple and visual |
| Friendly fire | Disabled — cannonball mask excludes player layer | Cannonballs spawn at muzzle inside player hull; self-hit would break every shot |
| Ship shake | Per-ship sprite offset (not camera shake) | Camera shake affects entire view; sprite shake is per-entity and more targeted |
| Hit feedback | Hull variant swap + brief white modulate flash | Hull variants exist in spritesheet; flash gives immediate feedback |
| Destruction | Large explosion VFX → fade out → queue_free | Simple, satisfying, reuses existing ExplosionEffect |
| Spawning | Timer-based from Main, max 4 concurrent | Conservative start; tunable via @export |
| Despawning | Remove enemies >1000px from player | Prevents unbounded accumulation |

### Collision Layer Plan

| Layer | Bit | Used By | Purpose |
|---|---|---|---|
| 1 | 0 | Player ship | Player body |
| 2 | 1 | Enemy ships | Enemy bodies |
| 4 | 2 | Player cannonballs | Projectiles (already assigned) |

**Mask assignments:**
- Player ship: layer = 1, mask = 2 (collides with enemy bodies)
- Enemy ship: layer = 2, mask = 1 (collides with player body)
- Player cannonball: layer = 4, mask = 2 (detects enemy bodies only, NOT player)

Enemy-enemy collision: disabled (enemies pass through each other to avoid clumping issues).

**Name layers in project.godot** for inspector readability:
```
[layer_names]
2d_physics/layer_1="player"
2d_physics/layer_2="enemies"
2d_physics/layer_3="player_projectiles"
```

## Technical Approach

### Phase 1: Collision Shapes & Layer Setup

**Name collision layers** in `project.godot`:
- Add layer names under `[layer_names]` section

**Add CollisionShape2D to player ship** (`scenes/ship.tscn`):
- Add `CollisionShape2D` child with `RectangleShape2D` sized to hull (~25x54 at 0.5 scale)
- Set ship collision layer = 1, mask = 2

**Create enemy ship scene** (`scenes/enemy_ship.tscn`):
- `CharacterBody2D` root with `MOTION_MODE_FLOATING`
- `HullSprite` (Sprite2D) — region from spritesheet hull damage states
- `SailSprite` (Sprite2D) — randomized sail variant
- `CollisionShape2D` with `RectangleShape2D` matching hull size
- Collision layer = 2, mask = 1
- Use `$` node path syntax (not `%`) to match existing `ship.gd` convention

**Create enemy ship script** (`scripts/enemy_ship.gd`):
```gdscript
class_name EnemyShip
extends CharacterBody2D

signal destroyed(ship: EnemyShip)

const SHAKE_DURATION: float = 0.3
const SHAKE_MAX_INTENSITY: float = 3.0

@export var drift_speed: float = 30.0
@export var turn_speed: float = 0.3
@export var max_health: int = 4

var _health: int = 0
var _is_destroyed: bool = false
var _is_shaking: bool = false
var _shake_timer: float = 0.0
var _original_hull_pos: Vector2 = Vector2.ZERO
var _flash_tween: Tween = null

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape

func _ready() -> void:
    assert(_hull_sprite != null, "EnemyShip: HullSprite not found")
    assert(_sail_sprite != null, "EnemyShip: SailSprite not found")
    assert(_collision_shape != null, "EnemyShip: CollisionShape not found")
    _health = max_health
    _original_hull_pos = _hull_sprite.position
    _randomize_appearance()

func _physics_process(delta: float) -> void:
    rotation += randf_range(-turn_speed, turn_speed) * delta
    velocity = -transform.y * drift_speed
    move_and_slide()
    _process_shake(delta)

func take_damage(_from_direction: Vector2) -> void:
    if _is_destroyed:
        return
    _health -= 1
    if _health <= 0:
        _is_destroyed = true
        _destroy()
        return
    var damage_variant: int = max_health - _health
    _hull_sprite.region_rect = ShipConfig.get_hull_region(
        mini(damage_variant, 3)
    )
    _start_shake()
    _flash_white()

func _destroy() -> void:
    # Kill any active flash tween to prevent conflict with fade-out
    if _flash_tween and _flash_tween.is_valid():
        _flash_tween.kill()
    # Disable collision immediately (deferred for physics safety)
    _collision_shape.set_deferred("disabled", true)
    # Large destruction explosion — parented to get_parent() (Main) so it
    # survives this node's queue_free
    ExplosionEffect.create(
        get_parent(), global_position, Vector2.UP,
        360, 1.5, 80.0, velocity
    )
    destroyed.emit(self)
    # Fade out then remove
    var tween: Tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.4)
    tween.tween_callback(queue_free)

func _start_shake() -> void:
    _is_shaking = true
    _shake_timer = SHAKE_DURATION

func _process_shake(delta: float) -> void:
    if not _is_shaking:
        return
    _shake_timer -= delta
    if _shake_timer <= 0.0:
        _is_shaking = false
        _hull_sprite.position = _original_hull_pos
        _sail_sprite.position = Vector2.ZERO
        return
    var intensity: float = _shake_timer / SHAKE_DURATION * SHAKE_MAX_INTENSITY
    # Snap to whole pixels for pixel-art consistency
    var offset: Vector2 = Vector2(
        roundf(randf_range(-intensity, intensity)),
        roundf(randf_range(-intensity, intensity))
    )
    _hull_sprite.position = _original_hull_pos + offset
    _sail_sprite.position = offset

func _flash_white() -> void:
    if _flash_tween and _flash_tween.is_valid():
        _flash_tween.kill()
    modulate = Color(3.0, 3.0, 3.0, 1.0)
    _flash_tween = create_tween()
    _flash_tween.tween_property(self, "modulate", Color.WHITE, 0.15)

func _randomize_appearance() -> void:
    var sail_variant: int = randi_range(0, 23)
    _sail_sprite.region_rect = ShipConfig.get_sail_region(sail_variant)
    _hull_sprite.region_rect = ShipConfig.get_hull_region(0)
```

### Phase 2: Cannonball Hit Detection

**Update cannonball** (`scripts/cannonball.gd`):
- Set collision mask = 2 in `cannonball.tscn` (detect enemy ship bodies)
- Connect `body_entered` signal in `_ready()`
- Add `_impacted: bool` guard to prevent double-impact (range check + signal race)
- On `body_entered` with an `EnemyShip`: call `take_damage()` then `_on_impact()`

```gdscript
# In cannonball.gd — additions/modifications
var _impacted: bool = false

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
    if _impacted:
        return
    var step: float = speed * delta
    global_position += _direction * step
    _distance_traveled += step
    if _distance_traveled >= _target_distance:
        _on_impact()

func _on_body_entered(body: Node2D) -> void:
    if _impacted:
        return
    if body is EnemyShip:
        _impacted = true
        body.take_damage(_direction)
        _on_impact()

func _on_impact() -> void:
    if _impacted:
        # Called from body_entered path — explosion already handled
        # Just need to free if not already done
        if not is_queued_for_deletion():
            queue_free()
        return
    _impacted = true
    # Existing water splash explosion at max range
    ExplosionEffect.create(
        get_parent(), global_position, _direction,
        45.0, 1.0, 15.0, Vector2.ZERO
    )
    queue_free()
```

**Note:** The `_on_body_entered` path sets `_impacted = true` BEFORE calling `_on_impact()`, so `_on_impact()` early-returns and just frees. The range-based path calls `_on_impact()` with `_impacted = false`, so it spawns the water splash and frees. The enemy hit path should also spawn an impact explosion — add that in the `_on_body_entered` handler:

```gdscript
func _on_body_entered(body: Node2D) -> void:
    if _impacted:
        return
    if body is EnemyShip:
        _impacted = true
        body.take_damage(_direction)
        ExplosionEffect.create(
            get_parent(), global_position, _direction,
            45.0, 1.0, 15.0, Vector2.ZERO
        )
        queue_free()
```

This simplifies the flow — each path handles its own explosion and frees.

### Phase 3: Spawning & Despawning

**Update main.gd** — add enemy spawner:

```gdscript
# In main.gd — additions
const EnemyShipScene: PackedScene = preload("res://scenes/enemy_ship.tscn")

@export var max_enemies: int = 4
@export var spawn_interval: float = 8.0
@export var spawn_distance: float = 550.0
@export var despawn_distance: float = 1000.0

var _enemies: Array[EnemyShip] = []
var _spawn_timer: float = 2.0  # First enemy spawns quickly

func _physics_process(delta: float) -> void:
    _spawn_timer -= delta
    if _spawn_timer <= 0.0:
        _spawn_timer = spawn_interval
        _try_spawn_enemy()
    _despawn_distant_enemies()

func _try_spawn_enemy() -> void:
    if _enemies.size() >= max_enemies:
        return
    var angle: float = randf() * TAU
    var spawn_pos: Vector2 = $Ship.global_position + Vector2.from_angle(angle) * spawn_distance
    var enemy: EnemyShip = EnemyShipScene.instantiate()
    enemy.rotation = randf() * TAU
    enemy.destroyed.connect(_on_enemy_destroyed)
    enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
    add_child(enemy)
    enemy.global_position = spawn_pos  # Set AFTER add_child for correct transform
    _enemies.append(enemy)

func _on_enemy_destroyed(enemy: EnemyShip) -> void:
    _enemies.erase(enemy)

func _on_enemy_tree_exiting(enemy: EnemyShip) -> void:
    _enemies.erase(enemy)  # Safety net — erase is no-op if already removed

func _despawn_distant_enemies() -> void:
    for enemy: EnemyShip in _enemies.duplicate():
        if enemy.global_position.distance_to($Ship.global_position) > despawn_distance:
            _enemies.erase(enemy)
            enemy.queue_free()
```

### Phase 4: Player Ship Collision Response

**Update ship.gd** — add collision response to `move_and_slide()`:
- After `move_and_slide()`, check `get_slide_collision_count()`
- If colliding with an enemy, apply a small bounce velocity

```gdscript
# In ship.gd _physics_process — after move_and_slide()
for i: int in range(get_slide_collision_count()):
    var collision: KinematicCollision2D = get_slide_collision(i)
    var collider: Object = collision.get_collider()
    if collider is EnemyShip:
        var push: Vector2 = collision.get_normal() * 50.0
        velocity += push
```

## File Summary

| File | Action | Purpose |
|---|---|---|
| `project.godot` | **Modify** | Add named collision layers |
| `scenes/enemy_ship.tscn` | **Create** | Enemy ship scene with hull, sail, collision shape |
| `scripts/enemy_ship.gd` | **Create** | Enemy AI, health, damage, shake, destruction |
| `scenes/ship.tscn` | **Modify** | Add CollisionShape2D, set layer=1/mask=2 |
| `scripts/cannonball.gd` | **Modify** | Add body_entered signal, impact guard, enemy damage |
| `scenes/cannonball.tscn` | **Modify** | Set collision_mask = 2 |
| `scripts/main.gd` | **Modify** | Add spawner, despawner, enemy tracking |
| `scripts/ship.gd` | **Modify** | Add collision response after move_and_slide |

## System-Wide Impact

- **Signal chain**: Cannonball `body_entered` → `EnemyShip.take_damage()` → hull variant update + shake + flash. `EnemyShip.destroyed` signal → `Main._on_enemy_destroyed()` removes from tracking array. `tree_exiting` provides backup cleanup.
- **Error propagation**: `_impacted` guard prevents double-impact on cannonball. `_is_destroyed` guard prevents double-destroy on enemy. `set_deferred("disabled", true)` safely disables collision during physics callbacks.
- **State lifecycle risks**: `_enemies` array is protected by both `destroyed` signal and `tree_exiting` backup. Flash tween is explicitly killed before destroy tween starts. Explosion VFX are parented to Main, not the enemy, so they survive enemy's `queue_free()`.
- **Performance**: Each enemy adds one `CharacterBody2D` + one collision shape — negligible at 4 enemies. **SubViewport explosions are the bottleneck** — a full broadside hitting 4 enemies creates 4 muzzle flashes + 4 impact explosions = 8 SubViewports with 3D GPUParticles3D and glow. The 1.5s auto-free lifetime bounds this, but monitor for frame drops. If needed, consider pre-rendered spritesheet fallback (explosion spritesheet tool exists on a merged branch).
- **Resource safety**: `Rect2` assignments (region_rect) are value types — safe. `RectangleShape2D` in scene is shared but never mutated at runtime — safe. `modulate` is per-node — safe. `ExplosionEffect.create()` already duplicates materials per instance — safe.

## Acceptance Criteria

- [x] Collision layers named in project.godot (player, enemies, player_projectiles)
- [x] Enemy ships spawn offscreen at random intervals (default: every 8s, max 4)
- [x] First enemy spawns after ~2s, not a full interval wait
- [x] Enemies drift slowly with gentle random rotation changes
- [x] Enemies have randomized sail variants for visual variety
- [x] Player ship has a CollisionShape2D and bounces off enemy ships
- [x] Cannonballs detect and hit enemy ships (body_entered signal)
- [x] Impact spawns an ExplosionEffect at the hit position
- [x] Hit enemy ships shake briefly (pixel-snapped sprite offset, 0.3s decay)
- [x] Hit enemy ships flash white briefly (0.15s modulate tween)
- [x] Hull sprite updates to show progressive damage (4 states)
- [x] After 4 hits, enemy plays destruction explosion and fades out
- [x] Double-destroy prevented by `_is_destroyed` guard
- [x] Flash tween killed before destroy fade-out to prevent conflict
- [x] Destroyed enemies are removed from spawn tracking
- [x] Enemies >1000px from player are despawned
- [x] `tree_exiting` signal connected as backup for `_enemies` array cleanup
- [x] No friendly fire (cannonballs cannot hit the player)
- [x] `add_child()` called before `global_position` assignment on spawn
- [x] Zero errors in debug output during gameplay

## Sources & References

- Existing ship system: `scripts/ship.gd`, `scenes/ship.tscn`
- Cannon/cannonball: `scripts/cannonball.gd`, `scenes/cannonball.tscn`
- Explosion VFX: `scripts/explosion_effect.gd` (static factory pattern)
- Ship config with hull variants: `scripts/ship_config.gd`
- Spritesheet regions: `textures/ships_spritesheet.json`
- Resource safety: `docs/solutions/shared-resource-mutation.md`
- SubViewport alpha: `docs/solutions/subviewport-premultiplied-alpha.md`
- Composable ship brainstorm: `docs/brainstorms/2026-04-05-composable-ship-and-cannons-brainstorm.md`
- Godot docs: CharacterBody2D, Area2D.body_entered, CollisionShape2D.set_deferred, Tween, Node.queue_free
