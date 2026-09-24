// Iron railings, fences and fire-escape gratings: one quad each, cut into
// bars here (UV in metres: bars run up v, spaced along u). Where bars get
// thinner than a pixel they thin out instead of shimmering.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;

#include "res://shaders/street.gdshaderinc"

uniform float spacing = 0.12;
uniform float bar = 0.018;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 m = vec2(UV.x, -UV.y);
	vec3 n = normalize(world_normal);
	// Gratings (horizontal) get a crossed grid; railings upright bars.
	bool grating = abs(n.y) > 0.7;
	// Distance to the nearest bar's centre, in cells (0 on a bar, 0.5 between).
	float cell = m.x / spacing;
	float fw = max(fwidth(cell), 1e-4);
	float d = abs(fract(cell + 0.5) - 0.5);
	// Half a bar wide, but never thinner than about a pixel: far away the
	// bars thicken into a see-through haze rather than breaking up.
	float half_w = max(bar / spacing * 0.5, fw * 0.6);
	float cover = 1.0 - smoothstep(half_w - fw * 0.5, half_w + fw * 0.5, d);
	if (grating) {
		float cz = m.y / spacing;
		float fz = max(fwidth(cz), 1e-4);
		float dz = abs(fract(cz + 0.5) - 0.5);
		float hz = max(bar / spacing * 0.5, fz * 0.6);
		cover = max(cover, 1.0 - smoothstep(hz - fz * 0.5, hz + fz * 0.5, dz));
	}
	ALPHA = cover;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 albedo = COLOR.rgb;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		n = -n;
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.55;
	METALLIC = 0.3;
	EMISSION = albedo * street_ambient(n, 1.0);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y));
}
