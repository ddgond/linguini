Linguini: a Moonlight client where you are the fish.

Run:    Linguini.exe

Requirements
  - 64-bit Windows 10 or 11
  - Vulkan or Direct3D 12 graphics drivers
  - A host PC running Sunshine or GeForce Experience with GameStream

Keep liblinguini.windows.template_release.x86_64.dll next to Linguini.exe.

Windows may show a SmartScreen warning the first time, because Linguini isn't
code-signed. Choose "More info", then "Run anyway". When Windows Firewall asks,
allow Linguini on private networks; that's how it reaches your host.

Linguini.console.exe is the same program with a console window, for the
headless tools, e.g.:  Linguini.console.exe --headless -- --tool=pair HOST

Pairing and settings are stored in %APPDATA%\Godot\app_userdata\Linguini\.

Linguini is free software under the GNU General Public License v3
(LICENSE.txt). Licences for its third-party components are in licenses/.
