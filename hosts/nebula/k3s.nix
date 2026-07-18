{ config, lib, pkgs, ... }:

{
  services.k3s = {
    enable = true;
    role = "server";

    extraFlags = toString [
      "--disable=traefik"              # gestito da Flux
      "--disable=servicelb"
      "--disable=local-storage"        # ZFS fornisce storage locale
      "--disable=metrics-server"       # Beszel copre monitoring
      "--write-kubeconfig-mode=0644"
    ];

    # Override del ConfigMap bundled: delega a Technitium per lab.paroparo.it.
    # services.k3s.manifests piazza il file in /var/lib/rancher/k3s/server/manifests/
    # e lo applica al boot; il nome "coredns" è richiesto da k3s.
    # Kustomization "dyson" (root): dice a Flux di applicare tutti i Kustomization
    # che trova in k8s/clusters/dyson/ del repo (infrastructure, apps, ...).
    # Senza questo, Flux clona il repo ma non sa cosa applicare.
    manifests."flux-cluster-kustomization" = {
      content = {
        apiVersion = "kustomize.toolkit.fluxcd.io/v1";
        kind = "Kustomization";
        metadata = {
          name = "dyson";
          namespace = "flux-system";
        };
        spec = {
          interval = "10m";
          path = "./k8s/clusters/dyson";
          prune = true;
          sourceRef = {
            kind = "GitRepository";
            name = "flux-system";
          };
        };
      };
    };
    # GitRepository flux-system: punta al repo GitHub che ospita i Kustomization.
    # Al primo boot fallirà con "no CRD for GitRepository" perché Flux non è ancora
    # installato; k3s ritenta automaticamente dopo che il HelmChart qui sotto ha
    # installato Flux + CRD.
    manifests."flux-git-repository" = {
      content = {
        apiVersion = "source.toolkit.fluxcd.io/v1";
        kind = "GitRepository";
        metadata = {
          name = "flux-system";
          namespace = "flux-system";
        };
        spec = {
          interval = "10m";
          url = "ssh://git@github.com/iltruma/astra";
          ref.branch = "main";
          secretRef.name = "flux-system";  # Secret SSH con identity/identity.pub/known_hosts
        };
      };
    };
    # HelmChart Flux: il k3s Helm controller (built-in) installa il chart flux2
    # della community Flux. Dopo l'install, le 4 CRD Flux sono attive e i
    # Kustomization in k8s/clusters/dyson/ possono essere applicati.
    manifests."flux-helmchart" = {
      content = {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChart";
        metadata = { name = "flux2"; namespace = "kube-system"; };
        spec = {
          targetNamespace = "flux-system";
          createNamespace = true;
          chart = "oci://ghcr.io/fluxcd-community/charts/flux2";
          version = "2.19.0";
        };
      };
    };
    # Namespace flux-system: k3s non crea namespace implicitamente quando applica
    # i manifest in server/manifests/, quindi va materializzato prima dei Secret.
    # Naming: "flux-namespace" < "flux-secret-*" (n < s) → ordine lessicale garantito.
    manifests."flux-namespace" = {
      content = {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = "flux-system";
      };
    };
    manifests."coredns-custom" = {
      content = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "coredns";
          namespace = "kube-system";
        };
        data = {
          Corefile = ''
            .:53 {
                errors
                health
                ready
                kubernetes cluster.local in-addr.arpa ip6.arpa {
                  pods insecure
                  fallthrough in-addr.arpa ip6.arpa
                }
                forward . 192.168.178.2:53
                cache 30
                loop
                reload
                loadbalance
            }
            lab.paroparo.it:53 {
                errors
                cache 30
                forward . 192.168.178.2:53
            }
          '';
        };
      };
    };
  };

  sops.secrets = {
    "k3s/flux-git-auth" = {
      sopsFile = ../../secrets/flux-git-auth.enc.yaml;
      format = "yaml";
    };
    "k3s/flux-sops-age" = {
      sopsFile = ../../secrets/flux-sops-age.enc.yaml;
      format = "yaml";
    };
  };

  # Symlink dei secret Flux in manifests/ prima che k3s parta
  systemd.tmpfiles.rules = [
    "d /var/lib/rancher/k3s/server/manifests 0755 root root - -"
    "L+ /var/lib/rancher/k3s/server/manifests/flux-secret-git-auth.yaml - - - - /run/secrets/k3s/flux-git-auth"
    "L+ /var/lib/rancher/k3s/server/manifests/flux-secret-sops-age.yaml - - - - /run/secrets/k3s/flux-sops-age"
  ];

  networking.firewall.allowedTCPPorts = [ 10250 ]; # kubelet API

  environment.systemPackages = with pkgs; [ k3s fluxcd];
}
