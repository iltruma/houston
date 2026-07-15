# hosts/eos/networking.nix
#
# Configurazione rete per eos.
#
# Topologia rete:
#   rete 192.168.178.0/24
#   - iris (gateway Fritz!Box): 192.168.178.1
#   - eos (questo host):    192.168.178.2
#       ├─ Technitium DNS       (porta 53)
#       ├─ k3s API              (porta 6443)
#       └─ Traefik ingress      (porte 80/443)
#
# IP statico diretto su enp1s0. Se in futuro servono VM con IP nella LAN,
# si aggiunge il bridge br0 allora.

{ config, lib, pkgs, ... }:

{
  # ── Hostname ─────────────────────────────────────────────────────────────────
  networking.hostName = "eos";

  networking.useDHCP = false;
  networking.interfaces.enp1s0.ipv4.addresses = [
    {
      address = "192.168.178.2";
      prefixLength = 24;
    }
  ];

  networking.defaultGateway = "192.168.178.1";
  networking.nameservers = [
    "127.0.0.1"  # Technitium locale
    "1.1.1.1"    # Fallback Cloudflare
    "9.9.9.9"    # Fallback Quad9
  ];

  # ── Firewall ─────────────────────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      53    # DNS (Technitium)
      80    # HTTP (Traefik)
      443   # HTTPS (Traefik)
      6443  # k3s API (LAN only)
    ];
    allowedUDPPorts = [
      53    # DNS (Technitium)
    ];
  };

  # ── IPv6: disabilitato ───────────────────────────────────────────────────────
  networking.enableIPv6 = false;
}
