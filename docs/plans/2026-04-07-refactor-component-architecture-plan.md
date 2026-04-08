---
title: Deep Refactor — Component Architecture (Maximalist Tree)
type: refactor
status: active
date: 2026-04-07
origin: docs/brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md
---

# Deep Refactor — Component Architecture (Maximalist Tree)

## Enhancement Summary

**Deepened on:** 2026-04-07
**Review agents run:** Godot architecture, Godot timing, GDScript style,
Godot performance, Code simplicity, Resource safety, Pattern recognition,
Export verifier (8 parallel reviewers).

### Critical fixes applied directly to the plan

1. **Cooldown helper rewritten to timestamp-based** (was tick-based) — fixes
   a latent `progress()` ternary precedence bug AND eliminates ~50+ per-frame
   tick calls. See **Cooldown helper** section below.
2. **DashComponent freeze-frame cannot use the generic Cooldown** — `delta`
   is scaled by `Engine.time_scale`, so a freeze-frame started at
   `time_scale = 0` would never tick down. Uses `Time.get_ticks_msec()` +
   `PROCESS_MODE_ALWAYS` instead. See Phase 6 Step 34b/34c.
3. **Autoload order declared explicitly**: `Events → GameState → AudioManager`
   in `project.godot`. Autoloads may reference each other only inside
   `_ready()`, never at file scope (no `const X = preload("res://autoload/...")`).
4. **Mine iteration reentrancy fix**: `SpawnService` snapshots `_mines.duplicate()`
   before iterating, and mine detonation uses
   `Events.explosion_requested.emit.call_deferred(...)` to prevent synchronous
   recursion. See Phase 7 Step 36/38.
