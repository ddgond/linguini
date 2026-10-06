// The fish's colouring: the model is painted as Tortellini (variety 0);
// other varieties repaint it here from that, by what each painted colour is
// (orange body, red cap, silvery belly, pale fin edges) and where on the fish
// it is, so several local players' fish can be told apart.
//   0 Tortellini   as painted
//   1 Fusilli      calico: pale blue-white, with orange patches and black specks
//   2 Gnocchi      white all over but for the red cap
//   3 Ravioli      orange, with black patches and black-edged fins

uniform int variety = 0;

float v_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float v_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(v_hash(i), v_hash(i + vec3(1, 0, 0)), f.x), mix(v_hash(i + vec3(0, 1, 0)), v_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(v_hash(i + vec3(0, 0, 1)), v_hash(i + vec3(1, 0, 1)), f.x), mix(v_hash(i + vec3(0, 1, 1)), v_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// `c` the painted (linear) colour, `p` the point on the model (before it
// swims), `fin` 0 on the body to 1 at a fin's edge.
vec3 variety_colour(vec3 c, vec3 p, float fin) {
	if (variety == 0) {
		return c;
	}
	// What the paint was: silvery-white, or the red cap (low green).
	float white = smoothstep(0.25, 0.6, c.b / max(c.r, 0.001));
	float cap = smoothstep(0.12, 0.05, c.g) * (1.0 - white) * (1.0 - fin);
	float shade = max(max(c.r, c.g), c.b);  // keep the painted light and dark
	vec3 q = p * 70.0;
	float patch_a = smoothstep(0.52, 0.6, v_noise(q * 0.8 + 3.0));
	float patch_b = smoothstep(0.6, 0.66, v_noise(q * 1.7 + 11.0));
	if (variety == 1) {
		vec3 base = vec3(0.62, 0.68, 0.78);
		vec3 col = mix(base, vec3(1.0, 0.3, 0.03), patch_a * 0.9);
		col = mix(col, vec3(0.01, 0.01, 0.015), patch_b);
		return col * mix(0.85, 1.0, shade);
	}
	if (variety == 2) {
		vec3 white_col = vec3(0.86, 0.84, 0.8) * mix(0.9, 1.0, shade);
		return mix(white_col, vec3(0.9, 0.04, 0.01), cap);
	}
	// 3: black and orange.
	vec3 orange = vec3(1.0, 0.26, 0.015);
	float black = max(patch_a * (1.0 - white * 0.6), smoothstep(0.5, 0.95, fin));
	return mix(orange * mix(0.75, 1.0, shade), vec3(0.012, 0.01, 0.01), black);
}
