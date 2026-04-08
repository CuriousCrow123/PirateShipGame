<!-- verified against commit 090ed90 on 2026-04-08 -->

# VERIFY — manual recheck pass

Run through this list after any structural refactor. If a line fails,
fix the architecture doc it points to, then bump the
`verified against commit` stamp at the top of that file. The whole
pass is ~10 minutes.

**Failure is the signal, not the goal** — the docs are allowed to
lag refactors by one session, not by five.

## Scene tree + wiring

- [ ] [main/main.tscn](../../main/main.tscn) root is `Node2D`, script
  is [main/main.gd](../../main/main.gd).
- [ ] `Main` has a `Ship` child instanced from
  [features/ship/ship.tscn](../../features/ship/ship.tscn) with
  `@export var stats` pointing at
  `features/ship/stats/default_ship_stats.tres`.
- [ ] `Main` has these sibling service Nodes: `WaveDirector`,
  `SpawnService`, `StatsTracker`, `WaterEffectsManager`,
  `VfxListener`, `WaterListener`, `GameCamera`.
- [ ] [main/main.gd](../../main/main.gd) `_ready()` calls:
  `_water_effects.setup(...)`, `_spawn_service.setup(...)`,
  `_wave_director.setup(...)`, and `.connect()`s `Ship.cannon_fired`,
  `Ship.mine_dropped`, `Ship.died`, `Ship.respawned`,
  `Ship.game_over`, plus `WaveDirector.spawn_requested` →
  `SpawnService.spawn_wave_enemy`.
- [ ] `main.gd` still has `_on_ship_respawned()` calling
  `_camera.snap_to_target()`.

## Autoloads

- [ ] [project.godot](../../project.godot) autoload order is
  `Events → GameState → AudioManager → KeybindsManager` (no
  reordering, no new entries without updating
  [02-autoloads-and-signals.md](02-autoloads-and-signals.md)).
- [ ] [autoload/events.gd](../../autoload/events.gd) signals remain
  grouped under the comment banners `--- Combat ---`,
  `--- Waves ---`, `--- World / VFX ---`, `--- Water displacement ---`,
  `--- Audio ---`, `--- Meta / stats ---`.
- [ ] `sound_requested` still carries `sound_id: StringName` (not
  `name`).
- [ ] `cheat_toggled` still carries `cheat_id: StringName` (not
  `name`).

## Ship + components

- [ ] [features/ship/ship.gd](../../features/ship/ship.gd) is
  `class_name Ship`, `extends CharacterBody2D`.
- [ ] Nine components exist in
  [features/ship/components/](../../features/ship/components/):
  `health`, `hurtbox`, `hit_feedback`, `movement`, `dash`,
  `player_input`, `broadside`, `mine_drop`, `audio_emitter`. Plus
  `cannon.gd` under the marker tree and `dash_stats.gd` (a Resource,
  not a component).
- [ ] `ShipFSM` still lives at
  [features/ship/ship_fsm.gd](../../features/ship/ship_fsm.gd) — one
  level up from `components/`, because it is the entity's state
  backbone, not a sibling verb. It's the 10th "component" in the
  table in
  [03-entities-and-components.md](03-entities-and-components.md).
- [ ] `HurtboxComponent` still `extends Node2D`. **Regression check**:
  if it reverts to plain `Node`, its child `Area2D` will strand at
  world origin and the game will silently stop taking damage.
- [ ] `ShipFSM` state enum is `{ NORMAL, DASHING, IFRAME, DEAD }` (no
  boolean `is_invincible` field).
- [ ] `HitFeedbackComponent` is still the only component that
  publishes `Events.screen_shake_requested` directly.
- [ ] `AudioEmitterComponent` is still the only component that
  publishes `Events.sound_requested` directly.

## Damage path

- [ ] `Ship.take_damage(dir, amount)` still routes through
  `HurtboxComponent.process_hit` → `hit_taken` → `_apply_damage` →
  `HealthComponent.apply_damage`. The Mermaid sequence diagram in
  [02-autoloads-and-signals.md](02-autoloads-and-signals.md) reflects
  the actual flow.
- [ ] `HurtboxComponent.process_hit` still filters by
  `ShipFSM.is_vulnerable()`.

## Resources

- [ ] The Resource catalog table in
  [04-resources-and-vfx.md](04-resources-and-vfx.md) lists every
  `extends Resource` script in the project — no orphans, no stale
  entries. Run `grep -rln "extends Resource" features/ systems/` to
  cross-check.
- [ ] No runtime code writes to a top-level `@export var` Resource
  field (ADR 009). Spot-check with
  `grep -rn "stats\.\(thrust\|turn_speed\|drag\|brake\) =" features/`.
- [ ] The only surviving `.duplicate()` of a Resource is in
  [features/water/trails.gd](../../features/water/trails.gd) on
  `width_curve`. Any new hit means either a new legacy carve-out (add
  to ADR 009) or a new bug.

## ADRs

- [ ] [docs/decisions/](../decisions/) contains ADRs 001–014 with no
  gaps and no duplicates.
- [ ] The architecture index [README.md](README.md) ADR-map paragraph
  references every ADR at least once.
- [ ] No "ERRATA" or "SUPERSEDED" tags in the ADRs have been added
  without a matching note in the architecture README ADR map.

## Tests

- [ ] [tests/unit/](../../tests/unit/) contains `test_cooldown.gd`,
  `test_health_component.gd`, `test_run_stats.gd`,
  `test_wave_config.gd`, `test_wave_set_sharing.gd`. Add new suites
  here — no other test path.
- [ ] `gut -gdir=res://tests/unit -gexit` is still green.

## Export + Pages deploy

- [ ] [export_presets.cfg](../../export_presets.cfg) preset 0 is
  `name="Web"`, `export_path="build/web/index.html"`,
  `variant/thread_support=false`,
  `exclude_filter` strips `addons/gut`, `addons/pirate_dev_tools`,
  `tests/`.
- [ ] `.github/workflows/deploy-pages.yml` still exists and still
  references Godot `4.6.1` + `chickensoft-games/setup-godot@v2`.

## After a pass

If every checkbox is ticked, bump the `verified against commit` stamp
at the top of each touched file to the current `HEAD` sha and the
current date. If something failed, fix it first and re-run the pass.
