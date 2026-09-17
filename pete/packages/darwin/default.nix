# Darwin only packages
{ pkgs, ... }:
{
  yubioathDarwin = pkgs.callPackage ./yubioath-darwin { };
}
