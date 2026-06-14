# Fase 1b: Configurazione Rete

## Schema Rete

```
Internet
   │
   ▼
┌──────────┐
│  Router   │  192.168.178.1 (Gateway + DHCP per i client)
└────┬─────┘
     │
     ├── 192.168.178.2   houston   Proxmox VE (host)
     ├── 192.168.178.3   iss       VM   k3s single-node
     ├── 192.168.178.4   sentinel  LXC  Pi-hole (DNS)
     │
     └── 192.168.178.x   Altri dispositivi (DHCP dal router)
```

## Configurazione Bridge di Rete su Proxmox

Il file `/etc/network/interfaces` di Proxmox dovrebbe essere:

```
auto lo
iface lo inet loopback

iface enp1s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.178.2/24
    gateway 192.168.178.1
    bridge-ports enp1s0
    bridge-stp off
    bridge-fd 0
```

> `vmbr0` è il bridge Linux che permette a VM e container di accedere alla rete fisica.
> `enp1s0` è il nome dell'interfaccia fisica: **da verificare** sul tuo hardware (`ip link`).

## IP Statici

Gli host dell'homelab hanno IP statici (assegnati da Terraform/Proxmox, non via DHCP)
per stabilità. I client generici prendono l'IP dal DHCP del router.

| Host       | Ruolo                      | Tipo | IP            |
|------------|----------------------------|------|---------------|
| `houston`  | Hypervisor Proxmox VE      | host | 192.168.178.2 |
| `iss`      | Cluster k3s (single-node)  | VM   | 192.168.178.3 |
| `sentinel` | Pi-hole (DNS + adlists)    | LXC  | 192.168.178.4 |

## DNS

### Prima di Pi-hole
Il DNS punta al router: `192.168.178.1`

### Dopo Pi-hole attivo
1. Configurare il router per usare `192.168.178.4` (sentinel) come DNS primario,
   oppure distribuirlo via DHCP a tutti i client.
2. In Pi-hole, impostare l'upstream DNS (es. `1.1.1.1`, `8.8.8.8` — già in
   `setupVars.conf` del playbook).

## Firewall (opzionale)

Proxmox ha un firewall integrato. Per l'homelab locale si può lasciare disattivato,
ma se si vuole abilitarlo le regole minime per il nodo sono:

```
# Datacenter → Firewall → Options → Firewall: Yes
# Allow SSH (22)
# Allow Web UI (8006)
# Allow ICMP (ping)
```

## DNS locale personalizzato (via Pi-hole)

I record DNS locali sono gestiti **dichiarativamente** dal playbook
`pihole-setup.yml` (variabile `pihole_dns_records` in
`ansible/group_vars/all/vars.yml`), su un unico dominio **`lab.paroparo.it`**:

```
houston.lab.paroparo.it    → 192.168.178.2
iss.lab.paroparo.it        → 192.168.178.3
sentinel.lab.paroparo.it   → 192.168.178.4
```

> Usiamo un sottodominio del nostro dominio pubblico (`paroparo.it`, DNS su
> Cloudflare) **per tutto**, host e servizi web: così i servizi web ottengono
> certificati TLS Let's Encrypt validi senza una CA privata.
>
> I **servizi web** del cluster (`argocd`, `homepage`, …) non hanno record
> espliciti: li copre il **wildcard** `*.lab.paroparo.it → 192.168.178.3`
> (ingress k3s) in split-horizon su Pi-hole. Vedi [04-tls.md](04-tls.md). Si
> configura in S3. *da verificare*: i record host espliciti devono avere
> precedenza sul wildcard (comportamento dnsmasq).

## Verifica

- [ ] Proxmox raggiungibile via `ping 192.168.178.2`
- [ ] VM e LXC hanno connettività internet
- [ ] Risoluzione DNS funzionante da tutti i nodi (`dig iss.lab.paroparo.it @192.168.178.4`)
- [ ] Dispositivi sulla rete riescono ad accedere alle risorse dell'homelab

---

## Sicurezza di rete — Piano A (Proxmox Firewall, senza switch managed)

Senza uno switch managed non è possibile fare isolamento VLAN a livello hardware
verso la LAN fisica. Il firewall integrato di Proxmox permette comunque di
applicare regole per-VM/LXC a livello di hypervisor.

> Il Piano B (VLAN completo con switch managed) è pianificato come sprint finale
> del roadmap — vedi `roadmap.md`.

### Abilitazione

```
Proxmox UI → Datacenter → Firewall → Options → Firewall: Yes
Proxmox UI → Datacenter → Firewall → Options → Forward: No (non è un router)
```

Poi abilitare il firewall su ogni nodo:
```
Proxmox UI → houston → Firewall → Options → Firewall: Yes
```

### Regole per nodo

**sentinel (Pi-hole — 192.168.178.4)**

| Direzione | Proto | Porta | Sorgente | Azione | Motivo |
|---|---|---|---|---|---|
| IN | TCP+UDP | 53 | `192.168.178.0/24` | ACCEPT | DNS dalla LAN |
| IN | TCP | 443 | workstation | ACCEPT | Web UI Pi-hole |
| IN | TCP | 22 | workstation | ACCEPT | SSH admin |
| IN | any | any | any | DROP | blocca tutto il resto |
| OUT | TCP+UDP | 53 | `1.1.1.1`, `8.8.8.8` | ACCEPT | upstream DNS |
| OUT | TCP | 80,443 | any | ACCEPT | aggiornamenti OS + gravity |
| OUT | any | any | any | DROP | blocca tutto il resto |

**iss (k3s — 192.168.178.3)**

| Direzione | Proto | Porta | Sorgente | Azione | Motivo |
|---|---|---|---|---|---|
| IN | TCP | 6443 | workstation | ACCEPT | kubectl API server |
| IN | TCP | 80,443 | `192.168.178.0/24` | ACCEPT | Ingress Traefik |
| IN | TCP | 22 | workstation | ACCEPT | SSH admin |
| IN | any | any | any | DROP | blocca tutto il resto |
| OUT | any | any | any | ACCEPT | il cluster deve raggiungere internet (immagini, ACME, ecc.) |

> Le regole OUT di `iss` si restringeranno ulteriormente in S16 (download stack):
> il traffico torrent di qBittorrent dovrà uscire **solo** via VPN egress.

### Kubernetes NetworkPolicy (intra-cluster)

Il CNI di default di k3s (Flannel) **non** implementa NetworkPolicy. Per
applicare policy di rete tra i pod del cluster occorre sostituirlo con **Cilium**,
che supporta anche L7 policy e ha observability integrata (Hubble).

La migrazione Flannel → Cilium è pianificata contestualmente a S2 (bootstrap k3s).

### Verifica Piano A

- [ ] Firewall abilitato a livello Datacenter e nodo houston
- [ ] `nmap -p 53 192.168.178.4` risponde solo da LAN, non da internet
- [ ] API server k3s (6443) raggiungibile solo dalla workstation
