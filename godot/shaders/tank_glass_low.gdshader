// Aquarium glass on the Low preset (tank_glass.gdshaderinc): unshaded, so a
// pane that fills the screen doesn't add up every live light in reach. The
// mood sets `light`, roughly what the lit glass would catch, and the sheen at
// grazing angles takes its colour.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

#include "res://shaders/tank_glass.gdshaderinc"

uniform vec3 light : source_color = vec3(0.3);

void fragment() {
	float fresnel = glass_fresnel(NORMAL, VIEW);
	float algae = glass_algae();
	ALBEDO = mix(tint, algae_color, algae) * light + light * fresnel * 0.6 * (1.0 - algae);
	ALPHA = glass_alpha(fresnel, algae);
}
