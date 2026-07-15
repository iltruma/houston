# hosts/eos/hardware.nix
#
# Configurazione hardware-specific per Dell Optiplex 3050.
#
# Generato automaticamente da `nixos-generate-config` durante l'installazione,
# poi rivisto per riflettere lo storage ZFS dichiarato in disko.nix.
#
# Hardware target:
#   - CPU: Intel i5-6500T (Skylake)
#   - RAM: 16 GB (pianificato upgrade a 32 GB)
#   - Disco: 1× SATA SSD 500 GB su /dev/sda
#   - Rete: 1× Ethernet su enp1s0 (o eno1, da verificare a boot)
#   - Firmware: UEFI

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # ── Filesystem import (ZFS gestito da disko) ─────────────────────────────────
  # disko.nix crea e monta i dataset a runtime. Qui dichiariamo i mount point
  # per la valutazione NixOS (check/build). usiamo mkDefault così disko può
  # sovrascrivere se serve (es. per /boot genera da partlabel).

  boot.supportedFilesystems = [ "zfs" ];

  # Dichiarazioni esplicite per la valutazione NixOS.
  # Al primo boot, disko genera i filesystem veri.
  fileSystems."/" = lib.mkDefault {
    device = "tank/root";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/nix" = lib.mkDefault {
    device = "tank/nix";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/var" = lib.mkDefault {
    device = "tank/var";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/home" = lib.mkDefault {
    device = "tank/home";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/persist" = lib.mkDefault {
    device = "tank/persist";
    fsType = "zfs";
    options = [ "zfsutil" ];
    neededForBoot = true;  # impermanence crea bind mount da /persist prima del boot
  };

  fileSystems."/var/lib/rancher/k3s" = lib.mkDefault {
    device = "tank/volumes";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-id/ata-MicroFrom_512GB_SATA3_SSD_01312223B0788";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Kernel modules necessari per ZFS + boot
  boot.initrd.availableKernelModules = [
    "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"
  ];
  boot.initrd.kernelModules = [ "zfs" ];
  boot.initrd.supportedFilesystems = [ "zfs" ];

  # ── CPU: microcode update (sicurezza Spectre/Meltdown) ──────────────────────
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ── Kernel modules per rete e container ─────────────────────────────────────
  boot.kernelModules = [
    "ip6_tables"
    "ip6table_mangle"
    "ip6table_raw"
    "ip6table_filter"
  ];

  # ── ZFS tuning ───────────────────────────────────────────────────────────────
  # Auto-scrub settimanale per integrity check (single SSD, leggero)
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # Force-import: single-node, nessun altro host usa il pool.
  boot.zfs.forceImportAll = true;

  # ── Bootloader UEFI ──────────────────────────────────────────────────────────
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ── Host ID (richiesto da ZFS) ───────────────────────────────────────────────
  # Identificatore univoco per host (8 hex chars). ZFS lo usa per non importare
  # pool di altre macchine per errore. Genera il tuo con:
  #   head -c4 /dev/urandom | od -A none -t x4
  # Il valore va settato UNA volta e tenuto (è legato al sistema).
  # ponytail: rigenerare al primo install
  networking.hostId = "963e586d";
}
