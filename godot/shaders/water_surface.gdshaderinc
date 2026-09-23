// The water surface's gentle waves, shared by the full and Low shaders.
uniform float wave_height = 0.0015;

float wave(vec2 p, float t) {
	return sin(p.x * 23.0 + t * 1.3) * 0.5 + sin(p.y * 31.0 - t * 1.1) * 0.3 + sin((p.x + p.y) * 17.0 + t * 0.7) * 0.4;
}

vec3 wave_normal(vec2 p, float t) {
	float e = 0.004;
	float h = wave(p, t);
	float hx = wave(p + vec2(e, 0.0), t);
	float hz = wave(p + vec2(0.0, e), t);
	return normalize(vec3((h - hx) * wave_height / e, 1.0, (h - hz) * wave_height / e));
}
