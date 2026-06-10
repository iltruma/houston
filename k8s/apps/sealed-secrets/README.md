# sealed-secrets

Controller [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets):
permette di committare in Git secret **cifrati** (`SealedSecret`). Solo la chiave
privata, custodita nel cluster, può decifrarli → diventano `Secret` reali.

## controller.yaml

Manifest **vendorato** dalla release ufficiale, non un chart Helm: ogni risorsa
namespaced dichiara `namespace: kube-system`, quindi si integra con l'`ApplicationSet`
(che il namespace lo prende dai manifest). Gira in `kube-system`.

- Versione pinnata: **v0.37.0**

Per aggiornare:

```bash
VER=v0.X.Y
curl -fsSL https://github.com/bitnami-labs/sealed-secrets/releases/download/$VER/controller.yaml \
  -o k8s/apps/sealed-secrets/controller.yaml
# aggiorna la versione qui sopra, commit, push → ArgoCD applica
```

## ⚠️ Chiave privata = backup critico

La coppia di chiavi è generata dal controller al primo avvio e vive come `Secret`
in `kube-system` (label `sealedsecrets.bitnami.com/sealed-secrets-key`). **Se la
perdi, tutti i `SealedSecret` committati diventano indecifrabili.** Il suo backup è
parte di **S6 — Backup/DR**.

## Uso (kubeseal)

```bash
# cifra un Secret in un SealedSecret committabile
kubectl create secret generic mio-secret \
  --from-literal=key=value --dry-run=client -o yaml \
  | kubeseal --format yaml > sealed-mio-secret.yaml
```
