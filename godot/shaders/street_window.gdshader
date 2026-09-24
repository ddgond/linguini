// A window pane with a room behind it (interior mapping): the view ray is
// traced into a box room larger than the window, so walls, floor, ceiling and
// furniture shift with parallax as the camera moves. Rooms are lit or dark by
// mood and seed, with curtains or blinds, and the glass reflects the sky.
//
// Per pane (see art/models/street/facades.py):
//   UV     0..1 across the pane (UV.y = 0 at the top)
//   UV2    the pane's size in metres (y flipped on export: 1 - height)
//   COLOR  r: seed, g: lights-on threshold, b: kind (0 flat, 0.25 transom
//          light over a door, 0.5 shop, 0.75 laundromat)
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/street.gdshaderinc"

// Share of homes with their lights on, and how bright rooms are inside.
global uniform float street_windows_lit;
global uniform float street_interior_light;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 palette(float h, int which) {
	// Walls: soft, lived-in colours.
	if (which == 0) {
		vec3 walls[6] = vec3[](vec3(0.85, 0.8, 0.7), vec3(0.78, 0.82, 0.74), vec3(0.72, 0.78, 0.85),
				vec3(0.88, 0.75, 0.7), vec3(0.9, 0.88, 0.82), vec3(0.7, 0.62, 0.55));
		return walls[int(h * 5.99)];
	}
	// Curtains and furniture: stronger colours.
	vec3 cloth[7] = vec3[](vec3(0.75, 0.25, 0.2), vec3(0.2, 0.35, 0.55), vec3(0.85, 0.7, 0.4), vec3(0.3, 0.45, 0.3),
			vec3(0.9, 0.88, 0.8), vec3(0.45, 0.3, 0.45), vec3(0.6, 0.5, 0.4));
	return cloth[int(h * 6.99)];
}

