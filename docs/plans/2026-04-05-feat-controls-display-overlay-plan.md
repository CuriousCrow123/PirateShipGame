---
title: "feat: Add chalkboard controls display overlay at game start"
type: feat
status: active
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-controls-display-brainstorm.md
---

# feat: Add chalkboard controls display overlay at game start

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 7
**Review agents used:** architecture, timing, gdscript, performance, pattern-recognition, resource-safety, code-simplicity
**Research agents used:** best-practices, framework-docs

### Key Improvements
1. **Critical: Use `PROCESS_MODE_ALWAYS` instead of `WHEN_PAUSED`** — Godot bug #97054 causes `_unhandled_input` to not reliably fire during pause with `WHEN_PAUSED`. Using `ALWAYS` with visibility gating is the safe workaround.
2. **Improved GDScript** — type narrowing via `as InputEventKey`, callable-based `_dismiss.call_deferred()`, tween lifecycle management, process_mode set in script
3. **Font placement** — `resources/fonts/` instead of new top-level `fonts/` directory (matches project structure conventions)
4. **Explicit CanvasLayer layer** — set `layer = 100` to establish clear precedent for future UI
5. **Tween pause mode** — `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` required for animation during pause
6. **Concrete shader implementation** — two-noise approach (grain + smudge) with specific color values and uniform parameters

### New Considerations Discovered
- Godot engine bug #97054: `_unhandled_input` unreliable during pause (workaround: `PROCESS_MODE_ALWAYS`)
- Pre-existing missing UIDs on `ripple_material.tres` — run `update_project_uids` via MCP after changes
- Do NOT hand-edit `main.tscn` — use Godot editor or MCP tools to add the overlay instance
- British spelling convention: use `BoardColour` to match dominant codebase pattern (`WaterColour`, `FoamColour`, etc.)

---

## Overview

A nautical chalkboard-style controls overlay that appears when the game starts, pauses gameplay, and dismisses on keypress. This is the first UI element in the game — no HUD, CanvasLayer, or pause system currently exists.

(see brainstorm: [docs/brainstorms/2026-04-05-controls-display-brainstorm.md](../brainstorms/2026-04-05-controls-display-brainstorm.md))

## Problem Statement / Motivation

The game launches directly into gameplay with no indication of controls. Players face 7 key bindings across a non-standard layout (WASD movement, Q/E for port/starboard cannons, Down Arrow for mines). Without a controls display, new players have no way to discover how to play.

## Proposed Solution

A CanvasLayer overlay with:
- **Chalkboard shader background** — dark slate/green ColorRect with chalk-dust noise grain via custom `.gdshader`
- **Pixel font text** — "Captain's Orders" title, two-column key list, pulsing dismiss prompt
- **Pause system** — `get_tree().paused = true` while shown, overlay uses `PROCESS_MODE_ALWAYS` (not `WHEN_PAUSED` — see timing considerations)
- **Dismiss on keypress** — consumes the input and defers unpause to prevent the dismiss key from triggering game actions

## Technical Considerations

### Dismiss-key propagation (Critical — from SpecFlow analysis)

Every listed control key (W, S, A, D, Q, E, arrows) doubles as a valid dismiss key. Without mitigation, pressing Down Arrow to dismiss immediately drops a sea mine.

**Solution:** The overlay's `_unhandled_input()` must:
1. Use `as InputEventKey` type narrowing (not `is` check) for proper static typing
2. Accept only pressed events, no echoes
3. Set a `_dismissed` flag to guard against double-dismiss from rapid keypresses
4. Call `get_viewport().set_input_as_handled()` to consume the event
5. Defer the actual dismiss via `_dismiss.call_deferred()` (callable syntax, not string-based) so the keypress cannot propagate to `ship.gd` in the same frame

### Process mode: ALWAYS, not WHEN_PAUSED (Critical — from framework docs research)

**Godot bug #97054**: `_unhandled_input` does not reliably receive non-mouse-motion events when the scene tree is paused, even on nodes with `PROCESS_MODE_WHEN_PAUSED`. This is a known engine issue.

**Workaround:** Use `PROCESS_MODE_ALWAYS` on the overlay. Since the overlay `queue_free()`s itself on dismiss, it cannot accidentally process input after the game resumes. The overlay script sets `process_mode` in `_ready()` to make the requirement self-documenting and impossible to forget when recreating the scene.

