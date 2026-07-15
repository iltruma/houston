# Astra Homelab — Roadmap

Piano di costruzione del homelab, organizzato in **fasi** e **sprint**.
Ogni sprint è atomico: lo si fa, lo si verifica (Definition of Done), si committa,
si passa al successivo. Le dipendenze determinano l'ordine.

> Legenda stato: 🟢 fatto · 🟡 parziale · 🔴 da fare

> **Migrazione completata (Fase 0)**: Proxmox VE rimosso, tutto ora gira su
> NixOS baremetal. Stack: flake NixOS per OS/servizi host, k3s come servizio,
> Flux per GitOps k8s. Vedi [00-nixos-installation.md](00-nixos-installation.md)
> e [stack-decisions.md](stack-decisions.md) per le scelte architetturali.

## Convenzioni di rete

| Host       | Ruolo                      | Tipo | IP            |
|------------|----------------------------|------|---------------|
| `iris`     | Router Fritz!Box (gateway) | hw   | 192.168.178.1 |
| `eos`  | NixOS baremetal + k3s      | host | 192.168.178.2 |
| `iss`      | Cluster k3s (single-node)  | servizio sullo stesso host | 192.168.178.2:6443 (k3s API) |
| `sentinel` | Technitium DNS             | servizio NixOS | 192.168.178.2:53 |

> **Cambiamento post-migrazione**: `iss` e `sentinel` non sono più VM/LXC
> separati, ma servizi NixOS sullo stesso host `eos`. L'IP `.2` espone
> tutte le porte (k3s API, DNS, HTTP/HTTPS). `k8s/` resta invariato
> (manifesti k8s parlano di `*.lab.paroparo.it → 192.168.178.2` →
> Traefik su hostNetwork).

---

## Fase 0 — Migrazione NixOS (in corso)

| Sprint | Servizio | Stato | Note |
|--------|----------|-------|------|
| N0     | Flake skeleton + host config | 🟢 | `flake.nix`, `hosts/eos/`, `modules/common.nix` |
| N1     | Servizi host (Technitium, k3s, backup) | 🟢 | `modules/{technitium,k3s,backup}.nix` |
| N2     | ~~Cilium HelmRelease Flux~~ | ❌ rimosso | `k8s/infra/cilium/` rimosso; CNI è Flannel (vedi D1) |
| N3     | Docs + CI | 🟢 | Doc 00-08 + CI con `nix flake check` |
| N4     | Install fisico + cutover | 🔴 | Seguire [00-nixos-installation.md](00-nixos-installation.md) |
| N5     | Configurazione Technitium (zona, blocklist) | 🔴 | Via web UI dopo install |
| N6     | Validazione end-to-end | 🔴 | kubectl get nodes, flux get all, dig lab.paroparo.it |

**DoD Fase 0**:
- Eos fa boot da NixOS senza USB
- `nixos-rebuild switch` funziona da workstation remota
- k3s è up, Flannel è attivo, tutti i pod kube-system Running
- Flux sincronizza `k8s/clusters/iss/` e tutte le Kustomization sono Ready
- Technitium risolve `lab.paroparo.it` per la LAN
- `terraform/`, `ansible/`, `packer/` rimossi (✅ fatto)
- CI verde con `nix flake check`

---

## Fase 1 — Backbone

L'ossatura del homelab. Va completata in ordine perché ogni pezzo sblocca i successivi.

