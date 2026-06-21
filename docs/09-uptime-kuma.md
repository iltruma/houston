# S10 — Uptime Kuma (status page e monitor)

## Obiettivo

Monitorare dall'interno la raggiungibilità dei servizi dell'homelab (HTTP,
TCP, DNS, ping) e avere una **status page** interna consultabile via web
con TLS valido.

Non sostituisce l'osservabilità (Prometheus/Grafana, S7, in HOLD) — è un
complemento "binario su/giù" focalizzato sull'utente.

## Stack

| Componente | Versione | Note |
|---|---|---|
| Uptime Kuma | `2.3.0` (image) | pin 2.x, DB SQLite embedded |
| Manifest | raw k8s + Kustomize | stesso pattern di `homepage/`, no Helm chart esterno |

## Pattern

Identico a `homepage/` e `sealed-secrets/`:

- `k8s/apps/uptime-kuma/`: namespace + PVC + Deployment + Service + Ingress
- ArgoCD (via ApplicationSet *git directory generator*) crea l'Application
  e sincronizza le risorse automaticamente.
- TLS: coperto dal wildcard `*.lab.paroparo.it` emesso da cert-manager (S3).
  Niente `Certificate` per-resource.

## Architettura

```
  Browser → https://uptime.lab.paroparo.it
                    │
              Traefik Ingress
                    │
            uptime-kuma:3001
                    │
              ┌─────┴─────┐
              │ SQLite DB │  (PVC 4Gi, /app/data)
              └───────────┘
```

## File nel repo

```
k8s/apps/uptime-kuma/
  ├─ namespace.yaml        # Namespace "uptime-kuma"
  ├─ pvc.yaml              # 4Gi su local-path
  ├─ deployment.yaml       # 1 replica, securityContext stretto
  ├─ service.yaml          # ClusterIP :3001
  ├─ ingress.yaml          # uptime.lab.paroparo.it (wildcard TLS)
  └─ kustomization.yaml
```

## Decisioni tecniche

- **1 replica + `strategy: Recreate`**: Uptime Kuma tiene stato in-memory
  (check attivi, socket.io) e SQLite su PVC. Multi-replica causa
  duplicazione dei check e allarmi inconsistenti. Recreate evita 2 pod
  racing sul PVC.
- **`readOnlyRootFilesystem: true`** + `emptyDir` su `/tmp`: Uptime Kuma
  richiede `/tmp` scrivibile per alcuni check; `/app/data` resta sul PVC.
- **`runAsUser: 1000` + `runAsNonRoot`**: l'image di Uptime Kuma gira come
  UID 1000 (node), non root.
- **PVC 4Gi**: abbondante per SQLite + qualche status page export + extra
  CA certs.

## Pre-requisiti

- S2 (k3s) completato ✓
- S3 (cert-manager + wildcard TLS) completato ✓
- S4 (ArgoCD) completato ✓

## Passi di installazione

L'installazione è **completamente GitOps**: nessun `helm install` o
`kubectl apply` manuale.

1. Commit + push dei file in `k8s/apps/uptime-kuma/`.
2. L'ApplicationSet rileva la nuova cartella `apps/uptime-kuma/` al
   prossimo sync (~3 min) e crea l'`Application` automaticamente.
3. ArgoCD sincronizza le risorse nel cluster.
4. Visitare `https://uptime.lab.paroparo.it`, completare il wizard
   iniziale (crea utente admin), configurare i primi monitor.

## Configurazione monitor (manuale, via web UI)

**Decisione (2026-06-20)**: i monitor si configurano a mano dalla web UI.
Niente playbook Ansible, niente GitOps sui monitor.

**Motivazione**: Uptime Kuma 2.x non ha un'ecosistema stabile per
l'automazione lato Ansible:
- la libreria `lucasheld/uptime-kuma-api` (PyPI) supporta solo 1.21-1.23
- la collection `lucasheld/ansible-uptime-kuma` si basa su quella
- il PR ufficiale per REST API in Uptime Kuma è ancora draft (milestone 3.1)
- i bridge community esistenti (es. `pr1ncey1987/uptime-kuma-api-v2`,
  12★) sono troppo freschi per GitOps serio

Per homelab con 10-15 monitor il web UI è la scelta giusta. Rivedibile
in futuro se cresce a 50+ monitor o se esce un'API REST ufficiale.

## Monitor suggeriti (post-install via web UI)

| Monitor | Tipo | Target | Cosa verifica |
|---|---|---|---|
| ArgoCD | HTTPS | `https://argocd.lab.paroparo.it` | Web UI raggiungibile |
| Homepage | HTTPS | `https://homepage.lab.paroparo.it` | Web UI raggiungibile |
| Pi-hole admin | HTTPS | `https://sentinel.lab.paroparo.it/admin` | Web UI Pi-hole |
| Pi-hole DNS | DNS | `192.168.178.4:53` | DNS ricorsivo risponde |
| k3s API | TCP | `192.168.178.3:6443` | API k8s raggiungibile |
| Pi-hole FTL | HTTP | `http://192.168.178.4:80` | (opzionale) web interna Pi-hole |

## Notifiche (opzionale, da configurare via web UI)

Per ora **nessuna notifica** è configurata. Da abilitare in futuro:

- **Telegram**: bot + chat_id, free, affidabile
- **Email (SMTP)**: richiede SMTP relay
- **Discord / Slack / Gotify / Pushover**: 90+ provider supportati

## Definition of Done

- [x] Pod `Running` nel namespace `uptime-kuma`
- [x] `https://uptime.lab.paroparo.it` raggiungibile con TLS valido
- [x] Wizard di setup visibile (302 → `/setup-database`)
- [x] ArgoCD `Synced/Healthy` sull'app `uptime-kuma`
- [x] PVC `uptime-kuma-data` Bound su `local-path`
- [ ] Wizard completato (utente admin creato) — manuale
- [ ] Almeno 1 monitor configurato — manuale
