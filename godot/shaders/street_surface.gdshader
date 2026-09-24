// Most of the street: brick, stucco, stone and painted trim, asphalt and
// paving, roofs, metal, bark, awnings, cars. `kind` picks the surface; colour
// is Col times `tint`; UV is in metres (u along the surface, -v up), so
// patterns line up across faces. Lit by the street's own lights; ambient,
// sky reflections, wetness and haze come from street.gdshaderinc. Its own haze
// replaces the environment's fog (which is the tank's water, for underwater).
shader_type spatial;
render_mode ambient_light_disabled, cull_back;

#include "res://shaders/street.gdshaderinc"

const int PLAIN = 0;
const int BRICK = 1;
const int ASPHALT = 2;
const int PAVING = 3;
const int ROOF = 4;
const int METAL = 5;
const int BARK = 6;
const int AWNING = 7;
const int CAR_PAINT = 8;
const int CAR_GLASS = 9;
const int STUCCO = 10;
const int STONE = 11;
const int WOOD = 12;
const int SIDING = 13;
const int GHOST = 14;

uniform int kind = 0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float gloss = 0.0;        // extra sky reflection (car paint, glass)
uniform bool two_sided = false;   // thin sheets: awnings
// A moving car's paint (the templates are white).
instance uniform vec3 paint : source_color = vec3(1.0);

varying vec3 world_pos;
varying vec3 world_normal;
// Street coordinates (the street's node is placed, its meshes aren't), for
// patterns that follow the road: see art/models/street/street_layout.py.
varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Fades a pattern to its average where it's finer than a pixel or two.
float detail_fade(float scale_px) {
	return 1.0 - smoothstep(0.35, 1.0, scale_px);
}

vec3 brick(vec2 m, vec3 base, out float mortar_ao) {
	const vec2 size = vec2(0.2032, 0.0762);
	vec2 g = m / size;
	float row = floor(g.y);
	g.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(g);
	vec2 f = fract(g);
	vec2 mortar = vec2(0.01) / size;
	vec2 fw = fwidth(g);
	vec2 edge = smoothstep(mortar - fw, mortar + fw, f);
	float in_brick = edge.x * edge.y;
	float h = s_hash(id + vec2(row * 3.1, 7.7));
	vec3 b = base * (0.78 + 0.38 * h);
	b *= mix(vec3(1.0), vec3(1.08, 0.95, 0.9), s_hash(id * 1.7));
	// Soot and sun fading, at the scale of the wall.
	b *= 0.85 + 0.3 * s_fbm(m * 0.35);
	vec3 mortar_col = vec3(0.55, 0.53, 0.5) * (0.7 + 0.3 * s_fbm(m * 2.0));
	float fade = detail_fade(max(fw.x, fw.y));
	vec3 fine = mix(mortar_col, b, in_brick);
	vec3 avg = mix(mortar_col, base * (0.85 + 0.3 * s_fbm(m * 0.35)), 0.82);
	mortar_ao = mix(1.0, mix(0.8, 1.0, in_brick), fade);
	return mix(avg, fine, fade);
}

