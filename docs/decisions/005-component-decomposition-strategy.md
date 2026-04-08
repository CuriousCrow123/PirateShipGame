## ADR 005: Component Decomposition Strategy — Single-Responsibility Nodes, Signal-Up

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 006 (FSM)](006-flat-enum-fsm-over-hsm.md), [ADR 007 (bus discipline)](007-events-bus-discipline.md), [ADR 009 (resources)](009-resources-hot-reload-strategy.md), [ADR 013 (ship components)](013-ship-component-decomposition.md)

## Context

Pre-refactor, [scripts/ship.gd](../../scripts/ship.gd) was a 548-line god object that owned movement, dash, damage, iframes, lives, respawn, mine drops, broadside firing, hit feedback, camera shake, ghost trails, hull variants, a cheat toggle, and direct input reads — all in one class, with 22 member flags forming a state soup (`_is_dead`, `_input_locked`, `_dash_active`, `_iframes_left`, `_invincible`, …). `main.gd` had the same shape at 394 lines: wave management, spawning, stats hooks, and scene wiring all tangled together.

The brainstorm ([docs/brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md](../brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md)) evaluated three approaches: minimal cleanup (3–4 components only, no folder reorg), moderate refactor (~6 components + Events autoload), and maximalist tree (full component decomposition + feature folders + autoloads). The user explicitly selected the maximalist approach — "foundation laid once" over iterative cleanup.

Once we committed to decomposition, the open design questions were:

1. **What *is* a component?** A `Node` subclass, a `Resource`, a mixin class, a state-pattern state?
2. **How do components communicate?** Up to the entity root, sideways to siblings, or onto a global bus?
3. **How does each component know when to tick?** Per-frame by default, or signal-driven?
4. **How does an entity root wire its components together without the wiring code becoming the new god object?**

## Decision

### 1. Components are `Node` subclasses under an entity root

Each behavior cluster is a small `class_name FooComponent extends Node` that attaches to an entity's root `.tscn` as a direct child. The entity root (Ship, EnemyShip, …) is the only thing that knows the full component set; components never reach across to siblings.

