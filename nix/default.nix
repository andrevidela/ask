{ pkgs ? import ./nixpkgs.nix {} }:

with pkgs;
with lib;

{
  ask = (haskellPackages.callPackage ./project.nix {}).overrideAttrs (const {
    src = nix-gitignore.gitignoreSource [] ../.;
  });
}
