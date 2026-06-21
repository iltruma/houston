# S5 — Secrets management: SOPS + age (KSOPS in ArgoCD)

## Obiettivo

Gestire i Secret del cluster in **GitOps puro**: cifrati con **SOPS + age**,
committati in Git, **decifrati da ArgoCD** al sync via plugin **KSOPS**.
Nessun Secret in chiaro nel repo, nessun `kubectl apply` fuori banda.

Sostituisce **Sealed Secrets** (era S5, controller installato ma mai usato —
rimosso in questo sprint).

## Perché SOPS+age al posto di Sealed Secrets

| | Sealed Secrets | SOPS + age |
|---|---|---|
| Chiave di decifratura | nel controller in-cluster | file `age` in mano tua, **fuori** dal cluster |
| Disaster recovery | serve ripristinare la master key del controller | basta il file `age` (più semplice) |
| Diff in Git | ri-sigillare = file sempre diverso (churn) | re-encrypt stabile sui valori non cambiati |
| Unifica con Ansible | no | sì: stessa logica di `ansible-vault` già in uso |

Per un homelab single-node con repo pubblico e DR da zero (S6/NVMe), SOPS+age dà
un recovery più pulito e un solo strumento di cifratura su tutto l'IaC.

## Architettura

```
  Tu (workstation)                    Cluster k3s (iss)
  ────────────────                    ─────────────────
  age private key  ──(una volta)──►   Secret sops-age (ns argocd)
  (~/.config/sops/age/keys.txt)            │
        │ cifra con                        │ montata in
        │ age PUBLIC key                   ▼
        ▼                            argocd-repo-server + KSOPS (CMP sidecar)
  *.enc.yaml  ──git push──►  Git  ──sync──►  decifra → Secret nel cluster
  (cifrato, committabile)
```

- **age**: cifratura asimmetrica. La **chiave pubblica** (`age1...`) cifra, la
  **privata** decifra. La privata NON entra mai in Git.
- **SOPS**: cifra solo i *valori* (`data`/`stringData`) di un manifest, lasciando
  in chiaro chiavi e struttura → diff Git leggibili.
- **KSOPS**: plugin Kustomize che, dentro il repo-server di ArgoCD, decifra i file
  SOPS al momento del `kustomize build`. La chiave privata è montata da un Secret.

## Componenti

| Dove | Cosa | Gestione |
|---|---|---|
| workstation | binari `age`, `sops`, `ksops`, `kustomize` | install locale (tu) |
| repo root | `.sops.yaml` (regole di cifratura) | Git |
| `k8s/bootstrap/argocd-values.yaml` | repo-server con KSOPS (sidecar/init) | Git (bootstrap) |
| cluster, ns `argocd` | Secret `sops-age` (chiave privata) | fuori banda, una volta |
| `k8s/apps/*/...enc.yaml` + `secret-generator.yaml` | Secret cifrati + generatori KSOPS | Git |

## Secret da migrare (inventario)

| Secret | Namespace | Oggi | Dopo S5 |
|---|---|---|---|
| `cloudflare-api-token` | cert-manager | applicato a mano | SOPS+KSOPS (GitOps) |
| `cloudflared-credentials` | cloudflared | playbook Ansible dal vault | SOPS+KSOPS (GitOps) |
| `argocd-secret` (admin pwd) | argocd | patch in bootstrap | resta com'è (bootstrap, non un manifest) |
| `pihole_password` | — | vault Ansible (LXC) | resta nel vault (non è k8s) |

## Pre-requisiti