5. **Initial state emission via `call_deferred`**: Ship's first
   `state_changed(NULL, NORMAL)` is deferred so components that subscribe in
   their own (earlier-running) `_ready()` actually receive it. Mirrors the
   current [ship.gd:94](../../scripts/ship.gd#L94) `_emit_initial_status` pattern.
6. **`RunStats` declared as `class_name RunStats extends Resource`** — the
   plan referenced it in typed signal signatures but never defined the class.
   Added to Phase 1 Step 9 alongside Cooldown.
7. **Signal parameter rename**: `sound_requested(name)` → `sound_requested(sound_id)`
   (shadowed `Node.name`); `cheat_toggled(name)` → `cheat_toggled(cheat_id)`.
8. **`stat_recorded(Variant)` replaced with typed per-stat signals**
   (`kill_recorded`, `death_recorded`, `damage_recorded(int)`, etc.) — restores
   end-to-end type safety.
9. **Component default-OFF rule**: every component calls
   `set_physics_process(false)` and `set_process(false)` in `_ready()` unless
   it proves it needs ticking. Signal-driven by default.
10. **High-frequency signals stay OFF the bus**: `displacement_*_requested`
    would fire at 60Hz per entity. Direct injected references to
    `WaterEffectsManager` instead. Bus reserved for `<10Hz` aggregate events.
11. **set_shader_parameter audit** added as a Phase 6 sub-step — 6 production
    scripts mutate shared ShaderMaterials. Each must be classified as
    `.duplicate()`-required or intentionally shared.
12. **Export preset `exclude_filter` patch** specified for Step 50
    (`addons/gut/*, addons/pirate_dev_tools/*, tests/*, dev/*`).
13. **Ship-FSM ownership doctrine**: `_set_state()` is private; components
    *request* transitions via signals (`HealthComponent.death_requested → Ship
    → set_state(DEAD)`). No component writes the FSM directly. State signal
    signature is `state_changed(old: State, new: State)`.
14. **Area2D hurtbox convention**: collision layer/mask live on the Area2D
    itself; `_resolve_entity(area)` helper standardizes owner lookup.
15. **Component template specification** added before Phase 4 — every component
    follows the same skeleton (class_name, @export stats, `_ready()` asserts,
    signal-driven default-OFF).
16. **Naming convention locked**: all files under `features/ship/components/`
    use the `*Component` suffix. `PlayerInput` → `PlayerInputComponent`.
    `Cannon` keeps its bare name (it's a cannon, not a cannon-component).
17. **Shared component parameterization**: HealthComponent has
    `respawnable: bool` export (player=true, enemy=false);
    HitFeedbackComponent has `shake_on_hit: bool` export.
18. **Resource @export doctrine**: `@export var stats: ShipStats` with NO
    `preload()` default. Assigned in .tscn ExtResource slot. Embedded mutable
    sub-resources in component .tscn files are BANNED — Materials/Curves/
    Gradients must be ExtResources from `resources/`.
19. **Step 19/20 merged into one commit** (camera promotion + shake move to
    bus) — splitting them would leave one commit where shake is broken,
    violating the "game plays after every step" rule.
20. **Phase 4 extraction order adjusted**: `HurtboxComponent` moved AFTER
    `MovementComponent` so Ship root doesn't temporarily own both velocity
    AND relay hit events.

### Scope cuts applied (user-confirmed 2026-04-07, overriding brainstorm)

After deepen-plan review, the user accepted these simplifications from
Appendix A:

- **A1** — Fuse `CheatComponent` into `HealthComponent` (OS.is_debug_build() guard).
- **A2** — Fuse `GhostTrailComponent` into `DashComponent` (ghosts only exist during dash).
- **A3** — Fuse `HullVariantComponent` into Ship-root listener (2-line sprite swap).
- **A4** — Merge `StatsTracker` into `GameState` (autoload already owns RunStats).
- **A7** — Consolidate ADRs from 19 → 10 (one shared "ship component decomposition" ADR).

**Kept per brainstorm scope:**
- **A5** rejected: AudioManager stays as autoload (music persistence across scenes).
- **A6** rejected: full gamepad + InputMap remap + keybinds.cfg layer stays in Phase 3.

**Net effect:**
- Components: 13 → **10**
- Managers: 4 → **3** (WaveDirector, SpawnService, WaterEffectsManager)
- Autoloads: **3** (Events, GameState, AudioManager — unchanged)
- ADRs: 19 → **10**

### New considerations discovered

- **Sub-resource mutation is transitive**: `stats.weapon_config.damage = 5`
  is banned under the same rule as `stats.damage = 5`.
- **`.uid` sidecars must move atomically with their `.gd`** in Phase 10
  (`git mv` both in one commit).
- **`area_entered` reports the colliding Area2D, not its owner** — every
  HurtboxComponent subscriber needs a `_resolve_entity(area)` helper.
- **Camera `position_smoothing_enabled` causes a one-frame jump on respawn**
  unless `reset_smoothing()` is called on the respawn signal.
- **`set_deferred("monitoring", false)`** prevents "can't change state
  during query flush" errors when toggling Hurtbox during a physics callback.
- **`reset_physics_interpolation()`** needed on GhostTrail reparent or first
  frame in new parent lerps from old parent's transform.
- **`WaveSet` Array[WaveConfig] shared-reference**: two WaveSets pointing to
  the same `wave_03.tres` get the *same* in-memory instance. Plan's
  "runtime state in Node vars" doctrine covers this; unit test verifies.

### Phase 0/1 execution retro (added 2026-04-07 after Steps 1\u201310 landed)

Carry-over items discovered while executing Phases 0\u20131 that future steps
must respect or address:

- **GameState constants vs ShipStats** \u2014 [autoload/game_state.gd](../../autoload/game_state.gd)
  currently hard-codes `_DEFAULT_MAX_HP = 4` and `_DEFAULT_MAX_LIVES = 2`.
  **Phase 2 Step 11 MUST replace these with reads from `ShipStats.tres`**
  the moment that Resource exists, or the GameState seed will silently
  drift from the designer's intent.
- **GUT test convention** \u2014 the headless `gut_cmdln.gd` parse pass does
  not always pick up the global class index in time. **All test files in
  `tests/unit/`** must `preload("res://path/to/foo.gd")` the SUT into a
  local `const`, not rely on `class_name`. See
  [tests/unit/test_cooldown.gd](../../tests/unit/test_cooldown.gd) for the
  template.
- **GUT loader patch** \u2014 [addons/gut/gut_loader.gd:35](../../addons/gut/gut_loader.gd#L35)
  has a local null guard for `ProjectSettings.get("debug/gdscript/warnings/exclude_addons")`.
  Any future GUT version bump must re-apply this patch (or upstream it),
  otherwise the headless runner crashes during static-init with
  "Trying to assign value of type 'Nil' to a variable of type 'bool'".
- **Lint command divergence** \u2014 [CLAUDE.md](../../CLAUDE.md) was updated
  in Step 4 to use
  `find . -name "*.gd" -not -path "./addons/*" -not -path "./.git/*" -print0 | xargs -0 gdformat --check`
  because gdformat has no exclude option. The `gdlintrc` at the project
  root excludes `addons/` for gdlint. **Step 49 (CLAUDE.md update) must
  not regress these.**
- **Pre-existing warnings observed at every smoke test** (not introduced
  by Phases 0\u20131; left for the phase that owns the corresponding code):
  - `res://scenes/ship.tscn:5` stale UID for `cannon.tscn` \u2014 cleaned up
    in Phase 4 Step 21+ (Cannon component extraction).
  - `res://resources/dash_flame_sphere.tres` and `dash_flame_cone.tres`
    stale UIDs pointing at `dash_flame_material.tres` \u2014 cleaned up in
    Phase 10 (folder reorg + `git mv` + `.uid` regen).
  - `Camera2D overridden to physics process mode due to use of physics
    interpolation` \u2014 dissolves in Phase 3 Step 19+20 (camera promoted
    out of Ship).

### Phase 2 execution retro (added 2026-04-07 after Steps 11\u201316 landed)

Carry-over items discovered while executing Phase 2 that future steps
must respect or address:

- **Pre-existing duplicate `class_name RunStats`** (now resolved): Phase 1
  introduced `systems/run_stats.gd` (Resource) without removing the
  existing `scripts/run_stats.gd` (RefCounted, with the
  `start_wave/end_wave/register_*` method bundle). Two `class_name
  RunStats` declarations coexisted; Godot silently picked one each
  session. Merged in commit
  `fix(stats): merge duplicate RunStats class into Resource at systems/`
  before Step 11. Field renames `enemies_destroyed` \u2192 `kills`,
  `wave_times_sec` \u2192 `wave_times` (PackedFloat32Array per the plan).
  `scripts/game_over_screen.gd` migrated for the renames.
- **Class index cache hand-edits required**: Godot 4.6.1's editor only
  refreshes `.godot/global_script_class_cache.cfg` when scripts are
  opened in the editor; the MCP `run_project` cycle alone does not
  trigger a rescan. Phase 2 added `ShipStats`, `WeaponConfig`,
  `EnemyArchetype`, `WaveConfig`, `WaveSet`, and renamed `DashConfig`
  / `ExplosionConfig` \u2014 every one of those needed a manual edit to
  the cache file before the project would parse. **Future class
  additions during this refactor need the same treatment** until the
  user opens the editor.
- **WeaponConfig and EnemyArchetype read scopes are intentionally
  narrow**: Phase 2's "no behavior change" rule means I migrated only
  the reads where the existing code already had a clear consumer.
  - `sea_mine.gd` reads `weapon.damage` and `weapon.explosion_kind`
    (with explicit fallback constants).
  - `cannon.gd` holds the `weapon` slot but does not read it yet \u2014
    cannonball spawn parameters still live on `cannonball.gd`. **Phase
    4 Step 26 (Cannon component extraction) MUST migrate cannonball.gd's
    @exports into cannon.gd's `weapon` slot** so the WeaponConfig
    actually drives projectile speed/lifetime/explosion kind.
  - `enemy_ship.gd` reads `archetype.hp` and `archetype.chase_speed`
    only. **Phase 4 / Phase 8 must wire the rest** (`circle_speed`,
    `turn_speed`, `circle_radius`, `broadside_*`, `weapon`,
    `sprite_region`, `score`, `ai_kind`).
- **Boss wave placeholders**: `wave_11.tres` and `wave_12.tres` are
  parity-clamped to wave 10 values (the formula caps at wave 6 for
  speed and wave 4 for cooldown). **Phase 3.5 ships the Victory
  screen** that triggers when the last WaveSet entry clears, so the
  designer can then hand-tune 11/12 to be visibly distinct boss
  encounters.
- **WaveSet falls back to clamp-on-overflow** in `get_wave()` until
  Phase 3.5 ships the Victory transition. After clearing wave 12, play
  currently re-uses wave 12's tuning indefinitely. Phase 3.5 Step 20a
  must replace this fallback with a `run_ended(stats, victory=true)`
  emit before changing the clamping behavior.
- **Pre-existing warnings cleared**: the 4 stale-UID and Camera2D
  warnings that haunted Phase 0/1 smoke tests have stopped appearing.
  The editor re-imported `scenes/ship.tscn` and the dash flame .tres
  files during the rename steps (15/16), which cleaned up the orphan
  UIDs as a side effect.
- **GameState constants un-stubbed in Step 11** as required by the
  Phase 0/1 retro. The corresponding entry in the Phase 0/1 retro
  above is now stale historical context, not a TODO.

### Phase 3 + 3.5 execution retro (added 2026-04-07 after Steps 17–20a landed)

Carry-over items discovered while executing Phase 3 and 3.5 that
future steps must respect or address:

- **Stale `.godot/uid_cache.bin` from the DashConfig→DashStats rename**:
  the Phase 2 Step 16 rename commit (`c2d5743`) left a binary UID→path
  mapping pointing at `res://scripts/dash_config.gd` which no longer
  exists. Phase 3 Step 17's first smoke test tripped on it — hard
  assertion failure at [scripts/ship.gd:73](../../scripts/ship.gd#L73)
  because `resources/dash_stats.tres` couldn't resolve its script
  ExtResource. Fixed by deleting `.godot/uid_cache.bin` and letting
  Godot regenerate. **Consequence:** every subsequent non-editor run
  now emits ~45 "invalid UID, using text path instead" warnings
  because the MCP `run_project` cycle doesn't rebuild the UID cache
  the way the editor does. All resolutions fall back to text paths,
  so gameplay is unaffected, but the warning noise masks genuine
  issues during smoke tests. **Future steps:** when the user next
  opens the editor, the cache will regenerate and the warnings will
  clear. Don't chase them until then.
- **Class index cache hand-edits (Phase 2 retro still applies)**:
  Phase 3 added `PlayerInputComponent` (Step 17) and `GameCamera`
  (Step 19+20), both of which required manual edits to
  `.godot/global_script_class_cache.cfg`. `KeybindsManager` is an
  autoload with no `class_name`, so no cache edit was needed.
- **`const X: PackedStringArray = PackedStringArray([...])` is not a
  constant expression** in GDScript 2 — hit on
  [autoload/keybinds_manager.gd](../../autoload/keybinds_manager.gd)
  `REMAPPABLE_ACTIONS`. Workaround: use plain `const X: Array = [...]`.
  Future Resource/autoload constants that want typed string arrays
  should initialize with a var or accept an untyped Array constant.
- **`JoyButton` / `JoyAxis` enums must be used, not `int`**, when
  assigning `InputEventJoypadButton.button_index` or
  `InputEventJoypadMotion.axis`. Typed `int` parameters trigger
  4.6's "Integer used when enum expected" warning. See the last two
  private helpers in `keybinds_manager.gd` for the corrected pattern
  — applies to any future input-handling code that passes JoyButton/
  JoyAxis through function parameters.
- **Camera zoom-punch signal carries an ABSOLUTE zoom target**, not a
  scale multiplier against `_base_zoom`. Phase 3 Step 19+20 had to
  reconcile the ambiguous `scale` name in
  `Events.camera_zoom_punch_requested(scale_amount, duration)` with
  `DashStats.zoom_punch_target` (which is absolute, e.g. `1.1`). The
  camera script's `_on_camera_zoom_punch_requested` documents this
  choice. **Phase 4+ callers:** pass absolute zoom values, not
  multipliers.
- **Camera target injection is deferred**: `main.gd._ready` calls
  `_camera.call_deferred("set_target", _ship)` even though Ship's
  `_ready` has already run by the time Main's does. The deferral is
  belt-and-suspenders documentation that the camera supports post-hoc
  target injection and handles null gracefully, important for future
  intro/victory scenes that toggle the target.
- **`snap_to_target()` on respawn replaces `reset_smoothing()`**: the
  plan's original wording said "call `reset_smoothing()` on the
  respawn signal". The implementation went one step further — it
  forcibly syncs `global_position` to the target AND calls
  `reset_smoothing()`, so the camera doesn't lerp from the death
  location even if `_physics_process` hasn't run yet. Phase 4+ should
  use `snap_to_target()`, not raw `reset_smoothing()`, for any hard
  teleport.
- **Shake magnitude/decay constants moved from DashStats → GameCamera**:
  `GameCamera.SHAKE_MAGNITUDE_PX` and `SHAKE_TRAUMA_DECAY` are now
  the source of truth (hard-coded to the DashStats defaults at time
  of migration: `3.0` and `2.0`). The DashStats fields
  `shake_magnitude_px` and `shake_trauma_decay` are still read by
  `ship.gd._start_dash` to pass `shake_trauma_initial` via the bus,
  but the decay/magnitude fields are now dead weight on DashStats.
  **Phase 11 cleanup:** either remove the dead fields from DashStats
  or promote the constants back into a `CameraStats.tres` Resource.
- **KeybindsManager is the 4th autoload** and the plan's autoload
  order (`Events → GameState → AudioManager`) is now extended to
  `Events → GameState → AudioManager → KeybindsManager`. Order still
  matters: KeybindsManager doesn't touch other autoloads in `_ready`,
  but any future autoload that relies on InputMap being finalized
  should register AFTER KeybindsManager.
- **No controls-menu UI** — Phase 3 Step 18 only shipped the
  infrastructure (`rebind_action`, `save`, `reset_to_defaults`,
  `gamepad_connected/disconnected` signals). `REMAPPABLE_ACTIONS`
  excludes `toggle_explosion_mode` and `toggle_debug_overlay` so
  debug shortcuts can't be accidentally rebound. The menu itself
  lands in a post-Phase-11 follow-up (see Future Considerations).
- **VictoryScreen reuses GameOverScreen via scene inheritance** —
  `scenes/victory_screen.tscn` is a one-liner that inherits from
  `game_over_screen.tscn`. A single `GameOverScreen` script drives
  both; `show_results(stats, victory: bool)` picks title/subtitle.
  The `Title` label was promoted to `unique_name_in_owner` so the
  script can rewrite it at runtime. **Phase 10 folder reorg:** when
  both scenes move to `features/hud/`, the inheritance `ExtResource`
  path must update first (otherwise the child scene loses its base).
- **`WavePhase.ENDED` is a terminal state** — once set in
  `_on_game_over` or after final-wave-clear in `_update_wave_state`,
  the wave FSM idles. `_on_game_over` early-returns if phase is
  already `ENDED` to guard against a victory→death race where the
  ship dies during the 1-second grace timer between
  `Events.run_ended.emit(..., true)` and the victory screen sliding
  in. **Phase 7 WaveDirector extraction must preserve this guard**
  or the player can see both screens back-to-back.
- **`wave_set.is_final_wave(_current_wave - 1)` off-by-one contract**:
  `_current_wave` in `main.gd` is 1-indexed (UI-facing); `WaveSet`
  methods are 0-indexed. The `-1` conversion lives in the CLEARING
  branch of `_update_wave_state` and `_wave_config_for`. **Phase 7
  WaveDirector must unify this** — either make everything 0-indexed
  or add a 1-indexed wrapper on WaveSet and delete the `maxi(wave-1,
  0)` calls scattered in main.gd.
- **`WaveSet.get_wave` clamp is now defensive, not functional**:
  the Phase 2 retro's TODO is resolved — main.gd emits victory
  before any overflow read can happen. The clamp stays as a safety
  net; do not remove it.
- **DashStats still has unused camera-shake fields**: `shake_magnitude_px`,
  `shake_trauma_decay`, and `zoom_punch_target` (the camera reads it
  via the bus signal, so it's still *live* but its owner is now
  DashStats-the-data-source, not a camera-feedback Resource).
  Consider carving these into a `CameraFeedbackStats.tres` during
  Phase 11 cleanup, or at minimum document that these fields feed
  GameCamera via bus.

## Overview

A big-bang refactor of PirateShipGame from a rapidly vibecoded codebase
(~4,600 LOC across 30 scripts and 23 scenes) into a component-based scene
architecture with Resource-driven tuning, a signal bus, autoloads for
cross-cutting state, an input system, an audio system, a victory screen,
and a feature-folder layout. Executed on a single `refactor/component-architecture`
branch with `main` frozen for 4–6 weeks, one commit per sub-step, game-must-launch
discipline after every step. See brainstorm: [docs/brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md](../brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md).

## Problem Statement

The codebase has reached a stable, playable base but carries structural debt
that will compound as features land:

1. **[scripts/ship.gd](../../scripts/ship.gd) is a 548-line god object** —
   confirmed exact. It owns movement, dash, damage, iframes, lives, respawn,
   mine drops, broadside firing, hit feedback, camera shake, ghost spawning,
   hull variants, a cheat toggle, AND reads player input directly. 22 member
   vars form a flag soup (`_is_dead`, `_input_locked`, `_dash_active`,
   `_iframes_left`, `_invincible`, …). Four `get_tree().create_timer()`
   lambdas scattered at lines 365, 516, 525, 531.
2. **[scripts/main.gd](../../scripts/main.gd) is 394 lines** — confirmed. It
   bundles wave management (inline `WavePhase` enum FSM), 13 wave tuning
   constants, enemy/mine spawning, dual displacement SubViewport wiring,
   per-enemy wake-trail Line2D registration, 6 ship-signal connections, and
   stats hooks.
3. **Tuning lives in code constants** — 13 wave constants at
   [main.gd:8-31](../../scripts/main.gd#L8-L31) and 9 ship stat `@export`s at
   [ship.gd:26-36](../../scripts/ship.gd#L26-L36), none designer-tunable as
   `.tres`.
4. **Test scenes live in production** — [scenes/dash_fire_test.tscn](../../scenes/dash_fire_test.tscn),
   [scenes/explosion_test.tscn](../../scenes/explosion_test.tscn),
   [scenes/stylized_flame_test.tscn](../../scenes/stylized_flame_test.tscn) —
   totaling 999 LOC. **Two of these are active tooling, not scratchpads**
   (see Research Delta #3).
5. **Timer lambdas are scattered across 5 files, 10 sites** (not 5 as the
   brainstorm estimated — see Research Delta #4).
6. **Implicit ship state** — no FSM, just the 22-var flag soup.
7. **Camera2D is a child of Ship** ([scenes/ship.tscn:94](../../scenes/ship.tscn#L94)),
   coupling camera lifecycle to respawn.
8. **Player input reads live in ship.gd** at lines 127, 136, 143, 151, 164, 172.
   No InputMap remap support, keyboard-only bindings in
   [project.godot:26-83](../../project.godot#L26-L83).

**Strengths to preserve** (confirmed by research):

- No autoloads currently — all dependencies passed via `setup()` DI. Clean slate.
- Resources used well for `DashConfig`, `ExplosionConfig`, plus a visual-only
  `ShipConfig`.
- ADRs and per-feature plans are disciplined (4 ADRs, 20 plans).
- Project conventions in [CLAUDE.md](../../CLAUDE.md) are clear.
- `gdlint .` currently passes; `gdformat --check .` has only 2 trivial fixes
  (see Phase 0 step 3).

## Proposed Solution

Decompose into the **Maximalist Component Tree** (Approach C from brainstorm):

- **Components** own behavior (small, single-responsibility Nodes).
- **Resources** own data (read-only templates, hot-reloadable from inspector).
- **Signal bus** (`Events` autoload) carries cross-system events.
- **Feature folders** (`features/ship/`, `features/water/`, …) group each
  subsystem.
- **Pattern:** components emit signals upward → the entity root (Ship,
  EnemyShip) listens and dispatches → bus only for cross-system traffic.
- **FSM** (flat enum: `NORMAL, DASHING, IFRAME, DEAD`) replaces flag soup.
- **Scope expansions (explicitly in scope):** full audio system (built empty),
  PlayerInput + InputMap remap + gamepad layer, Victory screen / finite
  campaign, per-component ADRs.

Executed in 11 phases, 50+ sub-steps, one commit per step, game-launches-after-every-step.

## Technical Approach

### Architecture

#### Component tree — Player Ship

`features/ship/ship.tscn` (root: `CharacterBody2D`, ~80-line orchestrator):

```
Ship
├── PlayerInput              # reads InputMap, exposes typed axes/buttons
├── MovementComponent        # thrust, turn, friction, brake, collisions
├── DashComponent            # dash impulse, cooldown, freeze frames, OWNS Engine.time_scale
│                            # Also owns ghost trail spawning (A2: fused 2026-04-07)
├── HealthComponent          # current hp, lives, take_damage(), respawn via injected SpawnPoint
│                            # Also owns invincibility cheat (A1: fused 2026-04-07, OS.is_debug_build())
├── HurtboxComponent         # Area2D, emits hit_taken; disables in IFRAME/DEAD
├── BroadsideComponent       # orchestrates port/starboard cannon groups
├── CannonSlots/             # Marker2D slots, each containing a Cannon component
│   ├── PortCannon1          # Cannon component (per-cannon cooldown, muzzle)
│   ├── PortCannon2 ...
│   ├── StarboardCannon1 ...
│   └── StarboardCannon2
├── MineDropComponent        # mine cooldown + spawn request
├── HitFeedbackComponent     # flash, hit shake, iframe blink, screen-shake req
├── AudioEmitterComponent    # plays SoundConfig clips on local events
├── Sprite2D / CollisionShape2D

# A3 (fused 2026-04-07): HullVariantComponent removed — Ship root connects
# HealthComponent.health_changed to a 2-line method that swaps hull sprite
# via ShipConfig.get_hull_region(). No separate component.
```

**Communication pattern (canonical):**

> Components emit signals upward; Ship root listens and dispatches.
> Components do NOT find each other via groups or unique nodes.
> Components do NOT touch the Events bus directly (exception: VFX/Audio
> listener subsystems whose entire job is bus traffic).

#### Component tree — Enemy Ship

Shares the core combat components with Player — `HealthComponent`,
`HurtboxComponent`, `BroadsideComponent`, `Cannon`, `HitFeedbackComponent`,
`AudioEmitterComponent`. Bespoke `EnemyAIMovement` for chase-and-shoot. **No strategy
pattern until a 2nd archetype exists** (YAGNI gate).

#### Cannonball & SeaMine

Stay as cohesive scene scripts. Reuse `HurtboxComponent` (and `HealthComponent`
for mines) where it makes sense. **Not decomposed into 4-component trees.**

#### State machine

Flat enum FSM on Ship: `{NORMAL, DASHING, IFRAME, DEAD}`. Hand-rolled (4 states
does not justify an HSM addon). Components subscribe to `Ship.state_changed`.
Example: `HurtboxComponent` disables monitoring in `IFRAME`/`DEAD`.

#### Signal bus — `autoload/events.gd`

~20 signals, documented in one place. All bus signals are typed — no untyped
`Dictionary` payloads. Examples:

```gdscript
# Combat
signal player_damaged(amount: int, source: Node)
signal player_died
signal player_respawned
signal enemy_damaged(enemy: Node, amount: int, source: Node)
signal enemy_destroyed(enemy: Node, by_mine: bool)

# Waves
signal wave_announced(index: int)
signal wave_started(index: int, enemy_count: int)
signal wave_cleared(index: int, duration: float)
signal run_ended(stats: RunStats, victory: bool)

# World / VFX
signal explosion_requested(pos: Vector2, kind: StringName, dir: Vector2, vel: Vector2)
signal screen_shake_requested(trauma: float)
signal camera_zoom_punch_requested(scale: float, duration: float)  # NEW (Research Delta #1)
signal mine_dropped(pos: Vector2)
signal cannonball_fired(pos: Vector2, dir: Vector2, by_player: bool)
signal cannonball_water_impact(pos: Vector2)  # listened by Mine subsystem AND water listener

# Displacement (three typed signals — never untyped Dictionary)
signal displacement_impact_requested(pos: Vector2, radius: float, strength: float)
signal displacement_wake_ring_requested(pos: Vector2)
signal displacement_bob_requested(pos: Vector2, phase: float)

# Audio
signal sound_requested(sound_id: StringName, pos: Vector2)  # sound_id not "name" — shadows Node.name

# Meta — typed per-stat signals (replaces generic stat_recorded(Variant))
signal kill_recorded
signal death_recorded
signal damage_recorded(amount: int)
signal wave_time_recorded(index: int, seconds: float)
signal cheat_toggled(cheat_id: StringName, active: bool)  # cheat_id not "name"
```

**Discipline rules (enforced by review):**

- Bus is for *cross-system* events.
- Parent↔child communication uses direct signal connections in the same scene.
- **No signal bubbling** — components don't touch the bus. The entity root
  (Ship, Enemy, WaveDirector) decides what to publish.
- Every bus signal declared in one file with a typed signature.

#### Data-driven Resources (read-only templates, hot-reloadable)

Converted / created:

| Resource | Source of values |
|---|---|
| `ShipStats.tres` | **scattered @exports in ship.gd:26-36** (Research Delta #2) |
| `WeaponConfig.tres` | `cannon.gd` + `cannonball.gd` literals |
| `EnemyArchetype.tres` | `enemy_ship.gd` constants |
| `WaveConfig.tres` | `main.gd:8-31` (13 constants) |
| `WaveSet.tres` | `Array[WaveConfig]` — hand-authored campaign |
| `SoundConfig.tres` | Built empty — no clips yet |
| `DashStats.tres` | rename of existing `DashConfig` |
| `ExplosionStats.tres` | rename of existing `ExplosionConfig` |

**Hot-reload pattern (CRITICAL):**

> Components hold a **reference** to the shared Resource. They treat it as a
> read-only template. **No `.duplicate()` at spawn.**
>
> All mutable runtime state (current_hp, current_cooldown, dash_remaining) lives
> in Node `var`s on the component, **never** on the Resource.

This enables editing `ShipStats.tres` in the inspector while the game is running
to see changes propagate live.

**Reconciliation with [CLAUDE.md](../../CLAUDE.md) (Research Delta #5):**
The current CLAUDE.md says "always `.duplicate()` any Resource mutated at
runtime". This rule still holds — because *mutable Resources are banned
entirely* under the new doctrine. The rule shifts from "duplicate before
mutating" to "never write to fields on `@export var` Resources at all". Phase
11 step 49 rewords CLAUDE.md to document both rules (the old duplicate rule
still protects legacy mutable Resources like `width_curve` used in
[scripts/trails.gd](../../scripts/trails.gd)).

**Anti-trap:** Anyone writing `stats.current_hp = ...` is wrong. Lint gate:
no writes to fields on `@export var` Resources. Audit during code review.

#### Camera & spawn point

- **Camera2D** is promoted to its own scene under [main.tscn](../../scenes/main.tscn),
  no longer a child of Ship ([current location: scenes/ship.tscn:94](../../scenes/ship.tscn#L94)).
- Camera exposes `set_target(ship: Node2D)`; `main.gd` injects on `_ready`.
- Camera does its own position lerp / smoothing.
- `CameraShakeComponent` listens for `screen_shake_requested` on the bus.
- **NEW:** Camera listens for `camera_zoom_punch_requested` — dash tweens
  `_camera.zoom` today at [ship.gd:499-508](../../scripts/ship.gd#L499-L508),
  the brainstorm's bus signal list omitted this. (Research Delta #1.)
- **SpawnPoint** `Marker2D` in `main.tscn`, injected into `HealthComponent` on
  `_ready`. `HealthComponent` reads `spawn_point.global_position` on respawn.
  No `_spawn_position` magic on Ship.

#### Input system

- `PlayerInput` child component of Ship.
- Exposes typed state: `thrust_axis: float`, `turn_axis: float`,
  `fire_port_pressed: bool`, `fire_starboard_pressed: bool`, `dash_pressed: bool`,
  `mine_pressed: bool`, `brake_pressed: bool`.
- Reads from Godot `InputMap` actions (already defined at
  [project.godot:26-83](../../project.godot#L26-L83)).
- **Runtime InputMap remap** — bindings save/load to `user://keybinds.cfg`.
- **Gamepad detection layer** — auto-detect plug/unplug, per-device bindings,
  default keyboard + gamepad bindings.
- System-level inputs (fullscreen, debug overlay, explosion mode toggle at
  [main.gd:148, 154](../../scripts/main.gd#L148-L154)) move to a
  `SystemInput` node at the main level — not part of `PlayerInput`.

#### Audio system

- `autoload/audio_manager.gd` — global mixer, listens to `sound_requested`,
  plays via pooled `AudioStreamPlayer2D`s.
- `SoundConfig.tres` — clip, volume, pitch range, polyphony, spatial flag.
- `AudioEmitterComponent` on entities — holds a dict of named `SoundConfig`s and
  emits `sound_requested` on local events.
- Music handled directly by `AudioManager` (separate stream player).
- Bus volumes (`Master`, `SFX`, `Music`) saved with settings.
- **No actual sound files yet.** AudioManager logs no-ops until clips arrive.

#### HUD DI pattern (Research Delta #6)

Today 4 HUD nodes use `setup(ship)` injection ([main.gd:96-99](../../scripts/main.gd#L96-L99)).
With `GameState` autoload owning `current_wave/score/lives/RunStats`, HUD nodes
switch to: **read wave/lives/score from `GameState` autoload; read per-frame
ship state (mine cooldown progress) via a typed signal from the MineDropComponent
routed through the bus or via direct child-to-HUD signal connection in
main.tscn**. Decision: **HUD reads from GameState autoload for persistent run
state; HUD reads mine cooldown via `mine_cooldown_changed(progress: float)`
signal emitted from MineDropComponent and directly connected in main.tscn**
(not bus — this is scene-local).

### Folder structure (target)

```
project.godot
addons/
  pirate_dev_tools/    # debug overlay + atlas baker + flame tuning panel as EditorPlugin
  gut/                 # GUT testing addon
assets/
  textures/   audio/   fonts/
features/
  ship/
    ship.tscn  ship.gd  ship_fsm.gd
    components/
      player_input.gd  movement.gd  dash.gd  health.gd  hurtbox.gd
      broadside.gd  cannon.gd  mine_drop.gd  hit_feedback.gd
      ghost_trail.gd  hull_variant.gd  cheat.gd  audio.gd
    stats/
      default_ship_stats.tres
  enemies/
    enemy_ship.tscn  enemy_ship.gd  enemy_ai_movement.gd
    archetypes/   frigate.tres  ...
  weapons/
    cannonball.tscn  cannonball.gd
    sea_mine.tscn  sea_mine.gd
    configs/   default_cannon.tres  default_mine.tres
  waves/
    wave_director.gd  wave_config.gd  wave_set.gd
    sets/   default_campaign.tres
    configs/   wave_01.tres  wave_02.tres  ...  wave_NN.tres
  hud/
    hud.tscn  hp_display.tscn  lives_display.tscn
    mine_cooldown_display.tscn  wave_toast.tscn  game_over_screen.tscn
    victory_screen.tscn  controls_overlay.tscn
  vfx/
    explosion_effect.tscn  dash_fire_effect.tscn
    explosion_atlas_player.gd  explosion_sprite.gd  explosion_stats.gd
    wake_trails.gd  ghost_trail.gd
    vfx_listener.gd      # subscribes to explosion_requested / screen_shake_requested / camera_zoom_punch_requested
  water/
    water_chunks.gd  water_chunk_manager.gd
    displacement_stamps.gd
    shaders/   water_surface.gdshader  displacement_stamp.gdshader  ripple.gdshader  sea_mine_water.gdshader  sea_mine_ripple.gdshader
    materials/   water_material.tres  ...
    textures/   WaterTilesOffsetWithBlur.png  WaterTrailGradient.png  CausticTexture*.png
    water_listener.gd    # subscribes to displacement_*_requested signals
  camera/
    game_camera.tscn  game_camera.gd  camera_shake.gd
systems/
  cooldown.gd          # tiny RefCounted helper replacing timer lambdas
  run_stats.gd
autoload/
  events.gd            # signal bus
  game_state.gd        # current run/wave/score/lives + RunStats
  audio_manager.gd     # global audio mixer
main/
  main.tscn  main.gd   # thin scene wirer (~80 lines)
dev/
  archived_test_scenes/  # NOT loaded; for git-history reference only
  dev_README.md
docs/
  brainstorms/  decisions/  plans/  solutions/
  archived/              # thorough MD writeups of deleted test scenes
tests/
  unit/                # damage calc, wave config validation, cooldown, run_stats
  fixtures/
```

`dev/` and `tests/` excluded from export presets. `addons/pirate_dev_tools`
loaded only in editor context.

### Cooldown helper (REVISED — timestamp-based)

`systems/cooldown.gd`. **Rewritten after performance + GDScript review.** The
original tick-based version forced every owner into `_process`/`_physics_process`
to call `tick(delta)`, producing ~50+ per-frame callbacks. It also contained
a latent ternary-precedence bug in `progress()`. Replaced with a timestamp
design that has zero per-frame cost:

```gdscript
class_name Cooldown
extends RefCounted

var _ready_at_msec: int = 0
var _duration_msec: int = 0

func start(duration: float) -> void:
	_duration_msec = int(duration * 1000.0)
	_ready_at_msec = Time.get_ticks_msec() + _duration_msec

func is_ready() -> bool:
	return Time.get_ticks_msec() >= _ready_at_msec

func is_active() -> bool:
	return Time.get_ticks_msec() < _ready_at_msec

func remaining() -> float:
	return maxf(0.0, float(_ready_at_msec - Time.get_ticks_msec()) / 1000.0)

func duration() -> float:
	return float(_duration_msec) / 1000.0

func progress() -> float:
	if _duration_msec <= 0:
		return 1.0
	var left := maxi(0, _ready_at_msec - Time.get_ticks_msec())
	return 1.0 - float(left) / float(_duration_msec)

func reset() -> void:
	_ready_at_msec = 0
	_duration_msec = 0
```

**Properties:**

- **Zero per-frame cost.** No `tick()`, no `_process` fan-out.
- **`Engine.time_scale` independent** — `Time.get_ticks_msec()` is wall clock.
  This is important: it means you CANNOT use Cooldown for time-dip freeze frames
  (you want those scaled); DashComponent has a separate unscaled-timer path
  for the freeze-frame case — see Phase 6 Step 34b/34c.
- **Paused-scene behavior:** `Time.get_ticks_msec()` continues ticking when
  `get_tree().paused = true`. If a paused game-over or victory screen should
  NOT drain cooldowns, cooldown owners must snapshot remaining time on pause
  and reapply on unpause. Most gameplay cooldowns don't care because nothing
  fires during a paused game.
- **HUD progress polling** (mine cooldown display) works via `progress()`
  called from the HUD's own `_process` — one call per frame, not one per
  cooldown-owner.

Unit tested in `tests/unit/test_cooldown.gd` (Phase 1 Step 9):
`start(1.0)` → `is_ready()` false → wait 1s → `is_ready()` true;
`progress()` monotonic 0→1; `reset()` zeroes state.

Replaces **10 `get_tree().create_timer()` lambda sites** across 5 files
(Research Delta #4 — brainstorm said 5; actual count is 10):

| File | Sites | Lines |
|---|---|---|
| [scripts/ship.gd](../../scripts/ship.gd) | 4 | 365 (respawn), 516 (freeze), 525 (time-dip), 531 (dash cd) |
| [scripts/sea_mine.gd](../../scripts/sea_mine.gd) | 3 | arming / detonation / fuse |
| [scripts/main.gd](../../scripts/main.gd) | 1 | 204 (game-over grace await) |
| [scripts/explosion_effect.gd](../../scripts/explosion_effect.gd) | 1 | fade cleanup |
| [scripts/explosion_test.gd](../../scripts/explosion_test.gd) | 1 | bake pacing — lives in addon after Phase 11 |

Phase 6 must address all 10. Unit-tested.

### Implementation Phases

> **Game must launch after every sub-step.** One commit per sub-step.
> Regression validation uses the MCP run-test cycle (`run_project` →
> `get_debug_output` → `stop_project`) — no video baseline.

#### Phase 0 — Safety net

**Tasks & deliverables:**

- [x] **Step 1** — Fix the two trivial gdformat violations on main
  (`scripts/explosion_atlas_player.gd`, `scripts/explosion_test.gd`) via
  `gdformat .`, commit on `main` **before** branching. (Research Delta #7.)
- [x] **Step 2** — Branch `refactor/component-architecture`. Freeze `main`.
- [x] **Step 3** — *(REMOVED 2026-04-07)* Video baseline dropped per user
  decision. Regression validation uses the MCP run-test cycle (`run_project`
  → `get_debug_output` → `stop_project`) plus targeted manual smoke after
  each step.
- [x] **Step 4** — Install GUT addon at `addons/gut/` with empty
  `tests/unit/` skeleton. Verify `godot --headless -s addons/gut/gut_cmdln.gd`
  runs. *(Done 2026-04-07: GUT v9.4.0 vendored at `addons/gut/`. Patched
  `gut_loader.gd:35` null guard for missing `exclude_addons` setting. Added
  `gdlintrc` excluding `addons/`; CLAUDE.md lint commands updated to use
  `find | xargs gdformat --check` for addon-skipping formatting. Headless
  GUT runs clean against empty `tests/unit/`.)*

#### Phase 1 — Quick wins (autoloads, helpers, archive prep)

- [x] **Step 5** — For each of the 3 test scenes, write a thorough MD writeup
  in `docs/archived/<name>.md` (purpose, setup, parameters, findings,
  screenshots). **DO NOT delete yet** — `explosion_test.gd` is an active atlas
  baker (writes to `res://textures/explosions/`) and `stylized_flame_test.gd`
  is the canonical authoring tool for `resources/dash_flame_material.tres`
  and `resources/stylized_flame_snapshot.json` (Research Delta #3).
  Deletion is deferred to Phase 11 step 47 AFTER addon replacement lands.
  *(Done 2026-04-07: writeups at [docs/archived/dash_fire_test.md](../archived/dash_fire_test.md),
  [docs/archived/explosion_test.md](../archived/explosion_test.md),
  [docs/archived/stylized_flame_test.md](../archived/stylized_flame_test.md).
  Each one flags critical impl notes the dev-tools-addon replacement
  must preserve: dash_fire_test's per-emitter `.duplicate(true)` chain,
  explosion_test's `effect_scale = 1.0` bake-time override, and
  stylized_flame_test's `BLEND_MODE_PREMULT_ALPHA` blit on the
  SubViewportContainers.)*
- [x] **Step 6** — Add `Events` autoload at `autoload/events.gd` with all
  typed signals declared (empty bodies). Register in `project.godot` **FIRST
  in autoload order** — Events must be loaded before any other autoload or
  scene node can connect to its signals. **No file-scope `preload()` of other
  autoloads.** Autoloads may reference each other only inside `_ready()` or
  later. Add this as a rule in the Events ADR (pillar 007) to prevent
  parse-time cycles. *(Done 2026-04-07: 22 typed signals at
  [autoload/events.gd](../../autoload/events.gd) wrapped in
  `@warning_ignore_start("unused_signal")` because by-design no in-class
  emitters exist. Displacement signals deliberately omitted per the
  deepen-summary "high-frequency stays off the bus" rule. Also
  forward-declares `RunStats` at [systems/run_stats.gd](../../systems/run_stats.gd)
  with the **final** Step 9 field set so the typed
  `run_ended(stats: RunStats, ...)` signature parses now \u2014 deviation
  from the plan, which scheduled RunStats for Step 9. The Step 9 work
  is now Cooldown + GUT suite only.)*
- [x] **Step 7** — Add `GameState` autoload at `autoload/game_state.gd` —
  current wave/score/lives, `RunStats`. **Registered SECOND** in autoload
  order (after Events). `GameState` seeds initial values from `ShipStats.tres`
  at its own `_ready()` (NOT from a deferred HealthComponent emit) so HUD
  reads see valid data from frame 0. API is **methods only**
  (`start_new_run()`, `record_damage(amount)`, `record_kill()`,
  `record_death()`, `record_wave_cleared(index, duration)` …) plus
  read-only getters. External callers NEVER write fields directly.
  *(Done 2026-04-07 at [autoload/game_state.gd](../../autoload/game_state.gd).
  **TEMPORARY DEVIATION**: initial HP/lives are hard-coded constants
  `_DEFAULT_MAX_HP = 4` / `_DEFAULT_MAX_LIVES = 2` matching current
  ship.gd defaults, because `ShipStats.tres` does not exist until
  Phase 2 Step 11. **Phase 2 Step 11 must replace these constants with
  reads from ShipStats.** Also: no Events bus subscriptions yet \u2014 the
  recorder methods exist but nothing emits into them. Wiring real bus
  signals to the recorders happens incrementally in Phases 4\u20137 as the
  emitting components/managers come online.)*
- [x] **Step 8** — Add `AudioManager` autoload at `autoload/audio_manager.gd` —
  no-op until clips exist; subscribes to `Events.sound_requested` in its
  `_ready()`. **Registered THIRD** in autoload order.
  *(Done 2026-04-07 at [autoload/audio_manager.gd](../../autoload/audio_manager.gd).
  Routes `Events.sound_requested(sound_id, pos)` to `_on_sound_requested`
  which is currently a no-op. The Events reference is taken inside
  `_ready()`, never at file scope, per the deepen-summary autoload-order
  rule. Real SoundLibrary lookup + AudioStreamPlayer2D pool lands in a
  future phase together with the SoundConfig Resource.)*
- [x] **Step 9** — Add `Cooldown` helper at `systems/cooldown.gd` + unit test
  at `tests/unit/test_cooldown.gd`. **Also add `RunStats` at
  `systems/run_stats.gd`** — `class_name RunStats extends Resource` with
  typed `@export` fields: `kills: int`, `deaths: int`, `damage_taken: int`,
  `time_elapsed: float`, `waves_cleared: int`, `wave_times: PackedFloat32Array`.
  Required because `signal run_ended(stats: RunStats, victory: bool)` will
  not resolve at parse time without the class_name.
  *(Done 2026-04-07. Cooldown at [systems/cooldown.gd](../../systems/cooldown.gd)
  is the timestamp-based design from the deepen-summary fix #1 \u2014
  `progress()` short-circuits to 1.0 when `_duration_msec <= 0` so the
  latent ternary-precedence bug from the original tick-based draft
  cannot reappear. RunStats was added in Step 6 (early) so this step
  reduces to Cooldown + tests. Test suite at
  [tests/unit/test_cooldown.gd](../../tests/unit/test_cooldown.gd) has
  7 tests / 26 asserts, all passing under headless GUT (337ms).
  **Important detail for future test files:** the suite loads Cooldown
  via `const CooldownClass: GDScript = preload("res://systems/cooldown.gd")`
  rather than the global `class_name`, because the headless gut_cmdln.gd
  parse pass doesn't always pick up the global class index in time.
  All upcoming GUT tests under `tests/unit/` should follow the same
  preload pattern.)*
- [x] **Step 10** — Add `SpawnPoint` Marker2D to `main.tscn` at the current
  ship start position. *(Done 2026-04-07: SpawnPoint Marker2D under Main
  at `Vector2(176, 112)` \u2014 same as the Ship instance position. No script
  reads it yet; HealthComponent picks it up in Phase 4 Step 21.
  `validate_tscn.py` clean.)*

#### Phase 2 — Resources first (data, no behavior change)

- [x] **Step 11** — Create `ShipStats.tres` (+ `ship_stats.gd`
  `class_name ShipStats`). **Collects values from the 9 scattered @exports at
  [ship.gd:26-36](../../scripts/ship.gd#L26-L36)** — not from the existing
  visual-only `ShipConfig` (Research Delta #2). ship.gd reads
  `@export var stats: ShipStats` but keeps current behavior; existing visual
  `ShipConfig` stays as-is for hull/sail variant data. Decide: do they merge
  later? → **No.** `ShipConfig` = visual variant (sprites). `ShipStats` =
  motion/combat. Two Resources, two concerns.
  *(Done 2026-04-07: [scripts/ship_stats.gd](../../scripts/ship_stats.gd)
  + [resources/default_ship_stats.tres](../../resources/default_ship_stats.tres)
  hold the EFFECTIVE values that main.tscn previously achieved via
  per-instance overrides (`thrust = 120`, `linear_drag = 0.99`); the
  other 7 use the prior ship.gd defaults. All 27 internal references
  in ship.gd rewritten to `stats.X` via Python word-boundary regex
  (with negative lookahead so `mine_cooldown` does not catch
  `_mine_cooldown_left`). main.tscn drops the per-instance overrides
  and now sets `stats = ExtResource(default_ship_stats.tres)`.
  **Phase 0/1 retro carry-over resolved**: GameState now loads the
  same default_ship_stats.tres path inside its `_ready()` and reads
  `max_health` / `max_lives` from it instead of the temporary
  hard-coded constants. The Resource is shared in-memory across both
  loaders, so a designer edit propagates to both Ship and GameState.
  Sole external caller `scripts/lives_display.gd` migrated from
  `ship.max_lives` to `ship.stats.max_lives` (HP and mine cooldown
  HUDs already used signals/methods).)*
- [x] **Step 12** — Create `WeaponConfig.tres` read by `cannon.gd` /
  `sea_mine.gd` (damage, speed, lifetime, explosion_kind, fire_sound).
  *(Done 2026-04-07: WeaponConfig at [scripts/weapon_config.gd](../../scripts/weapon_config.gd)
  with two .tres instances at [resources/cannon_weapon.tres](../../resources/cannon_weapon.tres)
  (damage=1, speed=200, lifetime=0.75, explosion_kind=cannonball_impact)
  and [resources/sea_mine_weapon.tres](../../resources/sea_mine_weapon.tres)
  (damage=3, speed=0, lifetime=0, explosion_kind=sea_mine).
  **Read-site scope**: sea_mine.gd consumes `weapon.damage` (replacing
  `MINE_DAMAGE_TO_ENEMIES`) and `weapon.explosion_kind` (replacing the
  hard-coded "sea_mine" string). cannon.gd holds the `weapon` slot but
  doesn't read it yet \u2014 cannonball spawn parameters still live on
  cannonball.gd; that migration is scheduled for Phase 4 Step 26 alongside
  the Cannon component extraction. Both slots default to null and the
  sea_mine reads have explicit fallback constants so the .tscn can omit
  the assignment without breaking. cannon.tscn and sea_mine.tscn assign
  the new resources via ExtResource.)*
- [x] **Step 13** — Create `EnemyArchetype.tres` read by `enemy_ship.gd`
  (sprite, hp, speed, ai_kind, weapon, score).
  *(Done 2026-04-07: EnemyArchetype at [scripts/enemy_archetype.gd](../../scripts/enemy_archetype.gd)
  with the default instance at [resources/default_enemy_archetype.tres](../../resources/default_enemy_archetype.tres)
  pre-wired to `cannon_weapon.tres`. **Read-site scope**: enemy_ship.gd
  consumes `archetype.hp` and `archetype.chase_speed` in `_ready()` when
  the slot is non-null. Other fields (`sprite_region`, `score`, `ai_kind`,
  `circle_speed`, `turn_speed`, `circle_radius`, `broadside_*`, `weapon`)
  are forward declarations \u2014 the read sites land in Phase 4 (Cannon /
  HealthComponent / HurtboxComponent extraction) and Phase 8
  (EnemyAIMovement). The legacy @exports stay on enemy_ship.gd as
  fallbacks so any spawner not yet using the archetype keeps working.
  enemy_ship.tscn assigns the default archetype via ExtResource.)*
- [x] **Step 14** — Create `WaveConfig.tres` + `WaveSet.tres` +
  **`wave_01.tres` … `wave_NN.tres`** hand-authored from the current
  procedural formula at [main.gd:8-31](../../scripts/main.gd#L8-L31).
  **Initial campaign length: 12 waves** (10 normal + 2 designed "boss" waves).
  `main.gd` reads the WaveSet instead of computing from constants. **Verify:
  wave cadence and difficulty curve match the pre-refactor procedural values
  within ±10% on spawn interval and enemy count** (compute expected values
  from the formula at the same line).
  *(Done 2026-04-07: [scripts/wave_config.gd](../../scripts/wave_config.gd)
  (per-wave: `enemies_to_spawn`, `max_concurrent`, `spawn_interval`,
  `speed_mult`, `cooldown_mult`, `intermission_duration`),
  [scripts/wave_set.gd](../../scripts/wave_set.gd) (Array[WaveConfig]
  with `get_wave()` that clamps past the end and `is_final_wave()`
  for the future Phase 3.5 victory check), 12 wave .tres files at
  [resources/waves/](../../resources/waves/), and the aggregated
  [resources/waves/default_campaign.tres](../../resources/waves/default_campaign.tres).
  Wave values were generated **programmatically** from the procedural
  formula so cadence is identical (not just \u00b110%): wave 1 = 3 enemies
  / 3 concurrent / 1.0\u00d7 speed / 1.0\u00d7 cd / 2.0s spawn interval; the
  speed cap (1.6\u00d7) hits at wave 6 and the cooldown floor (0.6\u00d7) at
  wave 4 \u2014 same as before. main.gd drops all 13 wave constants except
  `WAVE_TOAST_LEAD_TIME` (UI lead, not difficulty). `_intermission_timer`
  is now seeded from the active WaveConfig in `_ready()` and reset
  between waves so per-wave breathers are designer-tunable. main.tscn
  binds `wave_set = ExtResource(default_campaign.tres)`. **Boss waves
  11/12** are still parity placeholders \u2014 currently identical to wave 10
  per the formula clamp; designer can hand-tune them in the .tres files
  whenever they want without touching code.)*
- [x] **Step 15** — Rename `DashConfig` → `DashStats` (plain text replace +
  run game + fix breaks). Update `resources/dash_config.tres` →
  `resources/dash_stats.tres` and `scripts/dash_config.gd` →
  `scripts/dash_stats.gd`. *(Done 2026-04-07: `git mv` of both files plus
  the .uid sidecar; class_name and field name `dash_config` \u2192 `dash_stats`
  rewritten in scripts/ship.gd, scripts/dash_fire_effect.gd, scripts/
  dash_stats.gd, scenes/ship.tscn, resources/dash_stats.tres. The
  `DashStats.FeelMode` enum reference and `start(dash_stats)` call site in
  dash_fire_effect.gd both updated. Cosmetic ExtResource id label
  `id="5_dash_config"` left as-is in ship.tscn (it is just a string id,
  not a reference). MCP run-test cycle clean.)*
- [x] **Step 16** — Rename `ExplosionConfig` → `ExplosionStats` (same
  procedure). *(Done 2026-04-07: `git mv` of scripts/explosion_config.gd
  + .uid sidecar + resources/explosion_config.tres to the `_stats` names;
  class_name and field references updated in scripts/explosion_stats.gd,
  scripts/explosion_test.gd (the active atlas baker), scripts/
  explosion_sprite.gd, and resources/explosion_stats.tres. MCP run-test
  cycle clean. GUT 7/7 still passing.)*

#### Phase 3 — Input + camera promotion

- [x] **Step 17** — Extract `PlayerInput` component. Add to Ship scene.
  Replace all `Input.is_action_pressed()` / `Input.get_axis()` calls in
  [ship.gd:127, 136, 143, 151, 164, 172](../../scripts/ship.gd#L127) with
  reads from `_player_input.thrust_axis` etc.
- [x] **Step 18** — Add `InputMap` remap support + gamepad detection layer +
  `user://keybinds.cfg` save/load. Default gamepad bindings for all 9 actions.
- [x] **Step 19+20 (SINGLE commit)** — Promote `Camera2D` to
  `features/camera/game_camera.tscn` under `main.tscn`, AND move camera shake
  + zoom-punch to bus listeners, **in the same commit**. Splitting them
  leaves one commit where shake is broken (current ship.gd writes
  `_camera.offset` directly; removing that without the listener in place
  kills shake entirely). Violates "game plays after every step".
  Substeps:
  - Fully remove the old `Camera2D` child at
    [scenes/ship.tscn:94](../../scenes/ship.tscn#L94). Not disable — remove.
    Leftover `current = true` cameras cause silent fights.
  - `main.gd` injects target on `_ready` via `call_deferred("set_target", _ship)`
    (main's `_ready` runs after Ship's).
  - `set_target(target: Node2D)` on the camera; `null` is a valid state
    (camera holds last position).
  - Camera's `position_smoothing_enabled` triggers one-frame rubber-band on
    respawn target re-inject → call `reset_smoothing()` on the respawn
    signal.
  - `CameraShakeComponent` child of Camera listens to
    `Events.screen_shake_requested` and applies trauma-squared offset.
  - `CameraZoomPunchComponent` (or folded into shake) listens to
    `Events.camera_zoom_punch_requested` — replaces the dash zoom tween at
    [ship.gd:499-508](../../scripts/ship.gd#L499-L508).

#### Phase 3.5 — Victory screen (small new feature)

- [x] **Step 20a** — Create `features/hud/victory_screen.tscn` as a sibling of
  `game_over_screen.tscn`, reading from the same `RunStats`. Wire
  `WaveDirector` to emit `run_ended(stats, victory: bool)` with
  `victory = true` when the last `WaveConfig` in the active `WaveSet` clears.
  `main.gd` routes to correct screen on `run_ended`. Confirm finite-campaign
  design shift with user during the planning review (scope item #4 in
  brainstorm).

#### Phase 4 preamble — Component template and naming convention

**Every component under `features/ship/components/` follows this skeleton
EXACTLY:**

```gdscript
class_name HealthComponent
extends Node

## Reacts to damage requests; owns current HP and lives; emits health_changed.

signal health_changed(hp: int)
signal death_requested  # Ship root listens → set_state(DEAD)
signal respawn_ready    # emitted when respawn cooldown elapses

@export var stats: ShipStats
@export var respawnable: bool = true  # player = true, enemy = false

var _hp: int = 0
var _lives: int = 0
var _respawn_cooldown := Cooldown.new()

@onready var _spawn_point: Marker2D = null  # injected by Ship root

func _ready() -> void:
	assert(stats != null, "HealthComponent requires a ShipStats reference")
	set_physics_process(false)  # DEFAULT OFF — signal-driven
	set_process(false)
	_hp = stats.max_hp
	_lives = stats.max_lives

func take_damage(amount: int, source: Node) -> void:
	# ... pure logic, no await, no timers
	pass
```

**Rules (all enforced in code review; `gdlint` does NOT check these):**

1. **Member ordering:** `class_name` → `extends` → doc comment → signals →
   enums → constants → `@export` → public `var` → `_private` var → `@onready`
   → `_ready` → `_process`/`_physics_process` (if any) → public methods →
   `_private` methods. Matches [CLAUDE.md](../../CLAUDE.md) mandate.
2. **Default OFF:** `set_physics_process(false)` and `set_process(false)` in
   `_ready()`. Enable only if the component proves it needs ticking.
   MovementComponent, EnemyAIMovement are the rare exceptions.
3. **`@export var stats: <Type>`** with NO `preload()` default — assigned via
   scene ExtResource slot. Asserted non-null in `_ready()`.
4. **Components emit, root dispatches.** Components connect to root signals
   by the **root** in its `_ready()`, NOT by children via `get_parent()`.
   Children never reference the parent.
5. **No writes to fields on `@export` Resources.** Transitive: no writes to
   sub-resources reached through them (`stats.weapon_config.damage = 5` is
   also banned). Mutable state lives in Node `var`s.
6. **Embedded sub-resources in component .tscn files are banned.** Materials,
   Curves, Gradients must be ExtResources from `resources/` so the
   shared-vs-per-instance decision is explicit at the .tres level.
7. **No direct `Events` bus access from within a component.** Two exceptions:
   `AudioEmitterComponent` publishes `sound_requested` (its entire purpose) and
   `HitFeedbackComponent` publishes `screen_shake_requested` (its entire
   purpose). Both exceptions documented in ADR 007 (Events bus discipline).

**Naming convention table** (locked before Phase 4 begins):

| File | class_name | Scene node name |
|---|---|---|
| `player_input.gd` | `PlayerInputComponent` | `PlayerInput` |
| `movement.gd` | `MovementComponent` | `Movement` |
| `dash.gd` | `DashComponent` | `Dash` |
| `health.gd` | `HealthComponent` | `Health` |
| `hurtbox.gd` | `HurtboxComponent` | `Hurtbox` |
| `broadside.gd` | `BroadsideComponent` | `Broadside` |
| `cannon.gd` | `Cannon` (not `CannonComponent` — it IS a cannon) | `PortCannon1` / `PortCannon2` / `StarboardCannon1` / `StarboardCannon2` |
| `mine_drop.gd` | `MineDropComponent` | `MineDrop` |
| `hit_feedback.gd` | `HitFeedbackComponent` | `HitFeedback` |
| `audio.gd` | `AudioEmitterComponent` | `AudioEmitter` |

**Removed per accepted Appendix A cuts (2026-04-07):**
- `ghost_trail.gd` / `GhostTrailComponent` — fused into DashComponent (A2).
- `hull_variant.gd` / `HullVariantComponent` — fused into Ship-root listener (A3).
- `cheat.gd` / `CheatComponent` — fused into HealthComponent (A1).

Net: **10 components** (down from 13).

**Shared component parameterization** (player vs enemy):

| Component | Export | Player | Enemy |
|---|---|---|---|
| `HealthComponent` | `respawnable: bool` | `true` | `false` |
| `HitFeedbackComponent` | `shake_on_hit: bool` | `true` | `false` |
| `AudioEmitterComponent` | `sound_bank: Dictionary[StringName, SoundConfig]` | player bank | enemy bank |
| `BroadsideComponent` | `fire_rate_mult: float` | 1.0 | per-archetype |

**Scene declaration order:** components are declared in the .tscn in
**dependency order** — `Health` first, then `Hurtbox` (reads health state),
then `HitFeedback` (listens to damage), then `Movement`, then `Dash`
(listens to movement), etc. Godot runs child `_ready()` in declaration
order, and any same-frame signal connection benefits from predictable order.

**Ship root FSM ownership rule** (from pattern review):

- `_set_state(new_state: State)` is **private** on Ship.
- Components **request** transitions via signals (e.g.,
  `HealthComponent.death_requested → Ship → _set_state(DEAD)`).
- Ship emits `state_changed(old: State, new: State)` — BOTH old and new.
  Components handling IFRAME → NORMAL need old to avoid double-handling.
- First emission is `call_deferred("_emit_initial_state")` in Ship `_ready()`
  so sibling components that subscribed in their earlier-running `_ready()`
  all receive it.
- Components react to state by subscribing, not by reading `ship.state`.
  No component holds a back-reference to Ship.

#### Phase 4 — Ship component extraction (one commit per component)

Order chosen to minimize inter-component coupling risk. **After each commit:
launch, play one wave, die, respawn, verify.**

- [x] **Step 21** — `HealthComponent` (cleanest boundary; reads from injected
  SpawnPoint; moves `take_damage()` from [ship.gd:303](../../scripts/ship.gd#L303)).
  **Respawn contract:** sets `_hp = max_hp` *before* emitting `health_changed`;
  exactly ONE emission per respawn. **Also owns the `_invincible` cheat
  toggle** (A1 fused: listens to its own cheat input in `_unhandled_input`
  guarded by `if not OS.is_debug_build(): return`; emits
  `Events.cheat_toggled(&"invincibility", _invincible)`).
- [x] **Step 22** — `MovementComponent` (thrust, turn, friction, brake,
  ram-damage pushback coordination at [ship.gd:179](../../scripts/ship.gd#L179)).
  **CRITICAL:** ram-damage mutual iframe coordination with EnemyShip must be
  preserved; route via `HurtboxComponent.hit_taken` so both ships see it.
  **Moved earlier than Hurtbox** (swap from brainstorm order) so Ship root
  doesn't briefly own velocity AND relay hit events simultaneously.
- [x] **Step 23** — `HurtboxComponent` (Area2D, emits `hit_taken(source: Node)`;
  Ship root relays to HealthComponent). **The Area2D and its CollisionShape2D
  are direct children of HurtboxComponent**, not the component itself.
  Collision layer/mask live on the Area2D, not the parent. Standard
  `_resolve_entity(area: Area2D) -> Node` helper walks `area.owner` to
  resolve the opposing Ship root. Toggles to `monitoring` use
  `set_deferred("monitoring", false)` to avoid "can't change state during
  query flush" errors when disabling during a contact callback.
- [x] **Step 24** — `HitFeedbackComponent` (flash + hit shake + iframe blink +
  emits `screen_shake_requested`). Moves code at
  [ship.gd:390-413](../../scripts/ship.gd#L390-L413) and iframe blink at
  326-340. **`shake_on_hit: bool` export** — player=true, enemy=false.
- [x] **Step 25** — `DashComponent` (dash impulse, cooldown, freeze frames,
  time-dip). **Owns `Engine.time_scale` writes** at
  [ship.gd:513, 524, 547](../../scripts/ship.gd#L513) **and the defensive
  `_exit_tree()` reset** at [ship.gd:102](../../scripts/ship.gd#L102) — the
  reset MUST move with the component or time_scale can survive the scene.
  (Research Delta #9.) **Also owns ghost trail spawning** (A2 fused:
  moves code at [ship.gd:241](../../scripts/ship.gd#L241)
  `_spawn_ghost` + ghost sources tracking; ghosts spawn into an injected
  `ghost_layer: Node2D` under `main.tscn` to avoid reparenting).
- [ ] **Step 26** — `Cannon` component — per-cannon cooldown + fire logic
  (today [scripts/cannon.gd](../../scripts/cannon.gd) is just a 19-line
  marker; this is a real expansion, not a refactor). Each CannonSlot child
  holds its own `Cooldown` and reads its own `WeaponConfig`.
- [ ] **Step 27** — `BroadsideComponent` — thin orchestrator triggering
  port/starboard cannon groups. Replaces
  [ship.gd:435-453 `_fire_broadside`](../../scripts/ship.gd#L435-L453).
- [ ] **Step 28** — `MineDropComponent` (emits `mine_cooldown_changed` for
  HUD; public `get_cooldown_progress()`).
- [ ] **Step 29 (FORMERLY GhostTrailComponent — REMOVED)** — Folded into
  DashComponent in Step 25 per Appendix A2. Skip.
- [ ] **Step 30 (FORMERLY HullVariantComponent — REMOVED)** — Folded into
  Ship root per Appendix A3. Ship root connects
  `HealthComponent.health_changed` → private
  `_on_health_changed(hp: int)` that calls `_hull_sprite.region_rect =
  config.get_hull_region(max_hp - hp)`. Two lines on Ship. No separate
  component, no ADR. Skip this step.
- [ ] **Step 31 (FORMERLY CheatComponent — REMOVED)** — Folded into
  HealthComponent in Step 21 per Appendix A1. Skip.
- [ ] **Step 32** — `AudioEmitterComponent` — emits
  `sound_requested(sound_id: StringName, pos)` on local events (cannon shot,
  hit, explosion). **Now the 10th and final component** after the three fusions.

#### Phase 5 — Ship FSM

- [ ] **Step 33** — Replace the 5 flag-soup vars (`_is_dead`, `_input_locked`,
  `_dash_active`, `_iframes_left`, `_invincible`) with a flat enum FSM at
  `features/ship/ship_fsm.gd`: `{NORMAL, DASHING, IFRAME, DEAD}`. Ship root
  emits `state_changed(old, new)`. `HurtboxComponent`, `PlayerInput`,
  `MovementComponent` subscribe and react.

#### Phase 6 — Replace timer lambdas

**All 10 sites** (Research Delta #4). One commit per site:

- [ ] **Step 34a** — [ship.gd:365](../../scripts/ship.gd#L365) respawn → Cooldown in HealthComponent.
- [ ] **Step 34b** — [ship.gd:516](../../scripts/ship.gd#L516) freeze frame →
  **NOT `Cooldown`** (Cooldown is wall-clock; freeze frame needs a scaled
  timer AND the whole point is `Engine.time_scale = 0`). Keep the existing
  `get_tree().create_timer(seconds, process_always=true, process_in_physics=false, ignore_time_scale=true)`
  or use a SceneTree timer with `ignore_time_scale=true`. Component
  `process_mode = PROCESS_MODE_ALWAYS` so the callback fires while paused/scaled.
- [ ] **Step 34c** — [ship.gd:525](../../scripts/ship.gd#L525) time-dip →
  same as 34b. Unscaled timer (wall clock) because `time_scale` is the thing
  being manipulated. The generic Cooldown helper is WRONG here — document
  in the DashComponent ADR (016) that time-scale-affecting timers use their
  own unscaled path.
- [ ] **Step 34d** — [ship.gd:531](../../scripts/ship.gd#L531) dash cooldown → Cooldown in DashComponent (safe — pure gameplay cooldown).
- [ ] **Step 34e** — `sea_mine.gd` site 1 → Cooldown.
- [ ] **Step 34f** — `sea_mine.gd` site 2 → Cooldown.
- [ ] **Step 34g** — `sea_mine.gd` site 3 → Cooldown.
- [ ] **Step 34h** — [main.gd:204](../../scripts/main.gd#L204) game-over grace → Cooldown in StatsTracker or VictoryScreen controller.
- [ ] **Step 34i** — `explosion_effect.gd` fade → Cooldown.
- [ ] **Step 34j** — `explosion_test.gd` bake pacing → Cooldown (moves into addon at Phase 11).
- [ ] **Step 34k (NEW)** — **`set_shader_parameter` audit.** Grep for
  `set_shader_parameter` across all production scripts. Confirmed hits:
  [hp_display.gd](../../scripts/hp_display.gd),
  [main.gd](../../scripts/main.gd),
  [sea_mine.gd](../../scripts/sea_mine.gd),
  [displacement_stamps.gd](../../scripts/displacement_stamps.gd),
  [dash_fire_effect.gd](../../scripts/dash_fire_effect.gd),
  [explosion_effect.gd](../../scripts/explosion_effect.gd).
  For each site, classify:
  - **(a) Per-instance mutation needed** → `.duplicate()` the material in
    `_ready()` of the node that owns the write. Document inline:
    `# per-instance material; duplicate to avoid shared-resource-mutation.md`.
  - **(b) Globally-shared write intended** (e.g., water DisplacementMap
    wired once from main.gd) → leave shared, document inline with the
    justification.
  Each classification becomes a one-line comment in the file; no ADR needed
  unless the decision is non-obvious. This closes the hot-reload doctrine
  blind spot called out by the resource-safety review.

#### Phase 7 — main.gd decomposition

- [ ] **Step 35** — Extract `WaveDirector` (the inline `WavePhase` FSM at
  [main.gd:244-313](../../scripts/main.gd#L244) + wave tuning logic). Reads
  active `WaveSet`. Emits `wave_announced/started/cleared/run_ended` on bus.
- [ ] **Step 36** — Extract `SpawnService` (instantiates enemies/mines,
  registers wakes). Subscribes to `WaveDirector.spawn_requested` AND to
  `Events.cannonball_water_impact` (for the mine-detonation cross-coupling
  at [main.gd:218-222](../../scripts/main.gd#L218-L222)).
  **Reentrancy guard:** when iterating the mine list in response to
  `cannonball_water_impact`, ALWAYS snapshot first:
  `for mine in _mines.duplicate(): if is_instance_valid(mine) and ...`.
  Mine detonation must emit explosion via
  `Events.explosion_requested.emit.call_deferred(pos, kind, dir, vel)` —
  synchronous emit during bus-handler iteration risks reentrancy into a
  half-mutated mine list. Documented in the SpawnService ADR.
- [ ] **Step 37** — Extract `StatsTracker` (subscribes to bus, updates
  `GameState.RunStats` via `stat_recorded`). Also owns the game-over grace
  timer.
- [ ] **Step 38** — Extract `WaterEffectsManager` (the displacement viewport
  tracking + wake-trail registration at
  [main.gd:102-139, 343-371](../../scripts/main.gd#L102-L139)). Also owns
  cross-coupling at [main.gd:218-222](../../scripts/main.gd#L218-L222)
  where cannonball water-impact iterates all mines — it re-emits
  `cannonball_water_impact(pos)` which the mine system subscribes to
  (Research Delta #10). **Critical:** dual SubViewports
  (`$DisplacementViewport/SubViewport` AND `$WaterTrail/SubViewport`) are
  both managed here. (Research Delta #11.)

#### Phase 8 — Enemy decomposition

- [ ] **Step 39** — `EnemyShip` reuses `HealthComponent`, `HurtboxComponent`,
  `BroadsideComponent`, `Cannon`, `HitFeedbackComponent`, `AudioEmitterComponent`.
- [ ] **Step 40** — `EnemyAIMovement` extracted as bespoke movement component
  (single chase-and-shoot strategy, no inheritance hierarchy yet).

#### Phase 9 — VFX + Water listeners (HIGH VISUAL-REGRESSION RISK)

- [ ] **Step 41** — `vfx_listener.gd` subscribes to `explosion_requested`,
  `screen_shake_requested`, and new `camera_zoom_punch_requested`. Wraps
  existing `ExplosionSprite.create()` factory.
- [ ] **Step 42** — `water_listener.gd` subscribes to the three typed
  displacement signals. Replaces direct
  `_displacement_stamps.spawn_impact/spawn_wake_ring/spawn_bob` calls at
  [main.gd:118-123, 126-139, 218-222](../../scripts/main.gd#L118-L139).
- [ ] **Step 43** — Full water subsystem refactor: `WaterChunkManager`, water
  folder consolidation, water tuning Resources. **Highest regression risk.**
  Verification checklist (expanded from brainstorm per Research Delta):
  - Spawn ship; wake rings appear at correct cadence.
  - Cannonball impacts produce displacement at correct radius (64.0, 2.0).
  - Mine bob displacement reads identically to baseline.
  - Smoke-test via MCP run-test cycle at the same ship speed; check
    `get_debug_output` for zero shader/script errors and visually confirm
    wake/displacement render in-editor.
  - Verify the **shared `DisplacementMap` SubViewport texture is still wired
    to all water chunks** via `$ChunkContainer.water_material` (single
    ShaderMaterial shared across chunks — most-likely regression site).
  - Verify **the SECOND SubViewport** `$WaterTrail/SubViewport` is still
    wired to `$WaterTrail/TrailSprite` and contributes to `WakeTrailMap`.
    (Research Delta #11 — brainstorm only listed one viewport.)
  - Verify per-enemy wake Line2D **`joint_mode = 1` (BEVEL)** — the Line2D
    round-joint / alpha-gradient asymmetry bug fix at
    [main.gd:353](../../scripts/main.gd#L353) must survive reorganization.
    (See solution: [line2d-round-joint-alpha-gradient-asymmetry.md](../solutions/line2d-round-joint-alpha-gradient-asymmetry.md).)
  - Verify `trails.gd` still `.duplicate()`s `width_curve` in `_ready()` —
    the shared-resource-mutation fix at
    [main.gd:348](../../scripts/main.gd#L348). (See solution:
    [shared-resource-mutation.md](../solutions/shared-resource-mutation.md).)
  - Verify `ViewportTexture` assignments happen in `_ready()` (not inspector)
    to avoid the Godot 4.6 regression. (See solution:
    [viewporttexture-46-regression.md](../solutions/viewporttexture-46-regression.md).)
  - Verify water shaders still declare `render_mode blend_premul_alpha` where
    they need it (see solution: [subviewport-premultiplied-alpha.md](../solutions/subviewport-premultiplied-alpha.md)).

#### Phase 10 — Folder reorganization (mechanical)

- [ ] **Step 44** — Move files into `features/`, `assets/`, `systems/`,
  `autoload/`, `main/`, `dev/`, `addons/`. **UID files travel with scripts.**
  Update preloads / `load()` paths / `class_name` registrations.
  **Also update:**
  - [docs/solutions/shared-resource-mutation.md](../solutions/shared-resource-mutation.md) — file paths moved.
  - [docs/solutions/line2d-round-joint-alpha-gradient-asymmetry.md](../solutions/line2d-round-joint-alpha-gradient-asymmetry.md) — file paths moved.
  - Any other solution doc referencing moved paths.

#### Phase 11 — Tests + ADRs + dev tools + cleanup

- [ ] **Step 45** — Write GUT tests at `tests/unit/`:
  - `test_health_component.gd` — `take_damage`, iframes, death threshold, signal emissions.
  - `test_cooldown.gd` — already exists from Phase 1, expand.
  - `test_wave_config.gd` — WaveConfig / WaveSet validation.
  - `test_run_stats.gd` — accumulation semantics.
- [ ] **Step 46** — Write ADRs at `docs/decisions/005-` through `014-`
  (reserved block — current last ADR is `004-dash-overspeed-via-drag-relax.md`,
  Research Delta #12). **A7 consolidated: 19 ADRs → 10.** The 9 per-component
  ADRs that shared the same rationale ("single-responsibility Node,
  signal-up pattern, reads @export stats") are merged into ONE
  `013-ship-component-decomposition.md` that documents the pattern once
  and lists each component as a short sub-section. Pillar ADRs (005-012)
  stay separate because each resolves a real architectural alternative.
  Fused components (CheatComponent, GhostTrailComponent, HullVariantComponent)
  get no ADR — their rationale lives in the fusion host's section of 013.
  - `005-component-decomposition-strategy.md` (pillar: why components, not inheritance)
  - `006-flat-enum-fsm-over-hsm.md` (pillar: FSM choice)
  - `007-events-bus-discipline.md` (pillar: bus rules, displacement direct-call override, AudioEmitter/HitFeedback exceptions)
  - `008-gamestate-autoload-scope.md` (pillar: methods-only API, StatsTracker merge A4)
  - `009-resources-hot-reload-strategy.md` (pillar: read-only templates, no preload defaults, no embedded sub-resources, set_shader_parameter audit)
  - `010-feature-folder-structure.md` (pillar: features/ layout, systems/ inclusion criteria)
  - `011-audio-architecture.md` (pillar: AudioManager autoload + SoundConfig + AudioEmitter)
  - `012-input-and-gamepad-architecture.md` (pillar: PlayerInput, InputMap remap, gamepad layer)
  - `013-ship-component-decomposition.md` (covers Health/Movement/Hurtbox/Dash/Cannon/Broadside/MineDrop/HitFeedback/AudioEmitter rationale in one doc; documents A1/A2/A3 fusions)
  - `014-cooldown-helper-timestamp-design.md` (why timestamp over ticked; time_scale incompatibility with freeze-frame)
- [ ] **Step 47** — Convert dev tools to `addons/pirate_dev_tools/` as a
  `plugin.cfg` + `plugin.gd` EditorPlugin. Register:
  - `debug_overlay.gd` (runtime perf/state overlay)
  - `explosion_atlas_baker.gd` (migrated from
    [scripts/explosion_test.gd](../../scripts/explosion_test.gd) —
    **preserve the bake-to-`res://textures/explosions/` workflow**)
  - `dash_fire_tuning_panel.gd` (migrated from
    [scripts/dash_fire_test.gd](../../scripts/dash_fire_test.gd))
  - `stylized_flame_tuning_panel.gd` (migrated from
    [scripts/stylized_flame_test.gd](../../scripts/stylized_flame_test.gd) —
    **preserve the save-to-`resources/dash_flame_material.tres` workflow**)
  - **Only after these migrations succeed**, delete the original 3 test
    scenes + associated .gd files. Commit deletion as a separate step.
- [ ] **Step 48** — Final lint pass (`gdformat --check .` + `gdlint .`), dead
  code removal, doc index update.
- [ ] **Step 49** — Update [CLAUDE.md](../../CLAUDE.md):
  - New folder structure (`features/`, `assets/`, `systems/`, `autoload/`,
    `main/`, `dev/`, `addons/`, `tests/`) alongside `docs/`.
  - New Resource safety doctrine: "Resources are read-only templates —
    mutable runtime state lives in Node `var`s, never on Resources. Do not
    write to fields on `@export var` Resources. Legacy pre-refactor mutable
    Resources (e.g. `width_curve` in `trails.gd`) still follow the old
    `.duplicate()`-first rule." (Research Delta #5.)
  - Member ordering rule preserved.
  - Signal bus discipline rule: "Components do not touch `Events` autoload
    directly. Entity roots (Ship, Enemy, WaveDirector) and VFX/Audio
    listeners are the only publishers."
- [ ] **Step 50** — Update [export_presets.cfg](../../export_presets.cfg)
  with the explicit `exclude_filter`. Current state (Web preset):
  `export_filter="all_resources"` with both include/exclude empty — meaning
  dev/, tests/, and addons WILL ship unless patched. Godot does NOT
  auto-exclude EditorPlugin addons. Required patch:
  ```
  exclude_filter="addons/gut/*, addons/pirate_dev_tools/*, tests/*, dev/*"
  ```
  Add identical `exclude_filter` to any future Windows/Linux/macOS presets.
  `.uid` sidecars are stripped automatically by the exporter (UIDs bake into
  binary `.scn`/`.res`) — do not list them.
  Compare built **PCK size** (not wrapper WASM, which is constant) against
  pre-refactor baseline; flag >10% increase for investigation. Run two clean
  exports (delete `PirateShipGameWeb/` between) to avoid stale-file
  contamination.

## Alternative Approaches Considered

The brainstorm evaluated three approaches and selected C. Recorded here for
traceability (see brainstorm: [docs/brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md](../brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md)).

- **Approach A — Minimal pragmatic cleanup.** Extract 3–4 components from
  ship.gd, no folder reorg, no autoloads. *Rejected:* doesn't address main.gd
  or tuning-in-code. Returns the codebase to the same problem in 3 months.
- **Approach B — Moderate component refactor.** ~6 ship components, Events
  autoload, Resource conversion, but no folder reorg. *Rejected:* the folder
  reorganization is cheap once everything else is done and leaves behind
  structural clutter.
- **Approach C — Maximalist component tree + feature folders + audio +
  input + gamepad + victory screen.** *Selected.* The user explicitly scoped
  in the extras, accepts 4–6 weeks, and wants the foundation laid once.

## System-Wide Impact

### Signal Chain

**Example: Player takes damage from enemy ram** (2+ levels deep):

1. `MovementComponent` (Enemy) collides with `MovementComponent` (Player).
2. Collision produces an Area2D overlap on both `HurtboxComponent`s.
3. Both `HurtboxComponent`s emit `hit_taken(source: Node)` upward.
4. Ship root relays to `HealthComponent.take_damage(ram_damage, source)`.
5. HealthComponent enters IFRAME → emits `health_changed(hp)` and
   `state_change_requested(IFRAME)`.
6. Ship FSM transitions → emits `state_changed(NORMAL, IFRAME)`.
7. HurtboxComponent subscribes, disables `monitoring`.
8. HitFeedbackComponent subscribes, starts flash tween + emits
   `screen_shake_requested(trauma)` on bus.
9. Camera's `CameraShakeComponent` (bus subscriber) applies trauma-squared
   offset.
10. Ship root re-emits `player_damaged(amount, source)` on bus.
11. `StatsTracker` (bus subscriber) updates
    `GameState.RunStats.damage_taken += amount`.
12. `AudioEmitterComponent` on Ship (local subscriber to Ship's `damaged` signal)
    emits `sound_requested(&"player_hit", global_position)`.
13. `AudioManager` (bus subscriber) no-ops (no clips yet).

Enemy side: identical chain, but with `EnemyAIMovement` handling `state_changed`
to back off briefly.

**Example: Cannonball hits water and detonates nearby mine:**

1. `Cannonball` collides with water Area2D.
2. Cannonball emits `water_impacted(pos)`.
3. WaterEffectsManager relays to bus as `cannonball_water_impact(pos)`.
4. `water_listener` (bus) emits `displacement_impact_requested(pos, 64.0, 2.0)`
   → WaterChunkManager calls `displacement_stamps.spawn_impact(...)`.
5. Mine subsystem (SpawnService-held list) subscribes to
   `cannonball_water_impact` and tests each mine's distance → detonates mines
   in radius, which emit `explosion_requested` on bus.
6. `vfx_listener` (bus) calls `ExplosionSprite.create(...)`.

### Error & Failure Propagation

- **@export node assertions** — every component's `_ready()` asserts its
  `@export` node references and its `@export var stats: <StatsResource>`.
  CLAUDE.md mandates.
- **Bus signal failures are silent** — listeners emit, publishers never know.
  This is a feature: decoupling. The trade-off: a missing listener connection
  silently drops the effect. Mitigation: each autoload (`Events`, `GameState`,
  `AudioManager`) logs via `print_debug()` on first bus connect in dev builds.
- **`push_error()` at `HealthComponent.take_damage()` entry** if `stats` is
  null or `_hp <= 0`. Cheap safety net.
- **Defensive `Engine.time_scale = 1.0` on `DashComponent._exit_tree()`** —
  absolutely critical, today lives at
  [ship.gd:102-106](../../scripts/ship.gd#L102-L106). Losing this during
  refactor causes respawn to run at slow-mo permanently.

### State Lifecycle Risks

- **Respawn partial failure** — if `HealthComponent` resets HP but FSM fails
  to transition out of DEAD, ship becomes permanently dead. Mitigation: FSM
  transition happens **before** HP reset, and the FSM transition is the
  *authoritative* respawn signal. Tests in `test_health_component.gd`.
- **GameState autoload staleness after game over** — if `RunStats` isn't
  reset on new run, stats accumulate across runs. Mitigation: `GameState.
  start_new_run()` explicit reset; called by main.gd on game restart.
- **`Engine.time_scale` leaks** — see above. Guarded by DashComponent.
- **Shared Resource mutation leaks** — see solution docs
  `shared-resource-mutation.md` and `godot-shared-mesh-surface-material.md`.
  **New discipline rule: never write to `@export var` Resources.** Lint gate
  in code review.
- **Camera lifecycle decoupled from Ship** — camera survives respawn. If
  camera loses target ref (e.g., Ship `queue_free`d + respawned), camera
  must handle null gracefully. Phase 3 step 19: camera's `set_target(null)`
  is a valid state (camera holds last position).
- **`SubViewport` texture invalidation on file move** (Phase 10) — see
  solution `viewporttexture-46-regression.md`; assign ViewportTexture in
  `_ready()` not in inspector.

### Scene Interface Parity

Scenes/autoloads that expose equivalent functionality and must co-evolve:

| Scene/Class | Related change |
|---|---|
| [scripts/enemy_ship.gd](../../scripts/enemy_ship.gd) | Phase 8 — reuses HealthComponent, HurtboxComponent, BroadsideComponent, Cannon, HitFeedbackComponent, AudioEmitterComponent |
| [scripts/sea_mine.gd](../../scripts/sea_mine.gd) | Phase 2 — reads `WeaponConfig.tres`; Phase 6 — 3 timer lambdas replaced; reuses HealthComponent/HurtboxComponent where natural |
| [scripts/cannonball.gd](../../scripts/cannonball.gd) | Phase 2 — reads `WeaponConfig.tres`; reuses HurtboxComponent |
| [scenes/minimap_display.tscn](../../scenes/minimap_display.tscn) + scripts | HUD DI pattern (Research Delta #6) — reads `GameState` autoload for persistent data |
| [scenes/hp_display.tscn](../../scenes/hp_display.tscn) | Same |
| [scenes/lives_display.tscn](../../scenes/lives_display.tscn) | Same |
| [scenes/mine_cooldown_display.tscn](../../scenes/mine_cooldown_display.tscn) | Reads from MineDropComponent's signal, not bus |
| [scenes/game_over_screen.tscn](../../scenes/game_over_screen.tscn) | Phase 3.5 — shares RunStats source with new VictoryScreen |

### Integration Test Scenarios

Cross-system scenarios that isolated GUT tests will NOT catch — **must be
manually validated via the MCP run-test cycle (`run_project` →
`get_debug_output` → `stop_project`) plus in-editor smoke playthrough:**

1. **Dash → collide with enemy at peak speed → take damage → respawn** —
   tests DashComponent / MovementComponent / HurtboxComponent /
   HealthComponent / FSM / CameraShake / Camera decoupling / Engine.time_scale
   reset.
2. **Drop mine → dash over water → mine detonates → explosion shakes camera
   → damage propagates to nearby enemy** — tests WaterEffectsManager /
   MineDropComponent / SpawnService / VFX listener / bus fan-out.
3. **Clear last wave → Victory screen reads RunStats → correct kill count /
   deaths / time shown** — tests WaveDirector `run_ended(victory=true)` /
   GameState RunStats accumulation / VictoryScreen.
4. **Hot-reload `default_ship_stats.tres` in inspector while running → ship
   speed changes live without restart** — merge-criteria gate.
5. **Gamepad plugged in mid-game → PlayerInput detects it → controls swap
   bindings → ship still controllable** — tests gamepad detection layer.
6. **Respawn → camera stays positioned / does not rubber-band** — tests
   camera promotion + target re-injection on respawn.

## Acceptance Criteria

### Functional Requirements

- [ ] Game plays end-to-end identically to pre-refactor behavior
  (waves spawn, ship dies, respawns, game-over screen shows correct stats,
  camera shakes on hit, dash zoom punch fires, wake trails render correctly).
  Validated by manual smoke playthrough + MCP run-test cycle.
- [ ] Last wave of `default_campaign.tres` transitions to a Victory screen
  sharing `RunStats` with GameOver.
- [ ] Player can rebind keys at runtime; gamepad auto-detects on plug-in and
  bindings load from `user://keybinds.cfg`.
- [ ] Adding a "homing torpedo weapon" requires only: new `torpedo.tscn` +
  `torpedo_config.tres` + a wave entry. NO edits to ship.gd, main.gd, or any
  manager.
- [ ] All wave/ship/enemy/sound tuning is editable in Godot inspector via
  `.tres`.
- [ ] Live editing `default_ship_stats.tres` while the game runs propagates
  to the ship without restart.

### Non-Functional Requirements

- [ ] `ship.gd` is under 100 lines.
- [ ] `main.gd` is under 100 lines.
- [ ] Zero errors in debug output after a full game session.
- [ ] Exports exclude `dev/`, `tests/`, and dev addons. Built binary size
  within 10% of pre-refactor baseline.
- [ ] Water shader + wake trail + displacement parity with pre-refactor
  behavior at same ship speed (in-editor smoke check, zero shader errors in
  `get_debug_output`).

### Quality Gates

- [ ] `gdformat --check .` passes on the entire tree.
- [ ] `gdlint .` passes on the entire tree.
- [ ] All GUT unit tests pass (4 suites: health, cooldown, wave config,
  run stats).
- [ ] Per-component ADRs 013–023 exist + pillar ADRs 005–012 exist.
- [ ] [CLAUDE.md](../../CLAUDE.md) updated with new folder structure and
  Resource safety doctrine.
- [ ] Solution docs with file-path references updated
  (`shared-resource-mutation.md`, `line2d-round-joint-alpha-gradient-asymmetry.md`).

## Success Metrics

- **Line budget:** ship.gd ≤ 100 LOC, main.gd ≤ 100 LOC, target total LOC ≈
  same as pre-refactor (decomposition redistributes, doesn't reduce net).
- **Designer tuning:** 100% of wave + ship + enemy + weapon stats editable
  in `.tres` inspector.
- **Hot-reload success:** ShipStats inspector edit → in-game effect without
  restart ≤ 500ms.
- **Test coverage:** 4 GUT suites passing; ~20–30 unit tests total.
- **Documentation:** 19 new ADRs (005–023), ~3 archived test-scene writeups.
- **Zero regressions** vs pre-refactor behavior across all validated
  scenarios (MCP run-test cycle + in-editor smoke).

## Dependencies & Prerequisites

- **Frozen `main` branch** for 4–6 weeks (scope item #28 in brainstorm).
- **gdformat clean main** before branching (2 trivial fixes — Research Delta #7).
- **GUT addon** installed (Phase 0 step 4).
- **Godot 4.6.1 stable** confirmed via `get_project_info` — matches project
  requirement.
- **No new external libraries.** Refactor is internal; no Context7 lookups
  needed beyond Godot documentation.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Water subsystem visual regression (Phase 9) | High | High | Pre-refactor in-editor smoke reference; expanded checklist with BEVEL joint_mode, dual SubViewport wiring, shared material wiring |
| Engine.time_scale leak on DashComponent refactor | Medium | High | Preserve defensive `_exit_tree()` reset; test respawn immediately after extraction; Research Delta #9 |
| HUD DI pattern ambiguity | Medium | Medium | Decided: GameState autoload for persistent state; signals for per-frame (mine cooldown) |
| Shared Resource mutation leaks back in | Medium | High | Doctrine rule "no writes to `@export var` Resources"; code review gate; solution docs referenced in CLAUDE.md |
| Timer lambda count undercounted (5 vs 10) | Already realized | Low | Research Delta #4; Phase 6 step 34 expanded to 10 sub-steps |
| Test scene deletion before addon replacement breaks authoring workflow | Medium | Medium | Research Delta #3 — Phase 1 step 5 writes MD only; actual deletion deferred to Phase 11 step 47 after addon migration succeeds |
| Camera zoom punch regression (omitted from bus) | Low | Medium | Research Delta #1 — added `camera_zoom_punch_requested` signal and Phase 3 step 20 ownership |
| Cannonball→mine cross-coupling dispatch path breaks | Medium | Medium | Research Delta #10 — explicit dispatch path defined in Phase 7 step 38 |
| File move (Phase 10) breaks UIDs / preloads | High | Medium | Move .uid sidecars with scripts; run `get_debug_output` after each major batch; update solution-doc paths (step 44 already covers) |
| ViewportTexture 4.6 regression on water files | Medium | High | Solution doc reference in Phase 9 verification; assign in `_ready()` not inspector |
| 4–6 week scope overrun | Medium | Medium | Scope expansions (audio, gamepad, victory) are the first-cut list per brainstorm Scope Expansions section |
| CLAUDE.md `.duplicate()` rule contradiction | Already identified | Low | Research Delta #5 — Phase 11 step 49 rewords |

## Resource Requirements

- **Single developer** (user) working full-time on a frozen branch.
- **~30–50 commits** over 4–6 weeks.
- **No new external dependencies** (GUT addon is internal-facing only).
- **Sound / gamepad assets NOT required** — systems built empty.

## Future Considerations

- **Homing torpedo weapon** — acceptance-criteria example, proves extensibility.
- **Multiple enemy archetypes** — EnemyAI strategy swap introduced only when
  the 2nd archetype lands (YAGNI gate).
- **Controls menu UI** — the remap infrastructure lands in Phase 3; a menu
  scene can be a follow-up plan.
- **Actual sound clips** — AudioManager no-ops wait for a future pass.
- **Per-cannon variation / upgrades** — Cannon-as-component sets this up
  cleanly for a future progression system.
- **Save/load** — explicitly deferred (brainstorm resolved question #10).
- **ECS migration** — explicitly NOT future work (YAGNI trap).

## Documentation Plan

- 3 archived test-scene MD writeups in `docs/archived/` (Phase 1 step 5).
- 19 ADRs (005–023) in `docs/decisions/` (Phase 11 step 46).
- [CLAUDE.md](../../CLAUDE.md) updated with new structure and Resource
  doctrine (Phase 11 step 49).
- 2 solution docs path-updated post-reorg (Phase 10 step 44).
- Doc index update (Phase 11 step 48).
- This plan serves as the Phase 0 contract.

## Research Deltas (Brainstorm vs. Current Codebase)

During local research the following gaps were found between the brainstorm
and the actual code state. Each is addressed in the phases above and flagged
here so the author can verify before `/gc:work` begins.

1. **Camera zoom punch missing from bus signal list.** ship.gd tweens
   `_camera.zoom` during dash at [ship.gd:499-508](../../scripts/ship.gd#L499-L508).
   Brainstorm only listed `screen_shake_requested`. Added
   `camera_zoom_punch_requested` to bus, owner is `CameraZoomPunchComponent`
   on the promoted Camera scene.

2. **ShipConfig is visual-only today.** Brainstorm Phase 2 step 11 implied
   `ShipStats` replaces current ShipConfig. In reality,
   [scripts/ship_config.gd](../../scripts/ship_config.gd) owns only hull/sail
   variant sprite data (HullSize enum, hull_variant 0-3, sail_variant 0-23,
   cannon_slots, CannonType). The 9 motion/combat stats live as scattered
   `@export`s at [ship.gd:26-36](../../scripts/ship.gd#L26-L36). Decision
   (Phase 2 step 11): `ShipConfig` stays as visual variant data; `ShipStats`
   is wholly new and consolidates the scattered exports. Two Resources,
   two concerns.

3. **Test scenes are active tooling, not scratchpads.**
   [scripts/explosion_test.gd](../../scripts/explosion_test.gd) (248 lines)
   is an active atlas baker writing to `res://textures/explosions/`.
   [scripts/stylized_flame_test.gd](../../scripts/stylized_flame_test.gd)
   (365 lines) writes to `resources/dash_flame_material.tres` and
   `resources/stylized_flame_snapshot.json`. Pure deletion in Phase 1 would
   lose the authoring workflow. **Reordering:** Phase 1 step 5 writes MD
   writeups only; actual deletion is deferred to Phase 11 step 47 AFTER
   addon replacements (`pirate_dev_tools`) successfully take over the
   bake/save workflows.

4. **Timer lambda count is 10, not 5.** Brainstorm listed "broadside, mine,
   dash, respawn, freeze frames". Actual grep: ship.gd has 4, sea_mine.gd
   has 3, main.gd has 1, explosion_effect.gd has 1, explosion_test.gd has 1.
   Phase 6 step 34 expanded to 10 sub-steps (34a–34j).

5. **CLAUDE.md `.duplicate()` rule contradicts hot-reload pillar.** Current
   CLAUDE.md: "always `.duplicate()` any Resource mutated at runtime".
   Brainstorm: "No `.duplicate()` at spawn; components hold references".
   These reconcile only if you read "mutated at runtime" as "the only
   Resources that should ever be mutated are legacy ones like `width_curve`
   in trails.gd". Phase 11 step 49 rewords CLAUDE.md to make the new
   doctrine explicit and preserve the legacy rule as a grandfather clause.

6. **HUD DI pattern needs a decision.** Today 4 HUD nodes use
   `setup(ship)` ([main.gd:96-99](../../scripts/main.gd#L96-L99)). Brainstorm
   didn't specify how they switch with GameState autoload landing.
   **Decision:** persistent run state (wave index, score, lives, RunStats)
   reads from `GameState` autoload. Per-frame UI state (mine cooldown
   progress) reads from a `mine_cooldown_changed(progress: float)` signal
   emitted by `MineDropComponent` and directly connected in main.tscn
   (scene-local, not bus).

7. **Two trivial gdformat violations on main right now.**
   `scripts/explosion_atlas_player.gd` and `scripts/explosion_test.gd`.
   Phase 0 step 1 fixes these on main BEFORE branching so the refactor
   commit history stays clean.

8. **Next ADR number is 005.** Current last ADR is
   [004-dash-overspeed-via-drag-relax.md](../decisions/004-dash-overspeed-via-drag-relax.md).
   Plan reserves 005–023 (19 ADRs).

9. **DashComponent owns `Engine.time_scale`.** Writes at
   [ship.gd:513, 524, 547](../../scripts/ship.gd#L513) and the defensive
   reset at [ship.gd:102-106](../../scripts/ship.gd#L102-L106). The
   `_exit_tree()` reset MUST move to DashComponent in Phase 4 step 25 or
   respawn can leave the game at slow-motion permanently.

10. **Cannonball→mine cross-coupling needs explicit dispatch path.**
    [main.gd:218-222](../../scripts/main.gd#L218-L222) eagerly iterates all
    mines on cannonball water impact. Phase 7 step 38 specifies:
    `WaterEffectsManager` re-emits `cannonball_water_impact(pos)` on the
    bus; mine subsystem (SpawnService-held list) subscribes and tests each
    mine's distance. Avoids losing the feature on decomposition.

11. **Two SubViewports for water, not one.**
    `$DisplacementViewport/SubViewport` (stamps) AND `$WaterTrail/SubViewport`
    (player wake Line2D). Phase 9 verification checklist must test both.

12. **Solution docs need file-path updates in Phase 10.**
    `shared-resource-mutation.md` and `line2d-round-joint-alpha-gradient-asymmetry.md`
    contain inline references to current paths that move in the reorg.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md](../brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md)
  — key decisions carried forward:
  1. Approach C (maximalist component tree) selected over A (minimal) and B (moderate).
  2. Components emit, root dispatches; no bus touches from components (except VFX/Audio listeners).
  3. Resources are read-only templates; no `.duplicate()` at spawn; runtime state in Node vars.
  4. 4-state enum FSM (NORMAL/DASHING/IFRAME/DEAD); no HSM addon.
  5. Scope expansions confirmed: full audio system (built empty), PlayerInput + InputMap remap + gamepad, Victory screen / finite campaign, per-component ADRs.
  6. 4–6 week frozen-main big-bang branch; one commit per sub-step.
  7. Cannonball/SeaMine stay cohesive; reuse components naturally.
  8. Partial enemy decomposition; shared core combat components.
  9. Dev tools migrate to `addons/pirate_dev_tools/` as EditorPlugin.
  10. Three typed displacement signals; never untyped Dictionary on bus.

### Internal References (current codebase)

- [scripts/ship.gd](../../scripts/ship.gd) — 548 lines, god object target
- [scripts/main.gd](../../scripts/main.gd) — 394 lines, second target
- [scripts/cannon.gd](../../scripts/cannon.gd) — 19-line marker; expansion target
- [scripts/ship_config.gd](../../scripts/ship_config.gd) — visual variant data (keep)
- [scripts/dash_config.gd](../../scripts/dash_config.gd) — rename target
- [scripts/explosion_config.gd](../../scripts/explosion_config.gd) — rename target
- [scripts/trails.gd](../../scripts/trails.gd) — legacy `.duplicate()` pattern
- [scripts/displacement_stamps.gd](../../scripts/displacement_stamps.gd) — three-API target
- [scripts/enemy_ship.gd](../../scripts/enemy_ship.gd) — Phase 8 target
- [scripts/sea_mine.gd](../../scripts/sea_mine.gd) — 3 timer lambdas
- [scenes/main.tscn](../../scenes/main.tscn) — root scene
- [scenes/ship.tscn](../../scenes/ship.tscn) — Camera child at line 94
- [project.godot](../../project.godot) — no autoloads, InputMap at 26-83
- [CLAUDE.md](../../CLAUDE.md) — project conventions

### Solution docs (institutional learnings)

- [docs/solutions/shared-resource-mutation.md](../solutions/shared-resource-mutation.md)
  — confirmed real: Curve/Gradient/Material mutations leak across instances.
  Reinforces "no `.duplicate()`, no writes to `@export` Resources" doctrine.
- [docs/solutions/godot-shared-mesh-surface-material.md](../solutions/godot-shared-mesh-surface-material.md)
  — `surface_set_material` on shared SphereMesh persists across instances.
  Relevant to explosion refactor.
- [docs/solutions/line2d-round-joint-alpha-gradient-asymmetry.md](../solutions/line2d-round-joint-alpha-gradient-asymmetry.md)
  — wake-trail direction asymmetry bug; fix is `joint_mode = 1` (BEVEL).
  Phase 9 must preserve.
- [docs/solutions/viewporttexture-46-regression.md](../solutions/viewporttexture-46-regression.md)
  — assign ViewportTexture in `_ready()`, not inspector.
- [docs/solutions/subviewport-premultiplied-alpha.md](../solutions/subviewport-premultiplied-alpha.md)
  — water shaders use `render_mode blend_premul_alpha`.

### Existing ADRs

- [docs/decisions/001-water-shader-approach.md](../decisions/001-water-shader-approach.md)
- [docs/decisions/002-prerendered-explosion-atlases.md](../decisions/002-prerendered-explosion-atlases.md)
- [docs/decisions/003-explosion-config-resource.md](../decisions/003-explosion-config-resource.md)
- [docs/decisions/004-dash-overspeed-via-drag-relax.md](../decisions/004-dash-overspeed-via-drag-relax.md)

### External references (none required)

Internal architecture refactor; no new libraries. Godot 4.6.1 stable
(confirmed via `get_project_info`). No Context7 lookups needed.

---

## Appendix A: Optional Simplifications (resolved 2026-04-07)

The simplicity reviewer identified 7 simplifications. The user reviewed and
resolved each after the deepen-plan pass. Final state:

| # | Simplification | Status | Notes |
|---|---|---|---|
| A1 | Fuse `CheatComponent` into `HealthComponent` | **APPLIED** | `OS.is_debug_build()`-guarded input in HealthComponent; emits `Events.cheat_toggled(&"invincibility", _invincible)`. Saves 1 component + 1 ADR. |
| A2 | Fuse `GhostTrailComponent` into `DashComponent` | **APPLIED** | Ghosts only exist during dash; DashComponent spawns them into an injected `ghost_layer: Node2D` under main.tscn. No reparent. Saves 1 component + 1 ADR. |
| A3 | Fuse `HullVariantComponent` into Ship-root listener | **APPLIED** | Ship root connects `HealthComponent.health_changed` → 2-line `_on_health_changed(hp)` method. Saves 1 component + 1 ADR. |
| A4 | Merge `StatsTracker` into `GameState` | **APPLIED** | GameState already owns RunStats; a separate Node-with-no-behavior fails the "managers with no real behavior" test. Drops managers 4 → 3. Revisit if StatsTracker grows real logic. |
| A5 | Demote `AudioManager` autoload to Node under main.tscn | **REJECTED** | AudioManager stays as autoload. Rationale: music persistence across scenes when a game-over-to-new-run flow lands. User kept brainstorm scope. |
| A6 | Defer gamepad per-device remap + `keybinds.cfg` | **REJECTED** | Full gamepad + InputMap remap + keybinds.cfg layer stays in Phase 3 Step 18 as planned. User kept brainstorm scope. |
| A7 | Consolidate 19 ADRs → ~10 | **APPLIED** | Pillar ADRs 005-012 stay separate (each resolves a real alternative). Per-component ADRs merged into one `013-ship-component-decomposition.md` covering all 10 components in one doc. `014-cooldown-helper-timestamp-design.md` added for the non-obvious Cooldown design. Total: 10 ADRs. |

**Applied: A1, A2, A3, A4, A7.** **Rejected: A5, A6.**

---

## Appendix B: Deepened Insights (detailed findings from review agents)

### B.1 — Architecture patterns and anti-pattern gates

**GameState API discipline (pattern review):** The brainstorm's signal-chain
example originally showed `GameState.RunStats.damage_taken += amount`. That's
a field-write-from-outside and creates a service-locator bag anti-pattern.
**Rule:** `GameState` exposes methods only (`record_damage(amount)`,
`record_kill()`, `start_new_run()`) plus read-only getters. External callers
never touch fields. Applied in Step 7 above.

**Bus-for-everything gate:** 20 typed signals is on the edge. **Rule:** any
new `Events.foo` signal requires a `## why:` comment in `events.gd`
justifying why it needs to be global (not a direct connection). Reviewer
rejects PRs that add bus signals without the comment.

**Entity-root re-emit is allowed; component re-emit is not.** Ship root
re-emitting `player_damaged` on the bus after a local `HurtboxComponent.hit_taken`
IS the canonical bridge — not signal bubbling. The original rule wording
("no signal bubbling") was ambiguous. **Rewording:** "components never
touch the bus directly; entity roots (Ship, Enemy, WaveDirector) and
dedicated listener subsystems (VFX, Water, Audio) are the only publishers."
AudioEmitterComponent and HitFeedbackComponent are documented exceptions in ADR 007.

**Events wiring test:** add `tests/unit/test_events_wiring.gd` that boots a
stub scene and asserts every `Events.*` signal has ≥1 listener connected.
Prevents silent listener drop during refactor.

**Camera respawn cleanliness:**
- `position_smoothing_enabled` = reset on respawn signal (`reset_smoothing()`).
- Old Ship-child Camera2D **fully removed**, not just `current = false` —
  leftover cameras silently fight for `current`.
- `set_target(null)` is a valid state; camera holds last position.

### B.2 — Timing and signal safety

**Autoload init invariants:**
- Declaration order: `Events → GameState → AudioManager`.
- No file-scope `preload("res://autoload/*.gd")` — parse-time resolution
  creates cycles. Reference other autoloads only inside `_ready()` or later.
- GameState seeds defaults from `ShipStats.tres` at its own `_ready()`,
  NOT from a deferred `HealthComponent.health_changed` emit. HUD reads
  valid data from frame 0.

**Component `_ready()` timing:**
- Children `_ready()` runs **before** parent's `_ready()` (Godot bottom-up).
- Initial state emission on Ship MUST use `call_deferred("_emit_initial_state")`
  — mirrors today's [ship.gd:94 `_emit_initial_status`](../../scripts/ship.gd#L94).
- Scene declaration order sets sibling `_ready()` order. Declare `Health`
  first, then listeners. Dependency order.

**Respawn signal order:**
- FSM transition → HP reset → single `health_changed` emission.
- `HealthComponent.respawn()` sets `_hp = max_hp` *before* emitting, so
  `HullVariantComponent` never sees an intermediate HP=0 between emissions.

**queue_free safety during bus emission:**
- Any listener iterating a collection where a member might `queue_free()`
  during the emission MUST snapshot first (`list.duplicate()`) and
  `is_instance_valid()` guard.
- Any emit that could trigger reentrancy (mine detonation chains to
  explosion emit) uses `.emit.call_deferred(...)`.
- Applies in Step 36 (mine list iteration) and anywhere the enemy list is
  iterated inside an `enemy_destroyed` handler.

### B.3 — Performance budget

**Default-OFF ticking rule** is the single biggest performance lever. At
13 ship components × (1 player + 12 enemies) = ~170 per-tick callbacks.
Most are purely signal-driven and should call
`set_physics_process(false)` / `set_process(false)` in `_ready()`.
Components that legitimately need ticking:

- `MovementComponent` (physics integration)
- `EnemyAIMovement` (AI tick)
- `HurtboxComponent` — NOT if it relies on Area2D signals (it doesn't
  need to tick; only subscribes to `area_entered`)
- None of the others.

**High-frequency signals bypass the bus.** `displacement_wake_ring_requested`
would fire at 60Hz per entity — routing through `Events` autoload is
wasteful fan-out. Decision: `displacement_*_requested` signals are REMOVED
from the bus; `WaterEffectsManager` exposes direct methods and entity wake
controllers hold a direct injected reference. Updated rule: "Bus signals
are for cross-system events at <10Hz aggregate; per-entity hot-path
requests use direct injected references."

**Affected plan edits:**
- Remove `displacement_impact_requested`, `displacement_wake_ring_requested`,
  `displacement_bob_requested` from the `events.gd` signal list.
- WaterEffectsManager exposes `spawn_impact(pos, radius, strength)`,
  `spawn_wake_ring(pos)`, `spawn_bob(pos, phase)` as public methods.
- Entities (Ship, Enemy, Mine) receive `water_fx: WaterEffectsManager`
  via `setup()` injection at spawn time, call methods directly.
- ADR 007 (Events discipline) explicitly states the <10Hz rule.
- **CONFIRMED USER OVERRIDE of brainstorm resolved question #32** (2026-04-07,
  deepen-plan step): all three displacement signals are direct methods on
  WaterEffectsManager, not bus signals. Brainstorm's three-typed-signals
  rationale is preserved at the method-signature level (typed params,
  no untyped Dictionary). Only the transport changes.

**Wake trail Line2D per-enemy:** move ownership to
`WakeTrailManager` under `features/water/` with
`register(target: Node2D, pivot: Node2D)` / `unregister(target)` API.
Line2D creation block at [main.gd:343-371](../../scripts/main.gd#L343) moves
there verbatim. Preserve the `tree_exiting` cleanup hook or orphaned
Line2Ds leak into the SubViewport.

**SubViewport tracking read:** `WaterEffectsManager._process` (NOT
`_physics_process`) reads ship transform so it picks up interpolated
visual position in the render frame. Add this to the Phase 9 verification
checklist.

**`Area2D.monitoring` toggles** use `set_deferred("monitoring", false)`
to avoid "can't change state during query flush" errors when toggled
from a contact callback.

**`GhostTrailComponent` reparent:** if preserved as a separate component,
call `reset_physics_interpolation()` after reparent or the first frame
lerps from the old parent's transform. Alternative: instantiate ghosts
directly into a dedicated `GhostTrailLayer: Node2D` under `main.tscn`
injected into GhostTrailComponent at spawn — no reparent at all.

### B.4 — Resource safety — expanded doctrine

Added to CLAUDE.md in Step 49:

1. **No writes to fields on `@export var` Resources.** Transitive:
   `stats.weapon_config.damage = 5` is banned.
2. **`set_shader_parameter` on a shared Material is a write.** Either
   `.duplicate()` the material per-instance in `_ready()`, or document
   inline that the write is globally intended (e.g., water DisplacementMap
   wired once from main.gd). Audit happens in Step 34k.
3. **Curve / Gradient mutations banned.** No `curve.add_point()` on an
   `@export`ed Curve.
4. **`@export var foo: FooType`** with NO `preload()` default — assigned
   via scene ExtResource slot. `preload` defaults fight hot-reload and
   hide dependencies.
5. **Component .tscn files must not embed mutable sub-resources.**
   Materials, Curves, Gradients are ExtResources from `resources/`,
   making the shared-vs-per-instance decision explicit at the .tres level.
6. **Every `@export var foo: <Type>` has a matching `assert(foo != null)`
   in `_ready()`.**
7. **Legacy grandfather clause:** `trails.gd` still uses `.duplicate()` on
   `width_curve` — this is fine because the pre-refactor code is mutating
   it. New code must not mutate, so it never needs to duplicate.

**WaveSet shared-reference test** (Step 45): add `test_wave_set_sharing.gd`
that loads a WaveSet referencing `wave_03.tres`, verifies the WaveDirector
does NOT mutate fields on the loaded WaveConfig (e.g., `enemies_remaining`
lives in a WaveDirector Node var, not on the Resource). Failing test
documents the doctrine executably.

### B.5 — Phase 10 move safety (expanded)

**Pre-move grep pass** (new Step 44a): enumerate every literal path
reference that Godot's refactor won't auto-update:
```
Grep: preload\(
Grep: load\(["']res://
Grep: "res://
```
Across all `*.gd` and `*.md` files. Update each in the same commit as the
file move.

**`.uid` sidecar strategy:** use `git mv <file>.gd <file>.gd.uid` for
*both* files in the same commit. Never move via Finder / non-Godot tools
while editor is closed (Godot 4.4 bug #104188 can silently delete `.uid`).
Project is on 4.6.1 (fix landed in 4.5) but the rule still holds.

**Post-move verification** (new Step 44b): after each batch of moves, run
`mcp__godot__update_project_uids` + `mcp__godot__get_debug_output` and
confirm zero errors.

### B.6 — GDScript style additions

- **`StringName` for all enum-like Resource string fields** (`explosion_kind`,
  `fire_sound`, `ai_kind`). Same rule in CLAUDE.md.
- **`enemy_destroyed(enemy: Node, by_mine: bool)`** → `(enemy: Node2D, ...)`
  since enemies are 2D.
- **Member ordering enforcement:** `gdlint` does NOT check member order.
  Code review is the only gate. Add a one-line reminder to Phase 4 preamble
  (above) and to the Step 48 final lint pass.
- **`distance_squared_to`** audit: `_despawn_distant_enemies` at
  [main.gd:388](../../scripts/main.gd#L388) likely uses `distance_to` — use
  squared form with squared threshold.

### B.7 — Updated signal list (supersedes original in Technical Approach)

Apply these deltas to the `events.gd` signal list shown earlier in
Technical Approach:

- `signal sound_requested(sound_id: StringName, pos: Vector2)` — renamed
  from `name` (shadows `Node.name`).
- `signal cheat_toggled(cheat_id: StringName, active: bool)` — renamed.
- **REMOVED:** `signal stat_recorded(key: StringName, value: Variant)`.
- **ADDED:** `signal kill_recorded`, `signal death_recorded`,
  `signal damage_recorded(amount: int)`, `signal wave_time_recorded(index: int, seconds: float)`.
- **ADDED:** `signal camera_zoom_punch_requested(scale: float, duration: float)`
  (already in Enhancement Summary; originally from Research Delta #1).
- **REMOVED from bus** (per B.3 performance): `signal displacement_impact_requested`,
  `signal displacement_wake_ring_requested`, `signal displacement_bob_requested`.
  These become direct methods on `WaterEffectsManager`. **User confirmed
  override of brainstorm resolved question #32** on 2026-04-07.
- `signal enemy_destroyed(enemy: Node2D, by_mine: bool)` — tightened from `Node`.

### B.8 — New research deltas (supplementing #1–12 in the original Research Deltas section)

**#13 — Cooldown ternary bug.** Original `progress()` had
`1.0 - (_remaining / _duration if _duration > 0.0 else 0.0)` — the ternary
binds to `0.0`, returning `1.0 - 0.0 = 1.0` when duration is zero. Fixed in
the timestamp-based rewrite.

**#14 — Cooldown `delta`-scaled incompatible with `Engine.time_scale = 0`.**
Freeze-frame CANNOT use the generic helper (Phase 6 Step 34b/34c).

**#15 — Autoload order unspecified in brainstorm.** Explicit:
`Events → GameState → AudioManager`. Added to Step 6/7/8.

**#16 — `sound_requested(name)` shadows `Node.name`.** Rename to `sound_id`.
Same for `cheat_toggled(name)` → `cheat_id`.

**#17 — `RunStats` referenced in typed signals but never declared as
`class_name`.** Added to Step 9.

**#18 — `stat_recorded(Variant)` defeats typed-bus discipline.** Replaced
with typed per-stat signals.

**#19 — Displacement signals at 60Hz don't belong on the bus.** Moved to
direct injection. Supersedes brainstorm resolved question #32.

**#20 — `set_shader_parameter` on shared Materials is a hidden mutation
surface.** Audit added as Step 34k, 6 production scripts affected.

**#21 — Export `exclude_filter` is empty.** Patch specified in Step 50.

**#22 — `PlayerInput` naming breaks the `*Component` suffix rule.**
Renamed to `PlayerInputComponent`. Table in Phase 4 preamble locks naming.

**#23 — HUD `mine_cooldown_changed` signal persistence across respawn.**
Document in Step 28 that Ship is NOT freed on respawn (current behavior
preserved). If Ship is ever freed, HUD must dynamically reconnect.

**#24 — Mine iteration reentrancy.** Snapshot + `call_deferred` fix in
Step 36.

**#25 — Camera `reset_smoothing()` required on respawn.** Step 19+20.

**#26 — Initial FSM emission must be `call_deferred`.** Step 33.

**#27 — `@export Resource` with no `preload()` default.** Added to doctrine.

**#28 — Embedded sub-resources in component .tscn files banned.** Added to
doctrine.

