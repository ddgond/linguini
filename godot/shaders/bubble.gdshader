// A little air bubble: mostly clear, bright at its rim, with a highlight.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

void fragment() {
	float facing = dot(NORMAL, VIEW);
	float rim = pow(1.0 - clamp(facing, 0.0, 1.0), 2.5);
	ALBEDO = vec3(0.9, 0.97, 1.0);
	ALPHA = clamp(0.08 + rim * 0.85, 0.0, 1.0) * COLOR.a;
	ROUGHNESS = 0.02;
	SPECULAR = 1.0;
	EMISSION = vec3(0.25, 0.3, 0.32) * rim;
}
