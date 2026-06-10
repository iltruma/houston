# k8s — GitOps con ArgoCD

Questa cartella contiene tutto ciò che gira sul cluster k3s (`iss`), gestito in
**GitOps** da ArgoCD: lo stato desiderato vive qui in Git, ArgoCD lo sincronizza
nel cluster.

## Struttura

```
k8s/
├── bootstrap/                  ← applicato A MANO una volta, NON gestito da GitOps
│   ├── argocd-values.yaml      values Helm per installare ArgoCD
│   └── applicationset.yaml     il generatore: 1 Application per cartella in apps/
│
└── apps/                       ← una cartella per servizio, con dentro TUTTI i suoi manifest
    ├── argocd/                 ingress + certificate della UI di ArgoCD
    ├── cert-manager/           ClusterIssuer (step-ca ACME) + root CA + cert di test
    ├── coredns/                ConfigMap custom: stub zone .internal → Pi-hole
    ├── homepage/               dashboard dichiarativa dei servizi
    └── sealed-secrets/         controller Sealed Secrets (secret cifrati in Git)
```

Due livelli, con ruoli distinti:

- **`bootstrap/`** — l'uovo e la gallina: ArgoCD non può installare sé stesso, quindi
  questi file si applicano a mano (`helm`/`kubectl`). Non sono sincronizzati da GitOps.
- **`apps/<servizio>/`** — il contenuto vero, gestito da ArgoCD. Ogni sottocartella è
  un servizio e contiene tutti i suoi manifest (ingress, certificate, configmap…).

## Come funziona l'ApplicationSet

`bootstrap/applicationset.yaml` è un **generatore** (*git directory generator*): guarda
ogni cartella sotto `k8s/apps/*` e per ciascuna genera automaticamente un'`Application`
ArgoCD chiamata come la cartella.

Punto chiave: il `destination` del template **non specifica il namespace**. Ogni
manifest dichiara il proprio (`namespace:` nel `metadata`), così un unico template
generico serve app che vivono in namespace diversi (`argocd`, `kube-system`,
`cert-manager`). Le risorse cluster-scoped (es. `ClusterIssuer`) non hanno namespace,
ed è corretto.

## Aggiungere un nuovo servizio

1. Crea `k8s/apps/<nome>/` con i suoi manifest (ricorda `metadata.namespace` su ogni
   risorsa namespaced).
2. Commit e push.
3. Al prossimo sync (polling ~3 min) l'ApplicationSet genera l'`Application` da sola.

Niente file `Application` da scrivere a mano: la cartella *è* l'app.

> ℹ️ ArgoCD fa **polling** del repo ogni ~3 min. I webhook GitHub (sync istantaneo)
> richiederebbero ArgoCD raggiungibile da internet: non disponibile finché il cluster
> è solo `.internal` (vedi S12 — Cloudflare Tunnel).

## Bootstrap (prima installazione, da rifare solo in disaster recovery)

```bash
export KUBECONFIG=~/.kube/config-k3s

# 1. Installa ArgoCD via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace \
  -f k8s/bootstrap/argocd-values.yaml

# 2. Applica l'ApplicationSet: genera e sincronizza tutte le app
kubectl apply -f k8s/bootstrap/applicationset.yaml
```

> ⚠️ Prerequisito: **cert-manager** installato (controller via Helm) e la root CA di
> step-ca presente, altrimenti i `Certificate` restano pending. Vedi
> [docs/04-stepca.md](../docs/04-stepca.md).
