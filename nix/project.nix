{ pkgs ? import ./nixpkgs.nix {} }:

with pkgs;

haskell-nix.cabalProject {
  src = haskell-nix.haskellLib.cleanGit {
    name = "ask";
    src = ../.;
  };

  compiler-nix-name = "ghc8105";
}
