// The fantail's body and eyes: painted colour times a subtle scale pattern,
// glossy like wet skin.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/fish_swim.gdshaderinc"
#include "res://shaders/caustics.gdshaderinc"

uniform sampler2D scales : source_color, filter_linear_mipmap, repeat_enable;
uniform float scale_strength = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float clearcoat : hint_range(0.0, 1.0) = 0.4;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	swim_vertex(VERTEX, NORMAL, UV2);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float s = mix(1.0, texture(scales, UV).r, scale_strength);
	ALBEDO = COLOR.rgb * s;
	ROUGHNESS = roughness;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = 0.2;
	EMISSION = vec3(0.75, 0.95, 1.0) * caustic_light(world_pos, world_normal, TIME, 0.0) * 0.35;
}
