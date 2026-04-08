---
title: Deep Codebase Refactor — Maximalist Component Tree
date: 2026-04-07
status: brainstorm
---

# Deep Codebase Refactor — Maximalist Component Tree

## Context

The codebase is ~4,600 LOC of GDScript across 30 scripts and 23 scenes. It was
built rapidly ("100% vibecoded") and has reached a stable, playable base.
The user wants a deep, opinionated refactor *now*, before more features
compound the structural debt.

### Pain points (confirmed)

1. **`ship.gd` is a 548-line god object.** It owns movement, dash, damage,
   iframes, lives, respawn, mine drops, broadside firing, hit feedback,
   camera shake, ghost spawning, hull variants, and a cheat. Player input
   is read directly inside the script (no input layer).
2. **`main.gd` is 394 lines.** It bundles wave management, enemy/mine
   spawning, displacement viewport tracking, wake-trail registration, signal
   wiring, and stats hooks.
3. **Tuning lives in code constants** (wave numbers, ship stats) instead of
   designer-tunable `.tres` Resources.
4. **Test scenes live alongside production scenes** (`dash_fire_test.tscn`,
   `explosion_test.tscn`, `stylized_flame_test.tscn`).
5. **Hand-rolled `get_tree().create_timer()` lambdas** scattered for
   cooldowns, freeze frames, and respawn delays.
6. **Implicit ship state** via flag soup (`_is_dead`, `_input_locked`,
   `_dash_active`, `_iframes_left > 0`, `_invincible`).

### Strengths to preserve

- **No autoloads currently** — all dependencies passed via `setup()` DI.
- Resources used well for `DashConfig`, `ShipConfig`, `ExplosionConfig`.
- ADRs and per-feature plans are already disciplined.
- Project conventions in `CLAUDE.md` are clear (typing, asserts, ordering).

## Goals

- **All four:** foundation for new features, readability, architectural
  rigor, testability.
- **Big-bang on a branch.** Single decisive overhaul.
- **Game scope: keep options open.**
- **Scope acceptance:** 4–6 weeks of focused work, frozen `main` branch.
  All systems below are in scope; no follow-up split.

## What We're Building — Maximalist Component Tree (Approach C)

A component-based scene architecture where ships, enemies, weapons, water,
audio, and input are composed of small, single-responsibility Node
components. Data lives in Resources, behavior lives in Nodes, cross-cutting
events flow through a signal bus, and folder structure follows features.

---

### Architecture pillars

#### 1. Component decomposition

**Player Ship (`features/ship/ship.tscn`):**

```
Ship (CharacterBody2D, ~80 lines orchestrator)
├── PlayerInput              # reads InputMap, exposes axes/buttons
├── MovementComponent        # thrust, turn, friction, brake, collisions
├── DashComponent            # dash impulse, cooldown, freeze frames
├── HealthComponent          # current hp, lives, take_damage(), respawn
├── HurtboxComponent         # Area2D, emits hit_taken
├── BroadsideComponent       # orchestrates port/starboard cannon firing
├── MineDropComponent        # mine cooldown + spawn request
├── HitFeedbackComponent     # flash, hit shake, iframe blink, screen-shake req
├── GhostTrailComponent      # dash ghost spawning
├── HullVariantComponent     # variant sprite swap based on HP (listens to Health)
├── CheatComponent           # invincibility cheat (OS.is_debug_build() only)
├── AudioComponent           # plays SoundConfig clips on local events
├── CannonSlots/
│   ├── PortCannon1 (Cannon component, owns own cooldown)
│   ├── PortCannon2 ...
│   ├── StarboardCannon1 ...
│   └── StarboardCannon2 ...
├── Sprite2D / CollisionShape2D
```

**Communication direction (canonical pattern):**

> Components emit signals upward; Ship root listens and dispatches.

Example: `HurtboxComponent.hit_taken → Ship root → HealthComponent.take_damage(...)`.
Components are pure publishers; the root is the orchestrator. Components
do **not** find each other via groups or unique nodes. This keeps each
component independently testable and avoids hidden coupling.

**Cannons as components, not just markers:**

Each `Cannon` is its own component holding its own per-cannon cooldown,
muzzle marker, and fire logic. `BroadsideComponent` is a thin coordinator
that triggers groups of Cannons (port group, starboard group) on input.
This sets up cleanly for future per-cannon variation (sizes, types,
upgrades).

**Enemy Ship (partial sharing):**

