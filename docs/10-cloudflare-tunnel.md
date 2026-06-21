# S12 — Cloudflare Tunnel (accesso esterno inbound)

## Obiettivo

Esporre i servizi del cluster (ArgoCD, Uptime Kuma, future app) su Internet
**senza aprire porte sul Fritz!Box** e senza IP pubblico statico.

`cloudflared` apre una connessione in uscita verso Cloudflare e la tiene
viva; il traffico in ingresso da Cloudflare rientra da quel tunnel.

## Stack

| Componente | Versione | Note |
|---|---|---|
| `cloudflared` | `2025.5.0` (image) | ultima 2025.x, pin |
| Tunnel name | `homelab` | creato una volta in Cloudflare Zero Trust |

## Pattern

**Tutti i manifest sono GitOps**: Namespace, Deployment e ConfigMap vivono in
`k8s/apps/cloudflared/` e sono sincronizzati da ArgoCD. Si editano a mano e si
committano.

**CNAMEs DNS**: creati **manualmente** nella Cloudflare Zero Trust dashboard
(Networks → Tunnels → homelab → Public Hostname). Non automatizzati per ora.

**File roles**:

- I manifest (Namespace, Deployment, ConfigMap) sono in `k8s/apps/cloudflared/`
  e gestiti da ArgoCD. Il **ConfigMap** `configmap.yaml` (ingress rules) si
  edita a mano e si committa.
- Il **Secret** `cloudflared-credentials` contiene il `TUNNEL_TOKEN`. È in Git
  cifrato come **SealedSecret** (`cloudflared-credentials-sealedsecret.yaml`):
  ArgoCD lo applica e il controller Sealed Secrets lo decifra in-cluster nel
  Secret montato dal pod. Il playbook Ansible non applica più nulla: fa solo
  da smoke test del rollout.

## Architettura

```
  Internet user → https://uptime.paroparo.it
                       │
                       ▼
                Cloudflare edge (DNS CNAME manuale)
                       │
                       │  outbound long-lived HTTPS (cloudflared pod)
                       │
              cloudflared pod (k3s, 2 repliche)
                       │
                       │  legge config.yaml: hostname → service
                       ▼
              Service: uptime-kuma:3001 (in-cluster)
```

## File nel repo

```
k8s/apps/cloudflared/
  ├─ namespace.yaml                            # Namespace "cloudflared"
  ├─ configmap.yaml                            # ingress rules (scritto a mano, GitOps)
  ├─ cloudflared-credentials-sealedsecret.yaml # TUNNEL_TOKEN cifrato (GitOps)
  ├─ deployment.yaml                           # 2 repliche, readOnlyRootFilesystem
  └─ kustomization.yaml

ansible/
  └─ playbooks/cloudflared-install.yml # solo smoke test del rollout (nessun secret)
```

## Decisioni tecniche

- **2 repliche**: HA minima, più `cloudflared` possono servire lo stesso
  tunnel. Oltre 2 è over-engineering per homelab.
- **`no-autoupdate: true`**: in k3s il pod viene sostituito dal Deployment
  rollout, un binario auto-updated andrebbe perso.
- **`readOnlyRootFilesystem` + `emptyDir` su `/tmp`**: richiesto da
  cloudflared per file temporanei.
