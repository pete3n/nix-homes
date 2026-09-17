# Directory hook for linux packages.
{ pkgs, ... }:
{
  ipodShuffle4g = import ./ipod-shuffle-4g { inherit pkgs; };
  vipAccess = import ./vipaccess { inherit pkgs; };
}