Enemies share the *core* combat components — `HealthComponent`,
`HurtboxComponent`, `BroadsideComponent`, `HitFeedbackComponent`,
`AudioComponent` — so damage and combat behave identically. Movement is
bespoke (`EnemyAIMovement`, single chase-and-shoot strategy for now).
A strategy/swap pattern is **only** introduced when a 2nd archetype
actually exists (YAGNI).

**Cannonball / SeaMine (cohesive scripts + shared components):**

These are small, focused scenes — they stay as cohesive scripts but
*reuse* the shared `HurtboxComponent` and (for mines) `HealthComponent`
where it makes sense. They are NOT decomposed into 4-component trees.

---

#### 2. State machine

A flat enum FSM on the Ship: `{NORMAL, DASHING, IFRAME, DEAD}`. Replaces
the flag soup. Components subscribe to `state_changed` and react (e.g.
`HurtboxComponent` disables itself in IFRAME and DEAD).

Hand-rolled, not an addon — 4 states does not justify ceremony.

---

#### 3. Signal bus (`autoload/events.gd`)

A larger Events autoload (~15–25 signals) for cross-cutting events:

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
signal run_ended(stats: RunStats)

# World / VFX
signal explosion_requested(pos: Vector2, kind: StringName, dir: Vector2, vel: Vector2)
signal screen_shake_requested(trauma: float)
signal mine_dropped(pos: Vector2)
signal cannonball_fired(pos: Vector2, dir: Vector2, by_player: bool)
signal cannonball_water_impact(pos: Vector2)
signal displacement_impact_requested(pos: Vector2, radius: float, strength: float)
signal displacement_wake_ring_requested(pos: Vector2)
signal displacement_bob_requested(pos: Vector2, phase: float)

# Audio
signal sound_requested(name: StringName, pos: Vector2)

# Meta
signal stat_recorded(key: StringName, value: Variant)
signal cheat_toggled(name: StringName, active: bool)
```

**Discipline rules** (enforced by review):
- Bus is for *cross-system* events. Parent↔child communication uses
  direct signal connections inside the same scene.
- **No signal bubbling.** If a component needs to emit to the bus, the
  containing entity (Ship root, Enemy root, etc.) decides — components
  don't touch the bus directly. *Exception:* Audio and VFX subsystems
  whose entire purpose is to listen to bus events.
- Every bus signal documented in one place (`autoload/events.gd`).

---

#### 4. Data-driven Resources (read-only templates, hot-reloadable)

Convert to `.tres`:

- `ShipStats` — max_hp, lives, thrust, turn_rate, drag, broadside_cd,
  mine_cd, respawn_delay, iframe_durations
- `WeaponConfig` — damage, speed, lifetime, explosion_kind, fire_sound
- `EnemyArchetype` — sprite, hp, speed, ai_kind, weapon, score
- `WaveConfig` — spawn_count, enemy_mix, spawn_interval, modifiers
- `WaveSet` — `Array[WaveConfig]` for the campaign
- `SoundConfig` — clip stream, volume, pitch range, polyphony
- (Existing, renamed) `DashStats`, `ExplosionStats`

**Hot-reload pattern (CRITICAL):**

> Components hold a **reference** to the shared Resource. They treat it
> as a read-only template. **No `.duplicate()` at spawn.**
>
> All mutable runtime state (current_hp, current_cooldown, dash_remaining,
> etc.) lives in Node `var`s on the component, **never** on the Resource.

This means editing `ShipStats.tres` in the inspector while the game is
running propagates live to the ship. Field reads happen each time
(`stats.thrust`), no caching of mutable defaults.

**Anti-trap:** Anyone tempted to write `stats.current_hp = ...` is wrong.
Resources are templates; node vars are state. Lint rule: no writes to
fields on `@export var` Resources.

**Wave authoring:** Hand-authored `wave_01.tres` … `wave_NN.tres` in a
`WaveSet`. Each wave hand-tuned. Pre-baked difficulty curve, no procedural
generation. Boss waves and special waves are designable.

**End-of-campaign behavior (NEW FEATURE — small scope expansion beyond
pure refactor):** When the last `WaveConfig` in the active `WaveSet` is
cleared, the game shows a **Victory screen** (a sibling to
`GameOverScreen` that reads from the same `RunStats`). The run is finite.
This converts the current endless arcade into a finite campaign — a
deliberate design shift to be confirmed during planning. Initial
WaveSet length: TBD during planning, suggested 10–15 waves with the
last being a designed "boss wave."

---

#### 5. Camera & spawn point

**Camera2D promoted to its own scene under `main.tscn`.** No longer a
child of Ship.

- Camera reads its target via setter: `camera.set_target(player_ship)`.
  `main.gd` injects on _ready.
- Camera does its own position lerp / smoothing.
- Decouples camera from Ship lifecycle — survives respawn cleanly,
  supports future use cases (boss focus, cinematic pans).
- A `CameraShakeComponent` on the Camera node listens for
  `screen_shake_requested` on the bus and applies trauma-squared offset.

**Spawn point:** A `SpawnPoint` Marker2D node lives in `main.tscn`
(designer-placed). `main.gd` injects it into HealthComponent on _ready.
HealthComponent reads `spawn_point.global_position` on respawn. No
`Ship._spawn_position` magic.

---

#### 6. Input system (PlayerInput component + gamepad)

- `PlayerInput` is a child component of Ship.
- Exposes typed state: `thrust_axis: float`, `turn_axis: float`,
  `fire_port_pressed: bool`, `fire_starboard_pressed: bool`,
  `dash_pressed: bool`, `mine_pressed: bool`, `brake_pressed: bool`.
- Reads from Godot `InputMap` actions — easy to remap.
- **Runtime InputMap remap support** for a future controls menu.
  Bindings save/load to `user://keybinds.cfg`.
