# Home-manager configuration specific to silver16
#
{ ... }:
{
  nixSpace = {
    hyprland = {
      nvidia = true;

      monitors = [
        {
          output = "eDP-1";
          mode = "preferred";
          position = "3440x0";
          scale = 1;
        }
        {
          output = "DP-2";
          mode = "preferred";
          position = "0x0";
          scale = 1;
        }
        # Catch-all for anything else plugged in, placed automatically.
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = 1;
        }
      ];
    };

    # The Framework 16's panel backlight is driven by the NVIDIA WMI interface
    # rather than an amdgpu one, so both the waybar module and powerproud need
    # the device named.
    waybar.backlight = {
      enable = true;
      device = "nvidia_wmi_ec_backlight";
    };

    services.powerproud.backlightDevice = "nvidia_wmi_ec_backlight";
  };
}
