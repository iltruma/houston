# TLS: certificati con Let's Encrypt (DNS-01 + Cloudflare)

I servizi web dell'homelab espongono HTTPS con certificati **pubblicamente
fidati**, emessi da **Let's Encrypt** e gestiti da **cert-manager** dentro k3s.
Nessuna CA privata: i certificati sono validi su qualsiasi browser/OS senza
installare nulla.

| Voce          | Valore                                       |
|---------------|----------------------------------------------|
| CA            | Let's Encrypt (ACME pubblico)                |
| Challenge     | **DNS-01** via API Cloudflare                |
| Dominio       | `paroparo.it` (DNS su Cloudflare)            |
| Wildcard      | `*.lab.paroparo.it`                          |
| Gestione      | cert-manager (k3s) — vedi [07-gitops.md](07-gitops.md) |
| DNS interno   | Technitium split-horizon → ingress k3s `.2`  |
| Roadmap       | Fase 1 — Sprint **S1** (strategia) + **S3** (implementazione) |

> **Storico**: questo servizio era inizialmente una CA privata `step-ca` su LXC
> `vanguard`. È stata abbandonata il 2026-06-14 a favore di Let's Encrypt: i cert
> privati richiedevano di installare la root CA nel trust store di ogni device,
> dolore che Let's Encrypt elimina. L'IP `.5` e l'LXC `vanguard` non sono più usati.

---

## 1. Perché Let's Encrypt + DNS-01

**Il problema di una CA privata.** Una CA privata (step-ca) emette certificati
che il mondo non conosce: ogni browser, OS, telefono e TV mostra "certificato non
valido" finché non installi *manualmente* la sua root CA. Per ogni device. Per
sempre.

**Let's Encrypt** è una CA pubblica già fidata ovunque. Per ottenere un cert devi
solo **dimostrare di controllare il dominio**. Tre modi (challenge ACME):

| Challenge   | Come prova                              | Richiede esposizione? | Wildcard? |
|-------------|-----------------------------------------|-----------------------|-----------|
| HTTP-01     | file su `http://dominio/.well-known/`   | sì (porta 80) ❌      | no        |
| TLS-ALPN-01 | handshake TLS speciale                   | sì (porta 443) ❌     | no        |
| **DNS-01**  | record TXT `_acme-challenge.dominio`     | **no** ✅             | **sì** ✅ |

**DNS-01 è l'unico** che (a) non richiede di esporre nulla su internet e (b)
supporta i certificati wildcard. cert-manager crea il record TXT su Cloudflare via
API, Let's Encrypt lo verifica, emette il cert, poi il record viene rimosso.

---

## 2. Architettura

```
                Let's Encrypt (ACME)
                      ▲   │ emette cert
       crea TXT       │   ▼
   _acme-challenge ──►Cloudflare DNS (API token)
        ▲
        │ DNS-01 solver
    cert-manager (k3s) ──► Certificate wildcard *.lab.paroparo.it
         │                         │ usato da
         ▼                         ▼
    Secret TLS in k3s ──────► Traefik Ingress (192.168.178.2)
                                   ▲
                                   │ split-horizon DNS
    Technitium: *.lab.paroparo.it ─┘ → 192.168.178.2
```

**Punto chiave**: tutti i servizi k3s passano da **un solo ingress** (Traefik su
`.2`). Quindi:

- **un solo record DNS interno** in Technitium: `*.lab.paroparo.it → 192.168.178.2`
- **un solo certificato wildcard** `*.lab.paroparo.it` copre ogni servizio
  presente e futuro

Aggiungere un servizio non richiede né un nuovo record DNS né un nuovo cert: basta
una `Ingress` rule con un hostname sotto `lab.paroparo.it`.

---

## 3. Split-horizon: i nomi pubblici risolvono a IP privati

Il dominio `lab.paroparo.it` è pubblico, ma i servizi vivono su IP **privati**
(`192.168.178.x`). Lo split-horizon risolve questa tensione:

- **DNS pubblico (Cloudflare)**: `lab.paroparo.it` **non** ha record A pubblici.
  Cloudflare ospita solo i record TXT temporanei del challenge. Dall'esterno i
  servizi non sono visibili né raggiungibili.
- **DNS interno (Technitium)**: risolve `*.lab.paroparo.it → 192.168.178.2`. Solo i
  client della LAN (che usano Technitium come resolver) raggiungono i servizi.