- **Gamepad detection layer.** Per-device action bindings. Auto-detect
  controller plug/unplug. Default bindings for keyboard AND gamepad.
- This is broader than YAGNI strictly allows but the user explicitly
  scoped in gamepad support.

---

#### 7. Audio system (AudioManager + SoundConfig + AudioComponent)

- `autoload/audio_manager.gd` — global mixer, listens for `sound_requested`
  on the bus, plays via pooled `AudioStreamPlayer2D` instances.
- `SoundConfig.tres` Resources — clip, volume, pitch range, polyphony,
  spatial flag.
- `AudioComponent` on entities — owns a small dict of named SoundConfigs;
  emits `sound_requested(name, pos)` when local events fire (cannon shot,
  hit, explosion, etc.).
- Music handled directly by `AudioManager` (separate stream player).
- Bus volumes (`Master`, `SFX`, `Music`) saved/loaded with settings.
- **No actual sound files yet.** The system is built empty so the path
  exists for when sounds get added. Components emit; AudioManager logs
  no-ops until clips arrive.

This is explicitly beyond YAGNI strict — user opted in.

---

#### 8. Folder structure

```
project.godot
addons/
  pirate_dev_tools/    # debug overlay + atlas baker as EditorPlugin
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
    configs/   wave_01.tres  wave_02.tres  ...
  hud/
    hud.tscn  hp_display.tscn  lives_display.tscn
    mine_cooldown_display.tscn  wave_toast.tscn  game_over_screen.tscn
    controls_overlay.tscn
  vfx/
    explosion_effect.tscn  dash_fire_effect.tscn
    explosion_atlas_player.gd  explosion_sprite.gd  explosion_stats.gd
    wake_trails.gd  ghost_trail.gd
    vfx_listener.gd      # subscribes to explosion_requested etc.
  water/
    water_chunks.gd  water_chunk_manager.gd
    displacement_stamps.gd
    shaders/   pixel_water.gdshader  ...
    materials/   water_material.tres  ...
    textures/   noise.png  ...
    water_listener.gd    # subscribes to displacement_stamp_requested
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
  dev_README.md          # see "Test scene archival" below
docs/
  brainstorms/  decisions/  plans/  solutions/
  archived/              # thorough MD writeups of deleted test scenes
tests/
  unit/                # damage calc, wave config validation, cooldown, run_stats
  fixtures/
```

`dev/` and `tests/` excluded from export presets. `addons/pirate_dev_tools`
loaded only in editor context.

---

#### 9. Cooldown helper

A `Cooldown` RefCounted in `systems/cooldown.gd` replaces the
`get_tree().create_timer().timeout.connect(lambda)` sprawl:

```gdscript
class_name Cooldown
extends RefCounted
var _remaining: float = 0.0
var _duration: float = 0.0
func tick(delta: float) -> void: _remaining = maxf(0.0, _remaining - delta)
func start(duration: float) -> void: _duration = duration; _remaining = duration
func is_ready() -> bool: return _remaining <= 0.0
func progress() -> float: return 1.0 - (_remaining / _duration if _duration > 0.0 else 0.0)
```

