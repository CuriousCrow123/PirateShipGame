---
title: "Mesh.surface_set_material() Mutates the Shared Mesh Sub-Resource"
category: resource-safety
date: 2026-04-06
---

# Mesh.surface_set_material() Mutates the Shared Mesh Sub-Resource

## Problem

`ExplosionEffect` spawns real-time 3D particles inside a SubViewport. Each instance duplicates its shader material so per-instance shader parameters (colors, alpha scales) don't interfere with other instances.

But: when we added a new per-type shader param override (`BrightAlphaScale`) for cannonball impacts, we discovered that setting it on one instance **leaked** into every subsequent explosion of any type. A cannonball splash would set `BrightAlphaScale = 0.7`, and the next enemy-ship destruction inherited that value.

## Cause

The original duplication code was:

```gdscript
var base_mat: ShaderMaterial = _vertical_emitter.draw_pass_1.surface_get_material(0)
var mat: ShaderMaterial = base_mat.duplicate() as ShaderMaterial
_vertical_emitter.draw_pass_1.surface_set_material(0, mat)     # ← the bug
_horizontal_emitter.draw_pass_1.surface_set_material(0, mat)
```

`_vertical_emitter.draw_pass_1` is the `SphereMesh` sub-resource embedded in `explosion_model.tscn`. **That sub-resource is shared across every `ExplosionEffect` instance** — instantiating the scene does not deep-copy embedded sub-resources.

So `surface_set_material(0, mat)` mutated the shared SphereMesh. The next instance's `_ready()` called `surface_get_material(0)` and got the *previous* instance's modified material. `.duplicate()` then produced a copy with the previous instance's overrides baked in.

The original code happened to be safe as long as no one ever called `set_shader_parameter` on `mat` — and no one did, until we added per-instance overrides. Adding the first override surfaced a latent bug.

## Solution

Don't mutate the shared mesh at all. Use `GeometryInstance3D.material_override` on the `GPUParticles3D` node itself, which is instance-local:

```gdscript
var base_mat: ShaderMaterial = _vertical_emitter.draw_pass_1.surface_get_material(0)
var mat: ShaderMaterial = base_mat.duplicate() as ShaderMaterial
_vertical_emitter.material_override = mat
_horizontal_emitter.material_override = mat
```

`material_override` wins over the mesh's surface material for that particular GeometryInstance3D, without touching the mesh. Since the mesh is never written to, every new instance's `surface_get_material(0)` returns the pristine original — and `.duplicate()` gives a clean copy.

## Lesson

Any time you get a Resource via `get_node().some_property` (mesh, material, texture, whatever) and call a mutating method on it, you're probably mutating a **shared** sub-resource. Safe alternatives:

- `.duplicate()` the resource first, then mutate the copy, then assign the copy *back to the node* (not to the shared parent)
- Use a per-instance override property if one exists (`material_override`, `material_overlay`)
- Mark the sub-resource `resource_local_to_scene = true` in the .tscn to force fresh copies on instantiation (heavy-handed but correct)

A code comment like `# Duplicate so instances don't share` is a hint that someone already smelled this trap. Check whether the duplication actually reaches the thing you're mutating.
