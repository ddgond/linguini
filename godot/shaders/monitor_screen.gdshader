// The room monitor's screen: decoded game video (Y + interleaved UV planes from
// MoonlightClient), letterboxed to the panel, with the monitor's menu UI
// composited on top.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D y_tex : filter_linear, repeat_disable;
uniform sampler2D uv_tex : filter_linear, repeat_disable;
uniform sampler2D menu_tex : source_color, filter_linear, repeat_disable;

uniform bool has_video = false;
uniform bool bt709 = true;
uniform bool full_range = false;
uniform vec2 video_size = vec2(1280.0, 720.0);
uniform vec2 panel_size = vec2(16.0, 9.0);
uniform float menu_opacity = 1.0;
uniform float brightness = 1.4;

vec3 yuv_to_rgb(float y, vec2 c) {
	if (full_range) {
		c -= 0.5;
	} else {
		y = (y - 16.0 / 255.0) * (255.0 / 219.0);
		c = (c - 128.0 / 255.0) * (255.0 / 224.0);
	}
	vec3 rgb;
	if (bt709) {
		rgb = vec3(y + 1.5748 * c.y, y - 0.1873 * c.x - 0.4681 * c.y, y + 1.8556 * c.x);
	} else {
		rgb = vec3(y + 1.402 * c.y, y - 0.344136 * c.x - 0.714136 * c.y, y + 1.772 * c.x);
	}
	return clamp(rgb, 0.0, 1.0);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 color = vec3(0.004, 0.006, 0.012);

	if (has_video) {
		// Letterbox / pillarbox the stream inside the panel.
		float panel_aspect = panel_size.x / panel_size.y;
		float video_aspect = video_size.x / video_size.y;
		vec2 scale = video_aspect > panel_aspect ? vec2(1.0, panel_aspect / video_aspect) : vec2(video_aspect / panel_aspect, 1.0);
		vec2 uv = (UV - 0.5) / scale + 0.5;
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			color = srgb_to_linear(yuv_to_rgb(texture(y_tex, uv).r, texture(uv_tex, uv).rg));
		}
	}

	vec4 menu = texture(menu_tex, UV);
	color = mix(color, menu.rgb, menu.a * menu_opacity);
	ALBEDO = color * brightness;
}
