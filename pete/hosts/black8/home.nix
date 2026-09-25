# Home-manager configuration specific to black8
#
_: {
  nixSpace = {
    hyprland = {
      # The eGPU is only present in the egpu specialisation, but this option
      # describes the hardware rather than the boot path.
      nvidia = true;

      monitors = [
        # TODO: replace with this machine's actual outputs. The catch-all
        # places everything automatically in the meantime.
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = 1;
        }
      ];
    };
  };
}
