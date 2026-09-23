# Linguini

A [Moonlight](https://moonlight-stream.org/) game-streaming client, inspired by the great deeds of the mighty Tortellini, where **you are the fish**. See [docs/core.md](docs/core.md) for the vision.

You play from inside a fish tank in a streamer's bedroom. The game stream plays on the monitor across the room. Flash cards in the tank press controller buttons on the host while the fish swims in front of them.

## Status: milestone 1 (vertical slice)

- Pair with a Sunshine or GeForce Experience host, pick an app and stream it. Video and audio go to the monitor in the room. All of this happens on the monitor itself.
- **Real Fishy Movement:** the stick or WASD sets the direction the fish wants to go and how hard to swim, not a velocity. The fish turns at a limited rate and moves in tail-beat pulses, so it swims in arcs. With no input it drifts.
- Third-person camera. Hold the gaze button to look past the fish at the monitor.
- 24 flash cards cover the whole controller.

Milestone 2 adds the card editor and presets, the fake ML tracking-camera window, and 3D speaker audio. Milestone 3 is the art pass.

## Controls

| | Keyboard / mouse | Gamepad |
|---|---|---|
| Swim | WASD | Left stick |
| Rise / sink | Space / C | RB / LB |
| Dart | Shift | A |
| Look around | Mouse | Right stick |
| Watch the monitor | Hold right mouse (or Tab) | Hold LT |
| Menu | Esc | Start |
| Show card trigger zones | F3 | |

Your own keyboard and gamepad never reach the host. Only the cards do.

## Flash cards

The default layout is in `godot/data/layouts/default.json`. Every card faces the front glass, where the room camera is. A card's trigger zone is its footprint, enlarged by 10%, extruded forward to the glass. From the room camera's point of view, the fish covering a card presses it.

- **Pressing:** a card presses as soon as the fish's body touches its zone. It stays held while the fish stays there.
- **Releasing:** a card releases once the fish has been out of the zone for 150 ms. The zone also has a 1.5 cm margin while held, so a fish drifting along an edge doesn't make the button flicker.
- **Stick diagonals:** stick directions are arranged as a cross with an empty centre. Swim into the corner between two arms to get a diagonal.

## Building

The extension is C++ on top of [godot-cpp](https://github.com/godotengine/godot-cpp). It builds these into one library:
- [moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c), for the streaming session.
- `libgamestream` from [moonlight-embedded](https://github.com/moonlight-stream/moonlight-embedded), for pairing, the app list and launching.

It needs Godot 4.5+ and SCons. It also needs these libraries: FFmpeg (libavcodec, libavutil), Opus, OpenSSL, libcurl, expat and (on Linux) libuuid.

```sh
git submodule update --init --recursive
scons                          # builds godot/bin/liblinguini.*
godot --path godot             # run it (or open godot/ in the editor)
```

On Nix, `nix develop` provides everything, Godot included. On Linux and macOS, the libraries are found with `pkg-config`. On Windows, set `LINGUINI_DEPS_PREFIX` to a prefix with `include/` and `lib/`, such as a vcpkg `installed/x64-windows` tree.

### Tests

```sh
godot --headless --path godot -s res://tests/run_tests.gd
LINGUINI_TEST_HOST=192.168.1.20 godot --headless --path godot -s res://tests/run_tests.gd   # also query a real host
```

The tests cover:
- Fish behaviour: drift, cruise pulses, arcs, dart, backing up, rising.
- Card timing and geometry, and the controller state sent to the host.
- The decode path, from an H.264 test stream to the Y/UV planes.
- Host requests.
- The fish staying inside the tank under physics.

Two headless tools help on machines without a display:

```sh
godot --headless --path godot -s res://tools/pair.gd -- HOST                    # prints a PIN, waits for it to be entered
godot --headless --path godot -s res://tools/stream_check.gd -- HOST Desktop 15 frame.png
```

`pair.gd` pairs with a host. `stream_check.gd` launches an app on a paired host and streams for the given number of seconds. It then reports decoded video, audio received and input, saves the last frame's luma plane, and quits the app.

`main.tscn` also accepts `-- --swim --test-video=PATH --gaze --zones --room-camera --screenshot=PATH` for manual checks without a host. The full list is in `godot/scripts/main.gd`.

## Landing page

`site/build.py` builds a static landing page with download links into `dist/site/`. It uses only the Python standard library.

```sh
python3 site/build.py                                    # dist/builds/* -> dist/site/
python3 site/build.py --builds DIR --out DIR --repo-url https://…
python3 site/build.py --base-url https://…/releases/v0.1.0/   # link to hosted files instead of copying
```

Put the packaged builds in `dist/builds/`. Each file is matched to a platform by its name:
- `linux`
- `win`, `windows` or `win64`
- `mac`, `macos`, `osx` or `darwin`

For example: `linguini-linux-x86_64.zip`, `linguini-windows-x86_64.zip`, `linguini-macos.zip`.

The script copies the builds into the site and writes `SHA256SUMS`. The page lists each file's size and SHA-256. On the visitor's own platform, the hero button becomes "Download for …". A platform without a build shows "Not built yet". The output is plain HTML and CSS with a small script, so any static host works.

## Layout

```
native/src/            GDExtension: MoonlightClient node, FFmpeg video decoder, Opus audio
native/compat/         shims that let libgamestream build unmodified off Linux
godot/scripts/         fish, camera, cards, monitor + menu, room builder (greybox)
godot/shaders/         monitor screen (YUV -> RGB, letterboxing, menu overlay)
godot/data/layouts/    card layouts
godot/tests/           headless tests
third_party/           submodules
```

## Known limitations

- Only the Linux build has been built and tested. The macOS and Windows paths in `SConstruct`, the shims, and the CI jobs are written but haven't been run.
- Hosts are added by IP or hostname. There's no mDNS discovery yet.
- Frames are decoded on the GPU where possible and copied back to system memory for upload. Zero-copy rendering is future work.
- The extension links system libraries dynamically. Packaging them for export isn't set up yet.
- libgamestream requests can't be cancelled. "Back" during pairing stops waiting, but the host keeps the PIN prompt open until it's entered or times out.
- libgamestream names the client "roth" on the host's paired-devices list.