Used inside components instead of scattering lambdas. Unit tested.

---

#### 10. GUT unit tests

Tests cover **pure logic only** — never physics, never rendering:

- `HealthComponent.take_damage` (iframes, death threshold, signal emissions)
- `Cooldown` helper math
- `WaveConfig` / `WaveSet` validation
- `RunStats` accumulation

Lives in `tests/unit/`. GUT addon under `addons/gut/`. Run via
`godot --headless -s addons/gut/gut_cmdln.gd ...`.

---

#### 11. ADRs per component (~11+ total)

Each extracted component gets a `docs/decisions/NNN-<name>-component.md`
ADR explaining: context, decision, alternatives considered, consequences.
This is explicitly maximalist — accepts the documentation overhead.

Plus pillar-level ADRs:
- Component decomposition strategy
- FSM choice (enum vs HSM)
- Events bus discipline
- GameState autoload scope
- Resources hot-reload strategy
- Folder structure (features/)
- Audio architecture
- Input + gamepad architecture

---

#### 12. Dev tools as Godot addons

`addons/pirate_dev_tools/` contains:
- `debug_overlay.gd` — runtime perf/state overlay
- `explosion_atlas_baker.gd` — pre-bake explosion sprite atlas tool
- `dash_fire_tuning_panel.gd` — live tuning panel for dash flame
- `plugin.cfg` + `plugin.gd`

Properly registered as `EditorPlugin` instances. Available via Godot's
Project menu / dock. Not shipped with the game.

---

#### 13. Test scene archival ("document well, then delete")

Existing `dash_fire_test.tscn`, `explosion_test.tscn`,
`stylized_flame_test.tscn` are scratchpads from earlier vibecoding. Their
job is done.

Process:
1. For each test scene, write a **thorough markdown writeup** in
   `docs/archived/<name>.md` covering:
   - Purpose (what was being tuned/explored)
   - Setup (key parameters, expected behavior)
   - Findings (what numbers worked, what didn't)
   - Screenshots (capture before deletion)
2. Then delete the `.tscn` and any test-only `.gd`.
3. Note in `dev/dev_README.md` that historical tests live in `docs/archived/`
   and the git history.

---

## Refactor Sequencing (Big-Bang Branch, ~30–50 commits)

Order minimizes broken-game time. **Game must launch after every numbered
sub-step.** One commit per sub-step.

### Phase 0 — Safety net
1. Branch `refactor/component-architecture`. Freeze `main` (no commits).
2. Record a 60–90s "known good" gameplay video as visual baseline that
   covers: spawn, full first wave, dash, take damage, blink iframes,
   die once, respawn, second wave, water shader at speed, mine drop,
   game over. This becomes the regression reference for every phase.
3. Confirm `gdformat --check .` and `gdlint .` pass on main; if they
   don't, fix them on main BEFORE branching (refactor cannot be the
   thing that introduces lint discipline AND tears apart code at once).
4. Install GUT addon (`addons/gut/`) with empty `tests/unit/` skeleton.

### Phase 1 — Quick wins
5. Document then delete test scenes (one MD writeup per scene).
6. Add `Events` autoload with all signals declared (empty bodies).
7. Add `GameState` autoload (current wave/score/lives, RunStats).
8. Add `AudioManager` autoload (no-op until clips exist).
9. Add `Cooldown` helper + unit test.
10. Add `SpawnPoint` Marker2D to main.tscn.

### Phase 2 — Resources first (data, no behavior change)
11. Create `ShipStats.tres` (read by current ship.gd, no other change).
12. Create `WeaponConfig.tres` (read by cannon.gd / sea_mine.gd).
13. Create `EnemyArchetype.tres` (read by enemy_ship.gd).
14. Create `WaveConfig.tres` + `WaveSet.tres` + first hand-authored waves.
15. Rename `DashConfig` → `DashStats` (plain text replace + run game + fix).
16. Rename `ExplosionConfig` → `ExplosionStats` (same).

### Phase 3 — Input + camera promotion
17. Extract `PlayerInput` component. Ship reads from it.
18. Add InputMap remap support + gamepad detection layer.
19. Promote `Camera2D` to its own scene under main. Inject ship target.
20. Move camera shake to `CameraShakeComponent` listening to bus.

