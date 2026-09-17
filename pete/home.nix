# Cross-platform declarative home-manager common configuration.
#
# Home-manager configuration files:
#   home.nix          this file: identity, credentials, portable tooling
#   home-linux.nix    Linux specific configuration
#   home-darwin.nix   Darwin specific configuration
#   <host>/home.nix   Host specific home-manager configuration
#
{
  config,
  inputs,
  lib,
  pkgs,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  inherit (nixSpaceAttrs) user host tags;
  inherit (nixSpaceLib.tags) hasTag;
  home = config.home.homeDirectory;
in
{
  # Reload changed user units on switch rather than at next login.
  systemd.user.startServices = "sd-switch";

  nixSpace = {
    programs = {
      git = {
        userEmail = "pete3n@protonmail.com";
        userName = "pete3n";
      };

      nixvim = {
        enable = true;
        package = inputs.nixvim.packages.${nixSpaceAttrs.system}.default;
      };

      firefox = {
        enable = true;
        extensions = with inputs.firefox-addons.packages.${nixSpaceAttrs.system}; [
          ublock-origin
          tridactyl
          multi-account-containers
        ];
        pkcs11Modules.OpenSC = "${pkgs.opensc}/lib/opensc-pkcs11.so";
      };

      aichat = {
        enable = true;
        local.enable = true;
      };

      # GPU monitoring in btop, from the tags rather than from the host name.
      # A machine with neither gets neither.
      btop = {
        cuda = hasTag "cuda" tags;
        rocm = hasTag "rocm" tags;
      };

      shells = {
        aliases = {
          grep = "grep --color";
          "?" = "smart_help";
          zf = "zfile";
        };
        bash.loginGreeting.fastfetch = true;
      };

      yazi.keymaps = [
        {
          on = [
            "g"
            "p"
          ];
          run = "cd ${config.xdg.userDirs.projects}";
          desc = "go to projects";
        }
      ];

      # Host file sync configuration.
      hostSync = {
        enable = true;
        localHost = host;
				# TODO: How to dynamically create this from configurations?
        hosts = {
          silver16.platform = "linux";
          black8.platform = "linux";
          macbook.platform = "darwin";
          macmini.platform = "darwin";
        };
        paths = [
          "Documents"
          "Downloads"
          "Music"
          "Nextcloud"
          "Pictures"
          "Projects"
          "Videos"
        ];
        excludePaths = [ "Downloads/Work" ];
      };

      crypto = {
        enable = hasTag "crypto" tags;
        bisq = {
          version = "v2";
          package = pkgs.unstable.bisq2;
        };
        monero = {
          cliPackage = pkgs.unstable.monero-cli;
          guiPackage = pkgs.unstable.monero-gui;
        };
        sparrow = pkgs.unstable.sparrow;
      };

      netsec.sdr = lib.mkIf (hasTag "sdr" tags) {
        gnuradio = pkgs.unstable.gnuradio;
        soapysdr = pkgs.unstable.soapysdr-with-plugins;
      };
    };

    services.backup = {
      enable = true;
      # NFS on .p22. A machine off that network has nowhere to write, which
      # borgmatic reports rather than failing silently.
      local.repository = "/mnt/nfs/share/backups/${host}-${user}";
      encryptedBackup = false;
      patterns = [
        "R ${home}"
        "- ${home}/.cache"
        "- ${home}/Downloads"
      ];
    };

    security = {
      yubikey = {
        enable = true;

        # Import resident keys from the YubiKey if any are missing from ~/.ssh.
        sshImport.expectedKeys.userKeys = [
          "id_ed25519_sk_rk_aws"
          "id_ed25519_sk_rk_github"
          "id_ed25519_sk_rk_linode"
          "id_ed25519_sk_rk_p22"
        ];

        u2f = {
          enable = true;
          credentials = [
            "jPXIHluUKJNDbiCSQ5+DRfMrG+ZNqMyQXTHSyByi5XHSXHNhZC2CduqlqNOIutx2NIc8Qhn2omlCFpcOoDjukw==,FQlfOdBDXUlixODcx+4gDsFIyLaX21KWqkEmbVx3ny7iwJpL43O2BRMAcArBJWJ/tEsz2/lxI/gZk7Dn9093vA==,es256,+presence"
            "4a218pdZXDWigFWVcGDubvTbdAN9cAlp9+r0CPezvDojRPeou4j1m6vv4ZqW70jzNhAd9HD4gV0ykhC4Uoxi0A==,ftm749QLZ7sgH9ITIyb+f3Wn4BXDjK32+qIMlkfkOnMZ8On6GWBteaITzdCZ6PRzbTCQPZ6TC+ylGLw/rn0Ewg==,es256,+presence"
          ];
        };

        tools = {
          legacyOtp = true;
          oathGui = true;
        };
      };

      gpg = {
        enable = true;
        keyFingerprint = "081B780E59C37C11F59EFA2BC89CFF43D68AD2CB";
        publicKey = ./secrets/pubkey.asc;
        ssh.keygrips = [ "1B73CE32F24F63ADCCC49061D9D95B414B057B7F" ];
      };
    };
  };

  home = {
    # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
    stateVersion = "24.05";
    username = user;
    # Cross-platform Linux/Darwin home definition.
    homeDirectory =
      if nixSpaceLib.platform.isDarwin nixSpaceAttrs.system then "/Users/${user}" else "/home/${user}";
  };

  programs = {
    home-manager.enable = true;

    librewolf.enable = true;

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "github github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = [
            "${home}/.ssh/id_ed25519_sk_rk_github"
            "${home}/.ssh/pete3n"
          ];
          IdentitiesOnly = true;
        };
        "linode" = {
          HostName = "tech.p3n.dev";
          User = "ubuntu";
          IdentityFile = [ "${home}/.ssh/id_ed25519_sk_rk_linode" ];
          IdentitiesOnly = true;
        };
      }
      // lib.optionalAttrs (hasTag "p22" tags) {
        # IdentityAgent = "none" forces the resident key rather than whatever
        # the agent offers first, so the touch prompt is predictable.
        "black8" = {
          HostName = "black8.p22";
          User = user;
          IdentityFile = "${home}/.ssh/id_ed25519_sk_rk_p22";
          IdentitiesOnly = true;
          IdentityAgent = "none";
          # Multiplexing: one touch per 10 minutes rather than one per
          # command, which matters for remote builds.
          ControlMaster = "auto";
          ControlPath = "~/.ssh/control-%r@%h:%p";
          ControlPersist = "10m";
        };
        "backupsvr" = {
          HostName = "backupsvr.p22";
          User = "root";
          IdentityFile = "${home}/.ssh/id_ed25519_sk_rk_p22";
          IdentitiesOnly = true;
          IdentityAgent = "none";
        };
        "mediasvr" = {
          HostName = "media.p22";
          User = "root";
          IdentityFile = "${home}/.ssh/id_ed25519_sk_rk_p22";
          IdentitiesOnly = true;
          IdentityAgent = "none";
        };
      };
    };
  };
}
