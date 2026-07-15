# Astra — Stack Decisioni e Motivazioni

Documento di riferimento per le **scelte architetturali** di Astra, con motivazione,
alternative scartate e rischio a lungo termine. Ogni decisione ha uno stato:
- 🟢 **applicato** = in produzione
- 🟡 **parziale** = in corso
- 🔴 **proposto** = documentato, non implementato

---

## Mappa decisioni

| #    | Decisione                            | Stato    | Note |
|------|--------------------------------------|----------|------|
| D1   | CNI: Flannel (bundled k3s)           | 🟢 applicato | Default k3s, sufficiente su single-node |
| D2   | CoreDNS bundled k3s + ConfigMap custom | 🟢 applicato | Delega split-horizon a Technitium |
| D3   | Rimuovere NVMe fisicamente           | 🟢 applicato | Single disk /dev/sda |
| D4   | ArgoCD → Flux CD v2                  | 🟢 applicato | Native SOPS, niente plugin esterni |
| D5   | Kubelet tuning k3s (low-RAM)         | 🟢 applicato | In `modules/k3s.nix` → `extraFlags` |
| D6   | Sealed Secrets → SOPS + age          | 🟢 applicato | Unificato host (sops-nix) + k8s (Flux SOPS) |
| D7   | Beszel monitoring                    | 🟡 parziale | Hub in k3s, agent su host NixOS (opzionale) |
| D8   | RAM upgrade 16 → 32 GB               | 🟡 parziale | Prerequisito hardware, non ancora fatto |
| D9   | Pi-hole v6 → Technitium DNS          | 🟢 applicato | Modulo NixOS nativo (nixpkgs) |
| D10  | Backup rclone → Cloudflare R2        | 🟢 applicato | systemd timer NixOS |
| D11  | Alerting channel (ntfy)              | 🔴 proposto | Beszel + Uptime Kuma → ntfy |
| D12  | Dependency updates (Renovate)        | 🔴 proposto | Aggiornamenti automatici Helm chart, Nix packages |
| D13  | ZFS encryption rimossa               | 🟢 applicato | No threat model reale su homelab; complessità TPM2 > benefici |

---

## D1 — Flannel (bundled k3s)

### Problema

Il bootstrap Cilium su NixOS era fragile per tre ragioni:
1. **Chicken-and-egg**: k3s parte con Flannel disabilitato (`--flannel-backend=none`),
   ma senza CNI l'API server non è operativo e helmfile non può eseguire.
2. **helm-diff plugin**: il path del plugin non era standard in NixOS (store Nix),
   richiedeva workaround con `HELM_PLUGINS` env var nel servizio systemd.
3. **Servizio systemd custom** (`k3s-cilium-bootstrap`): un servizio one-shot
   fragile, difficile da debuggare se falliva in silenzio.

### Scelta: Flannel (CNI bundled)

k3s ha Flannel integrato di default. Non richiede bootstrap esterno, niente
dipendenze aggiuntive, niente servizi systemd custom.

Su single-node homelab Flannel è più che sufficiente: routing L3 tra pod,
niente eBPF/NetworkPolicy avanzate necessarie.

### Alternative future

Cilium può essere aggiunto via Flux `HelmRelease` in futuro quando il cluster
è stabile, senza dipendere da un bootstrap pre-CNI. In quel caso il pattern
helmfile non è necessario perché Flannel fornisce già rete funzionante durante
l'installazione di Cilium.

### Rischio a lungo termine

🟢 Basso — Flannel è il CNI di default di k3s, ampiamente testato su
single-node.

---

## D2 — CoreDNS bundled + ConfigMap custom

### Problema

k3s ha CoreDNS bundled di default. Per il split-horizon (query `.lan` →
Technitium locale), serve un override del Corefile.

### Scelta: ConfigMap `coredns` in `/var/lib/rancher/k3s/server/manifests/`

k3s applica automaticamente i manifest con prefisso `00-` PRIMA del suo
CoreDNS bundled. Il ConfigMap deve avere `name: coredns` (nome esatto che
k3s sovrascrive) per fare override del Corefile di default.

