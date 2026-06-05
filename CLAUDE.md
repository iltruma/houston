# Houston Homelab

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

## Progetto

Homelab su Dell Optiplex 3050 (i5-6500T, 16GB RAM, 500GB SSD) con Proxmox VE come hypervisor.

## Stack

- **Hypervisor**: Proxmox VE
- **IaC**: Terraform (provider bpg/proxmox)
- **Config Management**: Ansible
- **Container Orchestration**: k3s (single node VM)
- **CI/CD**: GitHub Actions + ArgoCD
- **DNS**: Pihole (LXC container)
- **Ingress**: Traefik (incluso in k3s)

## Struttura

```
terraform/   - Infrastruttura come codice (VM, LXC, network)
ansible/     - Provisioning e configurazione (k3s, pihole)
k8s/         - Manifesti Kubernetes (ArgoCD, apps, runner)
docs/        - Documentazione step-by-step
.github/     - Workflow CI/CD
```

## Comandi Utili

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

## Commit Naming Convention

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

Lo scope è opzionale per modifiche trasversali (es. rinomina globale, refactor struttura repo).

## Network

- Houston host: 192.168.178.2
- VM k3s - ISS: 192.168.178.3
- LXC Pihole - Sentinel: 192.168.178.4
- Gateway: 192.168.178.1
