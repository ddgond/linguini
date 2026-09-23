// The filter's falling sheet of water: translucent streaks sliding down.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

void fragment() {
	float streaks = 0.5 + 0.5 * sin(UV.x * 90.0 + sin(UV.x * 17.0) * 2.0);
	float flow = fract(UV.y * 3.0 - TIME * 2.2);
	float a = mix(0.25, 0.6, streaks) * mix(0.7, 1.0, flow);
	ALBEDO = vec3(0.85, 0.95, 1.0);
	ALPHA = a;
}
