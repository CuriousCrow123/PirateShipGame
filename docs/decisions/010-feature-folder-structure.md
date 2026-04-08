## ADR 010: Feature-Folder Structure

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 005 (components)](005-component-decomposition-strategy.md)

## Context

Pre-refactor, the project used Godot's default loose-bag layout:

```
scripts/       — every .gd file, flat
scenes/        — every .tscn file, flat
resources/     — every .tres file, flat
textures/      — every .png, flat
shaders/       — every .gdshader, flat
```

This stopped scaling around the time `scripts/` hit 30 files. "Find the water script" turned into a grep for `water`; "delete the dash feature" would have been a cross-folder hunt. The pre-refactor `scripts/` directory had `ship.gd`, `enemy_ship.gd`, `cannonball.gd`, `sea_mine.gd`, `main.gd`, `ship_fsm.gd`, `trails.gd`, `water_chunks.gd`, `displacement_stamps.gd`, `vfx_listener.gd`, etc. — all siblings with no structural relationship to each other.

The brainstorm called for **feature folders**: each subsystem gets its own top-level folder that owns its scripts, scenes, resources, textures, and shaders. The maximalist-tree approach was selected explicitly in the brainstorm ([docs/brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md](../brainstorms/2026-04-07-deep-codebase-refactor-brainstorm.md)).

Open questions during Phase 10 execution:

1. **What are the top-level folders?**
2. **What counts as a "feature" vs a cross-cutting system?**
3. **Where does cross-feature code live when it has no natural feature home?**
4. **How are cross-instanced components grouped when one feature uses another's component?**

## Decision

### 1. Canonical top-level tree

```
addons/         — vendored third-party (GUT) + first-party EditorPlugins
                  (pirate_dev_tools)
assets/         — shared textures, fonts (cross-feature)
autoload/       — Events, GameState, AudioManager, KeybindsManager
dev/            — development-only scenes/tools (emptied by Phase 11 Step 47;
                  addon migration replaces everything in here)
docs/           — plans, decisions (this ADR), brainstorms, solutions
features/       — feature folders (one subfolder per subsystem)
main/           — main.tscn + main.gd (the scene registered as run/main_scene
                  in project.godot)
systems/        — cross-feature helpers + service nodes
tests/          — GUT unit tests
```

Plus top-level config: `CLAUDE.md`, `export_presets.cfg`, `gdlintrc`,
`icon.svg`, `project.godot`.

### 2. Feature folder contents

`features/<name>/` owns everything that's specifically about that feature:

```
features/ship/
├── ship.gd
├── ship.tscn
├── ship_fsm.gd
├── ship_stats.gd
├── ship_config.gd
├── components/
│   ├── health_component.gd
│   ├── movement_component.gd
│   ├── hurtbox_component.gd
│   ├── dash_component.gd
│   ├── dash_stats.gd
│   ├── dash_stats.tres
│   ├── cannon.gd
│   ├── cannon.tscn
│   ├── broadside_component.gd
│   ├── mine_drop_component.gd
│   ├── hit_feedback_component.gd
│   ├── audio_emitter_component.gd
│   └── player_input.gd
├── config/
│   └── default_ship_config.tres
└── stats/
    └── default_ship_stats.tres
```

The current top-level feature folders are: `camera`, `enemies`, `hud`, `ship`, `vfx`, `water`, `waves`, `weapons`.

### 3. `systems/` inclusion criterion

**Cross-feature `RefCounted` helpers + service `Node`s that aren't owned by a single feature.**

Current `systems/` contents:

| File                    | Why it's in systems/                                                         |
|-------------------------|------------------------------------------------------------------------------|
| `cooldown.gd`           | `RefCounted` helper used by Dash, MineDrop, Respawn, SeaMine, etc.           |
| `run_stats.gd`          | `Resource` accumulator consumed by HUD, WaveDirector, GameOverScreen.        |
| `spawn_service.gd`      | Service `Node` — spawns enemies for WaveDirector, mines for Ship, cannonballs for Cannon. Not owned by any one feature. |
| `stats_tracker.gd`      | Service `Node` — thin wrapper over GameState mutator calls used by WaveDirector / SpawnService for convenience. |

**Rule**: if a file would have to live in at least two `features/<x>/` folders to not be the odd one out, it belongs in `systems/`. If a file is only touched by one feature, it lives in that feature.

### 4. Components live with their host entity, not by class role

[features/ship/components/cannon.tscn](../../features/ship/components/cannon.tscn) lives with the ship even though Cannonball (the projectile it fires) lives in `features/weapons/`. The rule is:

**Components that attach to an entity root live with the entity that hosts them, even when cross-instanced.**

EnemyShip instantiates the same `cannon.tscn` via `res://features/ship/components/cannon.tscn`. This is fine — a "cannon" is a turret component that attaches to a ship-like entity, and both ships host it. Cannonball, the free-flying projectile, is a weapon and lives in `weapons/`.

Corollary: don't split shared components into a `components/shared/` folder. `HealthComponent` and `HurtboxComponent` are in `features/ship/components/` even though EnemyShip reuses them, because Ship was the first (and primary) host.

### 5. Atomic feature moves are cheap; folder reorgs amortize best when each feature is already cohesive

Phase 10 observation: the water folder consolidation that landed in Phase 9 paid off during Phase 10's folder reorg. The `scripts/water/` → `features/water/` rename was a single `git mv` + 8 `Edit replace_all` calls on 2 files. If Phase 9 hadn't already consolidated the water files, Phase 10 would have had to find them scattered across `scripts/`.

