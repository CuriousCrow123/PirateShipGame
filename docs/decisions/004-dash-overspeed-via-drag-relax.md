## ADR 004: Dash "Overspeed Cap" Implemented as Drag Relaxation

**Date:** 2026-04-07
**Status:** Accepted

## Context

The dash brainstorm ([docs/brainstorms/2026-04-07-ship-dash-brainstorm.md](../brainstorms/2026-04-07-ship-dash-brainstorm.md)) called for four selectable "feel modes" — locked-heading, steerable, velocity-aligned, and **overspeed-cap raise**. The phrasing for the fourth mode came from common platformer parlance: "lift the velocity cap during the dash so the burst lasts naturally as drag bleeds it off."

When implementing, this collided with a structural fact about the player ship: **there is no max-speed cap to lift.** [scripts/ship.gd](../../scripts/ship.gd) integrates motion as `velocity += transform.y * thrust * delta` with `velocity *= linear_drag` (default `0.97`) per physics frame. Terminal speed under continuous thrust is `thrust * delta / (1 - linear_drag)` ≈ 44 px/s — an emergent equilibrium of thrust and drag, not an explicit clamp.

Two implementation paths fell out of this:

1. **Introduce a `max_speed: float` export to the ship**, raise it on dash start, restore on dash end. Adds new state and a new code path (the `velocity = velocity.limit_length(max_speed)` clamp) that runs every physics frame whether dashing or not, just to support one feel mode that costs an active dash to use.
2. **Temporarily relax `linear_drag`** during the burst — multiply by something closer to `1.0` (default `0.995`) so the impulse decays slowly, giving the same "you go further than you should" feel without introducing a new clamp.

## Decision

We chose **path 2**: a `DashConfig.overspeed_drag: float = 0.995` export that the OVERSPEED_CAP feel mode uses in place of the ship's normal `linear_drag` for the duration of the burst. The relevant branch in [scripts/ship.gd `_physics_process`](../../scripts/ship.gd):

```gdscript
DashConfig.FeelMode.OVERSPEED_CAP:
    if not is_braking and Input.is_action_pressed("move_forward"):
        velocity += transform.y * thrust * delta
    velocity *= dash_config.overspeed_drag
    rotation += turn_input * turn_speed * delta
```

The other three modes use the ship's normal `linear_drag`. No new state, no new clamps, no additional per-frame code path outside the dash.

The export name **`overspeed_drag`** makes the mechanism explicit so a future contributor doesn't read "OVERSPEED_CAP" and wonder where the cap went.

## Consequences

**Positive:**
- Zero new code outside the dash branch — the existing momentum/drag model carries the feature for free.
- Tunable: shipping defaults `linear_drag = 0.97` and `overspeed_drag = 0.995`. The numerical difference is small per frame but compounds dramatically over a 0.35s burst (~21 physics frames).
- Composes cleanly with the impulse — initial impulse + relaxed drag = a long, slow tail.

**Negative:**
- The export name "OVERSPEED_CAP" is a slight misnomer relative to the mechanism. Documented in this ADR and in the export comment so the next reader isn't confused.
- If the codebase ever introduces an explicit `max_speed` cap for other reasons, this mode's behavior will need to be re-evaluated — the relaxed drag could push speeds above whatever cap the rest of the game expects.

## Alternatives Considered

**Add `max_speed: float` to the ship export and clamp every frame.** Rejected — adds an always-on `velocity.limit_length` call to support one feel mode, plus an extra DashConfig field for the during-dash cap. The clamp would also subtly change the existing momentum equilibrium.

**Apply an `overspeed_thrust_boost: float` instead of relaxing drag.** Rejected — visually similar but requires the player to hold `move_forward` for the boost to apply, breaking the "fire and let it ride" feel of the locked-heading and velocity-aligned modes the user might compare against.

**Skip mode 4 entirely and ship three feel modes.** Rejected — the user explicitly asked for all four modes ("Please implement each of these, selected by parameter"). The relaxed-drag interpretation is the simplest faithful implementation in this codebase.
