shader_type spatial;
render_mode unshaded, cull_disabled;

// --- Noise ---
uniform sampler2D NoiseTexture : hint_default_white, filter_linear;

// --- Colours ---
uniform vec3 DarkColour : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 FireColour : source_color = vec3(1.0, 0.5, 0.0);

// --- Dissolve control ---
uniform float SmoothStepEdge : hint_range(0.0, 1.0) = 0.0;
uniform float BrightDissolveScale : hint_range(0.5, 2.0) = 1.2;
uniform float DarkDissolveScale : hint_range(0.5, 2.0) = 0.8;

// --- Fresnel ---
uniform float FresnelPowerBright : hint_range(0.0, 8.0) = 1.0;
uniform float FresnelPowerDark : hint_range(0.0, 8.0) = 0.5;

// --- Alpha control ---
// Scales the fire-core alpha (bright_mask) and the smoke-stage alpha (dark_mask) independently.
// Lower DarkAlphaScale → more translucent smoke; lower BrightAlphaScale → more translucent fire.
uniform float BrightAlphaScale : hint_range(0.0, 2.0) = 1.0;
uniform float DarkAlphaScale : hint_range(0.0, 2.0) = 1.0;

// INSTANCE_CUSTOM is only available in vertex(); pass to fragment() via varying.
varying float dissolve_progress;

float fresnel(float power, vec3 normal, vec3 view) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), power);
}

void vertex() {
	// ParticleProcessMaterial sets INSTANCE_CUSTOM.y to normalized lifetime (0→1).
	dissolve_progress = INSTANCE_CUSTOM.y;
}

void fragment() {
	float noise_val = texture(NoiseTexture, UV).r;

	// --- Dark layer (lower fresnel power, slower dissolve) ---
	// Forms the smoke silhouette that lingers after the fire fades.
	float dark_fresnel = fresnel(FresnelPowerDark, NORMAL, VIEW);
	float dark_base = (1.0 - dark_fresnel) + noise_val;
	float dark_dissolve = dissolve_progress * DarkDissolveScale * 2.0;
	float dark_raw = dark_base - dark_dissolve;
	float dark_mask = smoothstep(0.0, SmoothStepEdge, dark_raw);

	// --- Bright layer (higher fresnel power, faster dissolve) ---
	// Fire core that burns away quickly, revealing the dark smoke beneath.
	float bright_fresnel = fresnel(FresnelPowerBright, NORMAL, VIEW);
	float bright_base = (1.0 - bright_fresnel) + noise_val;
	float bright_dissolve = dissolve_progress * BrightDissolveScale * 2.0;
	float bright_raw = bright_base - bright_dissolve;
	float bright_mask = smoothstep(0.0, SmoothStepEdge, bright_raw);

	// --- Combine: dark defines silhouette, bright adds fire within it ---
	// Boost fire color so the opaque core stands out against the smoke.
	vec3 color = dark_mask * DarkColour + bright_mask * FireColour * 1.8;

	ALBEDO = color;
	// Fire core renders near-opaque via bright_mask; once the fire fades,
	// alpha drops to the much lower smoke level driven by dark_mask alone.
	// No ALPHA_SCISSOR_THRESHOLD — that would force opaque/discard and kill blending.
	ALPHA = max(bright_mask * BrightAlphaScale, dark_mask * 0.08 * DarkAlphaScale);
}
