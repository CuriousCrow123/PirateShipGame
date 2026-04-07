---
status: pending
priority: p1
issue_id: "001"
tags: [code-review, gdscript, timing]
---

# P1: Despawning enemy can fire one final invisible salvo

## Problem
`Main._despawn_distant_enemies` calls `enemy.queue_free()`, but `queue_free` is deferred — the node lives one more frame before deletion. During that extra frame, `EnemyShip._physics_process` runs once more and `_try_fire_at_target` can fire a cannon. The result: an invisible cannonball spawns from a 1000px-away despawning enemy.

## Findings
- timing reviewer flagged this as P2 (gameplay artifact, not crash).
- Affected file: scripts/enemy_ship.gd `_physics_process`, scripts/main.gd `_despawn_distant_enemies`.

## Recommended fix
Add `if is_queued_for_deletion(): return` at the top of `EnemyShip._physics_process`. Single guard, covers all despawn paths.

## Acceptance criteria
- [ ] No fire after `queue_free()`.
- [ ] No regression to normal firing path.
