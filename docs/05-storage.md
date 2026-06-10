# Storage Layout

## Hardware attuale

| Disco | Tipo | Dimensione | Ruolo |
|---|---|---|---|
| `/dev/sda` | SATA SSD | 500GB | Tutto: OS Proxmox + VM/LXC + dati |

> ⚠️ **NVMe non ancora installato.** Il piano originale prevedeva un secondo disco
> NVMe per separare servizi (I/O casuale) da dati pesanti (media/download).
> Per ora tutto gira su SATA. Dopo l'installazione dell'NVMe si ricostruirà
> l'infrastruttura da zero con il layout definitivo.

---

## Layout attuale (solo SATA)

```
/dev/sda  500GB SATA SSD
  └── local (~94GB, dir)       OS Proxmox, ISO, template LXC
  └── local-lvm (~348GB, LVM thin)
        ├── template 9000      cloud image grezzo Debian 13
        ├── template 9001      debian13-base (output Packer)
        ├── iss (VM k3s)       20GB — root disk
        ├── sentinel (LXC)     root disk Pi-hole
        └── vanguard (LXC)     root disk step-ca
```

348GB su `local-lvm` è sufficiente per tutto il backbone (S3–S6) e la Fase 2
(osservabilità). I problemi di spazio si pongono solo in Fase 4 con media/download.

---

## Layout target post-NVMe

Da fare quando l'NVMe sarà installato — rebuild completo dell'infrastruttura.

### NVMe → pool `nvme` (ZFS)

```
/dev/nvme0n1
  └── zpool: nvme
        ├── nvme/vm-disks    (~200GB)  root disk VM e LXC
        └── nvme/k3s-pv      (~250GB)  PersistentVolumes k3s
```

### SATA → dati pesanti

```
/dev/sda
  └── VG: pve
        ├── pve-root     (~50GB)    Proxmox OS
        ├── local        (~30GB)    ISO e template LXC
        ├── sata-media   (~300GB)   disco dati ISS (Jellyfin + download)
        └── sata-backup  (~100GB)   target vzdump
```

### PersistentVolumes k3s su NVMe

`nvme/k3s-pv` esposto come zvol e attachato a ISS come `/dev/vdb`:

```
/dev/vdb → /mnt/k3s-data
  ├── PV Prometheus
  ├── PV Grafana
  ├── PV Loki
  └── PV ArgoCD
```

### Media su SATA

`sata-media` attachato a ISS come `/dev/vdc`:

```
/dev/vdc → /mnt/media
  ├── /mnt/media/jellyfin
  └── /mnt/media/downloads
```

---

## Sprint di riferimento

| Sprint | Operazione storage |
|---|---|
| S6 — Backup/DR | vzdump su `local` (per ora); post-NVMe su `sata-backup` |
| S14 — Storage Fase 4 | Prerequisito: NVMe installato; creare pool ZFS e LV SATA |
