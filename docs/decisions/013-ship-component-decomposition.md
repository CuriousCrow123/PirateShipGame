## ADR 013: Ship Component Decomposition — Per-Component Rationale

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 005 (decomposition strategy)](005-component-decomposition-strategy.md), [ADR 006 (FSM)](006-flat-enum-fsm-over-hsm.md), [ADR 007 (bus)](007-events-bus-discipline.md), [ADR 010 (folder structure)](010-feature-folder-structure.md)

## Context

ADR 005 established the component-decomposition strategy in the abstract: Node subclasses, signal-up, default-OFF ticks, @export Resource stats, entity root as dispatcher. This ADR is the **concrete mapping** — the per-component rationale for each of the 9 ship components, plus the fusion decisions (A1, A2, A3) that collapsed three components into their sibling hosts.

Per Appendix A of the parent plan, the A7 scope-cut consolidated 9 per-component ADRs into this single document: every component that shares the same underlying pattern ("single-responsibility Node, signal-up, reads @export stats") doesn't need its own ADR. Only the pattern-breakers and the fusion hosts get prose here; the rest are cataloged with short sub-sections.

Files live in [features/ship/components/](../../features/ship/components/). EnemyShip reuses HealthComponent, HurtboxComponent, BroadsideComponent, Cannon, HitFeedbackComponent, and AudioEmitterComponent from this same folder — see ADR 010 for the "components live with their host entity, not by class role" rule.

## Decision

### HealthComponent

**Owns:** HP, lives, respawn cooldown, damage gate.
**File:** [health_component.gd](../../features/ship/components/health_component.gd).

**Public surface:**
- `setup(max_health: int, max_lives: int, respawn_delay: float, fsm: ShipFSM)` — Phase 8 Step 39 switched from a `ShipStats` Resource arg to plain primitives so EnemyShip can reuse the component without a parallel `EnemyStats` Resource (EnemyArchetype provides `hp` directly).
- `apply_damage(amount: int = 1) -> bool` — the single damage entry point. Returns true if the hit landed. Queries `_fsm.is_vulnerable()` for the gate.
- `reset_for_respawn()` — HP refill + FSM respawn transition.
- Signals: `health_changed(current, maximum)`, `lives_changed(current, maximum)`, `died`, `respawn_ready`, `game_over`.

**Parameterization**: `@export var respawnable: bool = true` — player ships respawn until lives run out; enemies set this false so the non-respawnable branch in `_enter_death()` skips the game-over emit entirely. Without this export, enemies dying would trip the player game-over path.

**Default-OFF exception**: `_process` is enabled transiently during the respawn cooldown window so the wall-clock `Cooldown` can be polled for the `respawn_ready` emit. The instant the signal fires, `set_process(false)` runs. This keeps the doctrine honest: HealthComponent is OFF by default, on only during the ~2.5s respawn window (Phase 6 Step 34a).

**A1 fusion — CheatComponent**: The brainstorm's CheatComponent is gone. The Shift+5 invincibility cheat was fused into HealthComponent at Appendix A, then moved further into ShipFSM at Phase 5 Step 33 when the iframe state itself migrated (Phase 5 retro line 825–831). The cheat handler's current home is `ship_fsm.gd._unhandled_input`, guarded by `OS.is_debug_build()`.

### MovementComponent

**Owns:** Thrust, turn, brake, friction, ram-pushback.
**File:** [movement_component.gd](../../features/ship/components/movement_component.gd).

**Default-OFF exception**: `_physics_process` stays **on** because motion integration has to run every tick. Ship root flips two flags (`_enabled` false during DASHING, `_locked` true during DEAD) via `connect_fsm(fsm)` + `_on_fsm_state_changed`. The component reads its own flags; no branch lives on Ship root.

**Hot-reload target**: `MovementComponent` reads `_stats.thrust`, `_stats.linear_drag`, `_stats.turn_speed`, and `_stats.brake_decel` **per physics frame** inside `_physics_process`. Editing `default_ship_stats.tres` in the inspector mid-run propagates live. This is one of the two live-hot-reload paths (WaterEffectsManager is the other — see ADR 009 §6).

**Ram signal**: emits `rammed_enemy(enemy, normal)`. Ship root listens and forwards to HealthComponent's `apply_damage`, so the iframe gating stays centralized.

