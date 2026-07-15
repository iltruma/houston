# hosts/taiga/networking.nix
#
# Rete per Taiga (Raspberry Pi 4, stampante 3D).
#
# IP statico: 192.168.178.43 (attuale su MainsailOS, mantenuto per coerenza)
# Gateway: 192.168.178.1 (Fritz!Box iris)
# DNS: 192.168.178.2 (Technitium su eos)

{ ... }:

{
  networking = {
    hostName = "taiga";

    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.178.43";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.178.1";
    nameservers = [
      "192.168.178.2"  # Technitium eos
      "1.1.1.1"        # fallback
    ];

    # ── Firewall ───────────────────────────────────────────────────────────────
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22    # SSH
        80    # HTTP (redirect → HTTPS)
        443   # HTTPS Mainsail (TLS Let's Encrypt)
        7125  # Moonraker API
      ];
    };
  };
}
