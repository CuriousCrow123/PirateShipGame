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

	// --- Dark layer (fresnel power 0.5, slower dissolve) ---
	float dark_fresnel = fresnel(FresnelPowerDark, NORMAL, VIEW);
	float dark_base = (1.0 - dark_fresnel) + noise_val;
	float dark_dissolve = dissolve_progress * DarkDissolveScale * 2.0;
	float dark_raw = dark_base - dark_dissolve;
	float dark_mask = smoothstep(0.0, SmoothStepEdge, dark_raw);

	// --- Bright layer (fresnel power 1.0, faster dissolve) ---
	float bright_fresnel = fresnel(FresnelPowerBright, NORMAL, VIEW);
	float bright_base = (1.0 - bright_fresnel) + noise_val;
	float bright_dissolve = dissolve_progress * BrightDissolveScale * 2.0;
	float bright_raw = bright_base - bright_dissolve;
	float bright_mask = smoothstep(0.0, SmoothStepEdge, bright_raw);

	// --- Combine layers ---
	// Tutorial: dark_mask controls alpha (defines silhouette).
	// Bright layer adds fire colour within the dark layer's shape.
	vec3 color = dark_mask * DarkColour + bright_mask * FireColour;

	ALBEDO = color;
	ALPHA = dark_mask;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
