// The fantail's fins: thin, translucent and glowing when lit from behind.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

#include "res://shaders/fish_swim.gdshaderinc"
#include "res://shaders/fish_variety.gdshaderinc"

uniform float roughness : hint_range(0.0, 1.0) = 0.45;

varying vec3 model_pos;
varying float fin_amount;

void vertex() {
	// Where on the fish, before it swims (for its colouring's patches), and
	// how far out along a fin (UV2.y is 1 - v; v is 2 on the lower lip).
	model_pos = VERTEX;
	float v = 1.0 - UV2.y;
	fin_amount = v < 1.5 ? clamp(v, 0.0, 1.0) : 0.0;
	swim_vertex(VERTEX, NORMAL, UV2);
}

void fragment() {
	vec3 paint = variety_colour(COLOR.rgb, model_pos, fin_amount);
	ALBEDO = paint;
	// Faded up close by the same dither as the body: plain alpha isn't enough,
	// as the fins overlap many layers deep when seen edge-on.
	if (fish_dither_out(FRAGCOORD.xy, fish_fade(CAMERA_POSITION_WORLD, NODE_POSITION_WORLD, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz))) {
		discard;
	}
	ALPHA = COLOR.a;
	ROUGHNESS = roughness;
	// Light through the membrane.
	BACKLIGHT = paint * 0.7;
	// Both faces are drawn: light the back face as if it faced the camera.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
