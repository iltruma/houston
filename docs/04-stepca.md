# Servizio: step-ca (vanguard)

Certificate Authority **privata di rete** (Smallstep `step-ca`): emette
certificati TLS per i servizi dell'homelab tramite il protocollo **ACME**, come
una "Let's Encrypt interna". Gira nell'LXC `vanguard` (`192.168.178.5`).

| Voce        | Valore                                  |
|-------------|-----------------------------------------|
| Host        | `vanguard` — LXC                        |
| IP          | `192.168.178.5`                         |
| ACME dir    | `https://vanguard.internal:9000/acme/acme/directory` |
| CA name     | `Houston Homelab CA`                    |
| Terraform   | [`terraform/lxc-stepca.tf`](../terraform/lxc-stepca.tf) |
| Playbook    | [`ansible/playbooks/stepca-setup.yml`](../ansible/playbooks/stepca-setup.yml) |
| Roadmap     | Fase 1 — Sprint **S1**                   |

## Perché la CA vive FUORI dal cluster

step-ca è volutamente su un LXC dedicato e **non** dentro k3s: la fiducia nella CA
(la sua root key) non deve dipendere dal ciclo di vita del cluster. Se ricostruisci
k3s da zero, la CA — e tutti i certificati già emessi e installati nei trust store
— restano validi. cert-manager dentro k3s diventa solo un *client* di questo ACME.

---

## 1. Prerequisiti

1. **LXC creato** da Terraform: container `201`, hostname `vanguard`, Debian 13,
   IP `.5`, con `nesting = true`.
2. **Inventory**: `vanguard` raggiungibile come `root` via SSH.
3. **Password della CA** nel vault cifrato. È la passphrase che protegge la
   signing key — serve all'`init` e a ogni avvio del servizio. Aggiungi a
   `ansible/group_vars/all/vault.yml`:
   ```yaml
   stepca_password: "<password-forte-random>"
   ```

---

## 2. Variabili

Definite in [`ansible/group_vars/all/stepca.yml`](../ansible/group_vars/all/stepca.yml):

```yaml
homelab_domain: "internal"          # TLD interno (SAN, issuer, ingress)
step_cli_version: "0.30.2"          # client `step`   — pinnato
step_ca_version:  "0.30.2"          # daemon `step-ca` — pinnato
stepca_name: "Houston Homelab CA"
stepca_dns_names:                   # SAN con cui la CA è raggiungibile
  - "vanguard.internal"
  - "192.168.178.5"
stepca_listen_address: ":9000"
stepca_acme_provisioner: "acme"     # nome del provisioner ACME (usato da cert-manager)
stepca_home: "/etc/step-ca"         # config, chiavi e DB
```

> Le versioni sono **pinnate** per build riproducibili: verifica le ultime su
> [smallstep/cli](https://github.com/smallstep/cli/releases) e
> [smallstep/certificates](https://github.com/smallstep/certificates/releases)
> prima di fare un bump deliberato.

---

## 3. Cosa fa il playbook (i 5 blocchi)

1. **Install binari** — scarica i tarball `step` e `step-ca` alle versioni
   pinnate, li estrae e installa in `/usr/local/bin`. Idempotente via `creates:`.
2. **Utente e directory** — crea l'utente di sistema `step-ca` (nologin, niente
   shell) e gli dà ownership esclusiva di `stepca_home` (`0700`). La CA **non gira
   mai come root**.
3. **Init CA** — `step ca init` genera root CA + intermediate CA + `ca.json` + DB,
   con `--acme` aggiunge il provisioner ACME e `--provisioner admin` quello JWK
   amministrativo. La password è passata via tempfile, rimosso subito dopo; una
   copia permanente (`0600`, owner `step-ca`) resta per il runtime del servizio.
4. **Systemd** — installa e abilita `step-ca.service` (`STEPPATH` →
   `stepca_home`, `--password-file` → la copia permanente), con restart on-failure.
5. **Export root cert** — `fetch` di `root_ca.crt` dal container alla workstation
   in [`ansible/playbooks/certs/houston-homelab-root-ca.crt`](../ansible/playbooks/certs/houston-homelab-root-ca.crt).
   Serve per il trust store e per cert-manager (S3).

---

## 4. Esecuzione

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/stepca-setup.yml --ask-vault-pass
```

---

## 5. Verifica (Definition of Done — S1)

- [ ] ACME directory raggiungibile:
      ```bash
      curl -k https://vanguard.internal:9000/acme/acme/directory
      ```
      (restituisce un JSON con gli endpoint `newNonce`, `newAccount`, `newOrder`…)
- [ ] Servizio attivo: `systemctl status step-ca` su `vanguard` → `active (running)`
- [ ] Root CA esportata in `ansible/playbooks/certs/houston-homelab-root-ca.crt`
- [ ] Root CA installata nel trust store di **almeno un client** (vedi §6)

---

## 6. Installare la root CA nel trust store

Finché la root CA non è "fidata" su un client, i certificati emessi dalla CA
appaiono come non validi. Installa
`houston-homelab-root-ca.crt` dove serve:

**Linux (Debian/Ubuntu)**
```bash
sudo cp houston-homelab-root-ca.crt /usr/local/share/ca-certificates/houston-homelab-root-ca.crt
sudo update-ca-certificates
```

**macOS**
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain houston-homelab-root-ca.crt
```

**Windows (PowerShell come amministratore)**
```powershell
Import-Certificate -FilePath houston-homelab-root-ca.crt `
  -CertStoreLocation Cert:\LocalMachine\Root
```

> **Firefox** usa un proprio trust store: *Settings → Privacy & Security →
> Certificates → View Certificates → Authorities → Import*.

---

## 7. Passo successivo

In **S3** cert-manager userà questo endpoint ACME tramite un `ClusterIssuer`:
i servizi nel cluster otterranno certificati TLS firmati dalla `Houston Homelab CA`
in automatico. La root CA va resa fidata anche **dentro il controller** cert-manager.

## Note di sicurezza

- `stepca_password` sta **solo** nel vault cifrato, mai in chiaro nel repo.
- Le signing key restano sul container in `stepca_home` (`0700`, owner `step-ca`):
  **non vanno mai committate**. Solo `root_ca.crt` (pubblico) è nel repo.
- Compromettere la root key compromette ogni certificato della rete: tratta
  `vanguard` come un host sensibile.
