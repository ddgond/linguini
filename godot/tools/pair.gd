extends Node
## Pairs with a host without the 3D client, for headless machines:
##   godot --headless --path godot -- --tool=pair HOST
## Prints a PIN to enter in the host's web UI (Sunshine: https://HOST:47990 → PIN).
## Uses the same key directory as the app, so the pairing carries over.

## Positional command-line arguments, set by main.gd before the tool starts.
var args := PackedStringArray()


func _ready() -> void:
	var host := args[0] if args.size() > 0 else "127.0.0.1"
	var client: Node = ClassDB.instantiate("MoonlightClient")
	add_child(client)

	client.request_failed.connect(func(request: String, message: String) -> void:
		print("FAILED (%s): %s" % [request, message])
		get_tree().quit(1))
	client.host_ready.connect(func(info: Dictionary) -> void:
		print("Host %s, Sunshine/GFE %s" % [host, info.app_version])
		if info.paired:
			print("Already paired.")
			get_tree().quit(0)
			return
		var pin := "%04d" % randi_range(0, 9999)
		print("\n    PIN: %s\n" % pin)
		print("Enter it in the host's web UI (Sunshine: https://%s:47990, PIN tab). Waiting…" % host)
		client.pair(pin))
	client.paired.connect(func() -> void:
		print("Paired!")
		get_tree().quit(0))

	print("Connecting to %s…" % host)
	client.connect_host(host)
