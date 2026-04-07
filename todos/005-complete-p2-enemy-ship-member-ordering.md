---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, gdscript, conventions]
---

# P2: enemy_ship.gd member ordering — public methods after virtuals

## Problem
`is_destroyed()`, `setup()`, `consume_wake_distance()`, `get_wake_ring_position()` are placed before `_physics_process`, violating the project ordering convention (signals → enums → constants → exports → vars → @onready → _ready → _process → public → private).

## Recommended fix
Move public methods below `_physics_process` and `take_damage` (which is also public — should be in the public block).

## Acceptance criteria
- [ ] gdlint passes (no class-definitions-order errors).
- [ ] No semantic changes.
