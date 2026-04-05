shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// --- Noise ---
uniform sampler2D NoiseTexture : hint_default_white, filter_linear;
uniform float NoiseStrength : hint_range(0.0, 1.0) = 0.3;

// --- Colours ---
uniform vec3 DarkColour : source_color = vec3(0.2, 0.15, 0.1);
uniform vec3 FireColour : source_color = vec3(1.0, 0.5, 0.0);

// --- Dissolve control ---
uniform float DissolveSoftness : hint_range(0.01, 0.5) = 0.15;
uniform float DissolveSpeed : hint_range(0.5, 3.0) = 1.5;

// --- Emission / Glow ---
uniform float EmissionIntensity : hint_range(0.0, 10.0) = 4.0;
uniform float EdgeGlowWidth : hint_range(0.01, 0.3) = 0.08;

// INSTANCE_CUSTOM is only available in vertex(); pass to fragment() via varying.
// COLOR carries the color_ramp from ParticleProcessMaterial.
varying float dissolve_progress;
varying vec4 particle_color;

void vertex() {
	dissolve_progress = INSTANCE_CUSTOM.y;
	particle_color = COLOR;
}

void fragment() {
	// --- Radial gradient: 0 at center, 1 at edges ---
	float radial = length(UV - vec2(0.5)) * 2.0;

	// --- Noise adds organic breakup to the dissolve ---
	float noise_val = texture(NoiseTexture, UV).r;
	float dissolve_mask = radial + noise_val * NoiseStrength;

	// --- Dissolve threshold increases over lifetime ---
	float threshold = dissolve_progress * DissolveSpeed;

	// --- Soft alpha: feathered edge instead of hard scissor ---
	float alpha = 1.0 - smoothstep(threshold - DissolveSoftness, threshold + DissolveSoftness, dissolve_mask);

	// --- Edge glow: bright band at the dissolve front ---
	float edge = smoothstep(threshold - EdgeGlowWidth, threshold, dissolve_mask)
	           * (1.0 - smoothstep(threshold, threshold + EdgeGlowWidth, dissolve_mask));

	// --- Initial flash: blinding at start, fades by 30% lifetime ---
	float flash = pow(max(1.0 - dissolve_progress * 3.0, 0.0), 2.0);

	// --- Combine: particle_color carries the color_ramp lifecycle ---
	vec3 base_color = particle_color.rgb;
	vec3 color = base_color + edge * FireColour * 2.0 + flash * vec3(1.0);

	ALBEDO = color;
	EMISSION = (edge * FireColour + flash * vec3(1.0, 0.9, 0.7)) * EmissionIntensity;
	ALPHA = alpha * particle_color.a;
}
