# idm1 - first Identity Node (idm) for the p22 Lab.
#
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

  # The Lab Identity Domain's descriptor.
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
    domain = "p22.lan";
    useDHCP = false;
    useNetworkd = true;
    wireless.enable = false;
    networkmanager.enable = false;
    nameservers = [ ]; # resolved handles it
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = [ "192.168.1.11/24" ];
    routes = [ { Gateway = "192.168.1.1"; } ];
  };

  services = {
    resolved = {
      enable = true;
      settings.Resolve = {
        DNSSEC = "allow-downgrade";
        DNS = [ "192.168.1.1" ];
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

    timesyncd = {
      # mkDefault so the build-vm variant (which disables timesyncd) can override
      # without a priority clash. On the real host nothing else sets it, so it
      # stays enabled.
      enable = lib.mkDefault true;
      servers = [ "192.168.1.1" ];
    };
  };

  # Trust the domain's offline root (P22-CA). step-ca (below) runs as an
  # intermediate signed by this root.
  security.pki.certificateFiles = lib.optionals (hasTag "p22" tags) [
    ../../secrets/certs/p22-ca.crt
  ];

  # Trust the p22.lan SSH Host CA: Domain hosts showing a host certificate are
  # recognised with no known_hosts entry, and short names are tried as
  # <name>.p22.lan first.
  nixSpace.ssh.domainTrust.domains = lib.optional (hasTag "p22" tags) nixSpaceLib.domainDescriptor."p22.lan";

  # idm1 IS the certificate authority for the p22 Lab. step-ca serves
  # ACME for internal TLS and holds the SSH host + user CAs.
  nixSpace.services = {
    step-ca = {
      enable = true;
      inherit (node) fqdn;

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

        # Operator-held JWK provisioner for each host's first host cert; renewals
        # then go through SSHPOP.
        hostProvisioner = {
          publicKeyFile = "${inputs.nix-space}/hosts/${host}/pki/hosts-provisioner.pub.json";
          encryptedKeyFile = "${inputs.nix-space}/hosts/${host}/pki/hosts-provisioner.key.jwe";
        };
      };
    };

    # idm1's own TLS cert (idm1.p22.lan) from its own step-ca over ACME, 7-day
    # lifetime.
    internal-acme = {
      enable = true;
      directoryUrl = domain.ca.acmeDirectory;
      certs = [ node.fqdn ];
    };

    # idm1 presents its own SSH host certificate, renewed daily against its own
    # step-ca. The first cert is admin-signed.
    ssh-host-cert = {
      enable = true;
      caUrl = domain.ca.url;
      rootCertFile = ../../secrets/certs/p22-ca.crt;
    };
  };

  # The CA's private material, encrypted to idm1's host key + admin's YubiKeys
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

  # Trust the SSH USER CA now.
  services.openssh.settings.TrustedUserCAKeys = "${inputs.nix-space}/hosts/${host}/pki/ssh_user_ca.pub";

  # Bootstrap: passwordless sudo for wheel so the remote deploy
  # (`nixos-rebuild --target-host pete@idm1.p22 --use-remote-sudo`) works
  # before the identity plane exists.
  security.sudo.wheelNeedsPassword = false;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    curl
    dnsutils
    git
    tmux
  ];

  # https://nixos.org/nixos/options.html — read before changing. Set to the
  # release idm1 is first installed with; do not bump it on upgrade.
  system.stateVersion = "25.05";
}
