# Linux-specific declarative home-manager common configuration.
#
# Imported by the flake when the host's system is Linux. Everything cross-platform
# lives in home.nix; monitor layout and anything else host-specific lives in
# <host>/home.nix.
#
{
  config,
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
    hyprdesktop.lock = {
      placeholderText = "Speak friend...";
      background = "${config.xdg.userDirs.pictures}/wallpapers/hyprlock.jpg";
    };
    programs = {
      mediaPlayers.extraPackages = [
        pkgs.local.ipodShuffle4g
      ];

      messaging = {
        enable = true;
        # The overlay works around an Electron GPU failure on AMD and pins the
        # keyring backend; see overlays/default.nix.
        signal = pkgs.mod.no-gpu-signal-desktop;
        element = pkgs.unstable.element-desktop;
      };

      remote = {
        enable = true;
        remmina = pkgs.remmina;
        rustdesk = pkgs.rustdesk;
      };
    };

    services = {
      hyprlidmon.enable = hasTag "laptop" tags;
      batmond.enable = hasTag "laptop" tags;
      powerproud.enable = hasTag "laptop" tags;
    };
  };

  home.packages = with pkgs; [
    local.vipAccess # Provision Symantec VIP TOTP
    nextcloud-client
    standardnotes
  ];
}
