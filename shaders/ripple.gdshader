shader_type canvas_item;
// Forward+ SubViewport with transparent_bg outputs premultiplied alpha.
// Without this, semi-transparent ripple areas render too dark.
// See Godot #99715.
render_mode blend_premul_alpha;

uniform float InitialAlpha : hint_range(0.0, 1.0) = 0.46;
uniform float Speed : hint_range(0.01, 1.0) = 0.1;
uniform float QuantizeColourAmount : hint_range(1.0, 16.0) = 6.0;
uniform float BrightnessOffset : hint_range(-1.0, 1.0) = 0.0;
uniform float UpperCutoff : hint_range(0.0, 1.0) = 0.3;

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

	// Quantize for pixel art steps
	float quantized = floor(animAlpha * QuantizeColourAmount) / QuantizeColourAmount;

	// Apply alpha from texture and brightness offset
	float finalAlpha = clamp(quantized * pow(tex.a, 2.0) + BrightnessOffset, 0.0, UpperCutoff);

	COLOR.rgb = vec3(1.0);
	COLOR.a = finalAlpha;
}
