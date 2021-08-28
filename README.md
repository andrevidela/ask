# ask

being a particular fragment of Haskell, extended to a proof system

## Setup

Note that this project only fully supports x86-64 and Aarch64
variants of Linux and macOS hosts. If you are using Windows, first
[install WSL2][WSL2] and then proceed inside WSL2 as if you are on
Linux.

1. [Install Nix][Nix];

2. [Set up IOHK binary cache][IOHK binary cache].

[IOHK binary cache]: https://input-output-hk.github.io/haskell.nix/tutorials/getting-started/#setting-up-the-binary-cache
[Nix]: https://nixos.org/download.html
[WSL2]: https://docs.microsoft.com/en-us/windows/wsl/install-win10

## Recipes

Here are some of the useful things you can do once you complete
[the Setup section](#setup):

### Build

To build `ask` executable, run `nix-build -A ask`.

To build `ask` iOS library, run `nix-build -A ask-lib-ios`.
Currently, it only exposes `Ask.ChkRaw` module. This only works on macOS
(see [input-output-hk/haskell.nix#1099][]).

[input-output-hk/haskell.nix#1099]: https://github.com/input-output-hk/haskell.nix/issues/1099

### Develop

To enter Nix development environment, run `nix-shell`. This command
drops you into a shell with reproducible, pinned versions of GHC,
Cabal, Hoogle, and other development tools.

To add an additional package to Nix development environment, add
the package name to `buildInputs` in `shell.nix` file. To find
the package name, use [NixOS Search][].

For additional information about Nix development environment, consult
[the corresponding `haskell.nix` tutorial][haskell.nix tutorial].

[haskell.nix tutorial]: https://input-output-hk.github.io/haskell.nix/tutorials/development/
[NixOS Search]: https://search.nixos.org

### Maintain

To change GHC version, update `compiler-nix-name` value in
`nix/project.nix` file.

To update Cabal dependencies, remove `cabal.project.freeze` file,
update `index-state` value in `cabal.project` file, and finally run
`cabal v2-freeze`.

To update `haskell.nix` version (including Nixpkgs version),
run `niv update` inside `nix-shell`.
