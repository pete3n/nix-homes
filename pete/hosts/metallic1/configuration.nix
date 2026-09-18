# mettalic1 system configuration
#
{
  lib,
  pkgs,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  inherit (nixSpaceAttrs) user host tags;
  inherit (nixSpaceLib.tags) hasTag;
in
{
  imports = [
    ./secrets.nix
  ];

  # Determinate Nix owns /etc/nix/nix.conf. Without this, nix-darwin writes
  # its own and the two fight.
  determinateNix = {
    enable = true;
    determinateNix.customSettings = {
      trusted-users = [
        "root"
        user
      ];
      substituters = [
        "http://backupsvr.p22:8000/"
        "https://nix-community.cachix.org/"
        "https://cache.nixos.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  # nix-darwin's own versioning, unrelated to NixOS's stateVersion string.
  system = {
    stateVersion = 5;

    # Which user's defaults the system.defaults below apply to. Without it
    # nix-darwin writes them for whoever runs darwin-rebuild, which is a
    # different thing on a multi-user Mac.
    primaryUser = user;

    defaults = {
      menuExtraClock.Show24Hour = true;
      dock.autohide = true;

      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        # Fast repeat: 14 is roughly 200ms before repeat starts, 1 is the
        # fastest rate macOS accepts. Both are lower than anything the
        # Settings UI offers.
        InitialKeyRepeat = 14;
        KeyRepeat = 1;
      };
    };

    keyboard = {
      enableKeyMapping = true;

      # Left as-is deliberately: the external keyboard already has
      # ctrl | command | alt in the order this machine expects, and remapping
      # here would fight it.
      remapCapsLockToControl = false;
      remapCapsLockToEscape = false;
      swapLeftCommandAndLeftAlt = false;
    };
  };

  networking = {
    hostName = host;
    # What Finder and AirDrop show. Separate from hostName, which is what the
    # network sees: macOS keeps three names and lets them diverge.
    computerName = host;
    localHostName = host;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixSpace = {
    nix.cache = {
      enable = true;
      substituters =
        lib.optional (hasTag "p22" tags) {
          url = "http://backupsvr.p22:8000/";
        }
        ++ [
          {
            url = "https://nix-community.cachix.org/";
            publicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
          }
        ];
    };

    services.nfsMount = lib.mkIf (hasTag "p22" tags) {
      enable = true;
      server = "backupsvr.p22";
      shares = {
        share.remotePath = "/mnt/user/share";
        open.remotePath = "/mnt/user/open";
      };
    };

    security.yubikey.u2f = {
      enable = hasTag "yubi-u2f" tags;
      origin = "pam://p22";
    };
  };

  # Touch ID for sudo is off: the YubiKey U2F module above registers its own
  # pam_u2f line in sudo_local.
  security.pam.services.sudo_local.touchIdAuth = false;

  # The p22 internal CA. A trusted root means this machine accepts anything
  # that CA signs.
  security.pki.certificateFiles = lib.optionals (hasTag "p22" tags) [
    ../../secrets/certs/p22-ca.crt
  ];

  # zsh at the system level, so /etc/zshrc sources the Nix profile before any
  # user config runs. home-manager configures the user half; without this the
  # login shell has no Nix paths and nothing in the profile is reachable.
  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  time.timeZone = "America/New_York";

  # System-level fonts. home-manager's font directory is not on the Core Text
  # search path.
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];
}
