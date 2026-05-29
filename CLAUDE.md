# Houston Homelab

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

## Network

- Houston host: 192.168.178.2
- VM k3s - ISS: 192.168.178.3
- LXC Pihole - Sentinel: 192.168.178.4
- Gateway: 192.168.178.1
