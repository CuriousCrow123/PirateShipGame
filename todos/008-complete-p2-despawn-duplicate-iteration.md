---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, timing]
---

# P2: `_despawn_distant_enemies` should iterate `_enemies.duplicate()`

## Problem
The loop iterates `_enemies` directly while relying on `tree_exiting` to mutate `_enemies`. Today `tree_exiting` is deferred so it's safe, but the contract is fragile. Use `.duplicate()` like the cannonball water-impact loop already does.

## Recommended fix
Change `for enemy: EnemyShip in _enemies:` → `for enemy: EnemyShip in _enemies.duplicate():`.

## Acceptance criteria
- [ ] Despawn loop uses `.duplicate()`.
