# Monitoring — Uptime Kuma + Beszel

Stack di monitoring leggero: Uptime Kuma per availability, Beszel per metriche
host. Entrambi girano come pod k8s, gestiti da Flux.

## Uptime Kuma — status page + check

[Uptime Kuma](https://github.com/louislam/uptime-kuma) è un monitor self-hosted
con UI web. Supporta HTTP, TCP, DNS, ping, push, e molti altri check.

### Deploy

In [`k8s/apps/uptime-kuma/`](../k8s/apps/uptime-kuma/):
- `namespace.yaml` — namespace dedicato
- `deployment.yaml` — Uptime Kuma 1.x
- `service.yaml` — ClusterIP
- `ingress.yaml` — `uptime.lab.paroparo.it`
- `pvc.yaml` — 5 Gi per la DB SQLite

### Configurazione

Dopo il primo deploy:
1. Accedi a `https://uptime.lab.paroparo.it`
2. Crea utente admin
3. Aggiungi monitor per ogni servizio:
   - `eos.lab.paroparo.it` (HTTP, keyword check)
   - `k3s.lab.paroparo.it` o equivalente (TCP 6443)
   - DNS check: `dig @192.168.178.2 lab.paroparo.it` (keyword: NXDOMAIN/NOERROR)
   - Servizi app: `beszel.lab.paroparo.it`, `homepage.lab.paroparo.it`, ecc.
4. (Opzionale) Status page pubblica: `status.lab.paroparo.it`
5. Notifiche: configurare canale (vedi sotto)

## Beszel — metriche host

[Beszel](https://github.com/henrygd/beszel) è un monitor leggero (hub + agent)
per metriche host: CPU, RAM, disco, I/O, rete, temperatura.

### Deploy

In [`k8s/apps/beszel/`](../k8s/apps/beszel/):
- `namespace.yaml`
- `hub-deployment.yaml` — Beszel hub
- `hub-service.yaml`
- `hub-pvc.yaml` — DB hub
- `hub-ingress.yaml` — `beszel.lab.paroparo.it`
- `agent-daemonset.yaml` — agent in ogni nodo k8s (per ora solo eos)

### Limitazione: agent su host NixOS

Beszel non ha supporto K8s nativo. L'agent nel DaemonSet gira come pod
`privileged` con `hostPath` su `/proc`, `/sys`, `/var/lib/rancher/k3s`. Metriche
host OK, metriche per Pod/Deployment come oggetti K8s no.

Per avere un agent sul **host NixOS** (fuori da k3s), serve installarlo via Nix:

```nix
# modules/beszel-agent.nix (da creare)
services.beszel-agent = {
  enable = true;
  host = "beszel.lab.paroparo.it";
  port = 45876;
  # Secret key condiviso con l'hub (in secrets/beszel-agent-key.enc.yaml)
};
```

> **Stato**: agent host non ancora implementato. Per ora l'agent nel DaemonSet
> fornisce le metriche host base.

## Notifiche

Entrambi supportano notifiche push. Canali consigliati:

| Canale | Tipo | Note |
|--------|------|------|
| **ntfy** | Push notification | Self-hosted o `ntfy.sh` pubblico (free tier) |
| Telegram | Bot | Richiede bot token |
| Discord | Webhook | Gratuito |
| Email | SMTP | Lento, ma sempre funziona |

### ntfy (consigliato)

[ntfy](https://ntfy.sh) è push notification self-hosted. ~10 MB RAM.

1. Crea topic: `https://ntfy.sh/eos-<random-string>` (stringa random = privatezza)
2. Sottoscrivi dal telefono (app ntfy)
3. Configura in Uptime Kuma e Beszel

> Vedi `stack-decisions.md#d15--alerting-channel-ntfy` per il setup completo
> (proposto, non ancora implementato).

## Backup

- Uptime Kuma: PV `5Gi` con SQLite DB. Backup con rclone in `/var/lib/rancher/k3s/...`
- Beszel: PV con DB hub. Stesso backup.

## Verifica

```bash
# Uptime Kuma raggiungibile
curl -v https://uptime.lab.paroparo.it
# HTTP 200, UI visibile

# Beszel raggiungibile
curl -v https://beszel.lab.paroparo.it
# HTTP 200, login page

# Metriche raccolte
# Da Beszel UI: dashboard con CPU, RAM, disco di eos
```

## Roadmap

| Decisione | Stato | Note |
|-----------|-------|------|
| D11 — Beszel monitoring | 🟡 parziale | Hub OK, agent host NixOS da implementare |
| D11 — Alerting ntfy | 🔴 proposto | Da configurare dopo Beszel agent host |

## Alternative considerate (per memoria)

- **Prometheus + Grafana + Loki**: in HOLD. Troppo complesso (~500 MB+ RAM),
  centinaia di MB di storage. Per single-host è overkill.
- **VictoriaMetrics + Grafana**: più leggero di Prometheus. Da rivalutare se
  servono PromQL o log aggregation.
- **Netdata**: buono ma più pesante di Beszel, no UI comparabile.
- **Glances**: troppo minimale, no storage storico.

## Riferimenti

- [Uptime Kuma](https://github.com/louislam/uptime-kuma)
- [Beszel](https://github.com/henrygd/beszel)
- [ntfy](https://ntfy.sh)
