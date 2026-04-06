shader_type canvas_item;
// SubViewport.get_texture() may return non-premultiplied data where RGB is
// undefined at alpha=0. We use blend_premul_alpha for correct compositing
// and guard reads with tex.a to discard garbage in transparent areas.
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

	// Guard: discard garbage RGB where alpha is near zero
	float safeR = tex.r * step(0.01, tex.a);

	// Animate brightness via sine wave driven by texture r value
	float timeScaled = TIME / Speed;
	float sinInput = safeR * 15.0 + timeScaled;
	float sineVal = sin(sinInput);
	// Remap from [-1,1] to [-0.1, 0.1]
	float sinRemapped = sineVal * 0.1;

	// Subtract from initial alpha
	float baseAlpha = safeR * InitialAlpha;
	float animAlpha = baseAlpha - sinRemapped;

	// Quantize for pixel art steps
	float quantized = floor(animAlpha * QuantizeColourAmount) / QuantizeColourAmount;

	// Apply alpha from texture and brightness offset
	float finalAlpha = clamp(quantized * pow(tex.a, 2.0) + BrightnessOffset, 0.0, UpperCutoff);

	// Premultiply output for blend_premul_alpha
	COLOR.rgb = vec3(finalAlpha);
	COLOR.a = finalAlpha;
}
