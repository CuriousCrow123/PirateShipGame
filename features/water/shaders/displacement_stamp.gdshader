shader_type canvas_item;

// Encodes radial displacement direction as RG color for the displacement map.
// R = X offset, G = Y offset. 0.5 = neutral (no displacement).
// Used on Sprite2D stamps inside the displacement SubViewport.

uniform float RingRadius : hint_range(0.0, 0.5) = 0.0;
uniform float RingWidth : hint_range(0.01, 0.5) = 0.15;
uniform float Amplitude : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	vec2 dir = (dist > 0.001) ? normalize(centered) : vec2(0.0);

	// Ring or disc shape with smooth falloff
	float shape = smoothstep(RingRadius - RingWidth, RingRadius, dist)
		* smoothstep(RingRadius + RingWidth, RingRadius, dist);

	// Encode direction: 0.5 = neutral, direction * amplitude shifts from neutral
	vec2 encoded = dir * Amplitude * 0.5 + 0.5;
	COLOR = vec4(encoded.x, encoded.y, 0.0, shape);
}
