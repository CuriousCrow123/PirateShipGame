<!-- verified against commit 090ed90 on 2026-04-08 -->

# Architecture Tour

A curated onboarding path through PirateShipGame's codebase. Written
for a Godot-literate developer (human or AI agent) who has just
cloned the repo and wants to *understand the shape of the thing*
before editing it.

## Read in this order

1. **[01-overview.md](01-overview.md)** — game concept, engine /
   viewport / autoload settings, the run loop, and the annotated
   scene tree of [main/main.tscn](../../main/main.tscn).
2. **[03-entities-and-components.md](03-entities-and-components.md)**
   — Ship, EnemyShip, Cannonball, SeaMine, the 10 ship components,
   and the Ship finite state machine (Mermaid state diagram).
3. **[02-autoloads-and-signals.md](02-autoloads-and-signals.md)** —
   the four autoloads, the `Events` bus inventory grouped by domain,
   bus discipline rules, and the end-to-end player-damage signal
   trace (Mermaid sequence diagram).
4. **[04-resources-and-vfx.md](04-resources-and-vfx.md)** — the
   Resource catalog, the ADR 009 hot-reload doctrine in onboarding
   voice, and canonical pointers into the water shader and explosion
   atlas pipelines.

Files 02 and 03 are intentionally out of numeric order — the
component vocabulary from 03 locks in the nouns that the signal flow
in 02 uses, so reading 03 first stops 02 from forward-referencing
names the reader hasn't met yet. The numbers track the docs' original
carving, not the reading order.

## If you only have 15 minutes

Read `01-overview.md` + `03-entities-and-components.md`. That gets you
to the point where you can find where a gameplay behavior lives and
know which file to edit. The signal flow and Resource doctrine can
wait.

## Conventions used in this suite

- **Link, don't duplicate.** Every claim has a `file_path` link.
  Function-name anchors (`Ship._on_hurtbox_hit_taken`) outlive any
  refactor that doesn't rename them; line-number anchors (`#L42`)
  don't. You will not see `#Lxx` anywhere in these docs unless a
  single line is the entire point.
- **Mermaid only** for diagrams — three total across the suite: the
  scene-tree/flowchart in `01`, the Ship FSM stateDiagram-v2 in `03`,
  and the player-damage sequenceDiagram in `02`. GitHub renders
  Mermaid natively; no images, no external tooling.
- **`->>` vs `-->>`** in sequence diagrams is always the same:
  `->>` is a direct method call, `-->>` is a signal emission. If you
  see one used the other way, it's a doc bug.
- **Last-verified stamps** (`<!-- verified against commit <sha> on
  <date> -->`) live at the top of each file. After any structural
  refactor, run through [VERIFY.md](VERIFY.md), fix what's stale, and
  bump the stamp on touched files.
- **ADRs are frozen.** They describe a decision at a point in time.
  The architecture tour describes current state. If you want to know
  *why* something is a certain way, read the ADR; if you want to know
  *what is actually there today*, stay here.

## ADR map

The 14 decision records in
[docs/decisions/](../decisions/) — one sentence each, grouped by
"read this if you're about to…":

### Graphics + shaders
- **[001 — Water shader approach](../decisions/001-water-shader-approach.md)** — before editing any `.gdshader` file. Why handwritten shader code, not `VisualShader`.
- **[002 — Pre-rendered explosion atlases](../decisions/002-prerendered-explosion-atlases.md)** — before touching `features/vfx/`. Why atlases, not real-time 3D particles.
- **[003 — Explosion config Resource](../decisions/003-explosion-config-resource.md)** — before adding a new explosion kind. How `ExplosionStats` replaced a buried const dict.

### Gameplay feel
- **[004 — Dash overspeed via drag relax](../decisions/004-dash-overspeed-via-drag-relax.md)** — before retuning `DashStats`. Why drag relax instead of a hard `max_speed` cap.
- **[006 — Flat-enum FSM over HSM](../decisions/006-flat-enum-fsm-over-hsm.md)** — before adding a new `ShipFSM` state. Why one enum, not a hierarchical state machine.
- **[014 — Cooldown helper design](../decisions/014-cooldown-helper-timestamp-design.md)** — before using `Cooldown` in new code. Why timestamp-based + wall-clock, not `SceneTreeTimer`.

### Architecture + discipline
- **[005 — Component decomposition strategy](../decisions/005-component-decomposition-strategy.md)** — before creating a new component. Single-responsibility, signal-up, default-OFF, `@export` Resources.
- **[007 — Events bus discipline](../decisions/007-events-bus-discipline.md)** — before calling `Events.*.emit()` from a component. The two sanctioned exceptions and why.
- **[008 — GameState autoload scope](../decisions/008-gamestate-autoload-scope.md)** — before adding a new per-run mutable field. Methods-only API, merged `StatsTracker`.
- **[009 — Resources hot-reload strategy](../decisions/009-resources-hot-reload-strategy.md)** — before writing `ship.stats.x = y`. The three hazards.
- **[010 — Feature folder structure](../decisions/010-feature-folder-structure.md)** — before adding a new top-level folder. Inclusion criteria for `systems/` vs `features/`. **§7 is the Node-vs-Node2D rule you care about.**
- **[013 — Ship component decomposition](../decisions/013-ship-component-decomposition.md)** — before touching `features/ship/components/`. The concrete 9-component plan and the three fusions that were cut.

### Platform / input / audio
- **[011 — Audio architecture](../decisions/011-audio-architecture.md)** — before wiring a new sound source. The staged `AudioManager + SoundLibrary + AudioEmitterComponent` plan.
- **[012 — Input and gamepad architecture](../decisions/012-input-and-gamepad-architecture.md)** — before touching `KeybindsManager`. Why `PlayerInputComponent` owns gameplay reads and the remap / persistence split.

If you find yourself about to make a change and none of the above
ADRs feels load-bearing, the change is probably safe. If one of them
*is* load-bearing and the change contradicts it, prefer updating the
ADR via errata rather than silently diverging.

## Doc-rot maintenance

If you refactor a function referenced by these docs, `grep` for its
name inside `docs/architecture/` and fix anchors in the same commit.
After any structural refactor, run the [VERIFY.md](VERIFY.md) pass,
fix the stale items, and bump the `verified against commit` stamp
lines on touched files.

## What to read next

- **Start the tour** → [01-overview.md](01-overview.md).
- **Linting / formatting / component rules** →
  [../../CLAUDE.md](../../CLAUDE.md).
- **The refactor plan this tour documents** →
  [../plans/2026-04-07-refactor-component-architecture-plan.md](../plans/2026-04-07-refactor-component-architecture-plan.md).
- **Manual recheck pass after a refactor** → [VERIFY.md](VERIFY.md).
