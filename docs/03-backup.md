# Backup / Disaster Recovery

Strategia di backup off-site e procedura di ricostruzione. Configurato in
[`modules/backup.nix`](../modules/backup.nix).

## Strategia

**GitOps-first**: il cluster è completamente ricostruibile dal flake NixOS +
manifesti Flux in Git. Tempo di rebuild: ~2-3 ore da zero (install NixOS +
restore backup rclone).

I dati applicativi con stato che **non** vivono in Git vengono sincronizzati
su **Cloudflare R2** via `rclone` con systemd timer notturno (ore 03:00).

> I certificati TLS **non** sono critici: cert-manager li riemette
> automaticamente da Let's Encrypt. I manifest, i secret cifrati SOPS e tutta
> la config Flux sono in Git.

## Cosa viene backuppato su R2

Configurato in [`modules/backup.nix`](../modules/backup.nix):

| Sorgente                      | Cosa contiene                              | Note |
|-------------------------------|--------------------------------------------|------|
| `/var/lib/technitium-dns-server/` | Zona DNS, blocklist, config Technitium | Zona `lab.paroparo.it` qui |
| `/var/lib/rancher/k3s/`       | etcd, certificati CA, token k3s             | Escluso `data/` (immagini container) |
| `/home/`                      | Dotfiles utente, script                    | Escluso `.cache/`, Trash |

> I dati che vivono *solo* in Git (manifest, secret `.enc.yaml`, valori
> Helm) non richiedono backup separato: il repo Git è la fonte di verità.

## Cosa NON viene backuppato (sacrificabile)

- `/nix` (Nix store): scaricabile da `cache.nixos.org`
- `k8s/*.enc.yaml` decifrati (Secret in cluster): ricostruibili da Git
- Immagini container in `/var/lib/rancher/k3s/agent/containerd/`: rigenerate
  da k3s al primo avvio

## Setup rclone (una tantum)

Configurazione in `secrets/rclone-env.enc.yaml` (cifrato con sops-nix):

```dotenv
RCLONE_CONFIG_R2_TYPE=s3
RCLONE_CONFIG_R2_PROVIDER=Cloudflare
RCLONE_CONFIG_R2_ACCESS_KEY_ID=xxx
RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=xxx
RCLONE_CONFIG_R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com
RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
```

Procedura:
1. Crea bucket `eos-backup` su Cloudflare R2 dashboard
2. Crea API token R2 con scope: Object Read & Write, bucket: `eos-backup`
3. Popola `secrets/rclone-env.enc.yaml` con le credenziali
4. Cifra: `sops --encrypt --in-place secrets/rclone-env.enc.yaml`
5. `nixos-rebuild switch --flake .#eos` (il secret viene montato in
   `/run/secrets/backup/rclone-env`)

## Esecuzione backup

Il `systemd.timers.rclone-backup` è attivo e gira ogni notte alle 03:00
(configurable in `modules/backup.nix`). Esecuzione manuale:

```bash
# Esegui il backup subito (senza aspettare il timer)
systemctl start rclone-backup

# Verifica log
journalctl -u rclone-backup -n 50

# Lista file su R2
rclone ls r2:eos-backup/
```

## Verifica backup

```bash
# Da eos
journalctl -u rclone-backup --since "1 day ago"

# Lista i file presenti
rclone ls r2:eos-backup/technitium/
rclone ls r2:eos-backup/k3s/
rclone size r2:eos-backup/

# Verifica timer attivo
systemctl list-timers rclone-backup.timer
```

## Restore

### Restore dati applicativi

```bash
# Restore Technitium (zona DNS, blocklist)
systemctl stop technitium-dns-server
rclone sync r2:eos-backup/technitium/ /var/lib/technitium-dns-server/
systemctl start technitium-dns-server

# Restore k3s state (richiede stop k3s prima)
systemctl stop k3s
rclone sync r2:eos-backup/k3s/ /var/lib/rancher/k3s/
systemctl start k3s
```

### Restore dati app k8s (PV)

I PV k3s vivono in `tank/volumes` (dataset ZFS). Se il dataset è integro,
i PV sono ancora lì. Se il dataset è perso, ripristinare da R2:

```bash
# Restore k3s state + riavvia (i pod ripartono automaticamente)
systemctl stop k3s
rclone sync r2:eos-backup/k3s/ /var/lib/rancher/k3s/
systemctl start k3s

# Verifica PV
k3s kubectl get pv
k3s kubectl get pvc -A
```

### Rebuild completo (scenario: eos perso o disco cambiato)

1. USB NixOS minimal + procedura in [00-nixos-installation.md](00-nixos-installation.md)
   step 4-5 (Disko + nixos-install)
2. Cifra di nuovo i secret con sops (devi avere la chiave age backuppata!)
3. `nixos-rebuild switch --flake .#eos` per attivare moduli (Technitium,
   k3s, backup, ecc.)
4. Verifica: `k3s kubectl get nodes`, `k3s kubectl get pods -A`
5. Restore dati da R2 (sezione sopra)

> Tempo stimato rebuild completo: **2-3 ore** (incluso restore dati).

## Retention

rclone non ha retention built-in. Per evitare crescita illimitata del bucket:

```bash
# Elimina file più vecchi di 30 giorni (manuale, o via cron)
rclone delete r2:eos-backup/ --min-age 30d --include "**"
```

Da aggiungere a un timer separato se il bucket cresce troppo. Free tier R2
è 10 GB, sufficiente per anni di backup di Eos.

## DR test (da fare)

Pianificare almeno una volta dopo la migrazione:
1. Distruggi e ricrea `eos` da zero seguendo questo doc
2. Verifica che tutti i servizi ripartino
3. Verifica che i dati app siano integri
4. Documenta lessons learned

Stima effort: mezza giornata.
