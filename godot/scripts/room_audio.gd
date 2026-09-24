class_name RoomAudio
extends Node3D
## Game audio from the host.
##
## ROOM: plays from the two speakers by the monitor, positioned in 3D, with the
## left channel on the left speaker and the right on the right, through the
## Game bus, which the Sound autoload muffles lightly while the listener is
## underwater.
##
## STEREO: plain stereo straight to the output, no muffling.

enum Mode { ROOM, STEREO }

const BUS := "Game"
const MIX_RATE := 48000
const BUFFER_SECONDS := 0.08
const CLEAR_HZ := 20000.0

var mode := Mode.ROOM:
	set = set_mode

var _speakers: Array[AudioStreamPlayer3D] = []
var _speaker_playbacks: Array[AudioStreamGeneratorPlayback] = []
var _stereo: AudioStreamPlayer
var _stereo_playback: AudioStreamGeneratorPlayback


## `positions` are the speakers' global positions, left first.
func setup(positions: Array) -> void:
	for p: Vector3 in positions:
		var player := AudioStreamPlayer3D.new()
		player.stream = _generator()
		player.bus = BUS
		player.unit_size = 2.0
		player.max_db = 3.0
		player.attenuation_filter_cutoff_hz = CLEAR_HZ # distance muffling is ours to do
		add_child(player)
		player.global_position = p
		_speakers.append(player)
	_stereo = AudioStreamPlayer.new()
	_stereo.stream = _generator()
	_stereo.bus = BUS
	add_child(_stereo)


func _enter_tree() -> void:
	Sound.game_direct = mode == Mode.STEREO


func _exit_tree() -> void:
	Sound.game_direct = false


func set_mode(value: Mode) -> void:
	if value == mode:
		return
	var was_playing := is_playing()
	stop()
	mode = value
	Sound.game_direct = mode == Mode.STEREO
	if was_playing:
		start()


func is_playing() -> bool:
	return _stereo.playing or (not _speakers.is_empty() and _speakers[0].playing)


func start() -> void:
	if mode == Mode.STEREO:
		_stereo.play()
		_stereo_playback = _stereo.get_stream_playback()
	else:
		_speaker_playbacks.clear()
		for s in _speakers:
			s.play()
			_speaker_playbacks.append(s.get_stream_playback())


func stop() -> void:
	_stereo.stop()
	_stereo_playback = null
	for s in _speakers:
		s.stop()
	_speaker_playbacks.clear()


## Frames the output can take right now.
func frames_available() -> int:
	if mode == Mode.STEREO:
		return _stereo_playback.get_frames_available() if _stereo_playback else 0
	var n := 1 << 30
	for p in _speaker_playbacks:
		n = mini(n, p.get_frames_available())
	return n if not _speaker_playbacks.is_empty() else 0


func push(pcm: PackedVector2Array) -> void:
	if pcm.is_empty():
		return
	if mode == Mode.STEREO:
		if _stereo_playback:
			_stereo_playback.push_buffer(pcm)
		return
	# Each speaker gets one channel, duplicated so it plays as a point source.
	for i in _speaker_playbacks.size():
		_speaker_playbacks[i].push_buffer(split_channel(pcm, i % 2))


static func split_channel(pcm: PackedVector2Array, channel: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pcm.size())
	for i in pcm.size():
		var v := pcm[i][channel]
		out[i] = Vector2(v, v)
	return out


static func _generator() -> AudioStreamGenerator:
	var g := AudioStreamGenerator.new()
	g.mix_rate = MIX_RATE
	g.buffer_length = BUFFER_SECONDS
	return g
