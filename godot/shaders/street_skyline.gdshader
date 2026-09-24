// Distant towers: a grid of windows drawn on plain boxes (UV in metres), lit
// at night by seed, fading into the haze. UV2.x is the tower's seed and UV2.y
// its window style (flipped on export).
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/street.gdshaderinc"

global uniform float street_windows_lit;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float seed = UV2.x;
	float style = 1.0 - UV2.y;
	vec2 m = vec2(UV.x, -UV.y);
	vec2 cell = vec2(style > 0.6 ? 2.2 : 3.0, style > 0.3 ? 3.6 : 4.0);
	vec2 g = m / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float glassy = step(0.4, style) * step(style, 0.6);
	float win = step(0.18, f.x) * step(f.x, 0.82 + glassy * 0.18) * step(0.25, f.y) * step(f.y, 0.85);
	vec2 fw = fwidth(g);
	win = mix(win, 0.45, smoothstep(0.2, 0.6, max(fw.x, fw.y)));
	float roof = step(0.7, n.y);
	vec3 base = COLOR.rgb;
	// Daylight: facades lit by the sun and sky, glass a little darker and bluer.
	float sun = max(dot(n, normalize(street_sun_dir)), 0.0);
	vec3 lit_face = base * (street_ambient(n, 1.0) + street_sun_color.rgb * sun * 0.6);
	vec3 glass = mix(lit_face * 0.55, street_sky(reflect(normalize(world_pos - CAMERA_POSITION_WORLD), n)) * 0.7, 0.5);
	vec3 c = mix(lit_face, glass, win * (1.0 - roof));
	// Night: some windows glow.
	float on = step(s_hash(id + seed * 91.0), street_windows_lit * 0.9);
	vec3 warm = mix(vec3(1.0, 0.75, 0.45), vec3(0.85, 0.9, 1.0), step(0.7, s_hash(id * 1.3 + seed)));
	c += warm * on * win * (1.0 - roof) * street_night * 1.4;
	ALBEDO = c;
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y));
}
