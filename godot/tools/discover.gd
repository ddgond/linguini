extends Node
## Lists the Sunshine and GeForce Experience hosts on the local network, as
## the monitor's host page finds them (HostDiscovery):
##   godot --headless --path godot -- --tool=discover [SECONDS]

## Positional command-line arguments, set by main.gd before the tool starts.
var args := PackedStringArray()


func _ready() -> void:
	var seconds := float(args[0]) if args.size() > 0 else 5.0
	var discovery := HostDiscovery.new()
	add_child(discovery)
	discovery.found.connect(func(host: Dictionary) -> void:
		print("%-15s  %s  (answers at %s)" % [host.address, host.name, ", ".join(host.addresses)]))
	discovery.active = true
	print("Looking for hosts for %.0f s…" % seconds)
	await get_tree().create_timer(seconds).timeout
	if discovery.hosts.is_empty():
		print("None found.")
	get_tree().quit(0 if not discovery.hosts.is_empty() else 1)
