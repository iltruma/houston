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
- Dominio interno: **`.internal`** (record locali gestiti in Pi-hole "Local DNS")

---

## Fase 1 — Backbone

L'ossatura del homelab. Va completata in ordine perché ogni pezzo sblocca i successivi.

| Sprint | Servizio       | Dove           | Stato | Dipende da |
|--------|----------------|----------------|-------|------------|
| S0     | Pi-hole        | LXC `sentinel` | 🟢    | —          |
| S1     | step-ca        | LXC `vanguard` | 🟢    | —          |
| ST     | VM template    | houston        | 🟢    | —          |
| S2     | k3s            | VM `iss`       | 🟢    | ST         |
| S3     | cert-manager   | k3s            | 🟢    | S1, S2     |
| S4     | ArgoCD         | k3s            | 🟢    | S2         |
| S5     | Secrets mgmt   | k3s            | 🔴    | S4         |
| S6     | Backup / DR    | houston + k3s  | 🔴    | S1, S2     |

**S0 — Pi-hole** · doc: [03-pihole.md](03-pihole.md)
- Operativo: install v6 unattended, HTTPS sulla web UI, adlist e record DNS `.internal` via API.
- DoD: `ansible-playbook pihole-setup.yml` gira pulito e idempotente; adlist presenti; gravity aggiornato.
- da verificare: che gli upstream DNS finiscano in `pihole.toml` su v6 (vedi [03-pihole.md](03-pihole.md) §6).

**S1 — step-ca: CA di rete** · doc: [04-stepca.md](04-stepca.md)
- Terraform: LXC `vanguard`. Ansible: install `step`/`step-ca`, init CA (root+intermediate), provisioner ACME, systemd.
- DoD: ACME directory raggiungibile su `https://vanguard.internal:9000/acme/acme/directory`; root CA esportata e installata nel trust store di almeno un client.

**ST — VM template Debian 13 (Packer)** · dir: `packer/debian13-base/`
- `upload-cloud-image.sh` scarica il cloud image Debian 13 su houston e crea il template grezzo (ID 9000).
- `packer build` clona 9000, installa `qemu-guest-agent`, fa SSH hardening e cleanup, produce il template finale (ID 9001 — `debian13-base`).
- Terraform clona da 9001 per tutte le VM.
- DoD: template `debian13-base` visibile in Proxmox; `terraform plan` non mostra diff sul clone ID.

**S2 — k3s: completare il bootstrap**
- Ansible: fetch del kubeconfig in locale, riscrittura IP server, verifica nodo `Ready`.
- DoD: `kubectl get nodes` mostra `iss` Ready dalla workstation.

**S3 — cert-manager: TLS automatici dalla CA**
- `ClusterIssuer` di tipo ACME che punta a step-ca; trust della root CA nel controller.
- DoD: un `Certificate` di test viene emesso e risulta `Ready`, firmato dalla Houston Homelab CA.

**S4 — ArgoCD: GitOps**
- Install ArgoCD + pattern *app-of-apps* (una root `Application` che punta a `k8s/`).
- DoD: ArgoCD UI raggiungibile via Ingress TLS; la root app sincronizza dal repo.

**S5 — Secrets management: Sealed Secrets**
- Controller Sealed Secrets installato via ArgoCD; i `SealedSecret` cifrati si
  committano in Git, il controller li decifra dentro il cluster.
- DoD: un secret di test, cifrato e committato in Git, viene materializzato come
  `Secret` nel cluster; nessuna credenziale in chiaro nel repo.

**S6 — Backup / disaster recovery**
- Backup della root/intermediate CA (`/etc/step-ca` su `vanguard`), dello stato di
  k3s e dei volumi dati persistenti; restore verificato.
- DoD: esiste un backup ripristinabile di CA e stato cluster; il restore è stato
  testato almeno una volta.


---

## Fase 2 — Accesso & osservabilità

| Sprint | Servizio              | Note |
|--------|-----------------------|------|
| S7     | Prometheus + Grafana  | `kube-prometheus-stack` via ArgoCD |
| S8     | Host monitoring       | `node_exporter` su `houston`/`sentinel`/`vanguard` → scrape da Prometheus (Proxmox + LXC, non solo il cluster) |
| S9     | Loki                  | log aggregation, datasource in Grafana |
| S10    | Uptime Kuma           | status page / uptime |
| S11    | Homepage              | dashboard dichiarativa (YAML in Git) dei servizi |
| S12    | Cloudflare Tunnel     | accesso remoto inbound senza aprire porte |

