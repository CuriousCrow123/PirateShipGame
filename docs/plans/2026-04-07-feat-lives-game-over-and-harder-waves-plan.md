---
title: Lives, Game Over Screen, Harder Waves, and Controls Polish
type: feat
status: active
date: 2026-04-07
---

# Lives, Game Over Screen, Harder Waves, and Controls Polish

## Overview

A bundle of tightly related changes that turn the current infinite-respawn sandbox into a proper run with an end condition:

1. **Wave progression 2x harder** — double the per-wave speed & reload scaling and bump the enemy-count ramp.
2. **Lives system (2 lives)** — the player gets two lives per run. Losing the last life triggers a game over.
3. **Lives UI** — small framed hull-icon pips in the HUD that match the existing parchment UI language.
4. **Game over screen** — stats (per-wave completion times, enemies destroyed, hit rate) with a restart button, styled like the HP display and wave toast.
5. **Controls overlay polish** — retitle "Sail Backward" → "Decelerate", add the "Speed Boost" (dash / Space) row, and re-center the overlay so it reads as part of the same UI family.

This touches roughly five files directly and adds three new scene/script pairs. The core coupling is: `Ship` now owns life count and emits a `game_over` signal, `Main` tracks run stats, `GameOverScreen` consumes those stats, and wave progression constants get retuned.

## Problem Statement / Motivation

