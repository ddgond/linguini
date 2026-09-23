// The fantail's swimming, shared by its body and fin shaders.
//
// UV2.x is how far along the body a vertex is (0 at the nose, 1 at the tail
// tip), UV2.y how far out along a fin (0 at its root, 1 at its edge). Both are
// painted by art/models/fish.py. The model faces -Z, so the tail is toward +Z
// and "sideways" is X.

uniform float tail_phase = 0.0;  // Fish.tail_phase: advances with each tail beat
uniform float fin_phase = 0.0;   // Fish.fin_phase: pectoral fin sculling
uniform float effort = 0.0;      // Fish.effort, 0..1
uniform float turn = 0.0;        // yaw rate, rad/s: the tail trails out of turns

// Sideways displacement of the travelling wave at body position `b`.
float swim_wave(float b) {
	float amplitude = 0.004 + 0.011 * effort;
	// The head barely moves; the wave grows toward the tail and lags behind.
	return amplitude * b * b * sin(tail_phase - b * 3.2);
}

void swim_vertex(inout vec3 vertex, vec3 normal, vec2 weights) {
	float b = weights.x;
	float f = weights.y;
	vertex.x += swim_wave(b);
	// The tail trails away from the direction of a turn.
	vertex.x += turn * 0.004 * b * b * b;
	// Fins ripple along their normal, more at the edge. Tail lobes also lag
	// the body wave a little, like cloth.
	float ripple = sin(fin_phase * 1.3 + b * 9.0 + f * 5.0) * (0.0006 + 0.0012 * (1.0 - effort));
	vertex += normal * ripple * f * f;
	vertex.x += (swim_wave(b + 0.12) - swim_wave(b)) * f * 1.5;
}
