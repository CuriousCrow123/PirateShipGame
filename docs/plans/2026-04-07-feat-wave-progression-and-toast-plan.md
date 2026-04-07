---
title: Wave Progression with Incoming Wave Toast
type: feat
status: active
date: 2026-04-07
---

# Wave Progression with Incoming Wave Toast

## Overview

Replace the current "always 4 enemies, fixed spawn timer" sandbox in [scripts/main.gd](scripts/main.gd) with a wave-based progression system. Each wave fields more enemies that move slightly faster and reload their broadsides slightly faster than the previous wave. When a new wave begins, a polished UI toast announces the incoming wave number with the same pixel-frame visual language used by [scripts/hp_display.gd](scripts/hp_display.gd).

## Problem Statement / Motivation

Today the game spawns up to `max_enemies = 4` ships forever at a fixed `spawn_interval = 8.0` ([scripts/main.gd:13-15](scripts/main.gd#L13-L15)). There is no sense of escalation, no goal to chase, and no on-screen feedback that the world is reacting to the player. Wave progression gives the game a clear difficulty arc and a celebratory beat between waves. The wave toast also doubles as a quick visual rest before the next combat surge.

## Proposed Solution

1. **Wave state in `main.gd`** — track `_current_wave`, `_enemies_spawned_this_wave`, and `_enemies_to_spawn_this_wave`. When the alive-enemy count drops to zero AND the spawn quota is filled, start an "intermission" timer, then begin the next wave.
2. **Per-wave difficulty curve** — pass `chase_speed`, `circle_speed`, and `broadside_cooldown` overrides to each spawned `EnemyShip` via a new `apply_wave_modifiers(wave: int)` method on [scripts/enemy_ship.gd](scripts/enemy_ship.gd). Curves are gentle so the game stays playable for many waves.
3. **Wave toast** — new `scenes/wave_toast.tscn` + `scripts/wave_toast.gd` (CanvasLayer, modeled on `hp_display.tscn`). Displays a centered "WAVE N" with a smaller "INCOMING" subtitle. Tween: slide-in from above, brief hold, slide-out + fade. Reuses [resources/ui_frame_style.tres](resources/ui_frame_style.tres) and the bitmap font from `hp_display.tscn`.
4. **Main wires it up** — `main.gd` instantiates the toast in `_ready()`, calls `WaveToast.show_wave(n)` whenever a new wave begins (including wave 1 on game start, after a short grace period).

## Technical Considerations

### Wave configuration (constants in `main.gd`)

```gdscript
const WAVE_BASE_ENEMIES: int = 3
const WAVE_ENEMY_INCREMENT: int = 1            # +1 enemy per wave
const WAVE_MAX_CONCURRENT_BASE: int = 3        # cap on alive at once, wave 1
const WAVE_MAX_CONCURRENT_INCREMENT: int = 1   # +1 cap per wave (so spawns trickle in)
const WAVE_MAX_CONCURRENT_HARD_CAP: int = 8    # safety ceiling

const WAVE_SPEED_PER_WAVE: float = 0.06        # +6% chase/circle speed per wave
const WAVE_SPEED_HARD_CAP: float = 1.6         # max 1.6x base speed

const WAVE_COOLDOWN_PER_WAVE: float = 0.08     # -8% broadside cooldown per wave
const WAVE_COOLDOWN_FLOOR: float = 0.6         # never below 0.6x base cooldown

const WAVE_INTERMISSION_DURATION: float = 4.0  # gap between cleared & next wave start
const WAVE_TOAST_LEAD_TIME: float = 1.5        # toast appears this long before spawns begin
```

`enemy_count_for_wave(w) = WAVE_BASE_ENEMIES + (w - 1) * WAVE_ENEMY_INCREMENT`
`speed_mult(w) = min(1.0 + (w - 1) * WAVE_SPEED_PER_WAVE, WAVE_SPEED_HARD_CAP)`
`cooldown_mult(w) = max(1.0 - (w - 1) * WAVE_COOLDOWN_PER_WAVE, WAVE_COOLDOWN_FLOOR)`

### Wave lifecycle (state machine in `main.gd`)

```
INTERMISSION → (toast shown, timer counts down) → SPAWNING → (quota met, kill remaining) → CLEARING → (zero alive) → INTERMISSION
```

- `INTERMISSION`: timer ticks, no new spawns. When timer hits `WAVE_INTERMISSION_DURATION - WAVE_TOAST_LEAD_TIME`, fire `wave_toast.show_wave(n)`. When timer hits 0, advance to `SPAWNING`.
- `SPAWNING`: keep spawning (respecting `max_concurrent_for_wave`) until `_enemies_spawned_this_wave == _enemies_to_spawn_this_wave`. Spawn cadence reuses existing `spawn_interval` but is allowed to be shorter on later waves (also derived from `cooldown_mult`).
- `CLEARING`: quota met, waiting on existing enemies to die or despawn. Once `_enemies.is_empty()`, snap to `INTERMISSION` for the next wave.

The existing `_try_spawn_enemy()` and `_despawn_distant_enemies()` paths stay; only the trigger for `_try_spawn_enemy()` changes from "interval timer" to "wave-controlled timer".

### EnemyShip changes

Add a single new method:

```gdscript
# scripts/enemy_ship.gd
func apply_wave_modifiers(speed_mult: float, cooldown_mult: float) -> void:
    chase_speed *= speed_mult
    circle_speed *= speed_mult
    broadside_cooldown *= cooldown_mult
```

Called by `main.gd` immediately after `enemy.setup(_ship)`. No other enemy-ship logic changes — speeds and cooldowns are per-instance `@export` vars already.

### Wave toast scene structure

`scenes/wave_toast.tscn`:

```
WaveToast (CanvasLayer, layer = 60)         # above HPDisplay (layer 50)
└── CenterContainer (anchors full rect)
    └── Frame (PanelContainer, ui_frame_style.tres)
        └── Content (VBoxContainer, separation = 4)
            ├── Subtitle (Label, font_size = 7, text = "INCOMING")
            └── WaveLabel (Label, font_size = 24, text = "WAVE 1")
```

`scripts/wave_toast.gd` (sketch):

```gdscript
class_name WaveToast
extends CanvasLayer

const SLIDE_IN_DURATION: float = 0.35
const HOLD_DURATION: float = 1.1
const SLIDE_OUT_DURATION: float = 0.45
const SLIDE_OFFSET_Y: float = -40.0

var _frame_base_pos: Vector2 = Vector2.ZERO
var _active_tween: Tween = null

@onready var _frame: PanelContainer = $CenterContainer/Frame
@onready var _wave_label: Label = %WaveLabel

func _ready() -> void:
    assert(_frame != null, "WaveToast: Frame missing")
    assert(_wave_label != null, "WaveToast: WaveLabel missing")
    _frame_base_pos = _frame.position
    _frame.modulate.a = 0.0

func show_wave(wave: int) -> void:
    _wave_label.text = "WAVE %d" % wave
    if _active_tween and _active_tween.is_valid():
        _active_tween.kill()
    _frame.position = _frame_base_pos + Vector2(0.0, SLIDE_OFFSET_Y)
    _frame.modulate.a = 0.0
    _active_tween = create_tween().set_parallel(true)
    _active_tween.tween_property(_frame, "position", _frame_base_pos, SLIDE_IN_DURATION)\
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _active_tween.tween_property(_frame, "modulate:a", 1.0, SLIDE_IN_DURATION)
    _active_tween.chain().tween_interval(HOLD_DURATION)
    _active_tween.chain().tween_property(_frame, "modulate:a", 0.0, SLIDE_OUT_DURATION)
    _active_tween.parallel().tween_property(
        _frame, "position", _frame_base_pos + Vector2(0.0, SLIDE_OFFSET_Y * 0.5), SLIDE_OUT_DURATION
    )
```

Visual pizzazz beyond plain fade: BACK ease on slide-in for a snappy "drop", subtle slide-out drift, alpha fade so it never blocks combat for long. 9px subtitle + 24px wave number reuse the existing `kims_bit_hand.ttf` so it matches the HUD frame.

## System-Wide Impact

- **Signal chain**: enemies still emit `tree_exiting` → `_on_enemy_tree_exiting` → `_enemies.erase`. The wave state machine reads `_enemies.size()` after that erase to detect a cleared wave. No new signals required from `EnemyShip`.
- **Error propagation**: `WaveToast` validates child nodes in `_ready()` with `assert`. `Main` asserts the toast node in `_ready()` like every other HUD child.
- **State lifecycle risks**: if the player dies mid-wave, enemies still exist; on respawn the wave continues from where it left off (no reset). Wave count does NOT reset on death — death is a setback, not a wave restart. Document this in the script comment so it's not mistaken for a bug.
- **Scene interface parity**: `HPDisplay` is on `CanvasLayer` layer 50. `WaveToast` uses layer 60 so it sits above HUD without z-fighting; both are below the debug overlay (which we should verify in the implementation step).
- **Integration test scenarios**: (1) Wave 1 fully clears → toast appears → wave 2 spawns more + faster enemies. (2) Player dies during wave 3 → respawns → wave 3 still in progress. (3) Many enemies despawn from distance — `_despawn_distant_enemies` paths must still count toward wave completion (despawned counts as "removed", not "killed", but the wave still progresses since the spawn quota was already met).

## Acceptance Criteria

- [ ] `main.gd` runs a wave state machine with `INTERMISSION → SPAWNING → CLEARING` transitions.
- [ ] Wave 1 starts after a short grace period (toast appears ~1.5s before the first enemy spawns).
- [ ] Each subsequent wave spawns `WAVE_BASE_ENEMIES + (wave - 1) * WAVE_ENEMY_INCREMENT` enemies.
- [ ] Each subsequent wave's enemies are 6% faster (capped at 1.6x) and reload 8% faster (floored at 0.6x).
- [ ] `EnemyShip.apply_wave_modifiers(speed_mult, cooldown_mult)` exists and is called by `Main` after `setup`.
- [ ] `WaveToast` scene + script created; reuses `ui_frame_style.tres` and `kims_bit_hand.ttf`.
- [ ] Toast slides in (BACK ease), holds, fades out. No leftover position drift after re-show.
- [ ] Toast `CanvasLayer` layer = 60 (above HPDisplay's 50).
- [ ] Player death does NOT reset wave count or wave state.
- [ ] Distance-despawned enemies do not block wave progression (the wave still ends when alive-count hits zero, regardless of cause).
- [ ] `gdformat --check .` and `gdlint .` pass.
- [ ] `run_project` then `get_debug_output` reports zero errors.

## Files Touched

| File | Change |
|---|---|
| `scripts/main.gd` | Replace `_spawn_timer` flow with wave state machine; instantiate `WaveToast`; call `apply_wave_modifiers` per spawn |
| `scripts/enemy_ship.gd` | Add `apply_wave_modifiers(speed_mult, cooldown_mult)` |
| `scenes/main.tscn` | Add `WaveToast` instance child |
| `scenes/wave_toast.tscn` | NEW — CanvasLayer + CenterContainer + Frame + Labels |
| `scripts/wave_toast.gd` | NEW — `class_name WaveToast`, `show_wave(n)` |

## Sources & References

- `scripts/main.gd:13-21` — current spawn config & state vars
- `scripts/main.gd:101-106` — current `_physics_process` spawn tick (the trigger we're replacing)
- `scripts/main.gd:180-196` — `_try_spawn_enemy()` (call site for `apply_wave_modifiers`)
- `scripts/enemy_ship.gd:16-22` — `chase_speed`, `circle_speed`, `broadside_cooldown` exports
- `scripts/hp_display.gd` — pattern for CanvasLayer HUD with tweens & assertions
- `scenes/hp_display.tscn` — frame/font/style references reused by the toast
- `resources/ui_frame_style.tres` — shared HUD frame style
- `resources/fonts/kims_bit_hand.ttf` — bitmap font for HUD parity
