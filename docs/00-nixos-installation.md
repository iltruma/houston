# Installazione NixOS — Eos

Guida operativa per installare NixOS baremetal su Eos (Dell Optiplex 3050).

nixos-anywhere installa NixOS via SSH su qualsiasi Linux già avviato sul target,
usando kexec per caricare il kernel NixOS in memoria e disko per partizionare.

**Prima installazione** (disco vuoto): installa Debian minimal con SSH → poi nixos-anywhere.
**Reinstall futuri**: nixos-anywhere direttamente, NixOS risponde già su SSH.

> **Prerequisito**: backup di qualsiasi dato da conservare prima di procedere.

## Prerequisiti

- Workstation con `nix` installato e flakes abilitati
- Eos raggiungibile via SSH come root (o utente con sudo passwordless)
- Chiave SSH della workstation autorizzata sul target

---

## Step 1 — Prima installazione: prepara il target con Debian minimal

Solo per la prima installazione su disco vuoto. Se NixOS è già presente, salta a Step 3.

1. Scarica [Debian netinst ISO](https://www.debian.org/CD/netinst/) e scrivila su USB
2. Boot da USB su Eos (F12 → boot menu Dell)
3. Installazione Debian minimal: no desktop, no extra packages, solo `SSH server`
4. Configura IP statico durante l'install: `192.168.178.2/24`, gateway `192.168.178.1`
5. Abilita login root via SSH: in `/etc/ssh/sshd_config` imposta `PermitRootLogin yes`
6. Aggiungi la SSH key della workstation: `ssh-copy-id root@192.168.178.2`

Verifica connettività:
```bash
ssh root@192.168.178.2 uname -a
# Linux eos ... x86_64 GNU/Linux
```

Da questo punto in poi, **USB non serve più**: tutti i reinstall futuri usano nixos-anywhere via SSH.

---

## Step 2 — Prepara i secrets

Sulla workstation:

```bash
# Genera/riusa la chiave age del repo
age-keygen -o age-key.txt
# age-key.txt contiene la chiave privata (NON committare)
# La chiave pubblica è nella prima riga: # public key: age1xxxx...

# Aggiorna .sops.yaml con la chiave pubblica
# Sostituisci AGE_PUBLIC_KEY in .sops.yaml (root del repo)

# Popola i 4 file secret (vedi secrets/*.enc.yaml per lo schema):
#   secrets/secrets.yaml                 (opzionale, aggregato)
#   secrets/flux-git-auth.enc.yaml       (SSH key per Flux)
#   secrets/flux-sops-age.enc.yaml       (chiave age per k8s)
#   secrets/rclone-env.enc.yaml          (credenziali R2)

# Cifra con sops
sops --encrypt --in-place secrets/flux-git-auth.enc.yaml
sops --encrypt --in-place secrets/flux-sops-age.enc.yaml
sops --encrypt --in-place secrets/rclone-env.enc.yaml

# Genera l'hostId univoco per ZFS
head -c4 /dev/urandom | od -A none -t x4
# Aggiorna il valore in hosts/eos/hardware.nix → networking.hostId

# Aggiungi la tua SSH pubblica in modules/common.nix:
#   users.users.cosimo.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];

# Clona il repo sulla workstation (se non già presente)
git clone <repo> ~/astra
cd ~/astra
```

## Step 3 — Esegui nixos-anywhere

nixos-anywhere si connette a Eos via SSH, partiziona il disco con disko,
installa NixOS e riavvia. Tutto da un singolo comando sulla workstation.

⚠️ **Distruttivo**: cancella tutto su `/dev/sda`.

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#eos \
  root@192.168.178.2
```

nixos-anywhere:
1. Copia il flake sul target via SSH
2. Esegue `kexec` per caricare un NixOS live in RAM (il Debian sparisce)
3. Esegue disko → partiziona `/dev/sda` con ZFS
4. Esegue `nixos-install`
5. Riavvia in NixOS

Vedi [02-storage.md](02-storage.md) per il layout ZFS dettagliato.

## Step 4 — Verifica post-install

```bash
# SSH dalla workstation
ssh root@192.168.178.2

# Verifica servizi host
systemctl status technitium-dns-server
systemctl status k3s
systemctl status rclone-backup.timer    # attivo, prossimo run alle 03:00

# Verifica k3s
k3s kubectl get nodes
# NAME      STATUS   ROLES                  AGE     VERSION
# eos   Ready    control-plane,master   2m      v1.30.x+k3s1

# Verifica CNI (Flannel bundled, pod kube-flannel)
k3s kubectl get pods -n kube-system
# Tutti i pod devono essere Running (inclusi flannel, coredns, traefik dopo Flux)

# Verifica CoreDNS custom (il ConfigMap si chiama "coredns", non "coredns-custom")
k3s kubectl -n kube-system get configmap coredns
# Deve esistere con il Corefile che forward a Technitium

# Verifica Flux (se hai configurato i secret)
k3s kubectl -n flux-system get pods
# Tutti i pod flux-system devono essere Running

k3s flux get kustomizations
# Tutte le Kustomization devono essere Ready
```

## Step 5 — Configurazione Technitium via web UI

Technitium è un servizio host, non gestito dal flake. La zona DNS, blocklist e
config si fanno via web UI:

```bash
# Dalla workstation, tunnel SSH verso la web UI
ssh -L 5380:127.0.0.1:5380 root@192.168.178.2
# Apri browser su http://127.0.0.1:5380
```

Configurazione minima:
- Crea zona autoritativa `lab.paroparo.it`
- Aggiungi record wildcard `*.lab.paroparo.it → 192.168.178.2`
- Configura upstream DoH Cloudflare
- (Opzionale) Blocklist Steven Black + OISD

Vedi [04-dns-technitium.md](04-dns-technitium.md) per dettagli.

## Step 6 — Verifica end-to-end

```bash
# Da un client sulla LAN
dig @192.168.178.2 lab.paroparo.it
# Deve risolvere (Technitium ha la zona)

dig @192.168.178.2 uptime.lab.paroparo.it
# Wildcard → 192.168.178.2 (Traefik k3s)

# HTTPS valido
curl -v https://uptime.lab.paroparo.it
# Cert Let's Encrypt valido, servizio Uptime Kuma raggiungibile
```

---

## Upgrade futuro

Per aggiornare NixOS o un pacchetto:

```bash
# Update flake.lock (pin nixpkgs nuovo)
nix flake update --commit nixpkgs

# Build e applica da workstation
nixos-rebuild switch --flake .#eos --target-host root@192.168.178.2
```

Per aggiornare altri Helm chart (traefik, cert-manager):
1. Modifica versione nel rispettivo `helmrelease.yaml` in `k8s/infra/`
2. Commit → Flux riconcilia

---

## Disaster recovery

Per ricostruire da zero:

1. USB NixOS minimal + procedura step 4-5 (Disko + nixos-install)
2. Cifra di nuovo i secret con sops (devi avere la chiave age backuppata!)
3. Verifica che i backup rclone siano disponibili su R2

**Importante**: la chiave age deve essere backuppata FUORI dal repo (password
manager + copia offline). Senza chiave, i secret sono irrecuperabili.

### Restore da R2

```bash
# Setup rclone con credenziali
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=xxx
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=xxx
export RCLONE_CONFIG_R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com

# Restore Technitium
rclone sync r2:eos-backup/technitium/ /var/lib/technitium-dns-server/
systemctl restart technitium-dns-server

# Restore k3s state (richiede stop k3s prima)
systemctl stop k3s
rclone sync r2:eos-backup/k3s/ /var/lib/rancher/k3s/
systemctl start k3s
```

---

## Troubleshooting

### ZFS non si importa al boot

Verifica la `hostId` in `hosts/eos/hardware.nix` (deve corrispondere
all'ID del disco). Da live USB: `zpool import -f tank`.

### k3s non parte

`journalctl -u k3s` — di solito è la porta 6443 occupata o un errore di
configurazione. Flannel non richiede bootstrap esterno; se i pod kube-flannel
sono in CrashLoopBackOff verifica i log con `k3s kubectl logs -n kube-system`.

### Flux non si connette a GitHub

Verifica la SSH key in `secrets/flux-git-auth.enc.yaml` e che la chiave pubblica
sia aggiunta come Deploy Key su GitHub (read-only).

```bash
# Debug manuale Flux
k3s kubectl -n flux-system logs deploy/source-controller
k3s kubectl -n flux-system get gitrepository
```

### CoreDNS non delega a Technitium

Verifica che il ConfigMap `coredns` esista in `kube-system`:
```bash
k3s kubectl -n kube-system get configmap coredns -o yaml
```

E che il symlink sia presente:
```bash
ls -la /var/lib/rancher/k3s/server/manifests/00-coredns-custom.yaml
```

### DNS non risolve da client LAN

Verifica firewall NixOS:
```bash
# Sul server
ss -tlnp | grep :53
# tecnitium-dns-server deve essere in ascolto

# Da un client
dig @192.168.178.2 lab.paroparo.it
```

Se il firewall blocca: aggiungi le porte in `hosts/eos/networking.nix`.