### HurtboxComponent

**Owns:** Area2D for incoming-damage detection.
**File:** [hurtbox_component.gd](../../features/ship/components/hurtbox_component.gd).

**`extends Node2D`, NOT `extends Node` — the documented exception to ADR 005.** Godot's 2D transform chain only walks through CanvasItem ancestors. A plain-`Node` parent strands the child Area2D at world origin `(0, 0)`. Root-caused in the post-Phase-10 hot-fix (parent plan, "Post-Phase 10 hot-fix: Hurtbox transform inheritance"). Component-header comment documents the reason in-line.

**Signal**: `hit_taken(source: Node)`. Subscribes to `ShipFSM.state_changed` via `connect_fsm(fsm)` and auto-disables the Area2D when the entity enters DEAD (`set_active(false)` uses `set_deferred` on `monitoring`/`monitorable` to avoid "can't change state during query flush" errors when toggling from a contact callback).

**`resolve_entity(area)` helper**: static. `area.area_entered` reports the colliding Area2D, not its owner. `_resolve_entity(area)` walks `area.owner` to resolve the entity root. Documented in Research Delta #23 style notes.

### DashComponent (fused with GhostTrailComponent — A2)

**Owns:** Dash impulse, feel-mode dispatch, dash cooldown, dash fire effect driver, ghost trail spawning, freeze-frame / time-dip `Engine.time_scale` writes.
**File:** [dash_component.gd](../../features/ship/components/dash_component.gd).

**A2 fusion — GhostTrailComponent**: ghosts only exist during a dash burst. A separate component would have the same lifetime as DashComponent anyway, so fusion eliminated a useless intermediate scene. `_spawn_ghost()` + `_ghost_container` + `_ghost_additive_material` all live on DashComponent.

**Documented timer exception**: freeze-frame and time-dip use raw `get_tree().create_timer(seconds, process_always=true, ignore_time_scale=true)` lambdas, NOT the generic `Cooldown` helper. The reason (Phase 6 Step 34b/c + ADR 014):

- `Cooldown` is wall-clock (`Time.get_ticks_msec()`), which ticks during freeze-frame. So far so good.
- But `Cooldown` is polled from `_process`, and `_process` halts while `Engine.time_scale = 0`. A polled Cooldown would never fire during a freeze.
- `SceneTreeTimer.timeout` is dispatched by the SceneTree's always-loop and fires regardless of `process_mode`. So the timer's lambda gets called even during `time_scale = 0`.
- Setting `PROCESS_MODE_ALWAYS` on DashComponent would instead make the component's own `_physics_process` tick during freeze, which breaks freeze semantics.

The dash gameplay cooldown (`dash_stats.cooldown`) DOES use the `Cooldown` helper — that's a normal gameplay cooldown polled from `try_start()`, which is input-driven and only runs when a dash is requested (no per-frame poll).

