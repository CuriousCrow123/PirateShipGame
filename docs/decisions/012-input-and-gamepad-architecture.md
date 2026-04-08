## ADR 012: Input and Gamepad Architecture — PlayerInputComponent + KeybindsManager

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 005 (components)](005-component-decomposition-strategy.md), [ADR 006 (FSM)](006-flat-enum-fsm-over-hsm.md)

## Context

Pre-refactor, input reads lived directly inside `ship.gd`'s `_physics_process`:

```gdscript
# scripts/ship.gd:127-172 (pre-refactor)
if Input.is_action_pressed("move_forward"):
    velocity += transform.y * thrust * delta
if Input.is_action_pressed("dash"):
    _start_dash()
```

Keyboard bindings were hard-coded in [project.godot:26-83](../../project.godot#L26-L83). No remap support. No gamepad detection. No way for the FSM to lock input during DEAD state without threading a boolean flag through every Input call.

The brainstorm scoped in:

1. **Extract input reading into a component** (ADR 005 alignment — no direct `Input.*` calls in Ship).
2. **InputMap remap support** (designer-facing rebind menu, eventually).
3. **Gamepad layer** — detect plugged gamepads, swap action bindings accordingly.

Open questions during Phase 3 execution:

1. **One component or two?** One `PlayerInputComponent` that handles keyboard + gamepad, or separate components per device?
2. **Does remap require its own autoload?** Or can the component own the remap API?
3. **Where does the rebind menu UI live?** (Phase 3 scope vs post-Phase-11.)
4. **How does the FSM lock input during DEAD?** (Polling vs subscription.)

## Decision

### 1. PlayerInputComponent as a Node component

A [features/ship/components/player_input.gd](../../features/ship/components/player_input.gd) (`class_name PlayerInputComponent`) hosts all input reads on the player ship. Ship root no longer touches `Input.*`. The component exposes typed signals or polled getters, depending on the pattern the consumer prefers:

```gdscript
# Polled (MovementComponent reads this each physics frame):
func get_thrust_input() -> float: ...
func get_turn_input() -> float: ...

# Signal-driven (DashComponent subscribes):
signal dash_requested
signal mine_drop_requested
```

### 2. Naming — `PlayerInputComponent`, not `PlayerInput`

Research Delta #22: the file is named `player_input.gd` but the class name is `PlayerInputComponent` to match the `*Component` suffix rule locked in Phase 4. The file name stays as `player_input.gd` for git-history continuity — renaming the file would churn every consumer's ext_resource path without a commensurate clarity win. The `class_name` is what callers see.

### 3. FSM-gated input

PlayerInputComponent subscribes to ShipFSM via `connect_fsm(fsm)` (the same pattern HurtboxComponent uses). When the FSM enters `DEAD`, the component gates all input reads:

```gdscript
func get_thrust_input() -> float:
    if _fsm != null and _fsm.is_input_locked():
        return 0.0
    return Input.get_action_strength("move_forward")
```

The "input locked" concept is single-sourced in the FSM (`is_input_locked()` returns `_state == State.DEAD`), so future state additions (e.g., a STUNNED state) only need to extend the FSM predicate.

### 4. KeybindsManager as a fourth autoload

Registered fourth in the autoload order (`Events → GameState → AudioManager → KeybindsManager`). Owns:

- The `REMAPPABLE_ACTIONS` constant list.
- `rebind_action(action: StringName, event: InputEvent)` mutator that updates `InputMap` and persists to `keybinds.cfg`.
- `save()` / `load()` for the persistence layer.
- `reset_to_defaults()` that reloads the action list from `project.godot`.
- `gamepad_connected(device_index: int)` / `gamepad_disconnected(device_index: int)` signals.

**Autoload placement rationale**: remap state is cross-feature (Ship reads input, but so does any future menu screen that wants custom bindings). Persisting to disk from an autoload `_ready()` is the natural home. The 4-autoload total is still within the "small and stable" guideline (ADR 010).

### 5. `REMAPPABLE_ACTIONS` excludes debug shortcuts

```gdscript
const REMAPPABLE_ACTIONS: Array[StringName] = [
    &"move_forward",
    &"turn_left",
    &"turn_right",
    &"dash",
    &"drop_mine",
    &"fire_broadside",
]
# Intentionally excluded: toggle_explosion_mode, toggle_debug_overlay
```

Debug shortcuts (F1 for debug overlay, F2 for explosion mode, etc.) can't be accidentally rebound through the rebind UI. Hard-coded bindings stay in `project.godot` and bypass the KeybindsManager layer entirely.

### 6. No rebind menu UI — infrastructure only

Phase 3 shipped **only the infrastructure**: `KeybindsManager.rebind_action()`, `save()`, `load()`, and the gamepad connect/disconnect signals. The actual rebind menu (`features/hud/controls_menu/`) is a **post-Phase-11 follow-up**. A designer can currently test rebinding by calling `KeybindsManager.rebind_action` from the debug overlay or a test scene, but there is no player-facing UI.

Source: Phase 4 retro line 1082–1087 in the parent plan.

### 7. Gamepad detection

`Input.joy_connection_changed` fires on gamepad plug/unplug. KeybindsManager subscribes and re-emits as its own `gamepad_connected(index)` / `gamepad_disconnected(index)` signals. Subscribers (PlayerInputComponent, future HUD controller-glyph display) react to the autoload-level signals rather than poking `Input` directly.

Current behavior: when a gamepad connects, PlayerInputComponent does nothing special — Godot's InputMap already handles both keyboard and gamepad bindings per-action. The `gamepad_connected` signal exists for future glyph-swap code ("show X/O buttons instead of keyboard icons"). No glyph swap is implemented yet.

### 8. No haptic feedback

Gamepad rumble is scoped out of Phase 3 and Phase 11. Hook point would be a new `HapticEmitterComponent` or a `KeybindsManager.rumble(duration, strength)` call; neither exists. If added later, it slots in as a post-ADR-011 sibling to audio (output-only, bus-gated).

## Consequences

**Positive:**
- **Ship no longer touches `Input.*` directly.** All input reads go through PlayerInputComponent, which means the FSM can gate them, tests can inject a fake, and rebinds work uniformly.
- **Rebinding is ready the moment a UI is added.** All the hard parts — InputMap mutation, persistence, default reset — are done.
- **Gamepad works for free.** Godot's InputMap system handles keyboard + gamepad on the same action by default; the layer exists to extend this when custom rebinds need to preserve across devices.
- **Debug shortcuts are safe.** Excluded from `REMAPPABLE_ACTIONS`, so no rebind can break `toggle_debug_overlay`.
- **FSM single-sources input lock.** Adding a STUNNED state (or any future "can't move" state) means one line in `ShipFSM.is_input_locked()` — not a grep across PlayerInputComponent callers.

**Negative:**
- **No UI yet.** A player can't rebind keys in the current build; the infrastructure exists but there's no menu. Post-Phase-11 follow-up.
- **`player_input.gd` file name diverges from `class_name PlayerInputComponent`.** Git-history continuity won over filename uniformity. Documented here so future readers aren't confused.
- **Gamepad glyph swap is absent.** The `gamepad_connected` signal has one subscriber (PlayerInputComponent) and one no-op handler. Waiting for the HUD glyph pass to materialize.
- **Haptic rumble is absent.** Not a regression (pre-refactor didn't have it either), but the omission is explicit.
- **Keybinds persistence format** is Godot's default `ConfigFile` (INI-style `keybinds.cfg`). Survives everything we care about, but is not cross-platform-portable in any special way.

## Alternatives Considered

**Multiple input components (PlayerKeyboardInput + PlayerGamepadInput).** Rejected. Godot's InputMap already handles both devices on the same action; splitting by device would require the components to coordinate, and we'd be solving a problem the engine solved.

**Inline input reads inside MovementComponent.** Considered — MovementComponent is the consumer of `get_thrust_input()`. Rejected because DashComponent, MineDropComponent, and BroadsideComponent also need input; routing all of them through MovementComponent would make MovementComponent the input god object.

**KeybindsManager as a service Node instead of autoload.** Rejected. Persistent keybinds have to survive scene transitions for the same reason AudioManager does (ADR 011). A service Node would get freed on scene change.

**Hard-code InputMap and skip remap entirely.** Considered as A6 scope-cut. **Rejected** — the user explicitly kept the remap layer because "controls menu eventually" was in the original scope. Phase 3 ships the infrastructure even without the UI.

**Write our own `InputMap` replacement.** Rejected. Godot's InputMap is fit for purpose. The only thing it lacks is a persistence layer, which KeybindsManager adds.

**Store keybinds in a Resource (`KeybindsConfig.tres`) instead of ConfigFile.** Considered. Rejected because user-editable settings belong in a non-Resource file format — Resources are designer tuning, not user preferences. `ConfigFile` is also simpler and doesn't require importing on load.
