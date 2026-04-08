## ADR 008: GameState Autoload Scope — Methods-Only API, StatsTracker Merged In

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 007 (bus)](007-events-bus-discipline.md), [ADR 009 (resources)](009-resources-hot-reload-strategy.md)

## Context

Pre-refactor, there were no autoloads. Run-scoped state — current wave, kill/death counters, HP/lives snapshots for the HUD — lived on `main.gd` fields and was passed into subsystems via setup-injection. This had two problems:

1. **HUD widgets had to know their data source.** `hp_display.tscn` took a `setup(ship)` arg; `lives_display.tscn` took a different `setup(run_stats)` arg. Each HUD scene had its own injection pattern.
2. **Run lifecycle was implicit.** Starting a new run meant hand-resetting six fields across three call sites in `main.gd`. The "new run" concept didn't exist as a named operation.

The brainstorm called for a `GameState` autoload to own per-run state. The open questions:

1. **Field access or methods?** Should callers read `GameState.hp` directly or call `GameState.get_hp()`?
2. **How does the autoload know when state changes?** Subscribe to the bus, or accept direct method calls?
3. **What about `StatsTracker`?** The brainstorm listed a separate `StatsTracker` autoload that would subscribe to bus signals and update a `RunStats` instance. Is that a separate autoload, or folded in?
4. **Where does max-HP / max-lives come from?** Hard-coded, constructor arg, or loaded from a Resource?

## Decision

### 1. Methods-only API, no direct field reads

**Callers use methods; fields are `_`-prefixed and private.** From [autoload/game_state.gd](../../autoload/game_state.gd):

```gdscript
var _ship_stats: ShipStats = null
var _stats: RunStats = null
var _current_wave: int = 0
var _hp: int = 0
var _lives: int = 0

# Mutators — call these instead of writing fields
func record_damage(amount: int) -> void: ...
func record_kill() -> void: ...
func record_death() -> void: ...
func record_wave_cleared(index: int, duration: float) -> void: ...

# Read-only getters
func get_stats() -> RunStats: ...
func get_current_wave() -> int: ...
func get_hp() -> int: ...
func get_max_hp() -> int: ...
```

**Rationale:** methods are a contract. Callers can't accidentally mutate `_stats.kills` from outside; the getter returns the instance but the mutator path is the only way to bump it. This is weaker than immutability but stronger than bare fields, and it documents the legal operations in one place.

### 2. Direct method calls, not bus subscriptions

**GameState does NOT subscribe to the bus.** Publishers call `GameState.record_kill()` directly when they want state to change.

This is a deliberate departure from the brainstorm's original "StatsTracker subscribes to bus, updates RunStats via `stat_recorded`" design. Phase 7 shipped StatsTracker with shared-by-reference semantics (publishers pass `RunStats` into services via `setup()`, services mutate fields on the shared instance) and the Phase 7 retro (parent plan line 494–509) documents the reasoning: bus subscription would require a publisher in every call site anyway, plus `shot_fired_recorded` / `shot_hit_recorded` signals that would exist *only* for the bus hop.

The Phase 11 shape flipped one layer further: A4 scope-cut fused `StatsTracker` into `GameState`. The autoload now owns `RunStats` directly, and publishers call `GameState.record_*` methods. **No `StatsTracker` autoload exists.** The `stats_tracker.gd` Node in `systems/` is a service node (cross-feature helper) that wraps the method calls for WaveDirector / SpawnService convenience — see `systems/stats_tracker.gd` for the wrapper shape.

### 3. `StatsTracker` fused in (A4 scope cut)

A4 from Appendix A of the parent plan fused `StatsTracker` into `GameState`. The refactor's argument: if GameState already owns `RunStats` and exposes the mutator API, a separate autoload only exists to avoid putting more code in `GameState`. Separation-for-its-own-sake.

Trade-off accepted: `game_state.gd` is slightly longer (~107 lines vs ~60 without stats). Still readable in one scroll. Net autoload count: **4** (`Events`, `GameState`, `AudioManager`, `KeybindsManager`), not 5.

### 4. ShipStats as source of truth for max-HP / max-lives

`GameState._ready()` loads [`features/ship/stats/default_ship_stats.tres`](../../features/ship/stats/default_ship_stats.tres) and reads `max_health` / `max_lives` from it. **Same `.tres` the Ship instance is wired to in `main.tscn`.** Godot's Resource loader shares Resource instances in-memory for the same path, so a designer edit to the ShipStats inspector slot propagates to **both** consumers.