**Defensive `_exit_tree()`**: restores `Engine.time_scale = 1.0` if a freeze/dip lambda failed mid-burst. Without this, a crashing component during a freeze permanently strands the engine in slowed time (Research Delta #9).

### Cannon

**Owns:** A single cannon's muzzle point + per-cannon fire cooldown.
**File:** [cannon.gd](../../features/ship/components/cannon.gd).

**Design note**: bare `Cannon` class name, not `CannonComponent`. A cannon is a cannon, not a "cannon-component". The naming convention in ADR 005 is "components that attach to an entity root get the `*Component` suffix" — Cannon attaches to a `Marker2D` slot under a CannonSlots parent, then the slot attaches to the ship. One extra indirection, so the `*Component` suffix doesn't apply as cleanly.

**Public surface:**
- `try_fire() -> bool` — returns true and emits `fired(pos, dir)` if the per-cannon cooldown is ready.
- `@export var weapon: WeaponConfig` — Resource slot for projectile speed / damage / explosion kind.
- `@export var fire_cooldown: float = 0.0` — per-cannon cadence; defaults to 0 (no-op, Broadside drives all firing). Setting >0 would let individual cannons fire at different rates.

**Phase 8 note**: the legacy `fire() -> Dictionary` helper is gone. EnemyShip drives firing through BroadsideComponent just like the player.

### BroadsideComponent

**Owns:** Port/starboard cannon groups + per-side broadside cooldown.
**File:** [broadside_component.gd](../../features/ship/components/broadside_component.gd).

**Public surface:**
- `setup(cannon_slots: Node2D, broadside_cooldown: float)` — Phase 8 switched to primitive `float` instead of a Resource ref so EnemyShip can pass `archetype.broadside_cooldown` directly.
- `fire_port() -> bool` / `fire_starboard() -> bool` — salvo fires if the side's Cooldown is ready.
- Signal: `cannon_fired(pos, dir)` — aggregates per-cannon fires into a single upward stream.

**Wave modifiers**: `@export var fire_rate_mult: float = 1.0` is set by WaveDirector's wave modifier application. `cooldown / fire_rate_mult` inverts the polarity (a wave modifier of 0.5 = "twice as fast" becomes fire_rate_mult = 2.0). Phase 8 retro line 432–439 documents the polarity flip.

### MineDropComponent

**Owns:** Mine drop cooldown + drop entry point + cooldown progress publisher.
**File:** [mine_drop_component.gd](../../features/ship/components/mine_drop_component.gd).

**Public surface:**
- `try_drop() -> bool` — drops a mine behind the stern (`_ship.transform.y * STERN_OFFSET`).
- `get_cooldown_progress() -> float` — 0.0 just-dropped, 1.0 ready.
- Signals: `mine_dropped(pos)`, `mine_cooldown_changed(progress)`.

**Default-OFF exception**: `_physics_process` is ON because the component publishes `mine_cooldown_changed` for the HUD. The check is cheap (one float compare), so ticking every frame doesn't justify the complexity of a push model. The HUD's `MineCooldownDisplay` subscribes directly, not via the bus (ADR 007 "within-scene signals stay local").

### HitFeedbackComponent

**Owns:** White-flash on hit, per-sprite hull/sail shake, iframe blink envelope, outgoing screen_shake_requested bus publish.
**File:** [hit_feedback_component.gd](../../features/ship/components/hit_feedback_component.gd).

**ADR 007 exception**: HitFeedbackComponent publishes `Events.screen_shake_requested` directly. **This is one of the two sanctioned component-publishes-bus exceptions** (AudioEmitterComponent is the other). The reason: screen shake is terminal output — no local subscriber consumes it, so routing through Ship root would be a pointless forwarder.

**Parameterization**:
- `@export var shake_on_hit: bool = true` — player ships shake the camera on hit; enemies don't (the player camera shouldn't shake when an enemy gets hit).
- `@export var hit_trauma: float = 0.85` — the trauma value pushed into the shake request.

**Blink envelope**: subscribes (via Ship root wiring) to `ShipFSM.iframes_started` and `iframes_ended`. Phase 5 Step 33 moved these signals from HealthComponent to ShipFSM; HitFeedbackComponent no longer cares where they come from, just that it listens.

### AudioEmitterComponent

**Owns:** Local sound-event publish via `Events.sound_requested(sound_id, pos)`.
**File:** [audio_emitter_component.gd](../../features/ship/components/audio_emitter_component.gd).

**ADR 007 exception**: the second sanctioned component-publishes-bus exception. Same reasoning as HitFeedbackComponent — audio is terminal output.

**Design**:
- `@export var sound_bank: Dictionary[StringName, StringName]` — maps local event id (e.g., `&"cannon_fire"`) to global sound id (what AudioManager looks up in SoundConfig). Player and enemy ships can instance with different banks via inspector overrides.
- `play(local_event)` — looks up the local id, emits to the bus with the entity's global position.
- `play_global(sound_id, at)` — passthrough for callers that already know the global id.

**Phase 4 Step 32 scaffolding**: shipped as a no-op since AudioManager was (at the time) a stub. When the SoundConfig Resource gets real AudioStream clips wired in, this component fires them without code changes.

### PlayerInputComponent

**Owns:** Keyboard/gamepad input reads for the player ship.
**File:** [player_input.gd](../../features/ship/components/player_input.gd).

See [ADR 012](012-input-and-gamepad-architecture.md) for the full treatment — this component is the consumer side of the KeybindsManager autoload + InputMap remap layer.

**Class name vs file name**: `class_name PlayerInputComponent` but the file is `player_input.gd`. The `*Component` suffix is on the class; the file name stays unchanged for git-history continuity. Research Delta #22.

