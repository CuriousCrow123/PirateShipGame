---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, simplicity, yagni]
---

# P2: Demote `broadside_alignment_threshold` from @export to const

## Problem
It's exported but no scene/instance overrides it; it's a physics correctness value, not a balance knob.

## Recommended fix
Replace `@export var broadside_alignment_threshold: float = 0.85` with `const BROADSIDE_ALIGNMENT_THRESHOLD: float = 0.85`. Update references.

## Acceptance criteria
- [ ] Const declared, export removed.
- [ ] gdlint clean.