### Phase 3.5 — Victory screen (small new feature)
20a. Create `VictoryScreen.tscn` as a sibling of `GameOverScreen.tscn`,
     reading from the same `RunStats`. Wire `WaveDirector` to emit
     `run_ended` with a `victory: bool` flag (or use a new `run_victory`
     bus signal) when the last `WaveConfig` clears. main.gd routes to the
     correct screen.

### Phase 4 — Ship component extraction (one component per commit)
21. `HealthComponent` (cleanest boundary; reads from spawn point)
22. `HurtboxComponent`
23. `HitFeedbackComponent` (flash + hit shake + iframe blink + shake req)
24. `MovementComponent`
25. `DashComponent`
26. `Cannon` component (per-cannon cooldown)
27. `BroadsideComponent` (orchestrator)
28. `MineDropComponent`
29. `GhostTrailComponent`
30. `HullVariantComponent`
31. `CheatComponent` (`OS.is_debug_build()` guard)
32. `AudioComponent` (emits sound_requested on local events)

After each: launch, play one wave, die, respawn, verify. Commit.

### Phase 5 — Ship FSM
33. Replace flag soup with enum FSM. Components subscribe to `state_changed`.

### Phase 6 — Replace timer lambdas
34. Replace `get_tree().create_timer()` lambdas with `Cooldown`
    one-by-one (broadside, mine, dash, respawn, freeze frames). One commit
    per replacement.

### Phase 7 — main.gd decomposition
35. Extract `WaveDirector` (state machine, spawn cadence, reads WaveSet).
36. Extract `SpawnService` (instantiates enemies/mines, registers wakes).
37. Extract `StatsTracker` (listens to bus, updates GameState.RunStats).
38. Extract `WaterEffectsManager` (displacement viewport, wake trails).

### Phase 8 — Enemy decomposition
39. `EnemyShip` reuses Health, Hurtbox, Broadside, HitFeedback, Audio.
40. `EnemyAIMovement` extracted as bespoke movement component.

### Phase 9 — VFX + Water listeners
41. `vfx_listener.gd` subscribes to `explosion_requested` /
    `screen_shake_requested`. Wraps existing `ExplosionSprite.create()`.
42. `water_listener.gd` subscribes to the three typed displacement
    signals (`displacement_impact_requested`,
    `displacement_wake_ring_requested`, `displacement_bob_requested`).
43. Full water subsystem refactor: `WaterChunkManager`, water folder
    consolidation, water tuning Resources. **High visual-regression risk.**
    Verification checklist for this step:
    - Spawn ship; wake rings appear at correct cadence.
    - Cannonball impacts produce displacement at correct radius.
    - Mine bob displacement reads identically to baseline.
    - Compare side-by-side video with the Phase 0 baseline at the same
      ship speed.
    - Verify the shared `DisplacementMap` SubViewport texture is still
      wired to all water chunks (the most-likely regression site).

### Phase 10 — Folder reorganization
44. Move all files into `features/`, `assets/`, `systems/`, `autoload/`,
    `main/`, `dev/`, `addons/`. Update preloads. UID files travel with
    scripts. Big mechanical diff. **Also update `docs/solutions/*.md`**
    to reflect new file paths (e.g.
    `shared-resource-mutation.md` and
    `line2d-round-joint-alpha-gradient-asymmetry.md` reference current
    paths that will move).

### Phase 11 — Tests + ADRs + cleanup
45. Write GUT tests for HealthComponent, Cooldown, WaveConfig, RunStats.
46. Write per-component ADRs (~11) and pillar-level ADRs (~8).
47. Convert dev tools to `addons/pirate_dev_tools/` EditorPlugin.
48. Final lint pass, dead code removal, doc index update.
49. Update `CLAUDE.md` to reflect new conventions and folder structure.
50. Verify export build excludes `dev/`, `tests/`, dev addons. Compare
    build size vs baseline.

---

## Merge Criteria (Definition of Done)

The branch merges only when **all** are true:
- ✅ Game plays end-to-end identically to the pre-refactor video baseline
  (waves spawn, ship dies, respawns, game over screen shows correct stats).
- ✅ `gdformat --check .` passes on the entire tree.
- ✅ `gdlint .` passes on the entire tree.
- ✅ All GUT unit tests pass.
- ✅ `ship.gd` is under 100 lines.
- ✅ `main.gd` is under 100 lines.
- ✅ Editing `ShipStats.tres` in the inspector while running propagates
  live to the ship (hot-reload sanity check).

