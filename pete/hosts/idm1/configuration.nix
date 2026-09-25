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

    kanidm = {
      # The kanidm and kanidmd commands, for the bootstrap and account recovery.
      client.enable = true;

      # People and groups in kanidm, and the two OAuth2 clients step-ca trusts.
      # Passkeys can't be declared: each person enrolls theirs once, from a
      # reset link (see the bootstrap sheet).
      provision =
        let
          inherit (domain.groups) admins sshUsers;

          # `step ssh login` catches the browser on this local address when kanidm
          # sends it back. It matches the provisioners' listenAddress.
          loginRedirect = "http://127.0.0.1:10000";

          # One public client per step-ca provisioner. Only members of `groups` get
          # a token at all, and the ssh_groups claim tells step-ca which of those
          # groups the person is in.
          stepClient = displayName: groups: {
            inherit displayName;
            public = true;
            enableLocalhostRedirects = true;
            preferShortUsername = true;
            originUrl = [
              loginRedirect
              "http://localhost:10000"
            ];
            originLanding = loginRedirect;
            scopeMaps = lib.genAttrs groups (_group: [
              "openid"
              "email"
              "profile"
            ]);
            claimMaps.ssh_groups.valuesByGroup = lib.genAttrs groups (group: [ group ]);
          };
        in
        {
          enable = true;

          groups = {
            ${admins} = { };
            ${sshUsers} = { };
          };

          # Standard and Elevated identities for the same person. Only the
          # Elevated one is in `admins`.
          persons = {
            pete = {
              displayName = "Pete";
              mailAddresses = [ "pete@p22.lan" ];
              groups = [ sshUsers ];
            };
            pete-adm = {
              displayName = "Pete (admin)";
              mailAddresses = [ "pete-adm@p22.lan" ];
              groups = [ admins ];
            };
          };

          systems.oauth2 = {
            ${domain.oidc.standard.clientId} = stepClient "SSH certificates" [ sshUsers ];
            ${domain.oidc.elevated.clientId} = stepClient "SSH admin certificates" [ admins ];
          };
        };
    };
  };

  # Trust the domain's offline root (P22-CA). step-ca (below) runs as an
  # intermediate signed by this root.
  security.pki.certificateFiles = lib.optionals (hasTag "p22" tags) [
    ../../secrets/certs/p22-ca.crt
  ];

  nixSpace = {
    # Trust the p22.lan SSH Host CA: Domain hosts showing a host certificate are
    # recognised with no known_hosts entry, and short names are tried as
    # <name>.p22.lan first.
    ssh.domainTrust.domains = lib.optional (hasTag "p22" tags) nixSpaceLib.domainDescriptor."p22.lan";

    # idm1 IS the certificate authority for the p22 Lab. step-ca serves
    # ACME for internal TLS and holds the SSH host + user CAs.
    services = {
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

          # User certs, only after a kanidm login. Everyday certs last a working
          # day; admin certs last an hour and need a fresh login as `-adm`.
          userProvisioners = [
            {
              name = "kanidm";
              kind = "standard";
              inherit (domain.oidc.standard) clientId configurationEndpoint;
              certDuration = "16h";
              defaultCertDuration = "12h";
              adminGroup = domain.groups.admins;
            }
            {
              name = "kanidm-elevated";
              kind = "elevated";
              inherit (domain.oidc.elevated) clientId configurationEndpoint;
              certDuration = "1h";
              defaultCertDuration = "1h";
              adminGroup = domain.groups.admins;
            }
          ];
        };
      };

      # kanidm, the directory, served with idm1's internal ACME cert.
      kanidm-server = {
        enable = true;
        package = pkgs.kanidm_1_8;
        inherit (node) fqdn;
        inherit (domain) domain;
        inherit (domain.idm) origin;
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

    # Only elevated sessions log in here with a cert: idm1 holds the CA keys.
    # This also brings the SSH User CA trust.
    identity.login = {
      enable = true;
      inherit domain;
      acceptGroups = [ domain.groups.admins ];
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
