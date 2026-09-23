// Caustic light from the tank's water surface, shared by the caustics pass
// and the fish's own shader.
//
// The pattern is in world XZ, so neighbouring objects line up, and is
// projected straight down: upright surfaces get only a little of it.

global uniform vec3 tank_water_min;
global uniform vec3 tank_water_max;
global uniform float caustics_strength;

vec2 caustic_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Bright lines along the edges of a Voronoi pattern whose points wander over
// time, like light focused by a rippling surface.
float caustic_layer(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = caustic_hash(cell + o);
			vec2 point = o + 0.5 + 0.4 * sin(t + TAU * h);
			float d = length(point - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return pow(clamp(1.0 - (f2 - f1) * 3.2, 0.0, 1.0), 5.0);
}

// Caustic brightness at world position `uv` (metres in XZ), 0..~1.
float caustic(vec2 uv, float t) {
	float a = caustic_layer(uv * 16.0, t * 1.1);
	float b = caustic_layer(uv * 23.0 + 7.3, t * 1.4);
	return clamp(a * 0.75 + a * b * 1.2 + b * 0.25, 0.0, 1.2);
}

// How much caustic light reaches a point at `world_pos` whose surface faces
// `world_normal`. `side` is how much reaches upright surfaces (0 to 1).
float caustic_light(vec3 world_pos, vec3 world_normal, float time, float side) {
	vec3 lo = tank_water_min;
	vec3 hi = tank_water_max;
	vec3 inside = step(lo, world_pos) * step(world_pos, hi);
	float mask = inside.x * inside.y * inside.z;
	float edge = smoothstep(0.0, 0.03, min(world_pos.x - lo.x, hi.x - world_pos.x))
		* smoothstep(0.0, 0.03, min(world_pos.z - lo.z, hi.z - world_pos.z));
	float depth = clamp((hi.y - world_pos.y) / (hi.y - lo.y), 0.0, 1.0);
	float up = side + (1.0 - side) * max(world_normal.y, 0.0);
	return caustic(world_pos.xz, time * 0.8) * mask * edge * up * mix(0.9, 0.45, depth) * caustics_strength;
}
