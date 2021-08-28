args:

let
  sources = import ./sources.nix {};
  haskellNix = import sources.haskellNix args;
in

import
  haskellNix.sources.nixpkgs-2009
  haskellNix.nixpkgsArgs
