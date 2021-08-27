let
  overlay = final: previous: import ./. { pkgs = final; };

  nixpkgs = args: import ./nixpkgs.nix (args // {
    overlays = [ overlay ];
  });
in

{ pkgs ? nixpkgs {} }:

with pkgs;
with lib;

let
  platforms = {
    aarch64-ios-cross = pkgsCross.iphone64;
  };
in

genAttrs (attrNames (overlay {} {}))
  (name: mapAttrs (const (getAttr name)) platforms)
