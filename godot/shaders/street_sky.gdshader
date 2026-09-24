// The sky outside the window: a dome with the mood's gradient, the sun or
// moon, stars, drifting clouds and the city's glow at the horizon.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://shaders/street.gdshaderinc"

global uniform float street_clouds;       // cover, 0..1
global uniform vec4 street_cloud_color : source_color;
global uniform float street_stars;
global uniform vec3 street_moon_dir;
global uniform float street_moon;

varying vec3 dir;

void vertex() {
	dir = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 c = street_sky(d);
	// Sun disc.
	vec3 sd = normalize(street_sun_dir);
	float s = dot(d, sd);
	c += street_sun_color.rgb * (smoothstep(0.9993, 0.9997, s) * 12.0 + pow(max(s, 0.0), 300.0) * 1.5) * (1.0 - street_night);
	// Stars, twinkling, gone near the hazy horizon.
	if (street_stars > 0.0) {
		vec3 sp = d * 300.0;
		vec3 cell = floor(sp);
		float h = s_hash3(cell);
		vec3 f = fract(sp) - 0.5;
		float star = step(0.992, h) * smoothstep(0.25, 0.0, length(f));
		star *= 0.6 + 0.4 * sin(TIME * (1.0 + h * 3.0) + h * 50.0);
		c += vec3(0.9, 0.92, 1.0) * star * street_stars * smoothstep(0.05, 0.35, d.y) * 2.0;
	}
	// Moon, with a hint of its seas.
	if (street_moon > 0.0) {
		vec3 md = normalize(street_moon_dir);
		float m = dot(d, md);
		float disc = smoothstep(0.99955, 0.9997, m);
		vec3 side = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec2 q = vec2(dot(d - md, side), dot(d - md, cross(side, md))) * 60.0;
		float seas = 0.8 + 0.2 * s_noise(q * 1.7 + 3.0);
		c += vec3(1.0, 0.97, 0.9) * disc * 3.0 * seas * street_moon;
		c += vec3(0.6, 0.65, 0.8) * pow(max(m, 0.0), 800.0) * 0.6 * street_moon;
	}
	// Clouds: a thin layer seen in perspective, drifting.
	if (street_clouds > 0.0 && d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * 1.4 + vec2(TIME * 0.006, TIME * 0.002);
		float cl = s_fbm(uv * 1.3) * 0.65 + s_fbm(uv * 4.1) * 0.35;
		float cover = smoothstep(1.0 - street_clouds, 1.15 - street_clouds * 0.6, cl);
		// Lit from the sun's side.
		float toward = pow(max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sd.x, 0.0, sd.z))), 0.0), 2.0);
		vec3 cc = street_cloud_color.rgb * (0.8 + 0.4 * s_fbm(uv * 3.0)) + street_sun_color.rgb * toward * 0.25 * (1.0 - street_night);
		c = mix(c, cc, cover * smoothstep(0.0, 0.15, d.y));
	}
	ALBEDO = c;
}