> **✅ DNS rebind protection (S3 verificato)**: i client interrogano Technitium
> direttamente senza passare dal router, quindi la rebind protection non interferisce.
> Confermato: `dig uptime.lab.paroparo.it @192.168.178.2` → `192.168.178.2`.

> **✅ Technitium wildcard (S3 verificato)**: zona `lab.paroparo.it` primaria locale
> con record `* → 192.168.178.2`. Configurato via web UI Technitium dopo install.

---

## 4. Prerequisiti

1. **Dominio `paroparo.it` con DNS su Cloudflare** ✅ (già così).
2. **API token Cloudflare** *scoped* — non la Global API Key. Permessi minimi:
   - `Zone → DNS → Edit` sulla zona `paroparo.it`
   - `Zone → Zone → Read` (per trovare la zone ID)

   Si crea da: *Cloudflare dashboard → My Profile → API Tokens → Create Token →
   "Edit zone DNS"*, limitando alla zona `paroparo.it`.
3. **k3s + cert-manager** in piedi (vedi [07-gitops.md](07-gitops.md)).

> ⚠️ Il token Cloudflare va trattato come una credenziale: finirà in un
> file **`secret.enc.yaml`** cifrato con SOPS + age (S5), **mai in chiaro nel repo**.

---

## 5. Implementazione (Sprint S3 — cert-manager)

L'implementazione vera vive in **S3**, dopo k3s. In sintesi:

1. **Secret** con l'API token Cloudflare nel namespace `cert-manager` — cifrato
   come `k8s/infra/cert-manager/secret.enc.yaml` (SOPS + age, decifrato da Flux).
2. **`ClusterIssuer`** ACME che punta a Let's Encrypt (prima `staging` per i test,
   poi `production`) con un **solver DNS-01 Cloudflare**.
3. **`Certificate`** wildcard `*.lab.paroparo.it` → cert-manager lo emette e lo
   salva in un Secret TLS, rinnovandolo in automatico (ogni ~60 giorni, validità 90).
4. Le `Ingress` dei servizi referenziano quel Secret TLS.

Tutti i manifest (`HelmRelease`, `ClusterIssuer`, `Certificate`) vivono in
`k8s/infra/cert-manager/` e sono sincronizzati da Flux (`k8s/clusters/iss/`).

---

## 6. Verifica (Definition of Done — S1)

S1 ora è solo **strategia + prerequisiti** (l'infra LXC non serve più):

- [x] Dominio `paroparo.it` con DNS su Cloudflare
- [x] Sottodominio scelto: `lab.paroparo.it`
- [x] API token Cloudflare creato e salvato (servirà in S3)
- [x] step-ca / LXC `vanguard` rimossi dal repo

Il *Definition of Done* sostanziale (un `Certificate` wildcard emesso e `Ready`,
firmato da Let's Encrypt) si verifica in **S3**.

---

## 7. Trade-off (per memoria)

- ➕ Certificati fidati ovunque, zero trust store da gestire.
- ➕ Wildcard unico per tutti i servizi; split-horizon tiene i servizi privati.
- ➕ Il dominio su Cloudflare è già lì: DNS-01, Renovate, eventuale tunnel futuro condividono la stessa infrastruttura.
- ➖ Dipendenza da internet e da Let's Encrypt per il rinnovo (automatico via
  cert-manager). Non adatto a scenari air-gapped — irrilevante per questo homelab.
- ➖ I cert finiscono nei log di Certificate Transparency: usando **solo il
  wildcard** nei log appare `*.lab.paroparo.it`, non i nomi dei singoli servizi.

---

## 8. Reverse proxy per host fisici

Il namespace `infra-proxy` espone tramite Traefik host fisici che non fanno parte del cluster:

| Hostname | Backend | Note |
|---|---|---|
| `eos.lab.paroparo.it` | `192.168.178.2:80` | NixOS (HTTP, vari servizi host) |
| `iris.lab.paroparo.it` | `192.168.178.1:443` | Router Fritz!Box (HTTPS, self-signed) |

> **Cambiamento post-migrazione**: Proxmox non c'è più, quindi `eos` non
> espone più la UI Proxmox (8006). Sentinel (Technitium) gira sullo stesso
> host di eos, non serve proxy separato.

Ogni backend self-signed (es. Fritz!Box) usa un `ServersTransport` con
`insecureSkipVerify: true`. Il certificato esposto al browser è sempre il
wildcard Let's Encrypt.
