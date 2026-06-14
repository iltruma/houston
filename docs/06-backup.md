# Backup / Disaster Recovery

## Cosa viene backuppato

| Target | Tipo | ID Proxmox | Contiene |
|--------|------|------------|----------|
| ISS    | VM   | 100        | Root disk k3s: etcd, token, `/var/lib/rancher/k3s/` |
| sentinel | LXC | 200       | Root disk Pi-hole: `pihole.toml`, adlist, gravity DB |

> **Nota GitOps**: i manifesti Kubernetes, i SealedSecret cifrati e tutta la config
> ArgoCD sono in Git. In caso di perdita totale del cluster si può ricostruire
> quasi tutto con `ansible-playbook` + ArgoCD sync. Il backup vzdump è il livello
> aggiuntivo che evita il rebuild completo.
>
> I certificati TLS **non** sono critici: cert-manager li riemette da Let's Encrypt.

---

## Storage target

`sata-backup` — LV su SATA SSD, montato su `/mnt/sata-backup`.

```
/mnt/sata-backup/dump/
  ├── vzdump-qemu-100-<data>.vma.zst   ← ISS (VM)
  └── vzdump-lxc-200-<data>.tar.zst    ← sentinel (LXC)
```

Retention: 3 backup per target (i più vecchi vengono rimossi automaticamente da
`--maxfiles 3`).

---

## Eseguire il backup

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/backup.yml
```

Modalità `snapshot`: nessun downtime, lo snapshot LVM-thin viene creato mentre la
VM/LXC è in esecuzione. Durata stimata: 5–15 minuti in base alla dimensione dei
dischi.

Per verificare i backup creati:

```bash
ls -lh /mnt/sata-backup/dump/
```

---

## Restore

### Restore ISS (VM k3s)

```bash
# 1. Ferma la VM se è in esecuzione
qm stop 100

# 2. Restore (sovrascrive la VM esistente)
qmrestore /mnt/sata-backup/dump/vzdump-qemu-100-<data>.vma.zst 100 \
  --storage nvme \
  --force

# 3. Riavvia
qm start 100
```

> `--storage nvme` — il disco root viene ricreato sul thin pool NVMe.
> `--force` — necessario se la VM con ID 100 esiste già.

### Restore sentinel (LXC Pi-hole)

```bash
# 1. Ferma il container
pct stop 200

# 2. Restore
pct restore 200 /mnt/sata-backup/dump/vzdump-lxc-200-<data>.tar.zst \
  --storage nvme \
  --force

# 3. Riavvia
pct start 200
```

### Rebuild da zero (scenario: disco OS rotto)

Se il SATA SSD (OS Proxmox) è perso ma l'NVMe (dati VM) è intatto:

1. Reinstalla Proxmox sul nuovo SATA seguendo [01-proxmox-install.md](01-proxmox-install.md).
2. Ricrea lo storage `nvme` in Proxmox (il thin pool NVMe è intatto).
3. Importa le VM/LXC presenti sull'NVMe con `qm importdisk` / ricrea la config.
4. Se l'NVMe è perso: ripristina da sata-backup con i comandi di restore sopra,
   poi rilancia i playbook Ansible per ri-allineare la configurazione.

---

## Verifica (Definition of Done — S6)

- [ ] `ansible-playbook backup.yml` completa senza errori
- [ ] I file `.vma.zst` e `.tar.zst` sono presenti in `/mnt/sata-backup/dump/`
- [ ] Il processo di restore è documentato e i comandi sono stati verificati
- [ ] Retention: una seconda esecuzione del playbook lascia al massimo 3 backup
