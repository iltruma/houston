{ config, lib, pkgs, ... }:

{
  services.technitium-dns-server = {
    enable = true;
    # Gestisco il firewall manualmente per:
    # - 53 UDP/TCP: DNS, aperto per la LAN
    # - 53443 (HTTPS web UI): NON aperto — l'unico accesso è via
    #   Traefik reverse proxy su dns.lab.paroparo.it (443 → 5380)
    # - 5380 (HTTP web UI): aperto SOLO per loopback, per Traefik in
    #   hostNetwork che gira sullo stesso host
    openFirewall = false;
  };

  networking.firewall = {
    allowedUDPPorts = [ 53 ];   # DNS UDP
    allowedTCPPorts = [ 53 ];   # DNS TCP
    # 5380 (Technitium web UI HTTP): solo per loopback.
    # Traefik gira in hostNetwork su nebula, quindi quando accede a
    # 192.168.178.2:5380 il traffico attraversa l'interfaccia lo e
    # questa regola matcha. Client LAN vengono droppati.
    extraInputRules = ''
      -A INPUT -i lo -p tcp --dport 5380 -j ACCEPT
    '';
  };
}
