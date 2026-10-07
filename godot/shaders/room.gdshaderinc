// The bedroom's surface, shared by the lit and Low shaders: the material's
// colour times the mood's baked lightmap, plus what glows.
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

vec3 room_base(vec4 color, vec2 uv) {
	vec3 base = albedo.rgb * color.rgb;
	if (use_texture) {
		base *= texture(albedo_texture, uv).rgb;
	}
	return base;
}

// The baked light and the glow, as emission.
vec3 room_light(vec3 base, vec2 uv2) {
	vec3 baked = texture(lightmap, uv2).rgb * exposure;
	// Ease off light above white (sunlit window reveals bake several times
	// brighter than white and bloomed into a lightbox), keeping its colour.
	float lum = max(max(baked.r, baked.g), baked.b);
	if (lum > 1.0) {
		float over = lum - 1.0;
		baked *= (1.0 + over / (1.0 + over * 0.9)) / lum;
	}
	return base * baked + (emission_from_texture ? base : emission_color) * emission_energy;
}
