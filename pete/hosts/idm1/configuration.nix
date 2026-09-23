# idm1 — first Identity Node (idm) for the p22 Lab.
#
# Headless server archetype. The archetype module (server.nix) supplies the
# SSH posture (key-only, no root login, no agent forwarding — ADR-0001) and
# turns openssh on; the libvirt-vm chassis module supplies the virtio/guest
# hardware. This file is just what is specific to idm1: its network identity,
# time sync, CA trust, and interim bootstrap access.
#
# What runs ON idm1 — step-ca, then kanidm — arrives in later build steps. For
# now this is a reachable, time-synced, trusted base to build them on.
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
  system.nixos.tags = [
    "nixSpace"
    "idm"
  ];

  boot.tmp.cleanOnBoot = true;

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  networking = {
    hostName = host;
    # ADR-0005: the Lab Identity Domain is anchored on p22.lan (a bare .p22 is
    # not a valid WebAuthn RP-ID). idm1's FQDN is therefore idm1.p22.lan — how
    # the Fleet will name this node.
    domain = "p22.lan";

    # The infrastructure VLAN has no DHCP server — every host is statically
    # assigned — so idm1 carries its own address. OPNsense holds the matching
    # idm1.p22.lan record. useDHCP off overrides the mkDefault in
    # hardware-configuration.nix.
    useDHCP = false;
    useNetworkd = true;
    wireless.enable = false;
    networkmanager.enable = false;
    nameservers = [ ]; # resolved handles it
  };

  # Static address on the guest's single ethernet NIC, matched by type rather
  # than name so it binds whatever the hypervisor calls it (enp0s8 under the
  # silver16 quickemu smoke test, a virtio name under black8's libvirt).
  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = [ "192.168.1.11/24" ];
    routes = [ { Gateway = "192.168.1.1"; } ];
  };

  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "allow-downgrade";
      DNS = [ "192.168.1.1" ];
      # New p22.lan identity zone, plus the existing flat p22 names (backupsvr
      # etc.) idm1 still needs to reach during the Lab build.
      Domains = [
        "~p22.lan"
        "~p22"
      ];
      FallbackDNS = [
        "1.1.1.1"
        "8.8.8.8"
      ];
    };
  };

  # A certificate authority and a passkey directory both live or die by the
  # clock. Sync against OPNsense (the LAN NTP server for build-step 1).
  services.timesyncd = {
    # mkDefault so the build-vm variant (which disables timesyncd) can override
    # without a priority clash. On the real host nothing else sets it, so it
    # stays enabled.
    enable = lib.mkDefault true;
    servers = [ "192.168.1.1" ];
  };

  # Trust the existing p22 CA, so idm1 can reach internal TLS services. idm1
  # will later BECOME the CA (step-ca), but that is a later build step.
  security.pki.certificateFiles = lib.optionals (hasTag "p22" tags) [
    ../../secrets/certs/p22-ca.crt
  ];

  # INTERIM bootstrap: passwordless sudo for wheel so the remote deploy
  # (`nixos-rebuild --target-host pete@idm1.p22 --use-remote-sudo`) works
  # before the identity plane exists. ADR-0001's elevated-session model
  # supersedes this at build-step 6.
  security.sudo.wheelNeedsPassword = false;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    # Minimal operator toolkit for a headless box reached over serial/SSH.
    curl
    dnsutils
    git
    tmux
  ];

  # https://nixos.org/nixos/options.html — read before changing. Set to the
  # release idm1 is first installed with; do not bump it on upgrade.
  system.stateVersion = "25.05";
}
