# Hook for host secrets.
{
  lib,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  inherit (nixSpaceAttrs) tags;
  inherit (nixSpaceLib.tags) hasTag;
in
{
  imports = [
    ../../secrets/git-ssh.nix
    ../../secrets/yubi-age.nix
  ]
  ++ lib.optional (hasTag "vpn-user" tags) ../../secrets/p22-vpn.nix;
}
