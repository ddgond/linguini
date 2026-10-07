// Rain on the bedroom window, shared by the full and Low glass shaders: the
// beads, the running drops and their trails (see window_glass.gdshader).
uniform float rain = 0.0;
uniform vec3 tint : source_color = vec3(0.85, 0.92, 1.0);
// Glass size in metres, so drops stay round.
uniform vec2 size = vec2(1.9, 1.3);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// A drop's shape: returns (lens vector x, y, coverage, radius in metres).
// `d` is the offset from its centre (metres, y up); gravity makes it fuller
// below its middle.
vec4 drop_shape(vec2 d, float r) {
	d.y *= d.y > 0.0 ? 1.18 : 0.92;
	float k = length(d) / max(r, 1e-5);
	float cover = 1.0 - smoothstep(0.82, 1.0, k);
	return vec4(d / max(r, 1e-5), cover, r);
}

// Beads sitting on the glass, one per cell at most, each living its own life.
vec4 beads(vec2 q, float cell, float t, float seed) {
	vec2 g = q / cell + seed;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = hash(id + seed * 7.0);
	if (h < 0.45) {
		return vec4(0.0);
	}
	float life = fract(t / (9.0 + 14.0 * hash(id + 3.1)) + h * 5.0);
	float grow = smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.9, 1.0, life));
	float r = cell * (0.12 + 0.2 * hash(id + 5.7)) * grow;
	vec2 c = vec2(hash(id + 1.3), hash(id + 9.1)) * 0.5 + 0.25;
	return drop_shape((f - c) * cell, r);
}

// Where column `col`'s running drop is now: (x of its line, y, radius, how
// far through its run it is, 0..1); `phase` is its wiggle, so the path at
// height y is x + 0.004 sin(28 y + phase). Each column sends a drop down now
// and then: it slides at its own mean speed but stalls and lurches.
vec4 runner(float col, float t, float width, out float phase) {
	float h = hash(vec2(col, 2.7));
	float period = 7.0 + 10.0 * h;
	float cyc = floor(t / period + h);
	float age = fract(t / period + h) * period;  // seconds since it set off
	float hc = hash(vec2(col, cyc));
	float start = size.y * (0.55 + 0.45 * hash(vec2(cyc, col + 0.5)));
	float v = 0.05 + 0.08 * hc;                 // m/s, on average
	float w = 2.0 + 3.0 * hash(vec2(col, cyc + 3.0));
	float travel = v * age + (v * 0.85 / w) * sin(age * w + hc * 6.0);
	float y = start - travel;
	float x = (col + 0.5 + (hash(vec2(cyc, col)) - 0.5) * 0.4) * width;
	float r = 0.0055 + 0.0035 * hash(vec2(cyc + 1.0, col));
	phase = hc * 9.0;
	return vec4(x, y, r, age / period);
}

float path_x(vec4 rd, float phase, float y) {
	return rd.x + 0.004 * sin(y * 28.0 + phase);
}

// The drop over this point of the glass, `q` in metres (y up) with `mpp`
// metres to a pixel: (lens vector x, y, coverage, radius in metres). `wet`
// is a trail's film of water.
vec4 rain_hit(vec2 q, float mpp, float t, out float wet) {
	vec4 hit = vec4(0.0);  // lens xy, coverage, radius
	wet = 0.0;
	if (rain > 0.0) {
		// Running drops, one column every 4.5 cm; check this and the next column over.
		float width = 0.045;
		float col0 = floor(q.x / width);
		for (int k = -1; k <= 1; k++) {
			float col = col0 + float(k);
			if (hash(vec2(col, 11.0)) > 0.55) {
				continue;  // not every column has drops
			}
			float phase;
			vec4 rd = runner(col, t, width, phase);
			// The drop itself, a little drawn out behind (above) it.
			vec2 d = q - vec2(path_x(rd, phase, rd.y), rd.y);
			d.y = d.y > 0.0 ? d.y * 0.6 : d.y;
			vec4 s = drop_shape(d, rd.z);
			if (s.z > hit.z) {
				hit = s;
			}
			// Its trail above it: the path it came down, wet, beaded, drying.
			if (q.y > rd.y && q.y < rd.y + 1.2) {
				float px_line = path_x(rd, phase, q.y);
				float off = abs(q.x - px_line);
				float dry = 1.0 - smoothstep(0.0, 0.9, (q.y - rd.y) / max(0.05, 1.2 * rd.w + 0.1));
				wet = max(wet, (1.0 - smoothstep(0.002, 0.0035, off)) * dry);
				// Tiny beads left along it.
				float seg = floor(q.y / 0.011);
				if (hash(vec2(seg, col)) > 0.45) {
					vec2 bc = vec2(px_line + (hash(vec2(seg, col + 1.0)) - 0.5) * 0.003, (seg + 0.5) * 0.011);
					vec4 tb = drop_shape(q - bc, 0.0012 + 0.0012 * hash(vec2(col, seg + 2.0)));
					tb.z *= dry;
					if (tb.z > hit.z) {
						hit = tb;
					}
				}
			}
		}
		bool wiped = false;
		for (int k = -1; k <= 1; k++) {
			float col = col0 + float(k);
			if (hash(vec2(col, 11.0)) > 0.55) {
				continue;
			}
			float phase;
			vec4 rd = runner(col, t, width, phase);
			// The runner wiped the beads out of its way.
			if (q.y > rd.y && abs(q.x - path_x(rd, phase, q.y)) < rd.z * 1.6 && rd.w < 0.9) {
				wiped = true;
			}
		}
		if (!wiped) {
			vec4 b1 = beads(q, 0.02, t, 0.0);
			vec4 b2 = beads(q + 0.37, 0.011, t, 3.0);
			vec4 b3 = beads(q + 0.71, 0.006, t, 7.0);
			// Beads smaller than a pixel or two fade rather than sparkle.
			b2.z *= smoothstep(0.6, 1.8, b2.w / mpp);
			b3.z *= smoothstep(0.6, 1.8, b3.w / mpp);
			if (b1.z > hit.z) { hit = b1; }
			if (b2.z > hit.z) { hit = b2; }
			if (b3.z > hit.z) { hit = b3; }
		}
		hit.z *= smoothstep(0.4, 1.4, hit.w / mpp);
		hit.z *= rain;
		wet *= rain;
	}
	return hit;
}
