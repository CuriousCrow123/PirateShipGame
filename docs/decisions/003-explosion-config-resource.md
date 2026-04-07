# ADR 003: Live-Editable Explosion Config via Resource File

**Date:** 2026-04-06
**Status:** Accepted

## Context

After adopting the baked sprite atlases from [ADR 002](002-prerendered-explosion-atlases.md), we still kept `ExplosionEffect` (the real-time 3D version) alive as:
1. A fallback / A-B comparison when tuning
2. The capture tool used by `explosion_test.gd` to re-bake atlases

A `toggle_explosion_mode` input action (key 9) lets us flip between sprite and 3D modes at runtime. `ExplosionSprite.create()` delegates to `ExplosionEffect.create()` when sprite mode is off.

This made `ExplosionEffect` the source of truth for visual tuning — but `create()` had grown to 13 positional parameters, and the per-type values were buried in a `const TYPE_3D_PARAMS` dict inside `explosion_sprite.gd` that only changes at parse time. Iterating on "what does a cannonball impact look like?" meant: edit constant → save → reload game → spawn → observe → repeat. Painful.

## Decision

Two changes that work together:

### 1. Refactor `ExplosionEffect.create()` to take a `config: Dictionary`

```gdscript
static func create(parent: Node, pos: Vector2, config: Dictionary = {}) -> ExplosionEffect
```

All overrides flow through a single dict. Missing keys fall back to scene/shader defaults. The heavy lifting lives in [`_apply_config()`](../../scripts/explosion_effect.gd) which reads each supported key and writes to the corresponding emitter/material/particle property.

Supported keys (see `_apply_config` for the full list): `cone_dir`, `cone_spread`, `effect_scale`, `lifetime`, `drift_velocity`, `vert_velocity`, `vert_amount`, `horiz_amount`, `horiz_velocity_min/max`, `vert_damping`, `horiz_damping`, `particle_scale`, `turbulence_strength`, `turbulence_influence`, `glow_enabled`, `glow_intensity`, `glow_strength`, `glow_bloom`, `dark_color`, `fire_color`, `bright_alpha_scale`, `dark_alpha_scale`, `smooth_step_edge`, `bright_dissolve_scale`, `dark_dissolve_scale`.

Adding a new tunable param is now: add the key to `_apply_config`, add an `@export` var to the config Resource, add the key to `_TYPE_KEYS`. No callsite churn.

### 2. Store per-type params in a `Resource` file loaded at runtime

- [`scripts/explosion_config.gd`](../../scripts/explosion_config.gd) — `class_name ExplosionConfig extends Resource` with `@export var <type>_<param>` for each of the 4 types × ~19 params, plus global glow controls
- [`resources/explosion_config.tres`](../../resources/explosion_config.tres) — an instance of `ExplosionConfig` holding the current tuned values
- `ExplosionConfig.get_params(type_name)` returns a `Dictionary` ready to pass to `ExplosionEffect.create()` — the `_TYPE_KEYS` const lists the per-type keys that get looked up via string concatenation (`"%s_%s" % [type_name, key]`)

[`ExplosionSprite._create_3d()`](../../scripts/explosion_sprite.gd) loads the .tres and passes its `get_params()` result:

```gdscript
var config_res: ExplosionConfig = load(CONFIG_PATH) as ExplosionConfig
var config: Dictionary = config_res.get_params(type_name)
config["cone_dir"] = ...
config["drift_velocity"] = drift_velocity
config["effect_scale"] = ...
var effect := ExplosionEffect.create(parent, pos, config)
```

### The live-edit workflow

Because Godot caches `Resource` instances by path, the `.tres` loaded by the running game and the `.tres` opened in the editor's Inspector are the **same in-memory object**. Editing values in the Inspector immediately updates the running game's next spawn, and pressing Ctrl+S persists those edits to disk.

This gives us:
- **Zero-latency iteration** on any visual param (no recompile, no restart)
- **Persistence** — changes save to the `.tres` automatically
- **Source-controlled** — the `.tres` is a text file so tuning is diffable in git
- **No autoload** — the config isn't global state, it's a regular Resource loaded where needed

## Alternatives Considered

**Autoload Node with `@export` vars** — we tried this first. Editing via the Remote tab worked for the running game but changes didn't persist to disk. You'd spend an hour tuning, hit Stop, and lose everything. Rejected.

**Per-type Resource subclasses** (`MuzzleFlashConfig`, etc.) — cleaner class hierarchy but Godot's Remote/Inspector is clunkier with nested sub-resources, and we'd duplicate schema across 4 files for no real benefit. Rejected.

**Custom in-game tuning UI** — sliders overlaid in the game. Nice UX but `@export`s in the Inspector get you 90% of the value for 10% of the work. Rejected (for now).

**Keyed ResourceLoader cache-busting** on every spawn — re-loading the `.tres` from disk each spawn to catch file changes. Unnecessary given the cache-sharing trick works; would also thrash the FS. Rejected.

## Consequences

**Positive:**
- Visual tuning is now a live, WYSIWYG workflow
- The config file is the single source of truth for all per-type params
- Adding new tunable params is cheap (one key in three places)
- Works for both sprite mode (where only some params affect appearance) and 3D mode (where all params apply live)
- The `.tres` is diffable and source-controlled

**Negative:**
- A change to visual tuning and a change to code both touch the config — the .tres file becomes a hot spot for merge conflicts if multiple people tune
- Sprite mode only reflects a subset of params (those that affect the baked output); the rest require a re-bake via `explosion_test.gd` to become visible in sprite mode
- `ExplosionEffect.create()`'s positional-args API is gone — `explosion_test.gd` was the only other caller and was updated to use the dict form

**Related fixes made while refactoring:**
- [`godot-shared-mesh-surface-material.md`](../solutions/godot-shared-mesh-surface-material.md) — per-instance shader overrides leaked through the shared `SphereMesh`; fixed by switching to `material_override` on the GPUParticles3D node
- [`godot-alpha-scissor-vs-blend.md`](../solutions/godot-alpha-scissor-vs-blend.md) — `ALPHA_SCISSOR_THRESHOLD` forces opaque rendering and ignores the `ALPHA` value; removed for the dissolve shader so we get graduated transparency for smoke stages

## Follow-ups

- Re-bake the sprite atlases after the final visual tuning is dialed in, so sprite mode matches 3D mode
- Consider adding a "reset to defaults" button per group (requires a tool script or custom Inspector plugin)
- Consider a per-variation seed override so tuners can repro a specific visual in the Inspector
