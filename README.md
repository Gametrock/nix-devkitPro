# nix-devkitPro

A Nix flake providing devkitPro SDKs for GBA, Nintendo DS, Nintendo 3DS,
GameCube, Wii, Wii U, and Nintendo Switch projects.

Please report packaging issues to this repository rather than upstream.
This project is not affiliated with or endorsed by devkitPro.

## Development shells

Enter a shell for the console you are targeting:

```sh
nix develop .#gba
nix develop .#nds
nix develop .#3ds
nix develop .#gamecube
nix develop .#wii
nix develop .#wiiu
nix develop .#switch
```

Each shell provides the corresponding SDK and build tools, sets the SDK
environment variables, and selects portlibs paths for the target console. Use
the project's usual build instructions, for example:

```sh
nix develop .#switch
cd /path/to/your/application
make
```

Toolchain-wide shells are also available as `devkitarm`, `devkitppc`, and
`devkita64`. The `devkita64` shell selects Switch portlibs. For other consoles,
use the matching console shell to select its portlibs.

## SDK packages

The flake provides these packages on `x86_64-linux`:

- `devkitarm`: GBA, Nintendo DS, and Nintendo 3DS
- `devkitppc`: GameCube, Wii, and Wii U
- `devkita64`: Nintendo Switch

Each package contains the SDK contents from its pinned official image,
including tools, headers, libraries, build rules, and examples. The SDKs are
immutable in the Nix store. To change SDK versions, update the image pins.

## Downstream Nix builds

`devkitpro.lib.mkDerivation` selects the SDK and portlibs for the requested
`platform` and provides a Make-oriented build environment:

```nix
{
  inputs.devkitpro.url = "github:Gametrock/nix-devkitpro";

  outputs = { self, nixpkgs, devkitpro }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.${system}.default = devkitpro.lib.mkDerivation {
        platform = "switch";
        pname = "my-switch-project";
        version = "1.0.0";
        src = ./.;
        dontConfigure = true;
        installPhase = ''
          mkdir -p "$out"
          cp *.nro "$out/"
        '';
      };
    };
}
```

Supported `platform` values are `gba`, `nds`, `3ds`, `gamecube`, `wii`,
`wiiu`, and `switch`. The helper provides Make, Python, pkg-config, zip, and
unzip. Add other build tools to `nativeBuildInputs` as needed.


## Contributing

### Checks and examples

To run all checks:

```sh
nix flake check -L --keep-going
```

This builds the SDK inventory and helper checks, verifies the downstream consumer example, and cross-compiles representative projects for each supported console. Example checks include artifact and ELF validation, some also check portlibs.

To build or test one example directly:

```sh
nix build .#example-gba
nix build .#example-switch
nix build .#example-switch-portlibs
```

### Updating SDK images

Run the updater from the repository root:

```sh
nix run .#update-images -- devkita64
nix run .#update-images -- devkitarm
nix run .#update-images -- devkitppc
```
or
```sh
nix run .#update-images -- all
```

Review the image pin changes and run the checks after an update.

## License

This repository's original code and documentation are licensed under the
Apache License, Version 2.0. See [LICENSE](LICENSE).

Third-party SDKs, tools, libraries, examples, and assets retain their
respective licenses. The repository's Apache-2.0 license does not relicense
those components. Redistribution of SDK packages or compiled examples
must comply with the applicable upstream licenses, including notice and
source-code requirements where applicable.