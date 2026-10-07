shader_type spatial;
// The bedroom (art/models/room): lit by a lightmap baked in Blender, one per
// mood. The bake holds the light arriving at each surface; the colour comes
// from the material, so base × lightmap is the baked look. It's emitted rather
// than lit so live lights (the monitor's glow) can still add on top, and
// ambient light is off because the bake already has the room's bounce. Both
// sides are drawn: curtains, leaves, the hoodie and lettering are thin sheets.
render_mode ambient_light_disabled, cull_disabled;

#include "res://shaders/room.gdshaderinc"

void fragment() {
	vec3 base = room_base(COLOR, UV);
	ALBEDO = base;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	EMISSION = room_light(base, UV2);
}
