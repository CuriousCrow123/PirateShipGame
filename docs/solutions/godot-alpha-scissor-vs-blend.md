---
title: "ALPHA_SCISSOR_THRESHOLD Forces Opaque Rendering (Ignores ALPHA)"
category: shader-gotchas
date: 2026-04-06
---

# ALPHA_SCISSOR_THRESHOLD Forces Opaque Rendering

## Problem

We wanted a spatial shader to produce semi-transparent output (e.g. smoky explosions fading out gradually) by setting `ALPHA = dark_mask * 0.65`. The result was fully opaque — the multiplier had no visible effect.

Confirmed by sampling pixel alpha in captured viewport textures: every surviving pixel was either `0.0` or `1.0`, never a value in between.

## Cause

The shader had:

```glsl
ALPHA = dark_mask * 0.65;
ALPHA_SCISSOR_THRESHOLD = 0.5;
```

Setting `ALPHA_SCISSOR_THRESHOLD` puts the shader into **alpha-tested** rendering mode, not alpha-blended:

- If `ALPHA >= threshold` → fragment is rendered **fully opaque**, ignoring the ALPHA value
- If `ALPHA < threshold` → fragment is discarded entirely

So our `* 0.65` scale was pointless: the scissor snapped surviving pixels back to `1.0` before composition.

## Solution

Remove `ALPHA_SCISSOR_THRESHOLD` entirely. The shader then enters **transparent blending** mode and uses the full `ALPHA` value for alpha compositing:

```glsl
ALPHA = dark_mask * 0.65;
// No ALPHA_SCISSOR_THRESHOLD — that would force opaque/discard and kill blending.
```

For the explosion dissolve shader we kept a similar hard-edge look via the existing `smoothstep(0.0, SmoothStepEdge, dark_raw)` in the alpha calculation, which gives a soft-but-quick falloff without needing scissor.

## When to use scissor vs blend

**Alpha scissor** is for things like foliage, grates, or masked cutouts where you want *hard edges* and want to avoid depth-sort overhead — the object is still rendered in the opaque pass and Z-writes normally.

**Alpha blend** (no scissor) is for smoke, glass, particles, fog — anywhere you need *graduated* transparency. The object is rendered in the transparent pass, which requires depth sorting and has more overhead.

Picking the wrong one won't crash anything — it just silently ignores your alpha math.