---

## Key Decisions (Consolidated)

### Architecture
1. **Component tree over inheritance.** Hull variants are sprite swaps via
   `ShipStats`, never subclasses.
2. **Components emit, root dispatches.** No group-finding, no scene-unique
   cross-references. Pure publish/orchestrate pattern.
3. **Flat enum FSM** on Ship: `{NORMAL, DASHING, IFRAME, DEAD}`. No HSM.
4. **Signal bus is large but disciplined.** ~15–25 signals; components don't
   touch the bus directly (except VFX/Audio listeners).
5. **Partial enemy decomposition.** Health/Hurtbox/Broadside/HitFeedback/
   Audio shared with player; movement is bespoke.
6. **Cannons are components**, each with own cooldown. BroadsideComponent
   orchestrates groups.
7. **Cannonball/SeaMine stay as cohesive scene scripts** but reuse
   Hurtbox/Health where natural.

### Data
8. **Resources are read-only templates.** Components hold a *reference*
   (no `.duplicate()`); mutable runtime state is in Node vars. Enables
   live hot-reload from inspector.
9. **Hand-authored WaveConfigs** per wave, no procedural generation.
10. **Resource renames:** `DashConfig` → `DashStats`,
    `ExplosionConfig` → `ExplosionStats` (plain text replace + verify).

### Subsystems
11. **GameState autoload** owns current wave/score/lives + RunStats.
12. **Camera promoted** to own scene under main; reads target via setter;
    survives respawn.
13. **Spawn point** is a Marker2D in main.tscn injected into HealthComponent.
14. **CameraShakeComponent** on Camera listens to bus for shake events.
15. **VFX flows through the bus.** `explosion_requested`,
    `screen_shake_requested`. `vfx_listener.gd` wraps existing factory.
16. **Water subsystem fully refactored** into `features/water/`. Highest
    visual regression risk; tested carefully.
17. **Full audio system** built empty: AudioManager autoload + SoundConfig
    Resources + AudioComponent on entities.
18. **Full input system:** PlayerInput component + InputMap remap support
    + gamepad detection.

### Tooling / Discipline
19. **Cooldown helper** replaces all timer lambdas.
20. **GUT** for pure logic only (4 suites).
21. **ADR per component** (~11) + pillar ADRs (~8).
22. **Dev tools as Godot addons** in `addons/pirate_dev_tools/`.
23. **CheatComponent guarded** by `OS.is_debug_build()`.
24. **Test scenes documented thoroughly in MD then deleted.**
25. **`features/` folder reorg happens LATE** (Phase 10) — code settles first.
26. **`assets/` folder reorg** consolidates `shaders/`, `textures/` under
    `assets/` (water shaders are an exception — they live with the water
    feature).
27. **One commit per sub-step** in the 50-step plan.
28. **Freeze `main` branch** during the 4–6 week refactor window.

---

## YAGNI Traps to Watch For

The research explicitly warned about these. Approach C inherently flirts
with several. If we catch ourselves doing them, stop and reconsider:

- **Manager proliferation.** The 4 main-decomposition managers
  (WaveDirector, SpawnService, StatsTracker, WaterEffectsManager) are the
  cap. No `EnemyManager`, `EffectManager`, `GameManager`.
- **Signal bubbling.** Components must NOT touch the bus directly. The
  Ship/Enemy root decides what to publish. (Exception: VFX/Audio listener
  subsystems whose entire job is bus traffic.)
- **Premature ECS.** Godot's node tree IS the ECS. No custom entity
  registry, no system iterator.
- **Interface simulation.** No empty `IDamageable` base classes.
- **Object pooling.** GDScript is reference-counted. Skip unless profiler
  proves the need.
- **Service locator autoloads.** Use scene tree / groups / signals, not
  `Services.get_ship()`.
- **Dynamic `load(path)` with string concatenation.** Grep-invisible.
  Use preload dicts or typed consts.
- **Tests for everything.** Pure logic only. ~4 suites total.
- **HSM addon.** Hand-rolled enum is enough.
- **Resource over-nesting.** No `WaveConfig → SubWaveConfig → EnemyGroup`
  doll. Flat arrays.
- **Hot-reload race conditions.** Live-edited Resources change underfoot.
  Components must not cache mutable values from Resources between frames.

---

## Scope Expansions Beyond Pure Refactor

