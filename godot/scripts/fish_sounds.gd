class_name FishSounds
extends Node
## The fish's own sounds: a swish on each tail beat (louder the harder it
## swims), a whoosh when it darts, and a soft knock when it bumps the glass or
## something solid. Add as a child of the fish; it plays at the fish's side.

const MIN_EFFORT := 0.18
const BUMP_SPEED := 0.06 ## m/s into a surface before it knocks
const BUMP_COOLDOWN := 0.35

var fish: Fish
var _last_beat := 0
var _prev_velocity := Vector3.ZERO
var _bump_timer := 0.0


func _ready() -> void:
	fish = get_parent() as Fish
	fish.darted.connect(func() -> void: _play("dart", -4.0, 0.08))


func _physics_process(delta: float) -> void:
	if fish == null or not fish.is_inside_tree():
		return
	# A beat each half turn of the tail (sin² peaks twice per cycle).
	var beat := int(fish.tail_phase / PI)
	if beat != _last_beat:
		_last_beat = beat
		if fish.effort > MIN_EFFORT:
			_play("swish_%d" % randi_range(1, 3), lerpf(-24.0, -10.0, clampf(fish.effort, 0.0, 1.0)), 0.1)
	_bump_timer = maxf(_bump_timer - delta, 0.0)
	for i in fish.get_slide_collision_count():
		var hit := fish.get_slide_collision(i)
		var into := -_prev_velocity.dot(hit.get_normal())
		if into > BUMP_SPEED and _bump_timer <= 0.0:
			_bump_timer = BUMP_COOLDOWN
			_play("bump", lerpf(-16.0, -4.0, clampf(into / 0.5, 0.0, 1.0)), 0.1)
			break
	_prev_velocity = fish.velocity


func _play(sound_name: String, volume_db: float, jitter: float) -> void:
	Sound.play_at(sound_name, fish.global_position, volume_db, jitter, 0.5)
