# Houston 🛰️

Homelab as Code su un singolo Dell Optiplex 3050 (i5-6500T, 16GB RAM, 500GB SSD)
con **Proxmox VE** come hypervisor. Tutto dichiarativo: infrastruttura in
Terraform, configurazione in Ansible, applicazioni in Kubernetes via GitOps.

> Progetto anche **didattico**: si costruisce un pezzo alla volta, capendo cosa fa.
> Il piano completo è in **[docs/roadmap.md](docs/roadmap.md)**.

## Stack

| Layer            | Tecnologia                          |
|------------------|-------------------------------------|
| Hypervisor       | Proxmox VE                          |
| IaC              | Terraform (provider `bpg/proxmox`)  |
| Config mgmt      | Ansible                             |
| Orchestrazione   | k3s (single-node VM)                |
| GitOps           | ArgoCD                              |
| Ingress          | Traefik (incluso in k3s)            |
| TLS              | cert-manager + Let's Encrypt (DNS-01 Cloudflare) |
| DNS              | Pi-hole                             |

## Architettura

```
                  rete 192.168.178.0/24
  iris     .1  ─  Router Fritz!Box    (gateway)
  houston  .2  ─  Proxmox VE (hypervisor)
  sentinel .4  ─  LXC  Pi-hole        (DNS + adlists)
  iss      .3  ─  VM   k3s single-node
                    ├─ Traefik        (ingress)
                    ├─ cert-manager   (TLS ← Let's Encrypt via DNS-01 Cloudflare)
                    ├─ ArgoCD         (app-of-apps)
                    ├─ SOPS + age     (secret cifrati in Git)
                    └─ app (Fasi 2-4)
```

Dominio: **`lab.paroparo.it`** (record locali in Pi-hole; host + servizi web,
wildcard `*.lab.paroparo.it` → ingress k3s, TLS Let's Encrypt).

## Struttura

```
packer/      Template VM (immagini base Debian per Proxmox)
terraform/   Infrastruttura (VM, LXC, network)
ansible/     Provisioning e configurazione (pihole, k3s)
k8s/         Manifesti Kubernetes (ArgoCD, infra, apps) — in costruzione
docs/        Documentazione passo-passo + roadmap
.github/     Workflow CI/CD
```

## Quick start

```bash
# Terraform — crea VM/LXC
cd terraform && terraform init && terraform plan

# Ansible — provisiona gli host
cd ansible && ansible-playbook -i inventory.yml playbooks/<playbook>.yml

# Kubernetes
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

## Roadmap

Costruzione in 4 fasi (dettaglio e Definition of Done in [docs/roadmap.md](docs/roadmap.md)):

1. **Backbone** — Pi-hole, k3s, cert-manager (Let's Encrypt), ArgoCD, SOPS+age (secrets), backup/DR
2. **Accesso & osservabilità** — Prometheus+Grafana, host monitoring, Loki, Uptime Kuma, Homepage, Cloudflare Tunnel
3. **App tue** — deploy di applicazioni proprie sul cluster
4. **Media** — storage, Jellyfin, download stack, Jellyseerr

## Licenza

MIT — Copyright (c) 2026 Cosimo Casini
