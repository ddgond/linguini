shader_type spatial;
// A soft shaft of lamp light falling through the water: brightest at the
// top, fading down, with slow shimmering streaks.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float seed = 0.0;
uniform float strength = 0.07;
uniform vec3 tint : source_color = vec3(0.8, 0.95, 1.0);
uniform float half_height = 0.25;

varying float up;  // 0 at the shaft's foot, 1 at its top (by the lamp)

void vertex() {
	up = clamp(VERTEX.y / half_height * 0.5 + 0.5, 0.0, 1.0);
}

float streaks(float x, float t) {
	return 0.55 + 0.25 * sin(x * 17.0 + t * 0.7 + seed) + 0.2 * sin(x * 41.0 - t * 1.1 + seed * 2.0);
}

void fragment() {
	// smoothstep() needs edge0 < edge1, so the far edges are 1 - smoothstep.
	float edge = smoothstep(0.0, 0.35, UV.x) * (1.0 - smoothstep(0.65, 1.0, UV.x));
	// With MSAA, pixels on the plane's edge can sample the varying from just
	// outside it; a slightly negative `up` makes pow() NaN, and glow blooms
	// that into a white bar along the shaft's foot. Clamp it back.
	float u = clamp(up, 0.0, 1.0);
	// Brightest by the lamp, fading down, and soft at both ends so neither
	// the water's surface nor the gravel shows a hard edge.
	float fall = pow(u, 1.6) * smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.9, 1.0, u));
	float s = streaks(UV.x, TIME);
	// Fade where the plane is seen edge-on, so it never shows as a sheet.
	float facing = abs(dot(NORMAL, VIEW));
	float a = edge * fall * s * strength * smoothstep(0.1, 0.5, facing);
	ALBEDO = tint * a;
}
