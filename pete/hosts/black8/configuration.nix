# black8 system configuration
# Baseline hardware configuration loaded by the flake from:
# ${nixSpace}/hosts/${host}
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
  inherit (nixSpaceAttrs) host tags;
  inherit (nixSpaceLib.tags) hasTag;
in
{
  imports = [
    ./secrets.nix
    ./specialisations.nix
  ];

  system.nixos.tags = [
    "nixSpace"
    "migration"
    "Hyprdesktop"
  ];

  documentation = {
    man.enable = true;
    man.cache.enable = true;
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_6_18;
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [ "ntfs" ];
  };

  hardware.enableRedistributableFirmware = true;

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Keep build dependencies and derivations for offline rebuilds. Less
    # aggressive than system.includeBuildDependencies, which multiplies the
    # closure.
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
  };

  # The p22 internal CA. Trusted root cert, means this machine accepts anything
  # that CA signs.
  security.pki.certificateFiles = lib.optionals (hasTag "p22" tags) [ ../../secrets/certs/p22-ca.crt ];

  # Trust the p22.lan SSH Host CA: Domain hosts showing a host certificate are
  # recognised with no known_hosts entry, and short names are tried as
  # <name>.p22.lan first (ADR-0009).
  nixSpace.ssh.domainTrust.domains = lib.optional (hasTag "p22" tags) nixSpaceLib.domainDescriptor."p22.lan";

  # black8 presents an SSH host certificate for black8.p22.lan, renewed daily
  # against idm1's step-ca. The operator signs the first cert (see the
  # host-cert sheet).
  nixSpace.services.ssh-host-cert = lib.mkIf (hasTag "p22" tags) {
    enable = true;
    caUrl = nixSpaceLib.domainDescriptor."p22.lan".ca.url;
    rootCertFile = ../../secrets/certs/p22-ca.crt;
  };

  nixSpace = {
    nix = {
      cache = {
        enable = true;
        substituters =
          lib.optional (hasTag "p22" tags) {
            # nginx pass-through for cache.nixos.org and nix-community. No
            # publicKey: it re-serves upstream-signed paths and signs nothing
            # itself.
            url = "http://backupsvr.p22:8000/";
          }
          ++ [
            {
              url = "https://nix-community.cachix.org/";
              publicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
            }
          ];
      };

      buildHost = {
        enable = true;
        authorizedKeys = [
          # Primary YubiKey
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEFU2BKDdywiMqeD7LY8lgKeBo0mjHEyP7ej+Y2JNuJDAAAABHNzaDo= pete@framework16"
          # Backup YubiKey
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHwNQ411TYRwGAGINX4i4FI7Ek7lfTQv0s8vbXmnqVh/AAAABHNzaDo= pete@framework16"
          # Nix daemon builder key
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKDa64nzci/B0UqrvqJxmzVJgI3c7f8LD48x3UBwD8jQ remotebuild@p22"
        ];
      };
    };

    # Cross-architecture builds for the Pi and any aarch64 target, through
    # qemu-user and binfmt rather than a full system emulator. This is what
    # makes black8 useful as a builder for hosts it does not share an
    # architecture with.
    virtualisation = {
      enable = hasTag "virtualisation" tags;
      emulatedSystems = [
        "aarch64-linux"
        "armv7l-linux"
      ];
      libvirt.enable = true;
      docker.mode = "system";
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

        # Vulkan instance for the Radeon 8060S
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
    };
  };

  networking = {
    hostName = host;

    # Static, because this machine is a build target and an NFS client that
    # other hosts name by address as well as by DNS.
    useDHCP = false;
    nameservers = [ ]; # resolved handles it

    wireless.enable = false;
    networkmanager.enable = false;

    # net10g is enslaved to br0 so VM guests (idm1) can attach to the p22 LAN
    # at layer 2 and get real LAN addresses. black8's own static IP moves onto
    # the bridge; net10g itself carries no address. libvirt creates guest taps
    # on br0 directly, so no qemu-bridge-helper is involved.
    bridges.br0.interfaces = [ "net10g" ];
    interfaces.br0.ipv4.addresses = [
      {
        address = "192.168.1.8";
        prefixLength = 24;
      }
    ];
    defaultGateway = {
      address = "192.168.1.1";
      interface = "br0";
    };
  };

  age.secrets = lib.optionalAttrs (hasTag "crypto" tags) {
    bitcoind-rpc-hmac = {
      file = ../../secrets/bitcoind-rpc-hmac.age;
      owner = config.nixSpace.services.bitcoind.user;
      mode = "0400";
    };
  };

  systemd.network.links."10-net10g" = {
    matchConfig.MACAddress = "34:c8:d6:b3:05:6f";
    linkConfig.Name = "net10g";
  };

  services = {
    hardware.bolt.enable = true; # boltctl, for the Thunderbolt enclosure
    udisks2.enable = true;

    resolved = {
      enable = true;
      settings.Resolve = {
        DNSSEC = "allow-downgrade";
        DNSOverTLS = "opportunistic";
        DNS = [ "192.168.1.1" ];
        Domains = [ "~p22" ];
        FallbackDNS = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
    };

    openssh = {
      enable = true;
      ports = [ 22 ];
      hostKeys = [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
      settings = {
        PubkeyAuthentication = true;
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        UseDns = true;
        X11Forwarding = false;
        AllowAgentForwarding = false;
        PermitTunnel = "no";
      };
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    fwupd.enable = true;
    power-profiles-daemon.enable = true;
  };

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    # AMD iGPU inspection
    amdgpu_top
    clinfo
    mesa-demos
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
    vulkan-tools

    # Disk and firmware tooling, kept at system level so it is reachable from
    # a rescue boot where the user profile is not.
    cryptsetup
    gptfdisk
    nvme-cli
    parted
    smartmontools
  ];

  # https://nixos.org/nixos/options.html — read before changing.
  system.stateVersion = "24.05";
}
