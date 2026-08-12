{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      zig-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };
        zig = pkgs.zigpkgs."0.16.0";
        zls = pkgs.zls_0_16;

        zonNixFile = ./build.zig.zon.nix;
        zigDeps = import zonNixFile {
          inherit (pkgs)
            linkFarm
            runCommand
            ;
          inherit zig;
          name = "zig-packages";
        };
        zigDepsStorePath = toString zigDeps;
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "godot-zig";
          version = "0.1.0";
          src = ./.;

          preBuild = ''
            export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
            export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-local"

            mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

            mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
            find ${zigDepsStorePath} -maxdepth 1 -type l | while read dep; do
              ln -sf "$(readlink "$dep")" "$ZIG_GLOBAL_CACHE_DIR/p/$(basename "$dep")"
            done
          '';

          nativeBuildInputs = [ zig.hook ];

          installPhase = ''
            mkdir -p $out
            cp -r zig-out/* $out/
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [
            zig
            zls
          ];
        };
      }
    );
}
