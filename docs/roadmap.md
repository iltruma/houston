# Astra — Roadmap

Piano di costruzione della fleet, organizzato in **fasi** e **sprint**.
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
| `nebula`  | NixOS baremetal + k3s      | host | 192.168.178.2 |
| `dyson`      | Cluster k3s (single-node)  | servizio sullo stesso host | 192.168.178.2:6443 (k3s API) |
| `sentinel` | Technitium DNS             | servizio NixOS | 192.168.178.2:53 |

> **Cambiamento post-migrazione**: `dyson` e `sentinel` non sono più VM/LXC
> separati, ma servizi NixOS sullo stesso host `nebula`. L'IP `.2` espone
> tutte le porte (k3s API, DNS, HTTP/HTTPS). `k8s/` resta invariato
> (manifesti k8s parlano di `*.lab.paroparo.it → 192.168.178.2` →
> Traefik su hostNetwork).

---

## Fase 0 — Migrazione NixOS (in corso)

| Sprint | Servizio | Stato | Note |
|--------|----------|-------|------|
| N0     | Flake skeleton + host config | 🟢 | `flake.nix`, `hosts/nebula/`, `modules/common.nix` |
| N1     | Servizi host (Technitium, k3s, backup) | 🟢 | `modules/{technitium,k3s,backup}.nix` |
| N2     | ~~Cilium HelmRelease Flux~~ | ❌ rimosso | `k8s/infra/cilium/` rimosso; CNI è Flannel (vedi D1) |
| N3     | Docs + CI | 🟢 | Doc 00-08 + CI con `nix flake check` |
| N4     | Install fisico + cutover | 🔴 | Seguire [00-nixos-installation.md](00-nixos-installation.md) |
| N5     | Configurazione Technitium (zona, blocklist) | 🔴 | Via web UI dopo install |
| N6     | Validazione end-to-end | 🔴 | kubectl get nodes, flux get all, dig lab.paroparo.it |

**DoD Fase 0**:
- Nebula fa boot da NixOS senza USB
- `nixos-rebuild switch` funziona da workstation remota
- k3s è up, Flannel è attivo, tutti i pod kube-system Running
- Flux sincronizza `k8s/clusters/dyson/` e tutte le Kustomization sono Ready
- Technitium risolve `lab.paroparo.it` per la LAN
- `terraform/`, `ansible/`, `packer/` rimossi (✅ fatto)
- CI verde con `nix flake check`

---

## Fase 1 — Backbone

L'ossatura della fleet. Va completata in ordine perché ogni pezzo sblocca i successivi.

