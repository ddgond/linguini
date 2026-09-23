Linguini: a Moonlight client where you are the fish.

Run:    ./Linguini.x86_64

Requirements
  - x86_64 Linux with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36
    and later)
  - Vulkan or OpenGL 3.3 graphics drivers
  - libva (VA-API), installed on nearly every desktop distribution
    (Debian/Ubuntu: libva2 libva-drm2, Fedora: libva, Arch: libva).
    Hardware video decoding also needs your GPU's VA-API driver; without
    one, Linguini decodes in software.
  - A host PC running Sunshine or GeForce Experience with GameStream

Keep liblinguini.linux.template_release.x86_64.so next to the executable.

Pairing and settings are stored in ~/.local/share/godot/app_userdata/Linguini/.

Licences for Linguini's third-party components are in licenses/.
