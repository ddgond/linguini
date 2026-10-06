// The stream, full screen, for direct input mode: decoded game video (Y +
// interleaved UV planes from MoonlightClient), letterboxed to the window.
// The same conversion as the monitor's screen (monitor_screen.gdshader), but
// straight to the 2D canvas, which works in sRGB.
shader_type canvas_item;

uniform sampler2D y_tex : filter_linear, repeat_disable;
uniform sampler2D uv_tex : filter_linear, repeat_disable;
uniform bool has_video = false;
uniform bool bt709 = true;
uniform bool full_range = false;
uniform vec2 video_size = vec2(1280.0, 720.0);
uniform vec2 view_size = vec2(1280.0, 720.0);

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

void fragment() {
	vec3 color = vec3(0.0);
	if (has_video) {
		float view_aspect = view_size.x / view_size.y;
		float video_aspect = video_size.x / video_size.y;
		vec2 scale = video_aspect > view_aspect ? vec2(1.0, view_aspect / video_aspect) : vec2(video_aspect / view_aspect, 1.0);
		vec2 uv = (UV - 0.5) / scale + 0.5;
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			color = yuv_to_rgb(texture(y_tex, uv).r, texture(uv_tex, uv).rg);
		}
	}
	COLOR = vec4(color, 1.0);
}
