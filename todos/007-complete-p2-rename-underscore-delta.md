---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, gdscript, conventions]
---

# P2: Rename `_delta` → `delta` in main.gd `_process` (parameter is used)

## Problem
GDScript convention: `_`-prefixed parameters are unused. main.gd `_process(_delta)` uses `_delta` in `enemy.velocity.length() * _delta`. Misleading name.

## Recommended fix
Rename parameter from `_delta` to `delta` in the `_process` signature and update its single use.

## Acceptance criteria
- [ ] Parameter is `delta`.
- [ ] gdformat/gdlint clean.
