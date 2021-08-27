{ pkgs ? import ./nixpkgs.nix {} }:

with pkgs;

{
  ask = haskellPackages.callPackage ./project.nix {};
}
