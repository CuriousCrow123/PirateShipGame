# Water Ripple Distortion Brainstorm

**Date:** 2026-04-05
**Status:** Ready for planning

## What We're Building

Replace the current expanding-circular-lines ripple effects with actual UV distortion of the water surface. When a ripple passes, the water's caustics, specular highlights, and color patterns visibly warp — creating a convincing refraction-like effect from the top-down perspective.

### Current State

- Ship wake: brightness/alpha overlay via SubViewport + Line2D ([ripple.gdshader](../../shaders/ripple.gdshader))
- Mine idle bob: expanding concentric ring lines ([sea_mine_ripple.gdshader](../../shaders/sea_mine_ripple.gdshader))
- Mine explosion: tweened expanding ring lines (spawned in [sea_mine.gd](../../scripts/sea_mine.gd))
- Cannonball impact: explosion VFX only, no water ripple at all
- **None of these actually displace the water surface UVs**

### Target State

All ripple sources (ship wake, cannonball impacts, mine bob, mine explosions) produce visible UV warping of the water surface. The water's own caustic/specular layers shift position as waves pass through.

## Why This Approach

### Displacement Map via SubViewport (Industry Standard)

A dedicated SubViewport renders interaction "stamps" (white radial gradients) at ripple source positions. These stamps fade over time. The water surface shader reads this SubViewport texture as a UV displacement map, offsetting `worldFloor` before sampling caustics and specular.

**Why this over alternatives:**
- **Industry standard** — virtually every shipped indie game with interactive water distortion uses this pattern (render interaction events to off-screen buffer, read as displacement)
- **Unlimited simultaneous ripples** — just draw more stamps, no uniform array limits
- **All ripple types use one system** — ship wakes, point impacts, and explosions all just spawn stamps of different shapes
- **Builds on existing infrastructure** — the project already has a SubViewport trail system that will be converted
- **Decoupled** — game objects just emit stamps; they don't need to know about the water shader

**Why not procedural sine waves:**
- Become a uniform management nightmare with 10+ simultaneous sources
- Hard to art-direct (changing shape = changing math)
- Mainly a tutorial/demo technique, not used in shipped games for interactive ripples

**Why not ping-pong wave simulation (yet):**
- "Stamp and fade" gets 90% of the visual quality at 30% of the complexity
- At 640x360 with pixel art, the difference is subtle
- Can upgrade later without changing the water shader — only the SubViewport pipeline changes
- Worth pursuing if we want physically propagating chain reaction waves later

## Key Decisions

1. **Displacement map SubViewport** — single system for all ripple types, replacing the current brightness overlay trail
2. **Replace existing wake trail SubViewport** — convert the current [trails.gd](../../scripts/trails.gd) SubViewport from brightness overlay to displacement data output. One system replaces two.
3. **Distort water surface only** — modify `worldFloor` UV in [water_surface.gdshader](../../shaders/water_surface.gdshader) before sampling caustics/specular. Ships and above-water objects are unaffected.
4. **Foam is NOT distorted** — foam reads from tile-local UV and is a surface feature that rides on waves. Caustics and specular are distorted; foam stays put.
5. **Pixel-snapped by default** — quantize displacement offsets to whole-pixel steps. Can relax to sub-pixel later if it looks better.
6. **All sources produce distortion** — ship wake, cannonball splashes, mine idle bobs, mine explosions

## Integration Points

### Water Surface Shader ([water_surface.gdshader](../../shaders/water_surface.gdshader))

Add displacement map sampling after `worldFloor` computation, before caustic/specular sampling:

```glsl
uniform sampler2D DisplacementMap : filter_linear;
uniform float DisplacementStrength : hint_range(0.0, 20.0) = 5.0;

// After: vec2 worldFloor = floor(var_WorldPos);
vec2 disp_uv = /* project worldFloor into displacement SubViewport space */;
vec2 displacement = (texture(DisplacementMap, disp_uv).rg - 0.5) * DisplacementStrength;
vec2 distortedWorldFloor = worldFloor + displacement;
// Use distortedWorldFloor for caustic and specular sampling
// Keep worldFloor for foam sampling
```

### SubViewport Conversion

The existing 1024x1024 SubViewport (used by [trails.gd](../../scripts/trails.gd)) gets repurposed:
- Instead of rendering a visible Line2D trail, render displacement gradient stamps
- R channel = X displacement, G channel = Y displacement, 0.5 = neutral
- Stamps are spawned by game events, fade over time via alpha decay or tween

### Ripple Stamp Sources

| Source | Stamp Shape | Trigger |
|--------|------------|---------|
| Ship wake | V-shaped or radial at ship position each frame | Continuous while moving |
| Cannonball impact | Expanding radial gradient | `water_impacted` signal |
| Mine idle bob | Small pulsing radial | Continuous, synced to bob phase |
| Mine explosion | Large expanding radial | Detonation |

## Open Questions

None — all questions resolved during brainstorming.

## Upgrade Path

**Ping-pong wave simulation:** If we later want physically propagating waves (mine explosion wave visibly traveling outward, chain reactions), we can swap the "stamp and fade" SubViewport for a double-buffered wave equation solver. The water surface shader does not change — only the SubViewport pipeline changes.

## Sources

- [Minions Art: Making Interactive Water using RenderTexture](https://www.patreon.com/posts/making-water-24192529) — canonical render-texture approach
- [Cyanilux: 2D Water Shader Breakdown](https://www.cyanilux.com/tutorials/2d-water-shader-breakdown/) — UV distortion with tile-aware edge handling
- [Dynamic Water Demo (John Wigg)](https://john-wigg.dev/DynamicWaterDemo/) — ping-pong wave equation in Godot
- [Hugo Elias Water Algorithm](https://web.archive.org/web/20160418004149/http://freespace.virgin.net/hugo.elias/graphics/x_water.htm) — classic wave propagation reference
- [Godot Docs: SubViewport as Texture](https://docs.godotengine.org/en/stable/tutorials/shaders/using_viewport_as_texture.html)
