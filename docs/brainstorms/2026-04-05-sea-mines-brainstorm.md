# Sea Mines — Brainstorm

**Date:** 2026-04-05
**Status:** Draft

## What We're Building

Floating sea mines that serve as both a player weapon and a world hazard. The mine is a classic naval mine — a sphere with 14 cylindrical detonation triggers uniformly distributed around it. It's modeled in 3D and rendered as 2D pixel art via a SubViewport (same pattern as ExplosionEffect).

Mines float partially submerged, bobbing up and down with an oscillating water line that naturally follows the sphere's curvature (via fragment shader). A ripple effect around the mine's waterline sells the floating-in-water feel.

### Core Behavior

- **Dual source:** Player can drop mines at their current position AND mines spawn as world hazards
- **Detonation trigger:** Timed fuse — when a ship enters proximity, a 1-2 second countdown starts with a flashing red glow of increasing urgency, then explosion
- **Cannonball interaction:** Cannonballs that hit the water near a mine trigger detonation (water impact proximity, not direct mine hit)
- **Damage:** Damages everything in blast radius equally — player-laid mines can hurt the player too (risk/reward)
- **Quantity:** Unlimited player mines, 2-3 second cooldown between drops
- **Blast radius:** Medium (2.5x visual size)
- **Chain reactions:** Yes — mines in blast radius trigger each other
- **Visibility:** Always visible on the water surface

## Why This Approach

**SubViewport 3D mine + shader water line** was chosen over alternatives:

- Matches the existing ExplosionEffect SubViewport rendering pattern — consistency
- Shader-based water line gives precise, smooth "partially submerged" look that follows the sphere's curvature naturally
- Live 3D rendering allows potential future enhancements (rotation, dynamic lighting) without rework
- Performance concern (SubViewport per mine) is acceptable given the game's scale; can optimize to shared viewport or pre-bake later if needed

**Rejected alternatives:**
- Pre-baked sprite sheet: Better performance but less flexible; premature optimization
- Sprite overlay for water: Simpler but water line wouldn't wrap the sphere curvature convincingly

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Entity type | Area2D | Mines are stationary triggers, not moving bodies |
| Collision layer | New layer 4 (`hazards`) | Mask: player + enemies. Cannonball interaction via water-impact proximity check, not direct collision |
| 3D rendering | SubViewport with MeshInstance3D | Matches ExplosionEffect pattern |
| Water line effect | Fragment shader clipping at oscillating Y | Smooth curvature-following submersion look |
| Bobbing animation | Sine-wave Y offset on sprite + shader water line Y | Simple, convincing floating motion |
| Ripple effect | Shader-based concentric rings or animated sprite at water level | Sells the bobbing-in-water feel |
| Fuse visual | Flashing red glow with increasing frequency | Clear "about to explode" feedback |
| Detonation | Reuse ExplosionEffect.create() | Consistent explosion VFX |
| Spawning | Follow enemy_ship pattern in main.gd | Preload, track in array, signal-based lifecycle |

## Visual Breakdown

### Mine Model (3D)
- **Sphere:** Main body, dark metal material
- **Triggers:** 14 cylinders with rounded caps, uniformly distributed using fibonacci sphere or icosahedron vertex placement
- Rendered in SubViewport at pixel-art resolution, captured as Sprite2D texture

### Water Bobbing
- Sprite Y position oscillates via sine wave (configurable amplitude + frequency)
- Fragment shader draws a water-line overlay at an oscillating clip position
- Below the water line: tint/darken the mine sprite to simulate submersion
- Above the water line: normal mine rendering

### Water Ripple
- Concentric ring effect at the mine's base position
- Amplitude modulated by bobbing phase (stronger ripple at bob extremes)
- Could be a separate Sprite2D with a ring shader or a simple animated spritesheet

### Fuse Countdown
- Red glow pulse on the mine (modulate or emission shader)
- Pulse frequency increases: slow blink -> fast blink -> solid -> BOOM
- Duration: ~1.5 seconds from trigger to detonation

## Entity Architecture

```
SeaMine (Area2D)                    — scripts/sea_mine.gd
  MineViewport (SubViewport)        — 3D rendering
    MineModel (Node3D)              — sphere + trigger cylinders
      Camera3D                      — orthographic, aimed at mine
  MineSprite (Sprite2D)             — displays SubViewport texture
  WaterOverlay (Sprite2D or shader) — water line + ripple effect
  ProximityArea (CollisionShape2D)  — detection radius for fuse trigger
  DamageArea (CollisionShape2D)     — blast radius (enabled on detonation)
```

## Resolved Questions

1. **Cooldown for player mine placement?** 2-3 seconds between drops
2. **Blast radius size?** Medium (2.5x visual size) — balanced risk/reward
3. **Chain reactions?** Yes — mines in blast radius trigger their own detonation, enabling satisfying chain explosions
4. **World mine density/placement?** Deferred — focus on the mine entity and player placement first; world spawning patterns to be designed later

## Open Questions

(None remaining)
