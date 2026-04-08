shader_type canvas_item;

uniform float RingCount : hint_range(1.0, 8.0) = 3.0;
uniform float RingThickness : hint_range(0.01, 0.15) = 0.04;
uniform float ExpandSpeed : hint_range(-10.0, 10.0) = -2.0;
uniform float MaxRadius : hint_range(0.1, 0.5) = 0.45;
uniform vec4 RingColor : source_color = vec4(0.8, 0.9, 1.0, 0.35);
uniform float BobPhase : hint_range(-1.0, 1.0) = 0.0;
uniform float PixelSnap : hint_range(4.0, 64.0) = 32.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;

	// Quantize UV to pixel grid for pixel-art look
	uv = floor(uv * PixelSnap) / PixelSnap;
	float dist = length(uv);

	// Expanding ring positions — evenly spaced, wrapping with time
	float ring_spacing = MaxRadius / RingCount;
	float time_offset = fract(TIME * abs(ExpandSpeed) * 0.1);
	float ring_alpha = 0.0;

	for (float i = 0.0; i < 8.0; i += 1.0) {
		if (i >= RingCount) break;
		float ring_pos = fract(i / RingCount + time_offset) * MaxRadius;
		// Hard pixel-art ring: 1px line at this radius
		float on_ring = step(ring_pos - RingThickness, dist) * step(dist, ring_pos + RingThickness);
		// Fade ring out as it expands
		float ring_fade = 1.0 - ring_pos / MaxRadius;
		ring_alpha = max(ring_alpha, on_ring * ring_fade);
	}

	// Clip beyond max radius
	ring_alpha *= step(dist, MaxRadius);

	// Modulate by bob phase (stronger at bob extremes)
	float bob_strength = 0.5 + 0.5 * abs(BobPhase);

	COLOR = RingColor;
	COLOR.a *= ring_alpha * bob_strength;
}
