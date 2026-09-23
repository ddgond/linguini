// Dancing light from the water surface, drawn as an extra additive pass over
// things in the tank (gravel, cards, decor). Quality adds and removes it; it's
// off on Low. The fish draws its caustics in its own shader instead, since it
// bends in its vertex shader and a separate pass wouldn't follow.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled;

#include "res://shaders/caustics.gdshaderinc"

uniform vec3 caustic_color : source_color = vec3(0.75, 0.95, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	// Sit a hair in front of the surface: an additive pass at exactly the same
	// depth fails the transparent pass's depth test.
	VERTEX += NORMAL * 0.0003;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = caustic_color * caustic_light(world_pos, world_normal, TIME, 0.12) * 0.6;
}