The user has explicitly approved scope items that go beyond a structural
refactor. Listed here so planning can checkpoint each one:

1. **Audio system** — full AudioManager + SoundConfig + AudioComponent +
   bus signal, with **zero current sound clips**. Built empty.
2. **Gamepad input layer** — runtime gamepad detection + per-device
   bindings, with **zero current gamepad users** and no controls menu.
3. **Runtime InputMap remap support** — bindings save/load to
   `user://keybinds.cfg`, with **no controls menu yet**.
4. **Victory screen + finite campaign** — converts the current endless
   arcade into a finite WaveSet with a victory ending. NEW gameplay
   feature, not just refactor.
5. **Per-component ADRs** (~11 docs) + per-pillar ADRs (~8 docs).

These are confirmed in scope but each is a YAGNI risk. If the refactor
runs long, this list is the first place to cut.

## Resolved Questions (all)

1. **Component naming:** file `health.gd`, `class_name HealthComponent`,
   node name `Health`.
2. **VFX routing:** Through the bus.
3. **GameState autoload:** Yes — owns run state + RunStats.
4. **`RunStats`:** Lives inside `GameState` autoload.
5. **`CheatComponent`:** Guarded by `OS.is_debug_build()`.
6. **Resource renaming:** `DashConfig`/`ExplosionConfig` →
   `DashStats`/`ExplosionStats`.
7. **Asset reorg:** Yes — `shaders/`/`textures/` under `assets/` (water
   shaders excepted, they live with the water feature).
8. **Branch policy:** Freeze `main`.
9. **Component communication:** Components emit; Ship root listens &
   dispatches.
10. **Persistence:** In-memory only (no save/load yet).
11. **Camera ownership:** Promoted to own scene under main; injected target.
12. **Hull-variant sprite logic:** `HullVariantComponent` listens to
    `Health.health_changed`.
13. **Camera follow:** Setter-injected target on the Camera scene.
14. **Cannons:** Each is its own component with its own cooldown.
    `BroadsideComponent` triggers groups.
15. **Enemy AI variation:** Single chase-and-shoot for now. Strategy
    pattern only when a 2nd archetype exists.
16. **Iframe blink:** Lives in `HitFeedbackComponent`.
17. **Hot-reload:** Components hold references; runtime state in Node vars;
    no `.duplicate()`.
18. **Class rename strategy:** Plain text replace + run game + fix breaks.
19. **Merge criteria:** Gameplay parity + lint + GUT (no build size gate).
20. **ADR scope:** Per component (~11) + per pillar (~8).
21. **Water folder:** `features/water/` — full subsystem refactor.
22. **Commit cadence:** One commit per sub-step (~30–50 total).
23. **Audio scope:** Full AudioManager + SoundConfig + AudioComponent
    (built empty).
24. **Input scope:** PlayerInput + InputMap remap + gamepad layer.
25. **Spawn point:** Marker2D in main.tscn, injected.
26. **Test scene archival:** Thorough MD docs in `docs/archived/`, then
    delete.
27. **Cannonball/SeaMine:** Cohesive scripts, share components naturally.
28. **Water refactor scope:** Full subsystem refactor.
29. **Dev tools:** `addons/pirate_dev_tools/` as EditorPlugin.
30. **Total scope acceptance:** 4–6 weeks, frozen main, do it all.
31. **Past last wave:** Game ends with a Victory screen. Finite campaign.
32. **`displacement_stamp_requested` signal:** Split into three typed
    signals (`displacement_impact_requested`,
    `displacement_wake_ring_requested`, `displacement_bob_requested`).
    No untyped Dictionary on the bus.

## Open Questions

(none — all resolved before planning)

## Success Criteria

After the refactor:
- `ship.gd` is under 100 lines.
- `main.gd` is under 100 lines.
- Adding "homing torpedo weapon" requires creating `torpedo.tscn` +
  `torpedo_config.tres` + a wave entry. No edits to ship.gd, main.gd, or
  any manager.
- All wave/ship/enemy/sound tuning is editable in the Godot inspector
  via `.tres`.
- Live editing `ShipStats.tres` while the game runs propagates to the
  ship without restart.
- `dev/`, `tests/`, and dev addons excluded from exports.
- `gdformat --check` and `gdlint` pass on the entire tree.
- 4 GUT unit suites pass.
- ADRs exist for each component decision and architectural pillar.
- Player can rebind keys at runtime; gamepad works on plug-in.
