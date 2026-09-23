{
  user = "pete";
  host = "idm1";
  system = "x86_64-linux";

  # First host of the headless server archetype: no desktop, no per-user home.
  archetype = "server";

  # A libvirt/QEMU-KVM virtio guest, hosted on black8's libvirtd.
  chassis = "libvirt-vm";

  # Build on the local machine, activate over SSH. The guest is a first-class
  # managed host: after the one-time image build + libvirt import, updates ship
  # with `nixos-rebuild --target-host`.
  deployMode = "remote";

  isHomeAlone = false;
  useHomebrew = false;

  # INTERIM bootstrap access, valid until the identity plane exists. `ssh-user`
  # authorizes the YubiKey below; `sudo-user` puts pete in wheel so the remote
  # deploy can `--use-remote-sudo`. ADR-0001's Standard/Elevated identities
  # (build-step 6) replace this — idm1 will then get its accounts from kanidm,
  # not from this file.
  tags = [
    "ssh-user"
    "sudo-user"
    # Deploy account must be a nix trusted-user, or `nixos-rebuild
    # --target-host` cannot copy an unsigned closure to idm1 (the daemon
    # rejects unsigned paths from untrusted users). Same as pete on black8.
    "trusted-user"
    "p22"
  ];

  sshPubKeys = [
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIH0sKLi0IwMU62lLAEBiPudg4OxqQGY1n3MOsV8rAJybAAAAB3NzaDpwMjI= ssh:p22"
  ];
}
