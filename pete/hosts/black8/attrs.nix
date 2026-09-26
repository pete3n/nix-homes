{
  user = "pete";
  host = "black8";
  chassis = "framework-dt";
  system = "x86_64-linux";
  isHomeAlone = false;
  useHomebrew = false;
  tags = [
    "crypto"
    "cuda"
    "gaming"
    "git-ssh-user"
    "hw-nvidia-dgpu"
    "hw-amd-igpu"
    "hyprland"
    "hyprdesktop"
    "local-ai"
    "media-creation"
    "messaging"
    "mpd"
    "nixvim"
    "office"
    "p22"
    "power-user"
    "rocm"
    "ssh-user"
    "virtualisation"
    "vm-user"
    "yubi-age-user"
    "yubi-ssh-import"
    "yubi-u2f"
  ];

  specialisations = [
    "egpu"
  ];

  sshPubKeys = [
    #Primary Yubikey
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIJFGmlG/CcvESUuFCGx66DyW9GUqWoMR+Almk1i+E98CAAAACHNzaDpwZXRl pete-primary@p22.lan"
    #Backup Yubikey
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAICjaf/0nEezgVctqf3IkMC3T6oeS6RP3ap1owC939VgWAAAACHNzaDpwZXRl pete-backup@p22.lan"
  ];
}
