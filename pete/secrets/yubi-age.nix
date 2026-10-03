{ lib, nixSpaceAttrs, ... }:
let
  inherit (nixSpaceAttrs) user;
in
{
  environment.etc."age/${user}/age-plugin-yubikeys".source = ./age-plugin-yubikeys;

  # Place ssh keys before yubikey to prevent non-interactive failures
  age = {
    identityPaths = lib.mkAfter [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/static/age/${user}/age-plugin-yubikeys"
    ];

    secrets."anthropic-api-key" = {
      file = ./api_keys/anthropic-aichat-api.age;
      owner = user;
      mode = "0400";
    };

    secrets."wifi-${user}-wifi-lan" = {
      file = ./wpa_supplicant/wifi-lan.conf.age;
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/wpa_supplicant/${user}/wifi-lan.conf";
    };
  };
}
