# Overlays specific to this machine set: packages built here, and workarounds
# for upstream defects on this hardware. Neither belongs in nixSpace — the
# library has never heard of them, and a consumer without this hardware should
# not carry the workarounds.
#
# The library's shared overlays are pulled in below rather than restated, so
# there is one definition of pkgs.unstable and pkgs.nsPkgs across every
# consumer.
{
  inputs,
  lib,
  nixSpaceLib,
  nixSpaceAttrs ? null,
  ...
}:
let
  nsOverlays = import "${inputs.nix-space}/overlays" {
    inherit lib nixSpaceLib nixSpaceAttrs;
    inherit (inputs) nixpkgs-unstable;
  };

  # Packages built in this repo, reachable as pkgs.local.
  local-packages = final: _prev: {
    local = import ../packages {
      pkgs = final;
      inherit nixSpaceLib nixSpaceAttrs;
    };
  };
  # Upstream packages modified for this hardware, reachable as pkgs.mod.
  #
  # Each entry should carry the defect it works around and a link, so that it
  # can be DELETED when upstream catches up rather than being carried forever
  # because nobody remembers why it exists.
  #
  # Reads `final.unstable`, not `prev.unstable` — the fixpoint resolves it
  # regardless of overlay order, so this no longer has to be applied last and
  # no longer needs a guard asserting that unstable was applied first. The old
  # guard also required `local`, which nothing here uses.
  mod-packages = final: _prev: {
    mod = {
      # Electron's GPU process fails on this AMD hardware with
      #   Cannot find target for triple amdgcn--
      # and the window renders blank. Forcing software GL is the workaround.
      #   https://github.com/signalapp/Signal-Desktop/issues/6855
      #
      # --password-store is pinned so Electron does not pick a keyring by
      # detecting the desktop environment. It chose kwallet6 under Plasma and
      # then could not read its own key back under Hyprland; the database had
      # to be reset. Electron records the backend on first key creation and
      # does not migrate, so this flag only governs new keys.
      #
      # --use-tray-icon is passed but currently does nothing: tray integration
      # is broken upstream as of 8.24/8.25 across multiple distributions, and
      # the in-app "minimize to tray" settings are ignored too.
      #   https://github.com/signalapp/Signal-Desktop/issues/8007
      # Kept because it is correct and will work again when upstream fixes it.
      no-gpu-signal-desktop = final.unstable.signal-desktop.overrideAttrs (oldAttrs: {
        installPhase = oldAttrs.installPhase + ''
          wrapProgram $out/bin/signal-desktop \
            --set LIBGL_ALWAYS_SOFTWARE 1 \
            --set ELECTRON_DISABLE_GPU true \
            --add-flags "--password-store=basic_text" \
            --add-flags "--use-tray-icon"
        '';
      });

      # Defaults to the Wayland Qt platform, which it does not render
      # correctly under. Forcing xcb puts it through XWayland.
      _86box = final._86box-with-roms.overrideAttrs (oldAttrs: {
        preFixup = oldAttrs.preFixup + ''
          makeWrapperArgs+=(--set QT_QPA_PLATFORM "xcb")
        '';
      });
    };
  };
in
{
  inherit local-packages mod-packages;
  inherit (nsOverlays) unstable-packages nix-space-packages;

  all = nsOverlays.shared ++ [
    (nsOverlays.pins.hyprland inputs.Hyprland)
    local-packages
    mod-packages
  ];
}
