---
status: pending
priority: p2
issue_id: "004"
tags: [code-review, gdscript, timing]
---

# P2: Mirror EnemyShip's float-counter cooldowns into Ship

## Problem
`scripts/ship.gd` still uses `get_tree().create_timer(...).timeout.connect(lambda)` for port/starboard/mine cooldowns. SceneTreeTimer captures `self`; if the player is ever freed (scene change, restart), the lambda fires on a freed instance.

## Recommended fix
Replace `_port_ready: bool` / `_starboard_ready: bool` / `_mine_ready: bool` with float counters decremented in `_physics_process`. Mirror EnemyShip's pattern exactly. Drop the `create_timer.timeout.connect` calls.

## Acceptance criteria
- [ ] No SceneTreeTimer cooldowns in ship.gd.
- [ ] Cooldowns still work — observable by spam-testing port/starboard fire.
- [ ] gdformat/gdlint clean.
