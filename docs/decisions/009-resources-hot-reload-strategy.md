## ADR 009: Resources as Read-Only Templates — Hot-Reload Strategy

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 005 (components)](005-component-decomposition-strategy.md), [ADR 008 (GameState)](008-gamestate-autoload-scope.md), [ADR 013 (ship components)](013-ship-component-decomposition.md)

## Context

Pre-refactor, the codebase mixed two Resource patterns:

1. **Tuning templates** — `DashConfig.tres`, `ExplosionConfig.tres`. Read once at setup, never written. Works fine.
2. **Mutable shared Resources** — `trails.gd` reads an `@export var width_curve: Curve`, duplicates it to a per-instance copy, and writes to the copy at runtime. The `.duplicate()` step is critical: two trail instances referencing the same `.tres` file would mutate each other's curve points without it.

The second pattern caused two production incidents documented in [`docs/solutions/shared-resource-mutation.md`](../solutions/shared-resource-mutation.md) and [`docs/solutions/godot-shared-mesh-surface-material.md`](../solutions/godot-shared-mesh-surface-material.md): a shared `Curve` was mutated without duplication and a `ShaderMaterial` was mutated via `set_shader_parameter`, both causing cross-instance bleed.

The brainstorm's Resource pattern was "always `.duplicate()` before mutating." The deepen-plan review (Research Delta #5) flagged this as self-defeating: if every Resource gets duplicated on load, editor hot-reload stops working because the live scene holds per-instance copies that don't update when the `.tres` file is edited.

We needed a rule that:

- Enables inspector hot-reload of tuning values.
- Prevents cross-instance state bleed.
- Doesn't require developers to memorize which Resources are "the mutable ones".

## Decision

### 1. Resources are read-only templates

**Runtime state lives in Node `var`s, not on Resources.** Components cache primitive values from their Resource at setup time OR re-read per frame, but they never write to fields on an `@export var` Resource.

```gdscript
@export var stats: ShipStats

var _hp: int = 0       # runtime state — Node var
var _max_hp: int = 0   # cached from Resource, never written back


func _ready() -> void:
    assert(stats != null)
    _max_hp = stats.max_health    # read once
    _hp = _max_hp                 # mutable Node state
```

**Transitive**: `stats.weapon_config.damage = 5` is banned under the same rule as `stats.damage = 5`. Sub-resources are Resources too.

### 2. No `preload()` defaults on `@export var Resource` slots

```gdscript
# Banned:
@export var stats: ShipStats = preload("res://features/ship/stats/default_ship_stats.tres")

# Correct:
@export var stats: ShipStats   # assigned via .tscn ExtResource slot
```

Rationale: `preload()` defaults fight hot-reload (the `.tres` is baked into the script at parse time, not re-loaded on inspector change) AND hide dependencies. A component with a preloaded default looks fine when instantiated programmatically; a component WITHOUT a default fails loudly at the `assert(stats != null)` check in `_ready()`, which is what we want.

### 3. Embedded sub-resources in component `.tscn` files are banned

Materials, Curves, and Gradients live as `ExtResource` files in `features/<x>/resources/` (or wherever). A component `.tscn` that defines an inline `sub_resource type="ShaderMaterial" id="SubResource_xyz"` is a bug: the material lives uniquely inside that scene file, making it impossible to share, impossible to hot-reload, and impossible to reference by path.

Migration: every inline material in the pre-refactor `.tscn` files was extracted to `features/<feature>/<name>.tres` during Phase 6/7.

### 4. `set_shader_parameter` on a shared Material is a write

ShaderMaterial is a Resource. Calling `set_shader_parameter` on a `@export var mat: ShaderMaterial` mutates the shared instance the same way writing `mat.albedo = Color.RED` would. Two options per call site:

- **Intentionally shared**: document inline that the write is globally intended. Example: water DisplacementMap is wired once from `main.gd` and feeds every water shader; there's one displacement texture in the game, so writing it once is correct.
- **Per-instance**: `.duplicate()` the material in `_ready()` and write to the copy. Example: HitFeedbackComponent's flash material duplicates per-instance so two ships flashing simultaneously don't crosstalk.

Phase 6 Step 34k ran the audit across all 6 production `set_shader_parameter` call sites and classified each.

### 5. Every `@export var foo: <Type>` has a matching `assert(foo != null)` in `_ready()`

Without the assertion, a missing inspector slot silently produces null-deref crashes deep in `_physics_process`. The assertion turns the failure into a one-line, component-local error message:

```gdscript
assert(stats != null, "FooComponent: stats not assigned in inspector")
```

### 6. Hot-reload granularity

**Designer edits to tuning values propagate live IF the component re-reads per frame.**

