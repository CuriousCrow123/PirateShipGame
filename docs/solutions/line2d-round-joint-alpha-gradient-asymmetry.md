---
title: "Line2D Round Joints + Varying-Alpha Gradient = Direction-Asymmetric Rendering"
category: godot-engine-bugs
date: 2026-04-07
godot_source: "https://github.com/godotengine/godot/blob/master/scene/2d/line_builder.cpp#L481-L503"
---

# Line2D Round Joints + Varying-Alpha Gradient = Direction-Asymmetric Rendering

## Problem

A `Line2D` configured with:
- `joint_mode = LINE_JOINT_ROUND` (and/or `LINE_CAP_ROUND` on the caps)
- A `gradient` whose **alpha** varies along the line (e.g., `[Color(1,1,1,0), Color(1,1,1,1)]` for a fade-in)

…renders **direction-asymmetrically**. The same line geometry, mirrored across an axis, produces visibly different brightness and effective length depending on which way the line points. In a steered pirate ship's wake trail, the trail behind the ship looked clearly **brighter and longer when sailing up-right (+x −y)** than when sailing in the other three diagonal quadrants.

## Symptom

Same Line2D, same width, same gradient, same number of points (50), same speed:

| Velocity quadrant | Trail visible? | Brightness |
|---|---|---|
| `+x −y` (up-right) | very visible | bright white, ~30 px long |
| `+x +y` (down-right) | barely | faint |
| `−x −y` (up-left) | barely | faint |
| `−x +y` (down-left) | barely | nearly invisible |

The bias is consistent and reproducible at any speed above ~30 u/s. Sub-viewport texture content, captured via `SubViewport.get_texture().get_image()`, is **symmetric across all four quadrants** — the asymmetry only appears in the on-screen output, after Godot rasterizes the Line2D.

## Root Cause

In [`scene/2d/line_builder.cpp`](https://github.com/godotengine/godot/blob/master/scene/2d/line_builder.cpp), the helper that emits triangle-fan vertices for `LINE_JOINT_ROUND` and `LINE_CAP_ROUND` is `strip_add_tri` (lines 481-503):

```cpp
void LineBuilder::strip_add_tri(Vector2 up, Orientation orientation) {
    int vi = vertices.size();
    vertices.push_back(up);
    if (_interpolate_color) {
        colors.push_back(colors[colors.size() - 1]);   // ← line 487
    }
    ...
    if (texture_mode != Line2D::LINE_TEXTURE_NONE) {
        // UVs are just one slice of the texture all along
        uvs.push_back(uvs[_last_index[opposite_orientation]]);   // ← line 495
    }
    ...
}
```

**Every fan vertex inherits the color of whatever vertex was pushed most recently** — which after the preceding `strip_add_quad` is the post-corner gradient sample (`color1`). The fan is *not* sampled across the gradient; the entire round joint is uniformly colored with the post-corner color, and its UV is clamped to a single slice of the texture.

The cap-fan helper `new_arc` (lines 534-598) has the same problem: cap fan vertices are all painted a single uniform color (`gradient[0]` for the begin cap, `gradient[N-1]` for the end cap). For a `[transparent, opaque]` fade-in gradient, the entire begin-cap fan is fully transparent, and the entire end-cap fan is fully opaque.

### Why direction matters

The variable `orientation` (UP or DOWN — which side of the line the joint fan attaches to) is computed from the **signed turn direction** at line 187-188:

```cpp
float dp = u0.dot(f1);
Orientation orientation = (dp > 0.f) ? UP : DOWN;
```

So as the ship rotates, the joint fans flip from one side of the strip to the other. Combined with the uniform-color fan vertices above, the rendered line accumulates a directional bias: half-turns brighten the line (fan biased toward the high-alpha edge), half-turns dim it. Over ~50 accumulated joints in the wake trail, this compounds into the visible asymmetry, and *which way it compounds correlates with the recent steering history*, which strongly correlates with current velocity direction.

### Why varying-RGB gradients don't trigger it

There's no premultiplication of alpha in `line_builder.cpp` — vertex `color.rgb` and `color.a` interpolate independently and only combine in the fragment shader during the final blend. With **constant alpha**, the wrong-RGB joint vertices are at most a few-pixel hue artifact under the texture, swallowed by the standard `(SRC_ALPHA, ONE_MINUS_SRC_ALPHA)` blend.

With **varying alpha**, the wrong-alpha vertices directly change pixel **coverage** against the framebuffer — visible everywhere the joint fan exists, on whichever side it happens to be sewn into.

## Solution

Use `LINE_JOINT_BEVEL` instead of `LINE_JOINT_ROUND`. Bevel joints add only a single triangle per joint (vs. a full triangle-fan for round), so the bug's footprint shrinks from "round-fan width" to "single-tri width" — small enough to be visually invisible at our line width and never accumulates into a directional bias.

In [scenes/main.tscn](../../scenes/main.tscn) on the trail's `Line2D` node:

```tscn
joint_mode = 1   ; LINE_JOINT_BEVEL (was 2 = LINE_JOINT_ROUND)
```

Cap modes can stay as `LINE_CAP_ROUND` — the caps are at the head (always at the ship) and tail (always faded out via the gradient), so the per-fan uniform color happens to be the correct color in our usage.

## Alternatives Considered

| Alternative | Result |
|---|---|
| Remove `gradient` entirely, rely on `WaterTrailGradient.png` + `LINE_TEXTURE_STRETCH` for fade | Symmetric, but the visual fade was too weak — the texture's alpha is constant, so removing the gradient removed the actual head-to-tail alpha falloff |
| Constant-alpha gradient `(1,1,1,1) → (1,1,1,1)` | Symmetric, but no fade — trail looks like a hard-edged stripe |
| Varying-RGB gradient `(0,0,0,1) → (1,1,1,1)` (black-to-white) | Symmetric and gives a fade through the ripple shader's `tex.r` math, but didn't match the original visual style |
| `LINE_JOINT_BEVEL` + original alpha-fade gradient | **Selected** — symmetric *and* preserves the original look |

## Why this isn't a known Godot issue

I searched [godotengine/godot issues](https://github.com/godotengine/godot/issues) for variations of "Line2D gradient direction asymmetric", "Line2D round cap alpha", "Line2D rotation visual artifact". The closest match is [#35878](https://github.com/godotengine/godot/issues/35878) (Line2D + AA + alpha causes ghost wireframe lines) — different cause, same neighborhood. This specific bug appears unfiled. The relevant code in `line_builder.cpp` is essentially unchanged between Godot 4.0 and current `master` (as of 2026-04-07).

## Reference

- Affected file: [`scene/2d/line_builder.cpp:481-503`](https://github.com/godotengine/godot/blob/master/scene/2d/line_builder.cpp#L481-L503) (joint fan), `534-598` (cap fan)
- Affected variable: `orientation` computed from signed turn direction at lines 187-188
- Project workaround: [scenes/main.tscn](../../scenes/main.tscn) Line2D node, `joint_mode = 1`
- Discovered in: PirateShipGame wake trail rendering, while debugging quadrant-asymmetric trail brightness