```gdscript
const _SHIP_STATS_PATH: StringName = &"res://features/ship/stats/default_ship_stats.tres"

func _ready() -> void:
    _ship_stats = load(_SHIP_STATS_PATH) as ShipStats
    assert(_ship_stats != null, "GameState: failed to load ShipStats at " + _SHIP_STATS_PATH)
    start_new_run()
```

Note: `load()` is allowed from autoload `_ready()`. File-scope `preload()` of **other autoloads** is banned (see ADR 007) but loading a Resource from disk is fine — Resources are not autoloads.

### 5. Run lifecycle is a named operation

`start_new_run()` is the one method that resets everything: a fresh `RunStats.new()`, `_current_wave = 0`, `_hp = max_health`, `_lives = max_lives`. `main.gd` calls it on game restart. HP refill on respawn is a separate method (`record_respawn()`) so the HUD can show `0/4` in the gap between death and respawn cooldown.

### 6. Autoload init order

**Registered SECOND**, after Events. The order is `Events → GameState → AudioManager → KeybindsManager`. GameState needs Events to exist when listeners in `_ready()` want to subscribe; it does not subscribe itself, but this ordering future-proofs the rule.

**No file-scope cross-autoload references.** `game_state.gd` does not `preload()` `events.gd` or `audio_manager.gd`. If a future method needs to touch another autoload, the reference happens inside `_ready()` or later.

## Consequences

**Positive:**
- **HUD widgets have one data source.** `hp_display.tscn` calls `GameState.get_hp()` in its own `_process()` or subscribes to `Events.player_damaged` and re-reads. No per-widget setup-injection ceremony.
- **Run restart is a one-liner** — `GameState.start_new_run()`. `main.gd` doesn't need to know which fields to reset.
- **Max-HP designer-tunable.** Editing `default_ship_stats.tres` in the inspector updates both the player Ship instance and GameState without code changes.
- **Type-safe mutator surface.** `record_damage(amount: int)` is impossible to misspell into a silent no-op (unlike a generic `Events.stat_recorded("damage", amount)`).
- **One autoload covers stats + persistent run state.** No fragmentation into GameState + StatsTracker + ScoreManager.

**Negative:**
- **Direct method calls to an autoload are tighter coupling than bus signals.** A test for WaveDirector can't be written without GameState existing (WaveDirector calls `GameState.record_wave_cleared(...)` directly). Mitigation: GameState has no external dependencies of its own, so unit tests can use the real autoload.
- **`_stats` can be null during `_ready()` timing windows.** Each mutator guards with `if _stats == null: return`. This is belt-and-suspenders; `start_new_run()` initializes `_stats` at autoload boot, so in normal play the guard never fires.
- **Hot-reload caveat.** GameState caches `_ship_stats.max_health` into `_hp` and `_ship_stats.max_lives` into `_lives` at `start_new_run()` time. If a designer edits those values mid-run via the inspector, the autoload's `_hp` / `_lives` don't refresh (same limitation that HealthComponent and BroadsideComponent have — see Phase 8 retro line 369–377). Documented in ADR 009.
- **Not bus-subscribed** means we can't ever trigger a GameState mutation from a system that doesn't already hold a reference to the autoload. No realistic scenario requires this today.

## Alternatives Considered

**Separate `StatsTracker` autoload that subscribes to the bus.** Brainstorm's original design. Rejected as A4 because it required publishers in every call site anyway, plus bus signals for `shot_fired` / `shot_hit` that exist purely for the hop. Fusing reduced autoload count and eliminated a layer of indirection.

**Direct field reads instead of methods.** Rejected. Bare fields (`GameState.hp`) invite accidental writes from HUD widgets that "just want to update the display". Private fields + getters is a weak guarantee but costs nothing to enforce.

**`RunStats` on a per-scene basis, not in an autoload.** Rejected. Stats need to survive scene transitions (game over → restart) and be reachable from any HUD scene without dependency injection.

**Hard-coded max-HP / max-lives constants in `game_state.gd`.** Rejected. The ship has an authoritative ShipStats Resource; duplicating the values in the autoload would create a drift hazard. Loading the Resource at `_ready()` is cheap and single-source.

**Preload ShipStats at file scope** (`const SHIP_STATS = preload(...)` at the top of `game_state.gd`). Rejected. File-scope preloads of Resources in an autoload are fine from an autoload-order perspective (Resources aren't autoloads), but the `load()`-in-`_ready()` pattern is uniform with the autoload ordering rule. Either works; we picked `load()` for consistency.
