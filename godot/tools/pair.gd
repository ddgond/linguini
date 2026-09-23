extends SceneTree
## Pairs with a host without the 3D client, for headless machines:
##   godot --headless --path godot -s res://tools/pair.gd -- HOST
## Prints a PIN to enter in the host's web UI (Sunshine: https://HOST:47990 → PIN).
## Uses the same key directory as the app, so the pairing carries over.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var host := args[0] if args.size() > 0 else "127.0.0.1"
	var client: Node = ClassDB.instantiate("MoonlightClient")
	root.add_child(client)

	client.request_failed.connect(func(request: String, message: String) -> void:
		print("FAILED (%s): %s" % [request, message])
		quit(1))
	client.host_ready.connect(func(info: Dictionary) -> void:
		print("Host %s, Sunshine/GFE %s" % [host, info.app_version])
		if info.paired:
			print("Already paired.")
			quit(0)
			return
		var pin := "%04d" % randi_range(0, 9999)
		print("\n    PIN: %s\n" % pin)
		print("Enter it in the host's web UI (Sunshine: https://%s:47990, PIN tab). Waiting…" % host)
		client.pair(pin))
	client.paired.connect(func() -> void:
		print("Paired!")
		quit(0))

	print("Connecting to %s…" % host)
	client.connect_host(host)
