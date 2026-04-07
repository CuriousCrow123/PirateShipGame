# Ship Dash + Stylized Flame — Progress Log

Companion to [`2026-04-07-feat-ship-dash-with-stylized-fire-plan.md`](2026-04-07-feat-ship-dash-with-stylized-fire-plan.md). This file captures **what was actually built**, the pivots taken, and the open issues — so the next session can pick up without re-deriving any of it.

## TL;DR

A short, escape-oriented dash burst, propelled by a 3D stylized flame rendered into a small SubViewport and blitted into 2D as pixel art. Runs from `Ship._start_dash` through `Ship._end_dash`, hands off the burst envelope via `DashFireEffect.set_dash_strength`, and dissipates via a shader `Dissolve` uniform driven by `_process` after `stop()`.

## Final architecture

### Resource graph

| File | Type | Purpose |
|---|---|---|
| [`shaders/stylized_flame.gdshader`](../../shaders/stylized_flame.gdshader) | spatial Shader | Single-mesh fresnel-banded flame, ported from godotshaders.com/shader/stylized-flame, plus a `Dissolve` uniform |
| [`resources/dash_flame_material.tres`](../../resources/dash_flame_material.tres) | ShaderMaterial | The shared material — uniforms tuned in the test scene get persisted here |
| [`resources/dash_flame_profile.tres`](../../resources/dash_flame_profile.tres) | DashFlameProfile (custom Resource) | Cubic-Bezier lathe profile (`bulge_radius`, `tail_length`, `dome_radius`) |
| [`resources/dash_config.tres`](../../resources/dash_config.tres) | DashConfig | Per-burst motion + feel + brightness peak |
| [`resources/dash_intensity_curve.tres`](../../resources/dash_intensity_curve.tres) | Curve | Brightness envelope across the burst — `(0,0) → (0.2,1) → (1,1)`. Plateaus at peak; the `Dissolve` mask is the only fade-out |

### Code

| File | Role |
|---|---|
| [`scripts/dash_flame_profile.gd`](../../scripts/dash_flame_profile.gd) | `class_name DashFlameProfile : Resource` — three exported floats |
| [`scripts/dash_flame_lathe.gd`](../../scripts/dash_flame_lathe.gd) | `class_name DashFlameLathe : RefCounted` — `static build(bulge, tail, dome)` returns an `ArrayMesh` for a single cubic-Bezier teardrop, replacing the original sphere+cone composite |
| [`scripts/dash_fire_effect.gd`](../../scripts/dash_fire_effect.gd) | `class_name DashFireEffect : Node2D` — owns the SubViewport blit, builds the lathe at runtime, anchors the dome to the SternMarker, drives the dissolve |
| [`scripts/dash_config.gd`](../../scripts/dash_config.gd) | DashConfig fields (motion + flame_brightness peak) |
| [`scripts/ship.gd`](../../scripts/ship.gd) | `_start_dash` / `_tick_dash_visuals` / `_end_dash` — input → impulse + curve sampling + effect lifecycle |
| [`scripts/stylized_flame_test.gd`](../../scripts/stylized_flame_test.gd) | The live-tuning test scene script: builds the same lathe, exposes sliders for every shader uniform, persists `_material` and `_profile` to disk via `ResourceSaver` |

### Scene graph

```
ship.tscn (Ship CharacterBody2D, scale=0.5)
└── SternMarker (Marker2D, position=(0,-28))
    └── DashFireEffect (Node2D, z_index=1)             ← scripts/dash_fire_effect.gd
        └── SubViewportContainer (stretch=true)         ← CanvasItemMaterial PREMULT_ALPHA at runtime
            └── DashFireModel (SubViewport)             ← scenes/dash_fire_model.tscn
                ├── Camera3D  (transform y=-0.25, z=3.4, FOV 60)
                ├── FlameSphere (MeshInstance3D)        ← lathe assigned at runtime, rotated 180° X
                └── FlameCone (MeshInstance3D)          ← legacy node, hidden at runtime
```

[`scenes/stylized_flame_test.tscn`](../../scenes/stylized_flame_test.tscn) mirrors this with two side-by-side viewports (`4× UPSCALE` 44×76 LINEAR, `IN-GAME 1×` 11×19 NEAREST + `scale=1.2` to mimic the in-game Camera2D zoom) plus a control panel of HSliders.