- S4 (ArgoCD) ✓
- Binari locali: `age`, `sops`, `ksops`, `kustomize` (install a carico tuo — niente
  `sudo` da parte dell'agente)

## Passi di installazione

> ⚠️ I comandi `helm`/install e quelli che toccano il cluster li lanci **tu**.

### 1. Installare i binari (workstation)

```bash
# age + sops: vedi release ufficiali (FiloSottile/age, getsops/sops)
# ksops: viaduct-ai/kustomize-sops
# Verifica:
age --version && sops --version && kustomize version
```

### 2. Generare la coppia di chiavi age

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Annota la PUBLIC key stampata: "Public key: age1....."
```

La **privata** (`keys.txt`) resta solo sulla tua macchina + backup (vedi S6).

### 3. `.sops.yaml` nel root del repo

Definisce *cosa* cifrare e *con quale chiave*. Cifriamo solo `data`/`stringData`:

```yaml
creation_rules:
  - path_regex: \.enc\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: "age1....."   # la TUA public key
```

### 4. Bootstrap della chiave privata nel cluster (una volta)

L'unico segreto applicato fuori banda — la base di fiducia di tutto il resto:

```bash
kubectl create secret generic sops-age -n argocd \
  --from-file=keys.txt=$HOME/.config/sops/age/keys.txt
```

### 5. KSOPS nel repo-server di ArgoCD

Configurare `argocd-repo-server` perché esegua `kustomize` con KSOPS e abbia accesso
alla chiave. Si fa nei values Helm (`k8s/bootstrap/argocd-values.yaml`): init
container che installa `ksops`+`sops`, mount del Secret `sops-age`, env
`SOPS_AGE_KEY_FILE`, e registrazione del CMP (Config Management Plugin).

> 🔧 **Da verificare insieme**: la sintassi esatta (CMP sidecar vs init container)
> dipende dalla versione di ArgoCD installata e dalla doc corrente di KSOPS. Da
> definire in fase di esecuzione, leggendo la versione reale del chart.

### 6. Migrare un secret (esempio: cloudflared)

```bash
# 1. Manifest in chiaro temporaneo
kubectl create secret generic cloudflared-credentials \
  --namespace cloudflared --from-literal=token='eyJ...' \
  --dry-run=client -o yaml > /tmp/cf.yaml

# 2. Cifra in posizione nel repo
sops --encrypt /tmp/cf.yaml > k8s/apps/cloudflared/cloudflared-credentials.enc.yaml
rm /tmp/cf.yaml

# 3. Generatore KSOPS che il kustomization includerà
cat > k8s/apps/cloudflared/secret-generator.yaml <<'EOF'
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: cloudflared-secret-generator
  annotations:
    config.kubernetes.io/function: |
      exec:
        path: ksops
files:
  - ./cloudflared-credentials.enc.yaml
EOF
```

Poi nel `kustomization.yaml` dell'app aggiungere:
```yaml
generators:
  - ./secret-generator.yaml
```
Commit + push → ArgoCD decifra e crea il Secret. Stessa procedura per
`cloudflare-api-token` in `cert-manager/`.

### 7. Dismettere il vecchio mondo

```bash
# Sealed Secrets: disinstallare il controller (file già rimossi dal repo)
helm uninstall sealed-secrets-controller -n kube-system

# cloudflared: il Secret ora è GitOps → il playbook non serve più
git rm ansible/playbooks/cloudflared-install.yml
# (opzionale) rimuovere cloudflared_tunnel_token dal vault
```

## Definition of Done

- [ ] Binari `age`/`sops`/`ksops` installati; chiave age generata e in backup
- [ ] `.sops.yaml` committato; Secret `sops-age` applicato in `argocd`
- [ ] `argocd-repo-server` decifra i file SOPS via KSOPS
- [ ] `cloudflare-api-token` e `cloudflared-credentials` cifrati, committati e
      materializzati da ArgoCD nel cluster (nessun apply manuale)
- [ ] Nessuna credenziale in chiaro nel repo (CI secret-scanning verde)
- [ ] Controller Sealed Secrets disinstallato; `cloudflared-install.yml` rimosso
- [ ] Chiave `age` inserita nel piano di backup (S6)

## Disaster recovery

- Per ricostruire: reinstalla i binari, recupera `keys.txt` dal backup, riapplica
  il Secret `sops-age`, ArgoCD ri-decifra tutto dal repo.
- ⚠️ Senza la chiave `age` privata, i `*.enc.yaml` in Git sono **indecifrabili**.
  È il singolo punto da custodire (vedi [06-backup.md](06-backup.md)).

## Note / da verificare

- Config esatta di KSOPS nel repo-server: dipende dalla versione di ArgoCD (§5).
- Valutare se cifrare anche `argocd_admin_password` come Secret SOPS o lasciarlo
  come patch di bootstrap (oggi è una patch, non un manifest dichiarativo).
