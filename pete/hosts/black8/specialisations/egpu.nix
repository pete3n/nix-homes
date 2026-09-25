# Specialisation for the RTX 3080 eGPU over Thunderbolt.
#
# GPU CONFIGURATION ONLY. An earlier version also set
# programs.hyprland.enable = lib.mkForce true, which forced the compositor on
# regardless of tags — so building any other desktop still evaluated the
# Hyprland module. The compositor is chosen by tag; this chooses a GPU.
{
  lib,
  pkgs,
  pkgsCuda,
  ...
}:
{
  specialisation.egpu.configuration = {
    # mkForce because the parent configuration already set nixpkgs.pkgs, and a
    # specialisation inherits it.
    #
    # A separate package set rather than an override: cudaSupport is a nixpkgs
    # CONFIG value that changes how every CUDA-capable derivation is built, so
    # it cannot be applied to an instance that already exists.
    nixpkgs.pkgs = lib.mkForce pkgsCuda;

    system.nixos.tags = [
      "eGPU"
      "nvidia"
      "cuda"
      "RTX-3080"
    ];

    environment.systemPackages = with pkgs; [
      cudaPackages.cudatoolkit
      nvtopPackages.nvidia
    ];

    # Stable path to the eGPU's DRM node, for anything that needs to name a
    # card rather than take the first one.
    systemd.services.egpuLink = {
      description = "Create eGPU symbolic link";
      wantedBy = [ "multi-user.target" ];
      script = ''
        ln -sf /dev/dri/card1 /run/egpu
      '';
      serviceConfig = {
        Type = "oneshot";
        # Without this the unit reports inactive after running, which reads as
        # a failure when it is the normal state for a oneshot.
        RemainAfterExit = true;
      };
    };

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      open = true;
      nvidiaSettings = true;

      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        allowExternalGpu = true;
        # Imperative: these depend on which Thunderbolt port the enclosure is
        # plugged into. `lspci | grep -E "VGA|3D"` after moving it.
        nvidiaBusId = "PCI:65:0:0";
        intelBusId = "PCI:2:0:0";
      };
    };

    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        intel-media-driver
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; [
        nvidia-vaapi-driver
        intel-media-driver
      ];
    };

    services = {
      # Triggers egpuLink when the card appears, so hotplugging the enclosure
      # does not need a reboot to get the symlink.
      udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="pci", ATTRS{vendor}=="0x10de", ATTRS{device}=="0x2216", ENV{SYSTEMD_WANTS}+="egpuLink.service", TAG+="systemd"
      '';

      xserver.videoDrivers = [
        "modesetting"
        "nvidia"
      ];

      kmscon.enable = lib.mkForce false;
    };
  };
}
