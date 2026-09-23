shader_type spatial;
// The bedroom (art/models/room): lit by a lightmap baked in Blender, one per
// mood. The bake holds the light arriving at each surface; the colour comes
// from the material, so base × lightmap is the baked look. It's emitted rather
// than lit so live lights (the monitor's glow) can still add on top, and
// ambient light is off because the bake already has the room's bounce.
render_mode ambient_light_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
uniform sampler2D lightmap : hint_default_white, filter_linear;
uniform float exposure = 1.0;
uniform float roughness = 0.8;
// Glow* materials (lamp shades, LED strips, screens) also give off light.
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform bool emission_from_texture = false;

void fragment() {
	vec3 base = albedo.rgb * COLOR.rgb;
	if (use_texture) {
		base *= texture(albedo_texture, UV).rgb;
	}
	vec3 baked = texture(lightmap, UV2).rgb * exposure;
	ALBEDO = base;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	EMISSION = base * baked + (emission_from_texture ? base : emission_color) * emission_energy;
}
