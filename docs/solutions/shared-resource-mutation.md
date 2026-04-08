---
title: "Shared Curve Resource Mutation"
category: resource-issues
date: 2026-04-04
---

# Shared Resource Mutation Prevention

## Problem

Sub-resources defined in `.tscn` or `.tres` files are **shared by default** across all instances of that scene. If a script mutates a Resource at runtime (e.g., `width_curve.set_point_value()`), all instances sharing that Resource are affected.

This is especially dangerous with:
- `Curve` resources modified per-frame
- `Gradient` resources adjusted at runtime
- Any `Resource` subclass where you call setters

## Solution

Duplicate the Resource in `_ready()` before mutating:

```gdscript
func _ready() -> void:
    width_curve = width_curve.duplicate()  # Now safe to mutate every frame
```

## Rule

**Always `.duplicate()` any Resource that will be mutated at runtime.** This includes:
- `Curve` — `set_point_value()`, `add_point()`, `remove_point()`
- `Gradient` — `set_color()`, `set_offset()`
- `Material` — `set_shader_parameter()` (if per-instance values needed)
- Any custom `Resource` with runtime setters

## Reference

- Implementation: [trails.gd](../../scripts/water/trails.gd)
