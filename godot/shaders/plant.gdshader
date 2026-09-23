// Swaying plants: a slow current moves them, and they lean away when the fish
// brushes past. UV2.x (painted by art/lib/decor.py) is how free a vertex is to
// move: 0 at the roots, 1 at the tips. Colour is the painted gradient times the
// variant's tint.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/caustics.gdshaderinc"

global uniform vec3 fish_position;

uniform vec3 tint : source_color = vec3(0.37, 0.68, 0.3);
uniform float sway = 0.012;
uniform float push = 0.03;
uniform float push_radius = 0.07;
uniform float caustics = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	float w = UV2.x;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The current: a slow two-frequency wave, offset per plant.
	float phase = dot(root.xz, vec2(7.3, 5.1));
	vec3 current = vec3(sin(TIME * 0.9 + phase) + 0.35 * sin(TIME * 2.3 + phase * 1.7), 0.0,
			0.6 * cos(TIME * 0.7 + phase * 1.3));
	vec3 offset = current * sway * w;
	// Lean away from the fish when it's close.
	vec3 away = world_pos - fish_position;
	float d = length(away);
	offset += normalize(away + vec3(0.0001)) * push * w * smoothstep(push_radius, 0.0, d);
	offset.y = 0.0;
	world_pos += offset;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.55;
	BACKLIGHT = ALBEDO * 0.4;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	EMISSION = vec3(0.75, 0.95, 1.0) * caustic_light(world_pos, world_normal, TIME, 0.1) * 0.3 * caustics;
}
