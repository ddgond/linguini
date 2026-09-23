shader_type spatial;
// What's outside the window: a painted backdrop per mood, lit by nothing.
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D view : source_color, filter_linear_mipmap;
uniform float energy = 1.0;

void fragment() {
	ALBEDO = texture(view, UV).rgb * energy;
}