void fragment() {
	float seed = COLOR.r;
	float kindv = COLOR.b;
	bool transom = kindv > 0.2 && kindv < 0.4;
	bool shop = kindv > 0.4 && kindv < 0.65;
	bool laundry = kindv > 0.65;

	vec3 n = normalize(world_normal);
	vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 rd_w = -view_dir;
	vec3 rd = vec3(dot(rd_w, t), dot(rd_w, up), dot(rd_w, -n));
	rd.z = max(rd.z, 0.001);

	vec2 pane = vec2(UV2.x, 1.0 - UV2.y);
	vec2 p = vec2(UV.x * pane.x, (1.0 - UV.y) * pane.y);

	// The room: a box wider and taller than the window, sill at 0.9 m.
	float h1 = fract(seed * 13.7);
	float h2 = fract(seed * 71.3);
	float h3 = fract(seed * 191.1);
	vec3 room = vec3(pane.x + 2.0 + h1 * 1.5, 2.7, 3.5 + h2 * 2.0);
	float sill = 0.9;
	if (shop || laundry) {
		room = vec3(pane.x + 1.0, 3.2, 6.0);
		sill = 0.1;
	} else if (transom) {
		room = vec3(pane.x + 1.6, 3.0, 4.0);
		sill = 2.2;
	}
	vec3 o = vec3((room.x - pane.x) * 0.5 + p.x, sill + p.y, 0.0);

	// Nearest wall along the ray.
	vec3 tb = vec3(((rd.x > 0.0 ? room.x : 0.0) - o.x) / (abs(rd.x) < 1e-4 ? 1e-4 : rd.x),
			((rd.y > 0.0 ? room.y : 0.0) - o.y) / (abs(rd.y) < 1e-4 ? 1e-4 : rd.y),
			(room.z - o.z) / rd.z);
	float tt = min(tb.x, min(tb.y, tb.z));
	vec3 hit = o + rd * tt;

	vec3 wall = palette(h3, 0);
	vec3 col;
	if (tt == tb.z) {
		// The back wall: a doorway, a picture, sometimes a shelf of books.
		col = wall * 0.95;
		float door_x = room.x * (0.15 + 0.6 * fract(seed * 33.1));
		if (abs(hit.x - door_x) < 0.45 && hit.y < 2.05) {
			col = wall * 0.45;
		}
		vec2 pic = vec2(room.x * (0.25 + 0.5 * fract(seed * 57.9)), 1.55);
		vec2 dp = abs(hit.xy - pic);
		if (dp.x < 0.35 && dp.y < 0.25) {
			col = dp.x < 0.3 && dp.y < 0.2 ? palette(fract(seed * 91.0), 1) : vec3(0.1);
		}
		if (fract(seed * 5.3) > 0.6) {
			float sx = room.x * 0.78;
			if (abs(hit.x - sx) < 0.5 && hit.y < 1.9) {
				float shelf = fract(hit.y / 0.38);
				col = shelf < 0.1 ? vec3(0.35, 0.25, 0.18) : palette(s_hash(floor(vec2(hit.x * 18.0, hit.y / 0.38))), 1) * 0.8;
			}
		}
	} else if (tt == tb.x) {
		col = wall * 0.82;
	} else if (rd.y < 0.0) {
		// Floor: boards.
		float board = floor(hit.x / 0.14);
		col = vec3(0.45, 0.3, 0.2) * (0.8 + 0.3 * s_hash(vec2(board, floor(hit.z / 1.2 + board * 0.37))));
	} else {
		col = vec3(0.92, 0.9, 0.86);
	}

	// Furniture: a sofa or bed across the room at mid depth, seen in front of the walls.
	float fz = room.z * (0.45 + 0.25 * h1);
	float ft = (fz - o.z) / rd.z;
	vec3 fh = o + rd * ft;
	float fx0 = room.x * (0.1 + 0.3 * h2);
	float fx1 = fx0 + 1.6 + h3;
	float fh_top = 0.55 + 0.35 * fract(seed * 17.0);
	if (!shop && !laundry && ft < tt && fh.y < fh_top && fh.x > fx0 && fh.x < fx1) {
		col = palette(fract(seed * 23.1), 1) * (fh.y > fh_top - 0.12 ? 0.9 : 0.7);
		tt = ft;
		hit = fh;
	}

	// Shops: shelves of goods and a counter; the laundromat: rows of washers.
	if (shop) {
		if (tt == tb.z || tt == tb.x) {
			float row = fract(hit.y / 0.45);
			if (hit.y < 2.4 && hit.y > 0.2) {
				// Shelves of goods: packets and tins with gaps, each shelf's
				// underside in shadow.
				vec2 item = vec2((hit.x + hit.z) * 6.0, hit.y / 0.45);
				float gap = step(0.82, fract(item.x)) + step(0.78, row);
				vec3 goods = palette(s_hash(floor(item)), 1) * (0.45 + 0.25 * s_hash(floor(item) + 3.0));
				col = row < 0.1 ? vec3(0.55, 0.53, 0.5) : mix(goods, vec3(0.12, 0.11, 0.1), clamp(gap, 0.0, 1.0));
			}
		} else if (rd.y < 0.0) {
			vec2 tile = floor(hit.xz / 0.4);
			col = mod(tile.x + tile.y, 2.0) < 1.0 ? vec3(0.85, 0.84, 0.8) : vec3(0.55, 0.52, 0.5);
		}
		float cz = 2.2;
		float ct = (cz - o.z) / rd.z;
		vec3 ch = o + rd * ct;
		if (ct < tt && ch.y < 1.0 && ch.x > room.x * 0.55 && ch.x < room.x * 0.95) {
			col = vec3(0.5, 0.3, 0.2);
			tt = ct;
		}
	} else if (laundry) {
		if (tt == tb.z || tt == tb.x) {
			vec2 cell = vec2((hit.x + hit.z) / 0.75, (hit.y - 0.2) / 0.8);
			vec2 f = fract(cell) - 0.5;
			if (hit.y > 0.2 && hit.y < 1.8) {
				col = length(f) < 0.28 ? (length(f) < 0.22 ? vec3(0.2, 0.3, 0.38) : vec3(0.5)) : vec3(0.93);
			}
		} else if (rd.y < 0.0) {
			vec2 tile = floor(hit.xz / 0.3);
			col = mod(tile.x + tile.y, 2.0) < 1.0 ? vec3(0.9) : vec3(0.3, 0.45, 0.55);
		}
	}

	// Light. Each home switches on below a threshold that drifts over time,
	// so now and then a window goes dark or lights up.
	float drift = 0.08 * sin(street_time * 0.02 + seed * 40.0);
	bool lit = COLOR.g + drift < street_windows_lit;
	if (shop || laundry) {
		lit = COLOR.g > 0.5;
	}
	if (transom) {
		lit = COLOR.g < street_windows_lit + 0.2;
	}
	vec3 lamp_col = mix(vec3(1.0, 0.72, 0.42), vec3(1.0, 0.85, 0.65), fract(seed * 7.7));
	if (shop) {
		lamp_col = vec3(1.0, 0.92, 0.8) * 1.2;
	} else if (laundry) {
		lamp_col = vec3(0.85, 0.95, 1.0) * 1.8;
	}
	bool tv = !shop && !laundry && fract(seed * 43.7) > 0.82;
	vec3 lamp_pos = vec3(room.x * 0.5, room.y - 0.1, room.z * 0.5);
	float d = length(hit - lamp_pos);
	vec3 light;
	if (lit) {
		light = lamp_col * (0.35 + 1.2 / (1.0 + d * d * 0.6));
		if (tv) {
			// Only the TV's flicker lights the room.
			float flick = 0.6 + 0.4 * s_noise(vec2(street_time * 3.0, seed * 100.0));
			light = vec3(0.35, 0.5, 0.9) * flick * (0.4 + 0.8 / (1.0 + d * d * 0.3));
		}
		light *= street_interior_light;
	} else {
		// Daylight or night: what spills in from outside.
		light = street_ambient_sky.rgb * 0.4 * (1.0 - hit.z / room.z * 0.6);
	}
	vec3 inside = col * light;
	// The ceiling lamp itself.
	if (lit && !tv && rd.y > 0.0 && tt == tb.y) {
		inside += lamp_col * 3.0 * smoothstep(0.35, 0.1, length(hit.xz - lamp_pos.xz)) * street_interior_light;
	}

	// Curtains or blinds just inside the glass.
	if (!shop && !laundry && !transom) {
		float style = fract(seed * 29.3);
		float ct = 0.12 / rd.z;
		vec3 c = o + rd * ct;
		vec3 cloth = palette(fract(seed * 61.1), 1);
		float wx = (c.x - (room.x - pane.x) * 0.5) / pane.x;  // 0..1 across the window
		float wy = (c.y - sill) / pane.y;
		if (style < 0.45) {
			// Two drapes, drawn back by different amounts.
			float l = 0.1 + 0.4 * fract(seed * 3.1);
			float r = 0.1 + 0.4 * fract(seed * 8.9);
			if (wx < l || wx > 1.0 - r) {
				float fold = 0.75 + 0.25 * sin(c.x * 40.0 + seed * 10.0);
				vec3 glow = lit ? light * 0.55 : light * 0.6;
				inside = cloth * fold * glow;
			}
		} else if (style < 0.75) {
			// A blind, part way down.
			float down = 0.2 + 0.7 * fract(seed * 5.9);
			if (wy > 1.0 - down) {
				float slat = fract(c.y / 0.045);
				vec3 b = vec3(0.9, 0.88, 0.82) * (slat < 0.15 ? 0.6 : 1.0);
				inside = mix(inside, b * (lit ? light * 0.7 : light), 0.85);
			}
		} else if (style < 0.9) {
			// Sheers: everything behind goes soft and pale.
			inside = mix(inside, vec3(0.9, 0.88, 0.85) * (lit ? light * 0.8 : light * 0.9), 0.6);
		}
	}

	// Now and then something on the sill, against the glass: a potted plant,
	// or a cat watching the street.
	if (!shop && !laundry && !transom) {
		float which = fract(seed * 97.3);
		if (which > 0.86) {
			float ct = 0.05 / rd.z;
			vec3 c = o + rd * ct;
			float cx = (room.x - pane.x) * 0.5 + pane.x * (0.25 + 0.5 * fract(seed * 53.7));
			vec2 q = vec2(c.x - cx, c.y - sill);
			bool hit_it = false;
			if (which > 0.955) {
				// Cat: body, head, two ears, a tail curled round.
				float dir = fract(seed * 11.0) > 0.5 ? 1.0 : -1.0;
				vec2 qb = q - vec2(0.0, 0.12);
				bool body = dot(qb / vec2(0.13, 0.12), qb / vec2(0.13, 0.12)) < 1.0;
				vec2 qh = q - vec2(0.06 * dir, 0.29);
				bool head = length(qh) < 0.075;
				vec2 qe = vec2(abs(qh.x) - 0.045, qh.y - 0.055);
				bool ears = qe.y > 0.0 && qe.y < 0.06 && abs(qe.x) < 0.028 * (1.0 - qe.y / 0.06);
				vec2 qt = q - vec2(-0.14 * dir, 0.03);
				bool tail = abs(length(qt / vec2(1.0, 0.6)) - 0.09) < 0.018 && qt.y < 0.02;
				hit_it = body || head || ears || tail;
			} else {
				// Plant: a pot and a leafy head.
				bool pot = q.y > 0.0 && q.y < 0.13 && abs(q.x) < 0.06 + q.y * 0.15;
				vec2 ql = q - vec2(0.0, 0.27);
				float ang = atan(ql.y, ql.x);
				bool leaves = length(ql) < 0.13 + 0.05 * sin(ang * 7.0 + seed * 20.0);
				hit_it = pot || leaves;
			}
			if (hit_it) {
				inside = lit ? vec3(0.015, 0.012, 0.01) : inside * 0.3;
			}
		}
	}

	// The glass: a sky reflection, stronger at a glance.
	float f = 0.04 + 0.96 * pow(1.0 - clamp(dot(n, view_dir), 0.0, 1.0), 5.0);
	vec3 r = reflect(-view_dir, n);
	vec3 sky = street_sky(r) * 0.8;
	f = max(f, 0.12);
	vec3 result = mix(inside, sky, f);
	ALBEDO = result;
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y));
}