### A3 Fusion — HullVariantComponent

**Does not exist as a component.** The pre-refactor `_apply_hull_variant` was a 2-line sprite swap on Ship root's hull Sprite2D. Appendix A.3 rejected the proposed HullVariantComponent as an over-decomposition: "2-line sprite swap doesn't justify a component."

The logic lives as a private method on Ship root. If hull variants ever grow to include sail swaps, particle changes, and audio variations, a real HullVariantComponent becomes justified and this ADR should be revised.

## Consequences

**Positive:**
- **Ship.gd is a thin orchestrator**, ~100 LOC of wiring + dispatch. Every question of the form "what owns X?" routes to one component file.
- **Enemy reuse is free.** EnemyShip instantiates the same Health/Hurtbox/Broadside/Cannon/HitFeedback/AudioEmitter components with enemy-shaped parameters. No parallel `EnemyHealthComponent` hierarchy.
- **Testability.** Each component has a surface that can be unit-tested in isolation (see [tests/unit/test_health_component.gd](../../tests/unit/test_health_component.gd)).
- **Parameterization over inheritance works.** `respawnable: bool` for HealthComponent, `shake_on_hit: bool` for HitFeedbackComponent, `sound_bank: Dictionary` for AudioEmitterComponent. No subclass chain.
- **Default-OFF ticks mean idle components cost ~zero.** Only MovementComponent, ShipFSM (iframe countdown), MineDropComponent (HUD publish), and DashComponent (only during a burst) tick per physics frame.
- **Exceptions are narrow and documented.** Three of them — HurtboxComponent extending Node2D (ADR 005), HitFeedback/AudioEmitter direct bus publish (ADR 007), DashComponent freeze-frame timer (ADR 014). Each has its reason.

**Negative:**
- **Wiring in Ship.gd is long.** ~30 lines of `setup(...)` + `.connect()` calls. Visible coupling; better than hidden but not free.
- **Component fusion (A1/A2/A3)** means some of the pre-refactor "everything is its own component" aesthetic is gone. A reader looking for CheatComponent finds it in ShipFSM's `_unhandled_input`; a reader looking for GhostTrailComponent finds `_spawn_ghost` in DashComponent. Documented here so the search is short.
- **The `Cannon` naming break** — bare `Cannon`, not `CannonComponent` — is a one-off exception to the naming rule. New entity subcomponents should use the `*Component` suffix; `Cannon` is grandfathered because a cannon is a cannon.
- **`respawnable: bool` on HealthComponent and `shake_on_hit: bool` on HitFeedbackComponent** are small config bleeds across entity types. If the flag count grows past 2–3 per component, split into subclasses or data-resource variants.
- **HitFeedbackComponent and AudioEmitterComponent publishing to the bus** weakens the ADR 007 rule. The weakening is explicit and narrow, but it is a weakening.

## Alternatives Considered

**Separate component per state.** (`PlayerNormalState`, `PlayerDashingState`, etc. as components.) Rejected — see ADR 006.

**EnemyHealthComponent, EnemyHurtboxComponent, etc. as subclasses.** Rejected at Phase 8 in favor of primitive parameterization (`setup(max_health, max_lives, respawn_delay, fsm)`). Inheritance creates parallel file trees without reuse wins.

**EnemyStats as a parallel Resource mirroring ShipStats.** Rejected at Phase 8 (retro line 356–368). EnemyArchetype provides the fields directly; no second-level Resource hop.

**`@export var entity: Node2D` on AudioEmitterComponent instead of setup() injection.** Considered. Rejected because the entity ref is required and runtime-set, not inspector-set. Setup injection catches the null case at `setup()` time with a clear assertion.

**Keep CheatComponent, GhostTrailComponent, HullVariantComponent as separate files.** Rejected as A1/A2/A3. The components had exactly-overlapping lifetimes with their future host (HealthComponent, DashComponent, Ship root respectively), making the decomposition ceremony.

**Enemy ShipFSM.** Considered. EnemyShip has a 2-state AI (chase / circle) that doesn't need an FSM; `enemy_ai_movement.gd` handles the mode switch with a simple enum + conditional. If enemies grow a STUNNED state or multi-phase boss behavior, they get their own flat FSM sharing the player's pattern.
