---
title: "feat: Enemy ships shoot player + wake trails and water displacement"
type: feat
status: active
date: 2026-04-07
deepened: 2026-04-07
---

# feat: Enemy ships shoot player + wake trails and water displacement

## Enhancement Summary

**Deepened on:** 2026-04-07
**Review agents:** gc-godot-architecture-reviewer, gc-godot-timing-reviewer, gc-godot-performance-reviewer, gc-resource-safety-reviewer, gc-gdscript-reviewer, gc-pattern-recognition-specialist, gc-code-simplicity-reviewer, gc-spec-flow-analyzer, gc-learnings-researcher

### Critical fixes (MUST apply before / during implementation)

1. **Range mismatch (game-breaking):** `broadside_range = 180` exceeds `Cannonball.max_range = 150`. Enemy balls will die in the water before reaching the player. **Fix:** lower `broadside_range` to `130.0`, OR pass a higher `max_range` on `setup()` for enemy balls. Add an `assert(broadside_range <= Cannonball.max_range)` at startup.
2. **`SceneTreeTimer` lambda captures freed enemy:** The plan's per-side cooldown uses `create_timer(...).timeout.connect(func(): _port_ready = true)`. If the enemy is destroyed mid-cooldown, the timer (owned by the SceneTree, not the enemy) still fires on a freed instance. **Fix:** replace with `float` cooldown counters decremented in `_physics_process` (`_port_cd -= delta`), OR use a child `Timer` node (auto-frees with parent). This also applies retroactively to `ship.gd` for consistency.
3. **`.tscn` edits must NOT be hand-written:** Per project convention, `.tscn`/`.tres` files should be authored via the Godot editor or the `mcp__godot__*` tools (`add_node`, `save_scene`, `update_project_uids`). The Phase 3 and Phase 4 scene changes must go through those tools, not `Edit`/`Write`. The snippet using `instance=ExtResource("cannon.tscn")` is pseudocode — the real edit must declare a proper `[ext_resource type="PackedScene" path="res://scenes/cannon.tscn" id="..."]` header and bump `load_steps`.
4. **`instance_from_id()` is not a liveness check:** It can return freed objects and IDs can be reused. **Fix:** delete the `_enemy_wake_state` prune-in-`_process` loop entirely; clean up exclusively in `_unregister_enemy_wake()` which already fires on `tree_exiting`.
5. **Enemy wake trail snap-clears on death:** Freeing the Line2D in `_on_enemy_destroyed` cuts the trail on the same frame the hull starts fading. **Fix:** tween the Line2D's `modulate:a` from 1.0→0.0 over 0.4s (matching the hull fade) and `queue_free` on tween end. Unregister from `_enemy_trails` immediately so no new points are appended during the fade.
6. **Range mismatch fallout on timeout path (parity gap):** Neither the player nor enemy cannonball spawns a water splash on max-range timeout today — the current code only emits `water_impacted`. Plan should verify player parity remains and apply the same treatment to enemy balls (no HP change on player hit, splash + displacement stamp on timeout for both).

### Simplifications adopted

- **Delete `_enemy_wake_state` dict entirely.** Store `_wake_accum: float` and `_last_wake_pos: Vector2` as members on `EnemyShip`. Main calls `_displacement_stamps.spawn_wake_ring(pos)` when the enemy's own counter trips. Kills ~25 LOC and removes the whole pruning question.
- **Cut enemy cannons from 4 (2×2) to 2 (1×1).** Reads as a broadside, halves projectile pressure on `DisplacementStamps` and `ExplosionSprite`, trivially shrinks `_fire_broadside` to one direct reference per side.
- **Use `bool is_enemy_owned` instead of `Cannonball.Team` enum.** Two states, cheaper to read, no import of `Cannonball.Team.ENEMY` at call sites.
- **Use `bool is_starboard` instead of string `side`** in `_fire_broadside`. Eliminates `begins_with("Port")` string matching; cache `_port_cannons: Array[Cannon]` and `_starboard_cannons: Array[Cannon]` in `_ready()`.
- **Single cleanup path on `tree_exiting` only.** Delete the `destroyed`-signal path for bookkeeping (`_enemies.erase`, `_unregister_enemy_wake`). `destroyed` remains as a gameplay event for future hooks (score, combo).
- **Create `scenes/wake_trail.tscn`** (a Line2D with `trails.gd` attached) instead of building Line2D imperatively in `main.gd` with 13 property assignments. Refactor the player's Line2D in `main.tscn` to instance the same scene. One source of truth; editor-tunable.
- **Add `class_name Ship` to `scripts/ship.gd`** and drop the `add_to_group("player")` hack. `cannonball.gd` then uses `body is Ship` symmetrically with `body is EnemyShip`.
- **Name collision-layer bit constants** at the top of `cannonball.gd`: `const LAYER_PLAYER_BALL := 1 << 2`, `const LAYER_ENEMY_BALL := 1 << 4`, etc. No magic bit math in `setup()`.