Right now:
- Death is a mild setback — the player respawns forever, so the only "failure mode" is quitting the game. There is no run. There are no stakes.
- Wave progression shipped today is gentle (+6% speed, -8% reload per wave, capped). The player asked for 2x harder.
- The controls overlay is stale: `S` is labelled "Sail Backward" but the code actually brakes (`brake_decel`, not reverse thrust, see [scripts/ship.gd:159-160](scripts/ship.gd#L159-L160)), and the dash (Space → [scripts/ship.gd:270](scripts/ship.gd#L270)) isn't listed at all. Also the overlay currently uses `anchor_preset=8` with `-200,-120,200,240` offsets — the content container is not perfectly centered against the 640×360 viewport and the visual treatment is a plain VBox inside a chalkboard shader, missing the frame/shadow language the HUD now uses.
- There is no lives UI and no run-end celebration / stats screen. Without either, there is no reason to play a second run.

## Proposed Solution

### 1. Wave progression — 2x harder

Double the per-wave deltas and bump the enemy count increment. Keeps the existing wave state machine in [scripts/main.gd:205-239](scripts/main.gd#L205-L239) intact; only the tuning constants move.

| Constant | Before | After | Rationale |
|---|---|---|---|
| `WAVE_BASE_ENEMIES` | 3 | 3 | Leave the opening intact so wave 1 still feels inviting. |
| `WAVE_ENEMY_INCREMENT` | 1 | 2 | Count ramps twice as fast. |
| `WAVE_MAX_CONCURRENT_INCREMENT` | 1 | 2 | Concurrent pressure scales with count. |
| `WAVE_MAX_CONCURRENT_HARD_CAP` | 8 | 10 | Slight ceiling bump so count ramp has headroom. |
| `WAVE_SPEED_PER_WAVE` | 0.06 | 0.12 | Doubled. Hard cap (1.6x) now reached at wave 6 instead of 11. |
| `WAVE_COOLDOWN_PER_WAVE` | 0.08 | 0.16 | Doubled. Floor (0.6x) reached at wave 4 instead of 6. |
| Everything else | — | — | Unchanged (`WAVE_SPEED_HARD_CAP=1.6`, `WAVE_COOLDOWN_FLOOR=0.6`, intermission 4s, toast lead-time 1.5s). |

The hard cap + floor constants are **not** doubled — doubling them would make late waves unwinnable. Instead we reach those caps faster. If the player wants "2x harder" to also mean raised ceilings, we can revisit after playtesting.

### 2. Lives system

Add a second layer on top of the existing HP / death cycle in [scripts/ship.gd](scripts/ship.gd). The `_health` counter inside a single life is unchanged; the new `_lives` counter tracks how many deaths are permitted.

```gdscript
# scripts/ship.gd
signal lives_changed(current: int, maximum: int)
signal game_over

@export var max_lives: int = 2

var _lives: int = 0
```

Lifecycle:

- `_ready()` — `_lives = max_lives`, `call_deferred("_emit_initial_lives")` (mirrors the existing `_emit_initial_health` pattern at [ship.gd:87-91](scripts/ship.gd#L87-L91)).
- `_enter_death()` — decrement `_lives`, emit `lives_changed`. If `_lives <= 0`, **do not** schedule a respawn timer; emit `game_over` instead and leave the ship in its hidden / no-collision state. Otherwise schedule `_respawn()` as today.
- `_respawn()` — unchanged except it no longer refills lives.

Main listens for `game_over` and shows the game-over screen. The existing `died` / `respawned` signals stay — they cover the per-death visual reset (HPDisplay pulse, wake clear) and should still fire on non-terminal deaths.

### 3. Lives UI — aesthetic choice

**Visual concept: "captain's log porthole ships".** A small horizontal row under the HP pips, each life rendered as a tiny framed hull silhouette (reuses `ShipConfig.get_hull_region(0)` — the healthy hull spritesheet region at `Rect2(0, 522, 50, 108)`). Each icon sits inside its own `PanelContainer` using `ui_frame_style.tres` (same ivory-border, translucent wood background) so the "boundary" the request asked for is the frame itself — same visual grammar as the HULL pips.

Lost lives do NOT disappear: they dim to `LOST_COLOR = Color(0.35, 0.33, 0.3, 0.6)` (same tone the HPDisplay uses for drained pips), shrink to 0.6× scale, and the internal hull texture desaturates via a grayscale modulate. This communicates "ship lost" while keeping the frame layout stable and matching the existing HP pip drain tween.

Layout:

```
HPDisplay  (top-left, y=5, layer 50)
├── Frame (PanelContainer — ui_frame_style)
│   └── Content (VBox)
│       ├── Label "HULL"
│       └── Pips (HBox of 4 ColorRects)
│
LivesDisplay  (top-left, below HPDisplay, y≈48, layer 50)
├── Frame (PanelContainer — ui_frame_style)
│   └── Content (VBox)
│       ├── Label "SHIPS"
│       └── Icons (HBox of max_lives small PanelContainers, each wrapping a TextureRect)
```

Each ship-icon panel uses a slimmer inline `StyleBoxFlat` (2px border, 1px content-margin) so individual ships feel "docked" rather than sharing a big frame. Texture is a `TextureRect` with `stretch_mode = KEEP_ASPECT_CENTERED`, hull region scaled to ~16×24 px inside the 20×28 frame. Pixel-art filter inherits project nearest.

Tweening mirrors `hp_display.gd`:
- Life lost → `_tween_life_drain(icon)` → parallel tween of `color/modulate → LOST_COLOR`, `scale → Vector2(0.6, 0.6)`, `DRAIN_DURATION = 0.25`.
- Game-over → final life icon pulses once before the screen fades in (satisfying "final breath" beat).

Script: new `scripts/lives_display.gd` (`class_name LivesDisplay extends CanvasLayer`). Scene: new `scenes/lives_display.tscn`. Main instantiates via main.tscn and calls `setup(_ship)` during `_ready()` — same handshake as HPDisplay.

### 4. Game over screen

New scene `scenes/game_over_screen.tscn` and script `scripts/game_over_screen.gd` (`class_name GameOverScreen extends CanvasLayer`, layer 80 — above WaveToast's 60, below any future modal).

Layout (all inside a centered PanelContainer using `ui_frame_style.tres`):

```
Frame (PanelContainer, anchors center, min size ~260×200)
├── Title Label          "GAME OVER"          font_size 28
├── Subtitle Label       "scuttled at wave N"  font_size 10
├── HSeparator
├── StatsColumn (VBox, separation 3)
│   ├── "ENEMIES SUNK     N"
│   ├── "SHOTS FIRED      N"
│   └── "HIT RATE         NN%"
├── HSeparator
├── WaveTimesHeader Label "WAVE TIMES"
├── WaveTimesScroll (ScrollContainer, custom_minimum_size 160×60, horizontal_scroll_mode = DISABLED)
│   └── WaveTimesList (VBoxContainer, separation 1)
│       ├── "Wave 1       00:12.4"
│       ├── "Wave 2       00:18.1"
│       └── ...
└── RestartButton Button "RESTART RUN"  (styled)
```

- **Scrollable wave times**: `ScrollContainer` with a fixed min size — if the run has many waves, the list scrolls vertically within its bounded area while the rest of the panel stays fixed. Mouse wheel + click-drag scroll bar work out of the box. The scroll bar itself gets themed to match the parchment (slim, ivory thumb on translucent track).
- **Fade-in**: on `show_results(stats)` the panel starts at `modulate.a = 0.0`, slides in from `y += 20` with `TRANS_BACK / EASE_OUT` over 0.5s — same tween vocabulary as [scripts/wave_toast.gd:35-43](scripts/wave_toast.gd#L35-L43). A dim chalkboard-textured background `ColorRect` fades in behind the panel (0.0 → 0.75 alpha) to darken the live game scene beneath it.
- **Restart**: button `pressed` handler calls `get_tree().reload_current_scene()`. Simple, clean state reset — Main's `_ready()` re-runs and the whole run resets. No need to thread "reset" calls through every system.
- **Input focus & mouse**: CanvasLayer unpauses mouse (`mouse_filter = STOP` on the panel background), and the game tree can be optionally paused via `get_tree().paused = true` + `process_mode = PROCESS_MODE_ALWAYS` on the screen so the ship/enemies freeze during the review. The ControlsOverlay already uses this exact pattern, see [scripts/controls_overlay.gd:11-14](scripts/controls_overlay.gd#L11-L14).

### 5. Stat tracking

All accumulation lives in `Main` since it's already the hub for cannon firing, enemy destruction, and wave state. A tiny `RunStats` container class keeps the data tidy:

```gdscript
# scripts/run_stats.gd
class_name RunStats
extends RefCounted

var wave_times_sec: Array[float] = []   # wave i completion time (seconds since that wave began)
var enemies_destroyed: int = 0
var player_shots_fired: int = 0
var player_shots_hit: int = 0
var final_wave: int = 0
var _current_wave_started_at_msec: int = 0

func start_wave(_wave: int) -> void:
    _current_wave_started_at_msec = Time.get_ticks_msec()

func end_wave(_wave: int) -> void:
    var elapsed: float = float(Time.get_ticks_msec() - _current_wave_started_at_msec) / 1000.0
    wave_times_sec.append(elapsed)

func register_shot_fired() -> void:
    player_shots_fired += 1

func register_shot_hit() -> void:
    player_shots_hit += 1

func register_enemy_destroyed() -> void:
    enemies_destroyed += 1

func hit_rate() -> float:
    if player_shots_fired <= 0:
        return 0.0
    return float(player_shots_hit) / float(player_shots_fired)
```

Wire-up in Main:
- `_on_cannon_fired` — `_stats.register_shot_fired()` per cannon fired (the current handler at [main.gd:170](scripts/main.gd#L170) — note: multi-cannon broadsides fire multiple times, each counted).
- When a player cannonball hits an enemy — new signal on Cannonball. Plan below.
- Enemy destroyed — listen to `EnemyShip.destroyed` (already exists at [enemy_ship.gd:7](scripts/enemy_ship.gd#L7)). Connect in `_try_spawn_wave_enemy()`.
- Wave start — call `_stats.start_wave(wave)` in `_begin_wave`.
- Wave end — call `_stats.end_wave(wave)` in the `CLEARING → INTERMISSION` transition in `_update_wave_state`.

**Hit tracking on Cannonball**: add a new signal `hit_registered()` (no payload needed). Emit from `_on_body_entered` when `not is_enemy_owned and body is EnemyShip`. Main's existing `_on_cannon_fired` handler already wires `water_impacted`; extend it to also connect `hit_registered` → `_stats.register_shot_hit`. Enemy cannonballs do NOT emit this signal, keeping hit-rate a pure player metric.

### 6. Controls overlay — content + centering + style

File-by-file changes to [scenes/controls_overlay.tscn](scenes/controls_overlay.tscn):

- **Row updates:**
  - `Key2/Action2`: "S" → "Decelerate" (was "Sail Backward")
  - Add `Key8/Action8`: "Space" → "Speed Boost"
- **Centering:** replace the current anchor preset 8 with a proper full-rect `CenterContainer` wrapper (preset 15 with symmetric offsets) so the content block is exactly centered on the 640×360 viewport regardless of window scale.
- **Framed look:** wrap the ControlsList + Title + DismissPrompt inside a `PanelContainer` using `ui_frame_style.tres`, matching the HPDisplay / WaveToast family. The chalkboard background `ColorRect` stays (intentional — it's the "game is paused" curtain), but the content block gains the parchment frame so the overlay visually lives in the same world as the HUD.
- **Padding + separation**: bump `Content.theme_override_constants/separation` to 10, add `PanelContainer` content margins (12px horizontal, 8px vertical) so the frame has breathing room.
- **Title retains 24pt Kims font**, keys retain 16pt, but action labels get the same `Color(0.95, 0.93, 0.85, 0.95)` as the HPDisplay HULL label for cross-UI consistency.

Controls overlay is pop-up on game start, so we re-verify on first launch that nothing regresses in the pause flow.

## Technical Considerations

### Save/reset semantics

`get_tree().reload_current_scene()` reconstructs Main from scratch. That means:
- Wave state resets (`_current_wave = 0`, phase = INTERMISSION) — good.
- `Ship._lives` resets to `max_lives` via `_ready()` — good.
- `RunStats` gets recreated in Main's `_ready()` — good.
- The controls overlay pops up again — **undesired**. Add a static `ControlsOverlay._already_shown: bool = false` flag that flips on first `_ready()` and skips the pause on subsequent reloads. (Simple, no autoload needed.)

Alternative: add an autoload "GameSession" that persists the "controls already shown" bit. Rejected — a one-line static is simpler and stays local to the feature.

### Signal chain

```
Ship.take_damage → health_changed → HPDisplay.on_health_changed
                ↓ (health <= 0)
                _enter_death → died → Main._on_ship_died (wake trail pause)
                             → lives_changed → LivesDisplay.on_lives_changed
                             ↓ (lives <= 0)
                             game_over → Main._on_game_over
                                       → GameOverScreen.show_results(stats)
                                       → get_tree().paused = true
```

`died` and `game_over` both fire on the terminal hit. HPDisplay already handles `died`. LivesDisplay listens only to `lives_changed`. Main handles the terminal branch by delaying the game over screen slightly (e.g., `create_timer(1.0)`) so the player sees the hit explosion and HP drain before the stats panel takes over.

### State lifecycle risks

- **Partial state on reload**: `Engine.time_scale` is mutated by dash freeze frames / time dips. Ship already defends against this in `_exit_tree()` ([ship.gd:94-98](scripts/ship.gd#L94-L98)). Scene reload triggers `_exit_tree`, so the guard stays correct.
- **Paused tree + pause-immune screen**: `GameOverScreen.process_mode = PROCESS_MODE_ALWAYS` so its button still receives input while `get_tree().paused = true`. Same pattern as ControlsOverlay.
- **Respawn timer on terminal death**: make sure `_enter_death` does NOT schedule `_respawn` when `_lives <= 0`, otherwise the ship comes back after 2s and overlays the stats panel. Checked above.
- **Cannonball hit double-counting**: `Cannonball._on_body_entered` already guards with `_impacted` flag, so `hit_registered` fires at most once per ball. Safe.
- **Enemy destroyed signal parity**: `EnemyShip.destroyed` fires inside `_destroy()` before the fade-out tween — so it fires even for enemies that despawn from distance? No — `_despawn_distant_enemies` calls `queue_free()` directly without going through `_destroy()`, so despawned enemies do NOT emit `destroyed`, and `RunStats.enemies_destroyed` stays correct (only counts actual kills, not distance despawns). Good.

### Scene interface parity

- HPDisplay, LivesDisplay, WaveToast, GameOverScreen, ControlsOverlay all become CanvasLayer-based HUD elements using `ui_frame_style.tres` + `kims_bit_hand.ttf`. Main instantiates each in `_ready()` and wires signals. LivesDisplay follows the HPDisplay pattern exactly; GameOverScreen follows the WaveToast tween vocabulary.

### Integration test scenarios

1. **First run, first game over**: spawn enemies, die twice → stats screen appears with correct wave count, hit rate, wave times.
2. **Restart**: press RESTART → scene reloads, controls overlay does NOT re-popup, ship has 2 lives again.
3. **Mid-wave death**: die during wave 3 on first life → respawn continues, wave 3 still tracked, wave 3 time includes the death/respawn gap (intentional — it's the wall-clock time).
4. **Zero-shot game over**: die without firing → hit rate shown as "0%" or "—" gracefully (stats screen divides by zero guard).
5. **Long run**: play through 10+ waves → wave times list scrolls vertically inside its ScrollContainer without overflowing the game over panel.

## Acceptance Criteria

### Wave progression
- [ ] `WAVE_ENEMY_INCREMENT` = 2, `WAVE_MAX_CONCURRENT_INCREMENT` = 2, `WAVE_SPEED_PER_WAVE` = 0.12, `WAVE_COOLDOWN_PER_WAVE` = 0.16, `WAVE_MAX_CONCURRENT_HARD_CAP` = 10.
- [ ] Wave 2 spawns 5 enemies (was 4); wave 3 spawns 7.
- [ ] Wave 4 enemies are at the 0.6 cooldown floor; wave 6 enemies are at the 1.6 speed cap.

### Lives system
- [ ] `Ship.max_lives = 2` exported; `_lives` tracks deaths.
- [ ] `lives_changed(current, maximum)` signal fires on `_ready()` (deferred) and on every death.
- [ ] `game_over` signal fires when the last life is lost. `_respawn` is NOT scheduled in that case.
- [ ] First death: respawn works exactly as before (respawn delay, iframes, health refill).
- [ ] Second death: no respawn, game over screen appears.

### Lives UI
- [ ] New `scenes/lives_display.tscn` + `scripts/lives_display.gd` using `class_name LivesDisplay extends CanvasLayer`.
- [ ] Positioned top-left under HPDisplay, using `ui_frame_style.tres` outer frame and slimmer per-icon inner frames.
- [ ] Each icon is a hull silhouette (`TextureRect` with `ShipConfig.get_hull_region(0)`), scaled pixel-art.
- [ ] On life lost: drain tween (color → LOST_COLOR, scale → 0.6) matching HPDisplay vocabulary.
- [ ] Main instantiates + wires `LivesDisplay.setup(_ship)` in `_ready()`.
- [ ] CanvasLayer layer = 50 (same as HPDisplay).

### Game over screen
- [ ] New `scenes/game_over_screen.tscn` + `scripts/game_over_screen.gd`, `class_name GameOverScreen extends CanvasLayer`.
- [ ] Layer = 80 (above WaveToast 60, above HPDisplay 50).
- [ ] Shows: "GAME OVER" title, wave reached subtitle, enemies sunk, shots fired, hit rate, scrollable wave-time list, restart button.
- [ ] Uses `ui_frame_style.tres` and `kims_bit_hand.ttf` for visual parity.
- [ ] Slides in with TRANS_BACK / EASE_OUT over 0.5s, background dim fade 0.0 → 0.75 alpha.
- [ ] `process_mode = PROCESS_MODE_ALWAYS`; pauses tree while shown.
- [ ] ScrollContainer scrolls when wave count exceeds visible area.
- [ ] Restart button calls `get_tree().reload_current_scene()` and the controls overlay does NOT re-popup on that reload.
- [ ] Hit rate shows "—" or "0%" when `player_shots_fired == 0` (divide-by-zero guard).

### Stat tracking
- [ ] New `scripts/run_stats.gd` (`class_name RunStats extends RefCounted`).
- [ ] Tracks per-wave completion times (wall clock between wave start and CLEARING→INTERMISSION transition).
- [ ] Tracks enemies destroyed (via `EnemyShip.destroyed` signal).
- [ ] Tracks player shots fired (incremented in `Main._on_cannon_fired`).
- [ ] Tracks player shots hit (new `Cannonball.hit_registered` signal, connected per player-owned ball).
- [ ] Final wave number stored so the subtitle can read "scuttled at wave N".

### Controls overlay polish
- [ ] "S" label reads "Decelerate" (not "Sail Backward").
- [ ] New row: "Space" → "Speed Boost".
- [ ] Content block perfectly centered on the 640×360 viewport (full-rect CenterContainer).
- [ ] Content wrapped in a `PanelContainer` using `ui_frame_style.tres` so the overlay visually matches the HUD.
- [ ] Chalkboard background shader retained as the "paused curtain".
- [ ] `ControlsOverlay._already_shown` static flag prevents re-popup after scene reload.

### Quality gates
- [ ] `gdformat --check .` and `gdlint .` pass on all changed/new files.
- [ ] `run_project` → `get_debug_output` reports zero new errors through: play wave 1, take damage, die, respawn, die again, land on game over screen, restart.

## Files Touched

| File | Kind | Change |
|---|---|---|
| [scripts/main.gd](scripts/main.gd) | edit | Wave tuning constants; instantiate LivesDisplay + GameOverScreen; wire `Ship.game_over`; stats tracking calls; connect `Cannonball.hit_registered` + `EnemyShip.destroyed` |
| [scripts/ship.gd](scripts/ship.gd) | edit | `max_lives`, `_lives`, `lives_changed`, `game_over` signals; rewrite `_enter_death` to branch on remaining lives |
| [scripts/cannonball.gd](scripts/cannonball.gd) | edit | Add `hit_registered` signal; emit on player-ball hit |
| [scripts/enemy_ship.gd](scripts/enemy_ship.gd) | no change | — |
| [scripts/wave_toast.gd](scripts/wave_toast.gd) | no change | — |
| [scripts/run_stats.gd](scripts/run_stats.gd) | NEW | Run statistics accumulator |
| [scripts/lives_display.gd](scripts/lives_display.gd) | NEW | `class_name LivesDisplay` |
| [scenes/lives_display.tscn](scenes/lives_display.tscn) | NEW | Framed ship icons in HBox |
| [scripts/game_over_screen.gd](scripts/game_over_screen.gd) | NEW | `class_name GameOverScreen`; `show_results(stats)`; restart handler |
| [scenes/game_over_screen.tscn](scenes/game_over_screen.tscn) | NEW | Stats panel with ScrollContainer + Button |
| [scenes/main.tscn](scenes/main.tscn) | edit | Add LivesDisplay + GameOverScreen children |
| [scenes/controls_overlay.tscn](scenes/controls_overlay.tscn) | edit | Label updates, Space row, CenterContainer wrapper, PanelContainer frame |
| [scripts/controls_overlay.gd](scripts/controls_overlay.gd) | edit | `_already_shown` static flag |

## Sources & References

- [scripts/main.gd:21-34](scripts/main.gd#L21-L34) — wave tuning constants (retune site)
- [scripts/main.gd:205-296](scripts/main.gd#L205-L296) — wave state machine + spawn path (stat tracking hooks)
- [scripts/ship.gd:31-32](scripts/ship.gd#L31-L32) — `max_health` / `respawn_delay` exports (co-locate `max_lives`)
- [scripts/ship.gd:314-335](scripts/ship.gd#L314-L335) — `_enter_death` (branch on lives here)
- [scripts/hp_display.gd](scripts/hp_display.gd) — visual vocabulary for LivesDisplay (color palette, drain tween, POP_STAGGER)
- [scripts/wave_toast.gd](scripts/wave_toast.gd) — tween vocabulary for GameOverScreen (TRANS_BACK slide-in)
- [scripts/controls_overlay.gd](scripts/controls_overlay.gd) — pause-immune pattern for GameOverScreen
- [resources/ui_frame_style.tres](resources/ui_frame_style.tres) — shared parchment frame style
- [resources/fonts/kims_bit_hand.ttf](resources/fonts/kims_bit_hand.ttf) — HUD bitmap font
- [scripts/ship_config.gd:17-18](scripts/ship_config.gd#L17-L18) — `get_hull_region` for lives icon texture
- [scripts/cannonball.gd:57-73](scripts/cannonball.gd#L57-L73) — `_on_body_entered` (hit_registered emission site)
- [scripts/enemy_ship.gd:7](scripts/enemy_ship.gd#L7) — existing `destroyed` signal (stat tracking source)
