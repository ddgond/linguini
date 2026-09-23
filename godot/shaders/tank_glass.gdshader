// Aquarium glass: a faint green-blue tint that thickens at grazing angles (you
// look through more glass), a Fresnel sheen, and a little algae along the
// bottom and up the corners. Coordinates are the tank's own (origin at the
// inside bottom, interior 1.2 x 0.6 x 0.5 m).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.78, 0.93, 0.92);
uniform vec3 algae_color : source_color = vec3(0.32, 0.45, 0.18);
uniform float algae_amount : hint_range(0.0, 1.0) = 0.55;
uniform vec3 half_extent = vec3(0.6, 0.3, 0.25);

varying vec3 local_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - facing, 4.0);

	// Algae: a band along the bottom and streaks up the corners, broken up by noise.
	vec2 along = vec2(local_pos.x + local_pos.z, local_pos.y);
	float n = noise(along * 38.0) * 0.6 + noise(along * 110.0) * 0.4;
	float bottom = smoothstep(0.07, 0.0, local_pos.y);
	float corner_x = smoothstep(0.035, 0.0, half_extent.x - abs(local_pos.x));
	float corner_z = smoothstep(0.035, 0.0, half_extent.z - abs(local_pos.z));
	// A vertical corner is near both the x and z edges. (Every point of the
	// front pane is near the z edge, so either alone would cover it.)
	float corner = min(corner_x, corner_z) * smoothstep(0.45, 0.05, local_pos.y);
	float algae = clamp(max(bottom, corner) * (n * 1.4 - 0.35), 0.0, 1.0) * algae_amount;

	ALBEDO = mix(tint, algae_color, algae);
	ALPHA = clamp(0.05 + fresnel * 0.5 + algae * 0.7, 0.0, 0.9);
	ROUGHNESS = mix(0.03, 0.8, algae);
	SPECULAR = 0.6;
}
