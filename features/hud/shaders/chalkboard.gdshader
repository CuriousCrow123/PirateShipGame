shader_type canvas_item;

// Board base
uniform vec4 BoardColour : source_color = vec4(0.08, 0.08, 0.10, 1.0);

// Chalk grain (fine noise for surface texture)
uniform sampler2D GrainNoise : filter_linear, repeat_enable;
uniform float GrainScale : hint_range(0.5, 8.0) = 3.0;
uniform float GrainStrength : hint_range(0.0, 0.15) = 0.02;

// Dust smudge (large-scale chalk residue variation)
uniform sampler2D SmudgeNoise : filter_linear, repeat_enable;
uniform float SmudgeScale : hint_range(0.1, 2.0) = 0.5;
uniform float SmudgeStrength : hint_range(0.0, 0.3) = 0.04;
uniform vec4 SmudgeColour : source_color = vec4(0.6, 0.6, 0.62, 1.0);

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

	COLOR = vec4(board, 0.85);
}
