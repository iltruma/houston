# Storage

Layout disco e dataset ZFS su Eos. Dichiarato in
[`hosts/eos/disko.nix`](../hosts/eos/disko.nix) e applicato da
[Disko](https://github.com/nix-community/disko) all'install.

## Hardware

| Disco | Tipo | Dimensione | Ruolo |
|-------|------|------------|-------|
| `/dev/sda` | SATA SSD | 500 GB | OS NixOS + dataset ZFS + tutto |

> Single disk. NVMe rimosso (vedi `stack-decisions.md#d6--rimozione-nvme-single-disk`).
> Il backup off-site è su Cloudflare R2 (vedi [03-backup.md](03-backup.md)),
> non su disco locale.

## Scelta del filesystem: ZFS

ZFS è stato scelto per:
- **Snapshot** nativi e leggeri (rollback al boot se vuoi, o snapshot manuali
  per DR)
- **Compressione** zstd su tutti i dataset (risparmio spazio trasparente)
- **Datasets separati** con mount point distinti (rollback granulare)
- **Auto-scrub** settimanale per integrity check

> **Nota**: la cifratura ZFS (`tank/root` con AES-256-GCM + TPM2) è stata
> **rimossa** (vedi `stack-decisions.md#d18--zfs-encryption-rimossa`). Su
> homelab domestico il threat model furto fisico non è reale; la complessità
> (TPM2, prompt al boot, modulo `zfs-tpm2.nix`) superava i benefici. ZFS resta
> per snapshot, CoW, compressione. Dataset cifrati specifici (es.
> `tank/secrets`) restano una possibile evoluzione futura senza impatto sul
> boot.

Alternativa scartata: **ext4 + LUKS** — più semplice ma senza snapshot,
senza compressione, senza datasets. Per un homelab con 500 GB e un solo disco,
ZFS è overkill solo in apparenza: il costo in RAM (~50 MB) e la complessità
sono minimi rispetto ai benefici.

## Layout

> Un disco "500 GB" commerciale dà **~465 GiB reali**.

```
/dev/sda  (~465 GiB)
├── sda1  (1 GB, vfat)       → /boot (EFI System Partition)
└── sda2  (resto, ZFS)       → tank pool
    ├── tank/root            → / (compression zstd)
    ├── tank/nix             → /nix (Nix store, compression zstd)
    ├── tank/var             → /var (log, journal, runtime)
    ├── tank/home            → /home (utenti)
    ├── tank/persist         → /persist (secrets/backup)
    └── tank/volumes         → /var/lib/rancher/k3s (PV k3s, local-path)
```

## Dataset

| Dataset | Mount point | Compressione | Note |
|---------|-------------|-------------|------|
| `tank/root` | `/` | zstd | OS + config NixOS |
| `tank/nix` | `/nix` | zstd | Nix store, ricostruibile da flake |
| `tank/var` | `/var` | zstd | Log e runtime |
| `tank/home` | `/home` | zstd | Utenti |
| `tank/persist` | `/persist` | zstd | Dati backup, secrets sops, R2 creds |
| `tank/volumes` | `/var/lib/rancher/k3s` | zstd | PV k8s, ricostruibili da Git |

> Nessun dataset è cifrato. La cifratura è stata rimossa (vedi nota sopra).

## Comandi utili

```bash
# Lista dataset
zfs list -o name,mountpoint,encryption,compression,quota

# Snapshot manuale prima di un cambio importante
zfs snapshot tank/root@pre-upgrade-2026-07-11
zfs list -t snapshot

# Rollback
zfs rollback tank/root@pre-upgrade-2026-07-11

# Status pool
zpool status tank
zpool scrub tank   # manual scrub (auto-scrub settimanale già attivo)

# Spazio
zfs list -o space
df -h /nix /var /persist /var/lib/rancher/k3s
```

## Snapshot policy

Auto-snapshot non è attivo di default (richiede `sanoid` o simile). Per la
maggior parte delle operazioni basta uno snapshot manuale prima di
`nixos-rebuild switch`.

Per operazioni ad alto rischio (es. cambio schema partizioni, upgrade NixOS
major), considera un backup completo rclone prima.

## ZFS tuning

In [`hosts/eos/hardware.nix`](../hosts/eos/hardware.nix):

```nix
services.zfs.autoScrub.enable = true;  # scrub settimanale
services.zfs.trim.enable = true;       # TRIM per SSD
```

## Persistenza (vs impermanence)

NixOS offre il pattern "impermanence" (`/` resettato a ogni boot, stato in
`/persist`). Eos ha scelto di **non** usarlo: complica il rollback e il
supporto di k3s state, e i benefici su single-host sono marginali. Lo state
vive normalmente sui dataset e viene backuppato con rclone.

## Storage aggiuntivo (futuro)

Per la Fase 4 (media library) servirà storage aggiuntivo (HDD esterno o NAS).
Opzioni:
- HDD USB 4-8 TB (~100€) → dataset ZFS `tank/media` come `hostPath` k3s (approccio scelto)
- NAS Synology/QNAP con NFS → mount in `/mnt/media`
- ~~Longhorn distribuito su k3s~~ — rimosso dalla roadmap (overkill per single-node)

Da decidere quando si avvicina Fase 4. Per ora `/dev/sda` basta per OS, k3s
state, e qualche app leggera.
