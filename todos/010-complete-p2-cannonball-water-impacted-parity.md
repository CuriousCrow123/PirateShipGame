---
status: pending
priority: p2
issue_id: "010"
tags: [code-review, parity, vfx]
---

# P2: Cannonball `water_impacted` parity on body hits

## Problem
The class doc claims `water_impacted` fires on both the timeout path AND the body-hit paths "for parity". In reality, only `_impact()` (timeout) emits it; `_on_body_entered` skips emission. The result: a cannonball that hits a ship does not produce a displacement splash even though its explosion VFX plays.

## Recommended fix
Have body-hit branches also call `water_impacted.emit(global_position)` so Main spawns the displacement splash. The mine detonation check on enemy hits is harmless (mines won't be at ship-hit positions).

Alternative: revise the docstring to admit that body hits skip the splash. But the displacement parity is the better fix — visually consistent with the timeout.

## Acceptance criteria
- [ ] Both `_on_body_entered` branches emit `water_impacted` before `queue_free`.
- [ ] No regressions in player ↔ enemy hits.