### Performance upgrades

- **`trails.gd` — incremental point updates.** Instead of `clear_points()` + `add_point()` × 90 every frame, `add_point(new)` once and `remove_point(0)` when `get_point_count() > max_length`. Reduces Line2D ops from ~450/frame to ~10/frame with five trails.
- **Use `distance_squared_to()`** in the trail length accumulation and in the 16px wake-ring distance check. Eliminates ~89 `sqrt`/frame per trail and one per enemy per frame.
- **Shrink wake SubViewport from 1024×1024 to 512×512** (4× fill reduction). Displacement sampling is low-frequency; the reduction is imperceptible.
- **Raise `DisplacementStamps.MAX_STAMPS` from 32 to 48** preemptively to absorb the enemy wake-ring load without starving the player wake. Stamps are 4×4 Sprite2Ds — cost is negligible.
- **Stagger enemy wake-ring interval to 24px** (vs player 16px). Halves enemy stamp rate with no visible loss.
- **Hoist dict reads:** pull `_wake_accum` / `_last_wake_pos` to typed locals, mutate, write back — but with simplification #1 above this becomes moot (members on the enemy node).

### Gaps closed (new acceptance criteria)

- Enemy cannonball must be visually distinguishable from player's (`modulate = Color(1.3, 0.7, 0.7)` applied in `setup()` when `is_enemy_owned`).
- Enemy cannonball max-range timeout must spawn a splash + displacement stamp (parity with player).
- `_try_fire_at_target` early-returns if `_target` has `is_destroyed()` or `is_queued_for_deletion()`.
- Mine-kill path on enemies must go through the same `tree_exiting` cleanup — audit `sea_mine.gd` kill codepath to confirm.
- Integration scenario: 4 enemies alive + player firing + mines exploding simultaneously; zero errors, all wakes visible, no DisplacementStamps starvation.

### Known Godot gotchas (from `docs/solutions/`)

- **Line2D round-joint alpha gradient asymmetry** — wake trails with round joints + alpha gradient render direction-asymmetrically. Already mitigated in the player's Line2D; the same gradient/curve must carry over to the new `wake_trail.tscn` instances. See [docs/solutions/line2d-round-joint-alpha-gradient-asymmetry.md](docs/solutions/line2d-round-joint-alpha-gradient-asymmetry.md).
- **Shared Curve mutation** — `trails.gd` must `.duplicate()` the `width_curve` in `_ready()` (already does). The new `_register_enemy_wake` path preloads the same `.tres`; relying on `_ready()` to duplicate is load-bearing — add a comment. See [docs/solutions/shared-resource-mutation.md](docs/solutions/shared-resource-mutation.md).
- **SubViewport premultiplied alpha on Forward+** — `transparent_bg = true` + Forward+ produces darkened edges. Player wake works today, so the existing `ripple_material` handles it; verify enemy wakes look consistent after SubViewport shrink. See [docs/solutions/subviewport-premultiplied-alpha.md](docs/solutions/subviewport-premultiplied-alpha.md).
- **ViewportTexture 4.6 regression** — not directly triggered here (we use the existing `WaterTrail/SubViewport`), but be alert if any new SubViewport is introduced. See [docs/solutions/viewporttexture-46-regression.md](docs/solutions/viewporttexture-46-regression.md).

---

## Overview

Extend enemy pirate ships with three abilities currently exclusive to the player:

1. **Broadside cannon fire** — enemies fire cannonballs at the player when oriented for a broadside.
2. **Wake trail (Line2D into the shared wake SubViewport)** — each enemy leaves the same soft foamy wake that the player does.
3. **Water displacement stamps** — each enemy emits expanding wake rings so their passage distorts the water surface like the player's does.

Player HP / damage-from-enemy-cannonballs is **out of scope**. Enemy cannonballs must fly, visually impact the water (or a placeholder hit on the player ship body with no damage), and despawn. The goal of this plan is purely to close the visual/behavioral gap between player and enemy ships while setting up the collision plumbing for future player-damage work.

All work must be performed in a **git worktree**.

## Problem Statement / Motivation

- Enemies are currently passive targets with no offense, which makes combat one-sided and boring.
- Enemies glide over the water without leaving a wake or displacing water, which visually breaks the convention established for the player and makes them feel "painted on" the surface.
- The existing wake/displacement systems are **hard-coded to the player** (single Line2D bound to `$Ship`, single wake-ring emitter in `main.gd`). To support multi-ship water effects cleanly, a small refactor is required.

