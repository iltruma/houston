# Houston Homelab — Roadmap

Piano di costruzione del homelab, organizzato in **fasi** e **sprint**.
Ogni sprint è atomico: lo si fa, lo si verifica (Definition of Done), si committa,
si passa al successivo. Le dipendenze determinano l'ordine.

> Legenda stato: 🟢 fatto · 🟡 parziale · 🔴 da fare

## Convenzioni di rete

| Host       | Ruolo                      | Tipo | IP            |
|------------|----------------------------|------|---------------|
| `houston`  | Hypervisor Proxmox VE      | host | 192.168.178.2 |
| `iss`      | Cluster k3s (single-node)  | VM   | 192.168.178.3 |
| `sentinel` | Pi-hole (DNS + adlists)    | LXC  | 192.168.178.4 |
| `vanguard` | step-ca (CA di rete, ACME) | LXC  | 192.168.178.5 |

- Gateway: `192.168.178.1`
- Dominio interno: **`iris.lan`** (record locali gestiti in Pi-hole "Local DNS")

---

## Fase 1 — Backbone

L'ossatura del homelab. Va completata in ordine perché ogni pezzo sblocca i successivi.

| Sprint | Servizio       | Dove           | Stato | Dipende da |
|--------|----------------|----------------|-------|------------|
| S0     | Pi-hole        | LXC `sentinel` | 🟢    | —          |
| S1     | step-ca        | LXC `vanguard` | 🟢    | —          |
| S2     | k3s            | VM `iss`       | 🟡    | —          |
| S3     | cert-manager   | k3s            | 🔴    | S1, S2     |
| S4     | ArgoCD         | k3s            | 🔴    | S2         |
| S5     | headroom       | k3s            | 🔴    | S4         |

**S0 — Pi-hole: chiudere il setup**
- Fix del task "Add adlists via API" (errori `UNIQUE`/`FOREIGN KEY` su gravity DB).
- DoD: `ansible-playbook pihole-setup.yml` gira pulito e idempotente; adlist presenti; gravity aggiornato.

**S1 — step-ca: CA di rete**
- Terraform: LXC `vanguard`. Ansible: install `step`/`step-ca`, init CA (root+intermediate), provisioner ACME, systemd.
- DoD: ACME directory raggiungibile su `https://vanguard.iris.lan:9000/acme/acme/directory`; root CA esportata e installata nel trust store di almeno un client.

**S2 — k3s: completare il bootstrap**
- Ansible: fetch del kubeconfig in locale, riscrittura IP server, verifica nodo `Ready`.
- DoD: `kubectl get nodes` mostra `iss` Ready dalla workstation.

**S3 — cert-manager: TLS automatici dalla CA**
- `ClusterIssuer` di tipo ACME che punta a step-ca; trust della root CA nel controller.
- DoD: un `Certificate` di test viene emesso e risulta `Ready`, firmato dalla Houston Homelab CA.

**S4 — ArgoCD: GitOps**
- Install ArgoCD + pattern *app-of-apps* (una root `Application` che punta a `k8s/`).
- DoD: ArgoCD UI raggiungibile via Ingress TLS; la root app sincronizza dal repo.

**S5 — headroom: primo carico applicativo**
- Deploy via ArgoCD con Ingress TLS. (Dettagli immagine/porta/env da verificare sul repo upstream chopratejas/headroom.)
- DoD: headroom raggiungibile e gestito da ArgoCD (sync = Healthy).

---

## Fase 2 — Accesso & osservabilità

| Sprint | Servizio              | Note |
|--------|-----------------------|------|
| S6     | Prometheus + Grafana  | `kube-prometheus-stack` via ArgoCD |
| S7     | Loki                  | log aggregation, datasource in Grafana |
| S8     | Uptime Kuma           | status page / uptime |
| S9     | Homepage              | dashboard dichiarativa (YAML in Git) dei servizi |
| S10    | Cloudflare Tunnel     | accesso remoto inbound senza aprire porte |

⚠️ **Cloudflare Tunnel** richiede un **dominio pubblico su Cloudflare** (non `iris.lan`).
Espone verso l'esterno solo i servizi scelti; gira come `cloudflared` nel cluster.

---

## Fase 3 — App tue

| Sprint | Servizio | Note |
|--------|----------|------|
| S11    | Deploy app personale/i | una o più app proprie sul k3s, via ArgoCD, con Ingress TLS dalla CA |

Obiettivo: usare tutto il backbone (GitOps + TLS + ingress) per pubblicare codice tuo.

---

## Fase 4 — Media

| Sprint | Servizio                | Note |
|--------|-------------------------|------|
| S12    | Storage persistente     | **prerequisito**: Longhorn o NFS verso disco/NAS |
| S13    | Jellyfin                | media server, transcoding HW via Intel QuickSync |
| S14    | Download stack          | qBittorrent (⚠️ dietro VPN egress) + Prowlarr + Sonarr + Radarr + Bazarr |
| S15    | Jellyseerr              | UI di richiesta film/serie |

⚠️ **Reality check hardware**: 500GB SSD totali sull'Optiplex non bastano per una
libreria media (TB). Lo **storage** (S12) va risolto prima — disco aggiuntivo o NAS via NFS.

⚠️ **VPN torrent**: il traffico di qBittorrent va instradato su una VPN egress
(es. Mullvad). È cosa diversa dal Cloudflare Tunnel (che è solo accesso inbound).

---

## Stato struttura repo

```
terraform/   VM e LXC (Proxmox)        — vm-k3s, lxc-pihole, lxc-stepca
ansible/     provisioning              — pihole, k3s, step-ca
k8s/         manifesti + ArgoCD        — (da creare in S3+)
docs/        guide passo-passo         — install, network, questa roadmap
```
