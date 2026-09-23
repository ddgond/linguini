// The water surface on the Low preset: the same waves and colours as
// water_surface.gdshader, without reading the screen for refraction.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;

#include "res://shaders/water_surface.gdshaderinc"

uniform vec3 shallow : source_color = vec3(0.55, 0.85, 0.88);
uniform vec3 underside : source_color = vec3(0.18, 0.45, 0.5);

varying vec2 surface_pos;

void vertex() {
	surface_pos = VERTEX.xz;
	VERTEX.y += wave(VERTEX.xz, TIME) * wave_height;
}

void fragment() {
	vec3 n = wave_normal(surface_pos, TIME);
	float facing = abs(dot(NORMAL, VIEW));
	if (FRONT_FACING) {
		float fresnel = pow(1.0 - facing, 3.0);
		ALBEDO = mix(shallow, vec3(0.85, 0.95, 1.0), fresnel);
		ALPHA = 0.3 + fresnel * 0.5;
	} else {
		float window = smoothstep(0.55, 0.8, facing);
		ALBEDO = mix(underside, vec3(0.75, 0.9, 0.95), window);
		ALPHA = mix(0.8, 0.45, window);
	}
	vec3 view_n = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = FRONT_FACING ? view_n : -view_n;
	ROUGHNESS = 0.05;
}
