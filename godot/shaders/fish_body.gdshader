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

// Overlapping scales, row on row, drawn here rather than sampled (the
// texture's rows blurred into stripes). UV runs u round the body, v along it.
float scale_pattern(vec2 uv) {
	vec2 g = vec2(uv.x * 1.7, uv.y * 2.4);
	float row = floor(g.y);
	g.x += 0.5 * mod(row, 2.0);
	vec2 f = vec2(fract(g.x) - 0.5, fract(g.y));
	// Each scale is an arc open toward the tail, its free edge a little darker.
	float d = length(vec2(f.x, (1.0 - f.y) * 1.1));
	vec2 fw = fwidth(g);
	float edge = smoothstep(0.42 - fw.x, 0.5, d);
	float shade = 0.95 + 0.08 * (1.0 - f.y) - 0.12 * edge;
	// Finer than a couple of pixels, the pattern fades to its average.
	return mix(shade, 0.97, smoothstep(0.25, 0.6, max(fw.x, fw.y)));
}

void fragment() {
	float s = mix(1.0, scale_pattern(UV), scale_strength);
	ALBEDO = COLOR.rgb * s;
	ROUGHNESS = roughness;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = 0.2;
	EMISSION = vec3(0.75, 0.95, 1.0) * caustic_light(world_pos, world_normal, TIME, 0.0) * 0.35;
}
