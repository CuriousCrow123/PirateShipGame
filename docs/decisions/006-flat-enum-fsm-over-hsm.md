## ADR 006: Flat-Enum FSM Over Hierarchical State Machine

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 005 (component decomposition)](005-component-decomposition-strategy.md), [ADR 013 (ship components)](013-ship-component-decomposition.md)

## Context

Pre-refactor, the player's discrete state was scattered across 5 Boolean flags on `ship.gd`: `_is_dead`, `_input_locked`, `_dash_active`, `_iframes_left`, `_invincible`. These flags were set and read from seven different code paths, and their combinations silently encoded states that no comment documented — e.g., `_is_dead=false, _iframes_left=0.5, _invincible=false` was "just got hit, recovering" while `_is_dead=false, _iframes_left=0.0, _invincible=true` was "cheat on."

Every refactor decision that touched damage, dash, or respawn started with "what does this flag combination mean?" and ended with "I hope I didn't miss a branch." The plan called for an explicit FSM.

Two obvious shapes for the FSM:

1. **Flat enum**: one `enum State { NORMAL, DASHING, IFRAME, DEAD }`, one `_state: int`, one `_set_state()` transition function.
2. **Hierarchical state machine (HSM)**: state classes with parent/child relationships (`Alive → Vulnerable → Normal`, `Alive → Vulnerable → Dashing`, `Alive → Invulnerable → Iframe`, `Dead`). Addons exist (e.g., `gdfsm`, `state-machine`) or we could hand-roll.

The player ship today has exactly **four discrete states**, and the pre-refactor audit found no realistic state-explosion pressure short of adding a fifth player mode entirely (e.g., stunned, grappled) — none of which are on the roadmap.

## Decision

We adopted a **flat enum FSM** implemented as [features/ship/ship_fsm.gd](../../features/ship/ship_fsm.gd), a 178-line `Node`:

```gdscript
class_name ShipFSM
extends Node

signal state_changed(old: int, new: int)
signal iframes_started
signal iframes_ended
signal invincibility_changed(active: bool)

enum State { NORMAL, DASHING, IFRAME, DEAD }

var _state: int = State.NORMAL
```

### Transition rules

- **Priority on transition**: `DEAD > DASHING > IFRAME > NORMAL`. The FSM never holds two states at once.
- **Iframes are a cross-cutting modifier**, not a state on their own axis. The iframe countdown (`_iframes_left: float`) keeps ticking while `DASHING` so dash-end can fall back into `IFRAME` if iframes remain.
- **`_set_state()` is private**. Components *request* transitions via public methods (`enter_dashing()`, `enter_dead()`, `respawn(iframe_duration)`), never by writing `_state` directly. The only `_set_state` callers are other methods inside `ship_fsm.gd`.

### Component wiring

Components don't share the FSM at construction time; instead, Ship root calls `connect_fsm(fsm)` on each subscriber after instantiating both. Subscribers store the ref and connect to `state_changed`. Example from [HurtboxComponent `connect_fsm()`](../../features/ship/components/hurtbox_component.gd):

```gdscript
func connect_fsm(fsm: ShipFSM) -> void:
    assert(fsm != null)
    _fsm = fsm
    _fsm.state_changed.connect(_on_fsm_state_changed)
    set_active(not _fsm.is_dead())
```

Chosen over threading the FSM ref through each component's existing `setup()` signature to limit blast radius — see Phase 5 retro line 804–812 in the parent plan.

### Initial emission

Ship's first `state_changed(NULL, NORMAL)` MUST fire via `call_deferred`. Components subscribe in their own `_ready()` callbacks, which run *before* Ship's `_ready()` finishes wiring. Without the deferral, the initial-state signal fires into a zero-subscriber bus and components miss their startup cue. Mirrors the pre-refactor [ship.gd `_emit_initial_status`](../../scripts/ship.gd) pattern.

### Cheat is part of the FSM

The Shift+5 invincibility cheat mutates FSM-owned state (`_invincible`), so its `_unhandled_input` handler lives in the FSM — not in HealthComponent or on Ship root. Toggling emits `Events.cheat_toggled(&"invincibility", active)` on the bus for the debug overlay banner (Phase 5 retro line 825–831).

## Consequences

**Positive:**
- **One source of truth for discrete state.** Every question about "is the ship dead? Is it vulnerable?" resolves to one method call on one object. The 22 flags are gone.
- **Transitions are logged.** `state_changed` is a typed signal; the debug overlay can list recent transitions for free.
- **Assertable.** Each public transition can bail early on illegal requests — e.g., `enter_dashing()` returns immediately if state is `DEAD`. See `ship_fsm.gd:105-109`.
- **Cheap to extend.** Adding a fifth state (e.g., STUNNED) is one enum entry, one `_set_state` branch, and one priority placement. No class hierarchy refactor.
- **Testable in isolation.** `tests/unit/test_ship_fsm.gd` (if it lands) can drive the FSM standalone and assert transition invariants.

**Negative:**
- **No substate sharing.** If we ever want "Alive" behavior that applies uniformly to NORMAL, DASHING, and IFRAME, it has to be expressed as a helper method (`is_alive()` returns `_state != State.DEAD`) rather than a parent-class override. At 4 states this is a trivial `in [a, b, c]` check; at 12 states it would get old.
- **Ship root still orchestrates wiring.** Ship's `_ready()` connects `_health.death_requested → _fsm.enter_dead`, etc. Not hidden, but visible — acceptable cost.
- **No HSM means no "natural" UNSTUCK-FROM-BUG escape valve.** If a transition logic bug strands the ship in `DEAD` forever, there's no hierarchical fallback; you need to ship a respawn.

## Alternatives Considered

**Hierarchical state machine via addon.** Rejected. Substate inheritance is overkill for 4 states and buys fragmentation — every state class is a separate file, every transition is a `get_parent()` hop. We'd pay syntactic cost on every transition to support a feature (substate sharing) we don't need.

**State-as-class hand-roll** (`class StateNormal extends PlayerState`, etc.). Rejected for the same substate-fragmentation reason, plus the bespoke glue code for "how do my state classes see each other?" adds a mini-framework to maintain.

**Keep the flag soup, rename the flags for clarity.** Rejected. Fundamentally doesn't solve the multi-flag combinatorial problem — better names still don't make `_dash_active && _iframes_left > 0` a legal combination.

**Enum but WITHOUT a dedicated Node.** Fold the state into HealthComponent as a private `_state` field. Rejected because DashComponent, HurtboxComponent, MovementComponent, PlayerInputComponent, and HitFeedbackComponent all need to subscribe. A dedicated `ShipFSM` Node is the natural publisher.

**Fork the FSM for EnemyShip.** Considered for Phase 8. Current enemies have a 2-state AI (chase / circle) that doesn't justify an FSM, so enemies don't get one yet. If they grow a `STUNNED` state or a multi-phase boss needs one, enemies will share this pattern (own flat enum, own `_set_state`, own public transition methods) rather than inherit from ShipFSM.
