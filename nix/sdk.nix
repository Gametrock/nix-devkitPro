{
  pkgs,
  name,
  image,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = name;

  version = "image-${builtins.substring 7 12 image.imageDigest}";
  src = pkgs.dockerTools.pullImage (
    image
    // {
      os = "linux";
      arch = "amd64";
    }
  );

  nativeBuildInputs = [
    pkgs.crane
    pkgs.autoPatchelfHook
    pkgs.python3
  ];

  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.ncurses
  ];
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  dontAutoPatchelf = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"

    # crane applies layer ordering and whiteouts
    crane export - - < "$src" |
      tar --extract --no-same-owner --no-same-permissions \
        --directory "$out" opt usr/share/pacman

    sdk="$out/opt/devkitpro"

    chmod -R u+w "$sdk"
    mkdir -p "$out/nix-support" "$out/share/devkitpro"

    cp ${builtins.toFile "${name}-image.json" (builtins.toJSON image)} \
      "$out/share/devkitpro/image.json"

    (cd "$sdk"; find . -printf '%y %p -> %l\n' | LC_ALL=C sort) \
      > "$out/share/devkitpro/inventory.txt"

    python3 ${./inventory.py} capture \
      "$sdk" "$out/share/devkitpro/inventory.json"

    python3 ${./relocate.py} "$sdk" ${pkgs.bash}/bin/bash

    # The package manager's original database is retained for provenance only.
    for component in "$sdk"/*; do
      case "$component" in
        */pacman) ;;
        *) autoPatchelf "$component" ;;
      esac
    done

    patchShebangs "$sdk/tools" "$sdk"/devkit*/bin

    cat > "$out/nix-support/setup-hook" <<EOF
    export DEVKITPRO="$sdk"

    for compiler in devkitARM devkitPPC devkitA64; do
      if [ -d "$sdk/\$compiler" ]; then
        case \$compiler in
          devkitARM) export DEVKITARM="$sdk/\$compiler" ;;
          devkitPPC) export DEVKITPPC="$sdk/\$compiler" ;;
          devkitA64) export DEVKITA64="$sdk/\$compiler" ;;
        esac
        addToSearchPath PATH "$sdk/\$compiler/bin"
      fi
    done

    addToSearchPath PATH "$sdk/tools/bin"

    for portlibs in \''${DEVKITPRO_PORTLIBS-}; do
      addToSearchPath PATH "$sdk/portlibs/\$portlibs/bin"
    done
    EOF

    ln -s "$sdk/tools/bin" "$out/bin"

    runHook postInstall
  '';

  postFixup = ''
    python3 ${./inventory.py} verify "$out/opt/devkitpro" "$out/share/devkitpro/inventory.json"
  '';

  meta = {
    description = "${name} SDK extracted from the devkitPro Docker image";
    homepage = "https://github.com/Gametrock/nix-devkitpro";
    platforms = [ "x86_64-linux" ];

    # This aggregate contains packages under multiple licenses.
    sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
  };
}
