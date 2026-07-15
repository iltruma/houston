# DNS — Technitium

Servizio DNS autorevole + ricorsivo, basato su [Technitium](https://technitium.com/dns/).
Nel setup NixOS gira come servizio nativo (modulo `services.technitium-dns-server`
in nixpkgs v15.2.0+), non più come LXC separato.

## Perché Technitium (e non Pi-hole o AdGuard)

| Funzionalità               | Pi-hole v6 | AdGuard Home | **Technitium DNS** |
|----------------------------|-----------|--------------|--------------------|
| Zona autoritativa          | ❌        | ❌           | ✅ nativa          |
| Wildcard DNS               | ❌        | ❌           | ✅                 |
| Split horizon              | ❌        | ❌           | ✅ nativo          |
| DoH/DoT built-in           | ❌        | ✅           | ✅                 |
| Clustering                 | ❌        | ❌           | ✅ (v14+)          |
| RAM idle                   | ~50 MB    | ~50 MB       | ~150 MB            |
| Pacchetto nixpkgs          | ❌        | ✅           | ✅ (v15.2.0+)      |
| Modulo NixOS               | ❌        | ❌           | ✅                 |

Technitium è l'unica opzione che supporta nativamente:
- Zona primaria autoritativa per `lab.paroparo.it` (split-horizon)
- Record wildcard `*.lab.paroparo.it → 192.168.178.2`
- DoH/DoT per query ricorsive
- Modulo NixOS pronto all'uso

## Configurazione NixOS

In [`modules/technitium.nix`](../modules/technitium.nix):

```nix
services.technitium-dns-server = {
  enable = true;
  openFirewall = true;  # apre 53 UDP/TCP, 5380, 53443
};
```

Questo abilita:
- Servizio systemd `technitium-dns-server` con `DynamicUser`, `NoNewPrivileges`,
  `ProtectSystem=strict`, `CAP_NET_BIND_SERVICE`
- State directory `/var/lib/technitium-dns-server` (ZFS dataset `tank/var`)
- Ascolto su `0.0.0.0:53` (UDP e TCP)
- Web UI su `0.0.0.0:5380` (HTTP) e `0.0.0.0:53443` (HTTPS)

> **Nota**: il modulo NixOS di default espone la web UI su tutte le interfacce.
> Per limitarla a localhost, serve un override (vedi
> [sezione override](#override-web-ui-su-localhost) sotto).

## Zone file (BIND)

I record DNS sono versionati in Git come zona BIND:
[`hosts/eos/dns-zone.lab.paroparo.it`](../hosts/eos/dns-zone.lab.paroparo.it)

Per importare in Technitium dopo un reinstall:
- *Zones → lab.paroparo.it → Import → seleziona il file*

Per aggiungere un nuovo servizio: aggiungi il record nel file e reimporta,
oppure aggiungilo dalla web UI (poi aggiorna il file nel repo per mantenerlo allineato).

## Configurazione via web UI

Dopo l'install NixOS e il primo boot, Technitium va configurato via web UI.
Accesso dalla workstation via SSH tunnel:

```bash
# Dalla workstation
ssh -L 5380:127.0.0.1:5380 root@192.168.178.2
# Apri browser su http://127.0.0.1:5380
```

### Configurazione minima

1. **Zona autoritativa `lab.paroparo.it`**:
   - *Zones → Add Zone → Primary Zone*
   - Nome: `lab.paroparo.it`
   - Tipo: Primary
   - Salva

2. **Record wildcard**:
   - Apri la zona `lab.paroparo.it`
   - *Add Record → A*
   - Name: `*` (o vuoto per la root)
   - IPv4 Address: `192.168.178.2`
   - Salva

3. **Record esplicito per Taiga** (necessario per ACME DNS-01):
   - *Add Record → A*
   - Name: `taiga`
   - IPv4 Address: `192.168.178.43`
   - Salva
   - Il wildcard coprirebbe anche `taiga`, ma il record esplicito ha priorità
      e punta al Pi direttamente invece che a Traefik su Eos.

3. **Upstream ricorsivi (DoH)**:
   - *Settings → DNS Client*
   - Add: `https://cloudflare-dns.com/dns-query` (Cloudflare 1.1.1.1)
   - Add: `https://dns.quad9.net/dns-query` (Quad9 9.9.9.9)
   - Disabilita UDP plain (forza DoH) per privacy

4. **Blocklist** (opzionale):
   - *Settings → Block List*
   - Add URLs:
     - `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
     - `https://big.oisd.nl/domainswild` (OISD)

5. **Cache e TTL**:
   - Default vanno bene per homelab
   - Cache: ~24h, TTL negativi: 5min

### Configurazione avanzata

- **Conditional forwarder**: per query `*.lan` o `*.local`, delega al router
  Fritz!Box (`192.168.178.1`)
- **Log**: abilita log query (utile per debug, attenzione a privacy)
- **Stats**: Technitium ha statistiche built-in (no Grafana necessario)

## Verifica

```bash
# Da un client sulla LAN
dig @192.168.178.2 lab.paroparo.it
# Deve risolvere dalla zona locale (NO upstream)

dig @192.168.178.2 uptime.lab.paroparo.it
# Wildcard → 192.168.178.2 (Traefik k3s)

dig @192.168.178.2 google.com
# Deve risolvere via upstream DoH (Cloudflare/Quad9)

# Verifica DoH/DoT
dig @192.168.178.2 -t TXT _dnssec. example.com
# DNSSEC validation attiva
```

## Override web UI su localhost

Il modulo NixOS espone la web UI su tutte le interfacce. Per limitarla:

```nix
# modules/technitium.nix
systemd.services.technitium-dns-server.serviceConfig = {
  # ... altri override
  # Nota: richiede override del servizio systemd completo
  # vedi https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/technitium-dns-server.nix
};
```

Per ora il workaround è il firewall:Technitium ascolta su 0.0.0.0:5380, ma il
firewall NixOS accetta solo connessioni LAN. L'accesso da WAN è bloccato.
Per accesso più stretto (solo localhost), usare sempre SSH tunnel.

## Backup e restore

Lo state di Technitium vive in `/var/lib/technitium-dns-server`. È incluso
nel backup rclone notturno (vedi [03-backup.md](03-backup.md)).

Restore:
```bash
systemctl stop technitium-dns-server
rclone sync r2:eos-backup/technitium/ /var/lib/technitium-dns-server/
systemctl start technitium-dns-server
```

## Monitoraggio

- Status: `systemctl status technitium-dns-server`
- Statistiche: web UI → Dashboard (query/sec, cache hit rate, ecc.)
- Log: `journalctl -u technitium-dns-server`

## Aggiornamento

Il pacchetto è in nixpkgs, versione aggiornata con `nix flake update`. Per
aggiornare:

```bash
nix flake update --commit nixpkgs
nixos-rebuild switch --flake .#eos --target-host root@192.168.178.2
```

Technitium non richiede migrazioni di state: ogni release mantiene
compatibilità del file system in `/var/lib/technitium-dns-server`.

## Trade-off

- **Pro**: zona autoritativa + ricorsivo in un unico processo, DoH/DoT built-in,
  modulo NixOS ufficiale, ~150 MB RAM.
- **Contro**: progetto single-developer (Shreyas Zare), ~5k stars (vs Pi-hole
  ~48k). Rischio abbandono medio, ma GPL-3 forkabile.
- **Piano B**: se Technitium viene abbandonato, alternative con split-horizon
  sono scarse. Workaround: AdGuard Home + dnsmasq wildcard sul Fritz!Box.