ℹ️ **Persistenza**: i servizi con stato (Prometheus, Grafana, Loki, ArgoCD) usano il
provisioner `local-path` di k3s puntato sull'NVMe (`/mnt/k3s-data`). Il SATA SSD
ospita invece media e download (Fase 4). Vedi [05-storage.md](05-storage.md) per il
layout completo dei due dischi.

⚠️ **Cloudflare Tunnel** richiede un **dominio pubblico su Cloudflare** (non `.internal`).
Espone verso l'esterno solo i servizi scelti; gira come `cloudflared` nel cluster.
I cert interni `.internal` della CA **non** valgono verso l'esterno: per i servizi
pubblicati serve un certificato pubblico (Cloudflare origin cert o Let's Encrypt).

---

## Fase 3 — App tue

| Sprint | Servizio | Note |
|--------|----------|------|
| S13    | Deploy app personale/i | una o più app proprie sul k3s, via ArgoCD, con Ingress TLS dalla CA |

Obiettivo: usare tutto il backbone (GitOps + TLS + ingress) per pubblicare codice tuo.

---

## Fase 4 — Media

| Sprint | Servizio                | Note |
|--------|-------------------------|------|
| S14    | Storage persistente     | **prerequisito**: Longhorn o NFS verso disco/NAS |
| S15    | Jellyfin                | media server, transcoding HW via Intel QuickSync |
| S16    | Download stack          | qBittorrent (⚠️ dietro VPN egress) + Prowlarr + Sonarr + Radarr + Bazarr |
| S17    | Jellyseerr              | UI di richiesta film/serie |

⚠️ **Reality check hardware**: il SATA SSD da 500GB ospita la media library (~300GB
disponibili dopo OS e VM). Per una collezione estesa servirà un HDD esterno o NAS
(vedi [05-storage.md](05-storage.md)).

⚠️ **VPN torrent**: il traffico di qBittorrent va instradato su una VPN egress
(es. Mullvad). È cosa diversa dal Cloudflare Tunnel (che è solo accesso inbound).

---

## Fase 5 — Rete avanzata (Piano B VLAN)

> **Prerequisito hardware**: switch managed (es. TP-Link TL-SG108E ~30€,
> Netgear GS308E ~40€, o MikroTik). Senza switch managed il firewall Proxmox
> (Piano A, già documentato in [02-network-setup.md](02-network-setup.md))
> è il livello di isolamento disponibile.

| Sprint | Servizio | Note |
|---|---|---|
| S18 | VLAN segmentation | Bridge `vmbr0` VLAN-aware; riassegnazione IP per VLAN; firewall inter-VLAN su Proxmox |

**Schema VLAN target:**

| VLAN | Subnet | Ospita |
|---|---|---|
| VLAN 1 (native) | 192.168.178.x | Management: workstation, Proxmox host |
| VLAN 10 | 10.10.0.x | Core infra: sentinel (Pi-hole), vanguard (step-ca) |
| VLAN 20 | 10.20.0.x | Cluster: iss (k3s) |
| VLAN 30 | 10.30.0.x | Downloads: qBittorrent + VPN egress (traffico untrusted) |
| VLAN 40 | 10.40.0.x | DMZ: Cloudflare Tunnel exit point (servizi pubblici) |

**Cosa cambia rispetto al Piano A:**

- Il bridge Proxmox diventa VLAN-aware: ogni VM/LXC riceve un tag VLAN nella
  propria configurazione di rete anziché stare tutte sulla stessa L2.
- Il router (o Proxmox come router inter-VLAN) applica policy di routing tra VLAN.
- VLAN 30 (download) non può raggiungere VLAN 10/20 — isolamento hardware
  garantito dallo switch, non solo da firewall software.
- Gli IP cambiano: le VM vanno riconfigurate e i record DNS `.internal`
  aggiornati nel playbook Pi-hole.

**DoD S18**: `iss`, `sentinel`, `vanguard` su VLAN distinte; ping cross-VLAN
bloccato dove atteso; DNS `.internal` risolve correttamente dai nuovi IP.

---

## Stato struttura repo

```
packer/      VM template (Debian 13)   — upload script + config Packer (sprint ST)
terraform/   VM e LXC (Proxmox)        — vm-k3s, lxc-pihole, lxc-stepca
ansible/     provisioning              — pihole, k3s, step-ca
k8s/         manifesti + ArgoCD        — (da creare in S3+)
docs/        guide passo-passo         — install, network, pihole, stepca, roadmap
```
