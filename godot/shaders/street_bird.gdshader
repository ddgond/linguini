// Pigeons in a flock: the wings flap (UV2.x: how far out along the wing),
// each bird at its own pace, gliding now and then.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;

#include "res://shaders/street.gdshaderinc"

instance uniform float flap_phase = 0.0;
instance uniform float flap_rate = 14.0;

varying vec3 world_pos;

void vertex() {
	float w = UV2.x;
	float t = TIME * flap_rate + flap_phase;
	// Mostly flapping, now and then a glide with the wings held up a little.
	float glide = smoothstep(0.6, 0.9, sin(TIME * 0.7 + flap_phase * 3.0));
	float a = mix(sin(t) * 0.9, 0.15, glide) * w;
	float side = sign(VERTEX.z);
	VERTEX.y += abs(VERTEX.z) * sin(a) * 1.2;
	VERTEX.z -= side * abs(VERTEX.z) * (1.0 - cos(a)) * 0.6;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = vec3(0.32, 0.33, 0.37);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	EMISSION = c * street_ambient(vec3(0.0, 1.0, 0.0), 1.0);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y));
}
