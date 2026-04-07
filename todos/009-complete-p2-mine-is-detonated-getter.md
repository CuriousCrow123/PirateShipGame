---
status: pending
priority: p2
issue_id: "009"
tags: [code-review, encapsulation]
---

# P2: Encapsulate `mine._is_detonated` access

## Problem
main.gd `_process` reads `mine._is_detonated` — pseudo-private cross-module access.

## Recommended fix
- Add `func is_detonated() -> bool: return _is_detonated` to `scripts/sea_mine.gd` (member ordering: place with other public methods).
- Replace `mine._is_detonated` in main.gd with `mine.is_detonated()`.

## Acceptance criteria
- [ ] No cross-module `_is_detonated` access in main.gd.
- [ ] gdlint clean.
