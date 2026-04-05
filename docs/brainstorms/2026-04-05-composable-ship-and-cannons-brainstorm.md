# Composable Ship Parts & Cannon System

**Date:** 2026-04-05
**Status:** Brainstorm complete
**Approach:** Scene-Layered Composition

## What We're Building

Replace the single pre-composed ship sprite with a layered ship assembled from individual spritesheet parts: hull, sails, and cannons. Add a broadside cannon firing system where cannonballs spawn exactly from the cannon muzzle.

### Core Features

1. **Composable ship scene** -- Hull Sprite2D + Sail Sprite2D layered as children, replacing the current single ShipSprite region
2. **Editor-placed cannon slots** -- Marker2D nodes in ship.tscn positioned on port and starboard sides; each slot holds a cannon.tscn instance
3. **Cannon sub-scene** -- Small reusable scene: Sprite2D (cannon sprite) + Muzzle Marker2D at barrel tip for precise projectile spawning
4. **Broadside firing** -- Q fires all port cannons, E fires all starboard cannons
5. **ShipConfig Resource** -- Defines which hull variant, sail variant, and which cannon slots are filled/type. Runtime-swappable via code (e.g. `set_config(config)`)
6. **Cannonball projectile** -- Fires from muzzle point, travels straight, has a hitbox. Despawns with water splash if no collision

## Why This Approach

**Scene-Layered Composition** was chosen because:

- Marker2D nodes let you visually place cannon slots in the editor and see exactly where they'll be on the hull
- cannon.tscn as a sub-scene is reusable for enemies later and encapsulates the muzzle offset naturally
- ShipConfig Resource gives runtime part-swapping via `set_hull()` / `set_sail()` style methods without needing UI
- Fits the standard Godot composition pattern: scene tree hierarchy with data-driven configuration

Rejected alternatives:
- **Code-driven:** No editor visualization of placement, magic number offsets
- **AnimationPlayer:** Awkward fit for static data, doesn't compose well with runtime swapping

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Part scope | Hull + Sails + Cannons | Crew, flags, misc deferred -- enough for a ship that looks composed and can fight |
| Cannon placement | Marker2D slots in ship scene | Visual editor placement, survives part swaps |
| Slot configuration | ShipConfig Resource | Data-driven: defines which variants and which slots are filled |
| Firing model | Broadside (Q = port, E = starboard) | Classic pirate game feel, simple controls |
| Projectile spawn | Muzzle Marker2D on cannon scene | Pixel-precise firing from barrel tip, no offset math |
| Projectile behavior | Straight line + hitbox + splash on despawn | Collision-ready; splash provides visual feedback even with nothing to hit yet |
| Part swapping | Runtime via code API | Enables future upgrade/shop systems, no UI needed now |
| Hull sizes | Large (50x108) and Small (40x108) available | ShipConfig selects which hull + damage state |
| Sail variants | 24 large (66x47), 13 small (42x9) | Rich variety available in spritesheet |
| Cannon variants | 4 types: cannon, ball, loose, mobile (29x20 each) | Different visual states for different gameplay contexts |

## Asset Details

All parts come from `textures/ships_spritesheet.png` with region rects:

- **Hull large:** 50x108px, 4 damage states starting at (0, 522)
- **Hull small:** 40x108px, 4 damage states starting at (0, 632)
- **Sail large:** 66x47px, 24 variants in 6x4 grid starting at (0, 742)
- **Sail small:** 42x9px, 13 variants starting at (0, 932)
- **Cannon:** 29x20px cells starting at (0, 943) -- cannon, cannonBall, cannonLoose, cannonMobile
- **Cannonball sprite:** The `cannonBall.png` region at (29, 943, 29, 20)

## Scene Structure (Target)

```
Ship (CharacterBody2D)              scripts/ship.gd
  HullSprite (Sprite2D)             region from spritesheet
  SailSprite (Sprite2D)             region from spritesheet, layered on hull
  PortCannon1 (Marker2D)            editor-positioned slot
    Cannon (cannon.tscn instance)
  PortCannon2 (Marker2D)
    Cannon (cannon.tscn instance)
  StarboardCannon1 (Marker2D)
    Cannon (cannon.tscn instance)
  StarboardCannon2 (Marker2D)
    Cannon (cannon.tscn instance)
  Camera2D

cannon.tscn:
  Cannon (Node2D)                   scripts/cannon.gd
    CannonSprite (Sprite2D)         region from spritesheet
    Muzzle (Marker2D)               at barrel tip

cannonball.tscn:
  Cannonball (Area2D)               scripts/cannonball.gd
    Sprite2D                        cannonBall region
    CollisionShape2D
```

## Resolved Questions

- **Cannon orientation:** Sprites are horizontal (29x20), barrel pointing sideways. Port cannons fire left, starboard fire right -- perpendicular broadside. Rotation and flip_h handle both sides.
- **Sail positioning:** Sails layer on top of hull, anchored relative to hull center. Reference the pre-composed ship sprites to match visual alignment -- the large sail (66x47) is wider than the large hull (50x108), creating the natural sail overhang look.
- **Ship scale:** Current ship is 66x113 at 0.25 scale. Hull large (50x108) is nearly identical in proportion. Using 0.25 scale for all parts should produce a consistent look. Fine-tune per-part in editor if needed.
