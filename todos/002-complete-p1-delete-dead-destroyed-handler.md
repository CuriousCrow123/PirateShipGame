---
status: pending
priority: p1
issue_id: "002"
tags: [code-review, simplicity, yagni]
---

# P1: Delete the empty `_on_enemy_destroyed` handler + signal connection

## Problem
The `destroyed` signal connection in `Main._try_spawn_enemy` and the `_on_enemy_destroyed` handler are pure dead code with a "reserved for future hooks" comment. YAGNI violation flagged by simplicity reviewer.

## Recommended fix
- Remove `enemy.destroyed.connect(_on_enemy_destroyed)` line in `_try_spawn_enemy`.
- Remove the `_on_enemy_destroyed` function entirely.
- Keep the `destroyed` signal on `EnemyShip` for now (zero-cost; may be wanted for future score/combo).

## Acceptance criteria
- [ ] No connect line, no handler.
- [ ] Project still runs cleanly.