### Tween pause mode

Tweens created with `create_tween()` inherit their bound node's process mode. However, to guarantee the pulse animation runs during pause, explicitly set `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` on the tween. Kill the tween explicitly in `_dismiss()` before `queue_free()`.

### Overlay lifecycle

Declared directly in `main.tscn` as a CanvasLayer child node (not instantiated dynamically). On dismiss, use `queue_free()` — no re-show mechanism for MVP. The spawn timer in `main.gd` (starts at 2.0s) naturally gives a grace period after unpause before the first enemy appears.

**Important:** Do NOT hand-edit `main.tscn` to add the overlay. Use the Godot editor (drag scene into tree) or MCP tools (`add_node` / `save_scene`). Scene files have strict section ordering and unique ID generation that is easy to corrupt.

### CanvasLayer layer property

Explicitly set `layer = 100` on the CanvasLayer. The default is `1`, which works but relies on an implicit default. Setting `100` establishes a clear precedent: game world is layer 0, future HUD could be layer 10, modal overlays are layer 100+. This prevents layer ordering conflicts when future UI is added.

### Shader conventions (from repo research)

Follow existing patterns in `shaders/`:
- File: `shaders/chalkboard.gdshader`, material: `shaders/chalkboard_material.tres`
- `shader_type canvas_item`
- PascalCase uniforms with **British spelling** to match dominant convention (`BoardColour`, `SmudgeColour` — matching `WaterColour`, `FoamColour`, `CausticColour`)
- Two noise textures: high-frequency grain (surface texture) + low-frequency smudge (erased chalk residue)
- Both use `filter_linear` hint (math inputs, not pixel art)
- Noise via `FastNoiseLite` → `NoiseTexture2D` sub-resource in the `.tres`

### Research Insights: Chalkboard shader

**Concrete color values** (linear space with `source_color`):

| Surface | RGB float | Description |
|---------|-----------|-------------|
| Dark green board | `vec4(0.14, 0.22, 0.16, 1.0)` | Classic school chalkboard |
| Chalk dust/smudge tint | `vec4(0.85, 0.88, 0.82, 1.0)` | Faint erased residue |

**Two-noise approach:**
- **Grain noise** (fine): FastNoiseLite Simplex Smooth, frequency 0.04-0.06, sampled at UV * 3.0. Remapped to `[-1,1]` range, strength ~0.06. Gives chalky micro-texture.
- **Smudge noise** (broad): FastNoiseLite Simplex Smooth, frequency 0.005-0.01, sampled at UV * 0.5. Mixed with smudge colour at strength ~0.12. Simulates erased chalk residue.
- **Vignette**: `smoothstep` on UV distance from center, darkens edges. Radius ~0.75, softness ~0.35, strength ~0.4.

### Pixel font

Add a free pixel font `.ttf` to `resources/fonts/` (not a new top-level `fonts/` directory — keeps the existing folder structure stable per CLAUDE.md conventions).

**Import settings:**
- Antialiasing: `FONT_ANTIALIASING_NONE`
- Hinting: `FONT_HINTING_NONE`
- Subpixel positioning: `SUBPIXEL_POSITIONING_DISABLED`
- MSDF: **OFF** (causes blurring at low pixel sizes)
- This ensures crisp rendering at 640x360 with nearest-neighbor filtering

**Font size:** Use the font's native design size (typically 8px or 16px for pixel fonts). Using any other size causes fractional scaling and blur. The viewport stretch mode `viewport` renders at 640x360 then upscales — text stays pixel-perfect.

**Recommended fonts** (free, pixel-art compatible): "Press Start 2P", "Silkscreen", "04b03"

### Pulsing dismiss prompt

Alpha pulse between 0.3 and 1.0, ~0.8s each direction (1.6s full cycle), `TRANS_SINE` + `EASE_IN_OUT` easing. No scale change — scale pulsing causes pixel swimming at this resolution. Use `modulate:a` property (affects label and children).

### Resource safety

