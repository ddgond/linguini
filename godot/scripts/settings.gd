extends Node
## Persistent settings: saved hosts, stream options and the card layout in use
## (user://settings.cfg).

const PATH := "user://settings.cfg"

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const FRAME_RATES := [30, 60, 120]
const BITRATES_KBPS := [5000, 10000, 20000, 40000, 80000]
const CODECS := ["auto", "h264", "hevc", "av1"]

var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(PATH)


func hosts() -> PackedStringArray:
	return _cfg.get_value("hosts", "addresses", PackedStringArray())


func add_host(address: String) -> void:
	var list := hosts()
	if address not in list:
		list.append(address)
		_cfg.set_value("hosts", "addresses", list)
		save()


func remove_host(address: String) -> void:
	var list := hosts()
	var i := list.find(address)
	if i >= 0:
		list.remove_at(i)
		_cfg.set_value("hosts", "addresses", list)
		save()


func get_value(section: String, key: String, default: Variant) -> Variant:
	return _cfg.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	save()


func get_stream(key: String, default: Variant) -> Variant:
	return _cfg.get_value("stream", key, default)


func set_stream(key: String, value: Variant) -> void:
	_cfg.set_value("stream", key, value)
	save()


## Options in the shape MoonlightClient.start_stream() expects.
func stream_options() -> Dictionary:
	var res: Vector2i = get_stream("resolution", RESOLUTIONS[0])
	return {
		"width": res.x,
		"height": res.y,
		"fps": get_stream("fps", 60),
		"bitrate_kbps": get_stream("bitrate_kbps", 10000),
		"codec": get_stream("codec", "auto"),
		"hardware_decode": get_stream("hardware_decode", true),
	}


func layout_preset() -> String:
	return _cfg.get_value("tank", "layout", LayoutPresets.DEFAULT)


func set_layout_preset(preset_name: String) -> void:
	_cfg.set_value("tank", "layout", preset_name)
	save()


func tracking_enabled() -> bool:
	return _cfg.get_value("tracking", "enabled", false)


func tracking_style() -> int:
	return _cfg.get_value("tracking", "style", 1) # TrackingCam.Style.EARNEST


func set_tracking(enabled: bool, style: int) -> void:
	_cfg.set_value("tracking", "enabled", enabled)
	_cfg.set_value("tracking", "style", style)
	save()


func save() -> void:
	_cfg.save(PATH)
