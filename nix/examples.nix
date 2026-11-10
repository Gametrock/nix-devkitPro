{
  pkgs,
  sdks,
  mkDerivation,
  switchExamples,
  wiiuExamples,
}:
let
  armExamples = "${sdks.devkitarm}/opt/devkitpro/examples";

  ppcExamples = "${sdks.devkitppc}/opt/devkitpro/examples";
  specs = {
    gba = {
      platform = "gba";
      src = "${armExamples}/gba/graphics/ansi_console";
      artifact = "example.gba";
      machine = "ARM";
    };

    nds = {
      platform = "nds";
      src = "${armExamples}/nds/hello_world";
      artifact = "example.nds";
      machine = "ARM";
    };

    "3ds" = {
      platform = "3ds";
      src = "${armExamples}/3ds/templates/application";
      artifact = "example.3dsx";
      machine = "ARM";
    };

    gamecube = {
      platform = "gamecube";
      src = "${ppcExamples}/gamecube/templates/application";
      artifact = "example.dol";
      machine = "PowerPC";
    };

    wii = {
      platform = "wii";
      src = "${ppcExamples}/wii/templates/makefile/application";
      artifact = "example.dol";
      machine = "PowerPC";
    };

    wiiu = {
      platform = "wiiu";
      src = "${wiiuExamples}/templates/application_make";
      artifact = "example.rpx";
      machine = "PowerPC";
    };

    switch = {
      platform = "switch";
      src = "${switchExamples}/templates/application";
      artifact = "example.nro";
      machine = "AArch64";
    };

    switch-romfs = {
      platform = "switch";
      src = "${switchExamples}/fs/romfs";
      artifact = "example.nro";
      machine = "AArch64";
    };

    switch-sysmodule = {
      platform = "switch";
      src = "${switchExamples}/templates/sysmodule";
      artifact = "example.nsp";
      machine = "AArch64";
      makeFlags = [ "CONFIG_JSON=sysmodule.json" ];
    };

    gba-assets = {
      platform = "gba";
      src = "${armExamples}/gba/graphics/PCXView";
      artifact = "example.gba";
      machine = "ARM";
    };
  };

  baseLibraries = {
    gba = "-lgba";
    nds = "-lnds9";
    "3ds" = "-lctru -lm";
    gamecube = "-logc -lm";
    wii = "-lwiiuse -lbte -logc -lm";
    wiiu = "-lwut";
    switch = "-lnx";
  };

  portlibsSpecs = pkgs.lib.genAttrs (builtins.attrNames baseLibraries) (
    platform: specs.${platform} // { portlibs = true; }
  );

  buildExample =
    name: spec:
    mkDerivation {
      inherit (spec) platform src;
      pname = "example-${name}";
      version = "1";
      passthru.platform = spec.platform;

      nativeBuildInputs = [
        pkgs.binutils
        pkgs.file
      ];

      unpackPhase = ''
        runHook preUnpack
        cp -R "$src" example
        chmod -R u+w example
        cd example
        runHook postUnpack
      '';
      dontConfigure = true;

      buildPhase = ''
        runHook preBuild
        sha256sum Makefile > makefile.sha256

        ${pkgs.lib.optionalString (spec.portlibs or false) ''
          cp ${../tests/fixtures/portlibs.cpp} source/portlibs.cpp
          pkg-config --static --cflags --libs libpng | tee portlibs-flags.txt
        ''}

        make -j"$NIX_BUILD_CORES" ${pkgs.lib.escapeShellArgs (spec.makeFlags or [ ])} ${
          pkgs.lib.optionalString (spec.portlibs or false) ''
            "CPPFLAGS=$(pkg-config --static --cflags libpng zlib)" \
            "LIBS=$(pkg-config --static --libs libpng) ${baseLibraries.${spec.platform}}"
          ''
        }

        sha256sum --check makefile.sha256
        runHook postBuild
      '';
      doCheck = true;

      checkPhase = ''
        runHook preCheck

        test -s ${spec.artifact}

        readelf -h example.elf | tee elf-header.txt
        grep -E 'Machine:.*${spec.machine}' elf-header.txt

        file ${spec.artifact} | tee artifact-type.txt

        python3 ${../tests/examples/artifact.py} ${spec.artifact} ${
          pkgs.lib.optionalString (name == "switch-romfs") "--romfs"
        }

        ${pkgs.lib.optionalString (spec.portlibs or false) ''
          readelf --wide --symbols example.elf > symbols.txt
          grep 'png_create_read_struct' symbols.txt
          grep 'crc32' symbols.txt

          if grep -F '/opt/devkitpro' portlibs-flags.txt | grep -vF "$DEVKITPRO"; then
            echo "Unrelocated SDK path in pkg-config output" >&2
            exit 1
          fi
        ''}

        runHook postCheck
      '';
      
      installPhase = ''
        mkdir -p "$out"
        cp ${spec.artifact} example.elf elf-header.txt artifact-type.txt makefile.sha256 "$out/"
        find . -maxdepth 1 -name '*.map' -exec cp {} "$out/" \;
      '';
    };
in
(pkgs.lib.mapAttrs buildExample specs)
// (pkgs.lib.mapAttrs' (
  platform: spec:
  pkgs.lib.nameValuePair "${platform}-portlibs" (buildExample "${platform}-portlibs" spec)
) portlibsSpecs)
