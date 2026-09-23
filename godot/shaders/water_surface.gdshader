// The water surface, seen from above or from below. From below (from the
// fish's point of view) it bends what's above it, with a bright wobbling
// "Snell's window" straight up and a darker mirror-like sheen at a slant.
// Medium and High use this; Low uses water_surface_low.gdshader.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;

#include "res://shaders/water_surface.gdshaderinc"

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow : source_color = vec3(0.55, 0.85, 0.88);
uniform vec3 underside : source_color = vec3(0.18, 0.45, 0.5);
uniform float refraction = 0.03;

varying vec2 surface_pos;

void vertex() {
	surface_pos = VERTEX.xz;
	VERTEX.y += wave(VERTEX.xz, TIME) * wave_height;
}

void fragment() {
	vec3 n = wave_normal(surface_pos, TIME);
	vec3 view_n = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec2 offset = view_n.xz * refraction;
	vec3 behind = textureLod(screen, SCREEN_UV + offset, 0.0).rgb;
	float facing = abs(dot(NORMAL, VIEW));
	if (FRONT_FACING) {
		// From above: mostly clear, a Fresnel sheen at grazing angles.
		float fresnel = pow(1.0 - facing, 3.0);
		ALBEDO = mix(behind * shallow, vec3(0.85, 0.95, 1.0), fresnel * 0.6);
		ALPHA = 0.35 + fresnel * 0.5;
	} else {
		// From below: Snell's window straight up, a teal mirror elsewhere.
		float window = smoothstep(0.55, 0.8, facing);
		ALBEDO = mix(underside, behind * 1.25 + vec3(0.05, 0.08, 0.08), window);
		ALPHA = mix(0.85, 0.6, window);
	}
	NORMAL = FRONT_FACING ? view_n : -view_n;
	ROUGHNESS = 0.05;
	SPECULAR = 0.7;
}
