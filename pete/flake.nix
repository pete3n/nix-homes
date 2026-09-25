{
  inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605";
    nixpkgs-unstable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

    nix-darwin = {
      url = "https://flakehub.com/f/nix-darwin/nix-darwin/0.2605";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "https://flakehub.com/f/nix-community/home-manager/0.2605.6823";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-space = {
      url = "git+https://github.com/pete3n/nix-space.git?ref=main&shallow=1";
      flake = false;
    };

    # TODO: Finish porting userspace inputs
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # https://flakehub.com/f/hyprwm/Hyprland/0.55.4 is a RANGE not a version pin.
    Hyprland.url = "https://flakehub.com/f/hyprwm/Hyprland/=0.56.1";

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "Hyprland";
    };

    nix-slop-dev.url = "github:pete3n/nix-slop-dev";

    nixvim = {
      url = "github:pete3n/nixvim-flake?ref=nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprcursor.url = "github:hyprwm/hyprcursor";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.darwin.follows = "nix-darwin";
    };
  };

  outputs =
    {
      determinate,
      nixpkgs,
      home-manager,
      nix-darwin,
      nix-space,
      self,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      nixSpaceLib = import "${nix-space}/lib" { inherit lib; };
      inherit (nixSpaceLib.tags) hasTag;

      systemModules = "${nix-space}/system-modules";
      homeModules = "${nix-space}/home-modules";

      # Each host directory holds attrs.nix plus its configuration and home files.
      hostNames = [
        "black8"
        "idm1"
        "metallic1"
        "silver16"
      ];
      hostAttrs = lib.genAttrs hostNames (host: nixSpaceLib.attrs.fromFile ./hosts/${host}/attrs.nix);
      systems = lib.unique (lib.mapAttrsToList (_: attr: attr.system) hostAttrs);

      # User supplied overlays
      overlays = (import ./overlays { inherit inputs lib nixSpaceLib; }).all;

      # One package set per target system, so two hosts of the same
      # architecture share an instance rather than evaluating nixpkgs twice.
      pkgsFor = lib.genAttrs systems (
        system:
        import nixpkgs {
          inherit system overlays;
          config.allowUnfree = true;
        }
      );

      # cudaSupport is a nixpkgs config value, not an overlay: it changes how
      # every CUDA-capable derivation is built, so it cannot be applied to an
      # instance that already exists.
      #
      # Expect a large local build: this will rebuild from source anything the
      # binary cache doesn't already have built for CUDA.
      pkgsCudaFor = lib.genAttrs (lib.filter nixSpaceLib.platform.isLinux systems) (
        system:
        import nixpkgs {
          inherit system overlays;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        }
      );

      specialArgsFor =
        host:
        let
          attrs = hostAttrs.${host};
        in
        {
          inherit inputs self nixSpaceLib;
          nixSpaceAttrs = attrs;
        }
        // lib.optionalAttrs (nixSpaceLib.platform.isLinux attrs.system) {
          pkgsCuda = pkgsCudaFor.${attrs.system};
        };

      mkNixosConfiguration =
        host:
        let
          attrs = hostAttrs.${host};
          inherit (attrs) tags;
        in
        lib.nixosSystem {
          # specialArgs, not _module.args, because an `imports` list would
          # cause infinite recursion.
          specialArgs = specialArgsFor host;

          modules = [
            # Preferred over the deprecated top-level `system =` argument.
            { nixpkgs.hostPlatform = attrs.system; }
            { nixpkgs.pkgs = pkgsFor.${attrs.system}; }

            determinate.nixosModules.default
            inputs.agenix.nixosModules.default
            systemModules
            # This contains hardware specific configurations for a system
            # that users should generally not touch.
            "${nix-space}/hosts/${host}"
            ./hosts/${host}/configuration.nix

            # Configure relevant system tags here
            {
              nixSpace.hyprland.enable = hasTag "hyprland" tags;
              nixSpace.plasma.enable = hasTag "plasma" tags;
            }
            (
              { lib, pkgs, ... }:
              {
                system.activationScripts.agenixInstall.text = lib.mkBefore ''
                  export PATH=${pkgs.age-plugin-yubikey}/bin:${pkgs.age}/bin:$PATH
                '';
              }
            )
          ];
        };

      mkDarwinConfiguration =
        host:
        let
          attrs = hostAttrs.${host};
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = specialArgsFor host;
          modules = [
            { nixpkgs.hostPlatform = attrs.system; }
            { nixpkgs.pkgs = pkgsFor.${attrs.system}; }
            inputs.agenix.darwinModules.default
            inputs.determinate.darwinModules.default
            # The darwin entry point, not systemModules: NixOS and nix-darwin
            # are separate module systems and never share an evaluation.
            "${nix-space}/system-modules/darwin.nix"
            ./hosts/${host}/configuration.nix
          ];
        };

      mkHomeConfiguration =
        host:
        let
          attrs = hostAttrs.${host};
          inherit (attrs) tags;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor.${attrs.system};
          extraSpecialArgs = specialArgsFor host;
          modules = [
            homeModules
            ./home.nix

            # Configure relevant home-manager tags here
            {
              nixSpace = {
                aerospace.enable = hasTag "aerospace" tags;
                hyprland.enable = hasTag "hyprland" tags;
                hyprdesktop.enable = hasTag "hyprdesktop" tags;
                plasmadesktop.enable = hasTag "plasmadesktop" tags;
              };
            }
          ]
          ++ lib.optional (nixSpaceLib.platform.isLinux attrs.system) ./home-linux.nix
          ++ lib.optional (nixSpaceLib.platform.isDarwin attrs.system) ./home-darwin.nix
          # Host specific home configuration settings, such as display layout.
          ++ [ ./hosts/${host}/home.nix ];
        };

      linuxHosts = lib.filter (host: nixSpaceLib.platform.isLinux hostAttrs.${host}.system) hostNames;
      darwinHosts = lib.filter (host: nixSpaceLib.platform.isDarwin hostAttrs.${host}.system) hostNames;

      # Only workstations get a home-manager configuration. A server archetype
      # is headless with no per-user desktop, so building one for it is both
      # meaningless and would drag in desktop modules it must not have.
      homeHosts = lib.filter (
        host: nixSpaceLib.archetype.isWorkstation hostAttrs.${host}.archetype
      ) hostNames;

    in
    {
      nixosConfigurations = lib.genAttrs linuxHosts mkNixosConfiguration;
      darwinConfigurations = lib.genAttrs darwinHosts mkDarwinConfiguration;

      homeConfigurations = lib.listToAttrs (
        map (
          host: lib.nameValuePair "${hostAttrs.${host}.user}@${host}" (mkHomeConfiguration host)
        ) homeHosts
      );
    };
}
