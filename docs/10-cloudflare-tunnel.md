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

**Single source of truth per ConfigMap: `cloudflared_public_hostnames`** in
`ansible/group_vars/all/cloudflared.yml`.

Ogni entry genera automaticamente una **ingress rule** nel ConfigMap di cloudflared
(rigenerato e committato).

**CNAMEs DNS**: creati **manualmente** nella Cloudflare Zero Trust dashboard
(Networks → Tunnels → homelab → Public Hostname). Non automatizzati per ora.

**File roles**:

- I manifest (Namespace, Deployment) sono in `k8s/apps/cloudflared/` e gestiti
  da ArgoCD
- Il **ConfigMap** `k8s/apps/cloudflared/configmap.yaml` è **generato** dal
  playbook (header "GENERATED, do not edit"). ArgoCD lo sincronizza al cluster.
- Il **Secret** `cloudflared-credentials` contiene il `TUNNEL_TOKEN`. NON è
  in Git: viene applicato a ogni run del playbook leggendo
  `cloudflared_tunnel_token` dal vault (stesso pattern di argocd/grafana)

## Architettura

```
  Internet user → https://uptime.paroparo.it
                       │
                       ▼
                Cloudflare edge (DNS CNAME auto)
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
  ├─ namespace.yaml        # Namespace "cloudflared"
  ├─ configmap.yaml        # GENERATED da cloudflared_public_hostnames
  ├─ deployment.yaml       # 2 repliche, readOnlyRootFilesystem
  └─ kustomization.yaml

ansible/
  ├─ group_vars/all/cloudflared.yml    # tunnel_id, public_hostnames
  ├─ files/cloudflared/config.yaml     # mirror per test locale (generato)
  └─ playbooks/cloudflared-install.yml # render configmap + Secret
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
7. Annotati il **Tunnel ID** (UUID) — lo trovi nella dashboard dopo la
   creazione, oppure nei log del pod dopo il primo deploy. Va in
   `cloudflared_tunnel_id` in `cloudflared.yml`.

> **Nota**: i CNAME DNS si creano manualmente nella dashboard. Il playbook
> renderizza solo il ConfigMap (ingress rules) da `cloudflared_public_hostnames`.

### 2. Aggiungere il token al vault Ansible

```bash
ansible-vault edit ansible/group_vars/all/vault.yml
```

Aggiungi la riga:

```yaml
cloudflared_tunnel_token: "eyJhIjoi...IL_TOKEN..."
```

(genera la password del vault con `openssl rand -base64 32` se non ce l'hai
e salvala in `~/.vault_pass`)

### 3. Aggiungere tunnel_id e (opzionale) zone_id a cloudflared.yml

`cloudflared.yml` contiene già `cloudflared_tunnel_id` e
`cloudflare_zone_id` con i valori usati finora. Se cambi tunnel/dominio,
aggiorna lì.

### 4. Lanciare il playbook (fa tutto lui)

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/cloudflared-install.yml
```

Il playbook:
1. Renderizza `k8s/apps/cloudflared/configmap.yaml` (NUOVO, con header
   "GENERATED, do not edit")
2. Applica il Secret `cloudflared-credentials` con il `TUNNEL_TOKEN`
3. Forza ArgoCD a sincronizzare
4. Aspetta che i pod siano Ready e verifica `/ready`

### 5. Commit + push del configmap.yaml generato

```bash
cd ~/houston
git diff k8s/apps/cloudflared/configmap.yaml    # rivedi cosa è cambiato
git add k8s/apps/cloudflared/configmap.yaml
git commit -m "cloudflared: regenerate configmap (S12)"
git push origin main
```

ArgoCD raccoglie il nuovo ConfigMap, lo applica al cluster, e i pod di
cloudflared si riavviano (rolling update) per leggere la nuova config.

### 6. Verifica da esterno

Da rete **non-LAN** (telefono 4G, VPN fuori casa):

- `https://uptime.paroparo.it` → Uptime Kuma

Nella dashboard Cloudflare (Zero Trust → Tunnels → homelab):
- Status: **Healthy**
- Connections: 2 (una per replica)
- Public Hostnames: `uptime.paroparo.it` (auto-aggiunto)

### Aggiungere un nuovo servizio pubblico (futuro)

1. Aggiungi una entry in `cloudflared_public_hostnames` in `cloudflared.yml`
2. Aggiungi manualmente il public hostname nella Cloudflare dashboard
   (Networks → Tunnels → homelab → Public Hostname)
3. Rilancia il playbook
4. Fai `git diff` → `git add` → `git commit` → `git push`
5. La ingress rule in cloudflared è già attiva

## Definition of Done

- [x] 4 file in `k8s/apps/cloudflared/` committati
- [x] Playbook Ansible committato
- [x] Token in vault Ansible
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