| Sprint | Servizio       | Dove           | Stato | Dipende da |
|--------|----------------|----------------|-------|------------|
| S0     | Technitium DNS | NixOS host (servizio) | 🟢    | —          |
| S1     | TLS (Let's Encrypt) | strategia | 🟢    | —          |
| S2     | k3s            | NixOS host (servizio) | 🟢    | S0         |
| S3     | cert-manager   | k3s            | 🟢    | S1, S2     |
| S4     | Flux CD v2     | k3s            | 🟢    | S2         |
| S5     | SOPS + age     | k3s            | 🟢    | S4         |
| S6     | Backup / DR    | eos + k3s  | 🟢    | S2         |

**S0 — Technitium DNS** · doc: [04-dns-technitium.md](04-dns-technitium.md)
- DNS ricorsivo + blocklist per tutta la rete, split-horizon per `lab.paroparo.it`.
- Servizio NixOS nativo (modulo `services.technitium-dns-server` v15.2.0+); zona
  `lab.paroparo.it` con wildcard `*.lab.paroparo.it → 192.168.178.2`; upstream DoH.
- DoD: `systemctl status technitium-dns-server` active; zona configurata via web UI; blocklist attive; `dig @192.168.178.2 lab.paroparo.it` risponde.

**S1 — TLS: strategia Let's Encrypt** · doc: [05-tls.md](05-tls.md)
- Niente CA privata: certificati pubblici Let's Encrypt via challenge DNS-01 su
  Cloudflare, wildcard `*.lab.paroparo.it`. L'infra (ClusterIssuer + Certificate)
  vive in cert-manager → confluisce in **S3**.
- DoD (S1): dominio su Cloudflare, sottodominio scelto, API token Cloudflare
  creato e salvato. Il DoD sostanziale (cert wildcard emesso) è in S3.

**S2 — k3s: completare il bootstrap** · doc: [07-gitops.md](07-gitops.md)
- NixOS `services.k3s` con Flannel come CNI di default (bundled). Nessun
  bootstrap esterno necessario (vedi [stack-decisions.md](stack-decisions.md#d17--cilium-rimosso--flannel-bundled-k3s)).
- DoD: `k3s kubectl get nodes` mostra `eos` Ready dalla workstation;
  `k3s kubectl get pods -n kube-system` mostra tutti i pod Running;
  un pod di test riesce a fare DNS lookup verso l'esterno.

**S3 — cert-manager: TLS automatici da Let's Encrypt** · doc: [05-tls.md](05-tls.md)
- `ClusterIssuer` ACME verso Let's Encrypt con solver DNS-01 Cloudflare (token in
  Secret). `Certificate` wildcard `*.lab.paroparo.it`. Split-horizon su Technitium.
- DoD: il `Certificate` wildcard risulta `Ready`, firmato da Let's Encrypt; un
  servizio di test è raggiungibile in HTTPS valido sotto `lab.paroparo.it`.

**S4 — Flux CD v2: GitOps**
- Flux CD (CNCF Graduated) installato via `flux bootstrap github`. La struttura
  `k8s/clusters/iss/` contiene le `Kustomization` radice; `k8s/infra/` ospita
  le HelmRelease di infrastruttura (Traefik, cert-manager); `k8s/apps/` ospita
  i servizi applicativi. Il kustomize-controller riconcilia ogni 10 minuti.
- DoD: `flux get kustomizations` mostra tutte le kustomization `Ready`; un
  manifest committato nel repo viene applicato al cluster entro il polling.

**S5 — Secrets management: SOPS + age**
- La chiave pubblica age è dichiarata in `.sops.yaml`; i file `*.enc.yaml` cifrati
  si committano in Git. Il kustomize-controller usa la chiave privata (Secret
  `sops-age` in `flux-system`) per decifrare al momento del sync.
- DoD: i token Cloudflare (API token cert-manager) cifrati come `*.enc.yaml`
  e committati in Git vengono materializzati come `Secret` dal controller;
  nessuna credenziale in chiaro nel repo.

**S6 — Backup / disaster recovery** · doc: [03-backup.md](03-backup.md)
- Strategia GitOps-first: il cluster è ricostruibile da Git in ~2-3 ore
  (nixos-install + Flux sync). I dati applicativi vengono sincronizzati
  su **Cloudflare R2** via `rclone` con systemd timer notturno
  (`modules/backup.nix`). Retention 7 giorni.
- DoD: `rclone ls r2:eos-backup/` mostra file; `journalctl -u rclone-backup`
  pulito; la strategia di restore da zero è documentata in [03-backup.md](03-backup.md).


---

## Fase 2 — Accesso & osservabilità

| Sprint | Servizio              | Stato | Note |
|--------|-----------------------|-------|------|
| S10    | Uptime Kuma           | 🟢    | Status page + monitor (HTTP/TCP/DNS/ping). `uptime.lab.paroparo.it`, manifesti in `k8s/apps/uptime-kuma/`, Flux GitOps. Doc: [08-monitoring.md](08-monitoring.md) — verificato 2026-06-20 |
| S11    | Homepage              | 🟢    | dashboard dichiarativa (YAML in Git) dei servizi |
| S12    | ~~Cloudflare Tunnel~~  | ❌ rimosso | Per accesso esterno valutare in futuro Tailscale (mesh VPN, zero infrastruttura). |

> Prometheus+Grafana+Loki rimossi dalla roadmap: troppo complessi per il caso d'uso.
> Per metriche host: Beszel (D11). Per log: `journalctl` via SSH è sufficiente su single-node.

---

## Fase 3 — App tue

| Sprint | Servizio | Note |
|--------|----------|------|
| S13    | Deploy app personale/i | una o più app proprie sul k3s, via Flux, con Ingress TLS dalla CA |
| S13b   | Technitium DNS zone auto-import | `system.activationScripts` chiama API Technitium per importare `dns-zone.lab.paroparo.it` ad ogni rebuild. Richiede token API in sops. **Per ora**: import manuale via web UI al reinstall. |

Obiettivo: usare tutto il backbone (GitOps + TLS + ingress) per pubblicare codice tuo.

---

## Fase 4 — Media

| Sprint | Servizio                | Note |
|--------|-------------------------|------|
| S15    | Jellyfin                | media server, transcoding HW via Intel QuickSync |
| S16    | Download stack          | qBittorrent (⚠️ dietro VPN egress) + Prowlarr + Sonarr + Radarr + Bazarr |
| S17    | Jellyseerr              | UI di richiesta film/serie |

⚠️ **Storage**: i workload media usano un dataset ZFS dedicato (`tank/media`) montato
come `hostPath` su k3s. Niente Longhorn. Per una collezione estesa servirà un HDD
esterno collegato a eos (vedi [02-storage.md](02-storage.md)).

⚠️ **VPN torrent**: il traffico di qBittorrent va instradato su una VPN egress
(es. Mullvad). È cosa diversa dal Cloudflare Tunnel (che è solo accesso inbound).

---

## Fase 5 — Rete avanzata (Piano B VLAN)

> **Prerequisito hardware**: switch managed (es. TP-Link TL-SG108E ~30€,
> Netgear GS308E ~40€, o MikroTik). Senza switch managed il firewall NixOS
> (Piano A, già documentato in [01-network.md](01-network.md))
> è il livello di isolamento disponibile.

| Sprint | Servizio | Note |
|---|---|---|
| S18 | VLAN segmentation | Bridge `br0` VLAN-aware; riassegnazione IP per VLAN; firewall inter-VLAN su NixOS |

**Schema VLAN target:**

| VLAN | Subnet | Ospita |
|---|---|---|
| VLAN 1 (native) | 192.168.178.x | Management: workstation, host eos |
| VLAN 10 | 10.10.0.x | Core infra: sentinel (Technitium DNS) |
| VLAN 20 | 10.20.0.x | Cluster: iss (k3s) |
| VLAN 30 | 10.30.0.x | Downloads: qBittorrent + VPN egress (traffico untrusted) |
| VLAN 40 | 10.40.0.x | DMZ: Cloudflare Tunnel exit point (servizi pubblici) |

**Cosa cambia rispetto al Piano A:**

- Il bridge NixOS `br0` diventa VLAN-aware: ogni container/VM riceve un tag
  VLAN nella propria configurazione di rete anziché stare tutti sulla stessa L2.
- Il router (o NixOS come router inter-VLAN) applica policy di routing tra VLAN.
- VLAN 30 (download) non può raggiungere VLAN 10/20 — isolamento hardware
  garantito dallo switch, non solo da firewall software.
- Gli IP cambiano: le VM vanno riconfigurate e i record DNS `lab.paroparo.it`
  aggiornati nel playbook Technitium.

**DoD S18**: `iss`, `sentinel` su VLAN distinte; ping cross-VLAN
bloccato dove atteso; DNS `lab.paroparo.it` risolve correttamente dai nuovi IP.

---

## Fase 6 — Visibilità di rete (IDS passivo)

| Sprint | Servizio | Note |
|---|---|---|
| S19 | Suricata IDS | Container passivo su `eos`, mirror del traffico East-West via `tc mirred` |

**S19 — Suricata IDS (container passivo)**

- **Problema che risolve**: oggi la rete è una scatola nera. Il firewall
  MikroTik/Fritz!Box logga i drop ma non c'è visibilità su **chi parla con chi**
  dentro la LAN e su quali domini/CDN vanno i device. Un cryptominer su un
  container k3s, una IoT compromessa che chiama server russi, un port scan
  interno passano inosservati.
- **Approccio**: Suricata 7 in un **container** su `eos` (nixos-container
  o podman), **non inline** (IDS only, no IPS). Il traffico di `br0` viene
  clonato con `tc mirred` su una `dummy0` passata al container; Suricata legge
  in modalità promiscua, alert su `eve.json` (newline-delimited JSON).
  Fail-safe: se il container muore, la rete continua a funzionare.
- **Risorse stimate**: 2 GB RAM allocati, 1-2 core CPU, ~300 MB a riposo,
  ~800 MB con ET Open caricato. 16 GB di Eos bastano con margine.
- **Cosa NON fa** (consapevolmente): non blocca pacchetti (IDS, non IPS), non
  vede il traffico tra device fisici che non passa per eos (manca una porta
  SPAN sullo switch). Per copertura totale serve OPNsense su mini-PC dedicato
  tra Fritz!Box e switch.
- **Tuning iniziale**: 200-500 falsi positivi attesi nelle prime 24h, da filtrare
  con `disable.conf` (regole ET Open troppo aggressive per homelab). Target
  operativo: 5-20 alert/giorno, 1-3 worth investigating.
- **DoD**:
  - Container Suricata su `eos` (tipo: nixos-container o podman),
    `eth0` su `br0`, `suricata0` come mirror di `br0` via `tc mirred`.
  - `systemctl status suricata` active; `suricata-update` con ET Open enabled.
  - `eve.json` viene popolato in `/var/log/suricata/`; un alert reale (es.
    DNS verso dominio noto di C2 o tentativo SSH brute force) viene catturato
    in un test controllato.
  - Tuning di base: `HOME_NET` = `192.168.178.0/24`, checksum validation
    disabilitato per gestire checksum offload del bridge `br0`, prime 48h di
    log riviste e `disable.conf` compilato.
  - Doc dedicata `11-suricata.md` (o `09-suricata.md`) con i passi riproducibili
    e il runbook di tuning.
- **Quando farlo**: dopo S18 (VLAN). Le VLAN producono traffico segmentato
  dove un IDS brilla (anomalie per segmento); farlo prima è spreco perché il
  traffico East-West è banale.

---

## Stato struttura repo

```
flake.nix         Entry point NixOS (pin nixpkgs, sops-nix, disko)
hosts/eos/    Config host: disko (ZFS), hardware, networking, default
modules/          Moduli NixOS: common, technitium, k3s, backup
secrets/          *.enc.yaml cifrati con SOPS + age (sops-nix)
k8s/              Manifesti GitOps (Flux): clusters/iss/, infra/, apps/
docs/             Guide operative: install, network, storage, dns, tls, secrets, gitops
.github/workflows/  CI: nix flake check, kubeconform, gitleaks
.sops.yaml        Regole cifratura SOPS
AGENTS.md         Regole agenti (opencode, Claude Code)
```
