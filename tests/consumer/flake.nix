{
  description = "Switch build test using the devkitPro helper";
  inputs.devkitpro.url = "path:../..";

  outputs = { devkitpro, ... }: {
    packages.x86_64-linux.default = devkitpro.lib.mkDerivation {
      platform = "switch";
      pname = "consumer-switch-example";
      version = "1";

      src = "${devkitpro.inputs.switch-examples}/templates/application";
      dontConfigure = true;

      installPhase = ''
        mkdir -p "$out"
        cp *.elf *.nro "$out/"
      '';
    };
  };
}
