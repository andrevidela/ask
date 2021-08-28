{ pkgs ? import ./nix/nixpkgs.nix {} }:

let
  project = import ./nix/project.nix { inherit pkgs; };
in

# shellFor provides a Haskell development environment using `nix-shell`.
#
# Documentation:
# https://input-output-hk.github.io/haskell.nix/reference/library/#shellfor
#
# Tutorial:
# https://input-output-hk.github.io/haskell.nix/tutorials/development/#how-to-get-a-development-shell
project.shellFor {
  packages = ps: with ps; [ ask ];

  tools = {
    cabal.version = "3.4.0.0";
  };

  buildInputs = with pkgs; [
    niv
  ];

  withHoogle = true;

  # Put askt onto $PATH
  shellHook = ''
    export PATH=$PWD/bin:$PATH
  '';
}