Config in `modules/k3s.nix`:
```nix
environment.etc."k3s/coredns-custom.yaml".text = ''
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: coredns
    namespace: kube-system
  data:
    Corefile: |
      .:53 { ... forward . 192.168.178.2:53 ... }
      lab.paroparo.it:53 { ... forward . 192.168.178.2:53 ... }
'';
```

Symlink in `systemd.tmpfiles.rules`:
```nix
"L+ /var/lib/rancher/k3s/server/manifests/00-coredns-custom.yaml - - - - /etc/k3s/coredns-custom.yaml"
```

### Vantaggi

- Zero helm chart per CoreDNS
- Config versionata nel flake
- k3s lo applica al boot, idempotente

### Rischio a lungo termine

🟢 Basso — pattern documentato da k3s upstream.

---

## D3 — Rimozione NVMe (single disk)

### Problema

Il vecchio setup aveva due dischi:
- SATA SSD 500 GB (`/dev/sda`, OS Proxmox)
- NVMe 500 GB (`/dev/nvme0n1`, VM root + PV k3s)

L'NVMe era fonte di calore/rumore e non usato in modo critico.

### Scelta: rimozione NVMe nel setup NixOS

Nel nuovo setup NixOS c'è solo `/dev/sda` (500 GB). ZFS usa tutto lo spazio
disponibile. PV k3s vivono in `tank/volumes` (ZFS dataset).

### Rischio a lungo termine

🟢 Nessuno — meno dischi = meno roba che può rompersi.

---

## D4 — ArgoCD → Flux CD v2

### Problema

ArgoCD ha tre criticità per un homelab GitOps-puro single-developer:
1. **RAM**: ~500 MB idle (API server + Redis + Dex + controller)
2. **Drift via UI**: la dashboard permette click-ops che bypassano Git
3. **SOPS**: richiede plugin esterno (argocd-vault-plugin)

### Scelta: Flux CD v2

| Metrica           | ArgoCD                            | Flux CD v2                        |
|-------------------|-----------------------------------|-----------------------------------|
| RAM idle          | ~500 MB                           | ~200 MB                           |
| SOPS support      | plugin esterno                    | **nativo** (kustomize-controller) |
| Helm SDK          | `helm template` interno           | **native Helm SDK** (`helm list`) |
| Sync failure      | Si ferma e aspetta                | **Riprova fino a convergenza**    |
| Web UI            | ✅ integrata                      | ❌ solo CLI (`flux`)              |

### Trade-off accettato

Nessuna web UI nativa. Per debug: `flux get all`, `kubectl describe kustomization`,
`flux logs`. Per un homelab single-developer la CLI è sufficiente.

### Rischio a lungo termine

🟢 Basso — CNCF Graduated, adottato in molti ambienti enterprise.

---

## D5 — Kubelet tuning k3s (low-RAM)

### Problema

k3s di default non è ottimizzato per single-node con RAM limitata.

### Scelta: `extraFlags` in `modules/k3s.nix`

```nix
services.k3s.extraFlags = toString [
  "--disable=traefik"              # Traefik via Flux
  "--disable=servicelb"            # non serve
  "--disable=local-storage"        # ZFS fornisce storage
  "--disable=metrics-server"       # Beszel copre monitoring
  "--write-kubeconfig-mode=0644"   # kubeconfig leggibile da utente
];
```

> Nota: `--flannel-backend=none` e `--disable-network-policy` sono stati
> rimossi insieme a Cilium (D1). Flannel è attivo di default.

### Rischio a lungo termine

🟢 Basso — flag k3s/kubelet standard e documentati.

---

## D6 — Sealed Secrets → SOPS + age (unificato)

### Problema

Due toolchain secrets nel vecchio setup:
- Sealed Secrets per k8s (controller in cluster, chiave in `kube-system`)
- Ansible Vault per Ansible (cifrato simmetrico, password condivisa)

Due modi per cifrare, due modi per decifrare, due punti di rottura.

### Scelta: SOPS + age ovunque