The shader material is on a single ColorRect and is never mutated at runtime (no `set_shader_parameter()` calls). No `.duplicate()` needed. If any `set_shader_parameter()` calls are added later, duplicate first per `docs/solutions/shared-resource-mutation.md`.

## Acceptance Criteria

- [ ] Chalkboard overlay appears immediately on game launch
- [ ] Game is paused while overlay is visible (no enemy spawning, no ship movement)
- [ ] Title "Captain's Orders" displayed at top in pixel font
- [ ] All 7 controls shown in two-column layout (keys left, actions right)
- [ ] Dismiss prompt "Press any key to set sail..." pulses at bottom (alpha 0.3–1.0, sine easing)
- [ ] Any keyboard press dismisses the overlay and unpauses the game
- [ ] Dismiss keypress does NOT trigger any game action (no cannon fire, no mine drop)
- [ ] Double-dismiss guard prevents errors from rapid keypresses
- [ ] Chalkboard shader has dark slate/green background with chalk-dust noise grain and vignette
- [ ] Text is chalk-white and readable at 640x360 viewport resolution
- [ ] CanvasLayer `layer` property explicitly set to 100
- [ ] `process_mode` set to `PROCESS_MODE_ALWAYS` in script (not relying on scene property)
- [ ] Tween uses `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)`
- [ ] Passes `gdformat --check .` and `gdlint .`

## Implementation

### New files

#### `shaders/chalkboard.gdshader`

```gdshader
shader_type canvas_item;

// Board base
uniform vec4 BoardColour : source_color = vec4(0.14, 0.22, 0.16, 1.0);

// Chalk grain (fine noise for surface texture)
uniform sampler2D GrainNoise : filter_linear, repeat_enable;
uniform float GrainScale : hint_range(0.5, 8.0) = 3.0;
uniform float GrainStrength : hint_range(0.0, 0.15) = 0.06;

// Dust smudge (large-scale chalk residue variation)
uniform sampler2D SmudgeNoise : filter_linear, repeat_enable;
uniform float SmudgeScale : hint_range(0.1, 2.0) = 0.5;
uniform float SmudgeStrength : hint_range(0.0, 0.3) = 0.12;
uniform vec4 SmudgeColour : source_color = vec4(0.85, 0.88, 0.82, 1.0);

// Vignette
uniform float VignetteRadius : hint_range(0.2, 1.0) = 0.75;
uniform float VignetteSoftness : hint_range(0.01, 0.5) = 0.35;
uniform float VignetteStrength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
    // Fine grain — chalky micro-texture
    float grain = texture(GrainNoise, UV * GrainScale).r;
    float grain_offset = (grain - 0.5) * 2.0 * GrainStrength;

    // Large smudge — erased chalk residue
    float smudge = texture(SmudgeNoise, UV * SmudgeScale).r;
    vec3 board = mix(BoardColour.rgb, SmudgeColour.rgb, smudge * SmudgeStrength);

    // Apply grain
    board += vec3(grain_offset);

    // Vignette — darken edges
    vec2 center_offset = UV - vec2(0.5);
    float dist = length(center_offset);
    float vignette = smoothstep(VignetteRadius, VignetteRadius - VignetteSoftness, dist);
    board *= mix(1.0 - VignetteStrength, 1.0, vignette);

    COLOR = vec4(board, 1.0);
}
```

#### `shaders/chalkboard_material.tres`

ShaderMaterial resource referencing `chalkboard.gdshader` with:
- `FastNoiseLite` (Simplex Smooth, freq 0.05) → `NoiseTexture2D` (256x256) for `GrainNoise`
- `FastNoiseLite` (Simplex Smooth, freq 0.008) → `NoiseTexture2D` (256x256) for `SmudgeNoise`
- Sub-resource ID naming: `FastNoiseLite_grain`, `NoiseTexture2D_grain`, `FastNoiseLite_smudge`, `NoiseTexture2D_smudge` (following descriptive suffix convention from `water_surface_material.tres`)

#### `scripts/controls_overlay.gd`

