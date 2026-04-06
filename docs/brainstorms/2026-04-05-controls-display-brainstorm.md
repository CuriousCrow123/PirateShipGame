# Controls Display — Brainstorm

**Date:** 2026-04-05
**Status:** Ready for planning

## What We're Building

A nautical chalkboard-style controls overlay that appears when the game starts, showing all player controls in a clean two-column layout (keys on the left, actions on the right). The game is paused while the overlay is visible. The player dismisses it with a keypress to begin playing.

This is the first UI element in the game — no HUD, CanvasLayer, or overlay currently exists.

## Why This Approach

- **Nautical chalkboard style** — dark slate/green background with chalk-white text fits the pirate theme without needing hand-drawn assets. A shader creates the chalkboard texture (chalk dust, subtle grain, worn edges).
- **Show on start, dismiss on keypress** — gives new players time to read controls without time pressure. Game is paused (process tree paused) so no enemies spawn or move.
- **Two-column key list** — simple and readable at 640x360 pixel resolution. Keys on left, descriptions on right. Grouped visually but not over-structured.
- **Shader-drawn chalkboard (Approach A)** — avoids external texture assets, leverages the project's existing shader expertise, and is easy to tweak. The project already uses custom shaders extensively (water, caustics, explosions).

## Key Decisions

1. **First CanvasLayer in the project** — the controls overlay will introduce CanvasLayer for the first time. It will be a child of the Main scene or instanced as its own scene.
2. **Game pauses while displayed** — use `get_tree().paused = true` with the overlay's `process_mode` set to `PROCESS_MODE_WHEN_PAUSED` so it remains interactive.
3. **Shader-based chalkboard background** — a custom `.gdshader` on a ColorRect for the board texture. Chalk-dust edge effects, subtle noise grain, dark green/slate color.
4. **Pixel font for text** — a pixel-art compatible font to match the game's aesthetic at 640x360. Chalk-white color with possible slight variation for a hand-written feel.
5. **Dismiss prompt** — a "Press any key to set sail..." (or similar) prompt at the bottom, possibly with a subtle pulsing animation to draw attention.

## Controls to Display

| Keys | Action |
|------|--------|
| W / Up Arrow | Sail Forward |
| S | Sail Backward |
| A | Turn Left |
| D | Turn Right |
| Q / Left Arrow | Fire Port Cannons |
| E / Right Arrow | Fire Starboard Cannons |
| Down Arrow | Drop Sea Mine |

## Resolved Questions

1. **Font choice** — add a pixel font asset to the project. A free pixel font that looks good at small sizes and fits the chalk/hand-drawn aesthetic. Better consistency with the pixel art game.
2. **Title text** — yes, a themed pirate-flavored title like "Captain's Orders" at the top of the chalkboard for personality.
