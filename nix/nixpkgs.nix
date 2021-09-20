args:

let
  sources = import ./sources.nix {};

  haskellNix = import sources.haskellNix args;
  nixpkgs = import sources.nixpkgs;

in

import nixpkgs haskellNix.nixpkgsArgs
