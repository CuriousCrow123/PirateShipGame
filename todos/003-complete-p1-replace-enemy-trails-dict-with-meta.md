---
status: pending
priority: p1
issue_id: "003"
tags: [code-review, simplicity]
---

# P1: Replace `_enemy_trails` dict with metadata on the enemy

## Problem
The `_enemy_trails: Dictionary` exists only to recover the per-enemy Line2D from the enemy at cleanup time. Stash the Line2D directly on the enemy via `set_meta`/`get_meta` (or a typed `var _wake_line: Line2D` on EnemyShip) and remove the dictionary indirection.

## Recommended fix
- Use `enemy.set_meta("wake_line", line)` in `_register_enemy_wake`.
- In `_unregister_enemy_wake`, read with `enemy.get_meta("wake_line", null)` and clear via `remove_meta`.
- Delete the `_enemy_trails` field.

## Acceptance criteria
- [ ] Dict field gone.
- [ ] Wake trails still register/unregister correctly across spawn, kill, despawn.
