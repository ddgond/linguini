extends Node
## Linguini's sound (autoload "Sound"): the mixer buses, their volumes, and
## playing the sounds in res://audio/ (built by audio/build.py).
##
## Buses:
##   Game   the stream from the host   ─┐
##   Room   room tone, tank, fish, cards ├─> Water ─> Master
##                                       ┘
##   UI     the monitor's clicks ────────────────────> Master
##
## Water muffles lightly (a low-pass and a little reverb) while the listener
## is underwater: always while piloting the fish, whose ears are the
## listener, and whenever the camera is in the tank. The Stream settings'
## Stereo audio sends Game straight to Master, clean.

const BUSES := ["Water", "Game", "Room", "UI"]
## Volume sliders on the monitor, by settings key.
const VOLUMES := {"master": "Master", "game": "Game", "room": "Room", "ui": "UI"}
const CLEAR_HZ := 20000.0
const UNDERWATER_HZ := 3500.0

var underwater := false
## Room-audio "Stereo" mode: the stream skips the water.
var game_direct := false:
	set = set_game_direct

var _lowpass: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _streams := {}


func _ready() -> void:
	_make_buses()
	for key: String in VOLUMES:
		_apply_volume(key, volume(key))


func _make_buses() -> void:
	for bus_name: String in BUSES:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	var water := AudioServer.get_bus_index("Water")
	AudioServer.set_bus_send(water, "Master")
	AudioServer.set_bus_send(AudioServer.get_bus_index("Game"), "Water")
	AudioServer.set_bus_send(AudioServer.get_bus_index("Room"), "Water")
	AudioServer.set_bus_send(AudioServer.get_bus_index("UI"), "Master")
	if AudioServer.get_bus_effect_count(water) == 0:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = CLEAR_HZ
		_lowpass.resonance = 0.5
		AudioServer.add_bus_effect(water, _lowpass, 0)
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.35
		_reverb.damping = 0.7
		_reverb.wet = 0.0
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(water, _reverb, 1)
	else:
		_lowpass = AudioServer.get_bus_effect(water, 0)
		_reverb = AudioServer.get_bus_effect(water, 1)
	AudioServer.set_bus_effect_enabled(water, 0, false)
	AudioServer.set_bus_effect_enabled(water, 1, false)


func _process(delta: float) -> void:
	var target := UNDERWATER_HZ if underwater else CLEAR_HZ
	# Glide in log space so diving and surfacing both sound smooth.
	var k := 1.0 - exp(-6.0 * delta)
	_lowpass.cutoff_hz = exp(lerpf(log(_lowpass.cutoff_hz), log(target), k))
	_reverb.wet = lerpf(_reverb.wet, 0.14 if underwater else 0.0, k)
	var water := AudioServer.get_bus_index("Water")
	AudioServer.set_bus_effect_enabled(water, 0, _lowpass.cutoff_hz < CLEAR_HZ * 0.95)
	AudioServer.set_bus_effect_enabled(water, 1, _reverb.wet > 0.005)


## How far the water bus is muffling right now (its low-pass cutoff).
func muffle_hz() -> float:
	return _lowpass.cutoff_hz


func set_game_direct(value: bool) -> void:
	game_direct = value
	AudioServer.set_bus_send(AudioServer.get_bus_index("Game"), "Master" if value else "Water")


# --- volumes -------------------------------------------------------------------

## A volume slider's value, 0..1 (linear, as heard).
func volume(key: String) -> float:
	return float(Settings.get_value("audio", "volume_" + key, 1.0 if key != "ui" else 0.8))


func set_volume(key: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	Settings.set_value("audio", "volume_" + key, value)
	_apply_volume(key, value)


func _apply_volume(key: String, value: float) -> void:
	var bus := AudioServer.get_bus_index(VOLUMES[key])
	AudioServer.set_bus_volume_db(bus, linear_to_db(value) if value > 0.001 else -80.0)
	AudioServer.set_bus_mute(bus, value <= 0.001)


# --- playing sounds -------------------------------------------------------------

## A sound from res://audio/, cached. Loops loop.
func stream(sound_name: String, loop := false) -> AudioStream:
	var key := sound_name + ("#loop" if loop else "")
	if not _streams.has(key):
		var s: AudioStream = load("res://audio/%s.ogg" % sound_name)
		if loop and s is AudioStreamOggVorbis:
			s = s.duplicate()
			(s as AudioStreamOggVorbis).loop = true
		_streams[key] = s
	return _streams[key]


## Plays a one-shot at a point in the world (Room bus). `pitch_jitter` varies
## the pitch a little so repeats don't sound mechanical.
func play_at(sound_name: String, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.06, unit_size := 1.5) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound_name)
	p.bus = "Room"
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.attenuation_filter_cutoff_hz = CLEAR_HZ  # the Water bus does the muffling
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


## A looping sound attached to `parent` (it moves and goes away with it).
func loop_on(parent: Node3D, sound_name: String, volume_db := 0.0, unit_size := 1.5) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Loop_" + sound_name
	p.stream = stream(sound_name, true)
	p.bus = "Room"
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.attenuation_filter_cutoff_hz = CLEAR_HZ
	p.autoplay = true
	parent.add_child(p)
	return p


func play_ui(sound_name := "ui_click", volume_db := -6.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound_name)
	p.bus = "UI"
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.97, 1.03)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
