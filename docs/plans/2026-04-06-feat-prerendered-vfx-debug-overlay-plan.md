---
title: "feat: Pre-rendered VFX, GPU Preloader & Debug Stats Overlay"
type: feat
status: active
date: 2026-04-06
origin: docs/brainstorms/2026-04-06-prerendered-vfx-and-debug-overlay-brainstorm.md
---

# Pre-rendered VFX, GPU Preloader & Debug Stats Overlay

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** All phases + system-wide impact
**Review agents used:** Architecture, Timing, Performance, Resource Safety, Simplicity, Pattern Recognition, Framework Docs, Best Practices, Learnings

### Key Improvements from Research
1. **Existing timing bug found** — `explosion_effect.gd` double-await in `_ready()` needs `is_inside_tree()` guards to prevent crashes on scene transitions
2. **Preloader detail** — `modulate = transparent` still triggers shader compilation (GPU processes draw call regardless); this is correct behavior for warming
3. **Premultiplied alpha** — atlas captured from transparent SubViewport must use `BLEND_MODE_PREMULT_ALPHA` on playback sprite (per `docs/solutions/subviewport-premultiplied-alpha.md`)
4. **`hframes/vframes`** — simpler alternative to manual `region_rect` stepping; built into `Sprite2D`
5. **Orphan node count** — critical leak detection metric added to debug overlay
6. **Performance monitors** — VRAM/video memory monitors return 0 on gl_compatibility; confirmed and handled
7. **Simplification opportunity** — toggle system adds complexity; documented as user-requested feature, not YAGNI

### New Considerations Discovered
- `DebugOverlay._visible` would shadow `CanvasItem.visible` — renamed to `_shown`
- Debug overlay should use `process_mode = PROCESS_MODE_ALWAYS` and `set_process()` toggle
- Color-coded FPS (green/yellow/red) aids quick visual assessment
- Batch capture in renderer tool needs `is_inside_tree()` checks per iteration (~15s total capture time)
- Preset dictionaries should be unified between renderer and effect to prevent drift
- 3D fallback path should cache color ramp/scale curve as static vars (existing duplication)

## Overview

Replace the expensive real-time 3D SubViewport explosion system with pre-rendered 2D sprite animations, add a GPU particle preloader for shader warmup, provide a runtime toggle between both VFX modes, and add an F3 debug stats overlay. This eliminates the primary performance bottleneck: 4+ simultaneous SubViewport 3D renders when firing a broadside.

## Problem Statement

