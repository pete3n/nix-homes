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

      # pam_u2f credentials in ~/.config/Yubico/u2f_keys, for sudo on this
      # Mac (origin pam://p22). Linux Workstations use the central
      # /etc/u2f_mappings on pam://p22.lan instead and ignore this file.
      yubikey.u2f = {
        enable = true;
        credentials = [
          "jPXIHluUKJNDbiCSQ5+DRfMrG+ZNqMyQXTHSyByi5XHSXHNhZC2CduqlqNOIutx2NIc8Qhn2omlCFpcOoDjukw==,FQlfOdBDXUlixODcx+4gDsFIyLaX21KWqkEmbVx3ny7iwJpL43O2BRMAcArBJWJ/tEsz2/lxI/gZk7Dn9093vA==,es256,+presence"
          "4a218pdZXDWigFWVcGDubvTbdAN9cAlp9+r0CPezvDojRPeou4j1m6vv4ZqW70jzNhAd9HD4gV0ykhC4Uoxi0A==,ftm749QLZ7sgH9ITIyb+f3Wn4BXDjK32+qIMlkfkOnMZ8On6GWBteaITzdCZ6PRzbTCQPZ6TC+ylGLw/rn0Ewg==,es256,+presence"
        ];
      };
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
