# silver16 system configuration
# Baseline hardware configuration loaded by the flake from:
# ${nixSpace}/hosts/${host}
#
{
  config,
  lib,
  inputs,
  pkgs,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:

let
  inherit (nixSpaceAttrs) host tags;
  inherit (nixSpaceLib.tags) hasTag;
in
{
  imports = [
		./secrets.nix
		./specialisations.nix
  ]
  ++ [ inputs.nix-slop-dev.nixosModules.sandboxed ];

  system.nixos.tags = [
    "nixSpace"
    "Hyprdesktop"
  ];

  documentation = {
    man.enable = true;
    man.cache.enable = true;
  };

  boot = {
    # Reserve 44Gb of unified memory of iGPU for local LLM
    kernelParams = lib.optionals (hasTag "local-ai" tags) [
      "ttm.pages_limit=11534336"
      "ttm.page_pool_size=11534336"
    ];

    # Removable CD-ROM support
    kernelModules = [
      "sg"
    ];

    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_7_0; -- MLO for WiFi7 broken
    kernelPackages = pkgs.linuxPackages_6_18;
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [ "ntfs" ];
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    # Extra options to keep build dependencies and derivatives for offline builds.
    # This is less aggressive than the system.includeBuildDependencies = true option
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
  };

  # The p22 internal CA. Trusted root cert, means this machine accepts anything
  # that CA signs.
  security.pki.certificateFiles = lib.optionals (hasTag "p22" tags) [ ../secrets/certs/p22-ca.crt ];

  age = {
    # Build key for remote build machines
    secrets =
      lib.optionalAttrs (hasTag "p22" tags) {
        p22-build-key = {
          file = "${inputs.nixSpace}/hosts/${host}/secrets/p22-build-key.age";
          path = "/etc/nix/p22-build-key";
          owner = "root";
          group = "root";
          mode = "0400";
        };
      }
      // lib.optionalAttrs (hasTag "crypto" tags) {
        bitcoind-rpc-hmac = {
          file = ../secrets/bitcoind-rpc-hmac.age;
          owner = config.nixSpace.services.bitcoind.user;
          mode = "0400";
        };
      };
  };

  nixSpace = {
    nix.remoteBuilders = {
      enable = true;
      machines.black8 = {
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO70Au6FegohwKFygshDnN9TGll69m4cc1WXMqa8tXl/";
        system = "x86_64-linux";
        sshKeyFile = config.age.secrets.p22-build-key.path;
        maxJobs = 28;
        speedFactor = 4;
      };
    };

    virtualisation = {
      enable = true;
      emulatedSystems = [
        "aarch64-linux"
        "armv7l-linux"
      ];
    };

    networking.firewall = {
      enable = true;
      hostServicesFromContainers.tcpPorts = [
        11434
        11435
      ];
    };

    security = {
      yubikey = {
        enable = true;

        # yubikey-pam-u2f.nix minus its global enable. Same origin and appid, so
        # nothing is re-enrolled; users = {} keeps reading ~/.config/Yubico/u2f_keys.
        u2f = {
          enable = true;
          # P22 tag
          origin = "pam://p22";
        };

        # The global enable put u2f on EVERY service. These are the ones that had
        # it and matter; unlisted services lose it, visibly, in the diff.
        # fprint = true keeps the fingerprint nixpkgs was already giving them.
        pam.services = lib.mkIf (hasTag "laptop" tags) {
          sudo = {
            fprint = true;
            password = false;
          };
          login = {
            fprint = true;
          };
          polkit-1 = {
            fprint = true;
          };
          hyprlock = {
            fprint = true;
          };
        };
      };
    };

    services = {
      nfsMount = lib.mkIf (hasTag "p22" tags) {
        enable = true;
        server = "backupsvr.p22";
        shares = {
          share.remotePath = "/mnt/user/share";
          open.remotePath = "/mnt/user/open";
        };
      };

      ollama = lib.mkIf (hasTag "local-ai" tags) {
        enable = true;
        package = if hasTag "cuda" tags then pkgs.unstable.ollama-cuda else pkgs.unstable.ollama;
        modelPath = "/data/ollama/models";

        # Vulkan instance for FW16 Radeon 890M
        extraInstances = {
          vulkan = {
            package = pkgs.unstable.ollama-vulkan;
            port = 11435;
            environment = {
              CUDA_VISIBLE_DEVICES = "-1";
              OLLAMA_IGPU_ENABLE = "1";
              OLLAMA_VULKAN = "1";
              VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
            };
          };
        };
      };

      llama-reranker = lib.mkIf (hasTag "local-ai" tags) {
        enable = true;
        model = "/data/llama-cpp/BGE-Reranker-v2-M3-Q8_0.gguf";
        alias = "bge-reranker-v2-m3";
      };

      openWebui = lib.mkIf (hasTag "local-ai" tags) {
        enable = true;
        backends = [
          "http://127.0.0.1:11434"
          "http://127.0.0.1:11435"
        ];
      };

      bitcoind = lib.mkIf (hasTag "crypto" tags) {
        enable = true;
        dataDir = "/data/bitcoind";
        prune = 102400;
        extraConfigFiles = [ config.age.secrets.bitcoind-rpc-hmac.path ];
      };

      monero = lib.mkIf (hasTag "crypto" tags) {
        enable = true;
        dataDir = "/data/monero";
        prune = true;
      };

      # FW16 HW Quirks
      fw16KbdAlsd.enable = true;
      fw16WakeTriggers.enable = true;
      fw16PortRecovery = {
        enable = true;
        mainboard = "AI_300";
      };
      fw16UcsiRebind.enable = true;

      lidmond = {
        enable = true;
        accessGroup = "wheel";
      };

    };
  };

  networking = {
    hostName = host;
    useDHCP = true;
    dhcpcd = {
      wait = "if-carrier-up"; # block only for interfaces that have link
      enable = true;
    };
    nameservers = [ ]; # Use resolved

    # Disable all wireless by default (use wpa_supplicant manually)
    wireless.enable = false;
    networkmanager.enable = false;

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  };

  # yubikey-pam-fprint.nix's fprintd timing, interim until pam.nix has
  # fprintTimeout / fprintMaxTries. Rides on nixpkgs' own fprintd rule the
  # way the module rides on the u2f rule; nothing is redefined.
  security.pam.services.sudo.rules.auth.fprintd.settings = {
    "max-tries" = 1;
    timeout = 3;
  };

  services = {
    # yubikey-pam-fprint.nix used to enable this. The module asserts on it
    # rather than owning it (hardware belongs to the chassis), so it must be
    # declared here or the fprint policy below fails to evaluate.
    fprintd.enable = true;

    udisks2.enable = true;

    resolved = {
      enable = true;
      settings.Resolve = {
        DNSSEC = "allow-downgrade";
        DNSOverTLS = "opportunistic";
        DNS = [ "192.168.1.1" ];
        Domains = [ "p22" ];
        FallbackDNS = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
    };

    # Generate system public key
    openssh = {
      enable = true;
      hostKeys = [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
    };

    # Power and thermal management
    thermald.enable = true;
    upower.enable = true;
    power-profiles-daemon.enable = true;

    # Audio
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    # Firmware update
    fwupd.enable = true;

    # boltctl
    hardware.bolt.enable = true;
  };

  # nix-slop-dev llm-agent sandboxed config
  security.sandboxed = {
    enable = true;
    users = [ nixSpaceAttrs.user ];
  };

  ### Fonts and Locale ###
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/New_York";

  # Framework16 specific system packages -- sort of
  # Common packages imported from ../shared-imports/linux/system-packages.nix
  environment.systemPackages = with pkgs; [
    amdgpu_top
    cryptsetup
    framework-tool
    framework-tool-tui
    fw-ectool
    git
    gparted
    gptfdisk
    mesa-demos
    nvme-cli
    nvtopPackages.amd
    parted
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
    smartmontools
    vim
    vulkan-tools
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
