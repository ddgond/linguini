// Things on the street that give off light: lamp glass, neon, headlights and
// tail lights, a taxi's roof sign, and the traffic signals. Colour is Col
// times `tint`; how bright is `energy` (set by the mood, and per car).
//
// Signals: Col.r is the lens (0 red, 0.5 amber, 1 green) and Col.g the road
// it serves (0 the main street, 1 the cross street); street_signal_main and
// street_signal_cross say which lens is lit (0 red, 1 amber, 2 green).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/street.gdshaderinc"

global uniform float street_signal_main;
global uniform float street_signal_cross;

uniform vec3 tint : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform float daylight_albedo = 0.8;
uniform bool signal = false;
// Neon flickers now and then.
uniform float flicker = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = COLOR.rgb * tint;
	float e = energy;
	if (signal) {
		vec3 lens = COLOR.r < 0.25 ? vec3(1.0, 0.08, 0.05) : (COLOR.r < 0.75 ? vec3(1.0, 0.55, 0.05) : vec3(0.1, 1.0, 0.45));
		float state = COLOR.g < 0.5 ? street_signal_main : street_signal_cross;
		float lens_id = COLOR.r < 0.25 ? 0.0 : (COLOR.r < 0.75 ? 1.0 : 2.0);
		bool on = abs(lens_id - state) < 0.5;
		c = lens;
		e = on ? energy : 0.0;
		ALBEDO = lens * (on ? 0.4 : 0.08);
	} else {
		ALBEDO = c * daylight_albedo;
	}
	if (flicker > 0.0) {
		float n = s_noise(vec2(street_time * 9.0, world_pos.x * 3.0));
		e *= 1.0 - flicker * step(0.93, n) * 0.8;
	}
	ROUGHNESS = 0.2;
	EMISSION = c * e;
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	// Lights cut through haze better than surfaces do.
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y) * 0.6);
}
