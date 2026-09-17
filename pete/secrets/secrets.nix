let
  pete_yk_pri = "age1yubikey1q2hzhr0yekk766v76s5gpsv45t2hl4p644e7w6v77fl30n6qy9keuctu0z6";
  pete_yk_bak = "age1yubikey1qdxcmeztxrax00vx5gnyteacgqn7jmdc3qnuvts82rkg2zwwmuccc85afcz";

  # Host keys
  silver16 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA7/v1drJEFf3X22NwB9ygO5V5NaobiQfXYb4LIuFoMP root@silver16";
  black8 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO70Au6FegohwKFygshDnN9TGll69m4cc1WXMqa8tXl/ root@black8";

  allKeys = [
    silver16
    black8
    pete_yk_pri
    pete_yk_bak
  ];
in
{
  "api_keys/anthropic-aichat-api.age".publicKeys = allKeys;
  "wpa_supplicant/wifi-lan.conf.age".publicKeys = allKeys;
  "pete3n.age".publicKeys = allKeys;
  "openvpn/p22-client1-tcp.age".publicKeys = allKeys;
  "openvpn/p22-client1.age".publicKeys = allKeys;
  "bitcoind-rpc-hmac.age".publicKeys = allKeys;
}
