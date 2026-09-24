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
	// Gratings (horizontal) get a crossed grid.
	vec3 n = normalize(world_normal);
	bool grating = abs(n.y) > 0.7;
	float fw = fwidth(m.x / spacing);
	float x = abs(fract(m.x / spacing) - 0.5) * 2.0;
	float width = bar / spacing;
	// Keep at least ~a pixel of bar, and fade the whole panel as bars merge.
	float w = max(width, fw * 0.9);
	float cover = 1.0 - smoothstep(1.0 - w - fw, 1.0 - w + fw, 1.0 - x);
	cover = max(cover, 1.0 - smoothstep(1.0 - w - fw, 1.0 - w + fw, x));
	if (grating) {
		float fz = fwidth(m.y / spacing);
		float y = abs(fract(m.y / spacing) - 0.5) * 2.0;
		cover = max(cover, 1.0 - smoothstep(1.0 - w - fz, 1.0 - w + fz, 1.0 - y));
	}
	// A rail along the bottom.
	ALPHA = clamp(cover, 0.0, 1.0);
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
