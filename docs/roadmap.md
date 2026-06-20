# Houston Homelab — Roadmap

Piano di costruzione del homelab, organizzato in **fasi** e **sprint**.
Ogni sprint è atomico: lo si fa, lo si verifica (Definition of Done), si committa,
si passa al successivo. Le dipendenze determinano l'ordine.

> Legenda stato: 🟢 fatto · 🟡 parziale · 🔴 da fare

## Convenzioni di rete

| Host       | Ruolo                      | Tipo | IP            |
|------------|----------------------------|------|---------------|
| `iris`     | Router Fritz!Box (gateway) | hw   | 192.168.178.1 |
| `houston`  | Hypervisor Proxmox VE      | host | 192.168.178.2 |
| `iss`      | Cluster k3s (single-node)  | VM   | 192.168.178.3 |
| `sentinel` | Pi-hole (DNS + adlists)    | LXC  | 192.168.178.4 |

- Gateway: `192.168.178.1`
- Dominio unico: **`lab.paroparo.it`** (record locali in Pi-hole; host + servizi
  web via wildcard `*.lab.paroparo.it` → ingress k3s). Niente più `.internal`.
- Dominio servizi web: **`*.lab.paroparo.it`** (TLS Let's Encrypt, split-horizon
  Pi-hole → ingress k3s `.3`; vedi [04-tls.md](04-tls.md))

---

## Fase 1 — Backbone

L'ossatura del homelab. Va completata in ordine perché ogni pezzo sblocca i successivi.

| Sprint | Servizio       | Dove           | Stato | Dipende da |
|--------|----------------|----------------|-------|------------|
| S0     | Pi-hole        | LXC `sentinel` | 🟢    | —          |
| S1     | TLS (Let's Encrypt) | strategia | 🟢    | —          |
| ST     | VM template    | houston        | 🟢    | —          |
| S2     | k3s            | VM `iss`       | 🟢    | ST         |
| S3     | cert-manager   | k3s            | 🟢    | S1, S2     |
| S4     | ArgoCD         | k3s            | 🟢    | S2         |
| S5     | Secrets mgmt   | k3s            | 🟢    | S4         |
| S6     | Backup / DR    | houston + k3s  | 🟢    | S2         |

**S0 — Pi-hole** · doc: [03-pihole.md](03-pihole.md)
- Operativo: install v6 unattended, HTTPS sulla web UI, adlist e record DNS `lab.paroparo.it` via API.
- DoD: `ansible-playbook pihole-setup.yml` gira pulito e idempotente; adlist presenti; gravity aggiornato.
- gli upstream DNS vengono migrati in `pihole.toml` dall'installer v6 (vedi [03-pihole.md](03-pihole.md) §6).

**S1 — TLS: strategia Let's Encrypt** · doc: [04-tls.md](04-tls.md)
- Niente CA privata: certificati pubblici Let's Encrypt via challenge DNS-01 su
  Cloudflare, wildcard `*.lab.paroparo.it`. L'infra (ClusterIssuer + Certificate)
  vive in cert-manager → confluisce in **S3**.
- DoD (S1): dominio su Cloudflare, sottodominio scelto, API token Cloudflare
  creato e salvato. Il DoD sostanziale (cert wildcard emesso) è in S3.

**ST — VM template Debian 13 (Packer)** · dir: `packer/debian13-base/`
- `upload-cloud-image.sh` scarica il cloud image Debian 13 su houston e crea il template grezzo (ID 9000).
- `packer build` clona 9000, installa `qemu-guest-agent`, fa SSH hardening e cleanup, produce il template finale (ID 9001 — `debian13-base`).
- Terraform clona da 9001 per tutte le VM.
- DoD: template `debian13-base` visibile in Proxmox; `terraform plan` non mostra diff sul clone ID.

**S2 — k3s: completare il bootstrap**
- Ansible: fetch del kubeconfig in locale, riscrittura IP server, verifica nodo `Ready`.
- DoD: `kubectl get nodes` mostra `iss` Ready dalla workstation.

**S3 — cert-manager: TLS automatici da Let's Encrypt** · doc: [04-tls.md](04-tls.md)
- `ClusterIssuer` ACME verso Let's Encrypt con solver DNS-01 Cloudflare (token in
  Secret). `Certificate` wildcard `*.lab.paroparo.it`. Split-horizon su Pi-hole.
- DoD: il `Certificate` wildcard risulta `Ready`, firmato da Let's Encrypt; un
  servizio di test è raggiungibile in HTTPS valido sotto `lab.paroparo.it`.

