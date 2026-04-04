# ADR 001: Water Shader Approach

**Date:** 2026-04-04
**Status:** Accepted

## Context

The PirateShipGame needs an animated water surface for its ocean environment. We needed to choose between:

1. Building a water shader from scratch
2. Porting an existing proven implementation
3. Using Godot's VisualShader editor
4. Using a code shader (.gdshader)

## Decision

**Port from jess-hammer/2d-pixel-water-shader-godot using code shaders (.gdshader).**

### Why code shaders over VisualShader

- The reference provides complete, tested GLSL code — direct copy-paste into `.gdshader`
- VisualShader graphs are opaque binary in `.tres` files — hard to review, diff, or merge
- Code shaders allow commenting out deferred features (specular, fade) with clear TODO markers
- Easier to understand the technique by reading the GLSL directly

### Why port from reference rather than build from scratch

- The reference is a complete, proven pixel-art water effect with all visual components
- Building caustics + foam + ripple trails from scratch would take significantly longer
- The reference's technique (world-space UV locking via `floor()`) is the correct approach for pixel art

## Key Technical Decisions

### var_VertexColor varying for TileMap foam

In Godot 4 TileMap shaders, `COLOR.x` in `fragment()` already includes the tile texture multiplied in. To read the raw vertex color (modulate) for foam height, we capture it in a `varying` during `vertex()`. This works around Godot issue [#69766](https://github.com/godotengine/godot/issues/69766).

In practice, we read foam height from `texture(TEXTURE, UV).r * var_VertexColor.x` — the baked tile gradients provide per-pixel foam data, with modulate as an optional multiplier.

### Noise textures as inline NoiseTexture2D

The original repo uses FastNoiseLite-based NoiseTexture2D sub-resources (not PNG files) for movement noise, foam noise, and deferred specular/fade noise. We replicate this as sub-resources in the ShaderMaterial `.tres` file.

### blend_premul_alpha on ripple shader

Forward+ SubViewport with `transparent_bg=true` outputs premultiplied alpha. Without `render_mode blend_premul_alpha`, ripple areas render too dark. See Godot issue [#99715](https://github.com/godotengine/godot/issues/99715).

## Consequences

- Shader parameters match the reference and can be tuned without code changes
- Deferred features (specular, fade, caustic highlights) can be enabled by uncommenting ~20 LOC and wiring 4 additional textures
- Trail system can be adapted for boat movement by changing `follow_target` export
- Code shaders are version-controlled and diffable

## Alternatives Considered

- **VisualShader**: Rejected — binary format, harder to maintain, no advantage for ported code
- **Custom from scratch**: Rejected — unnecessary when proven reference exists
- **GDShaderMaterial plugin**: Rejected — adds dependency for no benefit over raw `.gdshader`
