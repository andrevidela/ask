let
  json = with builtins; fromJSON (readFile ./nixpkgs.json);
in

import (fetchTarball {
  url = "https://github.com/${json.owner}/${json.repo}/archive/${json.rev}.tar.gz";
  sha256 = json.sha256;
})
