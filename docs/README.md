# Houston — Documentation Index

Documentazione operativa del homelab, organizzata per fase e sprint.
Per il piano completo vedi [`roadmap.md`](roadmap.md).

## Dove iniziare

Se è la prima volta che tocchi questo repo:

1. [`01-proxmox-install.md`](01-proxmox-install.md) — installare Proxmox VE su houston
2. [`02-network-setup.md`](02-network-setup.md) — LAN, IP statici, firewall, Cilium
3. [`03-pihole.md`](03-pihole.md) — DNS + ad-blocking (sentinel)
4. [`04-tls.md`](04-tls.md) — strategia Let's Encrypt + Cloudflare
5. [`05-storage.md`](05-storage.md) — layout dischi (NVMe + SATA)
6. [`06-backup.md`](06-backup.md) — backup/DR vzdump
7. [`09-uptime-kuma.md`](09-uptime-kuma.md) — status page e monitor
8. [`10-cloudflare-tunnel.md`](10-cloudflare-tunnel.md) — accesso esterno inbound

Per capire *cosa* si sta facendo e *perché*, parti dalla
[roadmap](roadmap.md). Per i dettagli operativi di un singolo sprint,
la tabella sotto indica quale doc aprire.

## Mappa sprint → documentazione

| Sprint | Servizio / attività          | Doc di riferimento                                  | Stato  |
|--------|------------------------------|-----------------------------------------------------|--------|
| —      | Roadmap completa             | [`roadmap.md`](roadmap.md)                          | 🟢     |
| ST     | VM template Debian 13        | [`packer/debian13-base/`](../packer/debian13-base/) | 🟢     |
| S0     | Pi-hole                      | [`03-pihole.md`](03-pihole.md)                      | 🟢     |
| S1     | TLS (strategia)              | [`04-tls.md`](04-tls.md)                            | 🟢     |
| S2     | k3s + Cilium CNI             | [`02-network-setup.md`](02-network-setup.md) (Cilium) | 🟢   |
| S3     | cert-manager + wildcard TLS  | [`04-tls.md`](04-tls.md) (impl)                     | 🟢     |
| S4     | ArgoCD (GitOps)              | [`k8s/README.md`](../k8s/README.md)                 | 🟢     |
| S5     | Sealed Secrets               | [`k8s/apps/sealed-secrets/README.md`](../k8s/apps/sealed-secrets/README.md) | 🟢 |
| S6     | Backup / DR                  | [`06-backup.md`](06-backup.md)                      | 🟢     |
| S7     | Prometheus + Grafana         | (HOLD)                                              | 🔴     |
| S8     | Host monitoring              | (HOLD — node_exporter installato, scrape in S7)     | 🟡     |
| S9     | Loki                         | (HOLD)                                              | 🔴     |
| S10    | Uptime Kuma                  | [`09-uptime-kuma.md`](09-uptime-kuma.md)            | 🟢     |
| S11    | Homepage                     | (manifesti in `k8s/apps/homepage/`)                 | 🟢     |
| S12    | Cloudflare Tunnel            | [`10-cloudflare-tunnel.md`](10-cloudflare-tunnel.md) | 🟡    |
| S13    | App personali                | da pianificare                                      | 🔴     |
| S14+   | Media, VLAN, …               | [`roadmap.md`](roadmap.md) (fasi 4-5)                | 🔴     |

Legenda: 🟢 fatto · 🟡 parziale · 🔴 da fare.

## Per fase

- **Fase 1 — Backbone** (completa): [01](01-proxmox-install.md) · [02](02-network-setup.md) · [03](03-pihole.md) · [04](04-tls.md) · [05](05-storage.md) · [06](06-backup.md)
- **Fase 2 — Accesso & osservabilità** (in corso / HOLD su monitoring): [09](09-uptime-kuma.md) · [10](10-cloudflare-tunnel.md)
- **Fase 3 — App tue**: nessun doc ancora, esempi nelle app esistenti
- **Fase 4 — Media**: [05](05-storage.md) (storage prerequisito)
- **Fase 5 — Rete avanzata (VLAN)**: [02](02-network-setup.md) (Piano A firewall)

## Convenzioni

- Tutti gli host `*.lab.paroparo.it` risolvono a `192.168.178.3` (split-horizon
  Pi-hole + wildcard Let's Encrypt)
- I playbook Ansible si lanciano con `--ask-vault-pass` (vault cifrato in
  `ansible/group_vars/all/vault.yml`, escluso dal repo)
- I secret nel cluster vivono come `SealedSecret` in
  `k8s/apps/*/kustomization.yaml` (mai plaintext)
- L'`ApplicationSet` in `k8s/bootstrap/applicationset.yaml` rileva
  automaticamente nuove cartelle in `k8s/apps/*/` (~3 min di polling)
