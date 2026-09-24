// Leaf cards on the street trees: an alpha-cut atlas of leaf sprays, tinted
// per card, swaying in the breeze (UV2.x: how far up the tree, UV2.y: a
// phase), lit through from behind.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;

#include "res://shaders/street.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float wind = 1.0;

varying vec3 world_pos;
varying float weight;

void vertex() {
	weight = UV2.x;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float phase = UV2.y * 6.2832;
	float w = weight * weight * wind;
	vec3 sway = vec3(sin(t * 0.9 + wp.x * 0.3) * 0.12 + sin(t * 2.1 + phase) * 0.04,
			sin(t * 2.7 + phase) * 0.025,
			cos(t * 0.7 + wp.z * 0.3) * 0.08 + cos(t * 2.9 + phase) * 0.03) * w;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(sway, 0.0)).xyz;
	world_pos = wp + sway;
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 albedo = tex.rgb * COLOR.rgb * 1.15;
	// Inner leaves sit in the crown's shade.
	float shade = mix(0.55, 1.0, smoothstep(0.3, 0.9, weight));
	albedo *= mix(1.0, 0.7, street_wet);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.7, 0.35, street_wet);
	BACKLIGHT = albedo * 0.6;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		n = -n;
	}
	EMISSION = albedo * street_ambient(vec3(0.0, 0.6, 0.0) + n * 0.4, shade);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y));
}
