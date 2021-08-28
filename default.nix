{ pkgs ? import ./nix/nixpkgs.nix {} }:

with pkgs;

let
  # Documentation:
  # https://input-output-hk.github.io/haskell.nix/reference/library/#cabalproject
  project = import ./nix/project.nix { inherit pkgs; };
in

{
  ask =
    project.hsPkgs.ask.components.exes.ask;

  # Only builds on macOS, see:
  # https://github.com/input-output-hk/haskell.nix/issues/1099
  ask-lib-ios =
    project.projectCross.iphone64.hsPkgs.ask.components.library;
}
