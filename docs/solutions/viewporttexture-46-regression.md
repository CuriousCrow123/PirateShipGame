---
title: "ViewportTexture 4.6 Defensive Assignment"
category: configuration-fixes
date: 2026-04-04
godot_issue: "https://github.com/godotengine/godot/issues/115402"
---

# ViewportTexture 4.6 Defensive Assignment

## Problem

In Godot 4.6, ViewportTextures defined in `.tscn` files can break (show magenta) after save/reload in the editor. The texture reference to the SubViewport becomes invalid.

## Solution

Assign the ViewportTexture in code during `_ready()`:

```gdscript
func _ready() -> void:
    var vt := ViewportTexture.new()
    vt.viewport_path = $SubViewport.get_path()
    $TrailSprite.texture = vt
```

This recreates the texture reference at runtime, bypassing the serialization issue.

## Reference

- [Godot #115402](https://github.com/godotengine/godot/issues/115402)
- Implementation: [main.gd](../../scripts/main.gd)
