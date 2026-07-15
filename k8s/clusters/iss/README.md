# k8s/clusters/iss/
#
# Entry point Flux CD per il cluster k3s su eos (192.168.178.2).
#
# Struttura:
#   flux-system/        ← generato da flux bootstrap (non committare a mano)
#   infrastructure.yaml ← Kustomization: sincronizza k8s/infra/ (cilium, cert-manager, traefik)
#   apps.yaml           ← Kustomization: sincronizza k8s/apps/ (beszel, uptime-kuma, homepage, infra-proxy)
#
# Ordine: infrastructure Ready → poi apps si attiva (dependsOn).
# Decryption SOPS con chiave age in Secret sops-age (namespace flux-system).
#
# Bootstrap (una tantum, da workstation):
#   flux bootstrap github \
#     --owner=iltruma \
#     --repository=astra \
#     --branch=main \
#     --path=k8s/clusters/iss \
#     --personal
#
# Subito dopo il bootstrap, crea il secret per la decryption SOPS:
#   kubectl create secret generic sops-age \
#     --namespace=flux-system \
#     --from-file=age.agekey=age-key.txt
