# modules/klipper.nix
#
# Stack stampa 3D: Klipper + Moonraker + Mainsail + TLS.
# Usato da hosts/taiga.
#
# ── Architettura ────────────────────────────────────────────────────────────
#   Mainsail (nginx :443, TLS) → Moonraker (:7125) → Klipper (socket) → MCU
#
# ── TLS: Let's Encrypt DNS-01 via Cloudflare ────────────────────────────────
# security.acme gestisce il certificato per taiga.lab.paroparo.it.
# DNS-01: non serve esporre Taiga su internet — il challenge avviene via API
# Cloudflare. Il token è in secrets/taiga-cloudflare-acme.enc.yaml (sops-nix).
#
# ── mutableConfig = true ────────────────────────────────────────────────────
# printer.cfg è modificabile dalla UI Mainsail (calibrazioni, PID, SAVE_CONFIG).
# NixOS inizializza il file se non esiste, ma non lo sovrascrive.
# Per "fotografare" lo stato nel repo:
#   scp pi@192.168.178.43:/var/lib/klipper/printer.cfg hosts/taiga/printer.cfg
#   git commit -am "feat(nix): aggiorna printer.cfg taiga"

{ config, lib, pkgs, ... }:

{
  # ── Klipper ──────────────────────────────────────────────────────────────────
  services.klipper = {
    enable = true;
    mutableConfig = true;

    configFile = lib.mkIf (builtins.pathExists ../hosts/taiga/printer.cfg)
      ../hosts/taiga/printer.cfg;

    settings = lib.mkIf (!(builtins.pathExists ../hosts/taiga/printer.cfg)) {
      printer = {
        kinematics = "none";
        max_velocity = 300;
        max_accel = 3000;
      };
    };
  };

  # ── Moonraker ────────────────────────────────────────────────────────────────
  services.moonraker = {
    enable = true;
    address = "0.0.0.0";

    settings = {
      authorization = {
        trusted_clients = [ "192.168.178.0/24" ];
        cors_domains = [
          "https://taiga.lab.paroparo.it"
          "http://192.168.178.43"
        ];
      };
      update_manager.enable_system_updates = false;
    };

    allowSystemControl = true;
  };

  # ── Mainsail ─────────────────────────────────────────────────────────────────
  services.mainsail = {
    enable = true;
    hostName = "taiga.lab.paroparo.it";

    # nginx extra config: redirect HTTP → HTTPS
    nginx = {
      forceSSL = true;
      enableACME = true;
    };
  };

  # ── TLS: Let's Encrypt DNS-01 via Cloudflare ─────────────────────────────────
  # security.acme emette e rinnova automaticamente il cert (systemd timer).
  # Il token Cloudflare viene da sops-nix: /run/secrets/taiga/cloudflare-acme-env
  # Formato del secret (dotenv):
  #   CLOUDFLARE_DNS_API_TOKEN=<token-con-permesso-DNS-Edit>
  security.acme = {
    acceptTerms = true;
    defaults.email = "casini.cosimo@gmail.com";

    certs."taiga.lab.paroparo.it" = {
      dnsProvider = "cloudflare";
      # environmentFile: file dotenv con CLOUDFLARE_DNS_API_TOKEN
      # Decifrato da sops-nix al boot in /run/secrets/
      environmentFile = config.sops.secrets."taiga/cloudflare-acme-env".path;
      group = "nginx";  # nginx può leggere il cert
    };
  };

  # ── sops-nix: token Cloudflare per ACME ──────────────────────────────────────
  sops.secrets."taiga/cloudflare-acme-env" = {
    sopsFile = ../secrets/taiga-cloudflare-acme.enc.yaml;
    format = "yaml";
    # owner nginx/acme non serve: il file è letto dal processo acme (root)
  };

  # ── polkit: richiesto da allowSystemControl ───────────────────────────────────
  security.polkit.enable = true;

  # ── dialout: accesso seriale MCU ─────────────────────────────────────────────
  users.groups.dialout = { };
}