## Proposed Solution

### Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Cannonball ownership | Add `owner_team: int` (PLAYER=0, ENEMY=1) to `Cannonball` | Cheapest way to reuse the existing scene/script and separate collision filtering from gameplay logic |
| Enemy cannonball collision | New physics layer `5 = enemy_projectiles`, mask targets `player` only | Mirrors player projectile layering, keeps friendly-fire naturally disabled |
| Enemy cannon firing condition | Fire a broadside when the player is roughly perpendicular to the enemy's heading AND within range AND that side's cooldown is ready | Reuses the existing "circle around player at broadside range" behavior — the AI is already lined up most of the time |
| Enemy cannon placement | Add `CannonSlots` with 2 Cannons per side to `enemy_ship.tscn` (matches player) | Shared `cannon.tscn`, zero new art, consistent visuals |
| Enemy firing signal | `cannon_fired(pos, dir)` emitted by `EnemyShip`, handled by `main.gd` (same pattern as player) | Keeps projectile spawning centralized in `main.gd` like it already is |
| Wake trail architecture | Refactor `trails.gd` to work in SubViewport-centered world coords; add one Line2D per EnemyShip as a child of the shared `WaterTrail/SubViewport` | All trails share the single `WakeTrailMap` texture that the water shader already samples — no new SubViewports, no new shader uniforms |
| Wake trail lifecycle | Main creates/frees the per-enemy Line2D on spawn/despawn (not a child of the enemy, so the trail doesn't disappear mid-fade on death) | Keeps SubViewport ownership clean and survives `queue_free()` |
| Displacement stamps | Extend `main._process` to iterate enemies with per-enemy "distance since last wake ring" counters | `DisplacementStamps.spawn_wake_ring()` already takes a world position — no changes to that node |
| Cannonball impact on player | When `owner_team == ENEMY` hits a `Ship` body, spawn the existing impact explosion + despawn (no HP change) | Satisfies "don't worry about player HP" while leaving a clear hook |
| Git worktree | `git worktree add ../PirateShipGame-enemy-combat -b feat/enemy-combat-and-wakes` | Isolate the refactor from `main` until fully validated |

### Collision Layer Plan

Existing (from `project.godot`):
- layer 1 = `player`
- layer 2 = `enemies`
- layer 3 = `player_projectiles`
- layer 4 = `hazards`

**Add**: layer 5 = `enemy_projectiles`

| Entity | Layer | Mask | Rationale |
|---|---|---|---|
| Player `Ship` | 1 | 2 + 5 = `enemies, enemy_projectiles` | Ship collides with enemies, gets hit by enemy cannonballs |
| `EnemyShip` | 2 | 1 + 3 = `player, player_projectiles` | Unchanged — still takes player hits |
| Player `Cannonball` (owner=PLAYER) | 3 | 2 = `enemies` | Unchanged |
| Enemy `Cannonball` (owner=ENEMY) | 5 | 1 = `player` | Can only hit the player, never other enemies |

Enemy cannonballs deliberately **exclude** layer 2 to prevent friendly fire across enemy ships.

## Technical Approach

### Phase 1 — Worktree setup

```bash
git worktree add ../PirateShipGame-enemy-combat -b feat/enemy-combat-and-wakes
cd ../PirateShipGame-enemy-combat
```

All subsequent work happens in this worktree. When done, `gdformat --check .` and `gdlint .` must be clean and `run_project` must produce zero errors.

### Phase 2 — Cannonball ownership + new collision layer

**[project.godot](project.godot)** — add:
```
[layer_names]
2d_physics/layer_5="enemy_projectiles"
```

**[scripts/cannonball.gd](scripts/cannonball.gd)** — add team ownership:

```gdscript
class_name Cannonball
extends Area2D

enum Team { PLAYER, ENEMY }

@export var speed: float = 200.0
@export var max_range: float = 150.0
@export var range_randomness: float = 0.3

var owner_team: Team = Team.PLAYER  # set by whoever spawns the ball
var _direction: Vector2 = Vector2.ZERO
var _target_distance: float = 0.0
var _distance_traveled: float = 0.0
var _impacted: bool = false


func setup(pos: Vector2, dir: Vector2, team: Team = Team.PLAYER) -> void:
    global_position = pos
    _direction = dir.normalized()
    rotation = _direction.angle()
    owner_team = team
    var min_dist: float = max_range * (1.0 - range_randomness)
    _target_distance = randf_range(min_dist, max_range)
    # Configure collision based on team
    if team == Team.ENEMY:
        collision_layer = 1 << 4  # bit 4 = layer 5 = enemy_projectiles
        collision_mask = 1 << 0   # bit 0 = layer 1 = player
    else:
        collision_layer = 1 << 2  # unchanged = player_projectiles
        collision_mask = 1 << 1   # unchanged = enemies


func _on_body_entered(body: Node2D) -> void:
    if _impacted:
        return
    if owner_team == Team.PLAYER and body is EnemyShip:
        _impacted = true
        body.take_damage(_direction)
        ExplosionSprite.create(get_parent(), global_position, "cannonball_impact", _direction)
        queue_free()
    elif owner_team == Team.ENEMY and body.is_in_group("player"):
        # Player-hit visual, NO HP change (per spec: don't worry about player HP)
        _impacted = true
        ExplosionSprite.create(get_parent(), global_position, "cannonball_impact", _direction)
        queue_free()
```

**[scenes/cannonball.tscn](scenes/cannonball.tscn)** — no layer bits in the scene; they are assigned in `setup()` based on team. Keep the default as `layer=4, mask=2` for inspector sanity (matches player default).

**[scripts/ship.gd](scripts/ship.gd)** `_ready()` — add to `"player"` group so enemy cannonballs can detect it:
```gdscript
add_to_group("player")
```

### Phase 3 — Enemy cannons and firing behavior

**[scenes/enemy_ship.tscn](scenes/enemy_ship.tscn)** — add cannons identical to player:

```
[node name="CannonSlots" type="Node2D" parent="."]

[node name="PortCannon1" type="Marker2D" parent="CannonSlots"]
position = Vector2(-12, -8)
rotation = 3.14159
[node name="Cannon" parent="CannonSlots/PortCannon1" instance=ExtResource("cannon.tscn")]

[node name="PortCannon2" type="Marker2D" parent="CannonSlots"]
position = Vector2(-12, 8)
rotation = 3.14159
[node name="Cannon" parent="CannonSlots/PortCannon2" instance=ExtResource("cannon.tscn")]

[node name="StarboardCannon1" type="Marker2D" parent="CannonSlots"]
position = Vector2(12, -8)
[node name="Cannon" parent="CannonSlots/StarboardCannon1" instance=ExtResource("cannon.tscn")]

[node name="StarboardCannon2" type="Marker2D" parent="CannonSlots"]
position = Vector2(12, 8)
[node name="Cannon" parent="CannonSlots/StarboardCannon2" instance=ExtResource("cannon.tscn")]
```

Reuse `res://scenes/cannon.tscn`. Add UID import via editor or text (validate with `update_project_uids`).

**[scripts/enemy_ship.gd](scripts/enemy_ship.gd)** — add firing logic:

```gdscript
signal destroyed(ship: EnemyShip)
signal cannon_fired(pos: Vector2, dir: Vector2)

@export var broadside_cooldown: float = 2.0
@export var broadside_range: float = 180.0
@export var broadside_alignment_threshold: float = 0.85  # |dot(right, to_target_dir)|

var _port_ready: bool = true
var _starboard_ready: bool = true

@onready var _cannon_slots: Node2D = $CannonSlots


func _ready() -> void:
    # ... existing asserts ...
    assert(_cannon_slots != null, "EnemyShip: CannonSlots not found")
    # ... existing setup ...


func _physics_process(delta: float) -> void:
    if _target and is_instance_valid(_target) and not _is_destroyed:
        _steer_toward_target(delta)
        _try_fire_at_target()
    move_and_slide()
    _process_shake(delta)


func _try_fire_at_target() -> void:
    if _is_destroyed:
        return
    var to_target: Vector2 = _target.global_position - global_position
    if to_target.length() > broadside_range:
        return
    var dir_to_target: Vector2 = to_target.normalized()
    # Ship forward is -transform.y, so starboard is +transform.x, port is -transform.x
    var starboard: Vector2 = transform.x
    var dot: float = starboard.dot(dir_to_target)
    if dot >= broadside_alignment_threshold and _starboard_ready:
        _fire_broadside("starboard")
    elif dot <= -broadside_alignment_threshold and _port_ready:
        _fire_broadside("port")


func _fire_broadside(side: String) -> void:
    var prefix: String = "Port" if side == "port" else "Starboard"
    for slot: Node in _cannon_slots.get_children():
        if not slot.name.begins_with(prefix):
            continue
        if slot.get_child_count() == 0:
            continue
        var cannon: Cannon = slot.get_child(0) as Cannon
        if cannon == null:
            continue
        var result: Dictionary = cannon.fire()
        cannon_fired.emit(result["position"], result["direction"])
    if side == "port":
        _port_ready = false
        get_tree().create_timer(broadside_cooldown).timeout.connect(
            func() -> void: _port_ready = true
        )
    else:
        _starboard_ready = false
        get_tree().create_timer(broadside_cooldown).timeout.connect(
            func() -> void: _starboard_ready = true
        )
```

**[scripts/main.gd](scripts/main.gd)** — wire enemy signal and spawn enemy cannonballs:

```gdscript
func _try_spawn_enemy() -> void:
    # ... existing code ...
    enemy.destroyed.connect(_on_enemy_destroyed)
    enemy.cannon_fired.connect(_on_enemy_cannon_fired)
    enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
    add_child(enemy)
    enemy.global_position = spawn_pos
    enemy.reset_physics_interpolation()
    enemy.setup(_ship)
    _enemies.append(enemy)
    _register_enemy_wake(enemy)  # see Phase 4


func _on_enemy_cannon_fired(pos: Vector2, dir: Vector2) -> void:
    var ball: Cannonball = CannonballScene.instantiate()
    add_child(ball)
    ball.setup(pos, dir, Cannonball.Team.ENEMY)
    ExplosionSprite.create(self, pos, "muzzle_flash", dir)
```

### Phase 4 — Multi-ship wake trail

**Refactor [scripts/trails.gd](scripts/trails.gd)** to compute positions in "SubViewport-centered world space" — i.e. `subviewport_pos = (world_pos - pivot.global_position) + viewport_center`, where `pivot` is the player ship (the node the SubViewport follows). This removes the `to_local()` rotation coupling and makes the Line2D's points consistent regardless of which ship it follows.

Rationale: the water shader samples `WakeTrailMap` with `disp_uv` which is already aligned with the player-centered displacement viewport. Using the player as the pivot for all trails means enemies render into the same correctly-aligned texture.

```gdscript
extends Line2D

@export var max_length: int = 90
@export var sub_viewport: SubViewport
@export var follow_target: Node2D     ## ship whose movement drives this trail
@export var pivot_target: Node2D      ## player ship — the SubViewport's center
@export var distance_at_largest_width: float = 16.0 * 6.0
@export var smallest_tip_width: float = 0.15
@export var largest_tip_width: float = 0.8

var _queue: Array[Vector2] = []
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
    assert(sub_viewport != null, "Trails: sub_viewport must be assigned")
    assert(follow_target != null, "Trails: follow_target must be assigned")
    assert(pivot_target != null, "Trails: pivot_target must be assigned")
    assert(width_curve != null and width_curve.point_count > 0,
        "Trails: width_curve must have at least one point")
    _center = Vector2(sub_viewport.size) / 2.0
    # Duplicate the Curve so per-instance width mutations don't cross-contaminate.
    width_curve = width_curve.duplicate()


func _process(_delta: float) -> void:
    if not is_instance_valid(follow_target) or not is_instance_valid(pivot_target):
        return
    var world_pos: Vector2 = follow_target.global_position
    _queue.append(world_pos)
    while _queue.size() > max_length and _queue.size() > 2:
        _queue.pop_front()

    var length: float = 0.0
    clear_points()
    var pivot_pos: Vector2 = pivot_target.global_position
    for i: int in range(_queue.size() - 1):
        length += _queue[i].distance_to(_queue[i + 1])
        add_point(_queue[i] - pivot_pos + _center)
    add_point(_queue[-1] - pivot_pos + _center)

    var t: float = clampf(inverse_lerp(0.0, distance_at_largest_width, length), 0.0, 1.0)
    width_curve.set_point_value(0, lerpf(smallest_tip_width, largest_tip_width, t))


func reset_line() -> void:
    clear_points()
    _queue.clear()
```

**Verify the player trail still looks correct** after the pivot refactor — this is the biggest risk in Phase 4. The player trail's visual should be visually identical before and after. If the old `to_local` rotation was producing a specific look, the new pivot-based math may look slightly different; if that happens, accept it (the new math is the correct world-space behavior) and tune width/gradient if needed.

**[scenes/main.tscn](scenes/main.tscn)** — set `pivot_target = NodePath("../../../Ship")` on the existing player Line2D inside `WaterTrail/SubViewport`.

**[scripts/main.gd](scripts/main.gd)** — create per-enemy Line2D on spawn, free on despawn. Use a small helper and a map:

```gdscript
const TrailsScript: Script = preload("res://scripts/trails.gd")
const TrailWidthCurve: Curve = preload("res://resources/trail_width_curve.tres")
const TrailGradientTex: Texture2D = preload("res://textures/WaterTrailGradient.png")

var _enemy_trails: Dictionary = {}  # enemy instance_id → Line2D


func _register_enemy_wake(enemy: EnemyShip) -> void:
    var line := Line2D.new()
    line.set_script(TrailsScript)
    line.width = 36.0
    line.width_curve = TrailWidthCurve
    line.texture = TrailGradientTex
    line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
    line.joint_mode = Line2D.LINE_JOINT_ROUND
    line.begin_cap_mode = Line2D.LINE_CAP_ROUND
    line.end_cap_mode = Line2D.LINE_CAP_ROUND
    # Gradient (white, 0→1 alpha) — same as player's SubResource
    var grad := Gradient.new()
    grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
    line.gradient = grad
    line.max_length = 90
    line.sub_viewport = $WaterTrail/SubViewport
    line.follow_target = enemy
    line.pivot_target = _ship
    $WaterTrail/SubViewport.add_child(line)
    _enemy_trails[enemy.get_instance_id()] = line


func _unregister_enemy_wake(enemy: EnemyShip) -> void:
    var id: int = enemy.get_instance_id()
    if _enemy_trails.has(id):
        var line: Line2D = _enemy_trails[id]
        if is_instance_valid(line):
            line.queue_free()
        _enemy_trails.erase(id)


func _on_enemy_destroyed(enemy: EnemyShip) -> void:
    _unregister_enemy_wake(enemy)
    _enemies.erase(enemy)


func _on_enemy_tree_exiting(enemy: EnemyShip) -> void:
    _unregister_enemy_wake(enemy)
    _enemies.erase(enemy)
```

Line2Ds live inside the SubViewport, not under the enemy node, so they are not freed when the enemy's `queue_free()` runs mid fade-out — Main owns their lifecycle.

### Phase 5 — Per-enemy displacement wake rings

Extend `main._process` with a per-enemy distance counter. Store `{instance_id: {"last_pos": Vector2, "accum": float}}`:

```gdscript
var _enemy_wake_state: Dictionary = {}  # instance_id → { last_pos, accum }


func _process(_delta: float) -> void:
    # ... existing player wake ring code ...

    # Per-enemy wake rings
    for enemy: EnemyShip in _enemies:
        if not is_instance_valid(enemy) or enemy.is_destroyed():
            continue
        var id: int = enemy.get_instance_id()
        if not _enemy_wake_state.has(id):
            _enemy_wake_state[id] = {
                "last_pos": enemy.global_position,
                "accum": 0.0,
            }
            continue
        var state: Dictionary = _enemy_wake_state[id]
        state["accum"] += enemy.global_position.distance_to(state["last_pos"])
        state["last_pos"] = enemy.global_position
        if state["accum"] >= 16.0:
            state["accum"] = 0.0
            var wake_pos: Vector2 = enemy.global_position - enemy.transform.y * 12.0
            _displacement_stamps.spawn_wake_ring(wake_pos)

    # Prune stale entries
    for id: int in _enemy_wake_state.keys():
        if not instance_from_id(id):
            _enemy_wake_state.erase(id)
```

(Prune can alternatively happen in `_unregister_enemy_wake`.)

Note: `DisplacementStamps` has a hard cap of `MAX_STAMPS = 32`. Four enemies + player + mines can approach this; verify during testing that stamps are still visible for the player and consider raising the cap to 48 if starvation occurs.

### Phase 6 — Polish & test

- Run the project via MCP (`run_project` → `get_debug_output` → `stop_project`).
- Drive the player within enemy broadside range and verify:
  - Enemies emit muzzle flashes and spawn cannonballs that travel outward.
  - Enemy cannonballs hit the player ship and spawn an impact explosion (no HP change).
  - Each enemy leaves a visible wake trail behind it.
  - Each enemy emits wake rings into the displacement map when moving.
  - Player's wake trail still looks correct after the `trails.gd` refactor.
- Verify zero errors in debug output.
- Run `gdformat --check .` and `gdlint .`.

## File Summary

| File | Action | Purpose |
|---|---|---|
| `project.godot` | **Modify** | Add layer 5 = `enemy_projectiles` |
| `scripts/cannonball.gd` | **Modify** | Add `Team` enum, `owner_team`, layer/mask assignment in `setup()`, branch `_on_body_entered` |
| `scripts/ship.gd` | **Modify** | `add_to_group("player")` in `_ready` |
| `scripts/enemy_ship.gd` | **Modify** | Add `cannon_fired` signal, `_try_fire_at_target`, `_fire_broadside`, per-side cooldowns, `CannonSlots` @onready |
| `scenes/enemy_ship.tscn` | **Modify** | Add `CannonSlots` + 4 Cannon instances (mirror player) |
| `scripts/trails.gd` | **Modify** | Add `pivot_target` export; replace `to_local()` with `world - pivot + center` math |
| `scenes/main.tscn` | **Modify** | Set `pivot_target` on the existing player Line2D |
| `scripts/main.gd` | **Modify** | `_on_enemy_cannon_fired`, `_register_enemy_wake`, `_unregister_enemy_wake`, per-enemy displacement ring spawning |

No new files are created.

## System-Wide Impact

### Signal chain

- `EnemyShip._physics_process` → `_try_fire_at_target()` → `_fire_broadside()` → `Cannon.fire()` → `EnemyShip.cannon_fired.emit(pos, dir)` → `main._on_enemy_cannon_fired()` → `Cannonball.setup(pos, dir, ENEMY)` → physics process moves ball → `body_entered` fires on player hit → impact explosion spawns → ball frees.
- `main._try_spawn_enemy()` → `_register_enemy_wake(enemy)` adds a Line2D to the wake SubViewport. Either `enemy.destroyed` or `enemy.tree_exiting` fires → `_unregister_enemy_wake()` frees the Line2D.

### Error & failure propagation

- `_try_fire_at_target` early-returns on `_is_destroyed` or missing target — no firing after death.
- `Cannonball.setup()` configures layer/mask deterministically; if `team` is wrong, the ball hits nothing and harmlessly times out at max range.
- `trails.gd` guards `is_instance_valid(follow_target/pivot_target)` — pivot death (impossible while player exists) or follow-target death during tween doesn't crash.
- `_unregister_enemy_wake` is called from BOTH `destroyed` and `tree_exiting` — the second call is a no-op (dictionary `has` check).

### State lifecycle risks

- Enemy fade-out tween must not be interrupted by `_unregister_enemy_wake` — the wake Line2D is a sibling of the enemy under the SubViewport, not a child, so freeing it has no effect on the enemy's fade.
- `_enemy_trails` and `_enemy_wake_state` dictionaries must be cleaned in both spawn-exit paths to avoid leaks.
- `DisplacementStamps.MAX_STAMPS = 32` could be saturated with 4 enemies + player + mines; verify or raise cap.

### Scene interface parity

- `EnemyShip` now mirrors `Ship` for firing (`cannon_fired` signal), cannon placement (identical `CannonSlots` structure), and wake trail contribution.
- Both use the same `Cannonball` script with an ownership flag.

### Integration test scenarios

1. **Crossfire** — player and enemy both fire at the same frame; neither ball hits its own team.
2. **Enemy death mid-fire** — enemy fires on the same frame a player cannonball destroys it; the enemy cannonball still travels and times out without errors.
3. **Enemy despawn** — enemy exits `despawn_distance` while its wake trail is mid-fade; trail Line2D is freed cleanly, no orphaned dictionary entries.
4. **Player trail parity** — player trail before and after the `trails.gd` refactor; side-by-side visual check.
5. **Displacement saturation** — 4 enemies circling + player dropping mines; verify displacement stamps don't starve the wake rings.

## Acceptance Criteria

### Setup
- [ ] Work happens in a git worktree (`../PirateShipGame-enemy-combat`, branch `feat/enemy-combat-and-wakes`).
- [ ] Layer 5 `enemy_projectiles` added to `project.godot`.
- [ ] `Cannonball.gd` exposes `const LAYER_PLAYER_BALL`, `const LAYER_ENEMY_BALL`, `const MASK_PLAYER`, `const MASK_ENEMIES` at top of file (no magic bit math in `setup()`).

### Combat
- [ ] `Cannonball.setup()` takes a `bool is_enemy_owned` (not an enum) and configures layer/mask + applies a reddish `modulate` when true.
- [ ] `class_name Ship` added to `scripts/ship.gd`; `Cannonball._on_body_entered` uses `body is Ship` (no `"player"` group).
- [ ] Enemy ship scene has **1 port + 1 starboard** cannon (not 4 total) at mirrored positions.
- [ ] Enemy fires when the player is roughly perpendicular AND within `broadside_range` AND per-side cooldown is ready.
- [ ] `broadside_range ≤ Cannonball.max_range`, enforced at `_ready` via `assert`.
- [ ] Per-side cooldowns use `float` counters in `_physics_process`, **not** `create_timer` lambdas (no freed-instance errors).
- [ ] `_try_fire_at_target` early-returns if `_target` is null, invalid, destroyed, or queued for deletion.
- [ ] Cached `_port_cannons: Array[Cannon]` and `_starboard_cannons: Array[Cannon]` in `_ready()` — no string matching in the fire path.
- [ ] Enemy muzzle flash spawns on each fired shot.
- [ ] Enemy cannonballs that hit the player spawn an impact explosion (no HP change).
- [ ] Enemy cannonballs that time out at max range spawn a splash + displacement stamp (parity with player).
- [ ] Enemy cannonballs **cannot** hit other enemies (mask excludes layer 2).
- [ ] Player cannonballs still hit enemies (regression).
- [ ] Enemy cannonballs are visually distinguishable from the player's (reddish tint).

### Wake trails
- [ ] `scenes/wake_trail.tscn` exists; both the player and each enemy use it (the existing player Line2D in `main.tscn` is refactored to instance it).
- [ ] `trails.gd` uses `pivot_target` with world-space math; player trail looks correct (side-by-side visual check vs pre-refactor).
- [ ] `trails.gd` uses incremental `add_point` / `remove_point(0)` (no `clear_points()` / full rebuild every frame).
- [ ] `trails.gd` uses `distance_squared_to()` for the length accumulation.
- [ ] `width_curve` is duplicated in `_ready` (confirm via comment).
- [ ] Each enemy has a visible wake trail while moving.
- [ ] On enemy death, the wake trail `modulate:a` fades 1→0 over ~0.4s (matches hull fade) before freeing; it does NOT snap-clear.
- [ ] Enemy wake trails are freed on despawn as well.
- [ ] Wake `SubViewport` is 512×512 (shrunk from 1024).

### Displacement stamps
- [ ] Each `EnemyShip` holds `_wake_accum: float` and `_last_wake_pos: Vector2` as its own members (no `_enemy_wake_state` dict on Main).
- [ ] Main emits wake rings per enemy at a **24px** interval (vs 16px for player).
- [ ] `DisplacementStamps.MAX_STAMPS` raised from 32 to 48.
- [ ] Single cleanup path: `tree_exiting` is the sole trigger for `_enemies.erase` and `_unregister_enemy_wake`. The `destroyed` signal is no longer connected to bookkeeping.

### Scene authoring
- [ ] All `.tscn` edits (`scenes/enemy_ship.tscn`, `scenes/main.tscn`, `scenes/wake_trail.tscn`) are authored via the Godot editor or MCP tools (`add_node`, `save_scene`, `update_project_uids`) — NOT hand-edited via `Write`/`Edit`.
- [ ] `mcp__godot__update_project_uids` run after scene edits; no dangling UIDs.

### Integration & hygiene
- [ ] Integration scenario: 4 enemies alive + player firing both broadsides + 1-2 mines exploding → zero errors in debug output; all wakes visible; no displacement-stamp starvation (player wake never stutters).
- [ ] Mine-kill path on enemies correctly cleans up wake trails (audit `sea_mine.gd` kill codepath; verify `tree_exiting` fires).
- [ ] `gdformat --check .` is clean.
- [ ] `gdlint .` is clean.
- [ ] `run_project` produces zero errors during a full play session.
- [ ] Player HP is **not** modified by enemy cannonball hits (per spec).

## Dependencies & Risks

- **`trails.gd` refactor** is the highest-risk change. The existing `to_local` math couples the trail to ship rotation in a way that may be intentional. Mitigation: keep the player trail fully working; if the visual changes, tune width/gradient or accept the new (more correct) world-space behavior.
- **DisplacementStamps cap** (32) could be saturated. Mitigation: raise to 48 if observed.
- **Layer bit math** — Godot layers are 1-indexed in the UI but zero-indexed in `1 << n`. Keep comments explicit.
- **Cannonball UID/scene stability** — if the enemy cannonball tree uses a second cannonball scene, we'd need a new `.tscn`/`.uid`. We deliberately reuse the single scene with team parameterization to avoid this.

## Sources & References

- Existing enemy plan: [docs/plans/2026-04-05-feat-enemy-ships-spawning-collisions-damage-plan.md](docs/plans/2026-04-05-feat-enemy-ships-spawning-collisions-damage-plan.md)
- Player ship: [scripts/ship.gd](scripts/ship.gd), [scenes/ship.tscn](scenes/ship.tscn)
- Enemy ship: [scripts/enemy_ship.gd](scripts/enemy_ship.gd), [scenes/enemy_ship.tscn](scenes/enemy_ship.tscn)
- Cannon/cannonball: [scripts/cannon.gd](scripts/cannon.gd), [scripts/cannonball.gd](scripts/cannonball.gd), [scenes/cannonball.tscn](scenes/cannonball.tscn)
- Wake trail: [scripts/trails.gd](scripts/trails.gd), [scenes/main.tscn](scenes/main.tscn)
- Displacement: [scripts/displacement_stamps.gd](scripts/displacement_stamps.gd)
- Water shader WakeTrailMap sampling: [shaders/water_surface.gdshader:51](shaders/water_surface.gdshader#L51)
- Main scene wiring: [scripts/main.gd](scripts/main.gd)
- Resource mutation safety: [docs/solutions/shared-resource-mutation.md](docs/solutions/shared-resource-mutation.md)
- Line2D gotcha: [docs/solutions/line2d-round-joint-alpha-gradient-asymmetry.md](docs/solutions/line2d-round-joint-alpha-gradient-asymmetry.md)
