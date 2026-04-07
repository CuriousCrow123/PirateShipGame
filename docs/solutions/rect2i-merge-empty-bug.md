---
title: "Rect2i.merge() Inflates Union When Input Is Empty"
category: gdscript-gotchas
date: 2026-04-06
---

# Rect2i.merge() Inflates Union When Input Is Empty

## Problem

`Image.get_used_rect()` returns `Rect2i(0, 0, 0, 0)` for a fully transparent image. When that empty rect is merged with a valid rect via `Rect2i.merge()`, the result is expanded to include position `(0, 0)` — because `merge()` treats `(0,0)` as a real coordinate, not a sentinel.

This was discovered while building a trim-to-union bounding box across an explosion's animation frames. The early and mid frames had particles clustered around position `(312, 316)` in a 640x640 SubViewport, but the final few frames were fully transparent (particles had dissolved). Those empty frames dragged the union rect all the way to the top-left corner.

## Symptom

A crop computed as the union of 25 frames returned `(0, 0) → (389, 336)` even though every individual frame's `get_used_rect()` was tightly clustered near the viewport center. The resulting sprite sheet was ~90% empty space.

Per-frame debug output revealed the culprit:

```
frame 20 used_rect: pos=(320,320) size=(27,5)
frame 21 used_rect: pos=(320,320) size=(25,3)
frame 22 used_rect: pos=(0,0) size=(0,0)      ← empty frame
frame 23 used_rect: pos=(344,322) size=(1,1)
frame 24 used_rect: pos=(0,0) size=(0,0)      ← empty frame
```

## Solution

Skip empty rects (size 0 in either dimension) before merging:

```gdscript
var union_rect := Rect2i()
var has_first: bool = false
for frame: Image in frames:
    var used: Rect2i = frame.get_used_rect()
    if used.size.x == 0 or used.size.y == 0:
        continue
    if not has_first:
        union_rect = used
        has_first = true
    else:
        union_rect = union_rect.merge(used)
```

## Why It Happens

`Rect2i.merge(other)` computes the smallest rect containing both input rects. There is no concept of "empty rect as identity element" — an empty `Rect2i(0,0,0,0)` is still a rect positioned at `(0,0)`, and merging with it forces the result to include that point.

The same bug applies to `Rect2.merge()` for float rects.

## Where This Matters

Anywhere you compute a union bounding box over data that may contain fully transparent / empty entries:

- Sprite sheet trimming across animation frames
- UI auto-sizing from optional child rects
- Collision bound aggregation from possibly-disabled shapes
