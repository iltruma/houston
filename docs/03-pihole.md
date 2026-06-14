# Servizio: Pi-hole (sentinel)

DNS ricorsivo + ad-blocking per tutta la rete dell'homelab. Gira nell'LXC
`sentinel` (`192.168.178.4`) e fa anche da **server DNS autorevole** per il
dominio interno `.internal` (record locali tipo `iss.internal`).

| Voce        | Valore                                  |
|-------------|-----------------------------------------|
| Host        | `sentinel` — LXC                        |
| IP          | `192.168.178.4`                         |
| Versione    | Pi-hole **v6** (config in `pihole.toml`)|
| Web UI      | `https://192.168.178.4` (HTTPS, porta 443) |
| Terraform   | [`terraform/lxc-pihole.tf`](../terraform/lxc-pihole.tf) |
| Playbook    | [`ansible/playbooks/pihole-setup.yml`](../ansible/playbooks/pihole-setup.yml) |
| Roadmap     | Fase 1 — Sprint **S0**                   |

---

## 1. Prerequisiti

1. **LXC creato** da Terraform (`terraform apply`): container `200`, hostname
   `sentinel`, Debian 13, IP `.4`.
2. **Inventory** Ansible: `sentinel` raggiungibile come `root` via SSH
   (vedi [`ansible/inventory.yml`](../ansible/inventory.yml)).
3. **Password web** nel vault cifrato. Aggiungi a
   `ansible/group_vars/all/vault.yml`:
   ```yaml
   pihole_password: "<password-forte>"
   ```
   Il vault si modifica con `ansible-vault edit ansible/group_vars/all/vault.yml`.

---

## 2. Variabili

Definite in [`ansible/group_vars/all/vars.yml`](../ansible/group_vars/all/vars.yml):

```yaml
pihole_base_url: "https://192.168.178.4"

pihole_dns_records:                 # record DNS locali (.internal)
  - { ip: "192.168.178.2", hostname: "houston.internal" }
  - { ip: "192.168.178.3", hostname: "iss.internal" }
  - { ip: "192.168.178.4", hostname: "sentinel.internal" }

pihole_adlists:                     # blocklist caricate via API
  - "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
  - "https://v.firebog.net/hosts/AdguardDNS.txt"
  - ...
```

I record DNS e le adlist sono **dichiarativi**: per aggiungerne uno si modifica
questa lista e si rilancia il playbook (idempotente).

---

## 3. Cosa fa il playbook (passo-passo)

1. **Dipendenze** — installa `curl`, `git`.
2. **`setupVars.conf`** — file che fa girare l'installer in modalità
   `--unattended` (semina interfaccia, upstream DNS, web server).
   ⚠️ È un artefatto **v5**: su v6 la config vera è `pihole.toml`. Vedi
   *Troubleshooting* per il caveat sugli upstream DNS.
3. **Install Pi-hole** — `curl https://install.pi-hole.net | bash --unattended`
   (idempotente via `creates: /usr/local/bin/pihole`).
4. **HTTPS su 443** — imposta `port = "443s"` in `pihole.toml` (FTL serve la web
   UI in TLS con cert self-signed).
5. **Password web** — `pihole setpassword` (formato hash corretto per v6).
6. **Ownership** — `/etc/pihole` di proprietà dell'utente `pihole` (serve all'API).
7. **Restart FTL** + attesa che l'API HTTPS sia pronta (porta 443).
8. **Auth API** — `POST /api/auth` → ottiene una `SID` di sessione.
9. **Adlist** — `POST /api/lists` per ogni blocklist; al termine fa partire
   l'handler **Update gravity** (`POST /api/action/gravity`) che ricompila il DB.
10. **Record DNS locali** — `PUT /api/config/dns/hosts/{IP%20hostname}`
    (idempotente: 200 = già presente, 201 = creato).

---

## 4. Esecuzione

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/pihole-setup.yml --ask-vault-pass
```

---

## 5. Verifica (Definition of Done — S0)

- [ ] Web UI raggiungibile: `https://192.168.178.4` (login con `pihole_password`)
- [ ] Risoluzione locale: `dig iss.internal @192.168.178.4` → `192.168.178.3`
- [ ] Ad-blocking attivo: le adlist compaiono in **Lists** e *gravity* è aggiornato
- [ ] Il playbook è **idempotente**: una seconda esecuzione gira pulita
- [ ] Puntare il router (o il DHCP) a `192.168.178.4` come DNS primario
      → vedi [02-network-setup.md](02-network-setup.md)

---

## 6. Troubleshooting

**Upstream DNS non applicati su v6** — gli upstream (`1.1.1.1`, `8.8.8.8`) sono
solo in `setupVars.conf`, che v6 potrebbe non migrare in `pihole.toml`. Controlla:
```bash
grep -A3 "\[dns\]" /etc/pihole/pihole.toml
```
Se mancano gli `upstreams`, vanno impostati lì (è la fonte di verità in v6).

**Campo `port` in `pihole.toml`** — il task HTTPS assume il path del campo `port`.
Se il restart fallisce, verifica con `grep -n "port" /etc/pihole/pihole.toml`.

**Record DNS risponde 4xx** — ispeziona con `ansible-playbook -v` e confronta con:
```bash
curl -k https://192.168.178.4/api/config/dns/hosts
```

**API restituisce 401** — la `SID` è scaduta o la password è errata; rilancia il
playbook (rifà l'auth) o controlla `pihole_password` nel vault.
