# hosts/eos/disko.nix
#
# Partizionamento ZFS dichiarativo per il disco principale.
# Eseguito UNA volta durante l'installazione:
#   nix run github:nix-community/disko -- --mode disko hosts/eos/disko.nix
#
# Layout (Dell Optiplex 3050, 500 GB SSD):
#   /dev/sda
#   ├── sda1 (1 GB, vfat)      → /boot (EFI System Partition)
#   └── sda2 (resto, ZFS)      → tank pool
#       ├── tank/root          → / (root filesystem, no encryption)
#       ├── tank/nix           → /nix (Nix store, compression zstd)
#       ├── tank/var           → /var (log, dati runtime)
#       ├── tank/home          → /home
#       ├── tank/persist       → /persist (snapshot frequenti, backup rclone)
#       └── tank/volumes       → /var/lib/rancher/k3s (PV k8s)
#
# Nessun dataset cifrato: nessun prompt al boot.
# Se in futuro serve cifratura su dati specifici (es. tank/secrets),
# si aggiunge come dataset separato senza impatto sul boot.
#
# Per reinstallare da zero:
#   nix run github:nix-community/disko -- --mode disko hosts/eos/disko.nix
#   nixos-install --flake .#eos

{ lib, ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda"; # Disco SATA principale (Dell Optiplex 3050)
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };
    };

    zpool = {
      tank = {
        type = "zpool";
        # Opzioni root: compression, no mountpoint (i figli lo settano)
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          mountpoint = "none";
        };
        # ashift 12 = 4K sector (standard SSD moderni)
        options.ashift = "12";
        # auto-trim per SSD (invia comandi TRIM al disco)
        options.autotrim = "on";

        datasets = {
          # Root filesystem (no encryption: nessun prompt al boot)
          "root" = {
            type = "zfs_fs";
            options.mountpoint = "/";
          };

          # Nix store separato (compression zstd, no encryption per semplicità DR)
          "nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
            mountpoint = "/nix";
          };

          # /var (log, journal, runtime)
          "var" = {
            type = "zfs_fs";
            options.mountpoint = "/var";
            mountpoint = "/var";
          };

          # Home utenti
          "home" = {
            type = "zfs_fs";
            options.mountpoint = "/home";
            mountpoint = "/home";
          };

          # Dataset persistente: sopravvive ai reboot, backup con rclone → R2.
          # Contiene lo stato dichiarato in modules/impermanence.nix:
          # SSH host keys, machine-id, chiave SOPS age.
          "persist" = {
            type = "zfs_fs";
            options.mountpoint = "/persist";
            mountpoint = "/persist";
          };

          # Volumi per PersistentVolume k8s (local-path provisioner)
          "volumes" = {
            type = "zfs_fs";
            options.mountpoint = "/var/lib/rancher/k3s";
            mountpoint = "/var/lib/rancher/k3s";
          };
        };
      };
    };
  };
}
