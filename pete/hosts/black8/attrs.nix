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
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIH0sKLi0IwMU62lLAEBiPudg4OxqQGY1n3MOsV8rAJybAAAAB3NzaDpwMjI= ssh:p22"
  ];
}
