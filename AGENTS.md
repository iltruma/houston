# Astra Homelab — Agent Instructions

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
  `**/.ssh/**`, `**/.aws/**`, `secrets/*.enc.yaml` non decifrati).
- **SOPS + age** per i secrets in repo (`.sops.yaml`). Mai committare plaintext.
- Non proporre soluzioni che richiedano `sudo` se non strettamente necessario.
- Se l'utente condivide un secret per errore, avvisalo immediatamente e
  consiglia rotazione.
- Per gestire l'host NixOS (eos), operare via SSH da workstation.
  Per applicare config: `nixos-rebuild switch --flake .#eos --target-host root@192.168.178.2`.

## Tool e workflow

- Preferisci `read`/`grep`/`glob` prima di lanciare comandi costosi.
- Per task ripetuti, valutare la creazione di un custom command
  (`.opencode/commands/`).
- Per task specializzati (review NixOS config, check manifest k8s), valutare un
  subagent dedicato (`.opencode/agents/`).
- Se trovi un pattern ricorrente del progetto, proporre una skill
  (`.opencode/skills/`).
- `nix flake check` e `nixos-rebuild` chiedono conferma per `switch`/`boot`.
- `kubectl apply/delete` chiedono sempre conferma.
- `sops --encrypt` chiede conferma (modifica file).

## Progetto

Homelab su Dell Optiplex 3050 (i5-6500T, 16 GB RAM pianificato 32 GB, 500 GB SSD)
con **NixOS baremetal** (no hypervisor). k3s gira come servizio host, Technitium
DNS come servizio NixOS nativo.

## Stack

- **OS host**: NixOS 25.11 (baremetal, no Proxmox)
- **File system**: ZFS (Disko per partizionamento dichiarativo)
- **IaC**: flake NixOS (Nix language, unica fonte di verità)
- **Config Management**: moduli NixOS + nixos-rebuild
- **Container Orchestration**: k3s (single-node, servizio host)
- **CNI**: Cilium 1.18.x (helmfile bootstrap + HelmRelease Flux)
- **CI/CD**: GitHub Actions + Flux CD v2 (GitOps)
- **Secrets**: SOPS + age (sops-nix per host, Flux SOPS per k8s)
- **DNS**: Technitium DNS (modulo NixOS nativo)
- **Ingress**: Traefik (HelmRelease Flux in k8s)
- **TLS**: Let's Encrypt (DNS-01 Cloudflare) + cert-manager
- **Backup**: rclone → Cloudflare R2 (systemd timer)

## Struttura

```
flake.nix         - Entry point NixOS (pin nixpkgs, sops-nix, disko)
hosts/eos/    - Config specifica del server (disko, hardware, networking)
modules/          - Moduli NixOS riusabili (common, technitium, k3s, backup)
secrets/          - Secret host cifrati con SOPS (*.enc.yaml)
k8s/              - Manifesti GitOps (Flux) — invariato dalla migrazione
docs/             - Documentazione step-by-step (roadmap, decisioni, migration)
.github/workflows/ - CI (nix flake check, kubeconform, gitleaks)
```

## Comandi utili

```bash
# Build/apply NixOS (da workstation, contro eos remoto)
nix flake check
nixos-rebuild switch --flake .#eos --target-host root@192.168.178.2

# k3s (via SSH su eos)
ssh root@192.168.178.2
k3s kubectl get nodes
k3s kubectl get pods -A

# Flux
k3s flux get kustomizations
k3s flux get helmreleases -A

# SOPS
sops --encrypt --in-place secrets/foo.enc.yaml
sops --decrypt secrets/foo.enc.yaml
```

## Commit naming convention

Formato: `<tipo>(<scope>): <descrizione>`

**Scope per layer:**

| Scope       | Quando usarlo                              |
|-------------|--------------------------------------------|
| `nix`       | Modifiche a flake.nix, hosts/, modules/    |
| `k8s`       | Manifesti Kubernetes, Helm chart, Flux     |
| `ci`        | GitHub Actions workflow                    |
| `docs`      | File in `docs/`                            |

**Esempi:**
```
feat(nix): add technitium-dns-server module
fix(k8s): correct cilium helm release values
chore(ci): add nix flake check job
docs: add nixos migration guide
```

Lo scope è opzionale per modifiche trasversali (es. rinomina globale,
refactor struttura repo).

## Network

- Iris (gateway/router Fritz!Box): 192.168.178.1
- Eos (NixOS host): 192.168.178.2
  - Servizi esposti: k3s API (.6443), DNS (.53), HTTP (.80), HTTPS (.443)
  - k3s gira come servizio sullo stesso host (no VM separata)
  - Technitium DNS gira come servizio NixOS (no LXC separato)
- Dominio: `lab.paroparo.it` (record locali in Technitium; host + servizi web via
  wildcard `*.lab.paroparo.it` → Traefik in k3s; TLS Let's Encrypt).
  Niente `.internal`.
