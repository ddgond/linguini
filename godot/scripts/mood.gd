extends Node
## The room's mood (autoload "Mood"): which baked lighting and accent lights
## the bedroom uses, and how the street outside looks. Picked on the monitor, remembered in settings.

signal changed(mood: String)

const NAMES := ["night", "rainy", "golden"]
const LABELS := ["Night gamer den", "Rainy evening", "Golden hour"]

var current := "night"


func _ready() -> void:
	var saved: String = Settings.get_value("room", "mood", "night")
	current = saved if saved in NAMES else "night"


func set_mood(value: String, remember := true) -> void:
	if value == current or value not in NAMES:
		return
	current = value
	if remember:
		Settings.set_value("room", "mood", value)
	changed.emit(value)
