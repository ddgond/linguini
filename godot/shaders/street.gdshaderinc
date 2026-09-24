// Shared by the street's shaders: the mood's sky and light (global uniforms
// set by Street.apply_mood), noise, the sky's colour in a direction, ambient
// light and the haze that fades distant things into the sky.
//
// The street is lit by its own sun (or moon) and lamps on the street's render
// layer; ambient and sky reflections come from here instead of the room's
// environment, so the room keeps its own.

global uniform vec4 street_sky_zenith : source_color;
global uniform vec4 street_sky_horizon : source_color;
global uniform vec4 street_haze : source_color;
global uniform float street_haze_density;
global uniform vec4 street_ambient_sky : source_color;
global uniform vec4 street_ambient_ground : source_color;
global uniform vec3 street_sun_dir;       // toward the sun (or moon)
global uniform vec4 street_sun_color : source_color;
global uniform float street_wet;          // 0 dry .. 1 soaked
global uniform float street_night;        // 0 day .. 1 night
global uniform float street_time;         // seconds, wraps slowly (set by Street)

float s_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float s_hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float s_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(s_hash(i), s_hash(i + vec2(1.0, 0.0)), u.x),
			mix(s_hash(i + vec2(0.0, 1.0)), s_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float s_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * s_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// The sky's colour looking along world direction d (used for reflections and
// by the sky dome itself, which adds the sun, moon, stars and clouds).
vec3 street_sky(vec3 d) {
	float h = clamp(d.y, -0.2, 1.0);
	vec3 c = mix(street_sky_horizon.rgb, street_sky_zenith.rgb, pow(clamp(h, 0.0, 1.0), 0.55));
	// A wide glow toward the sun, strongest low in the sky.
	float s = max(dot(d, normalize(street_sun_dir)), 0.0);
	float low = 1.0 - clamp(d.y, 0.0, 1.0) * 0.6;
	c += street_sun_color.rgb * (pow(s, 4.0) * 0.5 + pow(s, 24.0) * 0.8) * low * (1.0 - street_night);
	// Below the horizon, the far city: the haze colour.
	c = mix(c, street_haze.rgb, smoothstep(0.02, -0.12, d.y));
	return c;
}

// Hemisphere ambient for a world-space normal, darkened by `ao`.
vec3 street_ambient(vec3 n, float ao) {
	return mix(street_ambient_ground.rgb, street_ambient_sky.rgb, n.y * 0.5 + 0.5) * ao;
}

// How much haze lies between the camera and a point `dist` metres away at
// height `y` (thicker low down).
float street_haze_amount(float dist, float y) {
	float height = exp(-max(y + 6.4, 0.0) * 0.012);
	return 1.0 - exp(-dist * street_haze_density * height);
}

// Sky reflection off a glossy surface: Schlick fresnel times the sky.
vec3 street_reflection(vec3 n, vec3 view_dir, float rough, float f0) {
	vec3 r = reflect(-view_dir, n);
	r.y = abs(r.y) * 0.9 + 0.02; // reflections from below see the sky too (puddles)
	float f = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(n, view_dir), 0.0, 1.0), 5.0);
	return street_sky(r) * f * (1.0 - rough) * (1.0 - rough);
}
