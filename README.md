# Houston

**Homelab as Code** su un singolo Dell Optiplex 3050 (i5-6500T, 16 GB RAM, 500 GB SSD)
con **Proxmox VE** come hypervisor. Tutto dichiarativo: infrastruttura in
Terraform, provisioning in Ansible, applicazioni in Kubernetes via GitOps
(ArgoCD), TLS pubblico via Let's Encrypt (DNS-01 Cloudflare), DNS interno via
Pi-hole.

> Progetto anche **didattico**: si costruisce un pezzo alla volta, capendo cosa
> fa. Il piano completo è in **[docs/roadmap.md](docs/roadmap.md)**.

[![CI](https://github.com/iltruma/houston/actions/workflows/ci.yml/badge.svg)](https://github.com/iltruma/houston/actions/workflows/ci.yml)
[![terraform](https://github.com/iltruma/houston/actions/workflows/ci.yml/badge.svg?job=terraform)](https://github.com/iltruma/houston/actions/workflows/ci.yml)
[![ansible-lint](https://github.com/iltruma/houston/actions/workflows/ci.yml/badge.svg?job=ansible-lint)](https://github.com/iltruma/houston/actions/workflows/ci.yml)
[![kubeconform](https://github.com/iltruma/houston/actions/workflows/ci.yml/badge.svg?job=kubeconform)](https://github.com/iltruma/houston/actions/workflows/ci.yml)
[![gitleaks](https://github.com/iltruma/houston/actions/workflows/ci.yml/badge.svg?job=gitleaks)](https://github.com/iltruma/houston/actions/workflows/ci.yml)

---

## Where to start

Nuovo qui? Parti da **[docs/01-proxmox-install.md](docs/01-proxmox-install.md)**
e segui l'ordine della roadmap ([docs/roadmap.md](docs/roadmap.md)).

L'indice completo dei doc è in **[docs/README.md](docs/README.md)**.

---

## Stack

| Layer              | Tecnologia                                              |
|--------------------|---------------------------------------------------------|
| Hypervisor         | Proxmox VE 9 (Debian 13)                                |
| IaC                | Terraform (provider [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest)) |
| Provisioning       | Ansible (collections `community.general`, `ansible.posix`) |
| Orchestrazione     | k3s (single-node VM)                                   |
| CNI                | **Cilium** (1.18.x LTS, sostituisce Flannel per NetworkPolicy + Hubble) |
| GitOps             | ArgoCD + ApplicationSet                                 |
| Secrets cifrati    | **Sealed Secrets** (bitnami) in Git, decifrati in-cluster |
| Ingress            | Traefik (incluso in k3s, v3.6)                          |
| TLS                | cert-manager + Let's Encrypt (DNS-01 Cloudflare)        |
| DNS interno        | Pi-hole v6 (split-horizon per `*.lab.paroparo.it`)      |
| Accesso esterno    | **Cloudflare Tunnel** (`cloudflared` 2026.x in k3s)     |
| Backup             | vzdump su `sata-backup` (Proxmox)                       |

---

## Architettura

```
                   rete 192.168.178.0/24
  iris     .1  ─  Router Fritz!Box         (gateway)
  houston  .2  ─  Proxmox VE (hypervisor)
  sentinel .4  ─  LXC  Pi-hole             (DNS + adlists)
  iss      .3  ─  VM   k3s single-node
                  ├─ Traefik                (ingress 80/443)
                  ├─ cert-manager           (TLS ← Let's Encrypt via DNS-01 Cloudflare)
                  ├─ ArgoCD                 (ApplicationSet → apps/*)
                  ├─ Sealed Secrets         (decifra SealedSecret in Secret)
                  ├─ cloudflared            (tunnel outbound → Cloudflare)
                  └─ app (Fasi 2-4)
```

Dominio: **`lab.paroparo.it`** (record locali in Pi-hole, wildcard
`*.lab.paroparo.it → 192.168.178.3`, TLS valido via Let's Encrypt wildcard).

Per il setup completo dei servizi k3s vedi
[`k8s/README.md`](k8s/README.md).

---

## Prerequisiti hardware

- **Dell Optiplex 3050** (i5-6500T, 16 GB RAM)
- 2 dischi: **SATA SSD 500 GB** (`/dev/sda`, OS Proxmox) + **NVMe 500 GB**
  (`/dev/nvme0n1`, VM root + PersistentVolume k3s)
- Porta Ethernet + cavo di rete
- Workstation Linux/Mac/WSL con: `terraform`, `ansible`, `kubectl`, `helm`,
  `packer`, `kubeseal`, `ssh` (chiave ed25519)

Per il partizionamento, LVM, layout storage e motivazioni vedi
[`docs/05-storage.md`](docs/05-storage.md).

---

## Repository layout

```
houston/
├── packer/                     Template VM Debian 13 (sprint ST)
│   └── debian13-base/          upload-cloud-image.sh + Packer config
├── terraform/                  Infrastruttura (VM, LXC, network)
│   ├── main.tf                 provider bpg/proxmox
│   ├── vm-k3s.tf               VM iss (k3s single-node)
│   ├── lxc-pihole.tf           LXC sentinel (Pi-hole)
│   ├── variables.tf            input variables
│   ├── .terraform.lock.hcl     ← tracciato (HashiCorp best practice)
│   └── .terraform/             ← ignorato (cache provider, rigenerata da init)
├── ansible/                    Provisioning
│   ├── inventory.yml           houston, iss, sentinel
│   ├── ansible.cfg             host key checking ON
│   ├── requirements.yml        community.general, ansible.posix
│   ├── group_vars/all/         vars.yml, k3s.yml, argocd.yml,
│   │                           cert-manager.yml, vault.yml (ignorato)
│   ├── tasks/                  node-exporter, proxmox-api-users (riusabili)
│   └── playbooks/              houston-setup, pihole-setup, k3s-install,
│                               cert-manager-install, argocd-install, backup
├── k8s/                        Manifesti Kubernetes (GitOps)
│   ├── bootstrap/              applicato a mano una volta sola
│   │   ├── argocd-values.yaml
│   │   ├── cert-manager-values.yaml
│   │   └── applicationset.yaml   git directory generator → una Application
│   │                              per cartella in apps/*
│   └── apps/                   una cartella per servizio (sincronizzata
│                               da ArgoCD):
│      ├── argocd/              Ingress UI ArgoCD
│      ├── cert-manager/        ClusterIssuer + wildcard Certificate +
│      │                        SealedSecret con token Cloudflare
│      ├── cloudflared/         tunnel verso Cloudflare (SealedSecret)
│      ├── homepage/            dashboard dichiarativa dei servizi
│      ├── infra-proxy/         reverse proxy Traefik per host fisici
│      │                        (houston, sentinel, iris)
│      ├── sealed-secrets/      controller Sealed Secrets
│      ├── traefik/             TLSStore wildcard
│      └── uptime-kuma/         status page
├── docs/                       Documentazione (indice in docs/README.md)
│   ├── README.md               indice navigabile
│   ├── roadmap.md              piano in 5 fasi
│   ├── 01-proxmox-install.md
│   ├── 02-network-setup.md     LAN + firewall + Cilium (S2)
│   ├── 03-pihole.md            S0
│   ├── 04-tls.md               S1 + S3 (Let's Encrypt + Cloudflare)
│   ├── 05-storage.md           layout dischi
│   ├── 06-backup.md            S6
│   ├── 09-uptime-kuma.md       S10
│   └── 10-cloudflare-tunnel.md S12
├── certs/                      (ignorata) — directory vuota riservata
│                               a eventuali cert auto-firmati
├── .github/workflows/
│   ├── ci.yml                  terraform/ansible-lint/kubeconform/gitleaks
│   └── terraform-docs.yml      genera terraform/README.md (CI)
├── .gitleaks.toml              estende i default (secrets scanning)
├── .gitignore                  terraform, ansible, packer, secrets
├── AGENTS.md                   regole agenti (opencode, Claude Code)
├── CLAUDE.md → AGENTS.md       symlink per Claude Code
└── opencode.json               config opencode
```

---

## Fasi

| # | Fase                            | Stato  | Sprint chiave                                |
|---|---------------------------------|--------|----------------------------------------------|
| 1 | Backbone                        | 🟢     | S0 Pi-hole, S2 k3s+Cilium, S3 cert-manager, S4 ArgoCD, S5 Sealed Secrets, S6 backup |
| 2 | Accesso & osservabilità         | 🟡     | S10 Uptime Kuma, S12 Cloudflare Tunnel — monitoring (S7-S9) in HOLD |
| 3 | App tue                         | 🔴     | S13 — da pianificare                          |
| 4 | Media                           | 🔴     | S14 storage, S15 Jellyfin, S16 download stack, S17 Jellyseerr |
| 5 | Rete avanzata (VLAN)            | 🔴     | S18 — richiede switch managed                |

DoD di ogni sprint, decisioni architetturali e storia: vedi
[`docs/roadmap.md`](docs/roadmap.md).

---

## Quick start

```bash
# 1. Terraform — crea VM/LXC
cd terraform && terraform init && terraform plan

# 2. Ansible — provisiona gli host
cd ansible && ansible-playbook -i inventory.yml playbooks/houston-setup.yml
cd ansible && ansible-playbook -i inventory.yml playbooks/pihole-setup.yml
cd ansible && ansible-playbook -i inventory.yml playbooks/k3s-install.yml
cd ansible && ansible-playbook -i inventory.yml playbooks/cert-manager-install.yml
cd ansible && ansible-playbook -i inventory.yml playbooks/argocd-install.yml

# 3. Kubernetes
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

> Tutti i playbook sono idempotenti (vedi `ansible-lint` su CI).

---

## Sicurezza e gestione segreti

**Cosa è committato** (e va bene):
- manifest k8s (in chiaro)
- terraform plan/apply dei file `.tf` e `.tfvars.example`
- SealedSecret (`encryptedData:` cifrato col controller, decifrabile solo
  dalla chiave privata in `kube-system`)

**Cosa NON è committato** (gitignored):
- `terraform/terraform.tfvars` (token Proxmox)
- `packer/debian13-base/variables.pkrvars.hcl` (token Packer Proxmox)
- `ansible/group_vars/all/vault.yml` (vault cifrato Ansible)
- `terraform/.terraform/` (cache provider, rigenerata con `init`)
- `terraform/*.tfstate*` (state locale)
- `certs/` (cert self-signed di servizio)
- `*.kubeconfig` (kubeconfig workstation)

**PII in repo**: l'email `casini.cosimo@gmail.com` è presente nei due
`ClusterIssuer` Let's Encrypt (`k8s/apps/cert-manager/clusterissuer-*.yaml`)
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

L'[`ApplicationSet`](k8s/bootstrap/applicationset.yaml) rileva la nuova
cartella entro ~3 minuti e genera l'`Application` ArgoCD automaticamente.

### Linting locale

```bash
cd terraform && terraform fmt -check -diff -recursive
cd terraform && terraform init -backend=false && terraform validate
cd ansible && ansible-lint playbooks/
curl -sSL https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz | tar xz kubeconform
./kubeconform -strict -summary -skip CustomResourceDefinition -ignore-missing-schemas k8s/
```

CI fa tutto questo su ogni push/PR (vedi
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

### Aggiornare un tool pinnato

Le versioni sono in `ansible/group_vars/all/*.yml` e in alcuni file
`k8s/apps/*/deployment.yaml`. Bump intenzionale, test in staging, commit
atomico.

---

## Troubleshooting

- **k3s non raggiungibile**: `ssh iss 'sudo k3s kubectl get nodes'`
- **Cert non emesso**: `kubectl describe certificate -A` e
  `kubectl describe challenge -A` (DNS-01 deve creare TXT su Cloudflare)
- **ArgoCD non sincronizza**: `argocd app list` (via port-forward) o
  controlla la `Application` specifica
- **Vault dimenticato**: `ansible-vault edit ansible/group_vars/all/vault.yml`
  (vedi [AGENTS.md](AGENTS.md) per la password — in chiaro, decidi tu se
  salvarla in un password manager)
- **Storage pieno su NVMe**: `lvs` vede il thin pool; ricorda che lo spazio
  è over-committed, non usato (vedi [docs/05-storage.md](docs/05-storage.md))

Per problemi specifici di un servizio vedi la doc del singolo sprint in
[docs/README.md](docs/README.md).

---

## Licenza

MIT — Copyright (c) 2026 Cosimo Casini.
