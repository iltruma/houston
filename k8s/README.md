# k8s — GitOps con Flux CD v2

Questa cartella contiene tutto ciò che gira sul cluster k3s (`iss`), gestito in
**GitOps** da Flux CD v2: lo stato desiderato vive qui in Git, il
kustomize-controller lo sincronizza nel cluster ogni 10 minuti.

## Struttura

```
k8s/
├── clusters/
│   └── iss/                    ← Kustomization radice per il cluster "iss"
│       ├── flux-system/        applicate da `flux bootstrap`, NON editare a mano
│       ├── infra.yaml          Kustomization → k8s/infra/
│       └── apps.yaml           Kustomization → k8s/apps/
│
├── infra/                      ← Infrastruttura (HelmRelease, ClusterIssuer, …)
│   ├── cilium/                 HelmRelease + bootstrap Cilium CNI
│   ├── traefik/                HelmRelease Traefik 3.7.x
│   └── cert-manager/           HelmRelease cert-manager + ClusterIssuer + secret.enc.yaml
│
└── apps/                       ← Servizi applicativi, una cartella per servizio
    ├── uptime-kuma/            Status page
    ├── beszel/                 Hub + agent monitoring
    ├── homepage/               Dashboard dichiarativa
    ├── infra-proxy/            Traefik reverse proxy → iris (router) / eos (legacy)
    └── <nome>/                 Qualsiasi nuovo servizio
```

## Come funziona

`k8s/clusters/iss/infra.yaml` e `apps.yaml` sono oggetti `Kustomization` Flux.
Puntano rispettivamente a `k8s/infra/` e `k8s/apps/` e le riconciliano in
sequenza (infra prima, poi apps, per garantire che CRD e cert siano pronti).

Aggiungere un nuovo servizio:

1. Crea `k8s/apps/<nome>/` con i suoi manifest + `kustomization.yaml`.
2. Commit e push.
3. Al prossimo polling (~10 min) Flux applica la cartella. Per forzare subito:
   ```bash
   flux reconcile kustomization apps --with-source
   ```

## SOPS — decifrazione automatica dei secret

I file `*.enc.yaml` sono secret Kubernetes cifrati con **SOPS + age**. Il
kustomize-controller li decifra autonomamente usando la chiave privata age
contenuta nel Secret `sops-age` nel namespace `flux-system`.

La chiave pubblica age usata per la cifratura è in `.sops.yaml` alla radice
del repo. Per cifrare un nuovo secret:

```bash
# Cifra un Secret Kubernetes esistente
sops --encrypt k8s/apps/<nome>/secret.yaml > k8s/apps/<nome>/secret.enc.yaml
rm k8s/apps/<nome>/secret.yaml   # mai committare il plaintext
```

Verifica che il file contenga `sops:` metadata (e non `data:` in chiaro) prima
di committare.

## Bootstrap (prima installazione, da rifare solo in disaster recovery)

```bash
export KUBECONFIG=~/.kube/config-k3s

# 1. Installa Flux sul cluster e lo collega al repo GitHub
flux bootstrap github \
  --owner=<github-org> \
  --repository=astra \
  --branch=main \
  --path=k8s/clusters/iss \
  --personal

# 2. Crea il Secret con la chiave age privata (SOPS decryption)
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=<path/to/age.key>
```

> ⚠️ Il Secret `sops-age` va creato **prima** che Flux tenti di sincronizzare
> qualsiasi `*.enc.yaml`. Senza di esso il kustomize-controller fallisce con
> errore di decifrazione.

## Verifica

```bash
flux get kustomizations          # tutte Ready
flux get helmreleases -A         # Traefik, cert-manager Ready
kubectl get pods -A              # nessun pod in CrashLoopBackOff
