<!-- verified against commit 090ed90 on 2026-04-08 -->

# 04 — Resources and VFX

## What you'll know after reading this

- Every gameplay-tuning `Resource` in the project and what it owns.
- The Resource doctrine from ADR 009 in onboarding voice — three
  hazards and how components avoid them.
- Which components live-reload from Resource edits and which cache
  values at `setup()` time.
- Where to look for the water shader, wake trail, and explosion atlas
  pipelines (with a single canonical pointer each — no duplication).

## Resource catalog

All of these `extends Resource` and are consumed via `@export var`
slots on their host Node. Ground-truth files are linked inline; the
values in the `.tres` under each folder are the shipped tuning.

| Resource | File | Used by | Owns |
|---|---|---|---|
| `ShipStats` | [features/ship/ship_stats.gd](../../features/ship/ship_stats.gd) | `Ship`, `MovementComponent` | thrust, turn speed, drag, brake, broadside/mine cooldown, max_health, max_lives, respawn_delay |
| `ShipConfig` | [features/ship/ship_config.gd](../../features/ship/ship_config.gd) | `Ship` | hull / sail sprite variant, which cannon slots are active |
| `DashStats` | [features/ship/components/dash_stats.gd](../../features/ship/components/dash_stats.gd) | `DashComponent` | dash `feel_mode`, impulse speed, duration, cooldown, flame brightness, intensity curve |
| `WeaponConfig` | [features/weapons/weapon_config.gd](../../features/weapons/weapon_config.gd) | `Cannonball`, `SeaMine` | damage, speed, lifetime, `explosion_kind: StringName`, `fire_sound: StringName` |
| `EnemyArchetype` | [features/enemies/enemy_archetype.gd](../../features/enemies/enemy_archetype.gd) | `EnemyShip` | hp, chase/circle/turn speed, circle radius, broadside cooldown + range |
| `WaveConfig` | [features/waves/wave_config.gd](../../features/waves/wave_config.gd) | `WaveDirector` | enemies_to_spawn, max_concurrent, spawn_interval, `speed_mult`, `cooldown_mult`, intermission_duration |
| `WaveSet` | [features/waves/wave_set.gd](../../features/waves/wave_set.gd) | `WaveDirector` | Array of `WaveConfig`; `get_wave(i)`, `is_final_wave(i)` |
| `ExplosionStats` | [features/vfx/explosion_stats.gd](../../features/vfx/explosion_stats.gd) | `ExplosionEffect` / `ExplosionAtlasPlayer` | per-kind (`muzzle_flash`, `cannonball_impact`, `enemy_destruction`, `sea_mine`) particle params + atlas refs |
| `WaterTuning` | [features/water/water_tuning.gd](../../features/water/water_tuning.gd) | `WaterEffectsManager` | wake ring spacing, speed threshold, wake strength mapping, impact radius/duration, mine bob scale |
| `RunStats` | [systems/run_stats.gd](../../systems/run_stats.gd) | `GameState`, `StatsTracker` | kills, deaths, damage_taken, elapsed, waves cleared, wave_times |

And one non-`Resource` helper used throughout cooldown logic:

- `Cooldown` — [systems/cooldown.gd](../../systems/cooldown.gd) —
  timestamp-based `RefCounted`, wall-clock (unaffected by
  `time_scale`), ADR 014.

## Resource doctrine — three hazards (ADR 009)

Resources are **read-only templates**. Runtime state lives in Node
`var`s, never on Resources. There are three failure modes this rule
guards against:

### Hazard 1 — writing to `@export var` Resource fields

```gdscript
# ILLEGAL
ship.stats.damage = 5
ship.stats.weapon_config.damage = 5  # transitive — still a Resource
```

Both of the above mutate a shared `.tres` and leak into every ship
loaded from the same file. If you need per-instance damage scaling,
the value lives on the Node, not the Resource. **The transitive case
is the easy one to miss** — drilling through one Resource into another
Resource is still a Resource write.

### Hazard 2 — `set_shader_parameter` on a shared Material

`Material` is a `Resource`. Calling `set_shader_parameter` on a
material loaded from a `.tres` mutates the shared instance — every
other consumer of that material gets the write too. Either call
`.duplicate()` in `_ready()` for per-instance state, or explicitly
document that the write is globally intended (the water
`DisplacementMap` uniform wired once from `main.gd` is the only
current "globally intended" case).

### Hazard 3 — mutating `Curve` / `Gradient` sub-resources

`curve.add_point(...)` on an `@export`ed `Curve` is banned by the
same rule. The single legacy survivor is
[features/water/trails.gd](../../features/water/trails.gd), which
`.duplicate()`s `width_curve` because the pre-refactor code mutates
it in place. New code must never mutate — if it never mutates, it
never needs to duplicate.