| Sprint | Servizio       | Dove           | Stato | Dipende da |
|--------|----------------|----------------|-------|------------|
| S0     | Technitium DNS | NixOS host (servizio) | 🟢    | —          |
| S1     | TLS (Let's Encrypt) | strategia | 🟢    | —          |
| S2     | k3s            | NixOS host (servizio) | 🟢    | S0         |
| S3     | cert-manager   | k3s            | 🟢    | S1, S2     |
| S4     | Flux CD v2     | k3s            | 🟢    | S2         |
| S5     | SOPS + age     | k3s            | 🟢    | S4         |
| S6     | Backup / DR    | nebula + k3s  | 🟢    | S2         |

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
  bootstrap esterno necessario (vedi [stack-decisions.md](stack-decisions.md#d1--flannel-bundled-k3s)).
- DoD: `k3s kubectl get nodes` mostra `nebula` Ready dalla workstation;
  `k3s kubectl get pods -n kube-system` mostra tutti i pod Running;
  un pod di test riesce a fare DNS lookup verso l'esterno.

**S3 — cert-manager: TLS automatici da Let's Encrypt** · doc: [05-tls.md](05-tls.md)
- `ClusterIssuer` ACME verso Let's Encrypt con solver DNS-01 Cloudflare (token in
  Secret). `Certificate` wildcard `*.lab.paroparo.it`. Split-horizon su Technitium.
- DoD: il `Certificate` wildcard risulta `Ready`, firmato da Let's Encrypt; un
  servizio di test è raggiungibile in HTTPS valido sotto `lab.paroparo.it`.

**S4 — Flux CD v2: GitOps**
- Flux CD (CNCF Graduated) installato via `flux bootstrap github`. La struttura
  `k8s/clusters/dyson/` contiene le `Kustomization` radice; `k8s/infra/` ospita
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
- DoD: `rclone ls r2:nebula-backup/` mostra file; `journalctl -u rclone-backup`
  pulito; la strategia di restore da zero è documentata in [03-backup.md](03-backup.md).


---

## Fase 2 — Accesso & osservabilità

| Sprint | Servizio              | Stato | Note |
|--------|-----------------------|-------|------|
| S10    | Uptime Kuma           | 🟢    | Status page + monitor (HTTP/TCP/DNS/ping). `uptime.lab.paroparo.it`, manifesti in `k8s/apps/uptime-kuma/`, Flux GitOps. Doc: [08-monitoring.md](08-monitoring.md) — verificato 2026-06-20 |
| S11    | Homepage              | 🟢    | dashboard dichiarativa (YAML in Git) dei servizi |
| S12    | ~~Cloudflare Tunnel~~  | ❌ rimosso | Per accesso esterno valutare in futuro Tailscale (mesh VPN, zero infrastruttura). |

> Prometheus+Grafana+Loki rimossi dalla roadmap: troppo complessi per il caso d'uso.
> Per metriche host: Beszel (D7). Per log: `journalctl` via SSH è sufficiente su single-node.

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
esterno collegato a nebula (vedi [02-storage.md](02-storage.md)).

⚠️ **VPN torrent**: il traffico di qBittorrent va instradato su una VPN egress
(es. Mullvad). È cosa diversa dal Cloudflare Tunnel (che è solo accesso inbound).

---

## Fase 5 — Rete avanzata (Piano B VLAN)

> **Prerequisito hardware**:
> - **MikroTik hEX S 2025** (~69€) — router/gateway principale
> - **MikroTik cAP ax** (~129€) — access point WiFi 6, gestito da hEX S via CAPsMAN
> - Fritz!Box 3490 in PPPoE passthrough (bridge VDSL puro)
>
> Senza questo hardware il firewall NixOS (Piano A, già documentato in
> [01-network.md](01-network.md)) è il livello di isolamento disponibile.

| Sprint | Servizio | Note |
|---|---|---|
| S17b | Hardware: hEX S + cAP ax + Fritz bridge | Acquisto hEX S + cAP ax; Fritz!Box in PPPoE passthrough; PPPoE su hEX S Ether1 |
| S18  | VLAN segmentation | VLAN 10/20/30 su hEX S; trunk verso nebula; subinterface NixOS; firewall inter-VLAN |
| S18b | WiFi multi-SSID via CAPsMAN | cAP ax gestito da hEX S; SSID per VLAN 10/20/30 |
| S18c | VLAN 40 downloads | Aggiunta VLAN 40 quando si installa qBittorrent (Fase 4) |

**Schema rete con hEX S + cAP ax:**

```
Internet
    │
Fritz!Box 3490 (bridge VDSL puro — solo modem)
    │ Ethernet
    ▼
hEX S (router, gateway, DHCP, firewall inter-VLAN, WireGuard ingress, CAPsMAN)
    ├── Ether1: WAN — PPPoE verso Aruba (VLAN 100 gestita dal Fritz)
    ├── Ether2: trunk 802.1Q → nebula (enp1s0, tutte le VLAN tagged)
    ├── Ether3: access VLAN 10 → workstation admin
    ├── Ether4: access VLAN 20 → altri device di casa (cablati)
    └── Ether5: trunk 802.1Q → cAP ax (+ injector PoE 802.3af)
                               ├── SSID "home"    → VLAN 10
                               ├── SSID "family"  → VLAN 20
                               └── SSID "guest"   → VLAN 30
```

> ⚠️ **Alimentazione cAP ax**: usare l'alimentatore diretto incluso nella
> confezione. Il PoE passivo dell'hEX S (Ether5, tensione fissa senza
> negoziazione) potrebbe danneggiare il cAP ax se fuori range — non testare.
> Ether5 rimane libero per altri device.

**Schema VLAN target:**

| VLAN | Subnet | Gateway | Ospita | Accesso |
|------|--------|---------|--------|---------|
| 10 — Trusted | `10.10.0.0/24` | `10.10.0.1` | nebula (`10.10.0.2`), workstation admin | tutto |
| 20 — Home | `10.20.0.0/24` | `10.20.0.1` | PC/telefoni altri utenti di casa | Internet + nebula :80/443; no SSH, no k3s API |
| 30 — IoT/Guest | `10.30.0.0/24` | `10.30.0.1` | smart TV, IoT, ospiti WiFi | solo Internet |
| 40 — Downloads | `10.40.0.0/24` | `10.40.0.1` | qBittorrent + VPN egress | solo Internet via VPN (aggiunta in Fase 4) |

**Regole firewall inter-VLAN (hEX S):**

```
VLAN 10 → qualsiasi          ALLOW   # admin, accesso totale
VLAN 20 → Internet           ALLOW
VLAN 20 → nebula :80/:443    ALLOW   # servizi web Traefik
VLAN 20 → nebula :22/:6443   DENY    # SSH e k3s API solo VLAN 10
VLAN 20 → RFC1918            DENY
VLAN 30 → Internet           ALLOW
VLAN 30 → RFC1918            DENY    # isolamento totale dalla LAN
VLAN 40 → Internet via VPN   ALLOW
VLAN 40 → RFC1918            DENY
```

**Cosa cambia su nebula (NixOS):**

- `enp1s0` passa da IP statico diretto a trunk 802.1Q
- Subinterface `enp1s0.10` con IP `10.10.0.2/24` (unica necessaria)
- Gateway diventa `10.10.0.1` (hEX S VLAN 10)
- Record DNS `lab.paroparo.it` aggiornato a `10.10.0.2`
- Firewall NixOS rimane invariato (le porte restano le stesse)

**WireGuard ingress**: gira direttamente sull'hEX S (RouterOS v7 nativo).
I peer remoti entrano in VLAN 10 come se fossero fisicamente in LAN.
Zero modifiche a nebula.

**DoD S18**: dispositivi su VLAN corrette; ping cross-VLAN bloccato dove
atteso; `dig @10.10.0.2 lab.paroparo.it` risolve; servizi nebula
raggiungibili da VLAN 20 su :443, non su :22.

---

## Fase 6 — Visibilità di rete (IDS passivo)

| Sprint | Servizio | Note |
|---|---|---|
| S19 | Suricata IDS | Container passivo su `nebula`, mirror del traffico East-West via `tc mirred` |

**S19 — Suricata IDS (container passivo)**

- **Problema che risolve**: oggi la rete è una scatola nera. Il firewall
  MikroTik/Fritz!Box logga i drop ma non c'è visibilità su **chi parla con chi**
  dentro la LAN e su quali domini/CDN vanno i device. Un cryptominer su un
  container k3s, una IoT compromessa che chiama server russi, un port scan
  interno passano inosservati.
- **Approccio**: Suricata 7 in un **container** su `nebula` (nixos-container
  o podman), **non inline** (IDS only, no IPS). Il traffico di `br0` viene
  clonato con `tc mirred` su una `dummy0` passata al container; Suricata legge
  in modalità promiscua, alert su `eve.json` (newline-delimited JSON).
  Fail-safe: se il container muore, la rete continua a funzionare.
- **Risorse stimate**: 2 GB RAM allocati, 1-2 core CPU, ~300 MB a riposo,
  ~800 MB con ET Open caricato. 16 GB di Nebula bastano con margine.
- **Cosa NON fa** (consapevolmente): non blocca pacchetti (IDS, non IPS), non
  vede il traffico tra device fisici che non passa per nebula (manca una porta
  SPAN sullo switch). Per copertura totale serve OPNsense su mini-PC dedicato
  tra Fritz!Box e switch.
- **Tuning iniziale**: 200-500 falsi positivi attesi nelle prime 24h, da filtrare
  con `disable.conf` (regole ET Open troppo aggressive per astra). Target
  operativo: 5-20 alert/giorno, 1-3 worth investigating.
- **DoD**:
  - Container Suricata su `nebula` (tipo: nixos-container o podman),
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
hosts/nebula/    Config host: disko (ZFS), hardware, networking, default
modules/          Moduli NixOS: common, technitium, k3s, backup
secrets/          *.enc.yaml cifrati con SOPS + age (sops-nix)
k8s/              Manifesti GitOps (Flux): clusters/dyson/, infra/, apps/
docs/             Guide operative: install, network, storage, dns, tls, secrets, gitops
.github/workflows/  CI: nix flake check, kubeconform, gitleaks
.sops.yaml        Regole cifratura SOPS
AGENTS.md         Regole agenti (opencode, Claude Code)
```
