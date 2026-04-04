# Plan: Integrate bfollington-terma-godot into godot-compound

## Context

The `bfollington-terma-godot` skill (project-local at `.claude/skills/bfollington-terma-godot/`) contains valuable Godot development knowledge that should live in the `godot-compound` plugin (`~/.claude/godot-compound/`) so it's available across all Godot projects, not just PirateShipGame.

**Key value from terma-godot not already in godot-compound:**
1. **File format syntax** (`file-formats.md`) -- .tscn/.tres syntax rules, ExtResource/SubResource mechanics, instance property overrides. Zero coverage in godot-compound.
2. **Physics API** (`godot4-physics-api.md`) -- raycasting, shape queries, collision layers. No equivalent exists.
3. **Common pitfalls** (`common-pitfalls.md`) -- @onready timing, CharacterBody3D movement, transform confusion, tween issues. ~90% net-new vs existing timing-async.md/resource-system.md.
4. **Validation scripts** (`validate_tres.py`, `validate_tscn.py`) -- automated .tres/.tscn file validation.
5. **Code templates** (5 .gd/.tres files) -- component, attribute, interaction, spell, item templates.
6. **GUT testing guide** -- setup, writing tests, running from CLI.
7. **Godot CLI reference** -- headless runs, debug flags, exports, script validation.
8. **MCP tool documentation** -- godot-mcp tool table and workflows.

**Content to skip (already covered by godot-compound):**
- Architecture patterns (component composition, signals, state machines) -- covered by `scene-architecture.md` and `gdscript-quality.md`
- Basic principles (composition over inheritance, call down/signal up) -- in CLAUDE.md and godot-patterns

## Approach: Expand godot-patterns + add new skill

### Step 1: Create `godot-file-formats` skill (new)

Create `~/.claude/godot-compound/skills/godot-file-formats/` with:

- **SKILL.md** -- Non-invocable skill focused on .tscn/.tres file editing. Points to references and includes validation script docs.
- **references/file-formats.md** -- Copy verbatim from terma-godot
- **references/common-pitfalls.md** -- Copy from terma-godot, removing sections already covered by `timing-async.md` and `resource-system.md` (resource `.duplicate()` and signal timing pitfalls). Add cross-references to godot-patterns for those topics.
- **scripts/validate_tres.py** -- Copy from terma-godot
- **scripts/validate_tscn.py** -- Copy from terma-godot
- **assets/templates/spell_resource.tres** -- Copy from terma-godot
- **assets/templates/item_resource.tres** -- Copy from terma-godot

### Step 2: Expand godot-patterns skill

Add to `~/.claude/godot-compound/skills/godot-patterns/`:

- **references/physics-api.md** -- Copy `godot4-physics-api.md` from terma-godot
- **assets/templates/component_template.gd** -- Copy from terma-godot
- **assets/templates/attribute_template.gd** -- Copy from terma-godot
- **assets/templates/interaction_template.gd** -- Copy from terma-godot
- Update **SKILL.md** to reference the new physics-api.md and templates

### Step 3: Update CLAUDE.md

Add to `~/.claude/godot-compound/CLAUDE.md`:

- **MCP: godot-mcp** section -- tool table and workflow guidance from terma-godot SKILL.md
- **Godot CLI** section -- key CLI commands (headless run, script validation, debug flags, exports)
- **GUT Testing** section -- setup, running tests, what to test
- **File Validation** section -- how to run validate_tres.py / validate_tscn.py

### Step 4: Update plugin.json

- Bump version to 0.4.0 (new skill = minor bump)
- Add godot-mcp to mcpServers config

### Step 5: Update CHANGELOG.md

Add v0.4.0 entry documenting the integration.

## Files to modify

| File | Action |
|------|--------|
| `~/.claude/godot-compound/skills/godot-file-formats/SKILL.md` | Create |
| `~/.claude/godot-compound/skills/godot-file-formats/references/file-formats.md` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-file-formats/references/common-pitfalls.md` | Copy + deduplicate |
| `~/.claude/godot-compound/skills/godot-file-formats/scripts/validate_tres.py` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-file-formats/scripts/validate_tscn.py` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-file-formats/assets/templates/spell_resource.tres` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-file-formats/assets/templates/item_resource.tres` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-patterns/references/physics-api.md` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-patterns/assets/templates/component_template.gd` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-patterns/assets/templates/attribute_template.gd` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-patterns/assets/templates/interaction_template.gd` | Copy from terma-godot |
| `~/.claude/godot-compound/skills/godot-patterns/SKILL.md` | Edit -- add physics + templates refs |
| `~/.claude/godot-compound/CLAUDE.md` | Edit -- add MCP, CLI, GUT, validation sections |
| `~/.claude/godot-compound/.claude-plugin/plugin.json` | Edit -- version bump + godot-mcp |
| `~/.claude/godot-compound/CHANGELOG.md` | Edit -- add v0.4.0 entry |

## Verification

1. Check all new files exist with correct content
2. Verify SKILL.md references point to actual files
3. Verify validation scripts are executable (`python3 scripts/validate_tres.py --help`)
4. Run `ls -R ~/.claude/godot-compound/skills/godot-file-formats/` and `ls -R ~/.claude/godot-compound/skills/godot-patterns/` to confirm structure
5. Read updated CLAUDE.md and plugin.json to verify correctness