| Aspetto | Sealed Secrets | SOPS + age (vecchio) | SOPS + age (nuovo) |
|---------|---------------|---------------------|--------------------|
| Dove vive la chiave | Controller in `kube-system` | File locale + Secret k8s | File locale + Secret k8s (unificato) |
| Reinstall cluster | ❌ secret irrecuperabili | ✅ ricrei il Secret | ✅ ricrei il Secret |
| Host secrets | n/a (solo k8s) | ❌ Ansible Vault separato | ✅ `secrets/*.enc.yaml` con sops-nix |
| PR diff | Base64 illeggibile | Chiavi visibili, valori cifrati | Chiavi visibili, valori cifrati |
| Tools | `kubeseal` | `sops` + `kubectl` | `sops` + `sops-nix` + Flux |

Nel nuovo setup:
- `secrets/*.enc.yaml` → sops-nix (host secrets, mount in `/run/secrets/`)
- `k8s/**/*.enc.yaml` → Flux kustomize-controller (k8s secrets, Secret resource)
- Stessa chiave age in `.sops.yaml`

### Rischio a lungo termine

🟢 Basso — SOPS è maturo (2016), sotto [getsops org](https://github.com/getsops/sops).

---

## D7 — Beszel monitoring

### Problema

Prometheus + Grafana + Loki era in HOLD: troppo complesso, ~500 MB RAM.
Serve sapere CPU/RAM host, disco, container up/down.

### Scelta: Beszel + Uptime Kuma

- **Uptime Kuma**: HTTP/TCP/DNS check, status page. In k3s (HelmRelease).
- **Beszel**: metriche host (CPU, RAM, disco, I/O, rete, temperatura). Hub in k3s, agent opzionale su host NixOS.

### Limitazione: K8s metrics

Beszel non ha supporto K8s nativo. Per metriche per Pod/Deployment come
oggetti K8s serve altro (VictoriaMetrics o simile). Per Eos è accettabile:
l'interesse è il nodo, non l'introspection dei workload.

### Stato

🟡 Parziale — Hub in k3s operativo, agent non ancora deployato su host.

### Rischio a lungo termine

🟡 Medio — progetto giovane (2024), 22k stars, MIT, non CNCF.

---

## D8 — RAM upgrade 16 → 32 GB

### Problema

Con 16 GB RAM: NixOS host (~1 GB) + k3s (~500 MB) + Traefik + cert-manager +
Beszel + Flux = headroom limitato.

### Scelta: DDR4 SO-DIMM 2×16 GB (~35€)

Prerequisito per workload Fase 4 (Jellyfin transcoding) e per buffer generale.

### Stato

🟡 Parziale — non ancora acquistato/installato.

### Rischio a lungo termine

🟢 Basso — hardware commodity, nessun lock-in.

---

## D9 — Pi-hole v6 → Technitium DNS

### Problema

Pi-hole è un ad-blocker DNS, non un server DNS completo. Per il pattern
Eos (`*.lab.paroparo.it` interno → 192.168.178.2, split horizon) servono:
- Zona primaria autoritativa per `lab.paroparo.it`
- Record wildcard gestibile
- Split horizon (risposta diversa per query interne vs esterne)
- DoH/DoT built-in

Pi-hole v6 non supporta nessuno di questi nativamente.

### Scelta: Technitium DNS (modulo NixOS nativo)

`pkgs.technitium-dns-server` v15.2.0 in nixpkgs con modulo
`services.technitium-dns-server`:
- systemd hardened (`DynamicUser`, `NoNewPrivileges`, `ProtectSystem=strict`)
- `StateDirectory` gestito automaticamente
- Web UI su `127.0.0.1:5380` (accesso via SSH tunnel)
- Niente container/Docker, gira come servizio host

Vedi [04-dns-technitium.md](04-dns-technitium.md) per la configurazione.

### Rischio a lungo termine

🟡 Medio — sviluppatore singolo (Shreyas Zare). Attivo dal 2017, GPL-3, forkabile.

---

## D10 — Backup rclone → Cloudflare R2

### Problema

Lo stato attuale (no backup off-site) non è un DR reale. I dati che **non** si
possono ricostruire da Git:
- `/var/lib/technitium-dns-server/` (zona DNS, blocklist)
- `/var/lib/rancher/k3s/` (etcd, certificati k3s)
- `/home/` (dotfiles)

### Scelta: rclone crypt → Cloudflare R2

- **Cloudflare R2**: S3-compatible, free tier 10 GB, **zero egress fees**
- **rclone**: client universale, supporta S3 + cifratura client-side
- **systemd timer NixOS** (`modules/backup.nix`): esecuzione notturna alle 03:00

```nix
systemd.services.rclone-backup = {
  serviceConfig.ExecStart = ''
    rclone sync /var/lib/technitium-dns-server r2:eos-backup/technitium/
    rclone sync /var/lib/rancher/k3s r2:eos-backup/k3s/
    rclone sync /home r2:eos-backup/home/
  '';
};
systemd.timers.rclone-backup = {
  timerConfig.OnCalendar = "*-*-* 03:00:00";
  timerConfig.Persistent = true;
};
```

Configurazione R2 in `secrets/rclone-env.enc.yaml` (cifrato con sops-nix).

### Rischio a lungo termine

🟢 Basso — rclone maturo (~45k stars), Cloudflare R2 servizio commerciale stabile.

---

## D11 — Alerting channel (ntfy)

### Problema

Beszel e Uptime Kuma hanno alert configurabili ma senza un canale notifiche
sono inutili. Senza notifiche, disco pieno o servizio down vengono scoperti
per caso.

### Scelta: ntfy (self-hosted o `ntfy.sh`)

**ntfy** è push notification self-hosted. Sia Beszel che Uptime Kuma lo
supportano nativamente.

`ntfy.sh` pubblico è OK per iniziare (topic privato = stringa casuale).
Migra a self-hosted se vuoi eliminare la dipendenza esterna.

### Stato

🔴 Proposto — non ancora configurato.

### Rischio a lungo termine

🟢 Basso — MIT, 18k stars, attivamente mantenuto.

---

## D12 — Dependency updates (Renovate)

### Problema

Le versioni sono pinnate ovunque (Helm chart, Nix packages) ma senza un
meccanismo automatico di bump. Nel tempo: Cilium EOL silenzioso,
cert-manager non aggiornato, ecc.

### Scelta: Renovate Bot

Configurazione minima in `.renovaterc.json`:
- Aggiorna Helm chart in `HelmRelease` Flux
- Aggiorna Nix packages (via flake-update detection)
- Aggiorna GitHub Actions
- Schedule settimanale

### Stato

🔴 Proposto — `.renovaterc.json` esiste ma Renovate non è ancora attivato
su GitHub.

### Rischio a lungo termine

🟢 Basso — Mend-backed, usato in migliaia di repo.

---

## D13 — ZFS encryption rimossa

### Problema

`tank/root` era cifrato (AES-256-GCM) con chiave in TPM2 (`modules/zfs-tpm2.nix`).
Questo aggiungeva:
- Dipendenza da TPM2 al boot (chip presente ma non standard su Optiplex 3050)
- Prompt al boot se TPM2 falliva
- Modulo NixOS extra (`zfs-tpm2.nix`) da mantenere
- Complessità di recovery (perdita TPM = perdita dati)

### Threat model reale

Astra è un homelab domestico su rete casuale. Il rischio di furto fisico con
attacco ai dati a disco è trascurabile. I dati sensibili (credenziali,
certificati) sono già protetti da SOPS + age. La cifratura del filesystem di
root non aggiungeva protezione pratica.

### Scelta: ZFS senza cifratura

`tank/root` e tutti i dataset senza `encryption`, `keyformat`, `keylocation`.
ZFS resta per snapshot, CoW, compressione zstd — i motivi per cui è stato
scelto.

### Possibilità futura

Dataset cifrati specifici (es. `tank/secrets`) restano possibili senza
impatto sul boot, se in futuro il threat model cambia.

### Rischio a lungo termine

🟢 Nessuno sul fronte operativo. Se il threat model cambiasse (colocation,
ufficio), rivalutare.

---

## Note aperte

### CI: kubeconform

Schema Flux già incluso nel catalogo datree. Aggiornamenti futuri dei CRD
incluso automaticamente.

### DR test

Da eseguire almeno una volta dopo la migrazione NixOS:
1. `nix flake check` verde
2. `nixos-install --flake .#eos` su disco pulito
3. Verifica che k3s, Flannel, Flux ripartano
4. Verifica che Technitium risolva `lab.paroparo.it`
5. Verifica che il backup rclone sia leggibile da R2

Pianificare come sprint stand-alone dopo il cutover.
