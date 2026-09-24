shader_type spatial;
// A mote drifting in the tank water: a tiny soft dot, facing the camera.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.0, d) * COLOR.a;
	ALBEDO = vec3(0.75, 0.9, 0.85) * a * 0.35;
}
