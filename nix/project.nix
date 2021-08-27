{ mkDerivation, base, containers, lib, mtl }:
mkDerivation {
  pname = "ask";
  version = "0.1.0.0";
  src = ./..;
  isLibrary = false;
  isExecutable = true;
  libraryHaskellDepends = [ base containers mtl ];
  executableHaskellDepends = [ base containers mtl ];
  doHaddock = false;
  license = "unknown";
  hydraPlatforms = lib.platforms.none;
}
