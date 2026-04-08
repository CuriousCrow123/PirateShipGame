## ADR 014: Cooldown Helper — Timestamp Over Ticked

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 005 (components)](005-component-decomposition-strategy.md), [ADR 013 (ship components)](013-ship-component-decomposition.md)

## Context

Pre-refactor, "wait N seconds and then do X" was implemented via `get_tree().create_timer(seconds).timeout.connect(func(): ...)` lambdas scattered across:

- Ship respawn cooldown (`scripts/ship.gd`).
- Mine arm + fuse timers (`scripts/sea_mine.gd`).
- Wave spawn staggering (`scripts/main.gd`).
- Dash freeze-frame / time-dip (`scripts/ship.gd`).
- HUD toast fade-out (`scripts/wave_toast.gd`).
- Explosion atlas bake pacing (`scripts/explosion_test.gd`).

The audit count (Research Delta #4) found **10 sites across 5 files**, not 5 as the brainstorm estimated. Three problems with this pattern:

1. **Lambda allocation per call.** A new Callable + one-shot Timer object per fire.
2. **No way to query "how much time remains?"** — the SceneTreeTimer is fire-and-forget. Progress bars and HUD cooldown displays had to track the start time manually.
3. **No idempotency.** Calling the fire path twice creates two overlapping timers that both fire their lambdas.

The brainstorm called for a `Cooldown` helper. The open design question: **tick-based or timestamp-based?**

**Tick-based** looked like the "Godot-native" option:
```gdscript
class_name Cooldown extends RefCounted
var _remaining: float = 0.0
func tick(delta: float) -> void: _remaining = max(0.0, _remaining - delta)
func is_ready() -> bool: return _remaining <= 0.0
```
Callers would add `_cooldown.tick(delta)` to their `_physics_process` or `_process`.

**Timestamp-based**:
```gdscript
var _ready_at_msec: int = 0
func start(duration: float) -> void:
    _ready_at_msec = Time.get_ticks_msec() + int(duration * 1000.0)
func is_ready() -> bool: return Time.get_ticks_msec() >= _ready_at_msec
```

Zero per-frame cost. But wall-clock based, so `Engine.time_scale` doesn't affect it.

## Decision

**Timestamp-based**, implemented as [systems/cooldown.gd](../../systems/cooldown.gd). The file header documents the trade-offs:

```gdscript
class_name Cooldown
extends RefCounted

## Timestamp-based cooldown timer. Zero per-frame cost: no tick() callback,
## no _process subscription. Owners just call start() and is_ready().
##
## Wall-clock based (Time.get_ticks_msec()), so this is INDEPENDENT of
## Engine.time_scale. That makes it the wrong tool for freeze-frame /
## time-dip effects — those need a scaled timer; DashComponent has its
## own unscaled+wall-clock pair (see plan Phase 6 Step 34b/34c).

var _ready_at_msec: int = 0
var _duration_msec: int = 0


func start(duration: float) -> void:
    _duration_msec = int(duration * 1000.0)
    _ready_at_msec = Time.get_ticks_msec() + _duration_msec


func is_ready() -> bool:
    return Time.get_ticks_msec() >= _ready_at_msec


func remaining() -> float:
    return maxf(0.0, float(_ready_at_msec - Time.get_ticks_msec()) / 1000.0)


func progress() -> float:
    if _duration_msec <= 0:
        return 1.0
    var left: int = maxi(0, _ready_at_msec - Time.get_ticks_msec())
    return 1.0 - float(left) / float(_duration_msec)
```

### Why timestamp won

1. **Zero per-frame cost.** No `tick(delta)` call in `_process`. A cooldown that nobody queries for an hour costs exactly nothing. The 10 pre-refactor timer sites became 10 cheap query-on-demand call sites; MovementComponent, DashComponent, and friends don't tick helpers they don't need.

2. **Queries are O(1).** `remaining()` and `progress()` are one subtraction + one divide. HUD progress bars (MineCooldownDisplay) read `progress()` per frame directly — no start-time bookkeeping on the consumer side.

3. **Idempotent.** Calling `start(2.0)` twice restarts the cooldown from now with a 2.0s duration. No overlapping timers.

4. **Survives pause.** `Time.get_ticks_msec()` continues across `get_tree().paused = true`. This is sometimes what you want (respawn cooldown shouldn't freeze when the pause menu is up) and sometimes not (see Consequences). The header documents the caveat.

### Why not ticked

A ticked `Cooldown` would require every owning component to add a line to its `_physics_process`:
```gdscript
func _physics_process(delta: float) -> void:
    _respawn_cooldown.tick(delta)
    _mine_cooldown.tick(delta)
    # ... repeat for every helper
```

This fights ADR 005's default-OFF rule: components that hold cooldowns but have no other per-frame work would have to turn `_physics_process` on just for the tick. HealthComponent, for instance, holds a respawn cooldown and otherwise has nothing to do each frame — it would flip back to per-frame tick just for the helper.

Multiplied across 10 sites, that's 10 extra `tick()` calls per physics frame, and a doctrine break for every component that previously qualified for OFF.

### Freeze-frame incompatibility (the carve-out)

**`Cooldown` is the wrong tool for freeze-frame / time-dip effects.** Two reasons:

1. `Engine.time_scale = 0` halts `_process` and `_physics_process`, so polling a timestamp from `_process` never runs during the freeze. The timestamp itself is correct (wall-clock keeps ticking), but the poll site is frozen.
2. Even if we worked around point 1 by polling from an `_unhandled_input` or a `SceneTreeTimer` callback, the ergonomics of "Cooldown plus a separate polling mechanism that bypasses `_process`" defeat the whole point of using the helper.

**DashComponent's freeze-frame uses raw `SceneTreeTimer`** with `process_always=true, ignore_time_scale=true`:

```gdscript
# From dash_component.gd
if dash_stats.freeze_frames > 0:
    var freeze_seconds: float = float(dash_stats.freeze_frames) / 60.0
    Engine.time_scale = 0.0
    get_tree().create_timer(freeze_seconds, true, false, true).timeout.connect(
        func() -> void:
            if is_instance_valid(self):
                Engine.time_scale = 1.0
    )
```

`SceneTreeTimer.timeout` is dispatched by the SceneTree's always-loop and fires regardless of `process_mode` or `Engine.time_scale`. ADR 013 documents this as the DashComponent exception.

**Research Delta #14** captured this: "freeze-frame CANNOT use the generic Cooldown helper." Documented in the helper's header comment AND in DashComponent's header so the reason is visible at both call sites.

### Ternary precedence bug fix (Research Delta #13)

The original Phase 1 `progress()` had:

```gdscript
# Phase 1 Step 9 — broken
func progress() -> float:
    return 1.0 - (_remaining / _duration if _duration > 0.0 else 0.0)
```

The ternary `_remaining / _duration if _duration > 0.0 else 0.0` groups as `(_remaining / _duration) if _duration > 0.0 else 0.0` — which crashes on `_duration == 0.0` because the division is evaluated before the ternary chooses its branch. Actually worse: in GDScript 2 the ternary binds tightly to `0.0`, so the expression becomes `_remaining / _duration if _duration > 0.0 else 0.0` = `1.0 - 0.0 = 1.0` when `_duration` is zero — returning "100% progress" for a zero-duration cooldown, which is wrong-semantically-but-doesn't-crash.

The timestamp-based rewrite sidesteps this entirely with an early return:

```gdscript
func progress() -> float:
    if _duration_msec <= 0:
        return 1.0
    var left: int = maxi(0, _ready_at_msec - Time.get_ticks_msec())
    return 1.0 - float(left) / float(_duration_msec)
```

Unit test regression coverage lives in [tests/unit/test_cooldown.gd](../../tests/unit/test_cooldown.gd).

## Consequences

**Positive:**
- **Zero per-frame cost.** Components hold cooldowns without needing a tick channel. Ten cooldown sites mean zero added per-frame work.
- **O(1) queries** for HUD progress bars. `MineCooldownDisplay` reads `progress()` directly.
- **Idempotent restart.** `_cooldown.start(X)` from any state resets the cooldown to X seconds from now.
- **Fixed the ternary bug** while we were rewriting it. Free win.
- **Call-site clarity.** `if _cooldown.is_ready(): ...` is obvious; `if _remaining <= 0.0: ...` was not.

**Negative:**
- **Wall-clock means it doesn't respect `Engine.time_scale`.** Freeze-frame needs a different tool (raw `SceneTreeTimer`). Documented in the helper header AND in DashComponent.
- **Drains during pause.** `Time.get_ticks_msec()` continues across `get_tree().paused = true`, so a respawn cooldown started mid-game would keep counting down during a pause menu. Currently not a problem because no game-level pause menu exists; if one lands, the owner must snapshot `remaining()` on pause and `start(remaining_snapshot)` on unpause.
- **Shadow warning on `start(duration)`.** The parameter `duration` shadows the `duration()` method. Pre-existing since Phase 1; trivial to rename (`start(secs)`) but churns every call site. **Phase 11 Step 48c renames it** as part of the cleanup pass.
- **Depends on `Time.get_ticks_msec()` not wrapping.** 32-bit ticks wrap at ~24 days of continuous uptime. Not a real-world concern for a game session, but documented here in case a future test harness does a crazy thing.

## Alternatives Considered

**Tick-based helper** (`_cooldown.tick(delta)` per `_physics_process`). Rejected because it forces every component holding a cooldown to enable its per-frame tick channel, which breaks ADR 005's default-OFF rule. Cost is 10× per-frame function calls that do nothing interesting.

**Pure `SceneTreeTimer.timeout` connections** (the pre-refactor pattern, just wrapped). Rejected because:
- Lambda allocation per call.
- No progress query.
- No idempotency.
- The wrapping helper would be ~5 lines and add no value.

**`Tween`-based countdown.** Considered. Tweens fire a callback on completion but have their own lifetime-management complexity (tween is a Node that needs to be orphaned or parented), and querying "time remaining" on a running tween is awkward. Too much overhead for a cooldown primitive.

**Godot's `Timer` Node.** Rejected for components that hold multiple cooldowns (HealthComponent has respawn + iframe, DashComponent has burst + cooldown + freeze + dip). Each Timer is a separate scene-tree node, which bloats the entity tree and requires explicit parenting. A `RefCounted` helper stays invisible.

**Typed-duration value class** (`var _cooldown: Cooldown = Cooldown.new(2.5)` where constructor takes the duration). Considered. Rejected because the "same helper, restarted many times with different durations" pattern (Cannon with per-cannon override, wave modifiers changing broadside cooldown) is natural with `start(duration)` and clunky with constructor-fixed values.

**Per-component private `_cooldown_*_msec: int` fields, no helper class.** Rejected. Helper class centralizes the bug-fix surface (Research Delta #13) and the pause-caveat documentation. Inlining the pattern 10 times means any future fix has 10 places to touch.
