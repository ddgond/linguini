// People walking the sidewalks (art/models/street/people.py). Col.r says
// which part a vertex is (skin, top, bottom, shoes, hair) and each person
// brings their own colours; UV2 says which limb swings and about what height.
shader_type spatial;
render_mode ambient_light_disabled, cull_back;

#include "res://shaders/street.gdshaderinc"

instance uniform vec3 skin : source_color = vec3(0.8, 0.6, 0.45);
instance uniform vec3 top : source_color = vec3(0.2, 0.25, 0.4);
instance uniform vec3 bottom : source_color = vec3(0.15, 0.2, 0.3);
instance uniform vec3 shoes : source_color = vec3(0.08);
instance uniform vec3 hair : source_color = vec3(0.1, 0.07, 0.05);
instance uniform float step_rate = 5.0;   // radians of the stride cycle per second
instance uniform float phase = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	float limb = UV2.x;
	float pivot = 1.0 - UV2.y;  // flipped on export
	float t = TIME * step_rate + phase;
	float swing = 0.0;
	if (limb > 0.1 && limb < 0.3) {
		swing = sin(t) * 0.42;          // left leg
	} else if (limb > 0.3 && limb < 0.5) {
		swing = -sin(t) * 0.42;         // right leg
	} else if (limb > 0.5 && limb < 0.7) {
		swing = -sin(t) * 0.32;         // left arm, with the right leg
	} else if (limb > 0.7) {
		swing = sin(t) * 0.32;
	}
	if (swing != 0.0) {
		vec2 p = VERTEX.xy - vec2(0.0, pivot);
		float c = cos(swing);
		float s = sin(swing);
		VERTEX.xy = vec2(p.x * c - p.y * s, p.x * s + p.y * c) + vec2(0.0, pivot);
		NORMAL.xy = vec2(NORMAL.x * c - NORMAL.y * s, NORMAL.x * s + NORMAL.y * c);
	}
	// A little bob, twice a stride.
	VERTEX.y += abs(sin(t)) * 0.025;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float part = COLOR.r;
	vec3 c = part < 0.2 ? skin : (part < 0.5 ? top : (part < 0.7 ? bottom : (part < 0.9 ? shoes : hair)));
	c *= mix(1.0, 0.6, street_wet * step(0.2, part) * step(part, 0.7));
	ALBEDO = c;
	ROUGHNESS = part < 0.2 ? 0.6 : 0.85;
	EMISSION = c * street_ambient(normalize(world_normal), 1.0);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y));
}