Point 5 of ADR 009 follows from the above: **component `.tscn` files
must not embed mutable sub-resources inline**. Materials, curves, and
gradients are `ExtResource` references from the feature's own folder,
which makes the shared-vs-per-instance decision explicit at the
`.tres` level.

## Hot-reload granularity

Some components re-read Resource fields every frame, which means
inspector edits live-update during play. Others cache at
`setup()` / `_ready()` time and require a scene restart to pick up
changes. This is **by design**, not a bug:

| Live-reloads from inspector | Caches at setup (restart to see changes) |
|---|---|
| `MovementComponent` reads `ShipStats.thrust`, `turn_speed`, `drag` per frame | `HealthComponent._max_health` captured once |
| `WaterEffectsManager` reads `WaterTuning.*` per frame | `BroadsideComponent._cooldown_duration` captured once |
| `DashComponent` re-reads `DashStats` on each dash start | `WaveDirector` caches `WaveSet` at boot |

When tuning a stat mid-run, check this table first. If the stat you
edited isn't live, restart the scene — it's not a bug, it's the
ADR-9 contract.

## `@export` patterns and assertion gates

Every `@export var foo: <Type>` has a matching `assert(foo != null,
"<host>: <field> unset")` in `_ready()` — you'll see this at the top
of every component. Same goes for `@onready` node references. The
assertion gate catches forgotten inspector slots at the point of
failure instead of letting a null propagate three frames later into a
cryptic `Invalid call` in `_process`.

**No `preload()` default on `@export`.** The pattern is:

```gdscript
@export var stats: ShipStats        # good — scene assigns ExtResource
@export var stats: ShipStats = preload("res://...")  # bad — hides dependency
```

`preload()` defaults fight hot-reload and make it impossible to see at
the scene-file level which Resource a node is actually consuming.

## Water pipeline — one paragraph and one link

The canonical deep dive for the water / wake / displacement shader
pipeline is [docs/pixel-water-shader-reference.md](../pixel-water-shader-reference.md).
**Do not re-explain the shader here** — the reference document is the
single source of truth and lives next to this file. One-paragraph
summary: `ChunkContainer` streams a 3×3 grid of water-tile chunks
around the ship using
[features/water/water_chunk_manager.gd](../../features/water/water_chunk_manager.gd);
the wake trail is a `Line2D` rendered into a `SubViewport` by
[features/water/trails.gd](../../features/water/trails.gd);
`DisplacementViewport/SubViewport/Stamps` draws displacement stamps
(cannonball impacts, wake rings, mine bob) into a second `SubViewport`
that the water shader samples as a `DisplacementMap` uniform. The
`WaterEffectsManager` Node owns the timing/gating and publishes the
displacement events; the `WaterListener` autoload-adjacent Node
converts those events into `Stamps.draw_*` calls. See `ADR 001` for
why the shader is handwritten GDShader code rather than VisualShader.

## Explosion / VFX pipeline

Explosions are **pre-rendered sprite atlases** (ADR 002) rather than
real-time 3D GPU particles. The atlas build tool lives at
[addons/pirate_dev_tools/explosion_test.gd](../../addons/pirate_dev_tools/explosion_test.gd)
(editor-only, not shipped in exports — see
[export_presets.cfg](../../export_presets.cfg) `exclude_filter`). At
runtime, `VfxListener` subscribes to `Events.explosion_requested(pos,
kind, dir, vel)` and spawns either an `ExplosionAtlasPlayer` sprite
or (debug-toggle via `Shift+9` → `toggle_explosion_mode`) a 3D model
version — the `ExplosionSprite.use_sprite` boolean toggled in
`main.gd:70` flips between them.

All per-kind tuning lives in
[features/vfx/explosion_stats.tres](../../features/vfx/explosion_stats.tres)
(the `ExplosionStats` Resource above). Four kinds are shipped:
`muzzle_flash`, `cannonball_impact`, `enemy_destruction`, `sea_mine`.
Adding a new kind = add a new sub-Resource slot on `ExplosionStats` +
emit the new `StringName` from wherever you want it to fire.

## `stylized_flame_snapshot.json`

[features/vfx/stylized_flame_snapshot.json](../../features/vfx/stylized_flame_snapshot.json)
is a baked preset dump from the `stylized_flame_test` editor plugin —
captured profile values for the dash flame lathe/sphere. Treat it as
authored content, not generated junk. If you re-tune the flame via
the editor plugin, re-export and commit the updated snapshot.

## What to read next

- **The architecture tour start point** →
  [README.md](README.md).
- **If you're refactoring and want the shader deep dive** →
  [docs/pixel-water-shader-reference.md](../pixel-water-shader-reference.md).
- **If you need the original decision rationale** → `ADR 009`
  (`docs/decisions/009-resources-hot-reload-strategy.md`) and
  `ADR 002` (explosion atlases).