void fragment() {
	vec3 n = normalize(world_normal);
	if (two_sided && !FRONT_FACING) {
		n = -n;
		NORMAL = -NORMAL;
	}
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec2 m = vec2(UV.x, -UV.y);
	vec3 base = COLOR.rgb * tint;
	vec3 albedo = base;
	float rough = roughness;
	float metal = metallic;
	float ao = 1.0;
	float spec = 0.5;
	float gloss_amt = gloss;
	// How much standing water a surface holds: flat and facing up.
	float flatness = smoothstep(0.75, 0.95, n.y);
	float wet = street_wet;

	if (kind == BRICK) {
		albedo = brick(m, base, ao);
	} else if (kind == STUCCO) {
		albedo = base * (0.9 + 0.18 * s_fbm(m * 1.3)) * (0.92 + 0.08 * s_noise(m * 18.0));
	} else if (kind == STONE) {
		albedo = base * (0.88 + 0.2 * s_fbm(m * 3.0));
	} else if (kind == SIDING) {
		// Lap siding: boards 18 cm high, each shadowed along its lower edge.
		float board = m.y / 0.18;
		float f = fract(board);
		float fw = fwidth(board);
		float lip = mix(smoothstep(0.0, 0.12 + fw, f), 0.85, detail_fade(fw * 2.0) < 0.5 ? 1.0 : 0.0);
		albedo = base * (0.9 + 0.1 * s_hash(vec2(floor(board), floor(m.x / 3.7)))) * mix(0.72, 1.0, lip);
		albedo *= 0.92 + 0.1 * s_fbm(m * 0.8);
	} else if (kind == GHOST) {
		// Paint worn off an old brick wall: patchy, and faded toward the brick.
		float wear = s_fbm(m * 3.0) * 0.7 + s_noise(m * 22.0) * 0.3;
		if (wear < 0.42) {
			discard;
		}
		albedo = base * (0.8 + 0.25 * s_fbm(m * 1.5));
	} else if (kind == WOOD) {
		albedo = base * (0.9 + 0.12 * s_noise(vec2(m.x * 3.0, m.y * 40.0)));
	} else if (kind == ASPHALT) {
		float patches = s_fbm(local_pos.xz * 0.18);
		float grain = mix(0.5, s_noise(local_pos.xz * 40.0), detail_fade(fwidth(local_pos.x) * 40.0));
		albedo = base * (0.75 + 0.35 * patches) * (0.9 + 0.2 * grain);
		// Tar-sealed cracks.
		float crack = abs(s_fbm(local_pos.xz * 0.6) - 0.5);
		albedo *= mix(0.78, 1.0, smoothstep(0.0, 0.012 + fwidth(local_pos.x) * 0.5, crack));
		// Darker where tyres run, lighter where they don't.
		float lane = fract((local_pos.z + 16.6) / 3.2);
		albedo *= 0.95 + 0.08 * smoothstep(0.2, 0.5, abs(lane - 0.5));
		rough = 0.92;
	} else if (kind == PAVING) {
		vec2 slab = local_pos.xz / 1.5;
		vec2 f = fract(slab);
		vec2 fw = fwidth(slab);
		float joint = smoothstep(0.0, 0.012 + fw.x, f.x) * smoothstep(0.0, 0.012 + fw.x, 1.0 - f.x)
				* smoothstep(0.0, 0.012 + fw.y, f.y) * smoothstep(0.0, 0.012 + fw.y, 1.0 - f.y);
		float t = s_hash(floor(slab));
		albedo = base * (0.86 + 0.18 * t) * (0.88 + 0.2 * s_fbm(local_pos.xz * 0.9));
		albedo *= mix(0.72, 1.0, joint);
		// Gum and stains.
		float spot = step(0.985, s_hash(floor(local_pos.xz * 6.0)));
		albedo *= 1.0 - spot * 0.35 * detail_fade(fwidth(local_pos.x) * 6.0);
	} else if (kind == ROOF) {
		albedo = base * (0.8 + 0.3 * s_fbm(m * 0.8));
	} else if (kind == BARK) {
		albedo = base * (0.75 + 0.35 * s_noise(vec2(UV.x * 8.0, UV.y * 1.5)));
	} else if (kind == AWNING) {
		bool stripes = UV2.y < 0.5; // flipped on export: 1 means stripes
		if (stripes) {
			float s = step(0.5, fract(UV2.x / 0.5));
			albedo = mix(base, vec3(0.9, 0.87, 0.8), s);
		}
		albedo *= 0.92 + 0.08 * s_noise(m * 6.0);
		BACKLIGHT = albedo * 0.35;
		wet = 0.0;
	} else if (kind == CAR_PAINT) {
		albedo = base * paint;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.1;
		gloss_amt = 0.6;
	} else if (kind == CAR_GLASS) {
		albedo = vec3(0.02, 0.025, 0.03);
		rough = 0.05;
		spec = 1.0;
		gloss_amt = 1.0;
	}

	// Grime near the ground on walls.
	if (abs(n.y) < 0.5 && kind != CAR_PAINT && kind != CAR_GLASS) {
		float up = local_pos.y + 6.25;
		albedo *= mix(0.72, 1.0, smoothstep(0.0, 1.6, up));
	}

	// Rain: everything darkens a little; flat ground pools into glossy puddles.
	if (wet > 0.0) {
		float puddle = 0.0;
		if (kind == ASPHALT || kind == PAVING) {
			puddle = smoothstep(0.52, 0.62, s_fbm(local_pos.xz * 0.23 + 3.1)) * flatness;
		}
		float soak = wet * mix(0.35, 1.0, flatness);
		albedo *= mix(1.0, 0.55, soak);
		rough = mix(rough, 0.28, soak * flatness);
		rough = mix(rough, 0.03, puddle * wet);
		albedo *= mix(1.0, 0.6, puddle * wet);
		gloss_amt = max(gloss_amt, mix(0.3, 1.0, puddle) * wet * flatness);
		spec = mix(spec, 0.8, wet * flatness);
		// Raindrops ringing the puddles (and, fainter, all wet ground).
		if (flatness > 0.5) {
			vec2 dn = vec2(0.0);
			for (int layer = 0; layer < 2; layer++) {
				vec2 p = local_pos.xz * 1.7 + float(layer) * vec2(0.37, 0.61);
				vec2 cell = floor(p);
				vec2 c = vec2(s_hash(cell + 1.3), s_hash(cell + 7.1)) * 0.6 + 0.2;
				float period = 0.9 + 0.8 * s_hash(cell + 4.4);
				float age = fract(TIME / period + s_hash(cell + 9.2));
				vec2 d = fract(p) - c;
				float r = length(d) / 1.7;
				float front = age * 0.18;
				float ring = cos((r - front) * 110.0) * smoothstep(0.03, 0.0, abs(r - front)) * (1.0 - age);
				dn += normalize(d + 1e-4) * ring;
			}
			float amount = mix(0.15, 1.0, puddle) * wet * flatness * detail_fade(fwidth(local_pos.x) * 30.0);
			n = normalize(n + vec3(dn.x, 0.0, dn.y) * 0.25 * amount);
			NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	vec3 amb = albedo * street_ambient(n, ao) * (1.0 - metal * 0.7);
	vec3 refl = street_reflection(n, view_dir, rough, 0.04) * gloss_amt;
	EMISSION = amb + refl;
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	FOG = vec4(street_haze.rgb, street_haze_amount(dist, world_pos.y));
}