Components that re-read on demand:
- `MovementComponent` — reads `stats.thrust`, `stats.linear_drag` inside `_physics_process`. Editing `default_ship_stats.tres` mid-run updates ship speed next physics tick.
- `PlayerInputComponent` — reads input-lock flags per frame.
- `WaterEffectsManager` — reads `WaterTuning.tres` per frame for wake spacing / speed cap.

Components that cache values at setup time:
- `HealthComponent` — caches `max_health`, `max_lives`, `respawn_delay`. Mid-run edits do NOT propagate (Phase 8 retro line 369–377 in parent plan).
- `BroadsideComponent` — caches `broadside_cooldown` at setup.

**This is a documented limitation, not a bug.** Per-frame re-reads on HP/lives fields would make "take damage" a three-step dance (read max, compute new value, write runtime var) with no gameplay benefit. The cost of mid-run hot-reload for these fields is a restart after editing the `.tres`.

If specific cached fields ever need live-reload, the upgrade path is a `stats.changed` signal subscription (`Resource.changed` fires when the inspector edits a field) — not a blanket re-read.

### 7. Legacy grandfather clause — `trails.gd`

[`features/water/trails.gd`](../../features/water/trails.gd) predates this doctrine and still uses `.duplicate()` on `width_curve` because the pre-refactor code actively mutates it. The grandfather clause says: **legacy code that mutates a Resource must continue to `.duplicate()` first.** New code must not mutate, so it never needs to duplicate.

This is the *only* surviving instance of the old `.duplicate()` pattern in the codebase as of Phase 10. When `trails.gd` gets its next behavioral change, the mutation should be refactored out — but "refactor trails.gd" is not a Phase 11 task.

### 8. WaveSet shared-reference test

`WaveSet.tres` holds an `Array[WaveConfig]`, and two WaveSets pointing to the same `wave_03.tres` get the *same* in-memory instance. `WaveDirector` must not mutate fields on the loaded `WaveConfig` — runtime state (`enemies_remaining`, wave timer, etc.) lives in WaveDirector Node vars, not on the Resource.

[tests/unit/test_wave_set_sharing.gd](../../tests/unit/test_wave_set_sharing.gd) asserts this executably: load a WaveSet, instantiate two WaveDirectors, verify mutating one does not affect the other.

## Consequences

**Positive:**
- **Inspector hot-reload works** for every field that the consuming component re-reads per frame. Movement, input, and water tuning all hot-reload live.
- **No duplicate-on-load ceremony.** Components set up faster (one less allocation per component per spawn).
- **Cross-instance bleed is structurally prevented.** If writes to Resource fields don't happen, shared-reference bugs can't happen.
- **Component code is simpler.** The pattern is: read Resource fields into Node vars, mutate Node vars. No conditional `if _stats_owned: ... else: _stats = _stats.duplicate()` dance.
- **Audit is a grep.** `Grep: @export var \w+: \w+` and check each hit has an assert. `Grep: stats\.\w+ = ` finds policy violations.

**Negative:**
- **Hot-reload is partial.** Cached values (HealthComponent's max_hp, BroadsideComponent's cooldown) don't live-update. Designers need to know which fields hot-reload and which don't.
- **`preload()` default is forbidden.** Programmatic instantiation (tests, editor tools) must manually assign the Resource: `comp.stats = load("res://…")`. This is more verbose than relying on a default.
- **`set_shader_parameter` audit is ongoing maintenance.** Adding a new call site means classifying it (shared or per-instance) at code-review time.
- **Legacy `trails.gd` is an exception** that future readers will have to understand. The grandfather clause is documented both here and in the `trails.gd` header.

## Alternatives Considered

**`.duplicate()`-on-load for every Resource.** The brainstorm's original design. Rejected because it breaks hot-reload: per-instance copies don't see inspector edits. Also doubles every component's setup-time allocations.

**Mutable Resources with manual subscription to `Resource.changed`.** Components would write to the Resource *and* listen for external changes. Rejected because the subscription burden plus the shared-state coordination creates exactly the cross-instance bleed this ADR prevents.

**Split into `FooStats` (read-only) and `FooState` (mutable Resource).** Considered. Rejected because `FooState` as a Resource has no advantage over a plain Node var; the only Resource benefits (inspector, .tres persistence) are wrong for runtime state.

**Per-scene Resource instances baked into each `.tscn`.** I.e., every Ship has its own inline ShipStats sub-resource. Rejected because it eliminates the shared-source-of-truth benefit (one `.tres` file, many consumers) and makes balance changes require editing every Ship-instancing scene.

**Ship hot-reload of all cached fields via `Resource.changed` subscriptions.** Rejected for Phase 11 as unnecessary scope. The upgrade path is documented here; a future need would add a targeted subscription, not a blanket re-read.