**Pattern**: before a folder reorg, consolidate a feature's files into a single subfolder. Move the subfolder atomically. The intermediate "flat subfolder under the old layout" is a one-commit waypoint that costs almost nothing.

Source: Phase 10 retro line 217–223 in the parent plan.

### 6. `.uid` sidecar move rule

Every `.gd` script has a `.uid` sidecar file next to it (Godot writes these to cache the UID-to-path mapping). When moving a script, `git mv` BOTH files in the same commit:

```bash
git mv features/water/old_location.gd features/water/new_location.gd
git mv features/water/old_location.gd.uid features/water/new_location.gd.uid
```

**Never move files via Finder or shell tools while the editor is closed.** Godot 4.4 had a bug (#104188) where closing-editor moves could silently delete `.uid` sidecars. The project is on 4.6.1 (fix landed in 4.5), but the atomic `git mv` rule still holds as belt-and-suspenders.

### 7. Node-vs-Node2D rule for components (transform chain exception to ADR 005)

Inside `features/<x>/components/`, components default to `extends Node`. **The exception: if a component owns a `CanvasItem` child whose transform must track the entity (Area2D for collision, Sprite2D for positional VFX, etc.), the component MUST `extends Node2D` instead.**

Godot's 2D transform chain only walks through `CanvasItem` ancestors. A plain-`Node` parent silently strands its `CanvasItem` children at world origin `(0, 0)` — no error, no warning, just a collision shape that never touches anything because its world position is wrong.

**Current instance**: [features/ship/components/hurtbox_component.gd](../../features/ship/components/hurtbox_component.gd). The script header documents the reason inline.

**Audit candidates** for future components: anything with a hitbox, AoE detection radius, positional VFX anchor, or Camera2D peer relationship. If in doubt, `extends Node2D` — the overhead is one Transform2D per component, which is negligible.

This exception was discovered as a post-Phase-10 hot-fix (see parent plan "Post-Phase 10 hot-fix: Hurtbox transform inheritance" section). The bug had been latent since Phase 4 Step 23 and shipped undetected through Phase 10 because sea mines bypassed the hurtbox via a direct physics shape query — cannonballs vs ships had actually been non-functional for 6 phases.

### 8. No per-feature `.gd` inside `main/`

`main/` contains exactly `main.tscn`, `main.gd`, and anything that is *uniquely* the top-level orchestrator. No feature code lives here. If `main.gd` starts growing a feature-specific helper method, the method probably belongs in that feature's folder.

## Consequences

**Positive:**
- **"Delete feature X"** is a single folder removal. Water could be ripped out by deleting `features/water/` + references.
- **"Find everything about feature X"** is a single folder read.
- **Clear ownership.** No ambiguity about where a new ship-related script goes — `features/ship/components/`.
- **Diff hygiene.** A PR that touches one feature doesn't accidentally touch ten sibling files in a flat `scripts/` dir.
- **Assets live with their consumers.** `features/vfx/textures/`, `features/water/textures/` — a texture belongs in the folder of the feature that uses it.
- **`systems/` is a small, stable list.** 4 files, all justified. If `systems/` grows past ~10 files, the rule needs a second look.

**Negative:**
- **Cross-feature references are long.** `preload("res://features/water/shaders/displacement_stamp_material.tres")` can exceed gdlint's 100-char line limit. The line-length decision in Phase 11 Step 48b adopts a two-step pattern for long preloads: `const _PATH: String = "..."` followed by `const MAT: ShaderMaterial = preload(_PATH)`. Documented in [CLAUDE.md](../../CLAUDE.md).
- **A ship component referenced by an enemy creates an implicit cross-feature dependency.** EnemyShip depends on `features/ship/components/cannon.tscn`. Fine in practice but tracked by the ADR 005 "components stay with their host entity" rule.
- **`.uid` sidecar move discipline** is manual. Forgetting one produces stale UID warnings that persist until the editor rescans.
- **`assets/` + `features/<x>/textures/`** split means two valid homes for a texture. The rule: if more than one feature uses it, `assets/`; otherwise, the feature folder. Fonts are always in `assets/fonts/`.

## Alternatives Considered

**Keep flat `scripts/` layout and use naming prefixes** (`ship_movement.gd`, `ship_health.gd`, etc.). Rejected. Naming conventions don't survive refactors (a `ship_health.gd` used by enemies gets a misnamed prefix), and IDE navigation favors folders over prefix-sort.

**Group by layer instead of feature** (`scripts/components/`, `scripts/resources/`, `scripts/scenes/`). Considered. Rejected because the "find all ship code" query becomes a cross-folder hunt again — the exact problem we're solving.

**Hybrid: `features/` for gameplay, `scripts/` for infra.** Rejected. The split point between "gameplay" and "infra" is fuzzy and invites constant bikeshedding. `systems/` is the principled version (cross-feature helpers only), with strict inclusion criteria.

**Per-feature autoloads** (`features/audio/audio_manager.gd` as autoload). Rejected. Autoloads are intentionally kept in one flat `autoload/` folder so the project-wide autoload list is a single `ls` away. The autoload table in `project.godot` already groups them.

**`components/` as a top-level sibling of `features/`.** Rejected. Components are feature-owned; a top-level `components/` implies they're framework-like and reusable, which creates a false universality claim ("which component folder does my new ship-specific component go in?").