## Pivots taken (and *why*, so we don't redo them)

1. **GDQuest stylized_fire (particle-based)** — abandoned. Couldn't get the silhouette from the tutorial. Didn't look like the godotshaders.com reference.
2. **3D-into-SubViewport pipeline** — kept. Lets us render a real fresnel-banded shader with motion and dissolve at pixel-art resolution.
3. **stylized_fire (multi-particle) → stylized_flame (single-mesh)** — switched to [`shaders/stylized_flame.gdshader`](../../shaders/stylized_flame.gdshader) which uses `dot(NORMAL, VIEW)` bands on a single surface. Cleaner, more controllable.
4. **Sphere + Cone composite → procedural lathe** — the visible seam where the sphere's curved normal met the cone's flat normal banded the shader at the join. Replaced with a single continuous mesh.
5. **Hemisphere + power-curve tail → cubic Bezier** — the power-curve attempt still showed a band stripe at the equator because the tail section was nearly cylindrical there (`dot(NORMAL, VIEW)` ≈ constant). A single cubic Bezier from tail tip to dome cap (with `P1.x` slightly past `bulge_radius` for a teardrop bulge) eliminated all curvature discontinuities.
6. **`blend_add` → `blend_mix` + per-band ALPHA** — for true translucency (you can see what's behind the flame). Required adding `Opacity` uniform.
7. **Hardcoded constants → shared `.tres` resources** — material and profile both live as standalone `.tres` files referenced by both the test scene and the in-game effect, so test-scene SAVE persists to disk and the next game run picks up the new values via Godot's shared resource cache.
8. **Burning-paper noise dissolve → clean alpha fade** — the chunky noise erosion (mirroring `explosion_dissolve.gdshader`) was rejected. Final dissolve is a simple `1 - smoothstep(UV.y * 0.35, UV.y * 0.35 + 0.65, Dissolve)` multiplied into ALPHA.
9. **Brightness double-fade removed** — `_process` no longer dims `FlameBrightness` during dissolve. The shader's dissolve mask alone carries the alpha to 0 so surviving pixels keep full color until they go transparent.
10. **Curve `(1, 0)` ramp-down → `(1, 1)` plateau** — the original intensity curve dipped brightness back to 0 at the end of the burst, fighting the dissolve mask and producing a black flame at dissipation start. The curve now plateaus through the end of the burst and `stop()`'s dissolve is the sole fade-out mechanism.
11. **Anchor flame to SternMarker via camera unproject** — `_anchor_dome_to_stern()` calls `_camera.unproject_position(Vector3(0, -dome_radius, 0))` and offsets the SubViewportContainer so the projected dome pixel lands exactly on the Node2D origin. No magic offsets — change the lathe profile and the anchoring auto-adjusts.
12. **Counter-scale Node2D to undo `Ship.scale = 0.5`** — `_ready()` reads `global_scale` and sets local `scale` to its inverse, so the SubViewport blit ends up at 1:1 with screen pixels regardless of parent transforms.
13. **Test scene viewports resized to match in-game** — both viewports were 96×320 (aspect 0.30), making the projection look completely different from the in-game 32×56 (aspect 0.571). Now `IN-GAME 1×` is 11×19 (matching `_VIEWPORT_SIZE` after the size reduction) and `4× UPSCALE` is 44×76.
14. **Test scene background → real water material** — flat dark colour was producing different translucent-band blending than the in-game water shader. The Background ColorRect now applies `water_surface_material.tres` directly so the test composites against the same procedural water layers.
15. **`PixelContainer.scale = 1.2`** — mimics the in-game `Camera2D.zoom = (1.2, 1.2)` so the test viewport's blit goes through the same nearest-neighbour upscale as the in-game flame.

## Solved gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Visible seam between sphere and cone | Discontinuous normals at the join, banded by the shader | Single cubic-Bezier lathe (`DashFlameLathe.build`) |
| Visible stripe at the lathe equator | Power-curve tail was nearly cylindrical → near-constant `dot(NORMAL, VIEW)` | Single cubic Bezier covers tip→bulge→dome with continuously varying radius |
| Dissolved pixels render **black** | SubViewport with `transparent_bg + blend_mix` writes premultiplied colour `(rgb*alpha, alpha)`. Default `SubViewportContainer` blends straight-alpha → multiplies RGB by alpha a second time → low-alpha pixels darken instead of fading | `CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA` on the container, applied at runtime in both `dash_fire_effect.gd._ready()` and `stylized_flame_test.gd._ready()`. See [`docs/solutions/subviewport-premultiplied-alpha.md`](../solutions/subviewport-premultiplied-alpha.md) |
| Flame goes black mid-burst | Intensity curve dipped to 0 at `t=1.0`, so `FlameBrightness = base * 0` near end of burst | Curve plateaus at 1.0 through `t=1.0` |
| Flame is rendered at half resolution in-game | Parent Ship has `scale = Vector2(0.5, 0.5)`, so the 11×19 viewport blit was downsampled to 5.5×9.5 screen px | DashFireEffect Node2D counter-scales itself with `scale = Vector2(2, 2)` |
| Flame too big | Initial viewport was 96×320 then 32×56 | Reduced ~3× to 11×19 |
| Dome misaligned with stern | Manual `offset_top=-160 / offset_bottom=0` placed the wide end ~125 px above the marker (backwards for a thrust flame) | Camera-projection-based anchoring; rotate mesh 180° X so the dome points to -Y → bottom of viewport → near the stern |

## Open issues (today, 2026-04-07)

1. **In-game flame still appears more saturated than the test scene preview** despite matching backdrop, viewport size, projection, premult-alpha, and the 1.2× container scale. Remaining suspects to chase next session:
   - Composition order in the world: a sprite/foam/wake layer drawing *between* the dash effect (z=1) and the ship (z=2) could be tinting the visible flame pixels.
   - Pixel snapping interaction with the parent transform chain — `snap_2d_transforms_to_pixel` is on, and the multi-step parent scale might land the SubViewportContainer at sub-pixel positions that snap differently than the test scene.
   - The water material in the test scene background runs without the world's per-frame `DisplacementOrigin` / wake textures, so its caustic/foam noise samples differ from the in-game version. Translucent flame edges are blending through *some* water but not the same per-frame water.

2. **`project.godot` `run/main_scene` still points at `res://scenes/stylized_flame_test.tscn`** — needs to flip back to `res://scenes/main.tscn` when tuning is done.

3. **Worktree is uncommitted.** Final commit should bundle:
   - New: `dash_flame_lathe.gd`, `dash_flame_profile.gd`, `dash_flame_profile.tres`, `dash_flame_material.tres`, `dash_flame_sphere.tres`, `dash_flame_cone.tres`, `stylized_flame.gdshader`, `stylized_flame_test.tscn` + `.gd`, `dash_fire_test.tscn` + `.gd`
   - Modified: `dash_config.gd/.tres`, `dash_fire_effect.gd/.tscn`, `dash_fire_model.tscn`, `dash_intensity_curve.tres`, `ship.gd/.tscn`, `dash_fire_noise.tres`, `stylized_fire.gdshader` (legacy, can probably delete)
   - Plus the original plan + brainstorm + this progress doc

## Knobs cheat sheet

| Want to change… | File / value |
|---|---|
| Flame on-screen size | [`dash_fire_effect.gd`](../../scripts/dash_fire_effect.gd) `_VIEWPORT_SIZE` (currently `Vector2i(11, 19)`) |
| Flame shape | [`resources/dash_flame_profile.tres`](../../resources/dash_flame_profile.tres) — `bulge_radius`, `tail_length`, `dome_radius`. Tuneable live via the test scene |
| Colors / brightness / motion | [`resources/dash_flame_material.tres`](../../resources/dash_flame_material.tres) — every shader uniform. Tuneable live via the test scene |
| Burst duration / impulse / cooldown | [`resources/dash_config.tres`](../../resources/dash_config.tres) |
| Brightness envelope shape | [`resources/dash_intensity_curve.tres`](../../resources/dash_intensity_curve.tres) (must keep peak ≈1.0 through `t=1.0` or the flame will dim before the dissolve) |
| Dissipation duration | [`dash_fire_effect.gd`](../../scripts/dash_fire_effect.gd) `_DISSOLVE_DURATION` (currently `0.35`) |
| Dissolve fade direction | `1 - smoothstep(UV.y * 0.35, UV.y * 0.35 + 0.65, Dissolve)` in [`stylized_flame.gdshader`](../../shaders/stylized_flame.gdshader). The `UV.y * 0.35` bias makes the tail tip start fading slightly before the dome |
