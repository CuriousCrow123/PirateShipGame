# 2D Pixel Water Shader — Godot 4 Reference

Source: [jess-hammer/2d-pixel-water-shader-godot](https://github.com/jess-hammer/2d-pixel-water-shader-godot) (Godot Mono 4.4)

This document provides a complete implementation reference for the pixel-art animated water shader.
It covers both the water surface shader and the interactive ripple trail effect.

---

## Overview

The effect has two independent systems:

1. **Water Surface Shader** — Applied to a `TileMap` via a `ShaderMaterial`. Renders animated caustics, specular highlights, and edge foam using the TileMap's per-vertex color as the foam heightmap input.
2. **Water Trail / Ripple System** — A `Line2D` rendered inside a `SubViewport`, then displayed via a `Sprite2D` with a separate ripple shader. The cursor (or any moving object) drives the trail.

> **Note:** The original uses C# scripts. The logic is simple enough to port to GDScript.

---

## Required Textures

All textures should be imported with appropriate settings (see below).

| Texture | Purpose | Import settings |
|---------|---------|----------------|
| `CausticTexture.png` | Main caustic light pattern | `filter_nearest`, `repeat_enable`, grayscale/color |
| `CausticTextureHighlights.png` | Bright caustic highlights (blended over base) | `filter_nearest`, `repeat_enable` |
| `MovementNoise.png` | Noise used to offset caustic UV over time | `repeat_enable`, no filter required |
| `RandomFadeNoise.png` | Noise used to fade caustics, prevent repetition | `repeat_enable` |
| `SpecularNoiseTextureMoving1.png` | First noise layer for specular highlights | `repeat_enable` |
| `SpecularNoiseTextureMoving2.png` | Second noise layer for specular highlights | `repeat_enable` |
| `FoamNoiseTexture.png` | `filter_nearest`, `repeat_enable` — modulates foam wave threshold |
| `WaterTrailGradient.png` | Gradient for Line2D trail width/color | Default |
| `WaterTrailGradientFaded.png` | Faded gradient used by ripple shader | Default |
| `CircleBlur64x64.png` | Soft circle brush displayed at cursor tip | Default |

**Generating noise textures with FastNoiseLite:**
Create a `NoiseTexture2D` resource (e.g. 256×256) using `FastNoiseLite`. Export it as a PNG and import with `repeat_enable`. Using pre-generated textures (vs runtime noise) avoids per-frame noise evaluation but may show tiling — use larger textures if repetition is visible.

---

## Water Surface Shader (canvas_item)

The shader is a `canvas_item` shader applied to a `TileMap` node via a `ShaderMaterial`.

### Core Mechanism

- **Vertex stage:** transforms `VERTEX` by `MODEL_MATRIX` to get world-space position, stored in a `varying vec2 var_WorldPos`.
- **Fragment stage:** uses `floor(var_WorldPos)` as the pixelated UV base — this locks the texture coordinates to world-space pixels, so the pattern doesn't scroll with the camera.
- **Foam input:** reads `COLOR` (the per-vertex color of the TileMap tile) as a heightmap — lighter vertices = shallower/edge water = more foam.

### Complete Shader Code

```glsl
shader_type canvas_item;
render_mode blend_mix;

// Varyings
varying vec2 var_WorldPos;

uniform vec4 WaterColour : source_color;
uniform float CausticTextureScale = 0.0055;
uniform float MovementSpeed = 0.25;
uniform float MovementScale = 0.05;
uniform sampler2D MovementNoise : source_color, repeat_enable;
uniform float MovementStrength = 0.03;
uniform sampler2D CausticTexture : source_color, filter_nearest, repeat_enable;
uniform vec4 CausticColour : source_color = vec4(0.6, 0.878431, 0.878431, 0.431373);
uniform sampler2D CausticHighlightTexture : source_color, filter_nearest, repeat_enable;
uniform vec4 CausticHighlightColour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float RandomFadeSpeed = 0.03;
uniform float RandomFadeScale = 0.001;
uniform sampler2D RandomFadeNoise : source_color, repeat_enable;
uniform float RandomFadeStrength = 0.6;
uniform float SpecularScaleMoving = 0.07;
uniform float SpecularSpeed = 0.5;
uniform sampler2D SpecularNoiseTextureMoving1 : source_color, repeat_enable;
uniform sampler2D SpecularNoiseTextureMoving2 : source_color, repeat_enable;
uniform float SpecularThreshold = 0.5;
uniform vec4 SpecularColour : source_color = vec4(1.0, 1.0, 1.0, 0.843137);
uniform vec4 FoamColour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float FoamWaveSpeed = 5.0;
uniform float FoamNoiseScale = 0.000008;
uniform sampler2D FoamNoiseTexture : source_color, filter_nearest, repeat_enable;
uniform float FoamNoiseAmount = 0.8;
uniform float FoamFrequency = 32.0;
uniform float FoamQuantizeAmount = 4.0;

void vertex() {
    var_WorldPos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // --- 1. Pixelated world UV ---
    vec2 worldFloor = floor(var_WorldPos);

    // --- 2. Animated UV offset from noise ---
    vec2 moveUV = worldFloor * MovementScale + vec2(TIME * MovementSpeed);
    vec2 noiseOffset = texture(MovementNoise, moveUV).xy * MovementStrength;

    // --- 3. Caustic texture sampling ---
    vec2 causticUV = worldFloor * CausticTextureScale + noiseOffset;
    vec4 caustic = texture(CausticTexture, causticUV) * CausticColour;
    vec4 highlight = texture(CausticHighlightTexture, causticUV) * CausticHighlightColour;
    // Blend highlight over caustic using highlight alpha
    vec4 causticResult = mix(caustic, highlight, vec4(highlight.a));

    // --- 4. Random fade (prevents tiling repetition) ---
    vec2 fadeUV = worldFloor * RandomFadeScale + vec2(TIME * RandomFadeSpeed);
    float fadeNoise = texture(RandomFadeNoise, fadeUV).x;
    float fadedAlpha = fadeNoise * RandomFadeStrength * causticResult.a;
    vec4 fadedCaustic = vec4(causticResult.rgb, fadedAlpha);

    // --- 5. Specular highlights ---
    vec2 specBase = floor(var_WorldPos) * SpecularScaleMoving;
    vec2 specTime = vec2(SpecularSpeed * TIME);
    vec4 spec1 = texture(SpecularNoiseTextureMoving1, specBase - specTime);
    vec4 spec2 = texture(SpecularNoiseTextureMoving2, specBase + specTime);
    // Overlay blend of the two noise textures
    float specBlend;
    {
        float base = spec1.r; float blend = spec2.r;
        specBlend = (base < 0.5) ? 2.0 * base * blend : 1.0 - 2.0 * (1.0 - blend) * (1.0 - base);
    }
    float specMask = step(specBlend, SpecularThreshold);
    vec4 specResult = vec4(specMask) * SpecularColour;
    // Only show specular where there is caustic content
    float specAlpha = specResult.a * ceil(fadedAlpha);
    specResult.a = specAlpha;
    vec4 withSpec = mix(fadedCaustic, specResult, vec4(specAlpha));

    // --- 6. Combine with water base colour ---
    vec4 withWater = mix(WaterColour, withSpec, vec4(withSpec.a));

    // --- 7. Edge foam ---
    // COLOR is the per-vertex color from the TileMap (encodes height/edge data)
    float foamNoise = texture(FoamNoiseTexture, var_WorldPos * FoamNoiseScale).x;
    float foamWave = sin(TIME * FoamWaveSpeed * foamNoise * FoamNoiseAmount - COLOR.x * FoamFrequency);
    // Remap sin from [-1,1] to [0.1, 0.4]
    float foamThreshold = 0.1 + 0.3 * ((foamWave + 1.0) / 2.0);
    float foamRaw = COLOR.x - foamThreshold;
    float foamClamped = clamp(foamRaw, 0.0, 0.4);
    // Quantize for pixel art steps
    float foamQ = ceil(foamClamped * FoamQuantizeAmount) / FoamQuantizeAmount;
    float foamAlpha = foamQ * FoamColour.a;
    vec4 foamResult = vec4(FoamColour.rgb, foamAlpha);

    // --- 8. Combine foam with result ---
    vec4 finalColor = mix(withWater, foamResult, vec4(foamAlpha));

    // Multiply by vertex color alpha for tile transparency
    COLOR.rgb = finalColor.rgb;
    COLOR.a = finalColor.a * COLOR.a;
}
```

### Shader Parameters — Default Values and Purpose

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `WaterColour` | `Color(0.372, 0.549, 0.769, 0.796)` | Base water color (visible in deep areas) |
| `CausticTextureScale` | `0.0055` | How large caustic pattern appears in world space |
| `MovementSpeed` | `0.25` | Speed of the noise scroll driving UV distortion |
| `MovementScale` | `0.05` | How much world position contributes to movement offset |
| `MovementStrength` | `0.03` | Amplitude of UV distortion from noise |
| `CausticColour` | `rgba(0.6, 0.878, 0.878, 0.431)` | Tint for the base caustic texture |
| `CausticHighlightColour` | `rgba(1,1,1,1)` | Tint for the bright caustic highlights |
| `RandomFadeSpeed` | `0.03` | How fast the anti-repetition fade scrolls |
| `RandomFadeScale` | `0.001` | Zoom of the fade noise (large = slow variation) |
| `RandomFadeStrength` | `0.6` | Intensity of the fade effect |
| `SpecularScaleMoving` | `0.07` | Scale of specular noise in world space |
| `SpecularSpeed` | `0.5` | Speed of specular highlight movement |
| `SpecularThreshold` | `0.5` | Cutoff — higher = fewer/smaller highlights |
| `SpecularColour` | `rgba(1,1,1,0.843)` | Specular highlight tint |
| `FoamColour` | `rgba(1,1,1,1)` | Foam tint |
| `FoamWaveSpeed` | `5.0` | Speed of foam wave animation |
| `FoamNoiseScale` | `0.000008` | Zoom of foam noise (very small = large features) |
| `FoamNoiseAmount` | `0.8` | How much noise modulates the foam threshold |
| `FoamFrequency` | `32.0` | Spatial frequency of foam sine wave |
| `FoamQuantizeAmount` | `4.0` | Number of discrete foam intensity steps |

---

## TileMap Setup — Foam Heightmap via Vertex Colors

The foam system relies on TileMap per-vertex color to know where water edges are.
There is **no separate heightmap texture** — the vertex color IS the heightmap.

**How it works:**
- Edge/shallow tiles: vertex color closer to white (high R value) → more foam
- Deep center tiles: vertex color dark/black → no foam
- The shader reads `COLOR.x` as the foam height input

**Setting up TileMap vertex colors:**
In Godot 4, you can set per-tile modulate colors in the TileSet. Create your water tiles with appropriate colors baked into the tileset or applied via a script. Tiles at water edges should have lighter vertex colors.

Alternatively, encode height in the tile's modulate color and let the shader read it.

**TileSet configuration:**
- Create a `TileSet` resource
- Import water tile sprites (the source has `WaterTilesOffsetWithBlur.png` — tiles with pre-blurred edges for smooth foam transitions)
- Assign the `WaterMaterial` (ShaderMaterial with WaterShader) to the `TileMap` node's `material` property

---

## Ripple / Water Trail System

### Scene Structure

```
WaterTrail (Node2D)          ← FollowCursor script (or boat position driver)
├─ Sprite2D                  ← displays the SubViewport texture; uses WaterTrailSpriteMaterial
└─ SubViewport (256×256)     ← transparent_bg=true, disable_3d=true
    ├─ Line2D                ← Trails script; width=28; WaterTrailGradient texture; joint/cap=round
    └─ Circle (Sprite2D)     ← CircleBlur64x64, positioned at SubViewport center (128,128)
```

The `SubViewport` renders the trail into a texture. The `Sprite2D` displays that texture back in the scene, positioned at the moving object. The ripple shader on the Sprite2D animates the result.

### Trails Script (GDScript port of Trails.cs)

```gdscript
extends Line2D

@export var max_length: int = 20
@export var sub_viewport: SubViewport
@export var parent: Node2D
@export var distance_at_largest_width: float = 16.0 * 6.0
@export var smallest_tip_width: float = 0.5
@export var largest_tip_width: float = 1.0

var _length: float = 0.0
var _queue: Array[Vector2] = []
var _offset: Vector2

func _ready() -> void:
    _offset = Vector2(sub_viewport.size) / 2.0

func _process(_delta: float) -> void:
    _length = 0.0
    var pos := parent.global_position + _offset
    _queue.append(pos)
    while _queue.size() > max_length and _queue.size() > 2:
        _queue.pop_front()

    clear_points()
    for i in range(_queue.size() - 1):
        _length += _queue[i].distance_to(_queue[i + 1])
        add_point(parent.to_local(_queue[i]))
    add_point(parent.to_local(_queue[-1]))

    var t := inverse_lerp(0.0, distance_at_largest_width, _length)
    width_curve.set_point_value(0, lerpf(smallest_tip_width, largest_tip_width, t))

func reset_line() -> void:
    clear_points()
    _queue.clear()
```

### FollowCursor Script (GDScript port)

```gdscript
extends Node2D

func _physics_process(_delta: float) -> void:
    position = get_global_mouse_position()
```

Replace `get_global_mouse_position()` with your boat/object position for non-cursor use.

### Line2D Configuration

```
width = 28.0
width_curve: Curve with points [(0, 1.0), (1, 0.515882)]
gradient: Gradient [Color(1,1,1,0) → Color(1,1,1,1)]
texture = WaterTrailGradient.png
texture_mode = TILE (2)
joint_mode = ROUND (2)
begin_cap_mode = ROUND (2)
end_cap_mode = ROUND (2)
```

### Ripple Shader

Applied via `ShaderMaterial` to the trail `Sprite2D`. Animates the trail using a sine wave, then quantizes brightness.

```glsl
shader_type canvas_item;
render_mode blend_mix;

uniform float InitialAlpha = 0.46;
uniform float Speed = 0.1;
uniform float QuantizeColourAmount = 6.0;
uniform float BrightnessOffset = 0.0;
uniform float UpperCutoff = 0.3;

vec2 pixelate_uv(vec2 P, vec2 pixel_size) {
    return vec2(
        floor(P.x / pixel_size.x) * pixel_size.x,
        floor(P.y / pixel_size.y) * pixel_size.y
    );
}

void fragment() {
    vec2 pixUV = pixelate_uv(UV, TEXTURE_PIXEL_SIZE);
    vec4 tex = texture(TEXTURE, pixUV);

    // Animate brightness via sine wave driven by texture r value
    float timeScaled = TIME / Speed;
    float sinInput = tex.r * 15.0 + timeScaled;
    float sineVal = sin(sinInput);
    // Remap from [-1,1] to [-0.1, 0.1]
    float sinRemapped = sineVal * 0.1;

    // Subtract from initial alpha
    float baseAlpha = tex.r * InitialAlpha;
    float animAlpha = baseAlpha - sinRemapped;

    // Quantize
    float quantized = floor(animAlpha * QuantizeColourAmount) / QuantizeColourAmount;

    // Apply alpha from texture and brightness offset
    float finalAlpha = clamp(quantized * pow(tex.a, 2.0) + BrightnessOffset, 0.0, UpperCutoff);

    COLOR.rgb = vec3(1.0);
    COLOR.a = finalAlpha;
}
```

**Ripple material parameters (WaterTrailSpriteMaterial):**
- `InitialAlpha` = 0.6
- `Speed` = 0.09
- `QuantizeColourAmount` = 3.0
- `BrightnessOffset` = 0.0 (essentially 0)
- `UpperCutoff` = 0.5

---

## Full Scene Setup

```
Node2D (root)
├─ Camera2D
│   position = (390.5, 255)
│   zoom = Vector2(7, 7)       ← high zoom for pixel art look
│
├─ GrassTexture (Sprite2D)     ← background texture
│
├─ TileMap
│   material = WaterMaterial   ← ShaderMaterial using WaterShader
│   tile_set = WaterTileSet
│
└─ WaterTrail (Node2D)
    script = FollowCursor (or boat driver)
    ├─ Sprite2D
    │   material = WaterTrailSpriteMaterial (ShaderMaterial using RippleShader)
    │   texture = ViewportTexture(SubViewport path)
    └─ SubViewport
        size = Vector2i(256, 256)
        disable_3d = true
        transparent_bg = true
        ├─ Line2D
        │   script = Trails
        │   width = 28
        │   texture = WaterTrailGradient.png
        │   texture_mode = TILE
        │   [exports: subViewport="..", parent="../.."]
        └─ Circle (Sprite2D)
            position = Vector2(128, 128)
            scale = Vector2(0.3, 0.3)
            texture = CircleBlur64x64.png
```

---

## Custom Visual Shader Nodes (for VisualShader approach)

If building with the VisualShader editor instead of code, three custom `VisualShaderNodeCustom` GDScript files are used:

### VisualShaderNodePixelize.gd
Quantizes a vec2 UV by a scalar amount:
```gdscript
@tool
extends VisualShaderNodeCustom
class_name VisualShaderNodePixelize

func _get_name(): return "Pixelize"
func _get_category(): return "MyShaderNodes"
func _get_return_icon_type(): return VisualShaderNode.PORT_TYPE_VECTOR_2D
func _get_input_port_count(): return 2
func _get_input_port_name(port):
    match port:
        0: return "uv"
        1: return "amount"
func _get_input_port_type(port):
    match port:
        0: return VisualShaderNode.PORT_TYPE_VECTOR_2D
        1: return VisualShaderNode.PORT_TYPE_SCALAR
func _get_output_port_count(): return 1
func _get_output_port_name(_port): return "result"
func _get_output_port_type(_port): return VisualShaderNode.PORT_TYPE_VECTOR_2D
func _init(): set_input_port_default_value(1, 0.0)
func _get_global_code(_mode): return """
    float floatPixelate(float f, float amount) {
        return floor(f * amount) / amount;
    }
    vec2 pixelate(vec2 P, float amount) {
        return vec2(floatPixelate(P.x, amount), floatPixelate(P.y, amount));
    }
"""
func _get_code(input_vars, output_vars, _mode, _type):
    return output_vars[0] + " = pixelate(%s.xy, %s);" % [input_vars[0], input_vars[1]]
```

### VisualShaderNodePixelizeUV.gd
Quantizes a vec2 UV by a vec2 pixel size:
```gdscript
@tool
extends VisualShaderNodeCustom
class_name VisualShaderNodePixelizeUV

func _get_name(): return "PixelizeUV"
func _get_category(): return "MyShaderNodes"
func _get_return_icon_type(): return VisualShaderNode.PORT_TYPE_VECTOR_2D
func _get_input_port_count(): return 2
func _get_input_port_name(port):
    match port:
        0: return "uv"
        1: return "pixelSize"
func _get_input_port_type(port):
    match port:
        0: return VisualShaderNode.PORT_TYPE_VECTOR_2D
        1: return VisualShaderNode.PORT_TYPE_VECTOR_2D
func _get_output_port_count(): return 1
func _get_output_port_name(_port): return "result"
func _get_output_port_type(_port): return VisualShaderNode.PORT_TYPE_VECTOR_2D
func _init(): set_input_port_default_value(1, Vector2(0.1, 0.1))
func _get_global_code(_mode): return """
    float floatPixelate1(float f, float amount) {
        return floor(f * amount) / amount;
    }
    vec2 pixelate_uv(vec2 P, vec2 pixel_size) {
        float x_amount = 1.0 / pixel_size.x;
        float y_amount = 1.0 / pixel_size.y;
        return vec2(floatPixelate1(P.x, x_amount), floatPixelate1(P.y, y_amount));
    }
"""
func _get_code(input_vars, output_vars, _mode, _type):
    return output_vars[0] + " = pixelate_uv(%s.xy, %s.xy);" % [input_vars[0], input_vars[1]]
```

---

## Implementation Notes

### Using Code Shaders vs VisualShader

The `.tres` files in the original store `VisualShader` resources with the compiled GLSL embedded in a `code` property. When implementing from scratch, it is simpler to write the shader directly as GLSL code (using a `Shader` resource with `.gdshader` extension) rather than recreating the visual graph. The compiled GLSL extracted above can be used directly.

### Foam Without a Heightmap

The most important implementation detail: **the foam does not use a separate heightmap texture**. It reads `COLOR` (the TileMap's per-vertex color) directly. To use this:
- Paint your TileMap tiles so edge tiles have a lighter vertex color (high R value)
- The water material is applied to the TileMap, not individual sprites
- The shader reads `COLOR.x` as the foam height value per pixel

### World-Space UV Locking

Using `floor(var_WorldPos)` as the UV source (rather than `UV`) means the water texture is locked to world coordinates. This is the key technique for pixel-art water — the pattern doesn't swim/slide as the camera moves. The `floor()` call snaps to integer world pixels.

### Performance Considerations

- All noise textures are pre-baked (no runtime noise generation)
- The shader samples 7 textures per fragment — acceptable for a 2D scene
- The SubViewport for trails renders at 256×256, keeping trail rendering cheap
- Use `filter_nearest` for caustic textures to preserve the pixel-art look

### Adapting for Non-Cursor Use

To attach the trail to a boat or character instead of the cursor:
1. Remove `FollowCursor` script (or `_physics_process` override)
2. Drive `WaterTrail.position` from your boat's `global_position`
3. In `Trails`, change `parent.global_position` to reference your object

### GDScript vs C#

The original uses C# (`Trails.cs`, `FollowCursor.cs`). The GDScript ports above are functionally identical. Key differences:
- `Queue<Vector2>` → `Array[Vector2]` with `pop_front()`
- `Mathf.Lerp/InverseLerp` → `lerpf/inverse_lerp`
- `ClearPoints()` → `clear_points()`
- `AddPoint()` → `add_point()`

---

## Quick Checklist for Implementation

- [ ] Create `WaterShader.gdshader` with the GLSL code above
- [ ] Create `WaterMaterial` (ShaderMaterial) referencing the shader
- [ ] Import all noise textures with `repeat_enable`; caustic textures with `filter_nearest`
- [ ] Set up TileMap with `WaterMaterial` and vertex colors encoding edge height
- [ ] Create `RippleShader.gdshader` for trail effect
- [ ] Create `WaterTrailSpriteMaterial` (ShaderMaterial) referencing ripple shader
- [ ] Set up SubViewport (256×256, transparent) with Line2D and Trails script
- [ ] Connect ViewportTexture to Sprite2D
- [ ] Wire up cursor/boat position driver to `WaterTrail` node
- [ ] Tune `WaterColour`, `CausticColour`, foam, and specular parameters to taste
