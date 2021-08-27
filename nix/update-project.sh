#!/bin/sh

set -e
cd "$(dirname "$0")"

cabal2nix .. > project.nix
