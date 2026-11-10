{
  pkgs,
  sdks,
  platforms,
  examples,
  self,
  system,
}:
let
  lib = pkgs.lib;
  inventoryChecks = lib.mapAttrs (
    name: sdk:
    pkgs.runCommand "${name}-inventory-check"
      {
        nativeBuildInputs = [
          sdk
          pkgs.python3
          pkgs.pkgconf
          pkgs.patchelf
        ];
      }
      ''
        python3 ${../tests/sdk/sdk.py} "$out" ${./inventory.py} ${../tests/sdk/pkg-config-exceptions.json}
      ''
  ) sdks;

  consumer = (import ../tests/consumer/flake.nix).outputs { devkitpro = self; };

  groupedChecks = lib.mapAttrs (
    toolchain: _:
    pkgs.linkFarm "${toolchain}-checks" (
      lib.mapAttrsToList (name: path: { inherit name path; }) (
        (lib.filterAttrs (_: test: platforms.${test.platform}.toolchain == toolchain) examples)
        // {
          inventory = inventoryChecks.${toolchain};
          helpers = helperChecks;
        }
        // lib.optionalAttrs (toolchain == "devkita64") { consumer = consumer.packages.${system}.default; }
      )
    )
  ) sdks;

  helperChecks =
    pkgs.runCommand "devkitpro-helper-tests"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.jq
          pkgs.bash
        ];
      }
      ''
        python3 ${../tests/helpers.py} ${./relocate.py} ${./inventory.py} ${../scripts/update-images.sh}
        touch "$out"
      '';

in
examples
// groupedChecks
// lib.mapAttrs' (name: value: lib.nameValuePair "${name}-inventory" value) inventoryChecks
// {
  consumer = consumer.packages.${system}.default;
  helpers = helperChecks;
}
