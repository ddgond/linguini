shader_type spatial;
// The bedroom window on the Low preset: the same rain as window_glass.gdshader
// (window_glass.gdshaderinc), but laid over the view instead of bending it.
// Reading the screen costs a copy of the frame and its mipmaps every frame,
// rain or not, so here a drop is a dark rim with a glint and the mist is the
// street's haze.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

global uniform vec4 street_haze : source_color;

#include "res://shaders/window_glass.gdshaderinc"

void fragment() {
	vec2 q = vec2(UV.x * size.x, (1.0 - UV.y) * size.y);  // metres, y up (UV.y runs down the pane)
	float mpp = max(length(dFdx(q)), length(dFdy(q)));      // metres per pixel
	float wet;
	vec4 hit = rain_hit(q, mpp, TIME, wet);

	float sheen = 0.03 + 0.05 * pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	// Mist and wet trails: a veil of haze.
	vec3 col = street_haze.rgb;
	float a = rain * 0.05 + wet * 0.08;
	// A drop: mostly clear, darker toward its rim.
	float rim = smoothstep(0.55, 0.95, length(hit.xy));
	float drop = hit.z * mix(0.12, 0.6, rim);
	float a2 = a + drop - a * drop;
	col = mix(col, vec3(0.02, 0.025, 0.03), drop / max(a2, 1e-4));
	a = a2;
	float glint = (1.0 - smoothstep(0.0, 0.28, length(hit.xy - vec2(-0.32, 0.42)))) * 0.55 * hit.z;
	col += vec3(glint);
	a = max(a, glint);
	if (rain > 0.0) {
		ALBEDO = col + tint * sheen * 0.5;
		ALPHA = max(a, sheen);
	} else {
		ALBEDO = tint * sheen;
		ALPHA = sheen;
	}
}