**S4 — ArgoCD: GitOps**
- Install ArgoCD (Helm) + un `ApplicationSet` (*git directory generator*) che genera
  un'`Application` per ogni cartella sotto `k8s/apps/*`: una cartella per servizio,
  con dentro tutti i suoi manifest (ingress, certificate, configmap…). I file di
  bootstrap (values Helm, `ApplicationSet`) stanno in `k8s/bootstrap/`, applicati a
  mano una volta sola.
- DoD: ArgoCD UI raggiungibile via Ingress TLS; l'`ApplicationSet` genera e
  sincronizza le app dal repo.

**S5 — Secrets management: Sealed Secrets**
- Controller Sealed Secrets installato via ArgoCD; i `SealedSecret` cifrati si
  committano in Git, il controller li decifra dentro il cluster.
- DoD: un secret di test, cifrato e committato in Git, viene materializzato come
  `Secret` nel cluster; nessuna credenziale in chiaro nel repo.

**S6 — Backup / disaster recovery**
- Backup dello stato di k3s e dei volumi dati persistenti (su `sata-backup`);
  restore verificato. (Nessuna CA privata da salvare: i cert si riemettono da
  Let's Encrypt.)
- DoD: esiste un backup ripristinabile dello stato cluster; il restore è stato
  testato almeno una volta.


---

## Fase 2 — Accesso & osservabilità

> ⏸️ **IN HOLD** (2026-06-20): un tentativo di Prometheus+Grafana+Loki+Alloy
> ha funzionato ma ha richiesto troppa complessità e decisioni ripetute.
> Rimandato a data da destinarsi. Per ora si resta con Fase 1 completa.

| Sprint | Servizio              | Stato | Note |
|--------|-----------------------|-------|------|
| S7     | Prometheus + Grafana  | 🔴    | `kube-prometheus-stack` via ArgoCD — **HOLD** |
| S8     | Host monitoring       | 🟡    | `node_exporter` su `houston`/`sentinel` installato; scrape attivo solo dopo S7 (Prometheus) — **HOLD** |
| S9     | Loki                  | 🔴    | log aggregation, datasource in Grafana — **HOLD** |
| S10    | Uptime Kuma           | 🔴    | status page / uptime |
| S11    | Homepage              | 🟢    | dashboard dichiarativa (YAML in Git) dei servizi |
| S12    | Cloudflare Tunnel     | 🔴    | accesso remoto inbound senza aprire porte |

ℹ️ **Persistenza**: i servizi con stato (Prometheus, Grafana, Loki, ArgoCD) usano il
provisioner `local-path` di k3s puntato sull'NVMe (`/mnt/k3s-data`). Il SATA SSD
ospita invece media e download (Fase 4). Vedi [05-storage.md](05-storage.md) per il
layout completo dei due dischi.

⚠️ **Cloudflare Tunnel** espone verso l'esterno solo i servizi scelti; gira come
`cloudflared` nel cluster. Usiamo già `paroparo.it` su Cloudflare con certificati
Let's Encrypt, quindi i servizi pubblicati sono già su un dominio pubblico valido.

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
| VLAN 10 | 10.10.0.x | Core infra: sentinel (Pi-hole) |
| VLAN 20 | 10.20.0.x | Cluster: iss (k3s) |
| VLAN 30 | 10.30.0.x | Downloads: qBittorrent + VPN egress (traffico untrusted) |
| VLAN 40 | 10.40.0.x | DMZ: Cloudflare Tunnel exit point (servizi pubblici) |

**Cosa cambia rispetto al Piano A:**

- Il bridge Proxmox diventa VLAN-aware: ogni VM/LXC riceve un tag VLAN nella
  propria configurazione di rete anziché stare tutte sulla stessa L2.
- Il router (o Proxmox come router inter-VLAN) applica policy di routing tra VLAN.
- VLAN 30 (download) non può raggiungere VLAN 10/20 — isolamento hardware
  garantito dallo switch, non solo da firewall software.
- Gli IP cambiano: le VM vanno riconfigurate e i record DNS `lab.paroparo.it`
  aggiornati nel playbook Pi-hole.

**DoD S18**: `iss`, `sentinel` su VLAN distinte; ping cross-VLAN
bloccato dove atteso; DNS `lab.paroparo.it` risolve correttamente dai nuovi IP.

---

## Stato struttura repo

```
packer/      VM template (Debian 13)   — upload script + config Packer (sprint ST)
terraform/   VM e LXC (Proxmox)        — vm-k3s, lxc-pihole
ansible/     provisioning              — pihole, k3s
k8s/         manifesti GitOps          — bootstrap/ (ApplicationSet) + apps/<servizio>/
docs/        guide passo-passo         — install, network, pihole, tls, roadmap
.github/     CI                        — lint/validate (terraform, ansible, k8s) + secret scanning
```
