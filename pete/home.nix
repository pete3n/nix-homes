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
        # The Primary Key's handles; the Backup Key's are named *_backup by
        # hand for now (ssh-keygen -K names both the same).
        sshImport.expectedKeys.userKeys = [
          "id_ed25519_sk_rk_aws"
          "id_ed25519_sk_rk_github"
          "id_ed25519_sk_rk_linode"
          # Standard and Elevated Identity keys held in kanidm.
          "id_ed25519_sk_rk_pete"
          "id_ed25519_sk_rk_pete-adm"
          # Legacy: only the Unraid root logins (backup, media) still use it,
          # until they get a replacement key.
          "id_ed25519_sk_rk_p22"
        ];

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
        # The Primary Key's handle first, then the Backup Key's. With the
        # Backup Key plugged in, the first one costs a wasted PIN and touch.
        "black8" = {
          HostName = "black8.p22.lan";
          User = user;
          IdentityFile = [
            "${home}/.ssh/id_ed25519_sk_rk_pete"
            "${home}/.ssh/id_ed25519_sk_rk_pete_backup"
          ];
          IdentitiesOnly = true;
          IdentityAgent = "none";
          # Multiplexing: one touch per 10 minutes rather than one per
          # command, which matters for remote builds.
          ControlMaster = "auto";
          ControlPath = "~/.ssh/control-%r@%h:%p";
          ControlPersist = "10m";
        };
        # The Unraid boxes have no kanidm: root with the legacy key until
        # they get a replacement.
        "backup" = {
          HostName = "backup.p22.lan";
          User = "root";
          IdentityFile = "${home}/.ssh/id_ed25519_sk_rk_p22";
          IdentitiesOnly = true;
          IdentityAgent = "none";
        };
        "media" = {
          HostName = "media.p22.lan";
          User = "root";
          IdentityFile = "${home}/.ssh/id_ed25519_sk_rk_p22";
          IdentitiesOnly = true;
          IdentityAgent = "none";
        };
        # idm1 accepts only Elevated Identities, so it's pete-adm there,
        # deploys included.
        "idm1" = {
          HostName = "idm1.p22.lan";
          User = "pete-adm";
          IdentityFile = [
            "${home}/.ssh/id_ed25519_sk_rk_pete-adm"
            "${home}/.ssh/id_ed25519_sk_rk_pete-adm_backup"
          ];
          IdentitiesOnly = true;
          IdentityAgent = "none";
        };
      };
    };
  };
}
