// Aquarium glass (tank_glass.gdshaderinc), lit by the room's live lights.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

#include "res://shaders/tank_glass.gdshaderinc"

void fragment() {
	float fresnel = glass_fresnel(NORMAL, VIEW);
	float algae = glass_algae();
	ALBEDO = mix(tint, algae_color, algae);
	ALPHA = glass_alpha(fresnel, algae);
	ROUGHNESS = mix(0.03, 0.8, algae);
	SPECULAR = 0.6;
}
