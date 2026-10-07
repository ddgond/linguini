shader_type spatial;
// The bedroom window. Clear glass with a faint sheen; in the rainy mood, rain
// on the outside of it:
//  - beads that sit on the glass, each a tiny lens showing the street behind
//    it upside down and shrunken, with a dark rim and a glint; they come and
//    go as new ones land
//  - drops that run down, stalling and lurching, wandering a little, wiping
//    the beads in their way and leaving a wet trail of tiny beads that dries
//  - a fine mist over the glass that softens the view
// Sizes are real (millimetres); drops smaller than a pixel fade out rather
// than sparkle.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

#include "res://shaders/window_glass.gdshaderinc"

void fragment() {
	vec2 q = vec2(UV.x * size.x, (1.0 - UV.y) * size.y);  // metres, y up (UV.y runs down the pane)
	float mpp = max(length(dFdx(q)), length(dFdy(q)));      // metres per pixel
	float wet;
	vec4 hit = rain_hit(q, mpp, TIME, wet);

	// What's behind the glass. A drop is a lens: it shows a shrunken,
	// upside-down view of the scene around it.
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float r_px = hit.w / mpp;
	vec2 lens = vec2(-hit.x, hit.y) * r_px * 3.0 * px;  // flipped both ways (screen y runs down)
	float mist = rain * 0.35;
	vec3 clear_view = textureLod(screen, SCREEN_UV, mist * 1.2).rgb;
	vec3 through_drop = textureLod(screen, SCREEN_UV + lens, 0.8).rgb;
	vec3 film = textureLod(screen, SCREEN_UV + vec2(0.003, 0.0), 1.2).rgb * 1.06;
	// A drop's rim bends light away (dark), and it catches a glint up top.
	float k = length(hit.xy);
	float rim = smoothstep(0.55, 0.95, k);
	vec3 drop = through_drop * mix(0.95, 0.35, rim);
	float glint = (1.0 - smoothstep(0.0, 0.28, length(hit.xy - vec2(-0.32, 0.42)))) * 0.55;
	drop += vec3(glint);

	float sheen = 0.03 + 0.05 * pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	vec3 base = mix(clear_view, clear_view * 0.92 + vec3(0.02, 0.025, 0.03), mist);
	vec3 col = mix(base, film * 0.9, wet * 0.6);
	col = mix(col, drop, hit.z);
	if (rain > 0.0) {
		ALBEDO = col + tint * sheen * 0.5;
		ALPHA = 1.0;
	} else {
		ALBEDO = tint * sheen;
		ALPHA = sheen;
	}
}
