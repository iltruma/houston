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

**Half-GitOps, half-vault**:

- I manifest (Namespace, ConfigMap, Deployment) sono in `k8s/apps/cloudflared/`
  e gestiti da ArgoCD come per tutti gli altri servizi
- Il **token** del tunnel NON è in Git: sta in `ansible/group_vars/all/vault.yml`
  come `cloudflared_tunnel_token` (Ansible Vault, cifrato a riposo)
- Il playbook `cloudflared-install.yml` applica un Secret k8s a ogni run
  leggendo il token dal vault (stesso pattern di argocd/grafana)
- La **DNS pubblica** (CNAME → tunnel endpoint) si crea dalla dashboard
  Cloudflare quando aggiungi un "public hostname" al tunnel. Non è in Git.

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
  ├─ configmap.yaml        # config.yaml: ingress rules
  ├─ deployment.yaml       # 2 repliche, readOnlyRootFilesystem
  └─ kustomization.yaml

ansible/
  ├─ group_vars/all/cloudflared.yml    # image, replicas, tunnel name
  ├─ files/cloudflared/config.yaml     # mirror per test locale
  └─ playbooks/cloudflared-install.yml # applica Secret + wait
```

## Decisioni tecniche

- **2 repliche**: HA minima, più `cloudflared` possono servire lo stesso
  tunnel. Oltre 2 è over-engineering per homelab.
- **`no-autoupdate: true`**: in k3s il pod viene sostituito dal Deployment
  rollout, un binario auto-updated andrebbe perso.
- **`readOnlyRootFilesystem` + `emptyDir` su `/tmp`**: richiesto da
  cloudflared per file temporanei.
- **`credentials-file: /etc/cloudflared/creds/credentials.json`**:
  il Secret viene montato come file (formato richiesto da cloudflared).
  Alternativa env var `TUNNEL_TOKEN` esiste ma il file è più pulito.
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
6. Nella sezione "Public Hostname", aggiungi:
   - Subdomain: `uptime`, Domain: `paroparo.it`, Service:
     `http://uptime-kuma.uptime-kuma.svc.cluster.local:3001`
   - Subdomain: `argocd`, Domain: `paroparo.it`, Service:
     `http://argocd-server.argocd.svc.cluster.local:80`
7. (Opzionale, v2) abilita Cloudflare Access policies per proteggere
   gli endpoint pubblici.

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

### 3. Commit + push dei manifesti (se non già fatto)

```bash
git add -A
git commit -m "feat(cloudflared): S12 manifest"
git push origin main
```

ArgoCD crea namespace + ConfigMap + Deployment (in attesa del Secret).

### 4. Lanciare il playbook (applica il Secret e verifica)

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/cloudflared-install.yml
```

Output atteso:
- Secret applicato
- Pod cloudflared 2/2 Ready
- `/ready` endpoint risponde 200 (tunnel connesso a Cloudflare)

### 5. Verifica da esterno

Da rete **non-LAN** (telefono 4G, VPN fuori casa):

- `https://uptime.paroparo.it` → Uptime Kuma
- `https://argocd.paroparo.it` → ArgoCD login

Nella dashboard Cloudflare (Zero Trust → Tunnels → homelab) dovresti vedere:
- Status: **Healthy**
- Connections: 2 (una per replica)
- Active connections: dipende dal traffico

## Definition of Done

- [x] 4 file in `k8s/apps/cloudflared/` committati
- [x] Playbook Ansible committato
- [x] Token in vault Ansible
- [x] Pod `cloudflared` 2/2 Running
- [x] `/ready` endpoint OK (tunnel connesso)
- [x] Dashboard Cloudflare: tunnel `homelab` Healthy
- [x] `https://uptime.paroparo.it` raggiungibile da rete esterna
- [x] `https://argocd.paroparo.it` raggiungibile da rete esterna

## Note future (v2)

- **Cloudflare Access policies**: proteggere ArgoCD con email OTP
  (chiunque con la tua email può fare login)
- **WARP**: VPN Cloudflare per accesso "privato" al cluster senza
  esporre servizi su Internet
- **Tunnel HA**: >2 repliche non serve, ma si può fare
- **Più tunnel separati**: uno per servizio, se uno si compromette
