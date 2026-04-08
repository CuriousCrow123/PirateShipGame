# PirateShipGame — Project Conventions

## Language & Engine

- Godot 4.6, Forward+ renderer
- GDScript (no C#)

## Display Settings

- Viewport: 640x360
- Window: 1280x720 (2x integer scale)
- Stretch mode: `viewport`, scale: `integer`
- Default texture filter: `Nearest`
- Pixel snapping: enabled (`snap_2d_transforms_to_pixel`, `snap_2d_vertices_to_pixel`)

## Folder Structure

```
addons/         — vendored third-party (GUT) + first-party EditorPlugins
                  (pirate_dev_tools — editor-only authoring scenes)
assets/         — shared textures, fonts (cross-feature)
autoload/       — Events, GameState, AudioManager, KeybindsManager
                  (registered in this order; see ADR 008)
docs/           — plans, decisions (ADRs), brainstorms, solutions
features/       — feature folders (camera/, enemies/, hud/, ship/,
                  vfx/, water/, waves/, weapons/) — each owns its
                  scripts, scenes, resources, textures, shaders
main/           — main.tscn + main.gd (the run/main_scene)
systems/        — cross-feature RefCounted helpers (Cooldown,
                  RunStats) and service Nodes (SpawnService,
                  StatsTracker) that aren't owned by a single feature
tests/          — GUT unit tests (gut -gdir=res://tests/unit -gexit)
```

Plus top-level config: `CLAUDE.md`, `export_presets.cfg`, `gdlintrc`,
`icon.svg`, `project.godot`.

**Inclusion criteria** for `systems/` (ADR 010): cross-feature helpers
and service Nodes that aren't owned by a single feature. If a file
would have to live in at least two `features/<x>/` folders to not be
the odd one out, it belongs in `systems/`.

**Components live with their host entity, not by class role**. Cannon
lives in `features/ship/components/` even though Cannonball is in
`features/weapons/`, because cannons attach to ship entities. EnemyShip
reusing the same `cannon.tscn` is fine.

## GDScript Conventions

### Static typing
- All variables, parameters, and return types must be typed.
- `@export var` slots are typed; component `setup()` args are typed.

### Component pattern (ADR 005, 013)
- Components are `Node` subclasses under an entity root, one verb each.
- **Exception**: components whose behavior depends on the entity's 2D
  transform chain MUST `extends Node2D`. Plain-`Node` parents silently
  strand `CanvasItem` children at world origin (the post-Phase-10
  HurtboxComponent hot-fix). When in doubt, `extends Node2D` —
  Transform2D overhead is negligible.
- Components emit signals upward to the entity root; never reach
  sideways to siblings.
- **Default-OFF**: every component calls `set_physics_process(false)`
  and `set_process(false)` in `_ready()` unless it proves it needs
  ticking. MovementComponent, ShipFSM (iframes), and MineDropComponent
  (HUD publish) are the current exceptions.

### Member ordering
Follow GDScript style guide: signals, enums, constants, exports, vars,
`_ready`, `_process`, public methods, private methods. **gdlint does
NOT check member order — code review is the only gate.**

### Assertions on @export
Every `@export var foo: <Type>` has a matching `assert(foo != null)`
in `_ready()`. Same for `@onready` node references — validate in
`_ready()` with clear messages.

## Resource Safety Doctrine (ADR 009)

Resources are **read-only templates**. Runtime state lives in Node
`var`s, never on Resources.

1. **No writes to fields on `@export var` Resources.** Transitive:
   `stats.weapon_config.damage = 5` is banned under the same rule
   as `stats.damage = 5`.
2. **`set_shader_parameter` on a shared Material is a write.** Either
   `.duplicate()` the material per-instance in `_ready()`, or document
   inline that the write is globally intended (e.g., the water
   DisplacementMap wired once from main.gd).
3. **Curve / Gradient mutations banned.** No `curve.add_point()` on
   an `@export`ed Curve.
4. **`@export var foo: FooType`** with NO `preload()` default —
   assigned via scene ExtResource slot. `preload` defaults fight
   hot-reload and hide dependencies.
5. **Component .tscn files must not embed mutable sub-resources.**
   Materials, Curves, Gradients are ExtResources from a feature's
   own folder, making the shared-vs-per-instance decision explicit
   at the .tres level.
6. **Hot-reload granularity**: components that re-read Resource fields
   per frame (MovementComponent reads `stats.thrust`, WaterEffectsManager
   reads `WaterTuning.tres`) live-update from inspector edits.
   Components that cache values at setup time (HealthComponent's
   `max_health`, BroadsideComponent's cooldown) do NOT — this is a
   documented limitation, not a bug. Restart after editing if those
   fields matter mid-run.
7. **Legacy grandfather clause:** `features/water/trails.gd` still uses
   `.duplicate()` on `width_curve` because the pre-refactor code
   actively mutates it. New code must not mutate, so it never needs to
   duplicate. This is the **only** surviving instance of the old
   `.duplicate()` pattern.

## Signal Bus Discipline (ADR 007)

The `Events` autoload carries cross-system events only.

- **Components do NOT touch the `Events` autoload directly.** Entity
  roots (Ship, EnemyShip, WaveDirector, SpawnService) and service
  nodes are the only publishers. Components emit signals upward to
  the entity root, which dispatches.
- **Two component-publishes-bus exceptions:** `HitFeedbackComponent`
  (`screen_shake_requested`) and `AudioEmitterComponent`
  (`sound_requested`). Both are terminal-output components — routing
  through the entity root would be a pointless forwarder. Documented
  in ADR 007.
- **Listener-owns-the-work principle**: signals with a single natural
  receiver do NOT get an intermediate listener. Camera shake →
  GameCamera direct subscription, no listener proxy. VfxListener
  exists because `explosion_requested` has many spawn sites and needs
  a persistent parent.
- **Bus payloads MUST be typed.** No untyped Dictionary payloads.
- **High-frequency signals are OK on the bus** — Phase 9 measured the
  cost and dropped the carve-out rule. Uniformity beats premature
  optimization.

## Style additions

- **`StringName`** for all enum-like Resource string fields and signal
  parameters: `explosion_kind`, `fire_sound`, `sound_id`, `cheat_id`.
  StringName is interned; the lookup cost is a hash compare.
- **Avoid shadowing built-ins** in signal/method parameters:
  `sound_requested(sound_id, pos)` not `sound_requested(name, pos)`
  because `name` shadows `Node.name`.
- **`distance_squared_to`** preferred over `distance_to` when comparing
  against a threshold (skip the `sqrt`).

## Shader Conventions

- **File naming**: `snake_case.gdshader` (not PascalCase).
- **Uniform naming**: PascalCase (inherited from reference; diverges
  from GLSL convention).
- **Texture filter hints**: `filter_nearest` for player-visible
  textures, `filter_linear` for noise/math inputs (overrides project
  Nearest default).
- **Deferred features**: comment with `// TODO(post-mvp):` and include
  what to wire.

## Linting

`addons/` is excluded from both linters (vendored code). gdlint reads
`gdlintrc` at the project root; gdformat has no exclude option, so use
`find` to enumerate the project's `.gd` files:

```bash
# formatting (skip addons/)
find . -name "*.gd" -not -path "./addons/*" -not -path "./.git/*" \
  -not -path "./.godot/*" -print0 \
  | xargs -0 gdformat --check

# style (gdlintrc handles excludes)
gdlint .
```

Run both before committing. Fix gdformat issues by re-running the
same `find | xargs` pipeline without `--check`.

### Long preload paths (Phase 11 Step 48b)

The 100-char line limit can be tight when preloading from a deep
feature subfolder. Adopt the **two-step preload pattern** rather than
raising the cap:

```gdscript
# features/water/displacement_stamps.gd
const _MAT_PATH: String = "res://features/water/shaders/displacement_stamp_material.tres"
const BASE_MATERIAL: ShaderMaterial = preload(_MAT_PATH)
```

The private `_PATH` const stays under the cap, and the actual preload
is one short line. Use this pattern when an inline preload would
exceed 100 chars; otherwise inline the path.

## Testing

### Unit tests (GUT)
GUT is vendored at `addons/gut/` and excluded from release exports.
Tests live under `tests/unit/`. Run headless via:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Test conventions:
- `extends GutTest`
- `const FooClass: GDScript = preload("res://...")` rather than
  relying on `class_name` (the headless parser doesn't always pick
  up the global class index in time).
- `add_child_autofree(node)` for tests that need a SceneTree.
- `watch_signals(obj)` + `assert_signal_emitted(obj, name)` for
  signal coverage.

Current suites: `test_cooldown.gd`, `test_health_component.gd`,
`test_run_stats.gd`, `test_wave_config.gd`, `test_wave_set_sharing.gd`.

### Visual / integration smoke
Visual-only systems: run project via MCP (`run_project` →
`get_debug_output` → `stop_project`). Check for zero errors. Validate
`.tres`/`.tscn` files when changed.

**Pre-merge editor open**: open the editor in the GUI at least once
before a final smoke run to refresh the UID-by-text-path map. The MCP
workflow doesn't trigger Godot's UID rescan, so stale-UID warnings
accumulate even when the fallback paths are correct.
