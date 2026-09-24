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
  inputs,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  inherit (nixSpaceAttrs) host tags;
  inherit (nixSpaceLib.tags) hasTag;

  # The Lab Identity Domain's descriptor (ADR-0005) — the single source of the
  # per-domain facts step-ca needs (CA subject, node FQDN/address, endpoints).
  domain = nixSpaceLib.domainDescriptor."p22.lan";
  node = domain.nodes.${host};
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

  # Trust the domain's offline root (P22-CA). step-ca (below) runs as an
  # intermediate signed by this root, so everything it issues — including idm1's
  # own TLS — already chains under a Fleet-trusted anchor (ADR-0008). The root
  # cert stays trusted here; nothing to re-trust.
  security.pki.certificateFiles = lib.optionals (hasTag "p22" tags) [
    ../../secrets/certs/p22-ca.crt
  ];

  # Trust the p22.lan SSH Host CA: Domain hosts showing a host certificate are
  # recognised with no known_hosts entry, and short names are tried as
  # <name>.p22.lan first (ADR-0009).
  nixSpace.ssh.domainTrust.domains = lib.optional (hasTag "p22" tags) nixSpaceLib.domainDescriptor."p22.lan";

  # idm1 IS the certificate authority for the p22 Lab (Step 2). step-ca serves
  # ACME for internal TLS and holds the SSH host + user CAs. The OIDC provisioner
  # that mints user/elevated certs waits on kanidm (Step 3) — see the module.
  nixSpace.services.step-ca = {
    enable = true;
    fqdn = node.fqdn;

    # Nothing this CA issues may name anything outside the Domain.
    allowedDomains = domain.ca.allowedDomains;
    allowedAddresses = domain.ca.allowedAddresses;

    # Public certs (store paths are fine): the already-trusted root, and the
    # intermediate the operator has signed with the offline root key.
    rootCertFile = ../../secrets/certs/p22-ca.crt;
    intermediateCertFile = "${inputs.nix-space}/hosts/${host}/pki/p22-intermediate.crt";

    # Private key material: agenix targets decrypted at activation, owned by the
    # step-ca service account. Never store-path literals.
    intermediateKeyFile = config.age.secrets."step-ca/intermediate.key".path;
    intermediatePasswordFile = config.age.secrets."step-ca/intermediate.password".path;
    ssh = {
      hostCAKeyFile = config.age.secrets."step-ca/ssh_host_ca".path;
      userCAKeyFile = config.age.secrets."step-ca/ssh_user_ca".path;

      # Operator-held JWK provisioner for each host's FIRST host cert; renewals
      # then go through SSHPOP (ADR-0009). Both files are public (the private
      # key is password-encrypted, and the password stays with the operator).
      hostProvisioner = {
        publicKeyFile = "${inputs.nix-space}/hosts/${host}/pki/hosts-provisioner.pub.json";
        encryptedKeyFile = "${inputs.nix-space}/hosts/${host}/pki/hosts-provisioner.key.jwe";
      };
    };
  };

  # idm1 presents its own SSH host certificate, renewed daily against its own
  # step-ca. The first cert is operator-signed (see the host-cert sheet).
  nixSpace.services.ssh-host-cert = {
    enable = true;
    caUrl = domain.ca.url;
    rootCertFile = ../../secrets/certs/p22-ca.crt;
  };

  # The CA's private material, encrypted to idm1's host key + pete's YubiKeys
  # (rules in nix-space/hosts/idm1/secrets/secrets.nix). The .age files are
  # produced by the Step 2 bootstrap and committed under nix-space.
  age.secrets =
    let
      caSecret = name: {
        file = "${inputs.nix-space}/hosts/${host}/secrets/${name}.age";
        owner = config.nixSpace.services.step-ca.user;
        mode = "0400";
      };
    in
    {
      "step-ca/intermediate.key" = caSecret "step-ca/intermediate.key";
      "step-ca/intermediate.password" = caSecret "step-ca/intermediate.password";
      "step-ca/ssh_host_ca" = caSecret "step-ca/ssh_host_ca";
      "step-ca/ssh_user_ca" = caSecret "step-ca/ssh_user_ca";
    };

  # Trust the SSH USER CA now, so idm1 accepts user certificates the moment
  # Step 3's OIDC provisioner starts minting them — no later Nix edit needed to
  # grant access (ADR-0003). The public key is a committed, non-secret file.
  services.openssh.settings.TrustedUserCAKeys =
    "${inputs.nix-space}/hosts/${host}/pki/ssh_user_ca.pub";

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