**Exception**: components whose behavior depends on the entity's 2D transform chain MUST `extend Node2D`, not `Node`. Godot's `CanvasItem` transform chain only walks through `CanvasItem` ancestors — a plain-`Node` parent silently strands any `Area2D` / `Sprite2D` / etc. child at world origin `(0, 0)`. [HurtboxComponent](../../features/ship/components/hurtbox_component.gd) is the single current instance of this exception; the file header documents the reason inline. This was discovered as a post-Phase-10 hot-fix (see the parent plan's "Post-Phase 10 hot-fix: Hurtbox transform inheritance" section).

Scripts, not inheritance: we never `extends HealthComponent`. Shared behavior that two entity types need (HealthComponent for player AND enemies) is parameterized via `@export` fields or explicit `setup(...)` arguments, NOT subclassing. This keeps the component surface flat, inspectable in the scene dock, and free of the "whose parent defined this signal again?" problem.

### 2. Signal-up, not signal-sideways

**Components emit signals upward to the entity root. The entity root is the dispatcher.** A component never reaches across to a sibling component; it never reads another component's state. Example, from [HealthComponent](../../features/ship/components/health_component.gd):

```gdscript
signal health_changed(hp: int)
signal death_requested   # sent UP to Ship; Ship forwards to ShipFSM
```

Ship root connects `_health.death_requested → _fsm.enter_dead()`. HealthComponent doesn't know the FSM exists. This keeps each component a mini-module with a clean contract.

The global `Events` bus is reserved for **cross-entity** traffic (Ship → GameCamera, SpawnService → VfxListener, WaveDirector → HUD). ADR 007 documents the bus rules; the short version is "only entity roots and service nodes publish; components stay local."

### 3. Default-OFF process channels

Every component calls `set_physics_process(false)` and `set_process(false)` in `_ready()` unless it proves it needs ticking. Signal-driven by default. A grep across `features/ship/components/` on a correctly-refactored tree should find very few active `_process` / `_physics_process` bodies — typically just MovementComponent (thrust integration) and ShipFSM (iframe countdown). Example, from the [HurtboxComponent `_ready()`](../../features/ship/components/hurtbox_component.gd):

```gdscript
func _ready() -> void:
    set_physics_process(false)
    set_process(false)
    # ...
```

The win is both performance (fewer idle-component ticks) and clarity — "is this component active right now?" becomes answerable by looking at whether its process flag is set.

### 4. Entity root as dispatcher, not god object

Ship.gd's post-refactor shape is a thin orchestrator: `@onready` refs to its components, a `_ready()` that calls `setup(...)` and `connect(...)` on each, and signal-bridge methods that forward component signals to the FSM or the bus. Everything that used to be a flag on Ship is now owned by the component that touches it:

| Former ship.gd field            | Now owned by              |
|---------------------------------|---------------------------|
| `velocity`, `_thrust_input`     | MovementComponent         |
| `_is_dead`, `_input_locked`     | ShipFSM                   |
| `_iframes_left`, `_invincible`  | ShipFSM                   |
| `_dash_active`, `_dash_timer`   | DashComponent             |
| `_hp`, `_lives`, respawn timer  | HealthComponent           |
| `_mine_cooldown`                | MineDropComponent         |
| cannon/broadside bookkeeping    | Cannon + BroadsideComponent |
| flash tween, shake bridge       | HitFeedbackComponent      |
| camera reference, shake trauma  | (promoted to GameCamera)  |

ADR 013 documents each component individually.

### 5. Component template

Every component follows the same skeleton. Copy-paste starting point for new components:

```gdscript
class_name FooComponent
extends Node

## One-sentence "what this component owns" doc.

signal foo_changed(value: int)        # component-local signal UP to entity root

@export var stats: FooStats            # no preload() default — assigned in .tscn

var _foo: int = 0


func _ready() -> void:
    set_physics_process(false)          # prove you need it, or stay OFF
    set_process(false)
    assert(stats != null, "FooComponent: stats not assigned in inspector")
    # ... subscribe to entity-root or sibling wiring here
```

## Consequences

**Positive:**
- **Ship.gd dropped from 548 LOC to a thin orchestrator**; `main.gd` from 394 LOC to ~92 LOC. Both shapes are now "read in 5 minutes" files.
- **Testability**: each component can be unit-tested against its public surface in isolation (see ADR 009 and [tests/unit/test_health_component.gd](../../tests/unit/test_health_component.gd)).
- **Reuse**: HealthComponent and HurtboxComponent are shared across Ship and EnemyShip. Parameterization via primitives (Phase 8 retro line 356–368) or `@export respawnable: bool` avoids a parallel EnemyHealthComponent hierarchy.
- **Inspector visibility**: every component exposes its `@export` stats slot in the scene dock, so a designer can reassign `default_ship_stats.tres` without touching code.
- **Default-OFF**: per-frame cost of an idle entity with 10 components is ~zero. MovementComponent and ShipFSM are the only per-frame tickers on a normal player instance.

**Negative:**
- **More files**. ~10 component scripts under `features/ship/components/` plus stats Resources. IDE navigation replaces `ship.gd` grep. This was an explicit cost the brainstorm accepted.
- **Wiring pass in entity root**. Ship's `_ready()` contains 30+ lines of `setup(...)` and `.connect(...)` calls. This is visible code rather than hidden coupling, so we prefer it, but it's not free.
- **Signal-up indirection**. A reader tracing "how does dash lead to iframes?" must hop Component → Ship → FSM. The tradeoff buys decoupling; we accept it.
- **Transform-chain exception for Node2D**. The Node-only rule has one documented carve-out (HurtboxComponent) because of Godot's CanvasItem inheritance. New components must consider whether they're in the same boat before defaulting to `extends Node`.

## Alternatives Considered

**Subclass inheritance (`class EnemyHealthComponent extends HealthComponent`).** Rejected. Inheritance creates parallel hierarchies for every shared component (Health × Hurtbox × HitFeedback × Audio), and Godot's class-name registry does not handle deep trees well. Parameterization via `@export` or `setup()` args gives us the same code reuse with one file per role instead of N.

**Mixin via `Resource` composition.** Rejected. Resources would have to be `.duplicate()`d at runtime to avoid shared-state bugs (see ADR 009), and they don't get their own `_process` / `_physics_process` channels — the component model fits Godot's node-tree grain better.

**State pattern (one state-class per FSM state).** Rejected for the FSM itself (see ADR 006) and never seriously considered for components. States would fragment the decomposition across a second dimension (behavior × state) with no commensurate clarity win at our scale.

**Monolithic `Node2D` with helper `RefCounted` objects.** Rejected. Helpers can't participate in `_ready()`, can't receive `state_changed` subscriptions without a manual tick, and don't show up in the scene dock. The entire point of the refactor was to make structure visible.

**Keep `ship.gd` as-is, only extract Input/Dash/Movement.** Rejected as Approach A in the brainstorm. Kicks the cleanup can down the road without changing the shape that made it a god object in the first place.
