shader_type spatial;
// The printed face of a flash card: matte laminated paper with rounded
// corners. The lamination's clear edge lights up in the card's colour while
// the card is held, and sequence cards fill a thin bar along the bottom as
// their macro plays.

uniform sampler2D face : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 size = vec2(0.11, 0.08);  // metres
uniform float radius = 0.007;
uniform float edge = 0.0032;  // the clear laminated border
uniform vec3 edge_color : source_color = vec3(1.0);
uniform float glow = 0.0;
uniform float progress = -1.0;  // below 0: no bar

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	float d = rounded_box(p, size * 0.5, radius);  // < 0 inside the card
	vec3 paper = texture(face, UV).rgb;
	// The laminate: a pale, slightly cool rim where the paper stops short.
	float rim = smoothstep(-edge - 0.0003, -edge + 0.0003, d);
	vec3 laminate = vec3(0.9, 0.92, 0.93);
	vec3 col = mix(paper, laminate, rim);
	vec3 light = edge_color * glow * rim * 2.5;
	col = mix(col, edge_color, rim * clamp(glow, 0.0, 1.0) * 0.6);

	if (progress >= 0.0) {
		float bottom = p.y + size.y * 0.5;
		float bar = step(edge + 0.0012, bottom) * step(bottom, edge + 0.0042);
		float x = (p.x + size.x * 0.5 - edge - 0.002) / (size.x - 2.0 * edge - 0.004);
		bar *= step(0.0, x) * step(x, 1.0);
		float filled = step(x, progress);
		col = mix(col, mix(vec3(0.8), edge_color, filled), bar);
		light += edge_color * bar * filled * 1.5;
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.72, 0.45, rim);
	SPECULAR = 0.3;
	EMISSION = light;
}
