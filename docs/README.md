# Astra — Documentation Index

Documentazione operativa del homelab, organizzata per argomento. Per il piano
completo vedi [`roadmap.md`](roadmap.md). Per le decisioni architetturali vedi
[`stack-decisions.md`](stack-decisions.md).

## Dove iniziare

Se è la prima volta che tocchi questo repo:

1. [`00-nixos-installation.md`](00-nixos-installation.md) — installare NixOS baremetal
2. [`01-network.md`](01-network.md) — bridge br0, firewall, DNS
3. [`02-storage.md`](02-storage.md) — layout disco ZFS
4. [`03-backup.md`](03-backup.md) — backup rclone → Cloudflare R2
5. [`04-dns-technitium.md`](04-dns-technitium.md) — Technitium DNS
6. [`05-tls.md`](05-tls.md) — Let's Encrypt + Cloudflare
7. [`06-secrets-sops.md`](06-secrets-sops.md) — SOPS + age
8. [`07-gitops.md`](07-gitops.md) — k3s + Flux CD
9. [`08-monitoring.md`](08-monitoring.md) — Uptime Kuma + Beszel

Per capire *cosa* si sta facendo e *perché*, parti dalla
[roadmap](roadmap.md) e dalle [decisioni architetturali](stack-decisions.md).

## Mappa documentazione

| #   | Argomento                          | Doc                                              |
|-----|------------------------------------|--------------------------------------------------|
| 00  | Installazione NixOS                | [`00-nixos-installation.md`](00-nixos-installation.md) |
| 01  | Rete (bridge, firewall, DNS)       | [`01-network.md`](01-network.md)                 |
| 02  | Storage (ZFS, dataset, snapshot)   | [`02-storage.md`](02-storage.md)                 |
| 03  | Backup off-site (rclone → R2)      | [`03-backup.md`](03-backup.md)                   |
| 04  | DNS Technitium (zona, split-horizon) | [`04-dns-technitium.md`](04-dns-technitium.md) |
| 05  | TLS (cert-manager + Let's Encrypt) | [`05-tls.md`](05-tls.md)                         |
| 06  | Secrets (SOPS + age, host + k8s)   | [`06-secrets-sops.md`](06-secrets-sops.md)       |
| 07  | GitOps (k3s + Flux)                | [`07-gitops.md`](07-gitops.md)                   |
| 08  | Monitoring (Uptime Kuma + Beszel)  | [`08-monitoring.md`](08-monitoring.md)           |
| —   | Roadmap e sprint                   | [`roadmap.md`](roadmap.md)                       |
| —   | Decisioni architetturali           | [`stack-decisions.md`](stack-decisions.md)       |

## Per fase (roadmap)

- **Fase 0 — Migrazione NixOS** (completata, validazione in corso): [00](00-nixos-installation.md)
- **Fase 1 — Backbone** (Kubernetes + DNS + backup): [01](01-network.md) · [04](04-dns-technitium.md) · [05](05-tls.md) · [06](06-secrets-sops.md) · [07](07-gitops.md)
- **Fase 2 — Accesso & osservabilità** (Uptime Kuma attivo, monitoring in corso): [08](08-monitoring.md)
- **Fase 3 — App tue**: nessun doc ancora
- **Fase 4 — Media**: [02](02-storage.md) (storage prerequisito)
- **Fase 5 — Rete avanzata (VLAN)**: [01](01-network.md) (Piano A firewall)

## Convenzioni

- Tutti gli host `*.lab.paroparo.it` risolvono a `192.168.178.2` (split-horizon
  Technitium + wildcard Let's Encrypt). Traefik in k3s (hostNetwork) espone 80/443.
- I secret nel cluster vivono come file `*.enc.yaml` cifrati con SOPS + age in
  `k8s/infra/*/` e `k8s/apps/*/` (mai plaintext in Git)
- I secret host vivono come file `*.enc.yaml` in `secrets/`, decifrati da
  sops-nix all'attivazione, montati in `/run/secrets/`
- Flux CD (kustomize-controller) decifra i secret SOPS automaticamente al sync;
  le `Kustomization` in `k8s/clusters/iss/` governano l'intero albero
- Il flake NixOS (`flake.nix`) è l'unica fonte di verità per OS host e servizi
  NixOS; `nixos-rebuild switch --flake .#eos` applica tutto in modo idempotente

## Comandi rapidi

```bash
# Validare il flake
nix flake check

# Applicare modifiche NixOS (da workstation)
nixos-rebuild switch --flake .#eos --target-host root@192.168.178.2

# Stato k3s
ssh root@192.168.178.2
k3s kubectl get nodes
k3s kubectl get pods -A

# Stato Flux
k3s flux get kustomizations
k3s flux get helmreleases -A

# Stato servizi host
systemctl status technitium-dns-server
systemctl status k3s
systemctl list-timers rclone-backup.timer
```
