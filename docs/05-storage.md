# Storage Layout

## Hardware attuale

| Disco | Tipo | Dimensione | Ruolo |
|---|---|---|---|
| `/dev/nvme0n1` | NVMe | 500GB | I/O "caldo": root disk VM/LXC + PersistentVolumes k3s |
| `/dev/sda` | SATA SSD | 500GB | OS Proxmox + ISO/template + media + target backup |

> Due dischi fisici separati: il SO Proxmox e i backup stanno sul SATA, mentre
> tutto l'I/O performante (etcd di k3s, PV, root delle VM) sta sull'NVMe. Questa
> separazione è anche il prerequisito per S6 (backup/DR): un disco che muore non
> porta via con sé sia OS che dati.

---

## Scelta del filesystem

Il pool NVMe usa **LVM-thin**, non ZFS:

- **zero overhead di RAM** — su 16GB la RAM serve alle VM; l'ARC di ZFS si
  prenderebbe fino a ~8GB e andrebbe limitato a mano.
- **coerente** con `local-lvm` già usato sul SATA.
- **snapshot** supportati comunque dal thin pool.
- su **disco singolo** ZFS non darebbe la sua feature principale (la ridondanza),
  quindi il suo costo (RAM, complessità) non si ripaga.

ZFS resterebbe la scelta migliore con più RAM o più dischi in mirror.

---

## Layout definitivo

> Nota: un disco "500GB" commerciale dà **~465 GiB reali**. I tagli sotto partono
> da lì.

### NVMe → storage `nvme` (LVM-thin)

Nessuna partizione separata: un **unico thin pool** contiene tutti i volumi.
Le dimensioni sono tagli *logici* (thin = allocazione on-demand, non occupazione
reale dal giorno 1).

```
/dev/nvme0n1  (~465 GiB)
  └── VG: nvme
        └── thinpool nvme (LVM-Thin storage in Proxmox)
              ├── vm/lxc root disks   (~180 GiB)  iss, sentinel, vanguard, template
              ├── disco dati ISS      (~250 GiB)  PersistentVolumes k3s → /mnt/k3s-data
              └── margine pool        (~35 GiB)   metadata thin + headroom
```

### SATA → OS + dati pesanti + backup

LV "spessi" (dimensioni rigide, fissate all'install).

```
/dev/sda  (~465 GiB)
  └── VG: pve
        ├── swap         (~8 GiB)     swap (16GB RAM)
        ├── pve-root     (~50 GiB)    Proxmox OS + local (ISO, template LXC)
        ├── sata-media   (~290 GiB)   disco dati ISS (Jellyfin + download)
        └── sata-backup  (~110 GiB)   target vzdump
```

---

## Dischi dati attaccati a ISS

I PersistentVolumes di k3s e i media non stanno sul root disk della VM: sono
**dischi virtuali aggiuntivi** allocati sui rispettivi storage e attaccati a `iss`.

### PersistentVolumes k3s su NVMe

Disco da ~250GB allocato sullo storage `nvme` (LVM-thin) e attaccato a ISS come
`/dev/vdb`:

```
/dev/vdb → /mnt/k3s-data        (provisioner local-path di k3s)
  ├── PV Prometheus
  ├── PV Grafana
  ├── PV Loki
  └── PV ArgoCD
```

### Media su SATA

Disco da ~300GB allocato su `sata-media` e attaccato a ISS come `/dev/vdc`:

```
/dev/vdc → /mnt/media
  ├── /mnt/media/jellyfin
  └── /mnt/media/downloads
```

---

## Sprint di riferimento

| Sprint | Operazione storage |
|---|---|
| S6 — Backup/DR | vzdump su `sata-backup`; restore verificato |
| S14 — Storage Fase 4 | Creare il disco `sata-media` e attaccarlo a ISS |
