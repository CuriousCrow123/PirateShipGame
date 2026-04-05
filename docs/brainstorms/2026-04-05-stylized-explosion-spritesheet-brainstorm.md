# Stylized Explosion Spritesheet Tool

**Date:** 2026-04-05
**Status:** Brainstorm

## What We're Building

An offline tool scene within PirateShipGame that renders a stylized 3D explosion effect and captures it as a 2D spritesheet strip. The tool lives at `scenes/tools/explosion_renderer.tscn` and is run independently from the game.

**The explosion effect** recreates the tutorial's approach:
- A spatial shader combining fresnel + noise texture for dissolve (outside-in)
- Two GPUParticles3D emitters: vertical (cone) + horizontal (circle)
- Sphere mesh particles with the dissolve shader
- Dark color + bright/fire color layers, each with independent dissolve curves
- Smoothstep control for stylized (hard edge) vs realistic (soft) look

**The capture pipeline:**
- 3D scene rendered into a SubViewport
- Camera3D captures the explosion
- SubViewport displayed in 2D for live preview
- Tweakable parameters (colors, dissolve speed, smoothstep, etc.) via UI controls
- "Capture" button renders 8 frames into a horizontal strip PNG (8 x 32px = 256x32)

**The output** matches the project's pixel-art style:
- 32x32px per frame
- Quantized colors (floor/ceil stepping, matching water/ripple shader patterns)
- Nearest-neighbor filtering
- Single-row horizontal strip PNG saved to `textures/`

## Why This Approach

- **Full 3D recreation** of the tutorial preserves the distinctive fresnel dissolve look that makes the effect interesting
- **Offline tool** keeps VFX rendering separate from game runtime — no 3D overhead in the 2D game
- **SubViewport capture** is a proven pattern in this project (already used for wake trail)
- **Preview + tweak workflow** lets you iterate on the look before committing to a spritesheet
- **Reusable pipeline** — the capture system could render other 3D VFX to spritesheets later

## Key Decisions

1. **Full 3D with GPUParticles3D** over 2D approximation or shader-only — preserves the tutorial's fresnel effect authenticity
2. **Tool scene in this repo** (not a separate project) — convenient access, shares project settings
3. **8 frames at 32x32px** — snappy burst that fits the 640x360 viewport scale
4. **Single-row strip PNG** — simple format, easy to load as SpriteFrames or region-rect
5. **Quantized pixel-art output** — matches existing water/ripple shader aesthetic (floor/ceil stepping)
6. **Preview + tweak UI** — editable parameters with a capture button, not auto-run

## Key Components

### Spatial Shader (explosion_dissolve.gdshader)
- Noise texture sampling + fresnel (inverted with 1-minus for outside-in dissolve)
- Two layers: dark color (fresnel power 0.5) and bright color (fresnel power 1.0)
- Dissolve controlled by custom particle data via UV2 (X = bright, Y = dark)
- Smoothstep for edge hardness control
- Alpha clipping for stylized look

### GPUParticles3D Setup (x2)
- Vertical emitter: cone shape
- Horizontal emitter: circle shape (rotated -90 on X)
- Burst of ~30 particles, lifetime 1.5-4s, mesh render mode (sphere)
- Velocity drag ~0.75, random rotation
- Custom data curves driving dissolve over lifetime

### Capture System
- SubViewport at render size (e.g. 128x128 for quality, downscaled to 32x32)
- Camera3D framing the explosion
- Timer-based frame capture at even intervals across explosion lifetime
- Quantization pass on captured pixels
- Composite into horizontal strip and save as PNG

### Preview UI
- TextureRect showing live SubViewport output
- Sliders/spinboxes for: dark color, fire color (HDR), smoothstep value, simulation speed, frame count
- "Play" button to restart the explosion
- "Capture" button to render and save the strip

## Open Questions

None — all key decisions resolved through brainstorming.

## References

- Tutorial transcript: stylized explosion effect using fresnel + noise dissolve on mesh particles
- Existing project pattern: SubViewport rendering (wake trail system)
- Existing shader pattern: quantization via `floor(value * steps) / steps`
