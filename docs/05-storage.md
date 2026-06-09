# Storage Layout

## Dischi disponibili

| Disco | Tipo | Dimensione | Ruolo |
|---|---|---|---|
| `/dev/sda` | SATA SSD | 500GB | Proxmox OS + dati pesanti (media, download, backup) |
| `/dev/nvme0n1` | NVMe SSD | 512GB | Servizi: dischi VM/LXC + PersistentVolumes k3s |

## Principio di design

**NVMe → velocità → servizi**: i workload stateful del cluster (Prometheus TSDB,
Loki chunks, ArgoCD, etcd k3s) fanno I/O casuale intenso — l'NVMe li accelera
significativamente rispetto al SATA.

**SATA → capienza → dati**: Jellyfin e qBittorrent fanno I/O prevalentemente
sequenziale (streaming, download). Un SATA SSD è più che sufficiente e conserva
l'NVMe per chi ne ha davvero bisogno.

---

## NVMe — pool `nvme` (ZFS)

ZFS è scelto per: checksums di integrità dati, compressione trasparente (utile
su Prometheus/Loki che comprimono male da soli), snapshot nativi usabili con vzdump.
Con 16GB RAM il memory overhead di ZFS è trascurabile.

```
/dev/nvme0n1
  └── zpool: nvme
        ├── nvme/vm-disks    (~200GB)  root disk di VM e LXC
        └── nvme/k3s-pv      (~250GB)  disco PersistentVolumes k3s
            (spare ~62GB per headroom ZFS — vuole ~10-15% libero)
```

### Dettaglio `nvme/vm-disks`

Registrato in Proxmox come storage di tipo **ZFS** → contiene i root disk di
`iss`, `sentinel`, `vanguard`. I VM/LXC esistenti vanno migrati da `local-lvm`
(SATA) a questo pool; quelli nuovi creati qui direttamente.

### Dettaglio `nvme/k3s-pv`

Viene esposto come **zvol** (dispositivo a blocchi ZFS) e attachato alla VM `iss`
come secondo disco virtuale `/dev/vdb`. Dentro ISS:

```
/dev/vdb
  └── formato: ext4
  └── mount: /mnt/k3s-data
        └── k3s local-path provisioner usa /mnt/k3s-data
              ├── PV Prometheus (TSDB)
              ├── PV Grafana (stato)
              ├── PV Loki (chunks + index)
              └── PV ArgoCD (repo cache)
```

La configurazione del provisioner avviene in S2 aggiungendo l'argomento
`--default-local-storage-path=/mnt/k3s-data` al manifest k3s.

---

## SATA — riuso dopo migrazione VM

Il SATA ha già Proxmox OS nel VG `pve`. Dopo aver migrato i root disk delle VM
su NVMe, il thin pool `data` (LVM) libera spazio nel VG. Da quello spazio si
ricavano due nuovi Logical Volume:

```
/dev/sda
  └── VG: pve
        ├── pve-root     (~50GB)   Proxmox OS — fisso
        ├── local        (~30GB)   ISO e template LXC
        ├── [data]       (svuotato dopo migrazione VM su NVMe)
        ├── sata-media   (~300GB)  disco dati per ISS (media + download)
        └── sata-backup  (~100GB)  target vzdump
```

### Dettaglio `sata-media`

Attachato a ISS come terzo disco virtuale `/dev/vdc`:

```
/dev/vdc
  └── formato: ext4
  └── mount: /mnt/media
        ├── /mnt/media/jellyfin    ← libreria Jellyfin
        └── /mnt/media/downloads  ← cartella qBittorrent (torrent in uscita)
```

> ⚠️ **Realtà hardware**: ~300GB bastano per una libreria piccola/media. Per
> una collezione 4K o HD estesa servirà uno storage aggiuntivo (HDD esterno USB
> o NAS via NFS). Questo è il prerequisito S14 della Fase 4 — non è da risolvere
> ora.

### Dettaglio `sata-backup`

Registrato in Proxmox come storage di tipo **Directory** con contenuto `VZDump`.
Usato dal task di backup programmato configurato in S6.

---

## Sprint di riferimento

| Sprint | Operazione storage |
|---|---|
| S2 — k3s completamento | Aggiungere NVMe come pool ZFS; creare zvol `k3s-pv`; attacharlo a ISS come `/dev/vdb`; montare e configurare local-path provisioner |
| S6 — Backup/DR | Creare LV `sata-backup`; registrare in Proxmox; configurare vzdump schedulato |
| S14 — Storage Fase 4 | Creare LV `sata-media`; attachare a ISS come `/dev/vdc`; configurare path in Jellyfin e qBittorrent |
