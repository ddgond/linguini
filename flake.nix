{
  description = "Linguini - a Moonlight client where you are the fish";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forAll (pkgs: {
        # Blender for regenerating the models in art/ (art/build.sh). Kept out
        # of the default shell because it's large and only needed for art.
        art = pkgs.mkShell {
          packages = with pkgs; [ blender python3 ];
        };
        default = pkgs.mkShell {
          packages = with pkgs; [
            godot_4
            scons
            pkg-config
            python3
            ffmpeg.dev
            openssl.dev
            curl.dev
            expat.dev
            libopus.dev
            # Tests: fixture generation, headless screenshots
            ffmpeg
            xvfb-run
            mesa
          ];
        };
      });
    };
}
