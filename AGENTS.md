# Houston Homelab — Agent Instructions

Regole per opencode quando lavora in questo repo. Questo file ha precedenza
su qualsiasi `CLAUDE.md` o impostazione globale.

> Per il setup globale di opencode (permission, MCP, provider) vedi
> `~/.config/opencode/opencode.jsonc`.

## Modalità di lavoro (IMPORTANTE)

Questo repo è anche un percorso di **apprendimento**: l'obiettivo non è solo
avere l'infrastruttura, ma capirla. Quindi:

- **Spiega ogni file PRIMA di crearlo o modificarlo.** Descrivi a cosa serve,
  cosa contiene e perché, poi crealo. In alternativa costruiamolo insieme un
  pezzo alla volta.
- Niente raffiche di file creati in blocco senza spiegazione.
- Procedi un passo alla volta, lasciando spazio a domande e verifiche.
- **Prima la lista dei servizi, poi i file.** Si lavora per **sprint** atomici
  guidati da [docs/roadmap.md](docs/roadmap.md): un servizio alla volta, con
  Definition of Done, commit, poi il successivo. Non saltare avanti nelle fasi.
- Segnala sempre i punti incerti come "da verificare", non darli per oro colato.

## Lingua e stile

- Rispondi in **italiano** salvo quando l'utente scrive in inglese.
- Stile conciso: niente introduzioni/postamble inutili. Pochi emoji, solo se richiesti.
- Codice, comandi, path e identificativi tecnici sempre in inglese.
- Per task di learning: privilegia la spiegazione del *perché* prima del *come*.

## Sicurezza & secrets

- Non leggere, stampare o inviare al provider LLM il contenuto di file con
  secrets (`.env`, `*vault*`, `*secret*`, `*credential*`, `*.pem`, `*.key`,
  `**/.ssh/**`, `**/.aws/**`). I vault di Ansible in
  `ansible/group_vars/*/vault.yml` e `ansible/host_vars/*/vault.yml` sono
  già esclusi dal watcher.
- **SOPS + Ansible Vault** per i secrets in repo. Mai committare plaintext.
- Non proporre soluzioni che richiedano `sudo` se non strettamente necessario.
- Se l'utente condivide un secret per errore, avvisalo immediatamente e
  consiglia rotazione.
- Per gestire l'host Proxmox (houston), operare via SSH/UI da workstation,
  non da repo. Per gestire VM/LXC, usare Terraform o `qm/pct` da remoto.

## Tool e workflow

- Preferisci `read`/`grep`/`glob` prima di lanciare comandi costosi.
- Per task ripetuti, valutare la creazione di un custom command
  (`.opencode/commands/`).
- Per task specializzati (review TF plan, check manifest k8s), valutare un
  subagent dedicato (`.opencode/agents/`).
- Se trovi un pattern ricorrente del progetto, proporre una skill
  (`.opencode/skills/`).
- `terraform plan` e `terraform apply` devono sempre passare per review
  esplicita (chiedere conferma prima di `apply`).
- `kubectl apply/delete` chiedono sempre conferma.
- `ansible-playbook` chiede sempre conferma (escluso `--syntax-check` e
  `--check`).

## Progetto

Homelab su Dell Optiplex 3050 (i5-6500T, 16GB RAM, 500GB SSD) con Proxmox VE
come hypervisor.

## Stack

- **Hypervisor**: Proxmox VE
- **IaC**: Terraform (provider bpg/proxmox)
- **Config Management**: Ansible
- **Container Orchestration**: k3s (single node VM)
- **CI/CD**: GitHub Actions + ArgoCD
- **DNS**: Pihole (LXC container)
- **Ingress**: Traefik (incluso in k3s)
- **TLS**: Let's Encrypt (challenge DNS-01 via Cloudflare) + cert-manager

## Struttura

```
terraform/   - Infrastruttura come codice (VM, LXC, network)
ansible/     - Provisioning e configurazione (k3s, pihole)
k8s/         - Manifesti Kubernetes (ArgoCD, apps, runner)
docs/        - Documentazione step-by-step
.github/     - Workflow CI/CD
```

## Comandi utili

```bash
# Terraform
cd terraform && terraform init && terraform plan

# Ansible
cd ansible && ansible-playbook -i inventory.yml playbooks/k3s-install.yml

# Kubernetes
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
kubectl get pods -A
```

## Commit naming convention

Formato: `<tipo>(<scope>): <descrizione>`

**Scope per layer:**

| Scope       | Quando usarlo                              |
|-------------|--------------------------------------------|
| `terraform` | Modifiche a VM, LXC, network, variabili TF |
| `ansible`   | Playbook, inventory, group_vars            |
| `k8s`       | Manifesti Kubernetes, Helm chart, ArgoCD   |
| `ci`        | GitHub Actions workflow                    |
| `docs`      | File in `docs/`                            |

**Esempi:**
```
feat(terraform): add pihole LXC container
fix(ansible): correct task order in pihole-setup
chore(k8s): update argocd app manifest
docs: add proxmox install guide
```

Lo scope è opzionale per modifiche trasversali (es. rinomina globale,
refactor struttura repo).

## Network

- Iris (gateway/router Fritz!Box): 192.168.178.1
- Houston host: 192.168.178.2
- VM k3s - ISS: 192.168.178.3
- LXC Pihole - Sentinel: 192.168.178.4
- Dominio: `lab.paroparo.it` (record locali in Pi-hole; host + servizi web via
  wildcard `*.lab.paroparo.it` → ingress k3s; TLS Let's Encrypt).
  Niente `.internal`.
