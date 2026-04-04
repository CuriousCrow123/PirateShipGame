---
title: "SubViewport Premultiplied Alpha on Forward+"
category: rendering-issues
date: 2026-04-04
godot_issue: "https://github.com/godotengine/godot/issues/99715"
---

# SubViewport Premultiplied Alpha on Forward+

## Problem

When a SubViewport has `transparent_bg = true` and uses the Forward+ renderer, the ViewportTexture outputs **premultiplied alpha**. Semi-transparent areas in the viewport texture appear darker than expected when displayed on a Sprite2D.

## Solution

Use `render_mode blend_premul_alpha` in the shader applied to the Sprite2D displaying the viewport texture:

```glsl
shader_type canvas_item;
render_mode blend_premul_alpha;  // Fixes dark semi-transparent areas
```

Alternatively, use a `CanvasItemMaterial` with `blend_mode = BLEND_MODE_PREMULT_ALPHA`.

## Reference

- [Godot #99715](https://github.com/godotengine/godot/issues/99715)
- Implementation: [ripple.gdshader](../../shaders/ripple.gdshader)
