# Water Shader Guide

## Quick Start

1. Open the project in Godot 4.6
2. Press Play (F5) — the main scene runs automatically
3. Move the mouse cursor over the water to see ripple trails

## How It Works

### System 1: Water Surface (TileMap shader)

The [water_surface.gdshader](../shaders/water_surface.gdshader) renders animated caustics and edge foam on a TileMap:

- **Caustics**: Two-layer noise-driven UV animation samples a caustic texture. `floor(var_WorldPos)` locks textures to world-space pixels so the pattern doesn't swim with camera movement.
- **Foam**: Reads tile edge gradients from the tile texture. Edge tiles have bright pixels (high foam), center tiles are dark (no foam). Animated via sine wave and quantized for pixel-art steps.

### System 2: Ripple Trail (SubViewport + Line2D)

The cursor drives a `Line2D` rendered inside a 256x256 SubViewport. A [ripple shader](../shaders/ripple.gdshader) on the displaying Sprite2D animates brightness and quantizes it for a pixel-art look.

## Enabling Deferred Features

Three visual features are commented out in the shader, ready to enable:

### Specular Highlights
1. Open [water_surface.gdshader](../shaders/water_surface.gdshader)
2. Uncomment the `Specular` uniform declarations (~lines 34-40)
3. Uncomment the specular block in `fragment()` (~lines 87-100)
4. In the ShaderMaterial, add two `NoiseTexture2D` resources for `SpecularNoiseTextureMoving1/2`

### Random Fade (anti-tiling)
1. Uncomment the `RandomFade` uniform declarations (~lines 28-31)
2. Uncomment the fade block in `fragment()` (~lines 79-82)
3. Add a `NoiseTexture2D` resource for `RandomFadeNoise`

### Caustic Highlight Layer
1. Uncomment the `CausticHighlight` uniform declarations (~lines 24-25)
2. Uncomment the highlight blend in `fragment()` (~lines 75-77)
3. Wire `CausticTextureHighlights.png` (already downloaded in `textures/`)

## Swapping Cursor for Boat

To use a boat or character instead of the mouse cursor:

1. Remove or disable the `follow_cursor.gd` script from the WaterTrail node
2. Drive `WaterTrail.global_position` from your boat's position each frame:
   ```gdscript
   # In your boat script:
   func _process(_delta: float) -> void:
       $"../WaterTrail".global_position = global_position
   ```
3. Or change the `follow_target` export on the Line2D's Trails script to point at your boat node

## Parameter Tuning

### Water Surface

| Parameter | Effect | Range |
|-----------|--------|-------|
| `WaterColour` | Base water color (deep areas) | Any color |
| `CausticTextureScale` | Caustic pattern size | 0.001–0.1 (smaller = larger pattern) |
| `MovementSpeed` | How fast caustics animate | 0.0–1.0 |
| `MovementStrength` | Amount of UV distortion | 0.0–0.1 |
| `FoamWaveSpeed` | Foam animation speed | 0.0–10.0 |
| `FoamFrequency` | Spatial frequency of foam wave | 1.0–64.0 |
| `FoamQuantizeAmount` | Pixel-art foam steps | 1.0–16.0 (lower = chunkier) |

### Ripple Trail

| Parameter | Effect | Range |
|-----------|--------|-------|
| `InitialAlpha` | Overall ripple brightness | 0.0–1.0 |
| `Speed` | Ripple animation speed | 0.01–1.0 (lower = faster) |
| `QuantizeColourAmount` | Pixel-art ripple steps | 1.0–16.0 |
| `UpperCutoff` | Maximum ripple brightness | 0.0–1.0 |

## Architecture Reference

```
Main (Node2D) — scripts/main.gd (ViewportTexture wiring)
├── Camera2D
├── TileMap — water_surface_material.tres
└── WaterTrail (Node2D) — scripts/follow_cursor.gd
    ├── TrailSprite (Sprite2D) — ripple_material.tres
    └── SubViewport (256x256, transparent)
        ├── Line2D — scripts/trails.gd
        └── Circle (Sprite2D) — CircleBlur64x64.png
```