- **`TUNNEL_TOKEN` env var**: il token JWT (lungo `eyJhIjoi...`) letto dal
  Secret è self-contained: contiene già tunnel ID + credenziali. È
  l'unica auth necessaria, **non** servono `tunnel:` o
  `credentials-file:` nella config (sono del vecchio flusso con
  cert.pem e fanno fallire con "Cannot determine default origin
  certificate path").
- **`runAsUser: 65532` (nobody)**: l'image ufficiale di cloudflared gira
  come utente non-root.
- **No Cloudflare Access/Zero Trust policies** in v1: chi sa l'URL entra.
  Da aggiungere in v2 (es. email OTP).

## Pre-requisiti

- S2 (k3s) ✓
- S3 (cert-manager + wildcard `*.lab.paroparo.it`) ✓
- S4 (ArgoCD) ✓
- S10 (Uptime Kuma) ✓ (per test)
- **Account Cloudflare con dominio `paroparo.it`** ✓ (già usato per S3)
- **Tunnel creato in Cloudflare Zero Trust** (manual, vedi sotto)

## Passi di installazione

### 1. Creare il tunnel (manuale, lo fai tu)

1. Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels** →
   **Create a tunnel**
2. Tipo: **Cloudflared**
3. Nome: `homelab`
4. Nella schermata "Install connector", **copia solo il token**
   (un JWT lungo che inizia con `eyJhIjoi...`)
5. **NON** eseguire il comando proposto (lo gestiamo via Ansible)
6. Nella sezione "Public Hostname", aggiungi manualmente:
   - Subdomain: `uptime`, Domain: `paroparo.it`, Service:
     `http://uptime-kuma.uptime-kuma.svc.cluster.local:3001`
   (ArgoCD e altri servizi si aggiungeranno in seguito, **v1 = solo Kuma**)
7. Il **Tunnel ID** (UUID) serve solo per creare i CNAME DNS
   (`<tunnel-id>.cfargotunnel.com`) nella dashboard. Lo trovi nella dashboard
   o nei log del pod dopo il primo deploy. Non va salvato nel repo.

> **Nota**: i CNAME DNS si creano manualmente nella dashboard. Le ingress rules
> stanno in `k8s/apps/cloudflared/configmap.yaml` (scritto a mano, GitOps).

### 2. Sigillare il token in un SealedSecret

Il `TUNNEL_TOKEN` non va mai in chiaro nel repo: lo si cifra con `kubeseal`
(chiave pubblica del controller Sealed Secrets) e si committa solo il blob
cifrato. Il plaintext non tocca né cluster né disco (`--dry-run=client` + pipe):

```bash
export KUBECONFIG=~/.kube/config-k3s
read -rs CF_TUNNEL_TOKEN          # incolla il JWT eyJhIjoi..., Invio (non mostrato)
kubectl create secret generic cloudflared-credentials \
  --namespace cloudflared \
  --from-literal=token="$CF_TUNNEL_TOKEN" \
  --dry-run=client -o yaml \
| kubeseal --controller-namespace kube-system \
    --controller-name sealed-secrets-controller \
    --format yaml \
> k8s/apps/cloudflared/cloudflared-credentials-sealedsecret.yaml
unset CF_TUNNEL_TOKEN
```

Verifica che il file contenga `encryptedData` (e **non** `data:`) prima di committare.

### 3. Commit + push (ArgoCD applica tutto)

```bash
git add k8s/apps/cloudflared/ && git commit -m "feat(k8s): seal cloudflared tunnel token" && git push
```

ArgoCD applica Namespace, ConfigMap, SealedSecret e Deployment; il controller
decifra il SealedSecret nel Secret `cloudflared-credentials`. Opzionale, come
smoke test del rollout:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/cloudflared-install.yml
```

### 4. Verifica da esterno

Da rete **non-LAN** (telefono 4G, VPN fuori casa):

- `https://uptime.paroparo.it` → Uptime Kuma

Nella dashboard Cloudflare (Zero Trust → Tunnels → homelab):
- Status: **Healthy**
- Connections: 2 (una per replica)
- Public Hostnames: `uptime.paroparo.it` (aggiunto a mano)

### Aggiungere un nuovo servizio pubblico (futuro)

1. Aggiungi una entry nella lista `ingress` in
   `k8s/apps/cloudflared/configmap.yaml` (prima del catch-all 404)
2. Crea il CNAME DNS nella Cloudflare dashboard
   (Networks → Tunnels → homelab → Public Hostname)
3. `git add` → `git commit` → `git push`: ArgoCD applica il ConfigMap e
   i pod ricaricano la config (rolling update)

Se cambia il token, ri-sigillalo (passo 2) e committa il nuovo SealedSecret:
ArgoCD lo sincronizza e il controller aggiorna il Secret.

## Definition of Done

- [x] 4 file in `k8s/apps/cloudflared/` committati
- [x] Playbook Ansible committato (smoke test)
- [x] Token cifrato come SealedSecret in Git
- [x] Pod `cloudflared` 2/2 Running
- [x] `/ready` endpoint OK (tunnel connesso)
- [x] Dashboard Cloudflare: tunnel `homelab` Healthy
- [x] `https://uptime.paroparo.it` raggiungibile da rete esterna

## Note future (v2)

- **Cloudflare Access policies**: proteggere ArgoCD con email OTP
  (chiunque con la tua email può fare login)
- **WARP**: VPN Cloudflare per accesso "privato" al cluster senza
  esporre servizi su Internet
- **Tunnel HA**: >2 repliche non serve, ma si può fare
- **Più tunnel separati**: uno per servizio, se uno si compromette
