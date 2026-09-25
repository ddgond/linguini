// The fantail's swimming, shared by its body and fin shaders.
//
// UV2.x is how far along the body a vertex is (0 at the nose, 1 at the tail
// tip). UV2.y is 1 - v, v being how far out along a fin (0 at its root, 1 at
// its edge; 0 on the body; 2 on the lower lip): art/models/fish.py paints v
// and the glTF export flips it. The model faces -Z, so the tail is toward +Z
// and "sideways" is X.
//
// The body swims by bending its spine: a wave that grows toward the tail and
// travels back along it, a little recoil at the head, and a curve into turns.
// Each cross-section turns with the spine instead of just sliding sideways,
// so the body keeps its shape rather than shearing and bulging.

uniform float tail_phase = 0.0;  // Fish.tail_phase: advances with each tail beat
uniform float fin_phase = 0.0;   // Fish.fin_phase: pectoral fin sculling
uniform float effort = 0.0;      // Fish.effort, 0..1
uniform float turn = 0.0;        // yaw rate, rad/s: the body curves into a turn
uniform float screen_fade = 0.0; // Fish.screen_fade: 1 while it's in front of the monitor being watched

const float BODY_LENGTH = 0.104; // nose to tail tip, metres

// The spine's sideways offset at body position b.
float spine(float b) {
	float amplitude = 0.0035 + 0.0105 * effort;
	// The travelling wave: the head barely moves, the tail swings most.
	float x = amplitude * b * b * sin(tail_phase - b * 3.2);
	// Recoil: the head swings a touch the other way.
	x -= amplitude * 0.18 * (1.0 - b) * (1.0 - b) * sin(tail_phase - 0.3);
	// Turning: behind the head the body curves away from the turn.
	float bb = max(b - 0.2, 0.0);
	x += clamp(turn, -4.0, 4.0) * 0.0045 * bb * bb;
	return x;
}

void swim_vertex(inout vec3 vertex, inout vec3 normal, vec2 weights) {
	float b = weights.x;
	float v = 1.0 - weights.y;
	bool lower_lip = v > 1.5;
	float f = lower_lip ? 0.0 : v;

	// The mouth: now and then the lower lip drops and closes again, a
	// goldfish's gulp.
	if (lower_lip) {
		float gulp = pow(max(0.0, sin(TIME * 2.6)), 6.0) * 0.45 + effort * 0.1;
		vec2 hinge = vec2(-0.0045, -0.025);  // (y, z): behind the lips, the jaw
		vec2 p = vertex.yz - hinge;
		float c = cos(gulp);
		float s = sin(gulp);
		vertex.yz = hinge + vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
	}

	// Fins trail the body a little, like cloth.
	float lag = (spine(b + 0.12) - spine(b)) * f * 1.2;
	float x0 = spine(b) + lag;
	float slope = (spine(b + 0.01) - spine(b - 0.01)) / (0.02 * BODY_LENGTH);
	float a = atan(slope);
	float c = cos(a);
	float s = sin(a);
	vertex = vec3(x0 + vertex.x * c, vertex.y, vertex.z - vertex.x * s);
	normal = vec3(normal.x * c + normal.z * s, normal.y, -normal.x * s + normal.z * c);

	// Fins ripple along their normals, more at the edge, calmer when working.
	float ripple = sin(fin_phase * 1.3 + b * 9.0 + f * 5.0) * (0.0006 + 0.0012 * (1.0 - effort));
	vertex += normal * ripple * f * f;
}

// Up close the fish fades, so a camera squeezed in near it (against the
// gravel or the water surface) sees past it: by how close the camera is to
// the fish's middle and to this very pixel (the long tail can reach the lens
// while the body is further off). The room camera and the tank cam, further
// away, never see it fade.
float fish_fade(vec3 camera, vec3 fish, vec3 here) {
	float body = smoothstep(0.04, 0.1, distance(camera, fish));
	float part = smoothstep(0.025, 0.07, distance(camera, here));
	float fade = mix(0.1, 1.0, min(body, part));
	// In front of the monitor while the player is looking at it: faded to a
	// ghost, for the follow camera only (the room camera and tank cam are
	// much further off).
	if (distance(camera, fish) < 0.8) {
		fade = min(fade, 1.0 - 0.82 * screen_fade);
	}
	return fade;
}

// An ordered dither, so the opaque body can fade without sorting against
// the water and glass: a pixel is dropped when the fade falls below its
// threshold.
bool fish_dither_out(vec2 frag, float fade) {
	const float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	ivec2 p = ivec2(frag) % 4;
	return fade < 1.0 && (bayer[p.y * 4 + p.x] + 0.5) / 16.0 > fade;
}
