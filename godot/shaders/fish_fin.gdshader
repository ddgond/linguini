// The fantail's fins: thin, translucent and glowing when lit from behind.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

#include "res://shaders/fish_swim.gdshaderinc"

uniform float roughness : hint_range(0.0, 1.0) = 0.45;

void vertex() {
	swim_vertex(VERTEX, NORMAL, UV2);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
	ROUGHNESS = roughness;
	// Light through the membrane.
	BACKLIGHT = COLOR.rgb * 0.7;
	// Both faces are drawn: light the back face as if it faced the camera.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
