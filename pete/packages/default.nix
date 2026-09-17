# Directory hook for this user's own packages.
#
# Cross-platform packages live in ./cross-platform; platform-specific ones in
# ./linux and ./darwin. Each subdirectory is optional — the guard means adding
# ./darwin later needs no change here.
#
# Mirrors nixSpace's own packages hook. The two differ only in which namespace
# they land under: nsPkgs for the library, local for this repo.
{
  pkgs,
  nixSpaceLib,
  nixSpaceAttrs ? null,
}:
let
  system = if nixSpaceAttrs == null then pkgs.stdenv.hostPlatform.system else nixSpaceAttrs.system;

  importIf =
    path: if builtins.pathExists (path + "/default.nix") then import path { inherit pkgs; } else { };
in
builtins.trace
  "packages hook: system=${system} crossPlatform=${
    toString (builtins.pathExists (./cross-platform + "/default.nix"))
  } linux=${
    toString (builtins.pathExists (./linux + "/default.nix"))
  } isLinux=${toString (nixSpaceLib.platform.isLinux system)}"
  (
    importIf ./cross-platform
    // (if nixSpaceLib.platform.isLinux system then importIf ./linux else { })
    // (if nixSpaceLib.platform.isDarwin system then importIf ./darwin else { })
  )
