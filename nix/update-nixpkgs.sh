#!/bin/sh

set -e
cd "$(dirname "$0")"

nix-prefetch-github --json --no-fetch-submodules --no-prefetch --rev nixos-unstable NixOS nixpkgs > nixpkgs.json
