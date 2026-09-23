shader_type spatial;
// The bedroom window. Clear glass with a faint sheen; in the rainy mood, drops
// cling to it and run down, bending the view behind them.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float rain = 0.0;
uniform vec3 tint : source_color = vec3(0.85, 0.92, 1.0);
// Glass size in metres, so drops stay round.
uniform vec2 size = vec2(1.9, 1.3);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A layer of drops on a grid: returns the drop's slope (xy) and coverage (z).
vec3 drops(vec2 p, float cell, float t, float speed) {
	vec2 g = p / cell;
	float column = floor(g.x);
	// Running drops slide down their column at their own pace.
	g.y += t * speed * (0.6 + hash(vec2(column, 3.1)));
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float present = step(0.55, hash(id));
	vec2 offset = (vec2(hash(id + 1.7), hash(id + 5.3)) - 0.5) * 0.5;
	vec2 d = f - offset;
	d.y *= 1.0 + speed * 1.5;  // stretched while running
	float r = 0.18 + 0.12 * hash(id + 9.1);
	float cover = smoothstep(r, r * 0.6, length(d)) * present;
	return vec3(-d / r * cover, cover);
}

void fragment() {
	vec2 p = UV * size;
	vec3 still = drops(p, 0.035, TIME, 0.0);
	vec3 small = drops(p + 0.37, 0.018, TIME, 0.0);
	vec3 running = drops(p, 0.06, TIME, 1.4);
	// Streaks left behind the running drops.
	float trail = smoothstep(0.09, 0.0, abs(fract(p.x / 0.06) - 0.5)) * step(0.7, hash(vec2(floor(p.x / 0.06), 7.0))) * 0.25;
	// Fade drops out where they'd be smaller than a pixel (they'd sparkle).
	float fade = smoothstep(0.012, 0.004, fwidth(p.x));
	vec3 all = (still + small * 0.8 * fade + running) * rain * mix(0.35, 1.0, fade);
	vec2 slope = all.xy;
	float cover = clamp(all.z + trail * rain, 0.0, 1.0);

	vec2 uv = SCREEN_UV + slope * 0.02;
	vec3 behind = textureLod(screen, uv, cover * 1.5).rgb;
	float sheen = 0.03 + 0.05 * pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	// Drops dim what's behind a little and catch a highlight along one edge.
	float glint = clamp(slope.y, 0.0, 1.0) * cover * 0.12 * fade;
	ALBEDO = mix(tint * sheen, behind * 0.88 + vec3(glint), cover);
	ALPHA = max(sheen, cover);
}
