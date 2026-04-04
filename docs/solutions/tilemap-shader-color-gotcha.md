---
title: "TileMap Shader COLOR Gotcha"
category: shader-issues
date: 2026-04-04
godot_issue: "https://github.com/godotengine/godot/issues/69766"
---

# TileMap Shader COLOR Gotcha

## Problem

In a TileMap's `canvas_item` shader, `COLOR.x` in `fragment()` does **not** give you the raw vertex/modulate color. By the time `fragment()` runs, Godot has already multiplied `COLOR` by the tile's texture sample:

```
fragment() COLOR = texture(TEXTURE, UV) * vertex_color * modulate * self_modulate
```

If you're trying to read per-tile modulate as a data channel (e.g., foam heightmap), `COLOR.x` gives you `texture.r * modulate.r` — not pure `modulate.r`.

## Solution

Capture the vertex color in a `varying` during `vertex()`, where it hasn't been mixed with texture yet:

```glsl
varying vec4 var_VertexColor;

void vertex() {
    var_VertexColor = COLOR;  // Pure vertex_color * modulate here
}

void fragment() {
    float foamHeight = var_VertexColor.x;  // Clean modulate data
}
```

## When This Matters

- Reading per-tile modulate as a data channel (foam height, depth, etc.)
- Any shader that needs to separate tile texture from tile metadata
- NOT needed if you intentionally want texture * modulate (the common case)

## Reference

- [Godot #69766](https://github.com/godotengine/godot/issues/69766)
- Implementation: [water_surface.gdshader](../../shaders/water_surface.gdshader)
