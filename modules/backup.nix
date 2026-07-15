# modules/backup.nix
#
# Backup off-site via rclone → Cloudflare R2.
# Sostituisce il vecchio playbook ansible/backup.yml (rimosso nella migrazione).
#
# Cosa viene backuppato:
#   - /var/lib/technitium-dns-server  (zona DNS, blocklist, config)
#   - /var/lib/rancher/k3s            (etcd, certificati, stato k3s)
#   - /home                           (dotfiles, script)
#
# Cosa NON viene backuppato (ricostruibile da Git):
#   - k8s/                            (manifesti, GitOps)
#   - /nix                            (Nix store, scaricabile)
#   - /persist/sops                   (chiavi, gestite a parte)
#
# Configurazione richiesta:
#   1. Crea bucket R2 "eos-backup" su Cloudflare dashboard
#   2. Genera API token R2 con scope sul bucket
#   3. Cifra secrets/rclone-config.env.enc.yaml con sops (vedi sotto)
#
# Schedule: notturno alle 03:00.
# Retention: gestita via lifecycle rules su Cloudflare R2 (Object Lifecycle in dashboard),
# oppure aggiungendo un job separato: rclone delete r2:eos-backup --min-age 7d.
# NON usare --max-age su rclone sync: è un filtro di trasferimento (non trasferisce file
# sorgente più vecchi di 7d), non una retention policy. Con sync causa perdita silenziosa
# di file non modificati di recente.

{ config, lib, pkgs, ... }:

{
  # ── Pacchetto rclone ─────────────────────────────────────────────────────────
  environment.systemPackages = [ pkgs.rclone ];

  # ── Secret R2 (cifrato con sops) ────────────────────────────────────────────
  # File .env con le credenziali R2 (formato rclone expects):
  #   RCLONE_CONFIG_R2_TYPE=s3
  #   RCLONE_CONFIG_R2_PROVIDER=Cloudflare
  #   RCLONE_CONFIG_R2_ACCESS_KEY_ID=xxx
  #   RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=xxx
  #   RCLONE_CONFIG_R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com
  sops.secrets."backup/rclone-env" = {
    sopsFile = ../secrets/rclone-env.enc.yaml;
    format = "yaml";
  };

  # ── Systemd service: esegue rclone sync ──────────────────────────────────────
  systemd.services.rclone-backup = {
    description = "Backup off-site to Cloudflare R2";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.secrets."backup/rclone-env".path;
      # Path diretto al pacchetto: robusto a prescindere dal profile attivo
      ExecStart = pkgs.writeShellScript "rclone-backup" ''
        set -e
        R=${pkgs.rclone}/bin/rclone
        REMOTE=r2:eos-backup

        $R sync /var/lib/technitium-dns-server $REMOTE/technitium/ --log-level INFO

        $R sync /var/lib/rancher/k3s $REMOTE/k3s/ \
          --exclude "agent/containerd/**" \
          --exclude "agent/run/**" \
          --exclude "data/**" \
          --log-level INFO

        $R sync /home $REMOTE/home/ \
          --exclude ".cache/**" \
          --exclude ".local/share/Trash/**" \
          --log-level INFO
      '';
    };
  };

  # ── Systemd timer: esecuzione notturna alle 03:00 ───────────────────────────
  systemd.timers.rclone-backup = {
    description = "Schedule for rclone backup to R2";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;  # se il sistema era spento, esegui al boot
      RandomizedDelaySec = "15min";
    };
  };
}
