# Darwin-specific declarative home-manager common configuration.
#
# Imported by the flake when the host's system is Darwin. Everything cross-platform
# lives in home.nix; monitor layout and anything else host-specific lives in
# <host>/home.nix.
#
{
  config,
  lib,
  pkgs,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  inherit (nixSpaceAttrs) tags;
  inherit (nixSpaceLib.tags) hasTag;
in
{
  nixSpace = {
    sketchybar.enable = lib.mkDefault (hasTag "aerospace" tags);

    programs = {
      workstationCommon.enable = true;
      launchers = {
        fzf.enable = lib.mkDefault (hasTag "aerospace" tags);
        primary = lib.mkDefault "fzf";
      };
      shells.zsh = {
        enable = lib.mkDefault true;
        dotDir = "${config.xdg.configHome}/zsh";
      };
      yazi.plugins.office = false;
    };

    security = {
      yubikey.tools.oathGuiPackage = pkgs.local.yubioathDarwin;
      gpg.pinentry = lib.mkIf (hasTag "gpg-user" tags) {
        # pinentry-gnome3 has no macOS build. pinentry_mac is the only one that
        # prompts correctly from a launchd-started agent, and it has Keychain
        # integration the others lack.
        graphical = pkgs.pinentry_mac;
      };
    };
  };

  home.packages = lib.optionals (hasTag "yubi-age-user" tags) [
    # The macOS YubiKey Authenticator.
    # yubioath-flutter does not run.
    pkgs.local.yubioathDarwin
    pkgs.pinentry_mac
  ];
}
