{
  description = "devkitPro SDKs extracted from the official Docker images";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.switch-examples = {
    url = "github:switchbrew/switch-examples";
    flake = false;
  };
  inputs.wiiu-examples = {
    url = "github:devkitPro/wiiu-examples";
    flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      switch-examples,
      wiiu-examples,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      sdks = lib.genAttrs [ "devkitarm" "devkitppc" "devkita64" ] (
        name:
        import ./nix/sdk.nix {
          inherit pkgs name;
          image = lib.importJSON ./nix/images/${name}.json;
        }
      );

      platforms = {
        gba = {
          toolchain = "devkitarm";
          portlibs = [
            "gba"
            "armv4t"
          ];
        };
        nds = {
          toolchain = "devkitarm";
          portlibs = [
            "nds"
            "armv4t"
          ];
        };
        "3ds" = {
          toolchain = "devkitarm";
          portlibs = [ "3ds" ];
        };
        gamecube = {
          toolchain = "devkitppc";
          portlibs = [
            "gamecube"
            "ppc"
          ];
        };
        wii = {
          toolchain = "devkitppc";
          portlibs = [
            "wii"
            "ppc"
          ];
        };
        wiiu = {
          toolchain = "devkitppc";
          portlibs = [
            "wiiu"
            "ppc"
          ];
        };
        switch = {
          toolchain = "devkita64";
          portlibs = [ "switch" ];
        };
      };

      hostTools = [
        pkgs.gnumake
        pkgs.python3
        pkgs.pkg-config
        pkgs.zip
        pkgs.unzip
      ];

      shellTools = hostTools ++ [
        pkgs.cmake
        pkgs.ninja
      ];

      platformEnv =
        platform:
        let
          config = platforms.${platform};
          sdk = sdks.${config.toolchain};
        in
        {
          DEVKITPRO_PORTLIBS = lib.concatStringsSep " " config.portlibs;
          PORTLIBS_PREFIX = "${sdk}/opt/devkitpro/portlibs/${builtins.head config.portlibs}";
          PKG_CONFIG_LIBDIR = lib.concatMapStringsSep ":" (
            p:
            "${sdk}/opt/devkitpro/portlibs/${p}/lib/pkgconfig:${sdk}/opt/devkitpro/portlibs/${p}/share/pkgconfig"
          ) config.portlibs;
          PKG_CONFIG_PATH = "";
        };

      mkDerivation =
        args@{
          platform,
          nativeBuildInputs ? [ ],
          env ? { },
          ...
        }:
        pkgs.stdenvNoCC.mkDerivation (
          (builtins.removeAttrs args [ "platform" ])
          // {
            nativeBuildInputs = [ sdks.${platforms.${platform}.toolchain} ] ++ hostTools ++ nativeBuildInputs;
            env = platformEnv platform // env;
            dontStrip = args.dontStrip or true;
            dontPatchELF = args.dontPatchELF or true;
          }
        );

      examples = import ./nix/examples.nix {
        inherit pkgs sdks mkDerivation;
        switchExamples = switch-examples;
        wiiuExamples = wiiu-examples;
      };

      checks = import ./nix/checks.nix {
        inherit
          pkgs
          sdks
          platforms
          examples
          self
          system
          ;
      };

      updateImages = pkgs.writeShellApplication {
        name = "update-images";
        runtimeInputs = [
          pkgs.skopeo
          pkgs.nix
          pkgs.jq
          pkgs.coreutils
        ];
        text = builtins.readFile ./scripts/update-images.sh;
      };
    in
    {
      apps.${system}.update-images = {
        type = "app";
        program = "${updateImages}/bin/update-images";
        meta.description = "Update pinned devkitPro container images";
      };

      packages.${system} =
        sdks // lib.mapAttrs' (name: value: lib.nameValuePair "example-${name}" value) examples;

      checks.${system} = checks;

      devShells.${system} =
        (lib.mapAttrs (
          name: sdk:
          pkgs.mkShellNoCC {
            packages = [ sdk ] ++ shellTools;
            env = lib.optionalAttrs (name == "devkita64") (platformEnv "switch");
          }
        ) sdks)
        // (lib.mapAttrs (
          platform: config:
          pkgs.mkShellNoCC {
            packages = [ sdks.${config.toolchain} ] ++ shellTools;
            env = platformEnv platform;
          }
        ) platforms);
      lib = { inherit mkDerivation platforms; };
      formatter.${system} = pkgs.nixfmt;
    };
}
