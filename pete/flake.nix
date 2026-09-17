# Userspace configuration for pete.
#
# SCOPE: this repo owns one user's machines — the system configuration and the
# home configuration for each. It consumes nixSpace, which owns the modules,
# the library, and the fleet's own host facts.
#
# A second user on a shared machine would have their own repo. Nothing
# structural stops two repos from each defining nixosConfigurations.<host>:
# both evaluate, and whichever one you last switched from is the running
# system. That is a convention about who administers a machine rather than
# something the tooling enforces.
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

    nixSpace = {
      url = "git+file:///home/pete/srv/git/nix.git?ref=main&shallow=1";
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

    # TODO: add nix-darwin when the Mac Mini is ported. A darwin host needs
    # darwinSystem rather than nixosSystem and a darwinConfigurations output
    # alongside nixosConfigurations; the per-host structure below is otherwise
    # unchanged.
  };

  outputs =
    {
      determinate,
      nixpkgs,
      home-manager,
      nixSpace,
      self,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      nixSpaceLib = import "${nixSpace}/lib" { inherit lib; };
      inherit (nixSpaceLib.tags) hasTag;

      systemModules = "${nixSpace}/system-modules";
      homeModules = "${nixSpace}/home-modules";

      # ---- hosts ------------------------------------------------------------
      #
      # An explicit list rather than readDir: the flake should say what it
      # builds without being evaluated to find out, and an enumeration would
      # have to filter out the sibling directories here anyway.
      #
      # Each host directory holds attrs.nix plus its configuration and home
      # files. The user is the repo, so the directory is just the host — hence
      # no user@host in paths, and no `./. + "..."` needed to work around `@`
      # not being legal in a path token.
      hostNames = [
        "black8"
        "silver16"
      ];

      hostAttrs = lib.genAttrs hostNames (h: nixSpaceLib.attrs.fromFile ./${h}/attrs.nix);

      systems = lib.unique (lib.mapAttrsToList (_: a: a.system) hostAttrs);

      # ---- overlays ---------------------------------------------------------
      #
      # Built once, not per host. An overlay reads its platform from the
      # package set it is applied to, so it needs no host metadata — which is
      # also more correct than passing attrs, since the two can disagree under
      # cross-compilation.
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

      # cudaSupport is a nixpkgs CONFIG value, not an overlay: it changes how
      # every CUDA-capable derivation is built, so it cannot be applied to an
      # instance that already exists. The dGPU specialisation therefore needs
      # its own package set.
      #
      # Expect a large local build — this rebuilds from source anything the
      # binary cache holds only in non-CUDA form.
      pkgsCudaFor = lib.genAttrs systems (
        system:
        import nixpkgs {
          inherit system overlays;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        }
      );

      specialArgsFor = host: {
        inherit inputs self nixSpaceLib;
        nixSpaceAttrs = hostAttrs.${host};
        pkgsCuda = pkgsCudaFor.${hostAttrs.${host}.system};
      };

      # ---- builders ---------------------------------------------------------

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

            # Every library module, unconditionally. Importing enables
            # nothing — each module gates its config on its own enable — so
            # the cost is option declarations only.
            systemModules

            # Hardware facts for this machine, from the fleet repo. A host's
            # disk layout is something every user of that machine has to agree
            # on, which is why it does not live here.
            "${nixSpace}/hosts/${host}"

            ./${host}/configuration.nix

            # Tag-coordinated enables: the facts that the system and home
            # configurations both act on and cannot read from each other.
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

            {
              nixSpace = {
                hyprland.enable = hasTag "hyprland" tags;
                hyprdesktop.enable = hasTag "hyprdesktop" tags;
                plasmadesktop.enable = hasTag "plasmadesktop" tags;
              };
            }
          ]
          ++ lib.optional (nixSpaceLib.platform.isLinux attrs.system) ./home-linux.nix
          ++ lib.optional (nixSpaceLib.platform.isDarwin attrs.system) ./home-darwin.nix
          ++ [ (./. + "/${host}/home.nix") ];
        };
    in
    {
      nixosConfigurations = lib.genAttrs hostNames mkNixosConfiguration;

      homeConfigurations = lib.listToAttrs (
        map (
          host: lib.nameValuePair "${hostAttrs.${host}.user}@${host}" (mkHomeConfiguration host)
        ) hostNames
      );
    };
}
