shader_type spatial;
// The bedroom on the Low preset: just the bake (room.gdshaderinc), unshaded.
// Low has no live light for the room (the monitor's glow is off), and skipping
// the lighting saves every pixel of the room from walking the lights in reach.
render_mode unshaded, cull_disabled;

#include "res://shaders/room.gdshaderinc"

void fragment() {
	ALBEDO = room_light(room_base(COLOR, UV), UV2);
}