```gdscript
class_name ControlsOverlay
extends CanvasLayer


var _dismissed: bool = false
var _pulse_tween: Tween

@onready var _dismiss_prompt: Label = %DismissPrompt


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(_dismiss_prompt != null, "ControlsOverlay: DismissPrompt label not found")
	get_tree().paused = true
	_setup_pulse_tween()


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not key_event.is_pressed() or key_event.is_echo():
		return
	_dismissed = true
	get_viewport().set_input_as_handled()
	_dismiss.call_deferred()


func _setup_pulse_tween() -> void:
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pulse_tween.tween_property(_dismiss_prompt, "modulate:a", 0.3, 0.8) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_dismiss_prompt, "modulate:a", 1.0, 0.8) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _dismiss() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	get_tree().paused = false
	queue_free()
```

#### `scenes/controls_overlay.tscn`

```
ControlsOverlay (CanvasLayer, layer=100) — scripts/controls_overlay.gd
  └── Background (ColorRect, anchors=full_rect) — shaders/chalkboard_material.tres
  └── Content (VBoxContainer, anchored center, custom separation)
      ├── Title (Label) — "Captain's Orders", larger font size
      ├── ControlsList (GridContainer, columns=2, h_separation, v_separation)
      │   ├── Label "W / ↑"    │ Label "Sail Forward"
      │   ├── Label "S"        │ Label "Sail Backward"
      │   ├── Label "A"        │ Label "Turn Left"
      │   ├── Label "D"        │ Label "Turn Right"
      │   ├── Label "Q / ←"   │ Label "Fire Port Cannons"
      │   ├── Label "E / →"   │ Label "Fire Starboard Cannons"
      │   └── Label "↓"       │ Label "Drop Sea Mine"
      └── DismissPrompt (Label, unique_name=%DismissPrompt) — "Press any key to set sail..."
```

**Label styling:** All labels use chalk-white color (`Color(0.9, 0.92, 0.88)`) via theme overrides. Key column labels right-aligned, action column labels left-aligned. GridContainer `h_separation` provides visual column gap.

#### Font asset

Add a pixel font `.ttf` to `resources/fonts/`. Configure import settings as specified in Technical Considerations.

### Modified files

#### `scenes/main.tscn`

Add `controls_overlay.tscn` as an instanced child of the Main node. **Use the Godot editor or MCP tools only** — do not hand-edit the `.tscn` file. After adding, run `update_project_uids` via MCP to fix pre-existing missing UIDs on `ripple_material.tres` references.

## Dependencies & Risks

- **Font asset sourcing** — need to find a suitable free pixel font with a compatible license (SIL OFL or similar). Recommended: "Press Start 2P", "Silkscreen", or "04b03". This is the only external dependency.
- **Godot bug #97054** — `_unhandled_input` unreliable during pause. Mitigated by using `PROCESS_MODE_ALWAYS`. If the bug is fixed in a future Godot version, the workaround remains safe (ALWAYS is a superset of WHEN_PAUSED behavior).
- **Shader complexity** — the chalkboard effect should stay simple (two noise textures + vignette). The shader runs on a single 640x360 ColorRect for 5-10 seconds — no performance concern. Over-engineering is the real risk — start with the values above and tune visually.
- **First CanvasLayer** — introduces a new pattern to the project. Keep it clean as a reference for future UI work.

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-04-05-controls-display-brainstorm.md](../brainstorms/2026-04-05-controls-display-brainstorm.md) — key decisions: shader-drawn chalkboard, pause on show, dismiss on keypress, two-column layout, pixel font, "Captain's Orders" title
- **Existing shader patterns:** [shaders/water_surface.gdshader](../../shaders/water_surface.gdshader), [shaders/ripple.gdshader](../../shaders/ripple.gdshader) — PascalCase uniforms, British spelling, noise texture sub-resources
- **Input handling pattern:** [scripts/main.gd:43-48](../../scripts/main.gd) — `_unhandled_input()` for fullscreen toggle
- **Resource safety:** [docs/solutions/shared-resource-mutation.md](../solutions/shared-resource-mutation.md) — `.duplicate()` before runtime mutation
- **Godot bug #97054:** [_unhandled_input unreliable during pause](https://github.com/godotengine/godot/issues/97054) — reason for using PROCESS_MODE_ALWAYS
- **Godot docs:** [Pausing games](https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html), [CanvasLayer](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html), [Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)
- **SpecFlow analysis:** dismiss-key propagation, double-dismiss guard, alpha-only pulsing to avoid pixel swimming
