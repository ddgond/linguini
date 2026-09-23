class_name CardBinding
extends RefCounted
## What a flash card sends to the host.
##
## HOLD: a set of inputs held together for as long as the fish stays in front
## of the card: one button, a diagonal (L_UP + L_RIGHT), a chord (RB + A).
##
## SEQUENCE: a timed macro that plays once each time the fish arrives. Each
## step holds one input from `at` for `hold` milliseconds; steps may overlap
## to press several inputs together.
##
## Layout files store bindings as:
##   {"inputs": ["L_UP", "L_RIGHT"]}                                 hold
##   {"input": "A"}                                                  hold (older layouts)
##   {"label": "Roll", "sequence": [{"input": "B", "at": 0, "hold": 80}, ...]}

enum Kind { HOLD, SEQUENCE }

const MIN_HOLD_MS := 16
const MAX_SEQUENCE_MS := 10000

var kind := Kind.HOLD
var inputs := PackedStringArray()
## [{input: String, at: int ms, hold: int ms}], sorted by `at`.
var steps: Array[Dictionary] = []
## Optional name shown on the card; empty uses an automatic one.
var label := ""


static func hold(p_inputs: Array) -> CardBinding:
	var b := CardBinding.new()
	b.inputs = PackedStringArray(p_inputs)
	return b


static func sequence(p_steps: Array, p_label := "") -> CardBinding:
	var b := CardBinding.new()
	b.kind = Kind.SEQUENCE
	b.label = p_label
	for s: Dictionary in p_steps:
		b.steps.append({"input": String(s.input), "at": int(s.at), "hold": int(s.hold)})
	b.sort_steps()
	return b


## Parses a card entry from a layout file. Returns null (and warns) if it's invalid.
static func from_dict(d: Dictionary) -> CardBinding:
	var b: CardBinding
	if d.has("sequence"):
		b = sequence(d.sequence, String(d.get("label", "")))
	elif d.has("inputs"):
		b = hold(d.inputs)
		b.label = String(d.get("label", ""))
	elif d.has("input"):
		b = hold([d.input])
	else:
		push_warning("CardBinding: card has no inputs: %s" % d)
		return null
	var problem := b.validate()
	if problem != "":
		push_warning("CardBinding: %s in %s" % [problem, d])
		return null
	return b


func to_dict() -> Dictionary:
	var d := {}
	if kind == Kind.SEQUENCE:
		d.sequence = steps.duplicate(true)
	else:
		d.inputs = Array(inputs)
	if label != "":
		d.label = label
	return d


func duplicate_binding() -> CardBinding:
	var b := CardBinding.new()
	b.kind = kind
	b.inputs = inputs.duplicate()
	b.steps = steps.duplicate(true)
	b.label = label
	return b


## "" if the binding can be used, otherwise what's wrong with it.
func validate() -> String:
	if kind == Kind.HOLD:
		if inputs.is_empty():
			return "no inputs"
		for id in inputs:
			if not CardSystem.INPUTS.has(id):
				return "unknown input '%s'" % id
		return ""
	if steps.is_empty():
		return "empty sequence"
	for s in steps:
		if not CardSystem.INPUTS.has(s.input):
			return "unknown input '%s'" % s.input
		if s.at < 0 or s.hold < MIN_HOLD_MS:
			return "step times out of range"
	if duration_ms() > MAX_SEQUENCE_MS:
		return "sequence longer than %d ms" % MAX_SEQUENCE_MS
	return ""


func sort_steps() -> void:
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)


func duration_ms() -> int:
	var end := 0
	for s in steps:
		end = maxi(end, s.at + s.hold)
	return end


## Inputs a sequence presses `t_ms` after it started.
func inputs_at(t_ms: float) -> PackedStringArray:
	var out := PackedStringArray()
	for s in steps:
		if t_ms >= s.at and t_ms < s.at + s.hold and s.input not in out:
			out.append(s.input)
	return out


## Every input the card can press, in first-use order.
func all_inputs() -> PackedStringArray:
	if kind == Kind.HOLD:
		return inputs
	var out := PackedStringArray()
	for s in steps:
		if s.input not in out:
			out.append(s.input)
	return out


func display_name() -> String:
	if label != "":
		return label
	var names := PackedStringArray()
	for id in all_inputs():
		names.append(CardSystem.short_name(id))
	return (" › " if kind == Kind.SEQUENCE else " + ").join(names)
