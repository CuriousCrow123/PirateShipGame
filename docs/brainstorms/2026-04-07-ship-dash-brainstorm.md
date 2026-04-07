---
date: 2026-04-07
topic: Ship dash ability
status: brainstorm
---

# Ship Dash — Brainstorm

## What We're Building

A bursty, escape-oriented dash for the player ship, triggered by the **space bar**. The dash propels the ship forward with a stylized fire shader (ported from GDQuest's `StylizedFire` demo) emitting from the stern, leaving a classic 2D ghost-trail of fading sprite afterimages behind. Every dimension — motion, exhaust, trail, camera feedback — is exposed through a live-editable `DashConfig` Resource so the look and feel can be tuned without restarting the game (mirroring the existing `ExplosionConfig` pattern).

The dash is **not** a teleport. It is a strong velocity impulse that interacts with the ship's existing momentum/drag model, with a short cooldown (~1–2s).

## Why This Approach

- **Mirrors existing patterns.** `ExplosionConfig` already proves the live-tunable Resource workflow in this project (shader uniforms hot-reload via Godot's resource cache). Reusing that loop keeps cognitive overhead low and makes the dash feel native to the codebase.
- **Single quad + ported shader** is the lightest path to the desired stylized fire look. No particle systems to fight, no overlap with the existing explosion VFX style, and every parameter is a uniform we can drive from `DashConfig`.
- **Sprite afterimages** are the most legible "dash" signature in 2D and are trivial to spawn from `ship.gd` (just `Sprite2D` clones with tweened modulate). They read instantly as "I dashed" without competing with the existing wake/trail system.
- **No i-frames** keeps the design honest — the dash is escape *via positioning*, not invincibility. The player has to aim it.

## Key Decisions

### Mechanics
- **Trigger:** Space bar, new `dash` input action.
- **Type:** Velocity impulse on a `CharacterBody2D` ship — bursty but momentum-respecting.
- **Cooldown:** Short, tunable (default ~1–2s). Follows existing cannon/mine cooldown pattern in [scripts/ship.gd](scripts/ship.gd).
- **I-frames:** None. Pure positional escape.
- **Damage on contact:** No (not a ram).

### Dash "feel mode" (tunable enum)
The user wants all four behaviors implemented and selectable as a `DashConfig` parameter:
1. **Locked-heading burst** — fires along facing, steering disabled during the burst.
2. **Steerable burst** — fires along facing, steering remains enabled.
3. **Velocity-aligned burst** — fires along current velocity vector (drift-dash).
4. **Overspeed-cap raise** — impulse + temporarily lifted max-speed cap, bleeding off via existing drag.

This makes the dash itself a tuning playground, not just its parameters.

### Visuals
- **Fire shader:** Port the GDQuest `StylizedFire.gdshader` into [shaders/](shaders/) (rename to `snake_case`, follow project shader conventions). Single quad (Sprite2D or ColorRect) parented to the ship's stern. Shader intensity driven by a `dash_strength` uniform that ramps `0 → 1 → 0` across the burst via an `intensity_curve` from `DashConfig`.
- **Ghost trail:** Spawn N `Sprite2D` clones of the ship at fixed intervals during the dash. Each clone is detached from the ship, holds its spawn position/rotation, and tweens `modulate.a → 0` (with optional tint shift) over a configurable fade time, then `queue_free`s.
- **Camera feedback:** Optional shake / FOV-or-zoom punch / brief time-scale dip. All tunable on `DashConfig` and zeroable to disable.

### Live tunability — `DashConfig` Resource

Mirrors [scripts/explosion_config.gd](scripts/explosion_config.gd). Exports grouped by section:

- **Core motion:** `feel_mode` (enum), `impulse_speed`, `duration`, `cooldown`, `overspeed_cap_multiplier` (used by mode 4), `steering_dampen` (used by mode 1).
- **Fire shader uniforms:** color ramp (gradient), base scale, intensity curve, distortion strength, plus whatever the ported shader exposes (flame height, noise scroll speed, etc.).
- **Ghost trail:** afterimage count, spawn interval, fade duration, start tint, end tint, additive blend toggle.
- **Camera feedback:** shake magnitude, shake duration, zoom punch amount, zoom punch duration, time-scale dip target, time-scale dip duration.

Loaded once via `load("res://resources/dash_config.tres")`; Godot's resource cache propagates editor edits to the running game live.

## Open Questions

None — all design dimensions resolved during brainstorming. Implementation-level questions (where exactly the fire quad attaches in [scenes/ship.tscn](scenes/ship.tscn), how the afterimage Sprite2Ds are spawned without retaining ship references, exact uniform names from the GDQuest shader) belong in the plan, not here.

## Resolved Questions

- **Dash feel:** All four modes implemented, switchable via `DashConfig.feel_mode`.
- **Purpose:** Escape / panic button.
- **Cooldown:** Short (~1–2s), tunable.
- **Fire shader integration:** Port shader → single stern quad → driven by `dash_strength` uniform.
- **Trail style:** Sprite afterimages (classic 2D dash).
- **I-frames:** No.
- **Tunable scope:** Core motion + shader uniforms + trail params + camera feedback — all live-editable.

## References

- GDQuest stylized fire shader: https://github.com/gdquest-demos/godot-shaders/tree/main/godot/Demos/StylizedFire
- Live-tuning pattern to mirror: [scripts/explosion_config.gd](scripts/explosion_config.gd), [resources/explosion_config.tres](resources/explosion_config.tres)
- Ship to extend: [scripts/ship.gd](scripts/ship.gd), [scenes/ship.tscn](scenes/ship.tscn)
- Existing cooldown pattern to follow: [scripts/ship.gd](scripts/ship.gd) (cannon/mine timers)
