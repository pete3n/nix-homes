# Hook for host specialisations.
{ ... }:
{
  imports = [
    ./specialisations/dgpu.nix
  ];
}
