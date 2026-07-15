# Astra

**Homelab as Code** su un singolo Dell Optiplex 3050 (i5-6500T, 16 GB RAM pianificato 32 GB, 500 GB SSD)
con **NixOS baremetal** (no hypervisor). Tutto dichiarativo: OS e servizi in
un flake NixOS, applicazioni in Kubernetes via GitOps (Flux CD), TLS pubblico
via Let's Encrypt (DNS-01 Cloudflare), DNS interno via Technitium.

> Progetto anche **didattico**: si costruisce un pezzo alla volta, capendo cosa
> fa. Il piano completo è in **[docs/roadmap.md](docs/roadmap.md)**.

[![CI](https://github.com/iltruma/astra/actions/workflows/ci.yml/badge.svg)](https://github.com/iltruma/astra/actions/workflows/ci.yml)

> ⚠️ **Migrazione completata**: il repo gira su NixOS baremetal. Stack:
> flake NixOS per OS/servizi host, k3s come servizio, Flux per GitOps k8s.
> Vedi [docs/00-nixos-installation.md](docs/00-nixos-installation.md) per
> l'installazione e [docs/stack-decisions.md](docs/stack-decisions.md) per le
> scelte architetturali.

---

## Where to start

Nuovo qui? Parti da **[docs/00-nixos-installation.md](docs/00-nixos-installation.md)**
per l'installazione NixOS, poi segui la roadmap ([docs/roadmap.md](docs/roadmap.md))
e la mappa doc ([docs/README.md](docs/README.md)).

L'indice completo dei doc è in **[docs/README.md](docs/README.md)**.

---

## Stack

| Layer              | Tecnologia                                              |
|--------------------|---------------------------------------------------------|
| OS host            | NixOS 25.11 (baremetal, no hypervisor)                  |
| File system        | ZFS (Disko per partizionamento dichiarativo)            |
| IaC                | Flake NixOS (Nix language, unica fonte di verità)       |
| Config Management  | Moduli NixOS + nixos-rebuild                            |
| Orchestrazione     | k3s (single-node, servizio host)                        |
| CNI                | **Flannel** (bundled k3s, default)                      |
| GitOps             | Flux CD v2 + Kustomization                              |
| Secrets cifrati    | **SOPS + age** (sops-nix per host, Flux SOPS per k8s)   |
| Ingress            | Traefik (HelmRelease Flux in k3s)                       |
| TLS                | cert-manager + Let's Encrypt (DNS-01 Cloudflare)        |
| DNS interno        | Technitium DNS (servizio NixOS nativo, split-horizon)   |
| Backup             | rclone → Cloudflare R2 (systemd timer)                  |

---

## Architettura

```
                   rete 192.168.178.0/24
  iris     .1  ─  Router Fritz!Box         (gateway)
  eos  .2  ─  NixOS baremetal
                  ├─ Technitium DNS         (servizio NixOS, porta 53)
                  ├─ k3s                    (servizio NixOS, porta 6443)
                   │   ├─ Traefik            (ingress 80/443, hostNetwork)
                   │   ├─ cert-manager       (TLS ← Let's Encrypt via DNS-01 Cloudflare)
                   │   ├─ Flux CD v2         (GitOps → k8s/clusters/iss/)
                   │   └─ app (Fasi 2-4)
                  └─ systemd timer rclone   (backup → R2)
```

Dominio: **`lab.paroparo.it`** (record locali in Technitium, wildcard
`*.lab.paroparo.it → 192.168.178.2`, TLS valido via Let's Encrypt wildcard).

Per il setup completo dei servizi k3s vedi
[`k8s/README.md`](k8s/README.md).

---

## Prerequisiti hardware

- **Dell Optiplex 3050** (i5-6500T, 16 GB RAM pianificato 32 GB, 500 GB SSD)
- 1 disco: **SATA SSD 500 GB** (`/dev/sda`, OS NixOS + dataset ZFS)
- Porta Ethernet + cavo di rete
- Workstation Linux/Mac/WSL con: `nix` (flakes abilitati), `git`, `ssh` (chiave ed25519)

Per il partizionamento ZFS, dataset, layout storage e motivazioni vedi
[`hosts/eos/disko.nix`](hosts/eos/disko.nix) e
[`docs/02-storage.md`](docs/02-storage.md).

---

## Repository layout

```
astra/
├── flake.nix                    Entry point NixOS (pin nixpkgs, sops-nix, disko)
├── flake.lock                   ← tracciato (pin inputs)
├── hosts/
│   └── eos/                 Config specifica del server Dell Optiplex 3050
│       ├── default.nix          hostName, locale, nix settings, aggrega tutto
│       ├── hardware.nix         ZFS, kernel modules, bootloader, hostId
│       ├── networking.nix       bridge br0, firewall, IP statico
│       └── disko.nix            partizionamento ZFS dichiarativo
├── modules/                     Moduli NixOS riusabili
│   ├── default.nix              aggregatore
│   ├── common.nix               utenti, SSH, sops-nix config, pacchetti base
│   ├── technitium.nix           servizio DNS (nixpkgs nativo)
│   ├── k3s.nix                  k3s server + Flannel (bundled), CoreDNS custom, Flux secrets bootstrap
│   └── backup.nix               systemd timer rclone → R2
├── secrets/                     Secret host cifrati con SOPS + age
│   ├── secrets.yaml             aggregato (documentazione)
│   ├── flux-git-auth.enc.yaml   SSH key per Flux pull
│   ├── flux-sops-age.enc.yaml   chiave age per decifrare k8s/*.enc.yaml
│   └── rclone-env.enc.yaml      credenziali R2 per backup
├── k8s/                         Manifesti Kubernetes (GitOps, invariato)
│   ├── clusters/iss/            Kustomization radice (infrastructure + apps)
│   ├── infra/                   HelmRelease cert-manager, traefik
│   └── apps/                    una cartella per servizio (beszel, homepage,
│                                infra-proxy, uptime-kuma)
├── docs/                        Documentazione (indice in docs/README.md)
│   ├── README.md                indice navigabile
│   ├── roadmap.md               piano in 5 fasi (con Fase 0 = migrazione NixOS)
│   ├── stack-decisions.md       decisioni architetturali
│   ├── 00-nixos-installation.md installazione NixOS baremetal
│   ├── 01-network.md            bridge, firewall, DNS
│   ├── 02-storage.md            layout ZFS
│   ├── 03-backup.md             rclone → Cloudflare R2
│   ├── 04-dns-technitium.md      Technitium DNS
│   ├── 05-tls.md                Let's Encrypt + Cloudflare
│   ├── 06-secrets-sops.md       SOPS + age
│   ├── 07-gitops.md             k3s + Flux
│   └── 08-monitoring.md         Uptime Kuma + Beszel
├── .github/workflows/
│   └── ci.yml                   nix flake check / kubeconform / gitleaks
├── .gitleaks.toml               estende i default (secrets scanning)
├── .sops.yaml                   regole cifratura SOPS + age
├── .renovaterc.json             aggiornamenti automatici dipendenze
├── .gitignore                   nix, secrets, k8s
├── AGENTS.md                    regole agenti (opencode, Claude Code)
├── CLAUDE.md → AGENTS.md       symlink per Claude Code
└── opencode.json               config opencode
```

---

## Fasi

| # | Fase                            | Stato  | Sprint chiave                                |
|---|---------------------------------|--------|----------------------------------------------|
| 1 | Backbone                        | 🟢     | S0 Technitium DNS, S2 k3s+Flannel, S3 cert-manager, S4 Flux CD, S5 SOPS + age, S6 backup |
| 2 | Accesso & osservabilità         | 🟡     | S10 Uptime Kuma — monitoring (S7-S9) in HOLD |
| 3 | App tue                         | 🔴     | S13 — da pianificare                          |
| 4 | Media                           | 🔴     | S15 Jellyfin, S16 download stack, S17 Jellyseerr (storage: ZFS `tank/media` hostPath) |
| 5 | Rete avanzata (VLAN)            | 🔴     | S18 — richiede switch managed                |

DoD di ogni sprint, decisioni architetturali e storia: vedi
[`docs/roadmap.md`](docs/roadmap.md).

---

## Quick start

```bash
# 1. (Una tantum) Genera le chiavi e cifra i secret
nix-shell -p sops age --run "bash"
age-keygen -o age-key.txt                              # genera chiave age
sops --encrypt --in-place secrets/flux-git-auth.enc.yaml
sops --encrypt --in-place secrets/flux-sops-age.enc.yaml
sops --encrypt --in-place secrets/rclone-env.enc.yaml

# 2. Genera hostId univoco per ZFS
head -c4 /dev/urandom | od -A none -t x4
# Aggiorna il valore in hosts/eos/hardware.nix → networking.hostId

# 3. Valida il flake
nix flake check

# 4. Installa NixOS (da USB minimal, vedi docs/00-nixos-installation.md)
nix run github:nix-community/disko -- --mode disko hosts/eos/disko.nix
nixos-install --flake .#eos
reboot

# 5. Applica update da remoto (da workstation)
nixos-rebuild switch --flake .#eos --target-host root@192.168.178.2

# 6. Kubernetes
ssh root@192.168.178.2
k3s kubectl get nodes
k3s flux get kustomizations
```

> Il flake NixOS è idempotente: `nixos-rebuild switch` può essere rieseguito
> quante volte vuoi, lo stato converge sempre. Vedi `nix flake check` su CI.

---

## Sicurezza e gestione segreti

**Cosa è committato** (e va bene):
- manifest k8s in chiaro
- `secrets/*.enc.yaml` cifrati con SOPS + age (stessa chiave di Flux)
- ConfigMap k8s con dati non sensibili (es. ConfigMap homepage)

**Cosa NON è committato** (gitignored):
- `age-key.txt`, `keys.txt` (chiave privata age — MAI committare)
- `certs/` (cert self-signed)
- `*.kubeconfig` (kubeconfig workstation)
- `result*` (output di `nix build`)

**Toolchain unificata**: SOPS + age per TUTTI i segreti (host e k8s).
- Secret host (`secrets/*.enc.yaml`) decifrati da `sops-nix` all'attivazione
  NixOS, montati in `/run/secrets/` (tmpfs).
- Secret k8s (`k8s/**/*.enc.yaml`) decifrati dal `kustomize-controller` Flux.
- Stessa chiave age, stesso `.sops.yaml`, stessa CLI `sops`.

**PII in repo**: l'email `casini.cosimo@gmail.com` è presente nei due
`ClusterIssuer` Let's Encrypt (`k8s/infra/cert-manager/clusterissuer-*.yaml`)
come contatto ACME. È personale: da cambiare se il repo diventa pubblico.

**Scansione**: `gitleaks` gira in CI su ogni push/PR (`fetch-depth: 0` →
scansiona tutta la history).

**Protezione branch**: configurare GitHub → Settings → Branches → main →
"Require a pull request before merging".

---

## Sviluppo

### Aggiungere un nuovo servizio al cluster

```bash
mkdir k8s/apps/<nome>
# namespace.yaml + deployment.yaml + service.yaml + ingress.yaml
# kustomization.yaml che li elenca
git add k8s/apps/<nome>/
git commit -m "feat(k8s): add <nome>"
git push
```

Flux CD sincronizza automaticamente entro ~10 minuti. Per forzare:
`k3s flux reconcile kustomization apps --with-source`.

### Linting locale

```bash
nix flake check
curl -sSL "https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz" | tar xz kubeconform
./kubeconform -strict -summary -skip CustomResourceDefinition -ignore-missing-schemas -ignore-filename-pattern '.*\.enc\.yaml' -ignore-filename-pattern '.*README\.md' k8s/
```

CI fa tutto questo su ogni push/PR (vedi
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

### Aggiornare un tool pinnato

Le versioni sono in:
- `flake.lock` (nixpkgs, sops-nix, disko): `nix flake update --commit nixpkgs`
- `k8s/infra/*/helmrelease.yaml` (Helm chart version)

Bump intenzionale, test in staging, commit atomico. Vedi anche
[.renovaterc.json](.renovaterc.json) per aggiornamenti automatici (D12, proposto).

---

## Troubleshooting

- **k3s non raggiungibile**: `ssh root@eos 'k3s kubectl get nodes'`
- **Cert non emesso**: `k3s kubectl describe certificate -A` e
  `k3s kubectl describe challenge -A` (DNS-01 deve creare TXT su Cloudflare)
- **Flux non sincronizza**: `k3s flux get kustomizations` e
  `k3s kubectl -n flux-system get gitrepository`
- **Secret sops non decifrati**: verifica `/run/secrets/` esista e
  `sops --decrypt secrets/foo.enc.yaml` funzioni
- **ZFS pieno**: `zfs list -o space` vede lo spazio usato per dataset;
  `zfs list -o quota` per limiti. Snapshot manuali: `zfs snapshot tank/root@nome`

Per problemi specifici di un servizio vedi la doc del singolo sprint in
[docs/README.md](docs/README.md). Per una guida completa, vedi
[docs/00-nixos-installation.md](docs/00-nixos-installation.md) (sezione
Troubleshooting).

---

## Licenza

MIT — Copyright (c) 2026 Cosimo Casini.
