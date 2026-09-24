// Falling rain outside: a big sheet at some distance from the window, drawn
// as thin streaks falling at their own pace in columns. Several sheets at
// different depths give the rain depth as the camera moves. Added on top,
// brightest where the sky or a light is behind it.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/street.gdshaderinc"

uniform vec2 size = vec2(60.0, 20.0);  // the sheet, in metres
uniform float density = 3.0;           // columns per metre
uniform float speed = 9.0;             // metres per second
uniform float streak = 0.5;            // streak length, metres
uniform float strength = 0.25;
uniform float rain = 0.0;

varying vec3 world_pos;

float r_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 m = vec2(UV.x * size.x, UV.y * size.y);  // metres; y grows downward
	float col = floor(m.x * density);
	float fx = fract(m.x * density);
	float h1 = r_hash(col);
	float h2 = r_hash(col + 17.3);
	// Each column: a drop every so often, falling down the sheet.
	float spacing = 2.5 + 3.0 * h2;
	float y = m.y - TIME * speed * (0.85 + 0.3 * h1) + h1 * 40.0;
	float along = fract(y / spacing) * spacing;
	float line = smoothstep(streak, 0.0, along) * smoothstep(0.0, 0.05, along);
	// Thin, and a little off-centre in its column.
	float fw = fwidth(m.x * density);
	float centre = 0.2 + 0.6 * h2;
	float width = max(0.04, fw);
	float thin = 1.0 - smoothstep(width * 0.5, width * 0.5 + fw, abs(fx - centre));
	// Thin lines far away are fainter, not thicker.
	thin *= clamp(0.04 / max(fw, 0.04), 0.0, 1.0) * 0.6 + 0.4;
	float a = line * thin * strength * rain;
	// Lit by the sky and haze (lamps and neon show through the sheet anyway).
	vec3 light = street_haze.rgb * 1.6 + street_ambient_sky.rgb;
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	a *= smoothstep(0.5, 2.0, dist);  // never right in the camera's face
	// Fade at the sheet's edges.
	a *= smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x) * smoothstep(1.0, 0.9, UV.y);
	ALBEDO = light * a;
}
