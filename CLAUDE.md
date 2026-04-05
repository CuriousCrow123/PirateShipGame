# PirateShipGame — Project Conventions

## Language & Engine

- Godot 4.6, Forward+ renderer
- GDScript (no C#)

## Display Settings

- Viewport: 1280x720 (pixel art native resolution)
- Window: 1280x720
- Stretch mode: `viewport`, aspect: `keep`, scale: `integer`
- Default texture filter: `Nearest`
- Pixel snapping: enabled (`snap_2d_transforms_to_pixel`, `snap_2d_vertices_to_pixel`)

## Folder Structure

```
shaders/        — .gdshader files and .tres ShaderMaterials
textures/       — PNG texture assets
scripts/        — .gd script files
scenes/         — .tscn scene files
resources/      — .tres resource files (curves, etc.)
docs/plans/     — feature plans
docs/decisions/ — ADRs (Architecture Decision Records)
docs/solutions/ — solved problem documentation
```

## GDScript Conventions

- **Static typing required** — all variables, parameters, and return types must be typed
- **Assertions on @export node references** — validate in `_ready()` with clear messages
- **Resource safety** — always `.duplicate()` any Resource mutated at runtime
- **Member ordering** — follow GDScript style guide: signals, enums, constants, exports, vars, _ready, _process, public methods, private methods

## Shader Conventions

- **File naming**: `snake_case.gdshader` (not PascalCase)
- **Uniform naming**: PascalCase (inherited from reference; diverges from GLSL convention)
- **Texture filter hints**: `filter_nearest` for player-visible textures, `filter_linear` for noise/math inputs (overrides project Nearest default)
- **Deferred features**: comment with `// TODO(post-mvp):` and include what to wire

## Linting

```bash
gdformat --check .   # formatting
gdlint .             # style
```

Run both before committing. Fix gdformat issues with `gdformat .`.

## Testing

- Visual-only systems: run project via MCP (`run_project` → `get_debug_output` → `stop_project`)
- Check for zero errors in debug output
- Validate `.tres`/`.tscn` files when changed
