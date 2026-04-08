## ADR 007: Events Bus Discipline — Entity-Root Publishers, Listener-Owns-the-Work

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 005 (components)](005-component-decomposition-strategy.md), [ADR 008 (GameState)](008-gamestate-autoload-scope.md), [ADR 011 (audio)](011-audio-architecture.md)

## Context

Before the refactor, cross-system events were carried by direct signal connections made in `main.gd`'s `_ready()`:

```gdscript
ship.damaged.connect(_on_ship_damaged)
ship.died.connect(_on_ship_died)
enemy_spawned.connect(_on_enemy_spawned)
# …17 more lines
```

This works for a few entities but scales poorly:

1. Adding a new subscriber requires editing `main.gd` and knowing which publisher to find.
2. Dynamic entities (enemies spawned at runtime) have no central wire-up point — each spawner duplicates the subscription code.
3. `main.gd` becomes the implicit dependency graph, bloating in proportion to cross-system traffic.

The plan introduced the [`Events` autoload](../../autoload/events.gd) as a global signal bus. The open questions were:

1. **Who may publish?** Any component, or only specific nodes?
2. **Who may subscribe?** Anyone, or only specific listener nodes?
3. **What counts as "cross-system"?** (Where's the line between bus traffic and direct signal connection?)
4. **Are there payload-shape rules?** (Untyped Dictionary vs typed args; high-frequency vs low-frequency?)

## Decision

### 1. Publisher rules

**Only entity roots and service nodes publish to the bus.** Components do NOT touch the `Events` autoload directly. The entity root (Ship, EnemyShip, WaveDirector, SpawnService) listens to its own components and re-emits to the bus.

Publishers:
- **Entity roots**: `ship.gd`, `enemy_ship.gd`, `cannonball.gd`, `sea_mine.gd`.
- **Service nodes**: `wave_director.gd`, `spawn_service.gd`, `water_effects_manager.gd`, `stats_tracker.gd`.
- **Autoloads emit to themselves only**; no autoload re-publishes another autoload's signals.

**Exception — HitFeedbackComponent and AudioEmitterComponent publish directly.** These are "terminal output" components: they read state and emit signals nobody listens to locally. Routing their emissions through Ship root would add a line of forwarding code per signal with zero decoupling benefit. They're local subscribers to the entity root's signals (`damaged`, `state_changed`) and direct bus publishers.

### 2. Listener-owns-the-work principle

**A signal with a single natural receiver does NOT get an intermediate listener node.** Example:

- `screen_shake_requested` → GameCamera directly subscribes. No `camera_shake_listener.gd` proxy.
- `explosion_requested` → [VfxListener](../../features/vfx/vfx_listener.gd) subscribes and instantiates `ExplosionSprite`. Has a dedicated listener because there are many spawn sites and explosions need a persistent parent that outlives the emitter's `queue_free()`.
- `cannonball_water_impact` → WaterEffectsManager subscribes directly; it's the only receiver, so no proxy.

The pattern lesson from Phase 9 (parent plan line 249–262): "forwarding through a listener would add a pointless hop." Uniformity is not worth a needless layer of indirection.

### 3. Publishers own the tuning lookup, listeners are dumb

When a listener exists, the **publisher does the parameter lookup, the listener is a thin dispatch**. Example from Phase 9:

- `WaterEffectsManager` (smart publisher) reads `WaterTuning.tres` and emits `displacement_impact_requested(pos, radius_px, duration)` with pre-computed values.
- `water_listener.gd` (dumb forwarder) just calls `displacement_stamps.spawn_impact(pos, radius_px, duration)`.

The listener doesn't know WaterTuning exists; all tuning magic numbers live in one place.

### 4. Typed signals, no untyped Dictionaries

Every bus signal has explicit typed parameters. Example from [events.gd](../../autoload/events.gd):

```gdscript
signal player_damaged(amount: int, source: Node)
signal enemy_destroyed(enemy: Node, by_mine: bool)
signal explosion_requested(pos: Vector2, kind: StringName, dir: Vector2, vel: Vector2)
```

**Stat signals are typed per-stat, not a generic `stat_recorded(key, value: Variant)`:**

```gdscript
signal kill_recorded
signal death_recorded
signal damage_recorded(amount: int)
signal wave_time_recorded(index: int, seconds: float)
```

Rationale: typed per-stat signals restore end-to-end type safety — a misspelled key on a generic signal fails silently. See Research Delta #18 in the parent plan.

**`StringName` for enum-like string params** (`sound_id`, `cheat_id`, `kind`) to avoid allocation churn and document the expected value domain.

**Parameter naming avoids shadowing built-ins**: `sound_requested(sound_id, pos)` not `sound_requested(name, pos)` — `Node.name` would be shadowed by the parameter (Research Delta #16). Same for `cheat_toggled(cheat_id, active)`.

### 5. High-frequency signals are OK on the bus

The pre-Phase-9 rule "displacement signals stay off the bus because they fire at 60Hz" was a prediction, not a measurement. Phase 9 measured ~5 displacement emits/frame on a typed value-type signal with one listener as unmeasurable noise. The rule was dropped; `displacement_impact_requested`, `displacement_wake_ring_requested`, and `displacement_bob_requested` are all on the bus (Phase 9 retro line 263–272 in the parent plan).

**Uniformity beats premature optimization.** There are no carve-outs for "use the bus for some cross-system events but not others." Every cross-system event goes through the bus.

### 6. Silent-failure mitigation

**Bus signal failures are silent.** A missing listener connection silently drops the effect — no error, no warning. This is a feature (decoupling) with a cost (one missing `Events.foo.connect(...)` breaks a feature invisibly).

Mitigations:
- Each autoload logs via `print_debug()` on first bus connect in dev builds.
- `class_name` + typed signal parameters mean parse-time errors on shape mismatches.
- The `@warning_ignore_start("unused_signal")` / `_restore` block on `events.gd` documents that these signals are intentionally published-only from this file's perspective — emitters live elsewhere.

### 7. Autoload initialization order

`Events` is registered **first** among autoloads (`Events → GameState → AudioManager → KeybindsManager`). This ordering matters: any node connecting in its own `_ready()` must find the signals already declared. Cross-autoload references are allowed only inside `_ready()` or later — NO file-scope `const X = preload("res://autoload/…")`, which would create init-order dependencies before Godot's autoload table has finished booting.

### 8. Collision layer table

Phase 7 grew the collision layer/mask table by one slot to support player-vs-enemy projectile filtering:

| Layer | Name                  |
|-------|-----------------------|
| 1–5   | (pre-existing)        |
| 6     | `player_hurtbox`      |
| 7     | `enemy_hurtbox`       |

Cannonball masks split: player balls mask `MASK_ENEMY_HURTBOX (1<<6)`, enemy balls mask `MASK_PLAYER_HURTBOX (1<<5)`. Both sides route through `Area2D.area_entered` against hurtbox areas. The legacy `body_entered` direct-call path (`(body as EnemyShip).take_damage(...)`) is gone (Phase 7 retro line 388–397 in the parent plan).

## Consequences

**Positive:**
- **Dynamic entities wire themselves.** A newly spawned enemy connects to `Events.player_died` in its own `_ready()` — no spawner-side subscription bookkeeping.
- **`main.gd` shrank** from 394 LOC to ~92 LOC. Most of the disappearing lines were the pre-refactor `connect()` wall.
- **Replacing a listener is trivial.** Swap `vfx_listener.gd` for a test double; nothing upstream notices.
- **Type safety holds end-to-end.** Because every signal is typed, parse errors catch shape mismatches; the debug overlay can display recent bus traffic.
- **One rule for when to use the bus**: cross-system → bus. Within a scene → direct signal. No carve-outs to remember.

**Negative:**
- **Discovery is harder.** "Who subscribes to `explosion_requested`?" requires a grep instead of following a direct connection. Mitigation: `events.gd` header documents each listener class name in a comment where it matters (the `# --- Water displacement` block does this).
- **Initial connection gotcha**. Components running their `_ready()` before the entity root finishes wiring can miss the first emit if the entity root doesn't `call_deferred` the initial fire. ADR 006 documents the pattern for FSM initial state.
- **Silent failures are real.** One unconnected listener means one broken feature with no runtime error. The mitigation list above is real but incomplete; code review is the ultimate gate.
- **Layer table is fragile.** Adding a ninth physics layer means touching `project.godot` AND every mask in every scene that cares. Document the layer table in `project.godot` comments so the table doesn't drift.

## Alternatives Considered

**No bus; route everything through `main.gd`.** The pre-refactor state. Rejected because dynamic entities would still have to reach into `main.gd` somehow, and `main.gd` grows as a linear function of cross-system traffic.

**Bus carries anything, including within-scene signals.** Rejected. Within-scene traffic has a natural parent/child relationship — using the bus for it adds unnecessary indirection and makes local reasoning harder ("does my parent get this signal? Only if the bus finishes dispatching first?").

**High-frequency signals stay off the bus.** Tried in the pre-Phase-9 rule; Phase 9 measured the cost and discarded the rule. Uniformity beats micro-optimization at the measured emit rates.

**Dictionary payloads for extensibility.** Considered for `stat_recorded(key, value: Variant)`. Rejected because typed per-stat signals restore end-to-end type safety (Research Delta #18). If the stat schema ever gets large enough to justify a generic mechanism, a typed `Stat` enum + `stat_recorded(stat: Stat, value: float)` is the upgrade path, not untyped Variants.

**Explicit publish/subscribe registration (not raw `signal`).** I.e., an `Events.publish("foo", args)` + `Events.subscribe("foo", callback)` API. Rejected. Raw Godot signals give us everything we need: typed payloads, editor visibility, parse-time shape checking, and zero boilerplate.
