shader_type canvas_item;
render_mode blend_mix;

// --- Varyings ---
// CRITICAL: Capture vertex color in vertex() before fragment() multiplies it by texture.
// In Godot 4 TileMap shaders, COLOR in fragment() = texture * vertex_color * modulate.
// We need the raw vertex color for foam height input. See Godot #69766.
varying vec2 var_WorldPos;
varying vec4 var_VertexColor;

// --- Water base ---
uniform vec4 WaterColour : source_color = vec4(0.372549, 0.54902, 0.768627, 0.796078);

// --- Caustics ---
uniform float CausticTextureScale : hint_range(0.001, 0.1) = 0.0055;
uniform float MovementSpeed : hint_range(0.0, 1.0) = 0.25;
uniform float MovementScale : hint_range(0.01, 0.2) = 0.05;
// Noise textures need smooth interpolation for UV distortion — explicit filter_linear
// because the project default is Nearest after pixel art setup.
uniform sampler2D MovementNoise : source_color, filter_linear, repeat_enable;
uniform float MovementStrength : hint_range(0.0, 0.1) = 0.03;
uniform sampler2D CausticTexture : source_color, filter_nearest, repeat_enable;
uniform vec4 CausticColour : source_color = vec4(0.6, 0.878431, 0.878431, 0.321569);

// --- Caustic highlights (deferred) ---
// TODO(post-mvp): Enable caustic highlight layer — uncomment and wire CausticTextureHighlights.png
//uniform sampler2D CausticHighlightTexture : source_color, filter_nearest, repeat_enable;
//uniform vec4 CausticHighlightColour : source_color = vec4(1.0, 1.0, 1.0, 0.792157);

// --- Random fade (deferred) ---
// TODO(post-mvp): Enable random fade — uncomment and wire RandomFadeNoise (NoiseTexture2D)
//uniform float RandomFadeSpeed = 0.03;
//uniform float RandomFadeScale = 0.001;
//uniform sampler2D RandomFadeNoise : source_color, filter_linear, repeat_enable;
//uniform float RandomFadeStrength = 0.6;

// --- Specular highlights (deferred) ---
// TODO(post-mvp): Enable specular highlights — uncomment and wire SpecularNoiseTextureMoving1/2 (NoiseTexture2D)
//uniform float SpecularScaleMoving = 0.007;
//uniform float SpecularSpeed = 0.03;
//uniform sampler2D SpecularNoiseTextureMoving1 : source_color, filter_linear, repeat_enable;
//uniform sampler2D SpecularNoiseTextureMoving2 : source_color, filter_linear, repeat_enable;
//uniform float SpecularThreshold = 0.15;
//uniform vec4 SpecularColour : source_color = vec4(1.0, 1.0, 1.0, 0.843137);

// --- Edge foam ---
uniform vec4 FoamColour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float FoamWaveSpeed : hint_range(0.0, 10.0) = 5.0;
uniform float FoamNoiseScale : hint_range(0.00001, 0.001) = 0.00008;
uniform sampler2D FoamNoiseTexture : source_color, filter_nearest, repeat_enable;
uniform float FoamNoiseAmount : hint_range(0.0, 2.0) = 0.8;
uniform float FoamFrequency : hint_range(1.0, 64.0) = 32.0;
uniform float FoamQuantizeAmount : hint_range(1.0, 16.0) = 4.0;


void vertex() {
	var_WorldPos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	// Capture vertex color BEFORE fragment stage multiplies by tile texture.
	var_VertexColor = COLOR;
}

void fragment() {
	// --- 1. Pixelated world UV ---
	// floor() locks textures to world-space pixels so pattern doesn't swim with camera.
	vec2 worldFloor = floor(var_WorldPos);

	// --- 2. Animated UV offset from noise ---
	vec2 moveUV = worldFloor * MovementScale + vec2(TIME * MovementSpeed);
	vec2 noiseOffset = texture(MovementNoise, moveUV).xy * MovementStrength;

	// --- 3. Caustic texture sampling ---
	vec2 causticUV = worldFloor * CausticTextureScale + noiseOffset;
	vec4 causticResult = texture(CausticTexture, causticUV) * CausticColour;

	// TODO(post-mvp): Caustic highlight layer blended over base caustic
	// vec4 highlight = texture(CausticHighlightTexture, causticUV) * CausticHighlightColour;
	// causticResult = mix(causticResult, highlight, vec4(highlight.a));

	// TODO(post-mvp): Random fade to prevent tiling repetition
	// vec2 fadeUV = worldFloor * RandomFadeScale + vec2(TIME * RandomFadeSpeed);
	// float fadeNoise = texture(RandomFadeNoise, fadeUV).x;
	// causticResult.a *= fadeNoise * RandomFadeStrength;

	// --- 4. Combine with water base colour ---
	vec4 withWater = mix(WaterColour, causticResult, vec4(causticResult.a));

	// TODO(post-mvp): Specular highlights
	// vec2 specBase = worldFloor * SpecularScaleMoving;
	// vec2 specTime = vec2(SpecularSpeed * TIME);
	// vec4 spec1 = texture(SpecularNoiseTextureMoving1, specBase - specTime);
	// vec4 spec2 = texture(SpecularNoiseTextureMoving2, specBase + specTime);
	// float specBlend;
	// {
	//     float base_val = spec1.r; float blend_val = spec2.r;
	//     specBlend = (base_val < 0.5)
	//         ? 2.0 * base_val * blend_val
	//         : 1.0 - 2.0 * (1.0 - blend_val) * (1.0 - base_val);
	// }
	// float specMask = step(specBlend, SpecularThreshold);
	// vec4 specResult = vec4(specMask) * SpecularColour;
	// float specAlpha = specResult.a * ceil(causticResult.a);
	// specResult.a = specAlpha;
	// withWater = mix(withWater, specResult, vec4(specAlpha));

	// --- 5. Edge foam ---
	// Foam height comes from the tile texture's baked edge gradients:
	// bright pixels = shallow/edge = more foam, dark pixels = deep = no foam.
	// We sample the tile texture directly rather than using COLOR.x (which in
	// fragment() already includes texture * modulate — see Godot #69766).
	// var_VertexColor.x is available as an optional per-tile multiplier.
	float foamHeight = texture(TEXTURE, UV).r * var_VertexColor.x;
	float foamNoise = texture(FoamNoiseTexture, var_WorldPos * FoamNoiseScale).x;
	float foamWave = sin(TIME * FoamWaveSpeed * foamNoise * FoamNoiseAmount - foamHeight * FoamFrequency);
	// Remap sin from [-1,1] to [0.1, 0.4]
	float foamThreshold = 0.1 + 0.3 * ((foamWave + 1.0) / 2.0);
	float foamRaw = foamHeight - foamThreshold;
	float foamClamped = clamp(foamRaw, 0.0, 0.4);
	// Quantize for pixel art steps
	float foamQ = ceil(foamClamped * FoamQuantizeAmount) / FoamQuantizeAmount;
	float foamAlpha = foamQ * FoamColour.a;
	vec4 foamResult = vec4(FoamColour.rgb, foamAlpha);

	// --- 6. Combine foam with result ---
	vec4 finalColor = mix(withWater, foamResult, vec4(foamAlpha));

	// Multiply by vertex color alpha for tile transparency
	COLOR.rgb = finalColor.rgb;
	COLOR.a = finalColor.a * var_VertexColor.a;
}
