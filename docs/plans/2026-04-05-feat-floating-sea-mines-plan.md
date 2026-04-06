---
title: "feat: Add Floating Sea Mines"
type: feat
status: active
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-sea-mines-brainstorm.md
---

# feat: Add Floating Sea Mines

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 12
**Research agents used:** architecture-reviewer, performance-reviewer, timing-reviewer, resource-safety-reviewer, pattern-recognition-specialist, code-simplicity-reviewer, best-practices-researcher, framework-docs-researcher, godot-patterns skill

### Key Improvements
1. **Blast radius detection** — replaced broken CollisionShape2D toggle with `PhysicsDirectSpaceState2D.intersect_shape()` (original approach would return empty results)
2. **SubViewport rendering** — changed from UPDATE_ALWAYS to UPDATE_ONCE with periodic re-trigger (~10fps) for massive performance improvement while preserving live rotation
3. **Self-contained interactions** — mines detect cannonballs and chain reactions via collision layers and groups instead of routing through main.gd
4. **Timing safety** — added ARMING->IDLE overlap check, await race guards, `is_instance_valid()` chain guards, and `is_queued_for_deletion()` checks

### New Considerations Discovered
- `body_entered` is edge-triggered — won't re-fire for ships already overlapping during ARMING state
- Enabling a CollisionShape2D and querying `get_overlapping_bodies()` in the same frame returns empty (physics server hasn't stepped yet)
- Procedurally created resources (`.new()`) are already unique per instance — no `.duplicate()` needed for those
- `UPDATE_ONCE` on SubViewport renders one frame then auto-stops — ideal for slow rotation at low framerate

---

## Overview

Add floating sea mines as a new game entity — both a player-deployed weapon and a future world hazard. Mines are 3D-modeled (sphere + 14 cylindrical detonation triggers) rendered as 2D pixel art via SubViewport. They float partially submerged with bobbing animation, a shader-driven water-line effect, ripple visuals, and passive rotation simulating water currents. Ships entering proximity trigger a 1.5s fuse with escalating red glow, then a damaging explosion with chain reaction support.

## Problem Statement / Motivation

The game currently has cannons as the only offensive option. Sea mines add a fundamentally different tactical tool — area denial with risk/reward. The player can drop mines behind them to trap pursuing enemies, but must manage the danger of their own mines detonating on them. Chain reactions create emergent gameplay moments. This also establishes the "hazard entity" pattern for future world obstacles.

## Proposed Solution

### New Files

| File | Purpose |
|------|---------|
| `scripts/sea_mine.gd` | SeaMine entity — Area2D with fuse logic, 3D SubViewport, bobbing, blast via physics query |
| `scenes/sea_mine.tscn` | Scene definition — Area2D root, SubViewport, Sprite2D, RippleSprite, CollisionShapes |
| `scenes/sea_mine_model.tscn` | Separate 3D mine model scene (sphere + 14 trigger cylinders) — editable in editor, instanced into SubViewport |
| `shaders/sea_mine_water.gdshader` | Fragment shader for water-line clipping, submersion tinting, and ripple ring effect |

### Modified Files

| File | Change |
|------|--------|
| `project.godot` | Add collision layer 4 `hazards`, add `drop_mine` input action |
| `scripts/ship.gd` | Emit `mine_dropped(pos: Vector2)` signal on input, with 2-3s cooldown (same lambda timer pattern as broadsides) |
| `scripts/cannonball.gd` | Add `water_impacted(pos: Vector2)` signal, emit in `_impact()` before `queue_free()` |
| `scripts/main.gd` | Preload SeaMine scene, connect signals, spawn/track mines, connect `water_impacted` per cannonball at spawn |

### Entity Architecture

```
SeaMine (Area2D)                        — scripts/sea_mine.gd, class_name SeaMine
  MineSubViewportContainer (SubViewportContainer)  — stretch = false
    MineSubViewport (SubViewport)       — own_world_3d, transparent_bg, UPDATE_ONCE, ~32x32
      [sea_mine_model.tscn instance]    — Node3D root with sphere + 14 cylinders + Camera3D
  MineSprite (Sprite2D)                 — ViewportTexture (assigned in code per docs/solutions)
                                          ShaderMaterial: sea_mine_water.gdshader
  RippleSprite (Sprite2D)               — concentric ring shader (could share sea_mine_water.gdshader)
  ProximityShape (CollisionShape2D)     — CircleShape2D, fuse trigger radius
  VisibleNotifier (VisibleOnScreenNotifier2D) — toggles _process and SubViewport rendering
```

### Research Insights — Entity Architecture

**3D model as separate .tscn** (architecture reviewer): Follow the `ExplosionEffect` pattern — the explosion model lives in `explosion_model.tscn`, not built procedurally. Create `sea_mine_model.tscn` with the sphere + 14 cylinders pre-placed in the editor. This is inspectable, tweakable by artists, and uses Godot's internal resource caching via `PackedScene.instantiate()` instead of slower procedural construction.

**No BlastShape node needed** (timing reviewer): The original plan to enable a BlastShape CollisionShape2D for one frame is broken — `get_overlapping_bodies()` returns empty because the physics server hasn't stepped yet. Instead, use `PhysicsDirectSpaceState2D.intersect_shape()` for an immediate synchronous query at detonation time. The blast radius is defined by a `CircleShape2D` resource held in code, never added to the scene tree.

**VisibleOnScreenNotifier2D** (performance reviewer, patterns skill): Disable `_process()` and SubViewport rendering for off-screen mines. At 640x360 viewport, most mines in a large field are off-screen. This is called out explicitly in the Godot patterns reference as an architectural performance practice.

### Mine State Machine

```
ARMING (0.5s) -> IDLE -> FUSE_ACTIVE (1.5s) -> DETONATING

ARMING:       Post-spawn grace period. Ignores all proximity triggers.
              On completion: check get_overlapping_bodies() for ships already inside.
IDLE:         Bobbing, rotating. Proximity detection active. Waiting for trigger.
FUSE_ACTIVE:  Ship entered proximity. Committed — 1.5s countdown, escalating red glow pulse.
              Cannot be canceled even if ship exits radius.
DETONATING:   Explosion spawned on get_parent(), physics query for blast damage,
              chain reaction via group, queue_free().
```

### Research Insights — State Machine

**Dropped FREED state** (pattern recognition): The codebase uses simple guard flags (`_impacted`, `_is_destroyed`), not full state enums. FREED added no safety beyond `queue_free()` itself. Four states suffice — ARMING, IDLE, FUSE_ACTIVE, DETONATING. The `_is_detonated: bool` guard flag prevents double-detonation, matching the established pattern.

**ARMING -> IDLE overlap check is REQUIRED** (timing reviewer): `body_entered` is edge-triggered — it fires when a body *first enters* the area. If a ship is already overlapping when ARMING completes, `body_entered` will not fire again. The mine MUST call `get_overlapping_bodies()` on arm completion and process any bodies found:

```gdscript
func _on_arm_complete() -> void:
    _state = State.IDLE
    for body: Node2D in get_overlapping_bodies():
        _on_body_entered(body)
```

This is safe because the proximity shape has been enabled since spawn, giving the physics server many frames to register overlaps (0.5s arming > 1 physics frame).

### Collision Layer Setup

| Layer | Name | Bit | Assignment |
|-------|------|-----|------------|
| 1 | `player` | 1 | Ship |
| 2 | `enemies` | 2 | EnemyShip |
| 3 | `player_projectiles` | 4 | Cannonball |
| 4 | `hazards` | 8 | **SeaMine (new)** |

**SeaMine collision config:**
- `collision_layer = 8` (layer 4: hazards)
- `collision_mask = 7` (layers 1+2+3: player + enemies + projectiles) — proximity detects ships AND cannonballs via `area_entered`

**Updated masks on existing entities:**
- Ship: add bit 8 to mask (detect mines)
- EnemyShip: add bit 8 to mask (detect mines)
- Cannonball: add bit 8 to mask (so `area_entered` fires on mine overlap)

### Signal Flow

```
Player presses drop_mine
  -> ship.gd emits mine_dropped(global_position)
  -> main.gd connects, spawns SeaMine at position
  -> mine.setup() called, enters ARMING state

Ship enters mine proximity (body_entered on Area2D)
  -> if state != IDLE: return (guards ARMING and double-trigger)
  -> mine transitions IDLE -> FUSE_ACTIVE
  -> 1.5s timer via get_tree().create_timer() (NOT manual countdown in _process)
  -> _is_detonated guard checked after await

Fuse expires
  -> mine transitions FUSE_ACTIVE -> DETONATING
  -> ExplosionEffect.create(get_parent(), ...) for visuals
  -> PhysicsDirectSpaceState2D.intersect_shape() for blast damage
  -> For each body: call take_damage() if EnemyShip, emit player_damaged if Ship
  -> Chain reaction: get_tree().get_nodes_in_group("sea_mines") within blast radius
     -> call mine.trigger_detonation() on each with staggered SceneTreeTimer
  -> queue_free()

Cannonball enters mine proximity (area_entered on Area2D)
  -> Mine detects cannonball directly via collision layers
  -> if state == IDLE or state == FUSE_ACTIVE: immediate detonation (no fuse)
  -> No relay through main.gd needed

Chain reaction
  -> Mine A detonates, iterates group "sea_mines"
  -> For each mine B within blast radius:
     -> get_tree().create_timer(0.15).timeout.connect(func(): ...)
     -> Guard: if is_instance_valid(mine_b) and not mine_b.is_queued_for_deletion():
          mine_b.trigger_detonation()
```

### Research Insights — Signal Flow

**Self-contained cannonball detection** (architecture reviewer): The original plan routed cannonball impacts through main.gd as a relay. This violates the "call down, signal up" principle by making main.gd a manual message broker. Instead, the mine's Area2D masks layer 3 (projectiles) and uses `area_entered` to detect cannonballs directly. The cannonball's `water_impacted` signal is still added (for main.gd or future systems) but is not required for mine triggering.

**Self-contained chain reactions via groups** (architecture reviewer): Mines add themselves to the `"sea_mines"` group on `_ready()` and remove on detonation. Chain logic lives in the mine script, not main.gd. This keeps main.gd as a thin spawner/wirer consistent with its current role.

**is_instance_valid() + is_queued_for_deletion() guards** (timing reviewer, patterns skill): Chain reaction timers hold direct references to mines that may be freed during the 0.15s delay. Both guards are required in the timer callback. The `tree_exiting` cleanup handles array membership, but timer callbacks bypass the array.

**Cannonball signal wiring** (pattern recognition): Connect `ball.water_impacted` in `_on_cannon_fired` before the cannonball is added to the tree. No tracking array needed — signals auto-disconnect on `queue_free()`.

### 3D Mine Model Construction

Create `scenes/sea_mine_model.tscn` as a standalone 3D scene:

- **Root:** `Node3D` (MineModel)
- **Sphere:** `MeshInstance3D` with `SphereMesh` (radius ~0.5, radial_segments=16, rings=8). `StandardMaterial3D` with `shading_mode = PER_VERTEX` (low-poly look at 32px), metallic=0.8, roughness=0.4, albedo dark gray `Color(0.15, 0.15, 0.15)`.
- **14 Triggers:** `MeshInstance3D` children with `CylinderMesh` (top_radius=0.02, bottom_radius=0.06, height=0.25). Positioned via fibonacci sphere distribution, oriented outward with `look_at_from_position()`. Material: brass tone `Color(0.4, 0.35, 0.2)`.
- **Camera3D:** Orthographic projection, `size` ~1.5, `current = true`, positioned to frame the mine.
- **No lights** — use unshaded materials for consistent pixel-art appearance.

### Research Insights — 3D Model

**Fibonacci sphere for 14 points** (best practices researcher):

```gdscript
static func fibonacci_sphere_points(count: int = 14) -> PackedVector3Array:
    var points := PackedVector3Array()
    points.resize(count)
    var golden_ratio: float = (1.0 + sqrt(5.0)) / 2.0
    var epsilon: float = 0.33  # Improves pole coverage for small n
    for i: int in count:
        var theta: float = TAU * float(i) / golden_ratio
        var phi: float = acos(1.0 - 2.0 * (float(i) + epsilon) / (float(count) - 1.0 + 2.0 * epsilon))
        points[i] = Vector3(cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi))
    return points
```

**Pole edge case in look_at** (best practices researcher): When a point is near the pole (pos.y close to +/-1), the up vector becomes parallel. Use a fallback:

```gdscript
var up_vec: Vector3 = Vector3.FORWARD if abs(pos.y) > 0.99 else Vector3.UP
cyl.look_at_from_position(cyl.position, cyl.position + pos, up_vec)
```

**Built-in primitives over procedural mesh** (framework docs researcher): `SphereMesh` and `CylinderMesh` are the right choice. SurfaceTool/ArrayMesh are overkill when built-in primitives exist and the output is 32px.

**Model in .tscn, not code** (architecture reviewer): Follow the explosion_model.tscn pattern. Pre-build the mine model in a scene file for editor inspectability. If the fibonacci placement is too complex for static scene authoring, a `@tool` script can place the cylinders at editor time.

### SubViewport Rendering Strategy

**UPDATE_ONCE with periodic re-trigger** (~10fps):

The mine rotates slowly to simulate water currents. Instead of rendering the SubViewport every frame (UPDATE_ALWAYS), use UPDATE_ONCE and re-trigger rendering at a low framerate via a timer:

```gdscript
const RENDER_INTERVAL: float = 0.1  # 10fps — sufficient for slow rotation at 32px

func _on_render_timer_timeout() -> void:
    _mine_model.rotation.y += _rotation_speed * RENDER_INTERVAL
    _sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
```

### Research Insights — SubViewport Performance

**SubViewport-per-mine is viable but must be optimized** (performance reviewer): Each SubViewport is an independent render pass. The geometry is trivial (one sphere, 14 cylinders, no shadows) and the viewport is tiny (32x32), so per-viewport cost is mostly fixed overhead (command buffer submission). At 20-50 mines, this is manageable with optimizations:

1. **UPDATE_ONCE + timer** (~10fps): Reduces render passes from 60/frame to ~6/frame per mine. At pixel-art resolution, low framerate reinforces the aesthetic.
2. **VisibleOnScreenNotifier2D**: Skip rendering entirely for off-screen mines (most mines in a large field).
3. **Disable unnecessary rendering features**: `msaa_3d = DISABLED`, `gui_disable_input = true`, unshaded materials (no lighting pass).

**SubViewport minimal setup** (framework docs researcher):

```gdscript
var vp := SubViewport.new()
vp.size = Vector2i(32, 32)
vp.transparent_bg = true
vp.own_world_3d = true
vp.render_target_update_mode = SubViewport.UPDATE_ONCE
vp.msaa_3d = Viewport.MSAA_DISABLED
vp.gui_disable_input = true
```

**First-frame blank** (timing reviewer): The SubViewport hasn't rendered yet when ViewportTexture is assigned in `_ready()`. This is usually invisible (one frame). If noticeable, spawn with `modulate.a = 0` and fade in after one frame.

**Cap concurrent explosion effects at 4-5** (performance reviewer): Chain reactions with many mines spawn many ExplosionEffect SubViewports simultaneously. Consider a lightweight fallback (screen shake + sprite flash) when the explosion count exceeds a threshold. The 0.15s stagger helps but doesn't fully prevent overlap.

### Water Bobbing & Shader Effect

**Bobbing motion** (via AnimationPlayer or tween, not manual _process):
- Sine-wave Y offset with randomized phase per mine
- Driven by animation track or tween loop to reduce per-frame callback overhead

**Water-line shader** (`sea_mine_water.gdshader`):
- Applied to `MineSprite` as a `ShaderMaterial` (MUST `.duplicate()` in `_ready()`)
- Uniform `WaterLineY: float` — oscillates with bobbing, represents the water surface relative to sprite
- Below water line: darken/tint blue-green to simulate submersion
- At water line: wavy foam/highlight edge via sine offset
- `render_mode blend_premul_alpha` (per `docs/solutions/subviewport-premultiplied-alpha.md`)

### Research Insights — Shader Effects

**Water-line shader pattern** (best practices researcher):

```glsl
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform float WaterLineY : hint_range(0.0, 1.0) = 0.55;
uniform float BobOffset : hint_range(-0.2, 0.2) = 0.0;
uniform vec4 WaterTint : source_color = vec4(0.1, 0.2, 0.4, 0.6);
uniform float WaveAmplitude : hint_range(0.0, 0.05) = 0.015;
uniform float WaveFrequency : hint_range(0.0, 40.0) = 20.0;
uniform float WaveSpeed : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float wave = sin(UV.x * WaveFrequency + TIME * WaveSpeed) * WaveAmplitude;
    float effective_line = WaterLineY + BobOffset + wave;
    float submerged = step(effective_line, UV.y);
    vec3 tinted = mix(tex.rgb, tex.rgb * WaterTint.rgb, submerged * WaterTint.a);
    COLOR.rgb = tinted;
    COLOR.a = tex.a;
}
```

**Concentric ripple ring shader** (best practices researcher):

```glsl
shader_type canvas_item;

uniform float RingFrequency : hint_range(1.0, 80.0) = 30.0;
uniform float RingWidth : hint_range(-0.9, 0.9) = 0.0;
uniform float ExpandSpeed : hint_range(-20.0, 20.0) = -5.0;
uniform float FadeRadius : hint_range(0.1, 0.5) = 0.4;
uniform vec4 RingColor : source_color = vec4(0.8, 0.9, 1.0, 0.5);

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    float dist = length(uv);
    float rings = step(RingWidth, sin(dist * RingFrequency + TIME * ExpandSpeed));
    float fade = smoothstep(0.5, FadeRadius, dist);
    COLOR = RingColor;
    COLOR.a *= rings * fade;
}
```

**PascalCase uniform naming** matches the project's shader convention (CLAUDE.md). Both shaders could potentially be combined into one (water line on MineSprite, ripple on RippleSprite share similar logic), but keeping them separate maintains single-responsibility.

### Blast Radius Detection

**Use `PhysicsDirectSpaceState2D.intersect_shape()` for immediate synchronous query:**

```gdscript
func _apply_blast_damage() -> void:
    var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
    var query := PhysicsShapeQueryParameters2D.new()
    query.shape = _blast_shape  # CircleShape2D resource, not a scene node
    query.transform = global_transform
    query.collision_mask = 3  # player (1) + enemies (2)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var results: Array[Dictionary] = space.intersect_shape(query)
    for result: Dictionary in results:
        var body: Node2D = result["collider"]
        if body is EnemyShip and not body.is_queued_for_deletion():
            body.take_damage(global_position.direction_to(body.global_position))
        elif body == _player_ref:
            player_damaged.emit(global_position)
```

### Research Insights — Blast Detection

**Original approach was broken** (timing reviewer): Enabling a CollisionShape2D and immediately calling `get_overlapping_bodies()` returns empty because the physics server hasn't run a step with the newly enabled shape. The `intersect_shape()` approach is deterministic, single-frame, and requires no collision shape enable/disable dance. The blast radius is a `CircleShape2D` resource held as a variable, never added to the scene tree.

### Fuse Visual Feedback

During FUSE_ACTIVE state:
- Red glow via shader emission uniform or `MineSprite.modulate` tween
- Pulse frequency escalation: start at ~2Hz, accelerate to ~10Hz over 1.5s
- Final 0.2s: solid red before detonation
- Use `create_tween()` with easing for the pulse acceleration

### Research Insights — Fuse Timer

**Await race guard required** (timing reviewer, patterns skill): The fuse uses `await get_tree().create_timer(1.5).timeout`. If the mine is freed during the await (e.g., cannonball triggers immediate detonation), the coroutine resumes in an invalid state. Guard after every await:

```gdscript
func _start_fuse() -> void:
    _state = State.FUSE_ACTIVE
    # ... start glow tween ...
    await get_tree().create_timer(FUSE_TIME).timeout
    if _is_detonated or not is_inside_tree():
        return
    _detonate()
```

**`is_queued_for_deletion()` on all entry points** (patterns skill): Both `_on_body_entered()` and `trigger_detonation()` should check this, matching enemy_ship.gd's pattern.

### Player Damage (Wired but Deferred)

Mine blast detection will check for the player Ship in the blast radius and emit a `player_damaged(from_position: Vector2)` signal on the SeaMine. Main.gd can connect this if needed. No health reduction occurs yet — the signal exists as a hook for the future player health system.

## Technical Considerations

- **SubViewport rendering at ~10fps:** `UPDATE_ONCE` with periodic re-trigger via timer. Off-screen mines skip rendering entirely via `VisibleOnScreenNotifier2D`. Worst case ~20 on-screen mines = 20 tiny render passes at 10fps, manageable.
- **Material duplication:** Only needed for scene-defined or `@export` materials. Procedurally created resources (`.new()`) are already unique. ShaderMaterials with per-mine uniforms (WaterLineY, GlowIntensity) MUST be duplicated if loaded from .tscn. The underlying Shader (.gdshader) does NOT need duplication — shaders are stateless.
- **ViewportTexture assignment:** Per `docs/solutions/viewporttexture-46-regression.md`, assign ViewportTexture in code (`_ready()`), not in the .tscn file.
- **Chain reaction staggering:** 0.15s delay between chain detonations with `is_instance_valid()` + `is_queued_for_deletion()` guards in timer callbacks.
- **Physics interpolation:** Call `reset_physics_interpolation()` after setting mine position.
- **Explosion parenting:** `ExplosionEffect.create(get_parent(), ...)` so the effect survives the mine's `queue_free()`.
- **Cap concurrent explosions:** Consider limiting to 4-5 simultaneous ExplosionEffect instances. Excess chain detonations get screen shake + flash only.
- **@export assertions:** All `@onready` node references must be asserted in `_ready()` per project CLAUDE.md conventions.
- **.uid sidecar files:** New scripts/scenes will auto-generate `.uid` files on first editor load. Commit them to version control.

## System-Wide Impact

- **Signal chain:** `mine_dropped` -> main.gd spawns mine -> mine `body_entered` triggers fuse -> `await` timer -> `ExplosionEffect.create()` + `intersect_shape()` blast query -> `take_damage()` on enemies, `player_damaged` signal. Cannonball `area_entered` on mine triggers immediate detonation (self-contained). Chain reactions via `"sea_mines"` group iteration (self-contained).
- **Error propagation:** Mine guards against double-detonation with `_is_detonated: bool` flag + `is_queued_for_deletion()` check (matching cannonball's `_impacted` and enemy_ship's `_is_destroyed` patterns). `set_deferred("disabled", true)` on proximity collision shape during detonation (called from physics callback context).
- **State lifecycle risks:** Mine `queue_free()` during chain reaction could leave stale references in main.gd tracking array. Mitigated by `tree_exiting` signal connection (established pattern). Timer callbacks to freed mines mitigated by `is_instance_valid()` guard.
- **Scene interface parity:** `take_damage()` already exists on EnemyShip. Player Ship gets no new interface yet (deferred). Cannonball gets one new signal (`water_impacted`). Mine exposes `trigger_detonation()` as public API for chain reactions.
- **main.gd responsibility scope:** Mine spawning and tracking only. No relay logic — cannonball detection and chain reactions are self-contained in the mine script via collision layers and groups. Consistent with main.gd's current thin-orchestrator role.

## Acceptance Criteria

- [ ] Player can press a key to drop a mine at their current position
- [ ] Mine has a 2-3 second cooldown between drops (lambda timer matching broadside pattern)
- [ ] Mine appears as a 3D-rendered sphere with 14 trigger cylinders, displayed as 2D pixel art
- [ ] Mine visually bobs up and down with sine-wave motion (randomized phase per mine)
- [ ] Mine passively rotates in 3D via SubViewport at ~10fps (UPDATE_ONCE + timer)
- [ ] Shader-based water line clips the mine sprite, darkening the submerged portion
- [ ] Ripple effect visible around the mine's waterline
- [ ] When a ship enters proximity, a 1.5s fuse countdown begins (committed, cannot cancel)
- [ ] Fuse shows escalating red glow pulse (slow -> fast -> solid -> explosion)
- [ ] Mine has 0.5s arming delay after spawn; checks overlapping bodies on arm completion
- [ ] Explosion uses existing ExplosionEffect.create(get_parent(), ...) for visual consistency
- [ ] Blast radius (2.5x visual size) damages all EnemyShips via `intersect_shape()` + `take_damage()`
- [ ] Player ship in blast radius emits `player_damaged` signal (no HP reduction yet)
- [ ] Cannonball entering mine area triggers immediate detonation (self-contained via `area_entered`)
- [ ] Chain reactions: nearby mines triggered via group iteration with ~0.15s stagger + validity guards
- [ ] Mine uses new collision layer 4 (`hazards`), mask layers 1+2+3
- [ ] Off-screen mines disable `_process()` and SubViewport rendering via `VisibleOnScreenNotifier2D`
- [ ] Mine adds self to `"sea_mines"` group and removes on detonation
- [ ] All `@onready` nodes asserted in `_ready()` with clear messages
- [ ] ShaderMaterials `.duplicate()`d per instance for per-mine uniforms
- [ ] ViewportTexture assigned in code (not .tscn)
- [ ] `_is_detonated` + `is_queued_for_deletion()` guards on all entry points
- [ ] No errors in debug output during normal gameplay
- [ ] gdformat and gdlint pass on all new/modified files

## Dependencies & Risks

| Dependency/Risk | Impact | Mitigation |
|----------------|--------|------------|
| No player health system | Player damage is wired but non-functional | Signal-based hook allows future health system to plug in |
| SubViewport performance at scale | Many on-screen mines = many render passes | UPDATE_ONCE at ~10fps + VisibleOnScreenNotifier2D for off-screen |
| Cannonball.gd modification | Adds signal to existing stable code | Minimal change — one signal declaration + one emit call |
| Chain reaction frame spikes | Many simultaneous explosions | 0.15s stagger + consider capping concurrent ExplosionEffects at 4-5 |
| 3D mine model in .tscn | Fibonacci placement complex for static scene | Use @tool script for editor-time placement, or place procedurally in _ready() |
| Blast detection timing | CollisionShape2D enable+query is broken | Using PhysicsDirectSpaceState2D.intersect_shape() instead (synchronous, reliable) |
| body_entered edge-triggering | Ships present during ARMING state missed | Explicit get_overlapping_bodies() check on arm completion |

## Success Metrics

- Mines are visually convincing as floating objects (bobbing, water line, ripple)
- Tactical gameplay: players use mines to trap pursuers
- Chain reactions create satisfying emergent moments
- No performance degradation during normal gameplay sessions (<20 on-screen mines)
- Zero debug errors

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-04-05-sea-mines-brainstorm.md](docs/brainstorms/2026-04-05-sea-mines-brainstorm.md) — Key decisions: Area2D entity, SubViewport 3D rendering, shader water line, committed fuse, chain reactions
- **Entity pattern reference:** [scripts/enemy_ship.gd](scripts/enemy_ship.gd) — health, damage, destruction, signal lifecycle, `is_queued_for_deletion()` guard
- **Area2D/hazard reference:** [scripts/cannonball.gd](scripts/cannonball.gd) — Area2D setup, impact guard, ExplosionEffect usage
- **SubViewport VFX reference:** [scripts/explosion_effect.gd](scripts/explosion_effect.gd) — factory pattern, material duplication, SubViewport 3D-to-2D
- **3D model scene reference:** [scenes/explosion_model.tscn](scenes/explosion_model.tscn) — separate .tscn for 3D content instanced into SubViewport
- **Spawning reference:** [scripts/main.gd](scripts/main.gd) — preload, track, signal connect, despawn pattern
- **Institutional learnings:** [docs/solutions/subviewport-premultiplied-alpha.md](docs/solutions/subviewport-premultiplied-alpha.md), [docs/solutions/viewporttexture-46-regression.md](docs/solutions/viewporttexture-46-regression.md), [docs/solutions/shared-resource-mutation.md](docs/solutions/shared-resource-mutation.md)
- **Fibonacci sphere distribution:** [Extreme Learning — offset Fibonacci lattice](https://extremelearning.com.au/how-to-evenly-distribute-points-on-a-sphere-more-effectively-than-the-canonical-fibonacci-lattice/)
- **Ring/Wave shader pattern:** [Godot Shaders — Ring Wave](https://godotshaders.com/shader/ring-wave-shader/)
