# Hook for host specialisations.
{ ... }:
{
  imports = [
    ./specialisations/egpu.nix
  ];
}
