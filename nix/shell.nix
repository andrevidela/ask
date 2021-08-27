{ pkgs ? import ./nixpkgs.nix {} }:

with pkgs;

mkShell {
  buildInputs = [
    cabal-install
    ghc

    # dependency for nix/update-nixpkgs.sh
    nix-prefetch-github

    # dependency for nix/update-project.sh
    cabal2nix
  ];
}