Every `ExplosionEffect.create()` call spawns a `SubViewport` with `own_world_3d`, two `GPUParticles3D` emitters, a `WorldEnvironment`, and duplicates shader/process materials. A broadside fires 4 cannonballs = 4 SubViewports created in a single frame. Each impact creates another. This causes visible frame drops on desktop and multi-second freezes on web (see [godotengine/godot#87843](https://github.com/godotengine/godot/issues/87843)).

The project uses `gl_compatibility` renderer (`project.godot:85`), which means the glow setup in `explosion_effect.gd:32-41` silently does nothing. The pre-rendered sprites will capture WITH glow enabled (via Forward Plus in the renderer tool's SubViewport), providing a visual upgrade over what players currently see.

## Proposed Solution

Three complementary features + a debug overlay:

1. **GPU Particle Preloader** — warm shader caches at startup to eliminate first-spawn stalls
2. **Pre-rendered Sprite VFX** — lightweight `Sprite2D` + `hframes/vframes` animation from a pre-captured atlas
3. **Runtime Toggle** — static var on `ExplosionEffect` to switch between real-time 3D and sprites
4. **Debug Stats Overlay** — F3-toggled performance HUD showing FPS, frame time, memory, draw calls, VRAM

## Technical Approach

### Architecture

```
ExplosionEffect.create(type, parent, pos, dir, scale, drift)
        │
        ├── use_sprites == true ──► SpriteExplosion (Sprite2D + hframes/vframes)
        │                            └── reads from textures/explosion_atlas.png
        │                            └── uses BLEND_MODE_PREMULT_ALPHA
        │
        └── use_sprites == false ─► existing SubViewport pipeline (unchanged)
                                     └── GPU preloader warms shaders at startup
```

The `ExplosionEffect` class remains the single entry point. A new `ExplosionType` enum is added as the first parameter to `create()`. All 5 call sites are updated.

### ExplosionType Enum

```gdscript
# scripts/explosion_effect.gd
enum ExplosionType {
    MUZZLE_FLASH,    # rows 0-2 in atlas
    IMPACT,          # rows 3-5 (water + enemy hit)
    SHIP_DESTRUCTION,# rows 6-8
    MINE_DETONATION, # rows 9-11
}
```

### Call Site Updates

| File | Line | Current | Updated (first arg) |
|------|------|---------|---------------------|
| `scripts/main.gd` | 98 | `ExplosionEffect.create(self, pos, dir, 0, 0.25, 100, vel)` | `ExplosionEffect.create(ExplosionEffect.ExplosionType.MUZZLE_FLASH, self, pos, dir, 0.25, vel)` |
| `scripts/cannonball.gd` | 46-48 | `ExplosionEffect.create(get_parent(), pos, dir, 45.0, 1.0, 15.0, Vector2.ZERO)` | `ExplosionEffect.create(ExplosionEffect.ExplosionType.IMPACT, get_parent(), pos, dir, 1.0, Vector2.ZERO)` |
| `scripts/cannonball.gd` | 57 | `ExplosionEffect.create(get_parent(), pos, dir, 45.0, 1.0, 15.0)` | `ExplosionEffect.create(ExplosionEffect.ExplosionType.IMPACT, get_parent(), pos, dir)` |
| `scripts/enemy_ship.gd` | 78 | `ExplosionEffect.create(get_parent(), pos, UP, 360, 1.0, 55.0, velocity)` | `ExplosionEffect.create(ExplosionEffect.ExplosionType.SHIP_DESTRUCTION, get_parent(), pos, UP, 1.0, velocity)` |
| `scripts/sea_mine.gd` | 175 | `ExplosionEffect.create(get_parent(), pos, UP, 360, 1.5, 80.0)` | `ExplosionEffect.create(ExplosionEffect.ExplosionType.MINE_DETONATION, get_parent(), pos, UP, 1.5)` |

Note: `cone_spread` and `vert_velocity` move into preset configs keyed by `ExplosionType`, no longer passed by callers. `effect_scale` and `drift_velocity` remain as caller parameters since they vary per-instance.

### New API Signature

```gdscript
# scripts/explosion_effect.gd

static var use_sprites: bool = true  ## Toggle: true = sprites (default), false = real-time 3D

static func create(
    type: ExplosionType,
    parent: Node,
    pos: Vector2,
    cone_dir: Vector2 = Vector2.ZERO,
    effect_scale: float = 1.0,
    drift_velocity: Vector2 = Vector2.ZERO,
) -> Node2D:
    if use_sprites:
        return _create_sprite(type, parent, pos, cone_dir, effect_scale, drift_velocity)
    else:
        return _create_3d(type, parent, pos, cone_dir, effect_scale, drift_velocity)
```

### Research Insights: API Design

- **Return type `Node2D`** is correct — no call site captures or uses the return value, so widening from `ExplosionEffect` to `Node2D` is safe (architecture review confirmed all 5 call sites discard the return).
- **Static var as first project-wide setting** — intentional, documented as project-scoped global state. If more settings accumulate, migrate to a `GameSettings` autoload.
- **Enum + static dispatch** fits existing GDScript idioms — `ShipConfig` and `SeaMine.State` already use enums similarly.

### Implementation Phases

#### Phase 1: Renderer Tool Enhancement & Atlas Capture

**Goal:** Extend `explosion_renderer.gd` to support presets and batch capture, then generate the atlas.

**Tasks:**

- [ ] Add `ExplosionType` preset configs to `explosion_renderer.gd` — **reference `ExplosionEffect.TYPE_CONFIGS` directly** for shared parameters, add renderer-specific fields (cam_distance) as a supplementary dict to avoid duplication/drift

  ```gdscript
  # scripts/explosion_renderer.gd
  # Renderer-specific settings that supplement ExplosionEffect.TYPE_CONFIGS
  const RENDER_CONFIGS: Dictionary = {
      ExplosionEffect.ExplosionType.MUZZLE_FLASH: { "cam_distance": 12.0 },
      ExplosionEffect.ExplosionType.IMPACT: { "cam_distance": 8.0 },
      ExplosionEffect.ExplosionType.SHIP_DESTRUCTION: { "cam_distance": 10.0 },
      ExplosionEffect.ExplosionType.MINE_DETONATION: { "cam_distance": 14.0 },
  }
  ```

- [ ] Add "Batch Capture All" button that iterates all 4 presets x 3 random seeds, capturing each as a row into a combined atlas image
- [ ] **Add `is_inside_tree()` check at top of each batch iteration** — batch capture takes ~15 seconds total; user may close the tool window mid-capture
- [ ] Enable glow in renderer tool (intensity=5, bloom=1.0) to bake glow into sprites — this provides a visual upgrade since gl_compatibility doesn't support runtime glow
- [ ] Enable turbulence by default in renderer tool (matching `explosion_effect.gd` lines 83-88)
- [ ] Change output path to `res://textures/explosion_atlas.png` (512x384)
- [ ] Adjust `WARMUP_DELAY` to ensure frame 0 captures visible particles (test empirically — current 0.05s may need increasing to 0.1s)
- [ ] Run batch capture and commit the atlas PNG
- [ ] Ensure atlas PNG imports with `Compress Mode: Lossless`, `Filter: Nearest`, `Mipmaps: disabled` (no VRAM compression on transparent VFX — block artifacts)

**Files modified:**
- `scripts/explosion_renderer.gd` — preset system, batch capture, glow/turbulence alignment
- `scenes/tools/explosion_renderer.tscn` — Batch Capture button in UI
- `textures/explosion_atlas.png` — new 512x384 combined atlas (replaces unused `explosion_strip.png`)

#### Phase 2: Sprite Explosion Player + ExplosionEffect API Refactor

**Goal:** Create a lightweight `Sprite2D`-based explosion and refactor `ExplosionEffect` to dispatch between sprite and 3D modes. These are merged into one phase because they cannot be tested independently — `SpriteExplosion` requires the new enum, and `_create_sprite()` instantiates `SpriteExplosion`.

**Tasks:**

- [ ] Add `ExplosionType` enum to `scripts/explosion_effect.gd`
- [ ] Add `static var use_sprites: bool = true` to `scripts/explosion_effect.gd`
- [ ] Add preset config dictionary mapping `ExplosionType` to 3D particle parameters (cone_spread, vert_velocity) — used by both 3D mode and renderer tool

  ```gdscript
  # scripts/explosion_effect.gd
  const TYPE_CONFIGS: Dictionary = {
      ExplosionType.MUZZLE_FLASH: { "cone_spread": 0, "vert_velocity": 100 },
      ExplosionType.IMPACT: { "cone_spread": 45, "vert_velocity": 15 },
      ExplosionType.SHIP_DESTRUCTION: { "cone_spread": 360, "vert_velocity": 55 },
      ExplosionType.MINE_DETONATION: { "cone_spread": 360, "vert_velocity": 80 },
  }
  ```

- [ ] Refactor `create()` signature: add `type: ExplosionType` as first parameter, remove `cone_spread` and `vert_velocity` params (moved to `TYPE_CONFIGS`), keep `effect_scale` and `drift_velocity` as caller params
- [ ] Add `_create_sprite()` static method — instantiates `SpriteExplosion`, calls `parent.add_child(sprite)`, then calls `setup()` and sets `global_position` (matching existing factory pattern: properties before add_child, position after)
- [ ] Rename existing 3D creation logic to `_create_3d()` static method, pulling `cone_spread`/`vert_velocity` from `TYPE_CONFIGS`
- [ ] **Fix existing timing bug** in `_ready()`: add `if not is_inside_tree(): return` guard after each `await` (lines 108 and 115) to prevent crashes on scene transitions
- [ ] **Cache color ramp and scale curve as static vars** — `_create_color_ramp()` and `_create_scale_curve()` produce identical results every call; create once on first use

  ```gdscript
  static var _cached_color_ramp: GradientTexture1D
  static var _cached_scale_curve: CurveTexture

  static func _get_color_ramp() -> GradientTexture1D:
      if _cached_color_ramp == null:
          _cached_color_ramp = _create_color_ramp()
      return _cached_color_ramp
  ```

- [ ] Create `scripts/sprite_explosion.gd` (`class_name SpriteExplosion`, extends `Sprite2D`)

  ```gdscript
  # scripts/sprite_explosion.gd
  class_name SpriteExplosion
  extends Sprite2D
  ## Pre-rendered explosion animation from atlas. Internal to ExplosionEffect.

  const ATLAS: Texture2D = preload("res://textures/explosion_atlas.png")
  const FRAME_SIZE: int = 32
  const FRAME_COUNT: int = 16
  const VARIATIONS: int = 3
  const ROWS_PER_TYPE: int = VARIATIONS
  const LIFETIME: float = 1.2  # match ExplosionEffect.LIFETIME

  var _drift_velocity: Vector2 = Vector2.ZERO
  var _frame_duration: float = LIFETIME / float(FRAME_COUNT)
  var _frame_timer: float = 0.0
  var _current_row: int = 0

  func setup(type: ExplosionEffect.ExplosionType, cone_dir: Vector2,
      effect_scale: float, drift: Vector2) -> void:
      texture = ATLAS
      hframes = FRAME_COUNT
      vframes = ROWS_PER_TYPE * ExplosionEffect.ExplosionType.size()
      # Pick random variation (0-2) within the type's row range
      var base_row: int = type * ROWS_PER_TYPE
      _current_row = base_row + randi_range(0, VARIATIONS - 1)
      frame = _current_row * FRAME_COUNT  # first frame of chosen row
      # Rotate to match cone direction (skip for 360-degree types)
      if type == ExplosionEffect.ExplosionType.MUZZLE_FLASH or \
         type == ExplosionEffect.ExplosionType.IMPACT:
          rotation = cone_dir.angle()
      scale = Vector2.ONE * effect_scale
      _drift_velocity = drift
      # Premultiplied alpha: atlas captured from transparent SubViewport
      var mat := CanvasItemMaterial.new()
      mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMUL_ALPHA
      material = mat

  func _process(delta: float) -> void:
      _frame_timer += delta
      var col: int = mini(int(_frame_timer / _frame_duration), FRAME_COUNT - 1)
      frame = _current_row * FRAME_COUNT + col
      if _drift_velocity.length_squared() > 0.0:
          global_position += _drift_velocity * delta
      if _frame_timer >= LIFETIME:
          queue_free()
  ```

- [ ] No `.tscn` needed — instantiated purely from code (a `Sprite2D` with no children)
- [ ] Update all 5 call sites:
  - [ ] `scripts/main.gd:98` — `MUZZLE_FLASH`
  - [ ] `scripts/cannonball.gd:46-48` — `IMPACT`
  - [ ] `scripts/cannonball.gd:57` — `IMPACT`
  - [ ] `scripts/enemy_ship.gd:78` — `SHIP_DESTRUCTION`
  - [ ] `scripts/sea_mine.gd:175` — `MINE_DETONATION`

**Files created:**
- `scripts/sprite_explosion.gd`

**Files modified:**
- `scripts/explosion_effect.gd` — enum, toggle, dispatch, preset configs, timing fix, cached resources
- `scripts/main.gd` — call site update
- `scripts/cannonball.gd` — 2 call site updates
- `scripts/enemy_ship.gd` — call site update
- `scripts/sea_mine.gd` — call site update

### Research Insights: Sprite Animation

- **`hframes/vframes`** is simpler than manual `region_rect` stepping — built into `Sprite2D`, just set `frame` property. Avoids UV math entirely.
- **Premultiplied alpha is required** — atlas captured from transparent SubViewport produces premultiplied-alpha data. Without `BLEND_MODE_PREMULT_ALPHA`, semi-transparent areas appear darker (per `docs/solutions/subviewport-premultiplied-alpha.md`).
- **Single texture = optimal batching** — 10 simultaneous sprite explosions can batch into one draw call since they share the same texture.
- **No `AnimatedSprite2D` needed** — `SpriteFrames` resource adds overhead; `Sprite2D` + `hframes` is the lightest approach for one-shot effects.

#### Phase 3: GPU Particle Preloader

**Goal:** Warm GPU shader caches at startup when using real-time 3D mode.

**Tasks:**

- [ ] Add preloader logic to `scripts/explosion_effect.gd` as a static method `preload_shaders(parent: Node) -> void`

  ```gdscript
  # scripts/explosion_effect.gd
  static var _shaders_preloaded: bool = false

  static func preload_shaders(parent: Node) -> void:
      if _shaders_preloaded or use_sprites:
          return
      _shaders_preloaded = true
      var effect: ExplosionEffect = ExplosionScene.instantiate() as ExplosionEffect
      # Keep visible (not transparent!) -- invisible nodes skip GPU pipeline
      # compilation entirely. Position off-screen instead.
      effect.global_position = Vector2(-9999, -9999)
      parent.add_child(effect)
      # effect auto-frees after LIFETIME + 0.3s (existing behavior)
  ```

- [ ] Call `ExplosionEffect.preload_shaders(self)` in `main.gd:_ready()` — only runs if `use_sprites == false`
- [ ] When toggling from sprites → real-time at runtime, call `preload_shaders()` lazily (first toggle triggers warmup)

**Files modified:**
- `scripts/explosion_effect.gd` — `preload_shaders()` static method
- `scripts/main.gd` — call in `_ready()`

### Research Insights: Shader Warming

- **`modulate = Color(1,1,1,0)` still triggers shader compilation** — the GPU processes the draw call regardless of alpha output. However, `visible = false` would skip rendering entirely and NOT trigger compilation. The preloader must keep the node **visible** but position it off-screen.
- **Material `.duplicate()` does NOT re-trigger compilation** — only uniform values change; GPU reuses compiled pipeline. The existing duplicate pattern is safe.
- **Known limitation**: lazy preloader on mode toggle has a ~1.5s warmup window. If the player fires during this window, the first explosion still stalls. Documented as acceptable since the toggle is a debug feature and matches current behavior.
- **Web exports use WebGL2** — shader compilation is synchronous via ANGLE. Pre-rendered sprites bypass this entirely, making sprites the strongly preferred default for web.

#### Phase 4: Debug Stats Overlay

**Goal:** F3-toggled performance HUD in top-left corner.

**Tasks:**

- [ ] Add `toggle_debug_overlay` input action in `project.godot` mapped to F3 (physical_keycode `4194334`)
- [ ] Add `toggle_vfx_mode` input action mapped to F4 (physical_keycode `4194335`)
- [ ] Create `scripts/debug_overlay.gd` extending `CanvasLayer`

  ```gdscript
  # scripts/debug_overlay.gd
  class_name DebugOverlay
  extends CanvasLayer
  ## F3-toggled performance overlay. Shows FPS, frame time, draw calls, etc.
  ## Also handles F4 VFX mode toggle since it is a debug-only feature.

  const UPDATE_INTERVAL: float = 0.25  # 4 updates/sec to prevent flicker

  var _label: Label
  var _timer: float = 0.0
  var _shown: bool = false  # avoid shadowing CanvasItem.visible

  func _ready() -> void:
      layer = 90
      process_mode = Node.PROCESS_MODE_ALWAYS  # work during pause
      _label = Label.new()
      _label.position = Vector2(4, 4)
      _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
      var font: Font = preload("res://resources/fonts/kims_bit_hand.ttf")
      _label.add_theme_font_override("font", font)
      _label.add_theme_font_size_override("font_size", 8)
      _label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
      _label.add_theme_constant_override("shadow_offset_x", 1)
      _label.add_theme_constant_override("shadow_offset_y", 1)
      add_child(_label)
      visible = false
      set_process(false)  # don't process when hidden

  func _unhandled_input(event: InputEvent) -> void:
      if event.is_action_pressed("toggle_debug_overlay"):
          _shown = not _shown
          visible = _shown
          set_process(_shown)
      elif event.is_action_pressed("toggle_vfx_mode"):
          ExplosionEffect.use_sprites = not ExplosionEffect.use_sprites
          if not ExplosionEffect.use_sprites:
              ExplosionEffect.preload_shaders(get_parent())

  func _process(delta: float) -> void:
      _timer += delta
      if _timer < UPDATE_INTERVAL:
          return
      _timer = 0.0
      _update_stats()

  func _update_stats() -> void:
      var fps: float = Performance.get_monitor(Performance.TIME_FPS)
      var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
      var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
      var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
      var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
      var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
      var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
      var mem_static: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
      var mem_video: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
      var vfx_mode: String = "Sprite" if ExplosionEffect.use_sprites else "3D"

      # Color-code FPS
      if fps >= 58.0:
          _label.add_theme_color_override("font_color", Color.GREEN)
      elif fps >= 30.0:
          _label.add_theme_color_override("font_color", Color.YELLOW)
      else:
          _label.add_theme_color_override("font_color", Color.RED)

      var lines: PackedStringArray = PackedStringArray()
      lines.append("FPS: %d (%.1f ms)" % [int(fps), frame_ms])
      lines.append("Physics: %.1f ms" % physics_ms)
      lines.append("Draw: %d | Obj: %d" % [draw_calls, objects])
      lines.append("Nodes: %d | Orphans: %d" % [nodes, orphans])
      if mem_static > 0.0:
          lines.append("Mem: %.1f MB" % mem_static)
      if mem_video > 0.0:
          lines.append("VRAM: %.1f MB" % mem_video)
      lines.append("VFX: %s (F4)" % vfx_mode)
      _label.text = "\n".join(lines)
  ```

- [ ] Create `scenes/debug_overlay.tscn` (CanvasLayer root with script, layer set in `.tscn` to match minimap/controls_overlay convention)
- [ ] Instance `debug_overlay.tscn` in `main.tscn` as child of Main (via Godot editor or MCP tools, not text-editing `.tscn`)

**Files created:**
- `scripts/debug_overlay.gd`
- `scenes/debug_overlay.tscn`

**Files modified:**
- `project.godot` — `toggle_debug_overlay` and `toggle_vfx_mode` input actions
- `scenes/main.tscn` — instance DebugOverlay (via editor/MCP)

### Research Insights: Debug Overlay

- **Orphan node count** is the single most valuable debug metric — if it climbs over time, you have a node leak. Added to overlay.
- **Node count** helps catch effects that don't properly `queue_free()`. Added alongside orphan count.
- **Color-coded FPS** (green >= 58, yellow >= 30, red < 30) — universally understood visual indicator.
- **`set_process(false)` when hidden** eliminates even the per-frame `_shown` check, following process callback discipline.
- **`PROCESS_MODE_ALWAYS`** ensures overlay works during pause (matching `ControlsOverlay` pattern).
- **VFX toggle in `debug_overlay.gd`** not `main.gd` — keeps debug concerns encapsulated (architecture review recommendation).
- **Plain `Label` over `RichTextLabel`** — cheaper to update, sufficient for debug text.
- **Stats returning 0 on gl_compatibility/web** (VRAM, video memory) are conditionally hidden.
- **`.tscn` edits should go through Godot editor or MCP tools**, not raw text editing (resource safety review).

## System-Wide Impact

### Signal Chain

No new signals. The existing `cannon_fired` → `_on_cannon_fired` → `ExplosionEffect.create()` chain is preserved. The only change is `create()` dispatching internally between sprite and 3D implementations. No autoloads are added.

### Error & Failure Propagation

- `SpriteExplosion` has no failure modes — it's a `Sprite2D` with a timer. If the atlas texture is missing, it shows a white rect (Godot default). No crash risk.
- The 3D pipeline is unchanged except for timing bug fixes (await guards). If `use_sprites == false` and shaders haven't been preloaded, the existing first-frame stall occurs (acceptable — same as current behavior).
- Stats returning 0 on web/gl_compatibility (VRAM, memory) are conditionally hidden in the overlay.
- **Existing timing bug fixed**: `explosion_effect.gd` `_ready()` double-await now has `is_inside_tree()` guards preventing crashes on scene transitions.

### State Lifecycle Risks

- `SpriteExplosion` auto-frees via `queue_free()` after `LIFETIME` seconds — mirrors existing `ExplosionEffect` behavior. No orphan risk.
- `ExplosionEffect.use_sprites` is a static var — survives scene changes but is not persisted across sessions. This is intentional (no save system exists). If more settings accumulate, migrate to a `GameSettings` autoload.
- The preloader creates one off-screen `ExplosionEffect` that auto-frees normally. The await guards (new) prevent crashes if Main is freed during the preloader's lifetime.
- **3D fallback path retains two known SubViewport issues** documented in `docs/solutions/`: premultiplied alpha (requires `blend_premul_alpha`) and ViewportTexture 4.6 regression (requires runtime assignment in `_ready()`). The sprite path avoids both entirely.

### Scene Interface Parity

All 5 call sites go through `ExplosionEffect.create()`. No call site needs to know which implementation runs. The `SpriteExplosion` class is internal — only `ExplosionEffect.create()` instantiates it.

### Integration Test Scenarios

1. **Broadside in sprite mode:** Fire 4 cannons simultaneously. Verify 4 sprite explosions appear with correct rotation, no frame drops, and auto-free after ~1.2s. Check orphan node count stays at 0.
2. **Toggle mid-game:** Fire in sprite mode, toggle to 3D with F4, fire again. Verify in-flight sprite explosions continue normally, new explosions use 3D pipeline. Verify preloader triggers lazily on first toggle.
3. **Web export:** Run on web, fire first broadside. Verify no multi-second freeze (sprites bypass GPU compilation entirely).
4. **Mine chain reaction:** Detonate mine near enemies. Verify mixed explosion types (mine + ship destruction) render correctly in both modes.
5. **Debug overlay:** Toggle F3 during gameplay. Verify stats update ~4 times/second, FPS color-codes correctly. Toggle VFX mode with F4 and verify "VFX: Sprite/3D" updates. Verify overlay works during pause.
6. **Scene transition safety (3D mode):** If scene is freed while 3D explosions are active, verify no crash (await guards prevent null `get_tree()` access).

## Acceptance Criteria

### Functional Requirements

- [ ] Renderer tool has 4 presets matching `ExplosionEffect.TYPE_CONFIGS` with batch capture
- [ ] Atlas `textures/explosion_atlas.png` exists: 512x384, 12 rows x 16 frames @ 32x32, with glow baked in
- [ ] Atlas imports as Lossless, Nearest filter, no mipmaps
- [ ] `SpriteExplosion` plays correct animation type, random variation, rotates to match `cone_dir`, uses `BLEND_MODE_PREMULT_ALPHA`
- [ ] `ExplosionEffect.create()` accepts `ExplosionType` enum and dispatches to sprite or 3D based on `use_sprites` flag
- [ ] All 5 existing call sites updated to pass `ExplosionType`
- [ ] GPU preloader keeps node **visible** but off-screen (not transparent — transparent skips GPU pipeline)
- [ ] Preloader warms shaders at startup when `use_sprites == false`; skipped when sprites active
- [ ] Preloader runs lazily on first F4 toggle from sprites → 3D
- [ ] F3 toggles debug overlay (hidden by default)
- [ ] F4 toggles VFX mode (sprite/3D)
- [ ] Debug overlay shows: FPS (color-coded), frame time, physics time, draw calls, objects, nodes, orphans, memory (if available), VRAM (if available), current VFX mode
- [ ] Stats that return 0 on web/gl_compatibility are hidden
- [ ] Debug overlay updates 4 times/sec (0.25s interval) to prevent flicker
- [ ] Debug overlay uses `PROCESS_MODE_ALWAYS` (works during pause)
- [ ] Existing `_ready()` double-await in `explosion_effect.gd` has `is_inside_tree()` guards

### Non-Functional Requirements

- [ ] No visible frame drops when firing a full broadside in sprite mode
- [ ] Sprite explosions visually approximate the 3D explosions (with glow enhancement from baked capture)
- [ ] Atlas texture is under 1MB (512x384 RGBA @ 32bpp = ~768KB uncompressed)
- [ ] Debug overlay has negligible performance impact (`set_process(false)` when hidden)

### Quality Gates

- [ ] `gdformat --check .` passes
- [ ] `gdlint .` passes
- [ ] Run project via MCP: zero errors in debug output
- [ ] Test on web export: no freeze on first explosion
- [ ] Orphan node count stays at 0 after explosions complete

## Alternative Approaches Considered

1. **Object pooling for SubViewport explosions** — pre-create a pool of `ExplosionEffect` nodes and recycle them. Reduces instantiation cost but doesn't eliminate the per-frame rendering cost of multiple 3D viewports. Rejected: doesn't solve the core issue.

2. **CPUParticles2D replacement** — Godot's CPU particle system avoids GPU shader compilation. Lower quality but no stalls. Rejected: pre-rendered sprites are zero-cost at runtime and look better (baked glow).

3. **Staggering explosion creation across frames** — use `call_deferred` to spread SubViewport creation. Reduces per-frame spike but total cost remains. Rejected: only smooths the symptom.

4. **Sprites only, no toggle** (simplicity reviewer recommendation) — commit to sprites, delete 3D path entirely. Simpler (~90 LOC reduction, 1 fewer phase). Rejected per user preference: runtime toggle explicitly requested for visual comparison and future development flexibility. `git revert` is the fallback if sprites don't work out.

## Simplification Opportunity

The simplicity review identified that the runtime toggle (Phase 3 preloader + dispatch + `toggle_vfx_mode`) adds ~90 lines and one full phase. If after validating sprites the 3D path is no longer needed, it can be removed by:
1. Deleting `_create_3d()`, `preload_shaders()`, `_shaders_preloaded`, `TYPE_CONFIGS`
2. Removing the `use_sprites` check from `create()`
3. Removing the F4 toggle from debug overlay
4. Deleting `scenes/explosion_effect.tscn` and `scenes/explosion_model.tscn`

This is tracked as a future simplification, not a current task.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-04-06-prerendered-vfx-and-debug-overlay-brainstorm.md](docs/brainstorms/2026-04-06-prerendered-vfx-and-debug-overlay-brainstorm.md) — Key decisions: 4 explosion types with merged impact, 3 variations per type, combined 512x384 atlas, runtime toggle between modes, all stats in debug overlay.

### Internal References

- Existing renderer tool: `scripts/explosion_renderer.gd`, `scenes/tools/explosion_renderer.tscn`
- 3D explosion model: `scenes/explosion_model.tscn` (shared by renderer and game)
- Explosion effect runtime: `scripts/explosion_effect.gd:126-143` (static factory)
- ShipConfig region_rect pattern: `scripts/ship_config.gd:17-29`
- Input action pattern: `project.godot:58-62` (toggle_fullscreen), `scripts/main.gd:85-90`
- CanvasLayer patterns: `scenes/minimap.tscn` (layer 10), `scenes/controls_overlay.tscn` (layer 100)
- Institutional learnings:
  - `docs/solutions/shared-resource-mutation.md` — resource `.duplicate()` pattern
  - `docs/solutions/subviewport-premultiplied-alpha.md` — transparent SubViewport requires `blend_premul_alpha`
  - `docs/solutions/viewporttexture-46-regression.md` — runtime ViewportTexture assignment required in 4.6

### External References

- GPU particle web performance: [godotengine/godot#87843](https://github.com/godotengine/godot/issues/87843)
- Preloader reference implementation: [particle_effects_preloader.gd](https://github.com/hlimbo/definitelynotbomberman/blob/main/scripts/particle_effects_preloader.gd)
- Godot Performance monitors: [Performance class docs](https://docs.godotengine.org/en/stable/classes/class_performance.html)
